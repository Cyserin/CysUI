--------------------------------------------------------------------------------
-- Cys's Alerts - short on-screen notes for the things that are easy to miss
--
--   * unspent talent points (after a level up, and once when you log in)
--   * your potion is ready again (by default only during a fight)
--   * no pet out (Hunters and Warlocks who know how to call one) or your pet is dead
--   * someone in your group died
--   * a group healer is low on mana (once per drop, again only after they climb back up)
--   * someone in the group zeroes the XP in this dungeon (13+ levels over its lowest mob, WoW Forever's rule).
--     Mob levels are learned as you see them in each dungeon; a box like the Group level check lists who.
--
-- Each alert has its own switch. Lines appear in one spot (move it in Layout mode), stack up to three, and
-- fade after a few seconds. Nothing is said in chat.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "alerts", name = "Cys's Alerts",
    desc = "Short on-screen notes for things that are easy to miss: unspent talent points, potion ready again, no pet out (Hunter, Warlock), group members dying, a healer low on mana and someone whose level zeroes the XP in a dungeon. Each alert has its own switch.",
    open = function() CysUI:OpenConfig("Alerts") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Secret = CysUICompat and CysUICompat.Secret or function() return false end

CysUIDB.alerts = CysUIDB.alerts or {}
local db = CysUIDB.alerts
local DEFAULTS = { talents = true, potion = true, potionCombat = true, pet = true, petResting = false, death = true,
    sound = true, deathSound = false, size = 16, hold = 4,
    healerMana = true, healerManaPct = 30, healerManaCrit = 15, healerManaInstance = true, healerManaCombat = false,
    healerManaSelf = false, zeroXP = true, zeroXPGap = 13 }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local MAX_LINES = 3
local LINE_H = 26

--------------------------------------------------------------------------------
-- Display: up to three lines, newest on top, each fades out on its own
--------------------------------------------------------------------------------
local holder = CreateFrame("Frame", "CysAlertsFrame", UIParent)
holder:SetSize(380, MAX_LINES * LINE_H)
holder:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
holder:SetFrameStrata("HIGH")
CUI:RegisterMovable(holder, "alerts", "Alerts", { point = "CENTER", x = 0, y = 160 })

local lines, active = {}, {}
for i = 1, MAX_LINES do
    local l = CreateFrame("Frame", nil, holder)
    l:SetSize(380, LINE_H)
    l:SetPoint("TOP", 0, -(i - 1) * LINE_H)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.text = l:CreateFontString(nil, "OVERLAY")
    l.text:SetPoint("CENTER", 11, 0)
    l.icon:SetPoint("RIGHT", l.text, "LEFT", -6, 0)
    l:Hide()
    lines[i] = l
end

local function ApplyFont()
    for _, l in ipairs(lines) do
        l.text:SetFont(STANDARD_TEXT_FONT, db.size, "OUTLINE")
        l.icon:SetSize(db.size + 4, db.size + 4)
    end
end
ApplyFont()

local function Render()
    for i = 1, MAX_LINES do
        local a, l = active[i], lines[i]
        if a then
            l.text:SetText(a.msg)
            l.text:SetTextColor(a.r, a.g, a.b)
            if a.icon then l.icon:SetTexture(a.icon); l.icon:Show() else l.icon:Hide() end
            l:Show()
        else
            l:Hide()
        end
    end
end

holder:SetScript("OnUpdate", function()
    if #active == 0 then return end
    local now, changed = GetTime(), false
    for i = #active, 1, -1 do
        local left = active[i].ends - now
        if left <= 0 then
            table.remove(active, i)
            changed = true
        elseif lines[i] then
            lines[i]:SetAlpha(left < 1 and left or 1)
        end
    end
    if changed then Render() end
end)

local lastSound = 0
local function Alert(msg, icon, r, g, b, sound)
    -- the same note twice in a row only refreshes its time
    for i, a in ipairs(active) do
        if a.msg == msg then table.remove(active, i) break end
    end
    table.insert(active, 1, { msg = msg, icon = icon, r = r or T.accent[1], g = g or T.accent[2], b = b or T.accent[3],
        ends = GetTime() + db.hold })
    while #active > MAX_LINES do table.remove(active) end
    for _, l in ipairs(lines) do l:SetAlpha(1) end
    Render()
    if sound and db.sound and PlaySound and GetTime() - lastSound > 1 then
        lastSound = GetTime()
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end
CUI.Alert = Alert

--------------------------------------------------------------------------------
-- Unspent talent points
--------------------------------------------------------------------------------
local function UnspentTalents()
    if UnitCharacterPoints then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and type(n) == "number" then return n end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo then
        local okC, configID = pcall(C_ClassTalents.GetActiveConfigID)
        if not (okC and configID) then return 0 end
        local okI, info = pcall(C_Traits.GetConfigInfo, configID)
        local treeID = okI and type(info) == "table" and info.treeIDs and info.treeIDs[1]
        if not treeID then return 0 end
        local okT, cur = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
        local c = okT and type(cur) == "table" and cur[1]
        if c and type(c.quantity) == "number" then return c.quantity end
    end
    return 0
end

local function CheckTalents()
    if not db.talents or (UnitLevel("player") or 0) < 10 then return end
    local n = UnspentTalents()
    if n > 0 then
        Alert(n == 1 and "You have 1 unspent talent point" or ("You have " .. n .. " unspent talent points"),
            "Interface\\Icons\\Ability_Marksmanship", nil, nil, nil, false)
    end
end

--------------------------------------------------------------------------------
-- Potion ready again: when a potion in your bags goes on its long cooldown, we wait for it to end
--------------------------------------------------------------------------------
local ItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local potionUntil, potionItem = 0, nil

local function IsPotion(itemID)
    if not ItemInfoInstant then return false end
    local ok, _, _, _, _, _, classID, subClassID = pcall(ItemInfoInstant, itemID)
    return ok and classID == 0 and subClassID == 1
end

local function PotionReady()
    if GetTime() < potionUntil - 0.2 then return end
    potionUntil = 0
    if not db.potion then return end
    if db.potionCombat and not InCombatLockdown() then return end
    if potionItem and ItemCount and (ItemCount(potionItem) or 0) == 0 then return end
    local icon = potionItem and ItemInfoInstant and select(5, ItemInfoInstant(potionItem))
    Alert("Potion ready", icon or "Interface\\Icons\\INV_Potion_54", 0.4, 1, 0.4, true)
end

local function ScanPotions()
    if not db.potion or not (C_Container and C_Container.GetContainerNumSlots) then return end
    if potionUntil > GetTime() then return end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and IsPotion(id) then
                local start, duration = C_Container.GetContainerItemCooldown(bag, slot)
                if type(start) == "number" and type(duration) == "number" and not Secret(start) and not Secret(duration)
                    and start > 0 and duration > 30 then
                    potionUntil, potionItem = start + duration, id
                    C_Timer.After(potionUntil - GetTime() + 0.1, PotionReady)
                    return
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Pet: Hunters and Warlocks who know how to call one
--------------------------------------------------------------------------------
local _, CLASS = UnitClass("player")
local PET_SPELL = { HUNTER = 883, WARLOCK = 688 } -- Call Pet, Summon Imp
local lastPet = 0

local function KnowsPet()
    local id = PET_SPELL[CLASS]
    if not id then return false end
    if IsPlayerSpell then local ok, v = pcall(IsPlayerSpell, id); if ok and v then return true end end
    if IsSpellKnown then local ok, v = pcall(IsSpellKnown, id); if ok and v then return true end end
    return false
end

local function CheckPet(force)
    if not db.pet or not KnowsPet() then return end
    if UnitIsDeadOrGhost("player") or IsMounted() or (UnitOnTaxi and UnitOnTaxi("player")) then return end
    if UnitInVehicle and UnitInVehicle("player") then return end
    if not db.petResting and IsResting() and not InCombatLockdown() then return end
    if not force and GetTime() - lastPet < 60 then return end
    local msg
    if not UnitExists("pet") then
        msg = "No pet out"
    elseif UnitIsDead("pet") then
        msg = "Your pet is dead"
    end
    if msg then
        lastPet = GetTime()
        Alert(msg, CLASS == "HUNTER" and "Interface\\Icons\\Ability_Hunter_BeastCall" or "Interface\\Icons\\Spell_Shadow_SummonImp",
            1, 0.55, 0.2, InCombatLockdown())
    end
end

--------------------------------------------------------------------------------
-- Group member died (read from the game's dead flag; if the game locks it, that player is skipped)
--------------------------------------------------------------------------------
local dead = {}
local function IsDeadNow(unit)
    local ok, v = pcall(UnitIsDead, unit)
    if not ok or Secret(v) then return nil end
    if v and UnitIsFeignDeath then
        local okF, f = pcall(UnitIsFeignDeath, unit)
        if okF and not Secret(f) and f then return false end
    end
    return v and true or false
end

local function GroupUnit(unit)
    return type(unit) == "string" and (unit:match("^party%d$") or unit:match("^raid%d+$")) and true or false
end

local function SnapshotGroup()
    wipe(dead)
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local unit = prefix .. i
        local guid = UnitExists(unit) and UnitGUID(unit)
        if guid and not Secret(guid) then dead[guid] = IsDeadNow(unit) end
    end
end

local function OnHealth(unit)
    if not db.death or not GroupUnit(unit) or UnitIsUnit(unit, "player") then return end
    if IsInRaid() and unit:match("^party") then return end
    local guid = UnitGUID(unit)
    if not guid or Secret(guid) then return end
    local now = IsDeadNow(unit)
    if now == nil then return end
    if now and dead[guid] == false then
        local name = UnitName(unit)
        if name and not Secret(name) then
            local _, class = UnitClass(unit)
            local cc = class and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            local hex = cc and string.format("|cFF%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) or "|cFFFFFFFF"
            Alert(hex .. name .. "|r died", "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 1, 0.3, 0.3, db.deathSound)
        end
    end
    dead[guid] = now
end


--------------------------------------------------------------------------------
-- Healer low on mana: one line per drop under the line (and one more under the critical line); it re-arms once
-- they are back 10% above the line. Healers are the members marked Healer; if nobody is marked, the classes that
-- can heal (Priest, Druid, Paladin, Shaman). On WoW Forever another player's mana may be locked in a fight: then
-- nothing shows for them until the game hands it over again.
--------------------------------------------------------------------------------
local HEAL_CLASS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }
local REARM = 10
local manaStage = {}   -- guid -> 0 armed, 1 low shown, 2 critical shown

local function ClassHex(unit)
    local _, class = UnitClass(unit)
    local cc = class and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return cc and string.format("|cFF%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) or "|cFFFFFFFF"
end

local function Role(unit)
    if not UnitGroupRolesAssigned then return nil end
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if not ok or Secret(r) then return nil end
    return r
end

local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
    elseif IsInGroup() then
        list[1] = "player"
        for i = 1, 4 do list[#list + 1] = "party" .. i end
    end
    return list
end

local healers, anyRole = {}, false
local function FindHealers()
    wipe(healers)
    anyRole = false
    for _, u in ipairs(GroupUnits()) do
        if UnitExists(u) and Role(u) == "HEALER" then
            anyRole = true
            local g = UnitGUID(u)
            if g and not Secret(g) then healers[g] = true end
        end
    end
end

local function IsHealer(unit)
    if anyRole then
        local g = UnitGUID(unit)
        return g and not Secret(g) and healers[g] or false
    end
    local _, class = UnitClass(unit)
    return class and not Secret(class) and HEAL_CLASS[class] or false
end

local function CheckMana(unit)
    if not db.healerMana or not IsInGroup() then return end
    if unit ~= "player" and not GroupUnit(unit) then return end
    if IsInRaid() and unit:match("^party") then return end
    local isMe = UnitIsUnit(unit, "player")
    if isMe and not db.healerManaSelf then return end
    if db.healerManaInstance then
        local inInst, kind = IsInInstance()
        if not inInst or (kind ~= "party" and kind ~= "raid") then return end
    end
    if db.healerManaCombat and not InCombatLockdown() then return end
    if not UnitExists(unit) or not IsHealer(unit) then return end
    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return end
    local okT, ptype = pcall(UnitPowerType, unit)
    if not okT or Secret(ptype) or ptype ~= 0 then return end -- a Druid in a form shows no mana
    local ok1, cur = pcall(UnitPower, unit, 0)
    local ok2, max = pcall(UnitPowerMax, unit, 0)
    if not (ok1 and ok2) or Secret(cur) or Secret(max) or type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return end
    local guid = UnitGUID(unit)
    if not guid or Secret(guid) then return end
    local pct = cur / max * 100
    local stage = manaStage[guid] or 0
    local low, crit = db.healerManaPct, db.healerManaCrit
    if pct >= low + REARM then manaStage[guid] = 0 return end
    local name = UnitName(unit)
    if not name or Secret(name) then return end
    local who = ClassHex(unit) .. name .. "|r " .. math.floor(pct) .. "%"
    if crit > 0 and crit < low and pct < crit and stage < 2 then
        manaStage[guid] = 2
        Alert("Healer out of mana: " .. who, "Interface\\Icons\\INV_Potion_76", 1, 0.35, 0.35, true)
    elseif pct < low and stage < 1 then
        manaStage[guid] = 1
        Alert("Healer low mana: " .. who, "Interface\\Icons\\INV_Potion_76", 0.45, 0.75, 1, true)
    end
end

--------------------------------------------------------------------------------
-- Zeroes the XP: on WoW Forever kill XP in an instance is zero for the whole group once its highest member is 13+
-- levels over the mob. Each dungeon's mob levels are learned as you see them (nameplates, target, mouse-over;
-- bosses and critters left out), saved for the account, so a dungeon you have not been in yet shows nothing.
-- The box looks like the Group level check (Automation); close it with the X, move it in Layout mode.
--------------------------------------------------------------------------------
CysUIDB.dungeonMobs = CysUIDB.dungeonMobs or {}
local mobs = CysUIDB.dungeonMobs
local SKIP_TYPE = { Critter = true, ["Non-combat Pet"] = true, Totem = true, ["Wild Pet"] = true }

local function CurrentInstance()
    local name, kind, _, _, _, _, _, id = GetInstanceInfo()
    if (kind == "party" or kind == "raid") and id then return id, name end
end

local CheckZeroXP -- below
local function LearnMob(unit)
    if not unit or not UnitExists(unit) then return end
    local id, zone = CurrentInstance()
    if not id then return end
    if UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return end
    local okA, attack = pcall(UnitCanAttack, "player", unit)
    if not okA or Secret(attack) or not attack then return end
    local okL, lvl = pcall(UnitLevel, unit)
    if not okL or Secret(lvl) or type(lvl) ~= "number" or lvl <= 1 then return end -- -1 = boss / skull
    local okC, cls = pcall(UnitClassification, unit)
    if okC and not Secret(cls) and (cls == "worldboss" or cls == "trivial" or cls == "minus") then return end
    local okT, ctype = pcall(UnitCreatureType, unit)
    if okT and not Secret(ctype) and ctype and SKIP_TYPE[ctype] then return end
    local m = mobs[id]
    if not m then m = { min = lvl, max = lvl }; mobs[id] = m end
    m.name = zone or m.name
    local lowered = lvl < m.min
    if lowered then m.min = lvl end
    if lvl > m.max then m.max = lvl end
    if lowered and CheckZeroXP then C_Timer.After(0.5, CheckZeroXP) end
end

local zx, zxText
local function BuildZeroXP()
    if zx then return end
    zx = CreateFrame("Frame", "CysUIZeroXP", UIParent)
    zx:SetSize(300, 60)
    zx:SetFrameStrata("MEDIUM")
    W.Texture(zx, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.92 }):SetAllPoints()
    W.Border(zx, 1, T.border, "BORDER")
    zx.title = W.Text(zx, 12, T.accent)
    zx.title:SetPoint("TOPLEFT", 10, -8)
    zxText = W.Text(zx, 12, T.text)
    zxText:SetPoint("TOPLEFT", 10, -28)
    zxText:SetJustifyV("TOP")
    zxText:SetSpacing(2)
    local x = CreateFrame("Button", nil, zx)
    x:SetSize(18, 18)
    x:SetPoint("TOPRIGHT", -4, -4)
    x.t = W.Text(x, 12, { 1, 1, 1 }, "CENTER")
    x.t:SetPoint("CENTER")
    x.t:SetText("X")
    x:SetScript("OnClick", function() zx:Hide(); zx.dismissed = zx.shownFor end)
    zx:Hide()
    CUI:RegisterMovable(zx, "zeroxp", "Zero XP warning", { point = "TOP", x = 0, y = -300 })
end

CheckZeroXP = function()
    local id, zone = CurrentInstance()
    local m = id and mobs[id]
    if not db.zeroXP or not m then if zx then zx:Hide() end return end
    local limit = m.min + (db.zeroXPGap or 13)
    local over, keys = {}, {}
    local units = IsInGroup() and GroupUnits() or { "player" }
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local lvl = UnitLevel(u)
            local name = UnitName(u)
            if type(lvl) == "number" and not Secret(lvl) and lvl >= limit and name and not Secret(name) then
                over[#over + 1] = ClassHex(u) .. name .. "|r |cFFFF9F43(" .. lvl .. ")|r will zero out the XP here"
                keys[#keys + 1] = name .. lvl
            end
        end
    end
    if #over == 0 then if zx then zx:Hide() end return end
    BuildZeroXP()
    local key = id .. ":" .. table.concat(keys, ",")
    zx.shownFor = key
    if zx.dismissed == key then return end -- closed with the X; shows again if the group or the dungeon changes
    zx.title:SetText(string.format("No kill XP in %s (mobs from level %d)", zone or m.name or "this dungeon", m.min))
    zxText:SetText(table.concat(over, "\n"))
    zx:SetWidth(math.max(260, zx.title:GetStringWidth() + 46, zxText:GetStringWidth() + 24))
    zx:SetHeight(36 + zxText:GetStringHeight() + 8)
    zx:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "BAG_UPDATE_COOLDOWN", "UNIT_PET", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_HEALTH", "UNIT_FLAGS",
    "GROUP_ROSTER_UPDATE", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "PLAYER_ROLES_ASSIGNED", "UNIT_LEVEL",
    "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local loggedIn = false
ev:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if db.healerMana and (... == nil or ... == "MANA") then CheckMana(unit) end
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if db.zeroXP then LearnMob(unit) end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if db.zeroXP then LearnMob("target") end
        return
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if db.zeroXP then LearnMob("mouseover") end
        return
    elseif event == "UNIT_LEVEL" then
        C_Timer.After(1, CheckZeroXP)
        return
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        FindHealers()
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        if unit == "pet" then if not InCombatLockdown() then C_Timer.After(1, function() CheckPet(false) end) end return end
        OnHealth(unit)
    elseif event == "PLAYER_ENTERING_WORLD" then
        SnapshotGroup()
        FindHealers()
        wipe(manaStage)
        if zx then zx.dismissed = nil end
        C_Timer.After(2, CheckZeroXP)
        if not loggedIn then
            loggedIn = true
            C_Timer.After(6, CheckTalents)
        end
        C_Timer.After(5, function() CheckPet(false) end)
        ScanPotions()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(3, CheckTalents)
        C_Timer.After(1, CheckZeroXP)
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ScanPotions()
    elseif event == "GROUP_ROSTER_UPDATE" then
        SnapshotGroup()
        FindHealers()
        C_Timer.After(1, CheckZeroXP)
    elseif event == "PLAYER_REGEN_DISABLED" then
        CheckPet(true)
    elseif event == "UNIT_PET" then
        if unit == "player" and not InCombatLockdown() then C_Timer.After(3, function() CheckPet(false) end) end
    else -- dismounted, alive again, combat over
        C_Timer.After(3, function() if not InCombatLockdown() then CheckPet(false) end end)
    end
end)

SLASH_CYSUIALERTS1 = "/cuialerts"
SlashCmdList.CYSUIALERTS = function(msg)
    if type(msg) == "string" and strtrim(msg):lower() == "xp" then -- the page's test button passes itself
        local id, zone = CurrentInstance()
        local n = 0
        for _ in pairs(mobs) do n = n + 1 end
        print("|cFFE6B85C[Cys's Alerts]|r Dungeons learned: " .. n .. ".")
        if id then
            local m = mobs[id]
            print(m and string.format("  %s: mobs %d-%d seen, XP zeroed from level %d.", zone or "?", m.min, m.max,
                m.min + (db.zeroXPGap or 13)) or ("  " .. (zone or "This dungeon") .. ": no mobs seen yet."))
        end
        return
    end
    Alert("Cys's Alerts show here", "Interface\\Icons\\INV_Misc_Bell_01", nil, nil, nil, true)
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Alerts", function(page)
    local width = 480
    W.Header(page, "Alerts", width):SetPoint("TOPLEFT", 0, -4)
    local y = -36
    local function Check(text, key, fn)
        W.Checkbox(page, text, function() return db[key] end, function(v) db[key] = v; if fn then fn() end end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Unspent talent points (after a level up and at login)", "talents")
    Check("Potion ready again", "potion")
    Check("   ... only during a fight", "potionCombat")
    Check("No pet out, or your pet is dead (Hunter, Warlock)", "pet")
    Check("   ... also in cities and inns", "petResting")
    Check("Someone in your group died", "death")
    Check("A group healer is low on mana", "healerMana")
    Check("   ... only in dungeons and raids", "healerManaInstance")
    Check("   ... only during a fight", "healerManaCombat")
    Check("   ... also for yourself", "healerManaSelf")
    W.Stepper(page, "   Low mana at", function() return db.healerManaPct end, function(v) db.healerManaPct = v end, 10, 60, 5, "%")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 28
    W.Stepper(page, "   Critical at (0 = off)", function() return db.healerManaCrit end, function(v) db.healerManaCrit = v end, 0, 40, 5, "%")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 30
    Check("Someone's level zeroes the XP in this dungeon", "zeroXP", CheckZeroXP)
    y = y - 8
    Check("Play a sound (potion ready, no pet in a fight)", "sound")
    Check("Play a sound when someone in the group dies", "deathSound")
    y = y - 8
    W.Stepper(page, "Text size", function() return db.size end, function(v) db.size = v; ApplyFont() end, 12, 26, 1)
        :SetPoint("TOPLEFT", 4, y)
    y = y - 28
    W.Stepper(page, "Seconds on screen", function() return db.hold end, function(v) db.hold = v end, 2, 10, 1, " s")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 34
    local test = W.Button(page, 130, 24, "Show a test", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", function() SlashCmdList.CYSUIALERTS("") end)
    y = y - 40
    local note = W.Notes(page, 4, y, width, "", {
        { "Where", "the alerts show in one spot near the middle of the screen. Move it in Layout mode (box: Alerts). /cuialerts shows a test line." },
        { "Group deaths", "come from the game's dead flag. If the game keeps it locked during a fight, that death is not shown." },
        { "Warlocks", "who sacrifice their demon on purpose can switch the pet alert off here." },
        { "Healer mana", "goes by the group's Healer role; if nobody has one, by class (Priest, Druid, Paladin, Shaman). It shows once per drop and again only after they get back 10% above the line. A Druid in a form is skipped. If WoW Forever locks other players' mana in a fight, nothing shows until it unlocks." },
        { "Zero XP", "WoW Forever gives no kill XP to the whole group once its highest member is 13 or more levels above the mob. Cys's UI learns each dungeon's mob levels as you see them (saved for all your characters), so a dungeon is only checked once you have seen its mobs. The box lists who is too high; close it with the X (it comes back if the group changes) and move it in Layout mode (box: Zero XP warning). /cuialerts xp shows what is learned." },
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 100) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
