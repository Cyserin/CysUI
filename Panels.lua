--------------------------------------------------------------------------------
-- Window stacking: Cys's UI windows join Blizzard's own window layout, so they open side by side with the
-- character window, spellbook, quest log, map and the rest instead of piling on top of each other. Blizzard
-- decides like it does for its own windows: a window opens in the next free spot, pushes others over, or
-- closes the one in its spot when there is no room.
--
-- How: each window gets Blizzard's "UIPanelLayout" attributes (area, pushable) on itself and is opened
-- with ShowUIPanel. Only our own frames are touched; no Blizzard table or function is changed.
-- In combat Blizzard won't move windows, so a window opened then just shows where it last was.
-- Switch: /cui > General > "Open windows side by side like Blizzard's" (reload to apply).
--------------------------------------------------------------------------------
local CUI = CysUI

local SLOTS = { "left", "center", "right", "doublewide", "fullscreen" }
local managed = {}

local function Enabled()
    return not (CysUIDB and CysUIDB.stackWindows == false)
end

local function Available()
    return ShowUIPanel and HideUIPanel and GetUIPanel and true or false
end

-- which of Blizzard's window spots this frame sits in, if any
local function SlotOf(frame)
    if not GetUIPanel then return nil end
    for _, key in ipairs(SLOTS) do
        local ok, f = pcall(GetUIPanel, key)
        if ok and f == frame then return key end
    end
    return nil
end

-- A window closed with a plain Hide() (an X button, or code that hides it) still holds its spot in Blizzard's
-- layout. WoW Forever cleans that up on its own; Classic Era doesn't, so give the spot back the way Blizzard
-- expects: show it for an instant (invisible) and close it through HideUIPanel. Done a moment later, never
-- while Blizzard's own layout code is still running, and never in combat.
local function FreeSpot(frame)
    if CysUICompat and CysUICompat.isForever then return end
    if InCombatLockdown() or frame:IsShown() or not SlotOf(frame) then return end
    local alpha = frame:GetAlpha()
    frame:SetAlpha(0)
    frame:Show()
    pcall(HideUIPanel, frame)
    if frame:IsShown() then frame:Hide() end
    frame:SetAlpha(alpha)
end

-- Register one of our windows. area: "left", "center" or "right". pushable: like Blizzard's (0 = stays put).
function CUI:ManageWindow(frame, area, pushable, extra)
    if not (frame and frame.GetName and frame:GetName() and frame.SetAttribute) then return end
    if managed[frame] or not Enabled() or not Available() then return end
    managed[frame] = true
    frame:SetAttribute("UIPanelLayout-defined", true)
    frame:SetAttribute("UIPanelLayout-enabled", true)
    frame:SetAttribute("UIPanelLayout-area", area or "left")
    frame:SetAttribute("UIPanelLayout-pushable", pushable or 0)
    frame:SetAttribute("UIPanelLayout-whileDead", true)
    if extra then
        for k, v in pairs(extra) do frame:SetAttribute("UIPanelLayout-" .. k, v) end
    end
    frame:HookScript("OnHide", function(self)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() FreeSpot(self) end) end
    end)
end

function CUI:IsManagedWindow(frame)
    return managed[frame] == true
end

-- Open / close / toggle one of our windows. Falls back to a plain Show/Hide when the window isn't managed,
-- in combat, or when Blizzard refuses to place it (the shop is open, and so on).
function CUI:ShowWindow(frame)
    if not frame or frame:IsShown() then return end
    if managed[frame] and not InCombatLockdown() then
        pcall(ShowUIPanel, frame)
        if frame:IsShown() then return end
    end
    frame:Show()
end

function CUI:HideWindow(frame)
    if not frame or not frame:IsShown() then return end
    if managed[frame] and not InCombatLockdown() and SlotOf(frame) then
        pcall(HideUIPanel, frame)
        if not frame:IsShown() then return end
    end
    frame:Hide()
end

function CUI:ToggleWindow(frame)
    if not frame then return end
    if frame:IsShown() then self:HideWindow(frame) else self:ShowWindow(frame) end
end

-- after combat: hand back the spots of windows that were closed during the fight
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function()
        for frame in pairs(managed) do FreeSpot(frame) end
    end)
end
