CysUI:RegisterModule({
    key = "skills", name = "Cys's Skills",
    desc = "Weapon skill and profession tracker for the gear you have equipped. Move it in layout mode.",
    open = function() CysUI:OpenConfig("Skill Tracker") end,
    body = function(...)
local addonName, ns = ...
local frame = CreateFrame("Frame", "CysSkillsFrame", UIParent, "BackdropTemplate")

-- Default Position & Saved Variables Initialization
frame:SetSize(240, 100)
frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
CysSkillsDB = CysSkillsDB or {}

-- When the tracker is visible: with the Character window (default), always, or only when you type /cysws
local function DB()
    if not CysUIDB then CysUIDB = {} end
    CysUIDB.skillTracker = CysUIDB.skillTracker or {}
    if not CysUIDB.skillTracker.mode then CysUIDB.skillTracker.mode = "attached" end
    return CysUIDB.skillTracker
end
local PlaceAttached
local floor = math.floor
local forced -- /cysws overrides the setting until you change the setting or reload
local function UpdateVisibility()
    local show
    if forced ~= nil then show = forced
    else
        local mode = DB().mode
        if mode == "always" then show = true
        elseif mode == "attached" or mode == "character" then show = CharacterFrame and CharacterFrame:IsShown() or false
        else show = false end
    end
    if show then
        if not frame:IsShown() then frame:Show() end
        PlaceAttached()
    elseif frame:IsShown() then frame:Hide() end
end
-- position comes from layout mode (/cui layout)
CysUI:RegisterMovable(frame, "skills", "Skill Tracker", { point = "CENTER", x = 300, y = 0 })

-- Styling (Minimalist Flat Theme)
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
local function EdgeColor() local b = CysUI.W.T.border; frame:SetBackdropBorderColor(b[1], b[2], b[3], 1) end
EdgeColor()
CysUI.W.OnBorderStyle(EdgeColor)

-- "Attached": under Cys's Armory when it is open, otherwise right beside the Character window
local function Attached()
    return DB().mode == "attached" and forced == nil and CharacterFrame and CharacterFrame:IsShown()
end
local armoryHooked
function PlaceAttached()
    if not Attached() then return end
    local armory = _G.CysArmoryFrame
    if armory and not armoryHooked then
        armoryHooked = true
        armory:HookScript("OnShow", function() frame:RefreshSkills() end)
        armory:HookScript("OnHide", function() frame:RefreshSkills() end)
    end
    frame:ClearAllPoints()
    if armory and armory:IsShown() then
        frame:SetPoint("TOPLEFT", armory, "BOTTOMLEFT", 0, -4)
    else
        frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -32, -12)
    end
end
frame:SetFrameStrata("HIGH")

-- Header Title
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
title:SetText("Cys's Skill Tracker")
title:SetTextColor(1, 0.82, 0)

-- Text Container
local contentText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
contentText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
contentText:SetJustifyH("LEFT")
contentText:SetSpacing(1)

-- Master Set of All Known Weapon / Combat Skill Line Names
local WEAPON_SKILL_NAMES = {
    ["Axes"]             = true,
    ["Two-Handed Axes"]  = true,
    ["Swords"]           = true,
    ["Two-Handed Swords"]= true,
    ["Maces"]            = true,
    ["Two-Handed Maces"] = true,
    ["Daggers"]          = true,
    ["Polearms"]         = true,
    ["Staves"]           = true,
    ["Fist Weapons"]     = true,
    ["Bows"]             = true,
    ["Guns"]             = true,
    ["Crossbows"]        = true,
    ["Wands"]            = true,
    ["Thrown"]           = true,
    ["Unarmed"]          = true,
    ["Defense"]          = true,
}

-- Map Item SubType string returned by GetItemInfo -> Skill Line Name in Skills Tab
local ITEM_SUBTYPE_TO_SKILL = {
    ["One-Handed Axes"]    = "Axes",
    ["Two-Handed Axes"]    = "Two-Handed Axes",
    ["Axes"]               = "Axes",
    ["One-Handed Swords"]  = "Swords",
    ["Two-Handed Swords"]  = "Two-Handed Swords",
    ["Swords"]             = "Swords",
    ["One-Handed Maces"]   = "Maces",
    ["Two-Handed Maces"]   = "Two-Handed Maces",
    ["Maces"]              = "Maces",
    ["Daggers"]            = "Daggers",
    ["Polearms"]           = "Polearms",
    ["Staves"]             = "Staves",
    ["Fist Weapons"]       = "Fist Weapons",
    ["Bows"]               = "Bows",
    ["Guns"]               = "Guns",
    ["Crossbows"]          = "Crossbows",
    ["Wands"]              = "Wands",
    ["Thrown"]             = "Thrown",
    ["Shields"]            = "Defense",
}

-- List of class specs / non-professions to exclude
local IGNORED_SKILLS = {
    ["Arms"] = true, ["Fury"] = true, ["Protection"] = true,
    ["Holy"] = true, ["Retribution"] = true, ["Discipline"] = true,
    ["Shadow"] = true, ["Assassination"] = true, ["Combat"] = true,
    ["Subtlety"] = true, ["Elemental Combat"] = true, ["Enhancement"] = true,
    ["Restoration"] = true, ["Affliction"] = true, ["Demonology"] = true,
    ["Destruction"] = true, ["Arcane"] = true, ["Fire"] = true,
    ["Frost"] = true, ["Beast Mastery"] = true, ["Marksmanship"] = true,
}

-- Helper: Returns an RGB hex color code (|cFF...|r) based on rank vs maxCap
local function GetSkillColorCode(rank, maxCap)
    if rank >= maxCap then
        return "|cFF55FF55" -- Green (Capped)
    end
    
    local ratio = maxCap > 0 and (rank / maxCap) or 0
    if ratio < 0.75 then
        return "|cFFFF5555" -- Red (Under-leveled / Low)
    else
        return "|cFFFFCC00" -- Yellow (Middle range / Getting close)
    end
end

-- Resolve itemLink / itemID directly to Skill Line Name
local function GetWeaponSkillFromItem(item)
    if not item then return nil end
    local subType
    pcall(function()
        local _, _, _, _, _, _, sType = GetItemInfo(item)
        subType = sType
    end)
    if subType then
        return ITEM_SUBTYPE_TO_SKILL[subType] or subType
    end
    return nil
end

-- Core Scanner & UI Refresh Function
function frame:RefreshSkills()
    local playerLevel = UnitLevel("player")
    local maxCap = playerLevel * 5
    local allSkills = {}
    
    -- 1. Scan Character Skill Tab
    if not (GetNumSkillLines and GetSkillLineInfo) then return end
    local numSkills = GetNumSkillLines()
    for i = 1, numSkills do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and name then
            allSkills[name] = { rank = rank, maxRank = maxRank }
        end
    end

    -- 2. Identify Targeted Weapons
    local trackedWeapons = {}
    
    -- Always include Defense
    if allSkills["Defense"] then
        trackedWeapons["Defense"] = true
    end

    -- A. Scan Equipped Weapons (MainHand 16, OffHand 17, Ranged 18)
    for _, slotID in ipairs({16, 17, 18}) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local skillName = GetWeaponSkillFromItem(link)
            if skillName and allSkills[skillName] then
                trackedWeapons[skillName] = true
            end
        end
    end

    -- B. Scan Armory / Saved Equipment Set Weapons
    local setItemLinks = {}
    if CysUI and CysUI.GetArmorySetItems then
        setItemLinks = CysUI:GetArmorySetItems() or {}
    elseif C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
            local locations = C_EquipmentSet.GetItemLocations(setID)
            if locations then
                for _, loc in pairs(locations) do
                    local player, bank, bags, void, slot, bag = EquipmentManager_UnpackLocation(loc)
                    if bag and slot then
                        local link = C_Container and C_Container.GetContainerItemLink(bag, slot) or GetContainerItemLink(bag, slot)
                        if link then table.insert(setItemLinks, link) end
                    elseif slot then
                        local link = GetInventoryItemLink("player", slot)
                        if link then table.insert(setItemLinks, link) end
                    end
                end
            end
        end
    end

    for _, item in ipairs(setItemLinks) do
        local skillName = GetWeaponSkillFromItem(item)
        if skillName and allSkills[skillName] then
            trackedWeapons[skillName] = true
        end
    end

    -- 3. Build Display Sections
    local lines = {}
    
    -- Section A: Weapon Skills & Defense
    local weaponLines = {}
    for weaponName in pairs(trackedWeapons) do
        local data = allSkills[weaponName]
        if data then
            local color = GetSkillColorCode(data.rank, maxCap)
            table.insert(weaponLines, string.format("  %s: %s%d / %d|r", weaponName, color, data.rank, maxCap))
        end
    end

    if #weaponLines > 0 then
        table.insert(lines, "|cFFFFD100Weapons & Defense|r")
        for _, line in ipairs(weaponLines) do table.insert(lines, line) end
    end

    -- Section B: Current Professions
    local profLines = {}
    for skillName, data in pairs(allSkills) do
        -- Filter out ignored class specs, ALL weapon skills, defense, and languages
        if not IGNORED_SKILLS[skillName] and not WEAPON_SKILL_NAMES[skillName] and not skillName:find("Language") then
            if data.maxRank and data.maxRank > 1 then
                local isProfCapped = (data.rank >= data.maxRank)
                local profColor = isProfCapped and "|cFF55FF55" or "|cFFFFCC00"
                table.insert(profLines, string.format("  %s: %s%d / %d|r", skillName, profColor, data.rank, data.maxRank))
            end
        end
    end

    if #profLines > 0 then
        if #weaponLines > 0 then table.insert(lines, "") end -- Spacer line
        table.insert(lines, "|cFFFFD100Professions|r")
        for _, line in ipairs(profLines) do table.insert(lines, line) end
    end

    -- Render Output
    if #lines == 0 then
        contentText:SetText("|cFF888888No active skills tracked|r")
        frame:SetHeight(45)
    else
        contentText:SetText(table.concat(lines, "\n"))
        frame:SetHeight(28 + (#lines * 12))
    end
    -- the box is only as wide as its text
    local w = math.max(title:GetStringWidth(), contentText:GetStringWidth()) + 22
    if Attached() and _G.CysArmoryFrame and _G.CysArmoryFrame:IsShown() then w = _G.CysArmoryFrame:GetWidth() end -- same width as the Armory above it
    frame:SetWidth(math.max(math.floor(w + 0.5), 110))
    PlaceAttached()
    if not Attached() and CysUI and CysUI.ApplyLayout then CysUI:ApplyLayout("skills") end -- keep the layout box the same size
end

-- Event Handling
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_SKILL")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")

frame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        self:RefreshSkills()
    elseif event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
        self:RefreshSkills()
    elseif event == "CHAT_MSG_SKILL" or event == "SKILL_LINES_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" or event == "EQUIPMENT_SETS_CHANGED" then
        self:RefreshSkills()
    end
end)

-- Slash Command (/cysskills or /cysws)
SLASH_CYSSKILLS1 = "/cysskills"
SLASH_CYSSKILLS2 = "/cysws"
SlashCmdList["CYSSKILLS"] = function()
    forced = not frame:IsShown()
    UpdateVisibility()
    if forced then frame:RefreshSkills() end
end

if CharacterFrame then
    CharacterFrame:HookScript("OnShow", function() UpdateVisibility(); frame:RefreshSkills() end)
    CharacterFrame:HookScript("OnHide", UpdateVisibility)
end
frame:SetScript("OnShow", function(self) self:RefreshSkills() end)
UpdateVisibility()

CysUI:RegisterPage("Skill Tracker", function(page)
    local W = CysUI.W
    local T = W.T
    local db = DB()
    W.Header(page, "Skill Tracker", 480):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 11, T.desc)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(470)
    intro:SetJustifyH("LEFT")
    intro:SetText("Weapon skills for the weapons you carry, plus your professions. Type /cysws to show or hide it by hand.")
    local buttons = {}
    local function Paint() for key, b in pairs(buttons) do b:SetPrimary(db.mode == key) end end
    for n, def in ipairs({ { "attached", "Beside Character window" }, { "character", "Character window (my spot)" }, { "always", "Always" }, { "off", "Hidden" } }) do
        local b = W.Button(page, 190, 24, def[2])
        b:SetPoint("TOPLEFT", 4 + ((n - 1) % 2) * 198, -76 - floor((n - 1) / 2) * 30)
        b:SetScript("OnClick", function()
            db.mode = def[1]; forced = nil; Paint(); UpdateVisibility(); frame:RefreshSkills()
        end)
        buttons[def[1]] = b
    end
    Paint()
    local move = W.Button(page, 240, 22, "Move the tracker (layout mode)")
    move:SetPoint("TOPLEFT", 4, -146)
    move:SetScript("OnClick", function() CysUI:ToggleLayout() end)
end)
end,
})
