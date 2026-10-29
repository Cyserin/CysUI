--------------------------------------------------------------------------------
-- Cys's UI - Raid Frames
--
-- Flat raid frames for 10, 20 and 40 player raids, built on the game's secure group headers
-- (one per raid group) so they update, target and click in combat just like the stock ones.
--
--   10-man: groups 1-2 side by side, big frames with a small power bar
--   20-man: groups 1-4 side by side, medium frames
--   40-man: groups 1-8 side by side, compact frames
--   "Auto" picks the layout from the highest raid group in use (checked out of combat).
--
-- Class colored health bars, name, missing-health text, incoming heals, debuff-type border,
-- debuff icons, target highlight, out-of-range fade, raid markers and a leader star.
-- Layout changes wait for combat to end. Party frames stay in the Unit Frames module.
-- Untick Raid Frames under /cui > Modules and reload to get Blizzard's raid frames back.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min

local RF = {}
CUI.RaidFrames = RF
RF.headers = {}
local byUnit = {}   -- unit token ("raid7") -> its button
local buttons = {}  -- every button we dressed up

local FLAT = "Interface\\Buttons\\WHITE8X8"

local MODES = {
    ["10"] = { groups = 2, w = 118, h = 38, gap = 4, font = 11, icons = 3, power = true },
    ["20"] = { groups = 4, w = 94,  h = 30, gap = 3, font = 10, icons = 2, power = false },
    ["40"] = { groups = 8, cols = 4, w = 92, h = 24, gap = 2, font = 9, icons = 0, power = false },
}
RF.MODES = MODES

local DEFAULTS = { mode = "auto", classColors = true, healthText = "deficit", rangeFade = true,
                   debuffIcons = true, dispelBorder = true, dispelOnly = true, roleIcons = "all", roles = {}, powerBar = true, wAdj = 0, hAdj = 0 }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.raidframes = CysUIDB.raidframes or {}
    local db = CysUIDB.raidframes
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and {} or v end
    end
    return db
end

local anchor
local hidden = CreateFrame("Frame")
hidden:Hide()

--------------------------------------------------------------------------------
-- Colors, text, auras
--------------------------------------------------------------------------------
local function UnitColor(unit)
    if UnitIsDeadOrGhost(unit) then return 0.45, 0.45, 0.45 end
    if UnitIsConnected and not UnitIsConnected(unit) then return 0.3, 0.3, 0.3 end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function Short(n)
    if n >= 10000 then return format("%.0fk", n / 1000) end
    if n >= 1000 then return format("%.1fk", n / 1000) end
    return tostring(n)
end

local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if a then return a.name, a.icon, a.applications, a.dispelName end
        return
    end
    local name, icon, count, debuffType = UnitAura(unit, index, filter)
    return name, icon, count, debuffType
end

local FALLBACK_TYPES = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}
-- Spells that remove debuffs in Classic Era: { debuff types it removes, spell ids (every rank), pet = learned by the pet }.
-- The border only lights up for a type you can remove right now (spell learned; warlocks need the Felhunter out).
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

local canDispel = {}
local function Known(id, pet)
    if pet then
        if IsSpellKnown then return IsSpellKnown(id, true) and true or false end
        return false
    end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) and true or false
end

local function RebuildDispels()
    wipe(canDispel)
    local _, class = UnitClass("player")
    for _, entry in ipairs(DISPEL_SPELLS[class] or {}) do
        for _, id in ipairs(entry[2]) do
            local ok, known = pcall(Known, id, entry.pet)
            if ok and known then
                for _, t in ipairs(entry[1]) do canDispel[t] = true end
                break
            end
        end
    end
end
RF.RebuildDispels = RebuildDispels

local function CanDispel(debuffType)
    if not DB().dispelOnly then return true end
    return canDispel[debuffType] and true or false
end

local function TypeColor(debuffType)
    local c = DebuffTypeColor and DebuffTypeColor[debuffType]
    if c and c.r then return c.r, c.g, c.b end
    local f = FALLBACK_TYPES[debuffType]
    if f then return f[1], f[2], f[3] end
end

--------------------------------------------------------------------------------
-- Updating one button
--------------------------------------------------------------------------------
local function UpdateHealth(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local db = DB()
    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    b.health:SetMinMaxValues(0, max(mx, 1))
    b.health:SetValue(cur)

    local incoming = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
    if (not incoming or incoming <= 0) and CysUI.HealEstimate then incoming = CysUI.HealEstimate(unit) end
    if incoming and incoming > 0 and cur < mx then
        b.healBar:SetMinMaxValues(0, max(mx, 1))
        b.healBar:SetValue(min(mx, cur + incoming))
        b.healBar:Show()
    else
        b.healBar:Hide()
    end

    local text = ""
    if UnitIsDeadOrGhost(unit) then
        text = "|cFFAAAAAADead|r"
    elseif UnitIsConnected and not UnitIsConnected(unit) then
        text = "|cFFAAAAAAOff|r"
    elseif db.healthText == "deficit" then
        if mx > 0 and cur < mx then text = "|cFFFF6060-" .. Short(mx - cur) .. "|r" end
    elseif db.healthText == "percent" then
        text = mx > 0 and format("%d%%", floor(cur / mx * 100 + 0.5)) or ""
    end
    b.healthText:SetText(text)
end

local function UpdatePower(b)
    if not b.power or not b.power:IsShown() then return end
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local mx = UnitPowerMax(unit)
    b.power:SetMinMaxValues(0, max(mx, 1))
    b.power:SetValue(UnitPower(unit))
    local t = UnitPowerType(unit)
    local c = PowerBarColor and PowerBarColor[t]
    if c and c.r then b.power:SetStatusBarColor(c.r, c.g, c.b) else b.power:SetStatusBarColor(0.3, 0.5, 1) end
end

local function UpdateBorder(b)
    local unit = b.unit
    if not unit then return end
    local db = DB()
    local r, g, bl
    if db.dispelBorder and b.debuffType then r, g, bl = TypeColor(b.debuffType) end
    if not r and UnitIsUnit(unit, "target") then r, g, bl = T.accent[1], T.accent[2], T.accent[3] end
    if r then
        W.SetBorder(b.hl, { r, g, bl })
        for i = 1, 4 do b.hl[i]:Show() end
    else
        for i = 1, 4 do b.hl[i]:Hide() end
    end
end

local function UpdateAuras(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local db = DB()
    local mode = MODES[RF.mode or "10"]
    b.debuffType = nil
    local shown = 0
    local want = (db.debuffIcons and mode and mode.icons) or 0
    for i = 1, 40 do
        local name, icon, count, debuffType = GetAura(unit, i, "HARMFUL")
        if not name then break end
        if debuffType and not b.debuffType and CanDispel(debuffType) then b.debuffType = debuffType end
        if shown < want then
            shown = shown + 1
            local a = b.icons[shown]
            if not a then
                a = b:CreateTexture(nil, "OVERLAY", nil, 2)
                b.icons[shown] = a
            end
            local size = max(10, min(16, floor(b:GetHeight() * 0.42)))
            a:SetSize(size, size)
            a:ClearAllPoints()
            a:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2 - (shown - 1) * (size + 1), 2)
            a:SetTexture(icon)
            a:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            a:Show()
        end
    end
    for i = shown + 1, #b.icons do b.icons[i]:Hide() end
    UpdateBorder(b)
end

-- Roles. Order: your own /cysraid role setting, then a role the game assigned (role check), then Main Tank from the
-- raid tab, then a guess by class (priests heal, everyone else damage).
local ROLE_COORDS = {
    TANK    = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER  = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local function GetRole(unit)
    local name = UnitName(unit)
    local manual = name and DB().roles[name]
    if manual then return manual end
    if UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned(unit)
        if r and r ~= "NONE" then return r end
    end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return "TANK" end
    local _, class = UnitClass(unit)
    if class == "PRIEST" then return "HEALER" end
    return "DAMAGER"
end

local function SetRole(b, role)
    local mode = DB().roleIcons
    local show = role and mode ~= "off" and (mode == "all" or role == "TANK" or role == "HEALER")
    if show then
        b.role:SetTexCoord(unpack(ROLE_COORDS[role]))
        b.role:Show()
    else
        b.role:Hide()
    end
    b.name:ClearAllPoints()
    if show then b.name:SetPoint("LEFT", b.role, "RIGHT", 1, 0) else b.name:SetPoint("LEFT", b.health, "LEFT", 3, 0) end
    b.name:SetPoint("RIGHT", b.healthText, "LEFT", -2, 0)
end

local function UpdateRole(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    SetRole(b, GetRole(unit))
end

local function UpdateMarks(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if index and SetRaidTargetIconTexture then
        b.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(b.raidIcon, index)
        b.raidIcon:Show()
    else
        b.raidIcon:Hide()
    end
    local leader = (UnitIsGroupLeader and UnitIsGroupLeader(unit)) or (UnitIsPartyLeader and UnitIsPartyLeader(unit))
    b.leader:SetShown(leader and true or false)
end

local function UpdateName(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    b.name:SetText(UnitName(unit) or "")
end

local function Refresh(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local db = DB()
    local r, g, bl = UnitColor(unit)
    if not db.classColors then r, g, bl = T.accent[1], T.accent[2], T.accent[3] end
    b.health:SetStatusBarColor(r, g, bl)
    UpdateName(b)
    UpdateHealth(b)
    UpdatePower(b)
    UpdateAuras(b)
    UpdateMarks(b)
    UpdateRole(b)
end

local function UpdateRange(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then return end
    local alpha = 1
    if DB().rangeFade and not UnitIsUnit(unit, "player") and UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked and not inRange then alpha = 0.4 end
    end
    if UnitIsConnected and not UnitIsConnected(unit) then alpha = min(alpha, 0.5) end
    b:SetAlpha(alpha)
end

--------------------------------------------------------------------------------
-- Dressing up a header-created button (called from the XML template)
--------------------------------------------------------------------------------
local function RegisterWithClique(f)
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[f] = true
    if Clique and Clique.RegisterFrame then pcall(function() Clique:RegisterFrame(f) end) end
end

local function LayoutButton(b)
    local mode = MODES[RF.mode or "10"] or MODES["10"]
    local db = DB()
    local usePower = mode.power and db.powerBar
    b.power:SetShown(usePower and true or false)
    b.health:ClearAllPoints()
    b.health:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.health:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    if usePower then
        b.health:SetPoint("BOTTOMLEFT", b.power, "TOPLEFT", 0, 1)
        b.health:SetPoint("BOTTOMRIGHT", b.power, "TOPRIGHT", 0, 1)
    else
        b.health:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, -1 + 2)
        b.health:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, -1 + 2)
    end
    b.name:SetFont(STANDARD_TEXT_FONT, mode.font, "OUTLINE")
    b.healthText:SetFont(STANDARD_TEXT_FONT, mode.font - 1, "OUTLINE")
end

local function BuildButton(b, preview)
    if not preview then
        b:SetAttribute("*type1", "target")
        b:SetAttribute("*type2", "togglemenu")
        b:RegisterForClicks("AnyUp", "AnyDown")
    end

    W.Texture(b, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    b.edges = W.Border(b, 1, T.border, "BORDER")
    b.hl = W.Border(b, 1, { 1, 1, 1 }, "OVERLAY", 3) -- state border: debuff type / target
    for i = 1, 4 do b.hl[i]:Hide() end

    b.power = CreateFrame("StatusBar", nil, b)
    b.power:SetStatusBarTexture(FLAT)
    b.power:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.power:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.power:SetHeight(3)
    W.Texture(b.power, "BACKGROUND", T.field):SetAllPoints()

    b.health = CreateFrame("StatusBar", nil, b)
    b.health:SetStatusBarTexture(FLAT)
    W.Texture(b.health, "BACKGROUND", T.field):SetAllPoints()

    b.healBar = CreateFrame("StatusBar", nil, b.health)
    b.healBar:SetAllPoints(b.health)
    b.healBar:SetStatusBarTexture(FLAT)
    b.healBar:SetStatusBarColor(0.0, 0.9, 0.5, 0.35)
    b.healBar:SetFrameLevel(b.health:GetFrameLevel() + 1)
    b.healBar:Hide()

    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints(b)
    overlay:SetFrameLevel(b:GetFrameLevel() + 5)
    b.healthText = overlay:CreateFontString(nil, "OVERLAY")
    b.healthText:SetPoint("RIGHT", b.health, "RIGHT", -3, 0)
    b.name = overlay:CreateFontString(nil, "OVERLAY")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetTextColor(1, 1, 1)
    b.name:SetPoint("LEFT", b.health, "LEFT", 3, 0)
    b.name:SetPoint("RIGHT", b.healthText, "LEFT", -2, 0)
    b.role = overlay:CreateTexture(nil, "OVERLAY")
    b.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    b.role:SetSize(12, 12)
    b.role:SetPoint("LEFT", b.health, "LEFT", 2, 0)
    b.role:Hide()
    b.raidIcon = overlay:CreateTexture(nil, "OVERLAY")
    b.raidIcon:SetSize(12, 12)
    b.raidIcon:SetPoint("CENTER", b, "TOP", 0, -1)
    b.raidIcon:Hide()
    b.leader = overlay:CreateTexture(nil, "OVERLAY")
    b.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    b.leader:SetSize(10, 10)
    b.leader:SetPoint("TOPLEFT", b, "TOPLEFT", 1, 3)
    b.leader:Hide()
    b.icons = {}

    if not preview then
        b:SetScript("OnEnter", function(self)
            if not self.unit then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    LayoutButton(b)
    if not preview then
        RegisterWithClique(b)
        buttons[#buttons + 1] = b
    end
end

function CysUI_RaidButton_OnLoad(b) BuildButton(b, false) end

--------------------------------------------------------------------------------
-- Preview: 40 made-up raiders drawn with the same look, so every layout can be seen while solo
--------------------------------------------------------------------------------
local previewFrames = {}
local FAKE_CLASSES = { "WARRIOR", "PRIEST", "DRUID", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
local FAKE_NAMES = { "Tankzilla", "Healbot", "Moonfury", "Frostbolt", "Backstab", "Eaglehawk", "Shadowbane", "Lightbringer", "Earthmender" }

local function FillPreview(b, i)
    local class = FAKE_CLASSES[(i - 1) % #FAKE_CLASSES + 1]
    local c = RAID_CLASS_COLORS[class] or { r = 0.6, g = 0.6, b = 0.6 }
    local db = DB()
    local mode = MODES[RF.mode or "10"]
    local dead, off = i == 7, i == 12
    local pct = (i * 37) % 100 / 100
    if pct < 0.35 then pct = 1 - pct end
    if i % 4 == 1 then pct = 1 end
    b.health:SetMinMaxValues(0, 100)
    b.health:SetValue(dead and 0 or pct * 100)
    local r, g, bl = c.r, c.g, c.b
    if dead then r, g, bl = 0.45, 0.45, 0.45 elseif off then r, g, bl = 0.3, 0.3, 0.3 end
    if not db.classColors then r, g, bl = T.accent[1], T.accent[2], T.accent[3] end
    b.health:SetStatusBarColor(r, g, bl)
    b.name:SetText(FAKE_NAMES[(i - 1) % #FAKE_NAMES + 1] .. (i > #FAKE_NAMES and tostring(floor(i / #FAKE_NAMES) + 1) or ""))
    local text = ""
    if dead then text = "|cFFAAAAAADead|r"
    elseif off then text = "|cFFAAAAAAOff|r"
    elseif db.healthText == "deficit" and pct < 1 then text = "|cFFFF6060-" .. Short(floor((1 - pct) * 4200)) .. "|r"
    elseif db.healthText == "percent" then text = floor(pct * 100) .. "%" end
    b.healthText:SetText(text)
    b.healBar:SetMinMaxValues(0, 100)
    if pct < 0.8 and i % 3 == 0 then b.healBar:SetValue(min(100, pct * 100 + 15)); b.healBar:Show() else b.healBar:Hide() end
    if b.power:IsShown() then
        b.power:SetMinMaxValues(0, 100)
        b.power:SetValue(40 + (i * 13) % 60)
        b.power:SetStatusBarColor(0.2, 0.4, 1)
    end
    local dt = (i % 6 == 2 and "Magic") or (i % 9 == 4 and "Curse") or (i % 11 == 5 and "Poison") or nil
    if dt and not CanDispel(dt) then dt = nil end
    for k = 1, 4 do b.hl[k]:Hide() end
    if dt and db.dispelBorder then
        local tr, tg, tb = TypeColor(dt)
        if tr then W.SetBorder(b.hl, { tr, tg, tb }); for k = 1, 4 do b.hl[k]:Show() end end
    end
    for _, a in ipairs(b.icons) do a:Hide() end
    if dt and db.debuffIcons and mode.icons > 0 then
        local a = b.icons[1] or b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.icons[1] = a
        local size = max(10, min(16, floor(b:GetHeight() * 0.42)))
        a:SetSize(size, size)
        a:ClearAllPoints()
        a:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        a:SetTexture("Interface\\Icons\\Spell_Shadow_CurseOfTounges")
        a:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        a:Show()
    end
    b:SetAlpha(i == 15 and 0.4 or (off and 0.5 or 1))
    b.leader:SetShown(i == 1)
    local role = (class == "WARRIOR" and i <= 10 and "TANK") or (class == "SHAMAN" and i % 2 == 0 and "TANK") or (class == "PRIEST" and "HEALER")
        or (class == "DRUID" and i % 2 == 1 and "HEALER") or (class == "PALADIN" and "HEALER") or "DAMAGER"
    SetRole(b, role)
    b.raidIcon:Hide()
end

function RF:LayoutPreview()
    if not self.previewing or not anchor then return end
    local m = MODES[self.mode or "10"]
    local db = DB()
    local w, h = max(40, m.w + (db.wAdj or 0)), max(16, m.h + (db.hAdj or 0))
    local colW = w + m.gap * 2
    local cols = m.cols or m.groups
    local blockH = 5 * (h + m.gap) + m.gap * 2
    for i = 1, 40 do
        local g, row = floor((i - 1) / 5) + 1, (i - 1) % 5
        local b = previewFrames[i]
        if not b then
            b = CreateFrame("Button", nil, anchor)
            BuildButton(b, true)
            previewFrames[i] = b
        end
        if g <= m.groups then
            b:SetSize(w, h)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", anchor, "TOPLEFT", ((g - 1) % cols) * colW, -(floor((g - 1) / cols) * blockH + row * (h + m.gap)))
            LayoutButton(b)
            FillPreview(b, i)
            b:Show()
        else
            b:Hide()
        end
    end
end

function CysUI_RaidButton_OnAttributeChanged(b, name, value)
    if name ~= "unit" then return end
    if b.unit and byUnit[b.unit] == b then byUnit[b.unit] = nil end
    b.unit = value
    if value then
        byUnit[value] = b
        Refresh(b)
        UpdateRange(b)
    end
end

--------------------------------------------------------------------------------
-- Headers, layout and mode
--------------------------------------------------------------------------------
local pendingMode = false

local function AutoMode()
    local top = 0
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            if subgroup and subgroup > top then top = subgroup end
        end
    end
    if top <= 2 then return "10" end
    if top <= 4 then return "20" end
    return "40"
end

local function ChosenMode()
    local m = DB().mode
    if m == "10" or m == "20" or m == "40" then return m end
    return AutoMode()
end

function RF:ApplyMode()
    if not anchor then return end
    if InCombatLockdown() then pendingMode = true; return end
    pendingMode = false
    local key = ChosenMode()
    local db = DB()
    local m = MODES[key]
    self.mode = key
    local w, h = max(40, m.w + (db.wAdj or 0)), max(16, m.h + (db.hAdj or 0))
    local gap = m.gap
    local colW = w + gap * 2
    local cols = m.cols or m.groups
    local rowsOfGroups = math.ceil(m.groups / cols)
    local blockH = 5 * (h + gap) + gap * 2
    anchor:SetSize(cols * colW - gap * 2, rowsOfGroups * blockH - gap * 2 - gap)
    for g = 1, 8 do
        local hd = self.headers[g]
        if hd then
            local on = g <= m.groups
            hd:SetAttribute("showRaid", on)
            hd:SetAttribute("yOffset", -gap)
            hd:SetAttribute("initialConfigFunction", format("self:SetWidth(%d); self:SetHeight(%d)", w, h))
            hd:ClearAllPoints()
            hd:SetPoint("TOPLEFT", anchor, "TOPLEFT", ((g - 1) % cols) * colW, -floor((g - 1) / cols) * blockH)
            for i = 1, 5 do
                local child = hd:GetAttribute("child" .. i)
                if child then
                    child:SetSize(w, h)
                    LayoutButton(child)
                    if child.unit then Refresh(child) end
                end
            end
        end
    end
    if CUI.ApplyLayout then pcall(CUI.ApplyLayout, CUI, "raid") end
    if self.previewing then self:LayoutPreview() end
end

local function HideBlizzardRaid()
    for _, name in ipairs({ "CompactRaidFrameManager", "CompactRaidFrameContainer" }) do
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

local function Build()
    anchor = CreateFrame("Frame", "CysUIRaidAnchor", UIParent)
    anchor:SetSize(240, 170)
    for g = 1, 8 do
        local hd = CreateFrame("Frame", "CysUIRaidGroup" .. g, UIParent, "SecureGroupHeaderTemplate")
        hd:SetAttribute("template", "CysUIRaidUnitTemplate")
        hd:SetAttribute("templateType", "Button")
        hd:SetAttribute("showRaid", true)
        hd:SetAttribute("showParty", false)
        hd:SetAttribute("showPlayer", false)
        hd:SetAttribute("showSolo", false)
        hd:SetAttribute("groupFilter", tostring(g))
        hd:SetAttribute("sortMethod", "INDEX")
        hd:SetAttribute("point", "TOP")
        hd:SetAttribute("xOffset", 0)
        hd:SetAttribute("yOffset", -3)
        hd:SetAttribute("unitsPerColumn", 5)
        hd:SetAttribute("maxColumns", 1)
        hd:SetAttribute("columnAnchorPoint", "LEFT")
        hd:SetAttribute("initialConfigFunction", "self:SetWidth(94); self:SetHeight(30)")
        RF.headers[g] = hd
    end
    RF.mode = ChosenMode()
    RF:ApplyMode()
    -- create all five buttons of every group now, out of combat, so nothing has to be made mid-fight
    for g = 1, 8 do
        local hd = RF.headers[g]
        hd:SetAttribute("startingIndex", -4)
        hd:SetAttribute("startingIndex", 1)
    end
    CUI:RegisterMovable(anchor, "raid", "Raid Frames", { point = "LEFT", x = 40, y = 120 })
    for g = 1, 8 do RF.headers[g]:Show() end
    RF:ApplyMode()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_HEAL_PREDICTION",
                 "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY",
                 "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE", "PLAYER_REGEN_ENABLED",
                 "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UNIT_PET", "PLAYER_LEVEL_UP", "PLAYER_ROLES_ASSIGNED", "PARTY_LEADER_CHANGED" }

local POWER = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true, UNIT_MANA = true,
                UNIT_RAGE = true, UNIT_ENERGY = true }

local function EachActive(fn)
    for _, b in pairs(byUnit) do
        if b.unit and UnitExists(b.unit) then fn(b) end
    end
end

if CysUI.HealEstimateWatchers then
    table.insert(CysUI.HealEstimateWatchers, function() EachActive(UpdateHealth) end)
end

local function OnEvent(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEAL_PREDICTION" then
        local b = byUnit[unit]
        if b then UpdateHealth(b) end
    elseif event == "UNIT_AURA" then
        local b = byUnit[unit]
        if b then UpdateAuras(b) end
    elseif POWER[event] then
        local b = byUnit[unit]
        if b then UpdatePower(b) end
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_CONNECTION" then
        local b = byUnit[unit]
        if b then Refresh(b) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        EachActive(UpdateBorder)
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        EachActive(UpdateMarks)
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        EachActive(UpdateRole)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if DB().mode == "auto" then RF:ApplyMode() end
        EachActive(Refresh)
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or (event == "UNIT_PET" and unit == "player") then
        RebuildDispels()
        EachActive(UpdateAuras)
        if RF.previewing then RF:LayoutPreview() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingMode then RF:ApplyMode() end
    end
end

function RF.Enable()
    if InCombatLockdown() then
        CUI:Print("|cFFFF9F43Raid Frames: can't start in combat. Reload out of combat.|r")
        return
    end
    DB()
    local ok, err = pcall(Build)
    if not ok then
        CUI:Print("|cFFFF9F43Raid Frames skipped (" .. tostring(err) .. ")|r")
        return
    end
    HideBlizzardRaid()
    RebuildDispels()
    for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", OnEvent)
    local acc = 0
    ev:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.4 then return end
        acc = 0
        EachActive(UpdateRange)
    end)
end

-- show a made-up raid in the chosen layout (any time you are out of combat) to look at the styling
function RF:Test(on)
    if InCombatLockdown() then CUI:Print("The raid preview waits until you leave combat.") return end
    if on == nil then on = not self.previewing end
    self.previewing = on
    if on then
        self:LayoutPreview()
    else
        for _, b in ipairs(previewFrames) do b:Hide() end
    end
    CUI:Print("Raid frame preview " .. (on and "ON - pick 10 / 20 / 40 to compare; press Preview again to turn it off" or "off"))
end

SLASH_CYSRAID1 = "/cysraid"
SlashCmdList["CYSRAID"] = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "test" then RF:Test() return end
    local rest = msg:match("^role%s+(.+)$")
    if rest then
        local words = {}
        for w in rest:gmatch("%S+") do words[#words + 1] = w end
        local role = ({ tank = "TANK", heal = "HEALER", healer = "HEALER", dps = "DAMAGER", damage = "DAMAGER", clear = false })[words[#words]]
        if role == nil then CUI:Print("Role must be tank, healer, dps or clear.") return end
        local name
        if #words > 1 then
            name = words[1]:sub(1, 1):upper() .. words[1]:sub(2)
        else
            name = UnitName("target")
        end
        if not name then CUI:Print("Target someone, or type /cysraid role <name> tank|healer|dps|clear") return end
        DB().roles[name] = role or nil
        CUI:Print(format("%s: %s", name, role and (role == "DAMAGER" and "DPS" or role:lower()) or "back to automatic"))
        EachActive(UpdateRole)
        return
    end
    CUI:Print("/cysraid test - toggle a made-up 40-player preview")
    CUI:Print("/cysraid role [name] tank|healer|dps|clear - set a role by hand (uses your target without a name)")
end

CUI:RegisterModule({
    key = "raidframes",
    name = "Raid Frames",
    addon = "CysUI",
    desc = "Flat raid frames for 10, 20 and 40 player raids: class colors, missing health, incoming heals, debuff borders, range fade. Party frames are in Unit Frames.",
    onEnable = RF.Enable,
    open = function() CUI:OpenConfig("Raid Frames") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Raid Frames", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Layout", width):SetPoint("TOPLEFT", 0, -4)

    local modeButtons = {}
    local function PaintMode()
        for key, b in pairs(modeButtons) do b:SetPrimary(db.mode == key) end
    end
    local function SetMode(key)
        db.mode = key
        PaintMode()
        if InCombatLockdown() then CUI:Print("The layout changes when combat ends.") end
        RF:ApplyMode()
    end
    local x = 4
    for _, def in ipairs({ { "auto", "Auto" }, { "10", "10-man" }, { "20", "20-man" }, { "40", "40-man" } }) do
        local b = W.Button(page, 110, 24, def[2])
        b:SetPoint("TOPLEFT", x, -34)
        b:SetScript("OnClick", function() SetMode(def[1]) end)
        modeButtons[def[1]] = b
        x = x + 118
    end
    PaintMode()

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -66)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Auto picks 10 / 20 / 40-man from the highest raid group in use: groups 1-2, 1-4 or all 8 side by side.")

    W.Header(page, "Look", width):SetPoint("TOPLEFT", 0, -102)
    local function All() EachActive(Refresh); if RF.previewing then RF:LayoutPreview() end end
    local rows = {
        { "Class colored health bars", "classColors" },
        { "Fade members who are out of range", "rangeFade" },
        { "Show debuff icons (10 and 20-man)", "debuffIcons" },
        { "Border colored by debuff type (Magic / Curse / Disease / Poison)", "dispelBorder" },
        { "Only borders for debuffs I can dispel right now", "dispelOnly" },
        { "Mana bar on 10-man frames", "powerBar" },
    }
    local y = -132
    for _, row in ipairs(rows) do
        local cb = W.Checkbox(page, row[1], function() return db[row[2]] end, function(on)
            db[row[2]] = on
            if row[2] == "powerBar" then RF:ApplyMode() end
            All()
        end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end

    local texts = { "deficit", "percent", "none" }
    local textBtn = W.Button(page, 230, 22, "")
    textBtn:SetPoint("TOPLEFT", 4, y - 4)
    local function Label() textBtn:SetLabel("Health text: " .. db.healthText) end
    Label()
    textBtn:SetScript("OnClick", function()
        for i, m in ipairs(texts) do
            if m == db.healthText then db.healthText = texts[i % #texts + 1]; break end
        end
        Label()
        All()
    end)
    local roleModes = { "all", "tankheal", "off" }
    local roleNames = { all = "Role icons: all", tankheal = "Role icons: tank and healer only", off = "Role icons: off" }
    local roleBtn = W.Button(page, 230, 22, "")
    roleBtn:SetPoint("TOPLEFT", 242, y - 4)
    local function RoleLabel() roleBtn:SetLabel(roleNames[db.roleIcons] or roleNames.all) end
    RoleLabel()
    roleBtn:SetScript("OnClick", function()
        for i, m in ipairs(roleModes) do
            if m == db.roleIcons then db.roleIcons = roleModes[i % #roleModes + 1]; break end
        end
        RoleLabel()
        All()
        EachActive(UpdateRole)
    end)
    y = y - 34

    local wstep = W.Stepper(page, "Width adjust", function() return db.wAdj end,
        function(v) db.wAdj = v; RF:ApplyMode() end, -30, 60, 2, " px")
    wstep:SetPoint("TOPLEFT", 4, y)
    local hstep = W.Stepper(page, "Height adjust", function() return db.hAdj end,
        function(v) db.hAdj = v; RF:ApplyMode() end, -10, 30, 2, " px")
    hstep:SetPoint("TOPLEFT", 4, y - 30)
    y = y - 64

    local move = W.Button(page, 240, 22, "Move (layout mode)")
    move:SetPoint("TOPLEFT", 4, y)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    local test = W.Button(page, 240, 22, "Preview a full raid (on / off)")
    test:SetPoint("TOPLEFT", 252, y)
    test:SetScript("OnClick", function() RF:Test() end)

    local foot = W.Notes(page, 4, y - 38, width, "", {
            "Layout changes wait until combat ends.",
            "Needs a /reload when switching the module on or off - Blizzard's raid frames come straight back when it is off.",
            "Click-casting addons like Clique work on these frames.",
        })
end)
