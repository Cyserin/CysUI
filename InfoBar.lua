--------------------------------------------------------------------------------
-- Cys's UI - Info Bar
--
-- A slim bar of small readouts ("datatexts"): combat timer, guild and friends online,
-- durability, bag slots, gold, FPS / latency and a clock. Hover for details, click to
-- open the matching window. Pick which ones show (and their order) under /cui > Info Bar;
-- move and resize the bar with /cui layout.
--
-- Add a new readout by adding an entry to DT below: name, update() -> text, and
-- optionally events, timed (refresh every second), tooltip(tip) and click().
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min

local IB = {}
CUI.InfoBar = IB

local GOLD, WHITE = "|cFFFFD100", "|cFFFFFFFF"
local GREEN, ORANGE, RED = "|cFF4FD66B", "|cFFFF9F43", "|cFFFF4040"

local function Label(name, value) return GOLD .. name .. "|r " .. WHITE .. value .. "|r" end

--------------------------------------------------------------------------------
-- API compatibility
--------------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetNumFreeSlots = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local FL = C_FriendList

local function ShortName(name)
    return (Ambiguate and Ambiguate(name, "short")) or name
end

local function ClassColored(name, classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then
        return format("|cFF%02x%02x%02x%s|r", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), name)
    end
    return name
end

local function HeaderLine(tip, text)
    tip:AddLine(text, T.accent[1], T.accent[2], T.accent[3])
end

--------------------------------------------------------------------------------
-- Readouts
--------------------------------------------------------------------------------
local DT = {}
IB.readouts = DT

-- Combat timer ---------------------------------------------------------------
DT.combat = {
    name = "Combat timer",
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    timed = true,
    update = function()
        local d = IB.inCombat and (GetTime() - (IB.combatStart or GetTime())) or (IB.lastCombat or 0)
        return Label("Combat:", format("%02d:%02d:%02d", floor(d / 3600), floor(d / 60) % 60, floor(d) % 60))
    end,
}

-- Guild ----------------------------------------------------------------------
DT.guild = {
    name = "Guild online",
    events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
    update = function()
        if not IsInGuild() then return "|cFF777777No guild|r" end
        local _, online = GetNumGuildMembers()
        return Label("Guild:", tostring(online or 0))
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Guild")
        if not IsInGuild() then tip:AddLine("You're not in a guild.", 0.7, 0.7, 0.7) return end
        local total = GetNumGuildMembers() or 0
        local shown = 0
        for i = 1, total do
            local name, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if online and name then
                shown = shown + 1
                if shown > 40 then tip:AddLine("...", 0.7, 0.7, 0.7) break end
                tip:AddDoubleLine(format("%s |cFF999999%s|r", ClassColored(ShortName(name), classFile), tostring(level or "")),
                    zone or "", 1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        if shown == 0 then tip:AddLine("Nobody else is online.", 0.7, 0.7, 0.7) end
    end,
    click = function()
        if ToggleGuildFrame then ToggleGuildFrame() elseif ToggleFriendsFrame then ToggleFriendsFrame(3) end
    end,
}

-- Friends --------------------------------------------------------------------
local function FriendCounts()
    if FL and FL.GetNumOnlineFriends then
        return FL.GetNumOnlineFriends() or 0, (FL.GetNumFriends and FL.GetNumFriends()) or 0
    end
    local total, online = (GetNumFriends and GetNumFriends()) or 0, 0
    for i = 1, total do
        local _, _, _, _, connected = GetFriendInfo(i)
        if connected then online = online + 1 end
    end
    return online, total
end

DT.friends = {
    name = "Friends online",
    events = { "FRIENDLIST_UPDATE" },
    update = function()
        local online = FriendCounts()
        return Label("Friends:", tostring(online))
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Friends")
        local _, total = FriendCounts()
        local shown = 0
        for i = 1, total do
            local name, level, class, area, connected
            if FL and FL.GetFriendInfoByIndex then
                local info = FL.GetFriendInfoByIndex(i)
                if info then name, level, class, area, connected = info.name, info.level, info.className, info.area, info.connected end
            elseif GetFriendInfo then
                name, level, class, area, connected = GetFriendInfo(i)
            end
            if connected and name then
                shown = shown + 1
                tip:AddDoubleLine(format("%s |cFF999999%s %s|r", name, tostring(level or ""), class or ""), area or "",
                    1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        if shown == 0 then tip:AddLine("Nobody is online.", 0.7, 0.7, 0.7) end
    end,
    click = function() if ToggleFriendsFrame then ToggleFriendsFrame(1) end end,
}

-- Durability -----------------------------------------------------------------
local DURA_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local SLOT_NAMES = { [1] = "Head", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
                     [9] = "Wrists", [10] = "Hands", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged" }

local function PercentColor(p)
    if p >= 75 then return GREEN elseif p >= 40 then return GOLD elseif p >= 20 then return ORANGE end
    return RED
end

local function ReadDurability()
    local sum, n, list = 0, 0, {}
    for _, slot in ipairs(DURA_SLOTS) do
        local cur, mx = GetInventoryItemDurability(slot)
        if cur and mx and mx > 0 then
            local pct = cur / mx * 100
            sum, n = sum + pct, n + 1
            list[#list + 1] = { slot = slot, pct = pct }
        end
    end
    return n > 0 and (sum / n) or nil, list
end

DT.durability = {
    name = "Durability",
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    update = function()
        local avg = ReadDurability()
        if not avg then return GOLD .. "Durability:|r |cFF777777-|r" end
        return GOLD .. "Durability:|r " .. PercentColor(avg) .. floor(avg + 0.5) .. "%|r"
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Durability")
        local avg, list = ReadDurability()
        if not avg then tip:AddLine("Nothing you wear can break.", 0.7, 0.7, 0.7) return end
        for _, e in ipairs(list) do
            tip:AddDoubleLine(SLOT_NAMES[e.slot] or ("Slot " .. e.slot), PercentColor(e.pct) .. floor(e.pct + 0.5) .. "%|r", 1, 1, 1)
        end
    end,
    click = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end,
}

-- Bag slots ------------------------------------------------------------------
local function BagCounts()
    local free, total = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        total = total + (GetNumSlots(bag) or 0)
        free = free + ((GetNumFreeSlots(bag)) or 0)
    end
    return free, total
end

DT.bags = {
    name = "Bag slots",
    events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
    update = function()
        local free, total = BagCounts()
        local color = free <= 3 and RED or WHITE
        return GOLD .. "Bags:|r " .. color .. free .. "|r" .. WHITE .. "/" .. total .. "|r"
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Bag slots")
        local free, total = BagCounts()
        tip:AddDoubleLine("Free", tostring(free), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Total", tostring(total), 1, 1, 1, 1, 1, 1)
    end,
    click = function() if ToggleAllBags then ToggleAllBags() end end,
}

-- Gold -----------------------------------------------------------------------
DT.gold = {
    name = "Gold",
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    update = function() return GetCoinTextureString(GetMoney()) end,
    tooltip = function(tip)
        HeaderLine(tip, "Gold")
        local diff = GetMoney() - (IB.startMoney or GetMoney())
        local color = diff >= 0 and GREEN or RED
        tip:AddDoubleLine("This session", color .. (diff >= 0 and "+" or "-") .. GetCoinTextureString(math.abs(diff)) .. "|r", 1, 1, 1)
    end,
}

-- FPS and latency ------------------------------------------------------------
DT.fps = {
    name = "FPS and latency",
    timed = true,
    update = function()
        local _, _, home, world = GetNetStats()
        local ms = max(home or 0, world or 0)
        local color = ms < 100 and GREEN or (ms < 250 and GOLD or RED)
        return Label("FPS:", tostring(floor(GetFramerate() + 0.5))) .. "  " .. GOLD .. "MS:|r " .. color .. ms .. "|r"
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Performance")
        local _, _, home, world = GetNetStats()
        tip:AddDoubleLine("Home latency", (home or 0) .. " ms", 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("World latency", (world or 0) .. " ms", 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Frame rate", floor(GetFramerate() + 0.5) .. " fps", 1, 1, 1, 1, 1, 1)
    end,
}

-- Clock ----------------------------------------------------------------------
DT.clock = {
    name = "Clock",
    timed = true,
    update = function()
        local use24h = CysUIDB.infobar.use24h
        local text = date(use24h and "%H:%M" or "%I:%M %p")
        if not use24h then text = text:gsub("^0", "") end -- 8:46 AM, but keep 08:46 in 24-hour time
        return WHITE .. text .. "|r"
    end,
    tooltip = function(tip)
        HeaderLine(tip, "Time")
        tip:AddDoubleLine("Local", date("%A %H:%M"), 1, 1, 1, 1, 1, 1)
        if GetGameTime then
            local h, m = GetGameTime()
            tip:AddDoubleLine("Server", format("%02d:%02d", h or 0, m or 0), 1, 1, 1, 1, 1, 1)
        end
    end,
}

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------
local bars = {}                 -- [1] the main bar, [2] the bar under the minimap
local buttons = {}
local seps = { {}, {} }
local readoutEvents = {} -- event -> list of readout keys

-- which readouts start on the second (minimap) bar
local DEFAULT_SECOND = { guild = true, friends = true, clock = true }

local function DB() return CysUIDB.infobar end

-- which bar a readout sits on (1 or 2)
local function SlotOf(key)
    local db = DB()
    db.slot = db.slot or {}
    if db.slot[key] == nil then db.slot[key] = DEFAULT_SECOND[key] and 2 or 1 end
    return db.slot[key]
end

local function VisibleKeys(slot)
    local keys = {}
    for _, key in ipairs(DB().order) do
        if DT[key] and DB().enabled[key] and SlotOf(key) == slot then keys[#keys + 1] = key end
    end
    return keys
end

local function AnyShown()
    return (bars[1] and bars[1]:IsShown()) or (bars[2] and bars[2]:IsShown())
end

local function GetButton(key)
    local b = buttons[key]
    if b then return b end
    b = CreateFrame("Button", nil, bars[SlotOf(key)] or bars[1])
    b.text = W.Text(b, 11, T.text, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        local dt = DT[key]
        if dt.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            dt.tooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        local dt = DT[key]
        if dt.click then pcall(dt.click) end
    end)
    buttons[key] = b
    return b
end

-- text size follows the bar's height, and shrinks (down to 8) if a readout would overflow its slot
local function FitText(b)
    local size = max(8, min(12, floor(b:GetHeight() * 0.46 + 0.5)))
    local room = max(b:GetWidth() - 8, 20)
    b.text:SetFont(STANDARD_TEXT_FONT, size, "")
    while size > 8 and b.text:GetStringWidth() > room do
        size = size - 1
        b.text:SetFont(STANDARD_TEXT_FONT, size, "")
    end
end

function IB:UpdateItem(key)
    local b = buttons[key]
    if not (b and b:IsShown()) then return end
    local ok, text = pcall(DT[key].update)
    b.text:SetText(ok and text or (RED .. "error|r"))
    FitText(b)
end

function IB:Layout()
    for _, b in pairs(buttons) do b:Hide() end
    for slot = 1, 2 do for _, sep in ipairs(seps[slot]) do sep:Hide() end end
    for slot = 1, 2 do
        local bar = bars[slot]
        local keys = VisibleKeys(slot)
        local n = #keys
        if bar and n > 0 then
            local barW, h = bar:GetWidth(), bar:GetHeight()
            local function Edge(i) return floor((i - 1) * barW / n + 0.5) end -- whole pixels, so text and rules line up
            for i, key in ipairs(keys) do
                local b = GetButton(key)
                b:SetParent(bar)
                b:ClearAllPoints()
                b:SetSize(max(Edge(i + 1) - Edge(i), 4), max(h - 2, 4))
                b:SetPoint("LEFT", bar, "LEFT", Edge(i), 0)
                b:Show()
                self:UpdateItem(key)
                if i > 1 then
                    local sep = seps[slot][i - 1]
                    if not sep then
                        sep = W.Texture(bar, "ARTWORK", T.border) -- gold, like the micro menu's
                        sep:SetWidth(1)
                        seps[slot][i - 1] = sep
                    end
                    sep:ClearAllPoints()
                    sep:SetHeight(max(h - 6, 4))
                    sep:SetPoint("LEFT", bar, "LEFT", Edge(i), 0)
                    sep:Show()
                end
            end
        end
    end
end

function IB:Apply()
    if not bars[1] then return end
    bars[1]:SetShown(DB().shown and #VisibleKeys(1) > 0)
    if bars[2] then bars[2]:SetShown(DB().shown and #VisibleKeys(2) > 0) end
    self:Layout()
end

local function RequestRosters()
    if IsInGuild and IsInGuild() then
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    end
    if FL and FL.ShowFriends then FL.ShowFriends() elseif ShowFriends then ShowFriends() end
end

function IB.Enable()
    local db = DB()
    -- readouts added in a later update appear in the list automatically
    local have = {}
    for _, k in ipairs(db.order) do have[k] = true end
    for k in pairs(DT) do
        if not have[k] then
            db.order[#db.order + 1] = k
            if db.enabled[k] == nil then db.enabled[k] = true end
        end
    end
    IB.startMoney = GetMoney()

    local function MakeBar(slot, name, key, label, width, opts)
        local bar = CreateFrame("Frame", name, UIParent)
        bar:SetSize(width, 24)
        bar:SetFrameStrata("LOW")
        W.Texture(bar, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
        W.Border(bar, 1, T.border, "BORDER")
        opts.resizable = true
        opts.onResize = function() IB:Layout() end
        CUI:RegisterMovable(bar, key, label, opts)
        bars[slot] = bar
    end
    -- the main bar, and a second one that starts just under the minimap
    MakeBar(1, "CysUIInfoBar", "infobar", "Info Bar", 560,
        { point = "BOTTOM", x = 0, y = 6, minW = 200, maxW = 2000, minH = 18, maxH = 40 })
    MakeBar(2, "CysUIInfoBar2", "infobar2", "Info Bar (minimap)", 180,
        { point = "TOPRIGHT", x = -24, y = -211, minW = 100, maxW = 2000, minH = 18, maxH = 40 })
    IB:Apply()

    local f = CreateFrame("Frame")
    for key, dt in pairs(DT) do
        for _, ev in ipairs(dt.events or {}) do
            if not readoutEvents[ev] then
                readoutEvents[ev] = {}
                pcall(f.RegisterEvent, f, ev) -- skip events a client doesn't have
            end
            table.insert(readoutEvents[ev], key)
        end
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            IB.inCombat, IB.combatStart = true, GetTime()
        elseif event == "PLAYER_REGEN_ENABLED" then
            IB.inCombat = false
            IB.lastCombat = GetTime() - (IB.combatStart or GetTime())
        end
        if not AnyShown() then return end
        for _, key in ipairs(readoutEvents[event] or {}) do IB:UpdateItem(key) end
    end)

    -- once a second: the clock, the combat timer and FPS (only while the bar is visible)
    C_Timer.NewTicker(1, function()
        if not AnyShown() then return end
        for key, b in pairs(buttons) do
            if b:IsShown() and DT[key].timed then IB:UpdateItem(key) end
        end
    end)
    -- guild and friend lists only update when asked
    RequestRosters()
    C_Timer.NewTicker(60, RequestRosters)
end

CUI:RegisterModule({
    key = "infobar",
    name = "Info Bar",
    addon = "CysUI",
    desc = "Slim bars with combat timer, guild and friends online, durability, bag slots, gold, FPS / latency and a clock. Split them over a main bar and a bar under the minimap.",
    onEnable = IB.Enable,
    open = function() CUI:OpenConfig("Info Bar") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Info Bar", function(page)
    local db = DB()
    local width = 480

    W.Header(page, "Info Bar", width):SetPoint("TOPLEFT", 0, -4)

    local show = W.Checkbox(page, "Show the info bars", function() return db.shown end,
        function(on) db.shown = on; IB:Apply() end)
    show:SetPoint("TOPLEFT", 4, -34)
    local h24 = W.Checkbox(page, "24-hour clock", function() return db.use24h end,
        function(on) db.use24h = on; IB:UpdateItem("clock") end)
    h24:SetPoint("TOPLEFT", 4, -60)

    local move = W.Button(page, 280, 22, "Move and resize both bars (layout mode)")
    move:SetPoint("TOPLEFT", 4, -90)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    W.Header(page, "Items - tick to show, pick a bar, reorder with the arrows", width):SetPoint("TOPLEFT", 0, -128)

    local rows = {}
    local function RefreshRows()
        for i, row in ipairs(rows) do
            local key = db.order[i]
            row.key = key
            row.cb.label:SetText(DT[key] and DT[key].name or key)
            row.cb:SetWidth(24 + max(row.cb.label:GetStringWidth(), 40))
            row.cb:Refresh()
            row.up:SetActive(i > 1)
            row.down:SetActive(i < #rows)
            row.slot:SetLabel(SlotOf(key) == 1 and "Main bar" or "Minimap bar")
            row.slot:SetPrimary(SlotOf(key) == 2)
        end
    end
    local function Move(i, delta)
        local order = db.order
        order[i], order[i + delta] = order[i + delta], order[i]
        RefreshRows()
        IB:Layout()
    end
    for i = 1, #db.order do
        local row = {}
        row.cb = W.Checkbox(page, "", function() return db.enabled[row.key] end,
            function(on) db.enabled[row.key] = on; IB:Apply() end)
        row.cb:SetPoint("TOPLEFT", 4, -156 - (i - 1) * 26)
        row.slot = W.Button(page, 100, 20, "Main bar")
        row.slot:SetPoint("TOPLEFT", 180, -156 - (i - 1) * 26)
        row.slot:SetScript("OnClick", function()
            db.slot[row.key] = SlotOf(row.key) == 1 and 2 or 1
            RefreshRows()
            IB:Apply()
        end)
        row.up = W.Button(page, 44, 20, "Up")
        row.up:SetPoint("TOPLEFT", 296, -156 - (i - 1) * 26)
        row.up:SetScript("OnClick", function() Move(i, -1) end)
        row.down = W.Button(page, 44, 20, "Down")
        row.down:SetPoint("LEFT", row.up, "RIGHT", 6, 0)
        row.down:SetScript("OnClick", function() Move(i, 1) end)
        rows[i] = row
    end
    RefreshRows()
end)
