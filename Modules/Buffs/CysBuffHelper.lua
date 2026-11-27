--------------------------------------------------------------------------------
-- Cys's UI - Buff Helper
--
-- A small bar of buttons, one per person in your group who is missing a buff YOU can cast.
-- Click a button to cast that buff on that person. Hidden when nothing is missing, and in combat.
--   * Priest: Power Word: Fortitude, Divine Spirit, Shadow Protection
--   * Druid: Mark of the Wild, Thorns (tanks)
--   * Mage: Arcane Intellect (mana users)
--   * Paladin (PallyPower-style): Wisdom for casters, Might for melee, Kings for tanks, set per class.
--     Only people without one of YOUR blessings show; a blessing another paladin already gave is skipped.
-- Placed in Layout mode (Buff Helper). Settings: /cui -> Buff Helper. /cuibuff tank marks your target as a tank.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "buffhelper", name = "Buff Helper",
    desc = "Click-to-buff bar: one button per group member missing a buff you can cast (Fortitude, Mark, Intellect, Paladin blessings by role). Hidden in combat and when nobody needs anything.",
    open = function() CysUI:OpenConfig("Buff Helper") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Compat = CysUICompat

CysUIDB.buffHelper = CysUIDB.buffHelper or {}
local db = CysUIDB.buffHelper
for k, v in pairs({ fort = true, spirit = true, shadow = false, motw = true, thorns = false, int = true,
                    bless = true, size = 32, max = 8, early = 60, tankBless = "kings" }) do
    if db[k] == nil then db[k] = v end
end
db.pal = db.pal or {}
db.tanks = db.tanks or {}

local MOVER = "buffhelper"
local MAXBTN = 15

local function Set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local ALL = Set({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" })
local MANA = Set({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK" })

-- Plain buffs: spell you cast, aura names that count, who needs it ("tank" = tanks only)
local BUFFS = {
    { key = "fort",   class = "PRIEST", spell = "Power Word: Fortitude", label = "Fortitude",
      auras = { "Power Word: Fortitude", "Prayer of Fortitude" }, needs = ALL },
    { key = "spirit", class = "PRIEST", spell = "Divine Spirit", label = "Divine Spirit",
      auras = { "Divine Spirit", "Prayer of Spirit" }, needs = MANA },
    { key = "shadow", class = "PRIEST", spell = "Shadow Protection", label = "Shadow Protection",
      auras = { "Shadow Protection", "Prayer of Shadow Protection" }, needs = ALL },
    { key = "motw",   class = "DRUID", spell = "Mark of the Wild", label = "Mark of the Wild",
      auras = { "Mark of the Wild", "Gift of the Wild" }, needs = ALL },
    { key = "thorns", class = "DRUID", spell = "Thorns", label = "Thorns (tanks)",
      auras = { "Thorns" }, needs = "tank" },
    { key = "int",    class = "MAGE", spell = "Arcane Intellect", label = "Arcane Intellect",
      auras = { "Arcane Intellect", "Arcane Brilliance" }, needs = MANA },
}

-- Paladin blessings
local BLESS = {
    wisdom    = { "Blessing of Wisdom", "Greater Blessing of Wisdom", label = "Wisdom" },
    might     = { "Blessing of Might", "Greater Blessing of Might", label = "Might" },
    kings     = { "Blessing of Kings", "Greater Blessing of Kings", label = "Kings" },
    salvation = { "Blessing of Salvation", "Greater Blessing of Salvation", label = "Salvation" },
    light     = { "Blessing of Light", "Greater Blessing of Light", label = "Light" },
}
local BLESS_ORDER = { "wisdom", "might", "kings", "salvation", "light" }  -- no Sanctuary: WoW Forever removed it
local PAL_CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }

local function Secret(v) return Compat and Compat.Secret and Compat.Secret(v) end

--------------------------------------------------------------------------------
-- Spells I know (scanned from the spellbook)
--------------------------------------------------------------------------------
local known = {}
local function ScanSpells()
    wipe(known)
    local BookName = GetSpellBookItemName or (C_SpellBook and C_SpellBook.GetSpellBookItemName)
    local tabs = (GetNumSpellTabs and GetNumSpellTabs()) or 0
    if not BookName or tabs == 0 then return end
    for t = 1, tabs do
        local _, _, offset, num = GetSpellTabInfo(t)
        for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
            local ok, name = pcall(BookName, i, BOOKTYPE_SPELL or "spell")
            if ok and type(name) == "string" then known[name] = true end
        end
    end
end
local function Knows(spell) return known[spell] end

--------------------------------------------------------------------------------
-- Auras: what does the unit have from this list?
--   returns state ("none" / "mine" / "other" / "unknown"), seconds left (or nil), aura name
--------------------------------------------------------------------------------
local function Mine(src)
    if src == nil or Secret(src) then return nil end
    return UnitIsUnit(src, "player") and true or false
end

local function Left(exp)
    if type(exp) ~= "number" or Secret(exp) or exp <= 0 then return nil end
    return exp - GetTime()
end

local function AuraState(unit, names)
    local GetBy = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if GetBy then
        local best, unknown
        for _, n in ipairs(names) do
            local ok, a = pcall(GetBy, unit, n, "HELPFUL")
            if not ok then
                unknown = true
            elseif a then
                local m = Mine(a.sourceUnit)
                local st = (m == true and "mine") or (m == false and "other") or "unknown"
                if st == "mine" then return st, Left(a.expirationTime), n end
                best = best or { st, Left(a.expirationTime), n }
            end
        end
        if best then return best[1], best[2], best[3] end
        if not unknown then return "none" end
    end
    -- older path: walk the buffs
    if UnitBuff then
        local found
        for i = 1, 40 do
            local ok, name, _, _, _, _, exp, src = pcall(UnitBuff, unit, i)
            if not ok then return "unknown" end
            if not name then break end
            if Secret(name) then
                found = found or { "unknown" }
            else
                for _, n in ipairs(names) do
                    if name == n then
                        local m = Mine(src)
                        local st = (m == true and "mine") or (m == false and "other") or "unknown"
                        if st == "mine" then return st, Left(exp), n end
                        found = found or { st, Left(exp), n }
                    end
                end
            end
        end
        if found then return found[1], found[2], found[3] end
        return "none"
    end
    return "unknown"
end

local function HasAny(unit, names)
    local st = AuraState(unit, names)
    return st ~= "none"
end

--------------------------------------------------------------------------------
-- Group, roles, range
--------------------------------------------------------------------------------
local function GroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function FullName(unit)
    local n, realm = UnitName(unit)
    if not n or Secret(n) then return nil end
    return n, realm
end

local function IsTank(unit)
    local n = FullName(unit)
    if n and db.tanks[n] then return true end
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        if ok and r == "TANK" then return true end
    end
    if GetPartyAssignment then
        local ok, mt = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and mt then return true end
    end
    local _, c = UnitClass(unit)
    if c == "PALADIN" and HasAny(unit, { "Righteous Fury" }) then return true end
    if c == "DRUID" and HasAny(unit, { "Bear Form", "Dire Bear Form" }) then return true end
    return false
end

local function Role(unit)
    if not UnitGroupRolesAssigned then return nil end
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    return ok and r or nil
end

local function InRange(spell, unit)
    if UnitIsUnit(unit, "player") then return true end
    local f = IsSpellInRange or (C_Spell and C_Spell.IsSpellInRange)
    if f then
        local ok, r = pcall(f, spell, unit)
        if ok and not Secret(r) then
            if r == 1 or r == true then return true end
            if r == 0 or r == false then return false end
        end
    end
    if UnitInRange then
        local ok, r = pcall(UnitInRange, unit)
        if ok and not Secret(r) and r ~= nil then return r and true or false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Paladin: which blessing does this person get?
--------------------------------------------------------------------------------
local function AutoBless(unit, class)
    if class == "WARRIOR" or class == "ROGUE" then return "might" end
    if class == "DRUID" then
        return HasAny(unit, { "Cat Form" }) and "might" or "wisdom"
    end
    if class == "SHAMAN" or class == "PALADIN" then
        return Role(unit) == "DAMAGER" and "might" or "wisdom"
    end
    return "wisdom"   -- mages, warlocks, priests, hunters
end

local function BlessFor(unit, class, tank)
    local first
    if tank then
        first = db.tankBless or "kings"
    else
        local pick = db.pal[class] or "auto"
        first = (pick == "auto") and AutoBless(unit, class) or pick
    end
    if not BLESS[first] then first = "kings" end  -- an old saved pick (Sanctuary) that no longer exists
    local melee = (first == "might")
    -- what to try if the first choice isn't learned or another paladin already gave it
    local chain = { first, "kings", melee and "might" or "wisdom", melee and "wisdom" or "might" }
    -- already has one of MY blessings: done (unless it is running out)
    for _, key in ipairs(BLESS_ORDER) do
        local st, left = AuraState(unit, BLESS[key])
        if st == "mine" then
            if left and db.early > 0 and left < db.early then return key, left end
            return nil
        end
        if st == "unknown" then return nil end   -- can't tell whose it is: leave it alone
    end
    local tried = {}
    for _, key in ipairs(chain) do
        if not tried[key] then
            tried[key] = true
            if Knows(BLESS[key][1]) and AuraState(unit, BLESS[key]) == "none" then return key end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Frame + secure buttons
--------------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "CysBuffHelperAnchor", UIParent)
anchor:SetSize(db.size * 4, db.size + 14)
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
CUI:RegisterMovable(anchor, MOVER, "Buff Helper", { point = "CENTER", x = 0, y = 200 })

local holder = CreateFrame("Frame", "CysBuffHelperBar", anchor, "SecureHandlerStateTemplate")
holder:SetAllPoints()
RegisterStateDriver(holder, "visibility", "[combat] hide; show")

local btns = {}
local function Btn(i)
    if btns[i] then return btns[i] end
    local b = CreateFrame("Button", "CysBuffHelperButton" .. i, holder, "SecureActionButtonTemplate")
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    b:RegisterForClicks(down and "LeftButtonDown" or "LeftButtonUp")
    b:SetAttribute("type", "spell")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.Border(b, 1, T.border, "OVERLAY")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.25)
    b.who = b:CreateFontString(nil, "OVERLAY")
    b.who:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.who:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b.who:SetWidth(db.size + 14)
    b.who:SetWordWrap(false)
    b.time = b:CreateFontString(nil, "OVERLAY")
    b.time:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.time:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        if not self.info then return end
        local t = self.info
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(t.spell, 1, 0.82, 0)
        GameTooltip:AddLine(t.name .. (t.tank and " (tank)" or ""), 1, 1, 1)
        if t.left then GameTooltip:AddLine(format("Running out: %ds left", t.left), 1, 0.6, 0.2) end
        if not t.range then GameTooltip:AddLine("Out of range", 1, 0.3, 0.3) end
        GameTooltip:AddLine("Click to cast.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    btns[i] = b
    return b
end

--------------------------------------------------------------------------------
-- Work out who needs what, then lay out the buttons (out of combat only)
--------------------------------------------------------------------------------
local need = {}
local function Collect()
    wipe(need)
    if UnitIsDeadOrGhost("player") then return end
    local _, myClass = UnitClass("player")
    local mine = {}
    for _, b in ipairs(BUFFS) do
        if b.class == myClass and db[b.key] and Knows(b.spell) then mine[#mine + 1] = b end
    end
    local paladin = myClass == "PALADIN" and db.bless
    if #mine == 0 and not paladin then return end

    for _, u in ipairs(GroupUnits()) do
        local name = FullName(u)
        if name and UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) and UnitIsVisible(u) then
            local _, c = UnitClass(u)
            local tank = IsTank(u)
            for _, b in ipairs(mine) do
                local wants = (b.needs == "tank" and tank) or (type(b.needs) == "table" and b.needs[c])
                if wants then
                    local st, left = AuraState(u, b.auras)
                    local low = (st == "mine" or st == "other") and left and db.early > 0 and left < db.early
                    if st == "none" or low then
                        need[#need + 1] = { unit = u, name = name, class = c, spell = b.spell, tank = tank,
                                            left = low and left or nil, range = InRange(b.spell, u) }
                    end
                end
            end
            if paladin and c then
                local key, left = BlessFor(u, c, tank)
                if key then
                    local spell = BLESS[key][1]
                    need[#need + 1] = { unit = u, name = name, class = c, spell = spell, tank = tank,
                                        left = left, range = InRange(spell, u) }
                end
            end
        end
    end
    -- in range first, then tanks, then running-out last
    table.sort(need, function(a, b)
        if a.range ~= b.range then return a.range end
        if a.tank ~= b.tank then return a.tank end
        if (a.left ~= nil) ~= (b.left ~= nil) then return a.left == nil end
        return a.name < b.name
    end)
end

local function Paint()
    if InCombatLockdown() then return end
    Collect()
    local size = db.size
    local n = math.min(#need, db.max, MAXBTN)
    for i = 1, n do
        local t, b = need[i], Btn(i)
        b.info = t
        b:SetAttribute("spell", t.spell)
        b:SetAttribute("unit", t.unit)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (size + 6), 0)
        b.icon:SetTexture((GetSpellTexture and GetSpellTexture(t.spell)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(not t.range)
        b:SetAlpha(t.range and 1 or 0.45)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[t.class]
        b.who:SetWidth(size + 14)
        b.who:SetText(t.name)
        if cc then b.who:SetTextColor(cc.r, cc.g, cc.b) else b.who:SetTextColor(1, 1, 1) end
        b.time:SetText(t.left and format("%d", t.left) or "")
        b:Show()
    end
    for i = n + 1, #btns do
        btns[i].info = nil
        btns[i]:Hide()
    end
    anchor:SetSize(math.max(n, 1) * (size + 6), size + 14)
end

local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false Paint() end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_AURA",
                     "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ROLES_ASSIGNED", "UNIT_CONNECTION" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, unit)
    if e == "UNIT_AURA" and unit ~= "player" and not (type(unit) == "string" and (unit:find("^party") or unit:find("^raid"))) then
        return
    end
    if e == "SPELLS_CHANGED" or e == "LEARNED_SPELL_IN_TAB" or e == "PLAYER_ENTERING_WORLD" then ScanSpells() end
    Soon()
end)
C_Timer.NewTicker(2, Paint)   -- range and running-out timers
ScanSpells()

--------------------------------------------------------------------------------
-- /cuibuff
--------------------------------------------------------------------------------
local function TankList()
    local t = {}
    for n in pairs(db.tanks) do t[#t + 1] = n end
    table.sort(t)
    return #t > 0 and table.concat(t, ", ") or "none"
end

SLASH_CYSUIBUFF1 = "/cuibuff"
SlashCmdList.CYSUIBUFF = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "tank" then
        local n = rest ~= "" and rest or (UnitExists("target") and UnitIsPlayer("target") and FullName("target"))
        if not n then CUI:Print("Buff Helper: target a player or type /cuibuff tank Name.") return end
        n = n:sub(1, 1):upper() .. n:sub(2)
        db.tanks[n] = not db.tanks[n] or nil
        CUI:Print(format("Buff Helper: %s is %s a tank. Tanks: %s", n, db.tanks[n] and "now" or "no longer", TankList()))
        Soon()
    elseif cmd == "tanks" then
        CUI:Print("Buff Helper tanks you marked: " .. TankList())
    elseif cmd == "clear" then
        wipe(db.tanks)
        CUI:Print("Buff Helper: tank list cleared.")
        Soon()
    else
        CUI:Print("/cuibuff tank [Name] - mark or unmark a tank (your target if no name). /cuibuff tanks - list. /cuibuff clear - clear the list.")
    end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Buff Helper", function(page)
    local width = 480
    W.Header(page, "Buff Helper", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("One button per person missing a buff you can cast; click it to cast. Name under the button, grey when out of range, a number when the buff is running out. Hidden in combat and when nobody needs anything. Move it in Layout mode.")

    local y = -100
    local lastClass
    for _, b in ipairs(BUFFS) do
        if b.class ~= lastClass then
            local h = W.Text(page, 12, T.accent)
            h:SetPoint("TOPLEFT", 4, y)
            h:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[b.class]) or b.class)
            y = y - 20
            lastClass = b.class
        end
        W.Checkbox(page, b.label, function() return db[b.key] end, function(on) db[b.key] = on Soon() end):SetPoint("TOPLEFT", 12, y)
        y = y - 26
    end

    local h = W.Text(page, 12, T.accent)
    h:SetPoint("TOPLEFT", 4, y)
    h:SetText("Paladin")
    y = y - 20
    W.Checkbox(page, "Blessings", function() return db.bless end, function(on) db.bless = on Soon() end):SetPoint("TOPLEFT", 12, y)
    y = y - 30

    local opts = {}
    for _, k in ipairs(BLESS_ORDER) do opts[#opts + 1] = { k, BLESS[k].label } end
    local autoOpts = { { "auto", "Auto" } }
    for _, o in ipairs(opts) do autoOpts[#autoOpts + 1] = o end

    local lbl = W.Text(page, 12, T.text)
    lbl:SetPoint("TOPLEFT", 12, y - 4)
    lbl:SetText("Tanks")
    W.Dropdown(page, 140, opts, function() return db.tankBless end, function(v) db.tankBless = v Soon() end)
        :SetPoint("TOPLEFT", 110, y)
    y = y - 28
    for i, c in ipairs(PAL_CLASSES) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 12 + col * 236
        local l = W.Text(page, 12, T.text)
        l:SetPoint("TOPLEFT", x, y - row * 28 - 4)
        l:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c)
        W.Dropdown(page, 120, autoOpts, function() return db.pal[c] or "auto" end,
            function(v) db.pal[c] = (v ~= "auto") and v or nil Soon() end):SetPoint("TOPLEFT", x + 98, y - row * 28)
    end
    y = y - math.ceil(#PAL_CLASSES / 2) * 28 - 8

    W.Stepper(page, "Button size", function() return db.size end, function(v) db.size = v Soon() end, 20, 48, 2, "")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 34
    W.Stepper(page, "Most buttons", function() return db.max end, function(v) db.max = v Soon() end, 1, MAXBTN, 1, "")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 34
    W.Stepper(page, "Rebuff when under", function() return db.early end, function(v) db.early = v Soon() end, 0, 300, 15, "s")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 40

    W.Notes(page, 4, y, width, "", {
        "Auto blessings: Might for Warriors, Rogues, Cat Form Druids and damage-role Shamans/Paladins; Wisdom for everyone else (Hunters too: Might doesn't help ranged attacks). Tanks get the Tanks choice.",
        "If you haven't learned the blessing yet (Kings is a talent) or another paladin already gave it, the next one is used: Kings, then Might or Wisdom.",
        "Tanks: the group's Tank role, raid Main Tanks, Paladins with Righteous Fury, Druids in Bear Form, and anyone you mark with /cuibuff tank (your target) or /cuibuff tank Name.",
        "Rebuff when under: also shows a button when your buff has less time left than this (0 = only when missing).",
        "The Missing Buffs module still shows reminders; turn its icons off for buffs this bar covers if you want just one.",
    })
end)

    end,
})
