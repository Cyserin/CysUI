--------------------------------------------------------------------------------
-- Cys's UI - missing buffs
--
-- Looks at who is in your group and shows the buffs that are missing, only for classes that care:
--   * you can cast the buff: an icon with how many people in the group are missing it (hover for names)
--   * someone else in the group can cast it and you do not have it: an icon with a "!"
-- Only out of combat. Works for any class. Settings: /cui -> Missing Buffs. Move it in layout mode.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local ALL = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local CASTERS = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK" }   -- classes that use mana
local SPIRIT = { "DRUID", "MAGE", "PALADIN", "PRIEST", "SHAMAN", "WARLOCK" }

local function Set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

-- key, label, icon spell id, aura names that count, who can cast it, who needs it
local BUFFS = {
    { key = "fort", label = "Fortitude", icon = 1243,
      auras = { "Power Word: Fortitude", "Prayer of Fortitude" }, casters = Set({ "PRIEST" }), needs = Set(ALL) },
    { key = "motw", label = "Mark of the Wild", icon = 1126,
      auras = { "Mark of the Wild", "Gift of the Wild" }, casters = Set({ "DRUID" }), needs = Set(ALL) },
    { key = "int", label = "Arcane Intellect", icon = 1459,
      auras = { "Arcane Intellect", "Arcane Brilliance" }, casters = Set({ "MAGE" }), needs = Set(CASTERS) },
    { key = "spirit", label = "Divine Spirit", icon = 14752,
      auras = { "Divine Spirit", "Prayer of Spirit" }, casters = Set({ "PRIEST" }), needs = Set(SPIRIT) },
}

local DEFAULTS = { fort = true, motw = true, int = true, spirit = false, size = 32 }
local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.missingBuffs = CysUIDB.missingBuffs or {}
    local db = CysUIDB.missingBuffs
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local frame, icons = nil, {}

local function HasAura(unit, names)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then return false end
        for _, n in ipairs(names) do
            if name == n then return true end
        end
    end
    return false
end

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

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "CysMissingBuffsFrame", UIParent)
    frame:SetSize(160, 40)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()
    CUI:RegisterMovable(frame, "missingbuffs", "Missing Buffs", { point = "CENTER", x = 0, y = 260 })
    for i, b in ipairs(BUFFS) do
        local ic = CreateFrame("Frame", nil, frame)
        ic:EnableMouse(true)
        ic.tex = ic:CreateTexture(nil, "ARTWORK")
        ic.tex:SetAllPoints()
        ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic.tex:SetTexture((GetSpellTexture and GetSpellTexture(b.icon)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        W.Border(ic, 1, T.border, "OVERLAY")
        ic.count = ic:CreateFontString(nil, "OVERLAY")
        ic.count:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        ic.count:SetPoint("CENTER")
        ic.count:SetTextColor(1, 0.3, 0.3)
        ic:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(b.label, 1, 0.82, 0)
            if self.names and #self.names > 0 then
                GameTooltip:AddLine("Missing on: " .. table.concat(self.names, ", "), 1, 1, 1, true)
            else
                GameTooltip:AddLine("You are missing this buff.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ic:Hide()
        icons[i] = ic
    end
end

local function Update()
    Build()
    local db = DB()
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then frame:Hide() return end
    local _, instType = IsInInstance()
    if instType == "pvp" or instType == "arena" then frame:Hide() return end
    local units = GroupUnits()
    local _, myClass = UnitClass("player")
    local size = db.size or 32
    local shown = 0
    for i, b in ipairs(BUFFS) do
        local ic = icons[i]
        ic:Hide()
        if db[b.key] then
            local anyCaster = false
            for _, u in ipairs(units) do
                local _, c = UnitClass(u)
                if c and b.casters[c] and UnitIsConnected(u) then anyCaster = true; break end
            end
            if anyCaster then
                local iCast = b.casters[myClass]
                local names = {}
                if iCast then
                    for _, u in ipairs(units) do
                        local _, c = UnitClass(u)
                        if c and b.needs[c] and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
                            and UnitIsVisible(u) and not HasAura(u, b.auras) then
                            names[#names + 1] = UnitName(u)
                        end
                    end
                    if #names > 0 then ic.names = names; ic.count:SetText(#names) end
                else
                    if b.needs[myClass] and not HasAura("player", b.auras) then
                        ic.names = nil; ic.count:SetText("!")
                        names[1] = "me"
                    end
                end
                if #names > 0 then
                    ic:SetSize(size, size)
                    ic:ClearAllPoints()
                    ic:SetPoint("LEFT", frame, "LEFT", shown * (size + 6), 0)
                    ic:Show()
                    shown = shown + 1
                end
            end
        end
    end
    frame:SetSize(math.max(shown * (size + 6), size), size)
    frame:SetShown(shown > 0)
end

local ev, pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false; Update() end)
end

local function Enable()
    if ev then return end
    Build()
    ev = CreateFrame("Frame")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("UNIT_AURA")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" then
            if unit ~= "player" and not (unit and (unit:find("^party") or unit:find("^raid"))) then return end
        end
        Soon()
    end)
    C_Timer.NewTicker(5, Update)
end

CUI:RegisterModule({
    key = "missingbuffs",
    name = "Missing Buffs",
    addon = "CysUI",
    desc = "Shows the group buffs that are missing (Fortitude, Mark of the Wild, Arcane Intellect, Divine Spirit) for the classes that care. Out of combat only.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Missing Buffs") end,
})

CUI:RegisterPage("Missing Buffs", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Missing buffs", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("Icons for buffs your group is missing, only when the class that needs it is there. If you can cast the buff, the number is how many people lack it (hover for names). If someone else can cast it and you lack it, you see a !. Out of combat only. Move it with /cui layout.")

    local y = -112
    for _, b in ipairs(BUFFS) do
        local c = W.Checkbox(page, b.label, function() return db[b.key] end, function(on) db[b.key] = on end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    W.Notes(page, 4, y - 12, width, "", {
        "Divine Spirit is off by default; turn it on if your group uses it.",
        "It only checks people who are in range, alive and online.",
    })
end)
