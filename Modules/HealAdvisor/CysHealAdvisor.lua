--------------------------------------------------------------------------------
-- Cys's UI - Heal Advisor (Druid, Paladin, Priest, Shaman)
--
-- An on-demand advisor, not a combat popup. Type /cuirank (or /cui -> Class -> General -> Heal Advisor) and a
-- window shows which rank of your heals to use for what. It never plans for a health total (you heal strangers):
-- it compares the ranks you know by heal per mana, with the level penalty on bonus healing counted.
--
-- Scan: pressing Scan (or opening the window the first time) takes a snapshot of your stats and talents (bonus
-- healing, Intellect, Spirit, mana, and what each healing talent does). The advice keeps using that snapshot, so
-- swapping gear does not change it until you press Scan again. When you learn a spell or level up and the advice
-- would be different, a small popup says so.
--
-- Talents: every talent you have points in is read through the game's own tooltip, and the sentence is parsed:
-- "reduces the casting time of your X by N sec" and "increases the healing / effectiveness by N%" change the
-- numbers; mana-cost talents are already inside the costs the game reports; crit, regen and chance-based talents
-- are listed but not counted.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T
local _, myClass = UnitClass("player")

local DEFAULTS = { notify = true, snap = {} }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.healadvisor = CysUIDB.healadvisor or {}
    local db = CysUIDB.healadvisor
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then db[k] = {} else db[k] = v end
        end
    end
    return db
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- Base cast time (seconds, per rank or one number) and the level each rank is learned. Level comes from the game
-- when it can say; these are the fallback.
local SPELLS = {
    ["Healing Wave"]        = { cast = { 1.5, 2, 2.5, 3, 3, 3, 3, 3, 3, 3 }, levels = { 1, 6, 12, 18, 24, 32, 40, 48, 56, 60 } },
    ["Lesser Healing Wave"] = { cast = 1.5, levels = { 20, 28, 36, 44, 52, 60 } },
    ["Chain Heal"]          = { cast = 2.5, levels = { 40, 46, 54 }, chain = true },
    ["Lesser Heal"]         = { cast = { 1.5, 2, 2.5 }, levels = { 1, 4, 10 } },
    ["Heal"]                = { cast = 3, levels = { 16, 22, 28, 34 } },
    ["Greater Heal"]        = { cast = 3, levels = { 40, 46, 52, 58 } },
    ["Flash Heal"]          = { cast = 1.5, levels = { 20, 26, 32, 38, 44, 50, 56 } },
    ["Prayer of Healing"]   = { cast = 3, levels = { 30, 40, 50, 60 }, chain = true },
    ["Healing Touch"]       = { cast = { 1.5, 2, 2.5, 3, 3, 3, 3, 3, 3, 3, 3 }, levels = { 1, 8, 14, 20, 26, 32, 38, 44, 50, 56, 60 } },
    ["Regrowth"]            = { cast = 2, levels = { 12, 18, 24, 30, 36, 42, 48, 54, 60 } },
    ["Holy Light"]          = { cast = 2.5, levels = { 1, 6, 14, 22, 30, 38, 46, 54, 60 } },
    ["Flash of Light"]      = { cast = 1.5, levels = { 20, 26, 34, 42, 50, 58 } },
}

-- main = the heals compared for everyday use; fast = the quick expensive heal; group = the group heal
local FAMILY = {
    -- main = the slow, efficient single-target ladder (one ladder even when it holds several spells)
    -- fast = the fast-cast single-target heal
    -- group = group heals (own row); exclude = never used for the four single-target rows
    -- rows = which family a row reads from (default: heavy, general, small = main; emergency = fast)
    -- emergencyCast = the cast time that counts as fast when a class has no fast heal
    SHAMAN  = { main = { "Healing Wave" }, fast = { "Lesser Healing Wave" }, group = { "Chain Heal" },
                exclude = { "Chain Heal", "Healing Stream Totem" } },
    PRIEST  = { main = { "Lesser Heal", "Heal", "Greater Heal" }, fast = { "Flash Heal" }, group = { "Prayer of Healing" },
                exclude = { "Renew", "Power Word: Shield", "Prayer of Healing", "Holy Nova" } },
    DRUID   = { main = { "Healing Touch" }, fast = { "Regrowth" }, group = {}, emergencyCast = 2.0,
                exclude = { "Rejuvenation", "Tranquility", "Swiftmend" } }, -- Regrowth counts for its direct heal only
    PALADIN = { main = { "Holy Light" }, fast = { "Flash of Light" }, group = {},
                rows = { small = "fast", general = "fast", heavy = "main", emergency = "fast" }, -- to confirm with guild paladins
                exclude = { "Lay on Hands", "Holy Shock" } },
}
local MYFAM = FAMILY[myClass]
-- the spell lists of a class config (not its settings): main, fast, group
local function FamLists(f)
    return { f.main or {}, f.fast or {}, f.group or {} }
end
local ht = { on = false, ranks = {}, pending = {} } -- the /cuiheal test: what each rank really healed
local PV -- preview class token while the made-up sample is showing (nil = your real character)

--------------------------------------------------------------------------------
-- Reading the character
--------------------------------------------------------------------------------
local function BookRanks()
    -- [spell name][rank] = spell ID, from the spellbook
    local out = {}
    if not MYFAM then return out end
    local want = {}
    for _, group in ipairs(FamLists(MYFAM)) do for _, n in ipairs(group) do want[n] = true end end
    local getName = GetSpellBookItemName
    local bank = "spell"
    if not getName and C_SpellBook and C_SpellBook.GetSpellBookItemName then
        getName = C_SpellBook.GetSpellBookItemName
        bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
    end
    if not getName then return out end
    for i = 1, 1500 do
        local ok, name, sub, id = pcall(getName, i, bank)
        if not ok or not name then break end
        if want[name] then
            if not id and GetSpellBookItemInfo then
                local ok2, _, id2 = pcall(GetSpellBookItemInfo, i, bank)
                if ok2 then id = id2 end
            end
            local rank = tonumber((sub or ""):match("(%d+)")) or 1
            out[name] = out[name] or {}
            if id then out[name][rank] = id end
        end
    end
    return out
end

local scanTip
local function TalentText(tab, index)
    -- the talent's tooltip sentence for the rank you have (not the "Next rank" part)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "CysHealAdvisorTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetTalent, scanTip, tab, index)
    if not ok then return "" end
    local parts = {}
    for i = 2, scanTip:NumLines() do
        local fs = _G["CysHealAdvisorTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            if text:find("Next rank") then break end
            if not text:find("^Rank %d") and not text:find("^Requires") and not text:find("^Click") then
                parts[#parts + 1] = text
            end
        end
    end
    return table.concat(parts, " ")
end

-- Works out what a talent does from its own sentence. kind: cast, heal, cost (already in the game's mana costs),
-- or other (listed, not counted).
-- whole-word match, so "Heal" is not found inside "Healing Wave"
local function Mentions(text, name)
    local padded = " " .. text .. " "
    local from = 1
    while true do
        local a, b = padded:find(name, from, true)
        if not a then return false end
        if not padded:sub(a - 1, a - 1):match("%a") and not padded:sub(b + 1, b + 1):match("%a") then return true end
        from = a + 1
    end
end

local function Classify(text)
    local lower = text:lower()
    local scope = {}
    local names = {}
    for name in pairs(SPELLS) do names[#names + 1] = name end
    table.sort(names, function(x, y) return #x > #y end)
    local work = text
    for _, name in ipairs(names) do
        if Mentions(work, name) then
            scope[name] = true
            local esc = name:gsub("%p", "%%%0")
            work = work:gsub(esc, "#")
        end
    end
    local all = next(scope) == nil
    if lower:find("casting time") and lower:find("reduc") then
        local sec = tonumber(lower:match("by ([%d%.]+) sec"))
        if sec then return "cast", sec, scope, all end
    end
    if lower:find("critical") or lower:find("chance") or lower:find("regenerat") or lower:find("pushback") or lower:find("interrupt") then
        return "other", nil, scope, all
    end
    if lower:find("mana cost") then
        local pct = tonumber(lower:match("by ([%d%.]+)%%"))
        if pct then return "cost", pct, scope, all end
    end
    if lower:find("increases") and (lower:find("heal") or lower:find("effectiveness")) then
        local pct = tonumber(lower:match("by ([%d%.]+)%%"))
        if pct then return "heal", pct, scope, all end
    end
    return "other", nil, scope, all
end

-- talents that look like they change the numbers but do not (Illumination refunds mana on a crit)
local IGNORE = { ["Illumination"] = true }

local function ReadTalents()
    local t = { list = {}, points = {} }
    if not (GetNumTalentTabs and GetTalentInfo) then return t end
    local okTabs, tabs = pcall(GetNumTalentTabs)
    if not okTabs or not tabs then return t end
    for tab = 1, tabs do
        t.points[tab] = 0
        local okN, n = pcall(GetNumTalents, tab)
        for i = 1, (okN and n or 0) do
            local ok, name, _, _, _, rank, maxRank = pcall(GetTalentInfo, tab, i)
            if ok and name and rank and rank > 0 then
                t.points[tab] = t.points[tab] + rank
                local text = TalentText(tab, i)
                local kind, value, scope, all = Classify(text)
                if IGNORE[name] then kind, value = "other", nil end
                local lower = text:lower()
                local healing = lower:find("heal") or lower:find("mana cost") or lower:find("casting time")
                if healing or name == "Nature's Swiftness" then
                    t.list[#t.list + 1] = { name = name, rank = rank, max = maxRank, text = text, kind = kind, value = value, scope = scope, all = all }
                end
            end
        end
    end
    return t
end

local function ParseHeal(id)
    local getDesc = GetSpellDescription or (C_Spell and C_Spell.GetSpellDescription)
    if not (getDesc and id) then return nil end
    local ok, desc = pcall(getDesc, id)
    if not ok or type(desc) ~= "string" then return nil end
    desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", "")
    local lo, hi = desc:match("(%d+) to (%d+)")
    if lo and hi then return (tonumber(lo) + tonumber(hi)) / 2 end
    local one = desc:match("(%d+)")
    return one and tonumber(one) or nil
end

local function ManaCost(id)
    if not GetSpellPowerCost then return nil end
    local ok, costs = pcall(GetSpellPowerCost, id)
    if ok and type(costs) == "table" then
        for _, c in ipairs(costs) do
            if c.type == 0 or c.name == "MANA" then return c.cost end
        end
        if costs[1] then return costs[1].cost end
    end
    return nil
end

-- The scan: what is frozen until you press Scan again.
local function TakeSnapshot()
    local talents = ReadTalents()
    local snap = {
        time = date and date("%b %d, %H:%M") or "",
        bonus = GetSpellBonusHealing and GetSpellBonusHealing() or 0,
        int = UnitStat and select(2, UnitStat("player", 4)) or 0,
        spirit = UnitStat and select(2, UnitStat("player", 5)) or 0,
        mana = UnitPowerMax("player", 0) or 0,
        talents = talents.list,
        points = talents.points,
    }
    local okRegen, baseRegen, castRegen = pcall(GetManaRegen)
    if okRegen then snap.regenOut, snap.regenIn = baseRegen, castRegen end
    DB().snap[CharKey()] = snap
    return snap
end

--------------------------------------------------------------------------------
-- Preview: a made-up level 40 healer, so the window can be checked without that class
--------------------------------------------------------------------------------
local PV_LEVEL = 40
local function PVBook()
    local out = {}
    for _, group in ipairs(FamLists(MYFAM or {})) do
        for _, name in ipairs(group) do
            local sp = SPELLS[name]
            out[name] = out[name] or {}
            for rank, lv in ipairs(sp.levels) do
                if lv <= PV_LEVEL then out[name][rank] = 900000 + rank end
            end
        end
    end
    return out
end
-- sample numbers that look like the real thing: bigger ranks heal more and cost more
local function PVNumbers(name, rank)
    local sp = SPELLS[name]
    local lv = sp.levels[rank]
    local cast = type(sp.cast) == "table" and (sp.cast[rank] or sp.cast[#sp.cast]) or sp.cast
    local f = cast / 3
    return (40 + lv * lv * 0.62) * f * (sp.chain and 0.8 or 1), (18 + lv * 6.2) * f * (cast <= 1.5 and 1.6 or 1), lv
end
local function PVSnap()
    local first = MYFAM.main[1]
    local scope = {}
    scope[first] = true
    return {
        time = "sample", bonus = 150, int = 120, spirit = 95, mana = 1800, regenOut = 9.5, regenIn = 4.1,
        points = { 31, 0, 0 },
        talents = {
            { name = "Sample: faster main heal", rank = 5, max = 5, text = "Reduces the casting time of your " .. first .. " spell by 0.5 sec.",
              kind = "cast", value = 0.5, scope = scope },
            { name = "Sample: cheaper heals", rank = 5, max = 5, text = "Reduces the Mana cost of your healing spells by 5%.",
              kind = "cost", value = 5, scope = {}, all = true },
            { name = "Sample: critical heals", rank = 3, max = 3, text = "Gives you a 3% chance to critically heal.",
              kind = "other", scope = {} },
        },
    }
end

--------------------------------------------------------------------------------
-- The numbers
--------------------------------------------------------------------------------
local function Analyze(snap)
    local level = PV and PV_LEVEL or UnitLevel("player")
    local book = PV and PVBook() or BookRanks()
    local spells = {}
    local seen = {}
    for _, group in ipairs(FamLists(MYFAM or {})) do
        for _, name in ipairs(group) do
            if not seen[name] then
                seen[name] = true
                local list = {}
                local sp = SPELLS[name]
                for rank, id in pairs(book[name] or {}) do
                    local base, cost, apiLevel
                    if PV then
                        base, cost, apiLevel = PVNumbers(name, rank)
                    else
                        base = ParseHeal(id)
                        cost = ManaCost(id)
                        apiLevel = GetSpellLevelLearned and GetSpellLevelLearned(id) or 0
                    end
                    local learned = (apiLevel and apiLevel > 0) and apiLevel or (sp.levels[rank] or 0)
                    local cast = type(sp.cast) == "table" and (sp.cast[rank] or sp.cast[#sp.cast]) or sp.cast
                    local fullCoef = math.min(1, math.max(1.5, cast) / 3.5)
                    local coef = fullCoef
                    if learned > 0 then
                        if learned < 20 then coef = coef * (1 - (20 - learned) * 0.0375) end
                        coef = coef * math.min(1, (learned + 6) / math.max(level, 1))
                    end
                    -- talents that change this spell
                    local effCast, mult = cast, 1
                    for _, tl in ipairs(snap.talents) do
                        if tl.value and (tl.all or tl.scope[name]) then
                            if tl.kind == "cast" then effCast = effCast - tl.value
                            elseif tl.kind == "heal" then mult = mult * (1 + tl.value / 100) end
                        end
                    end
                    effCast = math.max(1, effCast)
                    local heal = base and ((base + snap.bonus * coef) * mult) or nil
                    list[#list + 1] = {
                        spell = name, rank = rank, id = id, heal = heal, cost = cost, cast = effCast,
                        hpm = (heal and cost and cost > 0) and heal / cost or nil,
                        casts = (cost and cost > 0) and math.floor(snap.mana / cost) or nil,
                        keep = fullCoef > 0 and math.min(1, coef / fullCoef) or 1,
                    }
                end
                table.sort(list, function(a, b) return a.rank < b.rank end)
                spells[name] = list
            end
        end
    end
    return spells
end

local function Gather(spells, names)
    local out = {}
    for _, n in ipairs(names or {}) do
        for _, r in ipairs(spells[n] or {}) do out[#out + 1] = r end
    end
    return out
end

local function Peak(list)
    local best
    for _, r in ipairs(list) do
        if r.hpm and (not best or r.hpm > best.hpm) then best = r end
    end
    return best
end

local function Biggest(list)
    local best
    for _, r in ipairs(list) do
        if r.heal and (not best or r.heal > best.heal) then best = r end
    end
    return best
end

-- Rank rules (single-target heals only; heal-over-time spells and parts, absorbs, group heals and cooldowns are left out).
--   families  main = the slow efficient ladder, fast = the quick heal (a class config can move a row to the other family)
--   best      the highest heal per mana among every single-target rank you know, across both families
--   eff(r)    r's heal per mana divided by best
--   heavy     the biggest rank in its family that is still efficient (eff >= HEAVY_EFF)
--   general   the next size down that is also efficient (eff >= GENERAL_EFF): less mana, less overheal, faster
--   small     the smallest efficient rank (eff >= SMALL_EFF) that heals at least SMALL_MIN_SIZE of the heavy heal
--   emergency the biggest heal in the fast family; with no fast heal, the biggest heal that casts quickly and is
--             not tiny. Efficiency is ignored. A rank is never picked just because it is short.
-- Each row has its own rule, so rows may land on the same rank but never share one "most efficient" pick.
-- Spells you do not know never appear.
local HEAVY_EFF, GENERAL_EFF, SMALL_EFF = 0.90, 0.90, 0.80
local SMALL_MIN_SIZE = 0.20
local EMERGENCY_MAX_CAST = 1.5
local DEFAULT_ROWS = { small = "main", general = "main", heavy = "main", emergency = "fast" }

local function BiggerHeal(a, b)
    if a.heal ~= b.heal then return a.heal > b.heal end
    return (a.cost or 0) < (b.cost or 0)
end
local function PickBest(list, better)
    local best
    for _, r in ipairs(list) do
        if not best or better(r, best) then best = r end
    end
    return best
end

local function Situations(spells, snap)
    local rows = {}
    local fam = MYFAM
    local skip = {}
    for _, n in ipairs(fam.exclude or {}) do skip[n] = true end
    local function Ranks(names)
        local out = {}
        for _, n in ipairs(names or {}) do
            if not skip[n] then
                for _, r in ipairs(spells[n] or {}) do
                    if r.heal and r.hpm then out[#out + 1] = r end
                end
            end
        end
        return out
    end
    local pools = { main = Ranks(fam.main), fast = Ranks(fam.fast) }
    local group = Gather(spells, fam.group)
    local src = {}
    for k, v in pairs(DEFAULT_ROWS) do src[k] = (fam.rows and fam.rows[k]) or v end
    local swift = false
    for _, tl in ipairs(snap.talents) do if tl.name == "Nature's Swiftness" then swift = true end end
    local function Add(key, label, r, why) rows[#rows + 1] = { key = key, label = label, rec = r, why = why } end

    local all = {}
    for _, r in ipairs(pools.main) do all[#all + 1] = r end
    for _, r in ipairs(pools.fast) do all[#all + 1] = r end
    local best = 0
    for _, r in ipairs(all) do if r.hpm > best then best = r.hpm end end

    local heavy
    if #all > 0 and best > 0 then
        -- efficiency is measured against the best rank across both families, except for a row a class config
        -- moved to another family (Paladin Small/General use Flash of Light): that is measured inside its own family
        local function effFor(row)
            local base = best
            if src[row] ~= DEFAULT_ROWS[row] then
                base = 0
                for _, r in ipairs(pools[src[row]]) do if r.hpm > base then base = r.hpm end end
                if base <= 0 then base = best end
            end
            return function(r) return r.hpm / base end
        end
        local effHeavy, effGeneral, effSmall = effFor("heavy"), effFor("general"), effFor("small")
        local function Pick(list, test, better, fallback)
            local pool = {}
            for _, r in ipairs(list) do if test(r) then pool[#pool + 1] = r end end
            return PickBest(pool, better) or fallback
        end
        local function pool(row)
            local p = pools[src[row]]
            if #p == 0 then p = (#pools.main > 0) and pools.main or pools.fast end
            return p
        end
        -- heavy first: the other rows depend on it
        local hp = pool("heavy")
        heavy = Pick(hp, function(r) return effHeavy(r) >= HEAVY_EFF end, BiggerHeal,
            PickBest(hp, function(a, b) return a.hpm > b.hpm end))
        local general = Pick(pool("general"), function(r) return r.heal < heavy.heal and effGeneral(r) >= GENERAL_EFF end,
            function(a, b)
                if a.heal ~= b.heal then return a.heal > b.heal end
                if a.cast ~= b.cast then return a.cast < b.cast end
                return (a.cost or 0) < (b.cost or 0)
            end, heavy)
        local small = Pick(pool("small"), function(r) return effSmall(r) >= SMALL_EFF and r.heal >= heavy.heal * SMALL_MIN_SIZE end,
            function(a, b)
                if a.heal ~= b.heal then return a.heal < b.heal end
                return (a.cost or 0) < (b.cost or 0)
            end, general)
        Add("small", "Small hits, topping off", small, "Cheapest heal that is still efficient. For small hits and topping people off.")
        Add("general", "General healing", general, general == heavy
            and "Nothing smaller is nearly as efficient, so this is also your biggest efficient heal. Use it most of the time."
            or "Almost as efficient as your biggest heal, faster, and wastes less on normal tank damage. Use this most of the time.")
        Add("heavy", "Heavy damage", heavy, "Your biggest efficient heal. Use it when the target is missing at least this much health.")
    elseif #Gather(spells, fam.main) > 0 then
        Add("general", "General healing", PickBest(Gather(spells, fam.main), BiggerHeal), "The game did not give the heal or mana numbers, so ranks cannot be compared.")
    end

    -- emergency: speed only, never a tiny heal
    local em
    local why = "Fastest big heal. Costs more mana per heal, so save it for real emergencies."
    local emPool = pools[src.emergency]
    if emPool and #emPool > 0 then
        em = PickBest(emPool, BiggerHeal)
    elseif heavy then
        local limit = fam.emergencyCast or EMERGENCY_MAX_CAST
        local quick = {}
        for _, r in ipairs(all) do
            if r.cast <= limit and r.heal >= heavy.heal * SMALL_MIN_SIZE then quick[#quick + 1] = r end
        end
        em = PickBest(quick, BiggerHeal)
    end
    if swift and heavy then why = why .. " Or: Nature's Swiftness + " .. heavy.spell .. " " .. heavy.rank .. "." end
    if em then
        Add("fast", "Emergency spot heal", em, why)
    elseif swift and heavy then
        Add("fast", "Emergency spot heal", heavy, "Nature's Swiftness + " .. heavy.spell .. " " .. heavy.rank .. ".")
    end
    if #group > 0 then
        Add("group", "Several people hurt", Peak(group) or Biggest(group), "Your most efficient group heal. It heals the first target fully; the rest get less.")
    end
    return rows
end

local function Recs(spells, snap)
    local out = {}
    local ok = false
    for _, row in ipairs(Situations(spells, snap)) do
        if row.rec then out[row.key] = row.rec.spell .. " " .. row.rec.rank; ok = true end
    end
    return out, ok
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local win, content, lines
local WIDTH, HEIGHT = 640, 580

local function Fmt(n) return n and tostring(math.floor(n + 0.5)) or "?" end
local function Fmt1(n) return n and string.format("%.1f", n) or "?" end
local function Gold(s) return "|cFFFFD100" .. s .. "|r" end
local function Grey(s) return "|cFFB0B0B0" .. s .. "|r" end

local function Txt(x, y, text, color, size, width, justify)
    local fs = W.Text(content, size or 12, color or T.text, justify or "LEFT")
    fs:SetPoint("TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    fs:SetWordWrap(false)
    fs:SetText(text)
    lines[#lines + 1] = fs
    return fs
end

local function Para(y, text, color, x, width)
    local fs = W.Text(content, 12, color or T.desc)
    fs:SetPoint("TOPLEFT", x or 14, y)
    fs:SetWidth(width or (WIDTH - 60))
    fs:SetJustifyV("TOP")
    fs:SetSpacing(3)
    fs:SetText(text)
    lines[#lines + 1] = fs
    return fs:GetStringHeight() or 14
end

local function Head(y, text)
    local fs = Txt(14, y, text, T.accent, 13)
    local rule = W.Texture(content, "ARTWORK", T.line)
    rule:SetPoint("TOPLEFT", 14, y - 19)
    rule:SetSize(WIDTH - 60, 1)
    lines[#lines + 1] = rule
    return 28
end

local function Band(y, h)
    local b = W.Texture(content, "BACKGROUND", T.field)
    b:SetPoint("TOPLEFT", 10, y + 3)
    b:SetSize(WIDTH - 52, h)
    lines[#lines + 1] = b
end

-- right-aligned number columns, shared by both tables
local COL = { heals = 490, mana = 545, cast = 600 } -- right edges for the situations table
local function Num(rightEdge, y, text, color, size)
    Txt(rightEdge - 90, y, text, color, size, 90, "RIGHT")
end

local function Refresh(fresh)
    if not win then return end
    for _, o in ipairs(lines) do o:Hide() end
    wipe(lines)
    local db = DB()
    local snap
    local spells, recs, haveRecs
    if PV then
        snap = PVSnap()
        spells = Analyze(snap)
    else
        snap = db.snap[CharKey()]
        if not snap or fresh then snap = TakeSnapshot() end
        spells = Analyze(snap)
        recs, haveRecs = Recs(spells, snap)
        if fresh or not snap.recs then
            if haveRecs then snap.recs = recs end
        end
    end

    local y = -8
    local level = PV and PV_LEVEL or UnitLevel("player")
    if PV then
        Band(y + 2, 22)
        Txt(14, y - 2, "|cFFFFD100PREVIEW|r  made-up level 40 " .. PV:sub(1, 1) .. PV:sub(2):lower() .. ", not your numbers. Scan or close to go back.", T.text, 12, WIDTH - 60)
        y = y - 28
    end
    local resto = 0
    for _, p in pairs(snap.points or {}) do resto = math.max(resto, p) end

    -- your character
    y = y - Head(y, "Your character (from your last scan)")
    Txt(14, y, "Level " .. level .. "   " .. (PV and (PV:sub(1, 1) .. PV:sub(2):lower()) or UnitClass("player")) .. "   Bonus healing " .. Gold(Fmt(snap.bonus)) .. "   Intellect " .. Gold(Fmt(snap.int)) .. "   Spirit " .. Gold(Fmt(snap.spirit)) .. "   Mana " .. Gold(Fmt(snap.mana)), T.desc, 12, WIDTH - 60)
    y = y - 18
    if snap.regenOut then
        local regen = "Mana per second: " .. Gold(Fmt1(snap.regenOut)) .. " resting"
        if snap.regenIn then regen = regen .. ", " .. Gold(Fmt1(snap.regenIn)) .. " while casting" end
        Txt(14, y, regen, T.desc, 12, WIDTH - 60)
        y = y - 18
    end
    Txt(14, y, Grey("Scanned " .. (snap.time or "?") .. ". Press Scan after changing gear or talents."), T.desc, 11, WIDTH - 60)
    y = y - 26

    -- talents
    y = y - Head(y, "What your healing talents do")
    if #snap.talents == 0 then
        Txt(14, y, "No healing talents with points in them, so nothing changes the numbers.", T.desc, 12, WIDTH - 60)
        y = y - 20
    end
    local TAGS = {
        cast = { "|cFF4FD66B", "counted" }, heal = { "|cFF4FD66B", "counted" },
        cost = { "|cFFFFD100", "already in your mana costs" }, other = { "|cFFB0B0B0", "listed, not counted" },
    }
    for _, tl in ipairs(snap.talents) do
        local tag = TAGS[tl.kind] or TAGS.other
        Txt(14, y, "|cFFFFD100\226\128\162|r " .. tl.name .. " " .. tl.rank .. (tl.max and ("/" .. tl.max) or "") .. "   " .. tag[1] .. tag[2] .. "|r", T.desc, 12, WIDTH - 60)
        y = y - 16
        local h = Para(y, tl.text ~= "" and tl.text or "(no description)", T.dim, 26, WIDTH - 80)
        y = y - h - 6
    end
    y = y - 12

    -- which rank for what
    y = y - Head(y, "Which rank for what")
    Txt(14, y, "Situation", T.dim, 11, 250)
    Txt(270, y, "Use", T.dim, 11, 160)
    Num(COL.heals, y, "Heals", T.dim, 11)
    Num(COL.mana, y, "Mana", T.dim, 11)
    Num(COL.cast, y, "Cast", T.dim, 11)
    y = y - 20
    local rows = Situations(spells, snap)
    if #rows == 0 then
        Txt(14, y, "No healing spells found in your spellbook yet.", T.desc, 12, WIDTH - 60)
        y = y - 20
    end
    for i, row in ipairs(rows) do
        local r = row.rec
        if i % 2 == 1 then Band(y, 40) end
        Txt(14, y - 2, row.label, T.text, 12, 250)
        Txt(270, y - 2, r and Gold(r.spell .. " " .. r.rank) or Grey("none"), T.text, 12, 160)
        if r then
            Num(COL.heals, y - 2, Fmt(r.heal))
            Num(COL.mana, y - 2, Fmt(r.cost))
            Num(COL.cast, y - 2, Fmt1(r.cast) .. "s")
        end
        local why = row.why
        Txt(14, y - 20, Grey(why), T.text, 11, WIDTH - 70)
        y = y - 44
    end
    y = y - 8

    -- all ranks
    y = y - Head(y, "Every rank you know")
    Txt(14, y, "Spell", T.dim, 11, 200)
    Num(320, y, "Heals", T.dim, 11)
    Num(380, y, "Mana", T.dim, 11)
    Num(440, y, "Cast", T.dim, 11)
    Num(515, y, "Per mana", T.dim, 11)
    Num(600, y, "Bonus kept", T.dim, 11)
    y = y - 20
    local any = false
    local n = 0
    local order = {}
    for _, group in ipairs({ MYFAM.main, MYFAM.fast, MYFAM.group }) do
        for _, name in ipairs(group) do order[#order + 1] = name end
    end
    for _, name in ipairs(order) do
        for _, r in ipairs(spells[name] or {}) do
            any = true
            n = n + 1
            if n % 2 == 0 then Band(y, 17) end
            Txt(14, y, r.spell .. "  " .. Grey("Rank " .. r.rank), T.text, 12, 220)
            Num(320, y, Fmt(r.heal))
            Num(380, y, Fmt(r.cost))
            Num(440, y, Fmt1(r.cast) .. "s")
            Num(515, y, r.hpm and Fmt1(r.hpm) or "?")
            Num(600, y, math.floor(100 * r.keep + 0.5) .. "%")
            y = y - 17
        end
    end
    if not any then
        Txt(14, y, "No healing spells found in your spellbook yet.", T.desc, 12, WIDTH - 60)
        y = y - 18
    end
    y = y - 10
    y = y - Para(y, "Per mana is heal divided by mana cost. Bonus kept is how much of your bonus healing the rank keeps: spells learned under level 20 and ranks far below your level lose some, which is the downranking penalty. Group heals show the first target. Damage-over-time and heal-over-time parts of spells (Regrowth, Renew) are not counted. These are estimates; /cuiheal logs the heal preview next to the real heal if a number looks off.", T.dim) - 10

    content:SetHeight(math.max(-y + 10, 100))
end

--------------------------------------------------------------------------------
-- "Your recommendations have changed" popup
--------------------------------------------------------------------------------
local popup
local LABELS = { small = "Small hits", general = "General healing", heavy = "Heavy damage", fast = "Emergency", group = "Group healing" }
local ORDER = { "small", "general", "heavy", "fast", "group" }

local function BuildPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", "CysHealAdvisorPopup", UIParent)
    popup:SetSize(380, 130)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -160)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    W.Texture(popup, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(popup, 2, T.border, "BORDER")
    local strip = W.Texture(popup, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(20)
    local line = W.Texture(popup, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -22)
    line:SetPoint("TOPRIGHT", -2, -22)
    line:SetHeight(2)
    local head = W.Text(popup, 11, T.accent, "CENTER")
    head:SetPoint("TOP", popup, "TOP", 0, -7)
    head:SetText("CYS'S HEAL ADVISOR")
    popup.title = W.Text(popup, 12, T.accent)
    popup.title:SetPoint("TOPLEFT", 12, -32)
    popup.title:SetText("Your recommendations have changed")
    popup.body = W.Text(popup, 12, T.desc)
    popup.body:SetPoint("TOPLEFT", 12, -52)
    popup.body:SetWidth(356)
    popup.body:SetJustifyV("TOP")
    popup.body:SetSpacing(3)
    popup.open = W.Button(popup, 120, 22, "Open the advisor", true)
    popup.open:SetPoint("BOTTOMLEFT", 12, 10)
    popup.open:SetScript("OnClick", function() popup:Hide(); SlashCmdList["CYSRANK"]("open") end)
    popup.close = W.Button(popup, 90, 22, "Dismiss")
    popup.close:SetPoint("LEFT", popup.open, "RIGHT", 8, 0)
    popup.close:SetScript("OnClick", function() popup:Hide() end)
    popup:Hide()
    return popup
end

local function CheckChanges()
    if not MYFAM then return end
    local db = DB()
    if not db.notify then return end
    local snap = db.snap[CharKey()]
    if not (snap and snap.recs) then return end -- nothing scanned yet: nothing to compare with
    local spells = Analyze(snap)
    local recs, ok = Recs(spells, snap)
    if not ok then return end
    local changes = {}
    for _, key in ipairs(ORDER) do
        local old, new = snap.recs[key], recs[key]
        if new and old ~= new then
            changes[#changes + 1] = LABELS[key] .. ": " .. (old and (old .. "  >  ") or "new: ") .. new
        end
    end
    if #changes == 0 then return end
    snap.recs = recs
    BuildPopup()
    popup.body:SetText(table.concat(changes, "\n"))
    popup:SetHeight(86 + 16 * #changes)
    popup:Show()
end

--------------------------------------------------------------------------------
-- The window frame
--------------------------------------------------------------------------------
local function Build()
    if win then return win end
    win = CreateFrame("Frame", "CysHealAdvisorFrame", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    tinsert(UISpecialFrames, "CysHealAdvisorFrame")
    W.Texture(win, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(win, 2, T.border, "BORDER")
    local strip = W.Texture(win, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(24)
    local line = W.Texture(win, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -26)
    line:SetPoint("TOPRIGHT", -2, -26)
    line:SetHeight(2)
    local title = W.Text(win, 12, T.accent)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("CYS'S HEAL ADVISOR")
    local sub = W.Text(win, 11, T.desc)
    sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    sub:SetText("which rank, for what")

    local close = W.Button(win, 22, 18, "X")
    close:SetPoint("TOPRIGHT", -6, -7)
    close:SetScript("OnClick", function() win:Hide() end)
    local again = W.Button(win, 90, 18, "Scan", true)
    again:SetPoint("RIGHT", close, "LEFT", -6, 0)
    again:SetScript("OnClick", function()
        if PV then PV = nil; MYFAM = FAMILY[myClass] end
        if not MYFAM then win:Hide() return end
        Refresh(true)
    end)
    local rep = W.Button(win, 100, 18, "Copy report")
    rep:SetPoint("RIGHT", again, "LEFT", -6, 0)
    rep:SetScript("OnClick", function() CUI.HealAdvisorReport() end)

    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 6, -34)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 12, 100)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        s:SetVerticalScroll(math.max(0, math.min(s:GetVerticalScroll() - delta * 40, s:GetVerticalScrollRange())))
    end)
    lines = {}
    -- closing the window always ends a preview, so /cuirank opens your real character next time
    win:SetScript("OnHide", function()
        if PV then PV = nil; MYFAM = FAMILY[myClass] end
    end)
    return win
end

local function Toggle(show)
    if not MYFAM and not PV then
        CUI:Print("Cys's Heal Advisor covers Druids, Paladins, Priests and Shamans. Your class has no healing spells to compare.")
        return
    end
    Build()
    if win:IsShown() and not show then win:Hide() return end
    Refresh(false)
    win:Show()
end

function CUI.HealAdvisorPreview(class)
    PV = class
    MYFAM = FAMILY[class]
    Build()
    Refresh(false)
    win:Show()
end

-- A plain-text report a tester can copy and paste into a GitHub issue (nothing is sent anywhere).
local reportWin
function CUI.HealAdvisorReport()
    if not FAMILY[myClass] then
        CUI:Print("The Heal Advisor report is for Druids, Paladins, Priests and Shamans.")
        return
    end
    local saved, savedPV = MYFAM, PV
    PV = nil
    MYFAM = FAMILY[myClass]
    local out = {}
    local function add(s) out[#out + 1] = s end
    local version, build = "?", "?"
    if GetBuildInfo then version, build = GetBuildInfo() end
    add("Cys's UI " .. CUI:GetVersion("CysUI") .. " Heal Advisor report")
    add("Game " .. tostring(version) .. " (" .. tostring(build) .. "), " .. myClass .. ", level " .. UnitLevel("player"))
    local snap = TakeSnapshot()
    add(string.format("Bonus healing %s, Intellect %s, Spirit %s, Mana %s", Fmt(snap.bonus), Fmt(snap.int), Fmt(snap.spirit), Fmt(snap.mana)))
    add("")
    add("Talents with points (kind: what the addon decided):")
    for _, tl in ipairs(snap.talents) do
        add(string.format("- %s %s/%s [%s %s] %s", tl.name, tl.rank, tostring(tl.max), tl.kind, tostring(tl.value), (tl.text or ""):sub(1, 100)))
    end
    add("")
    add("Ranks (spell, rank, id, learned-level from game, advisor heal, mana cost, heal test, raw description):")
    local spells = Analyze(snap)
    local getDesc = GetSpellDescription or (C_Spell and C_Spell.GetSpellDescription)
    for _, group in ipairs({ MYFAM.main, MYFAM.fast, MYFAM.group }) do
        for _, name in ipairs(group) do
            for _, r in ipairs(spells[name] or {}) do
                local raw = ""
                if getDesc then
                    local ok, d = pcall(getDesc, r.id)
                    if ok and type(d) == "string" then raw = d:gsub("[\r\n]+", " "):sub(1, 45) end
                end
                local lv = GetSpellLevelLearned and GetSpellLevelLearned(r.id) or "?"
                local castTxt = ""
                if GetSpellInfo then
                    local okI, _, _, _, castMs = pcall(GetSpellInfo, r.id)
                    if okI and type(castMs) == "number" then
                        castTxt = string.format(" cast game %.1f adv %s", castMs / 1000, Fmt1(r.cast))
                    end
                end
                local t = ht.ranks[r.id]
                local test = castTxt
                if t then
                    test = castTxt .. string.format(" | amount %s, overheal %s%s", tostring(t.real), tostring(t.over or 0), t.clean and "" or " (critical, not clean)")
                end
                add(string.format("- %s rank %s id %s lvl %s heal %s cost %s%s | %s", name, r.rank, tostring(r.id), tostring(lv), Fmt(r.heal), Fmt(r.cost), test, raw))
            end
        end
    end
    local rows = Situations(spells, snap)
    add("")
    add("Advice:")
    for _, row in ipairs(rows) do
        add("- " .. row.label .. ": " .. (row.rec and (row.rec.spell .. " " .. row.rec.rank) or "none"))
    end
    if ht.unmatched then add("Heals heard but not matched to a rank: " .. ht.unmatched) end
    MYFAM, PV = saved, savedPV

    -- the Discord /bug command takes 1500 characters, so the report comes in parts of up to 1400
    local parts, cur = {}, ""
    for _, line in ipairs(out) do
        if #cur > 0 and #cur + #line + 1 > 1400 then
            parts[#parts + 1] = cur
            cur = ""
        end
        cur = (#cur > 0 and (cur .. "\n") or "") .. line
    end
    if #cur > 0 then parts[#parts + 1] = cur end
    local who = myClass .. " L" .. UnitLevel("player")
    if #parts > 1 then
        for i, text in ipairs(parts) do parts[i] = "Heal Advisor report part " .. i .. "/" .. #parts .. " (" .. who .. ")\n" .. text end
    end

    if not reportWin then
        reportWin = CreateFrame("Frame", "CysHealAdvisorReport", UIParent)
        reportWin:SetSize(560, 360)
        reportWin:SetPoint("CENTER")
        reportWin:SetFrameStrata("DIALOG")
        reportWin:SetClampedToScreen(true)
        reportWin:SetMovable(true)
        reportWin:EnableMouse(true)
        reportWin:RegisterForDrag("LeftButton")
        reportWin:SetScript("OnDragStart", reportWin.StartMoving)
        reportWin:SetScript("OnDragStop", reportWin.StopMovingOrSizing)
        tinsert(UISpecialFrames, "CysHealAdvisorReport")
        W.Texture(reportWin, "BACKGROUND", T.bg):SetAllPoints()
        W.Border(reportWin, 2, T.border, "BORDER")
        local t = W.Text(reportWin, 12, T.accent)
        t:SetPoint("TOPLEFT", 12, -10)
        t:SetText("HEAL ADVISOR REPORT")
        reportWin.title = t
        local hint = W.Text(reportWin, 11, T.desc)
        hint:SetPoint("TOPLEFT", 12, -30)
        hint:SetWidth(536)
        hint:SetJustifyH("LEFT")
        hint:SetText("In the cysui-feedback channel in Discord type /bug, pick your class under area, then paste this into text and send. Click in the box, press Ctrl+A then Ctrl+C. Nothing is sent from the game.")
        local nextBtn = W.Button(reportWin, 100, 18, "Next part", true)
        reportWin.nextBtn = nextBtn
        local x = W.Button(reportWin, 22, 18, "X")
        x:SetPoint("TOPRIGHT", -6, -7)
        x:SetScript("OnClick", function() reportWin:Hide() end)
        reportWin.nextBtn:SetPoint("RIGHT", x, "LEFT", -6, 0)
        local sf = CreateFrame("ScrollFrame", nil, reportWin)
        sf:SetPoint("TOPLEFT", 10, -64)
        sf:SetPoint("BOTTOMRIGHT", -10, 10)
        sf:EnableMouseWheel(true)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        eb:SetWidth(520)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        sf:SetScrollChild(eb)
        sf:SetScript("OnMouseWheel", function(s, d)
            s:SetVerticalScroll(math.max(0, math.min(s:GetVerticalScroll() - d * 30, s:GetVerticalScrollRange())))
        end)
        reportWin.eb = eb
    end
    reportWin.parts, reportWin.part = parts, 1
    local function ShowPart()
        reportWin.title:SetText("HEAL ADVISOR REPORT" .. (#parts > 1 and ("  -  part " .. reportWin.part .. " of " .. #parts) or ""))
        reportWin.eb:SetText(parts[reportWin.part] or "")
        reportWin.eb:SetFocus()
        reportWin.eb:HighlightText()
    end
    reportWin.nextBtn:SetShown(#parts > 1)
    reportWin.nextBtn:SetScript("OnClick", function()
        reportWin.part = reportWin.part % #parts + 1
        ShowPart()
    end)
    reportWin:Show()
    ShowPart()
end

SLASH_CYSRANK1 = "/cuirank"
SlashCmdList["CYSRANK"] = function(msg)
    msg = strtrim((msg or ""):lower())
    local pvWord = msg:match("^preview%s*(%a*)")
    if msg == "report" then
        CUI.HealAdvisorReport()
    elseif pvWord then
        local want = pvWord ~= "" and pvWord:upper() or myClass
        if not FAMILY[want] then want = "SHAMAN" end
        CUI.HealAdvisorPreview(want)
    elseif msg == "scan" then
        if PV then PV = nil; MYFAM = FAMILY[myClass] end
        Toggle(true)
        if MYFAM then Refresh(true) end
    else
        Toggle(msg == "open")
    end
end


--------------------------------------------------------------------------------
-- /cuiheal: the heal test. Scans, then logs what each heal rank really heals next to what the numbers say.
--------------------------------------------------------------------------------
local testBox, testRows
local ev = CreateFrame("Frame")

local function TestRanks()
    local out = {}
    local book = BookRanks()
    for _, group in ipairs(FamLists(FAMILY[myClass])) do
        for _, name in ipairs(group) do
            local ranks = {}
            for rank, id in pairs(book[name] or {}) do ranks[#ranks + 1] = { name = name, rank = rank, id = id } end
            table.sort(ranks, function(a, b) return a.rank < b.rank end)
            for _, r in ipairs(ranks) do out[#out + 1] = r end
        end
    end
    return out
end

local function RefreshTest()
    if not testBox then return end
    for _, o in ipairs(testRows) do o:Hide() end
    wipe(testRows)
    local function Line(y, text, color, size, x, width)
        local fs = W.Text(testBox, size or 12, color or T.text)
        fs:SetPoint("TOPLEFT", x or 12, y)
        fs:SetWidth(width or 336)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text)
        testRows[#testRows + 1] = fs
        return fs
    end
    local list = TestRanks()
    local done = 0
    for _, r in ipairs(list) do if ht.ranks[r.id] and ht.ranks[r.id].clean then done = done + 1 end end
    local y = -36
    local s1 = Line(y, "1. Cast each heal below once on anyone, even yourself at full health. A critical heal does not count (it doubles the number), so just cast that rank again.", T.desc, 11)
    y = y - math.max(s1:GetStringHeight(), 28) - 6
    local s2 = Line(y, "2. When it says All ranks logged, click Copy report. In the cysui-feedback channel in Discord type /bug, pick your class under area, and paste the report into text. If the report has more than one part, send each part the same way.", T.desc, 11)
    y = y - math.max(s2:GetStringHeight(), 28) - 8
    if #list == 0 then
        Line(y, "No heal ranks found in your spellbook yet.", T.text, 12)
        y = y - 20
    elseif done == #list then
        Line(y, "|cFF4FD66BAll ranks logged.|r Click Copy report.", T.text, 13)
        y = y - 22
    else
        Line(y, "Ranks logged: |cFFFFD100" .. done .. " / " .. #list .. "|r", T.text, 12)
        y = y - 20
    end
    for _, r in ipairs(list) do
        local t = ht.ranks[r.id]
        local mark, text
        if t and t.clean then
            mark, text = "|cFF4FD66BOK|r", "healed " .. t.real .. ((t.over or 0) > 0 and (", overheal " .. t.over) or "")
        elseif t then
            mark, text = "|cFFFF5555!|r", "cast it again (it was a critical)"
        else
            mark, text = "|cFF888888-|r", "|cFF888888waiting|r"
        end
        Line(y, mark .. "  " .. r.name .. " Rank " .. r.rank .. "   " .. text, T.text, 12)
        y = y - 17
    end
    if ht.heard then
        y = y - 6
        local hl = Line(y, "|cFF888888Last heard: " .. ht.heard .. "|r", T.desc, 10)
        y = y - math.max(hl:GetStringHeight(), 12)
    else
        y = y - 6
        local hl = Line(y, "|cFF888888Nothing heard yet. Cast a heal.|r", T.desc, 10)
        y = y - 12
    end
    testBox:SetHeight(-y + 14)
end

local function StopTest()
    if not ht.on then return end
    ht.on = false
    ev:UnregisterAllEvents()
    CUI:Print("Heal log is off.")
end

local function BuildTestBox()
    if testBox then return end
    testBox = CreateFrame("Frame", "CysHealTestFrame", UIParent)
    testBox:SetSize(360, 200)
    testBox:SetPoint("TOP", UIParent, "TOP", 0, -110)
    testBox:SetFrameStrata("HIGH")
    testBox:SetClampedToScreen(true)
    testBox:SetMovable(true)
    testBox:EnableMouse(true)
    testBox:RegisterForDrag("LeftButton")
    testBox:SetScript("OnDragStart", testBox.StartMoving)
    testBox:SetScript("OnDragStop", testBox.StopMovingOrSizing)
    testBox:Hide()
    testRows = {}
    W.Texture(testBox, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(testBox, 2, T.border, "BORDER")
    local strip = W.Texture(testBox, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(24)
    local title = W.Text(testBox, 12, T.accent)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("HEAL TEST")
    local close = W.Button(testBox, 22, 18, "X")
    close:SetPoint("TOPRIGHT", -6, -7)
    close:SetScript("OnClick", function() testBox:Hide() end)
    local copy = W.Button(testBox, 100, 18, "Copy report", true)
    copy:SetPoint("RIGHT", close, "LEFT", -6, 0)
    copy:SetScript("OnClick", function() CUI.HealAdvisorReport() end)
    -- closing the box ends the test: logging turns itself off
    testBox:SetScript("OnHide", StopTest)
end

ev:SetScript("OnEvent", function(_, event)
    if not ht.on then return end
    if event == "UNIT_SPELLCAST_START" then
        local name, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
        if not spellID then return end
        local tgt = UnitExists("target") and UnitIsFriend("player", "target") and "target" or "player"
        ht.pending[spellID] = UnitGetIncomingHeals and UnitGetIncomingHeals(tgt) or nil
        ht.lastCast = { name = name, id = spellID }
        ht.heard = "cast " .. tostring(name) .. " (id " .. tostring(spellID) .. ")"
        RefreshTest()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, sub, _, srcGUID, _, _, _, _, _, _, _, spellID, spellName, _, amount, overheal, _, crit = CombatLogGetCurrentEventInfo()
        if sub ~= "SPELL_HEAL" or srcGUID ~= UnitGUID("player") then return end
        -- match the heal to a rank: by its spell ID, else by the spell that was just cast
        local list = TestRanks()
        local known
        for _, r in ipairs(list) do if r.id == spellID then known = r.id break end end
        if not known and ht.lastCast and (spellName == ht.lastCast.name or spellName == nil) then
            for _, r in ipairs(list) do if r.id == ht.lastCast.id then known = r.id break end end
        end
        ht.heard = "heal " .. tostring(spellName) .. " (id " .. tostring(spellID) .. ", amount " .. tostring(amount) .. ")" .. (known and "" or " - not matched to a rank")
        if not known then
            ht.unmatched = (ht.unmatched or "") .. string.format("%s id %s; ", tostring(spellName), tostring(spellID))
            RefreshTest()
            return
        end
        spellID = known
        local old = ht.ranks[spellID]
        if old and old.clean then return end
        ht.ranks[spellID] = {
            real = amount, pred = ht.pending[spellID], over = overheal, crit = crit and true or false,
            clean = not crit and (amount or 0) > 0,
        }
        RefreshTest()
        local all = true
        for _, r in ipairs(TestRanks()) do
            if not (ht.ranks[r.id] and ht.ranks[r.id].clean) then all = false break end
        end
        if all then CUI:Print("Heal test: All ranks logged. Click Copy report.") end
    end
end)

SLASH_CUIHEAL1 = "/cuiheal"
SlashCmdList["CUIHEAL"] = function(msg)
    msg = strtrim((msg or ""):lower())
    if not FAMILY[myClass] then
        CUI:Print("The heal test is for Druids, Paladins, Priests and Shamans.")
        return
    end
    BuildTestBox()
    if msg == "off" then
        if ht.on then testBox:Hide() else CUI:Print("Heal log is already off.") end
        return
    elseif msg == "clear" then
        wipe(ht.ranks)
        wipe(ht.pending)
        RefreshTest()
        CUI:Print("Heal log cleared.")
        return
    end
    if ht.on then
        CUI:Print("Heal log is already on")
        testBox:Show()
        RefreshTest()
        return
    end
    wipe(ht.ranks)
    wipe(ht.pending)
    ht.heard, ht.unmatched, ht.lastCast = nil, nil, nil
    -- the scan runs by itself, so there is no Scan step
    TakeSnapshot()
    if win and win:IsShown() then Refresh(false) end
    ht.on = true
    ev:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    testBox:Show()
    RefreshTest()
    CUI:Print("Heal log is ON. Follow the steps in the Heal Test box.")
end

do
    local pending
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "TRAINER_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function()
        if pending or not MYFAM then return end
        pending = true
        C_Timer.After(3, function()
            pending = false
            if InCombatLockdown and InCombatLockdown() then return end
            pcall(CheckChanges)
            if win and win:IsShown() then Refresh(false) end
        end)
    end)
end

CUI:RegisterModule({
    key = "healadvisor", name = "Heal Advisor", class = { "DRUID", "PALADIN", "PRIEST", "SHAMAN" },
    desc = "Healers: /cuirank opens a window that reads your bonus healing, mana, spirit, healing talents and heal ranks and says which rank to use for small hits, general healing, heavy damage, emergencies and group healing. A popup tells you when something you learn changes the advice.",
    open = function() CUI:OpenConfig("Heal Advisor") end,
})

--------------------------------------------------------------------------------
-- Settings page (listed under Class > General for every class)
--------------------------------------------------------------------------------
CUI:RegisterPage("Heal Advisor", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Heal advisor", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    if not MYFAM then
        intro:SetText("For healers (Druid, Paladin, Priest, Shaman). Your class has no healing spells to compare, so there is nothing to set.")
        page.contentHeight = 120
        return
    end
    intro:SetText("Opens a window that reads your character and tells you which heal rank to use for what. It is a lookup you open between pulls, not something that pops up in combat.")

    local open = W.Button(page, 190, 22, "Open the advisor", true)
    open:SetPoint("TOPLEFT", 4, -92)
    open:SetScript("OnClick", function() Toggle(true) end)
    local scan = W.Button(page, 150, 22, "Scan now")
    scan:SetPoint("LEFT", open, "RIGHT", 10, 0)
    scan:SetScript("OnClick", function() Toggle(true); Refresh(true) end)

    local c = W.Checkbox(page, "Tell me when something I learn changes the advice", function() return db.notify end,
        function(on) db.notify = on end)
    c:SetPoint("TOPLEFT", 4, -130)

    local pvClass = myClass
    if not FAMILY[pvClass] then pvClass = "SHAMAN" end
    local pvDrop = W.Dropdown(page, 190, { { "SHAMAN", "Shaman" }, { "PRIEST", "Priest" }, { "DRUID", "Druid" }, { "PALADIN", "Paladin" } },
        function() return pvClass end, function(v) pvClass = v end, "Preview as: ")
    pvDrop:SetPoint("TOPLEFT", 4, -166)
    local pvBtn = W.Button(page, 150, 22, "Preview (level 40)")
    pvBtn:SetPoint("LEFT", pvDrop, "RIGHT", 10, 0)
    pvBtn:SetScript("OnClick", function() CUI.HealAdvisorPreview(pvClass) end)
    local repBtn = W.Button(page, 190, 22, "Copy report for Cys")
    repBtn:SetPoint("TOPLEFT", 4, -200)
    repBtn:SetScript("OnClick", function() CUI.HealAdvisorReport() end)

    W.Notes(page, 4, -240, width, "", {
        { "Preview", "shows the window with a made-up level 40 healer of the class you pick, so you can see the layout without playing that class. The numbers are samples." },
        { "Copy report", "builds a plain-text list of your ranks, spell IDs, mana costs and talents that you can copy and paste into a GitHub issue if a number looks wrong." },
        { "/cuirank", "opens or closes the window; /cuirank scan takes a new scan." },
        { "Scan", "saves your bonus healing, Intellect, Spirit, mana and healing talents. The advice keeps using that scan, so changing gear does not move it until you press Scan." },
        { "Talents", "each healing talent you have points in is read from its own tooltip. Cast-time and healing-bonus talents change the numbers; mana-cost talents are already in the game's mana costs; crit and chance talents are listed but not counted." },
        { "How it picks", "Heavy damage is your biggest heal that is still within 10% of your best heal per mana. General healing is the next size down that is also within 10%, which is faster and wastes less on normal tank damage. Small hits is the smallest rank within 20% of your best that still heals at least a fifth of your heavy heal. Emergency is your biggest heal that casts in 1.5 seconds or less. It never needs a health number, and only spells you know are named." },
        { "Popup", "when you learn a spell or level up and the advice would be different, a small popup shows what changed." },
        { "Classes", "Shaman, Priest, Druid and Paladin heals. Priest, Druid and Paladin are new and unchecked in game, so tell me if a number looks off." },
    })
end)
