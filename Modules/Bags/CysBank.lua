--------------------------------------------------------------------------------
-- Cys's Bank - your whole bank (main slots + every bank bag) in one categorized window.
-- Part of the CysBags addon: it reuses CysBags' look, categories, search and the
-- drag-an-item-onto-a-category feature, so CysBags.lua must load first (see the .toc).
--
--   * Opens by itself at a banker and closes when you walk away.
--   * Footer bag bar: click a bank bag to show only that bag, drop a bag on a slot to
--     equip it, click a locked slot to buy it. The first button is the main bank.
--   * /cysbank toggles the window while you're at the bank.
--------------------------------------------------------------------------------

CysUI:RegisterModule({
    key = "bank", name = "Cys's Bank", requires = "bags",
    desc = "Your whole bank in one categorized window with its own bag bar. Opens at any banker.",
    open = function() if CysBank and CysBank.Toggle then CysBank:Toggle() end end,
    body = function(...)
local S = CysBags and CysBags.Shared
if not S then return end

CysBank = CysBank or {}
local CysBank = CysBank

local C = S.C
local SolidTexture, CreateBorder, SetBorderColor, ShowBorder, CreateText =
    S.SolidTexture, S.CreateBorder, S.SetBorderColor, S.ShowBorder, S.CreateText
local ResolveCategory, SortEntries, GetItemName = S.ResolveCategory, S.SortEntries, S.GetItemName
local GetSlotItem, IsQuestSlot, MatchesSearch = S.GetSlotItem, S.IsQuestSlot, S.MatchesSearch
local SECTIONS, SIDEBAR, CATEGORY_TITLE = S.SECTIONS, S.SIDEBAR, S.CATEGORY_TITLE
local SLOT_SIZE, SLOT_GAP, COLS, STEP, CONTENT_W = S.SLOT_SIZE, S.SLOT_GAP, S.COLS, S.STEP, S.CONTENT_W
local SIDEBAR_W, HEADER_H, FOOTER_H, PAD = S.SIDEBAR_W, S.HEADER_H, S.FOOTER_H, S.PAD
local SECTION_H, SECTION_GAP, FRAME_W, FRAME_H = S.SECTION_H, S.SECTION_GAP, S.FRAME_W, S.FRAME_H

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local lower, format = string.lower, string.format
local sort, wipe, tinsert = table.sort, wipe, table.insert

-- Bank containers: -1 is the 24 main slots, then the purchasable bank bags
local MAIN_BANK = BANK_CONTAINER or -1
local NUM_BANK_BAGS = NUM_BANKBAGSLOTS or 6
local FIRST_BANK_BAG = (NUM_BAG_SLOTS or 4) + 1
local BANK_BAGS = { MAIN_BANK }
for i = 0, NUM_BANK_BAGS - 1 do BANK_BAGS[#BANK_BAGS + 1] = FIRST_BANK_BAG + i end

local EMPTY_BAG_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local FALLBACK_BAG_TEXTURE = "Interface\\Icons\\INV_Misc_Bag_08"
local MAIN_BANK_TEXTURE = "Interface\\Buttons\\Button-Backpack-Up"
local BAR_SIZE, BAR_GAP = 22, 4

--------------------------------------------------------------------------------
-- API compatibility
--------------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink
local PickupItem = (CC and CC.PickupContainerItem) or PickupContainerItem
local UseItem = (CC and CC.UseContainerItem) or UseContainerItem
local SplitItem = (CC and CC.SplitContainerItem) or SplitContainerItem

local function GetBankBagInventorySlot(bagID)
    local id
    if CC and CC.ContainerIDToInventoryID then id = CC.ContainerIDToInventoryID(bagID) end
    if not id and ContainerIDToInventoryID then id = ContainerIDToInventoryID(bagID) end
    if not id and BankButtonIDToInvSlotID then id = BankButtonIDToInvSlotID(bagID - FIRST_BANK_BAG + 1, 1) end
    return id
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local frame, header, sidebar, footer, scroll, content, emptyText, searchBox
local buttons = {}          -- buttons[bag][slot]
local sidebarButtons = {}
local sectionHeaders = {}
local activeButtons = {}
local barButtons = {}
local entryPool, lists, counts = {}, {}, {}
for _, sec in ipairs(SECTIONS) do lists[sec.key] = {} end
for _, bag in ipairs(BANK_BAGS) do buttons[bag] = {} end

CysBank.filter = "ALL"
local slotEntries = {} -- slotEntries[bag][slot] = entry (All Slots view)
CysBank.search = ""
CysBank.dirty = true
CysBank.used, CysBank.total, CysBank.free = 0, 0, 0

StaticPopupDialogs["CYSBANK_BUY_SLOT"] = {
    text = "Buy another bank bag slot for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() PurchaseSlot() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Item buttons. Plain buttons with our own click handling (no Blizzard item template),
-- so they behave the same for the main bank (-1) and every bank bag.
--------------------------------------------------------------------------------
local function CreateBankButton(bag, slot)
    local b = CreateFrame("Button", "CysBankItem" .. (bag + 2) .. "_" .. slot, content)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b.bag, b.slot = bag, slot
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    SolidTexture(b, "BACKGROUND", C.slot):SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 2)
    b.qualityEdges = CreateBorder(b, 1, C.text, "OVERLAY", 5)
    ShowBorder(b.qualityEdges, false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    -- used by the stack-split popup
    b.SplitStack = function(self, amount) SplitItem(self.bag, self.slot, amount) end

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- the main bank (-1) is read through the inventory slot; other bags through the container API
        if self.bag == MAIN_BANK and BankButtonIDToInvSlotID then
            GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self.slot))
        else
            GameTooltip:SetBagItem(self.bag, self.slot)
        end
        -- last resort: build it from the item link
        if (GameTooltip:NumLines() or 0) == 0 then
            local link = GetSlotLink(self.bag, self.slot)
            if link then GameTooltip:SetHyperlink(link) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        local link = GetSlotLink(self.bag, self.slot)
        if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
        local entry = self.entry
        if button == "LeftButton" and IsShiftKeyDown() and not CursorHasItem()
            and entry and (entry.count or 1) > 1 and OpenStackSplitFrame then
            OpenStackSplitFrame(entry.count, self, "BOTTOMLEFT", "TOPLEFT")
            return
        end
        if button == "RightButton" then
            UseItem(self.bag, self.slot) -- at the bank this moves the item to your bags
        else
            PickupItem(self.bag, self.slot)
        end
    end)
    b:SetScript("OnDragStart", function(self) PickupItem(self.bag, self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) PickupItem(self.bag, self.slot) end)
    return b
end

-- An empty slot in the All Slots view: the plain dark square, still a working drop target
local function UpdateEmptyBankButton(b)
    b.entry = nil
    b.icon:SetTexture(nil)
    b.icon:SetDesaturated(false)
    b.count:SetText("")
    b.count:Hide()
    ShowBorder(b.qualityEdges, false)
    b:SetAlpha((CysBank.search or "") == "" and 1 or 0.25)
end

local function GetBankButton(bag, slot)
    local b = buttons[bag][slot]
    if not b then
        b = CreateBankButton(bag, slot)
        buttons[bag][slot] = b
    end
    return b
end

local function UpdateBankButton(b, e)
    b.entry = e
    b.icon:SetTexture(e.icon)
    b.icon:SetDesaturated(e.locked and true or false)
    if e.count and e.count > 1 then
        b.count:SetText(e.count)
        b.count:Show()
    else
        b.count:SetText("")
        b.count:Hide()
    end
    local qc = e.quality and e.quality >= 2 and ITEM_QUALITY_COLORS[e.quality]
    if e.isQuest then
        SetBorderColor(b.qualityEdges, C.quest[1], C.quest[2], C.quest[3])
        ShowBorder(b.qualityEdges, true)
    elseif qc then
        SetBorderColor(b.qualityEdges, qc.r, qc.g, qc.b)
        ShowBorder(b.qualityEdges, true)
    else
        ShowBorder(b.qualityEdges, false)
    end
    b:SetAlpha(MatchesSearch(e, CysBank.search) and 1 or 0.25)
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
function CysBank:Collect()
    for _, list in pairs(lists) do wipe(list) end
    for _, t in pairs(slotEntries) do wipe(t) end
    wipe(counts)
    S.BuildSetLookup()

    local filter = self.bagFilter
    if filter and (GetNumSlots(filter) or 0) == 0 then
        filter = nil
        self.bagFilter = nil
    end

    local n, used, total = 0, 0, 0
    for _, bag in ipairs(BANK_BAGS) do
        local slots = GetNumSlots(bag) or 0
        total = total + slots
        for slot = 1, slots do
            local icon, count, locked, quality, link, itemID = GetSlotItem(bag, slot)
            if link then
                used = used + 1
                itemID = itemID or tonumber(link:match("item:(%d+)"))
                if itemID and (not filter or filter == bag) then
                    n = n + 1
                    local e = entryPool[n]
                    if not e then e = {}; entryPool[n] = e end
                    e.bag, e.slot, e.link, e.itemID = bag, slot, link, itemID
                    e.icon, e.count, e.locked = icon, count or 1, locked
                    e.quality = quality or select(3, GetItemInfo(link)) or 1
                    e.name, e.nameLower = GetItemName(link)
                    e.isQuest = IsQuestSlot(bag, slot)
                    e.highlight = nil
                    slotEntries[bag] = slotEntries[bag] or {}
                    slotEntries[bag][slot] = e
                    local list = lists[ResolveCategory(e)]
                    list[#list + 1] = e
                end
            end
        end
    end
    for _, sec in ipairs(SECTIONS) do
        sort(lists[sec.key], SortEntries)
        counts[sec.key] = #lists[sec.key]
    end
    counts.ALL = n
    counts.SLOTS = filter and (GetNumSlots(filter) or 0) or total
    self.used, self.total, self.free = used, total, total - used

    -- First open after login: if the remembered category is empty now, start on All Items instead
    if self.restoredFilter then
        self.restoredFilter = nil
        local f = self.filter
        if f ~= "ALL" and f ~= "SLOTS" and (counts[f] or 0) == 0 then self.filter = "ALL" end
    end
end

function CysBank:Layout()
    for _, bag in ipairs(BANK_BAGS) do
        for _, b in pairs(buttons[bag]) do b:Hide() end
    end
    for _, h in pairs(sectionHeaders) do h:Hide() end
    wipe(activeButtons)

    local filter, y, any = self.filter, 0, false

    -- All Slots: every real slot in order, empty ones included
    if filter == "SLOTS" then
        local i = 0
        for _, bag in ipairs(BANK_BAGS) do
            if not self.bagFilter or self.bagFilter == bag then
                local entries = slotEntries[bag]
                for slot = 1, (GetNumSlots(bag) or 0) do
                    i = i + 1
                    local b = GetBankButton(bag, slot)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", content, "TOPLEFT", ((i - 1) % COLS) * STEP, -(floor((i - 1) / COLS) * STEP))
                    local e = entries and entries[slot]
                    if e then UpdateBankButton(b, e) else UpdateEmptyBankButton(b) end
                    b:Show()
                    activeButtons[#activeButtons + 1] = b
                end
            end
        end
        any = i > 0
        y = ceil(i / COLS) * STEP - SLOT_GAP + SECTION_GAP
    end

    for _, sec in ipairs(SECTIONS) do
        if filter == "ALL" or filter == sec.key then
            local list = lists[sec.key]
            local n = #list
            if n > 0 then
                any = true
                local h = GetSectionHeader(sec.key)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                h.label:SetText(format("%s |cff777777(%d)|r", sec.title, n))
                h:Show()
                y = y + SECTION_H + 6
                for i = 1, n do
                    local e = list[i]
                    local b = GetBankButton(e.bag, e.slot)
                    local col, row = (i - 1) % COLS, floor((i - 1) / COLS)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", content, "TOPLEFT", col * STEP, -(y + row * STEP))
                    UpdateBankButton(b, e)
                    b:Show()
                    activeButtons[#activeButtons + 1] = b
                end
                y = y + ceil(n / COLS) * STEP - SLOT_GAP + SECTION_GAP
            end
        end
    end
    content:SetHeight(max(y - SECTION_GAP, 1))
    emptyText:SetShown(not any)
end

function CysBank:UpdateSidebar()
    local dropping = CursorHasItem() and true or false
    for _, sb in ipairs(sidebarButtons) do
        ShowBorder(sb.dropEdges, dropping)
        local selected = (sb.key == self.filter)
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
            sb.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        elseif n == 0 then
            sb.label:SetTextColor(0.35, 0.35, 0.35)
        else
            sb.label:SetTextColor(0.9, 0.9, 0.9)
        end
        sb.count:SetText(n)
    end
end

function CysBank:UpdateBar()
    local purchased = GetNumBankSlots and (GetNumBankSlots()) or NUM_BANK_BAGS
    for _, b in ipairs(barButtons) do
        local active = (self.bagFilter == b.bagID)
        if b.isMain then
            b.icon:SetTexture(MAIN_BANK_TEXTURE)
            b.icon:SetAlpha(1)
            b.icon:SetVertexColor(1, 1, 1)
            b.icon:SetDesaturated(false)
        elseif b.index > purchased then
            -- locked slot: dim red bag
            b.icon:SetTexture(EMPTY_BAG_TEXTURE)
            b.icon:SetAlpha(0.7)
            b.icon:SetVertexColor(1, 0.3, 0.3)
            b.icon:SetDesaturated(false)
        else
            local tex = b.invID and GetInventoryItemTexture("player", b.invID)
            if not tex and (GetNumSlots(b.bagID) or 0) > 0 then tex = FALLBACK_BAG_TEXTURE end
            b.icon:SetVertexColor(1, 1, 1)
            if tex then
                b.icon:SetTexture(tex)
                b.icon:SetAlpha(1)
            else
                b.icon:SetTexture(EMPTY_BAG_TEXTURE)
                b.icon:SetAlpha(0.45)
            end
            b.icon:SetDesaturated(b.invID and IsInventoryItemLocked(b.invID) and true or false)
        end
        ShowBorder(b.activeEdges, active)
        b.activeFill:SetShown(active)
    end
end

-- Layout mode resizes the window: width decides the number of item columns, height the list room.
function CysBank:ApplySize(w)
    local cols = floor((w - SIDEBAR_W - PAD * 2 - 2 + SLOT_GAP) / STEP)
    cols = max(S.MIN_COLS or 4, min(cols, S.MAX_COLS or 16))
    if cols == COLS then return end
    COLS = cols
    CONTENT_W = COLS * STEP - SLOT_GAP
    if content then
        content:SetWidth(CONTENT_W)
        if emptyText then emptyText:SetWidth(CONTENT_W) end
        for _, h in pairs(sectionHeaders) do h:SetWidth(CONTENT_W) end
        self.dirty = true
        if frame and frame:IsShown() then self:Refresh() end
    end
end

function CysBank:Refresh()
    if not frame then return end
    self.dirty = false
    self:Collect()
    self:Layout()
    self:UpdateSidebar()
    self:UpdateBar()
    -- Trigger CysUpgrade overlay check for bank
    if _G["UpdateCysBankUpgradeOverlays"] then
    pcall(_G["UpdateCysBankUpgradeOverlays"])
end
    header.count:SetFormattedText("|cFFFFD100Bank|r |cFFFFFFFF[%d / %d Items]|r", self.used, self.total)
    footer.free:SetText("|cFFFFD100Free slots:|r |cFFFFFFFF" .. self.free .. "|r")
    footer.gold:SetText(GetCoinTextureString(GetMoney()))
end

function CysBank:SetFilter(key)
    self.filter = key
    if CysBagsDB then CysBagsDB.bankFilter = key end -- reopen on the same tab next time
    scroll:SetVerticalScroll(0)
    self.dirty = true
    if frame:IsShown() then self:Refresh() end
end

function CysBank:SetSearch(text)
    self.search = lower(strtrim(text or ""))
    for i = 1, #activeButtons do
        local b = activeButtons[i]
        if b.entry then
            b:SetAlpha(MatchesSearch(b.entry, self.search) and 1 or 0.25)
        else
            b:SetAlpha(self.search == "" and 1 or 0.25) -- empty slot
        end
    end
end

function CysBank:ToggleBagFilter(bagID)
    if self.bagFilter == bagID then
        self.bagFilter = nil
    elseif (GetNumSlots(bagID) or 0) > 0 then
        self.bagFilter = bagID
    else
        return
    end
    scroll:SetVerticalScroll(0)
    self.dirty = true
    if frame:IsShown() then self:Refresh() end
end

function CysBank:PromptPurchase()
    local numSlots, full = GetNumBankSlots()
    if full then return end
    StaticPopup_Show("CYSBANK_BUY_SLOT", GetCoinTextureString(GetBankSlotCost(numSlots)))
end

--------------------------------------------------------------------------------
-- Footer bag bar (main bank + bank bag slots)
--------------------------------------------------------------------------------
local function CreateBarButton(bagID)
    local isMain = (bagID == MAIN_BANK)
    local b = CreateFrame("Button", nil, footer)
    b:SetSize(BAR_SIZE, BAR_SIZE)
    b.bagID, b.isMain = bagID, isMain
    b.index = isMain and 0 or (bagID - FIRST_BANK_BAG + 1)
    b.invID = (not isMain) and GetBankBagInventorySlot(bagID) or nil
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")

    SolidTexture(b, "BACKGROUND", C.slot):SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    CreateBorder(b, 1, C.border, "BORDER")
    b.activeEdges = CreateBorder(b, 2, C.accent, "OVERLAY", 7)
    ShowBorder(b.activeEdges, false)
    b.activeFill = SolidTexture(b, "OVERLAY", { C.accent[1], C.accent[2], C.accent[3], 0.22 }, 3)
    b.activeFill:SetAllPoints()
    b.activeFill:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    local function Purchased(self)
        return self.index <= (GetNumBankSlots and (GetNumBankSlots()) or NUM_BANK_BAGS)
    end

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.isMain then
            GameTooltip:SetText("Bank", 1, 1, 1)
            GameTooltip:AddLine("Click: show only the main bank slots", C.accent[1], C.accent[2], C.accent[3])
        elseif not Purchased(self) then
            GameTooltip:SetText("Locked bank bag slot", 1, 0.3, 0.3)
            local numSlots, full = GetNumBankSlots()
            if not full then
                GameTooltip:AddLine("Click to buy: " .. GetCoinTextureString(GetBankSlotCost(numSlots)), 1, 1, 1)
            end
        else
            if not (self.invID and GameTooltip:SetInventoryItem("player", self.invID)) then
                GameTooltip:SetText("Empty bank bag slot", 1, 1, 1)
            end
            GameTooltip:AddLine("Click: show only this bag", C.accent[1], C.accent[2], C.accent[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.isMain then
            CysBank:ToggleBagFilter(MAIN_BANK)
        elseif CursorHasItem() then
            if self.invID and Purchased(self) then PutItemInBag(self.invID) end
        elseif not Purchased(self) then
            CysBank:PromptPurchase()
        else
            CysBank:ToggleBagFilter(self.bagID)
        end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if CursorHasItem() and self.invID and not self.isMain and Purchased(self) then
            PutItemInBag(self.invID)
        end
    end)
    b:SetScript("OnDragStart", function(self)
        if self.invID and not self.isMain and Purchased(self) then PickupBagFromSlot(self.invID) end
    end)
    return b
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
function CysBank:SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then CysBagsDB.bankPos = { point, relPoint, x, y } end
end

function CysBank:CreateFrames()
    if frame then return end

    frame = CreateFrame("Frame", "CysBankFrame", UIParent)
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
    local p = CysBagsDB and CysBagsDB.bankPos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("LEFT", UIParent, "LEFT", 60, 40)
    end
    -- With Cys's UI, position and scale come from layout mode (/cui layout)
    if CysUI and CysUI.RegisterMovable then
        CysUI:RegisterMovable(frame, "bank", "Cys's Bank", {
            point = "LEFT", x = 60, y = 40,
            resizable = true,
            minW = SIDEBAR_W + PAD * 2 + 2 + (S.MIN_COLS or 4) * STEP - SLOT_GAP,
            maxW = SIDEBAR_W + PAD * 2 + 2 + (S.MAX_COLS or 16) * STEP - SLOT_GAP,
            minH = 300, maxH = 1000,
            onResize = function(_, w) CysBank:ApplySize(w) end,
        })
    end
    tinsert(UISpecialFrames, "CysBankFrame")

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
    local function LayoutControlled() return CysUI and CysUI.movers and CysUI.movers.bank end
    header:SetScript("OnDragStart", function() if not LayoutControlled() then frame:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        if LayoutControlled() then return end
        frame:StopMovingOrSizing()
        CysBank:SavePosition()
    end)

    header.addonTitle = CreateText(header, 13, C.accent)
    header.addonTitle:SetPoint("LEFT", 12, 0)
    header.addonTitle:SetText("Cys's Bank")
    header.count = CreateText(header, 11, C.dim)
    header.count:SetPoint("LEFT", header.addonTitle, "RIGHT", 12, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -6, 0)
    close.text = CreateText(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    local sb = CreateFrame("EditBox", "CysBankSearchBox", header)
    sb:SetSize(190, 22)
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
    sb:SetScript("OnTextChanged", function(s)
        s.placeholder:SetShown(s:GetText() == "" and not s:HasFocus())
        CysBank:SetSearch(s:GetText())
    end)
    searchBox = sb

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

    for i, bagID in ipairs(BANK_BAGS) do
        local b = CreateBarButton(bagID)
        if i == 1 then
            b:SetPoint("LEFT", footer, "LEFT", 112, 0)
        else
            b:SetPoint("LEFT", barButtons[i - 1], "RIGHT", BAR_GAP, 0)
        end
        barButtons[i] = b
    end

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
            CysBank:UpdateSidebar()
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
            CysBank:UpdateSidebar()
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(s)
            if CursorHasItem() then CysBags:AssignCursorItem(s.key) else CysBank:SetFilter(s.key) end
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
        local value = s:GetVerticalScroll() - delta * (STEP * 1.5)
        s:SetVerticalScroll(max(0, min(value, s:GetVerticalScrollRange())))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(s, _, yRange)
        yRange = yRange or s:GetVerticalScrollRange()
        if s:GetVerticalScroll() > yRange then s:SetVerticalScroll(yRange) end
    end)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)

    emptyText = CreateText(content, 12, C.dim, "CENTER")
    emptyText:SetPoint("TOP", content, "TOP", 0, -30)
    emptyText:SetWidth(CONTENT_W)
    emptyText:SetText("No items")
    emptyText:Hide()

    ---------------------------------------------------------------- scripts
    frame:SetScript("OnShow", function()
        if SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
        CysBank.dirty = true
        CysBank:Refresh()
    end)
    frame:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
        frame:StopMovingOrSizing()
        sb:ClearFocus()
        CysBank.bagFilter = nil
        if CysBank.interacting then -- closed by the player: end the banker conversation too
            CysBank.interacting = false
            CloseBankFrame()
        end
    end)
    frame:SetScript("OnUpdate", function()
        if CysBank.dirty then CysBank:Refresh() end
        local carrying = CursorHasItem() and true or false
        if carrying ~= CysBank.carrying then
            CysBank.carrying = carrying
            CysBank:UpdateSidebar()
        end
    end)
end

--------------------------------------------------------------------------------
-- Opening at a banker; hiding Blizzard's own bank window
--------------------------------------------------------------------------------
local function MuteBlizzardBank()
    -- If Blizzard's window still opens, shrink it away rather than hiding it: hiding it
    -- would end the banker conversation.
    if BankFrame and BankFrame:IsShown() then
        BankFrame:SetAlpha(0)
        BankFrame:SetScale(0.001)
        CysBank.mutedBlizzard = true
    end
end

local function RestoreBlizzardBank()
    if CysBank.mutedBlizzard and BankFrame then
        BankFrame:SetAlpha(1)
        BankFrame:SetScale(1)
        CysBank.mutedBlizzard = nil
    end
end

function CysBank:Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    elseif self.interacting then
        frame:Show()
    else
        print("|cFFFFD100Cys's Bank|r: visit a banker first.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local lastFilter = CysBagsDB and CysBagsDB.bankFilter
        if lastFilter == "SLOTS" or (lastFilter and S.CATEGORY_TITLE[lastFilter]) then
            CysBank.filter = lastFilter
            CysBank.restoredFilter = true
        end
        CysBank:CreateFrames()
        if BankFrame and BankFrame.UnregisterAllEvents then pcall(BankFrame.UnregisterAllEvents, BankFrame) end
        for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "PLAYERBANKSLOTS_CHANGED",
                             "PLAYERBANKBAGSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY" }) do
            events:RegisterEvent(e)
        end
    elseif event == "BANKFRAME_OPENED" then
        CysBank.interacting = true
        frame:Show()
        if CysBags and CysBags.Open then CysBags:Open() end
        MuteBlizzardBank()
        C_Timer.After(0, MuteBlizzardBank)
        C_Timer.After(0.2, MuteBlizzardBank)
    elseif event == "BANKFRAME_CLOSED" then
        CysBank.interacting = false -- the server already closed it: don't call CloseBankFrame again
        frame:Hide()
        RestoreBlizzardBank()
        if CysBags and CysBags.Close then CysBags:Close() end
    elseif event == "BAG_UPDATE" then
        -- only bank containers matter here (the player's own bags are CysBags' job)
        if arg1 == nil or arg1 == MAIN_BANK or arg1 >= FIRST_BANK_BAG then CysBank.dirty = true end
    elseif event == "PLAYER_MONEY" then
        if frame and frame:IsShown() then footer.gold:SetText(GetCoinTextureString(GetMoney())) end
    else
        CysBank.dirty = true
    end
end)

SLASH_CYSBANK1 = "/cysbank"
SlashCmdList["CYSBANK"] = function() CysBank:Toggle() end
end,
})
