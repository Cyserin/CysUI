--------------------------------------------------------------------------------
-- Cys's UI - Spell Ranks (WoW Forever)
--
-- A window that sits beside the spellbook and answers three questions:
--   To Train    what can I learn at my trainer right now, what does it cost, and what comes later
--   Max Ranks   which of my spells are behind the best rank for my level
--   Trainers    city by city: my class trainers, then each weapon master and the weapons they can still
--               teach me (a master with nothing left to teach is left out)
--
-- Where the list comes from: the spellbook (what you know, and any spells the game lists as still to come)
-- and your class trainer. Levels and prices are remembered every time you open your class trainer, so one
-- visit fills the whole list in. Nothing here touches Blizzard's spellbook: this is our own frame placed
-- next to it.
--
--   /cuiranks          open or close the window (it shows with the spellbook)
--   /cuiranks check    print what was read (handy when something looks wrong)
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "ranks", name = "Cys's Spell Ranks", foreverOnly = true,
    desc = "WoW Forever: a window beside the spellbook that lists what you can train now and what it costs, what comes at later levels, which spells are behind their best rank, and your weapon skills. Open your class trainer once to fill in the prices.",
    open = function() CysUI:OpenConfig("Spell Ranks") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T

CysUIDB.ranks = CysUIDB.ranks or {}
local db = CysUIDB.ranks
if db.open == nil then db.open = true end
db.tab = db.tab or "train"
if db.tab == "weapons" then db.tab = "where" end -- Weapons is part of Trainers now
db.trainer = db.trainer or {}
local _, CLASS = UnitClass("player")
CLASS = CLASS or "?"

local WIDTH, HEIGHT, ROW_H, ROWS = 330, 560, 24, 18
local LIST_TOP = -104
local QUESTION = 134400

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function RankOf(sub) return tonumber((sub or ""):match("(%d+)")) end
local function Key(name, rank) return name .. ":" .. (rank or 0) end

local function Coins(c)
    c = math.floor(tonumber(c) or 0)
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, c)
        if ok and s then return s end
    end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return g .. "g " .. s .. "s" end
    if s > 0 then return s .. "s " .. k .. "c" end
    return k .. "c"
end

local levelSeen = 0 -- PLAYER_LEVEL_UP can arrive before UnitLevel catches up
local function MyLevel()
    return math.max(UnitLevel("player") or 1, levelSeen)
end

--------------------------------------------------------------------------------
-- Reading the spellbook: what you know (name -> highest rank) and every spell line it lists
--------------------------------------------------------------------------------
local function ReadBook()
    local known, items = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank) then
        return known, items
    end
    local bank = Enum.SpellBookSpellBank.Player
    local SPELL = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local FUTURE = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    for s = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(s)
        if line and not line.isGuild and not line.offSpecID then
            for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                if ok and info and info.name and info.name ~= "" and not info.isOffSpec
                    and (info.itemType == SPELL or info.itemType == FUTURE) then
                    local rank = RankOf(info.subName)
                    local okL, lvl = pcall(C_SpellBook.GetSpellBookItemLevelLearned, i, bank)
                    local isKnown = info.itemType == SPELL
                    items[#items + 1] = {
                        name = info.name, rank = rank, id = info.spellID or info.actionID, icon = info.iconID,
                        level = (okL and tonumber(lvl)) or 0, known = isKnown,
                    }
                    if isKnown then
                        local r = rank or 1
                        if (known[info.name] or 0) < r then known[info.name] = r end
                    end
                end
            end
        end
    end
    return known, items
end

--------------------------------------------------------------------------------
-- Reading the class trainer. Rows are kept per class in CysUIDB.ranks.trainer[CLASS].rows[name:rank] =
-- { n = name, r = rank, l = level, c = cost, i = icon, id = spellID }. The trainer's own filters are left
-- alone: we read whatever it lists and add to what earlier visits saved.
--------------------------------------------------------------------------------
local STATES = { available = true, unavailable = true, used = true }
local live -- name:rank -> the trainer's word for it, while a class trainer is open

local function ServiceSpellID(i)
    if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
    if ok and type(data) == "table" and type(data.id) == "number" and data.id > 0 then return data.id end
    return nil
end

-- name, state, icon, level, rank text - the order differs between clients, so look for the state word
local function Service(i)
    local name, a, b, c, d = GetTrainerServiceInfo(i)
    if not name then return nil end
    if STATES[a] then return name, a, b, tonumber(c), d end
    if STATES[b] then
        return name, b, GetTrainerServiceIcon and GetTrainerServiceIcon(i),
            GetTrainerServiceLevelReq and tonumber(GetTrainerServiceLevelReq(i)), a
    end
    return nil
end

local function ReadTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return false end
    local n = GetNumTrainerServices() or 0
    if n == 0 then return false end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    if C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType and Enum.TrainerType.Pet
        and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet then return false end

    -- weapon masters and riding trainers use the same window: a class trainer is one that teaches ranks
    local list, ranked, top = {}, false, 0
    for i = 1, n do
        local name, state, icon, req, sub = Service(i)
        if name then
            local rank = RankOf(sub)
            if rank then ranked = true end
            req = req or 0
            if req > top then top = req end
            local cost = GetTrainerServiceCost and (GetTrainerServiceCost(i)) or nil
            list[#list + 1] = { name = name, state = state, icon = icon, req = req, rank = rank,
                                cost = tonumber(cost), id = ServiceSpellID(i) }
        end
    end
    if not ranked then return false end

    -- remember who this trainer is and where (the Trainers tab marks the ones you have opened)
    pcall(function()
        local npc = UnitName("npc")
        if type(npc) ~= "string" or npc == "" then return end
        local zone = GetRealZoneText and GetRealZoneText() or ""
        local sub = GetSubZoneText and GetSubZoneText() or ""
        db.seen = db.seen or {}
        db.seen[CLASS] = db.seen[CLASS] or {}
        db.seen[CLASS][npc] = (sub ~= "" and sub ~= zone) and (zone .. ", " .. sub) or zone
    end)

    local rec = db.trainer[CLASS]
    if not rec or type(rec.rows) ~= "table" then
        rec = { rows = {} }
        db.trainer[CLASS] = rec
    end
    local seen, now = {}, {}
    for _, s in ipairs(list) do
        local k = Key(s.name, s.rank)
        local row = rec.rows[k] or {}
        rec.rows[k] = row
        row.n, row.r = s.name, s.rank
        if s.req > 0 or not row.l then row.l = s.req end
        if s.cost and s.cost > 0 then row.c = s.cost end
        row.i = s.icon or row.i
        row.id = s.id or row.id
        seen[k], now[k] = true, s.state
    end
    -- A spell this trainer no longer offers (a talent you dropped, say) leaves the list - but only when the
    -- trainer is showing everything it has and the spell is within the levels it teaches.
    local full = GetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter("available")
        and GetTrainerServiceTypeFilter("unavailable")
    if full then
        local known = ReadBook()
        for k, row in pairs(rec.rows) do
            if not seen[k] and (row.l or 0) <= top and not (known[row.n] and known[row.n] >= (row.r or 1)) then
                rec.rows[k] = nil
            end
        end
    end
    rec.level = MyLevel()
    rec.date = date("%Y-%m-%d")
    live = now
    return true
end

--------------------------------------------------------------------------------
-- Weapon skills each class can learn (Classic's own list; the spell IDs are the weapon skills themselves)
--------------------------------------------------------------------------------
local WEAPON_ORDER = { 201, 202, 196, 197, 198, 199, 1180, 15590, 200, 227, 264, 266, 5011, 2567, 5009 }
local WEAPON_NAMES = {
    [201] = "One-Handed Swords", [202] = "Two-Handed Swords", [196] = "One-Handed Axes", [197] = "Two-Handed Axes",
    [198] = "One-Handed Maces", [199] = "Two-Handed Maces", [1180] = "Daggers", [15590] = "Fist Weapons",
    [200] = "Polearms", [227] = "Staves", [264] = "Bows", [266] = "Guns", [5011] = "Crossbows",
    [2567] = "Thrown", [5009] = "Wands",
}
local function Set(...)
    local t = {}
    for i = 1, select("#", ...) do t[(select(i, ...))] = true end
    return t
end
local WEAPONS = {
    WARRIOR = Set(201, 202, 196, 197, 198, 199, 1180, 15590, 200, 227, 264, 266, 5011, 2567),
    PALADIN = Set(201, 202, 196, 197, 198, 199, 200),
    HUNTER  = Set(201, 202, 196, 197, 1180, 15590, 200, 227, 264, 266, 5011, 2567),
    ROGUE   = Set(201, 198, 1180, 15590, 264, 266, 5011, 2567),
    PRIEST  = Set(198, 1180, 227, 5009),
    SHAMAN  = Set(196, 198, 1180, 15590, 227),
    MAGE    = Set(201, 1180, 227, 5009),
    WARLOCK = Set(201, 1180, 227, 5009),
    DRUID   = Set(198, 199, 1180, 15590, 227),
}
local WEAPON_NOTES = {
    SHAMAN = "Two-Handed Axes and Two-Handed Maces come from a talent, not a weapon master.",
}

-- Weapon masters (Classic's own): city, where in the city, then each master and the weapon skills they teach
local WEAPON_MASTERS = {
    Alliance = {
        { "Stormwind", "Trade District", { { "Woo Ping", { 201, 202, 200, 227, 5011, 1180 } } } },
        { "Ironforge", "Military Ward", { { "Buliwyf Stonehand", { 196, 197, 198, 199, 15590, 266 } },
                                          { "Bixi Wobblebonk", { 1180, 5011, 2567 } } } },
        { "Darnassus", "Warrior's Terrace", { { "Ilyenia Moonfire", { 1180, 15590, 227, 264, 2567 } } } },
    },
    Horde = {
        { "Orgrimmar", "Valley of Honor", { { "Hanashi", { 196, 197, 227, 264, 2567 } },
                                            { "Sayoc", { 196, 197, 1180, 15590, 264, 2567 } } } },
        { "Thunder Bluff", "Lower rise", { { "Ansekhwa", { 198, 199, 227, 266 } } } },
        { "Undercity", "War Quarter", { { "Archibald", { 201, 202, 1180, 200, 5011 } } } },
    },
}
local WEAPON_EXTRA = { [5009] = "Wands: every class that can use them knows the skill from the start." }

-- Class trainers in the capital cities (Classic's own): city, where in the city, who
local CITY_TRAINERS = {
    Alliance = {
        WARRIOR = {
            { "Stormwind", "Old Town, Command Center", { "Ilsa Corbin", "Wu Shen", "Lyria Du Lac" } },
            { "Ironforge", "Military Ward, Hall of Arms", { "Kelstrum Stonebreaker", "Bilban Tosslespanner", "Kelv Sternhammer" } },
            { "Darnassus", "Warrior's Terrace", { "Arias'ta Bladesinger", "Sildanair", "Darnath Bladesinger" } },
        },
        PALADIN = {
            { "Stormwind", "Cathedral of Light", { "Lord Grayson Shadowbreaker", "Arthur the Faithful", "Katherine the Pure" } },
            { "Ironforge", "Mystic Ward, Hall of Mysteries", { "Valgar Highforge", "Beldruk Doombrow", "Brandur Ironhammer" } },
        },
        HUNTER = {
            { "Stormwind", "Dwarven District", { "Einris Brightspear", "Ulfir Ironbeard", "Thorfin Stoneshield" } },
            { "Ironforge", "Military Ward, Hall of Arms", { "Regnus Thundergranite", "Daera Brightspear", "Olmin Burningbeard" } },
            { "Darnassus", "Cenarion Enclave", { "Jocaste", "Dorion", "Jeen'ra Nightrunner" } },
        },
        ROGUE = {
            { "Stormwind", "Old Town, SI:7", { "Osborne the Night Man", "Lord Tony Romano", "Renzik \"The Shiv\"" } },
            { "Ironforge", "The Forlorn Cavern", { "Hulfdan Blackbeard", "Ormyr Flinteye", "Fenthwick" } },
            { "Darnassus", "Cenarion Enclave", { "Syurna", "Anishar", "Erion Shadewhisper" } },
        },
        PRIEST = {
            { "Stormwind", "Cathedral of Light", { "High Priestess Laurena", "Brother Joshua", "Brother Benjamin" } },
            { "Ironforge", "Mystic Ward, Hall of Mysteries", { "High Priest Rohan", "Braenna Flintcrag", "Toldren Deepiron" } },
            { "Darnassus", "Temple of the Moon", { "Jandria", "Lariia", "Astarii Starseeker" } },
        },
        MAGE = {
            { "Stormwind", "Mage Quarter, Wizard's Sanctum", { "Jennea Cannon", "Elsharin", "Maginor Dumas" } },
            { "Ironforge", "Mystic Ward, Hall of Mysteries", { "Juli Stormkettle", "Bink", "Dink" } },
        },
        WARLOCK = {
            { "Stormwind", "Mage Quarter, The Slaughtered Lamb", { "Demisette Cloyce", "Ursula Deline", "Sandahl" } },
            { "Ironforge", "The Forlorn Cavern", { "Briarthorn", "Alexander Calder", "Thistleheart" } },
        },
        DRUID = {
            { "Stormwind", "The Park", { "Sheldras Moontree", "Theridran", "Maldryn" } },
            { "Darnassus", "Cenarion Enclave", { "Mathrengyl Bearwalker", "Denatharion", "Fylerian Nightwing" } },
            { "Moonglade", "Nighthaven", { "Loganaar" } },
        },
    },
    Horde = {
        WARRIOR = {
            { "Orgrimmar", "Valley of Honor", { "Grezz Ragefist", "Sorek", "Zel'mak" } },
            { "Thunder Bluff", "Hunter Rise", { "Sark Ragetotem", "Ker Ragetotem", "Torm Ragetotem" } },
            { "Undercity", "War Quarter", { "Angela Curthas", "Baltus Fowler", "Christoph Walker" } },
        },
        HUNTER = {
            { "Orgrimmar", "Valley of Honor", { "Ormak Grimshot", "Xor'juul", "Sian'dur" } },
            { "Thunder Bluff", "Hunter Rise", { "Holt Thunderhorn", "Urek Thunderhorn", "Kary Thunderhorn" } },
        },
        ROGUE = {
            { "Orgrimmar", "Cleft of Shadow", { "Shenthul", "Ormok", "Gest" } },
            { "Undercity", "Rogues' Quarter", { "Carolyn Ward", "Miles Dexter", "Gregory Charles" } },
        },
        PRIEST = {
            { "Orgrimmar", "Valley of Spirits", { "Ur'kyo", "X'yera", "Zayus" } },
            { "Thunder Bluff", "Spirit Rise, Pools of Vision", { "Father Cobb", "Malakai Cross", "Miles Welsh" } },
            { "Undercity", "War Quarter", { "Aelthalyste", "Father Lankester", "Father Lazarus" } },
        },
        SHAMAN = {
            { "Orgrimmar", "Valley of Wisdom", { "Kardris Dreamseeker", "Sian'tsu", "Sagorne Creststrider" } },
            { "Thunder Bluff", "Spirit Rise", { "Tigor Skychaser", "Beram Skychaser", "Siln Skychaser" } },
        },
        MAGE = {
            { "Orgrimmar", "Valley of Spirits", { "Pephredo", "Enyo", "Deino" } },
            { "Thunder Bluff", "Spirit Rise, Pools of Vision", { "Archmage Shymm", "Thurston Xane", "Ursyn Ghull" } },
            { "Undercity", "Magic Quarter", { "Kaelystia Hatebringer", "Pierce Shackleton", "Anastasia Hartwell" } },
        },
        WARLOCK = {
            { "Orgrimmar", "Cleft of Shadow", { "Mirket", "Grol'dar", "Zevrost" } },
            { "Undercity", "Magic Quarter", { "Kaal Soulreaper", "Luther Pickman", "Richard Kerwin" } },
        },
        DRUID = {
            { "Thunder Bluff", "Elder Rise", { "Turak Runetotem", "Sheal Runetotem", "Kym Wildmane" } },
            { "Moonglade", "Nighthaven", { "Loganaar" } },
        },
    },
}
local function Faction()
    local ok, f = pcall(UnitFactionGroup, "player")
    return ok and f or nil
end

local function SpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and yes then return true end
    end
    if IsPlayerSpell then
        local ok, yes = pcall(IsPlayerSpell, id)
        if ok and yes then return true end
    end
    if IsSpellKnown then
        local ok, yes = pcall(IsSpellKnown, id)
        if ok and yes then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Putting it together
--------------------------------------------------------------------------------
local data = { fam = {}, train = {}, max = {}, weapons = {}, ready = 0, readyCost = 0, readyUnpriced = 0,
               behind = 0, ranked = 0, haveTrainer = false, weaponsKnown = 0 }

local function Rebuild()
    local known, items = ReadBook()
    local level = MyLevel()
    local uni = {}
    local rec = db.trainer[CLASS]
    data.haveTrainer = false
    if rec and type(rec.rows) == "table" then
        for k, row in pairs(rec.rows) do
            if row.n then
                uni[k] = { name = row.n, rank = row.r, level = row.l or 0, cost = row.c, icon = row.i, id = row.id }
                data.haveTrainer = true
            end
        end
    end
    for _, it in ipairs(items) do
        local k = Key(it.name, it.rank)
        local e = uni[k]
        if not e then
            e = { name = it.name, rank = it.rank, level = it.level or 0 }
            uni[k] = e
        end
        e.id = e.id or it.id
        e.icon = e.icon or it.icon
        if (e.level or 0) == 0 and (it.level or 0) > 0 then e.level = it.level end
        if it.known then e.known = true end
    end

    local fam = {}
    for k, e in pairs(uni) do
        e.state = live and live[k] or nil
        if not e.known then
            if e.state == "used" then e.known = true
            elseif known[e.name] and known[e.name] >= (e.rank or 1) then e.known = true end
        end
        local f = fam[e.name]
        if not f then f = {}; fam[e.name] = f end
        f[#f + 1] = e
    end
    for _, f in pairs(fam) do
        table.sort(f, function(a, b) return (a.rank or 0) < (b.rank or 0) end)
    end
    data.fam = fam

    -- To Train: everything not known; "ready" = your level is high enough (and the trainer agrees, when open)
    local train = {}
    data.ready, data.readyCost, data.readyUnpriced = 0, 0, 0
    for _, e in pairs(uni) do
        if not e.known then
            e.ready = (e.level or 0) <= level and e.state ~= "unavailable"
            if e.ready then
                data.ready = data.ready + 1
                if e.cost and e.cost > 0 then data.readyCost = data.readyCost + e.cost
                else data.readyUnpriced = data.readyUnpriced + 1 end
            end
            train[#train + 1] = e
        end
    end
    table.sort(train, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la < lb end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rank or 0) < (b.rank or 0)
    end)
    data.train = train

    -- Max Ranks: spells with more than one rank that you know at least one rank of
    local maxList = {}
    data.behind, data.ranked = 0, 0
    for name, f in pairs(fam) do
        local top = f[#f]
        if top.rank and top.rank >= 2 and known[name] then
            local have, best, nextUp, shown = known[name], known[name], nil, nil
            for _, e in ipairs(f) do
                local r = e.rank or 1
                if r <= have then shown = e end
                if r > have then
                    if (e.level or 0) <= level and (e.level or 0) > 0 and r > best then best = r end
                    if not nextUp then nextUp = e end
                end
            end
            data.ranked = data.ranked + 1
            if best > have then data.behind = data.behind + 1 end
            maxList[#maxList + 1] = { name = name, have = have, best = best, top = top.rank, next = nextUp,
                                      e = shown or f[1], behind = best > have }
        end
    end
    table.sort(maxList, function(a, b)
        if a.behind ~= b.behind then return a.behind end
        return a.name < b.name
    end)
    data.max = maxList

    -- Weapons
    local weapons, mine = {}, WEAPONS[CLASS]
    data.weaponsKnown = 0
    if mine then
        for _, id in ipairs(WEAPON_ORDER) do
            if mine[id] then
                local has = SpellKnown(id)
                if has then data.weaponsKnown = data.weaponsKnown + 1 end
                local icon
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
                    if ok then icon = tex end
                end
                weapons[#weapons + 1] = { id = id, name = WEAPON_NAMES[id], known = has, icon = icon }
            end
        end
    end
    data.weapons = weapons
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local win, opener, bookUp, winUp
local rows, view, offset = {}, {}, 0
local Sync, Refresh

local function Hex(c)
    return string.format("|cFF%02X%02X%02X", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local GREY = { 0.50, 0.50, 0.50 }
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"

-- a note takes as many rows as it needs (rows are one line high)
local NOTE_CHARS = 48
local function Note(text)
    local line = ""
    for word in text:gmatch("%S+") do
        if line ~= "" and #line + 1 + #word > NOTE_CHARS then
            view[#view + 1] = { kind = "note", text = line }
            line = word
        else
            line = (line == "" and word) or (line .. " " .. word)
        end
    end
    if line ~= "" then view[#view + 1] = { kind = "note", text = line } end
end

local function BuildView()
    wipe(view)
    local tab = db.tab
    if tab == "train" then
        local later
        if data.ready > 0 then view[#view + 1] = { kind = "head", text = "Ready to train", right = tostring(data.ready) } end
        for _, e in ipairs(data.train) do
            if not e.ready and not later then
                later = true
                view[#view + 1] = { kind = "head", text = "Later levels" }
            end
            view[#view + 1] = {
                kind = "spell", e = e, dim = not e.ready, mark = e.ready,
                lv = (e.level or 0) > 0 and tostring(e.level) or "",
                right = (e.cost and e.cost > 0) and Coins(e.cost) or "",
            }
        end
        if #data.train == 0 then
            Note(data.haveTrainer and "Nothing left to train. Every spell on your trainer's list is learned."
                or "No trainer list yet. Open your class trainer once and this fills in.")
        end
    elseif tab == "max" then
        local up
        if data.behind > 0 then view[#view + 1] = { kind = "head", text = "A better rank is ready", right = tostring(data.behind) } end
        for _, m in ipairs(data.max) do
            if not m.behind and not up then
                up = true
                view[#view + 1] = { kind = "head", text = "Best rank for your level" }
            end
            local right
            if m.behind then
                right = Hex(T.accent) .. "Rank " .. m.best .. " ready|r"
            elseif m.next and (m.next.level or 0) > 0 then
                right = "next at " .. m.next.level
            elseif m.have >= m.top then
                right = Hex(T.green) .. "top rank|r"
            else
                right = ""
            end
            view[#view + 1] = { kind = "spell", e = m.e, mark = m.behind, lv = tostring(m.have), right = right,
                                sub = "of " .. m.top }
        end
        if #data.max == 0 then
            Note("No ranked spells found yet. Open your class trainer once so the ranks are known.")
        end
    else -- "where": one block per city - class trainers, then weapon masters and what they teach you
        local seen = (db.seen and db.seen[CLASS]) or {}
        local listed, byID = {}, {}
        for _, w in ipairs(data.weapons) do byID[w.id] = w end
        local fac = Faction() or ""
        local trainers = CITY_TRAINERS[fac] and CITY_TRAINERS[fac][CLASS] or {}
        local masters = WEAPON_MASTERS[fac] or {}
        local cities, order = {}, {}
        local function City(name)
            if not cities[name] then cities[name] = {}; order[#order + 1] = name end
            return cities[name]
        end
        for _, c in ipairs(trainers) do City(c[1]).trainers = c end
        local taught = {}
        for _, m in ipairs(masters) do
            local list = {}
            for _, who in ipairs(m[3]) do
                local mine = {}
                for _, id in ipairs(who[2]) do
                    if byID[id] then
                        mine[#mine + 1] = byID[id]
                        taught[id] = true
                        byID[id].from = byID[id].from or {}
                        byID[id].from[#byID[id].from + 1] = who[1] .. " (" .. m[1] .. ")"
                    end
                end
                -- a master with nothing left to teach you is left out (unless the game can't tell us what you know)
                local left = 0
                for _, w in ipairs(mine) do if not w.known then left = left + 1 end end
                table.sort(mine, function(x, y)
                    if x.known ~= y.known then return not x.known end
                    return x.name < y.name
                end)
                if #mine > 0 and (left > 0 or data.weaponsKnown == 0) then list[#list + 1] = { who[1], mine } end
            end
            if #list > 0 then
                local c = City(m[1])
                c.masters, c.masterPlace = list, m[2]
            end
        end
        for _, name in ipairs(order) do
            local c = cities[name]
            view[#view + 1] = { kind = "head", text = name }
            if c.trainers then
                view[#view + 1] = { kind = "line", text = Hex(T.accent) .. "Class trainers|r", right = c.trainers[2] }
                for _, who in ipairs(c.trainers[3]) do
                    listed[who] = true
                    view[#view + 1] = { kind = "line", text = who, indent = true,
                                        right = seen[who] and (Hex(T.green) .. "visited|r") or "" }
                end
            end
            for _, m in ipairs(c.masters or {}) do
                view[#view + 1] = { kind = "line", text = Hex(T.accent) .. "Weapon master:|r " .. m[1], right = c.masterPlace }
                for _, w in ipairs(m[2]) do
                    view[#view + 1] = { kind = "weapon", w = w, gold = not w.known, right = w.known and TICK or CROSS }
                end
            end
        end
        if #trainers == 0 then Note("No city list for this class and faction yet. Trainers you open are remembered below.") end
        -- weapon skills no weapon master of your faction teaches
        local rest = {}
        for _, w in ipairs(data.weapons) do if not taught[w.id] then rest[#rest + 1] = w end end
        if #rest > 0 then
            view[#view + 1] = { kind = "head", text = "Not from a weapon master" }
            for _, w in ipairs(rest) do
                view[#view + 1] = { kind = "weapon", w = w, gold = not w.known, right = w.known and TICK or CROSS }
                if WEAPON_EXTRA[w.id] then Note(WEAPON_EXTRA[w.id]) end
            end
            if WEAPON_NOTES[CLASS] then Note(WEAPON_NOTES[CLASS]) end
        end
        if #data.weapons > 0 and data.weaponsKnown == 0 then
            Note("The game did not report any weapon skill as known, so Known / Not learned can't be trusted here yet.")
        end
        local extra = {}
        for name in pairs(seen) do if not listed[name] then extra[#extra + 1] = name end end
        table.sort(extra)
        if #extra > 0 then
            view[#view + 1] = { kind = "head", text = "Also visited" }
            for _, name in ipairs(extra) do
                view[#view + 1] = { kind = "line", text = name, indent = true, right = seen[name] }
            end
        end
    end
end

local function Summary()
    local tab = db.tab
    local money = GetMoney and GetMoney() or 0
    if tab == "train" then
        if data.ready == 0 then
            return "Nothing to train at level " .. MyLevel() .. ".", data.haveTrainer and "" or "Prices and levels come from your class trainer."
        end
        local cost = Coins(data.readyCost)
        if data.readyUnpriced > 0 then
            cost = data.readyCost > 0 and (cost .. " + " .. data.readyUnpriced .. " not priced yet") or "price not known yet"
        end
        local short = data.readyCost > money
        return "Train now:  " .. Hex(T.text) .. cost .. "|r",
            "You have:  " .. (short and Hex(T.danger) or Hex(T.text)) .. Coins(money) .. "|r"
    elseif tab == "max" then
        if data.ranked == 0 then return "Your spells against the best rank for level " .. MyLevel() .. ".", "" end
        return (data.ranked - data.behind) .. " of " .. data.ranked .. " spells are at their best rank.",
            data.behind > 0 and "The ones at the top have a rank waiting at your trainer." or "Nothing to catch up on."
    end
    local left = 0
    for _, w in ipairs(data.weapons) do if not w.known then left = left + 1 end end
    local second = (data.weaponsKnown == 0) and "Class trainers, then what each weapon master teaches."
        or (left == 0 and "Every weapon skill your class can use is learned." or
            (left == 1 and "1 weapon skill to learn." or (left .. " weapon skills to learn.")))
    return "Where your class trains, city by city.", second
end

local function PaintRows()
    local maxOff = math.max(0, #view - ROWS)
    if offset > maxOff then offset = maxOff end
    if offset < 0 then offset = 0 end
    for i = 1, ROWS do
        local row, v = rows[i], view[i + offset]
        row.v = v
        if not v then
            row:Hide()
        else
            row:Show()
            local head, note = v.kind == "head", v.kind == "note" or v.kind == "line"
            row.rule:SetShown(head)
            row.mark:SetShown(v.mark and true or false)
            row.icon:SetShown(not head and not note)
            row.lv:SetShown(not head and not note)
            row.name:ClearAllPoints()
            if head then
                row.name:SetPoint("LEFT", 6, 0)
                row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
                row.name:SetText(v.text)
                row.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                row.right:SetText(v.right or "")
                row.right:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
            elseif note then
                row.name:SetPoint("LEFT", v.indent and 16 or 6, 0)
                row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
                row.name:SetText(v.text)
                row.name:SetTextColor(T.desc[1], T.desc[2], T.desc[3])
                row.right:SetText(v.right or "")
                row.right:SetTextColor(GREY[1], GREY[2], GREY[3])
            else
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
                local c = v.dim and GREY or (v.gold and T.accent or T.text)
                local e, label = v.e, nil
                if v.kind == "weapon" then
                    label = v.w.name
                    row.icon:SetTexture(v.w.icon or QUESTION)
                    row.lv:SetText("")
                else
                    label = e.name
                    if db.tab == "train" and e.rank then
                        label = label .. "  " .. Hex(GREY) .. "Rank " .. e.rank .. "|r"
                    elseif v.sub then
                        label = label .. "  " .. Hex(GREY) .. v.sub .. "|r"
                    end
                    row.icon:SetTexture(e.icon or QUESTION)
                    row.lv:SetText(v.lv or "")
                end
                row.icon:SetDesaturated(v.dim and true or false)
                row.icon:SetAlpha(v.dim and 0.6 or 1)
                row.name:SetText(label)
                row.name:SetTextColor(c[1], c[2], c[3])
                local lc = v.mark and T.accent or (v.dim and GREY or T.text)
                row.lv:SetTextColor(lc[1], lc[2], lc[3])
                row.right:SetText(v.right or "")
                row.right:SetTextColor(c[1], c[2], c[3])
            end
        end
    end
    -- the thin thumb at the right edge
    if #view > ROWS then
        local track = ROWS * ROW_H
        local size = math.max(24, track * ROWS / #view)
        win.thumb:SetHeight(size)
        win.thumb:ClearAllPoints()
        win.thumb:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, LIST_TOP - (track - size) * (offset / maxOff))
        win.thumb:Show()
    else
        win.thumb:Hide()
    end
end

local function RowTip(self)
    local v = self.v
    if not v then return end
    if v.kind == "spell" then
        local f = data.fam[v.e.name]
        if not f then return end
        local level = MyLevel()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(v.e.name, T.accent[1], T.accent[2], T.accent[3])
        for _, e in ipairs(f) do
            local left = (e.rank and ("Rank " .. e.rank) or "Spell")
                .. ((e.level or 0) > 0 and ("   level " .. e.level) or "")
                .. (e.id and ("   " .. Hex(GREY) .. "ID " .. e.id .. "|r") or "")
            local right, r, g, b
            if e.known then
                right, r, g, b = "Known", T.green[1], T.green[2], T.green[3]
            else
                right = (e.cost and e.cost > 0) and Coins(e.cost) or "-"
                if (e.level or 0) <= level then r, g, b = 1, 1, 1 else r, g, b = GREY[1], GREY[2], GREY[3] end
            end
            GameTooltip:AddDoubleLine(left, right, r, g, b, r, g, b)
        end
        GameTooltip:Show()
    elseif v.kind == "weapon" then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(v.w.name, T.accent[1], T.accent[2], T.accent[3])
        if v.w.known then
            GameTooltip:AddLine("You can use these.", 1, 1, 1)
        elseif v.w.from then
            GameTooltip:AddLine("Taught by:", 1, 1, 1)
            for _, who in ipairs(v.w.from) do GameTooltip:AddLine("  " .. who, 1, 1, 1) end
        else
            GameTooltip:AddLine("Not taught by a weapon master.", 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

local TABS = { { "train", "To Train" }, { "max", "Max Ranks" }, { "where", "Trainers" } }

function Refresh()
    if not win then return end
    Rebuild()
    BuildView()
    for _, b in ipairs(win.tabs) do b:SetPrimary(b.key == db.tab) end
    local a, b = Summary()
    win.sum1:SetText(a or "")
    win.sum2:SetText(b or "")
    local rec = db.trainer[CLASS]
    if live then
        win.foot:SetText("Reading your trainer now.")
    elseif rec and rec.level then
        win.foot:SetText("Trainer list last read at level " .. rec.level .. ".")
    else
        win.foot:SetText("Open your class trainer once to fill in levels and prices.")
    end
    PaintRows()
end

local function BuildWindow()
    if win then return end
    win = CreateFrame("Frame", "CysRanksFrame", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:EnableMouseWheel(true)
    win:Hide()
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
    title:SetText("SPELL RANKS")

    local close = W.Button(win, 18, 18, "x")
    close:SetPoint("TOPRIGHT", -6, -5)
    close:SetScript("OnClick", function() db.open = false; Sync() end)

    win.tabs = {}
    local tw = math.floor((WIDTH - 24 - 4 * (#TABS - 1)) / #TABS)
    for i, t in ipairs(TABS) do
        local b = W.Button(win, tw, 22, t[2])
        b.key = t[1]
        b:SetPoint("TOPLEFT", 12 + (i - 1) * (tw + 4), -36)
        b:SetScript("OnClick", function() db.tab = t[1]; offset = 0; Refresh() end)
        win.tabs[i] = b
    end

    win.sum1 = W.Text(win, 12, T.accent)
    win.sum1:SetPoint("TOPLEFT", 14, -66)
    win.sum1:SetPoint("RIGHT", -14, 0)
    win.sum1:SetWordWrap(false)
    win.sum2 = W.Text(win, 11, T.desc)
    win.sum2:SetPoint("TOPLEFT", 14, -84)
    win.sum2:SetPoint("RIGHT", -14, 0)
    win.sum2:SetWordWrap(false)

    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 8, LIST_TOP - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -12, LIST_TOP - (i - 1) * ROW_H)
        row.hl = W.Texture(row, "BACKGROUND", T.selected)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.mark = W.Texture(row, "ARTWORK", T.brand)
        row.mark:SetPoint("TOPLEFT", 0, -3)
        row.mark:SetPoint("BOTTOMLEFT", 0, 3)
        row.mark:SetWidth(2)
        row.rule = W.Texture(row, "ARTWORK", T.line)
        row.rule:SetPoint("BOTTOMLEFT", 4, 1)
        row.rule:SetPoint("BOTTOMRIGHT", -4, 1)
        row.rule:SetHeight(1)
        row.lv = W.Text(row, 11, T.text, "RIGHT")
        row.lv:SetPoint("LEFT", 4, 0)
        row.lv:SetWidth(22)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 32, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.right = W.Text(row, 11, T.text, "RIGHT")
        row.right:SetPoint("RIGHT", -6, 0)
        row.name = W.Text(row, 12, T.text)
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if self.v and (self.v.kind == "spell" or self.v.kind == "weapon") then self.hl:Show() end
            RowTip(self)
        end)
        row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        rows[i] = row
    end

    win.thumb = W.Texture(win, "OVERLAY", T.brand)
    win.thumb:SetWidth(3)
    win.thumb:Hide()

    win.foot = W.Text(win, 10, T.dim)
    win.foot:SetPoint("BOTTOMLEFT", 14, 10)
    win.foot:SetPoint("RIGHT", -14, 0)
    win.foot:SetWordWrap(false)

    win:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        PaintRows()
    end)
    win:SetScript("OnShow", function() winUp = true end)
    win:SetScript("OnHide", function() winUp = false end)
end

local function BuildOpener()
    if opener then return end
    opener = W.Button(UIParent, 96, 22, "Spell ranks")
    opener:SetFrameStrata("HIGH")
    opener:Hide()
    opener:SetScript("OnClick", function() db.open = true; Sync() end)
end

-- Our frames sit just right of the spellbook's top-right corner and follow it; Blizzard's frame is only
-- ever used as an anchor.
function Sync()
    local host = _G.PlayerSpellsFrame
    if not (bookUp and host) then
        if win then win:Hide() end
        if opener then opener:Hide() end
        return
    end
    if db.open then
        BuildWindow()
        if opener then opener:Hide() end
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0)
        win:Show()
        local ok, err = pcall(Refresh)
        if not ok and CUI.debug then CUI:Print("Spell Ranks: " .. tostring(err)) end
    else
        BuildOpener()
        if win then win:Hide() end
        opener:ClearAllPoints()
        opener:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, -2)
        opener:Show()
    end
end

local hooked
local function Attach()
    if hooked then return end
    local host = _G.PlayerSpellsFrame
    local book = host and host.SpellBookFrame
    if not (book and book.HookScript) then return end
    hooked = true
    book:HookScript("OnShow", function() bookUp = true; Sync() end)
    book:HookScript("OnHide", function() bookUp = false; Sync() end)
    local ok, vis = pcall(function() return book:IsVisible() and true or false end)
    bookUp = ok and vis or false
    Sync()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local pending, readQueued
local function Dirty()
    if pending or not winUp then return end
    pending = true
    C_Timer.After(0.15, function()
        pending = false
        if winUp then pcall(Refresh) end
    end)
end
local function QueueRead()
    if readQueued then return end
    readQueued = true
    C_Timer.After(0.3, function()
        readQueued = false
        local ok, got = pcall(ReadTrainer)
        if ok and got then Dirty() end
    end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "SPELLS_CHANGED",
                     "PLAYER_LEVEL_UP", "PLAYER_MONEY", "SPELL_TEXT_UPDATE", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "Blizzard_PlayerSpells" then Attach() end
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        QueueRead()
    elseif event == "TRAINER_CLOSED" then
        live = nil
        Dirty()
    else
        if event == "PLAYER_LEVEL_UP" and tonumber(a1) then levelSeen = tonumber(a1) end
        Dirty()
    end
end)
Attach() -- in case the spellbook was loaded before us

--------------------------------------------------------------------------------
-- /cuiranks
--------------------------------------------------------------------------------
SLASH_CYSRANKS1 = "/cuiranks"
SlashCmdList["CYSRANKS"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "check" then
        local ok, err = pcall(Rebuild)
        if not ok then CUI:Print("Spell Ranks check failed: " .. tostring(err)) return end
        local known, items = ReadBook()
        local nKnown, nFuture, nRanked, nLevel = 0, 0, 0, 0
        for _, it in ipairs(items) do
            if it.known then nKnown = nKnown + 1 else nFuture = nFuture + 1 end
            if it.rank then nRanked = nRanked + 1 end
            if (it.level or 0) > 0 then nLevel = nLevel + 1 end
        end
        local nRows, nPriced, nIDs = 0, 0, 0
        local rec = db.trainer[CLASS]
        for _, row in pairs(rec and rec.rows or {}) do
            nRows = nRows + 1
            if row.c then nPriced = nPriced + 1 end
            if row.id then nIDs = nIDs + 1 end
        end
        CUI:Print(string.format("Spell Ranks check (%s, level %d). Spellbook: %d known, %d still to come, %d with a rank, %d with a level.",
            CLASS, MyLevel(), nKnown, nFuture, nRanked, nLevel))
        CUI:Print(string.format("Trainer list: %d spells, %d priced, %d with a spell ID. To train now: %d. Behind on rank: %d of %d. Weapon skills known: %d of %d. Spellbook hook: %s.",
            nRows, nPriced, nIDs, data.ready, data.behind, data.ranked, data.weaponsKnown, #data.weapons, hooked and "yes" or "no"))
        return
    end
    db.open = not db.open
    Sync()
    CUI:Print("Spell Ranks " .. (db.open and "on: it opens beside the spellbook." or "off. The Spell ranks button beside the spellbook brings it back."))
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Spell Ranks", function(page)
    local width = 480
    W.Header(page, "Spell ranks", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("A window beside the spellbook: what you can train now and what it costs, what comes at later levels, which spells are behind their best rank, and your weapon skills.")

    local c = W.Checkbox(page, "Show the Spell Ranks window beside the spellbook",
        function() return db.open end, function(on) db.open = on; Sync() end)
    c:SetPoint("TOPLEFT", 4, -92)

    W.Notes(page, 4, -130, width, "", {
        "Levels and prices are read from your class trainer. Open it once and the whole list fills in; it is read again on every visit.",
        "Point at a spell for every rank, the level it comes at and its price.",
        "The Trainers tab lists the cities that train your class, where in the city, and who. Weapon masters are at the bottom of the Weapons tab.",
        { "/cuiranks", "open or close the window; /cuiranks check prints what was read" },
    })
end)

    end,
})
