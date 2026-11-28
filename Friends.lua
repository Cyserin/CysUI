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
local lastMOTD -- guild message of the day, read out of combat
local W = CUI.W
local T = W.T

local F = {}
CUI.Friends = F

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local format = string.format

local ROW_H = 36                 -- row height: 36 Comfortable, 24 Compact (DB().density)
local TILE_Y, TILE_H = 54, 42     -- the count tiles in the header
local TAB_Y, TAB_H = 112, 26      -- the tab strip
local SEARCH_Y, SEARCH_H = 146, 24 -- search box, row size, add button
local TOP = 178                   -- space above the list
local BOTTOM = 10                 -- space below the list (42 on the Guild tab: its Guild window button)

local function DB()
    CysUIDB.friends = CysUIDB.friends or {}
    local d = CysUIDB.friends
    if d.collapsed == nil then d.collapsed = {} end
    if d.takeKey == nil then d.takeKey = true end
    if d.groupByGame == nil then d.groupByGame = true end
    if d.guildInviteMenu == nil then d.guildInviteMenu = true end
    if d.density ~= "compact" then d.density = "comfortable" end
    if not d.foldInit then -- the Offline groups start folded (click their header to open them)
        d.foldInit = true
        d.collapsed.off, d.collapsed.goff = true, true
    end
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

-- class icon (the game's own class icon sheet) and a round status dot
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function ClassIcon(tex, className, fileToken)
    local file = fileToken or (className and classFile[className])
    local c = file and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
    if not c then return false end
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(c[1] + 0.012, c[2] - 0.012, c[3] + 0.012, c[4] - 0.012)
    return true
end
-- another Blizzard game (or the app): that game's logo; anything else gets the Battle.net logo
local BNET_ICON = "Interface\\FriendsFrame\\Battlenet-Battleneticon"
local GAME_ICONS = {
    WoW = "Interface\\FriendsFrame\\Battlenet-WoWicon", S2 = "Interface\\FriendsFrame\\Battlenet-Sc2icon",
    D3 = "Interface\\FriendsFrame\\Battlenet-D3icon", WTCG = "Interface\\FriendsFrame\\Battlenet-WTCGicon",
    Pro = "Interface\\FriendsFrame\\Battlenet-Overwatchicon",
}
local function GameIcon(tex, client)
    local path = GAME_ICONS[client or ""]
    local get = BNet_GetClientTexture
    if not path and type(get) == "function" and client and client ~= "" and client ~= "App" and client ~= "BSAp" then
        local ok, p = pcall(get, client)
        if ok and p then path = p end
    end
    tex:SetTexture(path or BNET_ICON)
    tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    return true
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
-- Opens the chat box straight into a whisper. The chat type and target are set on the box
-- itself instead of typing "/w name", so Battle.net names (which the "/w" parser can't read
-- back) still open a Battle.net whisper instead of falling back to /say or the last /r target.
local function OpenWhisper(chatType, target)
    local eb = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
    if not (eb and ChatEdit_UpdateHeader) then
        ChatFrame_OpenChat("/w " .. target .. " ")
        return
    end
    if eb ~= (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) then
        ChatFrame_OpenChat("", eb.chatFrame)
    end
    eb:SetText("")
    eb:SetAttribute("chatType", chatType)
    eb:SetAttribute("tellTarget", target)
    ChatEdit_UpdateHeader(eb)
    eb:SetFocus()
end

local function Whisper(e)
    if not e or e.kind == "ignore" then return end
    if not e.online then Print((e.name or "That friend") .. " is offline.") return end
    if e.kind == "bnet" then
        local target = e.account or e.tag
        if not target then return end
        OpenWhisper("BN_WHISPER", target)
    else
        OpenWhisper("WHISPER", e.name)
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
local f, list, rows, track, thumb, searchBox, searchHint
local tabFriends, tabWho, tabGuild, tabIgnore, footM, emptyText
local tabBar, tiles, me, statusDD, bcBox, bcHint, densityDD, addBtn, fline
local Layout -- set further down
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

-- the round icon on the left: class icon, game icon, or a plain dot; the status dot sits on its corner
local function SetIcon(r, kind, a, b, online, status)
    local ok = false
    if kind == "class" then ok = ClassIcon(r.icon, a, b)
    elseif kind == "game" then ok = GameIcon(r.icon, a) end
    if not ok then
        -- nothing to show (offline, class unknown): a small quiet dot instead of an empty ring
        r.icon:SetTexture(CIRCLE)
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.icon:SetVertexColor(0.32, 0.32, 0.32)
        local dot = (r.iconSize or 24) >= 24 and 9 or 7
        r.icon:SetSize(dot, dot)
        r.icon:SetDesaturated(false)
        r.icon:SetAlpha(1)
        r.iconBg:Hide()
    else
        r.icon:SetVertexColor(1, 1, 1)
        r.icon:SetSize(r.iconSize or 24, r.iconSize or 24)
        r.icon:SetDesaturated(not online)
        r.icon:SetAlpha(online and 1 or 0.45)
        r.iconBg:SetAlpha(online and 1 or 0.4)
        r.iconBg:Show()
    end
    r.icon:Show()
    if status then
        r.status:SetVertexColor(status[1], status[2], status[3])
        r.status:Show(); r.statusRing:Show()
    else
        r.status:Hide(); r.statusRing:Hide()
    end
end
local STATUS_ON, STATUS_AWAY, STATUS_BUSY, STATUS_APP = { 0.30, 0.85, 0.40 }, { 1, 0.75, 0.15 }, { 0.95, 0.25, 0.25 }, { 0.35, 0.60, 0.95 }

local function RowWidth(r)
    local w = r:GetWidth()
    if not w or w < 50 then w = ((f and f:GetWidth()) or 360) - 34 end
    return w
end

-- group cards: every person sits on a soft panel with a thin outline; one group's rows stack into one card
local function ShowCard(r, e)
    r.card:Show(); r.bL:Show(); r.bR:Show(); r.bT:Show()
    r.bT:SetAlpha(e._first and 1 or 0.5) -- the card's top edge, or a quieter line between two people
    r.bB:SetShown(e._last and true or false)
end
local function HideCard(r)
    r.card:Hide(); r.bL:Hide(); r.bR:Hide(); r.bT:Hide(); r.bB:Hide()
end

-- Comfortable (two lines, 36 px) or Compact (one line, 24 px): icon sizes follow the row height
local function ApplyDensity(r)
    local d = DB().density
    if r.dens == d then return end
    r.dens = d
    local compact = d == "compact"
    local bg, ring, dot = compact and 18 or 26, compact and 9 or 11, compact and 5 or 7
    r.iconSize = compact and 16 or 24
    r.iconBg:SetSize(bg, bg)
    r.iconBg:ClearAllPoints()
    r.iconBg:SetPoint("LEFT", compact and 7 or 8, 0)
    r.statusRing:SetSize(ring, ring)
    r.statusRing:ClearAllPoints()
    r.statusRing:SetPoint("CENTER", r.iconBg, "BOTTOMRIGHT", compact and -2 or -3, compact and 2 or 3)
    r.status:SetSize(dot, dot)
    local bh = compact and 18 or 22
    for _, b in ipairs(r.acts.all) do b:SetHeight(bh) end
    r.acts:SetHeight(bh)
end

-- name / second line / zone / level for the row's density; the hover buttons take over the right side
local function PlaceText(r)
    local e = r.entry
    if not e or e.kind == "header" then return end
    local compact = r.dens == "compact"
    local left = (e.kind == "motd") and 10 or (compact and 30 or 42)
    local w = RowWidth(r)
    local actsW = r.actsOn and (r.acts:GetWidth() + 12) or 0
    r.name:ClearAllPoints(); r.sub:ClearAllPoints(); r.zone:ClearAllPoints(); r.right:ClearAllPoints()
    r.right:SetShown(not r.actsOn)
    r.right:SetWidth(30)
    if compact then
        r.sub:Hide()
        r.right:SetPoint("RIGHT", -10, 0)
        local zw = 0
        local zt = r.zone:GetText()
        if not r.actsOn and zt and zt ~= "" then
            r.zone:SetWidth(0)
            zw = min(ceil(r.zone:GetStringWidth() or 0) + 2, floor((w - left) * 0.45))
            r.zone:SetWidth(zw)
            r.zone:SetPoint("RIGHT", -44, 0)
            r.zone:Show()
        else
            r.zone:Hide()
        end
        r.name:SetPoint("LEFT", left, 0)
        r.name:SetWidth(max(20, w - left - (r.actsOn and actsW or (46 + (zw > 0 and zw + 8 or 0)))))
    else
        r.zone:Hide(); r.sub:Show()
        r.right:SetPoint("TOPRIGHT", -10, -7)
        r.name:SetPoint("TOPLEFT", left, -6)
        r.sub:SetPoint("BOTTOMLEFT", left, 6)
        r.name:SetWidth(max(20, w - left - (r.actsOn and actsW or 44)))
        r.sub:SetWidth(max(20, w - left - (r.actsOn and actsW or 10)))
    end
end

local function HideActs(r)
    r.actsOn = false
    r.acts:Hide()
    if r.entry then PlaceText(r) end
end

-- hover buttons on the row you point at: Whisper / Invite / ... (more), or Unignore on the Ignore tab
local function ShowActs(r)
    local e = r.entry
    if not e or e.kind == "header" or e.kind == "motd" then HideActs(r) return end
    local a = r.acts
    local want = {}
    if e.kind == "ignore" then
        want[1] = a.unignore
    else
        if e.online then want[#want + 1] = a.whisper end
        if e.online and e.sameGame and e.char then want[#want + 1] = a.invite end
        want[#want + 1] = a.more
    end
    for _, b in ipairs(a.all) do b:Hide() end
    local x = 0
    for i = #want, 1, -1 do
        local b = want[i]
        b:ClearAllPoints()
        b:SetPoint("RIGHT", a, "RIGHT", -x, 0)
        b:Show()
        x = x + b:GetWidth() + 3
    end
    a:SetWidth(max(1, x - 3))
    r.actsOn = true
    a:Show()
    PlaceText(r)
end

local function ShowEntry(r, e)
    r.entry = e
    r:Show()
    r:SetAlpha(1)
    ApplyDensity(r)
    local compact = r.dens == "compact"
    r.right:SetText(""); r.zone:SetText(""); r.sub:SetText("")
    if e.kind == "header" then
        -- quiet section break: small gold caps, a thin rule, the count on the right
        r.actsOn = false; r.acts:Hide()
        HideCard(r)
        r.sub:Hide(); r.zone:Hide(); r.sel:Hide(); r.edge:Hide(); r.right:Show()
        r.icon:Hide(); r.iconBg:Hide(); r.status:Hide(); r.statusRing:Hide()
        local label, n = (e.text or ""):match("^(.-) %((%d+)%)$")
        label = label or e.text or ""
        r.name:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "")
        r.name:ClearAllPoints()
        r.name:SetWidth(0)
        r.name:SetPoint("BOTTOMLEFT", 4, compact and 5 or 7)
        r.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        r.name:SetText((DB().collapsed[e.group] and "+  " or "-  ") .. label:upper())
        r.right:ClearAllPoints()
        r.right:SetWidth(0)
        r.right:SetPoint("BOTTOMRIGHT", -4, compact and 5 or 7)
        r.right:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        r.right:SetText(n or "")
        r.line:ClearAllPoints()
        r.line:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.line:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
        r.line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.35)
        r.line:Show()
        return
    end
    r.line:Hide()
    ShowCard(r, e)
    r.name:SetFont(CysUICompat.Font(), CysUICompat.FontSize(compact and 12 or 13), "")
    r.right:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    local isSel = selected == e.key
    r.sel:SetShown(isSel)
    r.edge:SetShown(isSel)
    local sub, short = "", ""

    if e.kind == "ignore" then
        SetIcon(r, "none", nil, nil, true, STATUS_BUSY)
        r.name:SetTextColor(T.text[1], T.text[2], T.text[3])
        r.name:SetText(e.name)
        sub, short = DIM .. "Ignored", DIM .. "Ignored"
    elseif e.kind == "motd" then
        r.icon:Hide(); r.iconBg:Hide(); r.status:Hide(); r.statusRing:Hide(); r.edge:Hide(); r.sel:Hide()
        r.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        if compact then
            r.name:SetText("Message of the day  " .. LIGHT .. (e.text or ""))
        else
            r.name:SetText("<" .. (e.guild or "Guild") .. ">  Message of the day")
            sub = LIGHT .. (e.text or "")
        end
    elseif e.kind == "guild" then
        local cr, cg, cb = ClassColor(e.class, e.file)
        local st = nil
        if e.online then st = (e.dnd and STATUS_BUSY) or (e.afk and STATUS_AWAY) or STATUS_ON end
        SetIcon(r, "class", e.class, e.file, e.online, st)
        if e.online then r.name:SetTextColor(cr, cg, cb) else r.name:SetTextColor(T.dim[1], T.dim[2], T.dim[3]); r:SetAlpha(0.75) end
        r.name:SetText(e.name .. DIM .. "   " .. (e.rank or ""))
        if e.level and e.online then r.right:SetText(e.level) end
        if e.online then
            sub = format("%s%s", e.afk and "<Away> " or (e.dnd and "<Busy> " or ""), e.class or "")
            if e.area and e.area ~= "" then sub = sub .. " - " .. e.area end
            sub = LIGHT .. sub
            short = e.area or ""
        else
            sub = DIM .. "Offline" .. (e.ago and (" - " .. e.ago) or "")
            short = DIM .. (e.ago or "Offline")
        end
        if e.note and e.note ~= "" then sub = sub .. DIM .. '  "' .. e.note .. '"' end
    elseif e.kind == "who" then
        local cr, cg, cb = ClassColor(e.class, e.file)
        SetIcon(r, "class", e.class, e.file, true, nil)
        r.name:SetTextColor(cr, cg, cb)
        r.name:SetText(e.name)
        if e.level then r.right:SetText(e.level) end
        local s = format("%s %s", e.race or "", e.class or "")
        if e.area and e.area ~= "" then s = s .. " - " .. e.area end
        sub = LIGHT .. s .. ((e.guild and e.guild ~= "") and (DIM .. "  <" .. e.guild .. ">") or "")
        short = e.area or ""
    else
        local st = nil
        if e.online then
            st = (e.dnd and STATUS_BUSY) or (e.afk and STATUS_AWAY) or (Category(e) == "app" and STATUS_APP) or STATUS_ON
        end
        if e.online and e.sameGame then SetIcon(r, "class", e.class, nil, true, st)
        elseif e.online then SetIcon(r, "game", e.client, nil, true, st)
        elseif e.kind == "bnet" then SetIcon(r, "game", nil, nil, false, nil) -- Battle.net logo, faded
        else SetIcon(r, "class", e.class, nil, false, nil) end
        if not e.online then r:SetAlpha(0.75) end

        if e.online and e.sameGame then
            local cr, cg, cb = ClassColor(e.class)
            local shown = e.char or e.name
            r.name:SetTextColor(1, 1, 1)
            local txt = Hex(cr, cg, cb) .. shown .. "|r"
            if e.kind == "bnet" and e.account and e.account ~= shown then txt = txt .. DIM .. "  " .. e.account .. "|r" end
            r.name:SetText(txt)
            local parts = {}
            if e.afk then parts[#parts + 1] = "|cFFFFBF26Away|r" elseif e.dnd then parts[#parts + 1] = "|cFFF07A6ABusy|r" end
            if e.class and e.class ~= "" then table.insert(parts, 1, e.class) end
            if e.level and e.level > 0 then r.right:SetText(e.level) end
            local zone
            if e.area and e.area ~= "" then
                -- the zone in green when they are in the same zone as you
                local here = GetRealZoneText and GetRealZoneText()
                zone = (here and here == e.area) and ("|cFF66DD77" .. e.area .. "|r") or e.area
                table.insert(parts, e.class and e.class ~= "" and 2 or 1, zone)
            end
            sub = DIM .. table.concat(parts, "  |cFF555555·|r  ")
            short = zone or ""
        elseif e.online then
            r.name:SetTextColor(T.text[1], T.text[2], T.text[3])
            r.name:SetText(e.name)
            local label = GameLabel(e)
            sub = GameColor(e) .. label .. "|r"
            short = sub
            if Category(e) ~= "app" and e.presence and e.presence ~= "" and e.presence ~= label then
                sub = sub .. LIGHT .. " - " .. e.presence
            end
        else
            r.name:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
            r.name:SetText(e.name)
            local ago = Ago(e.lastOnline)
            sub = DIM .. ((e.note and e.note ~= "" and e.note) or ("Offline" .. (ago and (" - " .. ago) or "")))
            short = DIM .. (ago or "Offline")
        end
    end
    r.sub:SetText(sub or "")
    r.zone:SetText(short or "")
    if r.actsOn then ShowActs(r) else PlaceText(r) end
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

-- your own line in the header: Battle.net status (Online / Away / Busy) and broadcast message
local STATUS_OPTS = { { "online", "Online" }, { "away", "Away" }, { "busy", "Busy" } }
local function MyStatus()
    if BNGetInfo then
        local ok, _, _, _, _, afk, dnd = pcall(BNGetInfo)
        if ok then return (dnd and "busy") or (afk and "away") or "online" end
    end
    if UnitIsDND and UnitIsDND("player") then return "busy" end
    if UnitIsAFK and UnitIsAFK("player") then return "away" end
    return "online"
end
local function StatusColor(s) return (s == "busy" and STATUS_BUSY) or (s == "away" and STATUS_AWAY) or STATUS_ON end
local function SetMyStatus(s)
    if BNSetDND then pcall(BNSetDND, s == "busy") end
    if BNSetAFK then pcall(BNSetAFK, s == "away") end
end
local function MyBroadcast()
    if not BNGetInfo then return "" end
    local ok, _, _, _, bc = pcall(BNGetInfo)
    return (ok and type(bc) == "string") and bc or ""
end

local function UpdateSelf()
    if not me then return end
    local cname, file = UnitClass("player")
    local cr, cg, cb = ClassColor(cname, file)
    if not ClassIcon(me.icon, cname, file) then
        me.icon:SetTexture(CIRCLE)
        me.icon:SetTexCoord(0, 1, 0, 1)
    end
    me.name:SetText(Hex(cr, cg, cb) .. (UnitName("player") or "") .. "|r  " .. DIM .. (UnitLevel("player") or "") .. " " .. (cname or ""))
    local c = StatusColor(MyStatus())
    me.status:SetVertexColor(c[1], c[2], c[3])
    if statusDD then
        statusDD:Refresh()
        statusDD.dot:SetVertexColor(c[1], c[2], c[3])
    end
    if bcBox and not bcBox:HasFocus() then
        local bc = MyBroadcast()
        bcBox:SetText(bc)
        bcHint:SetShown(bc == "")
    end
end

-- the three count tiles and the counts on the tabs
local function UpdateHeader(all)
    if not tiles then return end
    all = all or CollectFriends()
    local on, here = 0, 0
    for _, e in ipairs(all) do
        if e.online then
            on = on + 1
            if e.sameGame then here = here + 1 end
        end
    end
    tiles[1].value:SetText(on .. "  |cFF8C8475/ " .. #all .. "|r")
    tiles[2].value:SetText("|cFF7FD08A" .. here .. "|r")
    local gOn
    if IsInGuild and IsInGuild() and GetNumGuildMembers then
        local _, o = GetNumGuildMembers()
        gOn = tonumber(o)
    end
    tiles[3].value:SetText(gOn and (gOn .. "  |cFF8C8475on|r") or "|cFF8C8475No guild|r")
    tabFriends:SetCount(on)
    tabGuild:SetCount(gOn)
    UpdateSelf()
end

-- an online friend who is in your party or raid
local function InMyGroup(name)
    if not name or not (IsInGroup and IsInGroup()) then return false end
    local ok, a = pcall(UnitInParty, name)
    if ok and a then return true end
    local ok2, b = pcall(UnitInRaid, name)
    return (ok2 and b) and true or false
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
            items[1]._first = true
            items[#items]._last = true
            for _, e in ipairs(items) do view[#view + 1] = e end
        end
    end
    if mode == "friends" then
        local all = CollectFriends()
        local fav, on, off = {}, {}, {}
        local cats = { grp = {}, wow = {}, wowother = {}, game = {}, app = {} }
        for _, e in ipairs(all) do
            if Matches(e, q) then
                if e.fav then fav[#fav + 1] = e
                elseif e.online then
                    local c = Category(e)
                    if c == "wow" and InMyGroup(e.char) then
                        cats.grp[#cats.grp + 1] = e
                    else
                        on[#on + 1] = e
                        local t = cats[c]
                        t[#t + 1] = e
                    end
                else off[#off + 1] = e end
            end
        end
        local FAV_ORDER = { wow = 1, wowother = 2, game = 3, app = 4 }
        table.sort(fav, function(a, b)
            local ra = a.online and FAV_ORDER[Category(a)] or 5
            local rb = b.online and FAV_ORDER[Category(b)] or 5
            if ra ~= rb then return ra < rb end
            return SortName(a, b)
        end)
        AddGroup("fav", "Favorites", fav, true)
        AddGroup("grp", "In my group", cats.grp)
        if d.groupByGame then
            AddGroup("wow", CysUICompat.isForever and "Playing WoW Forever" or "Playing WoW Classic", cats.wow) -- the game you are in
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
        UpdateHeader(all)
    elseif mode == "guild" then
        if IsInGuild and IsInGuild() then
            local all = CollectGuild()
            local on, off = {}, {}
            for _, e in ipairs(all) do
                if Matches(e, q) then
                    if e.online then on[#on + 1] = e else off[#off + 1] = e end
                end
            end
            local function ByRank(a, b)
                if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
                return SortName(a, b)
            end
            table.sort(on, ByRank)
            table.sort(off, SortName)
            -- WoW Forever: the guild message of the day is locked during a fight; show the last one read
            if not InCombatLockdown() and GetGuildRosterMOTD then
                local ok, m = pcall(GetGuildRosterMOTD)
                if ok and type(m) == "string" then lastMOTD = m end
            end
            local motd = lastMOTD or ""
            if motd ~= "" and q == "" then
                view[#view + 1] = { kind = "motd", guild = (GetGuildInfo and GetGuildInfo("player")) or "Guild", text = motd,
                    _first = true, _last = true }
            end
            AddGroup("gon", "Online", on, true)
            AddGroup("goff", "Offline", off, true)
        end
        UpdateHeader()
    elseif mode == "who" then
        local items = CollectWho()
        AddGroup("who", "Results", items, true)
        UpdateHeader()
    else
        local items = {}
        for _, e in ipairs(CollectIgnores()) do
            if Matches(e, q) then items[#items + 1] = e end
        end
        AddGroup("ign", "Ignored", items)
        UpdateHeader()
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
        eb:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "")
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

-- the Guild tab gets one button at the bottom (Blizzard's Guild & Communities window); the other tabs use the full height
local function FooterLayout()
    if not (f and footM) then return end
    local guild = mode == "guild"
    BOTTOM = guild and 42 or 10
    footM:ClearAllPoints()
    footM:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    footM:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    footM:SetShown(guild)
    if fline then fline:SetShown(guild) end
    if addBtn then
        -- the gold button: add a friend / ignore a player, or run the search on the Who tab; none on the Guild tab
        addBtn:SetShown(not guild)
        addBtn.glyph:SetKind(mode == "who" and "right" or "plus")
        densityDD:ClearAllPoints()
        if guild then densityDD:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -SEARCH_Y)
        else densityDD:SetPoint("TOPRIGHT", addBtn, "TOPLEFT", -6, 0) end
    end
    if list then
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", 12, -TOP)
        list:SetPoint("BOTTOMRIGHT", -12, BOTTOM)
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

local function SetMode(m)
    if mode == "guild" and m ~= "guild" then LeaveGuild() end
    mode = m
    tabFriends:SetPrimary(m == "friends")
    tabWho:SetPrimary(m == "who")
    tabGuild:SetPrimary(m == "guild")
    tabIgnore:SetPrimary(m == "ignore")
    if m == "guild" then
        if savedShowOffline == nil and GetGuildRosterShowOffline then savedShowOffline = GetGuildRosterShowOffline() end
        if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end -- we sort online / offline ourselves
        RequestRoster()
    end
    searchHint:SetText(m == "who" and "Search players... (press Enter)" or (m == "friends" and "Search name, zone, note" or "Search..."))
    selected, offset, query = nil, 0, ""
    searchBox:SetText("")
    searchHint:Show()
    CloseMenu()
    Layout()
    Rebuild()
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- the group card: a soft panel and a thin outline (top / bottom edges only on a group's first / last row)
    r.card = W.Texture(r, "BACKGROUND", T.card, -2)
    r.card:SetAllPoints()
    r.bL = W.Texture(r, "BORDER", T.line); r.bL:SetWidth(1); r.bL:SetPoint("TOPLEFT"); r.bL:SetPoint("BOTTOMLEFT")
    r.bR = W.Texture(r, "BORDER", T.line); r.bR:SetWidth(1); r.bR:SetPoint("TOPRIGHT"); r.bR:SetPoint("BOTTOMRIGHT")
    r.bT = W.Texture(r, "BORDER", T.line); r.bT:SetHeight(1); r.bT:SetPoint("TOPLEFT"); r.bT:SetPoint("TOPRIGHT")
    r.bB = W.Texture(r, "BORDER", T.line); r.bB:SetHeight(1); r.bB:SetPoint("BOTTOMLEFT"); r.bB:SetPoint("BOTTOMRIGHT")
    HideCard(r)
    r.hl = W.Texture(r, "BACKGROUND", { T.accent[1], T.accent[2], T.accent[3], 0.06 })
    r.hl:SetPoint("TOPLEFT", 1, -1); r.hl:SetPoint("BOTTOMRIGHT", -1, 0); r.hl:Hide()
    r.sel = W.Texture(r, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.16 })
    r.sel:SetPoint("TOPLEFT", 1, -1); r.sel:SetPoint("BOTTOMRIGHT", -1, 0); r.sel:Hide()
    -- round icon: a dark disc, the class / game icon on it, a status dot on its lower-right corner
    r.iconBg = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.iconBg:SetTexture(CIRCLE)
    r.iconBg:SetVertexColor(T.border[1], T.border[2], T.border[3], 0.8)
    r.iconBg:SetSize(26, 26)
    r.iconBg:SetPoint("LEFT", 8, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("CENTER", r.iconBg, "CENTER", 0, 0)
    pcall(function()
        local mask = r:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(r.icon)
        r.icon:AddMaskTexture(mask)
    end)
    r.statusRing = r:CreateTexture(nil, "OVERLAY", nil, 1)
    r.statusRing:SetTexture(CIRCLE)
    r.statusRing:SetVertexColor(T.card[1], T.card[2], T.card[3])
    r.statusRing:SetSize(11, 11)
    r.statusRing:SetPoint("CENTER", r.iconBg, "BOTTOMRIGHT", -3, 3)
    r.status = r:CreateTexture(nil, "OVERLAY", nil, 2)
    r.status:SetTexture(CIRCLE)
    r.status:SetSize(7, 7)
    r.status:SetPoint("CENTER", r.statusRing, "CENTER", 0, 0)
    -- gold edge on the left of the selected row
    r.edge = W.Texture(r, "ARTWORK", T.accent)
    r.edge:SetWidth(2)
    r.edge:SetPoint("TOPLEFT", 1, -1)
    r.edge:SetPoint("BOTTOMLEFT", 1, 1)
    r.edge:Hide()
    r.name = W.Text(r, 13, T.text)
    r.name:SetWordWrap(false)
    r.right = W.Text(r, 11, T.accent, "RIGHT") -- level (gold) on people, the count on headers
    r.sub = W.Text(r, 11, T.dim)
    r.sub:SetWordWrap(false)
    r.zone = W.Text(r, 11, T.dim, "RIGHT") -- Compact rows: zone / game / last seen, before the level
    r.zone:SetWordWrap(false)
    r.line = W.Texture(r, "ARTWORK", T.line)
    r.line:SetHeight(1)
    r.line:Hide()

    -- hover buttons
    local a = CreateFrame("Frame", nil, r)
    a:SetPoint("RIGHT", -6, 0)
    a:SetSize(1, 22)
    a:Hide()
    a.all = {}
    local function Act(label, w, fn)
        local b = W.Button(a, w, 22, label)
        b:SetScript("OnClick", function() local e = r.entry; if e then fn(e) end end)
        b:HookScript("OnLeave", function() if not r:IsMouseOver() then r.hl:Hide(); HideActs(r) end end)
        b:Hide()
        a.all[#a.all + 1] = b
        return b
    end
    a.whisper = Act("Whisper", 54, Whisper)
    a.invite = Act("Invite", 44, Invite)
    a.more = Act("...", 26, function(e) Select(e); OpenMenu(r, e) end)
    a.unignore = Act("Unignore", 66, function(e) Remove(e); dirty = true end)
    r.acts = a
    ApplyDensity(r)

    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        ShowActs(s)
        local e = s.entry
        if e and e.kind == "motd" and GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.guild or "Guild", 1, 0.82, 0)
            GameTooltip:AddLine(e.text or "", 1, 1, 1, true)
            GameTooltip:Show()
        elseif e and e.kind == "guild" and GameTooltip then
            -- guild member: name, rank, level, zone, note, and the Cys's UI line if they run it
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            local cc = e.file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.file]
            GameTooltip:SetText(Ambiguate(e.name or "?", "guild"), cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1)
            if e.rank then GameTooltip:AddLine(e.rank, 1, 0.82, 0) end
            GameTooltip:AddLine(format("Level %s %s", tostring(e.level or "?"), e.class or ""), 1, 1, 1)
            if e.area and e.area ~= "" then GameTooltip:AddLine(e.area, 0.7, 0.7, 0.7) end
            if e.note and e.note ~= "" then GameTooltip:AddLine(e.note, 0.8, 0.8, 0.8, true) end
            if CUI.Hello and CUI.Hello.AddLine then CUI.Hello.AddLine(GameTooltip, e.name) end
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(s)
        if GameTooltip and GameTooltip:GetOwner() == s then GameTooltip:Hide() end
        if s:IsMouseOver() then return end -- moved onto one of its own hover buttons
        s.hl:Hide()
        HideActs(s)
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

function Layout()
    if not f then return end
    ROW_H = DB().density == "compact" and 24 or 36
    FooterLayout()
    local w = f:GetWidth() - 24
    if tiles then
        local tw = (w - 12) / 3
        for i, t in ipairs(tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * (tw + 6), -TILE_Y)
            t:SetWidth(tw)
        end
    end
    local shown = {}
    for _, b in ipairs({ tabFriends, tabWho, tabGuild, tabIgnore }) do if b.usable then shown[#shown + 1] = b end end
    local bw = (w - 6 - (#shown - 1) * 2) / max(1, #shown)
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 3 + (i - 1) * (bw + 2), -3)
        b:SetWidth(bw)
    end
    local vis = Visible()
    for i = 1, vis do
        if not rows[i] then rows[i] = MakeRow(i) end
        local r = rows[i]
        r:SetHeight(ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -10, -(i - 1) * ROW_H)
    end
    Update()
end

local DENSITY_OPTS = { { "comfortable", "Comfortable" }, { "compact", "Compact" } }

local function BuildHeader()
    -- header: you (class icon, name, level, broadcast), your status and close; then three count tiles
    local hbg = W.Texture(f, "BACKGROUND", T.header, -1)
    hbg:SetPoint("TOPLEFT", 1, -1)
    hbg:SetPoint("TOPRIGHT", -1, -1)
    hbg:SetHeight(TILE_Y + TILE_H + 6)
    local hline = W.Texture(f, "BORDER", T.line)
    hline:SetHeight(1)
    hline:SetPoint("TOPLEFT", 1, -(TILE_Y + TILE_H + 7))
    hline:SetPoint("TOPRIGHT", -1, -(TILE_Y + TILE_H + 7))

    me = {}
    me.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
    me.ring:SetTexture(CIRCLE)
    me.ring:SetSize(36, 36)
    me.ring:SetPoint("TOPLEFT", 12, -10)
    me.ring:SetVertexColor(T.brand[1], T.brand[2], T.brand[3])
    me.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
    me.icon:SetSize(32, 32)
    me.icon:SetPoint("CENTER", me.ring, "CENTER", 0, 0)
    pcall(function()
        local mask = f:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(me.icon)
        me.icon:AddMaskTexture(mask)
    end)
    me.statusRing = f:CreateTexture(nil, "OVERLAY", nil, 1)
    me.statusRing:SetTexture(CIRCLE)
    me.statusRing:SetVertexColor(T.header[1], T.header[2], T.header[3])
    me.statusRing:SetSize(13, 13)
    me.statusRing:SetPoint("CENTER", me.ring, "BOTTOMRIGHT", -5, 5)
    me.status = f:CreateTexture(nil, "OVERLAY", nil, 2)
    me.status:SetTexture(CIRCLE)
    me.status:SetSize(9, 9)
    me.status:SetPoint("CENTER", me.statusRing, "CENTER", 0, 0)
    me.name = W.Text(f, 14, T.text)
    me.name:SetWordWrap(false)
    me.name:SetPoint("TOPLEFT", 56, -12)
    me.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -138, -12)

    if BNSetCustomMessage then
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 56, -31)
        holder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -138, -31)
        holder:SetHeight(16)
        bcBox = CreateFrame("EditBox", nil, holder)
        bcBox:SetAllPoints()
        bcBox:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "")
        bcBox:SetTextColor(0.85, 0.82, 0.77)
        bcBox:SetAutoFocus(false)
        bcBox:SetMaxLetters(127)
        bcHint = W.Text(holder, 11, T.dim)
        bcHint:SetPoint("LEFT", 0, 0)
        bcHint:SetText("Set a broadcast message")
        bcBox:SetScript("OnEditFocusGained", function() bcHint:Hide() end)
        bcBox:SetScript("OnEditFocusLost", function(s) bcHint:SetShown((s:GetText() or "") == "") end)
        bcBox:SetScript("OnEscapePressed", function(s) s:SetText(MyBroadcast()); s:ClearFocus() end)
        bcBox:SetScript("OnEnterPressed", function(s)
            local t = s:GetText() or ""
            if strtrim then t = strtrim(t) end
            pcall(BNSetCustomMessage, t)
            s:ClearFocus()
        end)
        bcBox:SetScript("OnEnter", function(s)
            if s:HasFocus() then return end
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Broadcast message", 1, 0.82, 0)
            GameTooltip:AddLine("Shown to your Battle.net friends. Enter saves, Esc cancels.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        bcBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    if BNGetInfo and BNSetAFK then
        statusDD = W.Dropdown(f, 88, STATUS_OPTS, MyStatus, function(v)
            SetMyStatus(v)
            local c = StatusColor(v)
            statusDD.dot:SetVertexColor(c[1], c[2], c[3])
            me.status:SetVertexColor(c[1], c[2], c[3])
        end)
        statusDD:SetPoint("TOPRIGHT", -40, -14)
        statusDD.dot = statusDD:CreateTexture(nil, "OVERLAY")
        statusDD.dot:SetTexture(CIRCLE)
        statusDD.dot:SetSize(8, 8)
        statusDD.dot:SetPoint("LEFT", 9, 0)
        statusDD.label:ClearAllPoints()
        statusDD.label:SetPoint("LEFT", 22, 0)
        statusDD.label:SetPoint("RIGHT", -20, 0)
    end

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -12, -14)
    W.Border(close, 1, T.line, "BORDER")
    local x = CysUI.W.CloseGlyph(close, T.text)
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
    close:SetScript("OnClick", function() CUI:HideWindow(f) end)
end

local function BuildControls()
    -- count tiles: friends online, friends in this game, guild online (click Guild to open that tab)
    tiles = {}
    local TILE_LABELS = { "ONLINE", CysUICompat.isForever and "IN FOREVER" or "IN THIS GAME", "GUILD" }
    for i = 1, 3 do
        local t = CreateFrame("Button", nil, f)
        t:SetHeight(TILE_H)
        t.bg = W.Texture(t, "BACKGROUND", T.card)
        t.bg:SetAllPoints()
        t.edges = W.Border(t, 1, T.line, "BORDER")
        t.label = W.Text(t, 9, T.dim)
        t.label:SetPoint("TOPLEFT", 9, -7)
        t.label:SetText(TILE_LABELS[i])
        t.value = W.Text(t, 16, T.text)
        t.value:SetPoint("BOTTOMLEFT", 9, 6)
        t:SetScript("OnEnter", function(s) W.SetBorder(s.edges, T.glow) end)
        t:SetScript("OnLeave", function(s) W.SetBorder(s.edges, T.line) end)
        t:SetScript("OnClick", function() SetMode(i == 3 and "guild" or "friends") end)
        tiles[i] = t
    end

    -- tabs: one dark strip, the open tab filled with a soft gold, online counts in the labels
    tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", 12, -TAB_Y)
    tabBar:SetPoint("TOPRIGHT", -12, -TAB_Y)
    tabBar:SetHeight(TAB_H)
    W.Texture(tabBar, "BACKGROUND", T.field):SetAllPoints()
    W.Border(tabBar, 1, T.line, "BORDER")
    local function Tab(label)
        local b = CreateFrame("Button", nil, tabBar)
        b:SetSize(60, TAB_H - 6)
        b.usable = true
        b.fill = W.Texture(b, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.16 })
        b.fill:SetAllPoints()
        b.fill:Hide()
        b.text = W.Text(b, 12, T.dim, "CENTER")
        b.text:SetPoint("CENTER", 0, 0)
        b.label = label
        function b:Paint()
            local c = self.on and T.accent or (self.hot and T.text or T.dim)
            self.text:SetTextColor(c[1], c[2], c[3])
            local n = self.count
            self.text:SetText(self.label .. ((n and n > 0) and ("  " .. (self.on and "|cFFC9A55E" or "|cFF8C8475") .. n .. "|r") or ""))
            self.fill:SetShown(self.on and true or false)
        end
        function b:SetPrimary(on) self.on = on; self:Paint() end
        function b:SetCount(n) self.count = n; self:Paint() end
        b:SetScript("OnEnter", function(s) s.hot = true; s:Paint() end)
        b:SetScript("OnLeave", function(s) s.hot = false; s:Paint() end)
        b:Paint()
        return b
    end
    tabFriends = Tab("Friends")
    tabFriends:SetScript("OnClick", function() SetMode("friends") end)
    tabWho = Tab("Who")
    tabWho:SetScript("OnClick", function() SetMode("who") end)
    -- WoW Forever: /who lives in Blizzard's Looking For Group window there, so ours steps aside
    if CysUICompat.isForever then tabWho.usable = false; tabWho:Hide() end
    tabGuild = Tab("Guild")
    tabGuild:SetScript("OnClick", function() SetMode("guild") end)
    tabIgnore = Tab("Ignore")
    tabIgnore:SetScript("OnClick", function() SetMode("ignore") end)

    -- search row: search box, row size dropdown, gold add button
    addBtn = CreateFrame("Button", nil, f)
    addBtn:SetSize(SEARCH_H, SEARCH_H)
    addBtn:SetPoint("TOPRIGHT", -12, -SEARCH_Y)
    addBtn.bg = W.Texture(addBtn, "BACKGROUND", T.brand)
    addBtn.bg:SetAllPoints()
    addBtn.glyph = W.Glyph(addBtn, "plus", 10, T.dark, 2)
    addBtn.glyph:SetPoint("CENTER", 0, 0)
    addBtn:SetScript("OnEnter", function(s)
        s.bg:SetAlpha(0.8)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(mode == "who" and "Search" or (mode == "ignore" and "Ignore a player" or "Add a friend"), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function(s) s.bg:SetAlpha(1); GameTooltip:Hide() end)
    addBtn:SetScript("OnClick", function()
        if mode == "who" then RunWho()
        elseif mode == "ignore" then OpenPopup("Ignore Player", "Character name", AddIgnore)
        else OpenPopup("Add Friend", "Character name, or a BattleTag like Name#1234", AddFriend) end
    end)

    densityDD = W.Dropdown(f, 112, DENSITY_OPTS, function() return DB().density end, function(v)
        DB().density = v
        Layout()
    end)
    densityDD:SetHeight(SEARCH_H)
    densityDD:SetPoint("TOPRIGHT", addBtn, "TOPLEFT", -6, 0)

    local sbox = CreateFrame("Frame", nil, f)
    sbox:SetPoint("TOPLEFT", 12, -SEARCH_Y)
    sbox:SetPoint("TOPRIGHT", densityDD, "TOPLEFT", -6, 0)
    sbox:SetHeight(SEARCH_H)
    W.Texture(sbox, "BACKGROUND", T.field):SetAllPoints()
    W.Border(sbox, 1, T.line, "BORDER")
    searchBox = CreateFrame("EditBox", nil, sbox)
    searchBox:SetPoint("TOPLEFT", 8, 0)
    searchBox:SetPoint("BOTTOMRIGHT", -6, 0)
    searchBox:SetFont(CysUICompat.Font(), CysUICompat.FontSize(12), "")
    searchBox:SetTextColor(T.text[1], T.text[2], T.text[3])
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchHint = W.Text(sbox, 11, T.dim)
    searchHint:SetPoint("LEFT", 9, 0)
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
end

local function Build()
    BuildClassMap()
    f = CreateFrame("Frame", "CysFriendsFrame", UIParent)
    f:SetSize(360, 600)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    f:Hide()
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")
    rows = {}
    BuildHeader()
    BuildControls()

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

    -- footer (Guild tab only): Blizzard's Guild & Communities window
    fline = W.Texture(f, "BORDER", T.line)
    fline:SetHeight(1)
    fline:SetPoint("BOTTOMLEFT", 1, 42)
    fline:SetPoint("BOTTOMRIGHT", -1, 42)
    fline:Hide()
    footM = W.Button(f, 100, 24, "Open Guild & Communities")
    footM:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    footM:SetScript("OnClick", OpenGuildWindow)
    footM:Hide()
    if CysUICompat and CysUICompat.isForever and _G.GuildMicroButton then
        -- WoW Forever: opening Blizzard's guild window from addon code taints the game's window manager (the
        -- world map's quest pins then get blocked). A secure click on Blizzard's Guild micro button sits over
        -- this button instead. It belongs to UIParent, so this window stays free to open and move in combat,
        -- and it steps away in combat (the button then says so).
        local px = CreateFrame("Button", "CysFriendsGuildProxy", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
        px:RegisterForClicks("AnyUp")
        px:SetAttribute("useOnKeyDown", false)
        px:SetAttribute("type", "click")
        px:SetAttribute("clickbutton", _G.GuildMicroButton)
        px:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
        RegisterStateDriver(px, "combat", "[combat] 1; 0")
        px:Hide()
        px:SetScript("OnEnter", function() local h = footM:GetScript("OnEnter"); if h then pcall(h, footM) end end)
        px:SetScript("OnLeave", function() local h = footM:GetScript("OnLeave"); if h then pcall(h, footM) end end)
        local lastX, lastY
        local function Place()
            if InCombatLockdown() then return end
            local x, y = footM:GetLeft(), footM:GetBottom()
            if f:IsShown() and footM:IsShown() and x and y then
                local s = footM:GetEffectiveScale() / UIParent:GetEffectiveScale()
                px:ClearAllPoints()
                px:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x * s, y * s)
                px:SetSize(footM:GetWidth() * s, footM:GetHeight() * s)
                px:SetFrameStrata(f:GetFrameStrata())
                px:SetFrameLevel(footM:GetFrameLevel() + 5)
                px:Show()
                lastX, lastY = x, y
            else
                px:Hide()
                lastX, lastY = nil, nil
            end
        end
        footM:HookScript("OnShow", Place)
        footM:HookScript("OnHide", Place)
        f:HookScript("OnShow", Place)
        f:HookScript("OnHide", Place)
        -- the window can be dragged: follow it (cheap, only while shown and out of combat)
        local wait = 0
        f:HookScript("OnUpdate", function(_, elapsed)
            wait = wait + elapsed
            if wait < 0.2 or InCombatLockdown() then return end
            wait = 0
            if footM:IsShown() and (footM:GetLeft() ~= lastX or footM:GetBottom() ~= lastY or not px:IsShown()) then Place() end
        end)
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:SetScript("OnEvent", Place)
        footM:SetScript("OnClick", function()
            CUI:Print("The guild window opens from here after combat (or use your guild key).")
        end)
    end
    -- events: refresh when the lists change (batched)
    for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "IGNORELIST_UPDATE", "WHO_LIST_UPDATE", "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "PLAYER_GUILD_UPDATE",
        "BN_INFO_CHANGED", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE" }) do
        if not (ev == "WHO_LIST_UPDATE" and CysUICompat.isForever) then pcall(f.RegisterEvent, f, ev) end
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
            elseif FriendsFrame and FriendsFrame:IsShown() then pcall(FriendsFrame.Hide, FriendsFrame) end -- not HideUIPanel: taints the window manager
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
    CUI:ManageWindow(f, "left", 0) -- the same spot as Blizzard's Friends window

    SetMode("friends")

    CUI:RegisterMovable(f, "friends", "Friends Window", {
        point = "LEFT", x = 40, y = 0,
        resizable = true, minW = 320, maxW = 600, minH = 440, maxH = 900,
        onResize = function() Layout() end,
        freeMove = true, -- dragged by the title strip, resized by the corner grip
    })
    CUI:MakeResizeGrip("friends")
    -- drag the top of the header to move the window (the broadcast box, status and close keep their clicks)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", 1, -1)
    drag:SetPoint("TOPRIGHT", -138, -1)
    drag:SetHeight(48)
    drag:SetFrameLevel(f:GetFrameLevel())
    CUI:MakeDragHandle(drag, "friends")
end

--------------------------------------------------------------------------------
-- Open / close, Social key
--------------------------------------------------------------------------------
function F.Rebuild() if f then Rebuild() end end
F.SetMode, F.RunWho = SetMode, RunWho

-- Open the window on the Who tab and run a search (what /who does when we take it over)
function F:OpenWho(text)
    if not f or CysUICompat.isForever then return end
    CUI:ShowWindow(f)
    SetMode("who")
    query = strtrim and strtrim(text or "") or (text or "")
    searchBox:SetText(query)
    RunWho()
end

local origWho
function F.ApplyWho()
    if not SlashCmdList then return end
    if DB().takeKey and f and not CysUICompat.isForever then -- Forever: /who stays Blizzard's (Looking For Group)
        if not origWho then origWho = SlashCmdList["WHO"] end
        SlashCmdList["WHO"] = function(msg) F:OpenWho(msg) end
    elseif origWho then
        SlashCmdList["WHO"] = origWho
    end
end

function F.IsActive() return f ~= nil and DB().takeKey end

function F:Toggle()
    if not f then return end
    CUI:ToggleWindow(f)
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

--------------------------------------------------------------------------------
-- "Guild invite" in the right-click menu of other players (unit frames, chat names, party and raid).
-- Only shown to players who are allowed to invite. It opens a small box with /ginvite Name to copy into chat.
--------------------------------------------------------------------------------
do
    -- Forever lets only the game's own code send guild invites (C_GuildInfo.Invite is Blizzard-only). Even a chat
    -- box opened by addon code is blocked, so we show "/ginvite Name" in a box of our own to copy and paste.
    local W, T = CysUI.W, CysUI.W.T
    local copy
    local function ShowCopy(text)
        if not copy then
            copy = CreateFrame("Frame", "CysGInviteCopy", UIParent)
            copy:SetSize(320, 86)
            copy:SetPoint("CENTER", 0, 120)
            copy:SetFrameStrata("DIALOG")
            copy:EnableMouse(true)
            W.Texture(copy, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.96 }):SetAllPoints()
            W.Border(copy, 1, T.border, "BORDER")
            local title = W.Text(copy, 12, T.accent)
            title:SetPoint("TOPLEFT", 10, -8)
            title:SetText("Guild invite")
            local tip = W.Text(copy, 11, T.desc)
            tip:SetPoint("TOPLEFT", 10, -26)
            tip:SetText("Ctrl+C, then Enter, Ctrl+V, Enter")
            local holder = CreateFrame("Frame", nil, copy)
            holder:SetPoint("BOTTOMLEFT", 10, 10); holder:SetPoint("BOTTOMRIGHT", -10, 10); holder:SetHeight(24)
            W.Texture(holder, "BACKGROUND", T.field):SetAllPoints()
            W.Border(holder, 1, T.border, "BORDER")
            local eb = CreateFrame("EditBox", nil, holder)
            eb:SetPoint("TOPLEFT", 6, 0); eb:SetPoint("BOTTOMRIGHT", -6, 0)
            eb:SetFontObject(ChatFontNormal)
            eb:SetAutoFocus(false)
            eb:SetScript("OnEscapePressed", function() copy:Hide() end)
            eb:SetScript("OnEnterPressed", function() copy:Hide() end)
            eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(copy.text or ""); s:HighlightText() end end)
            eb:SetScript("OnKeyUp", function(_, key) if key == "C" and IsControlKeyDown() then copy:Hide() end end)
            copy.eb = eb
            local x = CreateFrame("Button", nil, copy)
            x:SetSize(20, 20); x:SetPoint("TOPRIGHT", -4, -4)
            x.t = CysUI.W.CloseGlyph(x, { 1, 1, 1 })
            x:SetScript("OnClick", function() copy:Hide() end)
        end
        copy.text = text
        copy:Show()
        copy.eb:SetText(text)
        copy.eb:SetFocus()
        copy.eb:HighlightText()
    end
    function CysUI.GuildInviteChat(name)
        if type(name) ~= "string" or name == "" then return end
        ShowCopy("/ginvite " .. name)
    end
end

do
    local Secret = (CysUICompat and CysUICompat.Secret) or function() return false end
    local function AddGuildInvite(_, root, ctx)
        if type(ctx) ~= "table" or DB().guildInviteMenu == false then return end
        if not (IsInGuild and IsInGuild() and CanGuildInvite and CanGuildInvite()) then return end
        local name, server, unit = ctx.name, ctx.server, ctx.unit
        if type(name) ~= "string" or Secret(name) or name == "" then return end
        if type(server) ~= "string" or Secret(server) then server = nil end
        if unit then
            local isPlayer, me, theirs, mine = UnitIsPlayer(unit), UnitIsUnit(unit, "player"), UnitFactionGroup(unit), UnitFactionGroup("player")
            if Secret(isPlayer) or Secret(me) or Secret(theirs) then return end
            if not isPlayer or me or theirs ~= mine then return end
            local guild = GetGuildInfo(unit)
            if Secret(guild) or guild then return end -- already in a guild
        elseif name == UnitName("player") and not server then
            return
        end
        local full = name
        if server and server ~= "" and server ~= (GetNormalizedRealmName and GetNormalizedRealmName() or "") then
            full = name .. "-" .. server
        end
        root:CreateDivider()
        root:CreateButton("Guild invite", function() CysUI.GuildInviteChat(full) end)
    end
    local hook = CreateFrame("Frame")
    hook:RegisterEvent("PLAYER_LOGIN")
    hook:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not (Menu and Menu.ModifyMenu) then return end
        for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER" }) do
            Menu.ModifyMenu(tag, function(owner, root, ctx) pcall(AddGuildInvite, owner, root, ctx) end)
        end
    end)
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
    local gi = W.Checkbox(page, "Add Guild invite to the right-click menu of players",
        function() return DB().guildInviteMenu ~= false end,
        function(on) DB().guildInviteMenu = on end)
    gi:SetPoint("TOPLEFT", 4, -90)
    local note = W.Notes(page, 4, -122, width, "", {
            "Guild invite shows on players who are not in a guild, and only if your rank can invite.",
            { "/cfriends", "opens the window any time; drag its title to move it, the corner grip to resize it." },
            "Point at someone for Whisper / Invite / more buttons; double-click a name to whisper, right-click for the menu.",
            "Row size (Comfortable or Compact) is the dropdown next to the search box.",
            "Your status (Online / Away / Busy) and Battle.net broadcast are at the top of the window.",
            "The Who tab searches players (name, level range, class or zone) when you press Enter.",
            "Blizzard's own friends window is untouched and still opens from the micro menu.",
        })
end)
