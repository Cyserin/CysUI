--------------------------------------------------------------------------------
-- Cys's UI - layout mode
--
-- Any Cys UI frame can be made movable / resizable / scalable by the player
-- (add keepSquare = true to resizable elements that must stay square):
--
--   CysUI:RegisterMovable(frame, "infobar", "Info Bar", {
--       point = "BOTTOM", x = 0, y = 4,        -- default spot (relative to the screen)
--       resizable = true, minW = 300, maxW = 1800, minH = 18, maxH = 40,
--       onResize = function(frame, w, h) ... end,   -- re-layout the frame's insides
--   })
--
-- Type /cui layout (or press Unlock on the General page): every registered frame gets a
-- gold box. Drag a box to move it; click one to fine-tune X / Y / size / scale in the
-- panel. Positions save per element, "Reset" puts one (or everything) back to default.
--
-- How it works: each frame is anchored to an invisible "mover" frame that lives directly
-- under UIParent at scale 1, so saved offsets are always simple screen coordinates.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, max, min = math.floor, math.max, math.min

CUI.movers = CUI.movers or {}
CUI.moverOrder = CUI.moverOrder or {}

local selected -- key of the element being fine-tuned
local panel, guides

local function Layout()
    CysUIDB.layout = CysUIDB.layout or {}
    return CysUIDB.layout
end

local function Entry(key, create)
    local layout = Layout()
    if not layout[key] and create then layout[key] = {} end
    return layout[key]
end

-- where an element is right now: saved position, or the default it registered with
local function Position(m)
    local e = Entry(m.key)
    return (e and e.point) or m.defPoint, (e and e.x) or m.defX, (e and e.y) or m.defY
end

local function Scale(m)
    local e = Entry(m.key)
    return (e and e.scale) or 1
end

--------------------------------------------------------------------------------
-- Applying a saved layout
--------------------------------------------------------------------------------
function CUI:ApplyLayout(key)
    local m = self.movers[key]
    if not m then return end
    local e = Entry(key)
    local frame, mover = m.frame, m.mover

    if m.opts.resizable then
        local w = (e and e.width) or m.defW
        -- keepSquare elements (the minimap) have a single size: height always follows width
        frame:SetSize(w, m.opts.keepSquare and w or ((e and e.height) or m.defH))
    end
    local scale = Scale(m)
    frame:SetScale(scale)

    mover:SetSize(max(frame:GetWidth() * scale, 24), max(frame:GetHeight() * scale, 16))
    local point, x, y = Position(m)
    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, point, x, y)

    if m.opts.onResize then m.opts.onResize(frame, frame:GetWidth(), frame:GetHeight()) end
end

--------------------------------------------------------------------------------
-- Selection + editor panel
--------------------------------------------------------------------------------
local function SelectMover(key)
    selected = key
    for k, m in pairs(CUI.movers) do
        local on = (k == key)
        W.SetBorder(m.moverEdges, on and T.accent or T.border)
        m.moverFill:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], on and 0.38 or 0.2)
    end
    if panel then panel:RefreshAll() end
end

-- store where the mover ended up after a drag (always as an offset from the screen centre)
local function CaptureDrag(m)
    local cx, cy = m.mover:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    local x, y = cx - ux, cy - uy
    if CysUIDB.snap then
        local s = CysUIDB.snapSize or 8
        x, y = floor(x / s + 0.5) * s, floor(y / s + 0.5) * s
    end
    local e = Entry(m.key, true)
    e.point, e.x, e.y = "CENTER", x, y
    CUI:ApplyLayout(m.key)
    if panel then panel:RefreshAll() end
end

function CUI:RegisterMovable(frame, key, label, opts)
    opts = opts or {}
    if self.movers[key] then return self.movers[key] end
    local m = { frame = frame, key = key, label = label or key, opts = opts }
    m.defPoint, m.defX, m.defY = opts.point or "CENTER", opts.x or 0, opts.y or 0
    m.defW, m.defH = frame:GetWidth(), frame:GetHeight()
    self.movers[key] = m
    self.moverOrder[#self.moverOrder + 1] = key

    local mover = CreateFrame("Frame", "CysUIMover_" .. key, UIParent)
    m.mover = mover
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(50)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()
    m.moverFill = W.Texture(mover, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.2 })
    m.moverFill:SetAllPoints()
    m.moverEdges = W.Border(mover, 1, T.border, "BORDER")
    local text = W.Text(mover, 11, { 1, 1, 1 }, "CENTER") -- white with an outline so it reads on any background
    text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(m.label)

    mover:SetScript("OnMouseDown", function() SelectMover(key) end)
    mover:SetScript("OnDragStart", function(s) SelectMover(key); s:StartMoving() end)
    mover:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        CaptureDrag(m)
    end)

    -- the real frame follows its mover
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", mover, "CENTER", 0, 0)
    self:ApplyLayout(key)
    return m
end

function CUI:ResetMover(key)
    local m = self.movers[key]
    if not m then return end
    Layout()[key] = nil
    self:ApplyLayout(key)
    if panel then panel:RefreshAll() end
end

function CUI:ResetAllMovers()
    for _, key in ipairs(self.moverOrder) do
        Layout()[key] = nil
        self:ApplyLayout(key)
    end
    if panel then panel:RefreshAll() end
end

--------------------------------------------------------------------------------
-- The editor panel (built the first time layout mode opens)
--------------------------------------------------------------------------------
local function Current() return selected and CUI.movers[selected] end

local function BuildPanel()
    local f = CreateFrame("Frame", "CysUILayoutPanel", UIParent)
    f:SetSize(360, 300)
    f:SetPoint("TOP", UIParent, "TOP", 0, -90)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.Texture(f, "BACKGROUND", T.bg, 1):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local title = W.Text(f, 13, T.accent)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Layout mode")
    local help = W.Text(f, 11, T.desc)
    help:SetPoint("TOPLEFT", 14, -32)
    help:SetWidth(332)
    help:SetJustifyV("TOP")
    help:SetText("Drag a gold box to move it. Click one to fine-tune it below.")
    f.name = W.Text(f, 12, T.text)
    f.name:SetPoint("TOPLEFT", 14, -62)

    local function Edit(fn)
        local m = Current()
        if not m then return end
        local e = Entry(m.key, true)
        if not e.point then e.point, e.x, e.y = Position(m) end
        fn(e, m)
        CUI:ApplyLayout(m.key)
    end

    f.rows = {}
    local function AddRow(label, get, set, lo, hi, step, suffix, applies)
        local row = W.Stepper(f, label, get, set, lo, hi, step, suffix)
        row.applies = applies
        f.rows[#f.rows + 1] = row
    end
    -- current value of something for the selected element, rounded
    local function Num(fn)
        local m = Current()
        if not m then return 0 end
        return floor(fn(m) + 0.5)
    end

    AddRow("X position",
        function() return Num(function(m) local _, x = Position(m); return x end) end,
        function(v) Edit(function(e) e.x = v end) end, -4000, 4000, 1)
    AddRow("Y position",
        function() return Num(function(m) local _, _, y = Position(m); return y end) end,
        function(v) Edit(function(e) e.y = v end) end, -4000, 4000, 1)
    AddRow("Width",
        function() return Num(function(m) local e = Entry(m.key); return (e and e.width) or m.defW end) end,
        function(v)
            local m = Current()
            if m then Edit(function(e) e.width = min(m.opts.maxW or 3000, max(m.opts.minW or 40, v)) end) end
        end, 0, 99999, 10, "", function(m) return m.opts.resizable end)
    AddRow("Height",
        function() return Num(function(m) local e = Entry(m.key); return (e and e.height) or m.defH end) end,
        function(v)
            local m = Current()
            if m then Edit(function(e) e.height = min(m.opts.maxH or 600, max(m.opts.minH or 10, v)) end) end
        end, 0, 99999, 2, "", function(m) return m.opts.resizable and not m.opts.keepSquare end)
    AddRow("Scale",
        function() local m = Current(); return m and floor(Scale(m) * 100 + 0.5) or 100 end,
        function(v) Edit(function(e) e.scale = v / 100 end) end, 50, 200, 5, "%",
        function(m) return m.opts.scalable ~= false end)

    -- up to 3 extra rows a module can add for its own element:
    --   opts.extras = { { label = "Buttons per row", get = fn, set = fn(v), min = 1, max = 12 }, ... }
    for i = 1, 3 do
        local function Extra() local mm = Current(); return mm and mm.opts.extras and mm.opts.extras[i] end
        local row = W.Stepper(f, "", function() local x = Extra(); return x and x.get() or 0 end,
            function(v)
                local x = Extra()
                if x then x.set(max(x.min or -99999, min(x.max or 99999, v))) end
            end, -99999, 99999, 1)
        row.extra = i
        row.applies = function() return Extra() ~= nil end
        f.rows[#f.rows + 1] = row
    end

    f.snap = W.Checkbox(f, "Snap to a grid when dragging", function() return CysUIDB.snap end,
        function(on) CysUIDB.snap = on end)

    f.resetOne = W.Button(f, 110, 22, "Reset this one")
    f.resetOne:SetScript("OnClick", function() if selected then CUI:ResetMover(selected) end end)
    f.resetAll = W.Button(f, 90, 22, "Reset all")
    f.resetAll:SetScript("OnClick", function() CUI:ResetAllMovers() end)
    f.done = W.Button(f, 100, 24, "Done", true)
    f.done:SetScript("OnClick", function() CUI:SetLayoutMode(false) end)

    function f:RefreshAll()
        local m = Current()
        self.name:SetText(m and ("Editing: |cFFFFD100" .. m.label:gsub("\n", " ") .. "|r") or "|cFF777777Click a box to edit it.|r")
        local y = -88
        for _, row in ipairs(self.rows) do
            if m and (not row.applies or row.applies(m)) then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, y)
                if row.extra then row.label:SetText(m.opts.extras[row.extra].label) end
                row:Show()
                row:Refresh()
                y = y - 28
            else
                row:Hide()
            end
        end
        self.snap:ClearAllPoints()
        self.snap:SetPoint("TOPLEFT", 14, y - 6)
        self.snap:Refresh()
        y = y - 40
        self.resetOne:ClearAllPoints(); self.resetOne:SetPoint("TOPLEFT", 14, y)
        self.resetAll:ClearAllPoints(); self.resetAll:SetPoint("LEFT", self.resetOne, "RIGHT", 8, 0)
        self.done:ClearAllPoints(); self.done:SetPoint("TOPRIGHT", -14, y)
        self:SetHeight(-y + 40)
    end
    return f
end

local function BuildGuides()
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetAllPoints(UIParent)
    g:SetFrameStrata("DIALOG")
    g:SetFrameLevel(1)
    g:Hide()
    local v = W.Texture(g, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.25 })
    v:SetWidth(1)
    v:SetPoint("TOP"); v:SetPoint("BOTTOM")
    local h = W.Texture(g, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.25 })
    h:SetHeight(1)
    h:SetPoint("LEFT"); h:SetPoint("RIGHT")
    return g
end

--------------------------------------------------------------------------------
-- Layout mode on / off
--------------------------------------------------------------------------------
function CUI:SetLayoutMode(on)
    on = on and true or false
    if on == (self.layoutMode or false) then return end
    if on then
        if InCombatLockdown() then self:Print("You can't change the layout during combat."); return end
        if #self.moverOrder == 0 then self:Print("Nothing to move yet."); return end
    end
    self.layoutMode = on
    panel = panel or BuildPanel()
    guides = guides or BuildGuides()
        for _, key in ipairs(self.moverOrder) do self.movers[key].mover:SetShown(on and not self.movers[key].disabled) end
    guides:SetShown(on)
    panel:SetShown(on)
    if on then
        if CysUIConfigFrame then CysUIConfigFrame:Hide() end
        SelectMover(selected or self.moverOrder[1])
    end
end

function CUI:ToggleLayout() self:SetLayoutMode(not self.layoutMode) end

-- leaving the layout editor open when combat starts would be asking for trouble
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function()
    if CUI.layoutMode then
        CUI:SetLayoutMode(false)
        CUI:Print("Layout mode closed because combat started.")
    end
end)
