--------------------------------------------------------------------------------
-- Cys's UI - Crate Tracker
--
-- A small window listing every crate in your bags that asks to be filled ("Fill the crate ..." in its tooltip),
-- with the items it needs and, on the far right, how many you carry: green in parentheses when you have enough.
-- Click a crate's heading to fold it. Opens by itself while a crate is in your bags (switch), or /cuicrates.
--
-- What each crate needs is read from the crate's own tooltip, so no item lists are kept here and new crates
-- work without an update.
-- Later: Cys's own Auction House scan can mark the cheapest item of each crate (see Crates.Price below).
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "crates", name = "Crate Tracker",
    desc = "Lists the crates in your bags that ask to be filled, what each one needs and how many you already carry.",
    open = function() CysUI:OpenConfig("Crate Tracker") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

local Crates = {}
CUI.Crates = Crates

CysUIDB.crates = CysUIDB.crates or {}
local db = CysUIDB.crates
-- when the window shows: "bags" = with Cys's Bags, docked beside them; "crate" = whenever a crate is in your
-- bags; "manual" = only /cuicrates. (Older saves had auto = false for manual.)
if db.show == nil then db.show = (db.auto == false) and "manual" or "bags" end
db.folded = db.folded or {}
db.ids = db.ids or {} -- [normalised item name] = itemID, remembered once seen

local floor, max, min = math.floor, math.max, math.min
local WIDTH, HEADER_H, ROW_H, CRATE_H, MAX_ROWS = 300, 26, 18, 22, 120
local TOP = HEADER_H + 4 -- where the list starts under the header
local BAR_W = 6 -- scroll bar width (only shown when the list is taller than the window)
local SLIM_W = 34 -- folded to a small strip (like the bags sidebar): crate icon + how many crates

--------------------------------------------------------------------------------
-- Reading the bags and the crates
--------------------------------------------------------------------------------
local function Norm(s)
    s = (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s:lower():gsub("[^%w]", "")
end

local carried = {}   -- [normalised name] = count in your bags
local idByName = {}  -- [normalised name] = itemID (for icons and tooltips)
local crateIDs = {}  -- itemIDs of everything in your bags, in bag order (crates are picked from these)
local spotByID = {}  -- [itemID] = { bag, slot } of its first stack (for the crates)
local countByID = {} -- [itemID] = how many you carry (how many crates of one kind)
local writs = {}     -- Craftsman's Writs in your bags: { itemID, bag, slot, name, active }
db.writQ = db.writQ or {} -- [questID] = true for quests started from a writ
local spotByKey = {} -- [normalised name] = { bag, slot, n } of its biggest stack (what a click puts in)

local function ScanBags()
    wipe(carried); wipe(crateIDs); wipe(spotByID); wipe(spotByKey); wipe(countByID); wipe(writs)
    local seen = {}
    local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = info.itemName or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID))
                    or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))
                if name then
                    local k = Norm(name)
                    carried[k] = (carried[k] or 0) + (info.stackCount or 1)
                    local n = info.stackCount or 1
                    if not spotByKey[k] or n > spotByKey[k][3] then spotByKey[k] = { bag, slot, n } end
                    idByName[k] = info.itemID
                    db.ids[k] = info.itemID
                end
                countByID[info.itemID] = (countByID[info.itemID] or 0) + (info.stackCount or 1)
                if name and name:find("Writ:") then
                    local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                    if q and q.questID then db.writQ[q.questID] = true end
                    writs[#writs + 1] = { itemID = info.itemID, bag = bag, slot = slot, name = name,
                        active = q and q.isActive, questID = q and q.questID }
                end
                if not seen[info.itemID] then
                    seen[info.itemID] = true
                    spotByID[info.itemID] = { bag, slot }
                    crateIDs[#crateIDs + 1] = info.itemID
                end
            end
        end
    end
end

local cache, tries = {}, {} -- [itemID] = { name, reqs = { { count, name } } } or false
local waiting = false

local function TooltipLines(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or not data or not data.lines then return end
    local lines = {}
    for _, l in ipairs(data.lines) do
        if type(l.leftText) == "string" then lines[#lines + 1] = l.leftText end
    end
    return #lines > 0 and lines or nil
end

local SKIP = { charge = true, charges = true, slot = true, slots = true }

-- Item IDs of things crates ask for, so their icons and tooltips work before you have ever carried them.
-- Anything not listed is learned the first time it is in your bags.
local KNOWN = {
    ["Handful of Copper Bolts"] = 4359, ["Copper Tube"] = 4361, ["Copper Modulator"] = 4363,
    ["Strange Dust"] = 10940, ["Lesser Magic Essence"] = 10938, ["Greater Magic Essence"] = 10939,
    ["Small Glimmering Shard"] = 10978, ["Large Glimmering Shard"] = 11084,
    ["Peacebloom"] = 2447, ["Silverleaf"] = 765, ["Earthroot"] = 2449, ["Mageroyal"] = 785, ["Briarthorn"] = 2450,
    ["Vision Dust"] = 11176, ["Greater Mystic Essence"] = 11135, ["Small Radiant Shard"] = 11177,
    ["Large Radiant Shard"] = 11178, ["Soul Dust"] = 11083, ["Greater Astral Essence"] = 11082,
    ["Small Glowing Shard"] = 11138, ["Large Glowing Shard"] = 11139,
    ["Mageweave Cloth"] = 4338, ["Bolt of Mageweave"] = 4339, ["Heavy Leather"] = 4234, ["Cured Heavy Hide"] = 4236,
    ["Gold Ore"] = 2776, ["Mithril Ore"] = 3858, ["Mechanical Repair Kit"] = 11590,
    ["Wintersbite"] = 3819, ["Firebloom"] = 4625, ["Purple Lotus"] = 8831, ["Arthas' Tears"] = 8836,
    ["Liferoot"] = 3357, ["Fadeleaf"] = 3818, ["Goldthorn"] = 3821, ["Khadgar's Whisker"] = 3358,
}
local KNOWN_IDS = {}
for name, id in pairs(KNOWN) do KNOWN_IDS[Norm(name)] = id end

-- Every item Cys's Auction House has seen, by name (its scan keeps names[itemID]). Rebuilt at most every 30 s,
-- and only when a lookup misses.
local ahIDs, ahBuilt = nil, nil
local function AHItemID(key)
    local names = CysAHDB and CysAHDB.names
    if type(names) ~= "table" then return nil end
    if ahIDs and ahIDs[key] then return ahIDs[key] end
    local now = GetTime and GetTime() or 0
    if ahBuilt and now - ahBuilt < 30 then return nil end
    ahBuilt = now
    ahIDs = {}
    for id, n in pairs(names) do
        if type(id) == "number" and type(n) == "string" and n ~= "" then ahIDs[Norm(n)] = id end
    end
    return ahIDs[key]
end

local function Analyze(itemID)
    if cache[itemID] ~= nil then return cache[itemID] end
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        tries[itemID] = (tries[itemID] or 0) + 1
        if tries[itemID] <= 20 then
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
            waiting = true
            return nil
        end
    end
    local lines = TooltipLines(itemID)
    if not lines then
        tries[itemID] = (tries[itemID] or 0) + 1
        if tries[itemID] > 20 then cache[itemID] = false else waiting = true end
        return nil
    end
    local isCrate = false
    for _, text in ipairs(lines) do
        if text:find("[Ff]ill the crate") then isCrate = true break end
    end
    if not isCrate then cache[itemID] = false return false end
    local reqs = {}
    for i = 2, #lines do
        for line in lines[i]:gmatch("[^\n]+") do
            line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*\226\128\162", ""):gsub("^%s*%-", "")
            local count, name = line:match("^%s*(%d+)%s*[xX]?%s+(.-)%s*$")
            if count and name and #name > 2 and not SKIP[name:lower()] then
                reqs[#reqs + 1] = { count = tonumber(count), name = name, key = Norm(name) }
            end
        end
    end
    if #reqs == 0 then cache[itemID] = false return false end
    cache[itemID] = { name = lines[1], reqs = reqs }
    return cache[itemID]
end

-- the crates in your bags, each with what it needs and what you carry
function Crates.List()
    waiting = false
    ScanBags()
    local list = {}
    for _, itemID in ipairs(crateIDs) do
        local c = Analyze(itemID)
        if c then
            local ready = 0
            for _, r in ipairs(c.reqs) do
                r.have = carried[r.key] or 0
                r.itemID = r.itemID or idByName[r.key] or db.ids[r.key] or AHItemID(r.key) or KNOWN_IDS[r.key]
                if r.itemID and not db.ids[r.key] then db.ids[r.key] = r.itemID end
                if not r.itemID and C_Item and C_Item.GetItemInfoInstant then
                    -- items you don't carry: the game knows many by name once it has seen them anywhere
                    local ok, id = pcall(C_Item.GetItemInfoInstant, r.name)
                    if ok and type(id) == "number" then r.itemID = id; db.ids[r.key] = id end
                end
                if r.have >= r.count then ready = ready + 1 end
            end
            list[#list + 1] = { itemID = itemID, name = c.name, reqs = c.reqs, ready = ready, n = countByID[itemID] or 1 }
        end
    end
    Crates.AddWrits(list)
    return list
end

-- Craftsman's Writs: a writ not started yet shows the item its name asks for (click its heading to start the
-- quest); a started one shows the quest's objectives with exact counts.
local function ReqFor(name, count)
    local key = Norm(name)
    local id = idByName[key] or db.ids[key] or AHItemID(key) or KNOWN_IDS[key]
    if not id and C_Item and C_Item.GetItemInfoInstant then
        local ok, v = pcall(C_Item.GetItemInfoInstant, name)
        if ok and type(v) == "number" then id = v end
    end
    if id then db.ids[key] = id end
    return { name = name, key = key, count = count, have = carried[key] or 0, itemID = id }
end

function Crates.AddWrits(list)
    local Q = C_QuestLog
    local inLog = {}
    if Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives then
        for i = 1, (Q.GetNumQuestLogEntries() or 0) do
            local info = Q.GetInfo(i)
            local qid = info and not info.isHeader and info.questID
            local title = info and info.title
            if qid and (db.writQ[qid] or (type(title) == "string" and title:find("Writ"))) then
                db.writQ[qid] = true
                inLog[qid] = true
                local reqs, ready = {}, 0
                for _, o in ipairs(Q.GetQuestObjectives(qid) or {}) do
                    local text = type(o.text) == "string" and o.text or ""
                    local nm = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":?%s*%d+%s*/%s*%d+%s*$", "")
                    if nm ~= "" and o.numRequired and o.numRequired > 0 then
                        local r = ReqFor(nm, o.numRequired)
                        if r.have == 0 and o.numFulfilled then r.have = o.numFulfilled end
                        if r.have >= r.count then ready = ready + 1 end
                        reqs[#reqs + 1] = r
                    end
                end
                list[#list + 1] = { writ = true, fold = "q" .. qid, name = title, reqs = reqs, ready = ready, n = 1 }
            end
        end
    end
    -- writs in your bags whose quest isn't started yet (one heading per kind)
    local seen = {}
    for _, w in ipairs(writs) do
        if not (w.questID and inLog[w.questID]) and not w.active and not seen[w.itemID] then
            seen[w.itemID] = true
            local want = w.name:match("Writ:%s*(.+)$")
            local reqs = want and { ReqFor(want, nil) } or {}
            list[#list + 1] = { writ = true, itemID = w.itemID, fold = w.itemID, name = w.name, reqs = reqs,
                ready = 0, n = countByID[w.itemID] or 1, startMacro = format("/use %d %d", w.bag, w.slot) }
        end
    end
end

local function Money(c)
    local ok, s = pcall(GetMoneyString, c, true)
    if ok and type(s) == "string" then return s end
    return format("%dg %ds", floor(c / 10000), floor(c / 100) % 100)
end

-- Hook for Cys's Auction House later: return a price in copper for an item, or nil. The cheapest item of each
-- crate then gets a (cheapest) tag. Nothing sets this yet.
Crates.Price = nil

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local frame, rows = nil, {}

local function ItemIcon(itemID)
    if not itemID then return nil end
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    if icon == 134400 then return nil end -- the game's "?" while it doesn't know the item yet
    return icon
end

-- Click a needed item to put it in its crate: does what right-clicking the crate and then the item in your bags
-- does. Using items is protected, so it is one secure button laid over the row you point at (out of combat only;
-- it hides itself when a fight starts).
local fill
local function RowTip(row, owner)
    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    if row.itemID then pcall(GameTooltip.SetItemByID, GameTooltip, row.itemID) end
    if row.fillMacro or row.searchName then GameTooltip:AddLine(" ") end
    if row.fillMacro then
        GameTooltip:AddLine(row.fillHint or "Click to put it in the crate", T.accent[1], T.accent[2], T.accent[3])
    end
    if row.searchName then
        GameTooltip:AddLine("Shift-click to search the Auction House", T.accent[1], T.accent[2], T.accent[3])
    end
    GameTooltip:Show()
end

-- Shift-click: the item's name goes into the Auction House search box (or a link into chat when the AH is closed)
function Crates.Search(row)
    local name = row and row.searchName
    if not name then return end
    local ah = _G.AuctionHouseFrame
    local box = ah and ah:IsShown() and ah.SearchBar and ah.SearchBar.SearchBox
    if box then
        box:SetText(name)
        box:SetFocus()
        box:HighlightText(0, 0)
        return
    end
    local link
    if row.itemID and C_Item and C_Item.GetItemInfo then
        local ok, _, l = pcall(C_Item.GetItemInfo, row.itemID)
        if ok then link = l end
    end
    if ChatEdit_InsertLink then ChatEdit_InsertLink(link or name) end
end

local function FillButton()
    if fill then return fill end
    fill = CreateFrame("Button", "CysCratesFillButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    fill:SetFrameStrata("DIALOG")
    fill:RegisterForClicks("LeftButtonUp")
    fill:SetAttribute("useOnKeyDown", false)
    fill:SetAttribute("type", "macro")
    fill:SetAttribute("shift-type1", "none") -- Shift-click searches instead of filling
    fill:HookScript("OnClick", function(self) if IsShiftKeyDown() and self.row then Crates.Search(self.row) end end)
    fill:Hide()
    fill:SetAttribute("_onstate-combat", [[ if newstate == "in" then self:Hide() end ]])
    RegisterStateDriver(fill, "combat", "[combat] in; out")
    fill:SetScript("OnEnter", function(self)
        local r = self.row
        if r and r:IsVisible() and r.itemID then r.hl:Show(); RowTip(r, self) end
    end)
    fill:SetScript("OnLeave", function(self)
        if self.row then self.row.hl:Hide() end
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
    end)
    return fill
end

local function HideFill()
    if fill and fill:IsShown() and not InCombatLockdown() then fill:Hide() end
end
Crates.HideFill = HideFill

local function ShowFill(row)
    if not row.fillMacro or InCombatLockdown() then return end
    local ok, l, b, w, h = pcall(function()
        local s = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local l, b, w, h = row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()
        -- only rows fully inside the scrolled view
        local sb, st = frame.scroll:GetBottom(), frame.scroll:GetTop()
        if b < sb - 0.5 or b + h > st + 0.5 then return nil end
        return l * s, b * s, w * s, h * s
    end)
    if not ok or not l then return end
    local f = FillButton()
    f.row = row
    f:SetAttribute("macrotext", row.fillMacro)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    f:SetSize(w, h)
    f:Show()
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, frame.content)
    r:SetHeight(ROW_H)
    r.hl = W.Texture(r, "BACKGROUND", T.hover)
    r.hl:SetAllPoints(); r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = W.Text(r, 11)
    r.name:SetWordWrap(false)
    r.right = W.Text(r, 11, { 1, 1, 1 }, "RIGHT")
    r.right:SetPoint("RIGHT", -8, 0)
    r.tag = W.Text(r, 10, T.accent, "RIGHT")
    r.tag:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r.line = W.Texture(r, "BORDER", T.line)
    r.line:SetPoint("BOTTOMLEFT", 6, 0); r.line:SetPoint("BOTTOMRIGHT", -6, 0); r.line:SetHeight(1)
    r:SetScript("OnEnter", function(self)
        if not (self.itemID or self.crate) then return end -- nothing to show for an item the game doesn't know
        self.hl:Show()
        if self.itemID then RowTip(self) end
        ShowFill(self)
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.searchName then Crates.Search(self) return end
        if self.crate then
            db.folded[self.crate] = not db.folded[self.crate] or nil
            Crates.Refresh()
        end
    end)
    rows[i] = r
    return r
end

local function Cheapest(c)
    if not Crates.Price then return nil end
    local best, bestKey
    for _, r in ipairs(c.reqs) do
        -- what it costs to buy the rest of this bundle: price each x how many you still need
        local each = r.itemID and Crates.Price(r.itemID)
        local p = each and each * max(0, r.count - (r.have or 0))
        if p and (not best or p < best) then best, bestKey = p, r.key end
    end
    return bestKey
end

function Crates.Refresh()
    HideFill()
    if not frame or not frame:IsShown() then return end
    local list = Crates.List()
    frame.header:SetShown(not db.slim)
    frame.slim:SetShown(db.slim and true or false)
    if db.slim then
        for i = 1, #rows do rows[i]:Hide() end
        frame.empty:Hide()
        frame.scroll:Hide(); frame.bar:Hide()
        local ready, total = 0, 0
        for _, c in ipairs(list) do total = total + 1; if c.ready == #c.reqs then ready = ready + 1 end end
        frame.slim.count:SetText(total)
        if total > 0 and ready == total then frame.slim.count:SetTextColor(0.35, 0.85, 0.35)
        else frame.slim.count:SetTextColor(1, 1, 1) end
        frame:SetSize(SLIM_W, 56)
        if waiting then C_Timer.After(1, Crates.Refresh) end
        return
    end
    frame:SetWidth(WIDTH)
    frame.scroll:Show()
    local y, n = TOP, 0
    for _, c in ipairs(list) do
        if n >= MAX_ROWS then break end
        n = n + 1
        local r = GetRow(n)
        r.crate, r.itemID, r.fillMacro, r.searchName = c.fold or c.itemID, c.itemID, c.startMacro, nil
        r.fillHint = c.startMacro and "Click to start the writ's quest" or nil
        r:SetHeight(CRATE_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -(y - TOP)); r:SetPoint("TOPRIGHT", -1, -(y - TOP))
        r.icon:SetSize(16, 16)
        r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexture(ItemIcon(c.itemID) or (c.writ and "Interface\\Icons\\INV_Scroll_03") or "Interface\\Icons\\INV_Crate_02")
        r.icon:Show()
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        r.name:SetText((db.folded[c.fold or c.itemID] and "+ " or "") .. (c.name or "Crate")
            .. ((c.n or 1) > 1 and format("  |cFFFFFFFFx%d|r", c.n) or ""))
        local all = c.ready == #c.reqs
        r.right:SetText(c.startMacro and "not started" or format("%d / %d", c.ready, #c.reqs))
        if all then r.right:SetTextColor(0.35, 0.85, 0.35) else r.right:SetTextColor(0.7, 0.7, 0.7) end
        r.tag:SetText("")
        r.line:Show()
        r:Show()
        y = y + CRATE_H
        if not db.folded[c.fold or c.itemID] then
            local cheap = (not c.writ and #c.reqs > 1) and Cheapest(c) or nil
            for _, q in ipairs(c.reqs) do
                if n >= MAX_ROWS then break end
                n = n + 1
                local s = GetRow(n)
                s.crate, s.itemID, s.searchName, s.fillHint = nil, q.itemID, q.name, nil
                local from, to = spotByID[c.itemID], spotByKey[q.key]
                s.fillMacro = (not c.writ and from and to and q.have > 0)
                    and format("/use %d %d\n/use %d %d", from[1], from[2], to[1], to[2]) or nil
                s:SetHeight(ROW_H)
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", 1, -(y - TOP)); s:SetPoint("TOPRIGHT", -1, -(y - TOP))
                s.icon:SetSize(14, 14)
                s.icon:ClearAllPoints(); s.icon:SetPoint("LEFT", 22, 0)
                local tex = ItemIcon(q.itemID)
                s.icon:SetTexture(tex)
                s.icon:SetShown(tex ~= nil)
                if not tex and q.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                    tries[q.itemID] = (tries[q.itemID] or 0) + 1
                    if tries[q.itemID] <= 5 then C_Item.RequestLoadItemDataByID(q.itemID); waiting = true end
                end
                s.name:ClearAllPoints(); s.name:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
                s.name:SetPoint("RIGHT", s.tag, "LEFT", -6, 0)
                s.name:SetTextColor(0.9, 0.9, 0.9)
                s.name:SetText(q.count and format("|cFFBBBBBB%d|r  %s", q.count, q.name) or q.name)
                s.right:SetText(format("(%d)", q.have))
                if not q.count then s.right:SetTextColor(1, 1, 1)
                elseif q.have >= q.count then s.right:SetTextColor(0.35, 0.85, 0.35)
                elseif q.have > 0 then s.right:SetTextColor(0.95, 0.75, 0.3)
                else s.right:SetTextColor(0.85, 0.35, 0.3) end
                local tag = cheap == q.key and "(cheapest)" or ""
                if c.writ and Crates.Price and q.itemID then
                    -- writs: what the rest costs on the AH (or one, before the quest says how many)
                    local each = Crates.Price(q.itemID)
                    local need = q.count and max(0, q.count - q.have) or 1
                    if each and need > 0 then tag = Money(each * need) end
                end
                s.tag:SetText(tag)
                s.line:Hide()
                s:Show()
                y = y + ROW_H
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local anyOpen = false
    for _, c in ipairs(list) do if not db.folded[c.fold or c.itemID] then anyOpen = true break end end
    local fold = frame.fold
    fold.collapse = anyOpen
    fold.text:SetText(anyOpen and "Collapse all" or "Expand all")
    fold:SetWidth((fold.text:GetStringWidth() or 60) + 4)
    fold:SetShown(#list > 1)
    frame.empty:SetShown(#list == 0)
    if #list == 0 then y = y + 30 end
    -- never taller than the bags (docked) or the bags height cap; scroll the rest
    local listH = y - TOP
    local viewH = max(ROW_H * 3, min(listH, Crates.MaxHeight() - TOP - 8))
    local over = listH > viewH + 0.5
    frame.scroll:SetHeight(viewH)
    frame.content:SetHeight(max(listH, 1))
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", 0, -TOP)
    frame.scroll:SetPoint("TOPRIGHT", over and -(BAR_W + 4) or 0, -TOP)
    frame.content:SetWidth(WIDTH - (over and (BAR_W + 4) or 0))
    frame.maxScroll = over and (listH - viewH) or 0
    Crates.SetScroll(frame.scroll:GetVerticalScroll() or 0)
    frame:SetHeight(TOP + viewH + 8)
    if waiting then C_Timer.After(1, Crates.Refresh) end -- some crate tooltips were still loading
end

-- How tall the window may be: as tall as Cys's Bags while docked, else the bags height cap.
local function SafeHeight(f)
    local ok, h = pcall(function()
        local v = f:GetHeight() * f:GetEffectiveScale() / frame:GetEffectiveScale()
        if v > 0 then return v end
    end)
    return ok and h or nil
end
function Crates.MaxHeight()
    local bags = _G.CysBagsFrame
    if frame and frame.docked and bags and bags:IsShown() then
        local h = SafeHeight(bags)
        if h then return h end
    end
    local auto = CysUIDB.automation
    return (auto and tonumber(auto.bagsMaxH)) or 650
end

function Crates.SetScroll(v)
    if not frame then return end
    local m = frame.maxScroll or 0
    v = max(0, min(v or 0, m))
    if v ~= frame.scroll:GetVerticalScroll() then HideFill() end
    frame.scroll:SetVerticalScroll(v)
    local bar, thumb = frame.bar, frame.thumb
    if m <= 0 then bar:Hide(); return end
    bar:Show()
    local track = frame.scroll:GetHeight()
    local th = max(20, track * track / (track + m))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -((track - th) * v / m))
end

local function BuildWindow()
    local f = CreateFrame("Frame", "CysCratesFrame", UIParent)
    frame = f
    f:SetSize(WIDTH, 120)
    f:SetFrameStrata("HIGH") -- same layer as Cys's Bags: drawn over action bars, chat and the like
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if db.pos then f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 60) end
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.94 }):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local header = CreateFrame("Frame", nil, f)
    f.header = header
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    W.Texture(header, "BACKGROUND", T.header):SetAllPoints()
    local hline = W.Texture(header, "BORDER", T.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not f.docked then f:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        if f.docked then return end
        f:StopMovingOrSizing()
        local p, _, rp, x, yy = f:GetPoint(1)
        if p then db.pos = { p, rp, x, yy } end
    end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\INV_Crate_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = W.Text(header, 12, T.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Crate Tracker")
    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function()
        f:Hide()
        Crates.closedWith = #Crates.List() -- don't pop straight back up for the same crates (until the bags reopen)
    end)

    -- one toggle: Collapse all while any crate is open, Expand all when all are folded
    local fold = CreateFrame("Button", nil, header)
    fold:SetHeight(20)
    fold:SetPoint("RIGHT", close, "LEFT", -6, 0)
    fold.text = W.Text(fold, 10, T.dim, "RIGHT")
    fold.text:SetPoint("RIGHT")
    fold:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
    fold:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    fold:SetScript("OnClick", function(s)
        for _, c in ipairs(Crates.List()) do db.folded[c.fold or c.itemID] = s.collapse or nil end
        Crates.Refresh()
    end)
    f.fold = fold

    -- fold the window down to a small strip (the bags sidebar does the same); click the strip to open it again
    local slimBtn = CreateFrame("Button", nil, header)
    slimBtn:SetSize(18, 20)
    slimBtn:SetPoint("RIGHT", fold, "LEFT", -6, 0)
    slimBtn.text = W.Text(slimBtn, 13, T.dim, "CENTER")
    slimBtn.text:SetPoint("CENTER")
    slimBtn.text:SetText(">")
    slimBtn:SetScript("OnEnter", function(s)
        s.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Fold to a small strip", 1, 1, 1)
        GameTooltip:Show()
    end)
    slimBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]); GameTooltip:Hide() end)
    slimBtn:SetScript("OnClick", function() db.slim = true; GameTooltip:Hide(); Crates.Refresh() end)

    local slim = CreateFrame("Button", nil, f)
    slim:SetAllPoints()
    slim:Hide()
    slim.icon = slim:CreateTexture(nil, "ARTWORK")
    slim.icon:SetSize(20, 20)
    slim.icon:SetPoint("TOP", 0, -7)
    slim.icon:SetTexture("Interface\\Icons\\INV_Crate_02")
    slim.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slim.count = W.Text(slim, 12, { 1, 1, 1 }, "CENTER")
    slim.count:SetPoint("TOP", slim.icon, "BOTTOM", 0, -4)
    slim.hl = slim:CreateTexture(nil, "HIGHLIGHT")
    slim.hl:SetAllPoints()
    slim.hl:SetColorTexture(1, 1, 1, 0.06)
    slim:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Crate Tracker", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Click to open it again", 1, 1, 1)
        GameTooltip:Show()
    end)
    slim:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slim:SetScript("OnClick", function() db.slim = nil; GameTooltip:Hide(); Crates.Refresh() end)
    f.slim = slim

    -- the list scrolls when it is taller than the window may be
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 0, -TOP); scroll:SetPoint("TOPRIGHT", 0, -TOP)
    scroll:SetHeight(100)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        Crates.SetScroll(scroll:GetVerticalScroll() - delta * ROW_H * 3)
    end)
    f.scroll, f.content = scroll, content

    local bar = CreateFrame("Frame", nil, f)
    bar:SetWidth(BAR_W)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", BAR_W + 2, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", BAR_W + 2, 0)
    W.Texture(bar, "BACKGROUND", { 1, 1, 1, 0.06 }):SetAllPoints()
    bar:EnableMouse(true)
    bar:Hide()
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(BAR_W)
    thumb.tex = W.Texture(thumb, "ARTWORK", { T.accent[1], T.accent[2], T.accent[3], 0.55 })
    thumb.tex:SetAllPoints()
    thumb:SetScript("OnEnter", function(s) s.tex:SetAlpha(1) end)
    thumb:SetScript("OnLeave", function(s) if not s.drag then s.tex:SetAlpha(0.55) end end)
    local function CursorY() local _, cy = GetCursorPosition(); return cy / bar:GetEffectiveScale() end
    thumb:SetScript("OnMouseDown", function(s)
        s.drag, s.startY, s.startScroll = true, CursorY(), scroll:GetVerticalScroll()
        s:SetScript("OnUpdate", function()
            local track = bar:GetHeight() - s:GetHeight()
            if track <= 0 then return end
            Crates.SetScroll(s.startScroll + (s.startY - CursorY()) / track * (f.maxScroll or 0))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(s)
        s.drag = nil; s:SetScript("OnUpdate", nil)
        if not s:IsMouseOver() then s.tex:SetAlpha(0.55) end
    end)
    -- clicking the track pages up / down
    bar:SetScript("OnMouseDown", function()
        local page = scroll:GetHeight() - ROW_H
        if CursorY() > thumb:GetTop() then page = -page end
        Crates.SetScroll(scroll:GetVerticalScroll() + page)
    end)
    f.bar, f.thumb = bar, thumb

    f.empty = W.Text(f, 11, T.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -(HEADER_H + 14))
    f.empty:SetText("No crates to fill in your bags.")
    f:SetScript("OnShow", Crates.Refresh)
    f:HookScript("OnHide", HideFill)
end


-- Docked: beside Cys's Bags (left side, top edges lined up; right side when the bags are near the left edge)
local function Bags() return _G.CysBagsFrame end

local function Place()
    if not frame then return end
    local bags = Bags()
    frame:ClearAllPoints()
    if db.show == "bags" and bags and bags:IsShown() then
        frame.docked = true
        local left = bags:GetLeft() or 0
        local scale = (bags:GetEffectiveScale() or 1) / (frame:GetEffectiveScale() or 1)
        if left * scale < WIDTH + 10 then
            frame:SetPoint("TOPLEFT", bags, "TOPRIGHT", 4, 0)
        else
            frame:SetPoint("TOPRIGHT", bags, "TOPLEFT", -4, 0)
        end
    else
        frame.docked = false
        if db.pos then frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        else frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 60) end
    end
end

local function AutoShow()
    if db.show == "manual" then return end
    local count = #Crates.List()
    if db.show == "bags" then
        local bags = Bags()
        local want = bags and bags:IsShown() and count > 0 and not Crates.closedWith
        if want then
            if not frame then BuildWindow() end
            Place()
            if not frame:IsShown() then frame:Show() end
        elseif frame and frame:IsShown() and frame.docked then
            frame:Hide()
        end
        return
    end
    -- "crate": open while a crate is in your bags (unless you closed it), close when the last one is gone
    if count == 0 then
        Crates.closedWith = nil
        if frame and frame:IsShown() then frame:Hide() end
    elseif not (Crates.closedWith and count <= Crates.closedWith) then
        if not frame then BuildWindow() end
        Place()
        if not frame:IsShown() then frame:Show() end
    end
end

-- follow Cys's Bags opening and closing (the window is made when the bags first open)
local hookedBags = false
local function HookBags()
    local bags = Bags()
    if hookedBags or not bags then return end
    hookedBags = true
    bags:HookScript("OnShow", function()
        Crates.closedWith = nil -- the X only keeps it closed until the bags open again
        C_Timer.After(0, AutoShow)
    end)
    bags:HookScript("OnHide", function()
        if frame and frame:IsShown() and frame.docked then frame:Hide() end
    end)
    bags:HookScript("OnSizeChanged", function()
        if frame and frame:IsShown() and frame.docked then Crates.Refresh() end
    end)
end
Crates.HookBags = HookBags

function Crates.Toggle()
    if not frame then BuildWindow() end
    if not frame:IsShown() then Place() end
    frame:SetShown(not frame:IsShown())
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued = false
ev:SetScript("OnEvent", function(_, e)
    if e == "GET_ITEM_INFO_RECEIVED" and not waiting then return end
    if queued then return end
    queued = true
    C_Timer.After(e == "PLAYER_ENTERING_WORLD" and 3 or 0.4, function()
        queued = false
        HookBags()
        AutoShow()
        Crates.Refresh()
    end)
end)

SLASH_CYSCRATES1 = "/cuicrates"
SlashCmdList.CYSCRATES = function() Crates.Toggle() end

CUI:RegisterPage("Crate Tracker", function(page)
    local width = 480
    W.Header(page, "Crate Tracker", width):SetPoint("TOPLEFT", 0, -4)
    local lab = W.Text(page, 12, T.accent)
    lab:SetPoint("TOPLEFT", 4, -38)
    lab:SetText("Show")
    W.Dropdown(page, 300, {
        { "bags", "with my bags (docked beside them)" },
        { "crate", "whenever a crate is in my bags" },
        { "manual", "only when I open it (/cuicrates)" },
    }, function() return db.show end, function(v)
        db.show = v
        Crates.closedWith = nil
        if frame and frame:IsShown() then frame:Hide() end
        HookBags(); AutoShow()
    end):SetPoint("TOPLEFT", 60, -34)
    local open = W.Button(page, 130, 22, "Open the window", true)
    open:SetPoint("TOPLEFT", 4, -72)
    open:SetScript("OnClick", function() if not (frame and frame:IsShown()) then Crates.Toggle() end end)
    W.Notes(page, 4, -108, width, "", {
        "Lists every crate in your bags that asks to be filled (Waylaid crates and the like), what it needs, and how many you carry: green when you have enough, yellow when you have some, red when you have none.",
        "With my bags: it opens and closes with Cys's Bags, docked to their side, and only when you have a crate. The X keeps it closed until you open your bags again.",
        "Click a crate's name to fold it. When it isn't docked, drag the window by its title. /cuicrates opens it any time.",
        "What a crate needs is read from its own tooltip, so new crates work without an update.",
    })
end, function() end)

    end,
})
