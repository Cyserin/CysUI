--------------------------------------------------------------------------------
-- Cys's UI - Vehicle Exit button (WoW Forever)
--
-- Our own Leave button for vehicles and flight paths, placed in Layout mode (Vehicle Exit). It does what the
-- game's button does: on a flight path it asks to land early, otherwise it leaves the vehicle. The game's own
-- button is only faded and made click-through (never moved or hidden), so its Edit Mode spot is untouched.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "vehicleexit", name = "Vehicle Exit Button", foreverOnly = true,
    desc = "WoW Forever: a Leave button for vehicles and flight paths that you place yourself in Layout mode.",
    open = function() CysUI:OpenConfig("Vehicle Exit") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

CysUIDB.vehicleexit = CysUIDB.vehicleexit or {}
local db = CysUIDB.vehicleexit
if db.size == nil then db.size = 36 end

local MOVER = "vehicleexit"
local ICON = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up"

local b = CreateFrame("Button", "CysVehicleExitButton", UIParent)
b:SetSize(db.size, db.size)
b:SetPoint("BOTTOM", UIParent, "BOTTOM", -260, 110)
b:SetFrameStrata("MEDIUM")
b:SetFrameLevel(20)
b:RegisterForClicks("LeftButtonUp")
local back = b:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints()
back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.9)
local icon = b:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 1, -1)
icon:SetPoint("BOTTOMRIGHT", -1, 1)
icon:SetTexture(ICON)
icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
local edge = CreateFrame("Frame", nil, b)
edge:SetAllPoints()
W.Border(edge, 1, T.border, "OVERLAY")
local hl = b:CreateTexture(nil, "HIGHLIGHT")
hl:SetAllPoints(icon)
hl:SetColorTexture(1, 1, 1, 0.15)
b:SetAlpha(0)
b:EnableMouse(false)

CUI:RegisterMovable(b, MOVER, "Vehicle Exit", { point = "BOTTOM", x = -260, y = 110 })

local landing = false
local function CanLeave()
    local ok, can = pcall(CanExitVehicle)
    if ok and can then return true end
    return UnitOnTaxi and UnitOnTaxi("player") or false
end

-- faded, not hidden, so its Layout mode box keeps working
local function Update()
    local show = CanLeave()
    if not show then landing = false end
    local visible = show or CUI.layoutMode
    b:SetAlpha(visible and 1 or 0)
    b:EnableMouse(show and true or false)
    icon:SetDesaturated(landing)
end

b:SetScript("OnClick", function()
    if UnitOnTaxi and UnitOnTaxi("player") then
        if TaxiRequestEarlyLanding then pcall(TaxiRequestEarlyLanding) end
        landing = true -- greyed until you land: the request went through
        Update()
    elseif VehicleExit then
        pcall(VehicleExit)
    end
end)
b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if UnitOnTaxi and UnitOnTaxi("player") then
        GameTooltip:SetText(TAXI_CANCEL or "Request Stop", 1, 1, 1)
        if TAXI_CANCEL_DESCRIPTION then GameTooltip:AddLine(TAXI_CANCEL_DESCRIPTION, 1, 0.82, 0, true) end
    else
        GameTooltip:SetText(LEAVE_VEHICLE or "Leave", 1, 1, 1)
    end
    GameTooltip:Show()
end)
b:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- the game's own button: faded and click-through (alpha and mouse only)
local function QuietBlizzard()
    local g = _G.MainMenuBarVehicleLeaveButton
    if not g then return end
    g:SetAlpha(0)
    if not InCombatLockdown() then pcall(g.EnableMouse, g, false) end
    if not g.cysHooked then
        g.cysHooked = true
        hooksecurefunc(g, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
        g:HookScript("OnShow", function(self)
            self:SetAlpha(0)
            if not InCombatLockdown() then pcall(self.EnableMouse, self, false) end
        end)
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "VEHICLE_UPDATE",
                     "UPDATE_BONUS_ACTIONBAR", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "UPDATE_MULTI_CAST_ACTIONBAR" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" then QuietBlizzard() end
    Update()
    C_Timer.After(0.3, Update) -- taxi state settles a moment after control changes
end)
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", Update) end
QuietBlizzard()
Update()

CUI:RegisterPage("Vehicle Exit", function(page)
    local width = 480
    W.Header(page, "Vehicle Exit", width):SetPoint("TOPLEFT", 0, -4)
    W.Stepper(page, "Button size", function() return db.size end, function(v)
        db.size = v
        b:SetSize(v, v)
        CUI:ApplyLayout(MOVER)
    end, 20, 64, 2, " px"):SetPoint("TOPLEFT", 4, -34)
    W.Notes(page, 4, -74, width, "", {
        "A Leave button that shows while you are in a vehicle or on a flight path. On a flight path it asks to land at the next stop.",
        "Move it in Layout mode (Vehicle Exit). The game's own button is faded and made click-through while this module is on.",
    })
end, function() end)

    end,
})
