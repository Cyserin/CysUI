--------------------------------------------------------------------------------
-- Cys's Armory - gear set manager for WoW Classic Era (1.15.x)
--
-- Saves your equipped gear as named sets, equips them again with one click, shows
-- which sets an item belongs to (tooltips + Cys's Bags highlight/category), and can
-- create a character macro per set. Includes automatic spec/shield set swapping.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "armory", name = "Cys's Armory",
    desc = "Save your gear as named sets and put them back on in one click.",
    open = function()
        if CharacterFrame and not CharacterFrame:IsShown() then ToggleCharacter("PaperDollFrame") end
        if CysArmoryFrame then CysArmoryFrame:Show() end
    end,
    body = function(...)
local ADDON_NAME = ...


CysArmoryDB = CysArmoryDB or {}
CysArmory = CysArmory or {}
local CysArmory = CysArmory
CysArmory.version = "2.2.2"

local format, sort = string.format, table.sort
local floor, max, min = math.floor, math.max, math.min

--------------------------------------------------------------------------------
-- Style (same palette as Cys's Bags)
--------------------------------------------------------------------------------
local function Hex(hex, a)
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        a or 1,
    }
end

local C = {
    bg        = Hex("111111"),
    header    = Hex("141414"),
    field     = Hex("0A0A0A"),
    card      = Hex("151515"),
    cardHover = Hex("1D1D1D"),
    button    = Hex("1A1A1A"),
    border    = CysUI.W.T.border, -- frame colour (follows the Border color setting)
    accent    = Hex("FFD100"), -- bright gold: active / hover / primary
    line      = Hex("2A2A2A"),
    text      = Hex("E0E0E0"),
    dim       = Hex("777777"),
    cyan      = Hex("00D9FF"), -- "this item belongs to a set"
    danger    = Hex("FF4040"),
    dark      = Hex("111111"),
}

local PANEL_W, PANEL_H = 300, 258
local PAD = 10
local HEADER_H = 30
local ROW_H, ROW_GAP = 46, 4
local ROW_W = PANEL_W - PAD * 2 - 10
local MAX_ICONS = 9
local LIST_TOP = 100

local function Say(msg) print("|cFFFFD100[Cys's Armory]|r " .. msg) end

local function SolidTexture(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    if color == C.border then CysUI.W.TrackEdge(t) end
    return t
end

local function CreateBorder(parent, thickness, color, layer, sublevel)
    local e = {}
    for i = 1, 4 do e[i] = SolidTexture(parent, layer or "BORDER", color, sublevel) end
    e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(thickness)
    e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(thickness)
    e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(thickness)
    e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(thickness)
    return e
end

local function SetBorderColor(edges, color)
    for i = 1, 4 do edges[i]:SetColorTexture(color[1], color[2], color[3], 1) end
end

local function CreateText(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function CreateFlatButton(parent, width, height, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.bg = SolidTexture(b, "BACKGROUND", C.button)
    b.bg:SetAllPoints()
    b.edges = CreateBorder(b, 1, C.line, "BORDER")
    b.label = CreateText(b, 11, C.accent, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label or "")
    b:SetScript("OnEnter", function(s) SetBorderColor(s.edges, C.accent) end)
    b:SetScript("OnLeave", function(s) SetBorderColor(s.edges, C.line) end)
    b:SetScript("OnMouseDown", function(s) s.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(s) s.label:SetPoint("CENTER", 0, 0) end)
    return b
end

local function CreateIconButton(parent, size, texture)
    local b = CreateFlatButton(parent, size, size, "")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetDesaturated(true)
    b.icon:SetVertexColor(0.8, 0.8, 0.8)
    b:SetScript("OnEnter", function(s)
        SetBorderColor(s.edges, s.armed and C.danger or C.accent)
        s.icon:SetDesaturated(false)
        s.icon:SetVertexColor(1, 1, 1)
        if s.ShowTip then
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            s:ShowTip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s)
        SetBorderColor(s.edges, s.armed and C.danger or C.line)
        s.icon:SetDesaturated(true)
        s.icon:SetVertexColor(0.8, 0.8, 0.8)
        GameTooltip:Hide()
    end)
    return b
end

--------------------------------------------------------------------------------
-- API compatibility & Helpers
--------------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink
local GetSlotItemID = (CC and CC.GetContainerItemID) or GetContainerItemID

local function ParseItem(v)
    if type(v) == "number" then return v, nil end
    if type(v) ~= "string" then return nil end
    local id = tonumber(v:match("item:(%-?%d+)")) or tonumber(v)
    if not id then return nil end
    local suffix = v:match("item:%-?%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d*)")
    return id, tonumber(suffix)
end

local function SameItem(a, b)
    local ida, sa = ParseItem(a)
    local idb, sb = ParseItem(b)
    if not ida or ida ~= idb then return false end
    if sa and sb and sa ~= sb then return false end
    return true
end

local function GetItemString(link)
    local id, suffix = ParseItem(link)
    if not id then return nil end
    return format("item:%d:0:0:0:0:0:%d", id, suffix or 0)
end

local function GetDB()
    local realm, name = GetRealmName(), UnitName("player")
    if not realm or not name or name == UNKNOWN then return {} end
    local key = realm .. " - " .. name
    CysArmoryDB[key] = CysArmoryDB[key] or {}
    if not CysArmoryDB[key].sets then
        local old = {}
        for k, v in pairs(CysArmoryDB[key]) do
            if type(v) == "table" and k ~= "specBindings" and k ~= "_meta" then
                old[k] = v
            end
        end
        CysArmoryDB[key] = { sets = old, specBindings = CysArmoryDB[key].specBindings or {} }
    end
    return CysArmoryDB[key].sets
end

local function GetCharDB()
    local realm, name = GetRealmName(), UnitName("player")
    if not realm or not name or name == UNKNOWN then return {} end
    local key = realm .. " - " .. name
    CysArmoryDB[key] = CysArmoryDB[key] or { sets = {}, specBindings = {} }
    return CysArmoryDB[key]
end

local function FindSetName(db, input)
    if not input or input == "" then return nil end
    if type(db[input]) == "table" then return input end
    local lowered = input:lower()
    for name, data in pairs(db) do
        if type(data) == "table" and name:lower() == lowered then return name end
    end
    return nil
end

local function FindItemInBags(saved)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local link = GetSlotLink(bag, slot)
            if link and SameItem(saved, link) then return bag, slot, link end
        end
    end
end

local function BuildOwnedIndex()
    local owned = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then owned[id] = true end
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetSlotItemID(bag, slot)
            if id then owned[id] = true end
        end
    end
    return owned
end

local function IsSetEquipped(set)
    local any = false
    for slot, saved in pairs(set) do
        if type(slot) == "number" then
            any = true
            if not SameItem(saved, GetInventoryItemLink("player", slot)) then return false end
        end
    end
    return any
end

local setIndex
local function InvalidateSetIndex() setIndex = nil end

local function RebuildSetIndex()
    setIndex = {}
    for setName, set in pairs(GetDB()) do
        if type(set) == "table" then
            for _, saved in pairs(set) do
                local id, suffix = ParseItem(saved)
                if id then
                    local list = setIndex[id]
                    if not list then list = {}; setIndex[id] = list end
                    list[#list + 1] = { name = setName, suffix = suffix }
                end
            end
        end
    end
end

function CysArmory:GetSetsForItem(itemLink, itemID)
    if not setIndex then RebuildSetIndex() end
    local id, suffix = itemID, nil
    if itemLink then
        local linkID, linkSuffix = ParseItem(itemLink)
        id = id or linkID
        suffix = linkSuffix
    end
    local out = {}
    local list = id and setIndex[id]
    if list then
        for _, entry in ipairs(list) do
            if not (suffix and entry.suffix and suffix ~= entry.suffix) then
                local dup = false
                for _, n in ipairs(out) do
                    if n == entry.name then dup = true; break end
                end
                if not dup then out[#out + 1] = entry.name end
            end
        end
        sort(out)
    end
    return out
end

function CysArmory:IsItemInSet(itemID)
    return #self:GetSetsForItem(nil, itemID) > 0
end

--------------------------------------------------------------------------------
-- Tooltip & Bags Integration
--------------------------------------------------------------------------------
local function OnTooltipSetItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local link = tooltip.GetItem and select(2, tooltip:GetItem())
    local itemID = (data and data.id) or (link and ParseItem(link))
    local sets = CysArmory:GetSetsForItem(link, itemID)
    if #sets > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cFF00D9FFCys's Armory:|r " .. table.concat(sets, ", "), 1, 1, 1, true)
        tooltip:Show()
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    GameTooltip:HookScript("OnTooltipSetItem", function(t) OnTooltipSetItem(t) end)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", function(t) OnTooltipSetItem(t) end)
    end
end

local function NotifyBags()
    if CysBags and CysBags.RefreshHighlights then CysBags:RefreshHighlights() end
end

local function IntegrateWithBags()
    if CysBags and CysBags.RegisterSetHighlighter and not CysArmory.bagsRegistered then
        CysArmory.bagsRegistered = true
        CysBags:RegisterSetHighlighter(function(itemID, bag, slot, link)
            local sets = CysArmory:GetSetsForItem(link, itemID)
            if #sets > 0 then return true, table.concat(sets, ", ") end
            return false
        end)
    end
end

--------------------------------------------------------------------------------
-- Set operations & Auto-Switching
--------------------------------------------------------------------------------
local panel

local function AfterSetsChanged()
    InvalidateSetIndex()
    if panel and panel:IsShown() then CysArmory:RefreshSetList() end
    NotifyBags()
end

function CysArmory:SaveSet(name)
    name = name and strtrim(name) or ""
    if name == "" then return false end
    local set = {}
    for slot = 1, 19 do
        local str = GetItemString(GetInventoryItemLink("player", slot))
        if str then set[slot] = str end
    end
    GetDB()[name] = set
    Say("Saved set: |cFFFFD100" .. name .. "|r")
    AfterSetsChanged()
    return true
end

function CysArmory:DeleteSet(name)
    local db = GetDB()
    name = FindSetName(db, name)
    if not name then return false end
    db[name] = nil
    
    local charDB = GetCharDB()
    if charDB.specBindings then
        for k, boundName in pairs(charDB.specBindings) do
            if boundName == name then charDB.specBindings[k] = nil end
        end
    end

    Say("Deleted set: |cFFFFD100" .. name .. "|r")
    AfterSetsChanged()
    return true
end

local function EquipPass(set)
    local sent = 0
    for slot = 1, 19 do
        local saved = set[slot]
        if saved and not SameItem(saved, GetInventoryItemLink("player", slot)) then
            local bag, bagSlot, link = FindItemInBags(saved)
            if bag then
                EquipItemByName(link, slot)
                sent = sent + 1
            end
        end
    end
    return sent
end

local equipToken = 0

function CysArmory:EquipSet(name)
    local db = GetDB()
    name = FindSetName(db, name)
    if not name then Say("|cFFFF4040Set not found.|r"); return end
    if CursorHasItem() then Say("Drop the item on your cursor first."); return end

    equipToken = equipToken + 1
    local token, passes = equipToken, 0
    local function Pass()
        if token ~= equipToken then return end
        local set = GetDB()[name]
        if not set then return end
        passes = passes + 1
        local sent = EquipPass(set)
        if passes == 1 then
            if sent == 0 then
                Say("You're already wearing |cFFFFD100" .. name .. "|r.")
                return
            end
            Say("Equipping: |cFFFFD100" .. name .. "|r")
        end
        if sent > 0 and passes < 4 then C_Timer.After(0.35, Pass) end
    end
    Pass()
end

function CysArmory:CreateMacro(name)
    local macroName = ("CA_" .. name):sub(1, 16)
    if GetMacroIndexByName(macroName) ~= 0 then
        Say("|cFFFF4040Macro " .. macroName .. " already exists.|r")
        return
    end
    local ok, err = pcall(CreateMacro, macroName, "INV_Misc_QuestionMark", "/armory equip " .. name, true)
    if ok then
        Say("Created character macro: |cFFFFD100" .. macroName .. "|r")
    else
        Say("|cFFFF4040Couldn't create the macro (" .. tostring(err) .. ").|r")
    end
end

local function CheckAutoEquipSet(event)
    -- Don't run auto-equip checks while in combat
    if InCombatLockdown() then return end

    local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
    if not CysUIDB or not CysUIDB.armory or not CysUIDB.armory.charSets or not CysUIDB.armory.charSets[charKey] then return end

    local charDB = CysUIDB.armory.charSets[charKey]
    charDB.specBindings = charDB.specBindings or {}

    -- Retrieve current spec (1 or 2)
    local activeSpec = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    local boundSetName = charDB.specBindings[activeSpec]

    -- STRICT RULE: Only auto-equip if the set is explicitly bound to the current spec!
    if boundSetName and charDB.sets and charDB.sets[boundSetName] then
        -- Equip the bound set only if it isn't already equipped
        if EquipSavedSet then
            EquipSavedSet(boundSetName)
        end
    end
    -- If no set is bound to spec 1 or 2, DO NOTHING on equipment change.
end

--------------------------------------------------------------------------------
-- Main panel & Spec Checkboxes
--------------------------------------------------------------------------------
local rows = {}
local scroll, content, thumb, emptyText, input, inputEdges, saveBtn
local spec1Check, spec2Check

local function UpdateThumb()
    if not (scroll and thumb) then return end
    local range = scroll:GetVerticalScrollRange()
    if not range or range <= 0 then thumb:Hide(); return end
    local viewH = scroll:GetHeight()
    local thumbH = max(24, viewH * viewH / (viewH + range))
    local y = (scroll:GetVerticalScroll() / range) * (viewH - thumbH)
    thumb:ClearAllPoints()
    thumb:SetSize(3, thumbH)
    thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, -y)
    thumb:Show()
end

local function UpdateSpecBindingCheckboxes(currentSetName)
    if not (spec1Check and spec2Check) then return end
    local charDB = GetCharDB()
    charDB.specBindings = charDB.specBindings or {}
    spec1Check:SetChecked(charDB.specBindings[1] == currentSetName)
    spec2Check:SetChecked(charDB.specBindings[2] == currentSetName)
end

local function ShowRowTooltip(row)
    local set = GetDB()[row.setName]
    if not set then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.setName, C.accent[1], C.accent[2], C.accent[3])
    
    -- Show Spec binding status in tooltip if bound
    local charDB = GetCharDB()
    if charDB.specBindings then
        if charDB.specBindings[1] == row.setName then
            GameTooltip:AddLine("(Bound to Spec 1)", 0, 0.84, 1)
        elseif charDB.specBindings[2] == row.setName then
            GameTooltip:AddLine("(Bound to Spec 2)", 0, 0.84, 1)
        end
    end

    GameTooltip:AddLine("Click to equip", C.dim[1], C.dim[2], C.dim[3])
    GameTooltip:AddLine(" ")
    local owned = row.owned or {}
    for slot = 1, 19 do
        local saved = set[slot]
        if saved then
            local id = ParseItem(saved)
            local name, _, quality = GetItemInfo(id or 0)
            local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            local text = name or ("item:" .. tostring(id))
            local r, g, b = 1, 1, 1
            if qc then r, g, b = qc.r, qc.g, qc.b end
            if id and not owned[id] then
                text = text .. " (missing)"
                r, g, b = 1, 0.25, 0.25
            end
            GameTooltip:AddDoubleLine(tostring(slot), text, 0.6, 0.6, 0.6, r, g, b)
        end
    end
    GameTooltip:Show()
end

local function CreateRow()
    local row = CreateFrame("Button", nil, content)
    row:SetSize(ROW_W, ROW_H)
    row.bg = SolidTexture(row, "BACKGROUND", C.card)
    row.bg:SetAllPoints()
    row.edges = CreateBorder(row, 1, C.line, "BORDER")
    row.accentBar = SolidTexture(row, "ARTWORK", C.accent)
    row.accentBar:SetPoint("TOPLEFT")
    row.accentBar:SetPoint("BOTTOMLEFT")
    row.accentBar:SetWidth(2)

    row.name = CreateText(row, 12, C.text)
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetWidth(168)
    row.name:SetWordWrap(false)
    row.tag = CreateText(row, 9, C.cyan, "RIGHT") -- which spec this set is bound to
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -80, -9)
    row.restColor = C.card

    row.icons = {}
    for i = 1, MAX_ICONS do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetPoint("TOPLEFT", 10 + (i - 1) * 18, -25)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icons[i] = t
    end
    row.more = CreateText(row, 10, C.dim)
    row.more:SetPoint("LEFT", row.icons[MAX_ICONS], "RIGHT", 3, 0)

    row.delBtn = CreateIconButton(row, 20, "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.delBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.macroBtn = CreateIconButton(row, 20, "Interface\\Icons\\INV_Misc_Note_01")
    row.macroBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -4, 0)
    row.updateBtn = CreateIconButton(row, 20, "Interface\\Buttons\\UI-RefreshButton")
    row.updateBtn:SetPoint("RIGHT", row.macroBtn, "LEFT", -4, 0)

    function row.updateBtn:ShowTip(tip)
        tip:SetText("Update set", 1, 1, 1)
        tip:AddLine("Overwrite this set with the gear you're wearing now.", 0.8, 0.8, 0.8, true)
    end
    function row.macroBtn:ShowTip(tip)
        tip:SetText("Create macro", 1, 1, 1)
        tip:AddLine("Adds a character macro that equips this set.", 0.8, 0.8, 0.8, true)
    end
    function row.delBtn:ShowTip(tip)
        if self.armed then
            tip:SetText("Click again to delete", 1, 0.25, 0.25)
        else
            tip:SetText("Delete set", 1, 1, 1)
        end
    end

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        CysArmory:EquipSet(self.setName)
        if input then input:SetText(self.setName) end
        UpdateSpecBindingCheckboxes(self.setName)
    end)
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.cardHover[1], C.cardHover[2], C.cardHover[3], 1)
        ShowRowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        local rc = self.restColor or C.card
        self.bg:SetColorTexture(rc[1], rc[2], rc[3], 1)
        GameTooltip:Hide()
    end)

    row.updateBtn:SetScript("OnClick", function() CysArmory:SaveSet(row.setName) end)
    row.macroBtn:SetScript("OnClick", function() CysArmory:CreateMacro(row.setName) end)
    row.delBtn:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = false
            CysArmory:DeleteSet(row.setName)
        else
            self.armed = true
            SetBorderColor(self.edges, C.danger)
            self.icon:SetDesaturated(false)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            self:ShowTip(GameTooltip)
            GameTooltip:Show()
            C_Timer.After(3, function()
                if self.armed then
                    self.armed = false
                    SetBorderColor(self.edges, C.line)
                end
            end)
        end
    end)
    return row
end

local PREVIEW_ORDER = { 16, 17, 18, 1, 3, 5, 7, 10, 8, 9, 6, 15, 2, 11, 12, 13, 14, 4, 19 }

local function FillRow(row, name, set, owned)
    row.setName, row.owned = name, owned
    row.delBtn.armed = false
    SetBorderColor(row.delBtn.edges, C.line)

    local equipped = IsSetEquipped(set)
    row.accentBar:SetShown(equipped)
    -- the set you are wearing gets a warm tint, not just the thin bar
    row.restColor = equipped and { 0.17, 0.145, 0.05, 1 } or C.card
    row.bg:SetColorTexture(row.restColor[1], row.restColor[2], row.restColor[3], 1)
    local bind = GetCharDB().specBindings or {}
    local tag = (bind[1] == name and bind[2] == name) and "Spec 1+2" or (bind[1] == name and "Spec 1") or (bind[2] == name and "Spec 2") or ""
    row.tag:SetText(tag)
    row.name:SetText(name)
    local c = equipped and C.accent or C.text
    row.name:SetTextColor(c[1], c[2], c[3])

    local shown, total = 0, 0
    for _, slot in ipairs(PREVIEW_ORDER) do
        local saved = set[slot]
        if saved then
            total = total + 1
            if shown < MAX_ICONS then
                shown = shown + 1
                local id = ParseItem(saved)
                local icon = id and select(5, GetItemInfoInstant(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
                local t = row.icons[shown]
                t:SetTexture(icon)
                if id and owned[id] then
                    t:SetDesaturated(false)
                    t:SetVertexColor(1, 1, 1)
                else
                    t:SetDesaturated(true)
                    t:SetVertexColor(1, 0.35, 0.35)
                end
                t:Show()
            end
        end
    end
    for i = shown + 1, MAX_ICONS do row.icons[i]:Hide() end
    row.more:SetText(total > shown and ("+" .. (total - shown)) or "")
end

function CysArmory:RefreshSetList()
    if not panel then return end
    local db = GetDB()
    local names = {}
    for name, set in pairs(db) do
        if type(set) == "table" then names[#names + 1] = name end
    end
    sort(names, function(a, b) return a:lower() < b:lower() end)

    local owned = BuildOwnedIndex()
    for i, name in ipairs(names) do
        local row = rows[i]
        if not row then
            row = CreateRow()
            rows[i] = row
        end
        FillRow(row, name, db[name], owned)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
        row:Show()
    end
    for i = #names + 1, #rows do rows[i]:Hide() end

    if panel.count then panel.count:SetText(#names == 1 and "1 set" or (#names .. " sets")) end
    content:SetHeight(max(1, #names * (ROW_H + ROW_GAP) - ROW_GAP))
    emptyText:SetShown(#names == 0)
    UpdateThumb()
end

local function CreatePanel()
    panel = CreateFrame("Frame", "CysArmoryFrame", CharacterFrame)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -32, -12)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    panel:Hide()
    SolidTexture(panel, "BACKGROUND", C.bg):SetAllPoints()
    CreateBorder(panel, 1, C.border, "BORDER")

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    SolidTexture(header, "BACKGROUND", C.header):SetAllPoints()
    local hline = SolidTexture(header, "BORDER", C.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)

    local glow = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 1)
    local gc = C.border
    if glow.SetGradient and CreateColor then
        pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(gc[1], gc[2], gc[3], 0), CreateColor(gc[1], gc[2], gc[3], 0.14))
    end

    local title = CreateText(header, 13, C.accent)
    title:SetPoint("LEFT", 12, 0)
    title:SetText("Cys's Armory")
    panel.count = CreateText(header, 10, C.dim, "RIGHT")
    panel.count:SetPoint("RIGHT", -34, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -6, 0)
    close.text = CreateText(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() panel:Hide() end)

    input = CreateFrame("EditBox", nil, panel)
    input:SetSize(PANEL_W - PAD * 2 - 78, 20)
    input:SetPoint("TOPLEFT", PAD, -(HEADER_H + 8))
    input:SetAutoFocus(false)
    input:SetMaxLetters(24)
    input:SetFont(STANDARD_TEXT_FONT, 12, "")
    input:SetTextColor(C.text[1], C.text[2], C.text[3])
    input:SetTextInsets(8, 8, 0, 0)
    SolidTexture(input, "BACKGROUND", C.field):SetAllPoints()
    local inputEdges = CreateBorder(input, 1, C.border, "BORDER")
    
    input.placeholder = CreateText(input, 12, C.dim)
    input.placeholder:SetPoint("LEFT", 8, 0)
    input.placeholder:SetText("Set name...")

    saveBtn = CreateFlatButton(panel, 68, 20, "Save")
    saveBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)
    saveBtn.bg:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    saveBtn.label:SetTextColor(C.dark[1], C.dark[2], C.dark[3])
    SetBorderColor(saveBtn.edges, C.border)
    saveBtn:SetScript("OnEnter", function(s) s.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1) end)
    saveBtn:SetScript("OnLeave", function(s) s.bg:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end)

    local function ResetSaveButton()
        saveBtn.armedFor = nil
        saveBtn.label:SetText("Save")
    end

    local function DoSave()
        local name = strtrim(input:GetText() or "")
        if name == "" then
            SetBorderColor(inputEdges, C.danger)
            C_Timer.After(0.6, function() SetBorderColor(inputEdges, C.border) end)
            return
        end
        if GetDB()[name] and saveBtn.armedFor ~= name then
            saveBtn.armedFor = name
            saveBtn.label:SetText("Overwrite?")
            C_Timer.After(3, function() if saveBtn.armedFor == name then ResetSaveButton() end end)
            return
        end
        ResetSaveButton()
        CysArmory:SaveSet(name)
        UpdateSpecBindingCheckboxes(name)
    end
    saveBtn:SetScript("OnClick", DoSave)
    input:SetScript("OnEnterPressed", DoSave)

    input:SetScript("OnEscapePressed", function(s)
        if s:GetText() ~= "" then
            s:SetText("")
        else
            s:ClearFocus()
        end
    end)

    input:SetScript("OnEditFocusGained", function(s)
        s.placeholder:Hide()
        SetBorderColor(inputEdges, C.accent)
    end)

    input:SetScript("OnEditFocusLost", function(s)
        s.placeholder:SetShown(s:GetText() == "")
        SetBorderColor(inputEdges, C.border)
    end)

    input:SetScript("OnTextChanged", function(s)
        local text = s:GetText()
        s.placeholder:SetShown(text == "")
    end)

    spec1Check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    spec1Check:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -6)
    spec1Check.text = spec1Check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spec1Check.text:SetPoint("LEFT", spec1Check, "RIGHT", 2, 0)
    spec1Check.text:SetText("Bind to Spec 1")

    spec2Check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    spec2Check:SetPoint("LEFT", spec1Check.text, "RIGHT", 20, 0)
    spec2Check.text = spec2Check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spec2Check.text:SetPoint("LEFT", spec2Check, "RIGHT", 2, 0)
    spec2Check.text:SetText("Bind to Spec 2")

    spec1Check:SetScript("OnClick", function(self)
        local currentName = strtrim(input:GetText() or "")
        if currentName == "" then self:SetChecked(false); return end
        local charDB = GetCharDB()
        charDB.specBindings = charDB.specBindings or {}
        charDB.specBindings[1] = self:GetChecked() and currentName or nil
    end)

    spec2Check:SetScript("OnClick", function(self)
        local currentName = strtrim(input:GetText() or "")
        if currentName == "" then self:SetChecked(false); return end
        local charDB = GetCharDB()
        charDB.specBindings = charDB.specBindings or {}
        charDB.specBindings[2] = self:GetChecked() and currentName or nil
    end)

    local div = SolidTexture(panel, "BORDER", C.line)
    div:SetPoint("TOPLEFT", PAD, -(LIST_TOP - 8))
    div:SetPoint("TOPRIGHT", -PAD, -(LIST_TOP - 8))
    div:SetHeight(1)

    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", PAD, -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 10, PAD)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local value = s:GetVerticalScroll() - delta * (ROW_H + ROW_GAP)
        s:SetVerticalScroll(max(0, min(value, s:GetVerticalScrollRange())))
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(content)

    thumb = SolidTexture(panel, "ARTWORK", { C.border[1], C.border[2], C.border[3], 0.5 })
    thumb:Hide()

    emptyText = CreateText(panel, 11, C.dim, "CENTER")
    emptyText:SetPoint("TOP", panel, "TOP", 0, -(LIST_TOP + 30))
    emptyText:SetWidth(PANEL_W - 60)
    emptyText:SetText("No sets yet.\nEquip your gear, type a name and press Save.")
    emptyText:Hide()

    panel:SetScript("OnShow", function() CysArmory:RefreshSetList() end)
end

local function CreateToggleButton()
    local b = CreateFlatButton(CharacterFrame, 55, 20, "Sets")
    b:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -40, -32)
    b:SetScript("OnClick", function()
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end)
    CysArmory.toggleButton = b
end

--------------------------------------------------------------------------------
-- Slash Commands & Events
--------------------------------------------------------------------------------
SLASH_CYSARMORY1 = "/armory"
SLASH_CYSARMORY2 = "/cysarmory"
SlashCmdList["CYSARMORY"] = function(msg)
    local cmd, name = (msg or ""):match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    name = name and strtrim(name) or ""

    if cmd == "save" and name ~= "" then
        CysArmory:SaveSet(name)
    elseif cmd == "equip" and name ~= "" then
        CysArmory:EquipSet(name)
    elseif cmd == "delete" and name ~= "" then
        if not CysArmory:DeleteSet(name) then Say("|cFFFF4040Set not found.|r") end
    elseif cmd == "list" then
        names = {}
        for setName, set in pairs(GetDB()) do
            if type(set) == "table" then names[#names + 1] = setName end
        end
        sort(names)
        Say(#names > 0 and ("Sets: " .. table.concat(names, ", ")) or "No sets saved yet.")
    else
        Say("Commands:")
        print("  /armory save <name>   - save current gear")
        print("  /armory equip <name>  - equip a set")
        print("  /armory delete <name> - delete a set")
        print("  /armory list          - list sets")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CreatePanel()
        CreateToggleButton()
        InvalidateSetIndex()
        IntegrateWithBags()
        NotifyBags()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        CheckAutoEquipSet(event)
        if panel and panel:IsShown() then CysArmory:RefreshSetList() end
    else
        if panel and panel:IsShown() then CysArmory:RefreshSetList() end
    end
end)
end,
})
