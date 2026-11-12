--------------------------------------------------------------------------------
-- Cys's UI - Vendor module
--
--   * "Sell Junk" button on the vendor window
--   * optional auto-sell of junk (grey items) when a vendor opens
--   * auto-repair when a vendor that can repair opens (uses your own gold)
--
-- Settings live in CysUIDB.vendor and on the Vendor page of /cui.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format = string.format

local V = {}
CUI.Vendor = V

--------------------------------------------------------------------------------
-- API compatibility
--------------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local UseItem = (CC and CC.UseContainerItem) or UseContainerItem

-- returns link, count, quality
local function GetSlot(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info then return info.hyperlink, info.stackCount, info.quality end
        return
    end
    local _, count, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
    return link, count, quality
end

--------------------------------------------------------------------------------
-- Junk
--------------------------------------------------------------------------------
-- grey items a vendor will actually buy (sell price > 0)
local function ScanJunk()
    local list, value = {}, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local link, count, quality = GetSlot(bag, slot)
            if link and quality == 0 then
                local sellPrice = select(11, GetItemInfo(link))
                if sellPrice and sellPrice > 0 then
                    list[#list + 1] = { bag = bag, slot = slot }
                    value = value + sellPrice * (count or 1)
                end
            end
        end
    end
    return list, value
end

local selling = false

-- Sells every junk item, one every 0.05s. `silent` hides the "nothing to sell" message
-- (used by auto-sell). onDone runs afterwards (auto-repair waits for the money).
function V:SellJunk(onDone, silent)
    if not V.merchantOpen then
        if not silent then CUI:Print("Open a vendor first.") end
        return
    end
    if selling then return end
    local list, value = ScanJunk()
    if #list == 0 then
        if not silent then CUI:Print("No junk to sell.") end
        if onDone then onDone() end
        return
    end
    selling = true
    local sold = 0
    C_Timer.NewTicker(0.05, function(ticker)
        if V.merchantOpen and sold < #list then
            sold = sold + 1
            UseItem(list[sold].bag, list[sold].slot)
        end
        if sold >= #list or not V.merchantOpen then
            ticker:Cancel()
            selling = false
            CUI:Print(format("Sold %d junk item%s for %s.", sold, sold == 1 and "" or "s",
                GetCoinTextureString(sold == #list and value or 0)))
            if onDone then onDone() end
        end
    end, #list + 1)
end

--------------------------------------------------------------------------------
-- Repair
--------------------------------------------------------------------------------
function V:Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if GetMoney() >= cost then
        RepairAllItems()
        CUI:Print("Repaired your gear for " .. GetCoinTextureString(cost) .. ".")
    else
        CUI:Print("|cFFFF4040Not enough gold to repair|r (" .. GetCoinTextureString(cost) .. " needed).")
    end
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------
local buttons = {}

local function WireButton(b)
    b:SetScript("OnClick", function() V:SellJunk() end)
    b:HookScript("OnEnter", function(self)
        local list, value = ScanJunk()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Sell Junk", 1, 1, 1)
        if #list > 0 then
            GameTooltip:AddLine(format("%d item%s worth %s", #list, #list == 1 and "" or "s",
                GetCoinTextureString(value)), T.accent[1], T.accent[2], T.accent[3])
        else
            GameTooltip:AddLine("No junk to sell.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EnsureButtons()
    if MerchantFrame and not buttons.merchant then
        local b = W.Button(MerchantFrame, 74, 20, "Sell Junk")
        b:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -64, -30)
        WireButton(b)
        buttons.merchant = b
    end
end

local function UpdateButtons()
    -- with auto-sell on the junk is gone as soon as the vendor opens, so the button has nothing to do
    local show = V.merchantOpen and CysUIDB.vendor.showButton and not CysUIDB.vendor.autoSell
    local junk = show and #ScanJunk() or 0
    for _, b in pairs(buttons) do
        b:SetShown(show and true or false)
        b:SetAlpha(junk > 0 and 1 or 0.5) -- dimmed (but still hoverable) when there's nothing to sell
    end
end

--------------------------------------------------------------------------------
-- Quest rewards: a gold coin on the choice that sells for the most
--------------------------------------------------------------------------------
local coins = {}
local function HideCoins() for _, c in pairs(coins) do c:Hide() end end

local function MarkBestReward(retry)
    HideCoins()
    if CysUIDB.vendor.questCoin == false then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return end
    local best, bestValue, missing = nil, 0, false
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local _, _, count = GetQuestItemInfo("choice", i)
        local price = link and select(11, GetItemInfo(link))
        if link and price == nil then missing = true end
        local value = (price or 0) * math.max(count or 1, 1)
        if value > bestValue then best, bestValue = i, value end
    end
    if missing and not retry then -- item info not cached yet: try again in a moment
        C_Timer.After(0.4, function() MarkBestReward(true) end)
    end
    if not best then return end
    local rf = QuestInfoRewardsFrame
    for _, btn in ipairs(rf and rf.RewardButtons or {}) do
        if btn.type == "choice" and btn:GetID() == best and btn:IsShown() then
            local c = coins[btn]
            if not c then
                c = btn:CreateTexture(nil, "OVERLAY", nil, 7)
                c:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
                c:SetSize(16, 16)
                local icon = btn.Icon or _G[(btn:GetName() or "") .. "IconTexture"]
                c:SetPoint("TOPLEFT", icon or btn, "TOPLEFT", -4, 4)
                coins[btn] = c
                btn:HookScript("OnEnter", function()
                    if c:IsShown() and GameTooltip:IsOwned(btn) then
                        GameTooltip:AddLine("Sells for the most of these rewards", 1, 0.82, 0)
                        GameTooltip:Show()
                    end
                end)
            end
            c:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
function V.Enable()
    local q = CreateFrame("Frame")
    q:RegisterEvent("QUEST_COMPLETE")
    q:RegisterEvent("QUEST_FINISHED")
    q:SetScript("OnEvent", function(_, event)
        if event == "QUEST_COMPLETE" then
            C_Timer.After(0.05, function() MarkBestReward() end) -- after the window lays out its buttons
        else
            HideCoins()
        end
    end)

    local f = CreateFrame("Frame")
    f:RegisterEvent("MERCHANT_SHOW")
    f:RegisterEvent("MERCHANT_CLOSED")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            V.merchantOpen = true
            EnsureButtons()
            UpdateButtons()
            local db = CysUIDB.vendor
            if db.autoSell then
                V:SellJunk(function() if db.autoRepair then V:Repair() end end, true)
            elseif db.autoRepair then
                V:Repair()
            end
        elseif event == "MERCHANT_CLOSED" then
            V.merchantOpen = false
            UpdateButtons()
        elseif V.merchantOpen then
            EnsureButtons() -- the bags window may have been created after the vendor opened
            UpdateButtons()
        end
    end)
end

--------------------------------------------------------------------------------
-- Known recipes (and anything else the tooltip calls "Already known") at vendors:
-- the item and its name are dimmed and a green "Known" tag sits in the corner. Visual only.
--------------------------------------------------------------------------------
local KNOWN = ITEM_SPELL_KNOWN or "Already known"
local tags = {}
local function IsKnown(index)
    if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return false end
    local data = C_TooltipInfo.GetMerchantItem(index)
    if not (data and data.lines) then return false end
    for _, line in ipairs(data.lines) do
        if line.leftText == KNOWN then return true end
    end
    return false
end

local recheck = false
function V.MarkKnown()
    local on = CysUIDB.vendor.markKnown ~= false and CUI:IsModuleEnabled("vendor")
    local per = MERCHANT_ITEMS_PER_PAGE or 10
    local page = (MerchantFrame and MerchantFrame.page) or 1
    local tab = MerchantFrame and PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(MerchantFrame) or 1
    local total = GetMerchantNumItems and GetMerchantNumItems() or 0
    local missing = false
    for i = 1, 12 do
        local cell = _G["MerchantItem" .. i]
        if cell then
            local known = false
            if on and tab == 1 and i <= per then
                local index = (page - 1) * per + i
                if index <= total then
                    local ok, k = pcall(IsKnown, index)
                    known = ok and k or false
                    if ok and not k and GetMerchantItemLink and not GetMerchantItemLink(index) then missing = true end
                end
            end
            local tag = tags[i]
            if known and not tag then
                tag = W.Text(cell, 10, T.green, "RIGHT")
                tag:SetPoint("TOPRIGHT", -4, -3)
                tag:SetText("Known")
                tags[i] = tag
            end
            if tag then tag:SetShown(known) end
            local ib = _G["MerchantItem" .. i .. "ItemButton"]
            local nm = _G["MerchantItem" .. i .. "Name"]
            if ib then ib:SetAlpha(known and 0.4 or 1) end
            if nm then nm:SetAlpha(known and 0.5 or 1) end
        end
    end
    -- item data still loading: look again once shortly after
    if missing and not recheck then
        recheck = true
        C_Timer.After(0.6, function() recheck = false; pcall(V.MarkKnown) end)
    end
end
if hooksecurefunc and MerchantFrame_Update then
    hooksecurefunc("MerchantFrame_Update", function() pcall(V.MarkKnown) end)
end

CUI:RegisterModule({
    key = "vendor",
    name = "Vendor",
    addon = "CysUI",
    desc = "Sell Junk button, optional auto-sell of grey items, and auto-repair at vendors.",
    onEnable = V.Enable,
    open = function() CUI:OpenConfig("Vendor") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Vendor", function(page)
    local width = 480
    local header = W.Header(page, "Vendors", width)
    header:SetPoint("TOPLEFT", 0, -4)

    local db = CysUIDB.vendor
    local function Toggle(label, key, y)
        local cb = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        cb:SetPoint("TOPLEFT", 4, y)
        return cb
    end
    Toggle("Show a Sell Junk button at vendors (hidden while auto-sell is on)", "showButton", -34)
    Toggle("Automatically sell junk when you open a vendor", "autoSell", -64)
    Toggle("Automatically repair your gear when you open a vendor", "autoRepair", -94)
    local coin = W.Checkbox(page, "Mark the quest reward that sells for the most with a gold coin",
        function() return db.questCoin ~= false end, function(on) db.questCoin = on end)
    coin:SetPoint("TOPLEFT", 4, -124)
    local known = W.Checkbox(page, "Dim recipes you already know and tag them Known",
        function() return db.markKnown ~= false end,
        function(on) db.markKnown = on; if MerchantFrame and MerchantFrame:IsShown() then pcall(V.MarkKnown) end end)
    known:SetPoint("TOPLEFT", 4, -154)

    local note = W.Notes(page, 4, -194, width, "", {
            { "Junk", "means grey (poor quality) items that a vendor will buy." },
            "The Sell Junk button shows up on the vendor window and in Cys's Bags.",
            "Auto-repair pays with your own gold and tells you the cost in chat.",
            "The gold coin only shows when a quest lets you pick one of several rewards.",
            "Known: recipes, plans and anything else the game calls Already known are dimmed on the vendor, so the ones you can still learn stand out.",
            "Turn the whole Vendor module off under Modules if you'd rather do it by hand.",
        })
end)
