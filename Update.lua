--------------------------------------------------------------------------------
-- Cys's UI - "a newer version is out" notice
--
-- An addon cannot look at the internet, so players tell each other: everyone's Cys's UI
-- shares its version number in guild / party / raid chat (a hidden addon message). If you
-- hear a higher number than yours, you get one line in chat with the download address.
-- Switch it off in /cui -> General.
--------------------------------------------------------------------------------
local CUI = CysUI
if not CUI then return end

local PREFIX = "CYSUI"
local URL = "https://github.com/Cyserin/CysUI/releases"
local REPLY_COOLDOWN = 300 -- seconds between answers to somebody who is behind

local Register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local Send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if not (Register and Send) then return end
pcall(Register, PREFIX)

local function Parse(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

-- 1 if x is newer than y, -1 if older, 0 if the same, nil if either is not a version number
local function Compare(x, y)
    local x1, x2, x3 = Parse(x)
    local y1, y2, y3 = Parse(y)
    if not (x1 and y1) then return nil end
    if x1 ~= y1 then return x1 > y1 and 1 or -1 end
    if x2 ~= y2 then return x2 > y2 and 1 or -1 end
    if x3 ~= y3 then return x3 > y3 and 1 or -1 end
    return 0
end

local function Enabled()
    local db = CysUIDB
    return not (db and db.update and db.update.enabled == false)
end

local mine
local function MyVersion()
    if not mine then mine = CUI:GetVersion("CysUI") end
    return mine
end

local lastReply = 0

local function Broadcast()
    if not Enabled() then return end
    local v = MyVersion()
    if not Parse(v) then return end
    local msg = "V:" .. v
    if IsInGuild and IsInGuild() then pcall(Send, PREFIX, msg, "GUILD") end
    if IsInRaid and IsInRaid() then
        pcall(Send, PREFIX, msg, "RAID")
    elseif IsInGroup and IsInGroup() then
        pcall(Send, PREFIX, msg, "PARTY")
    end
end

local pending
local function BroadcastSoon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 5, function() pending = false; Broadcast() end)
end

local function Heard(version, channel)
    local cmp = Compare(version, MyVersion())
    if cmp == 1 then
        CUI.newerVersion = version
        local db = CysUIDB
        db.update = db.update or {}
        if Compare(version, db.update.notified or "0.0.0") == 1 then
            db.update.notified = version
            CUI:Print(format("Version |cFFFFD100%s|r is out (you have %s). Download: |cFF6CB6FF%s|r", version, MyVersion(), URL))
        end
    elseif cmp == -1 and (channel == "GUILD" or channel == "PARTY" or channel == "RAID") then
        -- they are behind us: tell them (at most once in a while), so they hear about it too
        local now = GetTime()
        if now - lastReply > REPLY_COOLDOWN then
            lastReply = now
            Broadcast()
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or not Enabled() then return end
        if sender and Ambiguate and Ambiguate(sender, "none") == UnitName("player") then return end
        local v = tostring(message or ""):match("^V:(%d+%.%d+%.%d+)$")
        if v then Heard(v, channel) end
    elseif event == "PLAYER_LOGIN" then
        BroadcastSoon(8)
    else
        BroadcastSoon(5)
    end
end)
