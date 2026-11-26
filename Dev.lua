--------------------------------------------------------------------------------
-- Cys's UI - Stutter Watch (developer window, /cuidev)
--
-- Not a module and not in the settings: a small window for finding what makes the game stutter.
--   * Live frame rate, frame time and Lua memory (and how fast it grows).
--   * Every stutter (a frame slower than the line you pick) is logged with what caused it:
--       - the add-ons whose code ran over 5/10/50/100+ ms since the last check (the game's own add-on
--         profiler counts these for every add-on),
--       - a Lua clean-up (memory dropped: add-ons made lots of garbage and the game swept it up),
--       - or nothing from add-ons: the game itself (loading the area, textures, graphics).
--   * The busiest add-ons right now (average ms per frame, and their slowest frame).
-- Only runs while the window is open. Copy puts the log in a box to paste anywhere.
--------------------------------------------------------------------------------
local CUI = CysUI
local D = {}
CUI.Dev = D

local P = C_AddOnProfiler
local M = Enum and Enum.AddOnProfilerMetric
local floor, min = math.floor, math.min

local function HasProfiler()
    if not (P and M and P.GetAddOnMetric) then return false end
    if P.IsEnabled then
        local ok, on = pcall(P.IsEnabled)
        if ok and on == false then return false end
    end
    return true
end

local function Metric(name, m)
    if not m then return 0 end
    local ok, v = pcall(P.GetAddOnMetric, name, m)
    if ok and type(v) == "number" then return v end
    return 0
end

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.dev = CysUIDB.dev or { threshold = 50 }
    return CysUIDB.dev
end

--------------------------------------------------------------------------------
-- Measuring
--------------------------------------------------------------------------------
local addons = {}            -- loaded add-on folder names
local snap = {}              -- [name] = { counts at the last check }
local BUCKETS = {            -- biggest first: the label a stutter gets is the biggest bucket that grew
    { "CountTimeOver1000Ms", ">1 s" }, { "CountTimeOver500Ms", ">500 ms" }, { "CountTimeOver100Ms", ">100 ms" },
    { "CountTimeOver50Ms", ">50 ms" }, { "CountTimeOver10Ms", ">10 ms" }, { "CountTimeOver5Ms", ">5 ms" },
}

local function ListAddons()
    wipe(addons)
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    for i = 1, num do
        local name = info(i)
        if name and loaded(name) then addons[#addons + 1] = name end
    end
end

local function TakeSnapshot()
    if not HasProfiler() then return end
    for _, name in ipairs(addons) do
        local s = snap[name] or {}
        for i, b in ipairs(BUCKETS) do s[i] = Metric(name, M[b[1]]) end
        snap[name] = s
    end
end

local log = {}               -- newest first: { time, ms, combat, cause }
local MAX_LOG = 40
local loadingUntil = 0       -- loading screens always hitch: skip them

local function Blame(ms, memBefore, memNow)
    local hits = {}
    if HasProfiler() then
        for _, name in ipairs(addons) do
            local s = snap[name]
            if s then
                for i, b in ipairs(BUCKETS) do
                    if Metric(name, M[b[1]]) > (s[i] or 0) then
                        hits[#hits + 1] = { name = name, rank = i, label = b[2] }
                        break
                    end
                end
            end
        end
        table.sort(hits, function(a, b) return a.rank < b.rank end)
    end
    local parts = {}
    for i = 1, min(3, #hits) do parts[#parts + 1] = format("%s %s", hits[i].name, hits[i].label) end
    if #hits > 3 then parts[#parts + 1] = format("+%d more", #hits - 3) end
    local freed = memBefore - memNow
    if freed > 1024 then parts[#parts + 1] = format("Lua clean-up freed %.1f MB", freed / 1024) end
    local cause
    if #parts == 0 then
        cause = HasProfiler() and "|cFF9FD3FFthe game itself|r (loading the area, textures, graphics)" or "unknown (no add-on profiler)"
    else
        cause = table.concat(parts, ", ")
    end
    table.insert(log, 1, { date("%H:%M:%S"), ms, InCombatLockdown(), cause })
    if #log > MAX_LOG then log[#log] = nil end
    TakeSnapshot() -- the next stutter only counts what happens after this one
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local win, statsText, logRows, busyRows, copyBox
local LOG_ROWS, BUSY_ROWS = 8, 6

local function Paint()
    for i = 1, LOG_ROWS do
        local e = log[i]
        if e then
            local c = e[2] >= 200 and "|cFFFF4040" or e[2] >= 100 and "|cFFFF9F43" or "|cFFFFD100"
            logRows[i]:SetText(format("|cFF777777%s|r %s%d ms|r%s  %s", e[1], c, floor(e[2] + 0.5), e[3] and " |cFFFF4040(combat)|r" or "", e[4]))
        else
            logRows[i]:SetText(i == 1 and "|cFF777777No stutters yet. Leave this open and play where it happens.|r" or "")
        end
    end
end

local function PaintBusy()
    if not HasProfiler() then
        busyRows[1]:SetText("|cFF777777The game's add-on profiler isn't available here. Try /cui cpu on for Cys's UI's own parts.|r")
        for i = 2, BUSY_ROWS do busyRows[i]:SetText("") end
        return
    end
    local list = {}
    for _, name in ipairs(addons) do
        local avg = Metric(name, M.RecentAverageTime)
        if avg > 0 then list[#list + 1] = { name, avg, Metric(name, M.PeakTime) } end
    end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = 1, BUSY_ROWS do
        local e = list[i]
        busyRows[i]:SetText(e and format("%s  |cFFFFD100%.2f ms|r a frame  |cFF777777(slowest %.0f ms)|r", e[1], e[2], e[3]) or "")
    end
end

local function LogText()
    local out = { "Cys's UI Stutter Watch - " .. date("%Y-%m-%d") }
    for i = #log, 1, -1 do
        local e = log[i]
        local cause = e[4]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        out[#out + 1] = format("%s  %d ms%s  %s", e[1], floor(e[2] + 0.5), e[3] and " (combat)" or "", cause)
    end
    return table.concat(out, "\n")
end

-- a text box you can copy from (Ctrl+C), with a close button; used for the stutter log and the CPU report
local function CopyWindow(name, w, h, heading)
    local W = CUI.W
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Texture(f, "BACKGROUND", { W.T.bg[1], W.T.bg[2], W.T.bg[3], 0.97 }):SetAllPoints()
    W.Border(f, 1, W.T.border, "BORDER")
    local t = W.Text(f, 11, W.T.accent)
    t:SetPoint("TOPLEFT", 8, -7)
    t:SetText(heading)
    f.heading = t
    local close = W.Button(f, 22, 18, "X")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide() end)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -28)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(w - 40)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb
    return f
end

local function ShowCopy()
    if not copyBox then copyBox = CopyWindow("CysDevCopy", 460, 260, "Ctrl+C to copy, Esc to close") end
    copyBox.eb:SetText(LogText())
    copyBox:Show()
    copyBox.eb:SetFocus()
    copyBox.eb:HighlightText()
end

-- /cui cpu also lands here, so the report can be copied without digging through chat
local reportBox
function D.ShowReport(lines)
    if type(lines) ~= "table" or #lines == 0 then return end
    if not reportBox then reportBox = CopyWindow("CysDevReport", 560, 330, "CPU report  (Ctrl+C to copy, Esc to close)") end
    local out = { "Cys's UI CPU report - " .. date("%Y-%m-%d %H:%M:%S") }
    for _, l in ipairs(lines) do
        out[#out + 1] = (tostring(l):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
    reportBox:ClearAllPoints()
    if win and win:IsShown() then -- right beside Stutter Watch (or on its left if there is no room)
        if (win:GetRight() or 0) + 570 < (UIParent:GetRight() or 0) then
            reportBox:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
        else
            reportBox:SetPoint("TOPRIGHT", win, "TOPLEFT", -6, 0)
        end
    else
        reportBox:SetPoint("CENTER")
    end
    reportBox.eb:SetText(table.concat(out, "\n"))
    reportBox:Show()
    reportBox.eb:SetFocus()
    reportBox.eb:HighlightText()
end

local function Build()
    if win then return end
    local W = CUI.W
    local T = W.T
    local db = DB()
    local WIDTH = 600
    win = CreateFrame("Frame", "CysDevWindow", UIParent)
    win:SetSize(WIDTH, 380)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.pos = { p, rp, x, y }
    end)
    if db.pos then win:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120) end
    W.Texture(win, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.92 }):SetAllPoints()
    W.Border(win, 1, T.border, "BORDER")

    local title = W.Text(win, 13, T.accent)
    title:SetPoint("TOPLEFT", 8, -7)
    title:SetText("Stutter Watch")
    local close = W.Button(win, 22, 18, "X")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() win:Hide() end)

    statsText = W.Text(win, 11, T.text)
    statsText:SetPoint("TOPLEFT", 8, -30)

    local function Row(y)
        local r = W.Text(win, 11, T.text)
        r:SetPoint("TOPLEFT", 8, y)
        r:SetPoint("RIGHT", win, "RIGHT", -8, 0)
        r:SetJustifyH("LEFT")
        r:SetWordWrap(false)
        return r
    end
    local h1 = W.Text(win, 11, T.accent); h1:SetPoint("TOPLEFT", 8, -54); h1:SetText("Stutters, newest first")
    logRows = {}
    for i = 1, LOG_ROWS do logRows[i] = Row(-70 - (i - 1) * 15) end
    local h2 = W.Text(win, 11, T.accent); h2:SetPoint("TOPLEFT", 8, -196); h2:SetText("Busiest add-ons right now")
    busyRows = {}
    for i = 1, BUSY_ROWS do busyRows[i] = Row(-212 - (i - 1) * 15) end

    local tip = W.Text(win, 11, T.desc)
    tip:SetPoint("TOPLEFT", 8, -304)
    tip:SetPoint("RIGHT", win, "RIGHT", -8, 0)
    tip:SetJustifyH("LEFT")
    tip:SetText("|cFFFFD100If CysUI is the cause:|r type |cFFFFD100/cui cpu on|r, then |cFFFFD100/reload|r, play a bit where it stutters, then press |cFFFFD100CPU report|r (or type |cFFFFD100/cui cpu|r) to see which part of CysUI it is. |cFFFFD100/cui cpu off|r when done.")

    local dd = W.Dropdown(win, 170, { { 50, "Stutter at: 50 ms+" }, { 100, "Stutter at: 100 ms+" }, { 200, "Stutter at: 200 ms+" } },
        function() return db.threshold end, function(v) db.threshold = v end)
    dd:SetPoint("BOTTOMLEFT", 8, 8)
    local reset = W.Button(win, 70, 22, "Reset")
    reset:SetPoint("BOTTOMRIGHT", -84, 8)
    reset:SetScript("OnClick", function() wipe(log); TakeSnapshot(); Paint() end)
    local copy = W.Button(win, 70, 22, "Copy", true)
    copy:SetPoint("BOTTOMRIGHT", -8, 8)
    copy:SetScript("OnClick", ShowCopy)
    local cpu = W.Button(win, 96, 22, "CPU report")
    cpu:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    cpu:SetScript("OnClick", function() SlashCmdList.CYSUI("cpu") end)

    -- frame timing
    local frames, acc, slowest, tick = 0, 0, 0, 0
    local lastMem = collectgarbage("count")
    local memAt, memStart = GetTime(), lastMem
    win:SetScript("OnUpdate", function(_, elapsed)
        local ms = elapsed * 1000
        local mem = collectgarbage("count")
        if ms >= db.threshold and GetTime() > loadingUntil then
            Blame(ms, lastMem, mem)
            Paint()
        end
        lastMem = mem
        frames, acc = frames + 1, acc + elapsed
        if ms > slowest then slowest = ms end
        tick = tick + elapsed
        if tick >= 1 then
            local grow = (mem - memStart) / math.max(0.1, GetTime() - memAt)
            if grow < 0 then grow = 0 end
            statsText:SetText(format("|cFFFFD100%d|r fps   |cFFFFD100%.1f|r ms a frame (slowest %d)   Lua memory |cFFFFD100%.1f MB|r (+%d KB/s)   stutters: |cFFFFD100%d|r",
                floor(frames / acc + 0.5), acc / frames * 1000, floor(slowest + 0.5), mem / 1024, floor(grow + 0.5), #log))
            local need = math.ceil(statsText:GetStringWidth() + 20)
            if need > win:GetWidth() then win:SetWidth(need) end
            frames, acc, slowest, tick = 0, 0, 0, 0
            memAt, memStart = GetTime(), mem
            TakeSnapshot()
            PaintBusy()
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_ENABLED")
    pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_DISABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then ListAddons()
        else loadingUntil = GetTime() + 3 end
    end)
    win:Hide()
end

function D.Toggle()
    Build()
    if win:IsShown() then win:Hide() return end
    ListAddons()
    TakeSnapshot()
    Paint()
    PaintBusy()
    win:Show()
end

SLASH_CYSUIDEV1 = "/cuidev"
SlashCmdList.CYSUIDEV = D.Toggle
