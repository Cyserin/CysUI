--------------------------------------------------------------------------------
-- Cys's Raid Debuffs - the raid debuffs that matter on a boss, one box per effect
--
-- Each box shows the effect's category (Armor, Fire, Shadow...). Grey = not on the target, colored icon =
-- it is, with its stack count and timer. Hover for a tooltip. A box only appears if someone in your group
-- (you included) can provide that effect, so a group with no mage has no Fire / Frost boxes.
-- Works for any class. Settings: /cui > Raid Debuffs. Move it in layout mode.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "raiddebuffs", name = "Cys's Raid Debuffs",
    desc = "Tracks the key raid debuffs on your target (armor, fire, shadow, attack power, Hunter's Mark, Judgements...) and only shows the ones your group can apply.",
    open = function() CysUI:OpenConfig("Raid Debuffs") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local max, min, ceil = math.max, math.min, math.ceil

CysUIDB.raidDebuffs = CysUIDB.raidDebuffs or {}
local db = CysUIDB.raidDebuffs
local DEFAULTS = { iconSize = 34, perRow = 5, onlyGroupClasses = true, onlyHostileTarget = true, labels = true, timers = true }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local function SpellName(id, fallback)
    local n = GetSpellInfo and GetSpellInfo(id)
    return n or fallback
end

-- Each category: the spells that fill it, strongest first. { spell id, English name, class that has it }
local CATEGORIES = {
    { label = "Armor", spells = {
        { 8647, "Expose Armor", "ROGUE" }, { 7386, "Sunder Armor", "WARRIOR" }, { 770, "Faerie Fire", "DRUID" },
        { 16857, "Faerie Fire (Feral)", "DRUID" }, { 704, "Curse of Recklessness", "WARLOCK" } } },
    { label = "Fire", spells = { { 22959, "Fire Vulnerability", "MAGE" } }, note = "Improved Scorch" },
    { label = "Frost", spells = { { 12579, "Winter's Chill", "MAGE" } } },
    { label = "Shadow", spells = { { 17800, "Shadow Vulnerability", "WARLOCK" } }, note = "Improved Shadow Bolt" },
    { label = "Curses", spells = {
        { 1490, "Curse of the Elements", "WARLOCK" }, { 17862, "Curse of Shadow", "WARLOCK" } } },
    { label = "Atk Power", short = "A.P.", spells = {
        { 1160, "Demoralizing Shout", "WARRIOR" }, { 99, "Demoralizing Roar", "DRUID" }, { 702, "Curse of Weakness", "WARLOCK" } } },
    { label = "Atk Speed", short = "A.S.", spells = { { 6343, "Thunder Clap", "WARRIOR" } } },
    { label = "Miss", spells = { { 5570, "Insect Swarm", "DRUID" } } },
    { label = "Hunter", spells = { { 1130, "Hunter's Mark", "HUNTER" } } },
    { label = "Judgement", short = "Judge", spells = {
        { 20186, "Judgement of Wisdom", "PALADIN" }, { 20185, "Judgement of Light", "PALADIN" },
        { 21183, "Judgement of the Crusader", "PALADIN" } } },
}

local lookup = {}   -- debuff name -> { cat, rank }
for ci, cat in ipairs(CATEGORIES) do
    for rank, sp in ipairs(cat.spells) do
        sp.name = SpellName(sp[1], sp[2])
        lookup[sp.name] = { cat = ci, rank = rank }
    end
end

local CLASS_NAMES = {}
if LOCALIZED_CLASS_NAMES_MALE then for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE) do CLASS_NAMES[k] = v end end

--------------------------------------------------------------------------------
-- Which classes are in the group (you included)
--------------------------------------------------------------------------------
local present = {}
local function ScanGroup()
    wipe(present)
    local _, mine = UnitClass("player")
    if mine then present[mine] = true end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local _, c = UnitClass("raid" .. i)
            if c then present[c] = true end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local _, c = UnitClass("party" .. i)
            if c then present[c] = true end
        end
    end
end

local function CategoryAvailable(cat)
    if not db.onlyGroupClasses then return true end
    for _, sp in ipairs(cat.spells) do if present[sp[3]] then return true end end
    return false
end

--------------------------------------------------------------------------------
-- The boxes
--------------------------------------------------------------------------------
local holder = CreateFrame("Frame", "CysRaidDebuffs", UIParent)
local LABEL_H = 12
local GAP = 8
local function SizeHolder()
    local s = db.iconSize
    local perRow = db.perRow
    local rows = ceil(#CATEGORIES / perRow)
    holder:SetSize(perRow * (s + GAP) - GAP, rows * (s + LABEL_H + GAP) - GAP)
end
SizeHolder()
CUI:RegisterMovable(holder, "raiddebuffs", "Raid Debuffs", { point = "CENTER", x = 0, y = -220 })

local boxes = {}
local function MakeBox(ci)
    local b = CreateFrame("Frame", nil, holder)
    b:EnableMouse(true)
    local plate = CreateFrame("Frame", nil, b)
    plate:SetPoint("TOPLEFT", -2, 2)
    plate:SetPoint("BOTTOMRIGHT", 2, -2)
    plate:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
    W.Texture(plate, "BACKGROUND", { 0.03, 0.03, 0.03, 0.95 }):SetAllPoints()
    b.edge = W.Border(plate, 1, T.border, "BORDER")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetDrawEdge(false)
    b.cd.noCooldownCount = true   -- keeps cooldown-number addons (OmniCC and the like) from drawing a second counter
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b:GetFrameLevel() + 5)
    b.count = over:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.timer = over:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    b.timer:SetPoint("CENTER", 0, 0)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    b.cat = ci
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self.auraIndex then
            GameTooltip:SetUnitDebuff("target", self.auraIndex)
        else
            local cat = CATEGORIES[self.cat]
            GameTooltip:AddLine(cat.label .. (cat.note and (" (" .. cat.note .. ")") or ""), 1, 1, 1)
            GameTooltip:AddLine("Not on the target", 0.7, 0.7, 0.7)
            for _, sp in ipairs(cat.spells) do
                local who = CLASS_NAMES[sp[3]] or sp[3]
                local have = present[sp[3]]
                GameTooltip:AddLine(sp.name .. " - " .. who, have and 0.4 or 0.5, have and 1 or 0.5, have and 0.4 or 0.5)
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boxes[ci] = b
    return b
end

local function IconFor(cat)
    -- the icon shown while the effect is missing: the first spell somebody in the group can cast
    for _, sp in ipairs(cat.spells) do
        if present[sp[3]] then
            local tex = GetSpellTexture and GetSpellTexture(sp[1])
            if tex then return tex end
        end
    end
    local sp = cat.spells[1]
    return (GetSpellTexture and GetSpellTexture(sp[1])) or (select(3, GetSpellInfo(sp[1]))) or 134400
end

local function Refresh()
    ScanGroup()
    local s = db.iconSize
    local hostile = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    -- what is on the target right now
    local active = {}
    if hostile then
        for i = 1, 40 do
            local name, icon, count, _, duration, expires = UnitDebuff("target", i)
            if not name then break end
            local hit = lookup[name]
            if hit then
                local cur = active[hit.cat]
                if not cur or hit.rank < cur.rank then
                    active[hit.cat] = { rank = hit.rank, icon = icon, count = count, duration = duration,
                                        expires = expires, index = i }
                end
            end
        end
    end
    local show = hostile or not db.onlyHostileTarget
    local n = 0
    for ci, cat in ipairs(CATEGORIES) do
        local b = boxes[ci] or MakeBox(ci)
        if show and (CategoryAvailable(cat) or active[ci]) then
            local col, row = n % db.perRow, math.floor(n / db.perRow)
            n = n + 1
            b:SetSize(s, s)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (s + GAP), -row * (s + LABEL_H + GAP))
            b.label:SetWidth(s + GAP)
            b.label:SetText(db.labels and (cat.short or cat.label) or "")
            local a = active[ci]
            if a then
                b.icon:SetTexture(a.icon)
                b.icon:SetDesaturated(false)
                b.icon:SetVertexColor(1, 1, 1)
                b.count:SetText((a.count or 0) > 1 and a.count or "")
                b.expires = a.expires
                b.auraIndex = a.index
                if a.expires and a.duration and a.duration > 0 then
                    b.cd:SetCooldown(a.expires - a.duration, a.duration)
                else
                    b.cd:Clear()
                end
            else
                b.icon:SetTexture(IconFor(cat))
                b.icon:SetDesaturated(true)
                b.icon:SetVertexColor(0.45, 0.45, 0.45)
                b.count:SetText("")
                b.timer:SetText("")
                b.expires, b.auraIndex = nil, nil
                b.cd:Clear()
            end
            b:Show()
        else
            b:Hide()
            b.auraIndex = nil
        end
    end
end

local tick = 0
holder:SetScript("OnUpdate", function(_, elapsed)
    tick = tick + elapsed
    if tick < 0.2 then return end
    tick = 0
    local now = GetTime()
    for _, b in ipairs(boxes) do
        if b:IsShown() and b.auraIndex then
            local left = b.expires and b.expires > 0 and (b.expires - now)
            if db.timers and left and left > 0 then
                b.timer:SetText(left >= 10 and string.format("%d", left) or string.format("%.1f", left))
                if left < 5 then b.timer:SetTextColor(1, 0.3, 0.25) else b.timer:SetTextColor(1, 1, 1) end
            else
                b.timer:SetText("")
            end
        end
    end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_PET" }) do
    pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "target")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
ev:SetScript("OnEvent", Refresh)
Refresh()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Raid Debuffs", function(page)
    local width = 480
    W.Header(page, "Raid debuffs", width):SetPoint("TOPLEFT", 0, -4)
    W.Checkbox(page, "Only show effects someone in my party or raid can apply", function() return db.onlyGroupClasses end,
        function(on) db.onlyGroupClasses = on; Refresh() end):SetPoint("TOPLEFT", 4, -34)
    W.Checkbox(page, "Only show while I have a living hostile target", function() return db.onlyHostileTarget end,
        function(on) db.onlyHostileTarget = on; Refresh() end):SetPoint("TOPLEFT", 4, -60)
    W.Checkbox(page, "Show the category name under each icon", function() return db.labels end,
        function(on) db.labels = on; Refresh() end):SetPoint("TOPLEFT", 4, -86)
    W.Checkbox(page, "Show countdown numbers on the icons", function() return db.timers end,
        function(on) db.timers = on end):SetPoint("TOPLEFT", 4, -112)

    W.Header(page, "Size", width):SetPoint("TOPLEFT", 0, -154)
    local function Apply()
        SizeHolder(); Refresh()
        if CUI.ApplyLayout then CUI:ApplyLayout("raiddebuffs") end
    end
    W.Stepper(page, "Icon size", function() return db.iconSize end,
        function(v) db.iconSize = v; Apply() end, 22, 56, 2, " px"):SetPoint("TOPLEFT", 4, -184)
    W.Stepper(page, "Icons per row", function() return db.perRow end,
        function(v) db.perRow = v; Apply() end, 3, 10, 1, ""):SetPoint("TOPLEFT", 4, -214)

    local move = W.Button(page, 240, 22, "Move it (layout mode)")
    move:SetPoint("TOPLEFT", 4, -252)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    W.Header(page, "What is tracked", width):SetPoint("TOPLEFT", 0, -296)
    local G, R = "|cFFFFD100", "|r"
    local list = W.Text(page, 11, T.text)
    list:SetPoint("TOPLEFT", 4, -326)
    list:SetWidth(width)
    list:SetJustifyV("TOP")
    list:SetSpacing(4)
    list:SetText(
        "- " .. G .. "Armor" .. R .. " - Sunder Armor, Expose Armor, Faerie Fire, Curse of Recklessness\n"
        .. "- " .. G .. "Fire" .. R .. " - Improved Scorch\n"
        .. "- " .. G .. "Frost" .. R .. " - Winter's Chill\n"
        .. "- " .. G .. "Shadow" .. R .. " - Improved Shadow Bolt\n"
        .. "- " .. G .. "Curses" .. R .. " - Curse of the Elements, Curse of Shadow\n"
        .. "- " .. G .. "Atk Power" .. R .. " (A.P.) - Demoralizing Shout, Demoralizing Roar, Curse of Weakness\n"
        .. "- " .. G .. "Atk Speed" .. R .. " (A.S.) - Thunder Clap\n"
        .. "- " .. G .. "Miss" .. R .. " - Insect Swarm\n"
        .. "- " .. G .. "Hunter" .. R .. " - Hunter's Mark\n"
        .. "- " .. G .. "Judgement" .. R .. " (Judge) - Wisdom, Light, Crusader")

    W.Header(page, "How it works", width):SetPoint("TOPLEFT", 0, -482)
    local note = W.Text(page, 11, T.text)
    note:SetPoint("TOPLEFT", 4, -512)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("- " .. G .. "Which boxes show:" .. R .. " the class of everyone in your party or raid (and you) is checked. A box "
        .. "appears only if one of those classes can apply that effect, so no mage = no Fire or Frost box. Untick the first "
        .. "option to always show every box. It rechecks whenever the group changes.\n"
        .. "- " .. G .. "Grey" .. R .. " = not on the target. " .. G .. "Colored" .. R .. " = it is (any player's debuff counts, not "
        .. "only yours), with stacks and a timer where the game reports one, usually only for your own casts.\n"
        .. "- If several spells fill one box, the strongest is shown. Hover a box for details. Boxes hide on dead targets.")
    page.contentHeight = 700
end)

    end,
})
