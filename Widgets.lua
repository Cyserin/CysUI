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
    { key = "class", label = "Class color" },
    { key = "black", label = "Black" },
    { key = "grey",  label = "Grey" },
    { key = "shaman", label = "Shaman blue", class = "SHAMAN" },
}

-- Styles this character can use (the Shaman blue only shows for Shamans)
function W.AvailableBorderStyles()
    local _, class = UnitClass("player")
    local out = {}
    for _, st in ipairs(W.BORDER_STYLES) do
        if not st.class or st.class == class then out[#out + 1] = st end
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
    end
    -- the brighter gold: the brand gold washes out against the orange zones
    return { T.accent[1], T.accent[2], T.accent[3] }
end

local styleCallbacks = {}
function W.OnBorderStyle(fn) styleCallbacks[#styleCallbacks + 1] = fn end

-- The highlight and hover colours that go with a border style. They must stay visible on the dark
-- panels, so Black and Grey use lighter greys; Gold keeps the original golds.
local function ThemeColors(key, c)
    if key == "black" then return { 0.42, 0.42, 0.42 }, { 0.78, 0.78, 0.78 } end
    if key == "grey" then return { 0.55, 0.55, 0.55 }, { 0.85, 0.85, 0.85 } end
    if key == "gold" or not key then return { 0.851, 0.643, 0.129 }, { 1, 0.82, 0 } end
    -- class colours / Shaman blue: the colour itself, a touch brighter for hover
    local function lift(v) return math.min(1, v * 1.2 + 0.08) end
    return { c[1], c[2], c[3] }, { lift(c[1]), lift(c[2]), lift(c[3]) }
end

-- Recolour the frame-edge colour, the highlight / hover colours and everything already drawn with them.
-- (Highlights made from a copy of the colour, e.g. with their own transparency, follow after a /reload.)
function W.ApplyBorderStyle(key)
    key = key or (CysUIDB and CysUIDB.borderColor) or "gold"
    local c = W.BorderStyleColor(key)
    T.border[1], T.border[2], T.border[3], T.border[4] = c[1], c[2], c[3], 1
    local fill, glow = ThemeColors(key, c)
    T.brand[1], T.brand[2], T.brand[3] = fill[1], fill[2], fill[3]
    T.glow[1], T.glow[2], T.glow[3] = glow[1], glow[2], glow[3]
    for t in pairs(frameTex) do
        if t.cysFrame then t:SetColorTexture(c[1], c[2], c[3], 1)
        elseif t.cysTheme then t:SetColorTexture(t.cysTheme[1], t.cysTheme[2], t.cysTheme[3], 1) end
    end
    for _, fn in ipairs(styleCallbacks) do pcall(fn) end
end

function W.ShowBorder(edges, show)
    for i = 1, #edges do edges[i]:SetShown(show) end
end

function W.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    local c = color or T.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
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
        b.bg:SetColorTexture(base[1], base[2], base[3], 1)
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
function W.Checkbox(parent, label, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(20)

    local box = CreateFrame("Frame", nil, c)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    c.boxEdges = W.Border(box, 1, T.border, "BORDER")
    c.check = W.Texture(box, "ARTWORK", T.glow)
    c.check:SetPoint("TOPLEFT", 4, -4)
    c.check:SetPoint("BOTTOMRIGHT", -4, 4)

    c.label = W.Text(c, 12, T.text)
    c.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    c.label:SetText(label)
    c:SetWidth(24 + max(c.label:GetStringWidth(), 40))

    function c:Refresh()
        local on = get() and true or false
        self.check:SetShown(on)
        W.SetBorder(self.boxEdges, on and T.glow or T.border)
    end
    function c:SetActive(on)
        if on then self:Enable() else self:Disable() end
        self:SetAlpha(on and 1 or 0.45)
    end
    c:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        if self.onChange then self.onChange(self) end
    end)
    c:SetScript("OnEnter", function(self) self.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    c:SetScript("OnLeave", function(self) self.label:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
    c:Refresh()
    return c
end

--------------------------------------------------------------------------------
-- Stepper: "Label        [-]  20s  [+]"
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Dropdown: a button showing the current choice; click it to open the list, click a choice to pick it.
--   options = { { value, "Label" }, ... }   get() -> value   set(value)   prefix = text before the label ("Shows: ")
--------------------------------------------------------------------------------
function W.Dropdown(parent, width, options, get, set, prefix)
    local b = W.Button(parent, width, 22, "")
    b.arrow = W.Text(b, 10, T.accent, "RIGHT")
    b.arrow:SetPoint("RIGHT", -8, 0)
    b.arrow:SetText("v")

    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(50)
    list:SetClampedToScreen(true)
    list:SetSize(width, #options * 22 + 6)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    W.Texture(list, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    W.Border(list, 1, T.border, "BORDER")
    list:Hide()

    -- clicking anywhere else closes the list
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(40)
    catcher:Hide()
    catcher:SetScript("OnClick", function() list:Hide() end)
    list:SetScript("OnShow", function() catcher:Show() end)
    list:SetScript("OnHide", function() catcher:Hide() end)

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

    local rows = {}
    for i, o in ipairs(options) do
        local row = W.Button(list, width - 8, 20, o[2])
        row:SetPoint("TOPLEFT", 4, -3 - (i - 1) * 22)
        row:SetScript("OnClick", function()
            list:Hide()
            set(o[1])
            b:Refresh()
        end)
        rows[i] = row
    end
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        local cur = get()
        for i, o in ipairs(options) do
            rows[i]:SetLabel((o[1] == cur and "|cFFFFD100> |r" or "   ") .. o[2])
        end
        list:Show()
    end)
    b:HookScript("OnHide", function() list:Hide() end)
    b:Refresh()
    return b
end

function W.Stepper(parent, label, get, set, minValue, maxValue, step, suffix)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(320, 22)
    f.label = W.Text(f, 12, T.text)
    f.label:SetPoint("LEFT", 0, 0)
    f.label:SetText(label)

    local plus = W.Button(f, 22, 22, "+")
    plus:SetPoint("RIGHT", 0, 0)
    f.value = W.Text(f, 12, T.accent, "CENTER")
    f.value:SetPoint("RIGHT", plus, "LEFT", -6, 0)
    f.value:SetWidth(54)
    local minus = W.Button(f, 22, 22, "-")
    minus:SetPoint("RIGHT", f.value, "LEFT", -6, 0)

    function f:Refresh() self.value:SetText(tostring(get()) .. (suffix or "")) end
    minus:SetScript("OnClick", function() set(max(minValue, get() - step)); f:Refresh() end)
    plus:SetScript("OnClick", function() set(min(maxValue, get() + step)); f:Refresh() end)
    f:Refresh()
    return f
end

--------------------------------------------------------------------------------
-- Section header: gold title followed by a thin rule
--------------------------------------------------------------------------------
function W.Header(parent, text, width)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(width or 400, 20)
    h.label = W.Text(h, 12, T.accent)
    h.label:SetPoint("LEFT", 0, 0)
    h.label:SetText(text)
    local line = W.Texture(h, "ARTWORK", T.line)
    line:SetHeight(1)
    line:SetPoint("LEFT", h.label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
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
