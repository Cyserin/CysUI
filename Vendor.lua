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
    local show = V.merchantOpen and CysUIDB.vendor.showButton
    local junk = show and #ScanJunk() or 0
    for _, b in pairs(buttons) do
        b:SetShown(show and true or false)
        b:SetAlpha(junk > 0 and 1 or 0.5) -- dimmed (but still hoverable) when there's nothing to sell
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
function V.Enable()
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
    Toggle("Show a Sell Junk button when you're at a vendor", "showButton", -34)
    Toggle("Automatically sell junk when you open a vendor", "autoSell", -64)
    Toggle("Automatically repair your gear when you open a vendor", "autoRepair", -94)

    local note = W.Notes(page, 4, -134, width, "", {
            { "Junk", "means grey (poor quality) items that a vendor will buy." },
            "The Sell Junk button shows up on the vendor window and in Cys's Bags.",
            "Auto-repair pays with your own gold and tells you the cost in chat.",
            "Turn the whole Vendor module off under Modules if you'd rather do it by hand.",
        })
end)
