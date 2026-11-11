--------------------------------------------------------------------------------
-- CysBags - categorized all-in-one bags for WoW Classic Era (1.15.x)
--
-- Public API (global table `CysBags`):
--   CysBags:RegisterSetHighlighter(func)   func(itemID, bagID, slotID, itemLink) -> boolean
--   CysBags:UnregisterSetHighlighter(func)
--   CysBags:RefreshHighlights()            call when your saved sets change
--   CysBags:Open() / :Close() / :Toggle() / :IsShown()
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "bags", name = "Cys's Bags",
    desc = "One categorized window for all your bags, with sidebar, search, sort, an All Slots view and drag-to-recategorize.",
    open = function() if CysBags and CysBags.Toggle then CysBags:Toggle() end end,
    body = function(...)
local ADDON_NAME = ...


CysBags = CysBags or {}
local CysBags = CysBags
CysBags.version = "2.4.0"

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local lower, format = string.lower, string.format
local tinsert, sort, wipe = table.insert, table.sort, wipe

--------------------------------------------------------------------------------
-- Style
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
    -- panel colours are the shared ones, so they follow the Window style setting
    bg       = CysUI.W.T.bg,
    border   = CysUI.W.T.border, -- frame colour (follows the Border color setting)
    header   = CysUI.W.T.header,
    sidebar  = CysUI.W.T.sidebar,
    field    = CysUI.W.T.field,
    slot     = CysUI.W.T.button,
    hover    = CysUI.W.T.hover,
    selected = CysUI.W.T.selected,
    line     = CysUI.W.T.line,
    text     = Hex("E0E0E0"),
    dim      = Hex("777777"),
    accent   = Hex("FFD100"), -- gold: active category, focus rings, active bag slot
    cyan     = Hex("00D9FF"), -- reserved for the Cys's Armory set-highlight border
    quest    = Hex("FFD100"),
}

-- Layout
local SLOT_SIZE, SLOT_GAP, COLS = 34, 3, 12 -- COLS follows the window width (corner grip)
local STEP        = SLOT_SIZE + SLOT_GAP
local CONTENT_W   = COLS * STEP - SLOT_GAP
local SIDEBAR_W   = 190
local SIDEBAR_SLIM = 36 -- collapsed sidebar: icons only
local function Slim() return CysBagsDB and CysBagsDB.sidebarSlim and true or false end
local function SideW() return Slim() and SIDEBAR_SLIM or SIDEBAR_W end
local HEADER_H    = 34
local FOOTER_H    = 30
local PAD         = 12
local SECTION_H   = 22
local SECTION_GAP = 12
local FRAME_H     = 540 -- default window height (resize it in /cui layout)
local MIN_COLS, MAX_COLS = 6, 16
local FRAME_W     = CONTENT_W + SIDEBAR_W + PAD * 2 + 2

local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS or 4
-- WoW Forever has one more bag: the reagent bag (a gathering bag goes in that slot, and ore, herbs, cloth and
-- the like land in it). Its items are shown with the rest; its slots are not counted as free space, since only
-- reagents fit there.
local LAST_NORMAL_BAG = LAST_BAG
if CysUICompat and CysUICompat.isForever then
    LAST_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (LAST_BAG + 1)
end

-- Shown for an equipped bag whose real icon can't be read (see UpdateBagSlots)
local FALLBACK_BAG_TEXTURE = "Interface\\Icons\\INV_Misc_Bag_08"

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------
-- Item class IDs (GetItemInfoInstant 6th return). Edit this map to re-sort things.
--  0 Consumable  1 Container  2 Weapon  3 Gem  4 Armor  5 Reagent  6 Projectile
--  7 Trade Goods 8 Item Enhancement  9 Recipe  11 Quiver  12 Quest  13 Key  15 Misc
local CLASS_CATEGORY = {
    [0]  = "CONSUMABLE",
    [2]  = "GEAR",
    [4]  = "GEAR",
    [3]  = "TRADE",
    [5]  = "TRADE",
    [7]  = "TRADE",
    [8]  = "TRADE",
    [9]  = "TRADE",
    [12] = "QUEST",
}

-- A small icon in front of each sidebar category
local SIDEBAR_ICONS = {
    ALL = "Interface\\Icons\\INV_Misc_Bag_08",        SLOTS = "Interface\\Icons\\INV_Misc_Bag_10",
    SETS = "Interface\\Icons\\INV_Chest_Chain_05",    CONSUMABLE = "Interface\\Icons\\INV_Potion_54",
    GEAR = "Interface\\Icons\\INV_Sword_04",          BOE = "Interface\\Icons\\INV_Jewelry_Ring_03",
    QUEST = "Interface\\Icons\\INV_Misc_Note_01",     TRADE = "Interface\\Icons\\INV_Fabric_Linen_01",
    MISC = "Interface\\Icons\\INV_Misc_Gear_01",      JUNK = "Interface\\Icons\\INV_Misc_Coin_03",
}

-- Sidebar entries (label) and main-panel section order (title)
local SIDEBAR = {
    { key = "ALL",        label = "All Items" },
    { key = "SLOTS",      label = "All Slots" },
    { key = "SETS",       label = "Armory Sets" },
    { key = "CONSUMABLE", label = "Consumables" },
    { key = "GEAR",       label = "Armor / Weapons" },
    { key = "BOE",        label = "Bind on Equip" },
    { key = "QUEST",      label = "Quest Items" },       
    { key = "TRADE",      label = "Trade Goods" }, -- short in the sidebar (room for the icon); the section keeps the full title
    { key = "MISC",       label = "Miscellaneous" },
    { key = "JUNK",       label = "Junk" },
}

local SECTIONS = {
    { key = "SETS",       title = "Armory Sets" },
    { key = "CONSUMABLE", title = "Consumables" },
    { key = "GEAR",       title = "Armor / Weapons" },
    { key = "BOE",        title = "Bind on Equip" },
    { key = "QUEST",      title = "Quest Items" }, 
    { key = "TRADE",      title = "Trade Goods / Professions" },
    { key = "MISC",       title = "Miscellaneous" },
    { key = "JUNK",       title = "Junk" },
}

local VALID_CATEGORY, CATEGORY_TITLE = {}, {}
for _, sec in ipairs(SECTIONS) do
    VALID_CATEGORY[sec.key] = true
    CATEGORY_TITLE[sec.key] = sec.title
end

--------------------------------------------------------------------------------
-- API compatibility (C_Container on newer 1.14/1.15 clients, globals on older)
--------------------------------------------------------------------------------
local CC = C_Container

local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetItemCooldown = (CC and CC.GetContainerItemCooldown) or GetContainerItemCooldown
local GetNumFreeSlots = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local PickupItem = (CC and CC.PickupContainerItem) or PickupContainerItem

-- returns icon, count, locked, quality, link, itemID
local function GetSlotItem(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if not info then return end
        return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.hyperlink, info.itemID
    end
    local icon, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    return icon, count, locked, quality, link, itemID
end

local function IsQuestSlot(bag, slot)
    if CC and CC.GetContainerItemQuestInfo then
        local q = CC.GetContainerItemQuestInfo(bag, slot)
        return q and q.isQuestItem or false
    elseif GetContainerItemQuestInfo then
        return (GetContainerItemQuestInfo(bag, slot)) and true or false
    end
    return false
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local frame, header, sidebar, footer, scroll, content
local holders, buttons = {}, {}

-- WoW Forever runs on the retail client: item buttons are their own frame type ("ItemButton")
-- and ItemButtonTemplate no longer exists as an XML template. Era keeps the old Button + template.
local IS_FOREVER = CysUICompat and CysUICompat.isForever
local function NewItemButton(name, parent, template)
    if IS_FOREVER then
        if template == "ItemButtonTemplate" then template = nil end
        return CreateFrame("ItemButton", name, parent, template)
    end
    return CreateFrame("Button", name, parent, template)
end
local sidebarButtons = {}
local sectionHeaders = {}
local activeButtons = {}
local entryPool, lists, counts = {}, {}, {}
local highlighters, erroredHighlighters = {}, {}
local nameCache, lowerCache, classCache = {}, {}, {}
local slotEntries = {} -- slotEntries[bag][slot] = entry (for the All Slots view)
local setLookup = {} -- itemIDs found in Cys's Armory's saved sets (rebuilt on every Collect)

for _, s in ipairs(SECTIONS) do lists[s.key] = {} end

CysBags.filter = "ALL"
CysBags.search = ""
CysBags.dirty = true
CysBags.used, CysBags.total, CysBags.free = 0, 0, 0

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------
local function SolidTexture(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    if color == C.border then CysUI.W.TrackEdge(t) end
    return t
end

-- Flat border made of 4 textures drawn inside `parent`'s edges.
local function CreateBorder(parent, thickness, color, layer, sublevel)
    local e = {}
    for i = 1, 4 do e[i] = SolidTexture(parent, layer or "BORDER", color, sublevel) end
    e[1]:SetPoint("TOPLEFT");     e[1]:SetPoint("TOPRIGHT");     e[1]:SetHeight(thickness)
    e[2]:SetPoint("BOTTOMLEFT");  e[2]:SetPoint("BOTTOMRIGHT");  e[2]:SetHeight(thickness)
    e[3]:SetPoint("TOPLEFT");     e[3]:SetPoint("BOTTOMLEFT");   e[3]:SetWidth(thickness)
    e[4]:SetPoint("TOPRIGHT");    e[4]:SetPoint("BOTTOMRIGHT");  e[4]:SetWidth(thickness)
    return e
end

local function SetBorderColor(edges, r, g, b, a)
    for i = 1, #edges do edges[i]:SetColorTexture(r, g, b, a or 1) end
end

local function ShowBorder(edges, show)
    for i = 1, #edges do edges[i]:SetShown(show) end
end

local function CreateText(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

--------------------------------------------------------------------------------
-- Item helpers
--------------------------------------------------------------------------------
local function GetItemName(link)
    local n = nameCache[link]
    if not n then
        n = link:match("%[(.-)%]") or "?"
        nameCache[link] = n
        lowerCache[link] = lower(n)
    end
    return n, lowerCache[link]
end

local function GetItemClass(itemID)
    local c = classCache[itemID]
    if c == nil then
        local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
        c = classID
        if c ~= nil then classCache[itemID] = c end
    end
    return c
end
local scanner = CreateFrame("GameTooltip", "CysBagsTooltipScanner", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function IsBoE(bag, slot)
    scanner:ClearLines()
    scanner:SetBagItem(bag, slot)
    for i = 1, scanner:NumLines() do
        local text = _G["CysBagsTooltipScannerTextLeft" .. i]:GetText()
        if text then
            if text == ITEM_BIND_ON_EQUIP or text:find("Bind on Equip", 1, true) then
                return true
            end
        end
    end
    return false
end
local function Categorize(e)
    if e.isQuest or CLASS_CATEGORY[GetItemClass(e.itemID)] == "QUEST" then return "QUEST" end
    if e.quality == 0 then return "JUNK" end
    if e.isBoE then return "BOE" end -- <--- Catches BoE gear into its own section
    
    local cat = CLASS_CATEGORY[GetItemClass(e.itemID)]
    return cat or "MISC"
end

local function SortEntries(a, b)
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.name ~= b.name then return a.name < b.name end
    if a.count ~= b.count then return a.count > b.count end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Search matches the item's name, its type ("trade goods", "herb", "cloth"...), a profession name
-- ("herbalism" finds herbs, "mining" ore and stone...), and whatever the game's own bag search matches.
local PROFESSION_WORDS = {
    herbalism = { "herb" }, alchemy = { "herb", "potion", "elixir", "flask" }, mining = { "metal", "stone" },
    blacksmithing = { "metal", "stone" }, engineering = { "parts", "devices", "explosives", "metal" },
    skinning = { "leather" }, leatherworking = { "leather" }, tailoring = { "cloth" }, ["first aid"] = { "cloth", "bandage" },
    enchanting = { "enchanting" }, cooking = { "meat", "cooking" }, fishing = { "fish" },
}
local function MatchesSearch(e, search)
    if search == "" then return true end
    if e.nameLower:find(search, 1, true) then return true end
    local tl = e.typeLower
    if tl and tl:find(search, 1, true) then return true end
    if tl and #search >= 3 then
        for prof, words in pairs(PROFESSION_WORDS) do
            if prof:sub(1, #search) == search then
                for _, w in ipairs(words) do if tl:find(w, 1, true) then return true end end
            end
        end
    end
    -- the game's own bag search (knows more: tooltip words, sets, item kinds)
    if C_Container and C_Container.SetItemSearch and C_Container.GetContainerItemInfo and e.bag and e.slot then
        local ok, info = pcall(C_Container.GetContainerItemInfo, e.bag, e.slot)
        if ok and type(info) == "table" and info.isFiltered == false and CysBags.engineSearch then return true end
    end
    return false
end

local function IsHighlighted(e)
    for i = 1, #highlighters do
        local fn = highlighters[i]
        local ok, result = pcall(fn, e.itemID, e.bag, e.slot, e.link)
        if ok then
            if result then return true end
        elseif not erroredHighlighters[fn] then
            erroredHighlighters[fn] = true
            geterrorhandler()(result)
        end
    end
    return false
end
--------------------------------------------------------------------------------
-- Cys's Armory integration & Dynamic Set Sub-Categories
--------------------------------------------------------------------------------
local setItemMap = {}        -- itemID -> setKey ("SET_Tank")
local dynamicSetTitles = {}  -- setKey -> Title ("Armory: Tank")

local function BuildSetLookup()
    wipe(setLookup)
    wipe(setItemMap)
    wipe(dynamicSetTitles)

    -- Blizzard's own Equipment Manager (WoW Forever has one built in; Cys's Armory is Era only there)
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        local okIDs, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
        for _, setID in ipairs(okIDs and ids or {}) do
            local okInfo, setName = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
            local okItems, items = pcall(C_EquipmentSet.GetItemIDs, setID)
            if okInfo and setName and okItems and type(items) == "table" then
                local setKey = "SET_" .. setName
                dynamicSetTitles[setKey] = "Set: " .. setName
                VALID_CATEGORY[setKey] = true
                CATEGORY_TITLE[setKey] = "Set: " .. setName
                for _, id in pairs(items) do
                    if type(id) == "number" and id > 0 then
                        setLookup[id] = true
                        setItemMap[id] = setItemMap[id] or setKey
                    end
                end
            end
        end
    end

    local db = _G.CysArmoryDB
    if type(db) ~= "table" then return end
    local charEntry = db[(GetRealmName() or "") .. " - " .. (UnitName("player") or "")]
    if type(charEntry) ~= "table" then return end

    local sets = charEntry.sets or charEntry

    for setName, set in pairs(sets) do
        if type(set) == "table" and setName ~= "specBindings" and setName ~= "_meta" then
            local setKey = "SET_" .. setName
            local setTitle = "Armory: " .. setName -- Corrected concatenation operator (..)
            
            dynamicSetTitles[setKey] = setTitle
            VALID_CATEGORY[setKey] = true
            CATEGORY_TITLE[setKey] = setTitle

            for _, saved in pairs(set) do
                local id = type(saved) == "number" and saved or tonumber(tostring(saved):match("item:(%d+)"))
                if id then
                    setLookup[id] = true
                    setItemMap[id] = setKey
                end
            end
        end
    end
end

-- Resolve category: items belonging to a set return their specific set key ("SET_Tank")
local function ResolveCategory(e)
    if e.highlight == nil then e.highlight = IsHighlighted(e) end
    local overrides = CysBagsDB and CysBagsDB.overrides
    local manual = overrides and overrides[e.itemID]
    if manual and VALID_CATEGORY[manual] then return manual end
    
    -- Check if item belongs to a specific named set
    if setItemMap[e.itemID] then 
        return setItemMap[e.itemID] 
    end
    if e.highlight or setLookup[e.itemID] then 
        return "SETS" 
    end
    
    return Categorize(e)
end

--------------------------------------------------------------------------------
-- Item buttons (one persistent button per bag/slot - nothing is ever destroyed)
--------------------------------------------------------------------------------
local function UpdateButtonCooldown(btn)
    local cd = btn.cysCooldown
    if not cd then return end
    local start, duration, enable = GetItemCooldown(btn:GetParent():GetID(), btn:GetID())
    CooldownFrame_Set(cd, start or 0, duration or 0, (enable and enable ~= 0) and 1 or 0)
end

local function CreateItemButton(bag, slot)
    local name = "CysBagsItem" .. bag .. "_" .. slot
    local btn = NewItemButton(name, holders[bag], "ContainerFrameItemButtonTemplate")
    if btn.SetBagID then btn:SetBagID(bag) end -- retail item buttons keep their own bag ID
    btn:SetID(slot)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)

    -- Strip the stock chunky art for the flat look
    local nt = btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local pt = btn:GetPushedTexture()
    if pt then pt:SetAlpha(0) end
    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetColorTexture(1, 1, 1, 0.12)
        ht:ClearAllPoints()
        ht:SetAllPoints()
    end
    for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture",
                           "BattlepayItemTexture", "JunkIcon", "UpgradeIcon", "flash" }) do
        local t = btn[key]
        -- faded rather than only hidden: Blizzard shows IconBorder again on every update (the white edge on common items)
        if t and t.SetAlpha then t:SetAlpha(0) end
        if t and t.Hide then t:Hide() end
    end

    SolidTexture(btn, "BACKGROUND", C.slot):SetAllPoints()

    local icon = btn.icon or _G[name .. "IconTexture"]
    if not icon then icon = btn:CreateTexture(nil, "ARTWORK") end
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.cysIcon = icon

    local count = btn.Count or _G[name .. "Count"]
    if not count then
        count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -3, 2)
    end
    btn.cysCount = count

    local cd = btn.Cooldown or _G[name .. "Cooldown"]
    if not cd then
        cd = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
    end
    btn.cysCooldown = cd

    -- 1px quality / quest border (set pieces keep their rarity color; they're grouped in Armory Sets)
    btn.cysQuality = CreateBorder(btn, 1, C.text, "OVERLAY", 5)
    ShowBorder(btn.cysQuality, false)

    if CysBags.buttonsProtected == nil then
        CysBags.buttonsProtected = btn:IsProtected() and true or false
    end
    return btn
end

local function GetItemButton(bag, slot)
    local btn = buttons[bag][slot]
    if not btn then
        btn = CreateItemButton(bag, slot)
        buttons[bag][slot] = btn
    end
    return btn
end

local function UpdateButton(btn, e)
    btn.cysEntry = e
    btn.cysIcon:SetTexture(e.icon)
    btn.cysIcon:SetDesaturated(e.locked and true or false)

    local countFS = btn.cysCount
    if e.count and e.count > 1 then
        countFS:SetText(e.count)
        countFS:Show()
    else
        countFS:SetText("")
        countFS:Hide()
    end

    local qc = e.quality and e.quality >= 2 and ITEM_QUALITY_COLORS[e.quality]
    if e.isQuest then
        SetBorderColor(btn.cysQuality, C.quest[1], C.quest[2], C.quest[3])
        ShowBorder(btn.cysQuality, true)
    elseif qc then
        SetBorderColor(btn.cysQuality, qc.r, qc.g, qc.b)
        ShowBorder(btn.cysQuality, true)
    else
        ShowBorder(btn.cysQuality, false)
    end

    btn:SetAlpha(MatchesSearch(e, CysBags.search) and 1 or 0.25)
    UpdateButtonCooldown(btn)
end

-- An empty slot in the All Slots view: the plain dark square, still a working drop target
local function UpdateEmptyButton(btn)
    btn.cysEntry = nil
    btn.cysIcon:SetTexture(nil)
    btn.cysIcon:SetDesaturated(false)
    btn.cysCount:SetText("")
    btn.cysCount:Hide()
    ShowBorder(btn.cysQuality, false)
    btn:SetAlpha((CysBags.search or "") == "" and 1 or 0.25)
    UpdateButtonCooldown(btn)
end

local function GetSectionHeader(key)
    local h = sectionHeaders[key]
    if h then return h end
    h = CreateFrame("Frame", nil, content)
    h:SetSize(CONTENT_W, SECTION_H)
    h.label = CreateText(h, 11, C.text)
    h.label:SetPoint("LEFT", 0, 0)
    h.line = SolidTexture(h, "ARTWORK", C.line)
    h.line:SetHeight(1)
    h.line:SetPoint("LEFT", h.label, "RIGHT", 8, 0)
    h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    sectionHeaders[key] = h
    return h
end

--------------------------------------------------------------------------------
-- Collect / Layout / Refresh
--------------------------------------------------------------------------------
function CysBags:Collect()
    for _, list in pairs(lists) do wipe(list) end
    for _, t in pairs(slotEntries) do wipe(t) end
    wipe(counts)
    BuildSetLookup()

    -- Ensure a list container exists for every dynamic set category
    for setKey in pairs(dynamicSetTitles) do
        if not lists[setKey] then lists[setKey] = {} end
    end

    -- Drop the isolate-one-bag filter if that bag was unequipped
    local bagFilter = self.bagFilter
    if bagFilter and (GetNumSlots(bagFilter) or 0) == 0 then
        bagFilter = nil
        self.bagFilter = nil
    end

    local n, used, total = 0, 0, 0
    for bag = FIRST_BAG, LAST_BAG do
        local slots = GetNumSlots(bag) or 0
        local counted = bag <= LAST_NORMAL_BAG
        if counted then total = total + slots end
        for slot = 1, slots do
            local icon, count, locked, quality, link, itemID = GetSlotItem(bag, slot)
            if link then
                if counted then used = used + 1 end
                itemID = itemID or tonumber(link:match("item:(%d+)"))
                if itemID and (not bagFilter or bagFilter == bag) then
                    n = n + 1
                    local e = entryPool[n]
                    if not e then e = {}; entryPool[n] = e end
                    e.bag, e.slot, e.link, e.itemID = bag, slot, link, itemID
                    e.icon, e.count, e.locked = icon, count or 1, locked
                    e.quality = quality or select(3, GetItemInfo(link)) or 1
                    e.name, e.nameLower = GetItemName(link)
                    local _, itype, isub = GetItemInfoInstant(itemID)
                    e.typeLower = lower((itype or "") .. " " .. (isub or ""))
                    e.isQuest = IsQuestSlot(bag, slot)
                    slotEntries[bag] = slotEntries[bag] or {}
                    slotEntries[bag][slot] = e
                    e.highlight = nil -- recomputed by ResolveCategory
                    e.isBoE = IsBoE(bag, slot)
                    
                    local category = ResolveCategory(e)
                    if not lists[category] then lists[category] = {} end
                    lists[category][#lists[category] + 1] = e
                end
            end
        end
    end

    -- Sort standard sections
    for _, s in ipairs(SECTIONS) do
        sort(lists[s.key], SortEntries)
        counts[s.key] = #lists[s.key]
    end

    -- Sort and accumulate dynamic set sub-categories
    local totalSetItems = 0
    for setKey in pairs(dynamicSetTitles) do
        if lists[setKey] then
            sort(lists[setKey], SortEntries)
            counts[setKey] = #lists[setKey]
            totalSetItems = totalSetItems + counts[setKey]

            -- Populate master SETS list for the combined All Items view
            for i = 1, #lists[setKey] do
                local item = lists[setKey][i]
                local exists = false
                for j = 1, #lists["SETS"] do
                    if lists["SETS"][j] == item then exists = true; break end
                end
                if not exists then
                    tinsert(lists["SETS"], item)
                end
            end
        end
    end
    sort(lists["SETS"], SortEntries)
    counts.SETS = #lists["SETS"]

    counts.ALL = n
    counts.SLOTS = bagFilter and (GetNumSlots(bagFilter) or 0) or total
    self.used, self.total, self.free = used, total, total - used

    -- First open after login: if the remembered category is empty now, start on All Items instead
    if self.restoredFilter then
        self.restoredFilter = nil
        local f = self.filter
        if f ~= "ALL" and f ~= "SLOTS" and (counts[f] or 0) == 0 then self.filter = "ALL" end
    end
end

function CysBags:Layout()
    for bag = FIRST_BAG, LAST_BAG do
        for _, btn in pairs(buttons[bag]) do btn:Hide() end
    end
    for _, h in pairs(sectionHeaders) do h:Hide() end
    wipe(activeButtons)
    for _, f in ipairs(self.fillers or {}) do f:Hide() end
    local usedFillers = 0
    -- empty dark slots that finish a section's last row, so every section is a neat block (look only)
    local function Filler(x, yy)
        usedFillers = usedFillers + 1
        self.fillers = self.fillers or {}
        local f = self.fillers[usedFillers]
        if not f then
            f = CreateFrame("Frame", nil, content)
            f:SetSize(SLOT_SIZE, SLOT_SIZE)
            SolidTexture(f, "BACKGROUND", { C.slot[1], C.slot[2], C.slot[3], 0.45 }):SetAllPoints()
            CreateBorder(f, 1, C.line, "BORDER")
            self.fillers[usedFillers] = f
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", x, -yy)
        f:Show()
    end

    local filter, y, any = self.filter, 0, false

    -- Helper function to render an item section
    local function RenderSection(key, title)
        local list = lists[key]
        if not list then return end
        local n = #list
        if n > 0 then
            any = true
            local h = GetSectionHeader(key)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            h.label:SetText(format("%s |cff777777(%d)|r", title, n))
            h:Show()
            y = y + SECTION_H + 6

            for i = 1, n do
                local e = list[i]
                local btn = GetItemButton(e.bag, e.slot)
                local col = (i - 1) % COLS
                local row = floor((i - 1) / COLS)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", content, "TOPLEFT", col * STEP, -(y + row * STEP))
                UpdateButton(btn, e)
                btn:Show()
                activeButtons[#activeButtons + 1] = btn
            end
            for i = n + 1, ceil(n / COLS) * COLS do
                Filler(((i - 1) % COLS) * STEP, y + floor((i - 1) / COLS) * STEP)
            end
            y = y + ceil(n / COLS) * STEP - SLOT_GAP + SECTION_GAP
        end
    end

    -- All Slots: every real slot in bag order, empty ones included
    if filter == "SLOTS" then
        local i = 0
        for bag = FIRST_BAG, LAST_BAG do
            if not self.bagFilter or self.bagFilter == bag then
                local entries = slotEntries[bag]
                for slot = 1, (GetNumSlots(bag) or 0) do
                    i = i + 1
                    local btn = GetItemButton(bag, slot)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", content, "TOPLEFT", ((i - 1) % COLS) * STEP, -(floor((i - 1) / COLS) * STEP))
                    local e = entries and entries[slot]
                    if e then UpdateButton(btn, e) else UpdateEmptyButton(btn) end
                    btn:Show()
                    activeButtons[#activeButtons + 1] = btn
                end
            end
        end
        any = i > 0
        y = ceil(i / COLS) * STEP - SLOT_GAP + SECTION_GAP
    end

    -- 1. When viewing "ALL", show a single consolidated "Armory Sets" category
    if filter == "ALL" then
        RenderSection("SETS", CATEGORY_TITLE["SETS"] or "Armory Sets")
    end

    -- 2. When specifically clicking the "SETS" sidebar tab, split them into individual set sub-headers
    if filter == "SETS" then
        local sortedSets = {}
        for setKey, setTitle in pairs(dynamicSetTitles) do
            tinsert(sortedSets, { key = setKey, title = setTitle })
        end
        sort(sortedSets, function(a, b) return a.title < b.title end)

        for _, setInfo in ipairs(sortedSets) do
            RenderSection(setInfo.key, setInfo.title)
        end

        -- Fallback if no named sets exist
        if #sortedSets == 0 then
            RenderSection("SETS", CATEGORY_TITLE["SETS"] or "Armory Sets")
        end
    end

    -- 2b. One Armory set picked in the sidebar (its row under Armory Sets)
    if filter:find("^SET_") then
        RenderSection(filter, dynamicSetTitles[filter] or filter)
    end

    -- 3. Render standard non-set categories
    for _, sec in ipairs(SECTIONS) do
        if sec.key ~= "SETS" and (filter == "ALL" or filter == sec.key) then
            RenderSection(sec.key, sec.title)
        end
    end

    local contentH = max(y - SECTION_GAP, 1)
    content:SetHeight(contentH)
    self.emptyText:SetShown(not any)
    -- Auto-size (switch: /cui > Automation): the window grows or shrinks to fit the items, so nothing scrolls,
    -- up to 85% of the screen height. Otherwise it keeps its own height and the content scrolls.
    self:FitHeight(contentH)
end

local function AutoSize()
    local auto = CysUIDB and CysUIDB.automation
    return not (auto and auto.bagsAutoSize == false)
end

-- Set the window height for the content; the top edge stays where it is (the window grows downwards)
function CysBags:FitHeight(contentH)
    if not (frame and AutoSize()) or self.fitting then return end
    local want = HEADER_H + FOOTER_H + PAD * 2 + 2 + contentH + 6 -- a few pixels spare so the list never scrolls
    local minH = max(HEADER_H + FOOTER_H + (self.sidebarH or 320), 200) -- the sidebar's rows must still fit
    local maxH = floor((UIParent:GetHeight() or 900) * 0.85)
    want = floor(max(minH, min(want, maxH)) + 0.5)
    if math.abs((frame:GetHeight() or 0) - want) < 1 then return end
    self.fitting = true
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local top = frame:GetTop()
    local cx = frame:GetCenter()
    frame:SetHeight(want)
    local m = CysUI and CysUI.movers and CysUI.movers.bags
    if m and top and cx and CysUI.ApplyLayout then
        -- with Cys's UI the window hangs off its layout spot by its centre: move that spot so the top stays put
        CysUIDB.layout = CysUIDB.layout or {}
        local e = CysUIDB.layout.bags or {}
        CysUIDB.layout.bags = e
        local ux, uy = UIParent:GetCenter()
        e.point = "CENTER"
        e.x = floor(cx * s - ux + 0.5)
        e.y = floor(top * s - want * s / 2 - uy + 0.5)
        e.width = e.width or floor(frame:GetWidth() + 0.5)
        e.height = want
        CysUI:ApplyLayout("bags")
    elseif top then
        local left = frame:GetLeft()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    self.fitting = false
end

-- Layout mode resizes the window: its width decides how many item columns fit (the height just
-- gives the list more or less room), so the content is re-flowed whenever the column count changes.
function CysBags:ApplySize(w)
    local cols = floor((w - SideW() - PAD * 2 - 2 + SLOT_GAP) / STEP)
    cols = max(MIN_COLS, min(cols, MAX_COLS))
    if cols == COLS then return end
    COLS = cols
    CONTENT_W = COLS * STEP - SLOT_GAP
    if content then
        content:SetWidth(CONTENT_W)
        if self.emptyText then self.emptyText:SetWidth(CONTENT_W) end
        for _, h in pairs(sectionHeaders) do h:SetWidth(CONTENT_W) end
        self.dirty = true
        if frame and frame:IsShown() then self:Refresh() end
    end
end

-- Sub-category rows: one per Armory set, indented under Armory Sets
local setButtons = {}
local function SetChildButton(key)
    local b = setButtons[key]
    if b then return b end
    b = CreateFrame("Button", nil, sidebar)
    b.key = key
    b:SetHeight(22)
    b.bg = SolidTexture(b, "BACKGROUND", C.hover)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.accent = SolidTexture(b, "ARTWORK", C.accent)
    b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(2)
    b.accent:Hide()
    b.label = CreateText(b, 10, C.text)
    b.label:SetPoint("LEFT", 40, 0)
    b.count = CreateText(b, 10, C.dim, "RIGHT")
    b.count:SetPoint("RIGHT", -10, 0)
    b:SetScript("OnEnter", function(s) s.hover = true; CysBags:UpdateSidebar() end)
    b:SetScript("OnLeave", function(s) s.hover = false; CysBags:UpdateSidebar() end)
    b:SetScript("OnClick", function(s) if not CursorHasItem() then CysBags:SetFilter(s.key) end end)
    setButtons[key] = b
    return b
end

-- collapse / expand the sidebar (icons only <-> icons and names); the items get the room
function CysBags:SetSidebarSlim(on)
    if CysBagsDB then CysBagsDB.sidebarSlim = on and true or nil end
    if not sidebar then return end
    sidebar:SetWidth(SideW())
    if self.slimBtn then self.slimBtn.text:SetText(on and ">" or "<") end
    COLS = nil -- re-flow the columns for the new width
    if frame then self:ApplySize(frame:GetWidth()) end
    self:UpdateSidebar()
end

function CysBags:UpdateSidebar()
    local dropping = CursorHasItem() and true or false
    -- empty categories leave the sidebar (switch: /cui > Automation); they come back while an item is on the cursor
    local auto = CysUIDB and CysUIDB.automation
    local hideEmpty = not (auto and auto.hideEmptyBagCats == false) and not dropping
    -- the Armory sets in your bags, by name (their rows go under Armory Sets)
    local slim = Slim()
    local sets = {}
    for key, title in pairs(slim and {} or dynamicSetTitles) do
        if (counts[key] or 0) > 0 then sets[#sets + 1] = { key = key, title = (title:gsub("^Set: ", "")) } end
    end
    table.sort(sets, function(a, b) return a.title < b.title end)
    for _, cb in pairs(setButtons) do cb:Hide() end
    local y = 8
    for _, sb in ipairs(sidebarButtons) do
        local cnt = counts[sb.key] or 0
        local keep = sb.key == "ALL" or sb.key == "SLOTS" or sb.key == self.filter or cnt > 0
            or (sb.key == "SETS" and self.filter and self.filter:find("^SET_"))
        if hideEmpty and not keep then
            sb:Hide()
        else
            sb:Show()
            sb:ClearAllPoints()
            sb:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -y)
            sb:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -y)
            y = y + 27
            if sb.key == "SETS" then
                for _, s in ipairs(sets) do
                    local cb = SetChildButton(s.key)
                    cb:ClearAllPoints()
                    cb:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -y)
                    cb:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -y)
                    cb.label:SetText(s.title)
                    cb.count:SetText(counts[s.key] or 0)
                    local sel = self.filter == s.key
                    cb.accent:SetShown(sel)
                    if sel then cb.bg:SetColorTexture(unpack(C.selected)); cb.bg:Show()
                    elseif cb.hover then cb.bg:SetColorTexture(unpack(C.hover)); cb.bg:Show()
                    else cb.bg:Hide() end
                    if sel then cb.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                    else cb.label:SetTextColor(0.75, 0.75, 0.75) end
                    cb:Show()
                    y = y + 23
                end
            end
        end
    end
    self.sidebarH = y + 34 -- the rows plus room for the collapse button (used by auto-size)
    for _, sb in ipairs(sidebarButtons) do
        -- Check if this sidebar button is selected OR if it's the Armory Sets tab and a dynamic set is filtered
        local selected = (sb.key == self.filter) or (sb.key == "SETS" and self.filter and self.filter:find("^SET_"))
        
        local n = counts[sb.key] or 0
        sb.accent:SetShown(selected)
        if selected then
            sb.bg:SetColorTexture(unpack(C.selected)); sb.bg:Show()
        elseif sb.hover then
            sb.bg:SetColorTexture(unpack(C.hover)); sb.bg:Show()
        else
            sb.bg:Hide()
        end
        if sb.icon then sb.icon:SetDesaturated(n == 0 and not selected); sb.icon:SetAlpha((selected or n > 0) and 1 or 0.5) end
        sb.label:SetShown(not slim); sb.count:SetShown(not slim)
        if selected then
            sb.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) -- gold: active category
        elseif n == 0 then
            sb.label:SetTextColor(0.35, 0.35, 0.35)                      -- dim: empty category
        else
            sb.label:SetTextColor(0.9, 0.9, 0.9)                         -- white: category with items
        end
        sb.count:SetText(n)
    end
end

function CysBags:UpdateHeader()
    -- quiet title: light word, dim count (the gold stays on the Cys's Bags name)
    header.title:SetFormattedText("|cFFE0E0E0Inventory|r   |cFF8C8C8C%d / %d|r", self.used, self.total)
end

function CysBags:UpdateBagSlots()
    for i = 1, 4 do
        local btn = footer.bagSlots[i]
        local invID = btn:GetID()
        local tex = GetInventoryItemTexture("player", invID)
        -- Safety net: a bag with slots is definitely equipped even if the texture lookup failed
        if not tex and (GetNumSlots(btn.bagID) or 0) > 0 then tex = FALLBACK_BAG_TEXTURE end
        if tex then
            btn.cysIcon:SetTexture(tex)
            btn.cysIcon:SetAlpha(1)
        else
            btn.cysIcon:SetTexture(btn.emptyTexture)
            btn.cysIcon:SetAlpha(0.45)
        end
        btn.cysIcon:SetDesaturated(IsInventoryItemLocked(invID) and true or false)
        local active = (self.bagFilter == btn.bagID)
        ShowBorder(btn.cysActive, active)
        btn.cysActiveFill:SetShown(active)
    end
end

function CysBags:UpdateFooter()
    footer.free:SetText("|cFFFFD100Free slots:|r |cFFFFFFFF" .. (self.free or 0) .. "|r")
    footer.gold:SetText(GetCoinTextureString(GetMoney()))
    self:UpdateBagSlots()
end

function CysBags:UpdateCooldowns()
    if not (frame and frame:IsShown()) then return end
    for i = 1, #activeButtons do UpdateButtonCooldown(activeButtons[i]) end
end

function CysBags:ApplySearch()
    local s = self.search
    for i = 1, #activeButtons do
        local btn = activeButtons[i]
        local e = btn.cysEntry
        if e then
            btn:SetAlpha(MatchesSearch(e, s) and 1 or 0.25)
        else
            btn:SetAlpha(s == "" and 1 or 0.25) -- empty slot
        end
    end
end

function CysBags:Refresh()
    if not frame then return end
    -- If the item buttons are protected, we can't move them in combat; stay dirty and retry after.
    if InCombatLockdown() and self.buttonsProtected then return end
    self.dirty = false
    self:Collect()
    self:Layout()
    self:UpdateSidebar()
    self:UpdateHeader()
    self:UpdateFooter()
    -- Trigger CysUpgrade overlay check
    if _G.UpdateCysBagsUpgradeOverlays then pcall(_G.UpdateCysBagsUpgradeOverlays) end
end

function CysBags:SetFilter(key)
    self.filter = key
    if CysBagsDB then CysBagsDB.filter = key end -- reopen on the same tab next time
    scroll:SetVerticalScroll(0)
    self.dirty = true
    if frame:IsShown() then self:Refresh() end
end

function CysBags:SetSearch(text)
    self.search = lower(strtrim(text or ""))
    -- also ask the game's bag search; its answer arrives with INVENTORY_SEARCH_UPDATE
    if C_Container and C_Container.SetItemSearch then
        self.engineSearch = false -- trusted again once the game says its results are ready
        pcall(C_Container.SetItemSearch, self.search)
    end
    self:ApplySearch()
end

-- Footer bag slots: click to show only that bag's items, click again to show everything.
function CysBags:ToggleBagFilter(bagID)
    if self.bagFilter == bagID then
        self.bagFilter = nil
    elseif (GetNumSlots(bagID) or 0) > 0 then
        self.bagFilter = bagID
    else
        return -- no bag equipped in that slot
    end
    scroll:SetVerticalScroll(0)
    self.dirty = true
    if frame:IsShown() then self:Refresh() end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
-- Drop the item on your cursor onto a sidebar category to move it there for good.
-- Dropping on "All Items" puts it back to automatic sorting.
function CysBags:AssignCursorItem(key)
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" or not itemID then return false end
    if key ~= "ALL" and not VALID_CATEGORY[key] then return false end
    CysBagsDB.overrides = CysBagsDB.overrides or {}
    local shown = link or ("item " .. itemID)
    if key == "ALL" then
        CysBagsDB.overrides[itemID] = nil
        print("|cFFFFD100Cys's Bags|r: " .. shown .. " is sorted automatically again.")
    else
        CysBagsDB.overrides[itemID] = key
        print("|cFFFFD100Cys's Bags|r: " .. shown .. " moved to |cFFFFD100" .. CATEGORY_TITLE[key] .. "|r.")
    end
    ClearCursor() -- the item was only picked up, so this puts it back where it was
    self.dirty = true
    if CysBank then CysBank.dirty = true end
    return true
end

function CysBags:RegisterSetHighlighter(func)
    if type(func) ~= "function" then
        error("CysBags:RegisterSetHighlighter(func): func must be a function", 2)
    end
    for i = 1, #highlighters do
        if highlighters[i] == func then return end
    end
    highlighters[#highlighters + 1] = func
    self:RefreshHighlights()
end

function CysBags:UnregisterSetHighlighter(func)
    for i = #highlighters, 1, -1 do
        if highlighters[i] == func then
            table.remove(highlighters, i)
            erroredHighlighters[func] = nil
        end
    end
    self:RefreshHighlights()
end

function CysBags:RefreshHighlights()
    self.dirty = true -- picked up by the OnUpdate coalescer while the bags are open
end

function CysBags:IsShown() return frame and frame:IsShown() or false end
function CysBags:Open()
    if frame and not frame:IsShown() then frame:Show() end
end
function CysBags:Close()
    if frame and frame:IsShown() then frame:Hide() end
end
function CysBags:Toggle()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

--------------------------------------------------------------------------------
-- Sorting
--------------------------------------------------------------------------------
-- Classic Era has no C_Container.SortBags, so we move the items ourselves: one
-- pick-up/drop per tick, waiting for the server to unlock the slots in between.
-- Only normal bags are touched (backpack + bags of family 0). Ammo / profession
-- bags and the keyring are left alone, so a move can never be rejected by a bag
-- that doesn't accept the item.
local CATEGORY_RANK = {}
for i, s in ipairs(SECTIONS) do CATEGORY_RANK[s.key] = i end

local sorter = CreateFrame("Frame")
sorter:Hide()
sorter.running = false

local function GetBagFamily(bag)
    if bag == 0 then return 0 end
    local _, family = GetNumFreeSlots(bag)
    return family or 0
end

local function SameStack(a, b)
    if not a or not b then return a == b end
    return a.itemID == b.itemID and a.count == b.count and a.name == b.name
end

local function SortBefore(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.name ~= b.name then return a.name < b.name end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    return a.count > b.count
end

local function StopSort(message)
    sorter.running = false
    sorter.returnTo = nil
    sorter:Hide()
    if CysBags.sortBtn then CysBags.sortBtn.icon:SetVertexColor(0.8, 0.8, 0.8) end
    CysBags.dirty = true
    if message then print("|cFFFFD100Cys's Bags|r: " .. message) end
end

-- pos[i] = {bag, slot}; cur[i] = item snapshot or nil (empty); n = number of sortable slots
local function SnapshotSortSlots()
    local pos, cur, n, anyLocked = {}, {}, 0, false
    for bag = FIRST_BAG, LAST_NORMAL_BAG do
        if GetBagFamily(bag) == 0 then
            for slot = 1, (GetNumSlots(bag) or 0) do
                n = n + 1
                pos[n] = { bag, slot }
                local _, count, locked, quality, link, itemID = GetSlotItem(bag, slot)
                if locked then anyLocked = true end
                if link then
                    local e = {
                        bag = bag, slot = slot, link = link,
                        itemID = itemID or tonumber(link:match("item:(%d+)")),
                        count = count or 1, quality = quality or 1,
                        isQuest = IsQuestSlot(bag, slot),
                    }
                    e.name = GetItemName(link)
                    e.rank = CATEGORY_RANK[ResolveCategory(e)] or 99
                    cur[n] = e
                end
            end
        end
    end
    return pos, cur, n, anyLocked
end

-- Gives up if the exact same move keeps failing (e.g. an item that refuses to move).
local function Attempt(signature)
    if signature == sorter.lastSig then
        sorter.same = sorter.same + 1
    else
        sorter.lastSig, sorter.same = signature, 0
    end
    if sorter.same >= 5 then
        StopSort("Sort stopped: an item couldn't be moved.")
        return false
    end
    return true
end

local function SortStep()
    if CursorHasItem() then
        -- finish our own swap: put the displaced stack into the slot we picked from
        local r = sorter.returnTo
        if r then
            sorter.returnTo = nil
            PickupItem(r[1], r[2])
        end
        return -- otherwise the cursor is the player's: wait
    end
    sorter.returnTo = nil

    local pos, cur, n, anyLocked = SnapshotSortSlots()
    if anyLocked then return end -- the previous move is still settling
    if sorter.moves >= 500 then
        StopSort("Sort stopped (too many moves).")
        return
    end

    -- 1) merge partial stacks of the same item
    local firstPartial = {}
    for i = 1, n do
        local e = cur[i]
        if e then
            local maxStack = select(8, GetItemInfo(e.link))
            if maxStack and maxStack > 1 and e.count < maxStack then
                local first = firstPartial[e.itemID]
                if first then
                    if Attempt("m" .. i .. ":" .. first) then
                        local src, dst = pos[i], pos[first]
                        PickupItem(src[1], src[2])
                        PickupItem(dst[1], dst[2])
                        sorter.returnTo = src -- any overflow goes back where it came from
                        sorter.moves = sorter.moves + 1
                    end
                    return
                end
                firstPartial[e.itemID] = i
            end
        end
    end

    -- 2) put the first out-of-place slot right, one swap per tick
    local items, m = {}, 0
    for i = 1, n do
        if cur[i] then
            m = m + 1
            items[m] = cur[i]
        end
    end
    sort(items, SortBefore)

    for i = 1, m do
        local want = items[i]
        if not SameStack(cur[i], want) then
            local from
            for j = i + 1, n do
                local c = cur[j]
                if c and SameStack(c, want) and not SameStack(c, items[j]) then
                    from = j
                    break
                end
            end
            if not from then
                StopSort("Sort stopped: couldn't find an item to move.")
            elseif Attempt("s" .. i .. ":" .. from) then
                local src, dst = pos[from], pos[i]
                PickupItem(src[1], src[2])
                PickupItem(dst[1], dst[2])
                sorter.returnTo = src -- whatever was in the destination is now on the cursor
                sorter.moves = sorter.moves + 1
            end
            return
        end
    end

    StopSort("Bags sorted.")
end

sorter:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.12 then return end
    self.elapsed = 0
    if InCombatLockdown() then
        StopSort("Sort stopped: you entered combat.")
        return
    end
    SortStep()
end)

-- Sort button / "/cysbags sort": start the sorter, or stop it if it is already running
function CysBags:ToggleSort()
    if sorter.running then
        StopSort("Sort cancelled.")
        return
    end
    if InCombatLockdown() then
        print("|cFFFFD100Cys's Bags|r: can't sort in combat.")
        return
    end
    if CursorHasItem() then
        print("|cFFFFD100Cys's Bags|r: put down the item on your cursor first.")
        return
    end
    sorter.running = true
    sorter.moves, sorter.same, sorter.lastSig, sorter.returnTo, sorter.elapsed = 0, 0, nil, nil, 0
    if CysBags.sortBtn then CysBags.sortBtn.icon:SetVertexColor(1, 0.35, 0.35) end -- red while sorting: click again to stop
    sorter:Show()
end

--------------------------------------------------------------------------------
-- Guide window (gear button in the header)
--------------------------------------------------------------------------------
local GOLD = "|cFFFFD100"
local GUIDE_LINES = {
    GOLD .. "Overview|r",
    "All your bags in one window, split into sections with a filter sidebar. Inside each section items are ordered by quality, then name.",
    "",
    GOLD .. "Armory Sets|r",
    "Items saved in Cys's Armory sets (or in Blizzard's Equipment Manager on WoW Forever) are grouped into the Armory Sets section at the top.",
    "",
    GOLD .. "Moving items between categories|r",
    "Pick an item up and drop it on a category in the sidebar to move it there for good. Drop it on All Items to go back to automatic sorting.",
    "",
    GOLD .. "Bag bar|r (bottom left)",
    "Click a bag to show only that bag; click it again to show everything. Drop a bag onto a slot to equip it (the old bag lands on your cursor), or drag an equipped bag off its slot to pick it up.",
    "",
    GOLD .. "Search and Sort|r",
    "Search dims every item that doesn't match. Sort merges partial stacks and orders items by category. Ammo and profession bags are skipped. Click Sort again to stop it.",
    "",
    GOLD .. "Bank|r",
    "At a banker, Cys's Bank opens with the same sections, search and bag bar for your whole bank.",
    "",
    GOLD .. "Commands|r",
    "/cysbags or /cbags - toggle the bags",
    "/cysbags sort - sort your bags",
    "/cysbags resetcats - clear every manual category move",
    "/cysbags changelog - show what's new",
    "/cysbags reset - reset the window position",
    "",
    GOLD .. "Tips|r",
    "Drag the header to move the window. Esc closes it.",
}

function CysBags:CreateGuide()
    local g = CreateFrame("Frame", "CysBagsGuideFrame", UIParent)
    g:SetSize(420, 400)
    g:SetPoint("CENTER")
    g:SetFrameStrata("DIALOG")
    g:SetToplevel(true)
    g:SetClampedToScreen(true)
    g:SetMovable(true)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnDragStart", g.StartMoving)
    g:SetScript("OnDragStop", g.StopMovingOrSizing)
    g:Hide()
    SolidTexture(g, "BACKGROUND", C.bg):SetAllPoints()
    CreateBorder(g, 1, C.border, "BORDER")

    local title = CreateText(g, 14, C.accent, "CENTER")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Cys's Bags Guide")

    local close = CreateFrame("Button", nil, g)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.text = CreateText(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() g:Hide() end)

    local body = CreateText(g, 11, C.text)
    body:SetPoint("TOPLEFT", 20, -46)
    body:SetWidth(380)
    body:SetJustifyV("TOP")
    body:SetSpacing(3)
    body:SetText(table.concat(GUIDE_LINES, "\n"))
    g:SetHeight(46 + body:GetStringHeight() + 26) -- fit the text instead of clipping it

    tinsert(UISpecialFrames, "CysBagsGuideFrame")
    self.guide = g
end

function CysBags:ToggleGuide()
    if not self.guide then self:CreateGuide() end
    if self.guide:IsShown() then self.guide:Hide() else self.guide:Show() end
end

--------------------------------------------------------------------------------
-- Position persistence
--------------------------------------------------------------------------------
function CysBags:RestorePosition()
    local p = CysBagsDB and CysBagsDB.pos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 120)
    end
end

function CysBags:SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then CysBagsDB.pos = { point, relPoint, x, y } end
end

--------------------------------------------------------------------------------
-- Footer bag bar: equipped bag slots 1-4 (container IDs 1-4 = inventory slots 20-23)
--------------------------------------------------------------------------------
local BAGSLOT_SIZE, BAGSLOT_GAP = 22, 4
local EMPTY_BAG_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

-- Inventory slot that holds equipped bag `bagID` (1-4). This differs between client
-- generations (20-23 on old clients, 31-34 on current Classic), so ask the client.
local function GetBagInventorySlot(bagID)
    local id
    if C_Container and C_Container.ContainerIDToInventoryID then
        id = C_Container.ContainerIDToInventoryID(bagID)
    elseif ContainerIDToInventoryID then
        id = ContainerIDToInventoryID(bagID)
    end
    if not id then
        id = (GetInventorySlotInfo("Bag" .. (bagID - 1) .. "Slot"))
    end
    return id or (30 + bagID)
end

local function CreateBagSlotButton(i)
    local invID = GetBagInventorySlot(i)
    local name = "CysBagsBagSlot" .. i
    local btn = NewItemButton(name, footer, "ItemButtonTemplate")
    btn:SetSize(BAGSLOT_SIZE, BAGSLOT_SIZE)
    btn:SetID(invID)
    btn.bagID = i

    -- Empty-slot art as Blizzard defines it for "Bag0Slot".."Bag3Slot"
    local _, emptyTex = GetInventorySlotInfo("Bag" .. (i - 1) .. "Slot")
    btn.emptyTexture = emptyTex or EMPTY_BAG_TEXTURE

    -- The template's stock art is sized for a 37px button; at 22px it overflows
    -- and overlaps its neighbours, so strip it and draw our own flat slot.
    local nt = btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local pt = btn:GetPushedTexture()
    if pt then pt:SetAlpha(0) end
    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetColorTexture(1, 1, 1, 0.15)
        ht:ClearAllPoints()
        ht:SetAllPoints()
    end
    for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "Count", "Stock" }) do
        local t = btn[key] or _G[name .. key]
        if t and t.Hide then t:Hide() end
    end

    SolidTexture(btn, "BACKGROUND", C.slot):SetAllPoints()
    local icon = btn.icon or _G[name .. "IconTexture"]
    if not icon then icon = btn:CreateTexture(nil, "ARTWORK") end
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.cysIcon = icon

    CreateBorder(btn, 1, C.border, "BORDER") -- gold, matches the frame
    btn.cysActive = CreateBorder(btn, 2, C.accent, "OVERLAY", 7) -- shown while this bag is isolated
    ShowBorder(btn.cysActive, false)
    btn.cysActiveFill = SolidTexture(btn, "OVERLAY", { C.accent[1], C.accent[2], C.accent[3], 0.22 }, 3)
    btn.cysActiveFill:SetAllPoints()
    btn.cysActiveFill:Hide()

    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not GameTooltip:SetInventoryItem("player", self:GetID()) then
            GameTooltip:SetText(EQUIP_CONTAINER or "Equip Container", 1, 1, 1)
        end
        GameTooltip:AddLine("Click: show only this bag", C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self)
        if CursorHasItem() then
            PutItemInBag(self:GetID()) -- drop a bag here; the old bag swaps onto the cursor
        else
            CysBags:ToggleBagFilter(self.bagID)
        end
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if CursorHasItem() then PutItemInBag(self:GetID()) end
    end)
    btn:SetScript("OnDragStart", function(self)
        PickupBagFromSlot(self:GetID())
    end)

    return btn
end

--------------------------------------------------
-- Delete Cheapest Junk Helper Function
--------------------------------------------------
-- the grey item (or stack) worth the least at a vendor: bag, slot, link, total value in copper, stack count
local function FindCheapestJunk()
    local cheapestBag, cheapestSlot, cheapestLink, cheapestCount
    local lowestValue = math.huge

    if not C_Container then return end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local _, _, quality, _, _, _, _, _, _, _, itemSellPrice = GetItemInfo(info.hyperlink)
                
                -- Verify item is strictly Poor (grey = 0) and NOT a quest item
                local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                if quality == 0 and not (questInfo and questInfo.isQuestItem) then
                    local totalValue = (itemSellPrice or 0) * (info.stackCount or 1)
                    if totalValue < lowestValue then
                        lowestValue = totalValue
                        cheapestBag = bag
                        cheapestSlot = slot
                        cheapestLink = info.hyperlink
                        cheapestCount = info.stackCount or 1
                    end
                end
            end
        end
    end
    if cheapestBag then return cheapestBag, cheapestSlot, cheapestLink, lowestValue, cheapestCount end
end

local function CoinText(copper)
    copper = copper or 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function DeleteCheapestJunk()
    if InCombatLockdown() then
        print("|cFFFFD100Cys's Bags|r: Cannot delete items in combat!")
        return
    end
    local cheapestBag, cheapestSlot, cheapestLink, value, count = FindCheapestJunk()

    if cheapestBag and cheapestSlot then
        ClearCursor()
        C_Container.PickupContainerItem(cheapestBag, cheapestSlot)
        if CursorHasItem() then
            DeleteCursorItem()
            print(string.format("|cFFFFD100Cys's Bags|r: Destroyed cheapest junk %s%s (%s)", cheapestLink or "item",
                (count or 1) > 1 and (" x" .. count) or "", value and value > 0 and CoinText(value) or "no vendor value"))
            CysBags.dirty = true
            if CysBags.Refresh then CysBags:Refresh() end
        end
    else
        print("|cFFFFD100Cys's Bags|r: No grey junk items found to destroy.")
    end
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------
function CysBags:CreateFrames()
    if frame then return end

    frame = CreateFrame("Frame", "CysBagsFrame", UIParent)
    self.frame = frame
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    SolidTexture(frame, "BACKGROUND", C.bg):SetAllPoints()
    CreateBorder(frame, 1, C.border, "BORDER")
    self:RestorePosition()
    -- With Cys's UI, position and scale come from layout mode (/cui layout)
    if CysUI and CysUI.RegisterMovable then
        CysUI:RegisterMovable(frame, "bags", "Cys's Bags", {
            point = "BOTTOMRIGHT", x = -90, y = 120,
            resizable = true,
            minW = SIDEBAR_W + PAD * 2 + 2 + MIN_COLS * STEP - SLOT_GAP,
            maxW = SIDEBAR_W + PAD * 2 + 2 + MAX_COLS * STEP - SLOT_GAP,
            minH = 300, maxH = 1000,
            onResize = function(_, w) CysBags:ApplySize(w) end,
            freeMove = true, -- dragged by the title bar, resized by the corner grip
        })
        if CysUI.MakeResizeGrip then CysUI:MakeResizeGrip("bags") end
        -- once: back to 12 columns (an earlier auto-size widened windows to 16)
        if CysBagsDB and not CysBagsDB.cols12 and CysUIDB then
            CysBagsDB.cols12 = true
            CysUIDB.layout = CysUIDB.layout or {}
            local e = CysUIDB.layout.bags
            if e then e.width = SIDEBAR_W + PAD * 2 + 2 + 12 * STEP - SLOT_GAP; e.height = nil end
            if CysUI.ApplyLayout then CysUI:ApplyLayout("bags") end
        end
    end
    tinsert(UISpecialFrames, "CysBagsFrame") -- Esc closes the bags

    ---------------------------------------------------------------- header
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    SolidTexture(header, "BACKGROUND", C.header):SetAllPoints()
    local hline = SolidTexture(header, "BORDER", C.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    local function LayoutControlled() return CysUI and CysUI.movers and CysUI.movers.bags end
    -- with Cys's UI the drop spot is saved as the layout position (layout mode and dragging agree)
    header:SetScript("OnDragStart", function()
        if LayoutControlled() then
            if CysUI.StartWindowDrag then CysUI:StartWindowDrag("bags") end
        else frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        if LayoutControlled() then
            if CysUI.StopWindowDrag then CysUI:StopWindowDrag("bags") end
            return
        end
        frame:StopMovingOrSizing()
        CysBags:SavePosition()
    end)

    header.addonTitle = CreateText(header, 13, C.accent)
    header.addonTitle:SetPoint("LEFT", 12, 0)
    header.addonTitle:SetText("Cys's Bags")

    header.title = CreateText(header, 11, C.dim) -- "Inventory [x / y Items]" (colored in UpdateHeader)
    header.title:SetPoint("LEFT", header.addonTitle, "RIGHT", 12, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -6, 0)
    close.text = CreateText(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Guide button (gear icon) sits just left of the X
    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(16, 16)
    gearBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    local gearTex = gearBtn:CreateTexture(nil, "ARTWORK")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gearTex:SetVertexColor(0.8, 0.8, 0.8)
    gearBtn:SetScript("OnEnter", function(s)
        gearTex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Guide & Commands")
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function()
        gearTex:SetVertexColor(0.8, 0.8, 0.8)
        GameTooltip:Hide()
    end)
    gearBtn:SetScript("OnClick", function() CysBags:ToggleGuide() end)
    gearBtn:Hide() -- the old standalone guide button: gone from the header (Sort and Junk icons sit by the search box)

    local sb = CreateFrame("EditBox", "CysBagsSearchBox", header)
    sb:SetSize(160, 22)
    sb:SetPoint("RIGHT", close, "LEFT", -10, 0)
    sb:SetAutoFocus(false)
    sb:SetMaxLetters(40)
    sb:SetFont(STANDARD_TEXT_FONT, 11, "")
    sb:SetTextColor(C.text[1], C.text[2], C.text[3])
    sb:SetTextInsets(8, 8, 0, 0)
    SolidTexture(sb, "BACKGROUND", C.field):SetAllPoints()
    local sbBorder = CreateBorder(sb, 1, C.border, "BORDER")
    sb.placeholder = CreateText(sb, 11, C.dim)
    sb.placeholder:SetPoint("LEFT", 8, 0)
    sb.placeholder:SetText("Search items...")
    sb:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
    sb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    sb:SetScript("OnEditFocusGained", function(s)
        s.placeholder:Hide()
        SetBorderColor(sbBorder, C.accent[1], C.accent[2], C.accent[3])
    end)
    sb:SetScript("OnEditFocusLost", function(s)
        s.placeholder:SetShown(s:GetText() == "")
        SetBorderColor(sbBorder, C.border[1], C.border[2], C.border[3])
    end)
    -- X to clear the search
    local clear = CreateFrame("Button", nil, sb)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", -4, 0)
    clear.text = CreateText(clear, 12, C.dim)
    clear.text:SetPoint("CENTER", 0, 1)
    clear.text:SetText("x")
    clear:SetScript("OnEnter", function(s) s.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end)
    clear:SetScript("OnLeave", function(s) s.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end)
    clear:SetScript("OnClick", function() sb:SetText(""); sb:ClearFocus() end)
    clear:Hide()
    sb:SetTextInsets(8, 22, 0, 0)
    sb:SetScript("OnTextChanged", function(s)
        s.placeholder:SetShown(s:GetText() == "" and not s:HasFocus())
        clear:SetShown(s:GetText() ~= "")
        CysBags:SetSearch(s:GetText())
    end)
    self.searchBox = sb

    ---------------------------------------------------------------- footer
    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    SolidTexture(footer, "BACKGROUND", C.header):SetAllPoints()
    local fline = SolidTexture(footer, "BORDER", C.border)
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    footer.free = CreateText(footer, 11, C.dim)
    footer.free:SetPoint("LEFT", 12, 0)
    footer.gold = CreateText(footer, 12, C.text, "RIGHT")
    footer.gold:SetPoint("RIGHT", -12, 0)

    footer.bagSlots = {}
    for i = 1, 4 do
        local btn = CreateBagSlotButton(i)
        if i == 1 then
            btn:SetPoint("LEFT", footer, "LEFT", 112, 0)
        else
            btn:SetPoint("LEFT", footer.bagSlots[i - 1], "RIGHT", BAGSLOT_GAP, 0)
        end
        footer.bagSlots[i] = btn
    end

    -- Sort and "destroy cheapest junk" live down here, next to the bag slots
    -- (both are small icons in the header, just left of the search box)
    local function HeaderIcon(btn, texture)
        btn:SetSize(18, 18)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        btn.icon:SetTexture(texture)
        btn.icon:SetVertexColor(0.8, 0.8, 0.8)
        btn.text = btn:CreateFontString(nil, "OVERLAY") -- kept for older calls; the icon tells the state now
        btn.text:SetFont(STANDARD_TEXT_FONT, 10, ""); btn.text:Hide()
    end
    local sortBtn = CreateFrame("Button", nil, header)
    HeaderIcon(sortBtn, "Interface\\Buttons\\UI-RefreshButton")
    local sortBorder = {}
    sortBtn:SetScript("OnEnter", function(s)
        if not (sorter and sorter.running) then s.icon:SetVertexColor(1, 1, 1) end
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Sort bags", 1, 1, 1)
        GameTooltip:AddLine("Merges partial stacks and packs items into your first slots, ordered by category.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Ammo and profession bags are left alone.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function(s)
        if not (sorter and sorter.running) then s.icon:SetVertexColor(0.8, 0.8, 0.8) end
        GameTooltip:Hide()
    end)
    sortBtn:SetScript("OnClick", function() CysBags:ToggleSort() end)
    self.sortBtn = sortBtn

    local junkBtn = CreateFrame("Button", nil, header)
    HeaderIcon(junkBtn, "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    junkBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    junkBtn:SetPoint("RIGHT", self.searchBox, "LEFT", -10, 0)
    sortBtn:SetPoint("RIGHT", junkBtn, "LEFT", -8, 0)
    junkBtn:SetScript("OnEnter", function(s)
        s.icon:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Destroy Cheapest Junk", 1, 1, 1)
        GameTooltip:AddLine("Click to delete the cheapest grey junk item in your bags.", 0.8, 0.8, 0.8, true)
        -- what would go, and what it's worth at a vendor, so you can decide if the loot is worth more
        local _, _, link, value, count = FindCheapestJunk()
        GameTooltip:AddLine(" ")
        if link then
            GameTooltip:AddDoubleLine("Next to go:", link .. ((count or 1) > 1 and (" x" .. count) or ""), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Vendor value:", (value and value > 0) and CoinText(value) or "none", 1, 0.82, 0, 1, 1, 1)
        else
            GameTooltip:AddLine("No grey junk in your bags.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    junkBtn:SetScript("OnLeave", function(s)
        s.icon:SetVertexColor(0.8, 0.8, 0.8)
        GameTooltip:Hide()
    end)
    junkBtn:SetScript("OnClick", function() DeleteCheapestJunk() end)
    -- picked DropTheCheapestThing over this button in /cui > Conflicts: leave the job to it
    local cf = CysUIDB and CysUIDB.conflicts
    if cf and cf.DropTheCheapestThing == "theirs" then
        junkBtn:Hide()
        sortBtn:ClearAllPoints(); sortBtn:SetPoint("RIGHT", self.searchBox, "LEFT", -10, 0)
    end

    ---------------------------------------------------------------- sidebar
    sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H + 1)
    sidebar:SetWidth(SideW())
    SolidTexture(sidebar, "BACKGROUND", C.sidebar):SetAllPoints()
    local sline = SolidTexture(sidebar, "BORDER", C.border)
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)

    -- < / > at the bottom of the sidebar: collapse it to icons only, or open it again
    local slimBtn = CreateFrame("Button", nil, sidebar)
    slimBtn:SetSize(20, 20)
    slimBtn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -8, 6)
    slimBtn.text = CreateText(slimBtn, 14, C.dim, "CENTER")
    slimBtn.text:SetPoint("CENTER")
    slimBtn.text:SetText(Slim() and ">" or "<")
    slimBtn:SetScript("OnEnter", function(s)
        s.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(Slim() and "Expand sidebar" or "Collapse sidebar", 1, 1, 1)
        GameTooltip:Show()
    end)
    slimBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); GameTooltip:Hide() end)
    slimBtn:SetScript("OnClick", function() CysBags:SetSidebarSlim(not Slim()) end)
    self.slimBtn = slimBtn

    for i, cat in ipairs(SIDEBAR) do
        local b = CreateFrame("Button", nil, sidebar)
        b.key = cat.key
        b:SetHeight(26)
        b:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -(8 + (i - 1) * 27))
        b:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -(8 + (i - 1) * 27))
        b.bg = SolidTexture(b, "BACKGROUND", C.hover)
        b.bg:SetAllPoints()
        b.bg:Hide()
        b.accent = SolidTexture(b, "ARTWORK", C.accent)
        b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(2)
        b.accent:Hide()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 10, 0)
        b.icon:SetTexture(SIDEBAR_ICONS[cat.key] or "Interface\\Icons\\INV_Misc_Bag_08")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.label = CreateText(b, 11, C.text)
        b.label:SetPoint("LEFT", 32, 0)
        b.label:SetText(cat.label)
        b.count = CreateText(b, 11, C.dim, "RIGHT")
        b.count:SetPoint("RIGHT", -10, 0)
        b.dropEdges = CreateBorder(b, 1, { C.accent[1], C.accent[2], C.accent[3], 0.7 }, "OVERLAY")
        ShowBorder(b.dropEdges, false)
        b:SetScript("OnEnter", function(s)
            s.hover = true
            CysBags:UpdateSidebar()
            if CursorHasItem() and s.key ~= "SLOTS" then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                if s.key == "ALL" then
                    GameTooltip:SetText("Restore automatic sorting", 1, 1, 1)
                else
                    GameTooltip:SetText("Move to " .. (CATEGORY_TITLE[s.key] or s.key), 1, 1, 1)
                end
                GameTooltip:AddLine("Drop the item here.", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            elseif Slim() then
                -- collapsed sidebar: the name and count in a tooltip
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.label:GetText() or s.key, 1, 1, 1)
                GameTooltip:AddLine((s.count:GetText() or "0") .. " items", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(s)
            s.hover = false
            CysBags:UpdateSidebar()
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(s)
            if CursorHasItem() then CysBags:AssignCursorItem(s.key) else CysBags:SetFilter(s.key) end
        end)
        b:SetScript("OnReceiveDrag", function(s) CysBags:AssignCursorItem(s.key) end)
        sidebarButtons[i] = b
    end

    ---------------------------------------------------------------- main panel
    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, -PAD)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -PAD, PAD)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local newVal = s:GetVerticalScroll() - delta * (STEP * 1.5)
        s:SetVerticalScroll(max(0, min(newVal, s:GetVerticalScrollRange())))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(s, _, yRange)
        yRange = yRange or s:GetVerticalScrollRange()
        if s:GetVerticalScroll() > yRange then s:SetVerticalScroll(yRange) end
    end)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)

    self.emptyText = CreateText(content, 12, C.dim, "CENTER")
    self.emptyText:SetPoint("TOP", content, "TOP", 0, -30)
    self.emptyText:SetWidth(CONTENT_W)
    self.emptyText:SetText("No items")
    self.emptyText:Hide()

    -- Bag "holder" frames: ContainerFrameItemButtonTemplate reads the bag ID from its parent
    for bag = FIRST_BAG, LAST_BAG do
        local holder = CreateFrame("Frame", "CysBagsBagHolder" .. bag, content)
        holder:SetAllPoints(content)
        holder:SetID(bag)
        holder.GetBagID = holder.GetID -- retail item button code asks its parent for GetBagID()
        holders[bag] = holder
        buttons[bag] = {}
    end

    ---------------------------------------------------------------- scripts
    frame:SetScript("OnShow", function()
        if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
        CysBags.dirty = true
        CysBags:Refresh()
    end)
    frame:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
        frame:StopMovingOrSizing()
        sb:ClearFocus()
        CysBags.bagFilter = nil -- reopen showing every bag
    end)
    -- Only runs while visible. Coalesces bursts of BAG_UPDATE into one rebuild per frame.
    frame:SetScript("OnUpdate", function()
        if CysBags.dirty then CysBags:Refresh() end
        local carrying = CursorHasItem() and true or false
        if carrying ~= CysBags.carrying then -- show / hide the drop outlines on the sidebar
            CysBags.carrying = carrying
            CysBags:UpdateSidebar()
        end
    end)
end

function CysBags:PreCreateButtons()
    if not frame or InCombatLockdown() then return end
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, (GetNumSlots(bag) or 0) do
            GetItemButton(bag, slot)
        end
    end
end

--------------------------------------------------------------------------------
-- Replace the default bag toggles
--------------------------------------------------------------------------------
local hooksInstalled = false
local function InstallBagHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    if IS_FOREVER and hooksecurefunc then
        -- WoW Forever: Blizzard's bag functions are never replaced. Replacing them left addon "taint" in the
        -- path Blizzard's bank runs when it opens (OpenAllBags), and the bank's protected first-tab purchase
        -- got blocked. Instead Blizzard's own bag windows are tucked into a hidden frame, its functions run as
        -- normal, and ours follows whether Blizzard thinks the bags are open.
        local hidden = CreateFrame("Frame")
        hidden:Hide()
        local function Tuck(f) if f and f.SetParent then pcall(f.SetParent, f, hidden) end end
        Tuck(_G.ContainerFrameCombinedBags)
        for i = 1, (NUM_CONTAINER_FRAMES or 13) do Tuck(_G["ContainerFrame" .. i]) end

        local function BlizzardOpen()
            for id = FIRST_BAG, LAST_BAG do
                local ok, open = pcall(IsBagOpen, id)
                if ok and open then return true end
            end
            local cb = _G.ContainerFrameCombinedBags
            return cb and cb.IsShown and cb:IsShown() or false
        end
        -- A toggle (the bag key) flips ours, whatever Blizzard's hidden bags think; an open or close (bank,
        -- mailbox, vendor, Escape...) makes ours match Blizzard's. Calls in the same frame are handled once,
        -- because Blizzard's toggle runs its own open and close calls inside.
        local pending, toggled = false, false
        local function Sync()
            pending = false
            if toggled then
                toggled = false
                CysBags:Toggle()
            elseif BlizzardOpen() then
                CysBags:Open()
            else
                CysBags:Close()
            end
        end
        local function Later()
            if pending then return end
            pending = true
            C_Timer.After(0, Sync)
        end
        for _, name in ipairs({ "OpenBackpack", "CloseBackpack", "OpenAllBags", "CloseAllBags", "OpenBag", "CloseBag" }) do
            if _G[name] then hooksecurefunc(name, Later) end
        end
        local function Toggled(id)
            if id ~= nil and not (type(id) == "number" and id >= FIRST_BAG and id <= LAST_BAG) then return end
            toggled = true
            Later()
        end
        for _, name in ipairs({ "ToggleBackpack", "ToggleAllBags", "ToggleBag" }) do
            if _G[name] then hooksecurefunc(name, Toggled) end
        end
        return
    end

    local origToggleBag, origOpenBag, origCloseBag = ToggleBag, OpenBag, CloseBag
    local function Ours(id) return type(id) == "number" and id >= FIRST_BAG and id <= LAST_BAG end

    _G.ToggleBackpack = function() CysBags:Toggle() end
    _G.OpenBackpack   = function() CysBags:Open() end
    _G.CloseBackpack  = function() CysBags:Close() end
    _G.ToggleAllBags  = function() CysBags:Toggle() end
    _G.OpenAllBags    = function() CysBags:Open() end
    _G.CloseAllBags   = function() CysBags:Close() end

    _G.ToggleBag = function(id)
        if Ours(id) or not origToggleBag then CysBags:Toggle() else origToggleBag(id) end
    end
    _G.OpenBag = function(id)
        if Ours(id) or not origOpenBag then CysBags:Open() else origOpenBag(id) end
    end
    _G.CloseBag = function(id)
        if Ours(id) or not origCloseBag then CysBags:Close() else origCloseBag(id) end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Shared with CysBank.lua (loaded after this file) so the bank looks and sorts the same.
CysBags.Shared = {
    C = C, SIDEBAR = SIDEBAR, SECTIONS = SECTIONS, CATEGORY_TITLE = CATEGORY_TITLE,
    SolidTexture = SolidTexture, CreateBorder = CreateBorder, SetBorderColor = SetBorderColor,
    ShowBorder = ShowBorder, CreateText = CreateText,
    ResolveCategory = ResolveCategory, SortEntries = SortEntries, GetItemName = GetItemName,
    GetSlotItem = GetSlotItem, IsQuestSlot = IsQuestSlot, MatchesSearch = MatchesSearch,
    BuildSetLookup = BuildSetLookup,
    SLOT_SIZE = SLOT_SIZE, SLOT_GAP = SLOT_GAP, COLS = COLS, STEP = STEP, CONTENT_W = CONTENT_W,
    SIDEBAR_W = SIDEBAR_W, HEADER_H = HEADER_H, FOOTER_H = FOOTER_H, PAD = PAD,
    SECTION_H = SECTION_H, SECTION_GAP = SECTION_GAP, FRAME_W = FRAME_W, FRAME_H = FRAME_H,
    MIN_COLS = MIN_COLS, MAX_COLS = MAX_COLS,
}

local events = CreateFrame("Frame")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        events:UnregisterEvent("ADDON_LOADED")
        CysBagsDB = CysBagsDB or {}
        CysBagsDB.overrides = CysBagsDB.overrides or {}
        local lastFilter = CysBagsDB.filter
        if lastFilter == "SLOTS" or VALID_CATEGORY[lastFilter] then
            CysBags.filter = lastFilter
            CysBags.restoredFilter = true
        end
        CysBags:CreateFrames()
        events:RegisterEvent("PLAYER_LOGIN")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("BAG_UPDATE")
        events:RegisterEvent("BAG_UPDATE_COOLDOWN")
        events:RegisterEvent("PLAYER_MONEY")
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        events:RegisterEvent("UNIT_INVENTORY_CHANGED")
        pcall(events.RegisterEvent, events, "EQUIPMENT_SETS_CHANGED") -- Blizzard's Equipment Manager sets
        pcall(events.RegisterEvent, events, "INVENTORY_SEARCH_UPDATE") -- the game's bag search answered

    elseif event == "PLAYER_LOGIN" then
        InstallBagHooks()

    elseif event == "PLAYER_ENTERING_WORLD" then
        CysBags:PreCreateButtons()
        CysBags.dirty = true

    elseif event == "BAG_UPDATE" then
        -- ignore bank / keyring bags; we only draw the player's bags
        if arg1 == nil or (arg1 >= FIRST_BAG and arg1 <= LAST_BAG) then
            CysBags.dirty = true
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        CysBags:UpdateCooldowns()

    elseif event == "ITEM_LOCK_CHANGED" then
        CysBags.dirty = true

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then CysBags.dirty = true end

    elseif event == "EQUIPMENT_SETS_CHANGED" then
        CysBags.dirty = true

    elseif event == "INVENTORY_SEARCH_UPDATE" then
        CysBags.engineSearch = (CysBags.search or "") ~= ""
        if frame and frame:IsShown() then CysBags:ApplySearch() end

    elseif event == "PLAYER_MONEY" then
        if frame and frame:IsShown() then CysBags:UpdateFooter() end
    end
end)

-- Cys's UI runs this file after its settings load, so start up right away
events:GetScript("OnEvent")(events, "ADDON_LOADED", ADDON_NAME)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------
SLASH_CYSBAGS1 = "/cysbags"
SLASH_CYSBAGS2 = "/cbags"
SlashCmdList["CYSBAGS"] = function(msg)
    msg = lower(strtrim(msg or ""))
    if msg == "reset" then
        CysBagsDB.pos = nil
        CysBags:RestorePosition()
        print("|cFFFFD100Cys's Bags|r: position reset.")
    elseif msg == "sort" then
        CysBags:ToggleSort()
    elseif msg == "changelog" or msg == "whatsnew" then
        if CysChangelog then CysChangelog:Show("Cys's UI") end
    elseif msg == "resetcats" then
        CysBagsDB.overrides = {}
        CysBags.dirty = true
        if CysBank then CysBank.dirty = true end
        print("|cFFFFD100Cys's Bags|r: all manual category moves cleared.")
    elseif msg == "bags" then
        -- diagnostic: which inventory slot / texture the client reports for each equipped bag
        for i = 1, 4 do
            local invID = GetBagInventorySlot(i)
            print(format("|cFFFFD100Cys's Bags|r bag %d: invSlot=%s texture=%s containerSlots=%d",
                i, tostring(invID), tostring(GetInventoryItemTexture("player", invID)), GetNumSlots(i) or 0))
        end
    else
        CysBags:Toggle()
    end
end
end,
})
