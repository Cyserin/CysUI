--------------------------------------------------------------------------------
-- Cys's UI - Guild Recruiter (WoW Forever)
--
-- Searches /who for players without a guild in your level range and whispers them your message, one step per
-- key press or click (the game only allows /who from a real key press or click). Nobody is whispered twice
-- within the days you pick. Players who answer show in a small box: interested ones in gold, questions in white.
-- Invites are never sent by themselves: Invite shows /ginvite Name to copy into chat (the game allows no other way).
-- Optional: welcome new members in guild chat (one welcome per new member when several guildies run Cys's UI).
-- Left the guild: players who left or were removed show in the window until the days you pick have passed
-- (also the ones who left while you were offline, found by comparing the guild roster with your last login).
-- Guild levels: how many members sit in each level bracket (from the same roster snapshot), so thin brackets
-- stand out (with their share of the guild in %); click a bracket to recruit those levels.
-- Also recruiting: guildies running this recruiter right now, and their levels (guild addon channel).
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "recruit", name = "Guild Recruiter", foreverOnly = true,
    desc = "Finds players without a guild with /who, whispers them your message and lists the ones who answer so you can invite them.",
    open = function() CysUI:OpenConfig("Guild Recruiter") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T

local R = {}
CUI.Recruit = R

CysUIDB.recruit = CysUIDB.recruit or {}
local db = CysUIDB.recruit
local DEFAULT_MSG = "Hi {first}! {guild} is a friendly guild looking for new members. Want to join us? Just reply and I'll send you an invite. :)"
local DEFAULT_WELCOME = "Welcome to {guild}, {first}! Glad to have you with us."
if db.msg == nil then db.msg = DEFAULT_MSG end
if db.welcomeMsg == nil then db.welcomeMsg = DEFAULT_WELCOME end
db.lo = db.lo or 5
db.hi = db.hi or 60
db.gap = db.gap or 10
db.cap = db.cap or 50
db.days = db.days or 7
if db.hideSent == nil then db.hideSent = true end
if db.chatNote == nil then db.chatNote = true end
if db.welcome == nil then db.welcome = false end -- talks in guild chat: off by default
db.contacted = db.contacted or {} -- [realm-faction] = { [lower name] = time() }
db.box = db.box or {}             -- [realm-faction] = { { name, lvl, class, text, t, kind } }
db.left = db.left or {}           -- [realm-faction] = { { name, key, lvl, class, rank, t, by, offline } }
db.roster = db.roster or {}       -- [realm-faction] = { guild, n, m = { [key] = { n, l, c, r } } }
db.leftDays = db.leftDays or 3
if db.leftShow == nil then db.leftShow = true end
if db.levelsShow == nil then db.levelsShow = true end
db.levelsDays = db.levelsDays or 14 -- only members seen within this many days count

local floor, max, min, time, GetTime = math.floor, math.max, math.min, time, GetTime
local PREFIX = "CysUIRec"
local WHO_GAP, SWEEP_REST, WHO_TIMEOUT, BOX_DAYS = 10, 120, 6, 3
local MAX_WHO = MAX_WHOS_FROM_SERVER or 50
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function RealmKey()
    return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end
local function Contacted()
    local k = RealmKey()
    db.contacted[k] = db.contacted[k] or {}
    return db.contacted[k]
end
local function Box()
    local k = RealmKey()
    db.box[k] = db.box[k] or {}
    return db.box[k]
end
local function Key(name) return (name or ""):lower() end
local function Short(name) return Ambiguate and Ambiguate(name or "", "none") or (name or "") end
local function Secret(v) return CysUICompat and CysUICompat.Secret and CysUICompat.Secret(v) end
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100Cys's UI|r " .. msg) end
local function MaxLevel()
    local m = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    return (type(m) == "number" and m >= 60) and m or 60
end
local function Fill(text, name)
    local guild = GetGuildInfo("player") or "our guild"
    local first = (name or ""):match("^(%S+)") or name or ""
    text = (text or ""):gsub("{name}", function() return name or "" end)
    text = text:gsub("{first}", function() return first end)
    return (text:gsub("{guild}", function() return guild end))
end
-- a Blizzard format string ("%s has joined the guild.") as a pattern that catches the name
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$s", "\001"):gsub("%%s", "\001")
    fmt = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("\001", "(.+)") .. "$"
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
R.running = false
local queue = {}        -- players found by /who, waiting for their whisper: { name, lvl, class }
local queued = {}       -- [lower name] = true
local searches = {}     -- { filter, class } in sweep order
local searchIdx = 0
local foundThisSweep = 0
local nextWho, nextWhisper = 0, 0
local inFlight          -- the /who we are waiting on: { filter, class, sent = GetTime() }
local session = { whispered = 0, replies = 0, joined = 0 }
local sentText = {}     -- [lower name] = { text, t } for hiding our own whispers
local pendingWelcome    -- { name } waiting for the next key press
local welcomeTimers = {} -- [lower name] = cancelled flag table
local lastNote = ""      -- one-line status for the window
local frame, kb

-- Who else in the guild is recruiting: each Cys's UI tells the guild addon channel "R:lo:hi" while it runs
-- (again every minute), "X" when it stops; "Q" (sent at login) asks everyone running to answer.
local others = {}       -- [name] = { lo, hi, t = GetTime() }
local OTHERS_TTL = 150  -- no word for this long: they stopped (or logged off)
local announceTicker
local function Send(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD") end
end
local function Announce()
    if R.running then Send("R:" .. min(db.lo, db.hi) .. ":" .. max(db.lo, db.hi)) else Send("X") end
end
local function Others()
    local out, now = {}, GetTime()
    for n, o in pairs(others) do
        if now - o.t > OTHERS_TTL then others[n] = nil
        else out[#out + 1] = { name = n, lo = o.lo, hi = o.hi } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
R.Others = Others

local function BuildSearches()
    wipe(searches)
    local lo, hi = max(1, db.lo), min(MaxLevel(), db.hi)
    if hi < lo then lo, hi = hi, lo end
    local a = lo
    while a <= hi do
        local b = min(hi, a + 4)
        searches[#searches + 1] = { range = a .. "-" .. b }
        a = b + 1
    end
    searchIdx, foundThisSweep = 0, 0
    if R.running then Announce() end -- new levels: tell the guild
end

local function Recent(name)
    local t = Contacted()[Key(name)]
    return t and (time() - t) < db.days * 86400
end

local function InBox(name)
    local k = Key(name)
    for _, e in ipairs(Box()) do if Key(e.name) == k then return e end end
end

local function Eligible(name)
    if not name or name == "" or Secret(name) then return false end
    if Key(name) == Key(UnitName("player")) then return false end
    if not name:find("%a") then return false end -- names only in another alphabet are passed by
    if queued[Key(name)] or Recent(name) or InBox(name) then return false end
    return true
end

-- guild members by first name part (roster names are "Name Realm" or "Name-Realm" on Forever)
local function BaseKey(name)
    if type(name) ~= "string" then return nil end
    local b = name:match("^[^%s%-]+")
    return b and b:lower()
end
local function Left()
    local k = RealmKey()
    db.left[k] = db.left[k] or {}
    return db.left[k]
end
local function PruneLeft()
    local list, now = Left(), time()
    local keep = (db.leftDays or 3) * 86400
    for i = #list, 1, -1 do
        if now - (list[i].t or 0) > keep then table.remove(list, i) end
    end
end

local function PruneBox()
    local box, now = Box(), time()
    for i = #box, 1, -1 do
        if now - (box[i].t or 0) > BOX_DAYS * 86400 then table.remove(box, i) end
    end
end

--------------------------------------------------------------------------------
-- /who without the Who window popping open: while OUR search is out, the frames that would show the
-- results stop listening to WHO_LIST_UPDATE; they listen again as soon as the answer (or the timeout) comes.
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local detached = {}
local function Detach()
    if not GetFramesRegisteredForEvent then return end
    local ok, list = pcall(function() return { GetFramesRegisteredForEvent("WHO_LIST_UPDATE") } end)
    if not ok then return end
    for _, f in ipairs(list) do
        if f ~= ev and f.UnregisterEvent and pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE") then
            detached[#detached + 1] = f
        end
    end
end
local function Reattach()
    for i = #detached, 1, -1 do
        pcall(detached[i].RegisterEvent, detached[i], "WHO_LIST_UPDATE")
        detached[i] = nil
    end
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, false) end
end

local function WhoWindowOpen()
    local ok, shown = pcall(function()
        local f = LFGParentFrame or (FriendsFrame and WhoFrame and FriendsFrame)
        return f and f:IsShown() and true or false
    end)
    return ok and shown == true
end

local function Blocked()
    if InCombatLockdown() then return "paused in combat" end
    local _, it = IsInInstance()
    if it == "pvp" or it == "arena" then return "paused in battlegrounds and arenas" end
    return nil
end

local function DoWho()
    if #searches == 0 then BuildSearches() end
    searchIdx = searchIdx + 1
    if searchIdx > #searches then
        -- a full sweep is done: rest longer when it found nobody new
        local quiet = foundThisSweep == 0
        searchIdx, foundThisSweep = 0, 0
        -- drop class searches added for a crowded range; they are added again if still needed
        for i = #searches, 1, -1 do if searches[i].class then table.remove(searches, i) end end
        if quiet then nextWho = GetTime() + SWEEP_REST; lastNote = "Nobody new in range, searching again soon"; return end
        searchIdx = 1
    end
    local s = searches[searchIdx]
    local filter = 'g-"" ' .. s.range
    if s.class then filter = filter .. ' c-"' .. s.class .. '"' end
    inFlight = { filter = filter, s = s, sent = GetTime() }
    nextWho = GetTime() + WHO_GAP
    Detach()
    if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
    local ok = pcall(C_FriendList.SendWho, filter)
    if not ok then inFlight = nil; Reattach(); lastNote = "The game refused the search, trying again" ; return end
    lastNote = "Searching levels " .. s.range .. (s.classLabel and (" (" .. s.classLabel .. ")") or "")
    C_Timer.After(WHO_TIMEOUT, function()
        if inFlight and GetTime() - inFlight.sent >= WHO_TIMEOUT - 0.1 then inFlight = nil; Reattach() end
    end)
end

local function OnWho()
    if not inFlight then return end
    local s = inFlight.s
    inFlight = nil
    local n, total = C_FriendList.GetNumWhoResults()
    n, total = n or 0, total or 0
    local lo, hi = min(db.lo, db.hi), max(db.lo, db.hi)
    local added = 0
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo(i)
        local name = info and info.fullName
        if name and (info.fullGuildName or "") == "" and info.level and info.level >= lo and info.level <= hi
            and Eligible(name) then
            queue[#queue + 1] = { name = name, lvl = info.level, class = info.filename }
            queued[Key(name)] = true
            added = added + 1
        end
    end
    Reattach()
    foundThisSweep = foundThisSweep + added
    -- too many to list (the game shows 50): search that range again one class at a time
    if total > MAX_WHO and not s.class then
        local at = searchIdx
        for _, c in ipairs(CLASSES) do
            local label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]
            if label then
                at = at + 1
                table.insert(searches, at, { range = s.range, class = label, classLabel = label })
            end
        end
    end
    lastNote = added > 0 and ("Found " .. added .. " to whisper in levels " .. s.range) or ("Nobody new in levels " .. s.range)
    if R.Refresh then R.Refresh() end
end

--------------------------------------------------------------------------------
-- One step per real key press or click
--------------------------------------------------------------------------------
local function SendChat(text, kind, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        return pcall(C_ChatInfo.SendChatMessage, text, kind, nil, target)
    end
    return pcall(SendChatMessage, text, kind, nil, target)
end

local UpdateListeners -- defined below (Step needs it)

function R.Step()
    if pendingWelcome and not InCombatLockdown() then
        local w = pendingWelcome
        pendingWelcome = nil
        if IsInGuild() then
            local text = Fill(db.welcomeMsg, w.name)
            if text ~= "" then SendChat(text, "GUILD") end
        end
        UpdateListeners()
        return
    end
    if not R.running then return end
    local why = Blocked()
    if why then lastNote = "Paused: " .. why; return end
    local now = GetTime()
    if #queue > 0 then
        if now < nextWhisper then return end
        local p = table.remove(queue, 1)
        queued[Key(p.name)] = nil
        if Recent(p.name) or InBox(p.name) then return R.Step() end
        local text = Fill(db.msg, p.name)
        if text == "" then R.Stop("Your message is empty"); return end
        local ok = SendChat(text, "WHISPER", p.name)
        if ok then
            Contacted()[Key(p.name)] = time()
            sentText[Key(p.name)] = { text = text, t = now }
            session.whispered = session.whispered + 1
            lastNote = "Whispered " .. p.name
            nextWhisper = now + db.gap
            if session.whispered >= db.cap then R.Stop("Reached " .. db.cap .. " whispers this session") end
        else
            lastNote = "The game refused the whisper"
            nextWhisper = now + db.gap
        end
        if R.Refresh then R.Refresh() end
        return
    end
    if not inFlight and now >= nextWho then
        if WhoWindowOpen() then lastNote = "Waiting for the Who window to close"; return end
        DoWho()
        if R.Refresh then R.Refresh() end
    end
end

local held, lastKey = {}, {}
local function EnsureListeners()
    if kb then return true end
    if InCombatLockdown() then return false end
    kb = CreateFrame("Frame", "CysRecruitKeys")
    kb:SetFrameStrata("TOOLTIP") -- above other addons' keyboard frames
    kb:EnableKeyboard(true)
    kb:SetPropagateKeyboardInput(true) -- never swallow the player's keys
    -- a held key repeats; only its first press counts. Key-up doesn't always arrive, so a key also counts
    -- as released when the game says it is up, or when it comes again after a short pause.
    kb:SetScript("OnKeyDown", function(_, key)
        local now = GetTime()
        local prev = lastKey[key]
        lastKey[key] = now
        if held[key] and prev and now - prev < 0.6 then return end
        held[key] = true
        R.Step()
    end)
    kb:SetScript("OnKeyUp", function(_, key) held[key] = nil end)
    kb:SetScript("OnUpdate", function()
        for k in pairs(held) do
            local ok, down = pcall(IsKeyDown, k)
            if not ok or not down then held[k] = nil end
        end
    end)
    kb:SetScript("OnHide", function() wipe(held) end)
    kb:Hide()
    WorldFrame:HookScript("OnMouseDown", function() if kb:IsShown() then R.Step() end end)
    return true
end
function UpdateListeners()
    if kb then kb:SetShown(R.running or pendingWelcome ~= nil) end
end

function R.Start()
    if R.running then return end
    if not IsInGuild() then Print("You need to be in a guild to recruit."); return end
    if InCombatLockdown() then Print("Start the Guild Recruiter out of combat."); return end
    if not EnsureListeners() then return end
    if (db.msg or "") == "" then Print("Your recruiting message is empty (Guild Recruiter page)."); return end
    if session.whispered >= db.cap then session.whispered = 0 end
    BuildSearches()
    R.running = true
    Announce()
    if announceTicker then announceTicker:Cancel() end
    announceTicker = C_Timer.NewTicker(60, Announce)
    nextWho, nextWhisper = 0, 0
    lastNote = "Press any key or click to take the next step"
    UpdateListeners()
    R.closed = false
    if R.Refresh then R.Refresh(true) end
end

function R.Stop(reason)
    local was = R.running
    R.running = false
    if announceTicker then announceTicker:Cancel(); announceTicker = nil end
    if was then Announce() end
    wipe(queue); wipe(queued)
    if inFlight then inFlight = nil; Reattach() end
    lastNote = reason or "Stopped"
    if reason then Print("Guild Recruiter stopped: " .. reason .. ".") end
    UpdateListeners()
    if R.Refresh then R.Refresh() end
end

--------------------------------------------------------------------------------
-- Replies
--------------------------------------------------------------------------------
local NEG = { "no", "nah", "nope", "no thanks", "no thank you", "no ty", "no thx", "nty", "not interested", "not looking",
    "already", "stop", "pass", "dont", "don't", "leave me", "im good", "i'm good", "im ok", "i'm ok", "im fine", "i'm fine",
    "im set", "i'm set", "not now", "maybe later", "have a guild", "got a guild", "in a guild", "found a guild", "joined", "decline" }
-- a yes word next to one of these is not a yes ("appreciate the invite but im not going to play"): listed as a reply to read
local SOFT = { "not", "but", "sorry", "joining", "later", "maybe", "busy", "solo", "just checking", "thanks though", "ty though" }
local POS = { "yes", "yeah", "yea", "yep", "yup", "ya", "ye", "y", "sure", "ok", "okay", "k", "invite", "inv", "ginv",
    "join", "interested", "please", "pls", "plz", "why not", "count me in", "im in", "i'm in", "absolutely", "definitely", "send it" }
local function Has(text, word)
    return text:find("%f[%w']" .. word:gsub("([%p])", "%%%1") .. "%f[^%w']") ~= nil
end
local function Classify(text)
    local t = " " .. text:lower() .. " "
    if Has(t, "why not") then return "yes" end
    for _, w in ipairs(NEG) do if Has(t, w) then return "no" end end
    for _, w in ipairs(SOFT) do if Has(t, w) then return "ask" end end
    for _, w in ipairs(POS) do if Has(t, w) then return "yes" end end
    return "ask"
end

local function NameLink(name)
    return "|Hplayer:" .. name .. "|h|cFFFFD100[" .. name .. "]|r|h"
end

local function OnWhisper(text, sender)
    if Secret(text) or Secret(sender) then return end
    local name = Short(sender)
    if not name or name == "" then return end
    local ours = Contacted()[Key(name)] and (time() - Contacted()[Key(name)]) < 3 * 86400
    local kind = Classify(text or "")
    -- someone we never whispered still counts when they ask for a guild invite outright
    if not ours and not (kind == "yes" and (text or ""):lower():find("guild")) then return end
    if kind == "no" then return end
    local e = InBox(name)
    if not e then
        e = { name = name }
        local box = Box()
        table.insert(box, 1, e)
        while #box > 30 do table.remove(box) end
    end
    e.text, e.t = text, time()
    if kind == "yes" or e.kind ~= "yes" then e.kind = kind end
    session.replies = session.replies + 1
    if db.chatNote and kind == "yes" then
        Print(NameLink(name) .. " wants to join. Click Invite in the Guild Recruiter.")
    end
    PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
    R.closed = false
    if R.Refresh then R.Refresh(true) end
end

-- hide our own recruiting whispers (and "no player named ...") so they don't fill the chat
local NOTFOUND = Pattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(_, _, msg, target)
        if not db.hideSent or Secret(msg) or Secret(target) then return false end
        local s = sentText[Key(Short(target))]
        return s and s.text == msg and (GetTime() - s.t) < 15 or false
    end)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if not db.hideSent or not NOTFOUND or Secret(msg) then return false end
        local who = msg:match(NOTFOUND)
        local s = who and sentText[Key(who)]
        return s and (GetTime() - s.t) < 15 or false
    end)
end

--------------------------------------------------------------------------------
-- Invites (only from your click) and joins
--------------------------------------------------------------------------------
local INVITED = Pattern(ERR_GUILD_INVITE_S)
local JOINED = Pattern(ERR_GUILD_JOIN_S)
local DECLINED = Pattern(ERR_GUILD_DECLINE_S)
local pendingInvite = {} -- [lower name] = GetTime()

-- The game sends guild invites only from its own code (even a chat box opened by an addon is blocked):
-- Invite shows /ginvite Name in a small box to copy and paste into chat.
function R.Invite(name)
    if not (CanGuildInvite and CanGuildInvite()) then Print("Your guild rank can't invite."); return end
    if CUI.GuildInviteChat then CUI.GuildInviteChat(name)
    else Print("Type /ginvite " .. name .. " to invite them.") end
end

function R.Remove(name)
    local box = Box()
    for i = #box, 1, -1 do if Key(box[i].name) == Key(name) then table.remove(box, i) end end
    if R.Refresh then R.Refresh() end
end

local function StartWelcome(name)
    if not db.welcome then return end
    local k = Key(name)
    local token = {}
    welcomeTimers[k] = token
    -- wait a moment: if another guildie's Cys's UI says it is welcoming them, stay quiet
    C_Timer.After(1 + math.random() * 4, function()
        if welcomeTimers[k] ~= token then return end
        welcomeTimers[k] = nil
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, "W:" .. k, "GUILD") end
        pendingWelcome = { name = name }
        if not EnsureListeners() then
            -- in combat: try again afterwards
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(s) s:UnregisterAllEvents(); EnsureListeners(); UpdateListeners() end)
        end
        UpdateListeners()
    end)
end

--------------------------------------------------------------------------------
-- Left the guild
--------------------------------------------------------------------------------
local LEFT = Pattern(ERR_GUILD_LEAVE_S)
local KICKED = Pattern(ERR_GUILD_REMOVE_SS)
local loginAt = GetTime()

function R.RemoveLeft(key)
    local list = Left()
    for i = #list, 1, -1 do if list[i].key == key then table.remove(list, i) end end
    if R.Refresh then R.Refresh() end
end

local function AddLeft(name, by, offline)
    local key = BaseKey(name)
    if not key or key == BaseKey(UnitName("player")) then return end
    local list, now = Left(), time()
    for _, e in ipairs(list) do
        if e.key == key then
            if by and not e.by then e.by = Short(by); e.offline = nil end
            return
        end
    end
    local snap = db.roster[RealmKey()]
    local m = snap and snap.m and snap.m[key]
    table.insert(list, 1, {
        name = m and m.n or Short(name):match("^[^%s%-]+") or name, key = key,
        lvl = m and m.l, class = m and m.c, rank = m and m.r,
        t = now, by = by and Short(by) or nil, offline = offline or nil,
    })
    if R.Refresh then R.Refresh() end
end

-- Compare the guild roster with the last one we saw: members gone since then left while we were away.
local function ReadRoster()
    if not IsInGuild() or GetTime() - loginAt < 5 then return end
    local gname = GetGuildInfo("player")
    if not gname or Secret(gname) then return end
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    if Secret(total) or type(total) ~= "number" or total <= 0 then return end
    local m, count = {}, 0
    for i = 1, total do
        local ok, name, rank, _, level, _, _, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
        if not ok or Secret(name) then return end
        local key = BaseKey(name)
        if key then
            -- days since last online (0 = online now); nil when the game won't say
            local days
            if online then days = 0
            elseif GetGuildRosterLastOnline then
                local okL, yr, mo, dy = pcall(GetGuildRosterLastOnline, i)
                if okL and type(yr) == "number" and not Secret(yr) then days = yr * 365 + (mo or 0) * 30 + (dy or 0) end
            end
            m[key] = { n = name:match("^[^%s%-]+"), l = level, c = class, r = rank, o = days }
            count = count + 1
        end
    end
    if count == 0 then return end
    local rk = RealmKey()
    local snap = db.roster[rk]
    if snap and snap.guild == gname and snap.m then
        if count < (snap.n or 0) * 0.5 then return end -- roster not fully loaded yet
        local gone = {}
        for key, old in pairs(snap.m) do
            if not m[key] then gone[#gone + 1] = old.n or key end
        end
        -- a big chunk missing at once is a roster that hasn't fully loaded, not players leaving
        if #gone > 10 and #gone > (snap.n or 0) * 0.25 then return end
        table.sort(gone)
        for _, n in ipairs(gone) do AddLeft(n, nil, true) end
    end
    db.roster[rk] = { guild = gname, n = count, m = m }
    if R.Refresh and frame and frame:IsShown() then R.Refresh() end
end

-- Members per level bracket from the last roster snapshot: { { lo, hi, n, list = { {n, l, c} } } }, counted, low.
-- Only members seen within db.levelsDays count (alts too: the roster can't tell them apart).
local BRACKETS = { { 1, 9 } }
for a = 10, 55, 5 do BRACKETS[#BRACKETS + 1] = { a, a + 4 } end
BRACKETS[#BRACKETS + 1] = { 60, 60 }
function R.Levels()
    local snap = db.roster[RealmKey()]
    local out, total = {}, 0
    for i, b in ipairs(BRACKETS) do out[i] = { lo = b[1], hi = b[2], n = 0, list = {} } end
    if not (snap and snap.m) then return out, 0, 0 end
    local keep = db.levelsDays or 14
    for _, e in pairs(snap.m) do
        local l = tonumber(e.l)
        if l and (not e.o or e.o <= keep) then
            for _, b in ipairs(out) do
                if l >= b.lo and l <= b.hi then
                    b.n = b.n + 1
                    b.list[#b.list + 1] = e
                    total = total + 1
                    break
                end
            end
        end
    end
    -- a bracket under half the average (below max level) is "few"
    local sum, cnt = 0, 0
    for i = 2, #out - 1 do sum = sum + out[i].n; cnt = cnt + 1 end
    local avg = cnt > 0 and sum / cnt or 0
    for i = 1, #out - 1 do out[i].few = out[i].n < avg * 0.5 end
    return out, total, avg
end

function R.RecruitBracket(lo, hi)
    db.lo, db.hi = lo, hi
    BuildSearches()
    Print("Guild Recruiter: now looking for levels " .. lo .. "-" .. hi .. ".")
    if R.Refresh then R.Refresh() end
end

local rosterPending
local function RosterSoon()
    if rosterPending then return end
    rosterPending = true
    C_Timer.After(2, function() rosterPending = nil; pcall(ReadRoster) end)
end

local function OnSystem(msg)
    if Secret(msg) then return end
    local gone, by = nil, nil
    if KICKED then gone, by = msg:match(KICKED) end
    if not gone and LEFT then gone = msg:match(LEFT) end
    if gone then AddLeft(gone, by); return end
    local who = INVITED and msg:match(INVITED)
    if who then pendingInvite[Key(who)] = nil; local e = InBox(who); if e then e.invited = time() end; if R.Refresh then R.Refresh() end; return end
    who = JOINED and msg:match(JOINED)
    if who then
        if InBox(who) or Contacted()[Key(who)] then session.joined = session.joined + 1 end
        local bk = BaseKey(who)
        if bk then R.RemoveLeft(bk) end
        R.Remove(who)
        StartWelcome(who)
        return
    end
    who = DECLINED and msg:match(DECLINED)
    if who then local e = InBox(who); if e then e.declined = true; if R.Refresh then R.Refresh() end end end
end

--------------------------------------------------------------------------------
-- The window: status, Start / Stop, and the players who answered
--------------------------------------------------------------------------------
local WIDTH, HEADER_H, STRIP_H, ROW_H, MAX_ROWS = 340, 26, 46, 36, 8
local LEFT_HEAD, LEFT_ROW, MAX_LEFT = 24, 20, 8
local LV_ROW, LV_BAR = 15, 170
local rows, leftRows, lvRows = {}, {}, {}

local function Ago(t)
    local s = time() - (t or time())
    if s < 60 then return "now" elseif s < 3600 then return floor(s / 60) .. "m" elseif s < 86400 then return floor(s / 3600) .. "h" end
    return floor(s / 86400) .. "d"
end

local function ClassColored(name, class)
    local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return c and c:WrapTextInColorCode(name) or name
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r.hl = W.Texture(r, "BACKGROUND", T.hover); r.hl:SetAllPoints(); r.hl:Hide()
    r.line = W.Texture(r, "BORDER", T.line)
    r.line:SetPoint("BOTTOMLEFT", 8, 0); r.line:SetPoint("BOTTOMRIGHT", -8, 0); r.line:SetHeight(1)
    r.name = W.Text(r, 12, { 1, 1, 1 })
    r.name:SetPoint("TOPLEFT", 10, -4)
    r.age = W.Text(r, 10, T.dim, "RIGHT")
    r.say = W.Text(r, 11, T.desc)
    r.say:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.say:SetWordWrap(false)
    r.x = CreateFrame("Button", nil, r)
    r.x:SetSize(18, 18)
    r.x:SetPoint("RIGHT", -6, 0)
    r.x.text = W.Text(r.x, 12, T.dim, "CENTER"); r.x.text:SetPoint("CENTER"); r.x.text:SetText("x")
    r.x:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    r.x:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    r.x:SetScript("OnClick", function() if r.entry then R.Remove(r.entry.name) end end)
    r.inv = W.Button(r, 58, 20, "Invite", true)
    r.inv:SetPoint("RIGHT", r.x, "LEFT", -4, 0)
    r.inv:SetScript("OnClick", function() if r.entry then R.Invite(r.entry.name) end end)
    r.age:SetPoint("RIGHT", r.inv, "LEFT", -8, 0)
    r.age:SetPoint("TOP", r.name, "TOP")
    r.say:SetPoint("RIGHT", r.inv, "LEFT", -8, 0)
    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        if not s.entry then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine(s.entry.name, 1, 0.82, 0)
        GameTooltip:AddLine(s.entry.text or "", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Invite shows /ginvite and their name to copy: Ctrl+C, Enter, Ctrl+V, Enter. x takes them off the list.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    r:SetPoint("TOPLEFT", 1, -(HEADER_H + STRIP_H + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", -1, -(HEADER_H + STRIP_H + (i - 1) * ROW_H))
    rows[i] = r
    return r
end

local function MakeLeftRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetHeight(LEFT_ROW)
    r:EnableMouse(true)
    r.hl = W.Texture(r, "BACKGROUND", T.hover); r.hl:SetAllPoints(); r.hl:Hide()
    r.name = W.Text(r, 11, { 1, 1, 1 })
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetWordWrap(false)
    r.x = CreateFrame("Button", nil, r)
    r.x:SetSize(18, 18)
    r.x:SetPoint("RIGHT", -6, 0)
    r.x.text = W.Text(r.x, 11, T.dim, "CENTER"); r.x.text:SetPoint("CENTER"); r.x.text:SetText("x")
    r.x:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    r.x:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    r.x:SetScript("OnClick", function() if r.entry then R.RemoveLeft(r.entry.key) end end)
    r.age = W.Text(r, 10, T.dim, "RIGHT")
    r.age:SetPoint("RIGHT", r.x, "LEFT", -4, 0)
    r.name:SetPoint("RIGHT", r.age, "LEFT", -8, 0)
    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        local e = s.entry
        if not e then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine(ClassColored(e.name, e.class))
        if e.lvl then GameTooltip:AddLine("Level " .. e.lvl .. (e.rank and ("  -  " .. e.rank) or ""), 1, 1, 1) end
        if e.by then GameTooltip:AddLine("Removed by " .. e.by, 1, 0.45, 0.45)
        elseif e.offline then GameTooltip:AddLine("Left while you were offline (noticed " .. AgoText(e.t) .. ")", T.desc[1], T.desc[2], T.desc[3], true)
        else GameTooltip:AddLine("Left the guild " .. AgoText(e.t), T.desc[1], T.desc[2], T.desc[3]) end
        local days = db.leftDays or 3
        GameTooltip:AddLine("Clears from this list after " .. days .. (days == 1 and " day" or " days") .. ".", T.dim[1], T.dim[2], T.dim[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    leftRows[i] = r
    return r
end

local function AgoText(t)
    local a = Ago(t)
    return a == "now" and "just now" or (a .. " ago")
end

local function LeftLine(e)
    local s = ClassColored(e.name, e.class)
    if e.lvl then s = s .. "  |cFF999999" .. e.lvl .. "|r" end
    if e.by then s = s .. "  |cFFFF7373removed by " .. e.by .. "|r"
    elseif e.offline then s = s .. "  |cFF999999left while you were away|r"
    else s = s .. "  |cFF999999left|r" end
    return s
end

local function StatusText()
    if R.running then
        local s = "|cFF33FF66Recruiting|r"
        return s .. "  |cFF999999" .. session.whispered .. " whispered, " .. session.replies .. " replies, " .. session.joined .. " joined|r"
    end
    return "|cFF999999Stopped|r  |cFF999999" .. session.whispered .. " whispered this session|r"
end

local function NextText()
    if not R.running then return lastNote ~= "" and lastNote or "Press Start, then play as usual" end
    local why = Blocked()
    if why then return "Paused: " .. why end
    local now = GetTime()
    if #queue > 0 then
        local wait = nextWhisper - now
        return wait > 0.5 and ("Next: whisper " .. queue[1].name .. " in " .. floor(wait + 0.5) .. "s")
            or ("Next key press or click whispers " .. queue[1].name)
    end
    if inFlight then return "Searching..." end
    local wait = nextWho - now
    if wait > 0.5 then return lastNote .. "  |cFF999999(" .. floor(wait + 0.5) .. "s)|r" end
    return "Next key press or click searches /who"
end

local function BuildWindow()
    local f = CreateFrame("Frame", "CysRecruitFrame", UIParent)
    frame = f
    f:SetSize(WIDTH, HEADER_H + STRIP_H + 30)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if db.pos then f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else f:SetPoint("LEFT", UIParent, "LEFT", 40, 80) end
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
    end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = W.Text(header, 12, T.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Guild Recruiter")
    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide(); R.closed = true end)
    local gear = CreateFrame("Button", nil, header)
    gear:SetSize(54, 22)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear.text = W.Text(gear, 10, T.dim, "RIGHT")
    gear.text:SetPoint("RIGHT")
    gear.text:SetText("Settings")
    gear:SetScript("OnEnter", function(s) s.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    gear:SetScript("OnLeave", function(s) s.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    gear:SetScript("OnClick", function() CUI:OpenConfig("Guild Recruiter") end)

    f.status = W.Text(f, 11, { 1, 1, 1 })
    f.status:SetPoint("TOPLEFT", 10, -(HEADER_H + 7))
    f.next = W.Text(f, 11, T.desc)
    f.next:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -5)
    f.next:SetPoint("RIGHT", f, "RIGHT", -90, 0)
    f.next:SetWordWrap(false)
    f.toggle = W.Button(f, 70, 22, "Start", true)
    f.toggle:SetPoint("TOPRIGHT", -8, -(HEADER_H + 10))
    f.toggle:SetScript("OnClick", function()
        if R.running then R.Stop() else R.Start() end
    end)
    local sline = W.Texture(f, "BORDER", T.line)
    sline:SetPoint("TOPLEFT", 8, -(HEADER_H + STRIP_H - 1)); sline:SetPoint("TOPRIGHT", -8, -(HEADER_H + STRIP_H - 1)); sline:SetHeight(1)
    f.empty = W.Text(f, 11, T.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -(HEADER_H + STRIP_H + 8))
    f.empty:SetText("Players who answer show here.")
    f.more = W.Text(f, 10, T.dim, "CENTER")
    f.others = W.Text(f, 10, T.desc)
    f.others:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.others:SetWordWrap(true)

    -- Left the guild: header line (click folds it) + small rows
    local lh = CreateFrame("Button", nil, f)
    f.leftHead = lh
    lh:SetHeight(LEFT_HEAD)
    lh.line = W.Texture(lh, "BORDER", T.line)
    lh.line:SetPoint("TOPLEFT", 7, 0); lh.line:SetPoint("TOPRIGHT", -7, 0); lh.line:SetHeight(1)
    lh.text = W.Text(lh, 11, T.accent)
    lh.text:SetPoint("LEFT", 10, -1)
    lh.fold = W.Text(lh, 10, T.dim, "RIGHT")
    lh.fold:SetPoint("RIGHT", -10, -1)
    lh:SetScript("OnEnter", function(s) s.fold:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    lh:SetScript("OnLeave", function(s) s.fold:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    lh:SetScript("OnClick", function() db.leftFolded = not db.leftFolded; R.Refresh() end)
    f.leftMore = W.Text(f, 10, T.dim, "CENTER")

    -- Guild levels: header line (click folds it) + one row per level bracket
    local vh = CreateFrame("Button", nil, f)
    f.lvHead = vh
    vh:SetHeight(LEFT_HEAD)
    vh.line = W.Texture(vh, "BORDER", T.line)
    vh.line:SetPoint("TOPLEFT", 7, 0); vh.line:SetPoint("TOPRIGHT", -7, 0); vh.line:SetHeight(1)
    vh.text = W.Text(vh, 11, T.accent)
    vh.text:SetPoint("LEFT", 10, -1)
    vh.fold = W.Text(vh, 10, T.dim, "RIGHT")
    vh.fold:SetPoint("RIGHT", -10, -1)
    vh:SetScript("OnEnter", function(s) s.fold:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    vh:SetScript("OnLeave", function(s) s.fold:SetTextColor(T.dim[1], T.dim[2], T.dim[3]) end)
    vh:SetScript("OnClick", function() db.levelsFolded = not db.levelsFolded; R.Refresh() end)
    vh:Hide()

    local acc = 0
    f:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.5 then return end
        acc = 0
        f.status:SetText(StatusText())
        f.next:SetText(NextText())
    end)
end

function R.Refresh(show)
    if not frame then
        if not show and not R.running then return end
        BuildWindow()
    end
    PruneBox()
    local box = Box()
    if show and not R.closed then frame:Show() end
    if not frame:IsShown() then return end
    frame.toggle:SetLabel(R.running and "Stop" or "Start")
    frame.status:SetText(StatusText())
    frame.next:SetText(NextText())
    -- interested first, then questions; newest first inside each
    local list = {}
    for _, e in ipairs(box) do if e.kind == "yes" then list[#list + 1] = e end end
    for _, e in ipairs(box) do if e.kind ~= "yes" then list[#list + 1] = e end end
    local canInvite = CanGuildInvite and CanGuildInvite()
    local shown = min(#list, MAX_ROWS)
    for i = 1, max(shown, #rows) do
        local e = list[i]
        local r = rows[i] or (e and MakeRow(i))
        if r then
            r.entry = e
            r:SetShown(e ~= nil and i <= shown)
            if e and i <= shown then
                local color = e.kind == "yes" and "|cFFFFD100" or "|cFFFFFFFF"
                local tag = e.declined and "  |cFFFF5555declined|r" or (e.invited and "  |cFF33FF66invited|r" or "")
                r.name:SetText(ClassColored(e.name, e.class) .. (e.kind == "yes" and "  " .. color .. "wants to join|r" or "  " .. color .. "replied|r") .. tag)
                r.say:SetText('"' .. (e.text or "") .. '"')
                r.age:SetText(Ago(e.t))
                r.inv:SetActive(canInvite and true or false)
            end
        end
    end
    frame.empty:SetShown(#list == 0)
    local h = HEADER_H + STRIP_H + (shown > 0 and shown * ROW_H + 6 or 30)
    if #list > shown then
        frame.more:ClearAllPoints()
        frame.more:SetPoint("TOP", 0, -(HEADER_H + STRIP_H + shown * ROW_H + 4))
        frame.more:SetText("+" .. (#list - shown) .. " more (take some off the list)")
        frame.more:Show()
        h = h + 16
    else
        frame.more:Hide()
    end
    h = R.PaintOthers(h)
    h = R.PaintLeft(h)
    h = R.PaintLevels(h)
    frame:SetHeight(h)
end

-- "Also recruiting: Name 10-19, ..." under the replies (guildies running Cys's UI's recruiter right now)
function R.PaintOthers(y)
    local list = Others()
    if #list == 0 then frame.others:Hide(); return y end
    local parts = {}
    for _, o in ipairs(list) do parts[#parts + 1] = "|cFFFFFFFF" .. o.name .. "|r " .. o.lo .. "-" .. o.hi end
    frame.others:ClearAllPoints()
    frame.others:SetPoint("TOPLEFT", 10, -(y + 2))
    frame.others:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.others:SetText("|cFF33FF66Also recruiting:|r  " .. table.concat(parts, ",  "))
    frame.others:Show()
    return y + max(14, frame.others:GetStringHeight()) + 8
end

-- the Left the guild section under the replies; returns the new window height
function R.PaintLeft(y)
    PruneLeft()
    local list = db.leftShow and Left() or {}
    local lh = frame.leftHead
    local shown = 0
    if #list > 0 then
        lh:ClearAllPoints()
        lh:SetPoint("TOPLEFT", 1, -y); lh:SetPoint("TOPRIGHT", -1, -y)
        lh.text:SetText("Left the guild  |cFF999999(" .. #list .. ")|r")
        lh.fold:SetText(db.leftFolded and "Show" or "Hide")
        lh:Show()
        y = y + LEFT_HEAD
        if not db.leftFolded then shown = min(#list, MAX_LEFT) end
    else
        lh:Hide()
    end
    for i = 1, max(shown, #leftRows) do
        local e = i <= shown and list[i] or nil
        local r = leftRows[i] or (e and MakeLeftRow(i))
        if r then
            r.entry = e
            r:SetShown(e ~= nil)
            if e then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 1, -(y + (i - 1) * LEFT_ROW))
                r:SetPoint("TOPRIGHT", -1, -(y + (i - 1) * LEFT_ROW))
                r.name:SetText(LeftLine(e))
                r.age:SetText(Ago(e.t))
            end
        end
    end
    y = y + shown * LEFT_ROW
    if shown > 0 and #list > shown then
        frame.leftMore:ClearAllPoints()
        frame.leftMore:SetPoint("TOP", 0, -(y + 2))
        frame.leftMore:SetText("+" .. (#list - shown) .. " more")
        frame.leftMore:Show()
        y = y + 16
    else
        frame.leftMore:Hide()
    end
    if #list > 0 then y = y + 4 end
    return y
end

local function MakeLevelRow(i)
    local r = CreateFrame("Button", nil, frame)
    r:SetHeight(LV_ROW)
    r.hl = W.Texture(r, "BACKGROUND", T.hover); r.hl:SetAllPoints(); r.hl:Hide()
    r.label = W.Text(r, 10, T.desc, "RIGHT")
    r.label:SetPoint("LEFT", 10, 0)
    r.label:SetWidth(38)
    r.track = W.Texture(r, "BORDER", T.line)
    r.track:SetPoint("LEFT", 56, 0)
    r.track:SetSize(LV_BAR, 7)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("LEFT", r.track, "LEFT")
    r.bar:SetHeight(7)
    r.num = W.Text(r, 10, { 1, 1, 1 })
    r.num:SetPoint("LEFT", r.track, "RIGHT", 8, 0)
    r.tag = W.Text(r, 10, T.accent)
    r.tag:SetPoint("LEFT", r.num, "RIGHT", 6, 0)
    r:SetScript("OnEnter", function(s)
        s.hl:Show()
        local b = s.entry
        if not b then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("Levels " .. (b.lo == b.hi and b.lo or (b.lo .. "-" .. b.hi)) .. ":  " .. b.n .. (b.n == 1 and " member" or " members")
            .. (b.pct and ("  (" .. b.pct .. "%)") or ""), 1, 0.82, 0)
        table.sort(b.list, function(x, y)
            if (x.l or 0) ~= (y.l or 0) then return (x.l or 0) > (y.l or 0) end
            return (x.n or "") < (y.n or "")
        end)
        for k = 1, min(#b.list, 15) do
            local e = b.list[k]
            GameTooltip:AddDoubleLine(ClassColored(e.n or "?", e.c), tostring(e.l or ""), 1, 1, 1, 0.7, 0.7, 0.7)
        end
        if #b.list > 15 then GameTooltip:AddLine("+" .. (#b.list - 15) .. " more", 0.6, 0.6, 0.6) end
        local who = {}
        for _, o in ipairs(Others()) do
            if o.lo <= b.hi and o.hi >= b.lo then who[#who + 1] = o.name .. " (" .. o.lo .. "-" .. o.hi .. ")" end
        end
        if #who > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Also recruiting these levels: " .. table.concat(who, ", "), 0.2, 1, 0.4, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to recruit levels " .. b.lo .. "-" .. b.hi .. ".", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(s) if s.entry then R.RecruitBracket(s.entry.lo, s.entry.hi) end end)
    lvRows[i] = r
    return r
end

-- the Guild levels section at the bottom; returns the new window height
function R.PaintLevels(y)
    local lh = frame.lvHead
    local list, total = R.Levels()
    local show = db.levelsShow and total > 0
    lh:SetShown(show)
    local n = 0
    if show then
        lh:ClearAllPoints()
        lh:SetPoint("TOPLEFT", 1, -y); lh:SetPoint("TOPRIGHT", -1, -y)
        local days = db.levelsDays or 14
        lh.text:SetText("Guild levels  |cFF999999(" .. total .. " seen in " .. days .. (days == 1 and " day" or " days") .. ")|r")
        lh.fold:SetText(db.levelsFolded and "Show" or "Hide")
        y = y + LEFT_HEAD
        if not db.levelsFolded then n = #list end
    end
    local top = 0
    for _, b in ipairs(list) do top = max(top, b.n) end
    -- who else is recruiting exactly a bracket's levels shows next to it
    local exact = {}
    for _, o in ipairs(Others()) do
        local k = o.lo .. "-" .. o.hi
        exact[k] = exact[k] and (exact[k] .. ", " .. o.name) or o.name
    end
    for i = 1, max(n, #lvRows) do
        local b = i <= n and list[i] or nil
        local r = lvRows[i] or (b and MakeLevelRow(i))
        if r then
            r.entry = b
            r:SetShown(b ~= nil)
            if b then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 1, -(y + (i - 1) * LV_ROW))
                r:SetPoint("TOPRIGHT", -1, -(y + (i - 1) * LV_ROW))
                r.label:SetText(b.lo == b.hi and tostring(b.lo) or (b.lo .. "-" .. b.hi))
                local w = top > 0 and floor(LV_BAR * b.n / top + 0.5) or 0
                r.bar:SetWidth(max(w, 1))
                r.bar:SetShown(b.n > 0)
                if b.few then r.bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.95)
                else r.bar:SetColorTexture(0.55, 0.55, 0.55, 0.8) end
                b.pct = total > 0 and floor(100 * b.n / total + 0.5) or 0
                r.num:SetText(b.n .. "  |cFF999999" .. b.pct .. "%|r")
                local here = db.lo == b.lo and db.hi == b.hi
                local them = exact[b.lo .. "-" .. b.hi]
                local tag = here and "|cFF33FF66recruiting|r" or (b.few and "few" or "")
                if them then tag = (tag ~= "" and (tag .. "  ") or "") .. "|cFF33FF66" .. them .. "|r" end
                r.tag:SetText(tag)
            end
        end
    end
    y = y + n * LV_ROW
    if show then y = y + 6 end
    return y
end

function R.Toggle()
    if frame and frame:IsShown() then frame:Hide(); R.closed = true
    else R.closed = false; R.Refresh(true); if not frame then BuildWindow(); R.Refresh(true) end end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
ev:RegisterEvent("WHO_LIST_UPDATE")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
    if e == "WHO_LIST_UPDATE" then
        OnWho()
    elseif e == "CHAT_MSG_WHISPER" then
        pcall(OnWhisper, a1, a2)
    elseif e == "CHAT_MSG_SYSTEM" then
        pcall(OnSystem, a1)
    elseif e == "CHAT_MSG_ADDON" then
        if a1 == PREFIX and type(a2) == "string" and not Secret(a2) then
            local k = a2:match("^W:(.+)$")
            if k then welcomeTimers[k] = nil end -- someone else is welcoming them
            local who = type(a4) == "string" and not Secret(a4) and Short(a4) or nil
            if who and who ~= "" and Key(who) ~= Key(UnitName("player")) then
                local lo, hi = a2:match("^R:(%d+):(%d+)$")
                if lo then
                    others[who] = { lo = tonumber(lo), hi = tonumber(hi), t = GetTime() }
                    if R.Refresh then R.Refresh() end
                elseif a2 == "X" then
                    others[who] = nil
                    if R.Refresh then R.Refresh() end
                elseif a2 == "Q" and R.running then
                    C_Timer.After(math.random() * 3, Announce)
                end
            end
        end
    elseif e == "GUILD_ROSTER_UPDATE" then
        RosterSoon()
    elseif e == "PLAYER_ENTERING_WORLD" then
        if a1 or a2 then -- login or /reload: ask the server for the roster once we are settled
            C_Timer.After(8, function()
                if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
                RosterSoon()
                Send("Q") -- who else is recruiting right now?
            end)
        end
    elseif e == "PLAYER_GUILD_UPDATE" then
        if R.running and not IsInGuild() then R.Stop("You left your guild") end
    elseif e == "ADDON_ACTION_FORBIDDEN" or e == "ADDON_ACTION_BLOCKED" then
        if a1 == "CysUI" and type(a2) == "string" and a2:find("SendWho") then lastNote = "The game refused the search" end
    end
end)

SLASH_CYSRECRUIT1 = "/cuirecruit"
SlashCmdList.CYSRECRUIT = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "start" then R.Start()
    elseif msg == "stop" then R.Stop()
    elseif msg == "next" then R.Step()
    elseif msg == "reset" then wipe(Contacted()); Print("Guild Recruiter: whisper history cleared for this realm.")
    elseif msg == "left" then
        PruneLeft()
        local list = Left()
        if #list == 0 then Print("Guild Recruiter: nobody left the guild in the last " .. db.leftDays .. " days.") end
        for _, e in ipairs(list) do Print(LeftLine(e) .. "  |cFF999999" .. AgoText(e.t) .. "|r") end
    elseif msg == "levels" then
        local list, total = R.Levels()
        if total == 0 then Print("Guild Recruiter: no guild roster read yet (open the guild window once).") return end
        Print("Guild Recruiter: members per level (seen in the last " .. db.levelsDays .. " days, alts included):")
        for _, b in ipairs(list) do
            Print("  " .. (b.lo == b.hi and b.lo or (b.lo .. "-" .. b.hi)) .. ": " .. b.n .. "  |cFF999999(" .. floor(100 * b.n / total + 0.5) .. "%)|r"
                .. (b.few and "  |cFFFFD100few|r" or ""))
        end
    else R.Toggle() end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local function MessageBox(page, width, height, get, set)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(width, height)
    W.Texture(holder, "BACKGROUND", T.field):SetAllPoints()
    W.Border(holder, 1, T.border, "BORDER")
    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(255)
    eb:SetFontObject(ChatFontNormal)
    eb:SetPoint("TOPLEFT", 6, -5)
    eb:SetPoint("BOTTOMRIGHT", -6, 5)
    eb:SetWidth(width - 12)
    eb:SetText(get() or "")
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(s, user) if user then set(((s:GetText() or ""):gsub("[\r\n]+", " "))) end end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
    holder.eb = eb
    return holder
end

CUI:RegisterPage("Guild Recruiter", function(page)
    local width = 480
    local y = -4
    W.Header(page, "Guild Recruiter", width):SetPoint("TOPLEFT", 0, y)
    local open = W.Button(page, 130, 22, "Open the window", true)
    open:SetPoint("TOPLEFT", 4, y - 30)
    open:SetScript("OnClick", function() R.closed = false; if not frame then BuildWindow() end; frame:Show(); R.Refresh(true) end)
    local reset = W.Button(page, 170, 22, "Clear whisper history")
    reset:SetPoint("LEFT", open, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function() wipe(Contacted()); Print("Guild Recruiter: whisper history cleared for this realm.") end)

    y = y - 66
    W.Header(page, "Who to find", width):SetPoint("TOPLEFT", 0, y)
    W.Stepper(page, "Lowest level", function() return db.lo end, function(v) db.lo = v; BuildSearches() end, 1, MaxLevel(), 1)
        :SetPoint("TOPLEFT", 4, y - 28)
    W.Stepper(page, "Highest level", function() return db.hi end, function(v) db.hi = v; BuildSearches() end, 1, MaxLevel(), 1)
        :SetPoint("TOPLEFT", 4, y - 54)
    W.Stepper(page, "Don't whisper the same player again for", function() return db.days end, function(v) db.days = v end, 1, 30, 1, " days")
        :SetPoint("TOPLEFT", 4, y - 80)

    y = y - 116
    W.Header(page, "Your whisper", width):SetPoint("TOPLEFT", 0, y)
    local msgBox = MessageBox(page, width - 8, 58, function() return db.msg end, function(v) db.msg = v end)
    msgBox:SetPoint("TOPLEFT", 4, y - 26)
    local hint = W.Text(page, 11, T.desc)
    hint:SetPoint("TOPLEFT", 4, y - 90)
    hint:SetWidth(width)
    hint:SetJustifyH("LEFT")
    hint:SetText("{first} = their first name, {name} = their whole name, {guild} = your guild.")
    local def = W.Button(page, 110, 20, "Default text")
    def:SetPoint("TOPRIGHT", page, "TOPLEFT", width - 4, y - 2)
    def:SetScript("OnClick", function() db.msg = DEFAULT_MSG; msgBox.eb:SetText(DEFAULT_MSG) end)
    W.Stepper(page, "Seconds between whispers", function() return db.gap end, function(v) db.gap = v end, 5, 60, 1, " s")
        :SetPoint("TOPLEFT", 4, y - 112)
    W.Stepper(page, "Stop after this many whispers", function() return db.cap end, function(v) db.cap = v end, 10, 200, 10)
        :SetPoint("TOPLEFT", 4, y - 138)
    local hide = W.Checkbox(page, "Hide my recruiting whispers in chat", function() return db.hideSent end, function(v) db.hideSent = v end)
    hide:SetPoint("TOPLEFT", 4, y - 166)
    local note = W.Checkbox(page, "Tell me in chat when a player wants to join", function() return db.chatNote end, function(v) db.chatNote = v end)
    note:SetPoint("TOPLEFT", 4, y - 190)

    y = y - 224
    W.Header(page, "New members", width):SetPoint("TOPLEFT", 0, y)
    local wel = W.Checkbox(page, "Welcome new members in guild chat", function() return db.welcome end, function(v) db.welcome = v end)
    wel:SetPoint("TOPLEFT", 4, y - 26)
    MessageBox(page, width - 8, 40, function() return db.welcomeMsg end, function(v) db.welcomeMsg = v end):SetPoint("TOPLEFT", 4, y - 52)

    y = y - 104
    W.Header(page, "Left the guild", width):SetPoint("TOPLEFT", 0, y)
    W.Checkbox(page, "Show players who left the guild in the window", function() return db.leftShow end,
        function(v) db.leftShow = v; if R.Refresh then R.Refresh() end end):SetPoint("TOPLEFT", 4, y - 26)
    W.Stepper(page, "Keep them on the list for", function() return db.leftDays end,
        function(v) db.leftDays = v; if R.Refresh then R.Refresh() end end, 1, 30, 1, " days"):SetPoint("TOPLEFT", 4, y - 52)
    local clearLeft = W.Button(page, 110, 20, "Clear the list")
    clearLeft:SetPoint("TOPLEFT", 4, y - 80)
    clearLeft:SetScript("OnClick", function() wipe(Left()); if R.Refresh then R.Refresh() end end)

    y = y - 112
    W.Header(page, "Guild levels", width):SetPoint("TOPLEFT", 0, y)
    W.Checkbox(page, "Show members per level bracket in the window", function() return db.levelsShow end,
        function(v) db.levelsShow = v; if R.Refresh then R.Refresh() end end):SetPoint("TOPLEFT", 4, y - 26)
    W.Stepper(page, "Count members seen in the last", function() return db.levelsDays end,
        function(v) db.levelsDays = v; if R.Refresh then R.Refresh() end end, 1, 90, 1, " days"):SetPoint("TOPLEFT", 4, y - 52)

    W.Notes(page, 4, y - 86, width, "", {
        { "How it runs", "Press Start, then play as usual. The game only allows /who from a real key press or click, so each key press or click on the game world takes one step: a /who search or one whisper. Your keys still work as normal. It pauses in combat, battlegrounds and arenas." },
        { "Who is whispered", "Players without a guild in your level range, never the same player twice within the days above. Ranges with more than 50 players are searched again one class at a time." },
        { "Invites", "The game only lets you invite yourself, never an addon. Players who answer show in the window; Invite shows /ginvite and their name in a small box: Ctrl+C, then Enter, Ctrl+V, Enter (your guild rank must be allowed to invite)." },
        { "Left the guild", "Players who leave or are removed show under the replies in the window, with who removed them. Players who left while you were offline show after your next login. Each name clears by itself after the days above; x takes it off sooner." },
        { "Welcome", "Sent on your next key press or click after someone joins. When several guildies run Cys's UI, only one of them welcomes each new member." },
        { "Guild levels", "Members per level bracket, from the guild roster (alts count too; members not seen within the days above are left out). Each bracket shows its share of the guild in %. Thin brackets are gold and marked few. Click a bracket to recruit those levels; hover it to see who is in it." },
        { "Also recruiting", "Guildies running Cys's UI's recruiter right now show under the replies with their levels (and next to a bracket when they recruit exactly those levels), so you can pick other levels." },
        "/cuirecruit opens the window; /cuirecruit start, stop, next, left or levels. A key press with the chat box open doesn't count.",
    })
end, function() end)

    end,
})
