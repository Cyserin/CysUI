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
        eb:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "")
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
    -- the module switches in the string are this character's
    local copy = {}
    for k, v in pairs(CysUIDB or {}) do copy[k] = v end
    copy.modules = CUI:GetModuleSwitches()
    Ser(copy, out, 0)
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
    CUI:SetModuleSwitches(tbl.modules) -- imported switches apply to this character
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
        CUI:SetModuleSwitches({}) -- this character: every module back on
        CysUICompat.Reload()
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
            if ok then CysUICompat.Reload() else CUI:Print("|cFFFF4040Import failed:|r " .. err) end
        end })
end

--------------------------------------------------------------------------------
-- Profiles: whole setups (settings, positions, module switches) saved by name, swapped with one click.
-- The live settings are always CysUIDB; the other profiles wait in CysUIDB.profiles.list as copies.
-- Swapping needs a reload (modules read their settings when they load), so a swap is written down as
-- "pending" and done at the very start of the next load, before anything reads the settings.
-- Data that belongs to you rather than to a layout (character lists, run history, recruiter lists, bug
-- reports, Upgrade weights...) is shared by every profile and never swapped.
--------------------------------------------------------------------------------
local SHARED = {
    profiles = true, characters = true, runs = true, recruit = true, rested = true, bugs = true,
    trainerScan = true, dungeonMobs = true, spotlight = true, update = true, perf = true, dev = true,
    welcomeSeen = true, conflictsSnoozed = true, conflicts = true, hello = true, changelogSeen = true,
    talentPlans = true, armory = true, sideFolded = true, layoutMinimized = true, layoutFilter = true,
    killtracker = true, recipes = true, upgrade = true, macros = true, waypoints = true,
}
CUI.PROFILE_SHARED = SHARED
local DEFAULT_NAME = "Default"

local function Copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > 20 then return nil end
    local out = {}
    for k, val in pairs(v) do
        local vt = type(val)
        if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then out[k] = Copy(val, depth + 1) end
    end
    return out
end

local function Store()
    CysUIDB = CysUIDB or {}
    local P = CysUIDB.profiles
    if type(P) ~= "table" then P = {}; CysUIDB.profiles = P end
    if type(P.list) ~= "table" then P.list = {} end
    if type(P.spec) ~= "table" then P.spec = {} end
    if type(P.active) ~= "string" or P.active == "" then P.active = DEFAULT_NAME end
    return P
end

-- a copy of the live settings (without the shared data), plus this character's module switches
local function Snapshot()
    local snap = {}
    for k, v in pairs(CysUIDB or {}) do
        if not SHARED[k] then snap[k] = Copy(v) end
    end
    snap._charModules = Copy(CUI:GetModuleSwitches())
    return snap
end

function CUI:ProfileNames()
    local P = Store()
    local names, seen = {}, {}
    for name in pairs(P.list) do names[#names + 1] = name; seen[name] = true end
    if not seen[P.active] then names[#names + 1] = P.active end
    table.sort(names, function(a, b)
        if a == DEFAULT_NAME then return b ~= DEFAULT_NAME end
        if b == DEFAULT_NAME then return false end
        return a:lower() < b:lower() or (a:lower() == b:lower() and a < b)
    end)
    return names
end
function CUI:ActiveProfile() return Store().active end
-- the profile that will be live after the next reload (the active one when nothing is waiting)
function CUI:NextProfile() local P = Store(); return P.pending or P.active end
function CUI:ProfilePending() local P = Store(); return P.pending ~= nil and P.pending ~= P.active and P.pending or nil end

local listeners = {}
function CUI:OnProfilesChanged(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
    if CUI.UpdateSettingsFooter then pcall(CUI.UpdateSettingsFooter) end
end

-- pick the profile to load after the next reload (picking the live one cancels a waiting swap)
function CUI:SwitchProfile(name)
    local P = Store()
    if name == P.active then P.pending = nil
    elseif P.list[name] then P.pending = name end
    Changed()
end

-- Called by Core.lua first thing on load, before defaults are filled in and before any module reads its settings.
function CUI:ApplyPendingProfile()
    if type(CysUIDB) ~= "table" or type(CysUIDB.profiles) ~= "table" then return end
    local P = Store()
    local to = P.pending
    P.pending = nil
    if not to or to == P.active or type(P.list[to]) ~= "table" then return end
    P.list[P.active] = Snapshot()
    local snap = P.list[to]
    for k in pairs(CysUIDB) do if not SHARED[k] then CysUIDB[k] = nil end end
    for k, v in pairs(snap) do
        if k ~= "_charModules" and not SHARED[k] then CysUIDB[k] = Copy(v) end
    end
    if type(snap._charModules) == "table" then CUI:SetModuleSwitches(snap._charModules) end
    P.list[to] = nil -- it is the live settings now
    P.justLoaded = to
    P.active = to
end

local function UniqueName(base)
    local P = Store()
    base = (base or "Profile"):gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then base = "Profile" end
    base = base:sub(1, 24)
    local name, n = base, 2
    while P.list[name] or P.active == name do name = base .. " " .. n; n = n + 1 end
    return name
end

-- New: starts from the default settings. Copy: starts from the live settings.
function CUI:NewProfile(name, fromCurrent)
    local P = Store()
    name = UniqueName(name)
    P.list[name] = fromCurrent and Snapshot() or { _charModules = {} }
    Changed()
    return name
end

function CUI:RenameProfile(old, new)
    local P = Store()
    new = (new or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24)
    if new == "" or new == old then return end
    if P.list[new] or P.active == new then CUI:Print("A profile called " .. new .. " already exists.") return end
    if P.active == old then P.active = new
    elseif P.list[old] then P.list[new], P.list[old] = P.list[old], nil
    else return end
    if P.pending == old then P.pending = new end
    for _, map in pairs(P.spec) do
        if type(map) == "table" then
            for k, v in pairs(map) do if v == old then map[k] = new end end
        end
    end
    Changed()
end

function CUI:DeleteProfile(name)
    local P = Store()
    if name == P.active or not P.list[name] then return end
    P.list[name] = nil
    if P.pending == name then P.pending = nil end
    for _, map in pairs(P.spec) do
        if type(map) == "table" then
            for k, v in pairs(map) do if v == name then map[k] = nil end end
        end
    end
    Changed()
end

-- export one profile as a CYS1: string (the same format as Export settings, so either can be imported)
function CUI:ExportNamedProfile(name)
    local P = Store()
    if name == nil or name == P.active then return CUI:ExportProfile() end
    local snap = P.list[name]
    if not snap then return "" end
    local copy = {}
    for k, v in pairs(snap) do if k ~= "_charModules" then copy[k] = v end end
    copy.modules = snap._charModules or {}
    local out = {}
    Ser(copy, out, 0)
    return "CYS1:" .. Enc(table.concat(out))
end

-- import a CYS1: string as a new profile (nothing live changes until you pick it)
function CUI:ImportAsProfile(str, name)
    str = (str or ""):gsub("%s", "")
    local body = str:match("^CYS1:(.+)$")
    if not body then return false, "That doesn't look like a Cys's UI settings string (it should start with CYS1:)." end
    local raw = Dec(body)
    if not raw then return false, "The settings string is damaged (bad characters)." end
    local ok, tbl = Parse(raw, 1, 0)
    if not ok or type(tbl) ~= "table" then return false, "The settings string is damaged or cut short." end
    local snap = {}
    for k, v in pairs(tbl) do if not SHARED[k] and k ~= "modules" then snap[k] = v end end
    snap._charModules = type(tbl.modules) == "table" and tbl.modules or {}
    local P = Store()
    name = UniqueName(name or "Imported")
    P.list[name] = snap
    Changed()
    return true, name
end

--------------------------------------------------------------------------------
-- Swap by spec: each character can tie a profile to its Primary and Secondary spec
--------------------------------------------------------------------------------
local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    return (name or "?") .. "-" .. (realm or "")
end
local function SpecMap()
    local P = Store()
    local key = CharKey()
    if type(P.spec[key]) ~= "table" then P.spec[key] = {} end
    return P.spec[key]
end
function CUI:SpecProfile(group) return SpecMap()[group] end
function CUI:SetSpecProfile(group, name) SpecMap()[group] = (name ~= "" and name) or nil end
function CUI:SpecSwapOn() return SpecMap().auto == true end
function CUI:SetSpecSwap(on) SpecMap().auto = on and true or nil end
local function ActiveGroup()
    local fn = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup) or GetActiveTalentGroup
    local ok, g = pcall(fn)
    return ok and tonumber(g) or 1
end
CUI.ActiveTalentGroup = ActiveGroup

-- a small Cys pop-up: "Switch to Healer?" The button is a real /reload click on WoW Forever.
local swapBox
local function SwapBox()
    if swapBox then return swapBox end
    local f = CreateFrame("Frame", "CysProfileSwapBox", UIParent)
    f:SetSize(320, 104)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")
    f.title = W.Text(f, 13, T.accent, "CENTER")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("Profile for this spec")
    f.text = W.Text(f, 12, T.text, "CENTER")
    f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
    f.text:SetWidth(296)
    f.go = W.Button(f, 150, 24, "Switch and reload", true)
    f.go:SetPoint("BOTTOMLEFT", 14, 12)
    f.no = W.Button(f, 120, 24, "Not now")
    f.no:SetPoint("BOTTOMRIGHT", -14, 12)
    f.no:SetScript("OnClick", function() f.declined = f.target; f:Hide() end)
    f.go:SetScript("OnClick", function()
        if f.target then CUI:SwitchProfile(f.target) end
        CysUICompat.Reload()
    end)
    CysUICompat.SecureReload(f.go, f, function() if f.target then CUI:SwitchProfile(f.target) end end)
    tinsert(UISpecialFrames, "CysProfileSwapBox")
    f:Hide()
    swapBox = f
    return f
end

local function CheckSpec()
    if not CUI:SpecSwapOn() then return end
    local want = CUI:SpecProfile(ActiveGroup())
    if not want or want == CUI:ActiveProfile() then return end
    if not (Store().list[want]) then return end
    local f = SwapBox()
    if f.declined == want then return end
    f.target = want
    f.text:SetText("Load your |cFFFFD100" .. want .. "|r profile? The UI reloads.")
    if InCombatLockdown() then f.waiting = true return end
    f:Show()
end

local specEvents = CreateFrame("Frame")
specEvents:RegisterEvent("PLAYER_LOGIN")
specEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(specEvents.RegisterEvent, specEvents, "ACTIVE_TALENT_GROUP_CHANGED")
pcall(specEvents.RegisterEvent, specEvents, "PLAYER_SPECIALIZATION_CHANGED")
specEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    if event == "PLAYER_LOGIN" then
        local P = Store()
        if P.justLoaded then
            local name = P.justLoaded
            P.justLoaded = nil
            C_Timer.After(3, function() CUI:Print("Profile loaded: |cFFFFD100" .. name .. "|r") end)
        end
        C_Timer.After(4, CheckSpec)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if swapBox and swapBox.waiting then swapBox.waiting = nil; CheckSpec() end
    else
        if swapBox then swapBox.declined = nil end
        C_Timer.After(1, CheckSpec)
    end
end)

--------------------------------------------------------------------------------
-- Name prompt (StaticPopup with a text box)
--------------------------------------------------------------------------------
local function PopupEdit(self) return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()) end
StaticPopupDialogs["CYSUI_PROFILE_NAME"] = {
    text = "%s",
    button1 = "OK",
    button2 = "Cancel",
    hasEditBox = 1,
    maxLetters = 24,
    OnShow = function(self, data)
        local eb = PopupEdit(self)
        if eb then eb:SetText(data and data.default or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEdit(self)
        if data and data.fn and eb then data.fn(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self, data)
        local parent = self:GetParent()
        if data and data.fn then data.fn(self:GetText()) end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
local function AskName(prompt, default, fn)
    StaticPopup_Show("CYSUI_PROFILE_NAME", prompt, nil, { default = default, fn = fn })
end
StaticPopupDialogs["CYSUI_PROFILE_DELETE"] = {
    text = "Delete the profile %s? This can't be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data) if data then CUI:DeleteProfile(data) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Profiles page
--------------------------------------------------------------------------------
local function ProfileOptions()
    local out = {}
    for _, n in ipairs(CUI:ProfileNames()) do out[#out + 1] = { n, n } end
    return out
end
CUI.ProfileOptions = ProfileOptions

CUI:RegisterPage("Profiles", function(page)
    local width = 520
    local selected = CUI:ActiveProfile() -- the profile the buttons act on

    W.Header(page, "Active profile", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.desc)
    intro:SetPoint("TOPLEFT", 4, -32)
    intro:SetWidth(width - 8)
    intro:SetJustifyH("LEFT")
    intro:SetText("A profile is a whole setup: settings, frame positions and which modules are on. Swapping reloads the UI.")
    local dd = W.Dropdown(page, 220, ProfileOptions, function() return CUI:NextProfile() end, function(v) CUI:SwitchProfile(v) end)
    dd:SetPoint("TOPLEFT", 4, -58)
    page.dd = dd
    local state = W.Text(page, 11, T.accent)
    state:SetPoint("LEFT", dd, "RIGHT", 12, 0)
    page.state = state

    W.Header(page, "Your profiles", width):SetPoint("TOPLEFT", 0, -100)
    local rowsTop = -128
    page.rows = {}
    local function Row(i)
        local r = page.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, page)
        r:SetSize(width - 8, 26)
        r:SetPoint("TOPLEFT", 4, rowsTop - (i - 1) * 28)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetColorTexture(1, 1, 1, 0.045)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.sel = W.Texture(r, "BACKGROUND", T.brand, 1)
        r.sel:SetPoint("TOPLEFT"); r.sel:SetPoint("BOTTOMLEFT"); r.sel:SetWidth(2)
        r.name = W.Text(r, 12, T.text)
        r.name:SetPoint("LEFT", 12, 0)
        r.note = W.Text(r, 11, T.desc)
        r.note:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
        r.use = W.Button(r, 70, 20, "Use")
        r.use:SetPoint("RIGHT", -2, 0)
        r.use:SetScript("OnClick", function(s) CUI:SwitchProfile(s:GetParent().profile) end)
        r:SetScript("OnEnter", function(s) s.hl:Show() end)
        r:SetScript("OnLeave", function(s) s.hl:Hide() end)
        r:SetScript("OnClick", function(s) selected = s.profile; page:RefreshProfiles() end)
        page.rows[i] = r
        return r
    end

    -- everything under the list hangs from this anchor, which moves down as profiles are added
    local anchor = CreateFrame("Frame", nil, page)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", 0, -218)
    local function At(obj, x, dy) obj:ClearAllPoints(); obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, dy); return obj end
    -- actions on the selected row
    local bNew = W.Button(page, 80, 22, "New")
    local bCopy = W.Button(page, 80, 22, "Copy")
    local bRen = W.Button(page, 80, 22, "Rename")
    local bDel = W.Button(page, 80, 22, "Delete")
    page.actions = { bNew, bCopy, bRen, bDel }
    bNew:SetScript("OnClick", function()
        AskName("Name for the new profile (starts from the default settings):", "Healer", function(t)
            selected = CUI:NewProfile(t, false); page:RefreshProfiles()
        end)
    end)
    bCopy:SetScript("OnClick", function()
        AskName("Name for the copy of " .. selected .. ":", selected .. " copy", function(t)
            local P = Store()
            local name = UniqueName(t)
            P.list[name] = (selected == P.active) and Snapshot() or Copy(P.list[selected])
            selected = name; Changed()
        end)
    end)
    bRen:SetScript("OnClick", function()
        local old = selected
        AskName("New name for " .. old .. ":", old, function(t)
            CUI:RenameProfile(old, t)
            local P = Store()
            if not P.list[old] and P.active ~= old then selected = (t:gsub("^%s+", ""):gsub("%s+$", "")) end
            page:RefreshProfiles()
        end)
    end)
    bDel:SetScript("OnClick", function()
        StaticPopup_Show("CYSUI_PROFILE_DELETE", selected, nil, selected)
    end)

    At(W.Header(page, "Swap by spec", width), 0, -44)
    local auto = W.Checkbox(page, "Swap profiles when you change spec (this character, asks first)",
        function() return CUI:SpecSwapOn() end, function(v) CUI:SetSpecSwap(v) end)
    At(auto, 4, -74)
    local NONE = "-"
    local function SpecOptions()
        local out = { { NONE, "No profile" } }
        for _, o in ipairs(ProfileOptions()) do out[#out + 1] = o end
        return out
    end
    local specDD = {}
    for g = 1, 2 do
        local lbl = W.Text(page, 12, T.text)
        At(lbl, 4, -106 - (g - 1) * 30)
        lbl:SetText(g == 1 and "Primary spec" or "Secondary spec")
        local d = W.Dropdown(page, 200, SpecOptions, function() return CUI:SpecProfile(g) or NONE end,
            function(v) CUI:SetSpecProfile(g, v ~= NONE and v or nil) end)
        At(d, 140, -102 - (g - 1) * 30)
        specDD[g] = d
    end
    page.specNow = W.Text(page, 11, T.desc)
    At(page.specNow, 4, -166)

    At(W.Header(page, "Share", width), 0, -196)
    local ex = W.Button(page, 150, 22, "Export selected")
    At(ex, 4, -226)
    ex:SetScript("OnClick", function()
        CUI:ShowTextBox("Export profile: " .. selected, "Copy this line (Ctrl+A, Ctrl+C) and send it to a friend. They paste it under Import as a new profile.",
            CUI:ExportNamedProfile(selected), { readonly = true })
    end)
    local im = W.Button(page, 180, 22, "Import as a new profile")
    im:SetPoint("LEFT", ex, "RIGHT", 8, 0)
    im:SetScript("OnClick", function()
        CUI:ShowTextBox("Import profile", "Paste a settings string here (Ctrl+V), then press Import. It is added as a new profile; nothing changes until you pick it.",
            "", { acceptLabel = "Import", onAccept = function(text)
                local ok, res = CUI:ImportAsProfile(text)
                if ok then selected = res; page:RefreshProfiles(); CUI:Print("Imported as the profile |cFFFFD100" .. res .. "|r.")
                else CUI:Print("|cFFFF4040Import failed:|r " .. res) end
            end })
    end)
    local notes = W.Notes(page, 4, -478, width - 8, "", {
        { "Shared by every profile", "character lists, run history, recruiter lists, Upgrade weights, talent plans and bug reports." },
        { "Healer layout", "press Copy on your main profile, pick the copy, reload, then move and resize frames in Layout mode." },
    })
    At(notes, 4, -260)

    function page:RefreshProfiles()
        local P = Store()
        local names = CUI:ProfileNames()
        local found = false
        for _, n in ipairs(names) do if n == selected then found = true end end
        if not found then selected = P.active end
        local nextName = CUI:NextProfile()
        for i, n in ipairs(names) do
            local r = Row(i)
            r.profile = n
            r.name:SetText(n)
            local isSel = n == selected
            local c = isSel and T.accent or T.text
            r.name:SetTextColor(c[1], c[2], c[3])
            r.sel:SetShown(isSel)
            local note = ""
            if n == P.active and n == nextName then note = "in use"
            elseif n == P.active then note = "in use until you reload"
            elseif n == nextName then note = "loads after a reload" end
            r.note:SetText(note)
            r.use:SetShown(n ~= nextName)
            r:Show()
        end
        for i = #names + 1, #page.rows do page.rows[i]:Hide() end
        local y = rowsTop - #names * 28 - 6
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", 0, y)
        for k, b in ipairs(page.actions) do At(b, 4 + (k - 1) * 88, 0) end
        page.contentHeight = -y + 340
        bDel:SetActive(selected ~= P.active)
        dd:Refresh()
        for g = 1, 2 do specDD[g]:Refresh() end
        auto:Refresh()
        local pend = CUI:ProfilePending()
        state:SetText(pend and ("Reload to load " .. pend) or "")
        page.specNow:SetText("You are in your " .. (ActiveGroup() == 2 and "Secondary" or "Primary") .. " spec.")
        if CUI.RelayoutSettingsPage then CUI.RelayoutSettingsPage(page) end
    end
    CUI:OnProfilesChanged(function() if page:IsShown() then page:RefreshProfiles() end end)
    page:RefreshProfiles()
end, function(page) if page.RefreshProfiles then page:RefreshProfiles() end end)
