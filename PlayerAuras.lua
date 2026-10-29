--------------------------------------------------------------------------------
-- Cys's UI - Player Auras Module
--
-- Movable buff and debuff rows that replace Blizzard's. Right-click a buff to cancel it
-- (just like Blizzard's own buff frame), hover for the tooltip, optional timers below the icons.
-- These are plain buttons (not secure ones), so everything updates in combat too.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, ceil, max = string.format, math.floor, math.ceil, math.max

local PlayerAuras = {}
CUI.PlayerAuras = PlayerAuras

local DEFAULTS = {
    enabled = true, iconSize = 28, spacing = 6, numBuffs = 16, numDebuffs = 8, perRow = 8,
    rightClickCancel = true, showTimers = true, timerBelow = false,
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.playerAuras = CysUIDB.playerAuras or {}
    local db = CysUIDB.playerAuras
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    return db
end

local buffHolder, debuffHolder
local activeBuffIcons = {}
local activeDebuffIcons = {}

local function FormatTime(t)
    if t >= 3600 then return format("%dh", ceil(t / 3600)) end
    if t >= 60 then return format("%dm", ceil(t / 60)) end
    return format("%d", ceil(t))
end

local function PlaceTimer(f)
    f.timer:ClearAllPoints()
    if DB().timerBelow then
        f.timer:SetPoint("TOP", f, "BOTTOM", 0, -1)
    else
        f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
end

local function CreateAuraIcon(parent, size, isDebuff)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.isDebuff = isDebuff

    f.icon = f:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.border = W.Border(f, 1, T.border, "BORDER")

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if self.isWeaponEnchant then
            GameTooltip:SetInventoryItem("player", self.isWeaponEnchant == 1 and 16 or 17)
        elseif self.auraIndex and self.auraType then
            GameTooltip:SetUnitAura("player", self.auraIndex, self.auraType)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- right-click takes a buff off, exactly like Blizzard's buff frame does
    f:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" or self.isDebuff or not DB().rightClickCancel then return end
        if self.isWeaponEnchant then
            pcall(CancelItemTempEnchantment, self.isWeaponEnchant)
        elseif self.auraIndex then
            pcall(CancelUnitBuff, "player", self.auraIndex, "HELPFUL")
        end
    end)

    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.count:SetTextColor(1, 1, 1)
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.count:SetJustifyH("RIGHT")

    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    f.timer:SetTextColor(1, 1, 1, 1)
    f.timer:SetJustifyH("CENTER")
    PlaceTimer(f)

    return f
end

local function GetSortedAuras(auraType)
    local t = {}
    local auraIndex = 1
    while true do
        local name, icon, count, dispelName, duration, expirationTime
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", auraIndex, auraType)
            if not aura then break end
            name, icon, count, dispelName, duration, expirationTime =
                aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime
        else
            name, icon, count, dispelName, duration, expirationTime = UnitAura("player", auraIndex, auraType)
            if not name then break end
        end
        t[#t + 1] = {
            name = name, icon = icon, applications = count or 0, dispelName = dispelName,
            expirationTime = expirationTime or 0, duration = duration or 0,
            auraIndex = auraIndex, auraType = auraType,
        }
        auraIndex = auraIndex + 1
    end

    if auraType == "HELPFUL" and GetWeaponEnchantInfo then
        local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
        if hasMain and mainExp then
            t[#t + 1] = { name = "Main Hand Weapon Enchant", icon = GetInventoryItemTexture("player", 16) or 136244,
                applications = 0, expirationTime = GetTime() + mainExp / 1000, duration = 300, isWeaponEnchant = 1 }
        end
        if hasOff and offExp then
            t[#t + 1] = { name = "Off Hand Weapon Enchant", icon = GetInventoryItemTexture("player", 17) or 136244,
                applications = 0, expirationTime = GetTime() + offExp / 1000, duration = 300, isWeaponEnchant = 2 }
        end
    end

    -- no-expiry buffs first, then the longest remaining down to the shortest
    table.sort(t, function(a, b)
        if (a.expirationTime == 0) ~= (b.expirationTime == 0) then return a.expirationTime == 0 end
        return a.expirationTime > b.expirationTime
    end)
    return t
end

local function Fill(list, holder, auras, limit, isDebuff)
    local db = DB()
    local size, spacing, perRow = db.iconSize, db.spacing, db.perRow or 8
    local shown = 0
    for i = 1, #auras do
        if shown >= limit then break end
        shown = shown + 1
        local aura = auras[i]
        local f = list[shown]
        if not f then
            f = CreateAuraIcon(holder, size, isDebuff)
            list[shown] = f
        end
        f.icon:SetTexture(aura.icon)
        f.count:SetText(aura.applications > 1 and aura.applications or "")
        f.expirationTime = aura.expirationTime
        f.auraIndex = aura.auraIndex
        f.auraType = aura.auraType
        f.isWeaponEnchant = aura.isWeaponEnchant
        f:SetSize(size, size)
        local col = (shown - 1) % perRow
        local row = floor((shown - 1) / perRow)
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -col * (size + spacing), -row * (size + spacing + 4))
        f:Show()
        if isDebuff then
            local c = aura.dispelName and DebuffTypeColor and DebuffTypeColor[aura.dispelName]
            W.SetBorder(f.border, c and { c.r, c.g, c.b } or { 0.8, 0.2, 0.2 })
        else
            W.SetBorder(f.border, T.border)
        end
    end
    for i = shown + 1, #list do list[i]:Hide() end
end

local function UpdateAuras()
    local db = DB()
    if not buffHolder or not debuffHolder then return end
    if not db.enabled then buffHolder:Hide(); debuffHolder:Hide() return end
    buffHolder:Show()
    debuffHolder:Show()
    Fill(activeBuffIcons, buffHolder, GetSortedAuras("HELPFUL"), db.numBuffs, false)
    Fill(activeDebuffIcons, debuffHolder, GetSortedAuras("HARMFUL"), db.numDebuffs, true)
end

local function UpdateTimers(list)
    local db = DB()
    local now = GetTime()
    for _, f in ipairs(list) do
        if f:IsShown() then
            local left = db.showTimers and f.expirationTime and f.expirationTime > 0 and (f.expirationTime - now) or 0
            if left > 0 then
                f.timer:SetText(FormatTime(left))
                if left <= 10 then f.timer:SetTextColor(1, 0.35, 0.35) else f.timer:SetTextColor(1, 1, 1) end
            else
                f.timer:SetText("")
            end
        end
    end
end

-- Blizzard's own buff / debuff frames: ours replace them
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local function HideBlizzardAuras()
    for _, name in ipairs({ "BuffFrame", "TemporaryEnchantFrame", "DebuffFrame" }) do
        local frame = _G[name]
        if frame then
            if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
            frame:SetParent(hiddenParent)
            frame:Hide()
        end
    end
end

-- icon size / spacing / per row sliders, shown in layout mode and on the settings page
local function AuraFields(refresh)
    local db = DB()
    local function Field(key, label, lo, hi, default)
        return { label = label, min = lo, max = hi,
                 get = function() return db[key] or default end,
                 set = function(v) db[key] = v; refresh() end }
    end
    return { Field("perRow", "Icons per row", 1, 16, 8), Field("iconSize", "Icon size", 16, 48, 28),
             Field("spacing", "Spacing", 0, 16, 6) }
end

local function MakeHolder(name, key, label, y, resize)
    local h = CreateFrame("Frame", name, UIParent)
    h:SetSize(250, 40)
    CUI:RegisterMovable(h, key, label, {
        point = "TOPRIGHT", x = -200, y = y,
        scalable = true, extras = AuraFields(resize),
    })
    return h
end

function PlayerAuras.Enable()
    local db = DB()
    if not db.enabled then return end
    HideBlizzardAuras()

    local function ResizeHolders()
        local perRow, size, spacing = db.perRow or 8, db.iconSize, db.spacing
        local w = perRow * (size + spacing) - spacing
        if buffHolder then
            buffHolder:SetSize(w, ceil((db.numBuffs or 16) / perRow) * (size + spacing + 4))
            CUI:ApplyLayout("playerBuffs")
        end
        if debuffHolder then
            debuffHolder:SetSize(w, ceil((db.numDebuffs or 8) / perRow) * (size + spacing + 4))
            CUI:ApplyLayout("playerDebuffs")
        end
        for _, f in ipairs(activeBuffIcons) do PlaceTimer(f) end
        for _, f in ipairs(activeDebuffIcons) do PlaceTimer(f) end
        UpdateAuras()
    end

    buffHolder = MakeHolder("CysUI_PlayerBuffsAnchor", "playerBuffs", "Player Buffs", -30, ResizeHolders)
    debuffHolder = MakeHolder("CysUI_PlayerDebuffsAnchor", "playerDebuffs", "Player Debuffs", -120, ResizeHolders)

    local acc = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        UpdateTimers(activeBuffIcons)
        UpdateTimers(activeDebuffIcons)
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_AURA")
    ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_AURA" and event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then UpdateAuras() end
    end)

    PlayerAuras.Resize = ResizeHolders
    PlayerAuras.Update = UpdateAuras
    ResizeHolders()
end

CUI:RegisterModule({
    key = "playerAuras",
    name = "Player Auras",
    addon = "CysUI",
    desc = "Standalone, movable player buff and debuff rows styled with CysUI gold borders. Right-click a buff to cancel it.",
    onEnable = PlayerAuras.Enable,
    open = function() CUI:OpenConfig("PlayerAuras") end,
})

CUI:RegisterPage("PlayerAuras", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Player Auras", width):SetPoint("TOPLEFT", 0, -4)

    local function Apply() if PlayerAuras.Resize then PlayerAuras.Resize() end end

    local cb = W.Checkbox(page, "Enable standalone Player Auras (needs /reload)", function() return db.enabled end,
        function(on) db.enabled = on end)
    cb:SetPoint("TOPLEFT", 4, -34)

    W.Header(page, "Behavior", width):SetPoint("TOPLEFT", 0, -68)
    local rows = {
        { "Right-click a buff to cancel it", "rightClickCancel" },
        { "Show time left on each icon", "showTimers" },
        { "Put the time under the icon instead of on it", "timerBelow" },
    }
    local y = -98
    for _, r in ipairs(rows) do
        local c = W.Checkbox(page, r[1], function() return db[r[2]] end, function(on) db[r[2]] = on; Apply() end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end

    W.Header(page, "Size", width):SetPoint("TOPLEFT", 0, y - 8)
    y = y - 38
    local function AuraStepper(label, key, lo, hi, default)
        local st = W.Stepper(page, label, function() return db[key] or default end,
            function(v) db[key] = v; Apply() end, lo, hi, 1)
        st:SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    AuraStepper("Icons per row", "perRow", 1, 16, 8)
    AuraStepper("Icon size", "iconSize", 16, 48, 28)
    AuraStepper("Spacing", "spacing", 0, 16, 6)
    AuraStepper("Most buffs shown", "numBuffs", 4, 32, 16)
    AuraStepper("Most debuffs shown", "numDebuffs", 2, 16, 8)

    local move = W.Button(page, 240, 22, "Move buffs and debuffs (layout mode)")
    move:SetPoint("TOPLEFT", 4, y - 8)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
end)
