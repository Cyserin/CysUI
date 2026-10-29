--------------------------------------------------------------------------------
-- Cys's Roll Tracker - tracks /roll and "pass" for loot and announces the winner.
--
--   Party (2-5):  the window opens by itself; the winner is announced automatically
--                 once everyone has rolled or passed.
--   Raid:         only the raid leader, an assistant or the master looter get the
--                 window automatically and can announce. The winner is announced when
--                 the roll window ends (default 20s after the first roll of a round),
--                 or sooner if everyone answered. Everybody else can still open the
--                 window with /crt to watch, but can't announce.
--
-- Commands: /crt (toggle) | /crt clear | /crt announce | /crt status
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "rolls", name = "Cys's Roll Tracker",
    desc = "Tracks /roll and pass results for loot and announces the winner. In raids only the leader, assistants and master looter announce.",
    open = function() if CysRollTracker then CysRollTracker:Toggle() end end,
    body = function(...)
local ADDON_NAME = ...


CysRollTracker = CysRollTracker or {}
local RT = CysRollTracker
RT.version = "1.2.0"

local format, sort, ceil = string.format, table.sort, math.ceil
local max, min = math.max, math.min

local DEFAULTS = { raidAutoAnnounce = true, raidWindow = 20 }
local DB = {} -- replaced by the saved table on ADDON_LOADED

--------------------------------------------------------------------------------
-- Style
--------------------------------------------------------------------------------
local C = {
    bg     = { 0.067, 0.067, 0.067 },
    header = { 0.078, 0.078, 0.078 },
    gold   = CysUI.W.T.border, -- follows the Border color setting
    accent = { 1, 0.82, 0 },
    line   = { 0.165, 0.165, 0.165 },
    button = { 0.102, 0.102, 0.102 },
    text   = { 0.88, 0.88, 0.88 },
    dim    = { 0.47, 0.47, 0.47 },
    dark   = { 0.067, 0.067, 0.067 },
}
local GOLD = "|cFFFFD100"

local function Texture(parent, layer, color, alpha)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    if color == C.gold and not alpha then CysUI.W.TrackEdge(t) end
    return t
end

local function Border(parent, color)
    local e = {}
    for i = 1, 4 do e[i] = Texture(parent, "BORDER", color) end
    e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(1)
    return e
end

local function SetBorder(edges, color)
    for i = 1, 4 do edges[i]:SetColorTexture(color[1], color[2], color[3], 1) end
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Say(msg) print("|cFFFFD100[Cys's Roll Tracker]|r " .. msg) end

local function FlatButton(parent, width, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    b.bg = Texture(b, "BACKGROUND", C.button)
    b.bg:SetAllPoints()
    b.edges = Border(b, C.line)
    b.label = Text(b, 11, C.accent, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label)
    b:SetScript("OnEnter", function(s) SetBorder(s.edges, C.accent) end)
    b:SetScript("OnLeave", function(s) SetBorder(s.edges, C.line) end)
    b:SetScript("OnMouseDown", function(s) s.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(s) s.label:SetPoint("CENTER", 0, 0) end)
    return b
end

--------------------------------------------------------------------------------
-- Who may announce
--------------------------------------------------------------------------------
-- Older and newer clients expose these under different names, so each has a fallback.
local function IsLeader()
    if UnitIsGroupLeader then return UnitIsGroupLeader("player") and true or false end
    return (IsRaidLeader and IsRaidLeader()) and true or false
end

local function IsAssistant()
    if UnitIsGroupAssistant then return UnitIsGroupAssistant("player") and true or false end
    return (IsRaidOfficer and IsRaidOfficer()) and true or false
end

local function IsMasterLooter()
    if not GetLootMethod then return false end
    local method, partyID, raidID = GetLootMethod()
    if method ~= "master" then return false end
    if raidID and raidID > 0 then return UnitIsUnit("raid" .. raidID, "player") and true or false end
    return partyID == 0 -- 0 = you, in a party
end

-- Solo and parties: always. Raids: leader, assistant or master looter only.
local function CanAnnounce()
    if not (IsInGroup and IsInGroup()) then return true end
    if not IsInRaid() then return true end
    return IsLeader() or IsAssistant() or IsMasterLooter()
end

local function GroupSize()
    return max(GetNumGroupMembers and GetNumGroupMembers() or 0, 1)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local rolls, passes = {}, {} -- [shortName] = roll / true
local announced = false
local windowToken, windowEnd = 0, nil
local manualOpen = false
local frame, body, status, hint, btnAnnounce, btnRules

local function ShortName(name) return name and (name:match("^([^-]+)") or name) end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Parse "Name rolls 45 (1-100)" in whatever language the client uses
local ROLL_PATTERN
do
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1") -- escape pattern characters
    fmt = fmt:gsub("%%s", "(.+)")
    fmt = fmt:gsub("%%d", "(%%d+)")
    ROLL_PATTERN = "^" .. fmt .. "$"
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------
local function UpdateHint()
    if windowEnd then
        local left = max(0, ceil(windowEnd - GetTime()))
        hint:SetText(GOLD .. format("Announcing in %ds", left) .. "|r")
    elseif IsInRaid() and not CanAnnounce() then
        hint:SetText("|cFF777777Raid: the leader, assistants and master looter announce.|r")
    else
        hint:SetText("")
    end
end

local Announce -- forward declaration

local function Refresh()
    if not frame then return end

    local list = {}
    for name, roll in pairs(rolls) do list[#list + 1] = { name = name, roll = roll } end
    sort(list, function(a, b)
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.name < b.name
    end)

    local lines = { GOLD .. "ROLLS|r" }
    if #list == 0 then lines[#lines + 1] = "|cFF666666(no rolls yet)|r" end
    local top = list[1] and list[1].roll
    for _, e in ipairs(list) do
        local color = (e.roll == top) and "|cFFFFD100" or "|cFFE0E0E0"
        lines[#lines + 1] = format("|cFF4FD66B%3d|r  %s%s|r", e.roll, color, e.name)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = GOLD .. "PASSED|r"
    local passed = {}
    for name in pairs(passes) do passed[#passed + 1] = name end
    sort(passed)
    if #passed == 0 then lines[#lines + 1] = "|cFF666666(no passes)|r" end
    for _, name in ipairs(passed) do lines[#lines + 1] = "|cFF888888" .. name .. "|r" end

    body:SetText(table.concat(lines, "\n"))
    frame.content:SetHeight(max(body:GetStringHeight(), 1))

    local responded = #list + #passed
    status:SetText(format("|cFFB8860BResponded:|r |cFF4FD66B%d|r / %d", responded, GroupSize()))
    local ok = CanAnnounce()
    btnAnnounce:SetAlpha(ok and 1 or 0.4)
    btnRules:SetAlpha(ok and 1 or 0.4)
    UpdateHint()

    -- everyone answered: no need to wait for the timer
    if not announced and GroupSize() >= 2 and responded >= GroupSize() and ok
        and (not IsInRaid() or DB.raidAutoAnnounce) then
        announced = true
        Announce(true)
    end
end

local refreshQueued = false
local function RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Roll window (raids): announce N seconds after the first roll of a round
--------------------------------------------------------------------------------
local function CancelWindow()
    windowToken = windowToken + 1
    windowEnd = nil
    if frame then frame:SetScript("OnUpdate", nil) end
end

local function StartWindow()
    if windowEnd then return end
    windowToken = windowToken + 1
    local token, seconds = windowToken, max(5, DB.raidWindow or 20)
    windowEnd = GetTime() + seconds
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then acc = 0; UpdateHint() end
    end)
    C_Timer.After(seconds, function()
        if token == windowToken and not announced then
            CancelWindow()
            Announce(true)
        end
    end)
end

local function ResetData()
    rolls, passes = {}, {}
    announced = false
    CancelWindow()
    RequestRefresh()
end

--------------------------------------------------------------------------------
-- Announcing
--------------------------------------------------------------------------------
Announce = function(isAuto)
    local inRaid = IsInRaid()
    if inRaid and not CanAnnounce() then
        if not isAuto then Say("In a raid only the leader, an assistant or the master looter can announce.") end
        announced = false
        return
    end

    local highest, winners = -1, {}
    for name, roll in pairs(rolls) do
        if roll > highest then
            highest, winners = roll, { name }
        elseif roll == highest then
            winners[#winners + 1] = name
        end
    end
    sort(winners)

    local channel = (IsInGroup and IsInGroup()) and (inRaid and "RAID" or "PARTY") or nil
    local prefix = isAuto and "[Cys's Roll Tracker - Auto]" or "[Cys's Roll Tracker]"
    local function Send(msg)
        if channel then SendChatMessage(msg, channel) else Say(msg) end
    end

    if #winners > 1 then
        Send(format("%s TIE at %d between %s! Please re-roll!", prefix, highest, table.concat(winners, ", ")))
        ResetData()
    elseif #winners == 1 then
        Send(format("%s Winner: %s with a roll of %d!", prefix, winners[1], highest))
        ResetData()
    else
        if not isAuto then Send(prefix .. " No rolls recorded.") end
        announced = false
        CancelWindow()
    end
end

local function AnnounceRules()
    if not (IsInGroup and IsInGroup()) then
        Say("You must be in a group to announce the rules.")
        return
    end
    if IsInRaid() and not CanAnnounce() then
        Say("In a raid only the leader, an assistant or the master looter can announce.")
        return
    end
    SendChatMessage("[Cys's Roll Tracker] Enabled! Type /roll or 'pass' in chat for chests and mining nodes.",
        IsInRaid() and "RAID" or "PARTY")
end

--------------------------------------------------------------------------------
-- Window visibility
--------------------------------------------------------------------------------
-- Parties: open by themselves. Raids: only for people who can announce (so 40 players
-- don't all get a popup), but anyone can open it by hand with /crt.
local function CheckGroupStatus()
    if not frame then return end
    local size = GetNumGroupMembers and GetNumGroupMembers() or 0
    if size >= 2 then
        if not IsInRaid() or CanAnnounce() then
            frame:Show()
        elseif not manualOpen then
            frame:Hide()
        end
    else
        manualOpen = false
        frame:Hide()
    end
    RequestRefresh()
end

local function OnActivity()
    if IsInRaid() and DB.raidAutoAnnounce and CanAnnounce() then StartWindow() end
    if frame and not frame:IsShown() and (not IsInRaid() or CanAnnounce() or manualOpen) then frame:Show() end
    RequestRefresh()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function OnSystemMessage(msg)
    local name, roll = msg:match(ROLL_PATTERN)
    if not name then return end
    name = ShortName(name)
    rolls[name] = tonumber(roll)
    passes[name] = nil -- rolling overrides an earlier pass
    OnActivity()
end

local function OnGroupChat(msg, sender)
    local name = ShortName(sender)
    local clean = strtrim(msg or ""):lower()
    if (clean == "pass" or clean == "p" or clean == "pass chest") and name and not rolls[name] then
        passes[name] = true
        OnActivity()
    end
end

local CHAT_EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                      "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED",
                        "PLAYER_ENTERING_WORLD" }

local function SafeRegister(f, event) pcall(f.RegisterEvent, f, event) end -- skip events this client doesn't have

--------------------------------------------------------------------------------
-- Guide window
--------------------------------------------------------------------------------
local guide
local function ToggleGuide()
    if not guide then
        local g = CreateFrame("Frame", "CysRollTrackerGuideFrame", UIParent)
        g:SetSize(380, 300)
        g:SetPoint("CENTER")
        g:SetFrameStrata("DIALOG")
        g:SetClampedToScreen(true)
        g:SetMovable(true)
        g:EnableMouse(true)
        g:RegisterForDrag("LeftButton")
        g:SetScript("OnDragStart", g.StartMoving)
        g:SetScript("OnDragStop", g.StopMovingOrSizing)
        g:Hide()
        Texture(g, "BACKGROUND", C.bg):SetAllPoints()
        Border(g, C.gold)

        local title = Text(g, 14, C.accent, "CENTER")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Cys's Roll Tracker Guide")

        local close = CreateFrame("Button", nil, g)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -6, -6)
        close.text = Text(close, 14, { 1, 1, 1 }, "CENTER")
        close.text:SetPoint("CENTER", 0, 0)
        close.text:SetText("X")
        close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
        close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
        close:SetScript("OnClick", function() g:Hide() end)

        local text = Text(g, 11, C.text)
        text:SetPoint("TOPLEFT", 20, -46)
        text:SetWidth(340)
        text:SetJustifyV("TOP")
        text:SetSpacing(3)
        text:SetText(table.concat({
            GOLD .. "Overview|r",
            "Tracks /roll results and 'pass' in group chat, highest roll first.",
            "",
            GOLD .. "Parties|r",
            "The window opens by itself and the winner is announced once everyone has rolled or passed.",
            "",
            GOLD .. "Raids|r",
            "Only the raid leader, assistants and master looter get the window automatically and can announce. The winner is announced when the roll window ends (set in /cui under Roll Tracker) or when everyone answered.",
            "",
            GOLD .. "Commands|r",
            "/crt - show or hide the window",
            "/crt clear - clear the list",
            "/crt announce - announce the winner now",
            "/crt status - show why announcing is or isn't allowed",
        }, "\n"))
        g:SetHeight(46 + text:GetStringHeight() + 26)

        tinsert(UISpecialFrames, "CysRollTrackerGuideFrame")
        guide = g
    end
    if guide:IsShown() then guide:Hide() else guide:Show() end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function CreateFrames()
    local f = CreateFrame("Frame", "CysRollTrackerFrame", UIParent)
    frame = f
    f:SetSize(260, 300)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if DB.pos then
        f:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    -- With Cys's UI, position and scale come from layout mode (/cui layout)
    if CysUI and CysUI.RegisterMovable then
        CysUI:RegisterMovable(f, "rolls", "Roll Tracker", { point = "CENTER", x = 0, y = 0 })
    end
    Texture(f, "BACKGROUND", C.bg, 0.96):SetAllPoints()
    Border(f, C.gold)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    Texture(header, "BACKGROUND", C.header):SetAllPoints()
    local hline = Texture(header, "BORDER", C.gold)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    local function LayoutControlled() return CysUI and CysUI.movers and CysUI.movers.rolls end
    header:SetScript("OnDragStart", function() if not LayoutControlled() then f:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        if LayoutControlled() then return end
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if point then DB.pos = { point, relPoint, x, y } end
    end)

    local title = Text(header, 12, C.accent)
    title:SetPoint("LEFT", 10, 0)
    title:SetText("Cys's Roll Tracker")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() manualOpen = false; f:Hide() end)

    local gear = CreateFrame("Button", nil, header)
    gear:SetSize(16, 16)
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local gearTex = gear:CreateTexture(nil, "ARTWORK")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gearTex:SetVertexColor(0.8, 0.8, 0.8)
    gear:SetScript("OnEnter", function(s)
        gearTex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText("Guide & Commands")
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function()
        gearTex:SetVertexColor(0.8, 0.8, 0.8)
        GameTooltip:Hide()
    end)
    gear:SetScript("OnClick", ToggleGuide)

    -- list (mouse-wheel scrolling with a thin thumb)
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 12, -36)
    scroll:SetPoint("BOTTOMRIGHT", -22, 74)
    scroll:EnableMouseWheel(true)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(226, 1)
    scroll:SetScrollChild(f.content)

    local thumb = Texture(f, "ARTWORK", C.gold, 0.5)
    thumb:Hide()
    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange()
        if not range or range <= 0 then thumb:Hide() return end
        local viewH = scroll:GetHeight()
        local thumbH = max(24, viewH * viewH / (viewH + range))
        local y = (scroll:GetVerticalScroll() / range) * (viewH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetSize(3, thumbH)
        thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -y)
        thumb:Show()
    end
    scroll:SetScript("OnMouseWheel", function(s, delta)
        s:SetVerticalScroll(max(0, min(s:GetVerticalScroll() - delta * 28, s:GetVerticalScrollRange())))
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)

    body = Text(f.content, 11, C.text)
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetWidth(226)
    body:SetJustifyV("TOP")
    body:SetSpacing(2)

    status = Text(f, 11, C.text)
    status:SetPoint("BOTTOMLEFT", 12, 54)
    hint = Text(f, 10, C.dim)
    hint:SetPoint("BOTTOMLEFT", 12, 40)
    hint:SetWidth(236)

    local btnClear = FlatButton(f, 50, "Clear")
    btnClear:SetPoint("BOTTOMLEFT", 12, 12)
    btnClear:SetScript("OnClick", ResetData)
    btnRules = FlatButton(f, 50, "Rules")
    btnRules:SetPoint("LEFT", btnClear, "RIGHT", 5, 0)
    btnRules:SetScript("OnClick", AnnounceRules)
    btnAnnounce = FlatButton(f, 112, "Announce Winner")
    btnAnnounce:SetPoint("BOTTOMRIGHT", -12, 12)
    btnAnnounce:SetScript("OnClick", function() Announce(false) end)

    for _, e in ipairs(CHAT_EVENTS) do SafeRegister(f, e) end
    SafeRegister(f, "CHAT_MSG_SYSTEM")
    for _, e in ipairs(ROSTER_EVENTS) do SafeRegister(f, e) end
    f:SetScript("OnEvent", function(_, event, msg, sender)
        if event == "CHAT_MSG_SYSTEM" then
            OnSystemMessage(msg)
        elseif event:find("^CHAT_MSG_") then
            OnGroupChat(msg, sender)
        else
            CheckGroupStatus()
        end
    end)
end

function RT:Toggle()
    if not frame then return end
    if frame:IsShown() then
        manualOpen = false
        frame:Hide()
    else
        manualOpen = true
        frame:Show()
        Refresh()
    end
end

--------------------------------------------------------------------------------
-- Settings page in /cui
--------------------------------------------------------------------------------
if CysUI and CysUI.RegisterPage and CysUI.W then
    CysUI:RegisterPage("Roll Tracker", function(page)
        local W = CysUI.W
        local header = W.Header(page, "Roll Tracker", 480)
        header:SetPoint("TOPLEFT", 0, -4)
        local cb = W.Checkbox(page, "Announce the winner automatically in raids",
            function() return DB.raidAutoAnnounce end, function(on) DB.raidAutoAnnounce = on end)
        cb:SetPoint("TOPLEFT", 4, -34)
        local step = W.Stepper(page, "Raid roll window", function() return DB.raidWindow end,
            function(v) DB.raidWindow = v end, 5, 60, 5, "s")
        step:SetPoint("TOPLEFT", 4, -68)
    local note = W.Notes(page, 4, -108, 480, "", {
            "In a raid the winner is announced this many seconds after the first roll of a round (or sooner if everyone answered).",
            "Only the raid leader, assistants and master looter announce.",
            "In a party nothing changes: it announces as soon as everyone has rolled or passed.",
        })
    end)
end

--------------------------------------------------------------------------------
-- Startup, slash command, changelog
--------------------------------------------------------------------------------
local starter = CreateFrame("Frame")
starter:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    CysRollTrackerDB = CysRollTrackerDB or {}
    for k, v in pairs(DEFAULTS) do
        if CysRollTrackerDB[k] == nil then CysRollTrackerDB[k] = v end
    end
    DB = CysRollTrackerDB
    CreateFrames()
end)

-- Cys's UI runs this file after its settings load, so start up right away
starter:GetScript("OnEvent")(starter, "ADDON_LOADED", ADDON_NAME)

SLASH_CYSROLLTRACKER1 = "/crt"
SLASH_CYSROLLTRACKER2 = "/cysrolltracker"
SlashCmdList["CYSROLLTRACKER"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "clear" or msg == "reset" then
        ResetData()
        Say("Cleared.")
    elseif msg == "announce" then
        Announce(false)
    elseif msg == "status" then
        Say(format("in group: %s | raid: %s | members: %d", tostring(IsInGroup and IsInGroup() or false),
            tostring(IsInRaid()), GroupSize()))
        Say(format("leader: %s | assistant: %s | master looter: %s", tostring(IsLeader()),
            tostring(IsAssistant()), tostring(IsMasterLooter())))
        Say(format("may announce: %s | channel: %s", tostring(CanAnnounce()),
            (IsInGroup and IsInGroup()) and (IsInRaid() and "RAID" or "PARTY") or "none"))
    else
        RT:Toggle()
    end
end
end,
})
