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
    { name = "Kills to level + XP per hour here", text = function(kills)
        local s = KT.Spot and KT.Spot()
        if s and s.xpPerHour then
            local n = s.xpPerHour
            return format("Kills to level: %d  (%s XP/hr)", kills, n >= 10000 and format("%.1fk", n / 1000) or floor(n))
        end
        return format("Kills to level: %d", kills)
    end },
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
    if db.levelAlert == nil then db.levelAlert = true end
    if db.farmPrint == nil then db.farmPrint = true end
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

-- for the XP bar: average XP per kill and kills left (nil until the first kill)
function KT.Active() return frame ~= nil end
function KT.Average() return (kills > 0 and totalXP > 0) and totalXP / kills or nil end
function KT.KillsToLevel()
    local avg = KT.Average()
    if not avg then return nil end
    return max(0, ceil(((UnitXPMax("player") or 0) - (UnitXP("player") or 0)) / avg)), floor(avg)
end

-- "This kill levels you!": a short pop-up when you target a mob whose kill finishes the level
local alert, alertText, alertShown
local function LevelAlert()
    if not alert or not DB().levelAlert then return end
    local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local ok, tx = pcall(TargetXP)
    local hit = ok and tx and remaining > 0 and tx >= remaining
    local okG, guid = pcall(UnitGUID, "target")
    if not okG or (CysUICompat and CysUICompat.Secret and CysUICompat.Secret(guid)) then guid = nil end
    if not hit then return end
    if guid and guid == alertShown then return end -- once per mob
    alertShown = guid
    alertText:SetText("This kill levels you!")
    alert:SetAlpha(1)
    alert:Show()
    alert.left = 3
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
--------------------------------------------------------------------------------
-- Farm spots: where you kill in the open world and the XP per hour you make there (kept per character,
-- so a /reload keeps it). Kills in dungeons only go into the rolling XP-per-hour log (Dungeon Runs
-- tracks the dungeon itself). Other addons read it: KT.Spot(), KT.Spots(), KT.Rate(secs), KT.OnChange(fn).
--------------------------------------------------------------------------------
local BREAK = 180        -- a longer gap between kills is a break: not counted as farming time
local STALE = 2 * 3600   -- back at the same place after this long = a new visit
local MOVE_KILLS = 3     -- this many kills in a row somewhere else = you moved to a new spot
local KEEP_SPOTS = 30
local LOG_SECS = 3600

local function FDB()
    CysUICharDB = CysUICharDB or {}
    local d = CysUICharDB.farm or {}
    CysUICharDB.farm = d
    d.log = d.log or {}
    d.spots = d.spots or {}
    return d
end

local function Place()
    local zone = (GetZoneText and GetZoneText()) or ""
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    if sub == "" then sub = zone end
    return zone .. "|" .. sub, sub, zone
end

local function Short(n)
    n = n or 0
    if n >= 10000 then return format("%.1fk", n / 1000) end
    return tostring(floor(n + 0.5))
end
local function Mins(m)
    m = floor((m or 0) + 0.5)
    if m >= 60 then return format("%dh %02dm", floor(m / 60), m % 60) end
    return format("%dm", m)
end

-- a copy with the numbers worked out. Farming time covers the gaps between kills, so one more
-- average gap is added for the first kill (otherwise the first minutes read far too high).
local function SpotInfo(s)
    if not s then return nil end
    local c = {}
    for k, v in pairs(s) do if k ~= "pend" then c[k] = v end end
    local t = 0
    if (s.kills or 0) > 1 then t = (s.active or 0) * s.kills / (s.kills - 1) end
    c.time = t
    c.avgKill = (s.kills or 0) > 0 and s.xp / s.kills or nil
    if t >= 120 then
        c.xpPerHour = s.xp / t * 3600
        c.killsPerHour = s.kills / t * 3600
        local left = max(0, (UnitXPMax("player") or 0) - (UnitXP("player") or 0))
        c.minsToLevel = c.xpPerHour > 0 and left / c.xpPerHour * 60 or nil
    end
    return c
end

local listeners = {}
function KT.OnChange(fn) if type(fn) == "function" then listeners[#listeners + 1] = fn end end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

local function FinishSpot(quiet)
    local d = FDB()
    local s = d.cur
    if not s then return end
    d.cur = nil
    s.pend = nil
    s.stop = s.last
    if (s.kills or 0) >= 5 then
        d.spots[#d.spots + 1] = s
        while #d.spots > KEEP_SPOTS do table.remove(d.spots, 1) end
    end
    local i = SpotInfo(s)
    if not quiet and DB().farmPrint and i.xpPerHour and i.time >= 300 then
        CUI:Print(format("Farm spot done: |cffffd100%s|r  %s, %s XP from %d kills, |cff00ff00%s XP/hr|r (%d kills/hr)",
            s.name or "?", Mins(i.time / 60), Short(s.xp), s.kills, Short(i.xpPerHour), floor(i.killsPerHour + 0.5)))
    end
end

local function NewSpot(key, name, zone, now)
    return { key = key, name = name, zone = zone, start = now, last = now, active = 0, xp = 0, kills = 0,
             lvl = UnitLevel("player") or 1 }
end

local function FarmKill(xp)
    local now = time()
    local d = FDB()
    local log = d.log
    log[#log + 1] = { now, xp }
    while log[1] and now - log[1][1] > LOG_SECS do table.remove(log, 1) end
    if IsInInstance() then Changed() return end

    local key, name, zone = Place()
    local s = d.cur
    if s and now - (s.last or 0) > STALE then FinishSpot(true); s = nil end
    if s and s.key ~= key then
        -- killing somewhere else: hold those kills apart until it's clear you moved
        local p = s.pend
        if p and p.key == key then
            local gap = now - p.last
            if gap <= BREAK then p.active = p.active + gap end
            p.xp, p.kills, p.last = p.xp + xp, p.kills + 1, now
        else
            p = NewSpot(key, name, zone, now)
            p.xp, p.kills = xp, 1
            s.pend = p
        end
        if p.kills >= MOVE_KILLS then
            s.pend = nil
            FinishSpot()
            d.cur = p
        end
        Changed()
        return
    end
    if not s then
        s = NewSpot(key, name, zone, now)
        d.cur = s
    else
        local p = s.pend
        if p then -- a few kills next door, then back: they belong to this spot
            s.xp, s.kills, s.pend = s.xp + p.xp, s.kills + p.kills, nil
        end
        local gap = now - s.last
        if gap <= BREAK then s.active = s.active + gap end
    end
    s.xp, s.kills, s.last = s.xp + xp, s.kills + 1, now
    s.lvlNow = UnitLevel("player")
    Changed()
end

function KT.Spot() return SpotInfo(FDB().cur) end
function KT.Spots() -- finished spots, newest first
    local out, sp = {}, FDB().spots
    for i = #sp, 1, -1 do out[#out + 1] = SpotInfo(sp[i]) end
    return out
end
-- XP per hour over the last `secs` seconds (all kills, breaks included), nil with too little to go on
function KT.Rate(secs)
    secs = secs or 900
    local now, xp, oldest, n = time(), 0, nil, 0
    for _, e in ipairs(FDB().log) do
        if now - e[1] <= secs then
            xp, n = xp + e[2], n + 1
            oldest = oldest or e[1]
        end
    end
    if n < 2 or not oldest then return nil end
    local span = now - oldest
    if span < 120 then return nil end
    return xp / span * 3600, n / span * 3600
end
function KT.EndSpot() FinishSpot(); Changed() end

local function CountKill(xp)
    if not xp or xp <= 0 then return end
    totalXP = totalXP + xp
    kills = kills + 1
    FarmKill(xp)
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
        LevelAlert()
    elseif event == "PLAYER_LEVEL_UP" then
        if DB().resetOnLevel then totalXP, kills = 0, 0 end
        Refresh()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        -- left the zone (flew off, hearthed, zoned into a dungeon): the farm spot is done
        local d = FDB()
        if d.cur then
            local _, _, zone = Place()
            if zone ~= "" and zone ~= d.cur.zone then FinishSpot(); Changed() end
        end
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
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", OnEvent)
    KT.OnChange(Refresh)
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")

    alert = CreateFrame("Frame", "CysUIKillLevelAlert", UIParent)
    alert:SetSize(300, 30)
    alert:SetFrameStrata("HIGH")
    alertText = alert:CreateFontString(nil, "OVERLAY")
    alertText:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
    alertText:SetTextColor(T.green[1], T.green[2], T.green[3])
    alertText:SetPoint("CENTER")
    alert:Hide()
    alert:SetScript("OnUpdate", function(self, elapsed)
        self.left = (self.left or 0) - elapsed
        if self.left <= 0 then self:Hide() return end
        if self.left < 1 then self:SetAlpha(self.left) end -- fade out over the last second
    end)
    CUI:RegisterMovable(alert, "killalert", "Level-up kill alert", { point = "CENTER", x = 0, y = 160 })
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

    local la = W.Checkbox(page, "Pop-up when the target I pick will level me", function() return db.levelAlert end,
        function(on) db.levelAlert = on end)
    la:SetPoint("TOPLEFT", 4, -150)

    local fp = W.Checkbox(page, "Print a summary in my chat when I leave a farm spot", function() return db.farmPrint end,
        function(on) db.farmPrint = on end)
    fp:SetPoint("TOPLEFT", 4, -176)

    local reset = W.Button(page, 160, 22, "Reset this session")
    reset:SetPoint("TOPLEFT", 4, -210)
    reset:SetScript("OnClick", function() KT:Reset() end)
    local endSpot = W.Button(page, 160, 22, "End farm spot now")
    endSpot:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    endSpot:SetScript("OnClick", function() KT.EndSpot() end)

    W.Notes(page, 4, -248, width, "", {
        "It learns from the kills you make while you play, so the first number appears after your first kill. Quest rewards don't count as kills.",
        "Kills to level also shows on the XP bar and its tooltip, so this box can be switched off. The pop-up works solo (group XP is split) and can be moved in layout mode.",
        "Farm spots: kills in the open world are grouped by where you make them. XP per hour counts only the time you are pulling (breaks over 3 minutes are left out). Leave the zone or make 3 kills somewhere else and the spot is done.",
        "/cuifarm shows the spot you are at and your last ones; /cuifarm end finishes the spot now.",
    })
end)

SLASH_CYSUIFARM1 = "/cuifarm"
SlashCmdList.CYSUIFARM = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "end" then KT.EndSpot() return end
    local s = KT.Spot()
    if s then
        if s.xpPerHour then
            CUI:Print(format("Farming |cffffd100%s|r: %s, %d kills, |cff00ff00%s XP/hr|r, %d kills/hr, ~%s XP a kill, level in ~%s",
                s.name, Mins(s.time / 60), s.kills, Short(s.xpPerHour), floor(s.killsPerHour + 0.5), Short(s.avgKill),
                s.minsToLevel and Mins(s.minsToLevel) or "?"))
        else
            CUI:Print(format("Farming |cffffd100%s|r: %d kills so far, XP per hour shows after 2 minutes.", s.name, s.kills))
        end
    else
        CUI:Print("No farm spot right now. Kill something in the open world to start one.")
    end
    local list = KT.Spots()
    for i = 1, math.min(5, #list) do
        local r = list[i]
        print(format("    %s  %s  %s, %d kills, %s XP/hr (level %d)", date("%b %d", r.start), r.name or "?",
            Mins((r.time or 0) / 60), r.kills or 0, r.xpPerHour and Short(r.xpPerHour) or "-", r.lvl or 0))
    end
end
