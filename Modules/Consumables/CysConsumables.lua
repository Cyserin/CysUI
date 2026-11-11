--------------------------------------------------------------------------------
-- Cys's UI - Consumables
--
-- Self-updating macros that always use the best item you have and can use right now:
--   Cys Food, Cys Drink, Cys HP Potion, Cys MP Potion, Cys Bandage, Cys Healthstone
-- Drag them from the Macros window (character tab) onto your bars once; they rewrite themselves out of
-- combat as your bags, level and First Aid skill change.
--
-- Items are recognised from their own tooltip text ("Restores 552 health over 21 sec...") instead of a
-- fixed list, so new items (WoW Forever) work without updates. Red tooltip lines (level / skill too low,
-- wrong zone) rule an item out.
--
-- Restock list (per character): items and how many to keep. At a vendor that sells them, the missing
-- amount is bought and a line in chat says what it cost.
-- Settings: /cui -> Consumables.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, max, min = math.floor, math.max, math.min

-- do you have the Well Fed buff right now? (read out of combat; macros can't change in combat anyway)
local WELL_FED = (GetSpellInfo and GetSpellInfo(19705)) or "Well Fed"
local function IsWellFed()
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = CysUICompat and CysUICompat.AuraEntry and CysUICompat.AuraEntry("player", i, "HELPFUL")
            if not a then break end
            name = a.name
        else
            name = UnitBuff("player", i)
            if not name then break end
        end
        if name == WELL_FED or name == "Well Fed" then return true end
    end
    return false
end
local CC = C_Container

local DEFAULTS = {
    macros = { food = true, drink = true, hp = true, mp = true, bandage = true, stone = true },
    conjuredFirst = true,  -- eat / drink conjured items first while they are close to your best
    buffFood = false,      -- allow Well Fed food in the Food macro
    buffFoodUnfed = false, -- use Well Fed food in the Food macro only while you don't have the Well Fed buff
    restock = true,        -- buy the restock list at vendors
    foodStacks = 0,        -- keep this many stacks of the best food a vendor sells for your level (0 = off)
    drinkStacks = 0,       -- the same for water
    goldFloor = 1,         -- vendor buying never takes you below this much gold
    chars = {},            -- [name - realm] = { restock = { [itemID] = count } }
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.consumables = CysUIDB.consumables or {}
    local db = CysUIDB.consumables
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                for kk, vv in pairs(v) do db[k][kk] = vv end
            else
                db[k] = v
            end
        end
    end
    return db
end

local function CharKey() return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?") end
local function CharDB()
    local db = DB()
    local k = CharKey()
    db.chars[k] = db.chars[k] or { restock = {} }
    db.chars[k].restock = db.chars[k].restock or {}
    return db.chars[k]
end

--------------------------------------------------------------------------------
-- Reading items
--------------------------------------------------------------------------------
local scan = CreateFrame("GameTooltip", "CysConsumablesScan", nil, "GameTooltipTemplate")
scan:SetOwner(UIParent, "ANCHOR_NONE")

local function IsRed(fs)
    if not (fs and fs:IsShown()) then return false end
    local text = fs:GetText()
    if not text or text == "" then return false end
    local r, g, b = fs:GetTextColor()
    return r > 0.9 and g < 0.25 and b < 0.25
end

-- What a bag item does. Returns nil for anything that isn't food, drink, a potion, a bandage or a
-- healthstone. Fields: food, drink (amount restored), hp, mp (average potion amount), bandage, stone,
-- buff (Well Fed food), conjured, usable.
local function Read(bag, slot, itemID)
    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    if classID ~= 0 then return nil end -- consumables only
    scan:ClearLines()
    scan:SetBagItem(bag, slot)
    local info = { usable = true }
    local name = scan:GetName()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    for i = 1, scan:NumLines() do
        local left = _G[name .. "TextLeft" .. i]
        local right = _G[name .. "TextRight" .. i]
        if IsRed(left) or IsRed(right) then info.usable = false end
        local t = left and left:GetText()
        if t then
            if t == "Conjured Item" then info.conjured = true end
            if t:find("Only usable in") and not (zone ~= "" and t:find(zone, 1, true)) then info.usable = false end
            local hpOver = t:match("Restores (%d+) health")
            local mpOver = t:match("(%d+) mana over")
            local seated = t:find("eating") or t:find("drinking") or t:find("seated")
            if seated and (hpOver or mpOver) then
                if hpOver and t:find("health") and (t:find("eating") or t:find("seated")) then info.food = tonumber(hpOver) end
                if mpOver then info.drink = tonumber(mpOver) end
            end
            if t:find("well fed") then info.buff = true end
            local h1, h2 = t:match("Restores (%d+) to (%d+) health")
            if h1 then info.hp = (tonumber(h1) + tonumber(h2)) / 2 end
            local m1, m2 = t:match("Restores (%d+) to (%d+) mana")
            if m1 then info.mp = (tonumber(m1) + tonumber(m2)) / 2 end
            local band = t:match("Heals (%d+) damage over")
            if band then info.bandage = tonumber(band) end
            local stone = t:match("Instantly restores (%d+) health")
            if stone then info.stone = tonumber(stone) end
        end
    end
    -- a healthstone's text matches nothing else; anything else that "instantly restores" health is a potion
    if info.stone and not ((GetItemInfo(itemID) or ""):find("Healthstone")) then
        info.hp, info.stone = info.hp or info.stone, nil
    end
    if not (info.food or info.drink or info.hp or info.mp or info.bandage or info.stone) then return nil end
    return info
end

--------------------------------------------------------------------------------
-- Picking the best item of each kind
--------------------------------------------------------------------------------
local KINDS = {
    { key = "food",    field = "food",    macro = "Cys Food",       label = "Food",           default = 4540 },  -- Tough Hunk of Bread
    { key = "drink",   field = "drink",   macro = "Cys Drink",      label = "Drink",          default = 159 },   -- Refreshing Spring Water
    { key = "hp",      field = "hp",      macro = "Cys HP Potion",  label = "Healing potion", default = 118 },   -- Minor Healing Potion
    { key = "mp",      field = "mp",      macro = "Cys MP Potion",  label = "Mana potion",    default = 2455 },  -- Minor Mana Potion
    { key = "bandage", field = "bandage", macro = "Cys Bandage",    label = "Bandage",        default = 1251 },  -- Linen Bandage
    { key = "stone",   field = "stone",   macro = "Cys Healthstone", label = "Healthstone",   default = 5512 },  -- Minor Healthstone
}

local best = {}   -- kind key -> { id, amount, count, conjured }

local function Scan()
    local db = DB()
    local items = {}  -- itemID -> { info, count }
    for bag = 0, 4 do
        for slot = 1, (CC.GetContainerNumSlots(bag) or 0) do
            local id = CC.GetContainerItemID(bag, slot)
            if id and items[id] == nil then
                local info = Read(bag, slot, id)
                items[id] = info and { info = info, count = GetItemCount(id) } or false
            end
        end
    end
    wipe(best)
    -- "only while unbuffed": not Well Fed -> buff food is preferred over any plain food
    -- and while you are Well Fed it is left out, even with "allow buff food" on
    local fedNow = db.buffFoodUnfed and IsWellFed()
    local preferBuff = db.buffFoodUnfed and not fedNow
    local allowBuff = (db.buffFood or preferBuff) and not fedNow
    for _, kind in ipairs(KINDS) do
        local top, topConj
        for id, it in pairs(items) do
            local info = it and it.info
            local amount = info and info.usable and info[kind.field]
            local skip = info and kind.field == "food" and info.buff and not allowBuff
            if amount and not skip then
                local e = { id = id, amount = amount, count = it.count, conjured = info.conjured,
                            buff = (kind.field == "food" and info.buff) and true or false }
                -- best: most restored; ties go to the smaller stack so stacks get used up.
                -- While you want the Well Fed buff, buff food wins over plain food whatever it restores.
                local better
                if not top then
                    better = true
                elseif preferBuff and e.buff ~= top.buff then
                    better = e.buff
                else
                    better = amount > top.amount or (amount == top.amount and e.count < top.count)
                end
                if better then top = e end
                if info.conjured and (not topConj or amount > topConj.amount) then topConj = e end
            end
        end
        -- conjured first while it restores at least 3/4 of the best (it disappears anyway)
        if db.conjuredFirst and topConj and top and topConj.amount >= top.amount * 0.75
            and not (preferBuff and top.buff) then top = topConj end
        best[kind.key] = top
    end
end

--------------------------------------------------------------------------------
-- Macros
--------------------------------------------------------------------------------
local MAX_CHAR = MAX_CHARACTER_MACROS or 18

local function Body(kind, pick)
    if not pick then
        return "#showtooltip item:" .. kind.default .. "\n/run UIErrorsFrame:AddMessage(\"No " .. string.lower(kind.label)
            .. " you can use in your bags.\", 1, 0.3, 0.3)"
    end
    if kind.key == "bandage" then
        return "#showtooltip\n/use [@mouseover,help,nodead][help,nodead][@player] item:" .. pick.id
    end
    return "#showtooltip\n/use item:" .. pick.id
end

local pendingMacros = false
local warnedFull = false
local function WriteMacros()
    if InCombatLockdown() then pendingMacros = true return end
    pendingMacros = false
    local db = DB()
    for _, kind in ipairs(KINDS) do
        if db.macros[kind.key] then
            local body = Body(kind, best[kind.key])
            local index = GetMacroIndexByName(kind.macro)
            if index and index > 0 then
                local _, _, oldBody = GetMacroInfo(index)
                if oldBody ~= body then EditMacro(index, kind.macro, "INV_MISC_QUESTIONMARK", body) end
            else
                local _, perChar = GetNumMacros()
                if (perChar or 0) < MAX_CHAR then
                    pcall(CreateMacro, kind.macro, "INV_MISC_QUESTIONMARK", body, true)
                elseif not warnedFull then
                    warnedFull = true
                    CUI:Print("Your character macro list is full, so the " .. kind.macro .. " macro couldn't be made. Free a slot and /reload.")
                end
            end
        end
    end
end

local lastScan = 0
local queued = false
local function Refresh()
    if queued then return end
    queued = true
    -- bags fire many updates at once: wait a moment, then do one pass
    C_Timer.After(0.4, function()
        queued = false
        Scan()
        WriteMacros()
        lastScan = GetTime()
        if CUI.ConsumablesPage and CUI.ConsumablesPage:IsShown() then CUI.ConsumablesPage.RefreshPicks() end
    end)
end

--------------------------------------------------------------------------------
-- Restock at vendors
--------------------------------------------------------------------------------
local function Money(c)
    if GetCoinTextureString then return GetCoinTextureString(c) end
    return tostring(c)
end

-- name, price, how many one purchase gives, how many are left (-1 = no limit), costs something other than gold
local function MerchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if t then return t.name, t.price, t.stackCount, t.numAvailable, t.hasExtendedCost end
    end
    if GetMerchantItemInfo then
        local name, _, price, perBuy, available, _, _, extended = GetMerchantItemInfo(i)
        return name, price, perBuy, available, extended
    end
end

-- What a vendor item restores, read from its tooltip like the bag items: food amount, drink amount, Well Fed.
-- Nothing for an item you can't use yet (red text, such as a level you haven't reached).
local function ReadMerchant(i)
    if not scan.SetMerchantItem then return nil end
    scan:ClearLines()
    scan:SetMerchantItem(i)
    local food, drink, buff
    local name = scan:GetName()
    for l = 1, scan:NumLines() do
        local left = _G[name .. "TextLeft" .. l]
        local right = _G[name .. "TextRight" .. l]
        if IsRed(left) or IsRed(right) then return nil end
        local t = left and left:GetText()
        if t then
            local hpOver = t:match("Restores (%d+) health")
            local mpOver = t:match("(%d+) mana over")
            if hpOver and (t:find("eating") or t:find("seated")) then food = tonumber(hpOver) end
            if mpOver and (t:find("drinking") or t:find("seated")) then drink = tonumber(mpOver) end
            if t:find("well fed") then buff = true end
        end
    end
    return food, drink, buff
end

local function UsesMana()
    local mx = UnitPowerMax and UnitPowerMax("player", 0)
    return type(mx) == "number" and mx > 0
end

local function Restock()
    local db = DB()
    local list = db.restock and CharDB().restock or {}
    local reserve = (db.goldFloor or 0) * 10000
    local bought, spent = {}, 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local want = id and list[id]
        if want and want > 0 then
            local name, price, perBuy, available = MerchantInfo(i)
            local extended = GetMerchantItemCostInfo and (GetMerchantItemCostInfo(i) or 0) > 0 -- tokens, not gold
            local need = want - GetItemCount(id)
            if need > 0 and not extended and price and price > 0 then
                perBuy = max(perBuy or 1, 1)
                if available and available >= 0 then need = min(need, available * perBuy) end
                local unitPrice = price / perBuy
                local affordable = floor(max(0, GetMoney() - reserve - spent) / unitPrice)
                need = min(need, affordable)
                local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or need
                local left = need
                while left > 0 do
                    local n = min(left, max(maxStack, 1))
                    BuyMerchantItem(i, n)
                    left = left - n
                end
                if need > 0 then
                    bought[#bought + 1] = need .. "x " .. (name or link)
                    spent = spent + floor(unitPrice * need + 0.5)
                end
            end
        end
    end
    -- the best plain food and water this vendor sells that you can use at your level, kept at so many stacks
    local want = { food = db.foodStacks or 0, drink = UsesMana() and (db.drinkStacks or 0) or 0 }
    if want.food > 0 or want.drink > 0 then
        local pick = {}
        for i = 1, (GetMerchantNumItems() or 0) do
            local ok, food, drink, buff = pcall(ReadMerchant, i)
            if ok and not buff and (food or drink) then
                local _, price, _, _, extended = MerchantInfo(i)
                if price and price > 0 and not extended then
                    if food and want.food > 0 and (not pick.food or food > pick.food.amount) then pick.food = { i = i, amount = food } end
                    if drink and want.drink > 0 and (not pick.drink or drink > pick.drink.amount) then pick.drink = { i = i, amount = drink } end
                end
            end
        end
        for _, kind in ipairs({ "food", "drink" }) do
            local p, mine = pick[kind], best[kind]
            local link = p and GetMerchantItemLink(p.i)
            local id = link and tonumber(link:match("item:(%d+)"))
            -- not when the restock list already covers it, or when you carry something better (conjured aside)
            if id and not list[id] and not (mine and not mine.conjured and (mine.amount or 0) > p.amount) then
                local name, price, perBuy, available = MerchantInfo(p.i)
                perBuy = max(perBuy or 1, 1)
                local _, _, _, _, _, _, _, stackSize = GetItemInfo(id)
                local need = want[kind] * (stackSize or 20) - GetItemCount(id)
                if available and available >= 0 then need = min(need, available * perBuy) end
                local unitPrice = price / perBuy
                need = min(need, floor(max(0, GetMoney() - reserve - spent) / unitPrice))
                need = need - need % perBuy
                if need > 0 then
                    local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(p.i) or need
                    local left = need
                    while left > 0 do
                        local n = min(left, max(maxStack, 1))
                        BuyMerchantItem(p.i, n)
                        left = left - n
                    end
                    bought[#bought + 1] = need .. "x " .. (name or link)
                    spent = spent + floor(unitPrice * need + 0.5)
                end
            end
        end
    end
    if #bought > 0 then
        CUI:Print("Restocked " .. table.concat(bought, ", ") .. " for " .. Money(spent) .. ".")
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local frame
local function Enable()
    if frame then return end
    DB()
    frame = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
                         "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW" }) do
        pcall(frame.RegisterEvent, frame, e)
    end
    pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
    local fed
    frame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_AURA" then
            -- only matters when Well Fed comes or goes, and only with the "while unbuffed" option
            if not DB().buffFoodUnfed or InCombatLockdown() then return end
            local now = IsWellFed()
            if now ~= fed then fed = now; Refresh() end
            return
        end
        if event == "MERCHANT_SHOW" then
            C_Timer.After(0.3, Restock) -- give the vendor list a moment to fill
        elseif event == "PLAYER_REGEN_ENABLED" then
            if DB().buffFoodUnfed then fed = IsWellFed(); Refresh() -- Well Fed may have run out mid-fight
            elseif pendingMacros then WriteMacros() end
        else
            Refresh()
        end
    end)
end

CUI:RegisterModule({
    key = "consumables",
    name = "Consumables",
    addon = "CysUI",
    desc = "Macros that always use your best food, drink, potions, bandage and healthstone (conjured first), and a restock list that buys what you're short at vendors.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Consumables") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Consumables", function(page)
    local db = DB()
    local width = 480
    CUI.ConsumablesPage = page

    W.Header(page, "Consumables", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("Cys's UI makes these macros on your character tab of the Macros window (|cFFFFD100/macro|r). "
        .. "Drag them onto your bars once; they always use your best item and update themselves out of combat.")

    local y = -84
    W.Header(page, "Macros", width):SetPoint("TOPLEFT", 0, y); y = y - 28
    local picks = {}
    for _, kind in ipairs(KINDS) do
        local cb = W.Checkbox(page, kind.macro, function() return db.macros[kind.key] end, function(on)
            db.macros[kind.key] = on
            Refresh()
        end)
        cb:SetPoint("TOPLEFT", 4, y)
        local pick = W.Text(page, 11, T.desc)
        pick:SetPoint("TOPLEFT", 180, y - 3)
        pick:SetWidth(width - 184)
        pick:SetJustifyH("LEFT")
        picks[kind.key] = pick
        y = y - 24
    end
    function page.RefreshPicks()
        for _, kind in ipairs(KINDS) do
            local b = best[kind.key]
            local fs = picks[kind.key]
            if b then
                local name = GetItemInfo(b.id) or ("item " .. b.id)
                fs:SetText(string.format("|cFFFFFFFF%s|r  (%d)  x%d%s", name, b.amount, b.count, b.conjured and "  |cFF6CB6FFconjured|r" or ""))
            else
                fs:SetText("nothing usable in your bags")
            end
        end
    end
    page:HookScript("OnShow", function() Scan(); page.RefreshPicks() end)

    y = y - 6
    local c1 = W.Checkbox(page, "Use conjured food and water first (while close to your best)",
        function() return db.conjuredFirst end, function(on) db.conjuredFirst = on; Refresh() end)
    c1:SetPoint("TOPLEFT", 4, y); y = y - 26
    local c2 = W.Checkbox(page, "Allow Well Fed (buff) food in the Food macro",
        function() return db.buffFood end, function(on) db.buffFood = on; Refresh() end)
    c2:SetPoint("TOPLEFT", 4, y); y = y - 26
    local c2b = W.Checkbox(page, "Use Well Fed food only while I don't have the Well Fed buff",
        function() return db.buffFoodUnfed end, function(on) db.buffFoodUnfed = on; Refresh() end)
    c2b:SetPoint("TOPLEFT", 4, y); y = y - 34

    ---------------------------------------------------------------- best food and water
    W.Header(page, "Food and water at vendors", width):SetPoint("TOPLEFT", 0, y); y = y - 28
    W.Stepper(page, "Stacks of the best food to keep (0 = off)", function() return db.foodStacks or 0 end,
        function(v) db.foodStacks = v end, 0, 10, 1):SetPoint("TOPLEFT", 4, y); y = y - 28
    W.Stepper(page, "Stacks of the best water to keep (0 = off)", function() return db.drinkStacks or 0 end,
        function(v) db.drinkStacks = v end, 0, 10, 1):SetPoint("TOPLEFT", 4, y); y = y - 28
    W.Stepper(page, "Never buy below this much gold", function() return db.goldFloor or 0 end,
        function(v) db.goldFloor = v end, 0, 100, 1, " g"):SetPoint("TOPLEFT", 4, y); y = y - 36

    ---------------------------------------------------------------- restock list
    W.Header(page, "Restock list (this character)", width):SetPoint("TOPLEFT", 0, y); y = y - 28
    local c3 = W.Checkbox(page, "Buy what's missing when I open a vendor that sells it",
        function() return db.restock end, function(on) db.restock = on end)
    c3:SetPoint("TOPLEFT", 4, y); y = y - 30

    -- drop an item here (or click while holding one) to add it
    local drop = CreateFrame("Button", nil, page)
    drop:SetSize(width - 8, 34)
    drop:SetPoint("TOPLEFT", 4, y)
    W.Texture(drop, "BACKGROUND", T.field):SetAllPoints()
    local dropEdges = W.Border(drop, 1, T.line, "BORDER")
    local dropText = W.Text(drop, 11, T.desc, "CENTER")
    dropText:SetPoint("CENTER")
    dropText:SetText("Drop an item from your bags here to add it to the list")
    y = y - 44

    local listTop = y
    local rows = {}
    local function Rebuild()
        local list = CharDB().restock
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return (GetItemInfo(a) or "") < (GetItemInfo(b) or "") end)
        for _, r in ipairs(rows) do r:Hide() end
        local ry = listTop
        for i, id in ipairs(ids) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, page)
                r:SetSize(width - 8, 26)
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(20, 20)
                r.icon:SetPoint("LEFT", 2, 0)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.name = W.Text(r, 12, T.text)
                r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
                r.name:SetWidth(200)
                r.name:SetJustifyH("LEFT")
                r.minus = W.Button(r, 22, 22, "-")
                r.count = W.Text(r, 12, T.accent, "CENTER")
                r.count:SetWidth(44)
                r.plus = W.Button(r, 22, 22, "+")
                r.remove = W.Button(r, 70, 22, "Remove")
                r.remove:SetPoint("RIGHT", 0, 0)
                r.plus:SetPoint("RIGHT", r.remove, "LEFT", -12, 0)
                r.count:SetPoint("RIGHT", r.plus, "LEFT", -4, 0)
                r.minus:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
                rows[i] = r
            end
            local function Show() r.count:SetText(tostring(list[r.id] or 0)) end
            r.id = id
            r.icon:SetTexture(select(5, GetItemInfoInstant(id)))
            r.name:SetText(GetItemInfo(id) or ("item " .. id))
            -- steps of 5 (Shift: 1, Ctrl: 20)
            local function Step(dir)
                local s = IsShiftKeyDown() and 1 or (IsControlKeyDown() and 20 or 5)
                list[r.id] = max(1, min(1000, (list[r.id] or 0) + dir * s))
                Show()
            end
            r.minus:SetScript("OnClick", function() Step(-1) end)
            r.plus:SetScript("OnClick", function() Step(1) end)
            r.remove:SetScript("OnClick", function() list[r.id] = nil; Rebuild() end)
            Show()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, ry)
            r:Show()
            ry = ry - 28
        end
        if #ids == 0 then ry = ry - 4 end
        page.emptyNote = page.emptyNote or W.Text(page, 11, T.desc)
        page.emptyNote:ClearAllPoints()
        page.emptyNote:SetPoint("TOPLEFT", 4, ry - 4)
        page.emptyNote:SetWidth(width - 8)
        page.emptyNote:SetJustifyH("LEFT")
        page.emptyNote:SetText((#ids == 0 and "Nothing on the list yet.\n" or "")
            .. "|cFFFFD100+ / -|r change the amount by 5 (Shift: 1, Ctrl: 20). Items are bought until you carry that many.")
        page.contentHeight = -ry + 60
    end

    local function AddFromCursor()
        local kind, id = GetCursorInfo()
        if kind ~= "item" or not id then return end
        ClearCursor()
        local list = CharDB().restock
        if not list[id] then list[id] = 20 end
        Rebuild()
    end
    drop:SetScript("OnReceiveDrag", AddFromCursor)
    drop:SetScript("OnClick", AddFromCursor)
    drop:SetScript("OnEnter", function() W.SetBorder(dropEdges, T.glow) end)
    drop:SetScript("OnLeave", function() W.SetBorder(dropEdges, T.line) end)

    Rebuild()
    page:HookScript("OnShow", Rebuild)
end)
