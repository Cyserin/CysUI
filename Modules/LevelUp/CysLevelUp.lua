--------------------------------------------------------------------------------
-- Cys's UI - Level-Up Spells
--
-- When you level up (or open your trainer) a small box lists the spells worth buying right now, with the
-- reason for each. It reads your spellbook, so spells you already have are left out, and anything you
-- skipped on an earlier visit stays on the list. The guides are in GuideShaman.lua (one file per class).
--
--   /cuilevel        show the box now          /cuilevel 30   preview what you would buy at level 30
--   /cuiscan         at a class trainer: save the trainer's spells (levels, costs) to SavedVariables and
--                    check the guide's levels against the real ones
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = { onLevel = true, onTrainer = true, guide = {} }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.levelup = CysUIDB.levelup or {}
    local db = CysUIDB.levelup
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then db[k] = {} else db[k] = v end
        end
    end
    return db
end

--------------------------------------------------------------------------------
-- Guides
--------------------------------------------------------------------------------
local function ClassGuides()
    local _, cls = UnitClass("player")
    return (CUI.LevelGuides and CUI.LevelGuides[cls]) or {}, cls
end

local function CurrentGuide()
    local list, cls = ClassGuides()
    if #list == 0 then return nil, cls end
    local want = DB().guide[cls]
    for _, g in ipairs(list) do
        if g.key == want then return g, cls end
    end
    return list[1], cls
end

-- name -> highest rank you have (rankless spells count as 1)
local function KnownSpells()
    local known = {}
    local getName = GetSpellBookItemName
    local bank = "spell"
    if not getName and C_SpellBook and C_SpellBook.GetSpellBookItemName then
        getName = C_SpellBook.GetSpellBookItemName
        bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
    end
    if not getName then return known end
    for i = 1, 1500 do
        local ok, name, sub = pcall(getName, i, bank)
        if not ok or not name then break end
        local rank = tonumber((sub or ""):match("(%d+)")) or 1
        if (known[name] or 0) < rank then known[name] = rank end
    end
    return known
end

local function EffLevel(e) return e.buyAt or e.level end

-- buy = worth buying at `level` and not yet learned; later = still ahead of you
local function Evaluate(guide, level)
    local known = KnownSpells()
    local buy, later = {}, {}
    for _, e in ipairs(guide.spells) do
        local have = known[e.spell] and (not e.rank or known[e.spell] >= e.rank)
        if not have then
            if EffLevel(e) <= level then buy[#buy + 1] = e else later[#later + 1] = e end
        end
    end
    table.sort(buy, function(a, b)
        local la, lb = EffLevel(a), EffLevel(b)
        if la ~= lb then return la > lb end -- this level's spells first, older misses after
        return (a.spell .. (a.rank or 0)) < (b.spell .. (b.rank or 0))
    end)
    return buy, later
end

local function Label(e)
    return e.rank and (e.spell .. "  |cFFB0B0B0Rank " .. e.rank .. "|r") or e.spell
end

--------------------------------------------------------------------------------
-- The box
--------------------------------------------------------------------------------
local box
local MAXROWS = 10
local ROW_W = 320
local shownLevel, shownBy

local function Build()
    if box then return box end
    box = CreateFrame("Frame", "CysLevelUpBox", UIParent)
    box:SetSize(ROW_W + 20, 160)
    box:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    W.Texture(box, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(box, 1, T.border, "BORDER")

    box.title = W.Text(box, 13, T.accent)
    box.title:SetPoint("TOPLEFT", 10, -9)
    box.sub = W.Text(box, 10, T.desc)
    box.sub:SetPoint("TOPLEFT", 10, -27)

    local close = W.Button(box, 18, 18, "x")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() box:Hide() end)

    box.rows = {}
    for i = 1, MAXROWS do
        local r = {}
        r.name = W.Text(box, 12, T.accent)
        r.name:SetWidth(ROW_W)
        r.note = W.Text(box, 10, T.desc)
        r.note:SetWidth(ROW_W - 8)
        r.note:SetJustifyV("TOP")
        box.rows[i] = r
    end
    box.skip = W.Text(box, 10, { 0.69, 0.69, 0.69 })
    box.skip:SetWidth(ROW_W)
    box.skip:SetJustifyV("TOP")
    box.skip:SetSpacing(2)
    box.foot = W.Text(box, 10, T.desc)
    box.foot:SetWidth(ROW_W)
    box.foot:SetJustifyV("TOP")

    CUI:RegisterMovable(box, "levelup", "Level-up spells", { point = "RIGHT", x = -60, y = 60 })
    box:Hide()
    return box
end

local function Render(level)
    local guide = CurrentGuide()
    if not guide then return false end
    local buy, later = Evaluate(guide, level)
    Build()
    shownLevel = level

    box.title:SetText("Level " .. level .. ": spells worth buying")
    box.sub:SetText(guide.name .. " guide (" .. guide.role .. ")")

    local y = -46
    local shown = math.min(#buy, MAXROWS)
    for i = 1, MAXROWS do
        local r, e = box.rows[i], buy[i]
        if i <= shown then
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)
            local tag = ""
            if e.optional then tag = "  |cFF8FC8FF(optional)|r" end
            if EffLevel(e) < level then tag = tag .. "  |cFFFF9040(from level " .. EffLevel(e) .. ")|r" end
            r.name:SetText(Label(e) .. tag)
            r.name:Show()
            y = y - 16
            if e.note then
                r.note:ClearAllPoints()
                r.note:SetPoint("TOPLEFT", box, "TOPLEFT", 18, y)
                r.note:SetText(e.note)
                r.note:Show()
                y = y - (r.note:GetStringHeight() or 12) - 3
            else
                r.note:SetText("")
                r.note:Hide()
            end
            y = y - 4
        else
            r.name:Hide()
            r.note:Hide()
        end
    end

    -- spells the guide says not to spend gold on at this stage (this level and the one before it)
    local skipLines = {}
    for _, sk in ipairs(guide.skips or {}) do
        if sk.level <= level and sk.level >= level - 1 then
            skipLines[#skipLines + 1] = "Skip " .. sk.spell .. (sk.rank and (" R" .. sk.rank) or "") .. ": " .. sk.why
        end
    end
    box.skip:ClearAllPoints()
    if #skipLines > 0 then
        box.skip:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y - 2)
        box.skip:SetText(table.concat(skipLines, "\n"))
        box.skip:Show()
        y = y - (box.skip:GetStringHeight() or 12) - 8
    else
        box.skip:Hide()
    end

    local foot
    if #buy > MAXROWS then
        foot = "+" .. (#buy - MAXROWS) .. " more: see /cui -> Level-Up Spells"
    elseif #buy == 0 then
        foot = "Nothing to buy right now."
    end
    local nextLevel
    for _, e in ipairs(later) do
        local l = EffLevel(e)
        if not nextLevel or l < nextLevel then nextLevel = l end
    end
    if nextLevel then
        local n = 0
        for _, e in ipairs(later) do if EffLevel(e) == nextLevel then n = n + 1 end end
        local line = "Next: " .. n .. " spell" .. (n == 1 and "" or "s") .. " at level " .. nextLevel
        foot = foot and (foot .. "\n" .. line) or line
    end
    box.foot:ClearAllPoints()
    if foot then
        box.foot:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y - 2)
        box.foot:SetText(foot)
        box.foot:Show()
        y = y - (box.foot:GetStringHeight() or 12) - 6
    else
        box.foot:Hide()
    end
    box:SetHeight(math.max(70, -y + 10))
    return #buy
end

-- who: "level" (leveled up), "trainer" (opened a trainer), "manual"
local function Show(level, who)
    level = level or UnitLevel("player")
    local guide, cls = CurrentGuide()
    if not guide then
        if who == "manual" then
            local name = UnitClass("player")
            CUI:Print("No level-up guide for " .. tostring(name) .. " yet. Guides so far are listed under /cui -> Level-Up Spells.")
        end
        return
    end
    local n = Render(level)
    if n == 0 and who ~= "manual" then
        if box then box:Hide() end
        return
    end
    shownBy = who
    box:Show()
end

--------------------------------------------------------------------------------
-- Trainer scan: saves the trainer's list and checks the guide's levels
--------------------------------------------------------------------------------
local function Scan()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) or (GetNumTrainerServices() or 0) == 0 then
        CUI:Print("Open your class trainer first, then type /cuiscan.")
        return
    end
    -- make sure the trainer's own filters hide nothing
    local keep = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, k in ipairs({ "available", "unavailable", "used" }) do
            keep[k] = GetTrainerServiceTypeFilter(k)
            pcall(SetTrainerServiceTypeFilter, k, 1)
        end
    end
    local rows = {}
    for i = 1, GetNumTrainerServices() do
        local name, rank, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
            local cost = GetTrainerServiceCost and select(1, GetTrainerServiceCost(i)) or 0
            rows[#rows + 1] = {
                name = name,
                rank = tonumber((rank or ""):match("(%d+)")),
                req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = cost,
                state = category,
            }
        end
    end
    for k, v in pairs(keep) do pcall(SetTrainerServiceTypeFilter, k, v and 1 or 0) end

    local _, cls = UnitClass("player")
    CysUIDB.trainerScan = CysUIDB.trainerScan or {}
    CysUIDB.trainerScan[cls] = {
        date = date("%Y-%m-%d"),
        build = select(4, GetBuildInfo()),
        level = UnitLevel("player"),
        rows = rows,
    }
    CUI:Print("Saved " .. #rows .. " trainer spells for " .. cls .. " (CysUIDB.trainerScan).")

    -- compare with the guide
    local guide = CurrentGuide()
    if guide then
        local byKey = {}
        for _, r in ipairs(rows) do byKey[r.name .. ":" .. (r.rank or 0)] = r end
        local bad, checked = 0, 0
        for _, e in ipairs(guide.spells) do
            local r = byKey[e.spell .. ":" .. (e.rank or 0)]
            if r and r.req and r.req > 0 then
                checked = checked + 1
                if r.req ~= e.level then
                    bad = bad + 1
                    CUI:Print(string.format("|cFFFFD100%s|r%s: guide says level %d, trainer says %d", e.spell, e.rank and (" rank " .. e.rank) or "", e.level, r.req))
                end
            end
        end
        CUI:Print(string.format("%s guide: %d spells checked against this trainer, %d with a different level.", guide.name, checked, bad))
    end
end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local frame
local pendingLevel

local function Enable()
    if frame then return end
    Build() -- so the box shows up in layout mode
    frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("TRAINER_SHOW")
    frame:RegisterEvent("TRAINER_CLOSED")
    frame:RegisterEvent("SPELLS_CHANGED")
    local pending
    frame:SetScript("OnEvent", function(_, event, arg1)
        local db = DB()
        if event == "PLAYER_LEVEL_UP" then
            if not db.onLevel then return end
            pendingLevel = arg1 or UnitLevel("player")
            if InCombatLockdown() then return end
            if C_Timer and C_Timer.After then
                C_Timer.After(1.5, function()
                    if pendingLevel then Show(pendingLevel, "level"); pendingLevel = nil end
                end)
            else
                Show(pendingLevel, "level"); pendingLevel = nil
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingLevel then Show(pendingLevel, "level"); pendingLevel = nil end
        elseif event == "TRAINER_SHOW" then
            if db.onTrainer then Show(UnitLevel("player"), "trainer") end
        elseif event == "TRAINER_CLOSED" then
            if box and box:IsShown() and shownBy == "trainer" then box:Hide() end
        elseif event == "SPELLS_CHANGED" then
            -- you just bought something: drop it from the list
            if box and box:IsShown() and shownLevel and not pending then
                pending = true
                C_Timer.After(0.3, function()
                    pending = false
                    if box:IsShown() then
                        local n = Render(shownLevel)
                        if n == 0 and shownBy ~= "manual" then box:Hide() end
                    end
                end)
            end
        end
    end)
end

SLASH_CYSLEVELUP1 = "/cuilevel"
SlashCmdList["CYSLEVELUP"] = function(msg)
    local lvl = tonumber(strtrim(msg or ""))
    if lvl and (lvl < 1 or lvl > 60) then lvl = nil end
    Show(lvl, "manual")
end
SLASH_CYSSCAN1 = "/cuiscan"
SlashCmdList["CYSSCAN"] = function() Scan() end

CUI:RegisterModule({
    key = "levelup",
    name = "Level-Up Spells",
    addon = "CysUI",
    desc = "When you level up or open your trainer, a box lists the spells worth buying now and why (skipped ranks stay on the list). Shaman tank guide first; more classes and specs are added over time.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Level-Up Spells") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local CLASS_NAMES = {
    DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}
local CLASS_ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

CUI:RegisterPage("Level-Up Spells", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Level-up spells", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("A box that lists the spells worth buying at your level, with the reason for each. Spells you already know are left out; anything you skipped stays on the list until you buy it.")

    local y = -92
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Show the box when I level up", "onLevel")
    Check("Show the box when I open my trainer", "onTrainer")

    -- which guide
    local list, cls = ClassGuides()
    local gl = W.Text(page, 12, T.accent)
    gl:SetPoint("TOPLEFT", 4, y - 6)
    gl:SetText("Guide for your class")
    local gb = W.Button(page, 300, 22, "")
    gb:SetPoint("TOPLEFT", 4, y - 26)
    local function ShowGuide()
        local g = CurrentGuide()
        gb:SetLabel(g and (g.name .. " (" .. g.role .. ")") or "No guide for your class yet")
    end
    ShowGuide()
    gb:SetScript("OnClick", function()
        if #list < 2 then return end
        local cur = CurrentGuide()
        local idx = 1
        for i, g in ipairs(list) do if cur and g.key == cur.key then idx = i end end
        db.guide[cls] = list[idx % #list + 1].key
        ShowGuide()
    end)
    y = y - 62

    local show = W.Button(page, 150, 22, "Show the box now", true)
    show:SetPoint("TOPLEFT", 4, y)
    show:SetScript("OnClick", function() Show(UnitLevel("player"), "manual") end)
    y = y - 40

    -- support table, built from whatever guides are loaded
    local lines = {}
    for _, c in ipairs(CLASS_ORDER) do
        local gs = CUI.LevelGuides and CUI.LevelGuides[c]
        if gs then
            for _, g in ipairs(gs) do
                lines[#lines + 1] = { CLASS_NAMES[c] .. " - " .. g.name, g.role .. " (" .. g.client .. ")" }
            end
        end
    end
    local supported = W.Text(page, 12, T.accent)
    supported:SetPoint("TOPLEFT", 4, y)
    supported:SetText("Guides included")
    W.Notes(page, 4, y - 22, width, "", lines)
    y = y - 22 - (#lines * 20) - 18

    local tips = CUI.LevelTips and CUI.LevelTips[cls]
    if tips then
        local th = W.Text(page, 12, T.accent)
        th:SetPoint("TOPLEFT", 4, y)
        th:SetText("Which spell to use")
        W.Notes(page, 4, y - 22, width, "", tips)
        y = y - 22 - (#tips * 34) - 12
    end

    W.Notes(page, 4, y, width, "", {
        { "/cuilevel", "show the box now; /cuilevel 30 previews what you would buy at level 30" },
        { "/cuiscan", "at your class trainer: saves the trainer's spells and checks the guide's levels (helps fix the guides)" },
        "The Dungeon DPS, Healer and Questing guides start at level 10; levels 1 to 8 are only in Earth Warden.",
        "Other classes and specs, and WoW Forever, are being added as guides become available.",
    })
end)
