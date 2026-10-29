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
    if UnitThreatSituation then
        local status = UnitThreatSituation("player", unit)
        if status then return status >= 2 end
    end
    return UnitExists(unit .. "target") and UnitIsUnit(unit .. "target", "player") or false
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
local function DetectRole()
    -- 1. the role you picked for your group (Group Finder / right-click a party member > Set Role)
    if UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned("player")
        if r == "TANK" then return "tank", "your group role is Tank" end
        if r == "DAMAGER" or r == "HEALER" then return "dps", "your group role is " .. (r == "HEALER" and "Healer" or "Damage") end
    end
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
                         "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
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
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if a then return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime end
        return
    end
    local name, icon, count, debuffType, duration, expirationTime = UnitAura(unit, index, filter)
    return name, icon, count, debuffType, duration, expirationTime
end

local MAX_AURAS = 5

local function UpdateAuras(p)
    local db = DB()
    local shown = 0
    if db.myDebuffs and UnitCanAttack("player", p.unit) then
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
                p.auras[shown] = a
            end
            local size = max(db.height + 6, 14)
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
end

local function UpdateCast(p)
    local bar = p.cast
    if not DB().castBar then bar:Hide(); bar:SetScript("OnUpdate", nil); return end
    local unit = p.unit
    local name, _, texture, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, texture, startMS, endMS = UnitChannelInfo(unit)
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
    else
        bar:Hide()
        bar:SetScript("OnUpdate", nil)
    end
end

--------------------------------------------------------------------------------
-- A plate
--------------------------------------------------------------------------------
function NP:ApplySize(p)
    local db = DB()
    p:SetSize(db.width, db.height)
    p.name:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    p.healthText:SetFont(STANDARD_TEXT_FONT, max(db.height - 3, 7), "OUTLINE")
    p.cast:SetHeight(max(floor(db.height * 0.8), 7))
    p.cast.icon:SetSize(max(floor(db.height * 0.8), 7), max(floor(db.height * 0.8), 7))
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
    p.name:SetPoint("BOTTOM", p, "TOP", 0, 3)
    p.name:SetWordWrap(false)
    p.name:SetWidth(180)

    p.raid = overlay:CreateTexture(nil, "OVERLAY")
    p.raid:SetSize(16, 16)
    p.raid:SetPoint("RIGHT", p, "LEFT", -4, 0)
    p.raid:Hide()

    -- cast bar under the plate
    p.cast = CreateFrame("StatusBar", nil, p)
    p.cast:SetStatusBarTexture(FLAT)
    p.cast:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -3)
    p.cast:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -3)
    W.Texture(p.cast, "BACKGROUND", { 0, 0, 0, 0.7 }):SetAllPoints()
    W.Border(p.cast, 1, { 0, 0, 0, 1 }, "BORDER")
    p.cast.icon = p.cast:CreateTexture(nil, "ARTWORK")
    p.cast.icon:SetPoint("RIGHT", p.cast, "LEFT", -2, 0)
    p.cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.cast.text = p.cast:CreateFontString(nil, "OVERLAY")
    p.cast.text:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    p.cast.text:SetPoint("CENTER", p.cast, "CENTER", 0, 0)
    p.cast:Hide()

    p.auras = {}
    NP:ApplySize(p)

    p:SetScript("OnEvent", function(self, event)
        if event:find("^UNIT_SPELLCAST") then UpdateCast(self) else NP:Update(self) end
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

    -- keep Blizzard's own plate art invisible
    if p.base.UnitFrame then p.base.UnitFrame:SetAlpha(0) end

    local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
    p.health:SetMinMaxValues(0, max(mx, 1))
    p.health:SetValue(cur)
    local r, g, b = ThreatColor(unit)
    if not r then r, g, b = BaseColor(unit) end
    p.health:SetStatusBarColor(r, g, b)

    if db.healthText and mx > 0 then
        p.healthText:SetText(format("%d%%", mx <= 100 and cur or floor(cur / mx * 100 + 0.5)))
    else
        p.healthText:SetText("")
    end

    local name = UnitName(unit) or ""
    if db.showLevel then
        local level = UnitLevel(unit)
        if level and level > 0 then
            local lc = GetLevelColor(unit)
            local hex = format("%02x%02x%02x", math.floor(lc[1] * 255 + 0.5), math.floor(lc[2] * 255 + 0.5), math.floor(lc[3] * 255 + 0.5))
            name = format("|cFF%s%d|r %s", hex, level, name)
        else
            name = format("|cFFCCCCCC??|r %s", name)
        end
    end
    p.name:SetText(name)
    local nr, ng, nb = BaseColor(unit)
    p.name:SetTextColor(nr, ng, nb)

    -- the target gets a gold frame and a little extra size
    local isTarget = db.targetHighlight and UnitIsUnit(unit, "target")
    W.SetBorder(p.border, isTarget and T.accent or { 0, 0, 0, 1 })
    p:SetScale(isTarget and 1.15 or 1)

    local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if index and SetRaidTargetIconTexture then
        p.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(p.raid, index)
        p.raid:Show()
    else
        p.raid:Hide()
    end

    UpdateAuras(p)
end

-- The game fades its own plate in and out (distance, target, combat) by setting its alpha again and again,
-- which let its bar flash through under ours. Keep its alpha at zero for good.
-- Some of its pieces (the mouse-over highlight, the target border) ignore their parent's transparency, so every
-- frame, texture and text inside the game's plate is held at zero on its own as well.
local function Silence(obj, depth)
    if not obj or depth > 5 then return end
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
        for _, r in ipairs({ obj:GetRegions() }) do Silence(r, depth + 1) end
    end
    if obj.GetChildren then
        for _, c in ipairs({ obj:GetChildren() }) do Silence(c, depth + 1) end
    end
end

local function SilenceBlizzard(base)
    local uf = base.UnitFrame
    if not uf then return end
    Silence(uf, 0)
    if not uf.cysShowHook and uf.HookScript then
        uf.cysShowHook = true
        uf:HookScript("OnShow", function(self) self:SetAlpha(0) end)
    end
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
    p:UnregisterAllEvents()
    for _, ev in ipairs(PLATE_EVENTS) do pcall(p.RegisterUnitEvent, p, ev, unit) end
    for _, ev in ipairs(CAST_EVENTS) do pcall(p.RegisterUnitEvent, p, ev, unit) end
    p:Show()
    self:Update(p)
    UpdateCast(p)
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
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            NP:Add(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            NP:Remove(unit)
        else
            for _, p in pairs(NP.plates) do if p.unit then NP:Update(p) end end
        end
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
    Check("Show the level before the name", "showLevel")
    Check("Show health percent on the bar", "healthText")
    Check("Class colors for players", "classColors")
    Check("Gold frame and extra size for your target", "targetHighlight")
    Check("Show my debuffs on the mob", "myDebuffs")
    Check("Show a small cast bar", "castBar")

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

    local w = W.Stepper(page, "Plate width", function() return db.width end,
        function(v) db.width = v; NP:ApplyAll() end, 60, 220, 4)
    w:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -16) -- follows the description, whatever its height
    local h = W.Stepper(page, "Plate height", function() return db.height end,
        function(v) db.height = v; NP:ApplyAll() end, 4, 24, 1)
    h:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -6)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -18)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("The game still decides which plates exist and where they sit (V and Shift+V toggle enemy and friendly "
        .. "plates; the Interface options control stacking and distance). Casts on other units only show if your Classic "
        .. "version reports them. Untick Nameplates under Modules and reload to go back to Blizzard's.")
end)
