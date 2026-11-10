--------------------------------------------------------------------------------
-- Cys's UI - Compat
--
-- Loaded first. Newer game clients (and new Classic versions built on them) move old global functions into
-- C_ namespaces and drop the old names. Where an old name is gone, this file puts it back from the new one so
-- the rest of the UI keeps working unchanged. Nothing is touched while the old function still exists, so on
-- today's Classic Era client this file does nothing. /cui debug lists anything it had to fill in.
--------------------------------------------------------------------------------
CysUICompat = { shimmed = {}, errors = {} }
local Compat = CysUICompat
local shimmed = Compat.shimmed

local function Shim(name, fn)
    if _G[name] == nil and fn then
        _G[name] = fn
        shimmed[#shimmed + 1] = name
    end
end

-- WoW Forever runs on the retail client (interface 16xxx). Core sets CysUI.isForever the same way; this copy
-- exists because Compat loads before Core.
local _, _, _, interface = GetBuildInfo()
interface = tonumber(interface) or 0
Compat.isForever = interface >= 16000 and interface < 17000

--------------------------------------------------------------------------------
-- Secret values (WoW Forever, like retail Midnight)
--
-- The game hands addons some values as "secret": other units' health, casts, creature names in instances,
-- and every aura while you are in combat. A secret can still go on a status bar or into a font string, but
-- any math, comparison or true/false test on it throws an error. issecretvalue doesn't exist on Classic Era,
-- so there all of these simply pass values through and nothing changes.
--------------------------------------------------------------------------------
local issecret = issecretvalue

-- true when v is a secret value
function Compat.Secret(v)
    return issecret ~= nil and issecret(v) == true
end
local Secret = Compat.Secret

-- v, or nil when it is secret (so 'if x then' and math on it are safe)
function Compat.Plain(v)
    if issecret and issecret(v) then return nil end
    return v
end
local Plain = Compat.Plain

-- true only for a real true value; a secret counts as false
function Compat.Flag(v)
    if issecret and issecret(v) then return false end
    return v and true or false
end

-- WoW Forever heal prediction. The game gives real incoming heals there (every healer, not just you), but as a
-- locked number, so no math: a status bar that starts where the health fill ends takes the locked amount as its
-- value over max health, and the health bar clips it at the frame's edge. Overheal: an identical bar inside a
-- clipping strip just past the frame's right edge, so only the part beyond full health shows there (one colour:
-- telling a small overheal from a big one would need math on the locked number).
-- owner: the frame to keep the bar on; health: its health StatusBar; color: { r, g, b, a }.
function Compat.ForeverHealBar(owner, health, unit, color)
    local bar = owner.cysForeverHeal
    if not bar then
        bar = CreateFrame("StatusBar", nil, health)
        bar.cysOwn = true
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local c = color or { 0.0, 0.75, 0.45, 0.6 }
        bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 0.6)
        local fill = health:GetStatusBarTexture()
        bar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        bar:SetFrameLevel(health:GetFrameLevel())
        if health.SetClipsChildren then health:SetClipsChildren(true) end
        owner.cysForeverHeal = bar

        local strip = CreateFrame("Frame", nil, owner)
        strip.cysOwn = true
        strip:SetPoint("TOPLEFT", health, "TOPRIGHT", 1, 0)
        strip:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", 1, 0)
        strip:SetClipsChildren(true)
        strip:SetFrameLevel(health:GetFrameLevel() + 2)
        local over = CreateFrame("StatusBar", nil, strip)
        over.cysOwn = true
        over:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        over:SetStatusBarColor(0.0, 0.9, 0.8, 0.75)
        over:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0) -- -1: the strip starts 1px past the frame
        over:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", -1, 0)
        owner.cysForeverOver, owner.cysForeverStrip = over, strip
    end
    local w = math.max(health:GetWidth() or 1, 1)
    bar:SetWidth(w)
    local over, strip = owner.cysForeverOver, owner.cysForeverStrip
    over:SetWidth(w)
    strip:SetWidth(math.max(w * 0.6, 2)) -- up to 60% of the frame's width, like on Classic Era
    local incoming = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
    local mx = UnitHealthMax(unit)
    local dead = UnitIsDeadOrGhost and Compat.Flag(UnitIsDeadOrGhost(unit)) -- may be locked for others
    if incoming == nil or mx == nil or (dead == true) then bar:Hide(); strip:Hide() return end
    local ok = pcall(bar.SetMinMaxValues, bar, 0, mx) and pcall(bar.SetValue, bar, incoming)
    local ok2 = pcall(over.SetMinMaxValues, over, 0, mx) and pcall(over.SetValue, over, incoming)
    bar:SetShown(ok)
    strip:SetShown(ok2)
end

-- The game's own countdown text on a cooldown swipe ("59m") is drawn at full size; on small aura icons it spills
-- far past the icon (WoW Forever shows it by default). Shrink it to fit an icon of `iconSize` pixels.
function Compat.SmallCooldownText(cd, iconSize)
    if not (cd and cd.GetCountdownFontString) then return end
    local ok, fs = pcall(cd.GetCountdownFontString, cd)
    if not ok or not (fs and fs.SetFont) then return end
    local size = math.max(7, math.floor((iconSize or 20) * 0.45))
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    if cd.SetCountdownAbbrevThreshold then pcall(cd.SetCountdownAbbrevThreshold, cd, 90) end -- "2m" not "120"
end

-- true while the game is hiding aura data (in combat on WoW Forever)
function Compat.AurasLocked()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local ok, locked = pcall(C_Secrets.ShouldAurasBeSecret)
    return ok and locked == true
end

-- One aura as a table (name, icon, applications, dispelName, duration, expirationTime, spellId, ...), or nil.
-- On Classic Era this is exactly C_UnitAuras.GetAuraDataByIndex. On WoW Forever it answers nil while auras are
-- locked and gives back plain copies of the fields, so aura rows just stay empty instead of erroring.
-- Like AuraData, but tells "no aura at this index" (nil) apart from "an aura whose details are locked"
-- ({ locked = true, icon = <locked icon> }), so a list keeps going past a locked aura instead of stopping there.
-- The locked icon can still go on a Texture as it is.
function Compat.AuraEntry(unit, index, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    if not Compat.isForever then return C_UnitAuras.GetAuraDataByIndex(unit, index, filter) end
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok or a == nil then return nil end
    if Secret(a) then return { locked = true, applications = 0, duration = 0, expirationTime = 0 } end
    local name = Plain(a.name)
    if not name then
        return { locked = true, icon = a.icon, applications = 0, duration = 0, expirationTime = 0 }
    end
    return {
        name = name, icon = Plain(a.icon), applications = Plain(a.applications) or 0, dispelName = Plain(a.dispelName),
        duration = Plain(a.duration) or 0, expirationTime = Plain(a.expirationTime) or 0, spellId = Plain(a.spellId),
    }
end

function Compat.AuraData(unit, index, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    if not Compat.isForever then return C_UnitAuras.GetAuraDataByIndex(unit, index, filter) end
    if Compat.AurasLocked() then return nil end
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok or not a or Secret(a) then return nil end
    local name = Plain(a.name)
    if not name then return nil end
    return {
        name = name, icon = Plain(a.icon), applications = Plain(a.applications) or 0, dispelName = Plain(a.dispelName),
        duration = Plain(a.duration) or 0, expirationTime = Plain(a.expirationTime) or 0, sourceUnit = Plain(a.sourceUnit),
        isStealable = Plain(a.isStealable), nameplateShowPersonal = Plain(a.nameplateShowPersonal), spellId = Plain(a.spellId),
        auraInstanceID = Plain(a.auraInstanceID),
    }
end

-- Does the player have this buff? true / false, or nil when the game won't say. On WoW Forever most auras are
-- locked for addons in combat, and a locked aura simply reads as "not there", so in combat the answer only
-- counts when the game says none of the buff's ranks is locked right now. Callers must treat nil as "can't
-- tell", never as "missing". name = the buff's name, ids = every rank's spell ID.
-- Second return: the aura table when one was read (its fields can still be locked: use Plain on them).
function Compat.PlayerBuff(name, ids)
    if not name then return nil end
    if not Compat.isForever then
        for i = 1, 40 do
            local n = UnitBuff("player", i)
            if not n then return false end
            if n == name then return true end
        end
        return false
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    if Compat.AurasLocked() or (InCombatLockdown and InCombatLockdown()) then
        if not (ids and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return nil end
        for i = 1, #ids do
            local ok, locked = pcall(C_Secrets.ShouldSpellAuraBeSecret, ids[i])
            if not ok or Secret(locked) or locked ~= false then return nil end
        end
    end
    local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if not ok or Secret(a) then return nil end
    if not a then return false end
    return true, a
end

--------------------------------------------------------------------------------
-- Forever safety net
--
-- Guard(label, fn) returns fn unchanged on Classic Era. On WoW Forever it returns a protected copy: if a
-- locked value makes fn throw, that one update is skipped instead of erroring every frame (the client stops
-- reporting errors after 100 in a session). Each different error is printed once and listed in /cui debug.
-- Only for functions whose return value nobody uses.
--------------------------------------------------------------------------------
function Compat.Guard(label, fn)
    if not Compat.isForever or type(fn) ~= "function" then return fn end
    local seen = {}
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local msg = tostring(err)
            if not seen[msg] then
                seen[msg] = true
                local errs = Compat.errors
                if #errs < 50 then errs[#errs + 1] = label .. ": " .. msg end
                print("|cFFFFD100Cys's UI|r |cFFFF8040(Forever)|r " .. label .. ": " .. msg)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Old names put back from the new ones
--------------------------------------------------------------------------------
-- spells
if C_Spell then
    if C_Spell.GetSpellInfo then
        Shim("GetSpellInfo", function(spell)
            local i = C_Spell.GetSpellInfo(spell)
            if not i then return nil end
            return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID, i.originalIconID
        end)
    end
    Shim("GetSpellTexture", C_Spell.GetSpellTexture)
    Shim("GetSpellPowerCost", C_Spell.GetSpellPowerCost)
    Shim("GetSpellDescription", C_Spell.GetSpellDescription)
    Shim("GetSpellLevelLearned", C_Spell.GetSpellLevelLearned)
end

-- items
if C_Item then
    Shim("GetItemInfo", C_Item.GetItemInfo)
    Shim("GetItemInfoInstant", C_Item.GetItemInfoInstant)
    Shim("GetItemCount", C_Item.GetItemCount)
    Shim("GetItemIcon", C_Item.GetItemIconByID)
    Shim("GetItemStats", C_Item.GetItemStats)
    Shim("EquipItemByName", C_Item.EquipItemByName)
    Shim("GetItemQualityColor", C_Item.GetItemQualityColor)
    Shim("IsEquippableItem", C_Item.IsEquippableItem)
    Shim("IsEquippedItem", C_Item.IsEquippedItem)
    Shim("IsUsableItem", C_Item.IsUsableItem)
    Shim("GetItemSpell", C_Item.GetItemSpell)
    Shim("GetItemCooldown", C_Item.GetItemCooldown)
    Shim("GetDetailedItemLevelInfo", C_Item.GetDetailedItemLevelInfo)
    Shim("GetItemClassInfo", C_Item.GetItemClassInfo)
    Shim("GetItemSubClassInfo", C_Item.GetItemSubClassInfo)
end

-- auras: old UnitAura / UnitBuff / UnitDebuff return values in a list, the new call returns a table.
-- Only filled in where the old names are gone (WoW Forever), and read through AuraData so they stay safe there.
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    Shim("UnitAura", function(unit, index, filter)
        local a = Compat.AuraData(unit, index, filter)
        if not a then return nil end
        return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit,
               a.isStealable, a.nameplateShowPersonal, a.spellId
    end)
    Shim("UnitBuff", function(unit, index, filter)
        return UnitAura(unit, index, (filter and (filter .. "|") or "") .. "HELPFUL")
    end)
    Shim("UnitDebuff", function(unit, index, filter)
        return UnitAura(unit, index, (filter and (filter .. "|") or "") .. "HARMFUL")
    end)
end

-- money text (gold / silver / copper icons)
if C_CurrencyInfo then
    Shim("GetCoinTextureString", C_CurrencyInfo.GetCoinTextureString)
    Shim("GetCoinText", C_CurrencyInfo.GetCoinText)
end

-- reloading: ReloadUI() is blocked for addons on WoW Forever (calling it only gets an "Interface action failed"
-- message, not an error a script can catch), so buttons and commands that reload call this instead.
function Compat.Reload()
    if Compat.isForever then
        local spot
        for _, r in ipairs(Compat.reloadSpots or {}) do
            if r.owner:IsShown() then spot = r break end
        end
        if spot and not InCombatLockdown() then
            spot.sync()
            print("|cFFFFD100Cys's UI|r: click Reload UI once more (Forever needs the click itself), or type |cFFFFFFFF/reload|r.")
            return
        end
        print("|cFFFFD100Cys's UI|r: the game doesn't let addons reload the interface on WoW Forever - type |cFFFFFFFF/reload|r.")
        return
    end
    ReloadUI()
end

-- WoW Forever: ReloadUI is blocked for addons, but a click on a secure button running the /reload macro
-- is the player's own action, so that works. This lays such a button over a plain "Reload UI" button.
-- It sits on UIParent (a secure child would stop the window from closing in combat) and follows the
-- owner window out of combat; in combat it steps aside and the plain button explains /reload.
-- before (optional): runs on that same click, right before the reload (the Conflicts window saves its answers there).
-- Returns the function that puts the secure button back over the plain one (call it after moving the button).
function Compat.SecureReload(btn, owner, before)
    if not (Compat.isForever and btn and owner) then return end
    local sec
    local function Sync()
        if InCombatLockdown() then return end
        if not sec then
            sec = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
            sec:SetAttribute("type", "macro")
            sec:SetAttribute("macrotext", "/reload")
            sec:SetAttribute("useOnKeyDown", false)
            sec:RegisterForClicks("AnyUp")
            if before then sec:SetScript("PreClick", function() pcall(before) end) end
            sec:HookScript("OnEnter", function() local f = btn:GetScript("OnEnter"); if f then f(btn) end end)
            sec:HookScript("OnLeave", function() local f = btn:GetScript("OnLeave"); if f then f(btn) end end)
        end
        -- placed by screen position, never anchored to the button: anchoring a secure frame to the settings window
        -- would make the whole window protected, and then it couldn't be opened or closed in combat
        local l, b, w, h = btn:GetRect()
        if l and w then
            local ratio = (btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            sec:ClearAllPoints()
            sec:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
            sec:SetSize(w * ratio, h * ratio)
        end
        sec:SetFrameStrata("FULLSCREEN_DIALOG") -- always above the settings window, whatever raises it
        sec:SetShown(owner:IsShown() and btn:IsVisible())
    end
    Compat.reloadSpots = Compat.reloadSpots or {}
    table.insert(Compat.reloadSpots, { sync = Sync, owner = owner })
    owner:HookScript("OnShow", Sync)
    owner:HookScript("OnHide", Sync)
    if owner.HookScript then pcall(owner.HookScript, owner, "OnDragStop", Sync) end -- the window was moved
    -- the mouse reaching the plain button puts the secure one back over it (out of combat), so the click lands there
    btn:HookScript("OnEnter", Sync)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- still allowed to hide it here, right before combat locks it
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if sec then sec:Hide() end
        else
            Sync()
        end
    end)
    Sync()
    return Sync
end

-- WoW Forever: some of the game's own windows must be opened by the player, not by addon code (an addon opening
-- them leaves them tainted, and they then fail on protected actions). A slash command run from a secure button IS
-- the player's own action. SecureClick lets a plain button do that: while the mouse is on the button (out of
-- combat) a secure macro button sits over it and takes the click. It only exists during the hover, so it can't
-- drift when a page scrolls or changes. Returns true when the click will be handled this way.
function Compat.SecureClick(btn, macro)
    if not (Compat.isForever and btn and macro) then return false end
    local sec
    btn:HookScript("OnEnter", function()
        if InCombatLockdown() then return end
        if not sec then
            sec = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
            sec:SetAttribute("type", "macro")
            sec:SetAttribute("macrotext", macro)
            sec:SetAttribute("useOnKeyDown", false)
            sec:RegisterForClicks("AnyUp")
            sec:SetFrameStrata("FULLSCREEN_DIALOG")
            sec:SetScript("OnLeave", function(self)
                if not InCombatLockdown() then self:Hide() end
                local f = btn:GetScript("OnLeave"); if f then f(btn) end
            end)
        end
        local l, b, w, h = btn:GetRect()
        if not (l and w) then return end
        local ratio = (btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        sec:ClearAllPoints()
        sec:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
        sec:SetSize(w * ratio, h * ratio)
        sec:Show()
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- still allowed to hide it here, right before combat locks it
    ev:SetScript("OnEvent", function() if sec then sec:Hide() end end)
    return true
end

--------------------------------------------------------------------------------
-- Locked casts (WoW Forever): other units' cast name, icon and times are locked for addons, so no math on them.
-- What still works: the name and icon go straight onto a FontString / Texture, and the bar runs off the game's own
-- cast duration object (UnitCastingDuration / UnitChannelDuration + StatusBar:SetTimerDuration).
--------------------------------------------------------------------------------
-- kind ("cast" or "channel"), name, texture, duration object - only when the unit is casting and it is locked
function Compat.LockedCast(unit)
    if not Compat.isForever or not unit then return end
    local name, _, texture = UnitCastingInfo(unit)
    local kind
    if Secret(name) then
        kind = "cast"
    elseif name ~= nil then
        return -- a plain readable cast: the normal code handles it
    elseif UnitChannelInfo then
        name, _, texture = UnitChannelInfo(unit)
        if Secret(name) then kind = "channel" end
    end
    if not kind then return end
    local getDur = (kind == "cast") and UnitCastingDuration or UnitChannelDuration
    local dur
    if getDur then
        local ok, d = pcall(getDur, unit)
        if ok then dur = d end
    end
    return kind, name, texture, dur
end

-- run a StatusBar off a locked cast's duration; a full bar when the game gives no duration
function Compat.RunLockedCastBar(bar, kind, dur)
    local ok = false
    if dur and bar.SetTimerDuration then
        local E = Enum or {}
        local interp = (E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate) or 0
        local dirs = E.StatusBarTimerDirection or {}
        local dir = (kind == "channel") and (dirs.RemainingTime or 1) or (dirs.ElapsedTime or 0)
        ok = pcall(bar.SetTimerDuration, bar, dur, interp, dir)
    end
    if not ok then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
    end
    return ok
end

-- "1.4" time-left text for a locked cast (the number stays locked; the FontString formats it)
function Compat.LockedCastTime(fs, dur)
    if not (fs and dur and dur.GetRemainingDuration) then if fs then fs:SetText("") end; return end
    local ok, left = pcall(dur.GetRemainingDuration, dur)
    if not ok or not pcall(fs.SetFormattedText, fs, "%.1f", left) then fs:SetText("") end
end

--------------------------------------------------------------------------------
-- Locked health / power text (WoW Forever): UnitHealth / UnitPower are locked even for you, so the text is made
-- by the game: UnitHealthPercent / UnitPowerPercent scaled to 0-100 by a curve, AbbreviateNumbers for the
-- numbers, and FontString:SetFormattedText to put them together (all of these take locked values).
--------------------------------------------------------------------------------
local pctCurve
local function PercentCurve()
    if pctCurve ~= nil then return pctCurve or nil end
    if CurveConstants and CurveConstants.ScaleTo100 then pctCurve = CurveConstants.ScaleTo100; return pctCurve end
    local ok, c = pcall(function()
        local curve = C_CurveUtil.CreateCurve()
        curve:AddPoint(0, 0)
        curve:AddPoint(1, 100)
        return curve
    end)
    pctCurve = ok and c or false
    return pctCurve or nil
end
local function Abbrev(v)
    if AbbreviateNumbers then
        local ok, txt = pcall(AbbreviateNumbers, v)
        if ok then return txt end
    end
    return v
end

-- kind: "health" or "power"; mode: "percent", "value" / "current", "both" (value + percent) or "max" (current / max)
function Compat.LockedUnitText(fs, unit, kind, mode)
    if not fs then return end
    local ok = pcall(function()
        local pct
        local curve = PercentCurve()
        if kind == "health" then
            if UnitHealthPercent and curve then pct = UnitHealthPercent(unit, true, curve) end
        else
            if UnitPowerPercent and curve then pct = UnitPowerPercent(unit, nil, false, curve) end
        end
        local cur = (kind == "health") and UnitHealth(unit) or UnitPower(unit)
        if mode == "percent" then
            if pct == nil then error("no percent") end
            fs:SetFormattedText("%.0f%%", pct)
        elseif (mode == "both" and kind == "health") or mode == "valuepct" then
            if pct == nil then fs:SetText(Abbrev(cur)) else fs:SetFormattedText("%s  |cFFFFD100%.0f%%|r", Abbrev(cur), pct) end
        elseif mode == "both" or mode == "max" then
            local mx = (kind == "health") and UnitHealthMax(unit) or UnitPowerMax(unit)
            fs:SetFormattedText("%s / %s", Abbrev(cur), Abbrev(mx))
        else
            fs:SetText(Abbrev(cur))
        end
    end)
    if not ok then fs:SetText("") end
end

-- Mana cost preview on a locked mana bar: a reverse-filled StatusBar pinned to the end of the mana fill. Its range
-- is the (locked) max mana and its value the spell's cost, so the game sizes the segment; no math on locked values.
function Compat.LockedCostBar(f, cost)
    local bar = f.power
    if not bar then return end
    local cb = f.cysCostBar
    if not cb then
        cb = CreateFrame("StatusBar", nil, bar)
        cb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        cb:SetStatusBarColor(1, 1, 1, 0.85)
        cb:SetReverseFill(true)
        cb:SetFrameLevel(bar:GetFrameLevel() + 2)
        cb:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        cb:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        pcall(bar.SetClipsChildren, bar, true) -- a cost bigger than your mana stops at the bar's left edge
        f.cysCostBar = cb
    end
    if not cost or cost <= 0 then cb:Hide(); return end
    cb:SetWidth(bar:GetWidth())
    local ok = pcall(function()
        cb:SetMinMaxValues(0, UnitPowerMax("player"))
        cb:SetValue(cost)
    end)
    cb:SetShown(ok)
end

--------------------------------------------------------------------------------
-- Aura icons for other units (WoW Forever): their aura details are locked in combat, but the game still hands out
-- plain aura instance IDs, and per ID a ready-made stack text and a duration object. The icon (locked or not) goes
-- straight onto a Texture, the stack text onto a FontString, the duration onto a Cooldown. No math, no comparisons
-- and no if-tests on locked values: every locked value is checked with Secret() before anything else touches it.
-- Returns a list of { id, icon, count, dur, dispelName, filter } or nil when the game can't list them.
--------------------------------------------------------------------------------
local LOCKED_ICON = 134400 -- question mark, for an aura whose icon the game won't even hand over

-- plain "is there something here" test that never does an if-test on a locked value
local function Present(v)
    if Secret(v) then return true end
    return v ~= nil
end
Compat.Present = Present

-- debuff type (magic, curse, disease, poison) -> border color, worked out by the game so it works while locked
local dispelCurve
local function DispelCurve()
    if dispelCurve ~= nil then return dispelCurve or nil end
    dispelCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    if c.SetType and Enum and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Step) end
    -- x = the game's dispel type number: 0 none, 1 magic, 2 curse, 3 disease, 4 poison
    local pts = { { 0, 0.80, 0.20, 0.20 }, { 1, 0.20, 0.60, 1.00 }, { 2, 0.60, 0.00, 1.00 },
                  { 3, 0.60, 0.40, 0.00 }, { 4, 0.00, 0.60, 0.00 }, { 5, 0.80, 0.20, 0.20 } }
    for _, pt in ipairs(pts) do pcall(c.AddPoint, c, pt[1], CreateColor(pt[2], pt[3], pt[4], 1)) end
    dispelCurve = c
    return c
end

function Compat.AuraIcons(unit, filter, maxCount)
    if not (Compat.isForever and C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then return nil end
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter, maxCount)
    if not ok or Secret(ids) or type(ids) ~= "table" then return nil end
    local out = {}
    for _, id in ipairs(ids) do
        if not Secret(id) then
            local e = { id = id, unit = unit, filter = filter, icon = LOCKED_ICON }
            local okA, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
            if okA and not Secret(a) and type(a) == "table" then
                local okI, icon = pcall(function() return a.icon end)
                if okI and Present(icon) then e.icon = icon end
                local okD, dn = pcall(function() return a.dispelName end)
                if okD then e.dispelName = Plain(dn) end
                local okN, nm = pcall(function() return a.name end)
                if okN then e.name = Plain(nm) end
            end
            if C_UnitAuras.GetAuraApplicationDisplayCount then
                local okC, c = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2)
                if okC then e.count = c end
            end
            if C_UnitAuras.GetAuraDuration then
                local okT, d = pcall(C_UnitAuras.GetAuraDuration, unit, id)
                if okT then e.dur = d end
            end
            out[#out + 1] = e
        end
    end
    return out
end

-- put one Compat.AuraIcons entry on an icon frame that has .icon, .count and .cd
function Compat.ShowAuraIcon(a, e)
    if not pcall(a.icon.SetTexture, a.icon, e.icon) then a.icon:SetTexture(LOCKED_ICON) end
    if Present(e.count) then
        if not pcall(a.count.SetText, a.count, e.count) then a.count:SetText("") end
    else
        a.count:SetText("")
    end
    local shown = false
    if Present(e.dur) and a.cd.SetCooldownFromDurationObject then
        shown = pcall(a.cd.SetCooldownFromDurationObject, a.cd, e.dur)
    end
    a.cd:SetShown(shown)
    a.auraInstanceID, a.auraUnit, a.auraFilter = e.id, e.unit, e.filter
end

-- color a W.Border edge set by the aura's debuff type; falls back to the given plain color
function Compat.AuraBorder(edges, e, fallback)
    for i = 1, #edges do edges[i]:SetColorTexture(fallback[1], fallback[2], fallback[3], fallback[4] or 1) end
    if not (e and e.id and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor) then return end
    local curve = DispelCurve()
    if not curve then return end
    local ok, col = pcall(C_UnitAuras.GetAuraDispelTypeColor, e.unit, e.id, curve)
    if not ok or not col or Secret(col) then return end
    local okRGB, r, g, b = pcall(col.GetRGB, col)
    if not okRGB then return end
    for i = 1, #edges do
        edges[i]:SetColorTexture(1, 1, 1, 1)
        pcall(edges[i].SetVertexColor, edges[i], r, g, b, 1)
    end
end

--------------------------------------------------------------------------------
-- Dispels: which debuff types YOU can remove right now (spell learned; warlocks need the Felhunter out).
-- Shared by raid frames and party frames. Rebuilt whenever spells or the pet change.
--------------------------------------------------------------------------------
local DISPEL_SPELLS = {
    PRIEST = {
        { { "Disease" }, { 528, 552 } },                 -- Cure Disease, Abolish Disease
        { { "Magic" },   { 527, 988 } },                 -- Dispel Magic
    },
    PALADIN = {
        { { "Poison", "Disease" }, { 1152 } },           -- Purify
        { { "Magic", "Poison", "Disease" }, { 4987 } },  -- Cleanse
    },
    DRUID = {
        { { "Curse" },  { 2782 } },                      -- Remove Curse
        { { "Poison" }, { 8946, 2893 } },                -- Cure Poison, Abolish Poison
    },
    SHAMAN = {
        { { "Poison" },  { 526 } },                      -- Cure Poison
        { { "Disease" }, { 2870 } },                     -- Cure Disease
    },
    MAGE = {
        { { "Curse" }, { 475 } },                        -- Remove Lesser Curse
    },
    WARLOCK = {
        { { "Magic" }, { 19505, 19731, 19734, 19736 }, pet = true }, -- Felhunter: Devour Magic
    },
}
Compat.dispelTypes = {}

local function KnownDispel(id, pet)
    if pet then
        if IsSpellKnown then return IsSpellKnown(id, true) and true or false end
        return false
    end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) and true or false
end

function Compat.RebuildDispels()
    local can = Compat.dispelTypes
    wipe(can)
    local _, class = UnitClass("player")
    for _, entry in ipairs(DISPEL_SPELLS[class] or {}) do
        for _, id in ipairs(entry[2]) do
            local ok, known = pcall(KnownDispel, id, entry.pet)
            if ok and known then
                for _, t in ipairs(entry[1]) do can[t] = true end
                break
            end
        end
    end
end

function Compat.CanDispel(debuffType)
    return debuffType ~= nil and Compat.dispelTypes[debuffType] == true
end

local FALLBACK_TYPES = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}
function Compat.DebuffColor(debuffType)
    local c = DebuffTypeColor and DebuffTypeColor[debuffType]
    if c and c.r then return c.r, c.g, c.b end
    local f = FALLBACK_TYPES[debuffType]
    if f then return f[1], f[2], f[3] end
end

do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_PET", "player")
    ev:SetScript("OnEvent", function() pcall(Compat.RebuildDispels) end)
end

--------------------------------------------------------------------------------
-- Aura containers (WoW Forever): addons may not read other units' auras in combat at all, but they may hand the
-- game a container of icon frames and the game fills them itself - icon, stacks, timer swipe, debuff-type border,
-- tooltip - in and out of combat. Same system EllesmereUI uses. We build the look (dark edge, cropped icon, small
-- stack text); the game decides which aura goes where.
--   spec = { groups = { { key = "debuffs", filter = "HARMFUL", max = 16 }, ... },
--            size = 20, gap = 2, lineWidth = 180, anchor = "TOPLEFT", growH = "RIGHT", growV = "DOWN",
--            noClicks = true (nameplates: clicks go through to the plate) }
-- Returns the container, or nil where the system isn't there (Classic Era).
--------------------------------------------------------------------------------
function Compat.HasAuraContainers()
    if not Compat.isForever then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return AnchorUtil ~= nil and AnchorUtil.FlowDirection ~= nil
        and C_AddOns ~= nil and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") and true or false
end

local function AuraCellInit(spec)
    local size = spec.size or 20
    local function Build(button)
        -- the game's layout only spaces the icons; their size is ours to set (without it they are 0 wide)
        button:SetSize(size, size)
        -- every region is made and styled first; registering an unstyled FontString makes the game error
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        bg:SetColorTexture(0, 0, 0, 1)

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        cd.noCooldownCount = true
        Compat.SmallCooldownText(cd, size)

        -- text and border sit above the swipe and never take the mouse
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints(button)
        top:SetFrameLevel(cd:GetFrameLevel() + 2)
        top:EnableMouse(false)
        local count = top:CreateFontString(nil, "OVERLAY")
        count:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.45)), "OUTLINE")
        count:SetPoint("BOTTOMRIGHT", 1, 0)
        -- optional fixed-colour 1px edge (player buffs use the theme border), drawn under the debuff-type tint
        if spec.edgeColor then
            local c = spec.edgeColor
            for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                                 { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
                local t = top:CreateTexture(nil, "BORDER")
                t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                t:SetPoint(e[1], button, e[1]); t:SetPoint(e[2], button, e[2])
                if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
            end
        end
        -- time left as text, drawn by the game (works while locked): on the icon or under it
        local timerText
        if spec.timerText then
            timerText = top:CreateFontString(nil, "OVERLAY")
            timerText:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.4)), "OUTLINE")
            if spec.timerText == "below" then
                timerText:SetPoint("TOP", button, "BOTTOM", 0, -1)
            else
                timerText:SetPoint("CENTER", button, "CENTER", 0, 0)
            end
        end
        -- debuff-type tint on a thin 1px edge (the game's own border art is bigger than the icon and spills out)
        local edges = {}
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                             { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
            local t = top:CreateTexture(nil, "OVERLAY")
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetPoint(e[1], button, e[1]); t:SetPoint(e[2], button, e[2])
            if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
            edges[#edges + 1] = t
        end

        if spec.noClicks then pcall(button.SetMouseClickEnabled, button, false) end

        local function Try(label, fn, ...)
            local ok, err = pcall(fn, button, ...)
            if not ok and not Compat.auraInitLogged then
                Compat.errors[#Compat.errors + 1] = "Aura icon setup " .. label .. ": " .. tostring(err)
            end
            return ok
        end
        Try("icon", button.SetIcon, icon)
        if spec.noSwipe then
            cd:Hide()
        else
            Try("timer", button.SetDurationCooldown, cd)
            if timerText and cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        end
        if timerText and button.SetDurationText then
            if not Try("timer text", button.SetDurationText, timerText, {}) then timerText:Hide() end
        end
        if spec.cancel and button.SetCancelAuraButtons then Try("cancel", button.SetCancelAuraButtons, spec.cancel) end
        Try("stacks", button.SetApplicationCount, count, {})
        local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        if styles and styles.PreserveAsset ~= nil and button.AddDispelTypeTexture then
            for _, t in ipairs(edges) do Try("border", button.AddDispelTypeTexture, t, { style = styles.PreserveAsset }) end
        end
        Compat.auraInitCount = (Compat.auraInitCount or 0) + 1
    end
    return function(button)
        local ok, err = pcall(Build, button)
        if not ok then Compat.errors[#Compat.errors + 1] = "Aura icon setup: " .. tostring(err) end
    end
end

function Compat.AuraContainer(parent, unit, spec)
    if not Compat.HasAuraContainers() then return nil end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not c then
        Compat.errors[#Compat.errors + 1] = "Aura container: " .. tostring(c)
        return nil
    end
    if spec.point then c:SetPoint(unpack(spec.point)) end -- placed before any group, so it can draw at once
    c:SetSize(1, 1)
    local dirs = AnchorUtil.FlowDirection
    local size, gap = spec.size or 20, spec.gap or 2
    pcall(c.SetFlowLayoutAnchorPoint, c, spec.anchor or "TOPLEFT")
    pcall(c.SetFlowLayoutGrowthDirection, c, dirs[spec.growH == "LEFT" and "Left" or "Right"],
        dirs[spec.growV == "UP" and "Up" or "Down"])
    if spec.lineWidth then pcall(c.SetFlowLayoutMaximumLineSize, c, spec.lineWidth) end
    local init = AuraCellInit(spec)
    for i, g in ipairs(spec.groups or {}) do
        local okG, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
            maxFrameCount = g.max or 8,
            sortMethod = g.sortMethod, sortDirection = g.sortDirection,
            initializeFrame = init,
            layout = { elementWidth = size, elementHeight = size, elementSpacing = gap, lineSpacing = spec.lineGap or gap,
                       groupLineSpacing = (spec.lineGap or gap) + 2, forceNewLine = i > 1 },
        })
        if not okG then Compat.errors[#Compat.errors + 1] = "Aura container group " .. g.key .. ": " .. tostring(err) end
    end
    -- weapon enchants (imbues, oils, stones) as icons in the same row, before the buffs
    if spec.enchants and c.AddItemEnchantment and AuraContainerItemEnchantmentSlot then
        for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
            local slot = AuraContainerItemEnchantmentSlot[name]
            if slot ~= nil then
                pcall(c.AddItemEnchantment, c, slot, { initializeFrame = init, hidePermanent = true })
            end
        end
        if c.SetItemEnchantmentLayout then
            pcall(c.SetItemEnchantmentLayout, c, { elementWidth = size, elementHeight = size, elementSpacing = gap,
                lineSpacing = spec.lineGap or gap })
        end
    end
    -- a new container starts switched off: until SetEnabled(true) it never reads auras or listens for changes
    local okE, errE = pcall(c.SetEnabled, c, true)
    if not okE then Compat.errors[#Compat.errors + 1] = "Aura container enable: " .. tostring(errE) end
    if unit then
        pcall(c.SetUnit, c, unit)
        pcall(c.UpdateAllAuras, c)
    end
    return c
end

-- A dispel-type outline for a whole frame (raid frames): one aura slot that takes the first debuff matching the
-- filter, drawn as four thin edges the game tints by debuff type (magic blue, curse purple, ...). The slot never
-- takes the mouse, so clicks and tooltips still reach the frame under it.
function Compat.AuraDispelEdges(c, key, filter, owner, thickness)
    if not (c and c.AddAuraSlot) then return nil end
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if not (styles and styles.PreserveAsset ~= nil) then return nil end
    thickness = thickness or 2
    local function Init(button)
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)
        local edges = {
            { "TOPLEFT", "TOPRIGHT", nil, thickness }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness },
            { "TOPLEFT", "BOTTOMLEFT", thickness, nil }, { "TOPRIGHT", "BOTTOMRIGHT", thickness, nil },
        }
        for _, e in ipairs(edges) do
            local t = button:CreateTexture(nil, "OVERLAY", nil, 6)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetPoint(e[1]); t:SetPoint(e[2])
            if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
            local ok, err = pcall(button.AddDispelTypeTexture, button, t, { style = styles.PreserveAsset })
            if not ok then Compat.errors[#Compat.errors + 1] = "Aura dispel edge: " .. tostring(err) end
        end
    end
    local ok, f = pcall(c.AddAuraSlot, c, key, filter, {
        initializeFrame = Init,
        candidateFilters = { includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true } },
    })
    if not ok or not f then
        Compat.errors[#Compat.errors + 1] = "Aura dispel slot: " .. tostring(f)
        return nil
    end
    pcall(f.ClearAllPoints, f)
    pcall(f.SetAllPoints, f, owner)
    return f
end

-- point a container at another unit (nameplates get reused) or refresh it (target changed)
function Compat.AuraContainerUnit(c, unit)
    if not c then return end
    if unit and c.GetUnit and c:GetUnit() ~= unit then pcall(c.SetUnit, c, unit) end
    pcall(c.UpdateAllAuras, c)
end

-- set a group's icon count (0 hides it)
function Compat.AuraContainerCap(c, key, n)
    if not c then return end
    if c.SetAuraGroupEnabled then pcall(c.SetAuraGroupEnabled, c, key, n > 0) end
    pcall(c.SetAuraGroupMaxFrameCount, c, key, n)
end

-- tooltip for an aura by its instance ID
function Compat.AuraTooltip(owner, unit, id, filter, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOMRIGHT")
    local harmful = type(filter) == "string" and filter:find("HARMFUL")
    local fn = harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
    if fn then
        pcall(fn, GameTooltip, unit, id, filter)
    elseif GameTooltip.SetUnitAuraByAuraInstanceID then
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, unit, id)
    end
    GameTooltip:Show()
end

