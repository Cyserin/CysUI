--------------------------------------------------------------------------------
-- Cys's UI - Cys's UI Users
--
-- Says a quiet hello to other players running Cys's UI and marks them: a "Cys's UI <version>" line on their
-- tooltip, and (switch, default off) a chat note the first time one joins your group.
--
-- How: addon messages on the "CysUI" prefix, which other players never see in chat.
--   "H:<version>"  hello, sent to your group when it grows, and to your guild at login
--   "R:<version>"  the answer, whispered back once to whoever said hello
-- Nothing but "uses Cys's UI + its version" is ever sent. Sent only out of combat.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T
local Compat = CysUICompat

local Hello = {}
CUI.Hello = Hello

local PREFIX = "CysUI"
local KEEP_DAYS = 30
local CYS_MARK = "|TInterface\\Icons\\INV_Misc_GroupNeedMore:12:12:0:0:64:64:5:59:5:59|t"

local function DB()
    CysUIDB.hello = CysUIDB.hello or {}
    local db = CysUIDB.hello
    if db.tooltip == nil then db.tooltip = true end
    if db.chatNote == nil then db.chatNote = false end
    if db.guild == nil then db.guild = true end
    db.seen = db.seen or {} -- [Name-Realm] = { v = version, t = last seen }
    return db
end

local function Now() return (GetServerTime and GetServerTime()) or time() end

local function MyVersion()
    local v = CUI.GetVersion and CUI:GetVersion("CysUI")
    return (v and v ~= "?") and v or "?"
end

local function NormRealm(realm) return ((realm or ""):gsub("[%s%-']", "")) end

local function MyRealm()
    return NormRealm((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "")
end

-- "Name-Realm" from an addon message sender (the realm can be missing for your own realm)
local function KeyFromSender(sender)
    local name, realm = (sender or ""):match("^([^%-]+)%-?(.*)$")
    if not name or name == "" then return nil end
    if realm == "" then realm = MyRealm() end
    return name .. "-" .. NormRealm(realm)
end

local function KeyFromUnit(unit)
    local name, realm = UnitName(unit)
    if not name or Compat.Secret(name) or (realm and Compat.Secret(realm)) then return nil end
    if not realm or realm == "" then realm = MyRealm() end
    return name .. "-" .. NormRealm(realm)
end

local myKey

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------
local function Send(msg, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if InCombatLockdown() then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
end

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local pendingGroup, pendingGuild = false, false
local lastGroupHello, lastGroupSize = 0, 0

local function Flush()
    if InCombatLockdown() then return end -- tried again when the fight ends
    local hello = "H:" .. MyVersion()
    if pendingGroup then
        pendingGroup = false
        local ch = GroupChannel()
        if ch then Send(hello, ch); lastGroupHello = GetTime() end
    end
    if pendingGuild then
        pendingGuild = false
        if IsInGuild() and DB().guild then Send(hello, "GUILD") end
    end
end

local function GroupGrew()
    local size = GetNumGroupMembers() or 0
    local grew = size > lastGroupSize
    lastGroupSize = size
    if size <= 1 or not grew then return end
    pendingGroup = true
    -- one hello per 10 s however fast people join
    local wait = max(1, 10 - (GetTime() - lastGroupHello))
    C_Timer.After(wait, Flush)
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------
local answered = {} -- [key] = GetTime() of our last answer (this session)
local noted = {}    -- chat note shown this session

local function Seen(key, version, sender)
    if not key or key == myKey then return end
    local db = DB()
    local first = not db.seen[key]
    db.seen[key] = { v = version, t = Now() }
    if db.chatNote and not noted[key] and (first or UnitInParty(Ambiguate(sender, "none")) or
        UnitInRaid(Ambiguate(sender, "none"))) then
        noted[key] = true
        print(format("|cFFE6C068Cys's UI|r: %s %s uses Cys's UI too (%s).", CYS_MARK,
            Ambiguate(sender, "short"), version))
    end
end

local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    local kind, version = msg:match("^([HR]):([%w%.%-]+)$")
    if not kind then return end
    local key = KeyFromSender(sender)
    if not key or key == myKey then return end
    Seen(key, version, sender)
    if kind == "H" then
        local last = answered[key]
        if not last or GetTime() - last > 300 then
            answered[key] = GetTime()
            Send("R:" .. MyVersion(), "WHISPER", sender)
        end
    end
end

--------------------------------------------------------------------------------
-- Tooltip mark
--------------------------------------------------------------------------------
local function OnUnit(tip)
    if tip ~= GameTooltip or not DB().tooltip then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or Compat.Secret(unit) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or Compat.Secret(isPlayer) or not isPlayer then return end
    local key = KeyFromUnit(unit)
    local e = key and (key == myKey and { v = MyVersion() } or DB().seen[key])
    if not e then return end
    tip:AddLine(format("%s Cys's UI %s", CYS_MARK, e.v or ""), T.accent[1], T.accent[2], T.accent[3])
    tip:Show()
end

-- for other windows (Cys's Friends guild list): the Cys's UI line for a "Name" or "Name-Realm"
function Hello.Version(fullName)
    local key = KeyFromSender(fullName)
    if not key then return nil end
    if key == myKey then return MyVersion() end
    local e = DB().seen[key]
    return e and e.v
end

function Hello.AddLine(tip, fullName)
    if not DB().tooltip then return end
    local v = Hello.Version(fullName)
    if v then tip:AddLine(format("%s Cys's UI %s", CYS_MARK, v), T.accent[1], T.accent[2], T.accent[3]) end
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
function Hello.Enable()
    local db = DB()
    local cutoff = Now() - KEEP_DAYS * 86400
    for k, e in pairs(db.seen) do if (e.t or 0) < cutoff then db.seen[k] = nil end end

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    local greeted = false
    f:SetScript("OnEvent", function(_, ev, ...)
        if ev == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif ev == "PLAYER_ENTERING_WORLD" then
            myKey = KeyFromUnit("player")
            if not greeted then
                greeted = true
                lastGroupSize = 0
                pendingGuild = true
                C_Timer.After(10, function() GroupGrew(); Flush() end)
            end
        elseif ev == "GROUP_ROSTER_UPDATE" then
            if greeted then GroupGrew() end
            if not IsInGroup() then lastGroupSize = 0 end
        elseif ev == "PLAYER_REGEN_ENABLED" then
            if pendingGroup or pendingGuild then Flush() end
        end
    end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, OnUnit)
    else
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", OnUnit)
    end
end

SLASH_CYSHELLO1 = "/cuiusers"
SlashCmdList.CYSHELLO = function()
    local list = {}
    for k, e in pairs(DB().seen) do list[#list + 1] = { k = k, e = e } end
    table.sort(list, function(a, b) return (a.e.t or 0) > (b.e.t or 0) end)
    print(format("|cFFE6C068Cys's UI|r: %d other player%s seen with Cys's UI (last %d days):", #list,
        #list == 1 and "" or "s", KEEP_DAYS))
    for i = 1, min(#list, 30) do
        local ago = Now() - (list[i].e.t or Now())
        print(format("  %s  %s  |cFF999999%s|r", list[i].k, list[i].e.v or "?",
            ago >= 86400 and format("%dd ago", floor(ago / 86400)) or format("%dh ago", floor(ago / 3600))))
    end
end

CUI:RegisterModule({
    key = "hello",
    name = "Cys's UI Users",
    addon = "CysUI",
    desc = "Spots other players running Cys's UI and marks them on their tooltip. Only the version is shared.",
    onEnable = Hello.Enable,
    open = function() CUI:OpenConfig("Cys's UI Users") end,
})

CUI:RegisterPage("Cys's UI Users", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Cys's UI Users", width):SetPoint("TOPLEFT", 0, -4)
    local tt = W.Checkbox(page, "Mark Cys's UI users on their tooltip", function() return db.tooltip end,
        function(on) db.tooltip = on end)
    tt:SetPoint("TOPLEFT", 4, -34)
    local gu = W.Checkbox(page, "Say hello to your guild when you log in", function() return db.guild end,
        function(on) db.guild = on end)
    gu:SetPoint("TOPLEFT", 4, -60)
    local cn = W.Checkbox(page, "Chat note when a Cys's UI user joins your group", function() return db.chatNote end,
        function(on) db.chatNote = on end)
    cn:SetPoint("TOPLEFT", 4, -86)
    local forget = W.Button(page, 150, 22, "Forget everyone seen")
    forget:SetPoint("TOPLEFT", 4, -122)
    forget:SetScript("OnClick", function() wipe(db.seen) end)
    W.Notes(page, 4, -160, width, "", {
        "Cys's UI quietly says hello to your group when it grows and to your guild when you log in. Other players running it answer, and their tooltip gets a line: Cys's UI and their version.",
        "These are hidden addon messages: nobody sees them in chat, and nothing but the version of Cys's UI is shared. Nothing is sent during a fight.",
        "Players are remembered for 30 days. /cuiusers lists who has been seen.",
    })
end)
