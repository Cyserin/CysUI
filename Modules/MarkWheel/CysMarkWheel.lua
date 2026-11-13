--------------------------------------------------------------------------------
-- Cys's UI - Marker Wheel
--
-- Hold a key: a ring of the eight raid markers (and Clear) opens at your mouse. Move toward one and let go:
-- your target gets that marker. Let go in the middle to cancel. Works in combat.
-- A second key opens the same kind of ring for WORLD markers (on the ground): pick one, then click the ground
-- where it goes (the game's own placing circle). Clear all takes every world marker away.
--
-- How: markers are set by the game's own /tm, /wm and /cwm commands on secure buttons, so they are never
-- blocked. A secure snippet (wrapped around the button's click) reads where the mouse is when the key goes
-- down (shows the ring there) and when it comes up (picks the slice and puts that slice's command into the
-- button just before it runs). Our own code only paints: which slice is under the mouse lights up.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor = math.floor
local MW = {}
CUI.MarkWheel = MW

local SIZE, RADIUS, SLOT, DEAD, HUB = 236, 84, 40, 26, 28
-- clockwise from the top; 0 = clear
local ORDER = { 8, 7, 6, 5, 4, 3, 2, 1, 0 }
local NAMES = { [0] = "Clear", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local COLORS = { [0] = { 0.8, 0.8, 0.8 }, { 1, 0.92, 0 }, { 0.98, 0.5, 0.1 }, { 0.78, 0.25, 0.95 }, { 0.12, 0.85, 0.2 },
                 { 0.75, 0.85, 0.95 }, { 0.15, 0.6, 1 }, { 1, 0.2, 0.2 }, { 0.95, 0.95, 0.95 } }
-- world marker number -> the raid icon it looks like (1 blue square, 2 green triangle, 3 purple diamond,
-- 4 red cross, 5 yellow star, 6 orange circle, 7 silver moon, 8 white skull)
local WORLD_ICON = { [0] = 0, 6, 4, 3, 7, 1, 2, 5, 8 }
-- the world wheel puts each marker where the same-looking one sits on the target wheel
-- (skull, cross, square, moon, triangle, diamond, circle, star, clear)
local WORLD_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5, 0 }
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function DB()
    CysUIDB.markwheel = CysUIDB.markwheel or {}
    local db = CysUIDB.markwheel
    if db.mouseover == nil then db.mouseover = false end
    db.scale = db.scale or 0.8
    return db
end

local header, screen, keyOwner
-- the two wheels: { kind, ring, button, slots, icon(n) -> raid icon, cmd(n) -> command text, dbKey }
local wheels = {}

--------------------------------------------------------------------------------
-- Key binding (an override binding: the game's own key setup is left alone)
--------------------------------------------------------------------------------
local pendingBind = false
function MW:ApplyBinding()
    if not keyOwner then return end
    if InCombatLockdown() then pendingBind = true; return end
    pendingBind = false
    ClearOverrideBindings(keyOwner)
    local db = DB()
    for _, w in ipairs(wheels) do
        local key = db[w.dbKey]
        if key and key ~= "" then SetOverrideBindingClick(keyOwner, true, key, w.button:GetName(), "LeftButton") end
    end
end

function MW:ApplyUnit()
    if #wheels == 0 or InCombatLockdown() then return end
    local db = DB()
    for _, w in ipairs(wheels) do
        -- each slice's whole command, ready for the secure code to drop into the button
        for i, marker in ipairs(w.order) do w.button:SetAttribute("cys-m" .. i, w.cmd(marker, db)) end
        -- size: the ring is scaled, and the secure code is told the scale so the picked slice still matches
        w.ring:SetScale(db.scale)
        w.button:SetAttribute("cys-scale", db.scale)
    end
end

--------------------------------------------------------------------------------
-- The secure part
--------------------------------------------------------------------------------
local PRE_CLICK = [=[
    local ring, screen = owner:GetFrameRef("ring"), owner:GetFrameRef("screen")
    if down then
        local x, y = screen:GetMousePosition()
        if not x then return false end
        ring:ClearAllPoints()
        local sc = self:GetAttribute("cys-scale")
        ring:SetPoint("CENTER", screen, "BOTTOMLEFT", x * screen:GetWidth() / sc, y * screen:GetHeight() / sc)
        ring:Show()
        return false
    end
    if not ring:IsShown() then return false end
    local l, b, w, h = ring:GetRect()
    ring:Hide()
    local x, y = screen:GetMousePosition()
    if not (x and l) then return false end
    local sc = self:GetAttribute("cys-scale")
    local dx = x * screen:GetWidth() - (l + w / 2) * sc
    local dy = y * screen:GetHeight() - (b + h / 2) * sc
    local dead = self:GetAttribute("cys-dead") * sc
    if dx * dx + dy * dy < dead * dead then return false end
    local ang = math.atan2(dx, dy)
    if ang < 0 then ang = ang + 2 * math.pi end
    local step = 2 * math.pi / 9
    local idx = math.floor((ang + step / 2) / step) % 9 + 1
    self:SetAttribute("macrotext", self:GetAttribute("cys-m" .. idx))
]=]

-- which slice the mouse points at (for the highlight only; the secure code decides for itself)
local function HoveredSlice(ring)
    local cx, cy = ring:GetCenter()
    if not cx then return nil end
    local s = ring:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    local dx, dy = mx / s - cx, my / s - cy
    if dx * dx + dy * dy < DEAD * DEAD then return nil end
    local ang = math.atan2(dx, dy)
    if ang < 0 then ang = ang + 2 * math.pi end
    local step = 2 * math.pi / 9
    return math.floor((ang + step / 2) / step) % 9 + 1
end

-- a filled circle (the game's round portrait mask), used for discs and, layered, for thin rims
local function Circle(parent, layer, sub, size, color, alpha, x, y, blend)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetSize(size, size)
    t:SetPoint("CENTER", x or 0, y or 0)
    t:SetTexture(DISC)
    t:SetVertexColor(color[1], color[2], color[3], alpha)
    if blend then t:SetBlendMode(blend) end
    return t
end

local function BuildRing(w, name)
    local ring = CreateFrame("Frame", name, UIParent, "SecureHandlerBaseTemplate")
    w.ring = ring
    local slots = {}
    w.slots = slots
    ring:SetSize(SIZE, SIZE)
    ring:SetFrameStrata("DIALOG")
    ring:SetClampedToScreen(true)
    ring:EnableMouse(false)
    ring:Hide()

    -- the wheel: a thin gold rim around a dark, slightly see-through disc (the Cys window look, made round)
    Circle(ring, "BACKGROUND", 0, SIZE, T.border, 0.7)
    Circle(ring, "BACKGROUND", 1, SIZE - 4, T.bg, 0.9)
    -- the middle: let go inside it to cancel
    Circle(ring, "BORDER", 0, HUB * 2, T.border, 0.45)
    Circle(ring, "BORDER", 1, HUB * 2 - 3, T.bg, 1)

    local label = ring:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    label:SetPoint("CENTER", 0, 0)

    local step = 2 * math.pi / 9
    for i, marker in ipairs(w.order) do
        local a = (i - 1) * step
        local x, y = math.sin(a) * RADIUS, math.cos(a) * RADIUS
        local s = {}
        local look = w.icon(marker) -- the raid icon this slot shows (world markers map to their look-alike)
        -- soft halo in the marker's colour, only on the slot you point at
        s.halo = Circle(ring, "BORDER", 2, SLOT + 18, COLORS[look], 1, x, y, "ADD")
        s.halo:SetAlpha(0)
        s.rim = Circle(ring, "ARTWORK", 0, SLOT, T.border, 0.5, x, y)
        Circle(ring, "ARTWORK", 1, SLOT - 3, { 0.06, 0.055, 0.05 }, 1, x, y)
        s.icon = ring:CreateTexture(nil, "ARTWORK", nil, 2)
        s.icon:SetSize(SLOT - 14, SLOT - 14)
        s.icon:SetPoint("CENTER", x, y)
        if marker == 0 then
            s.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        else
            s.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. look)
        end
        s.marker = marker
        s.look = look
        slots[i] = s
    end

    local function Paint(hover)
        for i, s in ipairs(slots) do
            local on = i == hover
            local c = COLORS[s.look]
            if on then s.rim:SetVertexColor(c[1], c[2], c[3], 1) else s.rim:SetVertexColor(T.border[1], T.border[2], T.border[3], 0.5) end
            s.halo:SetAlpha(on and 0.35 or 0)
            s.icon:SetAlpha(on and 1 or (hover and 0.5 or 0.9))
        end
        if hover then
            local m = slots[hover].look
            local c = COLORS[m]
            label:SetText(w.kind == "world" and m == 0 and "Clear all" or NAMES[m])
            label:SetTextColor(c[1], c[2], c[3])
        else
            label:SetText("")
        end
    end
    local last = -1
    ring:SetScript("OnShow", function() last = -1 end)
    ring:SetScript("OnUpdate", function()
        local h = HoveredSlice(ring) or 0
        if h ~= last then last = h; Paint(h > 0 and h or nil) end
    end)
end

-- one wheel: its ring, its secure button (clicked by the key) and the snippet that picks the slice
local function MakeWheel(w, ringName, buttonName, headerName)
    BuildRing(w, ringName)
    -- each wheel has its own secure header, so its snippet finds its own ring
    local hd = CreateFrame("Frame", headerName, UIParent, "SecureHandlerBaseTemplate")
    local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
    w.button = button
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -50, -50) -- off screen; it is only clicked by the key
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    button:SetAttribute("useOnKeyDown", false) -- act when the key comes up
    button:SetAttribute("cys-dead", DEAD)
    hd:SetFrameRef("ring", w.ring)
    hd:SetFrameRef("screen", screen)
    SecureHandlerWrapScript(button, "OnClick", hd, PRE_CLICK)
    wheels[#wheels + 1] = w
end

local function Build()
    header = true
    -- a whole-screen frame that only measures where the mouse is (no mouse, nothing drawn)
    screen = CreateFrame("Frame", "CysMarkWheelScreen", UIParent, "SecureHandlerBaseTemplate")
    screen:SetAllPoints(UIParent)
    screen:EnableMouse(false)

    -- raid markers on your target (/tm; "[@mouseover,exists][]" first when that switch is on)
    MakeWheel({ kind = "target", dbKey = "key", order = ORDER, icon = function(m) return m end,
                cmd = function(m, db) return "/tm " .. (db.mouseover and "[@mouseover,exists][] " or "") .. m end },
        "CysMarkWheelRing", "CysMarkWheelButton", "CysMarkWheelHeader")
    -- world markers on the ground (/wm N gives the game's placing circle; /cwm all clears them all)
    MakeWheel({ kind = "world", dbKey = "worldKey", order = WORLD_ORDER, icon = function(m) return WORLD_ICON[m] end,
                cmd = function(m) return m == 0 and "/cwm all" or ("/wm " .. m) end },
        "CysWorldMarkWheelRing", "CysWorldMarkWheelButton", "CysWorldMarkWheelHeader")

    keyOwner = CreateFrame("Frame")
    keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
    keyOwner:SetScript("OnEvent", function()
        if pendingBind then MW:ApplyBinding() end
        MW:ApplyUnit()
    end)
    MW:ApplyUnit()
    MW:ApplyBinding()
end

function MW.Enable()
    DB()
    if InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); Build() end)
    else
        Build()
    end
end

CUI:RegisterModule({
    key = "markwheel",
    name = "Marker Wheel",
    addon = "CysUI",
    desc = "Hold a key, point at a raid marker on the ring around your mouse, let go: your target is marked. A second key does the same for world markers on the ground. Works in combat.",
    onEnable = MW.Enable,
    open = function() CUI:OpenConfig("Marker Wheel") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local function WithModifiers(key)
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    return mods .. key
end

CUI:RegisterPage("Marker Wheel", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Marker Wheel", width):SetPoint("TOPLEFT", 0, -4)

    -- a "Label: [key] [Clear]" row; press a key (or mouse button 3-5) to bind it, Escape cancels
    local function KeyRow(y, text, field)
        local keyLabel = W.Text(page, 11, T.accent)
        keyLabel:SetPoint("TOPLEFT", 4, y)
        keyLabel:SetWidth(150)
        keyLabel:SetText(text)
        local bind = W.Button(page, 170, 22, "", true)
        bind:SetPoint("TOPLEFT", 160, y + 5)
        local function ShowKey()
            bind:SetLabel(db[field] and GetBindingText(db[field]) or "Click to set a key")
        end
        ShowKey()
        local clear = W.Button(page, 70, 22, "Clear")
        clear:SetPoint("LEFT", bind, "RIGHT", 8, 0)
        clear:SetScript("OnClick", function() db[field] = nil; MW:ApplyBinding(); ShowKey() end)
        local catcher = CreateFrame("Frame", nil, bind)
        catcher:SetAllPoints()
        catcher:Hide()
        local function Done(key)
            catcher:Hide()
            catcher:EnableKeyboard(false)
            if key then db[field] = key; MW:ApplyBinding() end
            ShowKey()
        end
        catcher:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then Done(nil) return end
            if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then return end -- wait for the real key
            Done(WithModifiers(key))
        end)
        catcher:EnableMouse(true)
        catcher:SetScript("OnMouseDown", function(_, mouse)
            if MOUSE_KEYS[mouse] then Done(WithModifiers(MOUSE_KEYS[mouse])) end
        end)
        bind:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            bind:SetLabel("Press a key... (Esc cancels)")
            catcher:Show()
            catcher:EnableKeyboard(true)
        end)
    end
    KeyRow(-40, "Target markers key:", "key")
    KeyRow(-70, "World markers key:", "worldKey")

    local mo = W.Checkbox(page, "Mark the unit under your mouse first, else your target", function() return db.mouseover end,
        function(on) db.mouseover = on; MW:ApplyUnit() end)
    mo:SetPoint("TOPLEFT", 4, -104)
    local size = W.Stepper(page, "Wheel size", function() return floor(db.scale * 100 + 0.5) end,
        function(v) db.scale = v / 100; MW:ApplyUnit() end, 50, 130, 5, "%")
    size:SetPoint("TOPLEFT", 4, -138)

    W.Notes(page, 4, -178, width, "", {
        "Target markers: hold the key, the ring opens around your mouse. Move toward a marker and let go to put it on your target.",
        "Let go in the middle to cancel. Clear (the red X) takes the marker off. Picking the marker it already has takes it off too.",
        "World markers: hold the second key, point at a marker and let go - then click the ground where it goes (the game's placing circle). Clear all removes every world marker. In a raid only the leader and assistants can place them.",
        "Works in combat and in dungeons. The keys are only used by Cys's UI while this module is on; the game's own key settings are not changed.",
    })
end)
