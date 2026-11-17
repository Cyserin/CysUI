--------------------------------------------------------------------------------
-- Cys's UI - Flight Timer
--
-- While you are on a flight path: where you left from on the left, where you are going on the right, a line
-- between them that fills as you get closer, and the time left above its middle.
--
-- Flight times are not something the game tells addons, so they are learned: the first time you fly a route it
-- is timed (the bar shows the time flown so far), and from then on that route counts down. Times are saved for
-- the whole account. A flight you cut short (Request Stop) is not saved.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "flight", name = "Flight Timer",
    desc = "On a flight path: start on the left, destination on the right, a line that fills as you get closer and the time left. Times are learned as you fly.",
    open = function() CysUI:OpenConfig("Flight Timer") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

CysUIDB.flight = CysUIDB.flight or {}
local db = CysUIDB.flight
db.times = db.times or {}   -- ["From>To"] = seconds
if db.width == nil then db.width = 300 end

local MOVER = "flight"
local format, floor, max, min = string.format, math.floor, math.max, math.min

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------
local f = CreateFrame("Frame", "CysFlightBar", UIParent)
f:SetSize(db.width, 30)
f:SetPoint("TOP", UIParent, "TOP", 0, -150)
f:SetFrameStrata("MEDIUM")
f:SetAlpha(0)

local from = W.Text(f, 11, T.text)
from:SetPoint("TOPLEFT", 0, 0)
from:SetWordWrap(false)
local to = W.Text(f, 11, T.text, "RIGHT")
to:SetPoint("TOPRIGHT", 0, 0)
to:SetWordWrap(false)
local timer = W.Text(f, 13, T.accent, "CENTER")
timer:SetPoint("TOP", 0, 2)

local bar = CreateFrame("StatusBar", nil, f)
bar:SetPoint("BOTTOMLEFT", 0, 0)
bar:SetPoint("BOTTOMRIGHT", 0, 0)
bar:SetHeight(8)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(T.brand[1], T.brand[2], T.brand[3], 1)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
W.Texture(bar, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
W.Border(bar, 1, T.line, "OVERLAY")

local function Fit()
    f:SetWidth(db.width)
    local side = max(40, (db.width - 70) / 2) -- the names leave the middle to the time
    from:SetWidth(side)
    to:SetWidth(side)
end
Fit()

CUI:RegisterMovable(f, MOVER, "Flight Timer", { point = "TOP", x = 0, y = -150 })

--------------------------------------------------------------------------------
-- Which flight
--------------------------------------------------------------------------------
local nodes, here = {}, nil -- flight map as last seen: [slot] = name, and the stop you are standing at
local flight                -- { src, dst, start (GetTime), known (seconds or nil), early, test }
local pending               -- a flight just picked on the map, waiting for take-off

local function Short(name)
    if type(name) ~= "string" then return "?" end
    return (name:match("^(.-),")) or name -- "Thelsamar, Loch Modan" -> "Thelsamar"
end
local function Clock(s)
    s = max(0, floor(s + 0.5))
    return format("%d:%02d", floor(s / 60), s % 60)
end

local function ReadMap()
    wipe(nodes)
    here = nil
    local ok = pcall(function()
        if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
            local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current
            for _, n in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) or {}) do
                if n.slotIndex and n.name then
                    nodes[n.slotIndex] = n.name
                    if current ~= nil and n.state == current then here = n.name end
                end
            end
        end
    end)
    if (not ok or not here) and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        pcall(function()
            for i = 1, NumTaxiNodes() do
                nodes[i] = nodes[i] or TaxiNodeName(i)
                if TaxiNodeGetType(i) == "CURRENT" then here = TaxiNodeName(i) end
            end
        end)
    end
end

local function Paint()
    if not flight then
        if CUI.layoutMode then
            from:SetText("Start"); to:SetText("Destination"); timer:SetText("1:23")
            bar:SetValue(0.4)
            f:SetAlpha(1)
        else
            f:SetAlpha(0)
        end
        return
    end
    f:SetAlpha(1)
    from:SetText(Short(flight.src))
    to:SetText(flight.early and "Next stop" or Short(flight.dst))
end

local function Stop(save)
    if flight and save and not flight.early and not flight.test and not flight.resumed and flight.src and flight.dst then
        local took = GetTime() - flight.start
        if took > 5 then db.times[flight.src .. ">" .. flight.dst] = floor(took * 10 + 0.5) / 10 end
    end
    flight = nil
    db.current = nil
    f:SetScript("OnUpdate", nil)
    Paint()
end

local acc = 0
local function Tick(_, elapsed)
    if not flight then return end
    local now = GetTime()
    local flown = now - flight.start
    acc = acc + elapsed
    if acc >= 0.2 then
        acc = 0
        if flight.test then
            if flown >= flight.known then Stop(false) return end
        elseif flight.air then
            if not UnitOnTaxi("player") then Stop(true) return end
        elseif UnitOnTaxi("player") then
            flight.air = true -- wheels up: the clock starts here
            flight.start = now
            flown = 0
            if not flight.resumed then db.current = { src = flight.src, dst = flight.dst, at = GetServerTime() } end
        elseif flown > 8 then
            Stop(false) -- never took off (not enough money, walked away)
            return
        end
        if flight.known and not flight.early then
            timer:SetText(Clock(flight.known - flown))
        else
            timer:SetText(Clock(flown))
        end
    end
    if flight.known and not flight.early then
        bar:SetValue(min(1, flown / flight.known))
    else
        bar:SetValue(0)
    end
end

local function Start(src, dst, opts)
    flight = { src = src, dst = dst, start = GetTime(), known = db.times[src .. ">" .. dst] }
    for k, v in pairs(opts or {}) do flight[k] = v end
    acc = 1
    Paint()
    f:SetScript("OnUpdate", Tick)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
if type(TakeTaxiNode) == "function" then
    hooksecurefunc("TakeTaxiNode", function(slot)
        if not nodes[slot] then pcall(ReadMap) end
        local dst = nodes[slot]
        if here and dst and not (flight and flight.air) then Start(here, dst) end
    end)
end
if type(TaxiRequestEarlyLanding) == "function" then
    hooksecurefunc("TaxiRequestEarlyLanding", function()
        if flight and not flight.test then flight.early = true; Paint() end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, e)
    if e == "TAXIMAP_OPENED" then
        pcall(ReadMap)
        C_Timer.After(0.3, function() pcall(ReadMap) end) -- the map fills in a moment after it opens
    elseif not flight then
        -- logged in or reloaded in the air: pick the flight up again from what was saved at take-off
        local c = db.current
        if c and UnitOnTaxi and UnitOnTaxi("player") and c.src and c.dst and c.at then
            local gone = GetServerTime() - c.at
            Start(c.src, c.dst, { air = true, resumed = true })
            flight.start = GetTime() - max(0, gone)
        else
            db.current = nil
        end
    end
end)
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", Paint) end
Paint()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Flight Timer", function(page)
    local width = 480
    W.Header(page, "Flight Timer", width):SetPoint("TOPLEFT", 0, -4)
    W.Stepper(page, "Bar width", function() return db.width end, function(v)
        db.width = v
        Fit()
        CUI:ApplyLayout(MOVER)
    end, 160, 600, 10, " px"):SetPoint("TOPLEFT", 4, -34)

    local test = W.Button(page, 150, 22, "Show a test flight")
    test:SetPoint("TOPLEFT", 4, -68)
    test:SetScript("OnClick", function()
        if flight and not flight.test then return end
        Start("Stormwind, Elwynn", "Ironforge, Dun Morogh", { test = true, known = 20, air = true })
    end)

    local count = W.Text(page, 12, T.text)
    count:SetPoint("LEFT", test, "RIGHT", 12, 0)
    local function Count()
        local n = 0
        for _ in pairs(db.times) do n = n + 1 end
        count:SetText(n .. (n == 1 and " route learned" or " routes learned"))
    end
    local forget = W.Button(page, 150, 22, "Forget learned times")
    forget:SetPoint("TOPLEFT", 4, -98)
    forget:SetScript("OnClick", function(self)
        if not self.armed then self.armed = true; self:SetLabel("Click again to forget"); return end
        self.armed = nil
        self:SetLabel("Forget learned times")
        wipe(db.times)
        Count()
    end)
    page:HookScript("OnShow", Count)
    Count()

    W.Notes(page, 4, -136, width, "", {
        "Shows only while you are on a flight path. Move it in Layout mode (Flight Timer).",
        "The game does not tell addons how long a flight takes, so each route is timed the first time you fly it: that flight shows the time flown so far, and every flight after it counts down.",
        "Times are shared by all your characters. A flight you cut short with Request Stop is not saved.",
    })
end, function() end)

    end,
})
