--------------------------------------------------------------------------------
-- Cys's UI - interrupt-ready cast bars
--
-- Colors an enemy's cast bar by whether YOUR interrupt can stop it:
--   * grey while your interrupt is still on cooldown
--   * a white tick at the point in the cast where it comes off cooldown
--   * green from the moment it is ready
-- Used by the target cast bar and the nameplate cast bars. Works for every class that has an interrupt (for a
-- Warrior it follows the stance: Pummel in Berserker, Shield Bash otherwise).
--
-- WoW Forever locks other units' cast times, so no math is done on them. The game hands out timer objects for
-- the cast and for your cooldown; their values go straight into two invisible bars whose fill edges mark the
-- spot: the first is filled to how far the cast is now, the second starts at that edge and is filled by the time
-- your cooldown still needs. Where the second one ends is where the tick sits. Classic Era uses the same two
-- bars with ordinary numbers.
--------------------------------------------------------------------------------
local CUI = CysUI
local Compat = CysUICompat
local Secret = Compat.Secret

local K = {}
CUI.Kick = K

local FLAT = "Interface\\Buttons\\WHITE8X8"
local READY = { 0.25, 0.80, 0.35 }
local WAIT = { 0.58, 0.58, 0.62 }

-- every rank, highest first. Our own list of the Classic interrupts.
local PUMMEL = { 6554, 6552 }
local SHIELD_BASH = { 29704, 1672, 1671, 72 }
local BY_CLASS = {
    ROGUE = { { 38768, 1769, 1768, 1767, 1766 } },                        -- Kick
    MAGE = { { 2139 } },                                                   -- Counterspell
    SHAMAN = { { 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 } },   -- Earth Shock
    PRIEST = { { 15487 } },                                                -- Silence
    PALADIN = { { 10308, 5589, 5588, 853 } },                              -- Hammer of Justice
    DRUID = { { 16979 }, { 8983, 6798, 5211 } },                           -- Feral Charge, Bash
    WARLOCK = { { 19647, 19244, pet = true } },                            -- Felhunter: Spell Lock
}

local function Known(id, pet)
    local book = C_SpellBook
    if pet then
        if IsSpellKnown and IsSpellKnown(id, true) then return true end
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
        if book and book.IsSpellKnown and bank then
            local ok, known = pcall(book.IsSpellKnown, id, bank)
            if ok and known then return true end
        end
        return false
    end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if book and book.IsSpellKnown and book.IsSpellKnown(id) then return true end
    if book and book.IsSpellKnownOrInSpellBook and book.IsSpellKnownOrInSpellBook(id) then return true end
    return false
end

local cached, cachedSet
local function FindSpell()
    local _, class = UnitClass("player")
    local lists = BY_CLASS[class]
    if class == "WARRIOR" then
        local form = GetShapeshiftForm and GetShapeshiftForm() or 0
        if type(form) ~= "number" or Secret(form) then form = 0 end
        lists = (form == 3) and { PUMMEL, SHIELD_BASH } or { SHIELD_BASH, PUMMEL }
    end
    if not lists then return nil end
    for _, ranks in ipairs(lists) do
        for _, id in ipairs(ranks) do
            if Known(id, ranks.pet) then return id end
        end
    end
    return nil
end
-- your interrupt right now (spell ID), or nil when this character has none
function K.Spell()
    if not cachedSet then cached, cachedSet = FindSpell(), true end
    return cached
end

--------------------------------------------------------------------------------
-- Your interrupt's cooldown
--------------------------------------------------------------------------------
-- returns "timer", durationObject (WoW Forever)  |  "plain", seconds left (0 = ready)  |  nil = can't tell
local function Cooldown(id)
    if Compat.isForever and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, id, true) -- true: leave the global cooldown out
        if ok and dur then return "timer", dur end
        return nil
    end
    local start, length
    if GetSpellCooldown then
        start, length = GetSpellCooldown(id)
    elseif C_Spell and C_Spell.GetSpellCooldown then
        local t = C_Spell.GetSpellCooldown(id)
        if type(t) == "table" then start, length = t.startTime, t.duration end
    end
    if Secret(start) or Secret(length) then return nil end
    if type(start) ~= "number" or type(length) ~= "number" or length <= 1.5 then return "plain", 0 end -- the global cooldown doesn't count
    return "plain", math.max(0, start + length - GetTime())
end

--------------------------------------------------------------------------------
-- The overlay on one cast bar
--------------------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })
local active = {} -- bar -> cast info, while that bar shows an enemy cast

local function Invisible(sb)
    sb:SetStatusBarTexture(FLAT)
    local fill = sb:GetStatusBarTexture()
    fill:SetAlpha(0)
    if fill.SetSnapToPixelGrid then fill:SetSnapToPixelGrid(false) end
    if fill.SetTexelSnappingBias then fill:SetTexelSnappingBias(0) end
    return fill
end
local function Overlay(bar)
    local o = overlays[bar]
    if o then return o end
    o = {}
    o.clip = CreateFrame("Frame", nil, bar)
    o.clip:SetAllPoints(bar)
    o.clip:SetFrameLevel(bar:GetFrameLevel() + 2)
    if o.clip.SetClipsChildren then o.clip:SetClipsChildren(true) end -- a ready point past the end of the cast stays out of sight
    o.pos = CreateFrame("StatusBar", nil, o.clip)
    o.pos:SetAllPoints(o.clip)
    o.posFill = Invisible(o.pos)
    o.mark = CreateFrame("StatusBar", nil, o.clip)
    o.markFill = Invisible(o.mark)
    o.tick = o.clip:CreateTexture(nil, "OVERLAY")
    o.tick:SetColorTexture(1, 1, 1, 0.95)
    o.tick:SetWidth(2)
    overlays[bar] = o
    return o
end

local function SetColor(bar, r, g, b)
    if not pcall(bar.SetStatusBarColor, bar, r, g, b) then
        local fill = bar:GetStatusBarTexture()
        if fill then pcall(fill.SetVertexColor, fill, r, g, b) end
    end
end

-- color + tick visibility from the cooldown as it is this instant (cheap; runs a few times a second)
local function Paint(bar, o)
    local id = K.Spell()
    local kind, cd = nil, nil
    if id then kind, cd = Cooldown(id) end
    if kind == "plain" then
        local ready = cd <= 0
        local c = ready and READY or WAIT
        SetColor(bar, c[1], c[2], c[3])
        o.tick:SetAlpha(ready and 0 or 1)
    elseif kind == "timer" then
        local ok, zero = pcall(cd.IsZero, cd)
        if not ok then return end
        if not Secret(zero) then
            local c = zero and READY or WAIT
            SetColor(bar, c[1], c[2], c[3])
            o.tick:SetAlpha(zero and 0 or 1)
        elseif C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            -- a locked yes/no: the game picks between the two values itself
            local pick = C_CurveUtil.EvaluateColorValueFromBoolean
            local ok1, r = pcall(pick, zero, READY[1], WAIT[1])
            local ok2, g = pcall(pick, zero, READY[2], WAIT[2])
            local ok3, b = pcall(pick, zero, READY[3], WAIT[3])
            if ok1 and ok2 and ok3 then SetColor(bar, r, g, b) end
            local ok4, a = pcall(pick, zero, 0, 1)
            if ok4 then pcall(o.tick.SetAlpha, o.tick, a) end
        end
    end
end

-- where the tick sits: sampled when the cast starts and whenever your cooldown changes
local function Place(bar, o, info)
    local id = K.Spell()
    local kind, cd = nil, nil
    if id then kind, cd = Cooldown(id) end
    if not kind then o.clip:Hide() return end
    local total, done, left, wait
    if info.dur then -- WoW Forever: the cast's own timer
        local d = info.dur
        local ok1, ok2, ok3
        ok1, total = pcall(d.GetTotalDuration, d)
        ok2, done = pcall(d.GetElapsedDuration, d)
        ok3, left = pcall(d.GetRemainingDuration, d)
        if not (ok1 and ok2 and ok3) then o.clip:Hide() return end
    else
        local now = GetTime()
        total, done, left = info.endT - info.startT, now - info.startT, info.endT - now
        if total <= 0 then o.clip:Hide() return end
    end
    if kind == "timer" then
        local ok
        ok, wait = pcall(cd.GetRemainingDuration, cd)
        if not ok then o.clip:Hide() return end
    else
        wait = cd
    end
    local w = bar:GetWidth()
    o.mark:ClearAllPoints()
    o.tick:ClearAllPoints()
    if info.channel then
        -- a channel empties right to left: the first bar is filled to the time left, the second runs back from there
        o.mark:SetReverseFill(true)
        o.mark:SetPoint("TOPRIGHT", o.posFill, "TOPRIGHT")
        o.mark:SetPoint("BOTTOMRIGHT", o.posFill, "BOTTOMRIGHT")
        o.tick:SetPoint("TOP", o.markFill, "TOPLEFT")
        o.tick:SetPoint("BOTTOM", o.markFill, "BOTTOMLEFT")
    else
        o.mark:SetReverseFill(false)
        o.mark:SetPoint("TOPLEFT", o.posFill, "TOPRIGHT")
        o.mark:SetPoint("BOTTOMLEFT", o.posFill, "BOTTOMRIGHT")
        o.tick:SetPoint("TOP", o.markFill, "TOPRIGHT")
        o.tick:SetPoint("BOTTOM", o.markFill, "BOTTOMRIGHT")
    end
    o.mark:SetWidth(w > 1 and w or 1)
    local ok = pcall(o.pos.SetMinMaxValues, o.pos, 0, total)
        and pcall(o.pos.SetValue, o.pos, info.channel and left or done)
        and pcall(o.mark.SetMinMaxValues, o.mark, 0, total)
        and pcall(o.mark.SetValue, o.mark, wait)
    o.clip:SetShown(ok and true or false)
end

--------------------------------------------------------------------------------
-- For the cast bars
--------------------------------------------------------------------------------
-- bar: the StatusBar showing the cast.  unit: whose cast.  info: { dur = timer object, channel = bool } on
-- WoW Forever's locked casts, or { startT =, endT =, channel = } with plain times.
-- Returns true when the bar is now colored by your interrupt (the caller's own color is replaced).
function K.Apply(bar, unit, info)
    if not (bar and unit and info) or not K.Spell() then K.Clear(bar) return false end
    local okA, attack = pcall(UnitCanAttack, "player", unit)
    if okA and not Secret(attack) and not attack then K.Clear(bar) return false end -- a friend's cast: nothing to interrupt
    local o = Overlay(bar)
    active[bar] = info
    Place(bar, o, info)
    Paint(bar, o)
    K.driver:Show()
    return true
end

function K.Clear(bar)
    if not bar then return end
    active[bar] = nil
    local o = overlays[bar]
    if o then o.clip:Hide() end
end

local function Resample()
    for bar, info in pairs(active) do
        local o = overlays[bar]
        if o then Place(bar, o, info); Paint(bar, o) end
    end
end

K.driver = CreateFrame("Frame")
K.driver:Hide()
local since = 0
K.driver:SetScript("OnUpdate", function(self, elapsed)
    since = since + elapsed
    if since < 0.1 then return end
    since = 0
    local any
    for bar in pairs(active) do
        if bar:IsVisible() then
            any = true
            local o = overlays[bar]
            if o then Paint(bar, o) end
        else
            K.Clear(bar)
        end
    end
    if not any then self:Hide() end
end)

local ev = CreateFrame("Frame")
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD",
    "UNIT_PET", "LEARNED_SPELL_IN_TAB" }) do
    pcall(ev.RegisterEvent, ev, event)
end
ev:SetScript("OnEvent", function(_, event)
    if event ~= "SPELL_UPDATE_COOLDOWN" then cachedSet = false end -- your interrupt may have changed (stance, new rank, pet)
    Resample()
end)
