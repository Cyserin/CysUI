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

local DEFAULTS = { onLevel = true, onTrainer = true, char = {}, asked = {}, askedDual = {} } -- char / asked / askedDual: per character

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

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function GuideLabel(g)
    return g.name .. (g.role and (" (" .. g.role .. ")") or "")
end

-- the guide this character follows (chosen at level 10, changeable in settings); the first one until then
local function CurrentGuide()
    local list, cls = ClassGuides()
    if #list == 0 then return nil, cls end
    local want = DB().char[CharKey()]
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
local shownLevel, shownBy, shownGuide

local function Build()
    if box then return box end
    box = CreateFrame("Frame", "CysLevelUpBox", UIParent)
    box:SetSize(ROW_W + 20, 160)
    box:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    W.Texture(box, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(box, 2, T.border, "BORDER") -- two pixels so no edge is lost after the box is moved

    -- header strip with the module's name
    local strip = W.Texture(box, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(20)
    local line = W.Texture(box, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -22)
    line:SetPoint("TOPRIGHT", -2, -22)
    line:SetHeight(2)
    box.header = W.Text(box, 11, T.accent)
    box.header:SetPoint("TOPLEFT", 10, -7)
    box.header:SetText("CYS'S SPELL SCOUT")

    box.title = W.Text(box, 13, T.accent)
    box.title:SetPoint("TOPLEFT", 10, -32)
    box.sub = W.Text(box, 10, T.desc, "RIGHT") -- the loaded guide, in the header strip
    box.sub:SetPoint("TOPRIGHT", -28, -8)

    local close = W.Button(box, 18, 18, "x")
    close:SetPoint("TOPRIGHT", -5, -4)
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

    -- left-click and drag the box itself to move it (same saved position as layout mode)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function()
        local m = CUI.movers and CUI.movers.levelup
        if m and m.mover then m.mover:StartMoving() end
    end)
    box:SetScript("OnDragStop", function()
        local m = CUI.movers and CUI.movers.levelup
        if not (m and m.mover) then return end
        m.mover:StopMovingOrSizing()
        local cx, cy = m.mover:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (cx and ux) then return end
        CysUIDB.layout = CysUIDB.layout or {}
        local e = CysUIDB.layout.levelup or {}
        CysUIDB.layout.levelup = e
        e.point, e.x, e.y = "CENTER", math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
        CUI:ApplyLayout("levelup")
    end)
    box:Hide()
    return box
end

-- override: show a guide other than the one this character follows (a preview from /cuilevel)
local function Render(level, override)
    shownGuide = override
    local guide = override or CurrentGuide()
    if not guide then return false end
    local buy, later = Evaluate(guide, level)
    Build()
    shownLevel = level

    box.title:SetText("Level " .. level .. ": spells worth buying")
    box.sub:SetText(override and (guide.name .. " - preview") or guide.name)

    local y = -54
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
    box:SetHeight(math.max(90, math.ceil((-y + 10) / 2) * 2)) -- whole, even height keeps the edges on whole pixels
    if CUI.ApplyLayout then CUI:ApplyLayout("levelup") end -- keep the layout-mode box the same size
    return #buy
end

-- who: "level" (leveled up), "trainer" (opened a trainer), "manual"
local function Show(level, who, override)
    level = level or UnitLevel("player")
    local guide, cls = override or CurrentGuide()
    if not guide then
        if who == "manual" then
            local name = UnitClass("player")
            CUI:Print("Cys's Spell Scout doesn't support " .. tostring(name) .. " yet. The guides it has so far are listed under /cui -> Class -> General.")
        end
        return
    end
    local n = Render(level, override)
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
-- "Which are you leveling as?" - asked at level 10, and again at 40
--------------------------------------------------------------------------------
local chooser

local function BuildChooser()
    if chooser then return chooser end
    chooser = CreateFrame("Frame", "CysLevelUpChoose", UIParent)
    chooser:SetSize(340, 120)
    chooser:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    chooser:SetFrameStrata("DIALOG")
    chooser:SetClampedToScreen(true)
    chooser:SetMovable(true)
    chooser:EnableMouse(true)
    chooser:RegisterForDrag("LeftButton")
    chooser:SetScript("OnDragStart", chooser.StartMoving)
    chooser:SetScript("OnDragStop", chooser.StopMovingOrSizing)
    W.Texture(chooser, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(chooser, 2, T.border, "BORDER")
    local strip = W.Texture(chooser, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(20)
    local line = W.Texture(chooser, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -22)
    line:SetPoint("TOPRIGHT", -2, -22)
    line:SetHeight(2)
    local head = W.Text(chooser, 11, T.accent, "CENTER")
    head:SetPoint("TOP", chooser, "TOP", 0, -7)
    head:SetText("CYS'S SPELL SCOUT")
    chooser.title = W.Text(chooser, 13, T.accent)
    chooser.title:SetPoint("TOPLEFT", 10, -32)
    chooser.text = W.Text(chooser, 11, T.desc)
    chooser.text:SetPoint("TOPLEFT", 10, -52)
    chooser.text:SetWidth(320)
    chooser.text:SetJustifyV("TOP")
    chooser.src = W.Text(chooser, 10, { 0.69, 0.69, 0.69 })
    chooser.src:SetWidth(320)
    chooser.src:SetJustifyV("TOP")
    chooser.src:SetText("Picks come from Wowhead's Classic Era leveling recommendations and community guides.")
    chooser.btns = {}
    chooser:Hide()
    return chooser
end

local function Choose(key)
    DB().char[CharKey()] = key
    if chooser then chooser:Hide() end
    local g = CurrentGuide()
    if g then CUI:Print("Spell Scout will follow: " .. GuideLabel(g) .. ". Change it any time under /cui -> Level-Up Spells.") end
    Show(UnitLevel("player"), "level")
end

local function HasDualAPI()
    return GetNumTalentGroups ~= nil or (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups ~= nil)
end

local function DualSpec()
    local n
    if GetNumTalentGroups then
        local ok, v = pcall(GetNumTalentGroups)
        n = ok and v
    elseif C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups then
        local ok, v = pcall(C_SpecializationInfo.GetNumSpecGroups)
        n = ok and v
    end
    return (n or 1) >= 2
end

-- kind: "level" (reached 10) or "dual" (a second talent spec exists)
local function AskNow(kind)
    local list = ClassGuides()
    BuildChooser()
    if kind == "level" then
        chooser.title:SetText("Which are you leveling as?")
        chooser.text:SetText("Pick the guide Spell Scout follows for your spell recommendations. You can change it any time under /cui -> Level-Up Spells.")
    elseif kind == "forty" then
        chooser.title:SetText("Level 40: still on the same guide?")
        chooser.text:SetText("At 40 you can buy a second talent spec. If your plan changed, pick the guide to follow from here; you can change it any time under /cui -> Level-Up Spells.")
    else
        chooser.title:SetText("Dual spec: which guide now?")
        chooser.text:SetText("You have a second talent spec. Pick the guide to follow from here; you can change it any time under /cui -> Level-Up Spells.")
    end
    chooser.src:ClearAllPoints()
    chooser.src:SetPoint("TOPLEFT", chooser, "TOPLEFT", 10, -90)
    local y = -118
    for i, g in ipairs(list) do
        local b = chooser.btns[i]
        if not b then
            b = W.Button(chooser, 320, 24, "")
            chooser.btns[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", chooser, "TOPLEFT", 10, y)
        b:SetLabel(GuideLabel(g))
        b:SetScript("OnClick", function() Choose(g.key) end)
        b:Show()
        y = y - 28
    end
    for i = #list + 1, #chooser.btns do chooser.btns[i]:Hide() end
    local skip = chooser.skip
    if not skip then
        skip = W.Button(chooser, 320, 20, "Ask me later (keep the current guide)")
        chooser.skip = skip
        skip:SetScript("OnClick", function() chooser:Hide(); Show(UnitLevel("player"), "level") end)
    end
    skip:ClearAllPoints()
    skip:SetPoint("TOPLEFT", chooser, "TOPLEFT", 10, y - 2)
    chooser:SetHeight(-y + 36)
    chooser:Show()
    return true
end

-- asks once at level 10, and once more when the character gets a second talent spec; true when the question is up
local function MaybeAsk(level)
    if #ClassGuides() < 2 then return false end
    local db = DB()
    local key = CharKey()
    if DualSpec() and not db.askedDual[key] then
        db.askedDual[key] = true
        db.asked[key] = math.max(db.asked[key] or 0, 10) -- no need for the level-10 question after this one
        return AskNow("dual")
    end
    -- a client that can't report talent specs: ask at 40, when dual spec becomes available
    if not HasDualAPI() and (level or 0) >= 40 and (db.asked[key] or 0) < 40 then
        db.asked[key] = 40
        return AskNow("forty")
    end
    if (level or 0) >= 10 and (db.asked[key] or 0) < 10 then
        db.asked[key] = 10
        return AskNow("level")
    end
    return false
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
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- these only exist on clients with dual spec; an unknown event name would raise an error, so each is tried safely
    for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, ev)
    end
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
                    if pendingLevel then
                        local lv = pendingLevel
                        pendingLevel = nil
                        if not MaybeAsk(lv) then Show(lv, "level") end -- the question comes first; the box follows the answer
                    end
                end)
            else
                Show(pendingLevel, "level"); pendingLevel = nil
            end
        elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
            -- buying dual spec (or swapping to the second spec for the first time) both mean a second spec exists
            if db.onLevel and not InCombatLockdown() then MaybeAsk(UnitLevel("player")) end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- already past 10 (or 40) on a character that was never asked
            if db.onLevel and C_Timer and C_Timer.After then
                C_Timer.After(4, function()
                    if not InCombatLockdown() then MaybeAsk(UnitLevel("player")) end
                end)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingLevel then
                local lv = pendingLevel
                pendingLevel = nil
                if not MaybeAsk(lv) then Show(lv, "level") end
            end
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
                        local n = Render(shownLevel, shownGuide)
                        if n == 0 and shownBy ~= "manual" then box:Hide() end
                    end
                end)
            end
        end
    end)
end

SLASH_CYSLEVELUP1 = "/cuilevel"
SlashCmdList["CYSLEVELUP"] = function(msg)
    -- /cuilevel                       the box for you now
    -- /cuilevel 30                    what your guide buys at level 30
    -- /cuilevel 24 restoration        what another guide buys at 24 (a preview; your own guide is not changed)
    -- /cuilevel list                  the guides you can name
    msg = strtrim(msg or "")
    local list = ClassGuides()
    if msg:lower() == "list" then
        local names = {}
        for _, g in ipairs(list) do names[#names + 1] = g.key .. " (" .. GuideLabel(g) .. ")" end
        CUI:Print("Guides: " .. (#names > 0 and table.concat(names, ", ") or "none for your class yet") .. ". Example: /cuilevel 24 " .. (list[1] and list[1].key or "name"))
        return
    end
    local lvl, rest = msg:match("^(%d+)%s*(.-)$")
    if not lvl then lvl, rest = nil, msg end
    lvl = tonumber(lvl)
    if lvl and (lvl < 1 or lvl > 60) then lvl = nil end
    local override
    rest = (rest or ""):lower()
    if rest ~= "" then
        for _, g in ipairs(list) do
            if g.key:lower() == rest or g.name:lower() == rest then override = g break end
        end
        if not override then
            for _, g in ipairs(list) do
                if g.key:lower():find(rest, 1, true) or g.name:lower():find(rest, 1, true) then override = g break end
            end
        end
        if not override then
            CUI:Print("No guide called '" .. rest .. "'. Type /cuilevel list to see them.")
            return
        end
    end
    Show(lvl, "manual", override)
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
    gl:SetText("Guide this character follows")
    local opts = {}
    for _, g in ipairs(list) do opts[#opts + 1] = { g.key, GuideLabel(g) } end
    local tipsHolder, tipsY
    local function BuildTips() end -- filled in below
    if #opts > 0 then
        local gb = W.Dropdown(page, 300, opts, function() local g = CurrentGuide(); return g and g.key end,
            function(v) db.char[CharKey()] = v; BuildTips() end)
        gb:SetPoint("TOPLEFT", 4, y - 26)
    else
        local none = W.Text(page, 12, T.desc)
        none:SetPoint("TOPLEFT", 4, y - 26)
        none:SetText("Cys's Spell Scout doesn't support your class yet. Shaman is first; the lists below show what is covered.")
        none:SetWidth(width - 8)
        none:SetJustifyH("LEFT")
    end
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
                local detail = g.role and (g.role .. " (" .. g.spec .. ")") or g.spec
                lines[#lines + 1] = { CLASS_NAMES[c] .. " - " .. g.name, detail .. ", " .. g.client }
            end
        end
    end
    local cmdItems = {
        { "/cuilevel", "show the box now; /cuilevel 30 previews level 30; /cuilevel 24 restoration previews another guide (yours is not changed); /cuilevel list names the guides" },
        { "/cuiscan", "at your class trainer: saves the trainer's spells and checks the guide's levels (helps fix the guides)" },
        "Earth Warden is a community tank build; Enhancement, Elemental and Restoration follow Wowhead's Classic Era leveling guides. At level 10, and again when you get a second talent spec (or reach level 40 on a client that can't say), Spell Scout asks which guide to follow, once per character.",
        "Other classes and specs, and WoW Forever, are being added as guides become available.",
    }

    -- Which spell to use sits first (it is what you look at most); the lists below it move down
    -- when the quick reference changes height with the guide.
    local tipsY = y
    local tipsHead = W.Text(page, 12, T.accent)
    tipsHead:SetPoint("TOPLEFT", 4, tipsY)
    local lower = {}
    function BuildTips()
        if tipsHolder then tipsHolder:Hide() end
        for _, o in ipairs(lower) do o:Hide() end
        wipe(lower)
        local g = CurrentGuide()
        tipsHead:SetText(g and ("Which spell to use: " .. g.name) or "Which spell to use")
        local items = (g and g.tips) or { "No quick reference for this guide yet." }
        tipsHolder = W.Notes(page, 4, tipsY - 22, width, "", items)
        local ly = tipsY - 22 - tipsHolder:GetHeight() - 16
        local supported = W.Text(page, 12, T.accent)
        supported:SetPoint("TOPLEFT", 4, ly)
        supported:SetText("Guides included")
        local sbox = W.Notes(page, 4, ly - 22, width, "", lines)
        ly = ly - 22 - sbox:GetHeight() - 16
        local cbox = W.Notes(page, 4, ly, width, "", cmdItems)
        lower[1], lower[2], lower[3] = supported, sbox, cbox
    end
    BuildTips()
end)
