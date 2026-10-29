--------------------------------------------------------------------------------
-- Cys's UI - Compat
--
-- Loaded first. Newer game clients (and new Classic versions built on them) move old global functions into
-- C_ namespaces and drop the old names. Where an old name is gone, this file puts it back from the new one so
-- the rest of the UI keeps working unchanged. Nothing is touched while the old function still exists, so on
-- today's Classic Era client this file does nothing. /cui debug lists anything it had to fill in.
--------------------------------------------------------------------------------
CysUICompat = { shimmed = {} }
local shimmed = CysUICompat.shimmed

local function Shim(name, fn)
    if _G[name] == nil and fn then
        _G[name] = fn
        shimmed[#shimmed + 1] = name
    end
end

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
end

-- auras: old UnitAura / UnitBuff / UnitDebuff return values in a list, the new call returns a table
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    Shim("UnitAura", function(unit, index, filter)
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
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
