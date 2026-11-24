--------------------------------------------------------------------------------
-- Cys's UI - PvP Timers
--
-- Small bars that count down what matters in PvP:
--   * your PvP flag (the 5 minutes before it drops after you leave a PvP area or stop fighting)
--   * battleground queue: time waited, and the time left to enter once it pops
--   * battleground start (the "begins in 1 minute" countdown)
--   * Arathi Basin bases and Alterac Valley towers / graveyards being taken (who is taking it, time left)
--   * the Spirit Healer's next resurrection wave while you wait as a ghost
-- Placed in Layout mode (PvP Timers). /cuipvp test shows sample bars.
-- Battleground messages are read in English.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "pvptimers", name = "PvP Timers",
    desc = "Countdown bars for your PvP flag, battleground queues and start, base and tower captures, and the Spirit Healer's next resurrection.",
    open = function() CysUI:OpenConfig("PvP Timers") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Compat = CysUICompat
local floor, max, min = math.floor, math.max, math.min

CysUIDB.pvptimers = CysUIDB.pvptimers or {}
local db = CysUIDB.pvptimers
for k, v in pairs({ flag = true, queue = true, start = true, nodes = true, rez = true, width = 220 }) do
    if db[k] == nil then db[k] = v end
end

local MAXBARS = 8
local BAR_H, GAP = 18, 3
local MOVER = "pvptimers"

local AB, AV = 529, 30          -- instance map IDs
local AB_CAP, AV_CAP = 60, 300  -- seconds from assault to capture

local COLORS = {
    Alliance = { 0.25, 0.55, 1 },
    Horde    = { 0.9, 0.2, 0.2 },
    flag     = { 1, 0.82, 0 },
    rez      = { 0.6, 0.9, 1 },
    neutral  = { 0.85, 0.64, 0.13 },
}

local function Secret(v) return Compat and Compat.Secret and Compat.Secret(v) end
local function Clock(s)
    s = max(0, floor(s + 0.5))
    if s >= 3600 then return format("%d:%02d:%02d", floor(s / 3600), floor(s % 3600 / 60), s % 60) end
    return format("%d:%02d", floor(s / 60), s % 60)
end

--------------------------------------------------------------------------------
-- Frame + bars
--------------------------------------------------------------------------------
local f = CreateFrame("Frame", "CysPvPTimersFrame", UIParent)
f:SetSize(db.width, MAXBARS * (BAR_H + GAP))
f:SetPoint("TOP", UIParent, "TOP", 0, -180)
f:SetFrameStrata("MEDIUM")
CUI:RegisterMovable(f, MOVER, "PvP Timers", { point = "TOP", x = 0, y = -180 })

local bars = {}
local function Bar(i)
    if bars[i] then return bars[i] end
    local b = CreateFrame("StatusBar", nil, f)
    b:SetSize(db.width, BAR_H)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * (BAR_H + GAP))
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    b:SetMinMaxValues(0, 1)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.85)
    W.Border(b, 1, T.border, "OVERLAY")
    b.name = W.Text(b, 11, { 1, 1, 1 }, "LEFT")
    b.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.name:SetPoint("LEFT", 5, 0)
    b.name:SetPoint("RIGHT", -48, 0)
    b.name:SetWordWrap(false)
    b.time = W.Text(b, 11, { 1, 1, 1 }, "RIGHT")
    b.time:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.time:SetPoint("RIGHT", -5, 0)
    bars[i] = b
    return b
end

local function SetWidth(w)
    f:SetWidth(w)
    for _, b in ipairs(bars) do b:SetWidth(w) end
end

--------------------------------------------------------------------------------
-- Timers from battleground messages: { key, label, color, ends, total }
--------------------------------------------------------------------------------
local timers = {}
local test = nil

local function Add(key, label, color, secs)
    timers[key] = { label = label, color = color, ends = GetTime() + secs, total = secs }
end
local function Drop(key) timers[key] = nil end
local function ClearBG() wipe(timers) end

local function MapID()
    local _, kind, _, _, _, _, _, id = GetInstanceInfo()
    return kind == "pvp" and id or nil
end

local function Trim(s) return (s or ""):gsub("^[Tt]he ", ""):gsub("%s+$", "") end

local function OnStart(msg)
    if not msg:lower():find("begin") then return end
    local n = msg:match("(%d+) minute")
    local secs = n and tonumber(n) * 60
    if not secs then n = msg:match("(%d+) second") secs = n and tonumber(n) end
    if not secs and msg:lower():find("half a minute") then secs = 30 end
    if secs then Add("start", "Battle begins", COLORS.neutral, secs) end
end

local function OnNode(msg, side)
    local id = MapID()
    local node
    -- taken over / held: the timer is done
    node = msg:match("has defended the (.-)!") or msg:match("has taken the (.-)!")
        or msg:match("^(.-) was taken by") or msg:match("^(.-) was destroyed by")
    if node then Drop("node:" .. Trim(node)) return end

    local secs
    if id == AB then
        node = msg:match("has assaulted the (.-)!") or msg:match("claims the (.-)!")
        secs = AB_CAP
    elseif id == AV then
        node = msg:match("^(.-) is under attack")
        secs = AV_CAP
    end
    if not node then
        -- any other battleground that says how long: "... in 1 minute!"
        local m = msg:match("in (%d+) minute")
        if m then node, secs = msg:match("the (.-)!") or "Objective", tonumber(m) * 60 end
    end
    if node and secs then
        node = Trim(node)
        Add("node:" .. node, format("%s (%s)", node, side), COLORS[side] or COLORS.neutral, secs)
    end
end

--------------------------------------------------------------------------------
-- Gather what to show
--------------------------------------------------------------------------------
local list = {}
local function Collect()
    wipe(list)
    local now = GetTime()
    if test then
        for _, t in ipairs(test) do list[#list + 1] = t end
        return
    end

    if db.flag and IsPVPTimerRunning and IsPVPTimerRunning() then
        local ms = GetPVPTimer and GetPVPTimer()
        if type(ms) == "number" and ms > 0 then
            list[#list + 1] = { label = "PvP flag drops", color = COLORS.flag, left = ms / 1000, total = 300 }
        end
    end

    if db.queue and GetMaxBattlefieldID then
        for i = 1, GetMaxBattlefieldID() do
            local status, map = GetBattlefieldStatus(i)
            if status == "confirm" and GetBattlefieldPortExpiration then
                local left = GetBattlefieldPortExpiration(i)
                if type(left) == "number" and left > 0 then
                    list[#list + 1] = { label = "Enter " .. (map or "battleground"), color = COLORS.flag, left = left, total = 90, urgent = true }
                end
            elseif status == "queued" then
                local waited = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i) or 0
                local est = GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(i) or 0
                local label = "Queue: " .. (map or "battleground")
                if est and est > 0 then label = label .. format(" (est. %s)", Clock(est / 1000)) end
                list[#list + 1] = { label = label, color = COLORS.neutral, up = (waited or 0) / 1000,
                                    total = (est and est > 0) and est / 1000 or nil }
            end
        end
    end

    if db.rez and UnitIsGhost("player") and GetAreaSpiritHealerTime then
        local left = GetAreaSpiritHealerTime()
        if type(left) == "number" and left > 0 then
            list[#list + 1] = { label = "Resurrection", color = COLORS.rez, left = left, total = 30 }
        end
    end

    for key, t in pairs(timers) do
        local left = t.ends - now
        if left <= 0 then
            timers[key] = nil
        elseif (key == "start" and db.start) or (key ~= "start" and db.nodes) then
            list[#list + 1] = { label = t.label, color = t.color, left = left, total = t.total }
        end
    end
    table.sort(list, function(a, b) return (a.left or 1e9) < (b.left or 1e9) end)
end

local function Paint()
    Collect()
    local n = min(#list, MAXBARS)
    for i = 1, n do
        local t, b = list[i], Bar(i)
        local c = t.color
        b:SetStatusBarColor(c[1], c[2], c[3], 0.75)
        b.name:SetText(t.label)
        if t.up then
            b.time:SetText(Clock(t.up))
            b:SetValue(t.total and min(1, t.up / t.total) or 1)
        else
            b.time:SetText(Clock(t.left))
            b:SetValue(t.total and min(1, t.left / t.total) or 1)
            if t.urgent and t.left < 15 then b.time:SetTextColor(1, 0.3, 0.3) else b.time:SetTextColor(1, 1, 1) end
        end
        b:Show()
    end
    for i = n + 1, #bars do bars[i]:Hide() end
end

local acc = 0
f:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.2 then return end
    acc = 0
    Paint()
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
                     "CHAT_MSG_BG_SYSTEM_HORDE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, msg)
    if e == "PLAYER_ENTERING_WORLD" then
        if not MapID() then ClearBG() end
        return
    end
    if type(msg) ~= "string" or Secret(msg) then return end
    if e == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        OnStart(msg)
    elseif e == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then
        OnNode(msg, "Alliance")
    else
        OnNode(msg, "Horde")
    end
end)

local SAMPLE = {
    { label = "PvP flag drops", color = COLORS.flag, left = 212, total = 300 },
    { label = "Stables (Horde)", color = COLORS.Horde, left = 41, total = 60 },
    { label = "Lumber Mill (Alliance)", color = COLORS.Alliance, left = 18, total = 60 },
    { label = "Resurrection", color = COLORS.rez, left = 9, total = 30 },
}
local function Test(on)
    if on == nil then on = not test end
    test = on and SAMPLE or nil
    Paint()
end
local wasLayout
hooksecurefunc(CUI, "SetLayoutMode", function(_, on)
    if on then wasLayout = not test Test(true) elseif wasLayout then wasLayout = nil Test(false) end
end)

SLASH_CYSUIPVP1 = "/cuipvp"
SlashCmdList.CYSUIPVP = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "test" then
        Test()
        CUI:Print(test and "PvP Timers: sample bars on (/cuipvp test again hides them)." or "PvP Timers: sample bars off.")
    else
        CUI:Print("/cuipvp test - show sample bars to place them (or use Layout mode, PvP Timers).")
    end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("PvP Timers", function(page)
    local width = 480
    W.Header(page, "PvP Timers", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    for _, o in ipairs({
        { "flag",  "My PvP flag (time until it drops)" },
        { "queue", "Battleground queue (time waited, time left to enter)" },
        { "start", "Battleground start countdown" },
        { "nodes", "Bases, towers and graveyards being taken (Arathi Basin, Alterac Valley)" },
        { "rez",   "Spirit Healer's next resurrection (as a ghost)" },
    }) do
        local key = o[1]
        W.Checkbox(page, o[2], function() return db[key] end, function(on) db[key] = on Paint() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    W.Stepper(page, "Bar width", function() return db.width end,
        function(v) db.width = v SetWidth(v) end, 140, 360, 10, ""):SetPoint("TOPLEFT", 4, y - 4)

    local tb = W.Button(page, 150, 22, "Show sample bars")
    tb:SetPoint("TOPLEFT", 4, y - 42)
    tb:SetScript("OnClick", function(self)
        Test()
        self:SetText(test and "Hide sample bars" or "Show sample bars")
    end)

    W.Notes(page, 4, y - 84, width, "", {
        "Move the bars in Layout mode (PvP Timers); they show sample bars while it is open.",
        "Arathi Basin bases take 1 minute, Alterac Valley towers and graveyards 5 minutes. The bar is colored by the side taking it and goes away when it is taken or defended.",
        "/cuipvp test shows or hides the sample bars.",
    })
end)

    end,
})
