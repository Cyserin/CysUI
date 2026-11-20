--------------------------------------------------------------------------------
-- Cys's UI - Dungeon Runs (WoW Forever)
--
-- Times each dungeon run and counts the XP it gave you: kills, quests, XP per hour, and how many more runs like
-- it take you to your next level. When you leave the dungeon a short summary prints in your own chat window
-- (nobody else sees it). A run that ends because you died and ran back in keeps counting as the same run.
--
-- Other addons can read it through CysUI.Runs (Cys's Level Pace does): Current(), Last(), History(),
-- Average(instanceID), ThisHour(). If Level Pace is loaded the summary also says how many runs your goal takes.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "runs", name = "Dungeon Runs", foreverOnly = true,
    desc = "Times each dungeon run, counts its XP (kills and quests), and prints a summary in your chat when you leave: XP per hour and runs to level.",
    open = function() CysUI:OpenConfig("Dungeon Runs") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Compat = CysUICompat
local floor, max, min = math.floor, math.max, math.min

CysUIDB.runs = CysUIDB.runs or {}
local db = CysUIDB.runs
if db.print == nil then db.print = true end   -- prints to your own chat window only
if db.gold == nil then db.gold = true end
if db.raids == nil then db.raids = false end
if db.minMin == nil then db.minMin = 1 end    -- shorter visits are not reported (still saved)

local function CDB()
    CysUICharDB = CysUICharDB or {}
    CysUICharDB.runs = CysUICharDB.runs or { hist = {} }
    CysUICharDB.runs.hist = CysUICharDB.runs.hist or {}
    return CysUICharDB.runs
end

local KEEP = 60          -- runs kept per character
local GHOST_WAIT = 15 * 60 -- outside as a ghost this long = the run is over
local ALIVE_WAIT = 60    -- alive outside after dying (spirit healer) this long = the run is over
local STALE = 30 * 60    -- logged back in this long after the last thing we saw = start fresh

local function Plain(v) if Compat and Compat.Plain then return Compat.Plain(v) end return v end
local function MaxLevel()
    local m = GetMaxPlayerLevel and GetMaxPlayerLevel()
    return Plain(m) or 60
end

local function Commas(n)
    n = floor((n or 0) + 0.5)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end
local function Short(n)
    if n >= 10000 then return format("%.1fk", n / 1000) end
    return Commas(n)
end
local function Dur(s)
    s = max(0, floor(s or 0))
    if s >= 3600 then return format("%dh %02dm", floor(s / 3600), floor(s % 3600 / 60)) end
    return format("%dm %02ds", floor(s / 60), s % 60)
end
local function Money(c)
    c = floor(c or 0)
    local g, s, cp = floor(c / 10000), floor(c % 10000 / 100), c % 100
    local t = {}
    if g > 0 then t[#t + 1] = format("|cffffd100%dg|r", g) end
    if s > 0 or g > 0 then t[#t + 1] = format("|cffc7c7cf%ds|r", s) end
    t[#t + 1] = format("|cffeda55f%dc|r", cp)
    return table.concat(t, " ")
end

local R = {}
CUI.Runs = R

-- the run going on now (or nil). Saved per character so a /reload or a disconnect inside keeps it.
local function Cur() return CDB().cur end

local function Elapsed(run, now)
    local stop = run.stop or (run.out and run.out) or now or time()
    return max(0, stop - run.start)
end

local function Kills(run)
    return (run.kills or 0) + max(0, (run.sk or 0) - (run.qn or 0))
end

-- average XP and seconds per run of one dungeon (last n finished runs with XP, newest first)
function R.Average(id, n)
    n = n or 3
    local hist = CDB().hist
    local xp, secs, count = 0, 0, 0
    for i = #hist, 1, -1 do
        local r = hist[i]
        if r.id == id and (r.xp or 0) > 0 then
            xp, secs, count = xp + r.xp, secs + Elapsed(r), count + 1
            if count >= n then break end
        end
    end
    if count == 0 then return nil end
    return xp / count, secs / count, count
end

local function Copy(run)
    if not run then return nil end
    local c = {}
    for k, v in pairs(run) do c[k] = v end
    c.elapsed = Elapsed(run)
    c.killCount = Kills(run)
    c.xpPerHour = c.elapsed >= 60 and (run.xp or 0) / c.elapsed * 3600 or 0
    c.active = run.stop == nil
    return c
end
function R.Current() return Copy(Cur()) end
function R.Last() local h = CDB().hist return Copy(h[#h]) end
function R.History() local out = {} for i, r in ipairs(CDB().hist) do out[i] = Copy(r) end return out end
function R.ThisHour()
    local now, n = time(), 0
    for _, r in ipairs(CDB().hist) do if now - r.start < 3600 then n = n + 1 end end
    local c = Cur()
    if c and now - c.start < 3600 then n = n + 1 end
    return n
end

-- Level Pace (separate addon) tells us what is left to its goal
local function PaceGoal()
    local LP = _G.CysLevelingPace
    if type(LP) ~= "table" or type(LP.Goal) ~= "function" then return nil end
    local ok, g = pcall(LP.Goal)
    if ok and type(g) == "table" then return g end
end

local function Summary(run, again)
    local secs = Elapsed(run)
    local p = function(s) print("    " .. s) end
    CUI:Print(format("|cffffd100%s|r %s: |cffffffff%s|r", run.name or "Dungeon", again and "(last run)" or "run done", Dur(secs)))
    local xp = run.xp or 0
    if xp > 0 then
        local parts = {}
        if (run.kxp or 0) > 0 then
            local k = Kills(run)
            parts[#parts + 1] = k > 0 and format("kills %s from %d kills", Commas(run.kxp), k) or format("kills %s", Commas(run.kxp))
        end
        if (run.qxp or 0) > 0 then parts[#parts + 1] = format("quests %s", Commas(run.qxp)) end
        local hr = secs >= 60 and xp / secs * 3600 or 0
        p(format("XP: |cffffffff%s|r%s%s", Commas(xp), #parts > 0 and "  (" .. table.concat(parts, ", ") .. ")" or "",
            hr > 0 and format("  |cff00ff00%s XP/hr|r", Short(hr)) or ""))

        local avg, _, count = R.Average(run.id)
        if not avg then avg, count = xp, 1 end
        local level = UnitLevel("player") or 1
        if (run.lvlEnd or level) > (run.lvl or level) then
            p(format("|cff00ff00Leveled up to %d in this run!|r", run.lvlEnd or level))
        end
        if avg and avg > 0 and level < MaxLevel() then
            local left = max(0, (UnitXPMax("player") or 0) - (UnitXP("player") or 0))
            local note = count and count > 1 and format(" (~%s XP a run, last %d runs)", Short(avg), count) or ""
            p(format("Level %d: |cffffd100%.1f|r more runs like this to level %d%s", level, left / avg, level + 1, note))
            local g = PaceGoal()
            if g and (g.remainingXP or 0) > 0 and g.level and g.level > level then
                local runs = g.remainingXP / avg
                local perDay = ""
                if g.deadline and g.deadline > time() then
                    local days = (g.deadline - time()) / 86400
                    perDay = format(" (~%.1f a day to make %s)", runs / max(days, 0.01), date("%b %d", g.deadline))
                end
                p(format("Level Pace goal: ~|cffffd100%d|r runs to level %d%s", math.ceil(runs), g.level, perDay))
            end
        end
    end
    if db.gold and (run.money or 0) > 0 then p("Gold: +" .. Money(run.money)) end
    local hour = R.ThisHour()
    if hour >= 2 then p(format("Instances entered in the last hour: %d", hour)) end
end
R.PrintLast = function()
    local h = CDB().hist
    if #h == 0 then CUI:Print("No dungeon runs saved yet.") return end
    Summary(h[#h], true)
end

local listeners = {}
function R.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

local function Finish(stopAt, quiet)
    local c = CDB()
    local run = c.cur
    if not run then return end
    c.cur = nil
    run.stop = stopAt or run.out or time()
    run.out, run.dead = nil, nil
    run.lvlEnd = run.lvlEnd or UnitLevel("player")
    local secs = Elapsed(run)
    -- a zone-in-and-out with nothing gained is not a run
    if secs < 20 and (run.xp or 0) == 0 and (run.money or 0) == 0 then Changed() return end
    local hist = c.hist
    hist[#hist + 1] = run
    while #hist > KEEP do table.remove(hist, 1) end
    if db.print and not quiet and secs >= (db.minMin or 0) * 60 then Summary(run) end
    Changed()
end

local lastXP, lastMax, lastMoney

local function Start(id, name, kind)
    CDB().cur = { id = id, name = name, kind = kind, start = time(), last = time(), xp = 0, kxp = 0, qxp = 0,
                  kills = 0, sk = 0, qn = 0, money = 0, lvl = UnitLevel("player") }
    lastXP, lastMax, lastMoney = UnitXP("player"), UnitXPMax("player"), GetMoney()
    Changed()
end

local function Inside()
    local inInst, kind = IsInInstance()
    if not inInst then return nil end
    if kind ~= "party" and not (kind == "raid" and db.raids) then return nil end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    return id or name, name, kind
end

local function Check()
    local run = Cur()
    local now = time()
    if run and not run.out and now - (run.last or run.start) > STALE then
        Finish(run.last, true) -- logged out inside a while ago: close it quietly
        run = nil
    end
    local id, name, kind = Inside()
    if id then
        if run and run.id == id then
            run.out, run.dead = nil, nil -- back in (ran back as a ghost, or a reload)
            run.last = now
            lastXP, lastMax, lastMoney = UnitXP("player"), UnitXPMax("player"), GetMoney()
        else
            if run then Finish(run.out or now) end
            Start(id, name, kind)
        end
    elseif run and not run.out then
        run.out = now
        run.dead = UnitIsDeadOrGhost("player") and true or false
        if not run.dead then Finish(now) end
    end
end

-- waiting outside after a death: over when you are alive outside for a minute, or after 15 minutes
local function Tick()
    local run = Cur()
    if not run then return end
    local now = time()
    if not run.out then run.last = now return end
    if UnitIsDeadOrGhost("player") then
        run.alive = nil
        if now - run.out > GHOST_WAIT then Finish(run.out) end
    else
        run.alive = run.alive or now
        if now - run.alive > ALIVE_WAIT or now - run.out > GHOST_WAIT then Finish(run.out) end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
                     "CHAT_MSG_COMBAT_XP_GAIN", "QUEST_TURNED_IN", "PLAYER_MONEY", "PLAYER_UNGHOST", "PLAYER_ALIVE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
        Check()
        C_Timer.After(2, Check) -- instance info settles a moment after loading in
        return
    end
    if e == "PLAYER_UNGHOST" or e == "PLAYER_ALIVE" then Tick() return end
    local run = Cur()
    if not run or run.out then
        if e == "PLAYER_XP_UPDATE" then lastXP, lastMax = UnitXP("player"), UnitXPMax("player") end
        if e == "PLAYER_MONEY" then lastMoney = GetMoney() end
        return
    end
    run.last = time()
    if e == "PLAYER_XP_UPDATE" then
        local cur, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
        if lastXP then
            local gain = cur - lastXP
            if gain < 0 and lastMax then gain = cur + (lastMax - lastXP) end -- went over a level
            if gain > 0 then run.xp = run.xp + gain end
            run.kxp = max(0, run.xp - run.qxp)
        end
        lastXP, lastMax = cur, mx
    elseif e == "PLAYER_LEVEL_UP" then
        run.lvlEnd = Plain(a1) or UnitLevel("player")
    elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then
        if Compat and Compat.Secret and Compat.Secret(a1) then
            run.sk = run.sk + 1 -- can't read it in lockdown: counted as a kill unless a quest explains it
        elseif type(a1) == "string" and a1:find("dies") then
            run.kills = run.kills + 1
        end
    elseif e == "QUEST_TURNED_IN" then
        local xp = Plain(a2)
        if type(xp) == "number" and xp > 0 then
            run.qxp = run.qxp + xp
            run.qn = run.qn + 1
            run.kxp = max(0, run.xp - run.qxp)
        end
    elseif e == "PLAYER_MONEY" then
        local m = GetMoney()
        if lastMoney and m > lastMoney then run.money = run.money + (m - lastMoney) end
        lastMoney = m
    end
end)
C_Timer.NewTicker(15, Tick)
Check()

SLASH_CYSUIRUNS1 = "/cuiruns"
SlashCmdList.CYSUIRUNS = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "history" then
        local hist = CDB().hist
        if #hist == 0 then CUI:Print("No dungeon runs saved yet.") return end
        CUI:Print("Your last dungeon runs:")
        for i = #hist, max(1, #hist - 9), -1 do
            local r = hist[i]
            local secs = Elapsed(r)
            print(format("    %s  %s  %s  %s XP  %s/hr  (level %d)", date("%b %d %H:%M", r.start), r.name or "?", Dur(secs),
                Commas(r.xp or 0), secs >= 60 and Short((r.xp or 0) / secs * 3600) or "-", r.lvl or 0))
        end
    elseif msg == "now" then
        local c = Cur()
        if not c then CUI:Print("You are not in a dungeon run.") return end
        Summary(c, true)
    elseif msg == "" or msg == "last" then
        R.PrintLast()
    else
        CUI:Print("/cuiruns - last run, /cuiruns now - the run you are in, /cuiruns history - your last 10 runs.")
    end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local rows, emptyText = {}, nil
local function PaintList()
    local hist = CDB().hist
    local n = 0
    for i = #hist, 1, -1 do
        n = n + 1
        local row = rows[n]
        if not row then break end
        local r = hist[i]
        local secs = Elapsed(r)
        row.name:SetText(r.name or "?")
        row.when:SetText(date("%b %d", r.start))
        row.time:SetText(Dur(secs))
        row.xp:SetText((r.xp or 0) > 0 and Short(r.xp) or "-")
        row.hr:SetText(secs >= 60 and (r.xp or 0) > 0 and Short(r.xp / secs * 3600) or "-")
        row.lvl:SetText(tostring(r.lvl or ""))
        row:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    if emptyText then emptyText:SetShown(#hist == 0) end
end
R.OnChange(function() if rows[1] and rows[1]:GetParent():IsVisible() then PaintList() end end)

CUI:RegisterPage("Dungeon Runs", function(page)
    local width = 480
    W.Header(page, "Dungeon Runs", width):SetPoint("TOPLEFT", 0, -4)
    W.Checkbox(page, "Print a run summary in my chat when I leave", function() return db.print end,
        function(on) db.print = on end):SetPoint("TOPLEFT", 4, -34)
    W.Checkbox(page, "Show the gold you picked up in the summary", function() return db.gold end,
        function(on) db.gold = on end):SetPoint("TOPLEFT", 4, -60)
    W.Checkbox(page, "Count raids too", function() return db.raids end,
        function(on) db.raids = on end):SetPoint("TOPLEFT", 4, -86)
    W.Stepper(page, "Shortest run to report", function() return db.minMin end,
        function(v) db.minMin = v end, 0, 15, 1, " min"):SetPoint("TOPLEFT", 4, -116)

    local last = W.Button(page, 130, 22, "Print last run")
    last:SetPoint("TOPLEFT", 4, -154)
    last:SetScript("OnClick", R.PrintLast)
    local clear = W.Button(page, 130, 22, "Clear history")
    clear:SetPoint("LEFT", last, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetText("Clear history")
            wipe(CDB().hist)
            Changed()
        else
            self.armed = true
            self:SetText("Click again to clear")
            C_Timer.After(3, function() if self.armed then self.armed = nil; self:SetText("Clear history") end end)
        end
    end)

    local head = W.Text(page, 12, T.brand)
    head:SetPoint("TOPLEFT", 4, -194)
    head:SetText("Recent runs on this character")
    local cols = { { "name", 0, 170, "Dungeon" }, { "when", 172, 60, "Date" }, { "time", 234, 70, "Time" },
                   { "xp", 306, 60, "XP" }, { "hr", 368, 60, "XP/hr" }, { "lvl", 430, 40, "Level" } }
    for _, c in ipairs(cols) do
        local t = W.Text(page, 10, T.desc)
        t:SetPoint("TOPLEFT", 4 + c[2], -214)
        t:SetText(c[4])
    end
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(width, 18)
        row:SetPoint("TOPLEFT", 4, -230 - (i - 1) * 18)
        for _, c in ipairs(cols) do
            local t = W.Text(row, 11, c[1] == "name" and T.text or T.desc)
            t:SetPoint("LEFT", c[2], 0)
            t:SetWidth(c[3])
            t:SetJustifyH("LEFT")
            t:SetWordWrap(false)
            row[c[1]] = t
        end
        rows[i] = row
    end
    emptyText = W.Text(page, 11, T.desc)
    emptyText:SetPoint("TOPLEFT", 4, -230)
    emptyText:SetText("No runs yet. Your next dungeon shows up here when you leave it.")

    W.Notes(page, 4, -420, width, "", {
        "A run starts when you enter a dungeon and ends when you leave it. Died and ran back in? It stays the same run.",
        "The summary only prints in your own chat window. /cuiruns prints the last run again, /cuiruns now the run you are in, /cuiruns history your last 10.",
        "With Cys's Level Pace loaded the summary also says how many runs your goal takes, and Level Pace shows the run you are in.",
    })
    PaintList()
end, function() PaintList() end)

    end,
})
