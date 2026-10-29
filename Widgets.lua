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
    brand    = Hex("D9A421"), -- fixed gold for fills / thumbs / highlights that must stay visible whatever the border colour
    accent   = Hex("FFD100"), -- bright gold: active / hover / primary
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
    if color == T.border then W.TrackEdge(t) end
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
    for i = 1, #edges do
        edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        edges[i].cysFrame = isFrame
        if isFrame then frameTex[edges[i]] = true end
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

-- Recolour the frame-edge colour and everything already drawn with it.
function W.ApplyBorderStyle(key)
    key = key or (CysUIDB and CysUIDB.borderColor) or "gold"
    local c = W.BorderStyleColor(key)
    T.border[1], T.border[2], T.border[3], T.border[4] = c[1], c[2], c[3], 1
    for t in pairs(frameTex) do
        if t.cysFrame then t:SetColorTexture(c[1], c[2], c[3], 1) end
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
function W.Button(parent, width, height, label, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.primary = primary and true or false
    b.bg = W.Texture(b, "BACKGROUND", primary and T.brand or T.button)
    b.bg:SetAllPoints()
    b.edges = W.Border(b, 1, primary and T.brand or T.line, "BORDER")
    b.label = W.Text(b, 11, primary and T.dark or T.accent, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label or "")

    b:SetScript("OnEnter", function(s)
        if s.primary then
            s.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            W.SetBorder(s.edges, T.accent)
        end
    end)
    b:SetScript("OnLeave", function(s)
        if s.primary then
            s.bg:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 1)
        else
            W.SetBorder(s.edges, T.line)
        end
    end)
    b:SetScript("OnMouseDown", function(s) s.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(s) s.label:SetPoint("CENTER", 0, 0) end)

    function b:SetLabel(text) self.label:SetText(text) end
    -- grey out and ignore clicks
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
    end
    -- promote / demote between the gold-filled and flat looks (e.g. "Reload UI" when needed)
    function b:SetPrimary(on)
        self.primary = on and true or false
        local fill = self.primary and T.brand or T.button
        self.bg:SetColorTexture(fill[1], fill[2], fill[3], 1)
        W.SetBorder(self.edges, self.primary and T.brand or T.line)
        local c = self.primary and T.dark or T.accent
        self.label:SetTextColor(c[1], c[2], c[3])
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
    c.check = W.Texture(box, "ARTWORK", T.accent)
    c.check:SetPoint("TOPLEFT", 4, -4)
    c.check:SetPoint("BOTTOMRIGHT", -4, 4)

    c.label = W.Text(c, 12, T.text)
    c.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    c.label:SetText(label)
    c:SetWidth(24 + max(c.label:GetStringWidth(), 40))

    function c:Refresh()
        local on = get() and true or false
        self.check:SetShown(on)
        W.SetBorder(self.boxEdges, on and T.accent or T.border)
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
