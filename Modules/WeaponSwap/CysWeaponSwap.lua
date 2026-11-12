--------------------------------------------------------------------------------
-- Cys's UI - Weapon Swap
--
-- Two weapon sets (for example a one-hander + shield and a two-hander) and one key that swaps between
-- them. Weapons only: main hand and off hand. Works in combat.
--
-- How: a secure button runs the game's own /equipslot lines. Each press, a secure snippet puts the other
-- set's lines into the button just before it runs. Out of combat the button is told which set you are
-- wearing, so the next press always goes to the other one.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local WS = {}
CUI.WeaponSwap = WS

local MH, OH = 16, 17
local MH_TYPES = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OH_TYPES = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local function DB()
    CysUIDB.weaponswap = CysUIDB.weaponswap or {}
    local db = CysUIDB.weaponswap
    db.a = db.a or {}
    db.b = db.b or {}
    return db
end

local function ItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (f and id) then return end
    local _, _, _, equipLoc, icon = f(id)
    return equipLoc, icon
end

local function IsTwoHand(id) return id and ItemInfo(id) == "INVTYPE_2HWEAPON" end

local button, keyOwner
local pending = false

--------------------------------------------------------------------------------
-- Secure button
--------------------------------------------------------------------------------
local function MacroFor(set)
    if not set.mh then return "" end
    local text = format("/equipslot %d item:%d", MH, set.mh)
    if set.oh and not IsTwoHand(set.mh) then text = text .. format("\n/equipslot %d item:%d", OH, set.oh) end
    return text
end

-- out of combat: hand the button both sets and which one comes next
function WS:Apply()
    if not button then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local db = DB()
    button:SetAttribute("cys-macro-a", MacroFor(db.a))
    button:SetAttribute("cys-macro-b", MacroFor(db.b))
    local worn = GetInventoryItemID("player", MH)
    local nxt = "a"
    if worn and worn == db.a.mh and db.b.mh then nxt = "b" end
    button:SetAttribute("cys-next", nxt)

    ClearOverrideBindings(keyOwner)
    if db.key and db.key ~= "" then SetOverrideBindingClick(keyOwner, true, db.key, "CysWeaponSwapButton", "LeftButton") end
end

local PRE_CLICK = [=[
    local nxt = self:GetAttribute("cys-next") or "a"
    local text = self:GetAttribute("cys-macro-" .. nxt)
    if not text or text == "" then
        nxt = nxt == "a" and "b" or "a"
        text = self:GetAttribute("cys-macro-" .. nxt)
        if not text or text == "" then return false end
    end
    self:SetAttribute("macrotext", text)
    self:SetAttribute("cys-next", nxt == "a" and "b" or "a")
]=]

local function Build()
    button = CreateFrame("Button", "CysWeaponSwapButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -50, -50) -- off screen; only the key clicks it
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false) -- registered for key up only, so it must act on up
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    local header = CreateFrame("Frame", "CysWeaponSwapHeader", UIParent, "SecureHandlerBaseTemplate")
    SecureHandlerWrapScript(button, "OnClick", header, PRE_CLICK)

    keyOwner = CreateFrame("Frame")
    keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
    keyOwner:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    keyOwner:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_REGEN_ENABLED" or pending or slot == MH then WS:Apply() end
    end)
    WS:Apply()
    WS.ShowBox()
end

function WS.Enable()
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
    key = "weaponswap",
    name = "Weapon Swap",
    addon = "CysUI",
    desc = "Two weapon sets and one key that swaps between them, in combat too (for example sword and shield / two-hander).",
    onEnable = WS.Enable,
    open = function() CUI:OpenConfig("Weapon Swap") end,
})

--------------------------------------------------------------------------------
-- On-screen box: both sets, the worn one outlined in gold; fill and empty them right there
--------------------------------------------------------------------------------
local BuildBox -- defined after Slot

function WS.ShowBox()
    local on = DB().box and true or false
    if on and not box and BuildBox then BuildBox() end
    if box then box:SetShown(on) end
end

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

-- every weapon slot (settings page and the on-screen box) repaints together
local allSlots = {}
local box
function WS.PaintAll()
    for _, s in ipairs(allSlots) do s:Paint() end
    if box then box:PaintWorn() end
end

-- a weapon slot: drop a weapon on it (or click while holding one), right-click to empty
local function Slot(page, set, field, label, size)
    local paintAll = WS.PaintAll
    local b = CreateFrame("Button", nil, page)
    b:SetSize(size or 40, size or 40)
    allSlots[#allSlots + 1] = b
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    W.Texture(b, "BACKGROUND", T.field):SetAllPoints()
    b.edges = W.Border(b, 1, T.border, "BORDER")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.empty = W.Text(b, 9, T.dim, "CENTER")
    b.empty:SetPoint("CENTER")
    b.empty:SetText(label)

    function b:Paint()
        local id = set[field]
        local _, icon = ItemInfo(id)
        if id and icon then
            self.icon:SetTexture(icon); self.icon:Show(); self.empty:Hide()
        else
            self.icon:Hide(); self.empty:Show()
        end
        -- an off hand beside a two-hander cannot be used
        local blocked = field == "oh" and IsTwoHand(set.mh)
        self:SetAlpha(blocked and 0.35 or 1)
    end

    local function Take()
        local kind, id = GetCursorInfo()
        if kind ~= "item" or not id then return false end
        local loc = ItemInfo(id)
        local ok = (field == "mh" and MH_TYPES[loc]) or (field == "oh" and OH_TYPES[loc])
        if not ok then
            UIErrorsFrame:AddMessage(field == "mh" and "That can't go in the main hand." or "That can't go in the off hand.", 1, 0.3, 0.3)
            return true
        end
        set[field] = id
        if field == "mh" and loc == "INVTYPE_2HWEAPON" then set.oh = nil end
        ClearCursor()
        paintAll()
        WS:Apply()
        return true
    end
    b:SetScript("OnReceiveDrag", Take)
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            set[field] = nil
            paintAll()
            WS:Apply()
        else
            Take()
        end
    end)
    b:SetScript("OnEnter", function(self)
        W.SetBorder(self.edges, T.glow)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if set[field] then
            GameTooltip:SetItemByID(set[field])
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click to empty this slot", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(label, T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Drop a weapon from your bags here", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) W.SetBorder(self.edges, T.border); GameTooltip:Hide() end)
    return b
end

BuildBox = function()
    local db = DB()
    local S, GAP = 30, 4
    local f = CreateFrame("Frame", "CysWeaponSwapBox", UIParent)
    box = f
    f:SetSize(8 + (S * 2 + GAP) * 2 + 14 + 8, S + 24)
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
    W.Border(f, 1, T.line, "BORDER")
    local groups = {}
    for n, key in ipairs({ "a", "b" }) do
        local g = CreateFrame("Frame", nil, f)
        g:SetSize(S * 2 + GAP + 6, S + 6)
        g:SetPoint("BOTTOMLEFT", 5 + (n - 1) * (S * 2 + GAP + 14), 5)
        g.edges = W.Border(g, 1, T.border, "ARTWORK")
        g.set = db[key]
        local lbl = W.Text(f, 9, T.dim)
        lbl:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 2, 2)
        lbl:SetText("Set " .. n)
        g.lbl = lbl
        local mh = Slot(g, db[key], "mh", "Main", S)
        mh:SetPoint("LEFT", 3, 0)
        local oh = Slot(g, db[key], "oh", "Off", S)
        oh:SetPoint("LEFT", mh, "RIGHT", GAP, 0)
        groups[n] = g
    end
    function f:PaintWorn()
        local worn = GetInventoryItemID("player", MH)
        for _, g in ipairs(groups) do
            local on = worn and g.set.mh == worn
            W.ShowBorder(g.edges, on and true or false)
            local c = on and T.accent or T.dim
            g.lbl:SetTextColor(c[1], c[2], c[3])
        end
    end
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:SetScript("OnEvent", function(self) self:PaintWorn() end)
    CUI:RegisterMovable(f, "weaponswap", "Weapon Swap", { point = "CENTER", x = 0, y = -260 })
    WS.PaintAll()
end

CUI:RegisterPage("Weapon Swap", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Weapon Swap", width):SetPoint("TOPLEFT", 0, -4)

    -- key
    local keyLabel = W.Text(page, 11, T.accent)
    keyLabel:SetPoint("TOPLEFT", 4, -40)
    keyLabel:SetText("Key:")
    local bind = W.Button(page, 170, 22, "", true)
    bind:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    local function ShowKey() bind:SetLabel(db.key and GetBindingText(db.key) or "Click to set a key") end
    ShowKey()
    local clearKey = W.Button(page, 70, 22, "Clear")
    clearKey:SetPoint("LEFT", bind, "RIGHT", 8, 0)
    clearKey:SetScript("OnClick", function() db.key = nil; WS:Apply(); ShowKey() end)
    local catcher = CreateFrame("Frame", nil, bind)
    catcher:SetAllPoints()
    catcher:Hide()
    local function Done(key)
        catcher:Hide()
        catcher:EnableKeyboard(false)
        if key then db.key = key; WS:Apply() end
        ShowKey()
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

    -- the two sets
    local PaintAll = WS.PaintAll
    local function SetRow(y, title, set)
        local t = W.Text(page, 12, T.accent)
        t:SetPoint("TOPLEFT", 4, y)
        t:SetText(title)
        local mh = Slot(page, set, "mh", "Main")
        mh:SetPoint("TOPLEFT", 4, y - 20)
        local oh = Slot(page, set, "oh", "Off")
        oh:SetPoint("LEFT", mh, "RIGHT", 8, 0)
        local wear = W.Button(page, 150, 22, "Use what I'm wearing")
        wear:SetPoint("LEFT", oh, "RIGHT", 16, 0)
        wear:SetScript("OnClick", function()
            set.mh = GetInventoryItemID("player", MH)
            set.oh = not IsTwoHand(set.mh) and GetInventoryItemID("player", OH) or nil
            PaintAll()
            WS:Apply()
        end)
        local clear = W.Button(page, 60, 22, "Clear")
        clear:SetPoint("LEFT", wear, "RIGHT", 8, 0)
        clear:SetScript("OnClick", function() set.mh, set.oh = nil, nil; PaintAll(); WS:Apply() end)
    end
    SetRow(-78, "Set 1", db.a)
    SetRow(-150, "Set 2", db.b)
    PaintAll()

    local bx = W.Checkbox(page, "Show the weapon box on screen (move it in Layout mode)", function() return db.box end,
        function(on) db.box = on; WS.ShowBox() end)
    bx:SetPoint("TOPLEFT", 4, -218)

    W.Notes(page, 4, -256, width, "", {
        "Fill each set: put on the weapons and click Use what I'm wearing, or drop weapons from your bags on the slots. Right-click a slot to empty it.",
        "Leave the off hand empty for a two-hander. Swapping to a two-hander needs a free bag slot for your shield or off-hand.",
        "Each press of the key puts on the other set. Works in combat. Weapons only (main and off hand).",
        "Two copies of the same one-hander (one in each hand) may not swap cleanly.",
        "The weapon box shows both sets with the one you are wearing outlined in gold; drop weapons on it or right-click to empty a slot, same as here.",
    })
end)
