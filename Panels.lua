--------------------------------------------------------------------------------
-- Window stacking: Cys's UI windows open beside Blizzard's own windows (character, spellbook, quest log, map,
-- bank...) instead of on top of them, and beside each other.
--
-- How: Blizzard's windows are only LOOKED at (GetUIPanel tells which are open, GetRight where they end); ours are
-- then placed to the right of them, in the order they were opened. Nothing is handed to Blizzard's own window
-- manager: doing that leaves addon "taint" inside it, and then Blizzard's protected actions that run when its own
-- windows open (like the bank buying its free first tab) get blocked.
-- Our windows are plain frames, so they can be placed in combat too.
-- Switch: /cui > General > "Open windows side by side like Blizzard's" (reload to apply).
--------------------------------------------------------------------------------
local CUI = CysUI

local SLOTS = { "left", "center", "right", "doublewide", "fullscreen" }
local LEFT_OFFSET, TOP_OFFSET, GAP = 16, -104, 8
local managed, order = {}, {}

local function Enabled()
    return not (CysUIDB and CysUIDB.stackWindows == false)
end

-- right edge (in UIParent units) of the Blizzard windows that are open right now, or nil
-- short-lived panels our windows should not move aside for (looting would shuffle them left and back)
local IGNORE = { LootFrame = true, GroupLootHistoryFrame = true, StackSplitFrame = true }

local function BlizzardRightEdge()
    if not GetUIPanel then return nil end
    local edge
    local uiScale = UIParent:GetEffectiveScale() or 1
    for _, key in ipairs(SLOTS) do
        local ok, f = pcall(GetUIPanel, key)
        local okN, name = pcall(function() return f and f.GetName and f:GetName() end)
        if ok and f and not managed[f] and not (okN and name and IGNORE[name]) and f.IsShown and f:IsShown() then
            local okR, r = pcall(f.GetRight, f)
            if okR and type(r) == "number" then
                r = r * (f:GetEffectiveScale() or 1) / uiScale
                if not edge or r > edge then edge = r end
            end
        end
    end
    return edge
end

-- put a window we moved aside back on its own spot (its layout position); dragged windows stay where they were put
local function GoHome(f)
    if not f.cysStacked or f.cysDragged then f.cysStacked = nil return end
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then return end
    for _, m in pairs(CUI.movers or {}) do
        if m.frame == f and m.mover then
            f:ClearAllPoints()
            f:SetPoint("CENTER", m.mover, "CENTER", 0, 0)
            break
        end
    end
    f.cysStacked = nil
end

local arranging = false
local function Arrange()
    if arranging or not Enabled() then return end
    -- only when a Blizzard window is open: on their own, our windows sit on their own spot (no jump to the left)
    local edge = BlizzardRightEdge()
    if not edge then
        for f in pairs(managed) do if f.cysStacked then GoHome(f) end end
        return
    end
    arranging = true
    local x = edge + GAP
    for _, f in ipairs(order) do
        if f:IsShown() and not f.cysDragged and not (f.IsProtected and f:IsProtected() and InCombatLockdown()) then
            local scale = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / scale, TOP_OFFSET / scale)
            f.cysStacked = true
            x = x + (f:GetWidth() or 0) * scale + GAP
        end
    end
    arranging = false
end

local function Later()
    if C_Timer and C_Timer.After then C_Timer.After(0, Arrange) else Arrange() end
end

-- Register one of our windows. (area / pushable are kept for older callers; they no longer change anything)
function CUI:ManageWindow(frame, area, pushable, extra)
    if not frame or managed[frame] or not Enabled() then return end
    managed[frame] = true
    frame:HookScript("OnShow", function(self)
        for i = #order, 1, -1 do if order[i] == self then table.remove(order, i) end end
        order[#order + 1] = self -- newest opens furthest right
        Arrange() -- right away, so the window doesn't show in its old spot first
        Later()
    end)
    frame:HookScript("OnHide", function(self)
        self.cysDragged = nil -- dragged by hand: stacks again next time it opens
        for i = #order, 1, -1 do if order[i] == self then table.remove(order, i) end end
        GoHome(self) -- next time it opens on its own spot, not where it was moved aside to
        Later()
    end)
end

function CUI:IsManagedWindow(frame)
    return managed[frame] == true
end

function CUI:ShowWindow(frame)
    if frame and not frame:IsShown() then frame:Show() end
end

function CUI:HideWindow(frame)
    if frame and frame:IsShown() then frame:Hide() end
end

function CUI:ToggleWindow(frame)
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Blizzard's windows opening or closing move ours along (post-hooks only: nothing of Blizzard's is changed)
if hooksecurefunc then
    if ShowUIPanel then hooksecurefunc("ShowUIPanel", Later) end
    if HideUIPanel then hooksecurefunc("HideUIPanel", Later) end
    if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", Later) end
end
