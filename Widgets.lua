--------------------------------------------------------------------------------
-- Cys's UI - theme and widgets
--
-- The one place the gold-and-dark look lives. Anything that wants to match the UI
-- (settings pages, new modules) uses CysUI.W instead of re-inventing buttons:
--
--   local W = CysUI.W
--   W.T                                   color table (W.T.accent, W.T.border, ...)
--   W.Button(parent, w, h, label, primary)
--   W.Checkbox(parent, label, get, set)   -> :Refresh(), :SetActive(bool)
--   W.Stepper(parent, label, get, set, min, max, step, suffix)  -> :Refresh()
--   W.Dropdown(parent, width, options, get, set, prefix)  options = { {value, "Label"}, ... }  -> :Refresh()
--   W.Header(parent, text, width)         gold section title with a rule
--   W.Text(parent, size, color, justify), W.Texture(...), W.Border(...)
--------------------------------------------------------------------------------
local CUI = CysUI
local W = {}
CUI.W = W

local max, min = math.max, math.min

local function Hex(hex, a)
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        a or 1,
    }
end

local T = {
    bg       = Hex("111111"),
    header   = Hex("141414"),
    sidebar  = Hex("0D0D0D"),
    field    = Hex("0A0A0A"),
    card     = Hex("151515"),
    cardHover = Hex("1D1D1D"),
    button   = Hex("1A1A1A"),
    hover    = Hex("181818"),
    selected = Hex("1E1E1E"),
    border   = Hex("D9A421"), -- frame edge colour: follows the Border color setting (changed in place, see W.ApplyBorderStyle)
    brand    = Hex("D9A421"), -- fills / thumbs / highlights: follows the Border color setting, kept visible (see W.ApplyBorderStyle)
    glow     = Hex("FFD100"), -- hover and "on" edges, checkmarks: follows the Border color setting
    accent   = Hex("FFD100"), -- bright gold text: labels, headings, active text
    line     = Hex("2A2A2A"),
    text     = Hex("E0E0E0"),
    dim      = Hex("777777"),
    desc     = Hex("F2F2F2"), -- settings descriptions and notes: white, so they read easily on the dark panels
    danger   = Hex("FF4040"),
    green    = Hex("4FD66B"),
    dark     = Hex("111111"),
}
W.T = T

-- Window style: Soft (default) = warm charcoal panels that let a touch of the world through and quieter
-- frame edges (hover and selected highlights stay bright); Classic = the original flat black with full edges.
-- Applied once at load, before any window is built (changing it needs a /reload).
W.WINDOW_STYLES = {
    { key = "soft",    label = "Soft" },
    { key = "classic", label = "Classic" },
}
local PALETTES = {
    classic = { bg = "111111", header = "141414", sidebar = "0D0D0D", field = "0A0A0A", card = "151515",
                cardHover = "1D1D1D", button = "1A1A1A", hover = "181818", selected = "1E1E1E", line = "2A2A2A" },
    soft    = { bg = "16130F", header = "1B1713", sidebar = "12100D", field = "0E0C0A", card = "1C1814",
                cardHover = "231E19", button = "201B16", hover = "1E1A15", selected = "27211B", line = "332C24" },
}
W.edgeAlpha = 1
function W.ApplyWindowStyle(key)
    key = key or (CysUIDB and CysUIDB.windowStyle) or "soft"
    local p = PALETTES[key] or PALETTES.soft
    for name, hex in pairs(p) do
        local c = Hex(hex)
        T[name][1], T[name][2], T[name][3] = c[1], c[2], c[3] -- in place: everything holding these tables follows
    end
    local soft = (PALETTES[key] or PALETTES.soft) == PALETTES.soft
    T.bg[4] = soft and 0.95 or 1
    W.edgeAlpha = soft and 0.7 or 1
    T.border[4] = W.edgeAlpha
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------
-- Every texture drawn in the frame-edge colour is remembered so the Border color setting can recolour it live.
local frameTex = setmetatable({}, { __mode = "k" })

function W.TrackEdge(t)
    t.cysFrame = true
    frameTex[t] = true
    return t
end

function W.Texture(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    if color == T.border then W.TrackEdge(t)
    elseif color == T.brand or color == T.glow then
        -- drawn in a theme colour: recoloured with the Border color setting too
        t.cysTheme = color
        frameTex[t] = true
    end
    return t
end

-- Four edge textures drawn inside the parent's bounds.
function W.Border(parent, thickness, color, layer, sublevel)
    local e = {}
    for i = 1, 4 do e[i] = W.Texture(parent, layer or "BORDER", color, sublevel) end
    e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(thickness)
    e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(thickness)
    e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(thickness)
    e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(thickness)
    return e
end

function W.SetBorder(edges, color)
    local isFrame = color == T.border
    local theme = (color == T.brand or color == T.glow) and color or nil
    for i = 1, #edges do
        edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        edges[i].cysFrame = isFrame
        edges[i].cysTheme = theme
        if isFrame or theme then frameTex[edges[i]] = true end
    end
end

-- Border color setting: gold (the default), class color, black or grey
W.BORDER_STYLES = {
    { key = "gold",  label = "Gold" },
    { key = "brightgold", label = "Bright gold" },
    { key = "class", label = "Class color" },
    { key = "black", label = "Black" },
    { key = "grey",  label = "Grey" },
    { key = "shaman", label = "Shaman blue", class = "SHAMAN" },
}

-- Styles this character can use (the Shaman blue only shows for Shamans, and not on WoW Forever,
-- where Shamans are already blue so Class color gives the same thing)
function W.AvailableBorderStyles()
    local _, class = UnitClass("player")
    local isForever = CysUICompat and CysUICompat.isForever
    local out = {}
    for _, st in ipairs(W.BORDER_STYLES) do
        if (not st.class or st.class == class) and not (isForever and st.key == "shaman") then out[#out + 1] = st end
    end
    return out
end

function W.BorderStyleColor(key)
    if key == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return { c.r, c.g, c.b } end
    elseif key == "shaman" then
        local _, class = UnitClass("player")
        if class == "SHAMAN" then return { 0, 0.44, 0.87 } end
    elseif key == "black" then
        return { 0, 0, 0 }
    elseif key == "grey" then
        return { 0.5, 0.5, 0.5 }
    elseif key == "brightgold" then
        -- the bright gold: stands out against the orange zones (the Barrens)
        return { T.accent[1], T.accent[2], T.accent[3] }
    end
    -- Gold (default): a soft, muted antique gold so edges frame things without shouting
    return { 0.72, 0.57, 0.24 }
end

local styleCallbacks = {}
function W.OnBorderStyle(fn) styleCallbacks[#styleCallbacks + 1] = fn end

-- The highlight and hover colours that go with a border style. They must stay visible on the dark
-- panels, so Black and Grey use lighter greys; Gold keeps the original golds.
local function ThemeColors(key, c)
    if key == "black" then return { 0.42, 0.42, 0.42 }, { 0.78, 0.78, 0.78 } end
    if key == "grey" then return { 0.55, 0.55, 0.55 }, { 0.85, 0.85, 0.85 } end
    if key == "brightgold" then return { 0.851, 0.643, 0.129 }, { 1, 0.82, 0 } end
    if key == "gold" or not key then return { 0.72, 0.57, 0.24 }, { 0.92, 0.76, 0.32 } end
    -- class colours / Shaman blue: the colour itself, a touch brighter for hover
    local function lift(v) return math.min(1, v * 1.2 + 0.08) end
    return { c[1], c[2], c[3] }, { lift(c[1]), lift(c[2]), lift(c[3]) }
end

-- Recolour the frame-edge colour, the highlight / hover colours and everything already drawn with them.
-- (Highlights made from a copy of the colour, e.g. with their own transparency, follow after a /reload.)
function W.ApplyBorderStyle(key)
    key = key or (CysUIDB and CysUIDB.borderColor) or "gold"
    local c = W.BorderStyleColor(key)
    T.border[1], T.border[2], T.border[3], T.border[4] = c[1], c[2], c[3], W.edgeAlpha or 1
    local fill, glow = ThemeColors(key, c)
    T.brand[1], T.brand[2], T.brand[3] = fill[1], fill[2], fill[3]
    T.glow[1], T.glow[2], T.glow[3] = glow[1], glow[2], glow[3]
    for t in pairs(frameTex) do
        if t.cysFrame then t:SetColorTexture(c[1], c[2], c[3], W.edgeAlpha or 1)
        elseif t.cysTheme then t:SetColorTexture(t.cysTheme[1], t.cysTheme[2], t.cysTheme[3], 1) end
    end
    for _, fn in ipairs(styleCallbacks) do pcall(fn) end
end

function W.ShowBorder(edges, show)
    for i = 1, #edges do edges[i]:SetShown(show) end
end

function W.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size or 11), "")
    local c = color or T.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

--------------------------------------------------------------------------------
-- Glyph: crisp line icons drawn from thin bars instead of font letters ("X", "v", "+").
--   W.Glyph(parent, kind, size, color, thick) -> a small frame to SetPoint;  :SetKind(kind)  :SetColor(c | r, g, b, a)
--   kinds: "close", "down", "up", "right", "left", "plus", "minus", "none"
--------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local R45 = math.rad(45)
local function GlyphLayout(g)
    local s, th, k = g.size, g.thick, g.kind
    local a, b = g.bars[1], g.bars[2]
    a:Show(); b:Show()
    a:SetRotation(0); b:SetRotation(0)
    a:ClearAllPoints(); b:ClearAllPoints()
    if k == "close" then
        local len = s * 1.25
        a:SetSize(len, th); b:SetSize(len, th)
        a:SetPoint("CENTER", g, "CENTER", 0, 0); b:SetPoint("CENTER", g, "CENTER", 0, 0)
        a:SetRotation(R45); b:SetRotation(-R45)
    elseif k == "plus" or k == "minus" then
        a:SetSize(s, th); a:SetPoint("CENTER", g, "CENTER", 0, 0)
        b:SetSize(th, s); b:SetPoint("CENTER", g, "CENTER", 0, 0)
        b:SetShown(k == "plus")
    elseif k == "down" or k == "up" or k == "right" or k == "left" then
        -- two arms at 45 degrees that meet at the tip; nudged together a little so the tip has no notch
        local arm = s * 0.7
        local h = arm * 0.7071 / 2 - th * 0.25
        a:SetSize(arm, th); b:SetSize(arm, th)
        if k == "down" or k == "up" then
            local tip = k == "down" and 1 or -1
            a:SetPoint("CENTER", g, "CENTER", -h, 0); a:SetRotation(-R45 * tip)
            b:SetPoint("CENTER", g, "CENTER", h, 0);  b:SetRotation(R45 * tip)
        else
            local tip = k == "right" and 1 or -1
            a:SetPoint("CENTER", g, "CENTER", 0, h);  a:SetRotation(-R45 * tip)
            b:SetPoint("CENTER", g, "CENTER", 0, -h); b:SetRotation(R45 * tip)
        end
    else
        a:Hide(); b:Hide()
    end
end

function W.Glyph(parent, kind, size, color, thick)
    local g = CreateFrame("Frame", nil, parent)
    g.size, g.thick = size or 10, thick or 2
    g:SetSize(g.size, g.size)
    g.bars = {}
    for i = 1, 2 do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        -- rotated bars look jagged when snapped to the pixel grid
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        g.bars[i] = t
    end
    function g:SetColor(r, gg, b, a)
        if type(r) == "table" then r, gg, b, a = r[1], r[2], r[3], r[4] end
        for i = 1, 2 do self.bars[i]:SetVertexColor(r, gg, b, a or 1) end
    end
    g.SetTextColor = g.SetColor -- lets code written for the old letter icons keep working
    function g:SetKind(k)
        if self.kind == k then return end
        self.kind = k
        GlyphLayout(self)
    end
    g:SetColor(color or T.text)
    g:SetKind(kind or "none")
    return g
end

-- CloseGlyph: the drawn x for a close / clear / remove button, centered on it, with a faint red square under the
-- mouse (noHover skips the square, for buttons that light up on their own). small = the size for 16-18 px buttons.
-- Returns the glyph; it answers SetTextColor like the old "X" letter did, so existing hover code keeps working.
function W.CloseGlyph(btn, color, small, noHover)
    local g = W.Glyph(btn, "close", small and 7 or 9, color or T.desc, small and 1.5 or 2)
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if not noHover and btn.SetHighlightTexture then
        btn:SetHighlightTexture(WHITE, "BLEND")
        local hl = btn:GetHighlightTexture()
        if hl then hl:SetVertexColor(1, 0.3, 0.3, 0.14); hl:SetAllPoints() end
    end
    return g
end

--------------------------------------------------------------------------------
-- Button: flat, gold text; `primary` = the one gold-filled call-to-action button
--------------------------------------------------------------------------------
-- Every button has the same flat dark look with gold text. A "primary" button (the main action, or the
-- selected choice in a row of options) gets a gold edge and a faint gold tint instead of a solid fill.
local PRIMARY_TINT = 0.16
local function PaintButton(b, hover)
    local base = T.button
    if b.primary then
        local br = T.brand
        -- the button colour with a little gold mixed in
        b.bg:SetColorTexture(base[1] + (br[1] - base[1]) * PRIMARY_TINT, base[2] + (br[2] - base[2]) * PRIMARY_TINT,
            base[3] + (br[3] - base[3]) * PRIMARY_TINT, 1)
        W.SetBorder(b.edges, hover and T.glow or T.border)
    else
        local bg = hover and T.cardHover or base
        b.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
        W.SetBorder(b.edges, hover and T.glow or T.line)
    end
    b.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
end

function W.Button(parent, width, height, label, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.primary = primary and true or false
    b.bg = W.Texture(b, "BACKGROUND", T.button)
    b.bg:SetAllPoints()
    b.edges = W.Border(b, 1, T.line, "BORDER")
    b.label = W.Text(b, 11, T.accent, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label or "")
    PaintButton(b, false)

    b:SetScript("OnEnter", function(s) PaintButton(s, true) end)
    b:SetScript("OnLeave", function(s) PaintButton(s, false) end)
    b:SetScript("OnMouseDown", function(s) s.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(s) s.label:SetPoint("CENTER", 0, 0) end)

    function b:SetLabel(text) self.label:SetText(text) end
    -- grey out and ignore clicks
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
    end
    -- mark as the main / selected button (gold edge) or back to the plain look (e.g. "Reload UI" when needed)
    function b:SetPrimary(on)
        self.primary = on and true or false
        PaintButton(self, self:IsMouseOver())
    end
    return b
end

--------------------------------------------------------------------------------
-- Checkbox: get() -> boolean, set(boolean)
--------------------------------------------------------------------------------
-- Drawn as a toggle switch: a rounded track (dark when off, gold when on) with a knob that slides across.
-- Rows light up under the mouse, and the label is dimmed while the switch is off so the ones in use stand out.
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local TRACK_W, TRACK_H, KNOB = 28, 14, 10
local OFF_TRACK = { 0.24, 0.24, 0.24 }
local OFF_KNOB = { 0.62, 0.62, 0.62 }
local OFF_LABEL = { 0.74, 0.74, 0.74 }
local function Pill(parent, layer, sub, w, h)
    local p = {}
    p.l = parent:CreateTexture(nil, layer, nil, sub); p.l:SetTexture(CIRCLE)
    p.l:SetSize(h, h); p.l:SetPoint("LEFT", 0, 0)
    p.r = parent:CreateTexture(nil, layer, nil, sub); p.r:SetTexture(CIRCLE)
    p.r:SetSize(h, h); p.r:SetPoint("RIGHT", 0, 0)
    p.m = parent:CreateTexture(nil, layer, nil, sub); p.m:SetTexture("Interface\\Buttons\\WHITE8X8")
    p.m:SetPoint("TOPLEFT", h / 2, 0); p.m:SetPoint("BOTTOMRIGHT", -h / 2, 0)
    function p:Color(r, g, b, a) self.l:SetVertexColor(r, g, b, a or 1); self.r:SetVertexColor(r, g, b, a or 1); self.m:SetVertexColor(r, g, b, a or 1) end
    return p
end

function W.Checkbox(parent, label, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(20)

    -- hover band behind the whole row
    c.hl = c:CreateTexture(nil, "BACKGROUND")
    c.hl:SetColorTexture(1, 1, 1, 0.045)
    c.hl:SetPoint("TOPLEFT", -6, 2)
    c.hl:SetPoint("BOTTOMRIGHT", 8, -2)
    c.hl:Hide()

    local box = CreateFrame("Frame", nil, c)
    box:SetSize(TRACK_W, TRACK_H)
    box:SetPoint("LEFT", 0, 0)
    c.track = Pill(box, "BORDER", 0, TRACK_W, TRACK_H)
    c.knob = box:CreateTexture(nil, "ARTWORK")
    c.knob:SetTexture(CIRCLE)
    c.knob:SetSize(KNOB, KNOB)
    c.knobX = 2
    c.knob:SetPoint("LEFT", c.knobX, 0)
    -- kept for older code that reaches for these (no longer drawn)
    c.check = box:CreateTexture(nil, "ARTWORK")
    c.check:Hide()
    c.boxEdges = {}

    c.label = W.Text(c, 12, T.text)
    c.label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    c.label:SetText(label)
    -- a label too long for the settings page wraps onto a second line instead of running off the edge
    local labelW = c.label:GetStringWidth()
    if labelW > 440 then
        labelW = 440
        c.label:SetWidth(440)
        c.label:SetJustifyH("LEFT")
        c.label:SetWordWrap(true)
        if c.label.SetMaxLines then c.label:SetMaxLines(2) end
    end
    c:SetWidth(TRACK_W + 10 + max(labelW, 40))

    local function Slide(self, elapsed)
        local diff = self.knobTo - self.knobX
        if math.abs(diff) < 0.5 then
            self.knobX = self.knobTo
            self:SetScript("OnUpdate", nil)
        else
            self.knobX = self.knobX + diff * math.min(1, elapsed * 18)
        end
        self.knob:SetPoint("LEFT", self.knobX, 0)
    end
    function c:Paint()
        local on = self.on
        local tc = on and T.brand or OFF_TRACK
        self.track:Color(tc[1], tc[2], tc[3], 1)
        local kc = on and T.dark or OFF_KNOB
        self.knob:SetVertexColor(kc[1], kc[2], kc[3], 1)
        local lc = self.hot and T.accent or (on and T.text or OFF_LABEL)
        self.label:SetTextColor(lc[1], lc[2], lc[3])
    end
    function c:Refresh(animate)
        local on = get() and true or false
        self.on = on
        self.knobTo = on and (TRACK_W - KNOB - 2) or 2
        if animate and self:IsVisible() then
            self:SetScript("OnUpdate", Slide)
        else
            self.knobX = self.knobTo
            self.knob:SetPoint("LEFT", self.knobX, 0)
            self:SetScript("OnUpdate", nil)
        end
        self:Paint()
    end
    function c:SetActive(on)
        if on then self:Enable() else self:Disable() end
        self:SetAlpha(on and 1 or 0.45)
    end
    c:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh(true)
        if self.onChange then self.onChange(self) end
    end)
    c:SetScript("OnEnter", function(self) self.hot = true; self.hl:Show(); self:Paint() end)
    c:SetScript("OnLeave", function(self) self.hot = false; self.hl:Hide(); self:Paint() end)
    c:Refresh()
    return c
end

--------------------------------------------------------------------------------
-- Dropdown: a button showing the current choice; click it to open the list, click a choice to pick it.
--   options = { { value, "Label" }, ... }   get() -> value   set(value)   prefix = text before the label ("Shows: ")
--------------------------------------------------------------------------------
function W.Dropdown(parent, width, options, get, set, prefix)
    -- a dark field like a text box: the choice in white on the left, a gold chevron on the right
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    b.bg = W.Texture(b, "BACKGROUND", T.field)
    b.bg:SetAllPoints()
    b.edges = W.Border(b, 1, T.line, "BORDER")
    b.label = W.Text(b, 12, T.text, "LEFT")
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -22, 0)
    b.label:SetWordWrap(false)
    b.arrow = W.Glyph(b, "down", 8, T.dim, 1.5)
    b.arrow:SetPoint("RIGHT", -9, 0)
    function b:Paint()
        local hot = self.hot or self.open
        W.SetBorder(self.edges, hot and T.glow or T.line)
        local ac = hot and T.accent or T.dim
        self.arrow:SetColor(ac)
        self.arrow:SetKind(self.open and "up" or "down")
        local f = self.hot and T.hover or T.field
        self.bg:SetColorTexture(f[1], f[2], f[3], 1)
    end
    function b:SetLabel(text) self.label:SetText(text) end
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
    end
    -- a choice too long for the box shows in full in a tooltip
    b:SetScript("OnEnter", function(s)
        s.hot = true; s:Paint()
        if s.label.IsTruncated and s.label:IsTruncated() and not s.open then
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:AddLine(s.label:GetText() or "", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s) s.hot = false; s:Paint(); if not s.open then GameTooltip:Hide() end end)

    local ROW = 20
    -- the open list lives in the TOOLTIP strata: above every window, whatever level the window has climbed to
    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:SetFrameLevel(50)
    list:SetClampedToScreen(true)
    list:SetSize(width, #options * ROW + 6)
    W.Texture(list, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.98 }):SetAllPoints()
    W.Border(list, 1, T.border, "BORDER")
    list:Hide()

    -- clicking anywhere else closes the list
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(40)
    catcher:Hide()
    catcher:SetScript("OnClick", function() list:Hide() end)
    list:SetScript("OnShow", function() catcher:Show(); b.open = true; b:Paint() end)
    list:SetScript("OnHide", function() catcher:Hide(); b.open = false; b:Paint() end)

    local function Text(opt)
        return (prefix or "") .. opt[2]
    end
    function b:Refresh()
        local cur = get()
        local shown = options[1] and Text(options[1]) or ""
        for _, o in ipairs(options) do
            if o[1] == cur then shown = Text(o) end
        end
        self:SetLabel(shown)
    end

    -- list rows: a soft band under the mouse; the current choice in gold with a bar on its left
    local rows = {}
    for i, o in ipairs(options) do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(width - 8, ROW)
        row:SetPoint("TOPLEFT", 4, -3 - (i - 1) * ROW)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetColorTexture(1, 1, 1, 0.06)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.bar = W.Texture(row, "BORDER", T.brand)
        row.bar:SetPoint("TOPLEFT", 0, -3); row.bar:SetPoint("BOTTOMLEFT", 0, 3); row.bar:SetWidth(2)
        row.label = W.Text(row, 12, T.text, "LEFT")
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetPoint("RIGHT", -6, 0)
        row.label:SetWordWrap(false)
        row.label:SetText(o[2])
        function row:Paint()
            local c = self.current and T.accent or (self.hot and T.desc or T.text)
            self.label:SetTextColor(c[1], c[2], c[3])
            self.bar:SetShown(self.current)
            self.hl:SetShown(self.hot)
        end
        function row:SetLabel(text) self.label:SetText(text) end
        row:SetScript("OnEnter", function(s) s.hot = true; s:Paint() end)
        row:SetScript("OnLeave", function(s) s.hot = false; s:Paint() end)
        row:SetScript("OnClick", function()
            list:Hide()
            set(o[1])
            b:Refresh()
        end)
        rows[i] = row
    end
    -- the list can be wider than the box, so long choices are never cut off
    local listW = width
    for _, row in ipairs(rows) do
        local fs = row.label
        local tw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
        listW = math.max(listW, math.ceil(tw + 26))
    end
    listW = math.min(listW, 480)
    list:SetWidth(listW)
    for _, row in ipairs(rows) do row:SetWidth(listW - 8) end

    -- Open the list above whatever window holds the box (the settings window and the layout panel share its
    -- strata and climb in level when clicked), the click-catcher just under it. Opens upward near the bottom edge.
    local function Place()
        local lvl = 60
        catcher:SetFrameLevel(lvl - 10)
        list:SetFrameLevel(lvl)
        for _, row in ipairs(rows) do row:SetFrameLevel(lvl + 2) end
        list:Raise()
        list:ClearAllPoints()
        local bottom = b:GetBottom()
        local room = bottom and (bottom * b:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 9999
        if room < list:GetHeight() + 8 then
            list:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
        else
            list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
        end
    end
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        GameTooltip:Hide()
        local cur = get()
        for i, o in ipairs(options) do
            rows[i].current = o[1] == cur
            rows[i].hot = false
            rows[i]:Paint()
        end
        Place()
        list:Show()
    end)
    b:HookScript("OnHide", function() list:Hide() end)
    b:Paint()
    b:Refresh()
    return b
end

-- Stepper: "Label                 [====o-------]  [ 100% ]" - a slim slider with a gold fill and a round knob,
-- and the value in a small box you can click to type a number. Drag the knob (or click the track), or roll the
-- mouse wheel over the row for one step. While dragging only the number moves; the setting is saved when you let
-- go, so heavy settings (UI scale) don't re-apply on every pixel. The row lights up under the mouse like a switch row.
local SLIDER_W, VALUE_W = 124, 48
local function StepText(v, step, suffix)
    local s
    if type(v) ~= "number" then s = tostring(v)
    elseif step and step % 1 ~= 0 then s = (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
    else s = tostring(math.floor(v + 0.5)) end
    return s .. (suffix or "")
end

function W.Stepper(parent, label, get, set, minValue, maxValue, step, suffix)
    step = step or 1
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(320, 22)
    f:EnableMouse(true)
    -- the wheel changes the value only when switched on (General page) or on panels that don't scroll
    -- (layout mode sets f.wheelAlways); otherwise it passes through and scrolls the settings window
    local function WheelOn() return f.wheelAlways or (CysUIDB and CysUIDB.wheelSliders == true) end
    f:EnableMouseWheel(false)
    f.hl = f:CreateTexture(nil, "BACKGROUND")
    f.hl:SetColorTexture(1, 1, 1, 0.045)
    f.hl:SetPoint("TOPLEFT", -6, 1)
    f.hl:SetPoint("BOTTOMRIGHT", 6, -1)
    f.hl:Hide()
    f.label = W.Text(f, 12, T.text)
    f.label:SetPoint("LEFT", 0, 0)
    f.label:SetText(label)
    -- a long label widens the row instead of sliding under the slider
    local needW = (f.label:GetStringWidth() or 0) + SLIDER_W + VALUE_W + 30
    if needW > 320 then f:SetWidth(needW) end

    local function Snap(v)
        v = minValue + math.floor((v - minValue) / step + 0.5) * step
        if step % 1 == 0 then v = math.floor(v + 0.5) end
        return min(maxValue, max(minValue, v))
    end

    -- value box: dark field, gold number; click to type
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(VALUE_W, 18)
    box:SetPoint("RIGHT", 0, 0)
    box:SetAutoFocus(false)
    box:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "")
    box:SetJustifyH("CENTER")
    box:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    box:SetMaxLetters(8)
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    box.edges = W.Border(box, 1, T.line, "BORDER")
    f.value = box

    -- track: a thin rounded bar, gold up to the value, with a knob on top
    local track = CreateFrame("Frame", nil, f)
    track:SetSize(SLIDER_W, 16)
    track:SetPoint("RIGHT", box, "LEFT", -12, 0)
    track:EnableMouse(true)
    local bar = CreateFrame("Frame", nil, track)
    bar:SetHeight(4)
    bar:SetPoint("LEFT", 0, 0); bar:SetPoint("RIGHT", 0, 0)
    local back = Pill(bar, "BORDER", 0, SLIDER_W, 4)
    back:Color(OFF_TRACK[1], OFF_TRACK[2], OFF_TRACK[3], 1)
    local fillF = CreateFrame("Frame", nil, bar)
    fillF:SetHeight(4)
    fillF:SetPoint("LEFT", 0, 0)
    local fill = Pill(fillF, "ARTWORK", 0, 10, 4)
    -- the knob lives on its own frame above the bar (a child frame always draws over its parent's textures),
    -- with a dark ring so it stands out against the gold fill
    local knobF = CreateFrame("Frame", nil, track)
    knobF:SetSize(14, 14)
    knobF:SetFrameLevel(bar:GetFrameLevel() + 5)
    local ring = knobF:CreateTexture(nil, "ARTWORK")
    ring:SetTexture(CIRCLE)
    ring:SetAllPoints()
    ring:SetVertexColor(T.dark[1], T.dark[2], T.dark[3], 1)
    local knob = knobF:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(CIRCLE)
    knob:SetSize(10, 10)
    knob:SetPoint("CENTER")
    f.track, f.knob = track, knob

    local shown -- the value drawn right now (differs from get() while dragging)
    local function Draw(v)
        shown = v
        local frac = (type(v) == "number" and maxValue > minValue) and (v - minValue) / (maxValue - minValue) or 0
        frac = min(1, max(0, frac))
        local x = frac * SLIDER_W
        knobF:ClearAllPoints()
        knobF:SetPoint("CENTER", track, "LEFT", x, 0)
        fillF:SetWidth(max(4, x))
        fillF:SetShown(frac > 0)
        if not box:HasFocus() then box:SetText(StepText(v, step, suffix)) end
    end

    local function Hot()
        local hot = f:IsMouseOver() or f.dragging
        f.hl:SetShown(hot and true or false)
        local c = hot and T.accent or T.text
        f.label:SetTextColor(c[1], c[2], c[3])
        local kc = hot and T.glow or T.text
        knob:SetVertexColor(kc[1], kc[2], kc[3], 1)
        local fc = T.brand
        fill:Color(fc[1], fc[2], fc[3], 1)
        W.SetBorder(box.edges, (box:HasFocus() or box.hot) and T.glow or T.line)
    end
    f.Hot = Hot

    local function Commit(v)
        v = Snap(v)
        if v ~= get() then set(v) end
        f:Refresh()
    end

    local function CursorValue()
        local x = GetCursorPosition() / track:GetEffectiveScale()
        local left = track:GetLeft() or 0
        return minValue + (maxValue - minValue) * min(1, max(0, (x - left) / SLIDER_W))
    end
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or type(get()) ~= "number" then return end
        box:ClearFocus()
        f.dragging = true
        Draw(Snap(CursorValue()))
        track:SetScript("OnUpdate", function()
            local v = Snap(CursorValue())
            if v ~= shown then Draw(v) end
        end)
        Hot()
    end)
    track:SetScript("OnMouseUp", function()
        if not f.dragging then return end
        f.dragging = nil
        track:SetScript("OnUpdate", nil)
        Commit(shown)
        Hot()
    end)
    track:SetScript("OnEnter", Hot)
    track:SetScript("OnLeave", Hot)

    f:SetScript("OnMouseWheel", function(_, delta)
        local v = get()
        if type(v) ~= "number" or f.dragging then return end
        Commit(v + (delta > 0 and step or -step))
    end)
    f:SetScript("OnEnter", function() f:EnableMouseWheel(WheelOn() and true or false); Hot() end)
    f:SetScript("OnLeave", Hot)

    box:SetScript("OnEnter", function(s) s.hot = true; Hot() end)
    box:SetScript("OnLeave", function(s) s.hot = false; Hot() end)
    box:SetScript("OnEditFocusGained", function(s) s:SetText(StepText(get(), step)); s:HighlightText(); Hot() end)
    box:SetScript("OnEditFocusLost", function(s) s:HighlightText(0, 0); f:Refresh(); Hot() end)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s)
        local n = tonumber((s:GetText() or ""):match("%-?[%d%.]+") or "")
        s:ClearFocus()
        if n and type(get()) == "number" then Commit(n) end
    end)

    function f:Refresh()
        if self.dragging then return end
        Draw(get())
    end
    f:Refresh()
    Hot()
    return f
end

--------------------------------------------------------------------------------
-- Section header: a card strip - dark band, gold bar on the left, gold title, a thin rule under it
--------------------------------------------------------------------------------
function W.Header(parent, text, width)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(width or 400, 22)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if bg.SetGradient and CreateColor then
        bg:SetColorTexture(1, 1, 1, 1)
        bg:SetGradient("HORIZONTAL", CreateColor(T.card[1] + 0.03, T.card[2] + 0.03, T.card[3] + 0.03, 0.95),
            CreateColor(T.card[1], T.card[2], T.card[3], 0.15))
    else
        bg:SetColorTexture(T.card[1], T.card[2], T.card[3], 0.85)
    end
    h.bar = W.Texture(h, "BORDER", T.brand)
    h.bar:SetPoint("TOPLEFT"); h.bar:SetPoint("BOTTOMLEFT"); h.bar:SetWidth(3)
    h.label = W.Text(h, 13, T.accent)
    h.label:SetPoint("LEFT", 11, 0)
    h.label:SetText(text)
    local line = W.Texture(h, "ARTWORK", T.line)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 3, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    return h
end

-- A short intro and a bulleted list in one block whose height follows its text (wrapped lines hang under their own
-- text). Items are "text" or { "Gold label", "text" }. Returns the block; its bottom edge moves with the content.
function W.Notes(parent, x, y, width, intro, items)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(width, 20)
    local used = 0
    local function Line(w, color)
        local fs = W.Text(box, 11, color or T.desc)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(3)
        return fs
    end
    local function Add(fs, ox)
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", ox, -used)
        used = used + (fs:GetStringHeight() or 12) + 4
    end
    if intro and intro ~= "" then
        local fs = Line(width)
        fs:SetText(intro)
        Add(fs, 0)
    end
    for _, it in ipairs(items or {}) do
        local label, text
        if type(it) == "table" then label, text = it[1], it[2] else text = it end
        local dot = Line(12, T.accent)
        dot:SetText("\226\128\162")
        dot:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -used)
        local txt = Line(width - 22)
        txt:SetText(label and ("|cFFFFD100" .. label .. "|r - " .. text) or text)
        Add(txt, 20)
    end
    box:SetHeight(math.max(used, 14))
    -- keep the page scrollable down to the end of the block
    if type(y) == "number" then parent.contentHeight = math.max(parent.contentHeight or 0, -y + used + 16) end
    return box
end
