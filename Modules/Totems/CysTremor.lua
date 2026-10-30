--------------------------------------------------------------------------------
-- Cys's UI - Tremor Alert (Shaman)
--
-- Shows a Tremor Totem icon with "Mob - ability" lines when a mob that can fear, charm or sleep your
-- group is in the pack (nameplates, target, mouseover, party targets, and mobs fighting your group).
-- The dungeon list is in TremorData.lua. Mobs that are not on it are learned: when a hostile NPC puts a
-- fear / charm / sleep debuff on you or a party member, the mob and spell are saved and shown next time.
-- Only NPCs count (player GUIDs, pets, mind-controlled mobs are ignored) and nothing runs in battlegrounds
-- or arenas, so it stays out of the way when you PvP.
--
--   /cuitremor test | list | clear
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T
local D = CUI.Tremor or { ByNPC = {} }

local DEFAULTS = { learn = true, needSpell = true, unverified = true, learned = {} }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.tremor = CysUIDB.tremor or {}
    local db = CysUIDB.tremor
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then db[k] = {} else db[k] = v end
        end
    end
    return db
end

local COLORS = { fear = "ffb266ff", sleep = "ff80ccff", charm = "ffff80cc" }
local TYPE_LABEL = { fear = "fear", sleep = "sleep", charm = "charm" }
local FALLBACK_ICON = "Interface\\Icons\\Spell_Nature_TremorTotem"
local MAX_LINES = 3   -- mobs shown; one line per mob name, the rest become "+N more"

local function InBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

-- every ability known for a mob name: the shipped list plus what this install has learned
local function Threats(name)
    local db = DB()
    local out = {}
    local have = {}
    for _, e in ipairs(D.ByNPC[name] or {}) do
        if e.verified or db.unverified then
            out[#out + 1] = e
            have[e.spell] = true
        end
    end
    for _, e in ipairs(db.learned[name] or {}) do
        if not have[e.spell] then out[#out + 1] = e end
    end
    return out
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------
local scanTip
local typeCache = {}
local PATTERNS = {
    { "fear",  { "fear", "flee", "terror", "horrif", "scare" } },
    { "charm", { "charm", "mind control", "control of", "possess", "dominat" } },
    { "sleep", { "sleep", "slumber", "asleep" } },
}

-- Reads the spell's own tooltip to decide fear / charm / sleep. Returns nil for anything else.
local function Classify(spellId)
    if not spellId then return nil end
    if typeCache[spellId] ~= nil then return typeCache[spellId] or nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "CysTremorScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(scanTip.SetSpellByID, scanTip, spellId)
    local found = false
    if ok then
        local text = ""
        for i = 2, scanTip:NumLines() do
            local line = _G["CysTremorScanTipTextLeft" .. i]
            if line and line:GetText() then text = text .. " " .. line:GetText():lower() end
        end
        for _, p in ipairs(PATTERNS) do
            for _, word in ipairs(p[2]) do
                if text:find(word, 1, true) then found = p[1] break end
            end
            if found then break end
        end
    end
    typeCache[spellId] = found or false
    return found or nil
end

local function Learn(npcName, spellName, kind)
    local db = DB()
    for _, e in ipairs(D.ByNPC[npcName] or {}) do
        if e.spell == spellName then return end
    end
    local list = db.learned[npcName]
    if not list then list = {}; db.learned[npcName] = list end
    for _, e in ipairs(list) do
        if e.spell == spellName then return end
    end
    list[#list + 1] = { spell = spellName, type = kind, verified = true, learned = true, dungeon = GetRealZoneText and GetRealZoneText() or nil }
    CUI:Print("Tremor Alert learned: " .. npcName .. " - " .. spellName .. " (" .. TYPE_LABEL[kind] .. "). It will show next time.")
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------
local f, icon, rows, header
local testUntil = 0
local testLines
local active = {}  -- guid -> name (mobs in the pack that matter)
local seen = {}    -- guid -> { name, t } from the combat log

local function TremorIcon()
    local tex = select(3, GetSpellInfo("Tremor Totem"))
    return tex or FALLBACK_ICON
end

local function TremorUp()
    for slot = 1, 4 do
        local have, name = GetTotemInfo(slot)
        if have and name and name:find("Tremor") then return true end
    end
    return false
end

local function Build()
    if f then return end
    f = CreateFrame("Frame", "CysTremorFrame", UIParent)
    f:SetSize(340, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("HIGH")
    f:Hide()
    CUI:RegisterMovable(f, "tremor", "Tremor Alert", { point = "CENTER", x = 0, y = 120 })

    -- left-click and drag to move (same saved position as /cui layout)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        local m = CUI.movers and CUI.movers.tremor
        if m and m.mover then m.mover:StartMoving() end
    end)
    f:SetScript("OnDragStop", function()
        local m = CUI.movers and CUI.movers.tremor
        if not (m and m.mover) then return end
        m.mover:StopMovingOrSizing()
        local cx, cy = m.mover:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (cx and ux) then return end
        CysUIDB.layout = CysUIDB.layout or {}
        local e = CysUIDB.layout.tremor or {}
        CysUIDB.layout.tremor = e
        e.point, e.x, e.y = "CENTER", math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
        CUI:ApplyLayout("tremor")
    end)

    W.Texture(f, "BACKGROUND", T.field):SetAllPoints()
    W.Border(f, 2, T.border, "BORDER")

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(32, 32)
    box:SetPoint("TOPLEFT", 4, -4)
    icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(TremorIcon())

    header = W.Text(f, 12, T.accent)
    header:SetPoint("TOPLEFT", 44, -6)
    header:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    header:SetJustifyH("LEFT")

    rows = {}
    for i = 1, MAX_LINES + 1 do
        local r = W.Text(f, 12, T.text)
        r:SetPoint("TOPLEFT", 44, -6 - 15 * i)
        r:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        r:SetJustifyH("LEFT")
        r:SetWordWrap(false)
        rows[i] = r
    end
end

local function Render(lines)
    Build()
    if #lines == 0 then f:Hide() return end
    icon:SetTexture(TremorIcon())
    if TremorUp() then
        header:SetText("|cff66ff66Tremor Totem is down|r")
    else
        header:SetText("Drop Tremor Totem")
    end
    for i = 1, MAX_LINES + 1 do
        rows[i]:SetText(lines[i] or "")
    end
    local n = math.min(#lines, MAX_LINES + 1)
    f:SetHeight(math.max(44, 10 + 15 * (n + 1)))
    f:Show()
end

-- one line per mob name: "Name x2 - Ability / Other ability" (the same mob twice is still one line)
local function Line(name, count, list)
    local parts = {}
    for _, e in ipairs(list) do
        local c = COLORS[e.type] or "ffffffff"
        parts[#parts + 1] = string.format("|c%s%s|r%s", c, e.spell, e.verified == false and "?" or "")
    end
    local mult = count > 1 and (" x" .. count) or ""
    return name .. mult .. " - " .. table.concat(parts, " / ")
end

local function RandomPick(t, n)
    local copy, out = {}, {}
    for _, v in ipairs(t) do copy[#copy + 1] = v end
    for _ = 1, math.min(n, #copy) do
        out[#out + 1] = table.remove(copy, math.random(#copy))
    end
    return out
end

-- a test alert: either one boss, or a small pack of two mobs, picked from the real list
local function MakeTestLines()
    local bosses, trash = {}, {}
    for npc, list in pairs(D.ByNPC) do
        local entry = { name = npc, list = list }
        if list[1].boss then bosses[#bosses + 1] = entry else trash[#trash + 1] = entry end
    end
    local picks
    if math.random(2) == 1 or #trash == 0 then
        picks = RandomPick(bosses, 1)
    else
        local all = {}
        for _, v in ipairs(bosses) do all[#all + 1] = v end
        for _, v in ipairs(trash) do all[#all + 1] = v end
        picks = RandomPick(trash, 1)
        for _, v in ipairs(RandomPick(all, 3)) do
            if #picks < 2 and v ~= picks[1] then picks[#picks + 1] = v end
        end
    end
    local lines = {}
    for _, p in ipairs(picks) do
        lines[#lines + 1] = Line(p.name, 1, p.list)
    end
    return lines
end

local function Refresh()
    if testUntil > GetTime() then
        testLines = testLines or MakeTestLines()
        Render(testLines)
        return
    end
    testLines = nil
    if InBattleground() then Render({}) return end
    local db = DB()
    if db.needSpell and not GetSpellInfo("Tremor Totem") then Render({}) return end

    -- group the pack by mob name
    local counts, order = {}, {}
    for _, name in pairs(active) do
        if not counts[name] then counts[name] = 0; order[#order + 1] = name end
        counts[name] = counts[name] + 1
    end
    table.sort(order)
    local lines = {}
    for _, name in ipairs(order) do
        local list = Threats(name)
        if #list > 0 then lines[#lines + 1] = Line(name, counts[name], list) end
    end
    if #lines > MAX_LINES then
        local extra = #lines - MAX_LINES
        for i = #lines, MAX_LINES + 1, -1 do lines[i] = nil end
        lines[MAX_LINES + 1] = "+" .. extra .. " more mob" .. (extra > 1 and "s" or "")
    end
    Render(lines)
end

--------------------------------------------------------------------------------
-- Finding the pack
--------------------------------------------------------------------------------
local function Check(unit, found)
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
    if UnitPlayerControlled and UnitPlayerControlled(unit) then return end -- pets, mind-controlled mobs
    if not UnitCanAttack("player", unit) then return end
    local guid = UnitGUID(unit)
    if not guid or not guid:find("^Creature") then return end
    local name = UnitName(unit)
    if name and (D.ByNPC[name] or DB().learned[name]) then found[guid] = name end
end

local UNITS = { "target", "mouseover", "focus", "party1target", "party2target", "party3target", "party4target" }

local function Scan()
    local found = {}
    for _, u in ipairs(UNITS) do Check(u, found) end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then Check(u, found) end
    end
    -- mobs fighting the group that we have no unit for (seen in the combat log in the last 20 seconds)
    local now = GetTime()
    for guid, s in pairs(seen) do
        if now - s.t > 20 then
            seen[guid] = nil
        elseif not found[guid] then
            found[guid] = s.name
        end
    end
    active = found
    Refresh()
end

local function OnCombatLog()
    local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, dFlags, _, spellId, spellName, _, auraType = CombatLogGetCurrentEventInfo()
    if InBattleground() then return end
    if sub == "UNIT_DIED" then
        seen[dGUID] = nil
        active[dGUID] = nil
        return
    end
    local db = DB()
    -- a hostile NPC fighting someone in our group: remember it for a few seconds
    if sGUID and sGUID:find("^Creature") and sName and (D.ByNPC[sName] or db.learned[sName]) then
        if bit.band(dFlags or 0, 0x7) ~= 0 then seen[sGUID] = { name = sName, t = GetTime() } end
    end
    -- learning: NPC puts a fear / charm / sleep debuff on a group member
    if db.learn and sub == "SPELL_AURA_APPLIED" and auraType == "DEBUFF"
        and sGUID and sGUID:find("^Creature") and dGUID and dGUID:find("^Player")
        and bit.band(sFlags or 0, 0x40) ~= 0      -- hostile
        and bit.band(sFlags or 0, 0x100) == 0     -- not player-controlled
        and bit.band(dFlags or 0, 0x7) ~= 0 then  -- me, party or raid
        local kind = Classify(spellId)
        if kind and sName and spellName then Learn(sName, spellName, kind) end
    end
end

local function Enable()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return end
    Build()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog()
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(seen); wipe(active)
        else
            Refresh()
        end
    end)
    C_Timer.NewTicker(0.5, Scan)
end

CUI:RegisterModule({
    key = "tremor",
    name = "Tremor Alert",
    addon = "CysUI",
    class = "SHAMAN",
    desc = "Shaman only: shows a Tremor Totem icon with the mob and its ability when a mob that fears, charms or sleeps is in the pack. Dungeon list included; new mobs are learned (NPCs only, never in PvP).",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Tremor Alert") end,
})

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
SLASH_CYSTREMOR1 = "/cuitremor"
SlashCmdList["CYSTREMOR"] = function(msg)
    msg = strtrim((msg or ""):lower())
    local db = DB()
    if msg == "list" then
        local n = 0
        for name, list in pairs(db.learned) do
            for _, e in ipairs(list) do
                n = n + 1
                CUI:Print("Learned: " .. name .. " - " .. e.spell .. " (" .. e.type .. ")" .. (e.dungeon and (", " .. e.dungeon) or ""))
            end
        end
        if n == 0 then CUI:Print("Tremor Alert has not learned any mobs yet.") end
    elseif msg == "clear" then
        wipe(db.learned)
        CUI:Print("Tremor Alert forgot every learned mob.")
    else
        testUntil = GetTime() + 8
        testLines = nil
        Refresh()
        CUI:Print("Showing a test alert for 8 seconds. /cuitremor list shows learned mobs, /cuitremor clear forgets them.")
    end
end

--------------------------------------------------------------------------------
-- Settings page (listed under Class > Shaman for every class, so the Class section shows what each class has)
--------------------------------------------------------------------------------
local _, myClass = UnitClass("player")
CUI:RegisterPage("Tremor Alert", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Tremor alert", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText((myClass ~= "SHAMAN" and "Shaman only: this does nothing on your class. " or "") .. "When a mob that can fear, charm or sleep your group is in the pack, a Tremor Totem icon shows the mob and its ability so you can drop Tremor before the pull. Move it with /cui layout.")

    local y = -92
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Only show once I know Tremor Totem", "needSpell")
    Check("Learn new mobs that fear, charm or sleep my group", "learn")
    Check("Show entries that still need checking in game (marked ?)", "unverified")

    y = y - 8
    local test = W.Button(page, 150, 22, "Show a test alert", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", function() SlashCmdList["CYSTREMOR"]("test") end)
    local forget = W.Button(page, 190, 22, "Forget learned mobs")
    forget:SetPoint("LEFT", test, "RIGHT", 10, 0)
    forget:SetScript("OnClick", function() SlashCmdList["CYSTREMOR"]("clear") end)
    y = y - 40

    W.Notes(page, 4, y, width, "", {
        { "Dungeon list", "Wailing Caverns through Scholomance: bosses with fear, charm or sleep, plus a few trash packs. Trash is incomplete, so the rest is learned as you play." },
        { "Learning", "Only hostile NPCs are learned (never players, pets or mind-controlled mobs), and nothing runs in battlegrounds or arenas. /cuitremor list shows what was learned." },
        { "?", "Marks an ability that was reported but not confirmed; tell me if Tremor does not break it." },
    })
end, nil, "SHAMAN")
