--------------------------------------------------------------------------------
-- Cys's Alerts - short on-screen notes for the things that are easy to miss
--
--   * unspent talent points (after a level up, and once when you log in)
--   * your potion is ready again (by default only during a fight)
--   * no pet out (Hunters and Warlocks who know how to call one) or your pet is dead
--   * someone in your group died
--
-- Each alert has its own switch. Lines appear in one spot (move it in Layout mode), stack up to three, and
-- fade after a few seconds. Nothing is said in chat.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "alerts", name = "Cys's Alerts",
    desc = "Short on-screen notes for things that are easy to miss: unspent talent points, potion ready again, no pet out (Hunter, Warlock) and group members dying. Each alert has its own switch.",
    open = function() CysUI:OpenConfig("Alerts") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Secret = CysUICompat and CysUICompat.Secret or function() return false end

CysUIDB.alerts = CysUIDB.alerts or {}
local db = CysUIDB.alerts
local DEFAULTS = { talents = true, potion = true, potionCombat = true, pet = true, petResting = false, death = true,
    sound = true, deathSound = false, size = 16, hold = 4 }
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
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "BAG_UPDATE_COOLDOWN", "UNIT_PET", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_HEALTH", "UNIT_FLAGS",
    "GROUP_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local loggedIn = false
ev:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        if unit == "pet" then if not InCombatLockdown() then C_Timer.After(1, function() CheckPet(false) end) end return end
        OnHealth(unit)
    elseif event == "PLAYER_ENTERING_WORLD" then
        SnapshotGroup()
        if not loggedIn then
            loggedIn = true
            C_Timer.After(6, CheckTalents)
        end
        C_Timer.After(5, function() CheckPet(false) end)
        ScanPotions()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(3, CheckTalents)
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ScanPotions()
    elseif event == "GROUP_ROSTER_UPDATE" then
        SnapshotGroup()
    elseif event == "PLAYER_REGEN_DISABLED" then
        CheckPet(true)
    elseif event == "UNIT_PET" then
        if unit == "player" and not InCombatLockdown() then C_Timer.After(3, function() CheckPet(false) end) end
    else -- dismounted, alive again, combat over
        C_Timer.After(3, function() if not InCombatLockdown() then CheckPet(false) end end)
    end
end)

SLASH_CYSUIALERTS1 = "/cuialerts"
SlashCmdList.CYSUIALERTS = function()
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
    test:SetScript("OnClick", SlashCmdList.CYSUIALERTS)
    y = y - 40
    local note = W.Notes(page, 4, y, width, "", {
        { "Where", "the alerts show in one spot near the middle of the screen. Move it in Layout mode (box: Alerts). /cuialerts shows a test line." },
        { "Group deaths", "come from the game's dead flag. If the game keeps it locked during a fight, that death is not shown." },
        { "Warlocks", "who sacrifice their demon on purpose can switch the pet alert off here." },
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 100) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
