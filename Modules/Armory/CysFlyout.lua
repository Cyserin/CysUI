--------------------------------------------------------------------------------
-- CysFlyout - Alt-hover equipment flyout for the default character frame
-- (WoW Classic Era 1.15.x)
--
-- Hold Alt while the mouse is over an equipment slot on the character frame and a
-- flyout lists every matching item in your bags. Click one to equip it.
--   * Main hand: 1H and 2H weapons          * Off hand: shields, off-hand items and,
--   * Ranged: bows, guns, thrown, relics      if you can dual wield, 1H weapons too
--   * Items you can't use (level / armor type / weapon skill) are tinted red.
--   * The number in the corner is the level an item requires (red = you're too low).
--
-- Install: put this file in Cys's Armory's folder and add the line
--   CysFlyout.lua
-- to the Armory's .toc (anywhere after the main file). It doesn't depend on the
-- Armory's code, so it also works as its own tiny addon.
--
-- API:  CysFlyout:SetEnabled(true/false)    CysFlyout:Hide()
--------------------------------------------------------------------------------

CysUI:RegisterModule({
    key = "flyout", name = "Equipment Flyout",
    desc = "Hold Alt over a slot on the character frame to see the items in your bags that fit it.",
    body = function(...)
CysFlyout = CysFlyout or {}
local CysFlyout = CysFlyout
CysFlyout.enabled = true

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local sort = table.sort

--------------------------------------------------------------------------------
-- Style (same palette as CysBags)
--------------------------------------------------------------------------------
local function Hex(hex)
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
end

local C = {
    bg     = Hex("111111"),
    slot   = Hex("1A1A1A"),
    gold   = CysUI.W.T.border, -- frame colour (follows the Border color setting)
    accent = Hex("FFD100"), -- title / hover
    line   = Hex("2A2A2A"),
    text   = Hex("E0E0E0"),
    dim    = Hex("777777"),
}

local SIZE, GAP, PAD = 34, 4, 10
local HEADER_H = 26
local COLS_MAX = 6

--------------------------------------------------------------------------------
-- Which items fit which slot
--------------------------------------------------------------------------------
-- [inventory slot ID] = { global label name, flyout direction, accepted equip locations }
local SLOT_INFO = {
    [1]  = { "HEADSLOT",          "RIGHT", { INVTYPE_HEAD = true } },
    [2]  = { "NECKSLOT",          "RIGHT", { INVTYPE_NECK = true } },
    [3]  = { "SHOULDERSLOT",      "RIGHT", { INVTYPE_SHOULDER = true } },
    [4]  = { "SHIRTSLOT",         "RIGHT", { INVTYPE_BODY = true } },
    [5]  = { "CHESTSLOT",         "RIGHT", { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    [6]  = { "WAISTSLOT",         "LEFT",  { INVTYPE_WAIST = true } },
    [7]  = { "LEGSSLOT",          "LEFT",  { INVTYPE_LEGS = true } },
    [8]  = { "FEETSLOT",          "LEFT",  { INVTYPE_FEET = true } },
    [9]  = { "WRISTSLOT",         "RIGHT", { INVTYPE_WRIST = true } },
    [10] = { "HANDSSLOT",         "LEFT",  { INVTYPE_HAND = true } },
    [11] = { "FINGER0SLOT",       "LEFT",  { INVTYPE_FINGER = true } },
    [12] = { "FINGER1SLOT",       "LEFT",  { INVTYPE_FINGER = true } },
    [13] = { "TRINKET0SLOT",      "LEFT",  { INVTYPE_TRINKET = true } },
    [14] = { "TRINKET1SLOT",      "LEFT",  { INVTYPE_TRINKET = true } },
    [15] = { "BACKSLOT",          "RIGHT", { INVTYPE_CLOAK = true } },
    [16] = { "MAINHANDSLOT",      "UP",    { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
    [17] = { "SECONDARYHANDSLOT", "UP",    { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true } },
    [18] = { "RANGEDSLOT",        "UP",    { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
    [19] = { "TABARDSLOT",        "RIGHT", { INVTYPE_TABARD = true } },
}

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- Dual Wield is spell 674 for every class that gets it (Warrior, Rogue, Hunter, Shaman).
local function CanDualWield()
    if IsSpellKnown and IsSpellKnown(674) then return true end
    if IsPlayerSpell and IsPlayerSpell(674) then return true end
    return false
end

local function Accepts(invSlot, info, equipLoc)
    if info[3][equipLoc] then return true end
    -- one-hand weapons only go in the off hand if you can dual wield
    return invSlot == 17 and equipLoc == "INVTYPE_WEAPON" and CanDualWield()
end

--------------------------------------------------------------------------------
-- Bag scanning
--------------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotLink = (CC and CC.GetContainerItemLink) or GetContainerItemLink

-- Hidden tooltip: an item you can't use shows its requirement lines in red.
local scanTip = CreateFrame("GameTooltip", "CysFlyoutScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function IsUnusable(bag, slot)
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 2, scanTip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["CysFlyoutScanTipText" .. side .. i]
            local text = fs and fs:GetText()
            if text and text ~= "" then
                local r, g, b = fs:GetTextColor()
                if r > 0.9 and g < 0.25 and b < 0.25 then return true end
            end
        end
    end
    return false
end

local function CompareCandidates(a, b)
    if a.unusable ~= b.unusable then return b.unusable end -- usable first
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end -- best gear you can wear first
    if a.name ~= b.name then return a.name < b.name end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local function CollectCandidates(invSlot, info)
    local list, n = {}, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local link = GetSlotLink(bag, slot)
            if link then
                local _, _, _, equipLoc, icon = GetItemInfoInstant(link)
                if equipLoc and equipLoc ~= "" and Accepts(invSlot, info, equipLoc) then
                    local name, _, quality, _, minLevel = GetItemInfo(link)
                    n = n + 1
                    list[n] = {
                        bag = bag, slot = slot, link = link, icon = icon,
                        name = name or "", quality = quality or 1, minLevel = minLevel or 0,
                        unusable = IsUnusable(bag, slot),
                    }
                end
            end
        end
    end
    sort(list, CompareCandidates)
    return list
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------
local function MakeBorder(parent, color, layer)
    local edges = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        if color == C.gold then CysUI.W.TrackEdge(t) end
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT");    edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");    edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return edges
end

local function SetBorderColor(edges, r, g, b)
    for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, 1) end
end

local function MakeText(parent, size, color, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, outline or "")
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Over(frame)
    if not (frame and frame:IsShown()) then return false end
    if frame.IsMouseOver then return frame:IsMouseOver() end
    return MouseIsOver and MouseIsOver(frame) or false
end

local function PlaceTooltip(flyout)
    -- Beside the flyout, never on top of it
    GameTooltip:SetOwner(flyout, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if flyout.dir == "RIGHT" then
        GameTooltip:SetPoint("TOPLEFT", flyout, "TOPRIGHT", 6, 0)
    elseif flyout.dir == "LEFT" then
        GameTooltip:SetPoint("TOPRIGHT", flyout, "TOPLEFT", -6, 0)
    else
        GameTooltip:SetPoint("BOTTOM", flyout, "TOP", 0, 6)
    end
end

local function CreateFlyoutButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.slot[1], C.slot[2], C.slot[3], 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.border = MakeBorder(b, C.line, "OVERLAY")

    b.level = MakeText(b, 10, C.text, "OUTLINE") -- required level
    b.level:SetPoint("BOTTOMRIGHT", -2, 2)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b:SetScript("OnEnter", function(self)
        SetBorderColor(self.border, C.accent[1], C.accent[2], C.accent[3])
        PlaceTooltip(CysFlyout.frame)
        GameTooltip:SetBagItem(self.bag, self.slot)
        if GameTooltip_ShowCompareItem and (IsShiftKeyDown() or GetCVar("alwaysCompareItems") == "1") then
            pcall(GameTooltip_ShowCompareItem)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        SetBorderColor(self.border, self.br, self.bg, self.bb)
        GameTooltip:Hide()
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    end)
    b:SetScript("OnClick", function(self)
        local invSlot = CysFlyout.frame and CysFlyout.frame.invSlot
        GameTooltip:Hide()
        CysFlyout:Hide()
        if invSlot then EquipItemByName(self.link, invSlot) end
    end)
    return b
end

local function CreateFlyoutFrame()
    local f = CreateFrame("Frame", "CysFlyoutFrame", UIParent)
    -- Above the character frame, the Armory panel and every normal dialog.
    -- (Tooltips live in the TOOLTIP strata, so they still draw over this.)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.98)
    MakeBorder(f, C.gold, "BORDER")

    f.title = MakeText(f, 11, C.text)
    f.title:SetPoint("TOPLEFT", PAD, -8)

    -- small "Take off" buttons (they use the Armory's take-off code, so they only show when it is on)
    local function SmallButton(label, w, tipTitle, tipText)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(w, 16)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.slot[1], C.slot[2], C.slot[3], 1)
        b.edges = MakeBorder(b, C.line, "BORDER")
        b.label = MakeText(b, 10, C.accent)
        b.label:SetPoint("CENTER")
        b.label:SetText(label)
        b:SetScript("OnEnter", function(self)
            SetBorderColor(self.edges, C.accent[1], C.accent[2], C.accent[3])
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tipTitle, 1, 1, 1)
            GameTooltip:AddLine(tipText, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            SetBorderColor(self.edges, C.line[1], C.line[2], C.line[3])
            GameTooltip:Hide()
        end)
        return b
    end
    f.offOne = SmallButton("Take off", 48, "Take this off", "Moves the item in this slot into your bags.")
    f.offOne:SetPoint("TOPRIGHT", -PAD, -5)
    f.offOne:SetScript("OnClick", function()
        if CysArmory and CysArmory.UnequipSlot and f.invSlot then CysArmory:UnequipSlot(f.invSlot) end
    end)

    local div = f:CreateTexture(nil, "BORDER")
    div:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    div:SetPoint("TOPLEFT", PAD, -HEADER_H)
    div:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    div:SetHeight(1)

    f.empty = MakeText(f, 11, C.dim)
    f.empty:SetPoint("TOP", 0, -(HEADER_H + 12))
    f.empty:SetText("No matching items in your bags")

    f.buttons = {}

    -- Close shortly after the mouse leaves both the slot and the flyout
    f:SetScript("OnUpdate", function(self, elapsed)
        if Over(self) or Over(self.anchor) then
            self.leaveTime = 0
        else
            self.leaveTime = (self.leaveTime or 0) + elapsed
            if self.leaveTime > 0.2 then CysFlyout:Hide() end
        end
    end)
    f:SetScript("OnHide", function(self)
        self.anchor = nil
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    CysFlyout.frame = f
    return f
end

--------------------------------------------------------------------------------
-- Show / hide
--------------------------------------------------------------------------------
local function Populate(f, invSlot, info)
    local list = CollectCandidates(invSlot, info)
    local n = #list

    f.title:SetFormattedText("|cFFFFD100%s|r |cFF777777(%d)|r", _G[info[1]] or info[1], n)
    local canOff = CysArmory and CysArmory.UnequipSlot and true or false
    f.offOne:SetShown(canOff and GetInventoryItemLink("player", invSlot) ~= nil)
    local minW = canOff and 150 or 130
    for i = 1, #f.buttons do f.buttons[i]:Hide() end

    if n == 0 then
        f.empty:Show()
        f:SetSize(max(150, minW), HEADER_H + 40)
        return
    end
    f.empty:Hide()

    local playerLevel = UnitLevel("player") or 1
    local cols = min(n, COLS_MAX)
    local rows = ceil(n / cols)
    local contentW = cols * SIZE + (cols - 1) * GAP
    local width = max(contentW + PAD * 2, minW)
    local xOff = (width - contentW) / 2
    local top = HEADER_H + 8
    f:SetSize(width, top + rows * SIZE + (rows - 1) * GAP + PAD)

    for i = 1, n do
        local c = list[i]
        local b = f.buttons[i]
        if not b then
            b = CreateFlyoutButton(f)
            f.buttons[i] = b
        end
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", xOff + col * (SIZE + GAP), -(top + row * (SIZE + GAP)))
        b.bag, b.slot, b.link = c.bag, c.slot, c.link

        b.icon:SetTexture(c.icon)
        b.icon:SetDesaturated(c.unusable)
        if c.unusable then b.icon:SetVertexColor(1, 0.4, 0.4) else b.icon:SetVertexColor(1, 1, 1) end

        local qc = c.quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[c.quality]
        if qc then
            b.br, b.bg, b.bb = qc.r, qc.g, qc.b
        else
            b.br, b.bg, b.bb = C.line[1], C.line[2], C.line[3]
        end
        SetBorderColor(b.border, b.br, b.bg, b.bb)

        if c.minLevel > 1 then
            b.level:SetText(c.minLevel)
            if c.minLevel > playerLevel then
                b.level:SetTextColor(1, 0.3, 0.3) -- you can't use it yet
            else
                b.level:SetTextColor(C.text[1], C.text[2], C.text[3])
            end
        else
            b.level:SetText("")
        end
        b:Show()
    end
end

function CysFlyout:ShowFor(slotBtn)
    if not self.enabled or CursorHasItem() then return end
    local invSlot = slotBtn:GetID()
    local info = SLOT_INFO[invSlot]
    if not info then return end

    local f = self.frame or CreateFlyoutFrame()
    f.anchor, f.invSlot, f.dir = slotBtn, invSlot, info[2]
    Populate(f, invSlot, info)

    f:ClearAllPoints()
    if f.dir == "RIGHT" then
        f:SetPoint("TOPLEFT", slotBtn, "TOPRIGHT", 6, 4)
    elseif f.dir == "LEFT" then
        f:SetPoint("TOPRIGHT", slotBtn, "TOPLEFT", -6, 4)
    else
        f:SetPoint("BOTTOM", slotBtn, "TOP", 0, 6)
    end
    f.leaveTime = 0
    f:Show()
    f:Raise()
    GameTooltip:Hide() -- the slot's own tooltip would sit right on top of the flyout
end

function CysFlyout:Hide()
    if self.frame then self.frame:Hide() end
end

function CysFlyout:SetEnabled(enabled)
    self.enabled = enabled and true or false
    if not self.enabled then self:Hide() end
end

--------------------------------------------------------------------------------
-- Hooks and events
--------------------------------------------------------------------------------
local function HookSlots()
    for _, name in ipairs(SLOT_BUTTONS) do
        local b = _G[name]
        if b then
            b:HookScript("OnEnter", function(self)
                CysFlyout.hoverSlot = self
                if IsAltKeyDown() then
                    CysFlyout:ShowFor(self)
                elseif CysFlyout.frame and CysFlyout.frame:IsShown() and CysFlyout.frame.anchor ~= self then
                    CysFlyout:Hide()
                end
            end)
            b:HookScript("OnLeave", function(self)
                if CysFlyout.hoverSlot == self then CysFlyout.hoverSlot = nil end
            end)
        end
    end
    if CharacterFrame then
        CharacterFrame:HookScript("OnHide", function() CysFlyout:Hide() end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        HookSlots()
    elseif event == "MODIFIER_STATE_CHANGED" then
        -- Alt pressed while already hovering a slot
        if (arg1 == "LALT" or arg1 == "RALT") and arg2 == 1 and CysFlyout.hoverSlot then
            CysFlyout:ShowFor(CysFlyout.hoverSlot)
        end
    else
        -- gear or bags changed: refresh an open flyout
        local f = CysFlyout.frame
        if f and f:IsShown() and f.anchor then CysFlyout:ShowFor(f.anchor) end
    end
end)
end,
})
