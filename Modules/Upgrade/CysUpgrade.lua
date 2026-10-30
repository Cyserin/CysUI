CysUI:RegisterModule({
    key = "upgrade", name = "Cys's Upgrade",
    desc = "Scores gear with stat weights you choose and marks bag items that beat what you have equipped.",
    open = function() CysUI:OpenConfig("Upgrade") end,
    body = function(...)
local ADDON_NAME, addon = ...
local CC = C_Container or { GetContainerNumSlots = GetContainerNumSlots, GetContainerItemLink = GetContainerItemLink }
local CysUpgrade = CreateFrame("Frame", "CysUpgradeFrame", UIParent)
_G["CysUpgrade"] = CysUpgrade

CysUpgrade:RegisterEvent("PLAYER_LOGIN")
CysUpgrade:RegisterEvent("PLAYER_LOGOUT")
CysUpgrade:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
CysUpgrade:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

local CalculateItemScore
local GetTargetSlotAndEquipped
local UpdateWeightsFromRows
local RefreshRows
local CreateImportExportPopup
local CreateUserGuidePopup
local CheckAutoProfileSwitch

local cysScanner = CreateFrame("GameTooltip", "CysScannerTooltip", nil, "GameTooltipTemplate")
cysScanner:SetOwner(UIParent, "ANCHOR_NONE")

local function NormalizeStatKey(key)
    if not key then return "" end
    return string.gsub(key, "_SHORT$", "")
end

-- The game's GetItemStats ignores the stats of "of the Eagle / Owl / Monkey" style suffixes, so the
-- numbers are read from the item's own tooltip text instead, which always shows what the item really
-- has. GetItemStats only fills in anything the tooltip reading did not recognise.
local statCache = {}

local PRIMARY = {
    strength = "ITEM_MOD_STRENGTH", agility = "ITEM_MOD_AGILITY", stamina = "ITEM_MOD_STAMINA",
    intellect = "ITEM_MOD_INTELLECT", spirit = "ITEM_MOD_SPIRIT", health = "ITEM_MOD_HEALTH", mana = "ITEM_MOD_MANA",
}
local RESISTS = { holy = 1, fire = 2, nature = 3, frost = 4, shadow = 5, arcane = 6 }
local SCHOOL_DAMAGE = {
    arcane = "ITEM_MOD_SPELL_ARCANE_DAMAGE", fire = "ITEM_MOD_SPELL_FIRE_DAMAGE", nature = "ITEM_MOD_SPELL_NATURE_DAMAGE",
    frost = "ITEM_MOD_SPELL_FROST_DAMAGE", shadow = "ITEM_MOD_SPELL_SHADOW_DAMAGE", holy = "ITEM_MOD_SPELL_HOLY_DAMAGE",
}
-- "Equip:" lines, lower-cased and without the prefix
local EQUIP_LINES = {
    { "^increases attack power by (%d+) in cat", "ITEM_MOD_FERAL_ATTACK_POWER" },
    { "^increases ranged attack power by (%d+)", "ITEM_MOD_RANGED_ATTACK_POWER" },
    { "^increases attack power by (%d+)", "ITEM_MOD_ATTACK_POWER" },
    { "^increases damage and healing done by magical spells and effects by up to (%d+)", "ITEM_MOD_SPELL_POWER" },
    { "^increases healing done by spells and effects by up to (%d+)", "ITEM_MOD_SPELL_HEALING_DONE" },
    { "^restores (%d+) mana per 5 sec", "ITEM_MOD_POWER_REGEN0" },
    { "^restores (%d+) health per 5 sec", "ITEM_MOD_HEALTH_REGEN" },
    { "^improves your chance to get a critical strike with spells by (%d+)", "ITEM_MOD_SPELL_CRIT_RATING" },
    { "^improves your chance to get a critical strike by (%d+)", "ITEM_MOD_CRIT_RATING" },
    { "^improves your chance to hit with spells by (%d+)", "ITEM_MOD_SPELL_HIT_RATING" },
    { "^improves your chance to hit by (%d+)", "ITEM_MOD_HIT_RATING" },
    { "^increases your chance to dodge an attack by (%d+)", "ITEM_MOD_DODGE_RATING" },
    { "^increases your chance to parry an attack by (%d+)", "ITEM_MOD_PARRY_RATING" },
    { "^increases your chance to block attacks with a shield by (%d+)", "ITEM_MOD_BLOCK_RATING" },
    { "^increases the block value of your shield by (%d+)", "ITEM_MOD_BLOCK_VALUE" },
    { "^increased defense %+(%d+)", "ITEM_MOD_DEFENSE_SKILL_RATING" },
    { "^decreases the magical resistances of your spell targets by (%d+)", "ITEM_MOD_SPELL_PENETRATION" },
}

local function GetDetailedItemStats(itemLink)
    if not itemLink then return {} end
    if statCache[itemLink] then return statCache[itemLink] end

    cysScanner:ClearLines()
    cysScanner:SetHyperlink(itemLink)

    local stats = {}
    local function Add(key, value)
        value = tonumber(value)
        if key and value then stats[key] = (stats[key] or 0) + value end
    end

    local dps, weaponSpeed, rangedDps, rangedSpeed = 0, 0, 0, 0
    local dmgMin, dmgMax, rangedDmgMin, rangedDmgMax = 0, 0, 0, 0
    local equipLoc = select(9, GetItemInfo(itemLink))
    local isRanged = equipLoc and string.find(equipLoc, "RANGED") ~= nil
    local numLines = cysScanner:NumLines()
    for i = 1, numLines do
        local line = _G["CysScannerTooltipTextLeft"..i]
        local leftText = line and line:GetText()
        if leftText then
            local r, g = 1, 1
            if line.GetTextColor then r, g = line:GetTextColor() end
            local isGreen = (r or 1) < 0.5 and (g or 1) > 0.8 -- enchants and "Equip:" lines are green
            local plain = string.lower((string.gsub(string.gsub(leftText, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")))

            -- base and suffix stats: "+3 Intellect", "-5 Stamina", "39 Armor", "+10 Fire Resistance"
            if not isGreen then
                local n, word = string.match(plain, "^([%+%-]%d+) (%a+)$")
                if n and PRIMARY[word] then Add(PRIMARY[word], n) end
                local armor = string.match(plain, "^(%d+) armor$")
                if armor then Add("RESISTANCE0_NAME", armor) end
                -- a shield's base "13 Block" line is its Block Value (the site calls it "Block Value (Base)")
                local blockBase = string.match(plain, "^(%d+) block$")
                if blockBase then Add("ITEM_MOD_BLOCK_VALUE", blockBase) end
                -- weapon damage range "23 - 43 Damage" (listed in the change list like the site does, no score)
                local dmin, dmax = string.match(plain, "^(%d+)%s*%-%s*(%d+)%s+.-damage$")
                if dmin and dmax then
                    if isRanged then rangedDmgMin, rangedDmgMax = tonumber(dmin), tonumber(dmax)
                    else dmgMin, dmgMax = tonumber(dmin), tonumber(dmax) end
                end
                local rn, school = string.match(plain, "^%+(%d+) (%a+) resistance$")
                if rn and RESISTS[school] then Add("RESISTANCE" .. RESISTS[school] .. "_NAME", rn) end
            end

            local equip = string.match(plain, "^equip: (.+)$")
            if equip then
                for _, p in ipairs(EQUIP_LINES) do
                    local v = string.match(equip, p[1])
                    if v then Add(p[2], v); break end
                end
                local school, v = string.match(equip, "^increases damage done by (%a+) spells and effects by up to (%d+)")
                if school and SCHOOL_DAMAGE[school] then Add(SCHOOL_DAMAGE[school], v) end
            end

            -- "Speed 2.60" sits in the tooltip's right-hand column, "(9.4 damage per second)" on the left
            local rightLine = _G["CysScannerTooltipTextRight"..i]
            local rightText = rightLine and rightLine:GetText() or ""
            local s = string.match(rightText, "[Ss]peed%s+([%d%.]+)") or string.match(leftText, "[Ss]peed%s+([%d%.]+)")
            if s then
                local val = tonumber(s)
                if val and val > 0 and val < 10 then
                    if isRanged then rangedSpeed = val else weaponSpeed = val end
                end
            end

            local d = string.match(leftText, "%(([%d%.]+)%s+damage per second%)")
            if d then
                local val = tonumber(d)
                if val and val > 0 then
                    if isRanged then rangedDps = val else dps = val end
                end
            end
        end
    end

    -- if the speed was not found line by line, look at every piece of text the tooltip holds
    if weaponSpeed == 0 and rangedSpeed == 0 and cysScanner.GetRegions then
        for _, region in ipairs({ cysScanner:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                local t = region:GetText()
                local sp = t and string.match(t, "[Ss]peed%s+([%d%.]+)")
                local val = tonumber(sp)
                if val and val > 0 and val < 10 then
                    if isRanged then rangedSpeed = val else weaponSpeed = val end
                    break
                end
            end
        end
    end

    if dmgMax > 0 then stats["ITEM_MOD_WEAPON_DAMAGE_MIN"] = dmgMin; stats["ITEM_MOD_WEAPON_DAMAGE_MAX"] = dmgMax end
    if rangedDmgMax > 0 then stats["ITEM_MOD_RANGED_DAMAGE_MIN"] = rangedDmgMin; stats["ITEM_MOD_RANGED_DAMAGE_MAX"] = rangedDmgMax end
    if dps > 0 then stats["ITEM_MOD_WEAPON_DPS"] = dps end
    if weaponSpeed > 0 then stats["ITEM_MOD_ATTACK_SPEED"] = weaponSpeed end
    if rangedDps > 0 then stats["ITEM_MOD_RANGED_DPS"] = rangedDps end
    if rangedSpeed > 0 then stats["ITEM_MOD_RANGED_ATTACK_SPEED"] = rangedSpeed end

    -- whatever the tooltip reading did not cover
    for k, v in pairs(GetItemStats(itemLink) or {}) do
        local key = NormalizeStatKey(k)
        -- the game's own damage-per-second entry duplicates the weapon DPS read above
        if stats[key] == nil and key ~= "ITEM_MOD_DAMAGE_PER_SECOND" then stats[key] = v end
    end

    -- only keep it once the game has really loaded the item (an empty first read would stick otherwise)
    if numLines > 1 then statCache[itemLink] = stats end
    return stats
end

UpdateWeightsFromRows = function()
    CysUpgrade.weights = {}
    if CysUpgrade.statRows then
        for _, row in ipairs(CysUpgrade.statRows) do
            if row.key and row.key ~= "" and row.weight then
                CysUpgrade.weights[NormalizeStatKey(row.key)] = tonumber(row.weight) or 0
            end
        end
    end
end

local function IsItemValidForClass(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, itemType, itemSubType, _, itemEquipLoc = GetItemInfo(itemLink)
    local _, playerClass = UnitClass("player")
    playerClass = playerClass or ""
    local playerLevel = UnitLevel("player") or 1

    local subType = itemSubType and string.lower(itemSubType) or ""
    local equipLoc = itemEquipLoc or ""
    local t = itemType and string.lower(itemType) or ""

    if playerClass == "SHAMAN" or playerClass == "DRUID" or playerClass == "PALADIN" then
        if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_THROWN" then
            if subType ~= "totem" and subType ~= "idols" and subType ~= "librams" and subType ~= "relic" then
                return false
            end
        end
    end

    if subType == "wand" then
        if playerClass ~= "MAGE" and playerClass ~= "PRIEST" and playerClass ~= "WARLOCK" then
            return false
        end
    end

    if t == "armor" or equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_HEAD" or equipLoc == "INVTYPE_SHOULDER" or equipLoc == "INVTYPE_LEGS" or equipLoc == "INVTYPE_FEET" or equipLoc == "INVTYPE_WAIST" or equipLoc == "INVTYPE_WRIST" or equipLoc == "INVTYPE_HAND" then
        if playerClass == "SHAMAN" or playerClass == "HUNTER" then
            if subType == "plate" then return false end
            if subType == "mail" and playerLevel < 40 then return false end
        elseif playerClass == "DRUID" or playerClass == "MAGE" or playerClass == "PRIEST" or playerClass == "WARLOCK" then
            if subType == "mail" or subType == "plate" or subType == "leather" then
                if playerClass ~= "DRUID" and subType == "leather" then return false end
                if playerClass == "DRUID" and subType ~= "leather" and subType ~= "cloth" then return false end
            end
        elseif playerClass == "ROGUE" then
            if subType == "mail" or subType == "plate" then return false end
        elseif playerClass == "WARRIOR" or playerClass == "PALADIN" then
            if subType == "plate" and playerLevel < 40 then return false end
        end
    end

    return true
end

function CysUpgrade:GetItemEP(itemLink, customWeights)
    if not itemLink then return 0 end
    if not IsItemValidForClass(itemLink) then return 0 end

    local stats = GetDetailedItemStats(itemLink)
    UpdateWeightsFromRows()
    local rawWeights = (type(customWeights) == "table") and customWeights or CysUpgrade.weights
    local weights = {}
    for k, v in pairs(rawWeights) do weights[NormalizeStatKey(k)] = v end

    local totalScore = 0
    
    for statKey, statValue in pairs(stats) do
        if statKey ~= "ITEM_MOD_ATTACK_SPEED" and statKey ~= "ITEM_MOD_RANGED_ATTACK_SPEED" then
            local weight = weights[statKey] or 0
            if weight ~= 0 then
                totalScore = totalScore + (statValue * weight)
            end
        end
    end
    
    local weaponSpeed = stats["ITEM_MOD_ATTACK_SPEED"]
    if weaponSpeed and weaponSpeed > 0 then
        local speedWeight = weights["ITEM_MOD_ATTACK_SPEED"] or 0
        if speedWeight ~= 0 then
            totalScore = totalScore + (weaponSpeed * speedWeight)   -- same as SixtyUpgrades: speed x weight
        end
    end

    local rangedSpeed = stats["ITEM_MOD_RANGED_ATTACK_SPEED"]
    if rangedSpeed and rangedSpeed > 0 then
        local rSpeedWeight = weights["ITEM_MOD_RANGED_ATTACK_SPEED"] or 0
        if rSpeedWeight ~= 0 then
            totalScore = totalScore + (rangedSpeed * rSpeedWeight)
        end
    end

    if totalScore == 0 then
        for _, v in pairs(stats) do
            if v > 0 then totalScore = 1; break; end
        end
    end

    return totalScore
end

CalculateItemScore = function(link, weights) return CysUpgrade:GetItemEP(link, weights) end

local SLOT_MAP = {
    INVTYPE_HEAD              = 1,
    INVTYPE_NECK              = 6,
    INVTYPE_SHOULDER          = 3,
    INVTYPE_BODY              = 4,
    INVTYPE_CHEST             = 5,
    INVTYPE_ROBE              = 5,
    INVTYPE_WAIST             = 6,
    INVTYPE_LEGS              = 7,
    INVTYPE_FEET              = 8,
    INVTYPE_WRIST             = 9,
    INVTYPE_HAND              = 10,
    INVTYPE_FINGER            = {11, 12},
    INVTYPE_TRINKET           = {13, 14},
    INVTYPE_CLOAK             = 15,
    INVTYPE_WEAPON            = {16, 17},
    INVTYPE_2HWEAPON          = 16,
    INVTYPE_WEAPONMAINHAND    = 16,
    INVTYPE_WEAPONOFFHAND     = 17,
    INVTYPE_SHIELD            = 17,
    INVTYPE_HOLDABLE          = 17,
    INVTYPE_RANGED            = 18,
    INVTYPE_RELIC             = 18,
}

GetTargetSlotAndEquipped = function(itemLink, profileWeights)
    if not itemLink then return nil, nil, 0 end
    if not IsItemValidForClass(itemLink) then return nil, nil, nil end

    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    local slotOrTheTable = SLOT_MAP[itemEquipLoc]
    if not slotOrTheTable then return nil, nil, 0 end

    local activeProf = string.lower(CysUpgrade.activeProfileName or "")
    local mainLink = GetInventoryItemLink("player", 16)
    local mainEquipLoc = mainLink and select(9, GetItemInfo(mainLink)) or nil
    local hasTwoHanderEquipped = (mainEquipLoc == "INVTYPE_2HWEAPON")

    local isTankProfile = string.find(activeProf, "tank") ~= nil or string.find(activeProf, "mitigation") ~= nil
    if isTankProfile then
        if itemEquipLoc == "INVTYPE_2HWEAPON" then return nil, nil, nil end
    else
        if hasTwoHanderEquipped and (itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" or itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or itemEquipLoc == "INVTYPE_SHIELD") then
            return nil, nil, nil
        end
    end

    if type(slotOrTheTable) == "table" then
        local slot1, slot2 = slotOrTheTable[1], slotOrTheTable[2]
        if isTankProfile and itemEquipLoc == "INVTYPE_WEAPON" then
            slot1 = 16
            local link1 = GetInventoryItemLink("player", slot1)
            local ep1 = link1 and CysUpgrade:GetItemEP(link1, profileWeights) or 0
            return slot1, link1, ep1
        end

        local link1 = GetInventoryItemLink("player", slot1)
        local link2 = GetInventoryItemLink("player", slot2)
        local ep1 = link1 and CysUpgrade:GetItemEP(link1, profileWeights) or 0
        local ep2 = link2 and CysUpgrade:GetItemEP(link2, profileWeights) or 0

        if not link1 then return slot1, nil, 0 end
        if not link2 then return slot2, nil, 0 end

        if ep1 <= ep2 then return slot1, link1, ep1 else return slot2, link2, ep2 end
    elseif slotOrTheTable == 16 and (itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND") then
        local slotID = 16
        local equippedLink = GetInventoryItemLink("player", slotID)
local equippedEP = equippedLink and CysUpgrade:GetItemEP(equippedLink, profileWeights) or 0
return slotID, equippedLink, equippedEP
elseif itemEquipLoc == "INVTYPE_2HWEAPON" then
local link1 = GetInventoryItemLink("player", 16)
local link2 = GetInventoryItemLink("player", 17)
local ep1 = link1 and CysUpgrade:GetItemEP(link1, profileWeights) or 0
local ep2 = link2 and CysUpgrade:GetItemEP(link2, profileWeights) or 0
return 16, link1, ep1 + ep2
else
local slotID = slotOrTheTable
local equippedLink = GetInventoryItemLink("player", slotID)
local equippedEP = equippedLink and CysUpgrade:GetItemEP(equippedLink, profileWeights) or 0
return slotID, equippedLink, equippedEP
end
end
CheckAutoProfileSwitch = function(event)
local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
if not CysUIDB or not CysUIDB.upgrade or not CysUIDB.upgrade.charProfiles or not CysUIDB.upgrade.charProfiles[charKey] then return end
local charDB = CysUIDB.upgrade.charProfiles[charKey]
charDB.specBindings = charDB.specBindings or {}
local activeSpec = GetActiveTalentGroup and GetActiveTalentGroup() or 1
local targetProfile = charDB.specBindings[activeSpec]
-- a worn Armory set that is linked to a profile wins over the talent spec
if CysArmory and CysArmory.GetEquippedSetProfile then
local okSet, setProfile = pcall(CysArmory.GetEquippedSetProfile, CysArmory)
if okSet and setProfile and charDB.profiles[setProfile] then targetProfile = setProfile end
end
if targetProfile and CysUpgrade.activeProfileName ~= targetProfile and charDB.profiles[targetProfile] then
CysUpgrade.activeProfileName = targetProfile
charDB.activeProfile = targetProfile
CysUpgrade.statRows = charDB.profiles[targetProfile].statRows or { { key = "", weight = 0 } }
UpdateWeightsFromRows()
end
end
local FRIENDLY = {
    ITEM_MOD_STRENGTH = "Strength", ITEM_MOD_AGILITY = "Agility", ITEM_MOD_STAMINA = "Stamina",
    ITEM_MOD_INTELLECT = "Intellect", ITEM_MOD_SPIRIT = "Spirit", ITEM_MOD_MANA = "Mana", ITEM_MOD_HEALTH = "Health",
    ITEM_MOD_HEALTH_REGEN = "Health per 5 Sec.", ITEM_MOD_SPELL_POWER = "Spell Power",
    ITEM_MOD_SPELL_HEALING_DONE = "Healing", ITEM_MOD_SPELL_HIT_RATING = "Spell Hit",
    ITEM_MOD_SPELL_CRIT_RATING = "Spell Crit", ITEM_MOD_SPELL_PENETRATION = "Spell Penetration",
    ITEM_MOD_POWER_REGEN0 = "Mana per 5 Sec.", ITEM_MOD_ATTACK_POWER = "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER = "Ranged Attack Power", ITEM_MOD_FERAL_ATTACK_POWER = "Feral Attack Power",
    ITEM_MOD_WEAPON_DPS = "Weapon DPS", ITEM_MOD_RANGED_DPS = "Ranged DPS", ITEM_MOD_HIT_RATING = "Hit Chance",
    ITEM_MOD_CRIT_RATING = "Crit Chance", ITEM_MOD_HASTE_RATING = "Haste", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_DEFENSE_SKILL_RATING = "Defense", ITEM_MOD_DODGE_RATING = "Dodge Chance",
    ITEM_MOD_PARRY_RATING = "Parry Chance", ITEM_MOD_BLOCK_RATING = "Block Chance", ITEM_MOD_BLOCK_VALUE = "Block Value (Base)",
    ITEM_MOD_WEAPON_DAMAGE_MIN = "Weapon Damage (Min)", ITEM_MOD_WEAPON_DAMAGE_MAX = "Weapon Damage (Max)",
    ITEM_MOD_RANGED_DAMAGE_MIN = "Ranged Damage (Min)", ITEM_MOD_RANGED_DAMAGE_MAX = "Ranged Damage (Max)",
    ITEM_MOD_SPELL_ARCANE_DAMAGE = "Arcane Damage", ITEM_MOD_SPELL_FIRE_DAMAGE = "Fire Damage",
    ITEM_MOD_SPELL_NATURE_DAMAGE = "Nature Damage", ITEM_MOD_SPELL_FROST_DAMAGE = "Frost Damage",
    ITEM_MOD_SPELL_SHADOW_DAMAGE = "Shadow Damage", ITEM_MOD_SPELL_HOLY_DAMAGE = "Holy Damage",
    RESISTANCE1_NAME = "Holy Resistance", RESISTANCE2_NAME = "Fire Resistance", RESISTANCE3_NAME = "Nature Resistance",
    RESISTANCE4_NAME = "Frost Resistance", RESISTANCE5_NAME = "Shadow Resistance", RESISTANCE6_NAME = "Arcane Resistance",
}
local function StatLabel(k)
    if FRIENDLY[k] then return FRIENDLY[k] end
    local s = string.lower((string.gsub(string.gsub(k, "^ITEM_MOD_", ""), "_", " ")))
    return (string.gsub(s, "(%a)(%w*)", function(a, b) return string.upper(a) .. b end))
end
local function Fmt(v) return string.format(v % 1 == 0 and "%d" or "%.1f", v) end
local function FmtSpeed(v)
    local t = string.format("%.2f", v)
    t = string.gsub(t, "0+$", "")
    return (string.gsub(t, "%.$", ""))
end
-- whole numbers like the site; a value that would round to 0 keeps its decimal so it never reads as "+0"
local function Whole(v)
    local r = math.floor(math.abs(v) + 0.5)
    if r == 0 then return string.format("%.1f", math.abs(v)) end
    return tostring(r)
end
local SIDEGRADE = 0.05 -- a score difference smaller than this counts as the same

-- adds the score, what it replaces and exactly what changes to an item tooltip
local function OnTooltipItem(tooltip)
    -- comparison tooltips would otherwise compare an item with itself
    local tipName = tooltip:GetName()
    if tipName == "ShoppingTooltip1" or tipName == "ShoppingTooltip2" then return end

    local _, itemLink = tooltip:GetItem()
    if not itemLink or not IsItemValidForClass(itemLink) then return end

    UpdateWeightsFromRows()
    local weights = CysUpgrade.weights
    local profName = CysUpgrade.activeProfileName ~= "" and CysUpgrade.activeProfileName or "Default"
    local itemScore = CysUpgrade:GetItemEP(itemLink, weights)
    if itemScore <= 0 then return end

    local _, equippedLink = GetTargetSlotAndEquipped(itemLink, weights)
    local netDiff = itemScore
    if equippedLink then netDiff = itemScore - CysUpgrade:GetItemEP(equippedLink, weights) end

    tooltip:AddLine(" ")
    if netDiff > SIDEGRADE then
        tooltip:AddLine(string.format("CysUpgrade Score [%s]: %s EP |cff20ff20(+%s Upgrade)|r", profName, Whole(itemScore), Whole(netDiff)), 0, 1, 1)
    elseif netDiff < -SIDEGRADE then
        tooltip:AddLine(string.format("CysUpgrade Score [%s]: %s EP |cffff2020(-%s Downgrade)|r", profName, Whole(itemScore), Whole(netDiff)), 0, 1, 1)
    else
        tooltip:AddLine(string.format("CysUpgrade Score [%s]: %s EP |cffffd100(Side-grade)|r", profName, Whole(itemScore)), 0, 1, 1)
    end

    if not equippedLink then
        tooltip:AddLine("Replaces: nothing (empty slot)", 0.2, 1, 0.2)
        return
    end

    local eqName = GetItemInfo(equippedLink)
    if eqName then tooltip:AddLine(string.format("Replaces: %s", eqName), 0.8, 0.8, 0.8) end

    -- only the stats that really differ
    local newStats, eqStats = GetDetailedItemStats(itemLink), GetDetailedItemStats(equippedLink)
    local keys, changes = {}, {}
    for k in pairs(newStats) do keys[k] = true end
    for k in pairs(eqStats) do keys[k] = true end
    for k in pairs(keys) do
        if k ~= "ITEM_MOD_ATTACK_SPEED" and k ~= "ITEM_MOD_RANGED_ATTACK_SPEED" then
            local delta = (newStats[k] or 0) - (eqStats[k] or 0)
            if math.abs(delta) > 0.001 then
                changes[#changes + 1] = { label = StatLabel(k), delta = delta, ep = delta * (weights[k] or 0) }
            end
        end
    end
    -- weapon speed counts like any other stat (speed x weight, as on SixtyUpgrades): a negative weight favors
    -- fast weapons, a positive one slow weapons
    local sn, se = newStats["ITEM_MOD_ATTACK_SPEED"], eqStats["ITEM_MOD_ATTACK_SPEED"]
    if sn and se and math.abs(sn - se) > 0.004 then
        changes[#changes + 1] = { label = "Weapon Speed", speed = true, delta = sn - se,
            ep = (sn - se) * (weights["ITEM_MOD_ATTACK_SPEED"] or 0) }
    end
    -- like the site: gains first, then losses, each group in alphabetical order
    local function IsGain(c) return c.delta > 0 end
    table.sort(changes, function(a, b)
        local ga, gb = IsGain(a), IsGain(b)
        if ga ~= gb then return ga end
        return string.lower(a.label) < string.lower(b.label)
    end)
    if #changes == 0 then
        tooltip:AddLine("  Same stats as what you are wearing", 0.8, 0.8, 0.2)
    end
    for _, c in ipairs(changes) do
        local effect = ""
        if math.abs(c.ep) >= 0.05 then effect = string.format("  |cff999999(%+.1f EP)|r", c.ep) end
        local num = c.speed and FmtSpeed(c.delta) or Fmt(c.delta)
        if c.delta > 0 then
            tooltip:AddLine(string.format("  • +%s %s%s", num, c.label, effect), 0.2, 1, 0.2)
        else
            tooltip:AddLine(string.format("  • %s %s%s", num, c.label, effect), 1, 0.2, 0.2)
        end
    end
end

CysUpgrade:SetScript("OnEvent", function(self, event, arg1)
if event == "ADDON_LOADED" then
local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
if CysUIDB then
CysUIDB.upgrade = CysUIDB.upgrade or {}
CysUIDB.upgrade.charProfiles = CysUIDB.upgrade.charProfiles or {}
CysUIDB.upgrade.charProfiles[charKey] = CysUIDB.upgrade.charProfiles[charKey] or { profiles = {}, activeProfile = "", specBindings = {} }
local charDB = CysUIDB.upgrade.charProfiles[charKey]
-- one-time switch of the weapon speed convention: the weight used to be multiplied by (3.0 - speed), now by speed
-- itself like SixtyUpgrades does, so the sign of every saved speed weight flips and nothing changes in practice
if (CysUIDB.upgrade.speedConvention or 1) < 2 then
for _, cd in pairs(CysUIDB.upgrade.charProfiles) do
for _, prof in pairs(cd.profiles or {}) do
for _, row in ipairs(prof.statRows or {}) do
if (row.key == "ITEM_MOD_ATTACK_SPEED" or row.key == "ITEM_MOD_RANGED_ATTACK_SPEED") and row.weight then
row.weight = -row.weight
end
end
end
end
CysUIDB.upgrade.speedConvention = 2
end
CysUpgrade.activeProfileName = charDB.activeProfile or ""
if CysUpgrade.activeProfileName ~= "" and charDB.profiles[CysUpgrade.activeProfileName] then
CysUpgrade.statRows = charDB.profiles[CysUpgrade.activeProfileName].statRows
else
CysUpgrade.statRows = { { key = "", weight = 0 } }
CysUpgrade.activeProfileName = ""
end
else
CysUpgrade.statRows = { { key = "", weight = 0 } }
CysUpgrade.activeProfileName = ""
end
UpdateWeightsFromRows()
elseif event == "PLAYER_LOGIN" then
local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
if CysUIDB and CysUIDB.upgrade and CysUIDB.upgrade.charProfiles and CysUIDB.upgrade.charProfiles[charKey] then
local charDB = CysUIDB.upgrade.charProfiles[charKey]
if CysUpgrade.activeProfileName ~= "" and charDB.profiles[CysUpgrade.activeProfileName] then
CysUpgrade.statRows = charDB.profiles[CysUpgrade.activeProfileName].statRows
end
end
UpdateWeightsFromRows()
CheckAutoProfileSwitch(event)
-- newer clients feed item tooltips through TooltipDataProcessor and drop the OnTooltipSetItem script
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
if not CysUpgrade.tipHooked then
CysUpgrade.tipHooked = true
pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
if tooltip == GameTooltip then OnTooltipItem(tooltip) end
end)
end
elseif GameTooltip and GameTooltip.HookScript then
pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", OnTooltipItem)
end
elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
CheckAutoProfileSwitch(event)
elseif event == "PLAYER_LOGOUT" then
local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
if CysUIDB and CysUIDB.upgrade and CysUpgrade.activeProfileName ~= "" then
CysUIDB.upgrade.charProfiles = CysUIDB.upgrade.charProfiles or {}
CysUIDB.upgrade.charProfiles[charKey] = CysUIDB.upgrade.charProfiles[charKey] or { profiles = {} }
CysUpgrade.activeProfileName = CysUpgrade.activeProfileName
CysUIDB.upgrade.charProfiles[charKey].activeProfile = CysUpgrade.activeProfileName
CysUIDB.upgrade.charProfiles[charKey].profiles[CysUpgrade.activeProfileName] = { statRows = CysUpgrade.statRows }
end
end
end)
local STAT_REGISTRY = {
{ name = "Strength", key = "ITEM_MOD_STRENGTH_SHORT" },
{ name = "Agility", key = "ITEM_MOD_AGILITY_SHORT" },
{ name = "Stamina", key = "ITEM_MOD_STAMINA_SHORT" },
{ name = "Intellect", key = "ITEM_MOD_INTELLECT_SHORT" },
{ name = "Spirit", key = "ITEM_MOD_SPIRIT_SHORT" },
{ name = "Mana", key = "ITEM_MOD_MANA_SHORT" },
{ name = "Health", key = "ITEM_MOD_HEALTH_SHORT" },
{ name = "Health per 5 Sec.", key = "ITEM_MOD_HEALTH_REGEN_SHORT" },
{ name = "Spell Damage", key = "ITEM_MOD_SPELL_POWER_SHORT" },
{ name = "Healing", key = "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
{ name = "Spell Hit", key = "ITEM_MOD_SPELL_HIT_RATING_SHORT" },
{ name = "Spell Crit", key = "ITEM_MOD_SPELL_CRIT_RATING_SHORT" },
{ name = "Spell Penetration", key = "ITEM_MOD_SPELL_PENETRATION_SHORT" },
{ name = "Mana per 5 Sec.", key = "ITEM_MOD_POWER_REGEN0_SHORT" },
{ name = "Arcane Damage", key = "ITEM_MOD_SPELL_ARCANE_DAMAGE_SHORT" },
{ name = "Fire Damage", key = "ITEM_MOD_SPELL_FIRE_DAMAGE_SHORT" },
{ name = "Nature Damage", key = "ITEM_MOD_SPELL_NATURE_DAMAGE_SHORT" },
{ name = "Frost Damage", key = "ITEM_MOD_SPELL_FROST_DAMAGE_SHORT" },
{ name = "Shadow Damage", key = "ITEM_MOD_SPELL_SHADOW_DAMAGE_SHORT" },
{ name = "Holy Damage", key = "ITEM_MOD_SPELL_HOLY_DAMAGE_SHORT" },
{ name = "Attack Power", key = "ITEM_MOD_ATTACK_POWER_SHORT" },
{ name = "Feral Attack Power", key = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
{ name = "Weapon DPS", key = "ITEM_MOD_WEAPON_DPS" },
{ name = "Weapon Speed", key = "ITEM_MOD_ATTACK_SPEED" },
{ name = "Hit Chance", key = "ITEM_MOD_HIT_RATING_SHORT" },
{ name = "Crit Chance", key = "ITEM_MOD_CRIT_RATING_SHORT" },
{ name = "Haste", key = "ITEM_MOD_HASTE_RATING_SHORT" },
{ name = "Ranged Attack Power", key = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
{ name = "Ranged Weapon DPS", key = "ITEM_MOD_RANGED_DPS" },
{ name = "Ranged Weapon Speed", key = "ITEM_MOD_RANGED_ATTACK_SPEED" },
{ name = "Ranged Hit Chance", key = "ITEM_MOD_SPELL_HIT_RATING_SHORT" },
{ name = "Armor", key = "RESISTANCE0_NAME" },
{ name = "Defense", key = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
{ name = "Dodge Chance", key = "ITEM_MOD_DODGE_RATING_SHORT" },
{ name = "Parry Chance", key = "ITEM_MOD_PARRY_RATING_SHORT" },
{ name = "Block Chance", key = "ITEM_MOD_BLOCK_RATING_SHORT" },
{ name = "Block Value", key = "ITEM_MOD_BLOCK_VALUE_SHORT" },
{ name = "Arcane Resistance", key = "RESISTANCE6_NAME" },
{ name = "Fire Resistance", key = "RESISTANCE2_NAME" },
{ name = "Nature Resistance", key = "RESISTANCE3_NAME" },
{ name = "Frost Resistance", key = "RESISTANCE4_NAME" },
{ name = "Shadow Resistance", key = "RESISTANCE5_NAME" },
}
local ALIAS_MAP = {
strength = "ITEM_MOD_STRENGTH_SHORT", str = "ITEM_MOD_STRENGTH_SHORT",
agility = "ITEM_MOD_AGILITY_SHORT", agi = "ITEM_MOD_AGILITY_SHORT",
stamina = "ITEM_MOD_STAMINA_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
intellect = "ITEM_MOD_INTELLECT_SHORT", int = "ITEM_MOD_INTELLECT_SHORT",
spirit = "ITEM_MOD_SPIRIT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT",
mana = "ITEM_MOD_MANA_SHORT", health = "ITEM_MOD_HEALTH_SHORT",
hp5 = "ITEM_MOD_HEALTH_REGEN_SHORT", healthper5sec = "ITEM_MOD_HEALTH_REGEN_SHORT",
spelldamage = "ITEM_MOD_SPELL_POWER_SHORT", sp = "ITEM_MOD_SPELL_POWER_SHORT",
healing = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
spellhit = "ITEM_MOD_SPELL_HIT_RATING_SHORT",
spellcrit = "ITEM_MOD_SPELL_CRIT_RATING_SHORT",
spellpenetration = "ITEM_MOD_SPELL_PENETRATION_SHORT", spellpen = "ITEM_MOD_SPELL_PENETRATION_SHORT",
mp5 = "ITEM_MOD_POWER_REGEN0_SHORT", manaper5sec = "ITEM_MOD_POWER_REGEN0_SHORT",
arcanedamage = "ITEM_MOD_SPELL_ARCANE_DAMAGE_SHORT",
firedamage = "ITEM_MOD_SPELL_FIRE_DAMAGE_SHORT",
naturedamage = "ITEM_MOD_SPELL_NATURE_DAMAGE_SHORT",
frostdamage = "ITEM_MOD_SPELL_FROST_DAMAGE_SHORT",
shadowdamage = "ITEM_MOD_SPELL_SHADOW_DAMAGE_SHORT",
holydamage = "ITEM_MOD_SPELL_HOLY_DAMAGE_SHORT",
attackpower = "ITEM_MOD_ATTACK_POWER_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
feralattackpower = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT", fap = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
dps = "ITEM_MOD_WEAPON_DPS", weapondps = "ITEM_MOD_WEAPON_DPS",
speed = "ITEM_MOD_ATTACK_SPEED", weaponspeed = "ITEM_MOD_ATTACK_SPEED",
hit = "ITEM_MOD_HIT_RATING_SHORT", hitchance = "ITEM_MOD_HIT_RATING_SHORT",
crit = "ITEM_MOD_CRIT_RATING_SHORT", critchance = "ITEM_MOD_CRIT_RATING_SHORT",
haste = "ITEM_MOD_HASTE_RATING_SHORT",
rangedattackpower = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
rangeddps = "ITEM_MOD_RANGED_DPS", rangedweapondps = "ITEM_MOD_RANGED_DPS",
rangedweaponspeed = "ITEM_MOD_RANGED_ATTACK_SPEED",
rangedhitchance = "ITEM_MOD_SPELL_HIT_RATING_SHORT",
armor = "RESISTANCE0_NAME",
defense = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
dodge = "ITEM_MOD_DODGE_RATING_SHORT", dodgechance = "ITEM_MOD_DODGE_RATING_SHORT",
parry = "ITEM_MOD_PARRY_RATING_SHORT", parrychance = "ITEM_MOD_PARRY_RATING_SHORT",
block = "ITEM_MOD_BLOCK_RATING_SHORT", blockchance = "ITEM_MOD_BLOCK_RATING_SHORT",
blockvalue = "ITEM_MOD_BLOCK_VALUE_SHORT",
arcaneresistance = "RESISTANCE6_NAME", arcaneres = "RESISTANCE6_NAME",
fireresistance = "RESISTANCE2_NAME", fireres = "RESISTANCE2_NAME",
natureresistance = "RESISTANCE3_NAME", natureres = "RESISTANCE3_NAME",
frostresistance = "RESISTANCE4_NAME", frostres = "RESISTANCE4_NAME",
shadowresistance = "RESISTANCE5_NAME", shadowres = "RESISTANCE5_NAME",
}
CysUpgrade.activeProfileName = ""
CysUpgrade.weights = {}
local function NormName(s) return (string.gsub(string.lower(s or ""), "[^%w]", "")) end
local NAME_TO_KEY
local function ResolveStatKey(raw)
    if not NAME_TO_KEY then
        NAME_TO_KEY = {}
        for _, info in ipairs(STAT_REGISTRY) do
            local n = NormName(info.name)
            if not NAME_TO_KEY[n] then NAME_TO_KEY[n] = info.key end
        end
    end
    local n = NormName(raw)
    if ALIAS_MAP[n] then return ALIAS_MAP[n] end
    if NAME_TO_KEY[n] then return NAME_TO_KEY[n] end
    if string.find(raw, "^ITEM_MOD_") or string.find(raw, "^RESISTANCE%d_NAME$") then return raw end
    return nil
end

-- "Stamina=1, Intellect=0.8" (also one "Name, 1.2" or "Name: 1.2" per line)
local function ParseWeights(text)
    local rows, skipped = {}, 0
    local function Take(name, value)
        local key = ResolveStatKey(strtrim(name))
        local num = tonumber(value)
        if key and num then
            rows[#rows + 1] = { key = key, weight = num }
        else
            skipped = skipped + 1
        end
    end
    for rawLine in string.gmatch(text .. "\n", "([^\r\n]+)") do
        local line = strtrim(rawLine)
        if string.lower(line):gsub("%s", "") == "stat,value" then line = "" end -- the header line of a SixtyUpgrades CSV
        if line ~= "" then
            if string.find(line, "=") then
                for token in string.gmatch(line .. ",", "([^,;]+)[,;]") do
                    local name, value = string.match(token, "^%s*(.-)%s*=%s*([%-%d%.]+)%s*$")
                    if name then Take(name, value) elseif strtrim(token) ~= "" then skipped = skipped + 1 end
                end
            else
                local name, value = string.match(line, "^%s*(.-)%s*[,:\t]%s*([%-%d%.]+)%s*$")
                if name then Take(name, value) else skipped = skipped + 1 end
            end
        end
    end
    return rows, skipped
end

-- How SixtyUpgrades spells each stat in its CSV (Point Configuration > CSV). The first seven are confirmed from
-- the site; the rest follow the same style and may need a tweak if the site rejects one.
local SITE_NAMES = {
    ITEM_MOD_STRENGTH_SHORT = "strength", ITEM_MOD_AGILITY_SHORT = "agility", ITEM_MOD_STAMINA_SHORT = "stamina",
    ITEM_MOD_INTELLECT_SHORT = "intellect", ITEM_MOD_SPIRIT_SHORT = "spirit",
    ITEM_MOD_ATTACK_POWER_SHORT = "attackPower", ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_WEAPON_DPS = "dps", ITEM_MOD_ATTACK_SPEED = "speed", RESISTANCE0_NAME = "armor",
    ITEM_MOD_SPELL_POWER_SHORT = "spellPower", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_HASTE_RATING_SHORT = "haste",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
    ITEM_MOD_HEALTH_SHORT = "health", ITEM_MOD_MANA_SHORT = "mana", ITEM_MOD_HEALTH_REGEN_SHORT = "hp5",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rangedAttackPower", ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feralAttackPower",
}
local function ExportText()
    local lines = { "Stat,Value" }
    for _, row in ipairs(CysUpgrade.statRows or {}) do
        if row.key and row.key ~= "" and row.weight then
            local name = SITE_NAMES[row.key]
            if not name then
                for _, info in ipairs(STAT_REGISTRY) do
                    if info.key == row.key then name = NormName(info.name); break end
                end
            end
            lines[#lines + 1] = string.format("%s,%s", name or row.key, tostring(row.weight))
        end
    end
    return table.concat(lines, "\n")
end

CreateImportExportPopup = function(parent, callback)
    if CysUpgrade.iePopup then
        CysUpgrade.iePopup:ClearAllPoints()
        CysUpgrade.iePopup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return CysUpgrade.iePopup
    end
    local W = CysUI.W
    local T = W.T
    local f = CreateFrame("Frame", "CysUpgradeIEPopup", UIParent)
    CysUpgrade.iePopup = f
    f:SetSize(400, 290)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local title = W.Text(f, 13, T.accent, "CENTER")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Import / Export weights")
    local hint = W.Text(f, 11, T.desc)
    hint:SetPoint("TOPLEFT", 16, -38)
    hint:SetWidth(368)
    hint:SetJustifyV("TOP")
    hint:SetText("Copy this into SixtyUpgrades (Point Configuration > CSV). To bring weights in, paste the site's CSV, or a line like  Stamina=1, Intellect=0.8,  and press Import. Weights work exactly like the site's, so the same numbers give the same result. If the site rejects a stat name, delete that line.")

    local field = CreateFrame("Frame", nil, f)
    field:SetPoint("TOPLEFT", 16, -112)
    field:SetSize(368, 130)
    W.Texture(field, "BACKGROUND", T.field):SetAllPoints()
    W.Border(field, 1, T.line, "BORDER")
    local editBox = CreateFrame("EditBox", nil, field)
    editBox:SetPoint("TOPLEFT", 6, -6)
    editBox:SetPoint("BOTTOMRIGHT", -6, 6)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(STANDARD_TEXT_FONT, 11, "")
    editBox:SetTextColor(T.text[1], T.text[2], T.text[3])
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)

    local status = W.Text(f, 11, T.desc, "CENTER")
    status:SetPoint("BOTTOM", 0, 46)
    status:SetWidth(368)

    local importBtn = W.Button(f, 110, 24, "Import", true)
    importBtn:SetPoint("BOTTOMLEFT", 16, 14)
    importBtn:SetScript("OnClick", function()
        local rows, skipped = ParseWeights(editBox:GetText() or "")
        if #rows == 0 then
            status:SetText("Nothing could be read from that text.")
            status:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
            return
        end
        CysUpgrade.statRows = rows
        UpdateWeightsFromRows()
        if callback then callback() end
        print(string.format("|cFF00BFFF[CysUpgrade]|r Imported %d stat weights%s.", #rows,
            skipped > 0 and (" (" .. skipped .. " not recognised)") or ""))
        f:Hide()
    end)
    local closeBtn = W.Button(f, 110, 24, "Close")
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function()
        status:SetText("")
        editBox:SetText(ExportText())
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    tinsert(UISpecialFrames, "CysUpgradeIEPopup")
    f:Hide()
    return f
end
CreateUserGuidePopup = function(parent)
if CysUpgrade.guidePopup then
CysUpgrade.guidePopup:ClearAllPoints()
CysUpgrade.guidePopup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
return CysUpgrade.guidePopup
end
local f = CreateFrame("Frame", "CysUpgradeGuidePopup", UIParent)
CysUpgrade.guidePopup = f
f:SetSize(420, 360)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("FULLSCREEN_DIALOG")
f:SetFrameLevel(999)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetColorTexture(0.067, 0.067, 0.067, 1)
bg:SetAllPoints()
local function CreateBorder(p, thickness, color)
local e = {}
for i = 1, 4 do
e[i] = p:CreateTexture(nil, "BORDER")
e[i]:SetColorTexture(color[1], color[2], color[3], 1)
if color == CysUI.W.T.border then CysUI.W.TrackEdge(e[i]) end
end
e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(thickness)
e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(thickness)
e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(thickness)
e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(thickness)
return e
end
CreateBorder(f, 1, CysUI.W.T.border)
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", f, "TOP", 0, -16)
title:SetTextColor(1, 0.82, 0)
title:SetText("CysUpgrade - User Guide & Stat Weights")
local close = CreateFrame("Button", nil, f)
close:SetSize(24, 24)
close:SetPoint("TOPRIGHT", -6, -6)
local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
closeText:SetPoint("CENTER", 0, 0)
closeText:SetText("X")
closeText:SetTextColor(1, 1, 1)
close:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
close:SetScript("OnLeave", function() closeText:SetTextColor(1, 1, 1) end)
close:SetScript("OnClick", function() f:Hide() end)
local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(370, 240)
scrollFrame:SetPoint("TOP", title, "BOTTOM", 0, -10)
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(350, 260)
scrollFrame:SetScrollChild(content)
local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("TOPLEFT", 10, -10)
text:SetWidth(340)
text:SetJustifyH("LEFT")
text:SetText(
"|cFFFFD100How Equivalency Points (EP) Work:|r\n" ..
"CysUpgrade calculates an item's total worth by multiplying each stat value by its assigned weight and summing them up, identical to SixtyUpgrades.\n\n" ..
"|cFFFFD100Standard Stats:|r\n" ..
"• Formula: StatValue × Weight\n" ..
"• Example: 10 Stamina with a weight of 2.0 = 20 EP.\n\n" ..
"|cFFFFD100Weapon DPS:|r\n" ..
"• Formula: WeaponDPS × Weight\n" ..
"• Weights raw weapon damage output directly.\n\n" ..
"|cFFFFD100Weapon Speed:|r\n" ..
"• Formula: WeaponSpeed × Weight (the same as SixtyUpgrades).\n" ..
"• A NEGATIVE weight favors fast weapons, a POSITIVE weight favors slow ones. A weight of -5 means a weapon that is 1.0 faster is worth 5 EP.\n" ..
"• Early shaman tanking (no Stormstrike yet): use a negative weight like -5 so fast weapons (under 2.00) win. Later, once you have Stormstrike: switch it to a positive number, or make a second profile and bind it to your other spec."
)
content:SetHeight(text:GetStringHeight() + 24)
local closeBtn = CysUI.W.Button(f, 100, 24, "Got it", true)
closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
closeBtn:SetScript("OnClick", function() f:Hide() end)
f:Hide()
return f
end
local function SetupUpwardUpgradeIcon(btn)
if not btn.CysUpgradeIcon then
local bg = btn:CreateTexture(nil, "OVERLAY", nil, 1)
bg:SetSize(16, 16)
bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
bg:SetColorTexture(0, 0, 0, 0.8)
bg:Hide()
btn.CysUpgradeBg = bg
local icon = btn:CreateTexture(nil, "OVERLAY", nil, 2)
icon:SetSize(14, 14)
icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
icon:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
icon:SetTexCoord(0, 1, 1, 0)
icon:SetVertexColor(0, 1, 1)
icon:Hide()
btn.CysUpgradeIcon = icon
end
end
function _G.UpdateCysBagsUpgradeOverlays()
for bag = 0, 4 do
local numSlots = CC.GetContainerNumSlots(bag) or 0
for slot = 1, numSlots do
local btn = _G[string.format("CysBagsItem%d_%d", bag, slot)]
if btn then
SetupUpwardUpgradeIcon(btn)
local itemLink = CC.GetContainerItemLink(bag, slot)
local showUpgrade = false
if itemLink and IsItemValidForClass(itemLink) then
UpdateWeightsFromRows()
local itemScore = CysUpgrade:GetItemEP(itemLink, CysUpgrade.weights)
if itemScore > 0 then
local _, eqLink = GetTargetSlotAndEquipped(itemLink, CysUpgrade.weights)
local eqScore = eqLink and CysUpgrade:GetItemEP(eqLink, CysUpgrade.weights) or 0
if itemScore > eqScore + 0.05 then
showUpgrade = true
end
end
end
btn.CysUpgradeIcon:SetShown(showUpgrade)
if btn.CysUpgradeBg then btn.CysUpgradeBg:SetShown(showUpgrade) end
end
end
end
end
function _G.UpdateCysBankUpgradeOverlays()
for _, bag in ipairs({-1, 5, 6, 7, 8, 9, 10, 11}) do
local numSlots = CC.GetContainerNumSlots(bag) or 0
for slot = 1, numSlots do
local btn = _G[string.format("CysBankItem%d_%d", bag + 2, slot)]
if btn then
SetupUpwardUpgradeIcon(btn)
local itemLink = CC.GetContainerItemLink(bag, slot)
local showUpgrade = false
if itemLink and IsItemValidForClass(itemLink) then
UpdateWeightsFromRows()
local itemScore = CysUpgrade:GetItemEP(itemLink, CysUpgrade.weights)
if itemScore > 0 then
local _, eqLink = GetTargetSlotAndEquipped(itemLink, CysUpgrade.weights)
local eqScore = eqLink and CysUpgrade:GetItemEP(eqLink, CysUpgrade.weights) or 0
if itemScore > eqScore + 0.05 then
showUpgrade = true
end
end
end
btn.CysUpgradeIcon:SetShown(showUpgrade)
if btn.CysUpgradeBg then btn.CysUpgradeBg:SetShown(showUpgrade) end
end
end
end
end
local STAT_CATEGORIES = {
{ category = "ATTRIBUTES", stats = {
{ text = "Strength", key = "ITEM_MOD_STRENGTH_SHORT" },
{ text = "Agility", key = "ITEM_MOD_AGILITY_SHORT" },
{ text = "Stamina", key = "ITEM_MOD_STAMINA_SHORT" },
{ text = "Intellect", key = "ITEM_MOD_INTELLECT_SHORT" },
{ text = "Spirit", key = "ITEM_MOD_SPIRIT_SHORT" },
{ text = "Mana", key = "ITEM_MOD_MANA_SHORT" },
{ text = "Health", key = "ITEM_MOD_HEALTH_SHORT" },
{ text = "Health per 5 Sec.", key = "ITEM_MOD_HEALTH_REGEN_SHORT" },
}},
{ category = "SPELL", stats = {
{ text = "Spell Damage", key = "ITEM_MOD_SPELL_POWER_SHORT" },
{ text = "Healing", key = "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
{ text = "Spell Hit", key = "ITEM_MOD_SPELL_HIT_RATING_SHORT" },
{ text = "Spell Crit", key = "ITEM_MOD_SPELL_CRIT_RATING_SHORT" },
{ text = "Spell Penetration", key = "ITEM_MOD_SPELL_PENETRATION_SHORT" },
{ text = "Mana per 5 Sec.", key = "ITEM_MOD_POWER_REGEN0_SHORT" },
{ text = "Arcane Damage", key = "ITEM_MOD_SPELL_ARCANE_DAMAGE_SHORT" },
{ text = "Fire Damage", key = "ITEM_MOD_SPELL_FIRE_DAMAGE_SHORT" },
{ text = "Nature Damage", key = "ITEM_MOD_SPELL_NATURE_DAMAGE_SHORT" },
{ text = "Frost Damage", key = "ITEM_MOD_SPELL_FROST_DAMAGE_SHORT" },
{ text = "Shadow Damage", key = "ITEM_MOD_SPELL_SHADOW_DAMAGE_SHORT" },
{ text = "Holy Damage", key = "ITEM_MOD_SPELL_HOLY_DAMAGE_SHORT" },
}},
{ category = "MELEE", stats = {
{ text = "Attack Power", key = "ITEM_MOD_ATTACK_POWER_SHORT" },
{ text = "Feral Attack Power", key = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
{ text = "Weapon DPS", key = "ITEM_MOD_WEAPON_DPS" },
{ text = "Weapon Speed", key = "ITEM_MOD_ATTACK_SPEED" },
{ text = "Hit Chance", key = "ITEM_MOD_HIT_RATING_SHORT" },
{ text = "Crit Chance", key = "ITEM_MOD_CRIT_RATING_SHORT" },
{ text = "Haste", key = "ITEM_MOD_HASTE_RATING_SHORT" },
}},
{ category = "RANGED", stats = {
{ text = "Ranged Attack Power", key = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
{ text = "Ranged Weapon DPS", key = "ITEM_MOD_RANGED_DPS" },
{ text = "Ranged Weapon Speed", key = "ITEM_MOD_RANGED_ATTACK_SPEED" },
{ text = "Ranged Hit Chance", key = "ITEM_MOD_SPELL_HIT_RATING_SHORT" },
}},
{ category = "DEFENSE", stats = {
{ text = "Armor", key = "RESISTANCE0_NAME" },
{ text = "Defense", key = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
{ text = "Dodge Chance", key = "ITEM_MOD_DODGE_RATING_SHORT" },
{ text = "Parry Chance", key = "ITEM_MOD_PARRY_RATING_SHORT" },
{ text = "Block Chance", key = "ITEM_MOD_BLOCK_RATING_SHORT" },
{ text = "Block Value", key = "ITEM_MOD_BLOCK_VALUE_SHORT" },
}},
{ category = "RESISTANCES", stats = {
{ text = "Arcane Resistance", key = "RESISTANCE6_NAME" },
{ text = "Fire Resistance", key = "RESISTANCE2_NAME" },
{ text = "Nature Resistance", key = "RESISTANCE3_NAME" },
{ text = "Frost Resistance", key = "RESISTANCE4_NAME" },
{ text = "Shadow Resistance", key = "RESISTANCE5_NAME" },
}},
}

-- A small themed pop-up list (replaces the Blizzard drop-down): entries are
-- { text, func } or { text, children = {...} }; clicking outside closes it.
local menu
local function HideMenu() if menu then menu:Hide() end end
local function ShowMenu(anchor, entries)
    local W = CysUI.W
    local T = W.T
    if not menu then
        menu = CreateFrame("Frame", "CysUpgradeMenu", UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:EnableMouse(true)
        menu:SetClampedToScreen(true)
        W.Texture(menu, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.98 }):SetAllPoints()
        W.Border(menu, 1, T.border, "BORDER")
        menu.items = {}
        local was = false
        menu:SetScript("OnUpdate", function(self)
            local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            if down and not was and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then self:Hide() end
            was = down
        end)
        menu:Hide()
    end
    menu.anchor = anchor
    local ROW, WIDTH = 19, 200
    for _, b in ipairs(menu.items) do b:Hide() end
    for i, e in ipairs(entries) do
        local b = menu.items[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(ROW)
            b.hl = W.Texture(b, "BACKGROUND", T.selected)
            b.hl:SetAllPoints()
            b.hl:Hide()
            b.text = W.Text(b, 11, T.text)
            b.text:SetPoint("LEFT", 8, 0)
            b.arrow = W.Text(b, 11, T.dim, "RIGHT")
            b.arrow:SetPoint("RIGHT", -8, 0)
            b:SetScript("OnEnter", function(s) s.hl:Show() end)
            b:SetScript("OnLeave", function(s) s.hl:Hide() end)
            menu.items[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1 - (i - 1) * ROW)
        b:SetWidth(WIDTH - 2)
        b.text:SetText(e.text)
        local c = e.checked and T.accent or T.text
        b.text:SetTextColor(c[1], c[2], c[3])
        b.arrow:SetText(e.children and ">" or "")
        b:SetScript("OnClick", function()
            if e.children then
                local list = { { text = "< Back", func = function() ShowMenu(anchor, entries) end, keepOpen = true } }
                for _, child in ipairs(e.children) do list[#list + 1] = child end
                ShowMenu(anchor, list)
            else
                if not e.keepOpen then HideMenu() end
                if e.func then e.func() end
            end
        end)
        b:Show()
    end
    menu:SetSize(WIDTH, #entries * ROW + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function CharKey() return (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown") end
local function CharDB()
    CysUIDB.upgrade = CysUIDB.upgrade or {}
    CysUIDB.upgrade.charProfiles = CysUIDB.upgrade.charProfiles or {}
    local key = CharKey()
    local cd = CysUIDB.upgrade.charProfiles[key] or { profiles = {}, activeProfile = "", specBindings = {} }
    CysUIDB.upgrade.charProfiles[key] = cd
    cd.profiles = cd.profiles or {}
    cd.specBindings = cd.specBindings or {}
    return cd
end
local function RefreshOverlays()
    if _G.UpdateCysBagsUpgradeOverlays then _G.UpdateCysBagsUpgradeOverlays() end
    if _G.UpdateCysBankUpgradeOverlays then _G.UpdateCysBankUpgradeOverlays() end
end

local function BuildUpgradeSettingsPage(page)
    local W = CysUI.W
    local T = W.T
    local width = 484 -- the page scrollbar sits at the right edge, so stay clear of it

    -- themed text box
    local function Input(parent, w, h)
        local eb = CreateFrame("EditBox", nil, parent)
        eb:SetSize(w, h)
        eb:SetAutoFocus(false)
        eb:SetFont(STANDARD_TEXT_FONT, 11, "")
        eb:SetTextColor(T.text[1], T.text[2], T.text[3])
        eb:SetTextInsets(6, 6, 0, 0)
        W.Texture(eb, "BACKGROUND", T.field):SetAllPoints()
        eb.edges = W.Border(eb, 1, T.line, "BORDER")
        eb:SetScript("OnEditFocusGained", function(s) W.SetBorder(s.edges, T.accent) end)
        eb:SetScript("OnEditFocusLost", function(s) W.SetBorder(s.edges, T.line) end)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        return eb
    end

    W.Header(page, "Stat weights", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 11, T.desc)
    intro:SetPoint("TOPLEFT", 4, -32)
    intro:SetWidth(width - 90)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("An item's score is each stat times its weight, added up. Bag items that outscore what you wear get an upgrade arrow, and tooltips list exactly what you gain and lose.")
    local guideBtn = W.Button(page, 76, 22, "Guide")
    guideBtn:SetPoint("TOPLEFT", width - 76, -32)
    guideBtn:SetScript("OnClick", function()
        local popup = CreateUserGuidePopup(page)
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)

    -- profile row
    local nameLabel = W.Text(page, 12, T.text)
    nameLabel:SetPoint("TOPLEFT", 4, -100)
    nameLabel:SetText("Profile")
    local nameBox = Input(page, 150, 22)
    nameBox:SetPoint("TOPLEFT", 60, -96)
    nameBox:SetText(CysUpgrade.activeProfileName or "")
    local switchBtn = W.Button(page, 100, 22, "Switch profile")
    switchBtn:SetPoint("TOPLEFT", 220, -96)
    local delProfileBtn = W.Button(page, 100, 22, "Delete profile")
    delProfileBtn:SetPoint("TOPLEFT", 328, -96)
    delProfileBtn.label:SetTextColor(T.danger[1], T.danger[2], T.danger[3])

    -- which talent spec uses this profile
    local function Binding(spec)
        local n = strtrim(nameBox:GetText() or "")
        return n ~= "" and CharDB().specBindings[spec] == n
    end
    local function SetBinding(spec, on)
        local n = strtrim(nameBox:GetText() or "")
        if n == "" then print("|cFFFF0000[CysUpgrade]|r Give the profile a name first.") return end
        local cd = CharDB()
        if on then cd.specBindings[spec] = n elseif cd.specBindings[spec] == n then cd.specBindings[spec] = nil end
    end
    local bind1 = W.Checkbox(page, "Use for talent spec 1", function() return Binding(1) end, function(on) SetBinding(1, on) end)
    bind1:SetPoint("TOPLEFT", 4, -130)
    local bind2 = W.Checkbox(page, "Use for talent spec 2", function() return Binding(2) end, function(on) SetBinding(2, on) end)
    bind2:SetPoint("TOPLEFT", 210, -130)
    nameBox:SetScript("OnTextChanged", function() bind1:Refresh(); bind2:Refresh() end)

    W.Header(page, "Weights", width):SetPoint("TOPLEFT", 0, -166)
    local colStat = W.Text(page, 11, T.accent)
    colStat:SetPoint("TOPLEFT", 4, -194)
    colStat:SetText("Stat")
    local colWeight = W.Text(page, 11, T.accent)
    colWeight:SetPoint("TOPLEFT", 214, -194)
    colWeight:SetText("Weight")

    local ROW_H, ROWS_TOP = 28, 212
    local rowsHolder = CreateFrame("Frame", nil, page)
    rowsHolder:SetPoint("TOPLEFT", 0, -ROWS_TOP)
    rowsHolder:SetSize(width, 10)
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT", rowsHolder, "BOTTOMLEFT", 0, -12)
    bar:SetSize(width, 24)

    local rowFrames = {}
    local function StatName(key)
        if key and key ~= "" then
            for _, info in ipairs(STAT_REGISTRY) do
                if info.key == key then return info.name end
            end
            return key
        end
        return "Select a stat"
    end
    local function StatEntries(onPick)
        local list = {}
        for _, cat in ipairs(STAT_CATEGORIES) do
            local kids = {}
            for _, s in ipairs(cat.stats) do
                kids[#kids + 1] = { text = s.text, func = function() onPick(s) end }
            end
            list[#list + 1] = { text = string.sub(cat.category, 1, 1) .. string.lower(string.sub(cat.category, 2)), children = kids }
        end
        return list
    end

    local RefreshRows
    local function MakeRow()
        local row = CreateFrame("Frame", nil, rowsHolder)
        row:SetSize(width, ROW_H)
        local function Data() return CysUpgrade.statRows[row.index] end
        row.pick = W.Button(row, 200, 22, "Select a stat")
        row.pick:SetPoint("TOPLEFT", 4, -3)
        row.pick:SetScript("OnClick", function(self)
            ShowMenu(self, StatEntries(function(stat)
                local d = Data()
                if not d then return end
                d.key = stat.key
                row.pick:SetLabel(stat.text)
                UpdateWeightsFromRows()
                RefreshOverlays()
            end))
        end)
        row.input = Input(row, 72, 22)
        row.input:SetPoint("TOPLEFT", 214, -3)
        row.input:SetScript("OnTextChanged", function(self, user)
            local d = Data()
            if user and d then
                d.weight = tonumber(self:GetText()) or 0
                UpdateWeightsFromRows()
                RefreshOverlays()
            end
        end)
        row.up = W.Button(row, 24, 22, "^")
        row.up:SetPoint("TOPLEFT", 296, -3)
        row.up:SetScript("OnClick", function()
            local rows, i = CysUpgrade.statRows, row.index
            if i > 1 then rows[i], rows[i - 1] = rows[i - 1], rows[i]; UpdateWeightsFromRows(); RefreshRows() end
        end)
        row.down = W.Button(row, 24, 22, "v")
        row.down:SetPoint("TOPLEFT", 324, -3)
        row.down:SetScript("OnClick", function()
            local rows, i = CysUpgrade.statRows, row.index
            if i < #rows then rows[i], rows[i + 1] = rows[i + 1], rows[i]; UpdateWeightsFromRows(); RefreshRows() end
        end)
        row.del = W.Button(row, 24, 22, "x")
        row.del.label:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
        row.del:SetPoint("TOPLEFT", 356, -3)
        row.del:SetScript("OnClick", function()
            table.remove(CysUpgrade.statRows, row.index)
            if #CysUpgrade.statRows == 0 then table.insert(CysUpgrade.statRows, { key = "", weight = 0 }) end
            UpdateWeightsFromRows()
            RefreshRows()
            RefreshOverlays()
        end)
        return row
    end

    RefreshRows = function()
        local rows = CysUpgrade.statRows
        for i, data in ipairs(rows) do
            local row = rowFrames[i]
            if not row then row = MakeRow(); rowFrames[i] = row end
            row.index = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rowsHolder, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row.pick:SetLabel(StatName(data.key))
            row.input:SetText(tostring(data.weight or 0))
            row.up:SetActive(i > 1)
            row.down:SetActive(i < #rows)
            row:Show()
        end
        for i = #rows + 1, #rowFrames do rowFrames[i]:Hide() end
        rowsHolder:SetHeight(math.max(#rows * ROW_H, 1))
        page.contentHeight = ROWS_TOP + #rows * ROW_H + 12 + 24 + 24
        local content = page:GetParent()
        if content and content.SetHeight then content:SetHeight(math.max(440, page.contentHeight)) end
    end

    local function LoadProfile(name, data)
        CysUpgrade.activeProfileName = name
        CharDB().activeProfile = name
        CysUpgrade.statRows = data.statRows or { { key = "", weight = 0 } }
        nameBox:SetText(name)
        UpdateWeightsFromRows()
        RefreshRows()
        RefreshOverlays()
    end

    switchBtn:SetScript("OnClick", function(self)
        local names = {}
        for n in pairs(CharDB().profiles) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then print("|cFF00BFFF[CysUpgrade]|r No saved profiles yet.") return end
        local entries = {}
        for _, n in ipairs(names) do
            entries[#entries + 1] = { text = n, checked = (n == CysUpgrade.activeProfileName),
                func = function() LoadProfile(n, CharDB().profiles[n]) end }
        end
        ShowMenu(self, entries)
    end)

    delProfileBtn:SetScript("OnClick", function()
        local cd = CharDB()
        local cur = CysUpgrade.activeProfileName
        if cd.profiles[cur] then cd.profiles[cur] = nil end
        for n, b in pairs(cd.specBindings) do if b == cur then cd.specBindings[n] = nil end end
        CysUpgrade.activeProfileName = ""
        cd.activeProfile = ""
        local fallbackName, fallbackData = next(cd.profiles)
        if fallbackName then
            LoadProfile(fallbackName, fallbackData)
        else
            CysUpgrade.statRows = { { key = "", weight = 0 } }
            nameBox:SetText("")
            UpdateWeightsFromRows()
            RefreshRows()
            RefreshOverlays()
        end
    end)

    local addBtn = W.Button(bar, 96, 24, "+ Add stat")
    addBtn:SetPoint("TOPLEFT", 4, 0)
    addBtn:SetScript("OnClick", function()
        table.insert(CysUpgrade.statRows, { key = "", weight = 0 })
        RefreshRows()
    end)
    local newProfBtn = W.Button(bar, 104, 24, "+ New profile")
    newProfBtn:SetPoint("TOPLEFT", 104, 0)
    newProfBtn:SetScript("OnClick", function()
        CysUpgrade.statRows = { { key = "", weight = 0 } }
        CysUpgrade.activeProfileName = ""
        nameBox:SetText("")
        RefreshRows()
    end)
    local ieBtn = W.Button(bar, 112, 24, "Import / Export")
    ieBtn:SetPoint("TOPLEFT", 216, 0)
    ieBtn:SetScript("OnClick", function()
        local popup = CreateImportExportPopup(page, function() RefreshRows(); RefreshOverlays() end)
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    local saveBtn = W.Button(bar, 150, 24, "Save and apply", true)
    saveBtn:SetPoint("TOPLEFT", 340, 0)
    saveBtn:SetScript("OnClick", function()
        local profileName = strtrim(nameBox:GetText() or "")
        if profileName == "" then print("|cFFFF0000[CysUpgrade]|r Please enter a profile name!") return end
        -- a saved profile owns its own copy of the rows, so renaming never changes another profile
        local copy = {}
        for i, r in ipairs(CysUpgrade.statRows) do copy[i] = { key = r.key, weight = tonumber(r.weight) or 0 } end
        local cd = CharDB()
        cd.activeProfile = profileName
        cd.profiles[profileName] = { statRows = copy }
        CysUpgrade.activeProfileName = profileName
        CysUpgrade.statRows = copy
        UpdateWeightsFromRows()
        RefreshRows()
        bind1:Refresh(); bind2:Refresh()
        RefreshOverlays()
        print(string.format("|cFF00BFFF[CysUpgrade]|r Profile '%s' saved and applied.", profileName))
    end)

    RefreshRows()
    page.onShow = function()
        nameBox:SetText(CysUpgrade.activeProfileName or "")
        RefreshRows()
    end
end
if CysUI.RegisterPage then CysUI:RegisterPage("Upgrade", BuildUpgradeSettingsPage) end
_G["SLASH_CYSUP1"] = "/cysup"
_G["SLASH_CYSUP2"] = "/cysupgrade"
_G["SlashCmdList"]["CYSUP"] = function()
if CysUI and CysUI.OpenConfig then CysUI:OpenConfig("Upgrade") end
end
-- Cys's UI runs this file after its settings load, so load the saved profiles right away
CysUpgrade:GetScript("OnEvent")(CysUpgrade, "ADDON_LOADED", ADDON_NAME)
end,
})
