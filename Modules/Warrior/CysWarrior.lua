--------------------------------------------------------------------------------
-- Cys's Warrior - warrior-only helpers (plus a Battle Shout reminder for the other classes, at the bottom)
--   * "BATTLE SHOUT MISSING" alert when you don't have the buff (move it in layout mode)
-- Debuff tracking (Sunder, Thunder Clap...) lives in Cys's Raid Debuffs, which works for every class.
-- Switch it off on the Battle Shout page of /cui (Class > Warrior), or the whole module under Modules.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "warrior", name = "Cys's Warrior", class = "WARRIOR",
    desc = "Warrior only: a Battle Shout missing alert (hidden in towns by default). Debuff tracking is in Cys's Raid Debuffs.",
    open = function() CysUI:OpenConfig("Battle Shout") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local floor, max, min = math.floor, math.max, math.min

CysUIDB.warrior = CysUIDB.warrior or {}
local db = CysUIDB.warrior
local DEFAULTS = { shout = true, shoutGroupOnly = false, shoutHideResting = true, shoutCombatOnly = false }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local function SpellName(id, fallback)
    local n = GetSpellInfo and GetSpellInfo(id)
    return n or fallback
end

--------------------------------------------------------------------------------
-- Battle Shout missing
--------------------------------------------------------------------------------
local BATTLE_SHOUT = SpellName(6673, "Battle Shout")

local alert = CreateFrame("Frame", "CysWarriorShoutAlert", UIParent)
alert:SetSize(360, 40)
alert.text = alert:CreateFontString(nil, "OVERLAY")
alert.text:SetFont(STANDARD_TEXT_FONT, 28, "OUTLINE")
alert.text:SetPoint("CENTER")
alert.text:SetTextColor(1, 0.35, 0.25)
alert.text:SetText("BATTLE SHOUT MISSING")
alert:Hide()
CUI:RegisterMovable(alert, "warriorshout", "Battle Shout Alert", { point = "CENTER", x = 0, y = 220 })

-- every rank of Battle Shout: the first rank's ID stops counting once a higher rank replaces it
local SHOUT_RANKS = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local function ShoutKnown()
    for _, id in ipairs(SHOUT_RANKS) do
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
        if IsSpellKnown and IsSpellKnown(id) then return true end
    end
    -- last resort: the spell book knows the name
    if GetSpellInfo and GetSpellInfo(BATTLE_SHOUT) and GetSpellCooldown and GetSpellCooldown(BATTLE_SHOUT) then return true end
    return false
end

local function HasBuff(name)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if n == name then return true end
    end
    return false
end

local function UpdateAlert()
    local show = db.shout and ShoutKnown() and not UnitIsDeadOrGhost("player")
        and not (IsMounted and IsMounted()) and not (UnitOnTaxi and UnitOnTaxi("player"))
        and not (UnitInVehicle and UnitInVehicle("player"))
        and (not db.shoutGroupOnly or (IsInGroup and IsInGroup()))
        and not (db.shoutHideResting and IsResting and IsResting())
        and (not db.shoutCombatOnly or (InCombatLockdown and InCombatLockdown()))
        and not HasBuff(BATTLE_SHOUT)
    alert:SetShown(show and true or false)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED",
                     "GROUP_ROSTER_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING",
                     "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
ev:SetScript("OnEvent", function() UpdateAlert() end)
UpdateAlert()

CUI.WarriorRefresh = UpdateAlert -- the settings page (below, built for every class) calls this

    end,
})

--------------------------------------------------------------------------------
-- Battle Shout reminder for everyone else
-- Battle Shout is a level 2 Warrior spell, so a Warrior in your group can always give you the attack power.
-- This shows "BATTLE SHOUT MISSING - ask your Warrior" when a Warrior is with you and you lack the buff.
-- On by default for melee classes (Rogue, Hunter, Paladin, Shaman, Druid); anyone else can switch it on.
--------------------------------------------------------------------------------
local CUI, W = CysUI, CysUI.W
local T = W.T
local _, myClass = UnitClass("player")
local MELEE = { ROGUE = true, HUNTER = true, PALADIN = true, SHAMAN = true, DRUID = true }
local PAGE_DEFAULTS = { shout = true, shoutGroupOnly = false, shoutHideResting = true, shoutCombatOnly = false }

local function WDB()
    CysUIDB.warrior = CysUIDB.warrior or {}
    local db = CysUIDB.warrior
    for k, v in pairs(PAGE_DEFAULTS) do if db[k] == nil then db[k] = v end end
    if db.remind == nil then db.remind = MELEE[myClass] and true or false end
    return db
end

local remindFrame
local function WarriorInGroup()
    local n = (IsInRaid and IsInRaid()) and GetNumGroupMembers() or 4
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
            and UnitIsVisible(u) and select(2, UnitClass(u)) == "WARRIOR" then
            return true
        end
    end
    return false
end

local function HasShout()
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if n == "Battle Shout" then return true end
    end
    return false
end

local function UpdateReminder()
    if not remindFrame then return end
    local db = WDB()
    local show = db.remind and not UnitIsDeadOrGhost("player")
        and not (IsMounted and IsMounted()) and not (UnitOnTaxi and UnitOnTaxi("player"))
        and not (db.shoutHideResting and IsResting and IsResting())
        and (not db.shoutCombatOnly or (InCombatLockdown and InCombatLockdown()))
        and IsInGroup and IsInGroup() and WarriorInGroup() and not HasShout()
    remindFrame:SetShown(show and true or false)
end

local function EnableReminder()
    if myClass == "WARRIOR" then return end
    remindFrame = CreateFrame("Frame", "CysShoutReminder", UIParent)
    remindFrame:SetSize(420, 40)
    remindFrame.text = remindFrame:CreateFontString(nil, "OVERLAY")
    remindFrame.text:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
    remindFrame.text:SetPoint("CENTER")
    remindFrame.text:SetTextColor(1, 0.35, 0.25)
    remindFrame.text:SetText("BATTLE SHOUT MISSING - ask your Warrior")
    remindFrame:Hide()
    CUI:RegisterMovable(remindFrame, "shoutremind", "Battle Shout Reminder", { point = "CENTER", x = 0, y = 220 })
    CUI.ShoutRemindRefresh = UpdateReminder
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "GROUP_ROSTER_UPDATE",
                         "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
    ev:SetScript("OnEvent", UpdateReminder)
    C_Timer.NewTicker(2, UpdateReminder) -- a Warrior walking into range does not fire an event
    UpdateReminder()
end

CysUI:RegisterModule({
    key = "shoutremind", name = "Battle Shout Reminder",
    class = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK" },
    desc = "Shows 'Battle Shout missing - ask your Warrior' when a Warrior is in your group and you do not have the buff. On by default for melee classes.",
    onEnable = EnableReminder,
    open = function() CysUI:OpenConfig("Battle Shout") end,
})

--------------------------------------------------------------------------------
-- Settings page: built for every class (listed under Class > Warrior) so the Class section shows what
-- Warriors have. Warriors get the alert for their own buff; every other class gets the reminder options.
--------------------------------------------------------------------------------
CUI:RegisterPage("Battle Shout", function(page)
    local db = WDB()
    local isWarrior = myClass == "WARRIOR"
    local function Refresh()
        if CUI.WarriorRefresh then CUI.WarriorRefresh() end
        if CUI.ShoutRemindRefresh then CUI.ShoutRemindRefresh() end
    end
    local width = 480
    W.Header(page, isWarrior and "Battle Shout alert" or "Battle Shout reminder", width):SetPoint("TOPLEFT", 0, -4)

    local y = -34
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, y)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    if isWarrior then
        intro:SetText("Shows \"BATTLE SHOUT MISSING\" when you do not have your own buff.")
        y = y - 30
    else
        intro:SetText("Battle Shout is a Warrior spell that gives melee attack power. When a Warrior is in your group and you do not have the buff, this shows \"BATTLE SHOUT MISSING - ask your Warrior\". It is on by default for Rogues, Hunters, Paladins, Shamans and Druids; healers and casters gain nothing from it, so it starts off for them.")
        y = y - 78
    end
    local function Check(label, key)
        W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; Refresh() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    if isWarrior then
        Check("Show \"Battle Shout missing\" when you don't have the buff", "shout")
        Check("Only when I'm in a group", "shoutGroupOnly")
    else
        Check("Remind me when a Warrior in my group could buff me", "remind")
    end
    Check("Hide it while resting (towns and inns)", "shoutHideResting")
    Check("Only in combat", "shoutCombatOnly")

    y = y - 12
    local move = W.Button(page, 240, 22, "Move the alert (layout mode)")
    move:SetPoint("TOPLEFT", 4, y)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    y = y - 38

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, y)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Debuff tracking for Sunder Armor, Thunder Clap and the rest moved to the Raid Debuffs page, "
        .. "which works for every class and only shows effects your group can apply.")
    page.contentHeight = 340
end, nil, "WARRIOR")
