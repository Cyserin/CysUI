--------------------------------------------------------------------------------
-- Cys's Resource Bar - your rage, energy or mana as its own bar
--
-- One flat bar for whatever your character is spending right now (it follows a Druid through forms), placed in
-- Layout mode and sized on its settings page. Made to sit with the cooldown bars: it can take the main cooldown
-- bar's width so the two line up.
--
-- Works on Classic Era and WoW Forever. The amounts go straight from the game into the bar and its text, so
-- nothing here does math on a value the game may lock.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "resource", name = "Cys's Resource Bar",
    desc = "Your rage, energy or mana as its own bar for every class: move it in Layout mode, set its width and height, pick the text. It can match the width of Cys's main cooldown bar.",
    open = function() CysUI:OpenConfig("Resource Bar") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Secret = CysUICompat.Secret

CysUIDB.resource = CysUIDB.resource or {}
local db = CysUIDB.resource
local DEFAULTS = { width = 240, height = 16, text = "current", label = true, match = true, show = "always", fontSize = 12 }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MOVER = "resource"
local FALLBACK = { MANA = { 0.3, 0.5, 1 }, RAGE = { 0.9, 0.2, 0.2 }, FOCUS = { 1, 0.5, 0.25 }, ENERGY = { 1, 0.9, 0.2 } }
local NAMES = { MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy", RUNIC_POWER = "Runic Power" }

local holder = CreateFrame("Frame", "CysResourceBar", UIParent)
holder:SetSize(db.width, db.height)
holder:SetPoint("CENTER", UIParent, "CENTER", 0, -118)
holder:SetFrameStrata("MEDIUM")
local back = holder:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints()
back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.9)
local bar = CreateFrame("StatusBar", nil, holder)
bar:SetPoint("TOPLEFT", 1, -1)
bar:SetPoint("BOTTOMRIGHT", -1, 1)
bar:SetStatusBarTexture(FLAT)
local top = CreateFrame("Frame", nil, holder)
top:SetAllPoints()
top:SetFrameLevel(bar:GetFrameLevel() + 1)
W.Border(top, 1, T.border, "OVERLAY") -- follows the Border color setting
local text = top:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", 0, 0)
local label = top:CreateFontString(nil, "OVERLAY")
label:SetPoint("LEFT", 5, 0)

CUI:RegisterMovable(holder, MOVER, "Resource Bar", { point = "CENTER", x = 0, y = -118 })

local function ApplyFont()
    for _, fs in ipairs({ text, label }) do
        fs:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
        fs:SetTextColor(1, 1, 1)
    end
    label:SetTextColor(0.85, 0.85, 0.85)
end

-- width: your own number, or the main cooldown bar's when that bar is on and Match is ticked
local function WantedWidth()
    local main = db.match and _G.CysCooldownBar_main
    if main and main:IsShown() then
        local w = main:GetWidth()
        if type(w) == "number" and w > 20 then
            return w * (main:GetEffectiveScale() or 1) / (holder:GetEffectiveScale() or 1)
        end
    end
    return db.width
end
local lastW, lastH
local function ApplySize()
    local w, h = WantedWidth(), db.height
    if w == lastW and h == lastH then return end
    lastW, lastH = w, h
    holder:SetSize(w, h)
    CUI:ApplyLayout(MOVER) -- the Layout mode box follows
end

local function Update()
    local ptype, token = UnitPowerType("player")
    local c = (PowerBarColor and token and PowerBarColor[token]) or (PowerBarColor and PowerBarColor[ptype])
    if c and c.r then
        bar:SetStatusBarColor(c.r, c.g, c.b)
    else
        local d = FALLBACK[token or ""] or { 0.6, 0.6, 0.6 }
        bar:SetStatusBarColor(d[1], d[2], d[3])
    end
    -- straight from the game into the bar: locked or not, the bar can show it
    pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax("player"))
    pcall(bar.SetValue, bar, UnitPower("player"))
    local cur, mx = UnitPower("player"), UnitPowerMax("player")
    if db.text == "off" then
        text:SetText("")
    elseif db.text == "percent" and not Secret(cur) and not Secret(mx) and type(mx) == "number" and mx > 0 then
        text:SetFormattedText("%d%%", cur / mx * 100 + 0.5) -- plain numbers (Classic Era, or unlocked): our own math is fine
    else
        CysUICompat.LockedUnitText(text, "player", "power", db.text == "max" and "max" or db.text)
    end
    if db.label then
        label:SetText(string.upper(NAMES[token or ""] or (token and _G[token]) or ""))
    else
        label:SetText("")
    end
end

local function UpdateShown()
    local show = true
    if db.show == "combat" then show = InCombatLockdown() and true or false end
    if CUI.layoutMode then show = true end
    holder:SetAlpha(show and 1 or 0) -- faded, not hidden, so its Layout mode box keeps working
end

local function Refresh()
    ApplyFont()
    ApplySize()
    Update()
    UpdateShown()
end
CUI.ResourceRefresh = Refresh
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", UpdateShown) end -- always visible while placing it

local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_FREQUENT", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXPOWER", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_DISPLAYPOWER", "player")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "UPDATE_SHAPESHIFT_FORM")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateShown()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Refresh()
        C_Timer.After(1, Refresh) -- once more after the cooldown bars have built themselves
        return
    end
    Update()
end)

-- follow the main cooldown bar's width as it changes (it is our own frame, so a plain size hook is fine)
local hookedMain
local function HookMain()
    local main = _G.CysCooldownBar_main
    if hookedMain or not main then return end
    hookedMain = true
    main:HookScript("OnSizeChanged", function() C_Timer.After(0, ApplySize) end)
    ApplySize()
end
C_Timer.After(2, HookMain)
C_Timer.After(6, HookMain)

Refresh()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Resource Bar", function(page)
    local width = 480
    W.Header(page, "Resource Bar", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, y)
    intro:SetWidth(width - 8)
    intro:SetJustifyH("LEFT")
    intro:SetText("Your rage, energy or mana as its own bar. Move it in Layout mode (Resource Bar).")
    y = y - 30

    local function Check(text, key)
        W.Checkbox(page, text, function() return db[key] end, function(on) db[key] = on; Refresh() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    local function Step(text, key, lo, hi, step, suffix)
        W.Stepper(page, text, function() return db[key] end, function(v) db[key] = v; Refresh() end, lo, hi, step, suffix)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    Check("Match the width of Cys's main cooldown bar", "match")
    Step("Width", "width", 60, 800, 10, " px")
    Step("Height", "height", 6, 60, 1, " px")
    y = y - 6

    local lab = W.Text(page, 12, T.accent)
    lab:SetPoint("TOPLEFT", 4, y - 4)
    lab:SetText("Text")
    W.Dropdown(page, 230, { { "current", "current" }, { "max", "current / max" }, { "percent", "percent" }, { "off", "off" } },
        function() return db.text end, function(v) db.text = v; Refresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 30
    Step("Text size", "fontSize", 8, 24, 1)
    Check("Show the resource name on the left (RAGE, MANA...)", "label")
    y = y - 6

    local lab2 = W.Text(page, 12, T.accent)
    lab2:SetPoint("TOPLEFT", 4, y - 4)
    lab2:SetText("Show")
    W.Dropdown(page, 230, { { "always", "always" }, { "combat", "only in combat" } },
        function() return db.show end, function(v) db.show = v; Refresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 36

    W.Notes(page, 4, y, width, "", {
        { "Width", "your own Width is used when Match is off, or when Cys's own cooldown bars are not switched on." },
        { "Every class", "the bar shows what your character is spending right now and changes color with it - a Druid's bar follows the form." },
        { "Layout mode", "drag Resource Bar; the size setting on its box there scales the whole bar." },
    })
    page.contentHeight = -y + 110
end, function() end)

    end,
})
