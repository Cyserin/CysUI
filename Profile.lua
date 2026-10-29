--------------------------------------------------------------------------------
-- Cys's UI - Profile.lua
-- Copy-able text box, export / import of your settings as one pasteable line,
-- and "reset everything".
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T
local floor, min, max = math.floor, math.min, math.max

--------------------------------------------------------------------------------
-- Text box: shows text you can select and copy (or paste into, for importing)
--------------------------------------------------------------------------------
local box
function CUI:ShowTextBox(title, hint, text, opts)
    opts = opts or {}
    if not box then
        box = CreateFrame("Frame", "CysTextBox", UIParent)
        box:SetSize(540, 340)
        box:SetPoint("CENTER", 0, 40)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:EnableMouse(true)
        W.Texture(box, "BACKGROUND", T.bg):SetAllPoints()
        W.Border(box, 1, T.border, "BORDER")
        box.title = W.Text(box, 14, T.accent, "CENTER")
        box.title:SetPoint("TOP", 0, -10)
        box.hint = W.Text(box, 11, T.desc, "CENTER")
        box.hint:SetPoint("TOP", box.title, "BOTTOM", 0, -6)
        box.hint:SetWidth(500)
        local holder = CreateFrame("Frame", nil, box)
        holder:SetPoint("TOPLEFT", 14, -62)
        holder:SetPoint("BOTTOMRIGHT", -14, 50)
        W.Texture(holder, "BACKGROUND", T.field):SetAllPoints()
        W.Border(holder, 1, T.line, "BORDER")
        local sf = CreateFrame("ScrollFrame", nil, holder)
        sf:SetPoint("TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", -6, 6)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont(STANDARD_TEXT_FONT, 11, "")
        eb:SetTextColor(T.text[1], T.text[2], T.text[3])
        eb:SetWidth(484)
        eb:SetMaxLetters(0)
        sf:SetScrollChild(eb)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(s, d)
            local limit = max(0, eb:GetHeight() - s:GetHeight())
            s:SetVerticalScroll(min(limit, max(0, s:GetVerticalScroll() - d * 40)))
        end)
        eb:SetScript("OnEscapePressed", function() box:Hide() end)
        eb:SetScript("OnTextChanged", function(s, user)
            if user and box.readonly and box.orig and s:GetText() ~= box.orig then
                s:SetText(box.orig); s:HighlightText()
            end
        end)
        box.edit, box.scroll = eb, sf
        box.ok = W.Button(box, 150, 24, "OK", true)
        box.ok:SetPoint("BOTTOMLEFT", 14, 14)
        box.close = W.Button(box, 110, 24, "Close")
        box.close:SetPoint("BOTTOMRIGHT", -14, 14)
        box.close:SetScript("OnClick", function() box:Hide() end)
        tinsert(UISpecialFrames, "CysTextBox")
        box:Hide()
    end
    box.title:SetText(title or "")
    box.hint:SetText(hint or "")
    box.readonly = opts.readonly and true or false
    box.orig = box.readonly and text or nil
    box.edit:SetText(text or "")
    local _, newlines = (text or ""):gsub("\n", "\n")
    box.edit:SetHeight(max(250, 14 * (newlines + 1 + math.ceil(#(text or "") / 80)) + 10))
    box.scroll:SetVerticalScroll(0)
    if opts.onAccept then
        box.ok:Show()
        box.ok:SetLabel(opts.acceptLabel or "OK")
        box.ok:SetScript("OnClick", function()
            local t = box.edit:GetText()
            box:Hide()
            opts.onAccept(t)
        end)
    else
        box.ok:Hide()
    end
    box:Show()
    box.edit:SetFocus()
    if text and text ~= "" then box.edit:HighlightText() end
end

--------------------------------------------------------------------------------
-- Settings string: a small safe serializer + base64, so the whole thing is one pasteable line
--------------------------------------------------------------------------------
local function Ser(v, out, depth)
    local t = type(v)
    if t == "table" then
        if depth > 12 then return end
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                Ser(k, out, depth + 1)
                Ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. string.format("%.10g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    end
end

-- returns ok, value, nextIndex
local function Parse(s, i, depth)
    if depth > 14 then return false end
    local c = s:sub(i, i)
    if c == "{" then
        local tbl = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then return false end
            local ok, k, ni = Parse(s, i, depth + 1)
            if not ok or type(k) == "table" or type(k) == "boolean" then return false end
            local ok2, v, ni2 = Parse(s, ni, depth + 1)
            if not ok2 then return false end
            tbl[k] = v
            i = ni2
        end
        return true, tbl, i + 1
    elseif c == "s" then
        local len, after = s:match("^(%d+):()", i + 1)
        if not len then return false end
        len = tonumber(len)
        if after + len - 1 > #s then return false end
        return true, s:sub(after, after + len - 1), after + len
    elseif c == "n" then
        local j = s:find(";", i + 1, true)
        if not j then return false end
        local n = tonumber(s:sub(i + 1, j - 1))
        if not n then return false end
        return true, n, j + 1
    elseif c == "T" then return true, true, i + 1
    elseif c == "F" then return true, false, i + 1
    end
    return false
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Enc(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end
local function Dec(str)
    str = str:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #str, 4 do
        local n, pad = 0, 0
        for j = 0, 3 do
            local ch = str:sub(i + j, i + j)
            local v
            if ch == "=" or ch == "" then v = 0; pad = pad + 1 else v = B64:find(ch, 1, true); if not v then return nil end v = v - 1 end
            n = n * 64 + v
        end
        local b1, b2, b3 = floor(n / 65536) % 256, floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(b1)
        if pad < 2 then out[#out + 1] = string.char(b2) end
        if pad < 1 then out[#out + 1] = string.char(b3) end
    end
    return table.concat(out)
end

function CUI:ExportProfile()
    local out = {}
    Ser(CysUIDB or {}, out, 0)
    return "CYS1:" .. Enc(table.concat(out))
end

function CUI:ImportProfile(str)
    str = (str or ""):gsub("%s", "")
    local body = str:match("^CYS1:(.+)$")
    if not body then return false, "That doesn't look like a Cys's UI settings string (it should start with CYS1:)." end
    local raw = Dec(body)
    if not raw then return false, "The settings string is damaged (bad characters)." end
    local ok, tbl = Parse(raw, 1, 0)
    if not ok or type(tbl) ~= "table" then return false, "The settings string is damaged or cut short." end
    for k in pairs(CysUIDB) do CysUIDB[k] = nil end
    for k, v in pairs(tbl) do CysUIDB[k] = v end
    return true
end

--------------------------------------------------------------------------------
-- Reset everything
--------------------------------------------------------------------------------
StaticPopupDialogs["CYSUI_RESET_ALL"] = {
    text = "Reset ALL Cys's UI settings and positions to their defaults? The UI reloads. (Bag, set and skill data are kept.)",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        for k in pairs(CysUIDB) do CysUIDB[k] = nil end
        ReloadUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function CUI:ResetEverything() StaticPopup_Show("CYSUI_RESET_ALL") end

-- Buttons used by the General page
function CUI:ShowDebugBox()
    self:ShowTextBox("Debug info", "Select all (Ctrl+A), copy (Ctrl+C) and paste it into your bug report.",
        table.concat(self:DebugLines(), "\n"), { readonly = true })
end
function CUI:ShowExportBox()
    self:ShowTextBox("Export settings", "Copy this line (Ctrl+A, Ctrl+C) and send it to a friend. They paste it under Import.",
        self:ExportProfile(), { readonly = true })
end
function CUI:ShowImportBox()
    self:ShowTextBox("Import settings", "Paste a settings string here (Ctrl+V), then press Import. This replaces your current settings and reloads the UI.",
        "", { acceptLabel = "Import and reload", onAccept = function(text)
            local ok, err = CUI:ImportProfile(text)
            if ok then ReloadUI() else CUI:Print("|cFFFF4040Import failed:|r " .. err) end
        end })
end
