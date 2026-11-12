--------------------------------------------------------------------------------
-- Cys's UI - measuring mode (/cui cpu on, then /reload; /cui cpu shows the slow parts; /cui cpu off)
--
-- Only does anything while switched on. Then every module's frames (their events, per-frame updates), hooks and
-- timers are timed under the module's name, and so are the public functions of each part of Cys's UI. The game's
-- own add-on profiler only knows "CysUI" as a whole; this tells which part of it costs the time.
--------------------------------------------------------------------------------
local CUI = CysUI
local P = { stats = {}, on = false }
CUI.Perf = P

local now = debugprofilestop
local stats = P.stats

local function Rec(label, ms)
    local s = stats[label]
    if not s then s = { n = 0, total = 0, max = 0, over10 = 0, over50 = 0 }; stats[label] = s end
    s.n = s.n + 1
    s.total = s.total + ms
    if ms > s.max then s.max = ms end
    if ms > 10 then s.over10 = s.over10 + 1 end
    if ms > 50 then s.over50 = s.over50 + 1 end
end

local function Done(label, t0, ...)
    Rec(label, now() - t0)
    return ...
end
function P.Wrap(label, fn)
    if type(fn) ~= "function" then return fn end
    return function(...) return Done(label, now(), fn(...)) end
end
-- event handlers: one line per event name
local function WrapEvent(label, fn)
    return function(self, event, ...)
        local t0 = now()
        fn(self, event, ...)
        Rec(label .. " " .. tostring(event), now() - t0)
    end
end

-- our own frames only: their SetScript / HookScript time what they are given
local function Instrument(f, key)
    if type(f) ~= "table" then return end
    local set, hook = f.SetScript, f.HookScript
    if not set then return end
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then
            fn = script == "OnEvent" and WrapEvent(key, fn) or P.Wrap(key .. " " .. script, fn)
        end
        return set(self, script, fn)
    end
    if hook then
        f.HookScript = function(self, script, fn, ...)
            if type(fn) == "function" then
                fn = script == "OnEvent" and WrapEvent(key, fn) or P.Wrap(key .. " " .. script, fn)
            end
            return hook(self, script, fn, ...)
        end
    end
end

-- the world a module's code sees while measuring: the normal one, with timed CreateFrame / hooks / timers
function P.Env(key)
    local timer = setmetatable({
        After = function(d, fn) return C_Timer.After(d, P.Wrap(key .. " timer", fn)) end,
        NewTimer = function(d, fn) return C_Timer.NewTimer(d, P.Wrap(key .. " timer", fn)) end,
        NewTicker = function(d, fn, n) return C_Timer.NewTicker(d, P.Wrap(key .. " ticker", fn), n) end,
    }, { __index = C_Timer })
    local env = setmetatable({
        CreateFrame = function(kind, name, parent, template, ...)
            local f = CreateFrame(kind, name, parent, template, ...)
            -- only plain frames (event and update frames): anything built from one of the game's templates is
            -- left alone, so no game code ever runs through our timing
            if template == nil or template == "BackdropTemplate" then Instrument(f, key) end
            return f
        end,
        hooksecurefunc = function(a, b, c)
            if type(a) == "string" then return hooksecurefunc(a, P.Wrap(key .. " hook " .. a, b)) end
            return hooksecurefunc(a, b, P.Wrap(key .. " hook " .. tostring(b), c))
        end,
        C_Timer = timer,
    }, { __index = _G, __newindex = _G })
    return env
end

-- public functions of each part (CUI.UnitFrames.Update and the like, Cys's Bags and Bank methods)
local SKIP = { W = true, modules = true, pages = true, movers = true, order = true, moverOrder = true, Perf = true }
local function WrapTable(label, t, seen)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "function" and type(k) == "string" then t[k] = P.Wrap(label .. "." .. k, v) end
    end
end
function P.WrapPublic()
    local seen = {}
    for k, v in pairs(CUI) do
        if type(v) == "table" and type(k) == "string" and not SKIP[k] then WrapTable(k, v, seen) end
    end
    WrapTable("Bags", _G.CysBags, seen)
    WrapTable("Bank", _G.CysBank, seen)
end

function P.Report()
    local list = {}
    for label, s in pairs(stats) do list[#list + 1] = { label = label, s = s } end
    if #list == 0 then
        CUI:Print("Nothing measured yet. Play a while (where the stutter happens), then type /cui cpu again.")
        return
    end
    table.sort(list, function(a, b) return a.s.total > b.s.total end)
    CUI:Print("|cFFFFD100Inside CysUI, most time first|r (total ms, calls, slowest call, calls over 10 ms):")
    for i = 1, math.min(10, #list) do
        local s = list[i].s
        CUI:Print(string.format("  %s: %.0f ms, %d calls, max %.1f ms, %d over 10 ms", list[i].label, s.total, s.n, s.max, s.over10))
    end
    table.sort(list, function(a, b) return a.s.over10 > b.s.over10 end)
    if list[1].s.over10 > 0 then
        CUI:Print("|cFFFFD100Most calls over 10 ms (the stutters):|r")
        for i = 1, math.min(5, #list) do
            local s = list[i].s
            if s.over10 > 0 then
                CUI:Print(string.format("  %s: %d over 10 ms, %d over 50 ms, max %.0f ms", list[i].label, s.over10, s.over50, s.max))
            end
        end
    end
end
function P.Reset() wipe(stats) end
