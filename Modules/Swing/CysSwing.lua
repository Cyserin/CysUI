--------------------------------------------------------------------------------
-- Cys's Swing Timer (WoW Forever) - your auto attack as a thin bar
--
-- One flat bar that fills from one swing to the next: main hand, with a second line under it for an off hand
-- and a third for a ranged weapon while you are shooting. Placed in Layout mode and sized on its page; it can
-- take the width of Cys's main cooldown bar so it sits flush on top of the Resource Bar.
--
-- The game tells us when a swing starts and how long it lasts (PLAYER_SWING, new on Forever), so nothing is
-- guessed from the combat log. The bar only animates while a swing is running; the rest of the time it costs
-- nothing. The game's own swing timer is left alone (it has its own switch in the game's Options).
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "swing", name = "Cys's Swing Timer", foreverOnly = true, defaultOff = true,
    desc = "WoW Forever: your auto attack as a thin bar that fills from swing to swing, with extra lines for an off hand and a ranged weapon. Move it in Layout mode; it can match the width of Cys's main cooldown bar.",
    open = function() CysUI:OpenConfig("Swing Timer") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T
local Secret = CysUICompat.Secret

CysUIDB.swing = CysUIDB.swing or {}
local db = CysUIDB.swing
local DEFAULTS = { width = 240, height = 8, match = true, show = "combat", text = false, fontSize = 10,
    offhand = true, ranged = true, spark = true, color = "gold" }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MOVER = "swing"
local GAP = 1
local TYPES = Enum and Enum.PlayerSwingType or {}
local MAIN, OFF, RANGED = TYPES.MainHand or 0, TYPES.OffHand or 1, TYPES.Ranged or 2
local COLORS = { gold = nil, white = { 0.9, 0.9, 0.9 }, red = { 0.85, 0.25, 0.2 }, class = false }

local holder = CreateFrame("Frame", "CysSwingBar", UIParent)
holder:SetSize(db.width, db.height)
holder:SetPoint("CENTER", UIParent, "CENTER", 0, -104)
holder:SetFrameStrata("MEDIUM")
CUI:RegisterMovable(holder, MOVER, "Swing Timer", { point = "CENTER", x = 0, y = -104 })

-- one line: dark back, flat fill, thin edge, a bright tick at the fill's edge, optional time left
local rows = {}
local function MakeRow(kind)
    local r = CreateFrame("Frame", nil, holder)
    r.kind = kind
    local back = r:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.9)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", 1, -1)
    r.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    r.bar:SetStatusBarTexture(FLAT)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    r.spark = r.bar:CreateTexture(nil, "OVERLAY")
    r.spark:SetColorTexture(1, 1, 1, 0.9)
    r.spark:SetWidth(1)
    r.spark:SetPoint("TOP", r.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    r.spark:SetPoint("BOTTOM", r.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    r.spark:Hide()
    local top = CreateFrame("Frame", nil, r)
    top:SetAllPoints()
    top:SetFrameLevel(r.bar:GetFrameLevel() + 1)
    W.Border(top, 1, T.border, "OVERLAY") -- follows the Border color setting
    r.text = top:CreateFontString(nil, "OVERLAY")
    r.text:SetPoint("RIGHT", -3, 0)
    r:Hide()
    rows[kind] = r
    return r
end
MakeRow(MAIN); MakeRow(OFF); MakeRow(RANGED)

local function FillColor()
    local c = COLORS[db.color]
    if db.color == "class" then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if cc then return cc.r, cc.g, cc.b end
    end
    if c then return c[1], c[2], c[3] end
    return T.accent[1], T.accent[2], T.accent[3]
end

-- which lines exist right now: main hand always, off hand while one is equipped, ranged while a shot is running
local function Speeds()
    local main, off, ranged = UnitAttackSpeed("player")
    if Secret(main) then main = nil end
    if Secret(off) then off = nil end
    if Secret(ranged) then ranged = nil end
    return main, off, ranged
end
local function Wanted(kind)
    if kind == MAIN then return true end
    local _, off = Speeds()
    if kind == OFF then return db.offhand and type(off) == "number" and off > 0 end
    return db.ranged and rows[RANGED].ends ~= nil
end

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
local function Layout()
    local w, h = WantedWidth(), db.height
    local r, g, b = FillColor()
    local n = 0
    for _, kind in ipairs({ MAIN, OFF, RANGED }) do
        local row = rows[kind]
        if Wanted(kind) then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -n * (h + GAP))
            row:SetSize(w, h)
            row.bar:SetStatusBarColor(r, g, b, kind == MAIN and 1 or 0.75)
            row.text:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
            row.text:SetShown(db.text and h >= 8)
            row:Show()
            n = n + 1
        else
            row:Hide()
        end
    end
    local total = max(1, n) * h + (max(1, n) - 1) * GAP
    if w ~= lastW or total ~= lastH then
        lastW, lastH = w, total
        holder:SetSize(w, total)
        CUI:ApplyLayout(MOVER) -- the Layout mode box follows
    end
end

local function UpdateShown()
    local show = true
    if db.show == "combat" then show = UnitAffectingCombat("player") and true or false end
    if CUI.layoutMode then show = true end
    holder:SetAlpha(show and 1 or 0) -- faded, not hidden, so its Layout mode box keeps working
end

-- the only per-frame work, and only while at least one swing is running
local driver = CreateFrame("Frame")
local running = 0
local function Tick()
    local now = GetTime()
    local live = 0
    for _, row in pairs(rows) do
        if row.ends then
            local left = row.ends - now
            if left <= 0 then
                row.ends = nil
                row.bar:SetValue(0)
                row.spark:Hide()
                row.text:SetText("")
                if row.kind == RANGED then Layout() end -- the ranged line goes away between shots
            else
                row.bar:SetValue(1 - left / row.length)
                if db.text then row.text:SetFormattedText("%.1f", left) end
                live = live + 1
            end
        end
    end
    running = live
    if live == 0 then driver:SetScript("OnUpdate", nil) end
end

local function Swing(duration, kind)
    if Secret(duration) or Secret(kind) or type(duration) ~= "number" then
        -- a locked value: fall back to the weapon's own speed, which the game lets addons read
        local main, off, ranged = Speeds()
        if Secret(kind) then return end
        duration = (kind == OFF and off) or (kind == RANGED and ranged) or main
    end
    local row = rows[kind]
    if not row or type(duration) ~= "number" or duration <= 0 then return end
    local fresh = row.ends == nil
    row.length = duration
    row.ends = GetTime() + duration
    row.bar:SetValue(0)
    row.spark:SetShown(db.spark)
    if fresh and kind ~= MAIN then Layout() end
    if running == 0 then
        running = 1
        driver:SetScript("OnUpdate", Tick)
    end
end

local function Refresh()
    Layout()
    UpdateShown()
end
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", UpdateShown) end

local ev = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_SWING", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, event)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_INVENTORY_CHANGED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_ATTACK_SPEED", "player")
ev:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_SWING" then
        Swing(a, b)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateShown()
    else
        Refresh()
        if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(1, Refresh) end -- once more after the cooldown bars exist
    end
end)

-- follow the main cooldown bar's width as it changes (our own frame, so a plain size hook is fine)
local hookedMain
local function HookMain()
    local main = _G.CysCooldownBar_main
    if hookedMain or not main then return end
    hookedMain = true
    main:HookScript("OnSizeChanged", function() C_Timer.After(0, Layout) end)
    Layout()
end
C_Timer.After(2, HookMain)
C_Timer.After(6, HookMain)

Refresh()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Swing Timer", function(page)
    local width = 480
    W.Header(page, "Swing Timer", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, y)
    intro:SetWidth(width - 8)
    intro:SetJustifyH("LEFT")
    intro:SetText("Your auto attack as a thin bar that fills from one swing to the next. Move it in Layout mode (Swing Timer).")
    y = y - 34

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
    Step("Height of each line", "height", 3, 30, 1, " px")
    y = y - 6
    Check("A line for your off hand", "offhand")
    Check("A line for your ranged weapon while you shoot", "ranged")
    Check("Bright tick at the front of the bar", "spark")
    Check("Show the time left (lines 8 px or taller)", "text")
    Step("Text size", "fontSize", 7, 18, 1)
    y = y - 6

    local lab = W.Text(page, 12, T.accent)
    lab:SetPoint("TOPLEFT", 4, y - 4)
    lab:SetText("Color")
    W.Dropdown(page, 230, { { "gold", "gold (your accent)" }, { "class", "class color" }, { "white", "white" }, { "red", "red" } },
        function() return db.color end, function(v) db.color = v; Refresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 32
    local lab2 = W.Text(page, 12, T.accent)
    lab2:SetPoint("TOPLEFT", 4, y - 4)
    lab2:SetText("Show")
    W.Dropdown(page, 230, { { "combat", "only in combat" }, { "always", "always" } },
        function() return db.show end, function(v) db.show = v; Refresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 40

    local note = W.Notes(page, 4, y, width, "", {
        { "On top of the Resource Bar", "with Match ticked on both pages the two bars are the same width: drag Swing Timer onto the Resource Bar's top edge in Layout mode." },
        { "The game's own swing timer", "is separate (the game's Options). Switch it off there if you only want this one." },
        "The bar only animates while a swing is running, so it costs nothing out of combat.",
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 80) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
