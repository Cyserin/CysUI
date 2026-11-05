--------------------------------------------------------------------------------
-- Cys's UI - Kill Tracker
--
-- A small bar that learns how much XP your kills give and tells you how many more
-- kills it takes to level. Counts reset when you log in (and, if you like, on level up).
--
-- Everything here is optional: the whole module can be switched off under /cui > Modules,
-- and the bar itself can be hidden under /cui > Kill Tracker without a reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local KT = {}
CUI.KillTracker = KT

local floor, ceil, max = math.floor, math.ceil, math.max

local FORMATS = {
    { name = "Kills to level + average XP", text = function(kills, avg) return format("Kills to level: %d  (~%d XP each)", kills, avg) end },
    { name = "Kills to level only",         text = function(kills) return format("Kills to level: %d", kills) end },
    { name = "Average XP per kill only",    text = function(_, avg) return format("~%d XP per kill", avg) end },
}

local function DB()
    CysUIDB.killtracker = CysUIDB.killtracker or {}
    local db = CysUIDB.killtracker
    if db.show == nil then
        -- carry over the old switch from before this had its own page; off for anyone new
        local old = CysUIDB.unitframes and CysUIDB.unitframes.killTracker
        db.show = old and true or false
    end
    if db.format == nil then db.format = 1 end
    if db.resetOnLevel == nil then db.resetOnLevel = true end
    if db.hideAtMax == nil then db.hideAtMax = true end
    return db
end

local frame, text
local totalXP, kills = 0, 0
local LEVEL_CAP = 60

-- Classic Era kill XP for your current target (solo, before group split): the base value for a
-- same-level mob, more for higher mobs, less for lower ones, nothing for grey mobs, doubled for
-- elites and by rested XP. Returns nil when there is no attackable mob targeted.
local function ZeroDiff(lvl)
    if lvl < 8 then return 5 elseif lvl < 10 then return 6 elseif lvl < 12 then return 7
    elseif lvl < 16 then return 8 elseif lvl < 20 then return 9 elseif lvl < 30 then return 11
    elseif lvl < 40 then return 12 elseif lvl < 45 then return 13 elseif lvl < 50 then return 14
    elseif lvl < 55 then return 15 else return 16 end
end
local function GreyLevel(lvl)
    if lvl <= 5 then return 0 elseif lvl < 40 then return lvl - floor(lvl / 10) - 5 end
    return lvl - floor(lvl / 5) - 1
end
local function TargetXP()
    if IsInGroup and IsInGroup() then return nil end -- group XP is split; the average covers that case
    if not UnitExists("target") or UnitIsPlayer("target") or not UnitCanAttack("player", "target")
        or UnitIsDead("target") or (UnitIsTapDenied and UnitIsTapDenied("target")) then return nil end
    local me, mob = UnitLevel("player") or 1, UnitLevel("target") or 0
    if mob <= 0 then return nil end -- ?? level: unknown
    if mob <= GreyLevel(me) then return 0 end
    local base = me * 5 + 45
    local xp
    if mob >= me then
        xp = base * (1 + 0.05 * math.min(mob - me, 4))
    else
        xp = base * (1 - (me - mob) / ZeroDiff(me))
    end
    local c = UnitClassification and UnitClassification("target")
    if c == "elite" or c == "rareelite" or c == "worldboss" then xp = xp * 2 end
    xp = floor(xp)
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    return xp + math.min(rested, xp)
end

local function Refresh()
    if not frame then return end
    local db = DB()
    local atMax = db.hideAtMax and (UnitLevel("player") or 0) >= LEVEL_CAP
    if not db.show or atMax then
        frame:Hide()
        return
    end
    frame:Show()

    local line
    if kills == 0 or totalXP == 0 then
        line = "Kill a mob to track XP average"
    else
        local avg = totalXP / kills
        local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
        local needed = max(0, ceil(remaining / avg))
        local fmt = FORMATS[db.format] or FORMATS[1]
        line = fmt.text(needed, floor(avg))
    end
    -- the next kill finishes the level: from your target if one is selected, else from the average
    local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local okT, tx = pcall(TargetXP) -- a target's level can be locked on WoW Forever
    if not okT then tx = nil end
    if remaining > 0 and tx and tx >= remaining then
        line = "|cFF4FD66BKilling this target levels you!|r"
    elseif remaining > 0 and not tx and kills > 0 and totalXP / kills >= remaining then
        line = "|cFF4FD66BYour next kill should level you!|r"
    end
    text:SetText(line)
end

function KT:Reset()
    totalXP, kills = 0, 0
    Refresh()
end

function KT:Refresh() Refresh() end

-- WoW Forever can lock the XP message in combat (it names the mob). Then the kill's XP is read from your own XP
-- bar instead: the gain that arrives within a second of the locked message counts as the kill.
local IsSecret = (CysUICompat and CysUICompat.Secret) or function() return false end
local lastXP, lastMax = nil, nil
local pendingKillAt, lastGain, lastGainAt = nil, 0, 0
local function CountKill(xp)
    if not xp or xp <= 0 then return end
    totalXP = totalXP + xp
    kills = kills + 1
end
local function OnEvent(_, event, msg)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if IsSecret(msg) then
            local now = GetTime()
            if lastGain > 0 and now - lastGainAt < 1 then
                CountKill(lastGain); lastGain = 0 -- the XP bar moved first
            else
                pendingKillAt = now -- wait for the XP bar to move
            end
            Refresh()
            return
        end
        -- "<mob> dies, you gain 123 experience."  (quest rewards say "You gain 123 experience." and aren't kills)
        local xp = msg and msg:match("dies, you gain (%d+) experience")
        if xp then
            CountKill(tonumber(xp))
            lastGain = 0
            Refresh()
        end
    elseif event == "PLAYER_XP_UPDATE" then
        local cur, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
        if lastXP then
            local gain = cur - lastXP
            if gain < 0 and lastMax then gain = cur + (lastMax - lastXP) end -- went over a level
            if gain > 0 then
                if pendingKillAt and GetTime() - pendingKillAt < 1 then
                    CountKill(gain); pendingKillAt = nil
                else
                    lastGain, lastGainAt = gain, GetTime()
                end
            end
        end
        lastXP, lastMax = cur, mx
        Refresh()
    elseif event == "PLAYER_TARGET_CHANGED" then
        Refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        if DB().resetOnLevel then totalXP, kills = 0, 0 end
        Refresh()
    end
end

function KT.Enable()
    DB()
    frame = CreateFrame("Frame", "CysUIKillTrackerFrame", UIParent)
    frame:SetSize(250, 22)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    W.Texture(frame, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
    W.Border(frame, 1, T.border, "BORDER")

    text = W.Text(frame, 12, T.accent, "CENTER")
    text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    text:SetPoint("CENTER", 0, 0)

    CUI:RegisterMovable(frame, "killtracker", "Kill Tracker", { point = "CENTER", x = 0, y = -180, scalable = true,
        resizable = true, minW = 120, maxW = 600, minH = 16, maxH = 40 })

    frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    frame:RegisterEvent("PLAYER_XP_UPDATE")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", OnEvent)
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
    Refresh()
end

CUI:RegisterModule({
    key = "killtracker",
    name = "Kill Tracker",
    addon = "CysUI",
    desc = "Learns your average XP per kill and shows how many more kills it takes to level.",
    onEnable = KT.Enable,
    open = function() CUI:OpenConfig("Kill Tracker") end,
})

CUI:RegisterPage("Kill Tracker", function(page)
    local db = DB()
    local width = 480

    W.Header(page, "Kill Tracker", width):SetPoint("TOPLEFT", 0, -4)
    local show = W.Checkbox(page, "Show the kill tracker", function() return db.show end,
        function(on) db.show = on; Refresh() end)
    show:SetPoint("TOPLEFT", 4, -34)

    local fmtOpts = {}
    for i, f in ipairs(FORMATS) do fmtOpts[i] = { i, f.name } end
    local fmt = W.Dropdown(page, 300, fmtOpts, function() return db.format end,
        function(v) db.format = v; Refresh() end, "Shows: ")
    fmt:SetPoint("TOPLEFT", 4, -66)

    local lvl = W.Checkbox(page, "Start counting again when I level up", function() return db.resetOnLevel end,
        function(on) db.resetOnLevel = on end)
    lvl:SetPoint("TOPLEFT", 4, -98)
    local cap = W.Checkbox(page, "Hide it at max level", function() return db.hideAtMax end,
        function(on) db.hideAtMax = on; Refresh() end)
    cap:SetPoint("TOPLEFT", 4, -124)

    local reset = W.Button(page, 160, 22, "Reset this session")
    reset:SetPoint("TOPLEFT", 4, -158)
    reset:SetScript("OnClick", function() KT:Reset() end)

    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", 4, -196)
    note:SetWidth(width)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("It learns from the kills you make while you play, so the first number appears after your first kill. "
        .. "Quest rewards don't count as kills.")
end)
