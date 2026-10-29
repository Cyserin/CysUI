--------------------------------------------------------------------------------
-- Cys's UI - Kill Tracker
--
-- A small bar that learns how much XP your kills give and tells you how many more
-- kills it takes to level. Counts reset when you log in (and, if you like, on level up).
--
-- Everything here is optional: the whole module can be switched off under /cui > Modules,
-- and the bar itself can be hidden under /cui > Kill Tracker without a reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local KT = {}
CUI.KillTracker = KT

local floor, ceil, max = math.floor, math.ceil, math.max

local FORMATS = {
    { name = "Kills to level + average XP", text = function(kills, avg) return format("Kills to level: %d  (~%d XP each)", kills, avg) end },
    { name = "Kills to level only",         text = function(kills) return format("Kills to level: %d", kills) end },
    { name = "Average XP per kill only",    text = function(_, avg) return format("~%d XP per kill", avg) end },
}

local function DB()
    CysUIDB.killtracker = CysUIDB.killtracker or {}
    local db = CysUIDB.killtracker
    if db.show == nil then
        -- carry over the old switch from before this had its own page; off for anyone new
        local old = CysUIDB.unitframes and CysUIDB.unitframes.killTracker
        db.show = old and true or false
    end
    if db.format == nil then db.format = 1 end
    if db.resetOnLevel == nil then db.resetOnLevel = true end
    if db.hideAtMax == nil then db.hideAtMax = true end
    return db
end

local frame, text
local totalXP, kills = 0, 0
local LEVEL_CAP = 60

local function Refresh()
    if not frame then return end
    local db = DB()
    local atMax = db.hideAtMax and (UnitLevel("player") or 0) >= LEVEL_CAP
    if not db.show or atMax then
        frame:Hide()
        return
    end
    frame:Show()

    local line
    if kills == 0 or totalXP == 0 then
        line = "Kill a mob to track XP average"
    else
        local avg = totalXP / kills
        local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
        local needed = max(0, ceil(remaining / avg))
        local fmt = FORMATS[db.format] or FORMATS[1]
        line = fmt.text(needed, floor(avg))
    end
    text:SetText(line)
end

function KT:Reset()
    totalXP, kills = 0, 0
    Refresh()
end

function KT:Refresh() Refresh() end

local function OnEvent(_, event, msg)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- "<mob> dies, you gain 123 experience."  (quest rewards say "You gain 123 experience." and aren't kills)
        local xp = msg and msg:match("dies, you gain (%d+) experience")
        if xp then
            totalXP = totalXP + tonumber(xp)
            kills = kills + 1
            Refresh()
        end
    elseif event == "PLAYER_XP_UPDATE" then
        Refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        if DB().resetOnLevel then totalXP, kills = 0, 0 end
        Refresh()
    end
end

function KT.Enable()
    DB()
    frame = CreateFrame("Frame", "CysUIKillTrackerFrame", UIParent)
    frame:SetSize(250, 22)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    W.Texture(frame, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
    W.Border(frame, 1, T.border, "BORDER")

    text = W.Text(frame, 12, T.accent, "CENTER")
    text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    text:SetPoint("CENTER", 0, 0)

    CUI:RegisterMovable(frame, "killtracker", "Kill Tracker", { point = "CENTER", x = 0, y = -180, scalable = true,
        resizable = true, minW = 120, maxW = 600, minH = 16, maxH = 40 })

    frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    frame:RegisterEvent("PLAYER_XP_UPDATE")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:SetScript("OnEvent", OnEvent)
    Refresh()
end

CUI:RegisterModule({
    key = "killtracker",
    name = "Kill Tracker",
    addon = "CysUI",
    desc = "Learns your average XP per kill and shows how many more kills it takes to level.",
    onEnable = KT.Enable,
    open = function() CUI:OpenConfig("Kill Tracker") end,
})

CUI:RegisterPage("Kill Tracker", function(page)
    local db = DB()
    local width = 480

    W.Header(page, "Kill Tracker", width):SetPoint("TOPLEFT", 0, -4)
    local show = W.Checkbox(page, "Show the kill tracker", function() return db.show end,
        function(on) db.show = on; Refresh() end)
    show:SetPoint("TOPLEFT", 4, -34)

    local fmt = W.Button(page, 300, 22, "")
    local function SetFmtLabel() fmt:SetLabel("Shows: " .. (FORMATS[db.format] or FORMATS[1]).name) end
    SetFmtLabel()
    fmt:SetPoint("TOPLEFT", 4, -66)
    fmt:SetScript("OnClick", function()
        db.format = db.format % #FORMATS + 1
        SetFmtLabel()
        Refresh()
    end)

    local lvl = W.Checkbox(page, "Start counting again when I level up", function() return db.resetOnLevel end,
        function(on) db.resetOnLevel = on end)
    lvl:SetPoint("TOPLEFT", 4, -98)
    local cap = W.Checkbox(page, "Hide it at max level", function() return db.hideAtMax end,
        function(on) db.hideAtMax = on; Refresh() end)
    cap:SetPoint("TOPLEFT", 4, -124)

    local reset = W.Button(page, 160, 22, "Reset this session")
    reset:SetPoint("TOPLEFT", 4, -158)
    reset:SetScript("OnClick", function() KT:Reset() end)
    local move = W.Button(page, 240, 22, "Move the tracker (layout mode)")
    move:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -196)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("It learns from the kills you make while you play, so the first number appears after your first kill. "
        .. "Quest rewards don't count as kills.")
end)
