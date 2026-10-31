--------------------------------------------------------------------------------
-- Cys's logs - a combat log you can open in game
--
-- Records every fight your group is in (damage, healing, damage taken, deaths with a recap, interrupts,
-- dispels) and shows it in a window: /cuilog, or Combat Log in /cui. It is a summary of each fight, not a
-- full event log, so it stays small. The last fights are kept between sessions.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = { record = true, keep = 15 }
local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.combatLog = CysUIDB.combatLog or {}
    local db = CysUIDB.combatLog
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.fights = db.fights or {}
    return db
end

local band = bit.band
local TOP_SPELLS = 6
local IDLE_END = 6       -- seconds without group activity ends a fight
local classCache = {}
local cur, lastEvent
local ring = {}          -- player guid -> recent events (for the death recap)

local function ClassOf(guid)
    if not guid then return nil end
    local c = classCache[guid]
    if c == nil then
        c = false
        if guid:find("^Player") and GetPlayerInfoByGUID then
            local _, token = GetPlayerInfoByGUID(guid)
            c = token or false
        end
        classCache[guid] = c
    end
    return c or nil
end

local function Group(flags) return flags and band(flags, 0x7) ~= 0 end

local function Add(tbl, name, class, amt, spell)
    local e = tbl[name]
    if not e then e = { t = 0, c = class, s = {} }; tbl[name] = e end
    e.t = e.t + amt
    if spell then e.s[spell] = (e.s[spell] or 0) + amt end
end

local function NewFight()
    return { t0 = GetTime(), at = time(), zone = GetZoneText() or "", dmg = {}, heal = {}, taken = {}, enemy = {},
             deaths = {}, ints = {}, disp = {} }
end

local function Push(guid, kind, amt, src, spell)
    local r = ring[guid]
    if not r then r = {}; ring[guid] = r end
    r[#r + 1] = { t = GetTime(), kind = kind, amt = amt, src = src, spell = spell }
    if #r > 12 then table.remove(r, 1) end
end

local function Recap(guid)
    local r, out, now = ring[guid], {}, GetTime()
    if not r then return out end
    for _, e in ipairs(r) do
        if now - e.t <= 15 then
            if e.kind == "d" then
                out[#out + 1] = string.format("-%d  %s: %s  (%.1fs ago)", e.amt, e.src or "?", e.spell or "?", now - e.t)
            else
                out[#out + 1] = string.format("+%d  %s: %s  (%.1fs ago)", e.amt, e.src or "?", e.spell or "?", now - e.t)
            end
        end
    end
    return out
end

local function Touch()
    lastEvent = GetTime()
    if not cur then cur = NewFight() end
end

local function OnCombatLog()
    local db = DB()
    if not db.record then return end
    local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, dFlags, _, a12, a13, _, a15, a16 = CombatLogGetCurrentEventInfo()
    local sGroup, dGroup = Group(sFlags), Group(dFlags)
    if not sGroup and not dGroup then return end

    local amount, spell
    if sub == "SWING_DAMAGE" then amount, spell = a12, "Melee"
    elseif sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then
        amount, spell = a15, a13
    end
    if amount and amount > 0 then
        Touch()
        if sGroup and not dGroup then
            Add(cur.dmg, sName or "?", ClassOf(sGUID), amount, spell)
            cur.enemy[dName or "?"] = (cur.enemy[dName or "?"] or 0) + amount
        end
        if dGroup then
            Add(cur.taken, dName or "?", ClassOf(dGUID), amount, (sName or "?") .. ": " .. tostring(spell))
            if dGUID and dGUID:find("^Player") then Push(dGUID, "d", amount, sName, spell) end
        end
        return
    end

    if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        local eff = (a15 or 0) - (a16 or 0)
        if eff > 0 and cur then
            Touch()
            if sGroup then Add(cur.heal, sName or "?", ClassOf(sGUID), eff, a13) end
        end
        if eff > 0 and dGroup and dGUID and dGUID:find("^Player") then Push(dGUID, "h", eff, sName, a13) end
        return
    end

    if not cur then return end
    if sub == "SPELL_INTERRUPT" and sGroup then
        cur.ints[#cur.ints + 1] = { who = sName, spell = a13, target = dName, stopped = a16 }
    elseif sub == "SPELL_DISPEL" and sGroup then
        cur.disp[sName or "?"] = (cur.disp[sName or "?"] or 0) + 1
    elseif sub == "UNIT_DIED" and dGroup and dGUID and dGUID:find("^Player") then
        Touch()
        local lines = Recap(dGUID)
        cur.deaths[#cur.deaths + 1] = { who = dName, c = ClassOf(dGUID), t = GetTime() - cur.t0, lines = lines }
        if dGUID == UnitGUID("player") then
            local last = lines[#lines]
            CUI:Print("You died" .. (last and (" - last hit: " .. last) or "") .. ". Open /cuilog for the full recap.")
        end
    end
end

-- turn a spell map into the top list that is saved
local function TopList(map)
    local list = {}
    for k, v in pairs(map) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    while #list > TOP_SPELLS do list[#list] = nil end
    return list
end

local function Freeze(f)
    local out = { at = f.at, zone = f.zone, dur = math.max(1, (lastEvent or GetTime()) - f.t0),
                  deaths = f.deaths, ints = f.ints, disp = f.disp }
    for _, key in ipairs({ "dmg", "heal", "taken" }) do
        out[key] = {}
        for name, e in pairs(f[key]) do out[key][name] = { t = e.t, c = e.c, s = TopList(e.s) } end
    end
    local best, bestAmt, n = nil, 0, 0
    for name, amt in pairs(f.enemy) do
        n = n + 1
        if amt > bestAmt then best, bestAmt = name, amt end
    end
    out.name = best and (n > 3 and (best .. " +" .. (n - 1)) or best) or "Fight"
    return out
end

local function Finish()
    if not cur then return end
    local f = cur
    cur = nil
    local dur = (lastEvent or GetTime()) - f.t0
    local any = false
    for _ in pairs(f.dmg) do any = true; break end
    if not any then for _ in pairs(f.taken) do any = true; break end end
    if dur < 4 or not any then return end
    local db = DB()
    table.insert(db.fights, 1, Freeze(f))
    while #db.fights > (db.keep or 15) do table.remove(db.fights) end
    if CUI.CombatLog and CUI.CombatLog.Refresh then CUI.CombatLog.Refresh() end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local CL = {}
CUI.CombatLog = CL
local win
local state = { sel = 0, tab = "dmg" }
local TABS = { { "dmg", "Damage" }, { "heal", "Healing" }, { "taken", "Taken" }, { "deaths", "Deaths" }, { "other", "Other" } }
local ROWS = 15

local function Fmt(n)
    n = n or 0
    if n >= 1000000 then return string.format("%.2fm", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function Clock(s) return string.format("%d:%02d", s / 60, s % 60) end

local function ClassColor(c)
    local col = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
    if col then return col.r, col.g, col.b end
    return 0.55, 0.55, 0.55
end

-- the fight being shown: the live one first, then the saved ones
local function Fights()
    local list = {}
    if cur then
        local f = Freeze(cur)
        f.live = true
        f.name = "Now: " .. f.name
        list[#list + 1] = f
    end
    for _, f in ipairs(DB().fights) do list[#list + 1] = f end
    return list
end

local function SpellsOf(e)
    if e.s and e.s[1] then return e.s end
    return TopList(e.s or {})
end

local function Build()
    if win then return end
    win = CreateFrame("Frame", "CysLogFrame", UIParent)
    win:SetSize(640, 400)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    W.Texture(win, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(win, 1, T.border, "BORDER")
    win:Hide()
    tinsert(UISpecialFrames, "CysLogFrame")

    local title = W.Text(win, 13, T.accent)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Cys's logs")
    local close = W.Button(win, 22, 22, "x")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)

    -- fights (left)
    win.fightBtns = {}
    for i = 1, 16 do
        local b = W.Button(win, 170, 20, "")
        b:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 22)
        b.label:SetFont(STANDARD_TEXT_FONT, 10, "")
        b:SetScript("OnClick", function() state.sel = b.index - 1; CL.Refresh() end)
        win.fightBtns[i] = b
    end

    -- tabs
    win.tabBtns = {}
    local x = 196
    for _, def in ipairs(TABS) do
        local b = W.Button(win, 80, 22, def[2])
        b:SetPoint("TOPLEFT", x, -34)
        b:SetScript("OnClick", function() state.tab = def[1]; CL.Refresh() end)
        win.tabBtns[def[1]] = b
        x = x + 86
    end

    win.head = W.Text(win, 11, T.desc)
    win.head:SetPoint("TOPLEFT", 196, -64)

    -- rows
    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(430, 18)
        r:SetPoint("TOPLEFT", 196, -84 - (i - 1) * 20)
        r:EnableMouse(true)
        r.bar = r:CreateTexture(nil, "BACKGROUND")
        r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.name = W.Text(r, 11, T.text)
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetWidth(230)
        r.name:SetWordWrap(false)
        r.val = W.Text(r, 11, T.text, "RIGHT")
        r.val:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for n, line in ipairs(self.tip) do
                if n == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1) end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win.rows[i] = r
    end
    win.note = W.Text(win, 10, T.dim)
    win.note:SetPoint("BOTTOMLEFT", 196, 12)
end

local function SetRow(i, text, valText, frac, c, tip)
    local r = win.rows[i]
    if not text then r:Hide() return end
    r:Show()
    r.name:SetText(text)
    r.val:SetText(valText or "")
    r.tip = tip
    if frac then
        r.bar:Show()
        r.bar:SetWidth(math.max(1, 430 * frac))
        local cr, cg, cb = ClassColor(c)
        r.bar:SetVertexColor(cr, cg, cb, 0.45)
    else
        r.bar:Hide()
    end
end

function CL.Refresh()
    if not win or not win:IsShown() then return end
    local fights = Fights()
    for i, b in ipairs(win.fightBtns) do
        local f = fights[i]
        b.index = i
        if f then
            b:Show()
            b:SetLabel(string.format("%s  %s  %s", f.live and "live" or date("%H:%M", f.at or 0), f.name or "?", Clock(f.dur or 0)))
            b:SetPrimary((i - 1) == state.sel)
        else
            b:Hide()
        end
    end
    for key, b in pairs(win.tabBtns) do b:SetPrimary(key == state.tab) end
    if state.sel >= #fights then state.sel = 0 end
    local f = fights[state.sel + 1]
    for i = 1, ROWS do SetRow(i, nil) end
    if not f then
        win.head:SetText("No fights recorded yet. Go hit something.")
        win.note:SetText("")
        return
    end
    win.head:SetText(string.format("%s%s  -  %s", f.name or "?", f.zone ~= "" and (" (" .. f.zone .. ")") or "", Clock(f.dur or 0)))
    win.note:SetText("Hover a row for the spells. The last " .. (DB().keep or 15) .. " fights are kept.")

    if state.tab == "dmg" or state.tab == "heal" or state.tab == "taken" then
        local list, total = {}, 0
        for name, e in pairs(f[state.tab] or {}) do list[#list + 1] = { name = name, e = e }; total = total + e.t end
        table.sort(list, function(a, b) return a.e.t > b.e.t end)
        local top = list[1] and list[1].e.t or 1
        for i = 1, math.min(#list, ROWS) do
            local it = list[i]
            local tip = { it.name .. " - " .. Fmt(it.e.t) }
            for _, sp in ipairs(SpellsOf(it.e)) do
                tip[#tip + 1] = string.format("%s  %s (%d%%)", sp[1], Fmt(sp[2]), it.e.t > 0 and math.floor(sp[2] / it.e.t * 100 + 0.5) or 0)
            end
            SetRow(i, i .. ". " .. it.name,
                string.format("%s   %s/s   %d%%", Fmt(it.e.t), Fmt(it.e.t / math.max(1, f.dur or 1)), total > 0 and math.floor(it.e.t / total * 100 + 0.5) or 0),
                it.e.t / top, it.e.c, tip)
        end
        if #list == 0 then SetRow(1, "Nothing recorded for this one.", "", nil) end
    elseif state.tab == "deaths" then
        local deaths = f.deaths or {}
        for i = 1, math.min(#deaths, ROWS) do
            local d = deaths[i]
            local tip = { d.who .. " died at " .. Clock(d.t or 0) }
            for _, l in ipairs(d.lines or {}) do tip[#tip + 1] = l end
            if #tip == 1 then tip[2] = "No hits were seen in the last 15 seconds." end
            SetRow(i, d.who, Clock(d.t or 0), 1, d.c, tip)
            win.rows[i].val:SetText(Clock(d.t or 0))
        end
        if #deaths == 0 then SetRow(1, "Nobody died. Nice.", "", nil) end
    else
        local n = 0
        for _, it in ipairs(f.ints or {}) do
            n = n + 1
            if n <= ROWS then SetRow(n, string.format("%s interrupted %s's %s", it.who or "?", it.target or "?", it.stopped or "a cast"), it.spell or "", nil) end
        end
        for who, count in pairs(f.disp or {}) do
            n = n + 1
            if n <= ROWS then SetRow(n, who .. " dispelled", count .. "x", nil) end
        end
        if n == 0 then SetRow(1, "No interrupts or dispels.", "", nil) end
    end
end

function CL.Toggle()
    Build()
    if win:IsShown() then win:Hide() else win:Show(); CL.Refresh() end
end
function CL.Open()
    Build()
    win:Show()
    CL.Refresh()
end
function CL.Clear()
    DB().fights = {}
    cur = nil
    CL.Refresh()
    CUI:Print("Combat log cleared.")
end

SLASH_CYSLOG1 = "/cuilog"
SLASH_CYSLOG2 = "/cyslog"
SlashCmdList["CYSLOG"] = function() CL.Toggle() end

--------------------------------------------------------------------------------
-- Module and settings
--------------------------------------------------------------------------------
local ev
local function Enable()
    if ev then return end
    ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then OnCombatLog() else wipe(ring) end
    end)
    C_Timer.NewTicker(1, function()
        if cur and lastEvent and GetTime() - lastEvent >= IDLE_END and not UnitAffectingCombat("player") then
            Finish()
        end
        if win and win:IsShown() and cur then CL.Refresh() end
    end)
end

CUI:RegisterModule({
    key = "combatlog",
    name = "Combat Log (Cys's logs)",
    addon = "CysUI",
    desc = "Records each fight (damage, healing, damage taken, deaths with a recap, interrupts, dispels) and shows it in a window: /cuilog.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Combat Log") end,
})

CUI:RegisterPage("Combat Log", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Combat log (Cys's logs)", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("Every fight your group is in is summed up: who did the damage and healing, what hurt who, deaths with the last hits before them, interrupts and dispels. Open it with /cuilog. It is a summary, not a full event log, so it stays small.")

    local open = W.Button(page, 200, 24, "Open the log window", true)
    open:SetPoint("TOPLEFT", 4, -108)
    open:SetScript("OnClick", function() CL.Open() end)

    local rec = W.Checkbox(page, "Record fights", function() return db.record end, function(on) db.record = on end)
    rec:SetPoint("TOPLEFT", 4, -146)
    local keep = W.Stepper(page, "Fights to keep", function() return db.keep end,
        function(v) db.keep = v; while #db.fights > v do table.remove(db.fights) end end, 5, 25, 5, "")
    keep:SetPoint("TOPLEFT", 4, -176)
    local clear = W.Button(page, 200, 22, "Clear all saved fights")
    clear:SetPoint("TOPLEFT", 4, -210)
    clear:SetScript("OnClick", function() CL.Clear() end)

    W.Notes(page, 4, -250, width, "", {
        "Only your group (you, party, raid and their pets) is counted. Mobs are never listed on the meters, only as the fight name.",
        "A fight ends after a few seconds with nothing happening. Fights under 4 seconds are skipped.",
        "To make a real log for warcraftlogs.com use the game's own /combatlog.",
    })
end)
