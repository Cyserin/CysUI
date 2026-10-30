--------------------------------------------------------------------------------
-- Cys's Totems - Standalone Shaman Tracker with Combat-Log Range Detection
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "totems", name = "Cys's Totems", class = "SHAMAN",
    desc = "Shaman only: a totem bar. Left-click drops the totem you picked, right-click a slot to pick another (and keep an action-bar macro in step). Timers, Drop All, loadouts, expiry alerts and a weapon-imbue button. Move it in layout mode.",
    body = function(...)
local ADDON_NAME = ...
CysTotemsDB = CysTotemsDB or {}
CysTotemsDB.selectedImbue = CysTotemsDB.selectedImbue or "Rockbiter Weapon"
CysTotemsDB.choice = CysTotemsDB.choice or {}      -- [element key] = totem spell name
CysTotemsDB.dropAll = CysTotemsDB.dropAll or {}    -- [element key] = false when left out of Drop All
CysTotemsDB.loadouts = CysTotemsDB.loadouts or {}  -- [name] = { earth=..., fire=..., water=..., air=... }
if CysTotemsDB.macros == nil then CysTotemsDB.macros = false end
if CysTotemsDB.alertExpiring == nil then CysTotemsDB.alertExpiring = true end
if CysTotemsDB.alertGone == nil then CysTotemsDB.alertGone = true end
local db = CysTotemsDB

local f = CreateFrame("Frame", "CysTotemsFrame", UIParent)
f:SetSize(264, 42)
f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
-- position comes from layout mode (/cui layout)
CysUI:RegisterMovable(f, "totems", "Totem Tracker", { point = "CENTER", x = 0, y = -180 })

-- Theme plate: black backing and the UI's border sit around each box, behind the colored status ring
local W = CysUI.W
local function AddPlate(box)
    local plate = CreateFrame("Frame", nil, box)
    plate:SetPoint("TOPLEFT", -4, 4)
    plate:SetPoint("BOTTOMRIGHT", 4, -4)
    plate:SetFrameLevel(max(box:GetFrameLevel() - 1, 0))
    local bg = plate:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.95)
    W.Border(plate, 1, W.T.border, "BORDER")
    box.plate = plate
end

-- Styling Helper: Create a crisp square icon box with border.
-- `secure` boxes are buttons that can cast a spell (left-click) and open a menu (right-click).
local function CreateIconBox(parent, size, labelText, secure, name)
    local box
    if secure then
        box = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
        box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        box = CreateFrame("Frame", nil, parent)
    end
    box:SetSize(size, size)

    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 1)
    AddPlate(box)

    local border = box:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.2, 0.2, 0.2, 1)
    box.border = border

    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetPoint("TOPLEFT", 2, -2)
    box.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon:SetDesaturated(true)
    box.icon:SetVertexColor(0.4, 0.4, 0.4)

    box.cd = CreateFrame("Cooldown", nil, box, "CooldownFrameTemplate")
    box.cd:SetAllPoints(box.icon)
    box.cd:SetDrawEdge(false)

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("TOP", box, "BOTTOM", 0, -7)
    box.label:SetText(labelText or "")
    box.label:SetTextColor(0.7, 0.7, 0.7)

    -- time left, drawn over the icon
    local top = CreateFrame("Frame", nil, box)
    top:SetAllPoints()
    top:SetFrameLevel(box:GetFrameLevel() + 3)
    box.timer = top:CreateFontString(nil, "OVERLAY")
    box.timer:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    box.timer:SetPoint("CENTER", 0, 0)
    box.timer:SetTextColor(1, 1, 1)
    return box
end

-- Ordered strictly by unlock level: Earth (4), Fire (10), Water (20), Air (30)
-- Classic Era API element indices: 2=Earth, 1=Fire, 3=Water, 4=Air
local slots = {}
local elementData = {
    { key = "earth", name = "Earth", elementID = 2, levelReq = 4,  defaultIcon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem", color = { 0.2, 0.8, 0.2 },
      isBuff = true, buffNames = { "Stoneskin", "Strength of Earth", "Stoneclaw" },
      totems = { "Stoneclaw Totem", "Stoneskin Totem", "Earthbind Totem", "Strength of Earth Totem", "Tremor Totem" },
      prefer = { "Strength of Earth Totem", "Stoneskin Totem", "Stoneclaw Totem", "Earthbind Totem" } },
    { key = "fire",  name = "Fire",  elementID = 1, levelReq = 10, defaultIcon = "Interface\\Icons\\Spell_Fire_SearingTotem",     color = { 1.0, 0.3, 0.2 },
      isCombatTracked = true,
      totems = { "Searing Totem", "Fire Nova Totem", "Magma Totem", "Flametongue Totem", "Frost Resistance Totem" },
      prefer = { "Searing Totem", "Flametongue Totem", "Magma Totem", "Fire Nova Totem" } },
    { key = "water", name = "Water", elementID = 3, levelReq = 20, defaultIcon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",  color = { 0.2, 0.6, 1.0 },
      isBuff = true, buffNames = { "Healing Stream", "Mana Spring", "Fire Resistance" },
      totems = { "Healing Stream Totem", "Mana Spring Totem", "Poison Cleansing Totem", "Disease Cleansing Totem", "Fire Resistance Totem", "Mana Tide Totem" },
      prefer = { "Mana Spring Totem", "Healing Stream Totem", "Poison Cleansing Totem", "Disease Cleansing Totem" } },
    { key = "air",   name = "Air",   elementID = 4, levelReq = 30, defaultIcon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem", color = { 0.8, 0.8, 1.0 },
      isBuff = true, buffNames = { "Grace of Air", "Nature Resistance", "Tranq Air" },
      totems = { "Grounding Totem", "Nature Resistance Totem", "Sentry Totem", "Windfury Totem", "Grace of Air Totem", "Tranquil Air Totem", "Windwall Totem" },
      prefer = { "Windfury Totem", "Grace of Air Totem", "Nature Resistance Totem", "Tranquil Air Totem" } },
}

local function IsKnown(spell) return spell and GetSpellInfo(spell) ~= nil end

-- the totem this slot drops: your pick if you still know it, otherwise the first good one you know
local function ResolveChoice(data)
    local pick = db.choice[data.key]
    if IsKnown(pick) then return pick end
    for _, name in ipairs(data.prefer) do
        if IsKnown(name) then return name end
    end
end

for i = 1, 4 do
    local data = elementData[i]
    local iconBox = CreateIconBox(f, 34, data.name, true, "CysTotems" .. data.name .. "Button")
    iconBox.elementID = data.elementID
    iconBox.levelReq = data.levelReq
    iconBox.data = data
    slots[i] = iconBox
end

-- Tracking state for Searing Totem last action timestamp
local lastFireTime = nil

-- Create Secure Clickable Weapon Imbue Slot with full textures and backgrounds restored
local imbueBox = CreateFrame("Button", "CysTotemsImbueButton", f, "SecureActionButtonTemplate")
imbueBox:SetSize(34, 34)
imbueBox:RegisterForClicks("AnyUp")

imbueBox.bg = imbueBox:CreateTexture(nil, "BACKGROUND")
imbueBox.bg:SetAllPoints()
imbueBox.bg:SetColorTexture(0, 0, 0, 1)
AddPlate(imbueBox)

imbueBox.border = imbueBox:CreateTexture(nil, "BORDER")
imbueBox.border:SetPoint("TOPLEFT", -1, 1)
imbueBox.border:SetPoint("BOTTOMRIGHT", 1, -1)
imbueBox.border:SetColorTexture(0.2, 0.2, 0.2, 1)

imbueBox.icon = imbueBox:CreateTexture(nil, "ARTWORK")
imbueBox.icon:SetPoint("TOPLEFT", 2, -2)
imbueBox.icon:SetPoint("BOTTOMRIGHT", -2, 2)
imbueBox.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

imbueBox.cd = CreateFrame("Cooldown", nil, imbueBox, "CooldownFrameTemplate")
imbueBox.cd:SetAllPoints(imbueBox.icon)
imbueBox.cd:SetDrawEdge(false)

imbueBox.label = imbueBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
imbueBox.label:SetPoint("TOP", imbueBox, "BOTTOM", 0, -7)
imbueBox.label:SetText("Weapon")
imbueBox.label:SetTextColor(0.7, 0.7, 0.7)

--------------------------------------------------------------------------------
-- Secure Weapon Imbue Configuration
--------------------------------------------------------------------------------
-- Register both UP and DOWN states so the secure templates can validate the click action
imbueBox:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")

local function UpdateImbueMacro()
    if InCombatLockdown() then return end
    
    -- Wipe potential conflicts completely
    imbueBox:SetAttribute("type", nil)
    imbueBox:SetAttribute("macrotext", nil)
    imbueBox:SetAttribute("type1", nil)
    imbueBox:SetAttribute("macrotext1", nil)

    local spellName = CysTotemsDB.selectedImbue or "Rockbiter Weapon"
    
    -- Classic Era native assignment pattern
    imbueBox:SetAttribute("type", "macro")
    imbueBox:SetAttribute("macrotext", string.format("/cast %s\n/use 16", spellName))
end
UpdateImbueMacro()



-- Right-Click Menu to select known weapon imbues
local dropdownFrame = CreateFrame("Frame", "CysTotemsImbueDropdown", f, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(dropdownFrame, function(self, level)
    local imbues = { "Rockbiter Weapon", "Frostbrand Weapon", "Flametongue Weapon", "Windfury Weapon" }
    for _, spellName in ipairs(imbues) do
        if GetSpellInfo(spellName) then
            local info = UIDropDownMenu_CreateInfo()
            info.text = spellName
            info.checked = (CysTotemsDB.selectedImbue == spellName)
            info.func = function()
                CysTotemsDB.selectedImbue = spellName
                UpdateImbueMacro()
                if _G.CysTotemsUpdateImbueVisual then _G.CysTotemsUpdateImbueVisual() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end, "MENU")

imbueBox:SetScript("PreClick", function(self, button)
    if button == "RightButton" then
        ToggleDropDownMenu(1, nil, dropdownFrame, self, 0, 0)
    end
end)

imbueBox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(string.format("Left-Click: Cast %s\nRight-Click: Change Imbue", CysTotemsDB.selectedImbue or "Rockbiter Weapon"))
    GameTooltip:Show()
end)
imbueBox:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

--------------------------------------------------------------------------------
-- The totem bar: what each slot drops, Drop All, action-bar macros, loadouts
--------------------------------------------------------------------------------
local TAG = "|cFFFFD100[Totems]|r "
local function Say(msg) print(TAG .. msg) end

-- Drop All: one button that drops the picked totems one after another, a press at a time
local dropAll = CreateIconBox(f, 34, "Drop all", true, "CysTotemsDropAllButton")
dropAll.icon:SetTexture(nil)
dropAll.border:SetColorTexture(0.9, 0.75, 0.1, 1)
-- four little icons, one per element, showing the totems that Drop all will use
dropAll.quad = {}
for i = 1, 4 do
    local t = dropAll:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    t:SetPoint("TOPLEFT", dropAll, "TOPLEFT", 3 + col * 15, -3 - row * 15)
    dropAll.quad[i] = t
end

local pendingApply = false
local MACRO_NAMES = { earth = "CT_Earth", fire = "CT_Fire", water = "CT_Water", air = "CT_Air" }
local MACRO_DROPALL = "CT_DropAll"

local function DropAllText()
    local list = {}
    local level = UnitLevel("player") or 1
    for _, data in ipairs(elementData) do
        if level >= data.levelReq and db.dropAll[data.key] ~= false then
            local name = ResolveChoice(data)
            if name then list[#list + 1] = name end
        end
    end
    if #list == 0 then return nil end
    if #list == 1 then return "/cast " .. list[1] end
    return "/castsequence reset=6 " .. table.concat(list, ", ")
end

local function MacroBody(text)
    return "#showtooltip\n" .. text
end

-- The icon stays the plain "?" so #showtooltip can show the spell. (Editing a macro with the icon the
-- bar is currently showing would freeze that icon in place, which is what the first version did.)
local BLANK_ICON = "INV_Misc_QuestionMark"
local function SetMacro(name, body, create)
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        local okInfo, mName, mIcon, mBody = pcall(GetMacroInfo, idx)
        if okInfo and mBody == body and db.macroIconFix then return true end
        local ok = pcall(EditMacro, idx, mName or name, BLANK_ICON, body)
        return ok
    elseif create then
        local ok = pcall(CreateMacro, name, BLANK_ICON, body, true)
        return ok
    end
    return true
end

-- keeps the macros in step with your picks (created the first time you switch the option on)
local function SyncMacros(create)
    if not db.macros or InCombatLockdown() then return end
    local level = UnitLevel("player") or 1
    local failed = false
    for _, data in ipairs(elementData) do
        local name = ResolveChoice(data)
        if level >= data.levelReq and name then
            if not SetMacro(MACRO_NAMES[data.key], MacroBody("/cast " .. name), create) then failed = true end
        end
    end
    local text = DropAllText()
    if text and not SetMacro(MACRO_DROPALL, MacroBody(text), create) then failed = true end
    if not failed then db.macroIconFix = true end
    if failed and create then
        Say("|cFFFF4040Couldn't make every macro (you may be out of character macro slots).|r")
    end
end

local function UpdateDropAllIcon()
    local level = UnitLevel("player") or 1
    for i, data in ipairs(elementData) do
        local t = dropAll.quad[i]
        local name = ResolveChoice(data)
        local _, _, icon = name and GetSpellInfo(name)
        t:SetTexture(icon or data.defaultIcon)
        local used = level >= data.levelReq and name and db.dropAll[data.key] ~= false
        t:SetDesaturated(not used)
        t:SetAlpha(used and 1 or 0.35)
    end
end

-- point every button at the right spell; the game only lets us do this out of combat
local function ApplyChoices()
    if InCombatLockdown() then pendingApply = true; return end
    pendingApply = false
    for _, box in ipairs(slots) do
        local name = ResolveChoice(box.data)
        if name then
            box:SetAttribute("type1", "spell")
            box:SetAttribute("spell1", name)
        else
            box:SetAttribute("type1", nil)
            box:SetAttribute("spell1", nil)
        end
        box.chosen = name
    end
    local text = DropAllText()
    if text then
        dropAll:SetAttribute("type1", "macro")
        dropAll:SetAttribute("macrotext1", text)
    else
        dropAll:SetAttribute("type1", nil)
        dropAll:SetAttribute("macrotext1", nil)
    end
    SyncMacros(false)
    UpdateDropAllIcon()
end

local function SetChoice(data, name)
    db.choice[data.key] = name
    UpdateDropAllIcon()
    if InCombatLockdown() then
        pendingApply = true
        Say(data.name .. ": " .. name .. " will be ready as soon as combat ends.")
    else
        ApplyChoices()
    end
end

local function CurrentLoadout()
    local t = {}
    for _, data in ipairs(elementData) do t[data.key] = ResolveChoice(data) end
    return t
end

local function LoadLoadout(name)
    local lo = db.loadouts[name]
    if not lo then Say("|cFFFF4040No loadout called " .. tostring(name) .. ".|r"); return end
    for _, data in ipairs(elementData) do db.choice[data.key] = lo[data.key] end
    if InCombatLockdown() then
        pendingApply = true
        Say("Loadout |cFFFFD100" .. name .. "|r will be ready as soon as combat ends.")
    else
        ApplyChoices()
        Say("Loadout |cFFFFD100" .. name .. "|r loaded.")
    end
end

local function SaveLoadout(name)
    name = strtrim(name or "")
    if name == "" then return end
    db.loadouts[name] = CurrentLoadout()
    Say("Saved loadout |cFFFFD100" .. name .. "|r.")
end

StaticPopupDialogs["CYSTOTEMS_SAVE_LOADOUT"] = {
    text = "Name this totem loadout:",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, maxLetters = 24,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        if eb then SaveLoadout(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        SaveLoadout(self:GetText())
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- the right-click menu (one dropdown, filled in for whichever button was clicked)
local menuFrame = CreateFrame("Frame", "CysTotemsMenu", UIParent, "UIDropDownMenuTemplate")
local menuFor

local function SortedLoadouts()
    local names = {}
    for n in pairs(db.loadouts) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function AddTitle(text, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text; info.isTitle = true; info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
end

local function AddToggle(text, get, set, level, tip)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.isNotRadio = true
    info.checked = get()
    info.func = function() set(not get()) end
    if tip then info.tooltipTitle = text; info.tooltipText = tip; info.tooltipOnButton = true end
    UIDropDownMenu_AddButton(info, level)
end

local function InitMenu(self, level)
    level = level or 1
    if menuFor == dropAll then
        if level == 1 then
            AddTitle("Totem loadouts", 1)
            local names = SortedLoadouts()
            if #names == 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "(none saved yet)"; info.notCheckable = true; info.disabled = true
                UIDropDownMenu_AddButton(info, 1)
            end
            for _, n in ipairs(names) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = n; info.notCheckable = true
                info.func = function() LoadLoadout(n) end
                UIDropDownMenu_AddButton(info, 1)
            end
            local save = UIDropDownMenu_CreateInfo()
            save.text = "Save current picks as..."; save.notCheckable = true
            save.func = function() StaticPopup_Show("CYSTOTEMS_SAVE_LOADOUT") end
            UIDropDownMenu_AddButton(save, 1)
            if #names > 0 then
                local del = UIDropDownMenu_CreateInfo()
                del.text = "Delete a loadout"; del.notCheckable = true
                del.hasArrow = true; del.value = "DELETE"
                UIDropDownMenu_AddButton(del, 1)
            end
            AddTitle("Options", 1)
            AddToggle("Keep action-bar macros in step", function() return db.macros end, function(v)
                db.macros = v and true or false
                if v then
                    SyncMacros(true)
                    Say("Macros |cFFFFD100CT_Earth, CT_Fire, CT_Water, CT_Air|r and |cFFFFD100CT_DropAll|r are ready. Drag them from /macro onto your bars; they change when you pick a new totem.")
                end
            end, 1, "Makes five character macros and keeps them updated when you pick a different totem. Drag them onto your action bars from the /macro window.")
            AddToggle("Warn before a totem runs out", function() return db.alertExpiring end, function(v) db.alertExpiring = v and true or false end, 1)
            AddToggle("Tell me when a totem is gone", function() return db.alertGone end, function(v) db.alertGone = v and true or false end, 1)
        elseif UIDROPDOWNMENU_MENU_VALUE == "DELETE" then
            for _, n in ipairs(SortedLoadouts()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = n; info.notCheckable = true
                info.func = function()
                    db.loadouts[n] = nil
                    Say("Deleted loadout |cFFFFD100" .. n .. "|r.")
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, 2)
            end
        end
    elseif menuFor and menuFor.data then
        local data = menuFor.data
        AddTitle(data.name .. " totem", 1)
        local picked = ResolveChoice(data)
        local any = false
        for _, name in ipairs(data.totems) do
            local _, _, icon = GetSpellInfo(name)
            if icon then
                any = true
                local info = UIDropDownMenu_CreateInfo()
                info.text = name; info.icon = icon
                info.checked = (picked == name)
                info.func = function() SetChoice(data, name) end
                UIDropDownMenu_AddButton(info, 1)
            end
        end
        if not any then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "You don't know any yet"; info.notCheckable = true; info.disabled = true
            UIDropDownMenu_AddButton(info, 1)
        end
        AddToggle("Include in Drop All", function() return db.dropAll[data.key] ~= false end, function(v)
            db.dropAll[data.key] = v and true or false
            if InCombatLockdown() then pendingApply = true else ApplyChoices() end
        end, 1)
    end
end

local function OpenMenu(box)
    menuFor = box
    UIDropDownMenu_Initialize(menuFrame, InitMenu, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, box, 0, 0)
end

for _, box in ipairs(slots) do
    box:SetScript("PostClick", function(self, button)
        if button == "RightButton" then OpenMenu(self) end
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local data = self.data
        GameTooltip:AddLine(data.name .. " totem", 1, 0.82, 0)
        local name = self.chosen or ResolveChoice(data)
        if name then
            GameTooltip:AddLine("Left-click: drop " .. name, 1, 1, 1)
        else
            GameTooltip:AddLine("You don't know a " .. data.name:lower() .. " totem yet", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Right-click: choose a different totem", 0.7, 0.7, 0.7)
        local have, tName, start, dur = GetTotemInfo(data.elementID)
        if have and tName and tName ~= "" and dur and dur > 0 then
            local rem = start + dur - GetTime()
            if rem > 0 then GameTooltip:AddLine(format("Down now: %s (%d sec left)", tName, rem), 0.4, 1, 0.4) end
        end
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
dropAll:SetScript("PostClick", function(self, button)
    if button == "RightButton" then OpenMenu(self) end
end)
dropAll:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Drop all", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: drop your totems, one per press", 1, 1, 1)
    GameTooltip:AddLine("Right-click: loadouts and options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
dropAll:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------------------
-- Timers and alerts
--------------------------------------------------------------------------------
local EXPIRY_WARN = 10 -- seconds left when the slot starts flashing
local alertState = {}  -- per element: last totem name, end time, warned, flash end

local function FormatTime(sec)
    if sec >= 60 then return format("%d:%02d", floor(sec / 60), floor(sec % 60)) end
    return format("%d", ceil(sec))
end

local function Flash(box, r, g, b)
    box.flashColor = { r, g, b }
    box.flashUntil = GetTime() + 1.6
end

local function UpdateTimersAndAlerts()
    local now = GetTime()
    for _, box in ipairs(slots) do
        local data = box.data
        local st = alertState[data.key]
        if not st then st = {}; alertState[data.key] = st end
        local have, name, start, dur, icon = GetTotemInfo(data.elementID)
        local active = have and name and name ~= "" and dur and dur > 0
        if active then
            local endTime = start + dur
            local rem = endTime - now
            if rem < 0 then rem = 0 end
            box.timer:SetText(FormatTime(rem))
            if rem <= EXPIRY_WARN then box.timer:SetTextColor(1, 0.3, 0.2) else box.timer:SetTextColor(1, 1, 1) end
            box.cd:SetCooldown(start, dur)
            if st.name ~= name or st.endTime ~= endTime then
                st.name, st.endTime, st.warned = name, endTime, false -- a new totem went down
            end
            st.lastRem = rem
            if db.alertExpiring and not st.warned and rem <= EXPIRY_WARN and rem > 0 and dur > EXPIRY_WARN then
                st.warned = true
                Say(format("%s is about to run out (%d sec).", name, ceil(rem)))
                Flash(box, 1, 0.6, 0.1)
                pcall(PlaySound, 8959)
            end
        else
            box.timer:SetText("")
            box.cd:Clear()
            if st.name then
                if db.alertGone then
                    if (st.lastRem or 0) > 2.5 then
                        Say(format("|cFFFF4040%s is gone|r (destroyed or you moved away).", st.name))
                        Flash(box, 1, 0.1, 0.1)
                    end
                end
                st.name, st.endTime, st.warned = nil, nil, false
            end
        end
        -- flash the frame for a moment
        if box.flashUntil and box.flashUntil > now then
            local a = 0.4 + 0.6 * math.abs(math.sin(now * 8))
            local c = box.flashColor
            box.border:SetColorTexture(c[1], c[2], c[3], a)
            box.flashing = true
        elseif box.flashing then
            box.flashing = false
        end
    end
end
f:SetScript("OnUpdate", function(self, elapsed)
    self.tick = (self.tick or 0) + elapsed
    if self.tick < 0.1 then return end
    self.tick = 0
    UpdateTimersAndAlerts()
end)

-- /cystotems for macros and quick use
SLASH_CYSTOTEMS1 = "/cystotems"
SlashCmdList["CYSTOTEMS"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "load" and arg ~= "" then
        LoadLoadout(arg)
    elseif cmd == "save" and arg ~= "" then
        SaveLoadout(arg)
    elseif cmd == "list" then
        local names = SortedLoadouts()
        Say(#names > 0 and ("Loadouts: " .. table.concat(names, ", ")) or "No loadouts saved yet. Right-click the Drop all button.")
    else
        Say("/cystotems load <name>  |  save <name>  |  list.  Right-click the totem slots and the Drop all button for the rest.")
    end
end

--------------------------------------------------------------------------------
-- Range Evaluation Logic (Buff Scan vs Combat Log Activity)
--------------------------------------------------------------------------------
local function EvaluateTotemRange(box, haveTotem)
    local data = box.data
    if not haveTotem then
        if data.isCombatTracked then
            lastFireTime = nil
        end
        return false
    end

    if data.isBuff then
        local hasBuff = false
        if data.buffNames then
            for i = 1, 40 do
                local name = UnitBuff("player", i)
                if not name then break end
                for _, bName in ipairs(data.buffNames) do
                    if string.find(name, bName) then
                        hasBuff = true
                        break
                    end
                end
                if hasBuff then break end
            end
        end
        return hasBuff
    elseif data.isCombatTracked then
        if not lastFireTime then
            return true 
        end
        local elapsed = GetTime() - lastFireTime
        return elapsed <= 2.5
    end

    return true
end

--------------------------------------------------------------------------------
-- Dynamic Layout & Refresh UI State
--------------------------------------------------------------------------------
local function UpdateLayoutAndTotems()
    local playerLevel = UnitLevel("player") or 1
    local visibleSlots = {}

    for _, box in ipairs(slots) do
        if playerLevel >= box.levelReq then
            table.insert(visibleSlots, box)
            if not InCombatLockdown() then
                box:Show()
            end
        else
            if not InCombatLockdown() then
                box:Hide()
            end
        end
    end

        -- Loop through visibleSlots here, while it is in scope!
    for i, box in ipairs(visibleSlots) do
    if not InCombatLockdown() then
        box:ClearAllPoints()
        box:SetPoint("LEFT", f, "LEFT", (i - 1) * 44, 0)
    end
        
        local haveTotem, name, startTime, duration, icon = GetTotemInfo(box.elementID)
        local data = box.data

        if haveTotem and name ~= "" and duration > 0 then
            box.icon:SetTexture(icon)
            box.icon:SetDesaturated(false)
            box.icon:SetVertexColor(1, 1, 1)

            -- Fine-tune range checking to strictly isolate Searing Totem from generic fire utilities
            local inRange = true
            if box.elementID == 1 then -- Fire Slot
                if string.find(name, "Searing Totem") then
                    inRange = EvaluateTotemRange(box, haveTotem)
                else
                    -- Keep other fire totems (Fire Nova, Magma) normal instead of flashing red
                    inRange = true
                end
            else
                -- Fall back to standard range validation rules for Earth, Water, and Air slots
                inRange = EvaluateTotemRange(box, haveTotem)
            end

            if not (box.flashUntil and box.flashUntil > GetTime()) then
                if inRange then
                    box.border:SetColorTexture(data.color[1], data.color[2], data.color[3], 1)
                    box.icon:SetAlpha(1.0)
                else
                    box.border:SetColorTexture(1.0, 0.1, 0.1, 1) -- Red range warning border
                    box.icon:SetAlpha(0.5)
                end
            end
        else
            local chosen = box.chosen or ResolveChoice(data)
            local _, _, chosenIcon = chosen and GetSpellInfo(chosen)
            box.icon:SetTexture(chosenIcon or data.defaultIcon)
            box.icon:SetDesaturated(true)
            box.icon:SetVertexColor(0.5, 0.5, 0.5)
            if not (box.flashUntil and box.flashUntil > GetTime()) then
                box.border:SetColorTexture(0.2, 0.2, 0.2, 1)
            end
            box.cd:Clear()
            box.icon:SetAlpha(0.6)
        end
    end

if not InCombatLockdown() then
    dropAll:ClearAllPoints()
    imbueBox:ClearAllPoints()
    if #visibleSlots > 0 then
        dropAll:SetPoint("LEFT", visibleSlots[#visibleSlots], "RIGHT", 10, 0)
        dropAll:Show()
        imbueBox:SetPoint("LEFT", dropAll, "RIGHT", 10, 0)
    else
        dropAll:Hide()
        imbueBox:SetPoint("LEFT", f, "LEFT", 0, 0)
    end
end
end

--------------------------------------------------------------------------------
-- Logic: Weapon Imbue Visuals & 1-Minute Warning Pulsing Glow
--------------------------------------------------------------------------------
local function UpdateImbue()
    if not imbueBox or not imbueBox.icon or not imbueBox.border then return end

    local currentSelectedSpell = CysTotemsDB.selectedImbue or "Rockbiter Weapon"
    local _, _, selectedSpellIcon = GetSpellInfo(currentSelectedSpell)

    local hasMainHandEnchant, mainHandExpiration = GetWeaponEnchantInfo()
    local mainLink = GetInventoryItemLink("player", 16)
    
    local textureToDisplay = selectedSpellIcon or (mainLink and select(10, GetItemInfo(mainLink))) or "Interface\\Icons\\INV_Weapon_ShortBlade_01"
    imbueBox.icon:SetTexture(textureToDisplay)

    if hasMainHandEnchant then
        imbueBox.icon:SetDesaturated(false)
        local durationSec = floor((mainHandExpiration or 0) / 1000)
        local startTime = GetTime() - (1800 - durationSec)
        
        if imbueBox.cd then 
            imbueBox.cd:SetCooldown(startTime, 1800)
            imbueBox.cd:SetSwipeColor(0, 0, 0, 0)
        end
        
        -- 1-Minute Remaining: Flash/Pulse Warning State
        if durationSec <= 60 and durationSec > 0 then
            -- Calculate a smooth alpha pulse wave using a sine curve based on game time
            local pulseAlpha = 0.3 + (math.sin(GetTime() * 7) * 0.7)
            
            -- Pulse the border and icon tint red to grab your attention
            imbueBox.border:SetColorTexture(1.0, 0.1, 0.1, pulseAlpha)
            imbueBox.icon:SetVertexColor(1, 0.4, 0.4)

            if not imbueBox.warnedThisCycle then
                print(string.format("|cff00aaffCysTotems Warning: %s has less than 1 minute remaining!|r", currentSelectedSpell))
                imbueBox.warnedThisCycle = true
            end
        else
            -- Normal Active State (More than 1 minute remaining)
            imbueBox.icon:SetVertexColor(1, 1, 1)
            imbueBox.border:SetColorTexture(0.0, 0.8, 1.0, 1) -- Static blue active border
            
            if durationSec > 60 then
                imbueBox.warnedThisCycle = false
            end
        end
    else
        -- Completely Missing State
        imbueBox.icon:SetDesaturated(false)
        imbueBox.icon:SetVertexColor(1, 0.4, 0.4)
        imbueBox.border:SetColorTexture(1.0, 0.1, 0.1, 1) -- Solid red when completely missing
        if imbueBox.cd then imbueBox.cd:Clear() end
        imbueBox.warnedThisCycle = false
    end
end
_G.CysTotemsUpdateImbueVisual = UpdateImbue




-- Event Handling & Combat Log Listener

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_TOTEM_UPDATE")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(self, event, unit, _, spellID)
if event == "PLAYER_LOGIN" or event == "PLAYER_LEVEL_UP" or event == "SPELLS_CHANGED" then
ApplyChoices()
UpdateLayoutAndTotems()
UpdateImbue()
elseif event == "PLAYER_REGEN_ENABLED" then
UpdateImbueMacro()
ApplyChoices()
UpdateLayoutAndTotems()
elseif event == "PLAYER_TOTEM_UPDATE" or event == "UNIT_AURA" then
if event == "UNIT_AURA" and unit ~= "player" then return end
UpdateLayoutAndTotems()
           elseif event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
        -- 1. Grab the current enchantment ID BEFORE updating the visual state
        local hasMainHandEnchant, _, _, oldEnchantID = GetWeaponEnchantInfo()
        
        -- 2. Let the visual update run its course
        UpdateImbue()
        
        -- 3. Grab the new state after the visual code executes
        local currentlyHasEnchant, _, _, newEnchantID = GetWeaponEnchantInfo()
        local currentSelectedSpell = CysTotemsDB.selectedImbue or "Rockbiter Weapon"
        
        -- 4. Check if we just gained an enchant OR if the internal engine ID swapped 
        -- OR if the active selected spell doesn't match what we last logged
        if currentlyHasEnchant then
            local isNewEnchant = not imbueBox.hadEnchant
            local idChanged = (oldEnchantID and newEnchantID and oldEnchantID ~= newEnchantID)
            local spellChanged = (imbueBox.lastPrintedSpell ~= currentSelectedSpell)
            
            if isNewEnchant or idChanged or spellChanged then
                -- Print the vibrant electric blue notification text
                print(string.format("|cff00aaffCysTotems: %s applied!|r", currentSelectedSpell))
                -- Cache the current spell name to prevent duplicates on passive inventory updates
                imbueBox.lastPrintedSpell = currentSelectedSpell
            end
        else
            -- Reset the tracking variables clear if the enchant drops completely
            imbueBox.lastPrintedSpell = nil
        end
        
        -- Save the baseline state for the next event loop check
        imbueBox.hadEnchant = currentlyHasEnchant



elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2, spellId, spellName = CombatLogGetCurrentEventInfo()
if sourceName and string.find(sourceName, "Searing Totem") then
if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_MISSED" then
lastFireTime = GetTime()
end
end
end
end)
-- Smart Update Timer (0.3s loop)
C_Timer.NewTicker(0.3, function()
UpdateLayoutAndTotems()
UpdateImbue()
end)
end,
})
