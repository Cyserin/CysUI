--------------------------------------------------------------------------------
-- Cys's Totems - Standalone Shaman Tracker with Combat-Log Range Detection
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "totems", name = "Cys's Totems", class = "SHAMAN",
    desc = "Shaman only: totem timers with range detection and a weapon-imbue button. Move it in layout mode.",
    body = function(...)
local ADDON_NAME = ...
CysTotemsDB = CysTotemsDB or {}
CysTotemsDB.selectedImbue = CysTotemsDB.selectedImbue or "Rockbiter Weapon"

local f = CreateFrame("Frame", "CysTotemsFrame", UIParent)
f:SetSize(210, 42)
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

-- Styling Helper: Create a crisp square icon box with border
local function CreateIconBox(parent, size, labelText)
    local box = CreateFrame("Frame", nil, parent)
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

    return box
end

-- Ordered strictly by unlock level: Earth (4), Fire (10), Water (20), Air (30)
-- Classic Era API element indices: 2=Earth, 1=Fire, 3=Water, 4=Air
local slots = {}
local elementData = {
    { name = "Earth", elementID = 2, levelReq = 4,  defaultIcon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem", color = { 0.2, 0.8, 0.2 }, 
      isBuff = true, buffNames = { "Stoneskin", "Strength of Earth", "Stoneclaw" } },
    { name = "Fire",  elementID = 1, levelReq = 10, defaultIcon = "Interface\\Icons\\Spell_Fire_SearingTotem",     color = { 1.0, 0.3, 0.2 }, 
      isCombatTracked = true }, 
    { name = "Water", elementID = 3, levelReq = 20, defaultIcon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",  color = { 0.2, 0.6, 1.0 }, 
      isBuff = true, buffNames = { "Healing Stream", "Mana Spring", "Fire Resistance" } },
    { name = "Air",   elementID = 4, levelReq = 30, defaultIcon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem", color = { 0.8, 0.8, 1.0 }, 
      isBuff = true, buffNames = { "Grace of Air", "Nature Resistance", "Tranq Air" } },
}

for i = 1, 4 do
    local data = elementData[i]
    local iconBox = CreateIconBox(f, 34, data.name)
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

                        if inRange then
                -- FIXED: Safely unpack the RGB color values from the data table
                box.border:SetColorTexture(data.color[1], data.color[2], data.color[3], 1)
                box.icon:SetAlpha(1.0)
            else
                box.border:SetColorTexture(1.0, 0.1, 0.1, 1) -- Red range warning border
                box.icon:SetAlpha(0.5)
            end

            box.cd:Clear()
        else
            box.icon:SetTexture(data.defaultIcon)
            box.icon:SetDesaturated(true)
            box.icon:SetVertexColor(0.5, 0.5, 0.5)
            box.border:SetColorTexture(0.2, 0.2, 0.2, 1)
            box.cd:Clear()
            box.icon:SetAlpha(0.6)
        end
    end

if not InCombatLockdown() then
    imbueBox:ClearAllPoints()
    if #visibleSlots > 0 then
        imbueBox:SetPoint("LEFT", visibleSlots[#visibleSlots], "RIGHT", 10, 0)
    else
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
UpdateLayoutAndTotems()
UpdateImbue()
elseif event == "PLAYER_REGEN_ENABLED" then
UpdateImbueMacro()
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
