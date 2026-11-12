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
-- On WoW Forever the target's cast is locked, so the bar runs off the game's own cast timer.
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
-- WoW Forever: other units' casts are locked (your own and your pet's are not); a locked cast counts as none
local Secret = CysUICompat.Secret
local function Locked(name, startMS, endMS) return Secret(name) or Secret(startMS) or Secret(endMS) end
local function CastInfo(unit)
    if not UnitExists(unit) then return end
    local name, _, texture, startMS, endMS = UnitCastingInfo(unit)
    if Locked(name, startMS, endMS) then return end
    if name and startMS and endMS then return name, texture, startMS / 1000, endMS / 1000, false end
    name, _, texture, startMS, endMS = UnitChannelInfo(unit)
    if Locked(name, startMS, endMS) then return end
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

-- the target's bar is colored by your interrupt (Kick.lua): grey on cooldown, a tick where it comes ready, green
-- when it is up. Never on your own cast bar.
local function KickApply(f, info)
    local K = CUI.Kick
    if not K then return end
    if f.unit == "player" or DB().kick == false then K.Clear(f.bar) return end
    K.Apply(f.bar, f.unit, info)
end
local function KickClear(f)
    if CUI.Kick then CUI.Kick.Clear(f.bar) end
end

local function Stop(f)
    KickClear(f)
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

-- WoW Forever: a locked cast runs off the game's duration object instead of start/end times
local function LockedOnUpdate(f)
    if f.failedUntil then
        if GetTime() >= f.failedUntil then Stop(f) end
        return
    end
    if DB().time then CysUICompat.LockedCastTime(f.time, f.lockedDur) end
end

local function Refresh(f)
    local name, texture, startT, endT, channel = CastInfo(f.unit)
    if not name then
        local kind, lname, ltex, dur = CysUICompat.LockedCast(f.unit)
        if kind then
            f.casting, f.channel, f.failedUntil, f.lockedDur = true, kind == "channel", nil, dur
            local c = f.channel and COLOR_CHANNEL or COLOR_CAST
            f.bar:SetStatusBarColor(c[1], c[2], c[3])
            f.icon:SetTexture(ltex)
            f.text:SetText(lname)
            f.time:SetText("")
            CysUICompat.RunLockedCastBar(f.bar, kind, dur)
            KickApply(f, { dur = dur, channel = f.channel })
            f:Show()
            f:SetScript("OnUpdate", LockedOnUpdate)
            LockedOnUpdate(f)
            return
        end
        if not f.failedUntil then Stop(f) end
        return
    end
    f.lockedDur = nil
    f.casting, f.channel, f.startT, f.endT, f.failedUntil = true, channel, startT, endT, nil
    local c = channel and COLOR_CHANNEL or COLOR_CAST
    f.bar:SetStatusBarColor(c[1], c[2], c[3])
    f.icon:SetTexture(texture)
    f.text:SetText(name)
    f:Show()
    f:SetScript("OnUpdate", OnUpdate)
    OnUpdate(f)
    KickApply(f, { startT = startT, endT = endT, channel = channel })
end

local function Fail(f, label)
    KickClear(f)
    f.casting, f.lockedDur = false, nil
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
            if self:IsShown() and not CastInfo(self.unit) and not CysUICompat.LockedCast(self.unit) then Fail(self, "Failed") end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if not self.failedUntil then Refresh(self) end
        else
            Refresh(self)
        end
    end)
    CB.bars[key] = f
    return f
end

-- Joined to the target frame (off by default): the target's cast bar sits flush under Cys's target frame, the
-- same width, sharing one edge. While on, the bar's own spot and width from layout mode are not used (its height
-- still is). Only done out of combat; a change made mid-fight waits for the fight to end.
-- The same for your own cast bar under the player frame (joinPlayer).
local JOINS = { { key = "target", opt = "joinTarget" }, { key = "player", opt = "joinPlayer" } }
function CB.ApplyJoin()
    for _, j in ipairs(JOINS) do
        local f = CB.bars[j.key]
        local want = DB()[j.opt] and true or false
        if f and (want or f.joined) then
            if InCombatLockdown() then CB.joinPending = true return end
            local UF = CUI.UnitFrames
            local uf = UF and UF.frames and UF.frames[j.key]
            local m = CUI.movers and CUI.movers["castbar_" .. j.key]
            if want and uf then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", uf, "BOTTOMLEFT", 0, 1)
                f:SetPoint("TOPRIGHT", uf, "BOTTOMRIGHT", 0, 1)
                f.joined = true
            elseif m and m.mover then
                f:ClearAllPoints()
                f:SetPoint("CENTER", m.mover, "CENTER", 0, 0)
                f.joined = nil
                CUI:ApplyLayout("castbar_" .. j.key)
            end
            pcall(Layout, f)
        end
    end
    CB.joinPending = nil
end
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or CB.joinPending then CB.ApplyJoin() end
    end)
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
    if db.kick == nil then db.kick = true end
    Check("Color the target's cast by your interrupt", "kick", -86, true)
    W.Checkbox(page, "Join the target's cast bar to the bottom of the target frame", function() return db.joinTarget end,
        function(on) db.joinTarget = on and true or false; CB.ApplyJoin() end):SetPoint("TOPLEFT", 4, -112)
    W.Checkbox(page, "Join your cast bar to the bottom of the player frame", function() return db.joinPlayer end,
        function(on) db.joinPlayer = on and true or false; CB.ApplyJoin() end):SetPoint("TOPLEFT", 4, -138)

    W.Header(page, "Which bars (needs a /reload)", width):SetPoint("TOPLEFT", 0, -180)
    Check("Your cast bar", "player", -210)
    Check("Target cast bar", "target", -236)


    local note = W.Notes(page, 4, -316, width, "", {
            { "Joined to the player / target frame", "the bar sits flush under Cys's player or target frame at the same width and follows it wherever you move it. Its own box in layout mode then only sets the height. Changed in combat, it applies when the fight ends." },
            { "Your interrupt", "the target's cast is grey while your interrupt is on cooldown, with a white tick where it comes ready, and green once you can use it. Works for every class with an interrupt; nameplates have the same switch on their page." },
            "Blizzard's cast bar is hidden for any bar you turn on.",
            "The target bar only shows casts the game reports to addons, which varies by Classic version.",
            "Untick Cast Bar under Modules and reload to go back to Blizzard's.",
        })
end)
