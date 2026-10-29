--------------------------------------------------------------------------------
-- Cys's UI - Cast Bar
--
-- A flat cast bar for you and one for your target:
--   * spell icon, spell name, time left; gold for casts, blue for channels
--   * red "Interrupted" / "Failed" flash
--   * both move and resize in layout mode (/cui layout)
--
-- Classic doesn't report other players' and monsters' casts on every client. The target
-- bar simply shows whatever the game gives it, and stays hidden when there's nothing.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, max, min = string.format, math.max, math.min

local CB = {}
CUI.CastBar = CB
CB.bars = {}

local FLAT = "Interface\\Buttons\\WHITE8X8"
local function DB() return CysUIDB.castbar end

local hidden = CreateFrame("Frame")
hidden:Hide()

local COLOR_CAST = { T.accent[1], T.accent[2], T.accent[3] }
local COLOR_CHANNEL = { 0.3, 0.6, 1 }
local COLOR_FAIL = { 0.9, 0.2, 0.2 }

local function HideBlizzard(...)
    for _, name in ipairs({ ... }) do
        local fr = _G[name]
        if fr then
            pcall(function()
                if fr.UnregisterAllEvents then fr:UnregisterAllEvents() end
                fr:SetParent(hidden)
                fr:Hide()
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Reading a cast
--------------------------------------------------------------------------------
-- name, icon, start, end (seconds), isChannel
local function CastInfo(unit)
    if not UnitExists(unit) then return end
    local name, _, texture, startMS, endMS = UnitCastingInfo(unit)
    if name and startMS and endMS then return name, texture, startMS / 1000, endMS / 1000, false end
    name, _, texture, startMS, endMS = UnitChannelInfo(unit)
    if name and startMS and endMS then return name, texture, startMS / 1000, endMS / 1000, true end
end

--------------------------------------------------------------------------------
-- One bar
--------------------------------------------------------------------------------
local function Layout(f)
    local db = DB()
    local h = f:GetHeight()
    f.icon:SetShown(db.icon and true or false)
    f.iconEdges.frame:SetShown(db.icon and true or false)
    f.icon:SetSize(max(h - 2, 6), max(h - 2, 6))
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if db.icon then
        f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 1, 0)
        f.bar:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 1, 0)
    else
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    end
    f.time:SetShown(db.time and true or false)
end

local function Stop(f)
    f.casting, f.failedUntil = false, nil
    f:SetScript("OnUpdate", nil)
    f:Hide()
end

local function OnUpdate(f)
    local now = GetTime()
    if f.failedUntil then
        if now >= f.failedUntil then Stop(f) end
        return
    end
    local total = f.endT - f.startT
    if total <= 0 then return end
    local progress = f.channel and (f.endT - now) or (now - f.startT)
    f.bar:SetMinMaxValues(0, total)
    f.bar:SetValue(max(0, min(total, progress)))
    f.time:SetText(format("%.1f", max(0, f.endT - now)))
end

local function Refresh(f)
    local name, texture, startT, endT, channel = CastInfo(f.unit)
    if not name then
        if not f.failedUntil then Stop(f) end
        return
    end
    f.casting, f.channel, f.startT, f.endT, f.failedUntil = true, channel, startT, endT, nil
    local c = channel and COLOR_CHANNEL or COLOR_CAST
    f.bar:SetStatusBarColor(c[1], c[2], c[3])
    f.icon:SetTexture(texture)
    f.text:SetText(name)
    f:Show()
    f:SetScript("OnUpdate", OnUpdate)
    OnUpdate(f)
end

local function Fail(f, label)
    f.casting = false
    f.failedUntil = GetTime() + 0.6
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(1)
    f.bar:SetStatusBarColor(COLOR_FAIL[1], COLOR_FAIL[2], COLOR_FAIL[3])
    f.text:SetText(label)
    f.time:SetText("")
    f:Show()
    f:SetScript("OnUpdate", OnUpdate)
end

local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
                      "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
                      "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }

local function Create(key, unit, label, w, h, point, x, y)
    local f = CreateFrame("Frame", "CysUICastBar_" .. key, UIParent)
    f.unit = unit
    f:SetSize(w, h)
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    -- spell icon with its own thin edge
    local iconFrame = CreateFrame("Frame", nil, f)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("LEFT", f, "LEFT", 1, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconEdges = { frame = iconFrame }
    iconFrame:SetAllPoints(f.icon)
    W.Border(iconFrame, 1, T.line, "OVERLAY")

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetStatusBarTexture(FLAT)
    W.Texture(f.bar, "BACKGROUND", { T.field[1], T.field[2], T.field[3], 1 }):SetAllPoints()

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f.bar)
    overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f.text = overlay:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT, max(math.floor(h * 0.55), 9), "OUTLINE")
    f.text:SetPoint("LEFT", overlay, "LEFT", 5, 0)
    f.text:SetJustifyH("LEFT")
    f.time = overlay:CreateFontString(nil, "OVERLAY")
    f.time:SetFont(STANDARD_TEXT_FONT, max(math.floor(h * 0.55), 9), "OUTLINE")
    f.time:SetPoint("RIGHT", overlay, "RIGHT", -5, 0)
    f.text:SetPoint("RIGHT", f.time, "LEFT", -4, 0)

    Layout(f)
    CUI:RegisterMovable(f, "castbar_" .. key, label, { point = point, x = x, y = y, resizable = true,
        minW = 100, maxW = 600, minH = 10, maxH = 40, onResize = function(frame) Layout(frame) end })

    for _, ev in ipairs(CAST_EVENTS) do pcall(f.RegisterUnitEvent, f, ev, unit) end
    if unit ~= "player" then pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED") end
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event)
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            if self:IsShown() then Fail(self, "Interrupted") end
        elseif event == "UNIT_SPELLCAST_FAILED" then
            -- a failed second attempt shouldn't hide the cast that's still going
            if self:IsShown() and not CastInfo(self.unit) then Fail(self, "Failed") end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if not self.failedUntil then Refresh(self) end
        else
            Refresh(self)
        end
    end)
    CB.bars[key] = f
    return f
end

function CB:ApplyOptions()
    for _, f in pairs(self.bars) do Layout(f) end
end

function CB.Enable()
    local db = DB()
    if db.player then
        Create("player", "player", "Cast Bar", 230, 20, "CENTER", -200, -207)
        HideBlizzard("CastingBarFrame", "PlayerCastingBarFrame", "PetCastingBarFrame")
    end
    if db.target then
        Create("target", "target", "Target Cast Bar", 230, 20, "CENTER", 200, -207)
        HideBlizzard("TargetFrameSpellBar")
    end
end

CUI:RegisterModule({
    key = "castbar",
    name = "Cast Bar",
    addon = "CysUI",
    desc = "Flat cast bars for you and your target with icon, spell name, time left and an interrupt flash.",
    onEnable = CB.Enable,
    open = function() CUI:OpenConfig("Cast Bar") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Cast Bar", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Cast Bar", width):SetPoint("TOPLEFT", 0, -4)

    local function Check(label, key, y, live)
        local cb = W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; if live then CB:ApplyOptions() end end)
        cb:SetPoint("TOPLEFT", 4, y)
    end
    Check("Show the spell icon", "icon", -34, true)
    Check("Show the time left", "time", -60, true)

    W.Header(page, "Which bars (needs a /reload)", width):SetPoint("TOPLEFT", 0, -102)
    Check("Your cast bar", "player", -132)
    Check("Target cast bar", "target", -158)

    local move = W.Button(page, 240, 22, "Move and resize (layout mode)")
    move:SetPoint("TOPLEFT", 4, -198)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local note = W.Notes(page, 4, -238, width, "", {
            "Blizzard's cast bar is hidden for any bar you turn on.",
            "The target bar only shows casts the game reports to addons, which varies by Classic version.",
            "Untick Cast Bar under Modules and reload to go back to Blizzard's.",
        })
end)
