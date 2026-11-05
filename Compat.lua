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
        print("|cFFFFD100Cys's UI|r: the game doesn't let addons reload the interface on WoW Forever - type |cFFFFFFFF/reload|r.")
        return
    end
    ReloadUI()
end
