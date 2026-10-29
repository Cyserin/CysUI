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
    bg       = Hex("111111"),
    border   = CysUI.W.T.border, -- frame colour (follows the Border color setting)
    header   = Hex("141414"),
    sidebar  = Hex("0D0D0D"),
    field    = Hex("0A0A0A"),
    slot     = Hex("1A1A1A"),
    hover    = Hex("181818"),
    selected = Hex("1E1E1E"),
    line     = Hex("2A2A2A"),
    text     = Hex("E0E0E0"),
    dim      = Hex("777777"),
    accent   = Hex("FFD100"), -- gold: active category, focus rings, active bag slot
    cyan     = Hex("00D9FF"), -- reserved for the Cys's Armory set-highlight border
    quest    = Hex("FFD100"),
}

-- Layout
local SLOT_SIZE, SLOT_GAP, COLS = 37, 4, 8 -- COLS changes when the window is resized in layout mode
local STEP        = SLOT_SIZE + SLOT_GAP
local CONTENT_W   = COLS * STEP - SLOT_GAP
local SIDEBAR_W   = 190
local HEADER_H    = 34
local FOOTER_H    = 30
local PAD         = 12
local SECTION_H   = 22
local SECTION_GAP = 12
local FRAME_H     = 540 -- default window height (resize it in /cui layout)
local MIN_COLS, MAX_COLS = 6, 16
local FRAME_W     = CONTENT_W + SIDEBAR_W + PAD * 2 + 2

local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS or 4

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

-- Sidebar entries (label) and main-panel section order (title)
local SIDEBAR = {
    { key = "ALL",        label = "All Items" },
    { key = "SLOTS",      label = "All Slots" },
    { key = "SETS",       label = "Armory Sets" },
    { key = "CONSUMABLE", label = "Consumables" },
    { key = "GEAR",       label = "Armor / Weapons" },
    { key = "BOE",        label = "Bind on Equip" },
    { key = "QUEST",      label = "Quest Items" },       
    { key = "TRADE",      label = "Trade Goods / Professions" },
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

local function MatchesSearch(e, search)
    if search == "" then return true end
    return e.nameLower:find(search, 1, true) ~= nil
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
    local btn = CreateFrame("Button", name, holders[bag], "ContainerFrameItemButtonTemplate")
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
        total = total + slots
        for slot = 1, slots do
            local icon, count, locked, quality, link, itemID = GetSlotItem(bag, slot)
            if link then
                used = used + 1
                itemID = itemID or tonumber(link:match("item:(%d+)"))
                if itemID and (not bagFilter or bagFilter == bag) then
                    n = n + 1
                    local e = entryPool[n]
                    if not e then e = {}; entryPool[n] = e end
                    e.bag, e.slot, e.link, e.itemID = bag, slot, link, itemID
                    e.icon, e.count, e.locked = icon, count or 1, locked
                    e.quality = quality or select(3, GetItemInfo(link)) or 1
                    e.name, e.nameLower = GetItemName(link)
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

    -- 3. Render standard non-set categories
    for _, sec in ipairs(SECTIONS) do
        if sec.key ~= "SETS" and (filter == "ALL" or filter == sec.key) then
            RenderSection(sec.key, sec.title)
        end
    end

    local contentH = max(y - SECTION_GAP, 1)
    content:SetHeight(contentH)
    self.emptyText:SetShown(not any)
    -- The window keeps one fixed size (FRAME_H); only the scrolling content changes.
end

-- Layout mode resizes the window: its width decides how many item columns fit (the height just
-- gives the list more or less room), so the content is re-flowed whenever the column count changes.
function CysBags:ApplySize(w)
    local cols = floor((w - SIDEBAR_W - PAD * 2 - 2 + SLOT_GAP) / STEP)
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

function CysBags:UpdateSidebar()
    local dropping = CursorHasItem() and true or false
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
    header.title:SetFormattedText("|cFFFFD100Inventory|r |cFFFFFFFF[%d / %d Items]|r", self.used, self.total)
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
    if CysBags.sortBtn then CysBags.sortBtn.text:SetText("Sort") end
    CysBags.dirty = true
    if message then print("|cFFFFD100Cys's Bags|r: " .. message) end
end

-- pos[i] = {bag, slot}; cur[i] = item snapshot or nil (empty); n = number of sortable slots
local function SnapshotSortSlots()
    local pos, cur, n, anyLocked = {}, {}, 0, false
    for bag = FIRST_BAG, LAST_BAG do
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
    if CysBags.sortBtn then CysBags.sortBtn.text:SetText("Stop") end
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
    "Items saved in Cys's Armory sets are grouped into the Armory Sets section at the top.",
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
    local btn = CreateFrame("Button", name, footer, "ItemButtonTemplate")
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
local function DeleteCheapestJunk()
    if InCombatLockdown() then
        print("|cFFFFD100Cys's Bags|r: Cannot delete items in combat!")
        return
    end

    local cheapestBag, cheapestSlot, cheapestLink
    local lowestValue = math.huge

    if not C_Container then return end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local _, _, quality, _, _, _, _, _, _, _, itemSellPrice = GetItemInfo(info.hyperlink)
                
                -- Verify item is strictly Poor (grey = 0) and NOT a quest item
                if quality == 0 and not C_Container.GetContainerItemQuestInfo(bag, slot).isQuestItem then
                    local totalValue = (itemSellPrice or 0) * (info.stackCount or 1)
                    if totalValue < lowestValue then
                        lowestValue = totalValue
                        cheapestBag = bag
                        cheapestSlot = slot
                        cheapestLink = info.hyperlink
                    end
                end
            end
        end
    end

    if cheapestBag and cheapestSlot then
        ClearCursor()
        C_Container.PickupContainerItem(cheapestBag, cheapestSlot)
        if CursorHasItem() then
            DeleteCursorItem()
            print(string.format("|cFFFFD100Cys's Bags|r: Destroyed cheapest junk %s", cheapestLink or "item"))
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
        })
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
    header:SetScript("OnDragStart", function() if not LayoutControlled() then frame:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        if LayoutControlled() then return end
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

    local sb = CreateFrame("EditBox", "CysBagsSearchBox", header)
    sb:SetSize(190, 22)
    sb:SetPoint("RIGHT", gearBtn, "LEFT", -8, 0)
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
    sb:SetScript("OnTextChanged", function(s)
        s.placeholder:SetShown(s:GetText() == "" and not s:HasFocus())
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
    local sortBtn = CreateFrame("Button", nil, footer)
    sortBtn:SetSize(46, 22)
    sortBtn:SetPoint("LEFT", footer.bagSlots[4], "RIGHT", 14, 0)
    SolidTexture(sortBtn, "BACKGROUND", C.field):SetAllPoints()
    local sortBorder = CreateBorder(sortBtn, 1, C.border, "BORDER")
    sortBtn.text = CreateText(sortBtn, 11, C.accent, "CENTER")
    sortBtn.text:SetPoint("CENTER", 0, 0)
    sortBtn.text:SetText("Sort")
    sortBtn:SetScript("OnEnter", function(s)
        SetBorderColor(sortBorder, C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Sort bags", 1, 1, 1)
        GameTooltip:AddLine("Merges partial stacks and packs items into your first slots, ordered by category.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Ammo and profession bags are left alone.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function()
        SetBorderColor(sortBorder, C.border[1], C.border[2], C.border[3])
        GameTooltip:Hide()
    end)
    sortBtn:SetScript("OnClick", function() CysBags:ToggleSort() end)
    self.sortBtn = sortBtn

    local junkBtn = CreateFrame("Button", nil, footer)
    junkBtn:SetSize(46, 22)
    junkBtn:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)
    SolidTexture(junkBtn, "BACKGROUND", C.field):SetAllPoints()
    local junkBorder = CreateBorder(junkBtn, 1, C.border, "BORDER")
    junkBtn.text = CreateText(junkBtn, 11, C.accent, "CENTER")
    junkBtn.text:SetPoint("CENTER", 0, 0)
    junkBtn.text:SetText("Junk")
    junkBtn:SetScript("OnEnter", function(s)
        SetBorderColor(junkBorder, C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Destroy Cheapest Junk", 1, 1, 1)
        GameTooltip:AddLine("Click to delete the cheapest grey junk item in your bags.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    junkBtn:SetScript("OnLeave", function()
        SetBorderColor(junkBorder, C.border[1], C.border[2], C.border[3])
        GameTooltip:Hide()
    end)
    junkBtn:SetScript("OnClick", function() DeleteCheapestJunk() end)

    ---------------------------------------------------------------- sidebar
    sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H + 1)
    sidebar:SetWidth(SIDEBAR_W)
    SolidTexture(sidebar, "BACKGROUND", C.sidebar):SetAllPoints()
    local sline = SolidTexture(sidebar, "BORDER", C.border)
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)

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
        b.label = CreateText(b, 11, C.text)
        b.label:SetPoint("LEFT", 14, 0)
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
