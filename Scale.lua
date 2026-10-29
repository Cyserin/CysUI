--------------------------------------------------------------------------------
-- Cys's UI - UI Scale
--
-- Cys's UI is designed for a "pixel-perfect" screen: one UI unit is one real pixel, so
-- at 1920x1080 the UI is 1920 x 1080 units. That is what ElvUI sets up for you, and it is
-- why everything suddenly looks HUGE when ElvUI is switched off: the game's default scale
-- at 1080p is the same as a 1366 x 768 screen blown up.
--
--   Pixel perfect:  scale = 768 / your screen height  (1080p -> 0.711, 1440p -> 0.533)
--   Custom:         pick a percentage yourself
--   Off:            leave the game's own UI scale alone
--
-- On first start it asks once whether to switch to pixel perfect. Everything in Cys's UI
-- (and Blizzard's own frames, chat and action bars) scales together.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min

local S = {}
CUI.Scale = S

local function DB() return CysUIDB.scale end

local MIN_SCALE, MAX_SCALE = 0.35, 1.0

--------------------------------------------------------------------------------
-- Screen size and the scale we want
--------------------------------------------------------------------------------
function S:ScreenSize()
    if GetPhysicalScreenSize then
        local w, h = GetPhysicalScreenSize()
        if w and h and h > 0 then return w, h end
    end
    local scale = UIParent:GetEffectiveScale()
    local w, h = GetScreenWidth() * scale, GetScreenHeight() * scale -- fallback: estimate
    return floor(w + 0.5), floor(h + 0.5)
end

function S:PixelPerfect()
    local _, h = self:ScreenSize()
    return max(MIN_SCALE, min(MAX_SCALE, 768 / h))
end

function S:Target()
    local db = DB()
    if db.mode == "pixel" then return self:PixelPerfect() end
    if db.mode == "layout" then return 768 / 1080 end -- UIParent is 1920 x 1080 units on any screen
    if db.mode == "custom" then return max(MIN_SCALE, min(MAX_SCALE, (db.percent or 100) / 100)) end
    return nil -- "off"
end

--------------------------------------------------------------------------------
-- Applying it
--------------------------------------------------------------------------------
function S:Apply()
    local scale = self:Target()
    if not scale then return end
    if InCombatLockdown() then self.pending = true; return end
    self.pending = false
    -- Keep the game's own setting in step when the value is one its slider allows, so its
    -- video options don't fight us; otherwise set the scale on UIParent directly.
    if scale >= 0.64 and scale <= 1 then
        if GetCVar("useUiScale") ~= "1" then pcall(SetCVar, "useUiScale", "1") end
        local current = tonumber(GetCVar("uiScale")) or 0
        if math.abs(current - scale) > 0.001 then pcall(SetCVar, "uiScale", format("%.3f", scale)) end
    end
    UIParent:SetScale(scale)
end

local function Reapply() C_Timer.After(0.2, function() S:Apply() end) end

--------------------------------------------------------------------------------
-- First-start question
--------------------------------------------------------------------------------
StaticPopupDialogs["CYSUI_SCALE"] = {
    text = "Cys's UI is designed for a pixel-perfect scale. Your screen is %s: set the UI scale to %s? "
        .. "Everything gets smaller and sharper, like ElvUI's default. You can change this any time in /cui > UI Scale.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() DB().mode = "pixel"; DB().prompted = true; S:Apply() end,
    OnCancel = function() DB().prompted = true end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

local function MaybeAsk()
    local db = DB()
    if db.prompted or db.mode ~= "off" then return end
    local w, h = S:ScreenSize()
    local target = S:PixelPerfect()
    if math.abs(UIParent:GetScale() - target) < 0.03 then
        db.prompted = true -- already about right (e.g. ElvUI set it): nothing to ask
        return
    end
    StaticPopup_Show("CYSUI_SCALE", format("%dx%d", w, h), format("%.3f", target))
end

function S.Enable()
    Reapply()
    for _, ev in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        local f = S.events or CreateFrame("Frame")
        S.events = f
        pcall(f.RegisterEvent, f, ev)
    end
    S.events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not S.pending then return end
        Reapply()
    end)
    C_Timer.After(4, MaybeAsk)
end

CUI:RegisterModule({
    key = "scale",
    name = "UI Scale",
    addon = "CysUI",
    desc = "Sets a pixel-perfect UI scale for your resolution (the thing ElvUI does for you), so the UI isn't huge.",
    onEnable = S.Enable,
    open = function() CUI:OpenConfig("UI Scale") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("UI Scale", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "UI Scale", width):SetPoint("TOPLEFT", 0, -4)

    local info = W.Text(page, 12, T.text)
    info:SetPoint("TOPLEFT", 4, -34)
    info:SetWidth(width)
    info:SetJustifyV("TOP")
    info:SetSpacing(4)

    local buttons = {}
    local function Refresh()
        local w, h = S:ScreenSize()
        local mode = ({ pixel = "Pixel perfect", layout = "Match 1080p layout", custom = "Custom", off = "Off (the game's own scale)" })[db.mode] or db.mode
        info:SetText(format("Screen: |cFFFFD100%dx%d|r     Current UI scale: |cFFFFD100%.3f|r\n"
            .. "Pixel perfect for this screen: |cFFFFD100%.3f|r     Mode: |cFFFFD100%s|r", w, h, UIParent:GetScale(),
            S:PixelPerfect(), mode))
        for key, b in pairs(buttons) do b:SetPrimary(db.mode == key) end
    end

    local function SetMode(mode)
        db.mode = mode
        db.prompted = true
        if mode == "off" then
            CUI:Print("UI scale left to the game. Reload the UI if frames look off.")
        else
            S:Apply()
        end
        Refresh()
    end

    buttons.pixel = W.Button(page, 190, 24, "Pixel perfect (recommended)")
    buttons.pixel:SetPoint("TOPLEFT", 4, -84)
    buttons.pixel:SetScript("OnClick", function() SetMode("pixel") end)
    buttons.off = W.Button(page, 190, 24, "Leave it to the game")
    buttons.off:SetPoint("LEFT", buttons.pixel, "RIGHT", 8, 0)
    buttons.off:SetScript("OnClick", function() SetMode("off") end)

    buttons.layout = W.Button(page, 388, 24, "Match the 1080p layout (for 1440p / 4K screens)")
    buttons.layout:SetPoint("TOPLEFT", 4, -114)
    buttons.layout:SetScript("OnClick", function() SetMode("layout") end)

    W.Header(page, "Custom", width):SetPoint("TOPLEFT", 0, -150)
    local step = W.Stepper(page, "UI scale", function() return db.percent end,
        function(v) db.percent = v; db.mode = "custom"; db.prompted = true; S:Apply(); Refresh() end, 40, 100, 1, "%")
    step:SetPoint("TOPLEFT", 4, -180)

    local note = W.Notes(page, 4, -224, width, "Lower numbers make everything smaller.", {
            { "Pixel perfect", "at 1920x1080 it is 0.711, which is what ElvUI uses and what Cys's UI's sizes and default positions are designed around." },
            { "After changing it", "open /cui layout to check where things sit." },
            { "On a 1440p or 4K screen", "pixel perfect makes the UI physically smaller (2560x1440 units); \"Match the 1080p layout\" keeps the same size and positions you would get on a 1080p screen (1920x1080 units), just sharper." },
            "The game's own Video options UI scale slider is kept in step when it can be.",
        })
    page.refresh = Refresh
    Refresh()
end, function(page) if page.refresh then page.refresh() end end)
