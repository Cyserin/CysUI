--------------------------------------------------------------------------------
-- Cys's UI - Trinkets
--
-- Two buttons for your trinket slots. Click one to use that trinket. Point at one (or right-click it) and a
-- list of the trinkets in your bags opens beside it: left-click one to put it in that slot, right-click to put
-- it in the other slot, shift-click to link it.
-- In combat (or while dead) the game won't let you change trinkets, so the swap waits: the trinket shows small
-- in the corner of the slot and goes on as soon as the fight ends. Right-click the slot to cancel it.
-- Settings: /cui -> Trinkets. Move it in /cui layout.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, min, max = math.floor, math.min, math.max
local Plain = CysUICompat and CysUICompat.Plain or function(v) return v end

local TR = {}
CUI.Trinkets = TR

local SLOTS = { 13, 14 }
local function Other(slot) return slot == 13 and 14 or 13 end

local DEFAULTS = {
    open = "hover",     -- hover / click: how the list opens
    layout = "row",     -- row (side by side) / column (stacked)
    size = 34,          -- button size
    useOnly = false,    -- list only trinkets with a Use: effect
    numbers = true,     -- cooldown numbers on the buttons
    -- key13, key14: keys that use each trinket
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.trinkets = CysUIDB.trinkets or {}
    local db = CysUIDB.trinkets
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

--------------------------------------------------------------------------------
-- Items and bags (C_Container on WoW Forever, the old globals elsewhere)
--------------------------------------------------------------------------------
local Cn = C_Container
local NumSlots = (Cn and Cn.GetContainerNumSlots) or GetContainerNumSlots
local BagItemID = (Cn and Cn.GetContainerItemID) or GetContainerItemID
local BagLink = (Cn and Cn.GetContainerItemLink) or GetContainerItemLink
local BagCooldown = (Cn and Cn.GetContainerItemCooldown) or GetContainerItemCooldown
local InstantInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local ItemName = (C_Item and C_Item.GetItemNameByID) or function(id) return (GetItemInfo(id)) end
local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local LAST_BAG = NUM_BAG_SLOTS or 4

local function IsTrinket(id)
    if not id then return false end
    local _, _, _, loc = InstantInfo(id)
    return loc == "INVTYPE_TRINKET"
end

local function HasUse(id) return id and ItemSpell(id) ~= nil end

local function IconOf(id)
    if not id then return end
    local _, _, _, _, icon = InstantInfo(id)
    return icon
end

local function FindInBags(id)
    for bag = 0, LAST_BAG do
        for s = 1, NumSlots(bag) or 0 do
            if BagItemID(bag, s) == id then return bag, s end
        end
    end
end

-- what the list shows for a slot: trinkets in your bags plus the one in the other slot
local items = {}
local function Collect(slot)
    wipe(items)
    local db = DB()
    for bag = 0, LAST_BAG do
        for s = 1, NumSlots(bag) or 0 do
            local id = BagItemID(bag, s)
            if IsTrinket(id) and (not db.useOnly or HasUse(id)) then
                items[#items + 1] = { id = id, bag = bag, slot = s, link = BagLink(bag, s) }
            end
        end
    end
    local other = Other(slot)
    local worn = GetInventoryItemID("player", other)
    if worn and (not db.useOnly or HasUse(worn)) then
        items[#items + 1] = { id = worn, inv = other, link = GetInventoryItemLink("player", other) }
    end
    table.sort(items, function(a, b)
        local ua, ub = HasUse(a.id), HasUse(b.id)
        if ua ~= ub then return ua end
        local na, nb = ItemName(a.id) or "", ItemName(b.id) or ""
        if na ~= nb then return na < nb end
        return a.id < b.id
    end)
    return items
end

--------------------------------------------------------------------------------
-- Swapping, and the combat queue
--------------------------------------------------------------------------------
local queued = {}   -- [slot] = itemID waiting for the fight to end
local slotButtons = {}
local menu

local function Paint() end -- defined with the buttons below

local function CanSwap()
    return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
end

-- put item id into slot now; true when the game was asked
local function SwapNow(id, slot)
    if GetInventoryItemID("player", slot) == id then return true end
    if CursorHasItem() then return false end
    if GetInventoryItemID("player", Other(slot)) == id then
        -- already worn in the other slot: trade places
        PickupInventoryItem(Other(slot))
        PickupInventoryItem(slot)
        if CursorHasItem() then ClearCursor() end
        return true
    end
    if not FindInBags(id) then return false end
    -- the game's own equip: asks first if the trinket would become soulbound
    Equip(id, slot)
    return true
end

function TR.Swap(id, slot)
    if not id then return end
    if CanSwap() then
        queued[slot] = nil
        SwapNow(id, slot)
    else
        queued[slot] = id
        local name = ItemName(id) or "Trinket"
        UIErrorsFrame:AddMessage(format("%s goes on after the fight", name), 1, 0.82, 0)
    end
    Paint()
end

local function RunQueue()
    if not CanSwap() then return end
    local delay = 0
    for _, slot in ipairs(SLOTS) do
        local id = queued[slot]
        if id then
            queued[slot] = nil
            C_Timer.After(delay, function()
                if CanSwap() then SwapNow(id, slot) else queued[slot] = id end
                Paint()
            end)
            delay = delay + 0.4 -- let the first swap settle before the second
        end
    end
    Paint()
end

--------------------------------------------------------------------------------
-- Cooldowns
--------------------------------------------------------------------------------
local function TimeText(left)
    if left >= 3600 then return format("%dh", floor(left / 3600 + 0.5)) end
    if left >= 60 then return format("%dm", floor(left / 60 + 0.5)) end
    return format("%d", floor(left + 0.5))
end

local function SetCD(b, start, duration)
    pcall(b.cd.SetCooldown, b.cd, start or 0, duration or 0)
    start, duration = Plain(start), Plain(duration)
    if start and duration and duration > 1.5 and start > 0 then b.cdEnds = start + duration else b.cdEnds = nil end
end

local function TickText(b)
    if not b.timer then return end
    local left = b.cdEnds and (b.cdEnds - GetTime())
    if DB().numbers and left and left > 0 then b.timer:SetText(TimeText(left)) else b.timer:SetText("") end
end

--------------------------------------------------------------------------------
-- Shared look for a trinket button
--------------------------------------------------------------------------------
local function Dress(b)
    W.Texture(b, "BACKGROUND", T.field):SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetPoint("TOPLEFT", 1, -1)
    b.cd:SetPoint("BOTTOMRIGHT", -1, 1)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.timer = top:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "OUTLINE")
    b.timer:SetPoint("CENTER", 0, 0)
    b.top = top
    b.edges = W.Border(b, 1, T.border, "OVERLAY")
    b:HookScript("OnLeave", function(self) W.SetBorder(self.edges, self.worn and T.glow or T.border) end)
end

--------------------------------------------------------------------------------
-- The list of trinkets
--------------------------------------------------------------------------------
local menuButtons = {}
local hideAt

local function MenuButton(i)
    local b = CreateFrame("Button", nil, menu)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Dress(b)
    b:SetScript("OnClick", function(self, mouse)
        local it = self.item
        if not it then return end
        if IsShiftKeyDown() and it.link then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(it.link) end
            return
        end
        local slot = menu.slot
        if mouse == "RightButton" then slot = Other(slot) end
        TR.Swap(it.id, slot)
        menu:Hide()
    end)
    b:SetScript("OnEnter", function(self)
        W.SetBorder(self.edges, T.glow)
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if it.inv then GameTooltip:SetInventoryItem("player", it.inv)
        elseif it.bag then GameTooltip:SetBagItem(it.bag, it.slot) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("Left-click: Trinket %d   Right-click: Trinket %d", menu.slot - 12, Other(menu.slot) - 12), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    menuButtons[i] = b
    return b
end

local function BuildMenu()
    if menu then return end
    menu = CreateFrame("Frame", "CysTrinketMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    W.Texture(menu, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.92 }):SetAllPoints()
    W.Border(menu, 1, T.border, "BORDER")
    menu.empty = W.Text(menu, 11, T.dim, "CENTER")
    menu.empty:SetPoint("CENTER")
    menu.empty:SetText("No other trinkets in your bags")
    menu:Hide()
    menu:SetScript("OnUpdate", function(self)
        -- close a moment after the mouse leaves both the list and the slot buttons
        if self:IsMouseOver() or (TR.bar and TR.bar:IsMouseOver()) then hideAt = nil return end
        if DB().open == "click" and not hideAt then hideAt = GetTime() + 1.5 end
        hideAt = hideAt or (GetTime() + 0.35)
        if GetTime() >= hideAt then self:Hide() end
    end)
    menu:SetScript("OnHide", function() hideAt = nil end)
end

local function PaintMenu()
    if not (menu and menu:IsShown()) then return end
    local db = DB()
    local list = Collect(menu.slot)
    local S, GAP, PAD = db.size, 3, 4
    local cols, rowsN = 1, max(1, #list) -- one straight column, first trinket next to the button
    for i, it in ipairs(list) do
        local b = menuButtons[i] or MenuButton(i)
        b:SetSize(S, S)
        b:ClearAllPoints()
        if menu.up then b:SetPoint("BOTTOMLEFT", PAD, PAD + (i - 1) * (S + GAP))
        else b:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * (S + GAP)) end
        b.item = it
        b.icon:SetTexture(IconOf(it.id))
        b.icon:SetDesaturated(not HasUse(it.id))
        b.worn = it.inv ~= nil -- the one in your other slot: outlined
        W.SetBorder(b.edges, b.worn and T.glow or T.border)
        if it.inv then SetCD(b, GetInventoryItemCooldown("player", it.inv))
        else SetCD(b, BagCooldown(it.bag, it.slot)) end
        TickText(b)
        b:Show()
    end
    for i = #list + 1, #menuButtons do menuButtons[i]:Hide() end
    menu.empty:SetShown(#list == 0)
    if #list == 0 then menu:SetSize(190, 30)
    else menu:SetSize(PAD * 2 + cols * S + (cols - 1) * GAP, PAD * 2 + rowsN * S + (rowsN - 1) * GAP) end
end

function TR.OpenMenu(slot, anchor)
    BuildMenu()
    menu.slot = slot
    menu:ClearAllPoints()
    -- one straight column going up from the trinket you point at (down when the buttons sit near the top
    -- of the screen), lined up over that button
    local _, y = anchor:GetCenter()
    menu.up = not (y and y > UIParent:GetHeight() * 0.75)
    if menu.up then menu:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    else menu:SetPoint("TOP", anchor, "BOTTOM", 0, -2) end
    hideAt = nil
    menu:Show()
    PaintMenu()
end

--------------------------------------------------------------------------------
-- The two slot buttons
--------------------------------------------------------------------------------
local bar, keyOwner
local pendingLayout = false

Paint = function()
    for _, slot in ipairs(SLOTS) do
        local b = slotButtons[slot]
        if b then
            local id = GetInventoryItemID("player", slot)
            b.icon:SetTexture(GetInventoryItemTexture("player", slot) or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket")
            b.icon:SetDesaturated(id ~= nil and not HasUse(id))
            SetCD(b, GetInventoryItemCooldown("player", slot))
            TickText(b)
            local q = queued[slot]
            b.queued:SetShown(q ~= nil)
            if q then b.queued.icon:SetTexture(IconOf(q)) end
        end
    end
    PaintMenu()
end

local function ApplyKeys()
    if not keyOwner then return end
    if InCombatLockdown() then pendingLayout = true return end
    local db = DB()
    ClearOverrideBindings(keyOwner)
    for _, slot in ipairs(SLOTS) do
        local key = db["key" .. slot]
        if key and key ~= "" then SetOverrideBindingClick(keyOwner, true, key, "CysTrinketSlot" .. slot, "LeftButton") end
        local b = slotButtons[slot]
        if b then b.hotkey:SetText(key and GetBindingText(key, true) or "") end
    end
end

function TR.Layout()
    if not bar then return end
    if InCombatLockdown() then pendingLayout = true return end
    pendingLayout = false
    local db = DB()
    local S, GAP, PAD = db.size, 4, 4
    local stacked = db.layout == "column"
    if stacked then bar:SetSize(S + PAD * 2, S * 2 + GAP + PAD * 2)
    else bar:SetSize(S * 2 + GAP + PAD * 2, S + PAD * 2) end
    for i, slot in ipairs(SLOTS) do
        local b = slotButtons[slot]
        b:SetSize(S, S)
        b:ClearAllPoints()
        if stacked then b:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * (S + GAP))
        else b:SetPoint("TOPLEFT", PAD + (i - 1) * (S + GAP), -PAD) end
        b.queued:SetSize(max(12, floor(S * 0.45)), max(12, floor(S * 0.45)))
    end
    ApplyKeys()
end

local function SlotButton(slot)
    local b = CreateFrame("Button", "CysTrinketSlot" .. slot, bar, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    -- left button uses the trinket (any modifier, so Shift/Ctrl/Alt keys still work); right does nothing secure
    b:SetAttribute("*type1", "macro")
    b:SetAttribute("*macrotext1", "/use " .. slot)
    Dress(b)
    b.hotkey = b.top:CreateFontString(nil, "OVERLAY")
    b.hotkey:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
    b.hotkey:SetPoint("TOPRIGHT", -2, -2)
    b.hotkey:SetTextColor(0.8, 0.8, 0.8)
    -- the trinket waiting for the fight to end, small in the corner
    local q = CreateFrame("Frame", nil, b.top)
    q:SetPoint("BOTTOMRIGHT", 3, -3)
    W.Texture(q, "BACKGROUND", T.field):SetAllPoints()
    q.icon = q:CreateTexture(nil, "ARTWORK")
    q.icon:SetPoint("TOPLEFT", 1, -1); q.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    q.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.Border(q, 1, T.glow, "OVERLAY")
    q:Hide()
    b.queued = q

    b:HookScript("OnClick", function(self, mouse)
        if mouse ~= "RightButton" then return end
        if queued[slot] then
            queued[slot] = nil
            UIErrorsFrame:AddMessage("Trinket swap canceled", 1, 0.82, 0)
            Paint()
        elseif menu and menu:IsShown() and menu.slot == slot and DB().open == "click" then
            menu:Hide()
        else
            TR.OpenMenu(slot, self)
        end
    end)
    b:SetScript("OnEnter", function(self)
        W.SetBorder(self.edges, T.glow)
        if DB().open == "hover" then TR.OpenMenu(slot, self) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GetInventoryItemID("player", slot) then GameTooltip:SetInventoryItem("player", slot)
        else GameTooltip:SetText(format("Trinket %d (empty)", slot - 12), 1, 1, 1) end
        if queued[slot] then
            GameTooltip:AddLine(format("Goes on after the fight: %s", ItemName(queued[slot]) or "?"), T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Right-click to cancel", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    slotButtons[slot] = b
end

local function Build()
    if bar then return end
    bar = CreateFrame("Frame", "CysTrinketBar", UIParent)
    TR.bar = bar
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    W.Texture(bar, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
    W.Border(bar, 1, T.line, "BORDER")
    for _, slot in ipairs(SLOTS) do SlotButton(slot) end
    keyOwner = CreateFrame("Frame")
    TR.Layout()
    CUI:RegisterMovable(bar, "trinkets", "Trinkets", { point = "CENTER", x = 0, y = -220 })

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
                         "PLAYER_REGEN_ENABLED", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
            if pendingLayout then TR.Layout() end
            RunQueue()
        end
        Paint()
    end)
    C_Timer.NewTicker(0.25, function()
        for _, b in pairs(slotButtons) do TickText(b) end
        if menu and menu:IsShown() then for _, b in ipairs(menuButtons) do if b:IsShown() then TickText(b) end end end
    end)
    Paint()
end

function TR.Enable()
    DB()
    if InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); Build() end)
    else
        Build()
    end
end

CUI:RegisterModule({
    key = "trinkets",
    name = "Trinkets",
    addon = "CysUI",
    desc = "Buttons for your two trinkets: click to use, point at one to swap in another from your bags. Swaps made in combat go on after the fight.",
    onEnable = TR.Enable,
    open = function() CUI:OpenConfig("Trinkets") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local function WithModifiers(key)
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    return mods .. key
end

local function KeyPicker(page, db, field, title, y)
    local lbl = W.Text(page, 11, T.accent)
    lbl:SetPoint("TOPLEFT", 4, y - 5)
    lbl:SetText(title)
    local bind = W.Button(page, 170, 22, "", true)
    bind:SetPoint("TOPLEFT", 90, y)
    local function Show() bind:SetLabel(db[field] and GetBindingText(db[field]) or "Click to set a key") end
    Show()
    local clear = W.Button(page, 70, 22, "Clear")
    clear:SetPoint("LEFT", bind, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function() db[field] = nil; ApplyKeys(); Show() end)
    local catcher = CreateFrame("Frame", nil, bind)
    catcher:SetAllPoints()
    catcher:Hide()
    local function Done(key)
        catcher:Hide()
        catcher:EnableKeyboard(false)
        if key then db[field] = key; ApplyKeys() end
        Show()
    end
    catcher:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then Done(nil) return end
        if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then return end
        Done(WithModifiers(key))
    end)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function(_, mouse)
        if MOUSE_KEYS[mouse] then Done(WithModifiers(MOUSE_KEYS[mouse])) end
    end)
    bind:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        bind:SetLabel("Press a key... (Esc cancels)")
        catcher:Show()
        catcher:EnableKeyboard(true)
    end)
end

CUI:RegisterPage("Trinkets", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Trinkets", width):SetPoint("TOPLEFT", 0, -4)
    local y = -40
    W.Dropdown(page, 260, { { "hover", "List opens: On mouseover" }, { "click", "List opens: On right-click" } },
        function() return db.open end, function(v) db.open = v end):SetPoint("TOPLEFT", 4, y)
    y = y - 36
    W.Dropdown(page, 260, { { "row", "Buttons: Side by side" }, { "column", "Buttons: Stacked" } },
        function() return db.layout end, function(v) db.layout = v; TR.Layout() end):SetPoint("TOPLEFT", 4, y)
    y = y - 40
    W.Stepper(page, "Button size", function() return db.size end, function(v) db.size = v; TR.Layout(); PaintMenu() end, 24, 48, 2)
        :SetPoint("TOPLEFT", 4, y)
    y = y - 36
    y = y - 2
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on; Paint() end)
        c:SetPoint("TOPLEFT", 4, y); y = y - 26
    end
    Check("Only list trinkets with a Use effect", "useOnly")
    Check("Show cooldown numbers", "numbers")
    y = y - 10
    KeyPicker(page, db, "key13", "Trinket 1 key", y); y = y - 30
    KeyPicker(page, db, "key14", "Trinket 2 key", y); y = y - 40

    W.Notes(page, 4, y, width, "", {
        "Left-click a trinket button to use it.",
        "In the list: left-click puts the trinket in the slot you opened it from, right-click puts it in the other slot, shift-click links it in chat. Your other worn trinket is outlined; trinkets with no Use effect show grey.",
        "In combat or while dead the swap waits: the trinket shows small in the slot's corner and goes on when the fight ends. Right-click the slot to cancel it.",
        "A trinket that isn't soulbound yet asks before it goes on, like the game does.",
        "Move the buttons in /cui layout. Turn off Forever Trinket Menu if you use this, so both don't swap at once.",
    })
end)
