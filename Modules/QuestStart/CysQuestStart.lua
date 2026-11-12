--------------------------------------------------------------------------------
-- Cys's UI - Quest Starter pop-up
--
-- When an item that starts a quest is in your bags (you looted it, or it was there already), a small box pops up
-- with the item: click the icon and the quest opens, ready to accept. Close it with the x to leave that item
-- alone until you log in again. Placed in Layout mode (Quest Starter).
--
-- The box is the game's secure item button ("use this bag slot"), so the click works in combat too. A secure
-- frame can't be shown, hidden or changed during a fight, so a new item that comes in mid-fight shows when the
-- fight ends.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "queststart", name = "Quest Starter Pop-up",
    desc = "A small pop-up when an item that starts a quest is in your bags. Click it to open the quest.",
    open = function() CysUI:OpenConfig("Quest Starter") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Secret = CysUICompat and CysUICompat.Secret or function() return false end

CysUIDB.queststart = CysUIDB.queststart or {}
local db = CysUIDB.queststart
if db.sound == nil then db.sound = true end

local MOVER = "queststart"
local WIDTH, HEIGHT, ICON = 220, 92, 40
local dismissed = {} -- [itemID] = true for this session
local current        -- { bag, slot, itemID }
local pending = false

-- the whole box is the secure button (anything we anchor a secure frame to becomes locked in combat)
local b = CreateFrame("Button", "CysQuestStartPopup", UIParent, "SecureActionButtonTemplate")
b:SetSize(WIDTH, HEIGHT)
b:SetPoint("TOP", UIParent, "TOP", 0, -180)
b:SetFrameStrata("HIGH")
b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
b:SetAttribute("useOnKeyDown", false)
b:SetAttribute("type1", "item")
b:Hide()

local bg = b:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.95)
W.Border(b, 1, T.border, "BORDER")
local strip = b:CreateTexture(nil, "ARTWORK")
strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(2)
strip:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)

local title = W.Text(b, 12, T.accent, "CENTER")
title:SetPoint("TOPLEFT", 8, -8)
title:SetPoint("TOPRIGHT", -24, -8)
title:SetWordWrap(false)

local icon = b:CreateTexture(nil, "ARTWORK")
icon:SetSize(ICON, ICON)
icon:SetPoint("TOP", 0, -26)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local iconEdge = CreateFrame("Frame", nil, b)
iconEdge:SetPoint("TOPLEFT", icon, -1, 1)
iconEdge:SetPoint("BOTTOMRIGHT", icon, 1, -1)
W.Border(iconEdge, 1, T.border, "OVERLAY")
local bang = iconEdge:CreateTexture(nil, "OVERLAY")
bang:SetSize(18, 18)
bang:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 9, -4)
bang:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
local glow = b:CreateTexture(nil, "HIGHLIGHT")
glow:SetAllPoints(icon)
glow:SetColorTexture(1, 1, 1, 0.18)

local hint = W.Text(b, 10, T.dim, "CENTER")
hint:SetPoint("BOTTOM", 0, 8)
hint:SetText("Click the item to start the quest")

-- the x: a plain button inside the box. During a fight it can only fade the box; it closes after the fight.
local close = CreateFrame("Button", nil, b)
close:SetSize(18, 18)
close:SetPoint("TOPRIGHT", -3, -3)
close.text = W.Text(close, 13, { 0.85, 0.3, 0.25 }, "CENTER")
close.text:SetPoint("CENTER")
close.text:SetText("x")
close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.45, 0.4) end)
close:SetScript("OnLeave", function(s) s.text:SetTextColor(0.85, 0.3, 0.25) end)

CUI:RegisterMovable(b, MOVER, "Quest Starter", { point = "TOP", x = 0, y = -180 })

b:SetScript("OnEnter", function(self)
    if not current then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetBagItem, GameTooltip, current.bag, current.slot)
    GameTooltip:Show()
end)
b:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------------------
-- Finding quest starters in your bags
--------------------------------------------------------------------------------
local function QuestInfo(bag, slot)
    local C = C_Container
    if not (C and C.GetContainerItemQuestInfo) then return end
    local ok, a, b2, c = pcall(C.GetContainerItemQuestInfo, bag, slot)
    if not ok then return end
    if type(a) == "table" then return a.questID, a.isActive end
    return b2, c -- older clients: isQuestItem, questID, isActive
end

local function Done(questID)
    local Q = C_QuestLog
    if Q and Q.IsQuestFlaggedCompleted then
        local ok, done = pcall(Q.IsQuestFlaggedCompleted, questID)
        return ok and done
    end
    return false
end

local function Find()
    local last = NUM_BAG_SLOTS or 4
    for bag = 0, last do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and not dismissed[itemID] then
                local questID, active = QuestInfo(bag, slot)
                if questID and not Secret(questID) and not active and not Done(questID) then
                    return { bag = bag, slot = slot, itemID = itemID, icon = info.iconFileID,
                             name = info.itemName or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
                                 or (info.hyperlink and info.hyperlink:match("%[(.-)%]")) or "Quest item" }
                end
            end
        end
    end
end

local function Apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    local found = Find()
    if not found then
        current = nil
        b:SetAttribute("item1", nil)
        if not CUI.layoutMode then b:Hide() end
        return
    end
    local fresh = not current or current.itemID ~= found.itemID
    current = found
    b:SetAttribute("item1", found.bag .. " " .. found.slot)
    icon:SetTexture(found.icon or 134400)
    title:SetText(found.name)
    b:SetAlpha(1)
    b:Show()
    if fresh and db.sound and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then
        pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN)
    end
end

close:SetScript("OnClick", function()
    if current then dismissed[current.itemID] = true end
    if InCombatLockdown() then b:SetAlpha(0); pending = true return end
    Apply() -- the next quest starter, if there is one
end)

-- a right-click on the box also leaves the item alone
b:HookScript("OnClick", function(_, button)
    if button == "RightButton" and current then
        dismissed[current.itemID] = true
        if not InCombatLockdown() then Apply() else b:SetAlpha(0); pending = true end
    end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued = false
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_REGEN_ENABLED" and not pending then return end
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; Apply() end)
end)

if type(CUI.SetLayoutMode) == "function" then
    hooksecurefunc(CUI, "SetLayoutMode", function()
        if InCombatLockdown() then return end
        if CUI.layoutMode then
            if not current then title:SetText("Quest Starter"); icon:SetTexture(134400) end
            b:SetAlpha(1); b:Show()
        else
            Apply()
        end
    end)
end

CUI:RegisterPage("Quest Starter", function(page)
    local width = 480
    W.Header(page, "Quest Starter", width):SetPoint("TOPLEFT", 0, -4)
    W.Checkbox(page, "Play a sound when the pop-up shows", function() return db.sound end,
        function(on) db.sound = on end):SetPoint("TOPLEFT", 4, -34)
    local test = W.Button(page, 150, 22, "Look in my bags now")
    test:SetPoint("TOPLEFT", 4, -70)
    test:SetScript("OnClick", function() wipe(dismissed); Apply() end)
    W.Notes(page, 4, -108, width, "", {
        "When an item that starts a quest is in your bags, a small box shows it. Click the item to open the quest and accept it.",
        "The x (or a right-click on the box) leaves that item alone until you log in again. Look in my bags now brings them back.",
        "Works in combat; a quest item looted during a fight pops up when the fight ends. Move the box in Layout mode (Quest Starter).",
    })
end, function() end)

    end,
})
