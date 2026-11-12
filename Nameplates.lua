--------------------------------------------------------------------------------
-- Cys's UI - Nameplates
--
-- Draws our own flat nameplates on top of the game's. The game still creates, positions
-- and recycles the plates (so distance, stacking and the V / Shift+V toggles all keep
-- working); we hide its art and show ours:
--
--   * flat health bar colored by class / reaction, with the target in a gold frame
--   * name (with level) above, health percent inside
--   * "mob is on you" coloring (DPS mode: orange when it's hitting you;
--     Tank mode: green while you hold it, orange when it's loose)
--   * your own debuffs on the mob (handy for DoTs), a small cast bar, raid markers
--
-- Plates are made with Blizzard's own plate frames as the parent, so they show and hide
-- with them. If anything looks wrong, untick Nameplates under /cui > Modules and reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min
local Secret, Guard = CysUICompat.Secret, CysUICompat.Guard -- WoW Forever locked values (no-ops on Era)

local NP = {}
CUI.Nameplates = NP
NP.plates = {} -- Blizzard plate frame -> our plate

local FLAT = "Interface\\Buttons\\WHITE8X8"
local function DB() return CysUIDB.nameplates end

local PLATE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_AURA", "UNIT_TARGET",
                       "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
                      "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                      "UNIT_SPELLCAST_CHANNEL_STOP" }

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------
local function BaseColor(unit)
    if UnitIsPlayer(unit) and DB().classColors then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return 0.5, 0.5, 0.5 end
    if UnitIsTapDenied and UnitIsTapDenied(unit) and not UnitPlayerControlled(unit) then return 0.55, 0.55, 0.55 end
    local reaction = UnitReaction(unit, "player")
    if not reaction then return 0.8, 0.8, 0.8 end
    if reaction <= 2 then return 0.85, 0.2, 0.2 end
    if reaction <= 4 then return 1, 0.82, 0 end
    return 0.3, 0.85, 0.4
end

-- Does this mob have you? The threat API isn't on every Classic client, so when it's
-- missing we fall back to "is the mob targeting me".
local function HasAggro(unit)
    -- on Forever both answers can be locked in combat (never test those): then no aggro color this time
    if UnitThreatSituation then
        local ok, status = pcall(UnitThreatSituation, "player", unit)
        if ok and Secret(status) then return false end
        if ok and type(status) == "number" then return status >= 2 end
    end
    local okE, exists = pcall(UnitExists, unit .. "target")
    if not okE or Secret(exists) or not exists then return false end
    local okU, me = pcall(UnitIsUnit, unit .. "target", "player")
    if not okU or Secret(me) then return false end
    return me and true or false
end

-- Which role are you playing right now? Classic has no role API, so it is read from what you are doing:
-- Defensive Stance, Bear Form, Righteous Fury, or a shield with an Enhancement build.
local function TalentPoints(tab)
    if not GetTalentTabInfo then return 0 end
    local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
    if not ok then return 0 end
    if type(a) == "number" then return tonumber(e) or 0 end -- newer clients put an id first
    return tonumber(c) or 0
end
local function HasBuffNamed(spellID)
    local want = GetSpellInfo and GetSpellInfo(spellID)
    if not want then return false end
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == want then return true end
    end
    return false
end
-- Shaman tanks (Earth Warden) keep Rockbiter Weapon on: read the main-hand weapon's tooltip for it
local _, playerClass = UnitClass("player")
local rbScan
local function HasRockbiter()
    if playerClass ~= "SHAMAN" or not GetWeaponEnchantInfo then return false end
    local hasMain = GetWeaponEnchantInfo()
    if not hasMain then return false end
    local want = (GetSpellInfo and GetSpellInfo(8017)) or "Rockbiter" -- Rockbiter Weapon, in your game's language
    want = want:gsub(" Weapon$", "")
    -- newer clients (WoW Forever): tooltip data without a tooltip frame
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 16)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                local t = line.leftText
                if type(t) == "string" and t:find(want, 1, true) then return true end
            end
            return false
        end
    end
    if not rbScan then rbScan = CreateFrame("GameTooltip", "CysUINameplateRBScan", nil, "GameTooltipTemplate") end
    rbScan:SetOwner(UIParent, "ANCHOR_NONE")
    rbScan:ClearLines()
    rbScan:SetInventoryItem("player", 16)
    for i = 1, rbScan:NumLines() do
        local fs = _G["CysUINameplateRBScanTextLeft" .. i]
        local t = fs and fs:GetText()
        if type(t) == "string" and t:find(want, 1, true) then rbScan:Hide() return true end
    end
    rbScan:Hide()
    return false
end

local function DetectRole()
    -- 1. the role you picked for your group (Group Finder / right-click a party member > Set Role)
    local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if r == "TANK" then return "tank", "your group role is Tank" end
    -- 2. a Shaman with Rockbiter Weapon on is tanking (unless you set Damage or Healer for the group)
    if r ~= "DAMAGER" and r ~= "HEALER" and HasRockbiter() then return "tank", "Rockbiter Weapon is on" end
    if r == "DAMAGER" or r == "HEALER" then return "dps", "your group role is " .. (r == "HEALER" and "Healer" or "Damage") end
    return "dps", "no group role set"
end
function NP.RefreshRole()
    local role, why = DetectRole()
    local changed = NP.autoRole ~= role
    NP.autoRole, NP.autoWhy = role, why
    if changed and NP.ApplyAll and CysUIDB and CysUIDB.nameplates and CysUIDB.nameplates.threat == "auto" then NP:ApplyAll() end
end
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED",
                         "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ACTIVE_TALENT_GROUP_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
    ev:SetScript("OnEvent", function() pcall(NP.RefreshRole) end)
    -- also look now and then, so switching your Upgrade profile is picked up too
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(3, function() pcall(NP.RefreshRole) end) end
end

local function ThreatColor(unit)
    local mode = DB().threat
    if mode == "auto" then mode = NP.autoRole or "dps" end
    if mode == "off" then return end
    if not UnitAffectingCombat("player") or not UnitCanAttack("player", unit) or not UnitAffectingCombat(unit) then return end
    local aggro = HasAggro(unit)
    if mode == "dps" then
        if aggro then return 1, 0.5, 0 end -- it's on you
    else
        if aggro then return 0.3, 0.85, 0.4 end -- you're holding it
        return 1, 0.5, 0 -- loose
    end
end

--------------------------------------------------------------------------------
-- Auras (your own debuffs)
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

local MAX_AURAS = 5

local function NewPlateAura(p)
    local a = CreateFrame("Frame", nil, p)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetPoint("TOPLEFT", 1, -1)
    a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    a.edges = W.Border(a, 1, { 0, 0, 0, 1 }, "OVERLAY")
    a.count = a:CreateFontString(nil, "OVERLAY")
    a.count:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    a.count:SetPoint("BOTTOMRIGHT", 1, 0)
    a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cd:SetAllPoints(a.icon)
    if a.cd.SetDrawEdge then a.cd:SetDrawEdge(false) end
    CysUICompat.SmallCooldownText(a.cd, 18)
    return a
end

local function UpdateAuras(p)
    local db = DB()
    local shown = 0
    -- WoW Forever: whether you can attack a nameplate unit can be locked in combat; the "only my debuffs" filter
    -- below already keeps friendly plates empty, so a locked answer counts as yes
    local attackable = UnitCanAttack("player", p.unit)
    local mine = db.myDebuffs and (Secret(attackable) or attackable)
    -- WoW Forever: your debuffs on the mob are locked in combat; draw them from aura instance IDs instead
    local list = mine and CysUICompat.AuraIcons(p.unit, "HARMFUL|PLAYER", MAX_AURAS)
    if list then
        for _, e in ipairs(list) do
            if shown >= MAX_AURAS then break end
            shown = shown + 1
            local a = p.auras[shown] or NewPlateAura(p)
            p.auras[shown] = a
            local size = db.debuffSize or 20
            a:SetSize(size, size)
            CysUICompat.ShowAuraIcon(a, e)
            CysUICompat.SmallCooldownText(a.cd, size)
            a:ClearAllPoints()
            a:SetPoint("BOTTOMLEFT", p, "TOPLEFT", (shown - 1) * (size + 2), 16)
            a:Show()
        end
    elseif mine then
        for i = 1, 40 do
            if shown >= MAX_AURAS then break end
            local name, icon, count, _, duration, expiration = GetAura(p.unit, i, "HARMFUL|PLAYER")
            if not name then break end
            shown = shown + 1
            local a = p.auras[shown]
            if not a then
                a = CreateFrame("Frame", nil, p)
                a.icon = a:CreateTexture(nil, "ARTWORK")
                a.icon:SetPoint("TOPLEFT", 1, -1)
                a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                a.edges = W.Border(a, 1, { 0, 0, 0, 1 }, "OVERLAY")
                a.count = a:CreateFontString(nil, "OVERLAY")
                a.count:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                a.count:SetPoint("BOTTOMRIGHT", 1, 0)
                a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
                a.cd:SetAllPoints(a.icon)
                if a.cd.SetDrawEdge then a.cd:SetDrawEdge(false) end
                CysUICompat.SmallCooldownText(a.cd, a:GetHeight() > 0 and a:GetHeight() or 18)
                p.auras[shown] = a
            end
            local size = db.debuffSize or 20
            a:SetSize(size, size)
            a.icon:SetTexture(icon)
            a.count:SetText((count and count > 1) and count or "")
            if duration and duration > 0 and expiration then
                a.cd:SetCooldown(expiration - duration, duration)
                a.cd:Show()
            else
                a.cd:Hide()
            end
            a:ClearAllPoints()
            a:SetPoint("BOTTOMLEFT", p, "TOPLEFT", (shown - 1) * (size + 2), 16)
            a:Show()
        end
    end
    for i = shown + 1, #p.auras do p.auras[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Cast bar
--------------------------------------------------------------------------------
local function CastOnUpdate(bar)
    local now = GetTime()
    local total = bar.endT - bar.startT
    if total <= 0 then return end
    local progress = bar.channel and (bar.endT - now) or (now - bar.startT)
    bar:SetMinMaxValues(0, total)
    bar:SetValue(max(0, min(total, progress)))
    if bar.time:IsShown() then bar.time:SetFormattedText("%.1f", max(0, bar.endT - now)) end
end

-- WoW Forever: a locked cast's time left, written by the game's own number (no math on it), ten times a second
local function LockedTimeOnUpdate(bar, elapsed)
    bar.tAcc = (bar.tAcc or 0) + elapsed
    if bar.tAcc < 0.1 then return end
    bar.tAcc = 0
    CysUICompat.LockedCastTime(bar.time, bar.lockedDur)
end

-- cast colored by your interrupt (Kick.lua): grey on cooldown, a tick where it comes ready, green when it is up
local function KickApply(bar, unit, info)
    local K = CUI.Kick
    if K and DB().kickCast ~= false then K.Apply(bar, unit, info) end
end

local function UpdateCast(p)
    local bar = p.cast
    if CUI.Kick then CUI.Kick.Clear(bar) end
    if not DB().castBar then bar:Hide(); bar:SetScript("OnUpdate", nil); return end
    bar.time:SetShown(DB().castTime ~= false)
    bar.time:SetText("")
    local unit = p.unit
    local name, _, texture, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    -- WoW Forever: other units' casts are locked, so the bar runs off the game's own cast timer
    local function Locked() return Secret(name) or Secret(startMS) or Secret(endMS) end
    if Locked() or (name == nil and CysUICompat.LockedCast(unit)) then
        local kind, lname, ltex, dur = CysUICompat.LockedCast(unit)
        bar:SetScript("OnUpdate", nil)
        if not kind then bar:Hide(); return end
        bar.icon:SetTexture(ltex)
        bar.text:SetText(lname)
        if kind == "channel" then bar:SetStatusBarColor(0.3, 0.6, 1) else bar:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3]) end
        CysUICompat.RunLockedCastBar(bar, kind, dur)
        bar.lockedDur, bar.tAcc = dur, 1
        if dur and bar.time:IsShown() then bar:SetScript("OnUpdate", LockedTimeOnUpdate) end
        bar:Show()
        KickApply(bar, unit, { dur = dur, channel = kind == "channel" })
        return
    end
    if not name then
        name, _, texture, startMS, endMS = UnitChannelInfo(unit)
        if Locked() then bar:Hide(); bar:SetScript("OnUpdate", nil); return end
        channel = name ~= nil
    end
    if name and startMS and endMS then
        bar.startT, bar.endT, bar.channel = startMS / 1000, endMS / 1000, channel
        bar.icon:SetTexture(texture)
        bar.text:SetText(name)
        if channel then bar:SetStatusBarColor(0.3, 0.6, 1) else bar:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3]) end
        bar:Show()
        bar:SetScript("OnUpdate", CastOnUpdate)
        CastOnUpdate(bar)
        KickApply(bar, unit, { startT = bar.startT, endT = bar.endT, channel = channel })
    else
        bar:Hide()
        bar:SetScript("OnUpdate", nil)
    end
end
UpdateCast = Guard("Nameplate cast bar", UpdateCast)

--------------------------------------------------------------------------------
-- A plate
--------------------------------------------------------------------------------
function NP:ApplySize(p)
    local db = DB()
    p:SetSize(db.width, db.height)
    p.name:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    p.level:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    p.healthText:SetFont(STANDARD_TEXT_FONT, max(db.height - 3, 7), "OUTLINE")
    local ch = max(floor(db.height * 0.8), 8)
    p.cast:SetHeight(ch)
    p.cast.icon:SetSize(ch + 2, ch + 2)
    -- name on the left and level on the right above the bar, or both centred (the older look)
    p.name:ClearAllPoints()
    if db.nameStyle == "center" then
        p.name:SetPoint("BOTTOM", p, "TOP", 0, 3)
        p.name:SetWidth(180)
        p.name:SetJustifyH("CENTER")
        p.level:Hide()
    else
        p.name:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, 3)
        p.name:SetWidth(max(db.width - 28, 30))
        p.name:SetJustifyH("LEFT")
        p.level:Show()
    end
    -- the gold side marks stand a little off the bar, as tall as the bar plus a bit
    for _, m in ipairs(p.marks) do m:SetHeight(db.height + 6) end
end

-- a thin gold bracket beside the plate: [ on the left, ] on the right
local function Bracket(p, parent, side)
    local m = CreateFrame("Frame", nil, parent)
    m:SetWidth(4)
    if side == "left" then m:SetPoint("RIGHT", p, "LEFT", -2, 0) else m:SetPoint("LEFT", p, "RIGHT", 2, 0) end
    local edge = side == "left" and "LEFT" or "RIGHT"
    local v = W.Texture(m, "OVERLAY", T.accent)
    v:SetPoint("TOP" .. edge, 0, 0); v:SetPoint("BOTTOM" .. edge, 0, 0); v:SetWidth(2)
    local t = W.Texture(m, "OVERLAY", T.accent)
    t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0); t:SetHeight(2)
    local b = W.Texture(m, "OVERLAY", T.accent)
    b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(2)
    m.parts = { v, t, b }
    m:Hide()
    return m
end

local function CreatePlate(base)
    local p = CreateFrame("Frame", nil, base)
    p.base = base
    p:SetPoint("CENTER", base, "CENTER", 0, 0)
    p.border = W.Border(p, 1, { 0, 0, 0, 1 }, "BORDER")
    W.Texture(p, "BACKGROUND", { 0, 0, 0, 0.7 }):SetAllPoints()

    p.health = CreateFrame("StatusBar", nil, p)
    p.health:SetStatusBarTexture(FLAT)
    p.health:SetPoint("TOPLEFT", 1, -1)
    p.health:SetPoint("BOTTOMRIGHT", -1, 1)

    local overlay = CreateFrame("Frame", nil, p)
    overlay:SetAllPoints(p)
    overlay:SetFrameLevel(p:GetFrameLevel() + 3)
    p.healthText = overlay:CreateFontString(nil, "OVERLAY")
    p.healthText:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.name = overlay:CreateFontString(nil, "OVERLAY")
    p.name:SetWordWrap(false)
    p.level = overlay:CreateFontString(nil, "OVERLAY")
    p.level:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, 3)
    p.level:SetJustifyH("RIGHT")
    p.marks = { Bracket(p, overlay, "left"), Bracket(p, overlay, "right") }

    p.raid = overlay:CreateTexture(nil, "OVERLAY")
    p.raid:SetSize(16, 16)
    p.raid:SetPoint("RIGHT", p, "LEFT", -9, 0)
    p.raid:Hide()

    -- quest marker: a small sword to the right of the plate (see UpdateQuestMark)
    p.quest = overlay:CreateTexture(nil, "OVERLAY")
    p.quest:SetTexture("Interface\\CURSOR\\Attack")
    p.quest:SetSize(14, 14)
    p.quest:SetPoint("LEFT", p, "RIGHT", 8, 0)
    p.quest:Hide()

    -- cast bar tucked right under the plate
    p.cast = CreateFrame("StatusBar", nil, p)
    p.cast:SetStatusBarTexture(FLAT)
    p.cast:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -1)
    p.cast:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -1)
    W.Texture(p.cast, "BACKGROUND", { 0, 0, 0, 0.7 }):SetAllPoints()
    W.Border(p.cast, 1, { 0, 0, 0, 1 }, "BORDER")
    p.cast.icon = p.cast:CreateTexture(nil, "ARTWORK")
    p.cast.icon:SetPoint("RIGHT", p.cast, "LEFT", -2, 0)
    p.cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.cast.text = p.cast:CreateFontString(nil, "OVERLAY")
    p.cast.text:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    p.cast.text:SetPoint("LEFT", p.cast, "LEFT", 3, 0)
    p.cast.text:SetPoint("RIGHT", p.cast, "RIGHT", -24, 0)
    p.cast.text:SetJustifyH("LEFT")
    p.cast.text:SetWordWrap(false)
    p.cast.time = p.cast:CreateFontString(nil, "OVERLAY")
    p.cast.time:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    p.cast.time:SetPoint("RIGHT", p.cast, "RIGHT", -3, 0)
    p.cast.time:SetJustifyH("RIGHT")
    p.cast:Hide()

    p.auras = {}
    NP:ApplySize(p)

    p:SetScript("OnEvent", function(self, event)
        if event:find("^UNIT_SPELLCAST") then UpdateCast(self) return end
        -- health and threat ticks come often in combat; the debuff icons only need a redraw on aura changes
        self.cysSkipAuras = event ~= "UNIT_AURA" and event ~= "UNIT_FACTION" and event ~= "UNIT_NAME_UPDATE"
        NP:Update(self)
        self.cysSkipAuras = nil
    end)
    return p
end

-- Returns an RGB color table for unit level difficulty relative to the player
local function GetLevelColor(unit)
    local unitLevel = UnitLevel(unit)
    if not unitLevel or unitLevel <= 0 then
        return { 0.8, 0.8, 0.8 } -- Boss / unknown
    end
    local playerLevel = UnitLevel("player") or 1
    local diff = unitLevel - playerLevel

    if diff >= 5 then
        return { 1.0, 0.1, 0.1 }   -- Red (+5 or higher)
    elseif diff >= 3 then
        return { 1.0, 0.5, 0.25 }  -- Orange (+3 to +4)
    elseif diff >= -2 then
        return { 1.0, 0.92, 0.0 }  -- Yellow (-2 to +2)
    else
        local greenRange = GetQuestGreenRange and GetQuestGreenRange() or 5
        if unitLevel <= (playerLevel - greenRange) then
            return { 0.6, 0.6, 0.6 } -- Grey
        end
        return { 0.2, 0.8, 0.2 }     -- Green
    end
end

function NP:Update(p)
    local unit = p.unit
    if not (unit and UnitExists(unit)) then return end
    local db = DB()
    -- WoW Forever: addons can't read the mob's auras in combat, so the game's own debuff row is used instead
    if CysUICompat.isForever then
        -- the game's own debuff row shows your debuffs here (see ShowBlizzardAuras); ours stay hidden
        for i = 1, #p.auras do p.auras[i]:Hide() end
        if p.cysAuraBox then
            local want = db.myDebuffs and MAX_AURAS or 0
            if p.cysAuraCap ~= want then
                p.cysAuraCap = want
                CysUICompat.AuraContainerCap(p.cysAuraBox, "mine", want)
            end
        else
            local af = p.base and p.base.UnitFrame and p.base.UnitFrame.AurasFrame
            if af then pcall(af.SetAlpha, af, db.myDebuffs and 1 or 0) end
        end
    end

    -- keep Blizzard's own plate art invisible
    if p.base.UnitFrame then p.base.UnitFrame:SetAlpha(0) end

    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    -- WoW Forever: other units' health is locked. The bar can still show it; the percent text can't be worked out.
    local locked = Secret(cur) or Secret(mx)
    if locked then
        pcall(p.health.SetMinMaxValues, p.health, 0, mx)
        pcall(p.health.SetValue, p.health, cur)
    else
        p.health:SetMinMaxValues(0, max(mx, 1))
        p.health:SetValue(cur)
    end
    local r, g, b = ThreatColor(unit)
    if not r then r, g, b = BaseColor(unit) end
    p.health:SetStatusBarColor(r, g, b)

    -- health text: percent, value, both or none (older saves: healthText off = none)
    local hm = db.healthMode or (db.healthText == false and "none") or "percent"
    if hm == "none" then
        p.healthText:SetText("")
    elseif locked then
        -- WoW Forever: the game formats the locked numbers itself
        CysUICompat.LockedUnitText(p.healthText, unit, "health", hm == "both" and "valuepct" or hm)
    elseif mx > 0 then
        local pct = mx <= 100 and cur or floor(cur / mx * 100 + 0.5)
        local short = AbbreviateNumbers and AbbreviateNumbers(cur) or tostring(cur)
        if hm == "value" then p.healthText:SetText(short)
        elseif hm == "both" then p.healthText:SetText(format("%s  |cFFFFD100%d%%|r", short, pct))
        else p.healthText:SetText(format("%d%%", pct)) end
    else
        p.healthText:SetText("")
    end

    local name = UnitName(unit)
    if Secret(name) then
        -- WoW Forever: creature names are locked in instances; show the name as it is, without the level in front
        p.name:SetText(name)
        name = nil
    else
        name = name or ""
    end
    local split = db.nameStyle ~= "center"
    if split then
        -- level on the right in its difficulty color, a gold + for elites, Rare for rares, ?? for bosses
        local lt = ""
        if db.showLevel then
            local level = UnitLevel(unit)
            if Secret(level) then level = nil end
            local cls = UnitClassification and UnitClassification(unit)
            if Secret(cls) then cls = nil end
            if level and level > 0 then
                local lc = GetLevelColor(unit)
                lt = format("|cFF%02x%02x%02x%d|r", floor(lc[1] * 255 + 0.5), floor(lc[2] * 255 + 0.5), floor(lc[3] * 255 + 0.5), level)
            else
                lt = "|cFFFF4040??|r"
            end
            if cls == "elite" or cls == "rareelite" then lt = lt .. "|cFFFFD100+|r" end
            if cls == "rare" or cls == "rareelite" then lt = "|cFFC0C8D8Rare|r " .. lt end
        end
        p.level:SetText(lt)
    end
    if name and db.showLevel and not split then
        local level = UnitLevel(unit)
        if level and level > 0 then
            local lc = GetLevelColor(unit)
            local hex = format("%02x%02x%02x", math.floor(lc[1] * 255 + 0.5), math.floor(lc[2] * 255 + 0.5), math.floor(lc[3] * 255 + 0.5))
            name = format("|cFF%s%d|r %s", hex, level, name)
        else
            name = format("|cFFCCCCCC??|r %s", name)
        end
    end
    if name then p.name:SetText(name) end
    local nr, ng, nb = BaseColor(unit)
    p.name:SetTextColor(nr, ng, nb)

    -- the target gets a gold frame, gold side marks and a little extra size; other plates fade a little
    local onTarget = UnitIsUnit(unit, "target")
    if Secret(onTarget) then onTarget = false end
    local isTarget = db.targetHighlight and onTarget
    W.SetBorder(p.border, isTarget and T.accent or { 0, 0, 0, 1 })
    p:SetScale(isTarget and 1.15 or 1)
    local marks = onTarget and db.targetMarks ~= false
    for _, m in ipairs(p.marks) do
        if marks then for _, t in ipairs(m.parts) do t:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1) end end
        m:SetShown(marks)
    end
    local alpha = 1
    if db.fadeOthers ~= false and not onTarget and UnitExists("target") then alpha = (db.fadeAlpha or 70) / 100 end
    p:SetAlpha(alpha)

    local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if index and SetRaidTargetIconTexture then
        p.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(p.raid, index)
        p.raid:Show()
    else
        p.raid:Hide()
    end

    if not CysUICompat.isForever then UpdateAuras(p) end
end
NP.Update = Guard("Nameplates", NP.Update) -- WoW Forever: a locked value skips one update instead of erroring

-- The game fades its own plate in and out (distance, target, combat) by setting its alpha again and again,
-- which let its bar flash through under ours. Keep its alpha at zero for good.
-- Some of its pieces (the mouse-over highlight, the target border) ignore their parent's transparency, so every
-- frame, texture and text inside the game's plate is held at zero on its own as well.
local function Silence(obj, depth, keep)
    if not obj or depth > 5 or obj == keep then return end
    local first = not obj.cysSilenced
    obj.cysSilenced = true
    if obj.SetIgnoreParentAlpha then pcall(obj.SetIgnoreParentAlpha, obj, false) end
    if obj.SetAlpha and not first then pcall(obj.SetAlpha, obj, 0) end
    if obj.SetAlpha and first then
        pcall(obj.SetAlpha, obj, 0)
        local fixing = false
        pcall(hooksecurefunc, obj, "SetAlpha", function(self, a)
            if fixing or a == 0 then return end
            fixing = true
            self:SetAlpha(0)
            fixing = false
        end)
        if obj.SetIgnoreParentAlpha then
            pcall(hooksecurefunc, obj, "SetIgnoreParentAlpha", function(self, on)
                if on then self:SetIgnoreParentAlpha(false) end
            end)
        end
    end
    if obj.GetRegions then
        for _, r in ipairs({ obj:GetRegions() }) do Silence(r, depth + 1, keep) end
    end
    if obj.GetChildren then
        for _, c in ipairs({ obj:GetChildren() }) do Silence(c, depth + 1, keep) end
    end
end

-- WoW Forever: addons can't read other units' auras at all in combat ("Auras cannot be accessed when secret
-- while tainted"), but the game's own plate still draws your debuffs. So on Forever the game's debuff row is
-- left visible on top of our plate instead of being hidden with the rest. Only its transparency is touched.
local function ForeverAuras(uf)
    if not CysUICompat.isForever or CysUICompat.HasAuraContainers() then return nil end -- containers draw our own
    return uf and uf.AurasFrame or nil
end

local function ShowBlizzardAuras(uf)
    local af = ForeverAuras(uf)
    if not af then return end
    if af.SetIgnoreParentAlpha then pcall(af.SetIgnoreParentAlpha, af, true) end
    pcall(af.SetAlpha, af, DB().myDebuffs and 1 or 0)
    if not af.cysAlphaHook then
        af.cysAlphaHook = true
        -- the game's plate fades its pieces; keep the debuff row at the switch's value
        local fixing = false
        pcall(hooksecurefunc, af, "SetAlpha", function(self, a)
            if fixing then return end
            local want = DB().myDebuffs and 1 or 0
            if a == want then return end
            fixing = true
            self:SetAlpha(want)
            fixing = false
        end)
    end
end

local function SilenceBlizzard(base)
    local uf = base.UnitFrame
    if not uf then return end
    Silence(uf, 0, ForeverAuras(uf))
    ShowBlizzardAuras(uf)
    if not uf.cysShowHook and uf.HookScript then
        uf.cysShowHook = true
        uf:HookScript("OnShow", function(self) self:SetAlpha(0) end)
    end
end

function NP.MakeAuraBox(p, unit)
    p.cysAuraBox = CysUICompat.AuraContainer(p, unit, {
        point = { "BOTTOMLEFT", p, "TOPLEFT", 0, 16 },
        anchor = "BOTTOMLEFT", growV = "UP", size = DB().debuffSize or 20, gap = 2, noClicks = true,
        groups = { { key = "mine", filter = "HARMFUL|PLAYER", max = MAX_AURAS } },
    }) or false
    p.cysAuraCap = nil
end

-- the debuff icon size changed: rebuild the containers (they are built at one size)
function NP.RebuildAuras()
    for _, p in pairs(NP.plates) do
        if p.cysAuraBox then
            pcall(p.cysAuraBox.SetEnabled, p.cysAuraBox, false)
            p.cysAuraBox:Hide()
            p.cysAuraBox = nil
        end
        if p.unit and CysUICompat.isForever then NP.MakeAuraBox(p, p.unit) end
        if p.unit then NP:Update(p) end
    end
end

--------------------------------------------------------------------------------
-- Quest marker: a small sword beside the plate of a mob you still need for a quest - a kill objective or one
-- whose drops you are collecting. The game itself knows which mobs those are (it lists the quest in the mob's
-- tooltip), so this asks the game instead of matching names; a finished objective takes the sword away.
-- Asked when a plate appears and when the quest log changes. If the game won't say (locked mid-fight on
-- WoW Forever), the last answer stays.
--------------------------------------------------------------------------------
local LINE = Enum and Enum.TooltipDataLineType or {}
local LINE_OBJECTIVE, LINE_TITLE, LINE_PLAYER = LINE.QuestObjective or 8, LINE.QuestTitle or 17, LINE.QuestPlayer or 18
local function QuestNeededRaw(unit)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        if type(data) == "table" and type(data.lines) == "table" then
            local me = UnitName("player")
            local mine, saw, need = true, false, false
            for _, line in ipairs(data.lines) do
                local kind = line.type
                if kind == LINE_TITLE then
                    saw, mine = true, true
                elseif kind == LINE_PLAYER then
                    mine = line.leftText == me -- in a group the tooltip lists each member's progress
                elseif kind == LINE_OBJECTIVE then
                    saw = true
                    if mine and line.completed ~= true then need = true end
                end
            end
            if saw then return need end
        end
    end
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        return C_QuestLog.UnitIsRelatedToActiveQuest(unit) and true or false
    end
    return nil
end
local function UpdateQuestMark(p)
    local mark = p.quest
    if not mark then return end
    if DB().questMark == false or not p.unit then mark:Hide() return end
    local ok, need = pcall(QuestNeededRaw, p.unit)
    if ok and need ~= nil and not Secret(need) then p.questNeed = need end
    local size = DB().questMarkSize or 14
    mark:SetSize(size, size)
    mark:SetShown(p.questNeed == true)
end
function NP.UpdateQuestMarks()
    for _, p in pairs(NP.plates) do if p.unit then UpdateQuestMark(p) end end
end

function NP:Add(unit)
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base then return end
    SilenceBlizzard(base)
    local p = self.plates[base]
    if not p then
        p = CreatePlate(base)
        self.plates[base] = p
    end
    p.unit = unit
    p.questNeed = nil
    -- WoW Forever: the game fills our debuff icons itself through an aura container (works in combat)
    if CysUICompat.isForever then
        if p.cysAuraBox == nil then
            NP.MakeAuraBox(p, unit)
        else
            CysUICompat.AuraContainerUnit(p.cysAuraBox, unit)
        end
    end
    p:UnregisterAllEvents()
    for _, ev in ipairs(PLATE_EVENTS) do pcall(p.RegisterUnitEvent, p, ev, unit) end
    for _, ev in ipairs(CAST_EVENTS) do pcall(p.RegisterUnitEvent, p, ev, unit) end
    p:Show()
    self:Update(p)
    UpdateCast(p)
    UpdateQuestMark(p)
end

function NP:Remove(unit)
    for _, p in pairs(self.plates) do
        if p.unit == unit then
            p.unit = nil
            p:UnregisterAllEvents()
            p.cast:Hide()
            p.cast:SetScript("OnUpdate", nil)
            p:Hide()
        end
    end
end

function NP:ApplyAll()
    for _, p in pairs(self.plates) do
        self:ApplySize(p)
        if p.unit then self:Update(p) end
    end
end

function NP.Enable()
    -- one-time: threat coloring follows your role by itself unless you pick one
    if not DB().threatAuto then DB().threatAuto = true; DB().threat = "auto" end
    pcall(NP.RefreshRole)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        CUI:Print("|cFFFF9F43Nameplates: this client has no nameplate API, so the module is idle.|r")
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("RAID_TARGET_UPDATE") -- a skull or other marker set or cleared: show it right away
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            NP:Add(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            NP:Remove(unit)
        else
            for _, p in pairs(NP.plates) do if p.unit then NP:Update(p) end end
        end
    end)
    -- quest log changes: ask again which mobs are still needed (many changes in one moment count as one)
    local q = CreateFrame("Frame")
    pcall(q.RegisterEvent, q, "QUEST_LOG_UPDATE")
    pcall(q.RegisterEvent, q, "QUEST_ACCEPTED")
    pcall(q.RegisterEvent, q, "QUEST_REMOVED")
    local queued
    q:SetScript("OnEvent", function()
        if queued then return end
        queued = true
        C_Timer.After(0.3, function() queued = nil; NP.UpdateQuestMarks() end)
    end)
    -- plates that already exist (after a /reload)
    if C_NamePlate.GetNamePlates then
        for _, base in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = base.namePlateUnitToken or (base.UnitFrame and base.UnitFrame.unit)
            if unit then NP:Add(unit) end
        end
    end
end

CUI:RegisterModule({
    key = "nameplates",
    name = "Nameplates",
    addon = "CysUI",
    desc = "Flat nameplates: class and reaction colors, mob-on-you coloring, your debuffs, a small cast bar and a gold target frame.",
    onEnable = NP.Enable,
    open = function() CUI:OpenConfig("Nameplates") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Nameplates", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Nameplates", width):SetPoint("TOPLEFT", 0, -4)

    local y = -34
    local function Check(label, key)
        local cb = W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; NP:ApplyAll() end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    if db.targetMarks == nil then db.targetMarks = true end
    if db.fadeOthers == nil then db.fadeOthers = true end
    if db.castTime == nil then db.castTime = true end
    if not db.healthMode then db.healthMode = db.healthText == false and "none" or "percent" end
    Check("Show the level", "showLevel")
    Check("Class colors for players", "classColors")
    Check("Gold frame and extra size for your target", "targetHighlight")
    Check("Gold side marks on your target", "targetMarks")
    Check("Fade the other plates while you have a target", "fadeOthers")
    Check("Show the time left on casts", "castTime")
    Check("Show my debuffs on the mob", "myDebuffs")
    Check("Show a small cast bar", "castBar")
    if db.kickCast == nil then db.kickCast = true end
    Check("Color enemy casts by your interrupt (grey, green when ready)", "kickCast")
    if db.questMark == nil then db.questMark = true end
    W.Checkbox(page, "Sword beside mobs I still need for a quest (kills and drops)", function() return db.questMark end,
        function(on) db.questMark = on and true or false; NP.UpdateQuestMarks() end):SetPoint("TOPLEFT", 4, y)
    y = y - 26

    -- threat coloring: one row of choices and a line saying what it means right now
    local head = W.Text(page, 12, T.accent)
    head:SetPoint("TOPLEFT", 4, y - 4)
    head:SetText("Threat coloring")
    -- the explanation sits in a box whose height follows the text; wrapped bullet lines hang under their own text
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", 4, y - 52)
    box:SetSize(width, 20)
    local function Line(x, w, color)
        local fs = W.Text(box, 11, color or T.desc)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(3)
        return fs
    end
    local intro = Line(0, width)
    local status = Line(0, width)
    local BULLETS = {
        { "Tank", "green when you hold the mob, orange when it is loose" },
        { "Damage", "orange when a mob is on you" },
        { "Healer", "the same as Damage: healers don't hold threat, so a mob on you is the warning that matters" },
        { "Shaman with Rockbiter Weapon on", "Tank, unless you set Damage or Healer for your group" },
        { "No role set", "the same as Damage" },
    }
    local rows = {}
    for n, b in ipairs(BULLETS) do
        local dot = Line(0, 12, T.accent)
        dot:SetText("•")
        local txt = Line(0, width - 22)
        txt:SetText("|cFFFFD100" .. b[1] .. "|r - " .. b[2])
        rows[n] = { dot = dot, txt = txt }
    end
    local buttons = {}
    local function Describe()
        local m = db.threat
        local role = NP.autoRole or "dps"
        local used = 0
        local function Place(fs, x)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", box, "TOPLEFT", x, -used)
            used = used + (fs:GetStringHeight() or 12) + 4
        end
        for _, r in ipairs(rows) do r.dot:Hide(); r.txt:Hide() end
        status:Hide()
        if m == "auto" then
            intro:SetText("Auto follows the role you set for your group (Group Finder, or right-click yourself in a party and Set Role):")
            Place(intro, 0)
            for _, r in ipairs(rows) do
                r.dot:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -used)
                r.dot:Show(); r.txt:Show()
                Place(r.txt, 20)
            end
            status:SetText("Right now: " .. (role == "tank" and "Tank" or "DPS") .. " (" .. (NP.autoWhy or "") .. ").")
            status:Show()
            Place(status, 0)
        else
            if m == "tank" then intro:SetText("Tank: green when you hold the mob, orange when it is loose.")
            elseif m == "dps" then intro:SetText("DPS: orange when the mob is on you.")
            else intro:SetText("Plates keep their normal colors.") end
            Place(intro, 0)
        end
        box:SetHeight(max(used, 14))
    end
    local function Paint() for key, b in pairs(buttons) do b:SetPrimary(db.threat == key) end Describe() end
    for n, def in ipairs({ { "auto", "Auto" }, { "tank", "Tank" }, { "dps", "DPS" }, { "off", "Off" } }) do
        local b = W.Button(page, 78, 22, def[2])
        b:SetPoint("TOPLEFT", 4 + (n - 1) * 84, y - 24)
        b:SetScript("OnClick", function() db.threat = def[1]; Paint(); NP:ApplyAll() end)
        buttons[def[1]] = b
    end
    NP.RefreshRole()
    Paint()

    -- rows of choices: health text and name layout
    local function Choices(anchor, label, key, defs, fallback)
        local lab = W.Text(page, 12, T.accent)
        lab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
        lab:SetText(label)
        local set, first = {}, nil
        local function PaintRow() for k, bt in pairs(set) do bt:SetPrimary((db[key] or fallback) == k) end end
        for n, def in ipairs(defs) do
            local bt = W.Button(page, 96, 22, def[2])
            bt:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", (n - 1) * 102, -6)
            bt:SetScript("OnClick", function() db[key] = def[1]; PaintRow(); NP:ApplyAll() end)
            set[def[1]] = bt
            first = first or bt
        end
        PaintRow()
        return first
    end
    local hrow = Choices(box, "Health text on the bar", "healthMode",
        { { "percent", "Percent" }, { "value", "Value" }, { "both", "Both" }, { "none", "None" } }, "percent")
    local nrow = Choices(hrow, "Name and level above the bar", "nameStyle",
        { { "split", "Name | Level" }, { "center", "Centred" } }, "split")

    local w = W.Stepper(page, "Plate width", function() return db.width end,
        function(v) db.width = v; NP:ApplyAll() end, 60, 220, 4)
    w:SetPoint("TOPLEFT", nrow, "BOTTOMLEFT", 0, -16)
    local h = W.Stepper(page, "Plate height", function() return db.height end,
        function(v) db.height = v; NP:ApplyAll() end, 4, 24, 1)
    h:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -6)
    local ds = W.Stepper(page, "Debuff icon size", function() return db.debuffSize or 20 end,
        function(v) db.debuffSize = v; NP.RebuildAuras() end, 12, 36, 2, " px")
    ds:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
    local qs = W.Stepper(page, "Quest sword size", function() return db.questMarkSize or 14 end,
        function(v) db.questMarkSize = v; NP.UpdateQuestMarks() end, 8, 28, 2, " px")
    qs:SetPoint("TOPLEFT", ds, "BOTTOMLEFT", 0, -6)
    local fa = W.Stepper(page, "Faded plates", function() return db.fadeAlpha or 70 end,
        function(v) db.fadeAlpha = v; NP:ApplyAll() end, 20, 100, 5, " %")
    fa:SetPoint("TOPLEFT", qs, "BOTTOMLEFT", 0, -6)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", fa, "BOTTOMLEFT", 0, -18)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("The game still decides which plates exist and where they sit (V and Shift+V toggle enemy and friendly "
        .. "plates; the Interface options control stacking and distance). Casts on other units only show if your Classic "
        .. "version reports them. Untick Nameplates under Modules and reload to go back to Blizzard's.")
end)
