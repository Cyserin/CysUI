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
    if db.killsText == nil then db.killsText = true end
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
    local KT = CUI.KillTracker
    local n = db.killsText and KT and KT.KillsToLevel and KT.KillsToLevel()
    if n then extra = extra .. format("   ~%d kills", n) end
    text:SetText(line .. extra) -- one string, so the whole line is centred on the bar
    text2:SetText("")
    local mode = db.textMode
    local show = mode == 1 or (mode == 2 and bar.hovering)
    text:SetShown(show)
    text2:SetShown(show)
end

-- XP from completed quests in your log (the selected quest is put back afterwards)
local function QuestLogXP()
    -- newer clients (Forever): the old quest log calls are gone, but each quest's XP can be read by its ID,
    -- so nothing has to be selected
    if not GetNumQuestLogEntries and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and GetQuestLogRewardXP then
        local total = 0
        for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
            local info = C_QuestLog.GetInfo(i)
            -- only quests whose objectives you have finished. A plain delivery ("take this letter to...") has no
            -- objectives and the game calls it complete from the moment you accept it; that XP is not earned yet.
            local goals = 1
            if info and info.questID and C_QuestLog.GetNumQuestObjectives then
                local okG, n = pcall(C_QuestLog.GetNumQuestObjectives, info.questID)
                if okG and type(n) == "number" then goals = n end
            end
            if info and not info.isHeader and info.questID and goals > 0 and C_QuestLog.IsComplete
                and C_QuestLog.IsComplete(info.questID) then
                local ok, xp = pcall(GetQuestLogRewardXP, info.questID)
                if ok and xp then total = total + xp end
            end
        end
        return total
    end
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
    local KT = CUI.KillTracker
    local n, avg
    if KT and KT.Active and KT.Active() then n, avg = KT.KillsToLevel() end
    if n then
        GameTooltip:AddDoubleLine("Kills to level:", format("~%d  (%d XP each)", n, avg), 0.8, 0.8, 0.8, 1, 0.82, 0)
    elseif KT and KT.Active and KT.Active() then
        GameTooltip:AddDoubleLine("Kills to level:", "after your first kill", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
    end
    -- XP per hour: at the farm spot you are at, else over the last 15 minutes
    local function K(v) return v >= 10000 and format("%.1fk", v / 1000) or tostring(floor(v)) end
    local s = KT and KT.Active and KT.Active() and KT.Spot and KT.Spot()
    if s and s.xpPerHour then
        GameTooltip:AddDoubleLine("XP per hour here:", format("%s  (level in ~%d min)", K(s.xpPerHour), floor((s.minsToLevel or 0) + 0.5)),
            0.8, 0.8, 0.8, 0.3, 1, 0.3)
    elseif KT and KT.Active and KT.Active() and KT.Rate then
        local r = KT.Rate(900)
        if r then GameTooltip:AddDoubleLine("XP per hour (15 min):", K(r), 0.8, 0.8, 0.8, 0.3, 1, 0.3) end
    end
    GameTooltip:Show()
end

function XP:Refresh() Refresh() end

-- On the action bars: a thin XP line pinned along the top of the highest of action bars 1-3, as wide as that bar
-- (it follows the bar's width), numbers only when you point at it. Uses Layout mode's Attach, so it can still be
-- re-pinned or moved there. Off puts it back on its own spot with its old height and text setting.
local ONBARS_H = 12 -- tall enough for the numbers to sit inside it
local function TopActionBar()
    local best, bestTop
    for _, key in ipairs({ "bar_main", "bar_bl", "bar_br" }) do
        local m = CUI.movers and CUI.movers[key]
        local top = m and not m.disabled and m.frame and m.frame:IsShown() and m.mover:GetTop()
        if top and (not bestTop or top > bestTop) then best, bestTop = key, top end
    end
    return best
end
local hookedBars = {}
local function FollowWidth()
    local db = DB()
    local e = CysUIDB.layout and CysUIDB.layout.cys_xp_bar
    if not (db.onBars and e and e.attach) then return end
    local t = CUI.movers[e.attach]
    local w = t and t.mover:GetWidth()
    if w and w > 40 and math.abs((e.width or 0) - w) >= 1 then
        e.width = math.floor(w + 0.5)
        CUI:ApplyLayout("cys_xp_bar")
    end
end
function XP.SetOnBars(on)
    local db = DB()
    if InCombatLockdown() then CUI:Print("Out of combat, please.") return end
    CysUIDB.layout = CysUIDB.layout or {}
    local e = CysUIDB.layout.cys_xp_bar or {}
    CysUIDB.layout.cys_xp_bar = e
    if on then
        local target = TopActionBar()
        if not target then
            CUI:Print("No action bar to put the XP bar on (Action Bars module off?).")
            db.onBars = false
            return
        end
        if not db.onBars then db.savedText, db.savedH = db.textMode, e.height end
        db.onBars = true
        e.attach, e.spot, e.ax, e.ay = target, "above", 0, 3
        e.height = ONBARS_H
        db.textMode = 1 -- numbers always, inside the bar
        local m = CUI.movers[target]
        if m and not hookedBars[target] then
            hookedBars[target] = true
            m.mover:HookScript("OnSizeChanged", function() C_Timer.After(0, FollowWidth) end)
        end
        e.width = m and math.floor(m.mover:GetWidth() + 0.5) or e.width
    else
        if db.onBars then
            e.attach, e.spot, e.ax, e.ay = nil, nil, nil, nil
            e.height = db.savedH
            db.textMode = db.savedText or 1
        end
        db.onBars = false
    end
    CUI:ApplyLayout("cys_xp_bar")
    Refresh()
end

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
    text:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "OUTLINE")
    text:SetTextColor(1, 1, 1)
    text2 = textFrame:CreateFontString(nil, "OVERLAY")
    text2:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "OUTLINE")
    text2:SetTextColor(1, 1, 1)
    text:SetPoint("CENTER", 0, -1)
    text2:SetPoint("CENTER", text, "CENTER", 0, 0)
    -- text size follows the bar's height
    local function SizeText()
        local h = bar:GetHeight()
        local size = math.max(8, math.min(10, math.floor(h * 0.6 + 0.5)))
        text:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "OUTLINE")
        text2:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "OUTLINE")
        -- a bar too thin for its numbers (on the action bars) shows them just above it instead
        text:ClearAllPoints()
        if h < 10 then text:SetPoint("BOTTOM", bar, "TOP", 0, 3) else text:SetPoint("CENTER", 0, -1) end
        if h < 10 then bar:SetHitRectInsets(0, 0, -4, -1) else bar:SetHitRectInsets(0, 0, 0, 0) end -- easier to point at
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
        resizable = true, minW = 150, maxW = 2000, minH = 4, maxH = 30, scalable = false,
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
    -- on the action bars: keep matching the bar's width after a reload too
    C_Timer.After(3, function()
        local db = DB()
        local e = CysUIDB.layout and CysUIDB.layout.cys_xp_bar
        local m = db.onBars and e and e.attach and CUI.movers[e.attach]
        if m and not hookedBars[e.attach] then
            hookedBars[e.attach] = true
            m.mover:HookScript("OnSizeChanged", function() C_Timer.After(0, FollowWidth) end)
        end
        -- earlier versions made it 5 / 8 px with numbers on mouseover: now 12 px, numbers always shown inside
        if m and (e.height or 0) < ONBARS_H then e.height = ONBARS_H; CUI:ApplyLayout("cys_xp_bar") end
        if m and not db.onBarsText then
            db.onBarsText = true
            if db.textMode == 2 then db.textMode = 1 end
            Refresh()
        end
        FollowWidth()
    end)
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
        function(v) db.textMode = v; db.onBarsText = true; Refresh() end, "Numbers on the bar: ")
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
    local blizz = W.Checkbox(page, "Hide Blizzard's XP and reputation bars (off needs a /reload)",
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
    local kt = W.Checkbox(page, "Show kills to level on the bar (from the Kill Tracker)", function() return db.killsText end,
        function(on) db.killsText = on; Refresh() end)
    kt:SetPoint("TOPLEFT", 4, -202)
    local ob = W.Checkbox(page, "Slim bar along the top of the action bars",
        function() return db.onBars end, function(on) XP.SetOnBars(on); mode:Refresh() end)
    ob:SetPoint("TOPLEFT", 4, -228)

    W.Header(page, "Colors (click to change)", width):SetPoint("TOPLEFT", 0, -264)
    local function ColorButton(y, label, key)
        local opts = {}
        for i, p in ipairs(PALETTE) do
            opts[i] = { i, format("|cFF%02X%02X%02X%s|r", floor(p[2] * 255 + 0.5), floor(p[3] * 255 + 0.5), floor(p[4] * 255 + 0.5), p[1]) }
        end
        local b = W.Dropdown(page, 260, opts, function() return db[key] end,
            function(v) db[key] = v; Refresh() end, label .. ": ")
        b:SetPoint("TOPLEFT", 4, y)
    end
    ColorButton(-294, "Your XP", "xpColor")
    ColorButton(-322, "Rested XP", "restedColor")
    ColorButton(-350, "Completed-quest XP", "questColor")

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -388)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Width and height are set in layout mode. The Blizzard bars switch is the same one as on the Action Bars page.")
end)
