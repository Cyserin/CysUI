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

local function UnitColor(unit)
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return 0.5, 0.5, 0.5 end -- dead beats class color
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    if UnitIsTapDenied and UnitIsTapDenied(unit) and not UnitPlayerControlled(unit) then return 0.5, 0.5, 0.5 end
    local reaction = UnitReaction(unit, "player")
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
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if a then return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime end
        return
    end
    local name, icon, count, debuffType, duration, expirationTime = UnitAura(unit, index, filter)
    return name, icon, count, debuffType, duration, expirationTime
end

local AURA_SIZE, AURA_COLUMNS, AURA_ROWS = 20, 8, 2

local function MakeAura(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(AURA_SIZE, AURA_SIZE)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetPoint("TOPLEFT", 1, -1)
    a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    a.edges = W.Border(a, 1, T.line, "OVERLAY")
    a.count = a:CreateFontString(nil, "OVERLAY")
    a.count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    a.count:SetPoint("BOTTOMRIGHT", 1, 0)
    a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cd:SetAllPoints(a.icon)
    if a.cd.SetDrawEdge then a.cd:SetDrawEdge(false) end
    a:EnableMouse(true)
    a:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        pcall(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.index, self.filter)
        GameTooltip:Show()
    end)
    a:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return a
end

local function UpdateAuras(f)
    if not f.auras then return end
    local unit = f.unit
    local pools = f.auras
    local rowShift = 0
    for _, kind in ipairs({ "HARMFUL", "HELPFUL" }) do
        local pool = pools[kind]
        local shown = 0
        if UnitExists(unit) then
            for i = 1, 40 do
                if shown >= AURA_COLUMNS * AURA_ROWS then break end
                local name, icon, count, debuffType, duration, expiration = GetAura(unit, i, kind)
                if not name then break end
                shown = shown + 1
                local a = pool[shown]
                if not a then a = MakeAura(f); pool[shown] = a end
                a.unit, a.index, a.filter = unit, i, kind
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
                    a:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * (AURA_SIZE + 2), -(4 + (rowShift + row) * (AURA_SIZE + 2)))
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
    f.health:SetMinMaxValues(0, max(mx, 1))
    f.health:SetValue(cur)

    -- Incoming heals: a segment that starts where the health fill ends and only covers missing health;
    -- anything beyond max health shows as a small sliver past the frame's edge.
    if f.healTex then
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

local function UpdatePower(f)
    if not f.power then return end
    local unit = f.unit
    if not UnitExists(unit) then return end
    local mx = UnitPowerMax(unit)
    f.power:SetMinMaxValues(0, max(mx, 1))
    f.power:SetValue(UnitPower(unit))
    local r, g, b = PowerColor(unit)
    f.power:SetStatusBarColor(r, g, b)

    -- number on the mana bar (player only; Settings > Unit Frames)
    if f.powerText then
        local mode = DB().manaText or "current"
        local cur = UnitPower(unit)
        if mode == "off" or mx <= 0 then
            f.powerText:SetText("")
        elseif mode == "both" then
            f.powerText:SetText(cur .. " / " .. mx)
        elseif mode == "percent" then
            f.powerText:SetText(format("%d%%", floor(cur / mx * 100 + 0.5)))
        else
            f.powerText:SetText(tostring(cur))
        end
    end

    -- Cast cost preview (player only): a white segment at the end of the bar covering the mana the spell being cast will use
    if f.costTex then
        local cost = 0
        if unit == "player" and UnitCastingInfo then
            local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitCastingInfo, "player")
            if ok and name then
                if not spellID and GetSpellInfo then
                    local _, _, _, _, _, _, id = GetSpellInfo(name)
                    spellID = id
                end
                if spellID and GetSpellPowerCost then
                    local okc, costs = pcall(GetSpellPowerCost, spellID)
                    if okc and type(costs) == "table" then
                        local pt = UnitPowerType(unit)
                        for _, c in ipairs(costs) do
                            if c.type == pt and (c.cost or 0) > 0 then cost = c.cost break end
                        end
                    end
                end
            end
        end
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
    local levelText = (level and level > 0) and tostring(level) or "??"
    local class = UnitClassification and UnitClassification(unit)
    if class == "elite" or class == "worldboss" or class == "rareelite" then levelText = levelText .. "+" end
    f.name:SetText(format("|cFFFFD100%s|r %s", levelText, UnitName(unit) or ""))
end

function UF:Update(f)
    local unit = f.unit
    if not UnitExists(unit) then return end
    local r, g, b = UnitColor(unit)
    if not DB().classColors then r, g, b = T.accent[1], T.accent[2], T.accent[3] end
    f.health:SetStatusBarColor(r, g, b)
    UpdateName(f)
    UpdateHealth(f)
    UpdatePower(f)
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
    UpdateAuras(f)
    UpdateCombo(f)
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
    f:SetAttribute("*type2", "menu")
    f:RegisterForClicks("AnyUp", "AnyDown")
    f.noHealthText = def.noHealthText

    -- body
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    f.edges = W.Border(f, 1, T.border, "BORDER")

    if def.power then
        f.power = CreateFrame("StatusBar", nil, f)
        f.power:SetStatusBarTexture(FLAT)
        f.power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.power:SetHeight(def.powerH or 7)
        W.Texture(f.power, "BACKGROUND", { T.field[1], T.field[2], T.field[3], 1 }):SetAllPoints()
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
    W.Texture(f.health, "BACKGROUND", { T.field[1], T.field[2], T.field[3], 1 }):SetAllPoints()

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

    -- text lives on a frame above the bars
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f.healthText = overlay:CreateFontString(nil, "OVERLAY")
    f.healthText:SetFont(STANDARD_TEXT_FONT, def.fontSize or 11, "OUTLINE")
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", -5, 0)
    if def.powerH and f.power then
        f.powerText = overlay:CreateFontString(nil, "OVERLAY")
        f.powerText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
    end
    f.name = overlay:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(STANDARD_TEXT_FONT, def.fontSize or 11, "OUTLINE")
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
        if not (ev == "UNIT_AURA" and not def.auras) and not (ev == "UNIT_TARGET" and def.unit ~= "targettarget") then
            local unit = (ev == "UNIT_TARGET") and "target" or def.unit
            pcall(f.RegisterUnitEvent, f, ev, unit)
        end
    end
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE" }) do pcall(f.RegisterEvent, f, ev) end
    if def.unit == "target" or def.unit == "targettarget" then pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED") end
    if def.combo then pcall(f.RegisterEvent, f, "PLAYER_COMBO_POINTS") end
    if def.unit == "pet" then pcall(f.RegisterEvent, f, "UNIT_PET") end
    if def.unit == "player" and def.power then
        for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
                              "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED" }) do
            pcall(f.RegisterUnitEvent, f, ev, "player")
        end
    end
    if def.party then pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE") end
    f:SetScript("OnEvent", function(self) UF:Update(self) end)

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
}

local BLIZZARD = {
    player = { "PlayerFrame" },
    target = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    pet = { "PetFrame" },
    party = { "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "PartyFrame" },
}

-- Park Blizzard's frame somewhere it can never come back (we're out of combat at login).
local function HideBlizzard(key)
    for _, name in ipairs(BLIZZARD[key] or {}) do
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
            for i, pf in ipairs(UF.party) do
                pf:SetSize(w, mh)
                pf:ClearAllPoints()
                pf:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -(i - 1) * (mh + 6))
            end
        end })
    for i = 1, 4 do
        local f = CreateUnitFrame({ unit = "party" .. i, name = "CysUIPartyFrame" .. i, w = 180, h = 38, power = true,
            fontSize = 10, party = true })
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * 44)
        -- a party, not a raid: shown while that party member exists
        RegisterStateDriver(f, "visibility", format("[group:raid] hide; [@party%d,exists] show; hide", i))
        UF.party[i] = f
        UF.frames["party" .. i] = f
    end
    HideBlizzard("party")
end

function UF.Enable()
    if InCombatLockdown() then
        CUI:Print("|cFFFF9F43Unit Frames: can't start in combat. Reload out of combat.|r")
        return
    end
    local db = DB()
    for key in pairs(DEFS) do
        if db[key] then
            local ok, err = pcall(Build, key)
            if not ok then CUI:Print("|cFFFF9F43Unit Frames: " .. key .. " skipped (" .. tostring(err) .. ")|r") end
        end
    end
    if db.party then
        local ok, err = pcall(BuildParty)
        if not ok then CUI:Print("|cFFFF9F43Unit Frames: party skipped (" .. tostring(err) .. ")|r") end
    end
    UF.StartRangeCheck()
end

-- party members out of range fade; a player you target shows a rough distance
function UF.StartRangeCheck()
    if UF.rangeTicker then return end
    UF.rangeTicker = C_Timer.NewTicker(0.4, function()
        local db = DB()
        for unit, f in pairs(UF.frames) do
            if f.IsShown and f:IsShown() then
                local alpha = 1
                if db.rangeFade ~= false and unit:find("^party") and UnitExists(unit) and UnitInRange then
                    local inRange, checked = UnitInRange(unit)
                    if checked and not inRange then alpha = 0.45 end
                end
                if f.cysRangeAlpha ~= alpha then f.cysRangeAlpha = alpha; f:SetAlpha(alpha) end
            end
        end
        local tf = UF.frames.target
        if tf and tf:IsShown() then
            if not tf.rangeText then
                tf.rangeText = tf.healthText:GetParent():CreateFontString(nil, "OVERLAY")
                tf.rangeText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                tf.rangeText:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", -5, 3)
                tf.rangeText:SetTextColor(0.75, 0.75, 0.75)
            end
            local txt = ""
            if db.targetRange ~= false and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
                and not UnitIsDead("target") and CheckInteractDistance then
                if CheckInteractDistance("target", 3) then txt = "10 yd"
                elseif CheckInteractDistance("target", 1) then txt = "28 yd"
                else txt = "28+ yd" end
            end
            tf.rangeText:SetText(txt)
        end
    end)
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

    local manaBtn = W.Dropdown(page, 230, { { "current", "current" }, { "both", "current / max" }, { "percent", "percent" }, { "off", "off" } },
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

    local blue = W.Checkbox(page, "Blue Shamans instead of pink (everywhere; turning off needs a /reload)",
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

    W.Header(page, "Which frames (needs a /reload)", width):SetPoint("TOPLEFT", 0, -222)
    local y = -252
    for _, row in ipairs({ { "player", "Player" }, { "target", "Target (with buffs, debuffs, combo points)" },
                           { "targettarget", "Target of target" }, { "pet", "Pet" }, { "party", "Party" } }) do
        local cb = W.Checkbox(page, row[2], function() return db[row[1]] end, function(on) db[row[1]] = on end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end

    local move = W.Button(page, 240, 22, "Move and resize (layout mode)")
    move:SetPoint("TOPLEFT", 4, y - 14)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local note = W.Notes(page, 4, y - 52, width, "", {
            "Frames can only be moved or resized out of combat.",
            "Raid frames have their own page (Raid Frames).",
            "A frame you untick keeps Blizzard's version.",
            "If anything looks wrong, untick Unit Frames under Modules and reload: the game's own frames come straight back.",
        })
end)
