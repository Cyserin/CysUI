--------------------------------------------------------------------------------
-- Cys's UI - Friends
--
-- A light friends window in the Cys look: friends (game + Battle.net), ignore list.
-- Opens with /cfriends and (optionally) the Social key. Blizzard's own friends window is
-- left untouched, so it stays available as a fallback.
--
-- Settings live in CysUIDB.friends and on the Friends page of /cui.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local F = {}
CUI.Friends = F

local floor, max, min = math.floor, math.max, math.min
local format = string.format

local ROW_H = 34
local TOP = 86     -- space above the list (title, tabs, search)
local BOTTOM = 44  -- space below the list (buttons)

local function DB()
    CysUIDB.friends = CysUIDB.friends or {}
    local d = CysUIDB.friends
    if d.collapsed == nil then d.collapsed = {} end
    if d.takeKey == nil then d.takeKey = true end
    if d.groupByGame == nil then d.groupByGame = true end
    return d
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local classFile = {}
local function BuildClassMap()
    for _, tbl in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for file, name in pairs(tbl) do classFile[name] = file end
    end
end

local function ClassColor(className, fileToken)
    local file = fileToken or (className and classFile[className])
    local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if c then return c.r, c.g, c.b end
    return T.text[1], T.text[2], T.text[3]
end

local function Hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local DIM = Hex(0.66, 0.66, 0.66) -- secondary text: light enough to read on the dark panel
local LIGHT = Hex(0.82, 0.82, 0.82)

local function Ago(t)
    if not t or t <= 0 then return nil end
    local d = time() - t
    if d < 0 then return nil end
    if d < 3600 then return format("%dm ago", max(1, floor(d / 60))) end
    if d < 86400 then return format("%dh ago", floor(d / 3600)) end
    return format("%dd ago", floor(d / 86400))
end

local function Print(msg) CUI:Print(msg) end

local LegacyAddFriend, LegacyAddIgnore = AddFriend, AddIgnore -- old globals (our functions below share the names)

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local function CollectFriends()
    local list = {}
    local C = C_FriendList
    local n = (C and C.GetNumFriends and C.GetNumFriends()) or (GetNumFriends and GetNumFriends()) or 0
    for i = 1, n do
        local e
        local info = C and C.GetFriendInfoByIndex and C.GetFriendInfoByIndex(i)
        if info then
            e = { kind = "wow", name = info.name, level = info.level, class = info.className, area = info.area,
                online = info.connected, note = info.notes, afk = info.afk, dnd = info.dnd }
        elseif GetFriendInfo then
            local name, level, class, area, connected, status, note = GetFriendInfo(i)
            if name then
                e = { kind = "wow", name = name, level = level, class = class, area = area, online = connected, note = note,
                    afk = status and status:find("AFK") and true or false, dnd = status and status:find("DND") and true or false }
            end
        end
        if e and e.name then
            e.char, e.sameGame = e.name, true
            e.key = "w:" .. e.name
            list[#list + 1] = e
        end
    end

    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        local nb = BNGetNumFriends() or 0
        for i = 1, nb do
            local a = C_BattleNet.GetFriendAccountInfo(i)
            if a then
                local g = a.gameAccountInfo or {}
                local same = g.isOnline and g.characterName and g.characterName ~= ""
                    and (not (g.wowProjectID and WOW_PROJECT_ID) or g.wowProjectID == WOW_PROJECT_ID)
                    and (g.clientProgram == nil or g.clientProgram == "" or g.clientProgram == "WoW") or false
                list[#list + 1] = {
                    kind = "bnet", id = a.bnetAccountID, account = a.accountName, tag = a.battleTag,
                    name = a.accountName or a.battleTag or "?", online = g.isOnline and true or false,
                    note = a.note, fav = a.isFavorite, afk = a.isAFK or g.isGameAFK, dnd = a.isDND or g.isGameBusy,
                    client = g.clientProgram, project = g.wowProjectID, char = g.characterName, class = g.className,
                    level = g.characterLevel, area = g.areaName, presence = g.richPresence,
                    sameGame = same and true or false, lastOnline = a.lastOnlineTime,
                    key = "b:" .. tostring(a.bnetAccountID),
                }
            end
        end
    end
    return list
end

local function CollectIgnores()
    local list = {}
    local C = C_FriendList
    local n = (C and C.GetNumIgnores and C.GetNumIgnores()) or (GetNumIgnores and GetNumIgnores()) or 0
    for i = 1, n do
        local name = (C and C.GetIgnoreName and C.GetIgnoreName(i)) or (GetIgnoreName and GetIgnoreName(i))
        if name then list[#list + 1] = { kind = "ignore", name = name, key = "i:" .. name } end
    end
    return list
end

local function CollectWho()
    local list, total = {}, 0
    local C = C_FriendList
    local n, tot
    if C and C.GetNumWhoResults then n, tot = C.GetNumWhoResults() elseif GetNumWhoResults then n, tot = GetNumWhoResults() end
    n = tonumber(n) or 0
    total = tonumber(tot) or n
    for i = 1, n do
        local e
        local info = C and C.GetWhoInfo and C.GetWhoInfo(i)
        if info then
            e = { name = info.fullName, guild = info.fullGuildName, level = info.level, race = info.raceStr,
                class = info.classStr, area = info.area, file = info.filename }
        elseif GetWhoInfo then
            local name, guild, level, race, class, zone, file = GetWhoInfo(i)
            if name then e = { name = name, guild = guild, level = level, race = race, class = class, area = zone, file = file } end
        end
        if e and e.name then
            e.kind, e.online, e.char, e.sameGame, e.key = "who", true, e.name, true, "p:" .. e.name
            list[#list + 1] = e
        end
    end
    return list, total
end

local function AgoParts(y, mo, d, h)
    if y and y > 0 then return y .. "y ago" end
    if mo and mo > 0 then return mo .. "mo ago" end
    if d and d > 0 then return d .. "d ago" end
    if h and h > 0 then return h .. "h ago" end
    return "<1h ago"
end

local function CollectGuild()
    local list, online = {}, 0
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, rankIndex, level, class, zone, note, _, isOnline, status, file = GetGuildRosterInfo(i)
        if name then
            local e = { kind = "guild", name = name, rank = rank, rankIndex = rankIndex or 99, level = level, class = class,
                area = zone, note = note, online = isOnline and true or false, file = file, char = name, sameGame = true,
                key = "g:" .. name }
            if status == 1 then e.afk = true elseif status == 2 then e.dnd = true end
            if e.online then online = online + 1
            elseif GetGuildRosterLastOnline then e.ago = AgoParts(GetGuildRosterLastOnline(i)) end
            list[#list + 1] = e
        end
    end
    return list, online
end

local function SortName(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
end

local function Matches(e, q)
    if q == "" then return true end
    for _, v in ipairs({ e.name, e.char, e.account, e.tag, e.note, e.rank, e.area }) do
        if v and tostring(v):lower():find(q, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
local function Whisper(e)
    if not e or e.kind == "ignore" then return end
    if not e.online then Print((e.name or "That friend") .. " is offline.") return end
    if e.kind == "bnet" then
        local target = e.account or e.tag
        if not target then return end
        if ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end
    else
        if ChatFrame_SendTell then ChatFrame_SendTell(e.name) else ChatFrame_OpenChat("/w " .. e.name .. " ") end
    end
end

local function Invite(e)
    if not e or not e.online or not e.sameGame or not e.char then Print("Can only invite friends who are online in this version of WoW.") return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(e.char)
    elseif InviteUnit then InviteUnit(e.char) end
end

local function Remove(e)
    if not e then return end
    if e.kind == "bnet" then
        if BNRemoveFriend then BNRemoveFriend(e.id) end
    elseif e.kind == "wow" then
        if C_FriendList and C_FriendList.RemoveFriend then C_FriendList.RemoveFriend(e.name)
        elseif RemoveFriend then RemoveFriend(e.name) end
    elseif e.kind == "ignore" then
        if C_FriendList and C_FriendList.DelIgnore then C_FriendList.DelIgnore(e.name)
        elseif DelIgnore then DelIgnore(e.name) end
    end
end

local function AddFriend(text)
    text = strtrim and strtrim(text or "") or text
    if not text or text == "" then return end
    if text:find("#", 1, true) then
        if BNSendFriendInvite then BNSendFriendInvite(text) else Print("Battle.net invites are not available here.") end
    elseif C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(text)
    elseif LegacyAddFriend then LegacyAddFriend(text) end
end

local function AddIgnore(text)
    text = strtrim and strtrim(text or "") or text
    if not text or text == "" then return end
    if C_FriendList and C_FriendList.AddIgnore then C_FriendList.AddIgnore(text)
    elseif LegacyAddIgnore then LegacyAddIgnore(text) end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local f, list, rows, track, thumb, countText, searchBox, searchHint
local tabFriends, tabWho, tabGuild, tabIgnore, footL, footM, footR, emptyText
local menu, catcher, popup
local mode = "friends"
local view, offset = {}, 0
local selected
local query = ""
local dirty = false
local whoSearching = false
local whoSuppress -- until when to keep Blizzard's own Who panel from opening on top of ours

local function Visible() return max(1, floor((f:GetHeight() - TOP - BOTTOM) / ROW_H)) end

-- Battle.net client codes -> readable game names
local GAMES = {
    WoW = "World of Warcraft", WTCG = "Hearthstone", Hero = "Heroes of the Storm", Pro = "Overwatch",
    S1 = "StarCraft", S2 = "StarCraft II", D3 = "Diablo III", Fen = "Diablo IV", OSI = "Diablo II: Resurrected",
    ANBS = "Diablo Immortal", W3 = "Warcraft III", GRY = "Warcraft Rumble", VIPR = "Call of Duty: Black Ops 4",
    ODIN = "Call of Duty: Modern Warfare", LAZR = "Call of Duty: MW2", ZEUS = "Call of Duty: Black Ops Cold War",
    FORE = "Call of Duty: Vanguard", App = "Battle.net App", BSAp = "Battle.net Mobile",
}
-- each game gets its own colour so the list can be scanned at a glance
local GAME_COLORS = {
    WoW = { 0.25, 0.72, 1.00 }, WTCG = { 1.00, 0.67, 0.25 }, Hero = { 0.65, 0.50, 1.00 }, Pro = { 1.00, 0.62, 0.15 },
    S1 = { 0.35, 0.68, 1.00 }, S2 = { 0.35, 0.68, 1.00 }, W3 = { 0.35, 0.80, 1.00 }, GRY = { 0.35, 0.80, 1.00 },
    D3 = { 0.95, 0.35, 0.30 }, Fen = { 0.95, 0.35, 0.30 }, OSI = { 0.95, 0.35, 0.30 }, ANBS = { 0.95, 0.35, 0.30 },
    VIPR = { 0.50, 0.80, 0.35 }, ODIN = { 0.50, 0.80, 0.35 }, LAZR = { 0.50, 0.80, 0.35 }, ZEUS = { 0.50, 0.80, 0.35 },
    FORE = { 0.50, 0.80, 0.35 }, App = { 0.45, 0.68, 0.90 }, BSAp = { 0.45, 0.68, 0.90 },
}
local function GameColor(e)
    local c = GAME_COLORS[e.client] or T.accent
    return Hex(c[1], c[2], c[3])
end
local PROJECTS = { [1] = "Retail", [2] = "Classic Era", [5] = "TBC Classic", [11] = "Wrath Classic",
    [14] = "Cataclysm Classic", [19] = "Mists Classic" }

-- which group an online friend belongs to: wow (this game), wowother, game, app
local function Category(e)
    if e.sameGame then return "wow" end
    local c = e.client
    if c == "WoW" then return "wowother" end
    if c == "App" or c == "BSAp" or c == nil or c == "" then return "app" end
    return "game"
end

local function GameLabel(e)
    local c = e.client
    if c == "WoW" then
        local p = e.project and PROJECTS[e.project]
        return "World of Warcraft" .. (p and (" " .. p) or "")
    end
    return GAMES[c] or c or "Online"
end

local function ShowEntry(r, e)
    r.entry = e
    r:Show()
    if e.kind == "header" then
        r.dot:Hide(); r.sub:Hide(); r.line:Show(); r.card:Hide(); r.hbg:Show()
        r.line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", 8, 0)
        r.name:SetPoint("RIGHT", -6, 0)
        r.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        r.name:SetText((DB().collapsed[e.group] and "+ " or "- ") .. e.text)
        r.sel:Hide()
        return
    end
    r.dot:Show(); r.sub:Show(); r.line:Hide()
    r.sub:ClearAllPoints()
    r.sub:SetPoint("BOTTOMLEFT", 18, 5)
    r.sub:SetPoint("BOTTOMRIGHT", -6, 5)
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", 18, -5)
    r.name:SetPoint("TOPRIGHT", -6, -5)
    r.card:Show(); r.hbg:Hide()
    r.line:SetColorTexture(T.line[1], T.line[2], T.line[3], 1)
    r.sel:SetShown(selected == e.key)

    if e.kind == "ignore" then
        r.dot:SetColorTexture(T.danger[1], T.danger[2], T.danger[3], 1)
        r.name:SetTextColor(T.text[1], T.text[2], T.text[3])
        r.name:SetText(e.name)
        r.sub:SetText(DIM .. "Ignored")
        return
    end

    if e.kind == "motd" then
        r.dot:Hide()
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", 10, -4)
        r.name:SetPoint("TOPRIGHT", -6, -4)
        r.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        r.name:SetText("<" .. (e.guild or "Guild") .. ">  Message of the day")
        r.sub:ClearAllPoints()
        r.sub:SetPoint("BOTTOMLEFT", 10, 4)
        r.sub:SetPoint("BOTTOMRIGHT", -6, 4)
        r.sub:SetText(LIGHT .. (e.text or ""))
        r.sel:Hide()
        return
    end
    if e.kind == "guild" then
        local cr, cg, cb = ClassColor(e.class, e.file)
        local dot = T.green
        if not e.online then dot = { 0.3, 0.3, 0.3 } elseif e.dnd then dot = T.danger elseif e.afk then dot = T.accent end
        r.dot:SetColorTexture(dot[1], dot[2], dot[3], 1)
        if e.online then r.name:SetTextColor(cr, cg, cb) else r.name:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end
        r.name:SetText(e.name .. DIM .. "   " .. (e.rank or ""))
        local s
        if e.online then
            s = format("%sLvl %s %s", e.afk and "<Away> " or (e.dnd and "<Busy> " or ""), tostring(e.level or "?"), e.class or "")
            if e.area and e.area ~= "" then s = s .. " - " .. e.area end
            s = LIGHT .. s
        else
            s = DIM .. "Offline" .. (e.ago and (" - " .. e.ago) or "")
        end
        if e.note and e.note ~= "" then s = s .. DIM .. '  "' .. e.note .. '"' end
        r.sub:SetText(s)
        return
    end

    if e.kind == "who" then
        local cr, cg, cb = ClassColor(e.class, e.file)
        r.dot:SetColorTexture(cr, cg, cb, 1)
        r.name:SetTextColor(cr, cg, cb)
        r.name:SetText(e.name)
        local s = format("Lvl %s %s %s", tostring(e.level or "?"), e.race or "", e.class or "")
        if e.area and e.area ~= "" then s = s .. " - " .. e.area end
        r.sub:SetText(LIGHT .. s .. ((e.guild and e.guild ~= "") and (DIM .. "  <" .. e.guild .. ">") or ""))
        return
    end

    local dot = T.green
    if not e.online then dot = { 0.3, 0.3, 0.3 }
    elseif e.dnd then dot = T.danger
    elseif e.afk then dot = T.accent end
    if e.online and not e.dnd and Category(e) == "app" then dot = { 0.35, 0.6, 0.9 } end
    r.dot:SetColorTexture(dot[1], dot[2], dot[3], 1)

    local sub
    if e.online and e.sameGame then
        local cr, cg, cb = ClassColor(e.class)
        local shown = e.char or e.name
        r.name:SetTextColor(1, 1, 1)
        local txt = Hex(cr, cg, cb) .. shown .. "|r"
        if e.kind == "bnet" and e.account and e.account ~= shown then txt = txt .. DIM .. "  " .. e.account .. "|r" end
        r.name:SetText(txt)
        local parts = {}
        if e.afk then parts[#parts + 1] = "<Away>" elseif e.dnd then parts[#parts + 1] = "<Busy>" end
        if e.level and e.level > 0 then parts[#parts + 1] = "Lvl " .. e.level end
        if e.class and e.class ~= "" then parts[#parts + 1] = e.class end
        local s = table.concat(parts, " ")
        if e.area and e.area ~= "" then s = s .. (s ~= "" and " - " or "") .. e.area end
        sub = s
    elseif e.online then
        r.name:SetTextColor(T.text[1], T.text[2], T.text[3])
        r.name:SetText(e.name)
        local label = GameLabel(e)
        sub = GameColor(e) .. label .. "|r"
        if Category(e) ~= "app" and e.presence and e.presence ~= "" and e.presence ~= label then
            sub = sub .. LIGHT .. " - " .. e.presence
        end
    else
        r.name:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        r.name:SetText(e.name)
        local ago = Ago(e.lastOnline)
        sub = (e.note and e.note ~= "" and e.note) or ("Offline" .. (ago and (" - " .. ago) or ""))
    end
    r.sub:SetText(DIM .. (sub or ""))
end

local function Update()
    if not f then return end
    local vis = Visible()
    local total = #view
    offset = max(0, min(offset, max(0, total - vis)))
    for i = 1, #rows do
        local r = rows[i]
        local e = i <= vis and view[offset + i]
        if e then ShowEntry(r, e) else r:Hide(); r.entry = nil end
    end
    -- scrollbar
    if total > vis then
        track:Show()
        local th = max(20, track:GetHeight() * vis / total)
        thumb:SetHeight(th)
        local travel = track:GetHeight() - th
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -travel * offset / max(1, total - vis))
    else
        track:Hide()
    end
    if emptyText then
        if total == 0 then
            if mode == "who" then
                emptyText:SetText("Type a name, a level range (10-20), a class or a zone\nand press Enter. Leave it empty to list your zone.")
            elseif mode == "ignore" then
                emptyText:SetText("Nobody is ignored.")
            elseif mode == "guild" then
                emptyText:SetText((IsInGuild and IsInGuild()) and "No members to show yet - the roster is loading." or "You are not in a guild.")
            else
                emptyText:SetText(query ~= "" and "No matches." or "No friends yet.")
            end
            emptyText:Show()
        else
            emptyText:Hide()
        end
    end
end

local function Rebuild()
    if not f then return end
    view = {}
    local d = DB()
    local q = query:lower()
    local function AddGroup(group, text, items, keepOrder)
        if #items == 0 then return end
        if not keepOrder then table.sort(items, SortName) end
        view[#view + 1] = { kind = "header", group = group, text = text .. " (" .. #items .. ")" }
        if not d.collapsed[group] then
            for _, e in ipairs(items) do view[#view + 1] = e end
        end
    end
    if mode == "friends" then
        local all = CollectFriends()
        local fav, on, off, online = {}, {}, {}, 0
        local cats = { wow = {}, wowother = {}, game = {}, app = {} }
        for _, e in ipairs(all) do
            if e.online then online = online + 1 end
            if Matches(e, q) then
                if e.fav then fav[#fav + 1] = e
                elseif e.online then
                    on[#on + 1] = e
                    local t = cats[Category(e)]
                    t[#t + 1] = e
                else off[#off + 1] = e end
            end
        end
        AddGroup("fav", "Favorites", fav)
        if d.groupByGame then
            AddGroup("wow", "Playing WoW Classic", cats.wow)
            AddGroup("wowother", "Playing other WoW versions", cats.wowother)
            table.sort(cats.game, function(a, b)
                local ga, gb = GameLabel(a), GameLabel(b)
                if ga ~= gb then return ga < gb end
                return SortName(a, b)
            end)
            AddGroup("game", "Playing other games", cats.game, true)
            AddGroup("app", "Battle.net App and Mobile", cats.app)
        else
            AddGroup("on", "Online", on)
        end
        AddGroup("off", "Offline", off)
        countText:SetText(format("%d / %d online", online, #all))
    elseif mode == "guild" then
        if not (IsInGuild and IsInGuild()) then
            countText:SetText("No guild")
        else
            local all, online = CollectGuild()
            local on, off = {}, {}
            for _, e in ipairs(all) do
                if Matches(e, q) then
                    if e.online then on[#on + 1] = e elseif not d.guildHideOffline then off[#off + 1] = e end
                end
            end
            local function ByRank(a, b)
                if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
                return SortName(a, b)
            end
            table.sort(on, ByRank)
            table.sort(off, SortName)
            local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
            if motd ~= "" and q == "" then
                view[#view + 1] = { kind = "motd", guild = (GetGuildInfo and GetGuildInfo("player")) or "Guild", text = motd }
            end
            AddGroup("gon", "Online", on, true)
            AddGroup("goff", "Offline", off, true)
            countText:SetText(format("%d / %d online", online, #all))
        end
    elseif mode == "who" then
        local items, total = CollectWho()
        AddGroup("who", "Results", items, true)
        if whoSearching and #items == 0 then countText:SetText("Searching...")
        elseif total > #items then countText:SetText(format("%d of %d shown", #items, total))
        else countText:SetText(format("%d found", #items)) end
    else
        local items = {}
        for _, e in ipairs(CollectIgnores()) do
            if Matches(e, q) then items[#items + 1] = e end
        end
        AddGroup("ign", "Ignored", items)
        countText:SetText(format("%d ignored", #items))
    end
    Update()
end

local function Select(e)
    selected = e and e.key
    Update()
end

local function SelectedEntry()
    for _, e in ipairs(view) do if e.key and e.key == selected then return e end end
end

local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

local function OpenMenu(row, e)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("DIALOG")
        catcher:SetFrameLevel(10)
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:SetScript("OnClick", CloseMenu)
        catcher:Hide()

        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("DIALOG")
        menu:SetFrameLevel(20)
        menu:SetSize(140, 10)
        W.Texture(menu, "BACKGROUND", T.bg):SetAllPoints()
        W.Border(menu, 1, T.border, "BORDER")
        menu.items = {}
        local function Item(label, fn)
            local b = W.Button(menu, 130, 22, label)
            b.fn = fn
            b:SetScript("OnClick", function(s) s.fn(s) end)
            menu.items[#menu.items + 1] = b
            return b
        end
        menu.whisper = Item("Whisper", function() Whisper(menu.entry); CloseMenu() end)
        menu.invite = Item("Invite to group", function() Invite(menu.entry); CloseMenu() end)
        menu.addfriend = Item("Add friend", function() AddFriend(menu.entry.name); CloseMenu() end)
        menu.remove = Item("Remove", function(s)
            if s.armed then Remove(menu.entry); CloseMenu(); dirty = true
            else s.armed = true; s:SetLabel("Click again to confirm") end
        end)
        menu:Hide()
    end
    menu.entry = e
    menu.remove.armed = false
    menu.remove:SetLabel("Remove")
    local show = { menu.whisper, menu.invite, menu.remove }
    if e.kind == "ignore" then show = { menu.remove }
    elseif e.kind == "who" or e.kind == "guild" then show = { menu.whisper, menu.invite, menu.addfriend } end
    for _, b in ipairs(menu.items) do b:Hide() end
    for i, b in ipairs(show) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 24)
        b:Show()
    end
    menu:SetHeight(10 + #show * 24)
    menu:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, y / s - 4)
    catcher:Show()
    menu:Show()
end

local function OpenPopup(title, hint, onOk)
    if not popup then
        popup = CreateFrame("Frame", "CysFriendsPopup", UIParent)
        popup:SetSize(280, 110)
        popup:SetPoint("CENTER", 0, 120)
        popup:SetFrameStrata("DIALOG")
        popup:EnableMouse(true)
        W.Texture(popup, "BACKGROUND", T.bg):SetAllPoints()
        W.Border(popup, 1, T.border, "BORDER")
        popup.title = W.Text(popup, 13, T.accent, "CENTER")
        popup.title:SetPoint("TOP", 0, -10)
        popup.hint = W.Text(popup, 10, T.dim, "CENTER")
        popup.hint:SetPoint("TOP", popup.title, "BOTTOM", 0, -4)
        local box = CreateFrame("Frame", nil, popup)
        box:SetPoint("TOPLEFT", 14, -46)
        box:SetPoint("TOPRIGHT", -14, -46)
        box:SetHeight(24)
        W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
        W.Border(box, 1, T.line, "BORDER")
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetPoint("TOPLEFT", 6, 0)
        eb:SetPoint("BOTTOMRIGHT", -6, 0)
        eb:SetFont(STANDARD_TEXT_FONT, 12, "")
        eb:SetTextColor(T.text[1], T.text[2], T.text[3])
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(64)
        popup.edit = eb
        local function Done()
            local text = eb:GetText()
            popup:Hide()
            if popup.onOk then popup.onOk(text) end
        end
        eb:SetScript("OnEnterPressed", Done)
        eb:SetScript("OnEscapePressed", function() popup:Hide() end)
        local ok = W.Button(popup, 120, 24, "OK", true)
        ok:SetPoint("BOTTOMLEFT", 14, 12)
        ok:SetScript("OnClick", Done)
        local cancel = W.Button(popup, 120, 24, "Cancel")
        cancel:SetPoint("BOTTOMRIGHT", -14, 12)
        cancel:SetScript("OnClick", function() popup:Hide() end)
        tinsert(UISpecialFrames, "CysFriendsPopup")
        popup:Hide()
    end
    popup.title:SetText(title)
    popup.hint:SetText(hint or "")
    popup.onOk = onOk
    popup.edit:SetText("")
    popup:Show()
    popup.edit:SetFocus()
end

local function RunWho()
    local text = strtrim and strtrim(query or "") or (query or "")
    if text == "" then
        local zone = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or ""
        if zone == "" then Print("Type something to search for first.") return end
        text = 'z-"' .. zone .. '"'
    end
    whoSearching = true
    selected, offset = nil, 0
    whoSuppress = (FriendsFrame and not FriendsFrame:IsShown()) and (GetTime() + 4) or nil
    local C = C_FriendList
    if C and C.SetWhoToUi then C.SetWhoToUi(true) elseif SetWhoToUI then SetWhoToUI(1) end
    local ok, err
    if C and C.SendWho then
        ok, err = pcall(C.SendWho, text, Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or nil)
    elseif SendWho then
        ok, err = pcall(SendWho, text)
    end
    if ok == false then whoSearching = false; Print("Could not run that search: " .. tostring(err)) end
    Rebuild()
end

-- two footer buttons normally; the Guild tab adds a third one that opens Blizzard's Guild & Communities window
local function FooterLayout()
    if not (f and footL and footM and footR) then return end
    footL:ClearAllPoints(); footM:ClearAllPoints(); footR:ClearAllPoints()
    if mode == "guild" then
        local w = max(60, (f:GetWidth() - 20 - 8) / 3)
        footL:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 12); footL:SetWidth(w)
        footM:SetPoint("BOTTOMLEFT", footL, "BOTTOMRIGHT", 4, 0); footM:SetWidth(w)
        footR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12); footR:SetWidth(w)
        footM:Show()
    else
        footM:Hide()
        footL:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 12)
        footL:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -3, 12)
        footR:SetPoint("BOTTOMLEFT", f, "BOTTOM", 3, 12)
        footR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
    end
end

local function OpenGuildWindow()
    if ToggleGuildFrame then ToggleGuildFrame()
    elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame()
    elseif ToggleFriendsFrame then ToggleFriendsFrame(3) end
end

local savedShowOffline
local function LeaveGuild()
    if savedShowOffline ~= nil and SetGuildRosterShowOffline then SetGuildRosterShowOffline(savedShowOffline) end
    savedShowOffline = nil
end

local function RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
end

local function GuildLabel() return DB().guildHideOffline and "Show Offline" or "Hide Offline" end

local function SetMode(m)
    if mode == "guild" and m ~= "guild" then LeaveGuild() end
    mode = m
    tabFriends:SetPrimary(m == "friends")
    tabWho:SetPrimary(m == "who")
    tabGuild:SetPrimary(m == "guild")
    tabIgnore:SetPrimary(m == "ignore")
    if m == "guild" then
        if savedShowOffline == nil and GetGuildRosterShowOffline then savedShowOffline = GetGuildRosterShowOffline() end
        if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end -- we filter offline members ourselves
        RequestRoster()
    end
    footL:SetLabel(m == "friends" and "Add Friend" or (m == "who" and "Search" or (m == "guild" and GuildLabel() or "Add Ignore")))
    footR:SetLabel(m == "ignore" and "Remove" or "Whisper")
    searchHint:SetText(m == "who" and "Search players... (press Enter)" or "Search...")
    FooterLayout()
    selected, offset, query = nil, 0, ""
    searchBox:SetText("")
    searchHint:Show()
    CloseMenu()
    Rebuild()
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = W.Texture(r, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.10 })
    r.hl:SetAllPoints(); r.hl:Hide()
    r.sel = W.Texture(r, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.22 })
    r.sel:SetAllPoints(); r.sel:Hide()
    r.dot = W.Texture(r, "ARTWORK", T.green)
    r.dot:SetSize(3, ROW_H - 12)
    r.dot:SetPoint("LEFT", 6, 0)
    -- every person sits on a soft card; headers get their own darker bar
    r.card = W.Texture(r, "BACKGROUND", { T.card[1], T.card[2], T.card[3], 0.55 }, -2)
    r.card:SetPoint("TOPLEFT", 0, -1)
    r.card:SetPoint("BOTTOMRIGHT", 0, 1)
    r.hbg = W.Texture(r, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.07 }, -2)
    r.hbg:SetPoint("TOPLEFT", 0, -4)
    r.hbg:SetPoint("BOTTOMRIGHT", 0, 1)
    r.hbg:Hide()
    r.name = W.Text(r, 13, T.text)
    r.name:SetWordWrap(false)
    r.sub = W.Text(r, 11, T.dim)
    r.sub:SetWordWrap(false)
    r.sub:SetPoint("BOTTOMLEFT", 18, 5)
    r.sub:SetPoint("BOTTOMRIGHT", -6, 5)
    r.line = W.Texture(r, "ARTWORK", T.line)
    r.line:SetHeight(1)
    r.line:SetPoint("BOTTOMLEFT", 0, 0)
    r.line:SetPoint("BOTTOMRIGHT", 0, 0)
    r.line:Hide()
    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        local e = s.entry
        if e and e.kind == "motd" and GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.guild or "Guild", 1, 0.82, 0)
            GameTooltip:AddLine(e.text or "", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(s)
        s.hl:Hide()
        if GameTooltip and GameTooltip:GetOwner() == s then GameTooltip:Hide() end
    end)
    r:SetScript("OnClick", function(s, button)
        local e = s.entry
        if not e then return end
        if e.kind == "header" then
            local d = DB()
            d.collapsed[e.group] = not d.collapsed[e.group]
            Rebuild()
            return
        end
        if e.kind == "motd" then return end
        Select(e)
        if button == "RightButton" then
            OpenMenu(s, e)
        else
            CloseMenu()
            local now = GetTime()
            if s.lastClick and now - s.lastClick < 0.35 and e.kind ~= "ignore" then Whisper(e); s.lastClick = nil
            else s.lastClick = now end
        end
    end)
    return r
end

local function Layout()
    if not f then return end
    FooterLayout()
    local vis = Visible()
    for i = 1, vis do
        if not rows[i] then rows[i] = MakeRow(i) end
        local r = rows[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -10, -(i - 1) * ROW_H)
    end
    Update()
end

local function Build()
    BuildClassMap()
    f = CreateFrame("Frame", "CysFriendsFrame", UIParent)
    f:SetSize(340, 460)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    f:Hide()
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")
    rows = {}

    local strip = W.Texture(f, "BACKGROUND", { T.card[1], T.card[2], T.card[3], 1 }, -1)
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(29)
    local sline = W.Texture(f, "BORDER", T.border)
    sline:SetHeight(1)
    sline:SetPoint("TOPLEFT", 1, -30)
    sline:SetPoint("TOPRIGHT", -1, -30)
    local fline = W.Texture(f, "BORDER", T.line)
    fline:SetHeight(1)
    fline:SetPoint("BOTTOMLEFT", 1, 44)
    fline:SetPoint("BOTTOMRIGHT", -1, 44)
    local title = W.Text(f, 14, T.accent, "CENTER")
    title:SetPoint("TOP", 0, -9)
    title:SetText("Friends")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -4, -4)
    local x = W.Text(close, 14, T.text, "CENTER")
    x:SetPoint("CENTER")
    x:SetText("X")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)

    tabFriends = W.Button(f, 58, 22, "Friends")
    tabFriends:SetPoint("TOPLEFT", 10, -32)
    tabFriends:SetScript("OnClick", function() SetMode("friends") end)
    tabWho = W.Button(f, 50, 22, "Who")
    tabWho:SetPoint("LEFT", tabFriends, "RIGHT", 4, 0)
    tabWho:SetScript("OnClick", function() SetMode("who") end)
    tabGuild = W.Button(f, 54, 22, "Guild")
    tabGuild:SetPoint("LEFT", tabWho, "RIGHT", 4, 0)
    tabGuild:SetScript("OnClick", function() SetMode("guild") end)
    tabIgnore = W.Button(f, 54, 22, "Ignore")
    tabIgnore:SetPoint("LEFT", tabGuild, "RIGHT", 4, 0)
    tabIgnore:SetScript("OnClick", function() SetMode("ignore") end)

    countText = W.Text(f, 10, T.dim, "RIGHT")
    countText:SetPoint("TOPRIGHT", -12, -38)

    -- search
    local sbox = CreateFrame("Frame", nil, f)
    sbox:SetPoint("TOPLEFT", 10, -60)
    sbox:SetPoint("TOPRIGHT", -10, -60)
    sbox:SetHeight(22)
    W.Texture(sbox, "BACKGROUND", T.field):SetAllPoints()
    W.Border(sbox, 1, T.line, "BORDER")
    searchBox = CreateFrame("EditBox", nil, sbox)
    searchBox:SetPoint("TOPLEFT", 6, 0)
    searchBox:SetPoint("BOTTOMRIGHT", -6, 0)
    searchBox:SetFont(STANDARD_TEXT_FONT, 12, "")
    searchBox:SetTextColor(T.text[1], T.text[2], T.text[3])
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchHint = W.Text(sbox, 11, T.dim)
    searchHint:SetPoint("LEFT", 8, 0)
    searchHint:SetText("Search...")
    searchBox:SetScript("OnTextChanged", function(s)
        query = s:GetText() or ""
        searchHint:SetShown(query == "" and not s:HasFocus())
        if mode == "who" then return end -- a who search only runs when you press Enter
        offset = 0
        Rebuild()
    end)
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(s) searchHint:SetShown((s:GetText() or "") == "") end)
    searchBox:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(s) if mode == "who" then RunWho() end s:ClearFocus() end)

    -- list + scrollbar
    list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 10, -TOP)
    list:SetPoint("BOTTOMRIGHT", -10, BOTTOM)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; Update() end)
    emptyText = W.Text(list, 11, T.dim, "CENTER")
    emptyText:SetPoint("TOPLEFT", 10, -40)
    emptyText:SetPoint("TOPRIGHT", -20, -40)
    emptyText:SetJustifyV("TOP")
    emptyText:SetSpacing(3)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; Update() end)

    track = CreateFrame("Frame", nil, list)
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Texture(track, "BACKGROUND", T.field):SetAllPoints()
    thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    W.Texture(thumb, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.7 }):SetAllPoints()
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function(s)
        s.dragging = true
        s:SetScript("OnUpdate", function()
            local _, cy = GetCursorPosition()
            local scale = track:GetEffectiveScale()
            local top = track:GetTop()
            if not top then return end
            local frac = ((top - cy / scale) - thumb:GetHeight() / 2) / max(1, track:GetHeight() - thumb:GetHeight())
            offset = floor(max(0, min(1, frac)) * max(0, #view - Visible()) + 0.5)
            Update()
        end)
    end)
    thumb:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)

    -- footer
    footL = W.Button(f, 100, 24, "Add Friend")
    footL:SetPoint("BOTTOMLEFT", 10, 12)
    footL:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -3, 12)
    footL:SetScript("OnClick", function()
        if mode == "friends" then
            OpenPopup("Add Friend", "Character name, or a BattleTag like Name#1234", AddFriend)
        elseif mode == "who" then
            RunWho()
        elseif mode == "guild" then
            DB().guildHideOffline = not DB().guildHideOffline
            footL:SetLabel(GuildLabel())
            Rebuild()
        else
            OpenPopup("Ignore Player", "Character name", AddIgnore)
        end
    end)
    footM = W.Button(f, 100, 24, "Guild Window")
    footM:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    footM:SetScript("OnClick", OpenGuildWindow)
    footM:Hide()
    footR = W.Button(f, 100, 24, "Whisper")
    footR:SetPoint("BOTTOMLEFT", f, "BOTTOM", 3, 12)
    footR:SetPoint("BOTTOMRIGHT", -10, 12)
    footR:SetScript("OnClick", function()
        local e = SelectedEntry()
        if not e then Print("Pick someone in the list first.") return end
        if mode == "ignore" then Remove(e); dirty = true else Whisper(e) end
    end)

    -- events: refresh when the lists change (batched)
    for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "IGNORELIST_UPDATE", "WHO_LIST_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "PLAYER_GUILD_UPDATE" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "WHO_LIST_UPDATE" then whoSearching = false end
        dirty = true
    end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if whoSuppress then
            if GetTime() > whoSuppress then whoSuppress = nil
            elseif FriendsFrame and FriendsFrame:IsShown() then pcall(HideUIPanel, FriendsFrame) end
        end
        if dirty and acc > 0.2 then dirty = false; acc = 0; Rebuild() end
    end)
    f:SetScript("OnShow", function()
        if mode == "guild" then
            if GetGuildRosterShowOffline and savedShowOffline == nil then savedShowOffline = GetGuildRosterShowOffline() end
            if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
            RequestRoster()
        end
        if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() elseif ShowFriends then ShowFriends() end
        Rebuild()
    end)
    f:SetScript("OnHide", function()
        CloseMenu()
        if popup then popup:Hide() end
        if mode == "guild" then LeaveGuild() end
        if C_FriendList and C_FriendList.SetWhoToUi and not (FriendsFrame and FriendsFrame:IsShown()) then C_FriendList.SetWhoToUi(false) end
    end)
    tinsert(UISpecialFrames, "CysFriendsFrame")

    SetMode("friends")
    Layout()

    CUI:RegisterMovable(f, "friends", "Friends Window", {
        point = "LEFT", x = 40, y = 0,
        resizable = true, minW = 300, maxW = 600, minH = 320, maxH = 900,
        onResize = function() Layout() end,
    })
end

--------------------------------------------------------------------------------
-- Open / close, Social key
--------------------------------------------------------------------------------
function F.Rebuild() if f then Rebuild() end end
F.SetMode, F.RunWho = SetMode, RunWho

-- Open the window on the Who tab and run a search (what /who does when we take it over)
function F:OpenWho(text)
    if not f then return end
    f:Show()
    SetMode("who")
    query = strtrim and strtrim(text or "") or (text or "")
    searchBox:SetText(query)
    RunWho()
end

local origWho
function F.ApplyWho()
    if not SlashCmdList then return end
    if DB().takeKey and f then
        if not origWho then origWho = SlashCmdList["WHO"] end
        SlashCmdList["WHO"] = function(msg) F:OpenWho(msg) end
    elseif origWho then
        SlashCmdList["WHO"] = origWho
    end
end

function F.IsActive() return f ~= nil and DB().takeKey end

function F:Toggle()
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

local keyOwner, toggleButton
local function ApplyKey()
    if not keyOwner then return end
    if InCombatLockdown() then keyOwner.pending = true return end
    keyOwner.pending = false
    ClearOverrideBindings(keyOwner)
    if not DB().takeKey then return end
    for _, key in ipairs({ GetBindingKey("TOGGLESOCIAL") }) do
        SetOverrideBindingClick(keyOwner, true, key, "CysFriendsToggleButton")
    end
    for _, key in ipairs({ GetBindingKey("TOGGLEFRIENDSTAB") }) do
        SetOverrideBindingClick(keyOwner, true, key, "CysFriendsToggleButton")
    end
end
F.ApplyKey = ApplyKey

function F.Enable()
    Build()
    toggleButton = CreateFrame("Button", "CysFriendsToggleButton", UIParent)
    toggleButton:SetScript("OnClick", function() F:Toggle() end)
    keyOwner = CreateFrame("Frame")
    keyOwner:RegisterEvent("PLAYER_ENTERING_WORLD")
    keyOwner:RegisterEvent("UPDATE_BINDINGS")
    keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
    keyOwner:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" and not self.pending then return end
        ApplyKey()
    end)
    ApplyKey()
    F.ApplyWho()
end

SLASH_CYSFRIENDS1 = "/cfriends"
SLASH_CYSFRIENDS2 = "/cysfriends"
SlashCmdList["CYSFRIENDS"] = function()
    if f then F:Toggle() else Print("The Friends module is switched off in /cui.") end
end

CUI:RegisterModule({
    key = "friends",
    name = "Friends",
    addon = "CysUI",
    desc = "A light friends window: game and Battle.net friends, ignore list. Opens with /cfriends or the Social key.",
    onEnable = F.Enable,
    open = function() CUI:OpenConfig("Friends") end,
})

CUI:RegisterPage("Friends", function(page)
    local width = 480
    W.Header(page, "Friends", width):SetPoint("TOPLEFT", 0, -4)
    local cb = W.Checkbox(page, "Social key (O) and /who open this window instead of Blizzard's",
        function() return DB().takeKey end,
        function(on) DB().takeKey = on; if F.ApplyKey then F.ApplyKey() end; F.ApplyWho() end)
    cb:SetPoint("TOPLEFT", 4, -34)
    local gb = W.Checkbox(page, "Group online friends by the game they are playing",
        function() return DB().groupByGame end,
        function(on) DB().groupByGame = on; F.Rebuild() end)
    gb:SetPoint("TOPLEFT", 4, -62)
    local note = W.Notes(page, 4, -94, width, "", {
            { "/cfriends", "opens the window any time; move and resize it in /cui layout." },
            "Click a name to select, double-click to whisper, right-click for more.",
            "The Who tab searches players (name, level range, class or zone) when you press Enter.",
            "Blizzard's own friends window is untouched and still opens from the micro menu.",
        })
end)
