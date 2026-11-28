--------------------------------------------------------------------------------
-- Cys's UI - Unit Frames
--
-- Our own flat frames for player, target, target of target, pet and party, built on the
-- game's secure unit-button template so clicking, targeting and showing / hiding all keep
-- working in combat. Blizzard's versions are tucked away at login (before combat can start).
--
--   * class / reaction colored health bar, power bar, level + name, health text
--   * target: buffs and debuffs with tooltips, combo points
--   * party: shown for a party, hidden in a raid (raid frames are the Raid Frames module)
--   * every frame moves / resizes / scales in layout mode (/cui layout)
--
-- Frames can only be moved or resized out of combat; layout mode refuses to open in combat.
-- If anything misbehaves: untick Unit Frames under /cui > Modules and reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min
local Secret, Guard = CysUICompat.Secret, CysUICompat.Guard -- WoW Forever locked values (no-ops on Era)

local UF = {}
CUI.UnitFrames = UF
UF.frames = {}

local FLAT = "Interface\\Buttons\\WHITE8X8"
local function DB() return CysUIDB.unitframes end

local hidden = CreateFrame("Frame")
hidden:Hide()

--------------------------------------------------------------------------------
-- Colors and text
--------------------------------------------------------------------------------
local FALLBACK_POWER = { [0] = { 0.3, 0.5, 1 }, [1] = { 0.9, 0.2, 0.2 }, [2] = { 1, 0.5, 0.25 }, [3] = { 1, 0.9, 0.2 } }

local function PowerColor(unit)
    local t = UnitPowerType(unit)
    local c = PowerBarColor and PowerBarColor[t]
    if c and c.r then return c.r, c.g, c.b end
    local d = FALLBACK_POWER[t] or { 0.6, 0.6, 0.6 }
    return d[1], d[2], d[3]
end

local Flag = CysUICompat.Flag -- a locked true/false counts as false (WoW Forever)

local function UnitColor(unit)
    if UnitIsDeadOrGhost and Flag(UnitIsDeadOrGhost(unit)) then return 0.5, 0.5, 0.5 end -- dead beats class color
    if Flag(UnitIsPlayer(unit)) then
        local _, class = UnitClass(unit)
        class = CysUICompat.Plain(class)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    if UnitIsTapDenied and Flag(UnitIsTapDenied(unit)) and not Flag(UnitPlayerControlled(unit)) then return 0.5, 0.5, 0.5 end
    local reaction = UnitReaction(unit, "player")
    if Secret(reaction) then
        -- WoW Forever: the reaction is locked for this unit; fall back to attackable / friendly
        if UnitCanAttack and Flag(UnitCanAttack("player", unit)) then return 0.9, 0.2, 0.2 end
        if UnitIsFriend and Flag(UnitIsFriend("player", unit)) then return 0.3, 0.85, 0.4 end
        return 1, 0.82, 0
    end
    if not reaction then return 0.8, 0.8, 0.8 end
    if reaction <= 2 then return 0.9, 0.2, 0.2 end
    if reaction <= 4 then return 1, 0.82, 0 end
    return 0.3, 0.85, 0.4
end

local function Short(n)
    if n >= 1000000 then return format("%.1fm", n / 1000000) end
    if n >= 10000 then return format("%.1fk", n / 1000) end
    return tostring(n)
end

local function HealthString(cur, mx)
    local mode = DB().healthText
    -- enemies report health as a percentage out of 100 in Classic
    if mx <= 100 then return format("%d%%", cur) end
    if mode == "value" then return Short(cur) end
    if mode == "percent" then return format("%d%%", mx > 0 and floor(cur / mx * 100 + 0.5) or 0) end
    return format("%s  |cFFFFD100%d%%|r", Short(cur), mx > 0 and floor(cur / mx * 100 + 0.5) or 0)
end

--------------------------------------------------------------------------------
-- Aura icons (target)
--------------------------------------------------------------------------------
local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = CysUICompat.AuraData(unit, index, filter)
        if a then return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime end
        return
    end
    local name, icon, count, debuffType, duration, expirationTime = UnitAura(unit, index, filter)
    return name, icon, count, debuffType, duration, expirationTime
end

local AURA_SIZE, AURA_COLUMNS, AURA_ROWS = 24, 8, 2 -- size follows the "icon size" setting (UpdateAuras)

local function MakeAura(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(AURA_SIZE, AURA_SIZE)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetPoint("TOPLEFT", 1, -1)
    a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    a.edges = W.Border(a, 1, T.line, "OVERLAY")
    a.count = a:CreateFontString(nil, "OVERLAY")
    a.count:SetFont(CysUICompat.Font(), CysUICompat.FontSize(10), "OUTLINE")
    a.count:SetPoint("BOTTOMRIGHT", 1, 0)
    a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cd:SetAllPoints(a.icon)
    CysUICompat.SmallCooldownText(a.cd, AURA_SIZE)
    if a.cd.SetDrawEdge then a.cd:SetDrawEdge(false) end
    a:EnableMouse(true)
    a:SetScript("OnEnter", function(self)
        if self.auraInstanceID then return CysUICompat.AuraTooltip(self, self.unit, self.auraInstanceID, self.filter) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        pcall(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.index, self.filter)
        GameTooltip:Show()
    end)
    a:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return a
end

local function UpdateAuras(f)
    if not f.auras then return end
    AURA_SIZE = DB().auraSize or 24
    local unit = f.unit
    local pools = f.auras
    local rowShift = 0
    -- WoW Forever: addons can't read the target's auras in combat, so the game draws them into our icons
    -- through an aura container (debuffs on the first row, buffs below). Era keeps the code further down.
    if CysUICompat.isForever and unit ~= "player" then
        if f.cysAuraBox == nil then
            f.cysAuraBox = CysUICompat.AuraContainer(f, unit, {
                -- above the frame: the target cast bar sits right under it
                point = { "BOTTOMLEFT", f, "TOPLEFT", 0, 4 }, anchor = "BOTTOMLEFT", growV = "UP",
                size = AURA_SIZE, gap = 2, lineWidth = AURA_COLUMNS * (AURA_SIZE + 2),
                groups = { { key = "debuffs", filter = "HARMFUL", max = AURA_COLUMNS * AURA_ROWS },
                           { key = "buffs", filter = "HELPFUL", max = AURA_COLUMNS * AURA_ROWS } },
            }) or false
        end
        if f.cysAuraBox then
            for _, pool in pairs(pools) do for i = 1, #pool do pool[i]:Hide() end end
            return
        end
    end
    for _, kind in ipairs({ "HARMFUL", "HELPFUL" }) do
        local pool = pools[kind]
        local shown = 0
        -- WoW Forever: other units' auras are locked in combat; draw them from aura instance IDs instead
        local list = (unit ~= "player" and UnitExists(unit)) and CysUICompat.AuraIcons(unit, kind, AURA_COLUMNS * AURA_ROWS)
        if list then
            for _, e in ipairs(list) do
                if shown >= AURA_COLUMNS * AURA_ROWS then break end
                shown = shown + 1
                local a = pool[shown]
                if not a then a = MakeAura(f); pool[shown] = a end
                a.unit, a.index, a.filter = unit, nil, kind
                CysUICompat.ShowAuraIcon(a, e)
                local color = (kind == "HARMFUL" and e.dispelName and DebuffTypeColor and DebuffTypeColor[e.dispelName])
                if color or kind ~= "HARMFUL" then
                    color = color or { r = T.line[1], g = T.line[2], b = T.line[3] }
                    W.SetBorder(a.edges, { color.r, color.g, color.b })
                else
                    -- locked: the game colors the border by debuff type itself
                    CysUICompat.AuraBorder(a.edges, e, { 0.8, 0.2, 0.2 })
                end
                local col, row = (shown - 1) % AURA_COLUMNS, floor((shown - 1) / AURA_COLUMNS)
                a:ClearAllPoints()
                if f.unit == "targettarget" then
                    a:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * (AURA_SIZE + 1), -(2 + (rowShift + row) * (AURA_SIZE + 1)))
                else
                    a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * (AURA_SIZE + 2), 4 + (rowShift + row) * (AURA_SIZE + 2))
                end
                a:Show()
            end
        elseif UnitExists(unit) then
            for i = 1, 40 do
                if shown >= AURA_COLUMNS * AURA_ROWS then break end
                local name, icon, count, debuffType, duration, expiration = GetAura(unit, i, kind)
                if not name then break end
                shown = shown + 1
                local a = pool[shown]
                if not a then a = MakeAura(f); pool[shown] = a end
                a:SetSize(AURA_SIZE, AURA_SIZE)
                a.unit, a.index, a.filter, a.auraInstanceID = unit, i, kind, nil
                a.icon:SetTexture(icon)
                a.count:SetText((count and count > 1) and count or "")
                if duration and duration > 0 and expiration then
                    a.cd:SetCooldown(expiration - duration, duration)
                    a.cd:Show()
                else
                    a.cd:Hide()
                end
                local color = (kind == "HARMFUL" and debuffType and DebuffTypeColor and DebuffTypeColor[debuffType])
                    or (kind == "HARMFUL" and { r = 0.8, g = 0.2, b = 0.2 }) or { r = T.line[1], g = T.line[2], b = T.line[3] }
                W.SetBorder(a.edges, { color.r, color.g, color.b })
                local col, row = (shown - 1) % AURA_COLUMNS, floor((shown - 1) / AURA_COLUMNS)
                a:ClearAllPoints()
                if f.unit == "targettarget" then
                    a:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * (AURA_SIZE + 1), -(2 + (rowShift + row) * (AURA_SIZE + 1)))
                else
                    a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * (AURA_SIZE + 2), 4 + (rowShift + row) * (AURA_SIZE + 2))
                end
                a:Show()
            end
        end
        for i = shown + 1, #pool do pool[i]:Hide() end
        rowShift = rowShift + max(1, math.ceil(shown / AURA_COLUMNS))
    end
end

--------------------------------------------------------------------------------
-- Combo points (target)
--------------------------------------------------------------------------------
local function ComboPoints()
    if GetComboPoints then return GetComboPoints("player", "target") or 0 end
    return UnitPower("player", 4) or 0
end

local function UpdateCombo(f)
    if not f.pips then return end
    local n = UnitExists(f.unit) and ComboPoints() or 0
    for i, pip in ipairs(f.pips) do
        pip:SetShown(n > 0)
        local on = i <= n
        pip.tex:SetColorTexture(on and T.accent[1] or T.line[1], on and T.accent[2] or T.line[2], on and T.accent[3] or T.line[3], 1)
    end
end

--------------------------------------------------------------------------------
-- Updating a frame
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Heal estimate. Classic Era has no incoming-heal data from the game (UnitGetIncomingHeals gives nothing),
-- so the heal being cast is estimated from the spell's own description ("heals for 143 to 169" -> the middle).
-- Only your own cast is covered. Shared with the raid frames through CysUI.HealEstimate.
--------------------------------------------------------------------------------
CysUI.HealEstimateWatchers = CysUI.HealEstimateWatchers or {}
local healEst, healTarget
local function EstimateFromSpell(spellID)
    -- WoW Forever gives real incoming heals (drawn by CysUICompat.ForeverHealBar); its bonus healing is locked
    if CysUICompat.isForever then return nil end
    local getDesc = GetSpellDescription or (C_Spell and C_Spell.GetSpellDescription)
    if not (getDesc and spellID) then return nil end
    local ok, desc = pcall(getDesc, spellID)
    if not ok or type(desc) ~= "string" then return nil end
    desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", "")
    if not desc:lower():find("heal") then return nil end
    local base
    local lo, hi = desc:match("(%d+) to (%d+)")
    if lo and hi then base = (tonumber(lo) + tonumber(hi)) / 2 end
    if not base then
        local one = desc:match("(%d+)")
        base = one and tonumber(one) or nil
    end
    if not base then return nil end
    -- bonus healing (+healing gear): the usual Classic rule of thumb, cast time / 3.5 of the bonus, trimmed for
    -- low-level spells and for ranks well below your level. An estimate; with no +healing it adds nothing.
    local bonus = GetSpellBonusHealing and GetSpellBonusHealing() or 0
    if bonus > 0 then
        local castMs = select(4, GetSpellInfo(spellID))
        local coeff = math.min(1, math.max(1.5, (castMs or 3500) / 1000) / 3.5)
        local learned = GetSpellLevelLearned and GetSpellLevelLearned(spellID) or 0
        if learned > 0 then
            if learned < 20 then coeff = coeff * (1 - (20 - learned) * 0.0375) end
            coeff = coeff * math.min(1, (learned + 6) / math.max(UnitLevel("player"), 1))
        end
        base = base + bonus * coeff
    end
    return base
end
function CysUI.HealEstimate(unit)
    if not healEst or not unit then return 0 end
    if healTarget and healTarget ~= "" then
        if UnitName(unit) == healTarget then return healEst end
        return 0
    end
    return UnitIsUnit(unit, "player") and healEst or 0
end
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
                         "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        pcall(ev.RegisterUnitEvent, ev, e, "player")
    end
    ev:SetScript("OnEvent", function(_, event, _, target, _, spellID)
        if event == "UNIT_SPELLCAST_SENT" then
            healEst, healTarget = EstimateFromSpell(spellID), target
            if healEst and (not target or target == "") and UnitExists("target") and UnitIsFriend("player", "target") then
                healTarget = UnitName("target")
            end
        else
            -- SUCCEEDED also fires for instants; either way nothing is being cast any more
            healEst, healTarget = nil, nil
        end
        for _, fn in ipairs(CysUI.HealEstimateWatchers) do pcall(fn) end
    end)
end

local function UpdateHealth(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    if Secret(cur) or Secret(mx) then
        -- WoW Forever: this unit's health is locked. The bar can still show it; the math and text can't run.
        pcall(f.health.SetMinMaxValues, f.health, 0, mx)
        pcall(f.health.SetValue, f.health, cur)
        if f.healTex then
            f.healTex:Hide(); f.overhealTex:Hide()
            if CysUICompat.isForever then CysUICompat.ForeverHealBar(f, f.health, unit) end
        end
        -- the text is made by the game instead (Compat.LockedUnitText)
        local dead = CysUICompat.Plain(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
        local online = CysUICompat.Plain(UnitIsConnected and UnitIsConnected(unit))
        if dead then
            f.healthText:SetText("|cFF999999Dead|r")
        elseif online == false then
            f.healthText:SetText("|cFF999999Offline|r")
        elseif f.noHealthText then
            f.healthText:SetText("")
        else
            CysUICompat.LockedUnitText(f.healthText, unit, "health", DB().healthText or "both")
        end
        return
    end
    f.health:SetMinMaxValues(0, max(mx, 1))
    f.health:SetValue(cur)

    -- Incoming heals: a segment that starts where the health fill ends and only covers missing health;
    -- anything beyond max health shows as a small sliver past the frame's edge.
    if f.healTex and CysUICompat.isForever then
        -- WoW Forever: the incoming-heal amount is locked; draw it with a status bar instead (see Compat)
        f.healTex:Hide(); f.overhealTex:Hide()
        CysUICompat.ForeverHealBar(f, f.health, unit)
    elseif f.healTex then
        local incoming = (UnitGetIncomingHeals and UnitGetIncomingHeals(unit)) or 0
        if incoming <= 0 then incoming = CysUI.HealEstimate(unit) end
        local width = f.health:GetWidth()
        if incoming > 0 and mx > 0 and not UnitIsDeadOrGhost(unit) then
            local fit = min(incoming, max(mx - cur, 0))
            if fit > 0 then
                f.healTex:SetWidth(max(1, width * fit / mx))
                f.healTex:Show()
            else
                f.healTex:Hide()
            end
            local over = incoming - fit
            if over > 0 then
                -- the wasted part reaches out past the frame, as long as it is big (up to 60% of the frame's width);
                -- teal when it is small, yellow when it is a lot, red when most of the heal is wasted
                local ratio = over / incoming
                f.overhealTex:SetWidth(max(2, min(width * 0.6, width * over / mx)))
                if ratio > 0.6 then f.overhealTex:SetVertexColor(1.0, 0.2, 0.2, 0.85)
                elseif ratio > 0.3 then f.overhealTex:SetVertexColor(1.0, 0.8, 0.1, 0.85)
                else f.overhealTex:SetVertexColor(0.0, 0.9, 0.8, 0.75) end
                f.overhealTex:Show()
            else
                f.overhealTex:Hide()
            end
        else
            f.healTex:Hide()
            f.overhealTex:Hide()
        end
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        f.healthText:SetText("|cFF999999Dead|r")
    elseif UnitIsConnected and not UnitIsConnected(unit) then
        f.healthText:SetText("|cFF999999Offline|r")
    else
        f.healthText:SetText(f.noHealthText and "" or HealthString(cur, mx))
    end
end

-- the mana / rage / energy the spell you're casting will cost (0 when nothing is being cast)
local function CastCostNow(unit)
    local cost = 0
    if unit == "player" and UnitCastingInfo then
        local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitCastingInfo, "player")
        if ok and name and not Secret(name) then
            if not spellID and GetSpellInfo then
                local _, _, _, _, _, _, id = GetSpellInfo(name)
                spellID = id
            end
            if spellID and GetSpellPowerCost then
                local okc, costs = pcall(GetSpellPowerCost, spellID)
                if okc and type(costs) == "table" then
                    local pt = UnitPowerType(unit)
                    for _, c in ipairs(costs) do
                        local cc = CysUICompat.Plain(c.cost)
                        if c.type == pt and cc and cc > 0 then cost = cc break end
                    end
                end
            end
        end
    end
    return cost
end

-- Party: only mana matters to a healer, so a rage / energy bar is folded away and the health bar takes its room
-- (Unit Frames > Party). Only the bar's height changes, so it is safe in combat (druid forms switch it mid-fight).
local function PartyPowerShown(f, ptype)
    local show = ptype == nil or ptype == 0 or DB().partyManaOnly == false
    if f.cysPowerShown ~= show then
        f.cysPowerShown = show
        f.power:SetHeight(show and (f.cysPowerH or 7) or 0.001)
        f.power:SetShown(show)
    end
    return show
end

local function UpdatePower(f)
    if not f.power or f.powerHidden then return end
    local unit = f.unit
    if not UnitExists(unit) then return end
    if f.isParty and not PartyPowerShown(f, CysUICompat.Plain(UnitPowerType(unit))) then return end
    local mx = UnitPowerMax(unit)
    local r, g, b = PowerColor(unit)
    UF.Paint(f.power, f.powerBg, r, g, b, UF.HealthStyle() == "gradient" and "gradient" or "bright")
    local pcur = UnitPower(unit)
    if Secret(mx) or Secret(pcur) then
        -- WoW Forever: this unit's power is locked. The bar can still show it; the math and text can't run.
        pcall(f.power.SetMinMaxValues, f.power, 0, mx)
        pcall(f.power.SetValue, f.power, pcur)
        if f.powerText then
            local mode = DB().manaText or "current"
            if UnitPowerType(unit) == 1 and (mode == "percent" or mode == "valuepct") then mode = "current" end -- rage: no "%"
            if mode == "off" then
                f.powerText:SetText("")
            else
                CysUICompat.LockedUnitText(f.powerText, unit, "power", mode == "both" and "max" or mode)
            end
        end
        if f.costTex then
            f.costTex:Hide()
            CysUICompat.LockedCostBar(f, CastCostNow(unit))
        end
        return
    end
    f.power:SetMinMaxValues(0, max(mx, 1))
    f.power:SetValue(pcur)

    -- number on the mana bar (player only; Settings > Unit Frames)
    if f.powerText then
        local mode = DB().manaText or "current"
        if UnitPowerType(unit) == 1 and (mode == "percent" or mode == "valuepct") then mode = "current" end -- rage: no "%"
        local cur = UnitPower(unit)
        if mode == "off" or mx <= 0 then
            f.powerText:SetText("")
        elseif mode == "both" then
            f.powerText:SetText(cur .. " / " .. mx)
        elseif mode == "percent" then
            f.powerText:SetText(format("%d%%", floor(cur / mx * 100 + 0.5)))
        elseif mode == "valuepct" then
            f.powerText:SetText(format("%d  |cFFFFD100%d%%|r", cur, floor(cur / mx * 100 + 0.5)))
        else
            f.powerText:SetText(tostring(cur))
        end
    end

    -- Cast cost preview (player only): a white segment at the end of the bar covering the mana the spell being cast will use
    if f.costTex then
        if f.cysCostBar then f.cysCostBar:Hide() end
        local cost = CastCostNow(unit)
        local cur = UnitPower(unit)
        local width = f.power:GetWidth()
        if cost > 0 and mx > 0 and cur > 0 and width and width > 0 then
            f.costTex:SetWidth(max(1, width * min(cost, cur) / mx))
            f.costTex:Show()
        else
            f.costTex:Hide()
        end
    end
end

table.insert(CysUI.HealEstimateWatchers, function()
    for _, f in pairs(UF.frames) do
        if f.unit and f.healTex and UnitExists(f.unit) then UpdateHealth(f) end
    end
end)

local function UpdateName(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local level = UnitLevel(unit)
    local unitName = UnitName(unit)
    if Secret(level) or Secret(unitName) then
        -- WoW Forever: a locked name / level can go on the font string as it is, but not into format()
        pcall(f.name.SetText, f.name, unitName)
        return
    end
    local levelText = (level and level > 0) and tostring(level) or "??"
    local class = UnitClassification and CysUICompat.Plain(UnitClassification(unit))
    if class == "elite" or class == "worldboss" or class == "rareelite" then levelText = levelText .. "+" end
    f.name:SetText(format("|cFFFFD100%s|r %s", levelText, UnitName(unit) or ""))
end

-- Elite / rare tag between the level and the name: Elite in bright gold, Rare in silver, a skull for a boss.
-- Small frames (target of target, pet, party) get the short form. The classification is plain text from the game;
-- should it ever be locked it simply counts as none.
local TAG_GOLD, TAG_SILVER = "|cFFFFE680", "|cFFC9CED6"
local TAG_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"
local function ClassTag(unit, small)
    local class = UnitClassification and CysUICompat.Plain(UnitClassification(unit))
    if class == "worldboss" then
        return small and TAG_SKULL or (TAG_SKULL .. " " .. TAG_GOLD .. "Boss|r"), true
    elseif class == "rareelite" then
        return TAG_SILVER .. "Rare|r " .. TAG_GOLD .. (small and "+" or "Elite") .. "|r"
    elseif class == "elite" then
        return TAG_GOLD .. (small and "+" or "Elite") .. "|r"
    elseif class == "rare" then
        return TAG_SILVER .. "Rare|r"
    end
end

local UpdateNamePlain = UpdateName -- the older look: a + after the level
UpdateName = function(f)
    if DB().eliteTag == false then return UpdateNamePlain(f) end
    local unit = f.unit
    if not UnitExists(unit) then return end
    local level = UnitLevel(unit)
    local unitName = UnitName(unit)
    local tag, boss = ClassTag(unit, f.small)
    local lockedLevel = Secret(level)
    local prefix = ""
    -- a boss has no level to show (the game gives -1); its skull says enough
    if not lockedLevel and not (boss and not (level and level > 0)) then
        prefix = "|cFFFFD100" .. ((level and level > 0) and tostring(level) or "??") .. "|r "
    end
    if tag then prefix = prefix .. tag .. "  " end -- two spaces: the tag should not read as part of the name
    if lockedLevel or Secret(unitName) then
        -- WoW Forever: a locked name goes on the font string as it is; only our own plain text is put in front
        if not pcall(f.name.SetFormattedText, f.name, prefix .. "%s", unitName) then
            pcall(f.name.SetText, f.name, unitName)
        end
        return
    end
    f.name:SetText(prefix .. (unitName or ""))
end

-- WoW Forever: run each part on its own so one locked value can't blank the whole frame (on Classic Era the
-- parts are called directly, exactly as before)
local IS_FOREVER = CysUICompat.isForever
local stepErrors = {}
local function Step(label, fn, f)
    if not IS_FOREVER then return fn(f) end
    local ok, err = pcall(fn, f)
    if not ok then
        err = tostring(err)
        if not stepErrors[label .. err] then
            stepErrors[label .. err] = true
            local list = CysUICompat.errors
            if list and #list < 50 then list[#list + 1] = "Unit frames " .. label .. ": " .. err end
            print("|cFFFFD100Cys's UI|r |cFFFF8040(Forever)|r Unit frames " .. label .. ": " .. err)
        end
    end
end
-- Health bar look (Unit Frames > Health bar look):
--   gradient (default) - the full class / reaction color, a touch brighter at the top and deeper at the bottom
--   dark   - the older look: the color pulled toward black (flat)
--   bright - the plain class color (flat)
-- The empty part of the bar is a very dark shade of the same color, so missing health reads at a glance.
-- Colors are only re-applied when they change (this runs on every health update).
local DARK = 0.6
local function HealthStyle()
    local db = DB()
    return db.healthStyle or (db.darkFill == false and "bright" or "gradient")
end
UF.HealthStyle = HealthStyle

-- paints a bar's fill + backdrop: vertical gradient or flat, with a tinted dark backdrop
local function Paint(bar, bg, r, g, b, style)
    if bar.cysPaint == style and bar.cysR == r and bar.cysG == g and bar.cysB == b then return end
    bar.cysPaint, bar.cysR, bar.cysG, bar.cysB = style, r, g, b
    if style == "dark" then r, g, b = r * DARK, g * DARK, b * DARK
    elseif style == "gradient" then
        -- pale colors (Priest white, Rogue yellow) are toned down so the white text on top keeps reading
        local lum = 0.299 * r + 0.587 * g + 0.114 * b
        -- yellows (Rogue) keep more of their pop: they read fine a bit brighter than white does
        local cap = (b < 0.6 * min(r, g)) and 0.74 or 0.6
        if lum > cap then local k = cap / lum; r, g, b = r * k, g * k, b * k end
    end
    bar:SetStatusBarColor(r, g, b)
    local tex = bar:GetStatusBarTexture()
    if style == "gradient" and tex and tex.SetGradient and CreateColor then
        pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(r * 0.62, g * 0.62, b * 0.62, 1),                                  -- bottom
            CreateColor(min(1, r * 1.08 + 0.03), min(1, g * 1.08 + 0.03), min(1, b * 1.08 + 0.03), 1)) -- top
    end
    if bg then bg:SetColorTexture(r * 0.16 + 0.02, g * 0.16 + 0.02, b * 0.16 + 0.02, 1) end
end
UF.Paint = Paint

local function ApplyColor(f)
    local r, g, b = UnitColor(f.unit)
    if not DB().classColors then r, g, b = T.accent[1], T.accent[2], T.accent[3] end
    Paint(f.health, f.healthBg, r, g, b, HealthStyle())
end

--------------------------------------------------------------------------------
-- Party: what a healer needs to see. Up to 4 debuff icons beside each member and the frame's outline colored by
-- debuff type (magic, curse, disease, poison) - by default only for types you can remove right now.
-- WoW Forever: the game draws both itself (aura container), so they keep working in combat.
--------------------------------------------------------------------------------
local PARTY_ICON, PARTY_MAX = 22, 4
local DISPELLABLE = "HARMFUL|RAID_PLAYER_DISPELLABLE"

local function UpdatePartyAuras(f)
    local db = DB()
    local unit = f.unit
    if not (unit and UnitExists(unit)) then return end
    local showIcons = db.partyDebuffs ~= false
    local showOutline = db.partyDispel ~= false
    local onlyMine = db.partyDispelOnly ~= false

    if CysUICompat.isForever then
        if f.cysAuraBox == nil then
            local box = CysUICompat.AuraContainer(f, unit, {
                point = { "TOPLEFT", f, "TOPRIGHT", 4, 0 },
                anchor = "TOPLEFT", size = PARTY_ICON, gap = 2, noClicks = true,
                groups = { { key = "debuffs", filter = "HARMFUL", max = PARTY_MAX } },
            })
            f.cysAuraBox = box or false
            if box then
                f.cysDispel = CysUICompat.AuraDispelEdges(box, "dispel", DISPELLABLE, f, 3) or false
                f.cysDispelFilter = DISPELLABLE
            end
        end
        local box = f.cysAuraBox
        if box then
            local want = showIcons and PARTY_MAX or 0
            if f.cysAuraCap ~= want then
                f.cysAuraCap = want
                CysUICompat.AuraContainerCap(box, "debuffs", want)
            end
            if f.cysDispel then
                local filter = onlyMine and DISPELLABLE or "HARMFUL"
                if f.cysDispelFilter ~= filter then
                    f.cysDispelFilter = filter
                    pcall(box.SetAuraSlotFilterString, box, "dispel", filter)
                end
                if f.cysDispelOn ~= showOutline then
                    f.cysDispelOn = showOutline
                    pcall(box.SetAuraSlotEnabled, box, "dispel", showOutline)
                end
            end
            return
        end
    end

    -- Classic Era (and Forever if the game's containers are missing): read the debuffs ourselves
    f.partyIcons = f.partyIcons or {}
    if not f.dispelEdges then
        f.dispelEdges = W.Border(f.overlay or f, 3, { 1, 1, 1 }, "OVERLAY", 4) -- above the health bar
    end
    local outlineType
    local shown = 0
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expiration = GetAura(unit, i, "HARMFUL")
        if not name then break end
        if debuffType and not outlineType and (not onlyMine or CysUICompat.CanDispel(debuffType)) then
            outlineType = debuffType
        end
        if showIcons and shown < PARTY_MAX then
            shown = shown + 1
            local a = f.partyIcons[shown]
            if not a then a = MakeAura(f); f.partyIcons[shown] = a end
            a:SetSize(PARTY_ICON, PARTY_ICON)
            a.unit, a.index, a.filter, a.auraInstanceID = unit, i, "HARMFUL", nil
            a.icon:SetTexture(icon)
            a.count:SetText((count and count > 1) and count or "")
            if duration and duration > 0 and expiration then
                a.cd:SetCooldown(expiration - duration, duration)
                a.cd:Show()
            else
                a.cd:Hide()
            end
            local r, g, b = CysUICompat.DebuffColor(debuffType)
            W.SetBorder(a.edges, r and { r, g, b } or { 0.8, 0.2, 0.2 })
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", f, "TOPRIGHT", 4 + (shown - 1) * (PARTY_ICON + 2), 0)
            a:Show()
        end
    end
    for i = shown + 1, #f.partyIcons do f.partyIcons[i]:Hide() end
    local r, g, b
    if showOutline and outlineType then r, g, b = CysUICompat.DebuffColor(outlineType) end
    if r then
        W.SetBorder(f.dispelEdges, { r, g, b })
        for i = 1, 4 do f.dispelEdges[i]:Show() end
    else
        for i = 1, 4 do f.dispelEdges[i]:Hide() end
    end
end

function UF:Update(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    Step("color", ApplyColor, f)
    Step("name", UpdateName, f)
    Step("health", UpdateHealth, f)
    Step("power", UpdatePower, f)
    if f.raidIcon then
        local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
        if index and SetRaidTargetIconTexture then
            f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            SetRaidTargetIconTexture(f.raidIcon, index)
            f.raidIcon:Show()
        else
            f.raidIcon:Hide()
        end
    end
    Step("auras", UpdateAuras, f)
    if f.isParty then Step("party auras", UpdatePartyAuras, f) end
    Step("combo", UpdateCombo, f)
end
UF.Update = Guard("Unit frames", UF.Update) -- WoW Forever: a locked value skips one update instead of erroring

-- the icon size setting changed: WoW Forever's aura containers are built at one size, so they are rebuilt
function UF.RebuildAuras()
    for _, f in pairs(UF.frames) do
        if f.cysAuraBox and f.auras then -- party icons have their own fixed size
            pcall(f.cysAuraBox.SetEnabled, f.cysAuraBox, false)
            f.cysAuraBox:Hide()
            f.cysAuraBox = nil
        end
        if f.auras and f.unit and UnitExists(f.unit) then UF:Update(f) end
    end
end

--------------------------------------------------------------------------------
-- Building a frame & Click-Casting / Clique Registration
--------------------------------------------------------------------------------
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                      "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
                      "UNIT_CONNECTION", "UNIT_AURA", "UNIT_TARGET", "UNIT_HEAL_PREDICTION" }

local function RegisterWithClique(f)
    if not f then return end
    
    -- 1. Register with the global ClickCastFrames table used by Clique and standard click-casting systems
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[f] = true

    -- 2. Safely register with Clique addon APIs if present
    if Clique then
        if Clique.RegisterFrame then
            pcall(function() Clique:RegisterFrame(f) end)
        end
        if Clique.AddUnitFrame then
            pcall(function() Clique:AddUnitFrame(f) end)
        end
        if Clique.settings and Clique.settings.blacklist then
            Clique.settings.blacklist[f:GetName()] = nil
        end
    end
end

local function CreateUnitFrame(def)
    local f = CreateFrame("Button", def.name, UIParent, "SecureUnitButtonTemplate")
    f.unit = def.unit
    f:SetSize(def.w, def.h)
    f:SetAttribute("unit", def.unit)
    f:SetAttribute("*type1", "target")
    -- right-click menu: WoW Forever's "menu" action needs a menu function we don't have; its "togglemenu" opens
    -- Blizzard's own unit menu (Self / Party / Target...)
    f:SetAttribute("*type2", (CysUICompat and CysUICompat.isForever) and "togglemenu" or "menu")
    f:RegisterForClicks("AnyUp", "AnyDown")
    -- the game's ping key works on these frames (pings the unit the frame shows)
    if PingableType_UnitFrameMixin and Mixin then
        Mixin(f, PingableType_UnitFrameMixin)
        f:SetAttribute("ping-receiver", true)
    end
    f.noHealthText = def.noHealthText
    f.isParty = def.party
    f.small = def.fontSize ~= nil -- target of target, pet, party

    -- body
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    f.edges = W.Border(f, 1, T.border, "BORDER")
    -- soft drop shadow just outside the frame, so it lifts off busy ground
    f.shadow = {}
    for i, a in ipairs({ 0.45, 0.22, 0.1 }) do
        local sh = f:CreateTexture(nil, "BACKGROUND", nil, -8 + i)
        sh:SetColorTexture(0, 0, 0, a)
        sh:SetPoint("TOPLEFT", f, "TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i, -i)
        f.shadow[i] = sh
    end

    if def.power then
        f.power = CreateFrame("StatusBar", nil, f)
        f.power:SetStatusBarTexture(FLAT)
        f.power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.power:SetHeight(def.powerH or 7)
        f.cysPowerH = def.powerH or 7
        f.powerBg = W.Texture(f.power, "BACKGROUND", { T.field[1], T.field[2], T.field[3], 1 })
        f.powerBg:SetAllPoints()
        f.costTex = f.power:CreateTexture(nil, "ARTWORK", nil, 2)
        f.costTex:SetTexture(FLAT)
        f.costTex:SetVertexColor(1, 1, 1, 0.85)
        f.costTex:SetPoint("TOPRIGHT", f.power:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        f.costTex:SetPoint("BOTTOMRIGHT", f.power:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        f.costTex:Hide()
    end
    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetStatusBarTexture(FLAT)
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    if def.power then
        f.health:SetPoint("BOTTOMLEFT", f.power, "TOPLEFT", 0, 1)
        f.health:SetPoint("BOTTOMRIGHT", f.power, "TOPRIGHT", 0, 1)
    else
        f.health:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    end
    f.healthBg = W.Texture(f.health, "BACKGROUND", { T.field[1], T.field[2], T.field[3], 1 })
    f.healthBg:SetAllPoints()

    -- Heal prediction: starts at the end of the health fill (see UpdateHealth)
    f.healTex = f.health:CreateTexture(nil, "ARTWORK", nil, 1)
    f.healTex:SetTexture(FLAT)
    f.healTex:SetVertexColor(0.0, 0.75, 0.45, 0.6)
    f.healTex:SetPoint("TOPLEFT", f.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    f.healTex:SetPoint("BOTTOMLEFT", f.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    f.healTex:Hide()
    -- the part of a heal that would be wasted: a thin sliver just outside the frame
    f.overhealTex = f.health:CreateTexture(nil, "ARTWORK", nil, 1)
    f.overhealTex:SetTexture(FLAT)
    f.overhealTex:SetVertexColor(0.0, 0.9, 0.8, 0.75)
    f.overhealTex:SetPoint("TOPLEFT", f.health, "TOPRIGHT", 1, 0)
    f.overhealTex:SetPoint("BOTTOMLEFT", f.health, "BOTTOMRIGHT", 1, 0)
    f.overhealTex:Hide()
    f.health:SetScript("OnSizeChanged", function() if f.unit and UnitExists(f.unit) then UpdateHealth(f) end end)
    -- a faint top highlight on the health bar: a modern glassy edge without a texture
    local hl = f.health:CreateTexture(nil, "ARTWORK", nil, 3)
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:SetPoint("TOPLEFT"); hl:SetPoint("TOPRIGHT"); hl:SetHeight(1)

    -- text lives on a frame above the bars
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f.overlay = overlay
    f.healthText = overlay:CreateFontString(nil, "OVERLAY")
    f.healthText:SetFont(CysUICompat.Font(), CysUICompat.FontSize(def.fontSize or 11), "OUTLINE")
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", def.party and -19 or -5, 0) -- party: clear of the role icon
    if def.powerH and f.power then
        f.powerText = overlay:CreateFontString(nil, "OVERLAY")
        f.powerText:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
        f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
    end
    f.name = overlay:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(CysUICompat.Font(), CysUICompat.FontSize(def.fontSize or 11), "OUTLINE")
    -- white text with a soft drop shadow on every frame
    for _, fs in ipairs({ f.healthText, f.powerText, f.name }) do
        fs:SetTextColor(1, 1, 1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
    end
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.name:SetPoint("LEFT", f.health, "LEFT", 5, 0)
    f.name:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)

    f.raidIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.raidIcon:SetSize(16, 16)
    f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raidIcon:Hide()

    if def.auras then
        f.auras = { HARMFUL = {}, HELPFUL = {} }
    end
    if def.combo then
        f.pips = {}
        for i = 1, 5 do
            local pip = CreateFrame("Frame", nil, f)
            pip:SetSize(10, 6)
            pip:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -((5 - i) * 12), 3)
            pip.tex = pip:CreateTexture(nil, "ARTWORK")
            pip.tex:SetAllPoints()
            pip:Hide()
            f.pips[i] = pip
        end
    end

    -- mouse-over tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- events
    for _, ev in ipairs(UNIT_EVENTS) do
        if not (ev == "UNIT_AURA" and not def.auras and not def.party) and not (ev == "UNIT_TARGET" and def.unit ~= "targettarget") then
            local unit = (ev == "UNIT_TARGET") and "target" or def.unit
            pcall(f.RegisterUnitEvent, f, ev, unit)
        end
    end
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE" }) do pcall(f.RegisterEvent, f, ev) end
    if def.unit == "target" or def.unit == "targettarget" then pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED") end
    if def.combo then pcall(f.RegisterEvent, f, "PLAYER_COMBO_POINTS") end
    if def.unit == "pet" then pcall(f.RegisterEvent, f, "UNIT_PET") end
    if def.unit == "focus" then pcall(f.RegisterEvent, f, "PLAYER_FOCUS_CHANGED") end
    if def.unit == "player" and def.power then
        for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
                              "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED" }) do
            pcall(f.RegisterUnitEvent, f, ev, "player")
        end
    end
    if def.party then pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE") end
    f:SetScript("OnEvent", function(self, event)
        -- a new target: the game's aura icons need telling (WoW Forever)
        if self.cysAuraBox and (event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE") then
            CysUICompat.AuraContainerUnit(self.cysAuraBox)
        end
        UF:Update(self)
    end)

    -- Register safely with Clique and ClickCastFrames
    RegisterWithClique(f)

    return f
end

local DEFS = {
    player       = { unit = "player", name = "CysUIPlayerFrame", w = 230, h = 48, power = true, powerH = 11,
                     label = "Player Frame", point = "CENTER", x = -200, y = -170 },
    target       = { unit = "target", name = "CysUITargetFrame", w = 230, h = 48, power = true, auras = true, combo = true,
                     watch = true, label = "Target Frame", point = "CENTER", x = 200, y = -170 },
    targettarget = { unit = "targettarget", name = "CysUITargetTargetFrame", w = 120, h = 26, watch = true, fontSize = 10,
                     noHealthText = true, label = "Target of Target", point = "CENTER", x = 262, y = -246 },
    pet          = { unit = "pet", name = "CysUIPetFrame", w = 130, h = 32, power = true, watch = true, fontSize = 10,
                     noHealthText = true, label = "Pet Frame", point = "CENTER", x = -250, y = -246 },
    -- WoW Forever only (Classic Era has no focus); on unless switched off
    focus        = { unit = "focus", name = "CysUIFocusFrame", w = 150, h = 32, power = true, watch = true, fontSize = 10,
                     noHealthText = true, label = "Focus Frame", point = "CENTER", x = -420, y = -60 },
}

local BLIZZARD = {
    player = { "PlayerFrame" },
    target = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    pet = { "PetFrame" },
    focus = { "FocusFrame" },
    party = { "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "PartyFrame" },
}

-- Blizzard's own health/power bars inside a unit frame. They register their own events, so muting the
-- frame alone leaves them updating in the background (on WoW Forever that runs into locked "secret" health
-- values and throws taint errors blamed on CysUI, e.g. when the Character window opens).
local function BlizzardBars(fr)
    local bars = {}
    local function add(b) if b and b.UnregisterAllEvents then bars[#bars + 1] = b end end
    add(fr.healthbar); add(fr.healthBar); add(fr.HealthBar)
    add(fr.manabar); add(fr.manaBar); add(fr.ManaBar)
    local hbc = fr.HealthBarsContainer
    if hbc then add(hbc.healthBar); add(hbc.HealthBar) end
    return bars
end

local function Quiet(obj)
    if obj.UnregisterAllEvents then pcall(obj.UnregisterAllEvents, obj) end
    if obj.SetScript and obj.HasScript then
        if obj:HasScript("OnUpdate") then pcall(obj.SetScript, obj, "OnUpdate", nil) end
    end
end

-- Park Blizzard's frame somewhere it can never come back (we're out of combat at login).
local function HideBlizzard(key)
    for _, name in ipairs(BLIZZARD[key] or {}) do
        local fr = _G[name]
        if fr then
            Quiet(fr)
            for _, bar in ipairs(BlizzardBars(fr)) do Quiet(bar) end
            -- Forever: these are Edit Mode frames; hiding them from addon code taints Edit Mode (see Compat)
            if not CysUICompat.HideEditModeFrame(fr) then
                pcall(fr.SetParent, fr, hidden)
                pcall(fr.Hide, fr)
            end
        end
    end
end

local function Build(key)
    local def = DEFS[key]
    local f = CreateUnitFrame(def)
    UF.frames[key] = f
    f:ClearAllPoints()
    f:SetPoint(def.point, UIParent, def.point, def.x, def.y)
    CUI:RegisterMovable(f, key, def.label, { point = def.point, x = def.x, y = def.y, resizable = true,
        minW = 80, maxW = 500, minH = 18, maxH = 120 })
    if def.watch then RegisterUnitWatch(f) end
    HideBlizzard(key)
    UF:Update(f)
end

local PARTY_ROLE_COORDS = {
    TANK = { 0, 0.296875, 0.34375, 0.640625 },
    HEALER = { 0.3125, 0.609375, 0.015625, 0.3125 },
}
function UF.SetPartyRole(f, role)
    if not (f and f.cysHealer) then return end
    local c = role and PARTY_ROLE_COORDS[role]
    if c then f.cysHealer:SetTexCoord(c[1], c[2], c[3], c[4]) end
    f.cysHealer:SetShown(c and true or false)
end

local function BuildParty()
    local anchor = CreateFrame("Frame", "CysUIPartyAnchor", UIParent)
    anchor:SetSize(180, 4 * 44 - 6)
    UF.party = {}
    CUI:RegisterMovable(anchor, "party", "Party Frames", { point = "LEFT", x = 40, y = 120,
        resizable = true, minW = 100, maxW = 400, minH = 100, maxH = 320,
        -- width = frame width; height = all four frames together
        onResize = function(a, w, h)
            if InCombatLockdown() then return end
            local mh = math.max(16, math.floor((h + 6) / 4) - 6)
            UF.partyH = mh
            for _, pf in ipairs(UF.party) do pf:SetSize(w, mh) end
            if UF.LayoutParty then UF.LayoutParty() end
        end })
    for i = 1, 4 do
        local f = CreateUnitFrame({ unit = "party" .. i, name = "CysUIPartyFrame" .. i, w = 180, h = 38, power = true,
            fontSize = 10, party = true })
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * 44)
        -- a party, not a raid: shown while that party member exists. If the state driver is refused (a known
        -- WoW Forever beta bug), fall back to showing it whenever that party member exists.
        if not pcall(RegisterStateDriver, f, "visibility", format("[group:raid] hide; [@party%d,exists] show; hide", i)) then
            RegisterUnitWatch(f)
        end
        UF.party[i] = f
        UF.frames["party" .. i] = f
        -- role marker: a small tank shield or healer cross in the top-right corner. It sits on the text layer;
        -- on the frame itself the health bar covered it (it only showed through when the frame faded out of range).
        local role = (f.overlay or f):CreateTexture(nil, "OVERLAY", nil, 7)
        role:SetSize(14, 14)
        role:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        role:SetTexCoord(0.3125, 0.609375, 0.015625, 0.3125) -- the healer cross
        role:Hide()
        f.cysHealer = role
    end
    -- who heals: a role set by hand on the Raid Frames page, the game's assigned role, or a Priest by default
    local function IsHealer(unit)
        local okN, name = pcall(UnitName, unit)
        local roles = CysUIDB and CysUIDB.raidframes and CysUIDB.raidframes.roles
        if okN and type(name) == "string" and roles and roles[name] then return roles[name] == "HEALER" end
        if UnitGroupRolesAssigned then
            local okR, r = pcall(UnitGroupRolesAssigned, unit)
            if okR and r and r ~= "NONE" then return r == "HEALER" end
        end
        local okC, _, class = pcall(UnitClass, unit)
        return okC and class == "PRIEST"
    end
    -- party order: tank, then healer, then damage (by role), so the tank and healer sit in the top two spots.
    -- The frames are secure, so they are only moved out of combat; a change mid-fight is applied after it.
    local function Rank(unit)
        if not UnitExists(unit) then return 9 end -- empty slots go to the bottom
        local okN, name = pcall(UnitName, unit)
        local roles = CysUIDB and CysUIDB.raidframes and CysUIDB.raidframes.roles
        local r = okN and type(name) == "string" and roles and roles[name]
        if not r and UnitGroupRolesAssigned then
            local okR, g = pcall(UnitGroupRolesAssigned, unit)
            if okR and type(g) == "string" then r = g end
        end
        if r == "TANK" then return 1 end
        if r == "HEALER" or (r ~= "DAMAGER" and IsHealer(unit)) then return 2 end
        return 3
    end
    local function UpdateHealers()
        for i = 1, 4 do
            local f = UF.party[i]
            if f and f.cysHealer then
                local rank = UnitExists("party" .. i) and Rank("party" .. i)
                UF.SetPartyRole(f, rank == 1 and "TANK" or rank == 2 and "HEALER" or nil)
            end
        end
    end
    local sortPending = false
    local function LayoutParty()
        if InCombatLockdown() then sortPending = true; return end
        sortPending = false
        local order = { 1, 2, 3, 4 }
        if DB().partySort ~= false then
            local rank = {}
            for i = 1, 4 do rank[i] = Rank("party" .. i) end
            table.sort(order, function(x, y)
                if rank[x] ~= rank[y] then return rank[x] < rank[y] end
                return x < y
            end)
        end
        local mh = UF.partyH or 38
        for slot, i in ipairs(order) do
            local pf = UF.party[i]
            if pf then
                pf:ClearAllPoints()
                pf:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(slot - 1) * (mh + 6))
            end
        end
    end
    UF.LayoutParty = LayoutParty
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_ENABLED" then
            if sortPending then pcall(LayoutParty) end
            return
        end
        pcall(UpdateHealers)
        pcall(LayoutParty)
    end)
    UF.UpdateHealers = UpdateHealers
    pcall(UpdateHealers)
    pcall(LayoutParty)
    HideBlizzard("party")
end

--------------------------------------------------------------------------------
-- Party preview: four made-up members drawn on the real party frames, so the look can be checked while solo.
-- The frames' show / hide rules are paused while it is on and put back when it is turned off (out of combat only).
--------------------------------------------------------------------------------
local PARTY_FAKE = {
    { name = "Tankzilla", class = "WARRIOR", level = 60, pct = 0.82, power = 35, ptype = 1, role = "TANK" },
    { name = "Healbot", class = "PRIEST", level = 60, pct = 1, power = 70, ptype = 0, role = "HEALER", debuff = "Magic" },
    { name = "Backstab", class = "ROGUE", level = 59, pct = 0.46, power = 90, ptype = 3, debuff = "Poison" },
    { name = "Frostbolt", class = "MAGE", level = 58, pct = 0.68, power = 55, ptype = 0, debuff = "Curse", faded = true },
}
local PREVIEW_ICON = {
    Magic = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    Poison = "Interface\\Icons\\Ability_Creature_Poison_02",
    Curse = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
}

local function PartyVisibility(f, i, preview)
    if preview then
        pcall(UnregisterStateDriver, f, "visibility")
        pcall(UnregisterUnitWatch, f)
        f:Show()
    elseif not pcall(RegisterStateDriver, f, "visibility", format("[group:raid] hide; [@party%d,exists] show; hide", i)) then
        RegisterUnitWatch(f)
    end
end

local function FillPartyPreview(f, d)
    local db = DB()
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class] or { r = 0.6, g = 0.6, b = 0.6 }
    local r, g, b = c.r, c.g, c.b
    if not db.classColors then r, g, b = T.accent[1], T.accent[2], T.accent[3] end
    f.health:SetMinMaxValues(0, 4200)
    f.health:SetValue(floor(4200 * d.pct))
    Paint(f.health, f.healthBg, r, g, b, HealthStyle())
    if f.healTex then f.healTex:Hide(); f.overhealTex:Hide() end
    f.name:SetText(format("|cFFFFD100%d|r %s", d.level, d.name))
    f.healthText:SetText(f.noHealthText and "" or HealthString(floor(4200 * d.pct), 4200))
    if f.power and PartyPowerShown(f, d.ptype) then
        local pc = PowerBarColor and PowerBarColor[d.ptype]
        local fb = FALLBACK_POWER[d.ptype] or { 0.6, 0.6, 0.6 }
        f.power:SetMinMaxValues(0, 100)
        f.power:SetValue(d.power)
        if pc and pc.r then Paint(f.power, f.powerBg, pc.r, pc.g, pc.b, HealthStyle() == "gradient" and "gradient" or "bright")
        else Paint(f.power, f.powerBg, fb[1], fb[2], fb[3], HealthStyle() == "gradient" and "gradient" or "bright") end
        if f.costTex then f.costTex:Hide() end
    end
    if f.raidIcon then f.raidIcon:Hide() end
    UF.SetPartyRole(f, d.role)

    -- debuff icon beside the frame, and the outline colored by its type (same rules as the real thing)
    f.cysPreviewIcons = f.cysPreviewIcons or {}
    local a = f.cysPreviewIcons[1]
    if d.debuff and db.partyDebuffs ~= false then
        if not a then a = MakeAura(f); f.cysPreviewIcons[1] = a end
        a:SetSize(PARTY_ICON, PARTY_ICON)
        a.unit, a.index, a.filter, a.auraInstanceID = nil, nil, nil, nil
        a.icon:SetTexture(PREVIEW_ICON[d.debuff])
        a.count:SetText("")
        a.cd:Hide()
        local dr, dg, dbl = CysUICompat.DebuffColor(d.debuff)
        W.SetBorder(a.edges, dr and { dr, dg, dbl } or { 0.8, 0.2, 0.2 })
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
        a:Show()
    elseif a then
        a:Hide()
    end
    if not f.cysPreviewEdges then f.cysPreviewEdges = W.Border(f.overlay or f, 3, { 1, 1, 1 }, "OVERLAY", 4) end
    local showOutline = d.debuff and db.partyDispel ~= false
        and (db.partyDispelOnly == false or CysUICompat.CanDispel(d.debuff))
    local er, eg, eb
    if showOutline then er, eg, eb = CysUICompat.DebuffColor(d.debuff) end
    if er then W.SetBorder(f.cysPreviewEdges, { er, eg, eb }) end
    for k = 1, 4 do f.cysPreviewEdges[k]:SetShown(er and true or false) end

    -- out of range: the range check leaves the frame alone while it sees an empty slot at full alpha
    local alpha = (d.faded and db.rangeFade ~= false) and 0.45 or 1
    f.cysRangeAlpha = 1
    f:SetAlpha(alpha)
end

local function ClearPartyPreview(f)
    for _, a in ipairs(f.cysPreviewIcons or {}) do a:Hide() end
    if f.cysPreviewEdges then for k = 1, 4 do f.cysPreviewEdges[k]:Hide() end end
    f.cysRangeAlpha = nil
    f:SetAlpha(1)
    f.healthText:SetText("")
    f.name:SetText("")
end

function UF.RefreshPartyPreview()
    if not (UF.partyPreview and UF.party) then return end
    for i, f in ipairs(UF.party) do
        if PARTY_FAKE[i] and not UnitExists("party" .. i) then FillPartyPreview(f, PARTY_FAKE[i]) end
    end
end

function UF.PartyTest(on)
    if not UF.party then CUI:Print("Party frames are off (Unit Frames > Party). Turn them on and /reload to preview.") return end
    if InCombatLockdown() then CUI:Print("The party preview waits until you leave combat.") return end
    if on == nil then on = not UF.partyPreview end
    if on and IsInGroup() then CUI:Print("You're in a group - your real party frames are already showing.") return end
    UF.partyPreview = on and true or false
    for i, f in ipairs(UF.party) do
        PartyVisibility(f, i, on)
        if on then
            FillPartyPreview(f, PARTY_FAKE[i])
        else
            ClearPartyPreview(f)
            UF:Update(f)
        end
    end
    if not on and UF.UpdateHealers then pcall(UF.UpdateHealers) end
    if UF.LayoutParty then pcall(UF.LayoutParty) end
    CUI:Print("Party frame preview " .. (on and "ON - press Preview again to turn it off" or "off"))
end

-- joining a real group ends the preview (as soon as combat allows)
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function()
        if UF.partyPreview and IsInGroup() and not InCombatLockdown() then UF.PartyTest(false) end
    end)
end

function UF.Enable()
    if InCombatLockdown() then
        CUI:Print("|cFFFF9F43Unit Frames: can't start in combat. Reload out of combat.|r")
        return
    end
    local db = DB()
    for key in pairs(DEFS) do
        local on = db[key]
        if key == "focus" then on = db.focus ~= false and CysUICompat and CysUICompat.isForever end
        if on then
            local ok, err = pcall(Build, key)
            if not ok then CUI:Print("|cFFFF9F43Unit Frames: " .. key .. " skipped (" .. tostring(err) .. ")|r") end
        end
    end
    if db.party then
        local ok, err = pcall(BuildParty)
        if not ok then CUI:Print("|cFFFF9F43Unit Frames: party skipped (" .. tostring(err) .. ")|r") end
    end
    UF.StartRangeCheck()
    UF.SetupCombatIcon()
    UF.ApplyNameStyle()
    UF.ApplyTargetAccent()
    UF.SetupLeaderIcons()
    UF.ApplyPlayerPower()
    C_Timer.After(3, UF.ApplyPlayerPower) -- once more after the modules (Resource Bar) are up
end

-- The player frame's own power bar. "auto" (default) hides it while Cys's Resource Bar is on and always shown,
-- so rage / energy / mana isn't on screen twice; "show" / "hide" force it. The health bar takes the freed space.
-- Our own child frames only, but they sit in a secure button, so it waits until out of combat.
local powerWaiter
function UF.ApplyPlayerPower()
    local f = UF.frames.player
    if not (f and f.power and f.health) then return end
    if InCombatLockdown() then
        if not powerWaiter then
            powerWaiter = CreateFrame("Frame")
            powerWaiter:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                UF.ApplyPlayerPower()
            end)
        end
        powerWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local mode = DB().playerPower or "auto"
    local hide = mode == "hide"
    if mode == "auto" then
        local rdb = CysUIDB.resource
        hide = CUI:IsModuleEnabled("resource") and _G.CysResourceBar ~= nil and not (rdb and rdb.show == "combat")
    end
    local was = f.powerHidden
    f.powerHidden = hide or nil
    f.power:SetShown(not hide)
    if f.powerText then f.powerText:SetShown(not hide) end
    if hide and f.cysCostBar then f.cysCostBar:Hide() end
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    if hide then
        f.health:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    else
        f.health:SetPoint("BOTTOMLEFT", f.power, "TOPLEFT", 0, 1)
        f.health:SetPoint("BOTTOMRIGHT", f.power, "TOPRIGHT", 0, 1)
        if was then UF:Update(f) end
    end
end

-- Group leader: a small crown just left of the top-left corner of the leader's frame - on the party frames, and
-- on your own frame when you lead. Only shown while you are in a group.
function UF.UpdateLeaders()
    local on = DB().leaderIcon ~= false
    local grouped = IsInGroup and IsInGroup()
    for _, key in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local f = UF.frames[key]
        if f and f.overlay then
            if not f.leader then
                -- 18 px, pure gold, with a dark copy 1 px down-right as a shadow so it reads on any background
                f.leaderShadow = f.overlay:CreateTexture(nil, "OVERLAY", nil, 1)
                f.leaderShadow:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                f.leaderShadow:SetVertexColor(0, 0, 0, 0.9)
                f.leaderShadow:SetSize(18, 18)
                f.leader = f.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
                f.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                f.leader:SetVertexColor(1, 0.86, 0.25)
                f.leader:SetSize(18, 18)
                f.leader:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 2)
                f.leaderShadow:SetPoint("TOPLEFT", f.leader, "TOPLEFT", 1, -1)
            end
            local show = false
            if on and grouped and UnitIsGroupLeader then
                local ok, lead = pcall(UnitIsGroupLeader, f.unit)
                show = ok and not Secret(lead) and lead and true or false
            end
            f.leader:SetShown(show)
            f.leaderShadow:SetShown(show)
        end
    end
end
function UF.SetupLeaderIcons()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function() pcall(UF.UpdateLeaders) end)
    pcall(UF.UpdateLeaders)
end

-- Target accent: a soft gold line along the top edge of the target frame, so the frame you are fighting reads at
-- a glance. A flat line of our own, no glow.
function UF.ApplyTargetAccent()
    local f = UF.frames.target
    if not f or not f.overlay then return end
    if not f.accentLine then
        -- a crisp 1 px line in the theme color (follows the Border color setting) with a soft glow fading down
        local t = W.Texture(f.overlay, "ARTWORK", T.glow)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        t:SetHeight(1)
        f.accentLine = t
        local g = f.overlay:CreateTexture(nil, "ARTWORK", nil, -1)
        g:SetTexture(FLAT)
        g:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
        g:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", 0, 0)
        g:SetHeight(9)
        f.accentGlow = g
    end
    local c = T.glow
    if f.accentGlow.SetGradient and CreateColor then
        f.accentGlow:SetVertexColor(1, 1, 1, 1)
        pcall(f.accentGlow.SetGradient, f.accentGlow, "VERTICAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 0.32))
    else
        f.accentGlow:SetVertexColor(c[1], c[2], c[3], 0.15)
    end
    local on = DB().targetAccent ~= false
    f.accentLine:SetShown(on)
    f.accentGlow:SetShown(on)
end

-- Names on the player and target frames: small in the top-left corner of the health bar (the default), which
-- leaves the middle of the bar free for Frame Combat Text, or the classic larger name on the left.
-- Only font strings of our own are touched, so this is safe to change in combat.
function UF.ApplyNameStyle()
    local db = DB()
    local size = db.nameSize or 10
    local function Style(f, corner, cornerSize, plainSize, right)
        if not (f and f.name and f.health) then return end
        f.name:ClearAllPoints()
        f.name:SetShadowColor(0, 0, 0, 1) -- a dark drop shadow keeps the name readable on bright class colors
        f.name:SetShadowOffset(1, -1)
        if corner then
            f.name:SetFont(CysUICompat.Font(), CysUICompat.FontSize(cornerSize), "OUTLINE")
            f.name:SetPoint("TOPLEFT", f.health, "TOPLEFT", 4, -3)
            f.name:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", right or -4, -3)
        else
            f.name:SetFont(CysUICompat.Font(), CysUICompat.FontSize(plainSize), "OUTLINE")
            f.name:SetPoint("LEFT", f.health, "LEFT", 5, 0)
            f.name:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
        end
    end
    local corner = db.nameCorner ~= false
    Style(UF.frames.player, corner, size, 11)
    Style(UF.frames.target, corner, size, 11)
    -- the small frames follow with a smaller font; party names stop short of the healer icon
    local small = db.nameCornerSmall ~= false
    Style(UF.frames.targettarget, small, math.min(size, 9), 10)
    Style(UF.frames.pet, small, math.min(size, 9), 10)
    Style(UF.frames.focus, small, math.min(size, 9), 10)
    for i = 1, 4 do Style(UF.frames["party" .. i], small, math.min(size, 10), 10, -18) end
end

-- Combat: crossed swords on the player frame while you are in combat (switch on the Unit Frames page)
function UF.SetupCombatIcon()
    local f = UF.frames.player
    if not f or f.cysCombat then return end
    local holder = CreateFrame("Frame", nil, f)
    holder:SetSize(20, 20)
    holder:SetPoint("CENTER", f, "TOPRIGHT", -4, -2)
    holder:SetFrameLevel(f:GetFrameLevel() + 8)
    holder:EnableMouse(false)
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    tex:SetTexCoord(0.5, 1, 0, 0.49) -- the combat half of the state icon
    f.cysCombat = holder
    local function Apply()
        holder:SetShown(DB().combatIcon ~= false and (InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) or false))
    end
    UF.ApplyCombatIcon = Apply
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then holder:SetShown(DB().combatIcon ~= false)
        elseif event == "PLAYER_REGEN_ENABLED" then holder:Hide()
        else Apply() end
    end)
    Apply()
end

-- party members out of range fade; a player you target shows a rough distance
function UF.StartRangeCheck()
    if UF.rangeTicker then return end
    UF.rangeTicker = C_Timer.NewTicker(0.4, Guard("Unit frame range", function()
        local db = DB()
        for unit, f in pairs(UF.frames) do
            if f.IsShown and f:IsShown() then
                local alpha = 1
                local locked
                if db.rangeFade ~= false and unit:find("^party") and UnitExists(unit) and UnitInRange then
                    local inRange, checked = UnitInRange(unit)
                    if Secret(inRange) or Secret(checked) then
                        -- WoW Forever: range is a locked true/false; the frame can still apply it as alpha
                        locked = true
                        if f.SetAlphaFromBoolean then pcall(f.SetAlphaFromBoolean, f, inRange, 1, 0.45) end
                        f.cysRangeAlpha = nil
                    elseif checked and not inRange then alpha = 0.45 end
                end
                if not locked and f.cysRangeAlpha ~= alpha then f.cysRangeAlpha = alpha; f:SetAlpha(alpha) end
            end
        end
        local tf = UF.frames.target
        if tf and tf:IsShown() then
            if not tf.rangeText then
                tf.rangeText = tf.healthText:GetParent():CreateFontString(nil, "OVERLAY")
                tf.rangeText:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
                tf.rangeText:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", -5, 3)
                tf.rangeText:SetTextColor(0.75, 0.75, 0.75)
            end
            local txt = ""
            if db.targetRange ~= false and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
                and not UnitIsDead("target") and CheckInteractDistance
                and not (CysUICompat.isForever and InCombatLockdown()) then -- Forever blocks it in combat
                if CheckInteractDistance("target", 3) then txt = "10 yd"
                elseif CheckInteractDistance("target", 1) then txt = "28 yd"
                else txt = "28+ yd" end
            end
            tf.rangeText:SetText(txt)
        end
    end))
end

CUI:RegisterModule({
    key = "unitframes",
    name = "Unit Frames",
    addon = "CysUI",
    desc = "Flat player, target, target-of-target, pet and party frames with auras and combo points. Raid frames are in their own Raid Frames module.",
    onEnable = UF.Enable,
    open = function() CUI:OpenConfig("Unit Frames") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Keep the player and target frames clear of Cys's Cooldown bars: when a bar would run into one of them, the
-- frame slides outward (same size) until there is a small gap, and goes back to its layout spot when the bar
-- gets narrower again. Out of combat only (unit frames are locked during a fight). The frame's layout-mode box
-- slides with it (the shift is added to the box's spot, never saved), so layout mode shows where the frame is.
--------------------------------------------------------------------------------
local CLEAR_GAP = 6
local CLEAR_BARS = { "CysCooldownBar_main", "CysCooldownBar_utility" }
local clearPending, clearQueued = false, false

local function ScreenRect(f)
    local l, b, w, h = f:GetRect()
    if not (l and w) then return end
    local s = f:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

function UF.KeepClear()
    clearQueued = false
    if InCombatLockdown() then clearPending = true return end
    clearPending = false
    local stance = CUI.movers and CUI.movers["cooldowns_stance"]
    if stance and stance.stanceAttached and not DB().stanceAttach then
        stance.stanceAttached = nil
        CUI:ApplyLayout("cooldowns_stance") -- unpinned: back to its own layout spot
    end
    local on = DB().keepClear ~= false
    for _, key in ipairs({ "player", "target" }) do
        local f, m = UF.frames[key], CUI.movers and CUI.movers[key]
        local p, rel, rp, mx, my
        if f and m and m.mover then p, rel, rp, mx, my = m.mover:GetPoint(1) end
        if p then
            -- back to the saved spot first (take off the shift added last time)
            local bx = mx - (m.cysShift or 0)
            m.mover:ClearAllPoints()
            m.mover:SetPoint(p, rel, rp, bx, my)
            m.cysShift = 0
            f:ClearAllPoints()
            f:SetPoint("CENTER", m.mover, "CENTER", 0, 0)
            local fl, fb, fr, ft = ScreenRect(f)
            if on and fl then
                local gap = CLEAR_GAP * UIParent:GetEffectiveScale()
                local fc, shift = (fl + fr) / 2, 0
                for _, name in ipairs(CLEAR_BARS) do
                    local bar = _G[name]
                    if bar and bar:IsVisible() then
                        local bl, bb, br, bt = ScreenRect(bar)
                        -- room for the bar's widest stance (it can't be made in a fight): grow it the way it grows
                        local maxW = bl and type(bar.cysMaxW) == "number" and bar.cysMaxW * bar:GetEffectiveScale()
                        if maxW and maxW > br - bl then
                            local extra = maxW - (br - bl)
                            local pt = bar:GetPoint(1) or "CENTER"
                            if pt:find("LEFT") then br = br + extra
                            elseif pt:find("RIGHT") then bl = bl - extra
                            else bl, br = bl - extra / 2, br + extra / 2 end
                        end
                        if bl and bt > fb and bb < ft then -- the bar is level with the frame
                            if fc < (bl + br) / 2 then
                                shift = math.min(shift, bl - gap - fr) -- frame left of the bar: slide left
                            else
                                shift = math.max(shift, br + gap - fl) -- frame right of the bar: slide right
                            end
                        end
                    end
                end
                if shift ~= 0 then
                    local s = shift / m.mover:GetEffectiveScale()
                    m.mover:ClearAllPoints()
                    m.mover:SetPoint(p, rel, rp, bx + s, my)
                    m.cysShift = s
                end
            end
        end
    end
    if UF.AttachStance then UF.AttachStance() end -- defined just below
end

-- the Cooldown Manager's stance icon pinned above the player frame's top-right corner (follows the frame)
local function AttachStance()
    local m, f = CUI.movers and CUI.movers["cooldowns_stance"], UF.frames.player
    if not (m and f and DB().stanceAttach) then return end
    -- the stance icon is a plain frame, so it can be re-pinned in combat too; if it ever is a protected one,
    -- wait for the fight to end instead
    if InCombatLockdown() and m.frame and m.frame.IsProtected and m.frame:IsProtected() then clearPending = true return end
    m.mover:ClearAllPoints()
    m.mover:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 3)
    m.stanceAttached = true
end
UF.AttachStance = AttachStance

local WatchBars
local function QueueKeepClear()
    if WatchBars then WatchBars() end -- bars built since the last look (the Cooldown Manager can load late)
    if clearQueued then return end
    clearQueued = true
    C_Timer.After(0, UF.KeepClear)
end
UF.QueueKeepClear = QueueKeepClear

local watchedBars = {}
function WatchBars()
    for _, name in ipairs(CLEAR_BARS) do
        local bar = _G[name]
        if bar and not watchedBars[bar] then
            watchedBars[bar] = true
            bar:HookScript("OnSizeChanged", QueueKeepClear)
            bar:HookScript("OnShow", QueueKeepClear)
            bar:HookScript("OnHide", QueueKeepClear)
        end
    end
end

local clearWatch = CreateFrame("Frame")
clearWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
clearWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
clearWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
local clearHooked = false
clearWatch:SetScript("OnEvent", function(_, event)
    if not next(UF.frames) then return end -- unit frames off
    if event == "PLAYER_REGEN_ENABLED" then
        if clearPending then QueueKeepClear() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- last moment the frames can still be moved: settle them now, not after the fight
        WatchBars()
        if not InCombatLockdown() then pcall(UF.KeepClear) end
        return
    end
    if not clearHooked then
        clearHooked = true
        hooksecurefunc(CUI, "ApplyLayout", function(_, key)
            -- ApplyLayout just put the box back on its saved spot: no shift on it any more
            if (key == "player" or key == "target") and CUI.movers[key] then CUI.movers[key].cysShift = 0 end
            -- the Cooldown Manager re-places its stance icon (also mid-fight): pin it back straight away
            if key == "cooldowns_stance" then AttachStance() end
            if key == "player" or key == "target" or (type(key) == "string" and key:find("^cooldowns_")) then QueueKeepClear() end
        end)
        if CUI.ApplyLayoutFilter then hooksecurefunc(CUI, "ApplyLayoutFilter", QueueKeepClear) end
        for _, key in ipairs({ "player", "target" }) do
            local f = UF.frames[key]
            if f then f:HookScript("OnSizeChanged", QueueKeepClear) end
        end
    end
    -- Cys's Cooldown bars are built a little after login
    for _, t in ipairs({ 0.5, 2, 5, 10, 20 }) do
        C_Timer.After(t, function() WatchBars(); QueueKeepClear() end)
    end
end)

CUI:RegisterPage("Unit Frames", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Look", width):SetPoint("TOPLEFT", 0, -4)

    local colors = W.Checkbox(page, "Class and reaction colored health bars", function() return db.classColors end,
        function(on) db.classColors = on; for _, f in pairs(UF.frames) do if UnitExists(f.unit) then UF:Update(f) end end end)
    colors:SetPoint("TOPLEFT", 4, -34)

    local textBtn = W.Dropdown(page, 230, { { "both", "value and percent" }, { "value", "value" }, { "percent", "percent" } },
        function() return db.healthText end,
        function(v)
            db.healthText = v
            for _, f in pairs(UF.frames) do if UnitExists(f.unit) then UF:Update(f) end end
        end, "Health text: ")
    textBtn:SetPoint("TOPLEFT", 4, -66)

    local manaBtn = W.Dropdown(page, 230, { { "current", "current" }, { "valuepct", "value and percent" }, { "both", "current / max" }, { "percent", "percent" }, { "off", "off" } },
        function() return db.manaText or "current" end,
        function(v)
            db.manaText = v
            for _, f in pairs(UF.frames) do if f.powerText and UnitExists(f.unit) then UF:Update(f) end end
        end, "Mana number (player): ")
    manaBtn:SetPoint("TOPLEFT", 4, -98)

    local rfade = W.Checkbox(page, "Fade party members who are out of range", function() return db.rangeFade ~= false end,
        function(on) db.rangeFade = on end)
    rfade:SetPoint("TOPLEFT", 4, -156)
    local rtext = W.Checkbox(page, "Show a rough distance on a player you target (10 / 28 / 28+ yd)", function() return db.targetRange ~= false end,
        function(on) db.targetRange = on end)
    rtext:SetPoint("TOPLEFT", 4, -182)

    local blue = W.Checkbox(page, "Blue Shamans instead of pink (turning off needs a /reload)",
        function() return CysUIDB.blueShaman end,
        function(on)
            CysUIDB.blueShaman = on and true or false
            if on then
                CUI:ApplyShamanColor()
                for _, f in pairs(UF.frames) do if UnitExists(f.unit) then UF:Update(f) end end
            else
                CUI:Print("Shamans go back to pink after a /reload.")
            end
        end)
    blue:SetPoint("TOPLEFT", 4, -130)
    if CysUICompat and CysUICompat.isForever then blue:Hide() end -- Shamans are already blue on WoW Forever

    W.Header(page, "Which frames (needs a /reload)", width):SetPoint("TOPLEFT", 0, -222)
    local y = -252
    for _, row in ipairs({ { "player", "Player" }, { "target", "Target (with buffs, debuffs, combo points)" },
                           { "targettarget", "Target of target" }, { "pet", "Pet" }, { "focus", "Focus (WoW Forever; /focus sets it)" },
                           { "party", "Party" } }) do
        local cb = W.Checkbox(page, row[2], function()
            if row[1] == "focus" then return db.focus ~= false end
            return db[row[1]]
        end, function(on) db[row[1]] = on and true or false end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    local combat = W.Checkbox(page, "Show a combat icon on the player frame", function() return db.combatIcon ~= false end,
        function(on) db.combatIcon = on and true or false; if UF.ApplyCombatIcon then UF.ApplyCombatIcon() end end)
    combat:SetPoint("TOPLEFT", 4, y - 4)
    y = y - 30
    local corner = W.Checkbox(page, "Small names in the top-left corner (player and target)", function() return db.nameCorner ~= false end,
        function(on) db.nameCorner = on and true or false; UF.ApplyNameStyle() end)
    corner:SetPoint("TOPLEFT", 4, y - 4)
    y = y - 28
    local nameSize = W.Stepper(page, "Corner name size", function() return db.nameSize or 10 end,
        function(v) db.nameSize = v; UF.ApplyNameStyle() end, 7, 14, 1)
    nameSize:SetPoint("TOPLEFT", 24, y - 4)
    y = y - 30
    local function RefreshAll() for _, f in pairs(UF.frames) do if UnitExists(f.unit) then UF:Update(f) end end end
    for _, row in ipairs({
        { "nameCornerSmall", "Corner names on target of target, pet and party too", UF.ApplyNameStyle },
        { "eliteTag", "Elite / Rare / Boss tag beside the name", RefreshAll },
        { "targetAccent", "Gold accent and soft glow along the top of the target frame", function() UF.ApplyTargetAccent() end },
        { "leaderIcon", "Crown beside the group leader (player and party frames)", function() UF.UpdateLeaders() end },
    }) do
        local cb = W.Checkbox(page, row[2], function() return db[row[1]] ~= false end,
            function(on) db[row[1]] = on and true or false; row[3]() end)
        cb:SetPoint("TOPLEFT", 4, y - 4)
        y = y - 26
    end
    local function Repaint()
        for _, f in pairs(UF.frames) do
            if f.health then f.health.cysPaint = nil end
            if f.power then f.power.cysPaint = nil end
        end
        RefreshAll(); UF.RefreshPartyPreview()
    end
    local styleBtn = W.Dropdown(page, 340, {
            { "gradient", "Gradient (modern, default)" }, { "dark", "Dark (flat, deep colors)" }, { "bright", "Bright (flat class colors)" } },
        function() return HealthStyle() end,
        function(v) db.healthStyle = v; Repaint() end, "Health bar look: ")
    styleBtn:SetPoint("TOPLEFT", 4, y - 6)
    y = y - 34
    local ppBtn = W.Dropdown(page, 340, {
            { "auto", "hide while Cys's Resource Bar is on" }, { "show", "always show" }, { "hide", "always hide" } },
        function() return db.playerPower or "auto" end,
        function(v) db.playerPower = v; UF.ApplyPlayerPower() end, "Player power bar: ")
    ppBtn:SetPoint("TOPLEFT", 4, y - 6)
    y = y - 34
    y = y - 4
    local auraSize = W.Stepper(page, "Target buff and debuff icon size", function() return db.auraSize or 24 end,
        function(v) db.auraSize = v; UF.RebuildAuras() end, 16, 40, 2, " px")
    auraSize:SetPoint("TOPLEFT", 4, y - 10)
    y = y - 40

    local clearCb = W.Checkbox(page, "Keep player and target frames clear of the cooldown bars",
        function() return db.keepClear ~= false end,
        function(on) db.keepClear = on and true or false; UF.KeepClear() end)
    clearCb:SetPoint("TOPLEFT", 4, y)
    y = y - 26
    local stanceCb = W.Checkbox(page, "Pin the stance icon above the player frame",
        function() return db.stanceAttach end,
        function(on) db.stanceAttach = on and true or false; UF.KeepClear() end)
    stanceCb:SetPoint("TOPLEFT", 4, y)
    y = y - 30

    W.Header(page, "Party (for healers)", width):SetPoint("TOPLEFT", 0, y - 8)
    y = y - 38
    local sortCb = W.Checkbox(page, "Order party frames tank, healer, then damage", function() return db.partySort ~= false end,
        function(on) db.partySort = on and true or false; if UF.LayoutParty then UF.LayoutParty() end end)
    sortCb:SetPoint("TOPLEFT", 4, y)
    y = y - 26
    local function PartyRefresh() for i = 1, 4 do local pf = UF.frames["party" .. i]; if pf then UF:Update(pf) end end end
    for _, row in ipairs({
        { "partyManaOnly", "Power bars for mana users only (no rage / energy)" },
        { "partyDebuffs", "Show debuffs beside each party member" },
        { "partyDispel", "Color the outline by debuff type" },
        { "partyDispelOnly", "Only outline debuffs I can remove" },
    }) do
        local cb = W.Checkbox(page, row[2], function() return db[row[1]] ~= false end,
            function(on) db[row[1]] = on and true or false; PartyRefresh(); UF.RefreshPartyPreview() end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    local ptest = W.Button(page, 240, 22, "Preview a full party (on / off)")
    ptest:SetPoint("TOPLEFT", 4, y - 4)
    ptest:SetScript("OnClick", function() UF.PartyTest() end)
    y = y - 32

    local note = W.Notes(page, 4, y - 52, width, "", {
            "Frames can only be moved or resized out of combat.",
            "Clear of the cooldown bars: if a Cys Cooldown bar runs into the player or target frame, the frame (and its layout box) slides outward, same size, until there is a small gap; it goes back when the bar gets narrower.",
            "Raid frames have their own page (Raid Frames).",
            "Party outline colors: blue Magic, purple Curse, brown Disease, green Poison.",
            "Only debuffs I can remove goes by the cures you have learned (warlocks: Felhunter out).",
            "A frame you untick keeps Blizzard's version.",
            "If anything looks wrong, untick Unit Frames under Modules and reload: the game's own frames come straight back.",
        })
end)
