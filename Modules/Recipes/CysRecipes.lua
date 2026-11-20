--------------------------------------------------------------------------------
-- Cys's UI - Tracked Recipes (WoW Forever)
--
-- Tick Track Recipe in a profession window and a small window lists what that recipe needs: each material
-- with how many you carry and how many you need (green when you have enough), and how many you can make now.
-- Set how many you want to make with - and + and the counts follow. Shift-click a material to search the
-- Auction House (or link it in chat); with Cys's Auction House the cost of what you are missing shows too.
-- Click a recipe's name to open it in the profession window, Shift-click it to stop tracking: both clicks are
-- handed to the game's own (hidden) tracker line for that recipe, so the game does them itself (no taint).
-- A material you can craft yourself (and still need) lists its own materials under it, two levels deep
-- (Bronze Bar -> Copper Bar + Tin Bar -> ores). What you can craft is learned from your profession windows:
-- open each profession once. x on a recipe opens the game's own menu for it, with Untrack Recipe.
-- The window shows only while you track a recipe.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "recipes", name = "Tracked Recipes", foreverOnly = true,
    desc = "Recipes you track in a profession window show in a small window with every material, how many you carry and how many you need.",
    open = function() CysUI:OpenConfig("Tracked Recipes") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

local Rec = {}
CUI.Recipes = Rec

CysUIDB.recipes = CysUIDB.recipes or {}
local db = CysUIDB.recipes
db.n = db.n or {} -- [recipeID] = how many you want to make
if db.prices == nil then db.prices = true end
if db.subs == nil then db.subs = true end
CysUICharDB = CysUICharDB or {}
CysUICharDB.recipeMakes = CysUICharDB.recipeMakes or {} -- [itemID] = recipeID this character has learned
local makes = CysUICharDB.recipeMakes

local floor, max, min = math.floor, math.max, math.min
local WIDTH, HEADER_H, HEAD_H, ROW_H = 290, 26, 24, 18
local CTRL_W = 106 -- x - N + on the right of a recipe heading (kept clear of the click proxy)
local SUB_DEPTH, INDENT = 2, 14
local frame
local heads, rows = {}, {}
local closedFor -- true after X: stays closed until you track another recipe

local function Secret(v) return CysUICompat and CysUICompat.Secret and CysUICompat.Secret(v) end

local function Tracked()
    local out = {}
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked) then return out end
    local ok, list = pcall(C_TradeSkillUI.GetRecipesTracked, false)
    if ok and type(list) == "table" then
        for _, id in ipairs(list) do if type(id) == "number" and not Secret(id) then out[#out + 1] = id end end
    end
    table.sort(out)
    return out
end

local function Count(id, bank)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id, bank and true or false)
    return (ok and type(n) == "number") and n or 0
end

local waiting = {}
local function ItemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n then
        local ok, name = pcall(C_Item.GetItemInfo, id)
        if ok then n = name end
    end
    if not n then
        waiting[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return n
end

local function ItemIcon(id)
    local ok, tex = pcall(C_Item.GetItemIconByID, id)
    return ok and tex or 134400
end

local function Money(c)
    if CysAH and CysAH.Money then return CysAH.Money(c) end
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return f and f(c) or tostring(c)
end

local function Price(id)
    if not (db.prices and CysAH and CysAH.GetPrice) then return nil end
    local ok, p = pcall(CysAH.GetPrice, id)
    return (ok and type(p) == "number" and p > 0) and p or nil
end

local function Schematic(recipeID)
    local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and type(s) == "table" then return s end
end

-- { itemID, per craft } for every required material of a schematic
local function Mats(s)
    local out = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local re = slot.reagents and slot.reagents[1]
        local need = slot.quantityRequired or 0
        if re and re.itemID and need > 0 and (slot.required ~= false) then out[#out + 1] = { re.itemID, need } end
    end
    return out
end

-- the materials of a craftable item you are short of, listed under it: { id, need, have, depth }
local function AddSubs(lines, id, missing, depth, seen)
    if not db.subs or depth > SUB_DEPTH or missing <= 0 then return end
    local rid = makes[id]
    if not rid or seen[id] then return end
    local s = Schematic(rid)
    if not s then return end
    seen[id] = true
    local crafts = math.ceil(missing / max(1, s.quantityMin or 1))
    for _, m in ipairs(Mats(s)) do
        local need, have = m[2] * crafts, Count(m[1])
        lines[#lines + 1] = { id = m[1], need = need, have = have, depth = depth }
        AddSubs(lines, m[1], need - have, depth + 1, seen)
    end
    seen[id] = nil
end

-- What this character can craft: [output itemID] = recipeID, read from an open profession window
-- (a few recipes per frame, ~3 ms budget).
local scanList, scanAt
local function ScanStep()
    if not scanList then return end
    local t0 = debugprofilestop()
    while scanAt <= #scanList do
        local rid = scanList[scanAt]
        scanAt = scanAt + 1
        local okI, info = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
        if okI and type(info) == "table" and info.learned and not info.isRecraft then
            local s = Schematic(rid)
            if s and s.outputItemID and not makes[s.outputItemID] then makes[s.outputItemID] = rid end
        end
        if debugprofilestop() - t0 > 3 then C_Timer.After(0, ScanStep); return end
    end
    scanList = nil
    if Rec.Refresh then Rec.Refresh() end
end
local function ScanProfession()
    if scanList or not C_TradeSkillUI.GetAllRecipeIDs then return end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return end
    scanList, scanAt = ids, 1
    ScanStep()
end

-- { recipeID, name, icon, mats = { { id, need (for one), have } }, canMake }
local function Read(recipeID)
    local s = Schematic(recipeID)
    if not s then return nil end
    local r = { id = recipeID, name = s.name or ("Recipe " .. recipeID), icon = s.icon, out = s.outputItemID,
                makes = s.quantityMin or 1, mats = {} }
    for _, m in ipairs(Mats(s)) do
        r.mats[#r.mats + 1] = { id = m[1], need = m[2], have = Count(m[1]) }
    end
    local can
    for _, m in ipairs(r.mats) do
        local c = floor(m.have / m.need)
        can = can and min(can, c) or c
    end
    r.canMake = can or 0
    if r.out and not r.icon then r.icon = ItemIcon(r.out) end
    return r
end

--------------------------------------------------------------------------------
-- Click proxy: the recipe heading passes clicks to the game's own tracker line for that recipe
-- (ProfessionsRecipeTracker block header): click = open the recipe, Shift-click = stop tracking.
-- "*" attributes so they also count with Shift held. Out of combat only.
--------------------------------------------------------------------------------
local proxy
local function BlizzHeader(recipeID)
    local m = _G.ProfessionsRecipeTracker
    if not m then return end
    local ok, b = pcall(m.GetExistingBlock, m, recipeID)
    if ok and type(b) == "table" and b.HeaderButton then return b.HeaderButton end
    local used = rawget(m, "usedBlocks") -- read only: any block template
    if type(used) == "table" then
        for _, blocks in pairs(used) do
            local blk = type(blocks) == "table" and blocks[recipeID]
            if type(blk) == "table" and blk.HeaderButton then return blk.HeaderButton end
        end
    end
end

local function HeadTip(h, owner)
    local r = h.recipe
    if not r then return end
    GameTooltip:SetOwner(owner or h, "ANCHOR_LEFT")
    GameTooltip:AddLine(r.name, 1, 0.82, 0)
    local n = db.n[r.id] or 1
    GameTooltip:AddLine("You can make " .. r.canMake .. " now.", 1, 1, 1)
    local cost, unknown = 0, false
    for _, m in ipairs(r.mats) do
        local miss = max(0, m.need * n - m.have)
        if miss > 0 then
            local p = Price(m.id)
            if p then cost = cost + p * miss else unknown = true end
        end
    end
    if cost > 0 then GameTooltip:AddLine("Missing materials on the Auction House: " .. Money(cost) .. (unknown and " + more" or ""), 1, 1, 1) end
    GameTooltip:AddLine(" ")
    if h.header then
        GameTooltip:AddLine("Click to open it in the profession window", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Shift-click to stop tracking it", T.accent[1], T.accent[2], T.accent[3])
    else
        GameTooltip:AddLine("Untrack it in the profession window (Track Recipe box).", T.dim[1], T.dim[2], T.dim[3], true)
    end
    GameTooltip:Show()
end

local function ClickProxy()
    if proxy then return proxy end
    proxy = CreateFrame("Button", "CysRecipesClickProxy", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    proxy:SetFrameStrata("DIALOG")
    proxy:RegisterForClicks("LeftButtonUp")
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:SetAttribute("*type1", "click")
    proxy:Hide()
    proxy:SetAttribute("_onstate-combat", [[ if newstate == "in" then self:Hide() end ]])
    RegisterStateDriver(proxy, "combat", "[combat] in; out")
    proxy:SetScript("OnEnter", function(self)
        local h = self.head
        if h and h:IsVisible() and h.recipe then h.hl:Show(); h.header = self.header; HeadTip(h, self) end
    end)
    proxy:SetScript("OnLeave", function(self)
        if self.head then self.head.hl:Hide() end
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
    end)
    return proxy
end

local function ShowProxy(h)
    if InCombatLockdown() or not h.recipe then return end
    local header = BlizzHeader(h.recipe.id)
    h.header = header
    if not header then return end -- the game's tracker has no line for it: tooltip says where to untrack
    local ok, l, b, w, hh = pcall(function()
        local s = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return h:GetLeft() * s, h:GetBottom() * s, (h:GetWidth() - CTRL_W) * s, h:GetHeight() * s
    end)
    if not ok or not l or Secret(l) or Secret(w) then return end
    local p = ClickProxy()
    p.head, p.header = h, header
    p:SetAttribute("*clickbutton1", header)
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    p:SetSize(w, hh)
    p:Show()
end

-- x: untracking from our own code would make the game's tracker refresh tainted, so x hands the click to
-- something of the game's that does it:
--   1. the profession window's own Track Recipe box, while that window shows this recipe (one click), else
--   2. a right-click on the game's tracker line for the recipe, which opens its menu (Untrack Recipe).
--      The left click is remapped to RightButton (helpbutton; needs a unit, so "player").
-- The game's tracker lists recipes below all quests, so with many tracked quests it often has no line.
local function TrackBox(recipeID)
    local pf = _G.ProfessionsFrame
    if not (pf and pf:IsShown()) then return end
    local form = pf.CraftingPage and pf.CraftingPage.SchematicForm
    local box = form and form.TrackRecipeCheckbox
    local info = form and rawget(form, "currentRecipeInfo")
    if box and box:IsVisible() and type(info) == "table" and info.recipeID == recipeID and box:GetChecked() then return box end
end

local function UntrackTarget(p, h)
    local box = h.recipe and TrackBox(h.recipe.id)
    local header = (not box) and h.recipe and BlizzHeader(h.recipe.id)
    p.box, p.header = box, header
    if box then
        p:SetAttribute("*helpbutton1", nil)
        p:SetAttribute("*type1", "click"); p:SetAttribute("*clickbutton1", box)
    else
        p:SetAttribute("*type1", nil); p:SetAttribute("*clickbutton1", nil)
        p:SetAttribute("*helpbutton1", header and "RightButton" or nil)
        p:SetAttribute("*clickbutton2", header)
    end
    return box or header
end
local xproxy
local function UntrackProxy()
    if xproxy then return xproxy end
    xproxy = CreateFrame("Button", "CysRecipesUntrackProxy", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    xproxy:SetFrameStrata("DIALOG")
    xproxy:RegisterForClicks("LeftButtonUp")
    xproxy:SetAttribute("useOnKeyDown", false)
    xproxy:SetAttribute("*unit1", "player")
    xproxy:SetAttribute("*unit2", "player")
    xproxy:SetAttribute("*type2", "click")
    xproxy:SetScript("PreClick", function(self)
        if self.head and not InCombatLockdown() then UntrackTarget(self, self.head) end
    end)
    xproxy:Hide()
    xproxy:SetAttribute("_onstate-combat", [[ if newstate == "in" then self:Hide() end ]])
    RegisterStateDriver(xproxy, "combat", "[combat] in; out")
    xproxy:SetScript("OnEnter", function(self)
        if self.head then self.head.x.text:SetTextColor(1, 0.3, 0.3) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Stop tracking", 1, 1, 1)
        if self.box then
            GameTooltip:AddLine("Unticks Track Recipe in the profession window.", T.dim[1], T.dim[2], T.dim[3], true)
        else
            GameTooltip:AddLine("Opens the game's menu for this recipe: pick Untrack Recipe.", T.dim[1], T.dim[2], T.dim[3], true)
        end
        GameTooltip:Show()
    end)
    xproxy:SetScript("OnLeave", function(self)
        if self.head then self.head.x.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
    end)
    return xproxy
end

local function ShowUntrack(h)
    if InCombatLockdown() or not h.recipe then return end
    local p = UntrackProxy()
    if not UntrackTarget(p, h) then return end -- nothing of the game's can do it: the plain x explains
    local ok, l, b, w, hh = pcall(function()
        local s = h.x:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return h.x:GetLeft() * s, h.x:GetBottom() * s, h.x:GetWidth() * s, h.x:GetHeight() * s
    end)
    if not ok or not l or Secret(l) then return end
    p.head = h
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    p:SetSize(w, hh)
    p:Show()
end

local function HideProxy()
    if proxy and proxy:IsShown() and not InCombatLockdown() then proxy:Hide() end
    if xproxy and xproxy:IsShown() and not InCombatLockdown() then xproxy:Hide() end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function SmallButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.text = W.Text(b, 13, T.dim, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function GetHead(i)
    if heads[i] then return heads[i] end
    local h = CreateFrame("Button", nil, frame)
    h:SetHeight(HEAD_H)
    h.hl = W.Texture(h, "BACKGROUND", T.hover); h.hl:SetAllPoints(); h.hl:Hide()
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(16, 16)
    h.icon:SetPoint("LEFT", 8, 0)
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.name = W.Text(h, 12, T.accent)
    h.name:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.name:SetWordWrap(false)
    h.plus = SmallButton(h, "+", function() local r = h.recipe; if r then db.n[r.id] = min(99, (db.n[r.id] or 1) + 1); Rec.Refresh() end end)
    h.plus:SetPoint("RIGHT", -6, 0)
    h.num = W.Text(h, 12, { 1, 1, 1 }, "CENTER")
    h.num:SetWidth(30)
    h.num:SetPoint("RIGHT", h.plus, "LEFT", 0, 0)
    h.minus = SmallButton(h, "-", function() local r = h.recipe; if r then local v = (db.n[r.id] or 1) - 1; db.n[r.id] = v > 1 and v or nil; Rec.Refresh() end end)
    h.minus:SetPoint("RIGHT", h.num, "LEFT", 0, 0)
    h.x = SmallButton(h, "x", function()
        local msg = InCombatLockdown() and "x works again after the fight."
            or "open this recipe in its profession window, then click x again (or untick Track Recipe there)."
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100Cys's UI|r Tracked Recipes: " .. msg)
    end)
    h.x:SetPoint("RIGHT", h.minus, "LEFT", -6, 0)
    h.name:SetPoint("RIGHT", h, "RIGHT", -CTRL_W - 2, 0)
    h:SetScript("OnEnter", function(s) s.hl:Show(); HeadTip(s); ShowProxy(s); ShowUntrack(s) end)
    h:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    heads[i] = h
    return h
end

local function Search(row)
    if CUI.Crates and CUI.Crates.Search then CUI.Crates.Search(row); return end
    if ChatEdit_InsertLink and row.itemID then
        local ok, _, link = pcall(C_Item.GetItemInfo, row.itemID)
        ChatEdit_InsertLink((ok and link) or row.searchName)
    end
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, frame)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    r.hl = W.Texture(r, "BACKGROUND", T.hover); r.hl:SetAllPoints(); r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 26, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.right = W.Text(r, 11, { 1, 1, 1 }, "RIGHT")
    r.right:SetPoint("RIGHT", -10, 0)
    r.tag = W.Text(r, 10, T.dim, "RIGHT")
    r.tag:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r.name = W.Text(r, 11, { 1, 1, 1 })
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        if not s.itemID then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        pcall(GameTooltip.SetItemByID, GameTooltip, s.itemID)
        local bank = Count(s.itemID, true) - Count(s.itemID)
        if bank > 0 then GameTooltip:AddLine(bank .. " more in your bank", 1, 1, 1) end
        GameTooltip:AddLine("Shift-click to search the Auction House", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(s) if IsShiftKeyDown() then Search(s) end end)
    rows[i] = r
    return r
end

local function BuildWindow()
    local f = CreateFrame("Frame", "CysRecipesFrame", UIParent)
    frame = f
    f:SetSize(WIDTH, 80)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if db.pos then f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120) end
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.94 }):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    W.Texture(header, "BACKGROUND", T.header):SetAllPoints()
    local hline = W.Texture(header, "BORDER", T.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint(1)
        if p then db.pos = { p, rp, x, y } end
        HideProxy()
    end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = W.Text(header, 12, T.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Tracked Recipes")
    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide(); HideProxy(); closedFor = true end)
    f:SetScript("OnHide", HideProxy)
end

function Rec.Refresh(open)
    local list = Tracked()
    if #list == 0 then
        if frame then frame:Hide() end
        closedFor = nil
        return
    end
    if open then closedFor = nil end
    if closedFor then return end
    if not frame then BuildWindow() end
    wipe(waiting)
    local y = HEADER_H + 4
    local nh, nr = 0, 0
    for _, id in ipairs(list) do
        local r = Read(id)
        if r then
            nh = nh + 1
            local h = GetHead(nh)
            h.recipe = r
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 1, -y); h:SetPoint("TOPRIGHT", -1, -y)
            h.icon:SetTexture(r.icon or 134400)
            local n = db.n[id] or 1
            local tag = r.canMake >= n and ("  |cFF33FF66can make " .. r.canMake .. "|r") or ("  |cFF999999can make " .. r.canMake .. "|r")
            h.name:SetText(r.name .. tag)
            h.num:SetText("x" .. n)
            h:Show()
            y = y + HEAD_H
            local lines = {}
            for _, m in ipairs(r.mats) do
                local need = m.need * n
                lines[#lines + 1] = { id = m.id, need = need, have = m.have, depth = 0 }
                AddSubs(lines, m.id, need - m.have, 1, { [r.out or 0] = true })
            end
            for _, m in ipairs(lines) do
                nr = nr + 1
                local row = GetRow(nr)
                local name = ItemName(m.id)
                row.itemID, row.searchName = m.id, name
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 1, -y); row:SetPoint("TOPRIGHT", -1, -y)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 26 + m.depth * INDENT, 0)
                row.icon:SetTexture(ItemIcon(m.id))
                row.name:SetText(m.depth > 0 and ("|cFFBBBBBB" .. (name or "...") .. "|r") or (name or "..."))
                local need = m.need
                local done = m.have >= need
                row.right:SetText((done and "|cFF33FF66" or "|cFFFFFFFF") .. m.have .. "|r |cFF999999/ " .. need .. "|r")
                local p = (not done) and Price(m.id)
                row.tag:SetText(p and Money(p * (need - m.have)) or "")
                row:Show()
                y = y + ROW_H
            end
            y = y + 4
        end
    end
    for i = nh + 1, #heads do heads[i]:Hide(); heads[i].recipe = nil end
    for i = nr + 1, #rows do rows[i]:Hide(); rows[i].itemID = nil end
    if nh == 0 then frame:Hide(); return end
    frame:SetHeight(y + 2)
    frame:Show()
end

function Rec.Toggle()
    if frame and frame:IsShown() then frame:Hide(); closedFor = true
    else
        Rec.Refresh(true)
        if #Tracked() == 0 then DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100Cys's UI|r Tracked Recipes: no recipe tracked. Tick Track Recipe in a profession window.") end
    end
end

--------------------------------------------------------------------------------
-- Events (refresh at most a few times a second)
--------------------------------------------------------------------------------
local pending
local function Soon(open)
    if open then pending = "open" elseif not pending then pending = true else return end
    C_Timer.After(0.2, function()
        local o = pending == "open"
        pending = nil
        Rec.Refresh(o)
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("TRACKED_RECIPE_UPDATE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if e == "TRACKED_RECIPE_UPDATE" then
        Soon(a2 and true or false) -- a newly tracked recipe opens the window again after X
    elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_LIST_UPDATE" then
        C_Timer.After(1, ScanProfession)
    elseif e == "GET_ITEM_INFO_RECEIVED" then
        if a1 and waiting[a1] then Soon() end
    elseif e == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(3, function() Rec.Refresh() end)
    else
        if frame and frame:IsShown() then Soon() end
    end
end)

SLASH_CYSRECIPES1 = "/cuirecipes"
SlashCmdList.CYSRECIPES = function() Rec.Toggle() end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Tracked Recipes", function(page)
    local width = 480
    local y = -4
    W.Header(page, "Tracked Recipes", width):SetPoint("TOPLEFT", 0, y)
    W.Checkbox(page, "Show Auction House cost of missing materials", function() return db.prices end,
        function(v) db.prices = v; Rec.Refresh() end):SetPoint("TOPLEFT", 4, y - 26)
    W.Checkbox(page, "List what you can craft a missing material from", function() return db.subs end,
        function(v) db.subs = v; Rec.Refresh() end):SetPoint("TOPLEFT", 4, y - 52)
    local b = W.Button(page, 120, 20, "Show the window")
    b:SetPoint("TOPLEFT", 4, y - 82)
    b:SetScript("OnClick", function() Rec.Refresh(true) end)
    W.Notes(page, 4, y - 116, width, "", {
        { "Tracking", "Tick Track Recipe in a profession window. The recipe shows here with every material, how many you carry (green when you have enough) and how many you can make now." },
        { "How many", "- and + set how many you want to make; the needed counts follow." },
        { "Crafted materials", "A material you can craft yourself and still need lists its own materials under it (two levels: Bronze Bar, then the bars, then the ores). Open each of your profession windows once so Cys's UI learns what you can craft." },
        { "Stop tracking", "x on a recipe unticks Track Recipe while its profession window shows that recipe; otherwise it opens the game's own menu for it (pick Untrack Recipe) when the game's tracker has room to list it." },
        { "Clicks", "Click a recipe's name to open it in the profession window; Shift-click it to stop tracking. Shift-click a material to search the Auction House (or link it in chat). Out of combat only." },
        { "Cost", "With Cys's Auction House installed, the price of what you are still missing shows beside each material." },
        "/cuirecipes shows or hides the window. X hides it until you track another recipe.",
    })
end, function() end)

    end,
})
