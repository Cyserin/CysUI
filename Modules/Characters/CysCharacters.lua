--------------------------------------------------------------------------------
-- Cys's UI - Your Characters
--
-- A small window, opened from its own minimap button (or /cuichars), with what Cys's UI knows about every
-- character on your account. Three views, picked with the tabs under the title:
--   Rested XP   how rested each character is now and when it will be full
--   Gold        the gold on each character, the richest first, with the total in the footer
--   Currencies  each character's own currencies (Classic cannot share them between characters)
--
-- Rested XP: each character saves its own rested XP, level, whether it is resting and the time, when it
-- logs out and whenever these change. The others are worked out from that time: 5% of a level every
-- 8 hours while resting in an inn or city, a quarter of that elsewhere, up to 1.5 levels.
-- Gold and currencies: saved per character in CysUIDB.characters.data when they change.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local Chars = {}
CUI.Characters = Chars

local floor, min, max = math.floor, math.min, math.max
local LEVEL_CAP = 60
local RATE_RESTING = 0.05 / (8 * 3600) -- share of a level gained per second while resting
local RESTED_CAP = 1.5
local RESTING_ICON = "|TInterface\\CharacterFrame\\UI-StateIcon:12:12:0:0:64:64:0:32:0:27|t"
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore" -- a little party: all your characters
if GetFileIDFromPath and not GetFileIDFromPath(ICON) then ICON = "Interface\\Icons\\INV_Misc_GroupLooking" end
local ROWS, ROW_H, WIDTH = 14, 20, 400
local TOP = 70 -- first row: header 26 + tabs 22 + headings 22

local function DB()
    CysUIDB.characters = CysUIDB.characters or {}
    local db = CysUIDB.characters
    if db.minimap == nil then db.minimap = true end
    if db.showMax == nil then db.showMax = false end
    db.angle = db.angle or 215
    db.view = db.view or "rested"
    db.data = db.data or {}       -- [key] = { name, realm, class, level, money, cur = { [id] = amount }, time }
    db.curInfo = db.curInfo or {} -- [id] = { name, icon, quality }
    return db
end

local function RestDB()
    CysUIDB.rested = CysUIDB.rested or {}
    CysUIDB.rested.chars = CysUIDB.rested.chars or {}
    return CysUIDB.rested
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local function Now() return (GetServerTime and GetServerTime()) or time() end

-- realm names without spaces or dashes, so "CAMWOW US2 Realm 5 PvE" and "CAMWOWUS2Realm5PvE" (the game gives
-- either, depending on when it is asked) are the same realm
local function NormRealm(realm)
    return ((realm or ""):gsub("[%s%-']", ""))
end

local function MyKey()
    local realm = (GetRealmName and GetRealmName()) or ""
    if realm == "" then realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or "?" end
    return (UnitName("player") or "?") .. "-" .. NormRealm(realm), realm
end

-- one entry per character: older versions could save the same character under two realm spellings.
-- Keep the higher level, then the newer save.
local function Better(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return (a.time or 0) >= (b.time or 0)
end

local function MergeStore(store)
    local merged = {}
    for _, c in pairs(store) do
        if c.name then
            local key = c.name .. "-" .. NormRealm(c.realm)
            if not merged[key] or Better(c, merged[key]) then merged[key] = c end
        end
    end
    wipe(store)
    for key, c in pairs(merged) do store[key] = c end
end

-- currencies on the character you are on: { [id] = amount }. Entries under a collapsed heading in the
-- game's currency list cannot be read, so their last saved amounts are kept.
local function ReadCurrencies(old)
    local ci = C_CurrencyInfo
    if not (ci and ci.GetCurrencyListSize and ci.GetCurrencyListInfo) then return old end
    local db = DB()
    local cur, collapsed = {}, false
    local ok, size = pcall(ci.GetCurrencyListSize)
    if not ok or type(size) ~= "number" then return old end
    for i = 1, size do
        local okI, info = pcall(ci.GetCurrencyListInfo, i)
        if okI and info then
            if info.isHeader then
                if info.isHeaderExpanded == false then collapsed = true end
            elseif info.currencyID and (info.quantity or 0) > 0 then
                cur[info.currencyID] = info.quantity
                db.curInfo[info.currencyID] = { name = info.name, icon = info.iconFileID, quality = info.quality }
            end
        end
    end
    if collapsed and old then
        for id, q in pairs(old) do if cur[id] == nil then cur[id] = q end end
    end
    return cur
end

function Chars.Save()
    local name = UnitName("player")
    if not name or name == UNKNOWNOBJECT then return end
    local key, realm = MyKey()
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 1
    local now = Now()
    local maxXP = UnitXPMax("player") or 0
    if maxXP > 0 then
        RestDB().chars[key] = {
            name = name, realm = realm, class = class, level = level,
            rest = GetXPExhaustion() or 0, max = maxXP,
            resting = IsResting() and true or false,
            time = now,
        }
    end
    local data = DB().data
    local old = data[key]
    data[key] = {
        name = name, realm = realm, class = class, level = level,
        money = GetMoney() or 0,
        cur = ReadCurrencies(old and old.cur),
        time = now,
    }
end

function Chars.Forget(key)
    RestDB().chars[key] = nil
    DB().data[key] = nil
end

-- rested XP now and seconds until it is full
local function Estimate(c, now)
    local maxXP = c.max or 0
    if maxXP <= 0 then return 0, 0 end
    local cap = maxXP * RESTED_CAP
    local rate = RATE_RESTING * (c.resting and 1 or 0.25) * maxXP
    local rest = min(cap, (c.rest or 0) + max(0, now - (c.time or now)) * rate)
    return rest, rest >= cap and 0 or (cap - rest) / rate
end

local function MeFirst(a, b)
    if a.me ~= b.me then return a.me end
    return nil
end

function Chars.List()
    local showMax = DB().showMax
    Chars.Save() -- the character you are on uses live numbers
    local myKey = MyKey()
    local now = Now()
    local list = {}
    for key, c in pairs(RestDB().chars) do
        if showMax or (c.level or 0) < LEVEL_CAP then
            local rest, left = Estimate(c, now)
            list[#list + 1] = { key = key, c = c, left = left, me = key == myKey,
                                pct = (c.max or 0) > 0 and rest / c.max * 100 or 0 }
        end
    end
    table.sort(list, function(a, b)
        local m = MeFirst(a, b); if m ~= nil then return m end -- the character you are on is always first
        if a.pct ~= b.pct then return a.pct > b.pct end
        return (a.c.name or "") < (b.c.name or "")
    end)
    return list
end

function Chars.GoldList()
    Chars.Save()
    local myKey = MyKey()
    local list, total, top = {}, 0, 0
    for key, c in pairs(DB().data) do
        local money = c.money or 0
        list[#list + 1] = { key = key, c = c, money = money, me = key == myKey }
        total = total + money
        top = max(top, money)
    end
    table.sort(list, function(a, b)
        local m = MeFirst(a, b); if m ~= nil then return m end
        if a.money ~= b.money then return a.money > b.money end
        return (a.c.name or "") < (b.c.name or "")
    end)
    return list, total, top
end

-- currencies belong to each character (Classic cannot share them), so one row per character that holds any
function Chars.CurrencyList()
    Chars.Save()
    local db = DB()
    local myKey = MyKey()
    local list = {}
    for key, c in pairs(db.data) do
        local items = {}
        for id, q in pairs(c.cur or {}) do
            items[#items + 1] = { id = id, info = db.curInfo[id] or {}, q = q }
        end
        if #items > 0 then
            table.sort(items, function(a, b) return (a.info.name or "") < (b.info.name or "") end)
            list[#list + 1] = { key = key, c = c, items = items, me = key == myKey }
        end
    end
    table.sort(list, function(a, b)
        local m = MeFirst(a, b); if m ~= nil then return m end
        return (a.c.name or "") < (b.c.name or "")
    end)
    return list
end

local function Commas(n)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and s then return s end
    end
    local s = tostring(n)
    local k
    repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

-- gold and silver from 1 gold up (copper is noise there), silver and copper below
function Chars.MoneyText(copper)
    copper = floor(copper or 0)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then return format("%s%s %d%s", Commas(g), GOLD_ICON, s, SILVER_ICON) end
    if s > 0 then return format("%d%s %d%s", s, SILVER_ICON, c, COPPER_ICON) end
    return format("%d%s", c, COPPER_ICON)
end
local MoneyText = Chars.MoneyText

local function FormatLeft(sec)
    if sec <= 0 then return "|cFF40D040full|r" end
    local h = sec / 3600
    if h >= 48 then return format("full in %dd", floor(h / 24 + 0.5)) end
    if h >= 1 then return format("full in %dh", floor(h + 0.5)) end
    return format("full in %dm", max(1, floor(sec / 60 + 0.5)))
end

local function ClassColor(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b end
    return 1, 1, 1
end

local function ClassName(c, myRealm)
    local r, g, b = ClassColor(c.class)
    local realm = (c.realm and myRealm and NormRealm(c.realm) ~= NormRealm(myRealm)) and ("-" .. c.realm) or ""
    return format("|cFF%02X%02X%02X%s%s|r", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5),
        c.name or "?", realm)
end

local function NameText(c, myRealm, resting)
    return format("%s  |cFFBBBBBB%d|r%s", ClassName(c, myRealm), c.level or 0,
        (resting and c.resting) and ("  " .. RESTING_ICON) or "")
end

local function LastSeen(c)
    local ago = Now() - (c.time or Now())
    if ago >= 86400 then return format("%d days ago", floor(ago / 86400)) end
    return format("%d hours ago", floor(ago / 3600))
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local frame, rows, offset = nil, {}, 0
local current = {} -- the list the rows show

-- what each view puts in the column headings, footer and empty text
local VIEWS = {
    { key = "rested", label = "Rested XP", cols = { "CHARACTER", "RESTED", "FULL" },
      empty = "Nothing saved yet - log in on your characters once." },
    { key = "gold", label = "Gold", cols = { "CHARACTER", "SHARE", "GOLD" },
      empty = "Log in on each character once to save its gold." },
    { key = "currency", label = "Currencies", cols = { "CHARACTER", "", "CURRENCIES" },
      empty = "None of your saved characters holds a currency yet." },
}
local VIEW_BY_KEY = {}
for _, v in ipairs(VIEWS) do VIEW_BY_KEY[v.key] = v end

local function CurrencyIcon(info)
    if not info.icon then return "" end
    return format("|T%s:14:14:0:0:64:64:5:59:5:59|t ", tostring(info.icon))
end

local function CurrencyName(info)
    local r, g, b = 1, 1, 1
    local q = info.quality
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local qc = ITEM_QUALITY_COLORS[q]; r, g, b = qc.r, qc.g, qc.b
    end
    return format("|cFF%02X%02X%02X%s|r", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5),
        info.name or "?")
end

local function SetRowLayout(row, view)
    -- rested: name | bar | % | full in ;  gold: name | bar | gold ;  currency: name ............ total
    row.bar:SetShown(view ~= "currency")
    row.pct:SetShown(view == "rested")
    row.mark:SetShown(view == "rested")
    if view == "gold" then
        row.bar:SetStatusBarColor(T.brand[1], T.brand[2], T.brand[3], 0.85)
        row.bar:SetMinMaxValues(0, 1)
        row.left:SetTextColor(1, 1, 1)
    else
        row.bar:SetStatusBarColor(0.25, 0.55, 1, 0.9)
        row.bar:SetMinMaxValues(0, RESTED_CAP * 100)
        if view == "rested" then row.left:SetTextColor(0.45, 0.7, 1) else row.left:SetTextColor(1, 1, 1) end
    end
end

local function Paint()
    if not frame or not frame:IsShown() then return end
    local view = VIEW_BY_KEY[DB().view] and DB().view or "rested"
    local def = VIEW_BY_KEY[view]
    local total, top = 0, 0
    if view == "gold" then
        current, total, top = Chars.GoldList()
    elseif view == "currency" then
        current = Chars.CurrencyList()
    else
        current = Chars.List()
    end
    local _, myRealm = MyKey()
    offset = max(0, min(offset, #current - ROWS))
    for i = 1, ROWS do
        local row, e = rows[i], current[i + offset]
        if e then
            row.entry, row.view = e, view
            SetRowLayout(row, view)
            if view == "gold" then
                row.name:SetText(NameText(e.c, myRealm))
                row.bar:SetValue(top > 0 and e.money / top or 0)
                row.left:SetText(MoneyText(e.money))
            elseif view == "currency" then
                row.name:SetText(NameText(e.c, myRealm))
                local parts = {}
                for _, it in ipairs(e.items) do parts[#parts + 1] = Commas(it.q) .. " " .. CurrencyIcon(it.info) end
                row.left:SetText(table.concat(parts, "  "))
            else
                row.name:SetText(NameText(e.c, myRealm, true))
                row.bar:SetValue(min(e.pct, RESTED_CAP * 100))
                row.pct:SetText(format("%d%%", floor(e.pct + 0.5)))
                row.left:SetText(FormatLeft(e.left))
            end
            row.mine:SetShown(e.me and true or false)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    for i, h in ipairs(frame.heads) do h:SetText(def.cols[i]) end
    for _, tab in ipairs(frame.tabs) do tab:SetActive(tab.key == view) end
    if view == "gold" then
        frame.foot:SetText(format("Total: %s  |cFF999999on %d character%s|r", MoneyText(total), #current,
            #current == 1 and "" or "s"))
    elseif view == "currency" then
        frame.foot:SetText("Hover a character to see its currencies by name.")
    else
        frame.foot:SetText(RESTING_ICON .. " logged out resting.   Shift + right-click a row to forget it.")
    end
    local shown = min(ROWS, #current)
    frame.empty:SetText(def.empty)
    frame.empty:SetShown(#current == 0)
    frame:SetHeight(TOP + max(1, shown) * ROW_H + 30)
end
Chars.Refresh = Paint

local function TooltipCharacter(self, e)
    local c = e.c
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.name .. (c.realm and (" - " .. c.realm) or ""), ClassColor(c.class))
    GameTooltip:AddDoubleLine("Level", tostring(c.level or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
    if self.view == "gold" then
        GameTooltip:AddDoubleLine("Gold", MoneyText(e.money), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Rested", format("%d%% of a level", floor(e.pct + 0.5)), 0.8, 0.8, 0.8,
            0.45, 0.7, 1)
    end
    if not e.me then
        if self.view ~= "gold" then
            GameTooltip:AddDoubleLine("Logged out", c.resting and "resting (inn or city)" or "not resting",
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Last seen", LastSeen(c), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift + right-click to forget this character", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function TooltipCurrency(self, e)
    local c = e.c
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.name .. (c.realm and (" - " .. c.realm) or ""), ClassColor(c.class))
    for _, it in ipairs(e.items) do
        GameTooltip:AddDoubleLine(CurrencyIcon(it.info) .. CurrencyName(it.info), Commas(it.q), 1, 1, 1, 1, 1, 1)
    end
    if not e.me then
        GameTooltip:AddDoubleLine("Last seen", LastSeen(c), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift + right-click to forget this character", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function MakeRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 16, ROW_H)
    row:SetPoint("TOPLEFT", 8, -(TOP + (i - 1) * ROW_H))
    row:RegisterForClicks("RightButtonUp")
    local hl = W.Texture(row, "BACKGROUND", T.hover)
    hl:SetAllPoints()
    hl:Hide()
    -- the character you are on: a faint gold wash with a gold tick on the left
    row.mine = CreateFrame("Frame", nil, row)
    row.mine:SetAllPoints()
    local wash = W.Texture(row.mine, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.08 })
    wash:SetAllPoints()
    local tick = W.Texture(row.mine, "ARTWORK", T.border)
    tick:SetPoint("TOPLEFT", 0, -3)
    tick:SetPoint("BOTTOMLEFT", 0, 3)
    tick:SetWidth(2)

    row.name = W.Text(row, 11)
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(150)
    row.name:SetWordWrap(false)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(96, 8)
    row.bar:SetPoint("LEFT", 162, 0)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetStatusBarColor(0.25, 0.55, 1, 0.9)
    row.bar:SetMinMaxValues(0, RESTED_CAP * 100)
    W.Texture(row.bar, "BACKGROUND", { 0.02, 0.02, 0.02, 0.9 }):SetAllPoints()
    W.Border(row.bar, 1, T.line, "OVERLAY")
    -- a mark at 100% (one full level of rested XP)
    row.mark = W.Texture(row.bar, "OVERLAY", { 1, 1, 1, 0.35 }, 1)
    row.mark:SetSize(1, 8)
    row.mark:SetPoint("LEFT", 96 / RESTED_CAP - 1, 0)

    row.pct = W.Text(row, 11, { 0.45, 0.7, 1 }, "RIGHT")
    row.pct:SetPoint("LEFT", row.bar, "RIGHT", 4, 0)
    row.pct:SetWidth(38)
    row.left = W.Text(row, 11, { 0.45, 0.7, 1 }, "RIGHT")
    row.left:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnEnter", function(self)
        hl:Show()
        local e = self.entry
        if not e then return end
        if self.view == "currency" then TooltipCurrency(self, e) else TooltipCharacter(self, e) end
    end)
    row:SetScript("OnLeave", function() hl:Hide(); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and e.key and not e.me and IsShiftKeyDown() then
            Chars.Forget(e.key)
            GameTooltip:Hide()
            Paint()
        end
    end)
    return row
end

-- a tab under the title: label with a gold line under the active one
local function MakeTab(parent, view, x)
    local tab = CreateFrame("Button", nil, parent)
    tab.key = view.key
    tab.text = W.Text(tab, 11, { 1, 1, 1 }, "CENTER")
    tab.text:SetPoint("CENTER", 0, 1)
    tab.text:SetText(view.label)
    tab:SetSize(max(60, (tab.text:GetStringWidth() or 50) + 18), 20)
    tab:SetPoint("TOPLEFT", x, -27)
    tab.line = W.Texture(tab, "ARTWORK", T.border)
    tab.line:SetPoint("BOTTOMLEFT", 6, 0)
    tab.line:SetPoint("BOTTOMRIGHT", -6, 0)
    tab.line:SetHeight(2)
    function tab:SetActive(on)
        self.active = on
        self.line:SetShown(on)
        if on then
            self.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        else
            self.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    tab:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(1, 1, 1) end end)
    tab:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    tab:SetScript("OnClick", function(self)
        DB().view = self.key
        offset = 0
        Paint()
    end)
    return tab
end

local function BuildWindow()
    local db = DB()
    local f = CreateFrame("Frame", "CysCharactersFrame", UIParent)
    frame = f
    f:SetSize(WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if db.pos then
        f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -220)
    end
    tinsert(UISpecialFrames, "CysCharactersFrame")
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.96 }):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    W.Texture(header, "BACKGROUND", T.header):SetAllPoints()
    local hline = W.Texture(header, "BORDER", T.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if point then db.pos = { point, relPoint, x, y } end
    end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = W.Text(header, 12, T.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Your Characters")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- view tabs
    f.tabs = {}
    local x = 8
    for _, v in ipairs(VIEWS) do
        local tab = MakeTab(f, v, x)
        f.tabs[#f.tabs + 1] = tab
        x = x + tab:GetWidth() + 2
    end
    local tline = W.Texture(f, "BORDER", T.line)
    tline:SetPoint("TOPLEFT", 8, -47); tline:SetPoint("TOPRIGHT", -8, -47); tline:SetHeight(1)

    -- column headings (text set per view)
    f.heads = {}
    local function Heading(point, x2, justify)
        local h = W.Text(f, 10, T.dim, justify)
        h:SetPoint(point, f, point == "TOPRIGHT" and "TOPRIGHT" or "TOPLEFT", x2, -53)
        f.heads[#f.heads + 1] = h
    end
    Heading("TOPLEFT", 16)
    Heading("TOPLEFT", 170)
    Heading("TOPRIGHT", -14, "RIGHT")
    local cline = W.Texture(f, "BORDER", T.line)
    cline:SetPoint("TOPLEFT", 8, -67); cline:SetPoint("TOPRIGHT", -8, -67); cline:SetHeight(1)

    for i = 1, ROWS do rows[i] = MakeRow(f, i) end

    f.empty = W.Text(f, 11, T.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -(TOP + 8))

    f.foot = W.Text(f, 10, T.dim)
    f.foot:SetPoint("BOTTOMLEFT", 10, 10)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Paint()
    end)
    f:SetScript("OnShow", function() offset = 0; Paint() end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 30 then acc = 0; Paint() end
    end)
end

function Chars:Toggle(view)
    if not frame then BuildWindow() end
    if view and VIEW_BY_KEY[view] then
        DB().view = view
        if frame:IsShown() then offset = 0; Paint(); return end
        frame:Show()
        return
    end
    frame:SetShown(not frame:IsShown())
end

SLASH_CYSCHARS1 = "/cuichars"
SLASH_CYSCHARS2 = "/cuirested"
SLASH_CYSCHARS3 = "/cuigold"
SlashCmdList.CYSCHARS = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "probe" then -- what the game says about each currency on this character
        local ci = C_CurrencyInfo
        local size = ci and ci.GetCurrencyListSize and ci.GetCurrencyListSize() or 0
        print("|cFFE6C068Cys's UI|r currencies:", size)
        for i = 1, size do
            local info = ci.GetCurrencyListInfo(i)
            if info and not info.isHeader then
                print(format("  %s (%s): %s  accountWide=%s transferable=%s", tostring(info.name),
                    tostring(info.currencyID), tostring(info.quantity), tostring(info.isAccountWide),
                    tostring(info.isAccountTransferable)))
            end
        end
        return
    end
    local view = (msg == "gold" and "gold") or ((msg == "currency" or msg == "currencies") and "currency")
        or (msg == "rested" and "rested") or nil
    Chars:Toggle(view)
end

--------------------------------------------------------------------------------
-- Minimap button (Cys's minimap button panel picks it up when it collects buttons)
--------------------------------------------------------------------------------
local mmb

local function PlaceButton()
    if not mmb then return end
    local a = math.rad(DB().angle)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    mmb:ClearAllPoints()
    mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "CysCharactersMinimapButton", Minimap)
    mmb = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then CUI:OpenConfig("Characters") else Chars:Toggle() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Your Characters", T.accent[1], T.accent[2], T.accent[3])
        local _, total = Chars.GoldList()
        if total > 0 then
            GameTooltip:AddDoubleLine("Gold on all characters", MoneyText(total), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddLine("Click: rested XP, gold and currencies of all your characters", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- drag around the minimap edge (does nothing once the Cys button panel has collected it)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            DB().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceButton()
    b:SetShown(DB().minimap)
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
function Chars.Enable()
    MergeStore(DB().data)
    MergeStore(RestDB().chars)
    local saver = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION",
                          "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE" }) do
        pcall(saver.RegisterEvent, saver, ev)
    end
    -- money and currency events can come in bursts (looting, vendoring): save once per burst
    local pending = false
    saver:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGOUT" then Chars.Save(); return end
        if pending then return end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            Chars.Save()
            if frame and frame:IsShown() then Paint() end
        end)
    end)
    BuildMinimapButton()
end

CUI:RegisterModule({
    key = "characters",
    name = "Your Characters",
    addon = "CysUI",
    desc = "A minimap button and window with the rested XP, gold and currencies of all your characters.",
    onEnable = Chars.Enable,
    open = function() CUI:OpenConfig("Characters") end,
})

CUI:RegisterPage("Characters", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Your Characters", width):SetPoint("TOPLEFT", 0, -4)
    local mm = W.Checkbox(page, "Show the minimap button", function() return db.minimap end,
        function(on) db.minimap = on; if mmb then mmb:SetShown(on) end end)
    mm:SetPoint("TOPLEFT", 4, -34)
    local sm = W.Checkbox(page, "Rested XP: also list characters at level 60", function() return db.showMax end,
        function(on) db.showMax = on; Paint() end)
    sm:SetPoint("TOPLEFT", 4, -60)
    local open = W.Button(page, 130, 22, "Open the window", true)
    open:SetPoint("TOPLEFT", 4, -96)
    open:SetScript("OnClick", function() if not (frame and frame:IsShown()) then Chars:Toggle() end end)
    local clear = W.Button(page, 130, 22, "Clear the list")
    clear:SetPoint("LEFT", open, "RIGHT", 10, 0)
    clear:SetScript("OnClick", function()
        wipe(RestDB().chars); wipe(db.data); Chars.Save(); Paint()
    end)
    W.Notes(page, 4, -134, width, "", {
        "Three views, picked with the tabs at the top of the window: Rested XP, Gold and Currencies.",
        "Each character is added when you log in on it, and saved again when its gold, currencies or rested XP change and when you log out.",
        "Rested XP of the others is worked out from when they logged out: 5% of a level every 8 hours in an inn or city, a quarter of that elsewhere, up to 1.5 levels.",
        "Gold: the richest first, with the total of all characters at the bottom (also on the minimap button tooltip).",
        "Currencies: each character's own currencies (they cannot be shared between characters); hover a character to see them by name.",
        "/cuichars opens the window, /cuichars gold or /cuichars currencies opens it on that view.",
    })
end)
