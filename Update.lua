--------------------------------------------------------------------------------
-- Cys's UI - "a newer version is out" notice
--
-- An addon cannot look at the internet, so players tell each other: everyone's Cys's UI
-- shares its version number in guild / party / raid chat (a hidden addon message). If you
-- hear a higher number than yours, you get a pop-up (once per new version, never in a fight)
-- and one line in chat with the download address. Switch it off in /cui -> General.
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

-- The pop-up: which version is out, how to update, the link to copy. Once per new version.
local popup, waitingFor
local function ShowPopup(version)
    if InCombatLockdown() then waitingFor = version; return end
    waitingFor = nil
    local W = CUI.W
    if not W then return end
    local T = W.T
    if not popup then
        popup = CreateFrame("Frame", "CysUIUpdatePopup", UIParent)
        popup:SetSize(400, 176)
        popup:SetPoint("TOP", UIParent, "TOP", 0, -150)
        popup:SetFrameStrata("DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        W.Texture(popup, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.97 }):SetAllPoints()
        W.Border(popup, 1, T.border)
        local icon = popup:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT", 14, -14)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Gift_02")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local title = W.Text(popup, 14, T.accent)
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
        title:SetText("Cys's UI update available")
        popup.sub = W.Text(popup, 11, T.text)
        popup.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        popup.body = W.Text(popup, 11, T.text)
        popup.body:SetPoint("TOPLEFT", 14, -60)
        popup.body:SetWidth(372)
        popup.body:SetText("Update with the CurseForge app or the Wago app, or download it from this link (click it, then Ctrl+C to copy):")
        local eb = CreateFrame("EditBox", nil, popup)
        eb:SetSize(372, 22)
        eb:SetPoint("TOPLEFT", popup.body, "BOTTOMLEFT", 0, -8)
        eb:SetAutoFocus(false)
        eb:SetFont(STANDARD_TEXT_FONT, 11, "")
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetTextColor(0.42, 0.71, 1)
        W.Texture(eb, "BACKGROUND", T.field or { 0, 0, 0, 0.6 }):SetAllPoints()
        W.Border(eb, 1, T.line)
        eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
        eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(URL); s:HighlightText() end end)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        popup.link = eb
        local ok = W.Button(popup, 90, 24, "OK", true)
        ok:SetPoint("BOTTOMRIGHT", -14, 12)
        ok:SetScript("OnClick", function() popup:Hide() end)
        local note = W.Text(popup, 10, T.dim)
        note:SetPoint("BOTTOMLEFT", 14, 18)
        note:SetText("Reload or relog after updating.")
        tinsert(UISpecialFrames, "CysUIUpdatePopup") -- Esc closes it
    end
    popup.sub:SetText(format("Version |cFFFFD100%s|r is out - you have %s.", version, MyVersion() or "?"))
    popup.link:SetText(URL)
    popup:Show()
end

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
            pcall(ShowPopup, version)
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

-- Cys's UI Users hellos carry the version too
function CUI.UpdateHeard(version)
    if Enabled() and type(version) == "string" and version:match("^%d+%.%d+%.%d+$") then Heard(version, "HELLO") end
end
function CUI.UpdatePopupTest() ShowPopup(MyVersion() or "?") end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or not Enabled() then return end
        if sender and Ambiguate and Ambiguate(sender, "none") == UnitName("player") then return end
        local v = tostring(message or ""):match("^V:(%d+%.%d+%.%d+)$")
        if v then Heard(v, channel) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if waitingFor then pcall(ShowPopup, waitingFor) end
    elseif event == "PLAYER_LOGIN" then
        BroadcastSoon(8)
    else
        BroadcastSoon(5)
    end
end)
