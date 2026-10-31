--------------------------------------------------------------------------------
-- Cys's UI - Experience Bar
--
-- A slim, gold-edged XP bar with a rested overlay and a tooltip (XP, remaining, quest
-- log XP, rested). Move and resize it in layout mode (/cui layout). Blizzard's own
-- experience bar is hidden by the Action Bars module.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local XP = {}
CUI.XPBar = XP

local floor, min = math.floor, math.min
local LEVEL_CAP = 60

local TEXT_MODES = { "Always", "On mouseover", "Never" }

-- Colors you can pick from (click the buttons on the XP Bar page to cycle)
local PALETTE = {
    { "Purple", 0.60, 0.20, 0.80 }, { "Blue", 0.00, 0.40, 0.85 }, { "Light blue", 0.20, 0.70, 1.00 },
    { "Gold", 1.00, 0.82, 0.00 }, { "Green", 0.20, 0.75, 0.30 }, { "Orange", 1.00, 0.55, 0.10 },
    { "Red", 0.85, 0.20, 0.20 }, { "White", 0.90, 0.90, 0.90 },
}
local COLOR_DEFAULTS = { xpColor = 1, restedColor = 2, questColor = 4 } -- purple XP, blue rested, gold quests

local function DB()
    CysUIDB.xpbar = CysUIDB.xpbar or {}
    local db = CysUIDB.xpbar
    if db.show == nil then db.show = true end
    if db.textMode == nil then db.textMode = 1 end
    if db.hideAtMax == nil then db.hideAtMax = true end
    if db.questXP == nil then db.questXP = true end
    if db.questBar == nil then db.questBar = true end
    for k, v in pairs(COLOR_DEFAULTS) do if db[k] == nil then db[k] = v end end
    return db
end

local bar, status, rested, quest, text, text2
local questCache = 0

local function Color(key)
    local c = PALETTE[DB()[key]] or PALETTE[COLOR_DEFAULTS[key]]
    return c[2], c[3], c[4]
end

local function Hex(key)
    local r, g, b = Color(key)
    return format("|cFF%02X%02X%02X", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function Refresh()
    if not bar then return end
    local db = DB()
    local level = UnitLevel("player") or 1
    if not db.show or (db.hideAtMax and level >= LEVEL_CAP) then
        bar:Hide()
        return
    end
    bar:Show()

    local cur, maxXP = UnitXP("player") or 0, UnitXPMax("player") or 100
    local rest = GetXPExhaustion() or 0
    -- Three layers: your XP (always on top), then quest-log XP and rested XP stretching ahead of it
    status:SetMinMaxValues(0, maxXP)
    status:SetValue(cur)
    do local r, g, b = Color("xpColor"); status:SetStatusBarColor(r, g, b, 0.75) end -- slightly dimmed so the text stays readable

    if rest > 0 then
        rested:Show()
        rested:SetMinMaxValues(0, maxXP)
        rested:SetValue(min(maxXP, cur + rest))
        local r, g, b = Color("restedColor")
        rested:SetStatusBarColor(r, g, b, 0.6)
    else
        rested:Hide()
    end

    local q = db.questBar and questCache or 0
    if q > 0 then
        quest:Show()
        quest:SetMinMaxValues(0, maxXP)
        quest:SetValue(min(maxXP, cur + q))
        local r, g, b = Color("questColor")
        quest:SetStatusBarColor(r, g, b, 0.7)
    else
        quest:Hide()
    end

    local pct = maxXP > 0 and floor(cur / maxXP * 100) or 0
    local line = format("%d / %d (%d%%)", cur, maxXP, pct)
    local extra = ""
    if rest > 0 then extra = extra .. format("   +%d%% Rested", floor(rest / maxXP * 100)) end
    if q > 0 then extra = extra .. format("   +%d%% Quests", floor(q / maxXP * 100)) end
    text:SetText(line .. extra) -- one string, so the whole line is centred on the bar
    text2:SetText("")
    local mode = db.textMode
    local show = mode == 1 or (mode == 2 and bar.hovering)
    text:SetShown(show)
    text2:SetShown(show)
end

-- XP from completed quests in your log (the selected quest is put back afterwards)
local function QuestLogXP()
    if not (GetNumQuestLogEntries and GetQuestLogRewardXP and SelectQuestLogEntry) then return 0 end
    local total = 0
    local selected = GetQuestLogSelection and GetQuestLogSelection()
    for i = 1, (GetNumQuestLogEntries()) do
        local _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if not isHeader and isComplete and isComplete > 0 then
            SelectQuestLogEntry(i)
            total = total + (GetQuestLogRewardXP() or 0)
        end
    end
    if selected and selected > 0 then SelectQuestLogEntry(selected) end
    return total
end

-- Re-count quest XP a moment after the quest log changes (counting selects quests one by one,
-- so it must not run on every event, and the events it causes itself are ignored)
local counting, countTimer = false, nil
local function UpdateQuestXP()
    if counting then return end
    if countTimer then return end
    countTimer = true
    C_Timer.After(0.5, function()
        countTimer = nil
        counting = true
        questCache = QuestLogXP()
        counting = false
        Refresh()
    end)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    local cur, maxXP = UnitXP("player") or 0, UnitXPMax("player") or 1
    local rest = GetXPExhaustion() or 0
    local pct = cur / maxXP * 100
    local remaining = maxXP - cur
    GameTooltip:AddDoubleLine("Experience", "Level " .. (UnitLevel("player") or "?"), 1, 0.82, 0, 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("XP:", format("%.1fK / %.1fK (%.2f%%)", cur / 1000, maxXP / 1000, pct), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Remaining:", format("%.1fK (%.2f%% - %.2f bars)", remaining / 1000, 100 - pct, (100 - pct) / 5),
        0.8, 0.8, 0.8, 1, 1, 1)
    if DB().questXP then
        local q = QuestLogXP()
        GameTooltip:AddDoubleLine("Quest log XP:", format("%d (%.2f%%)", q, q / maxXP * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Rested:", format("+%d (%.2f%%)", rest, rest / maxXP * 100), 0.8, 0.8, 0.8,
        rest > 0 and 0.3 or 0.8, rest > 0 and 0.6 or 0.8, rest > 0 and 1 or 0.8)
    GameTooltip:Show()
end

function XP:Refresh() Refresh() end

function XP.Enable()
    DB()
    bar = CreateFrame("Button", "CysXPBar", UIParent)
    bar:SetSize(450, 14)
    bar:EnableMouse(true)
    W.Texture(bar, "BACKGROUND", { 0.05, 0.05, 0.05, 0.9 }):SetAllPoints()
    W.Border(bar, 1, T.border, "BORDER")

    -- quest XP is the bottom layer; rested XP is drawn over it (rested starts right after your XP and is
    -- used up first), see-through enough that the gold quest segment still shows underneath
    quest = CreateFrame("StatusBar", nil, bar)
    quest:SetPoint("TOPLEFT", 1, -1)
    quest:SetPoint("BOTTOMRIGHT", -1, 1)
    quest:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    quest:SetFrameLevel(bar:GetFrameLevel() + 1)
    rested = CreateFrame("StatusBar", nil, bar)
    rested:SetPoint("TOPLEFT", 1, -1)
    rested:SetPoint("BOTTOMRIGHT", -1, 1)
    rested:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rested:SetFrameLevel(quest:GetFrameLevel() + 1)
    status = CreateFrame("StatusBar", nil, bar)
    status:SetPoint("TOPLEFT", 1, -1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    status:SetFrameLevel(rested:GetFrameLevel() + 1)

    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(status:GetFrameLevel() + 5)
    text = textFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    text:SetTextColor(1, 1, 1)
    text2 = textFrame:CreateFontString(nil, "OVERLAY")
    text2:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    text2:SetTextColor(1, 1, 1)
    text:SetPoint("CENTER", 0, -1)
    text2:SetPoint("CENTER", text, "CENTER", 0, 0)
    -- text size follows the bar's height
    local function SizeText()
        local size = math.max(8, math.min(10, math.floor(bar:GetHeight() * 0.6 + 0.5)))
        text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        text2:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    end
    bar:SetScript("OnSizeChanged", SizeText)
    SizeText()

    bar:SetScript("OnEnter", function(self)
        self.hovering = true
        Refresh()
        ShowTooltip(self)
    end)
    bar:SetScript("OnLeave", function(self)
        self.hovering = false
        Refresh()
        GameTooltip:Hide()
    end)

    CUI:RegisterMovable(bar, "cys_xp_bar", "Experience Bar", {
        point = "BOTTOM", x = 0, y = 4,
        resizable = true, minW = 150, maxW = 1000, minH = 6, maxH = 30, scalable = false,
    })

    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
                          "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN" }) do
        f:RegisterEvent(ev)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_TURNED_IN"
            or event == "PLAYER_ENTERING_WORLD" then
            UpdateQuestXP()
        end
        Refresh()
    end)
    Refresh()
end

CUI:RegisterModule({
    key = "xpbar",
    name = "Experience Bar",
    addon = "CysUI",
    desc = "A slim gold-edged XP bar with a rested overlay and a detailed tooltip.",
    onEnable = XP.Enable,
    open = function() CUI:OpenConfig("XP Bar") end,
})

CUI:RegisterPage("XP Bar", function(page)
    local db = DB()
    local width = 480

    W.Header(page, "Experience Bar", width):SetPoint("TOPLEFT", 0, -4)
    local show = W.Checkbox(page, "Show the experience bar", function() return db.show end,
        function(on) db.show = on; Refresh() end)
    show:SetPoint("TOPLEFT", 4, -34)

    local modeOpts = {}
    for i, name in ipairs(TEXT_MODES) do modeOpts[i] = { i, name } end
    local mode = W.Dropdown(page, 260, modeOpts, function() return db.textMode end,
        function(v) db.textMode = v; Refresh() end, "Numbers on the bar: ")
    mode:SetPoint("TOPLEFT", 4, -66)

    local cap = W.Checkbox(page, "Hide it at max level", function() return db.hideAtMax end,
        function(on) db.hideAtMax = on; Refresh() end)
    cap:SetPoint("TOPLEFT", 4, -98)
    local q = W.Checkbox(page, "Include quest log XP in the tooltip", function() return db.questXP end,
        function(on) db.questXP = on end)
    q:SetPoint("TOPLEFT", 4, -124)
    local qb = W.Checkbox(page, "Show XP from completed quests as a segment on the bar", function() return db.questBar end,
        function(on) db.questBar = on; Refresh() end)
    qb:SetPoint("TOPLEFT", 4, -150)
    -- the same switch as on the Action Bars page: Blizzard's own XP and reputation bars
    local blizz = W.Checkbox(page, "Hide Blizzard's experience and reputation bars (turning off needs a /reload)",
        function()
            local ab = CysUIDB.actionbars
            return not ab or ab.hideStatusBars ~= false
        end,
        function(on)
            CysUIDB.actionbars = CysUIDB.actionbars or {}
            CysUIDB.actionbars.hideStatusBars = on
            if on and CUI.ActionBars and CUI.ActionBars.HideStatusBars then CUI.ActionBars:HideStatusBars() end
        end)
    blizz:SetPoint("TOPLEFT", 4, -176)

    W.Header(page, "Colors (click to change)", width):SetPoint("TOPLEFT", 0, -212)
    local function ColorButton(y, label, key)
        local opts = {}
        for i, p in ipairs(PALETTE) do
            opts[i] = { i, format("|cFF%02X%02X%02X%s|r", floor(p[2] * 255 + 0.5), floor(p[3] * 255 + 0.5), floor(p[4] * 255 + 0.5), p[1]) }
        end
        local b = W.Dropdown(page, 260, opts, function() return db[key] end,
            function(v) db[key] = v; Refresh() end, label .. ": ")
        b:SetPoint("TOPLEFT", 4, y)
    end
    ColorButton(-242, "Your XP", "xpColor")
    ColorButton(-270, "Rested XP", "restedColor")
    ColorButton(-298, "Completed-quest XP", "questColor")

    local move = W.Button(page, 280, 22, "Move and resize the bar (layout mode)")
    move:SetPoint("TOPLEFT", 4, -336)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -374)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Width and height are set in layout mode. The Blizzard bars switch is the same one as on the Action Bars page.")
end)
