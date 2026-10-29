--------------------------------------------------------------------------------
-- Cys's Warrior - warrior-only helpers
--   * "BATTLE SHOUT MISSING" alert when you don't have the buff (move it in layout mode)
-- Debuff tracking (Sunder, Thunder Clap...) lives in Cys's Raid Debuffs, which works for every class.
-- Switch it off on the Warrior page of /cui, or the whole module under Modules.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "warrior", name = "Cys's Warrior", class = "WARRIOR",
    desc = "Warrior only: a Battle Shout missing alert (hidden in towns by default). Debuff tracking is in Cys's Raid Debuffs.",
    open = function() CysUI:OpenConfig("Warrior") end,
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

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Warrior", function(page)
    local width = 480
    W.Header(page, "Battle Shout alert", width):SetPoint("TOPLEFT", 0, -4)
    W.Checkbox(page, "Show \"Battle Shout missing\" when you don't have the buff", function() return db.shout end,
        function(on) db.shout = on; UpdateAlert() end):SetPoint("TOPLEFT", 4, -34)
    W.Checkbox(page, "Only when I'm in a group", function() return db.shoutGroupOnly end,
        function(on) db.shoutGroupOnly = on; UpdateAlert() end):SetPoint("TOPLEFT", 4, -60)

    W.Checkbox(page, "Hide it while resting (towns and inns)", function() return db.shoutHideResting end,
        function(on) db.shoutHideResting = on; UpdateAlert() end):SetPoint("TOPLEFT", 4, -86)
    W.Checkbox(page, "Only in combat", function() return db.shoutCombatOnly end,
        function(on) db.shoutCombatOnly = on; UpdateAlert() end):SetPoint("TOPLEFT", 4, -112)

    local move = W.Button(page, 240, 22, "Move the alert (layout mode)")
    move:SetPoint("TOPLEFT", 4, -150)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -188)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Debuff tracking for Sunder Armor, Thunder Clap and the rest moved to the Raid Debuffs page, "
        .. "which works for every class and only shows effects your group can apply.")
    page.contentHeight = 260
end)

    end,
})
