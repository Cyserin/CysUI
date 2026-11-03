--------------------------------------------------------------------------------
-- Cys's UI - combat numbers
--
-- Floating numbers that rise from your own unit frames instead of the game's default ones:
--   * on your player frame: damage you take, healing you receive, and the attacks you avoid
--     (Miss, Dodge, Parry, Block, Resist, Immune, Absorb, Reflect)
--   * on your target frame: your damage (and your pet's), your heals on others, and your own misses
-- Crits pop in bigger. Settings: /cui -> Combat Numbers.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local band = bit.band
local floor, max, min = math.floor, math.max, math.min

local DEFAULTS = {
    incoming = true,     -- damage taken, on the player frame
    healsIn = true,      -- healing received, on the player frame
    avoid = true,        -- Miss / Dodge / Parry / Block ... when an enemy attack fails to hit you
    outgoing = true,     -- your damage, on the target frame
    outHeals = true,     -- your heals on other people, on the target frame
    myMisses = true,     -- your own attacks that miss, dodge, parry...
    pets = true,         -- pet damage (smaller)
    hideBlizzard = true, -- turn the game's own floating numbers off
    size = 20,
    inPlace = false,     -- pop and fade where they appear instead of rising (for numbers placed on the frames)
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.combatText = CysUIDB.combatText or {}
    local db = CysUIDB.combatText
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- the game's own numbers
-- the game's own numbers: direct hits, heals, misses, plus the ones that slipped through before
-- (damage over time, and pet / totem damage)
local CVARS = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing", "floatingCombatTextDodgeParryMiss",
    "floatingCombatTextCombatLogPeriodicSpells", "floatingCombatTextPetMeleeDamage", "floatingCombatTextPetSpellDamage",
    "floatingCombatTextCombatDamageAllAutos" }
local function ApplyBlizzard()
    local db = DB()
    db.cvarBackup = db.cvarBackup or {}
    for _, name in ipairs(CVARS) do
        if db.hideBlizzard then
            local ok, cur = pcall(GetCVar, name)
            if ok and cur ~= nil and db.cvarBackup[name] == nil then db.cvarBackup[name] = cur end
            pcall(SetCVar, name, "0")
        elseif db.cvarBackup[name] ~= nil then
            pcall(SetCVar, name, db.cvarBackup[name])
            db.cvarBackup[name] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Floating entries
--------------------------------------------------------------------------------
local MAX_ENTRIES = 70
local pool, active = {}, {}
local driver
local laneCount = {}

local STAGGER = { 0, -16, 16, -32, 32 }

-- Numbers rise inside two boxes you can move in layout mode ("Combat Numbers: you" / "...: target").
-- Until they are set up, they rise from the top of the player / target frame.
local holders = {}
local function UnitFrameFor(lane)
    local UF = CUI.UnitFrames
    if lane == "out" then return UF and UF.frames and UF.frames.target end
    return UF and UF.frames and UF.frames.player
end
local function Anchor(lane)
    local h = holders[lane == "out" and "out" or "in"]
    if h then return h end
    return UnitFrameFor(lane) or UIParent
end

local HOLDER_W, HOLDER_H = 180, 80
local function MakeHolders()
    if holders["in"] then return end
    local uiScale = UIParent:GetEffectiveScale()
    local function Default(lane, fallbackX)
        -- start just above the matching unit frame, clear of the bars that usually sit on top of it
        local uf = UnitFrameFor(lane)
        if uf and uf.GetCenter and uf:GetCenter() then
            local s = uf:GetEffectiveScale() / uiScale
            local cx, top = uf:GetCenter() * s, uf:GetTop() * s
            return cx - UIParent:GetWidth() / 2, top + 50 + HOLDER_H / 2 - UIParent:GetHeight() / 2
        end
        return fallbackX, -60
    end
    for _, spec in ipairs({ { "in", "combattext_in", "Combat Numbers: you", -260 },
                            { "out", "combattext_out", "Combat Numbers: target", 260 } }) do
        local h = CreateFrame("Frame", "CysCombatNumbers_" .. spec[1], UIParent)
        h:SetSize(HOLDER_W, HOLDER_H)
        local x, y = Default(spec[1], spec[4])
        CUI:RegisterMovable(h, spec[2], spec[3], { point = "CENTER", x = math.floor(x + 0.5), y = math.floor(y + 0.5),
            resizable = true, minW = 60, maxW = 500, minH = 24, maxH = 300 })
        holders[spec[1]] = h
    end
end

local function Acquire()
    for _, e in ipairs(pool) do
        if not e.on then return e end
    end
    if #pool < MAX_ENTRIES then
        local e = CreateFrame("Frame", nil, UIParent)
        e:SetSize(10, 10)
        e:SetFrameStrata("HIGH")
        e.fs = e:CreateFontString(nil, "OVERLAY")
        e.fs:SetPoint("CENTER")
        pool[#pool + 1] = e
        return e
    end
    -- everything is busy: reuse the one that has been up the longest
    local oldest = active[1]
    return oldest
end

local function Spawn(lane, text, r, g, b, opts)
    local db = DB()
    opts = opts or {}
    local e = Acquire()
    if not e then return end
    local size = floor(db.size * (opts.size or 1) + 0.5)
    e.fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    e.fs:SetText(text)
    e.fs:SetTextColor(r, g, b)
    laneCount[lane] = ((laneCount[lane] or 0) % #STAGGER) + 1
    e.lane = lane
    e.anchor = Anchor(lane)
    e.t = 0
    e.dur = opts.dur or 1.25
    e.rise = opts.rise or 55
    e.still = db.inPlace and true or false
    e.y0 = 0
    if e.still then
        -- static style: one number per box, dead centre. A new one replaces the one showing.
        for i = #active, 1, -1 do
            local o = active[i]
            if o ~= e and o.anchor == e.anchor then
                o.on = false
                o:Hide()
                table.remove(active, i)
            end
        end
    end
    e.baseScale = opts.scale or 1
    e.pop = opts.pop or 0.35
    e.x0 = STAGGER[laneCount[lane]] + (opts.x or 0)
    e.drift = (opts.drift or 0)
    if e.still then e.x0, e.drift = 0, 0 end
    e.on = true
    e:SetScale(e.baseScale * (e.still and 1 or (1 + e.pop)))
    e:SetAlpha(e.still and 0 or 1)
    e:Show()
    local seen
    for _, a in ipairs(active) do if a == e then seen = true break end end
    if not seen then active[#active + 1] = e end
    if driver then driver:Show() end
end

local function Step(_, elapsed)
    local n = #active
    if n == 0 then driver:Hide() return end
    for i = n, 1, -1 do
        local e = active[i]
        e.t = e.t + elapsed
        local p = e.t / e.dur
        if p >= 1 then
            e.on = false
            e:Hide()
            table.remove(active, i)
        else
            local rise, x, pop
            if e.still then
                rise, x, pop = e.y0, e.x0, 0
                -- fade in, hold, fade out
                e:SetAlpha(p < 0.12 and (p / 0.12) or (p < 0.6 and 1 or (1 - (p - 0.6) / 0.4)))
            else
                rise = e.rise * (1 - (1 - p) * (1 - p))                 -- eases out
                x = e.x0 + e.drift * p
                pop = e.pop * max(0, 1 - p * 7)                         -- quick pop at the start
                e:SetAlpha(p < 0.55 and 1 or (1 - (p - 0.55) / 0.45))
            end
            local sc = e.baseScale * (1 + pop)
            e:SetScale(sc)
            e:ClearAllPoints()
            if holders["in"] and DB().inPlace then
                e:SetPoint("CENTER", e.anchor, "CENTER", x / sc, rise / sc)          -- pops in the middle of its box
            elseif holders["in"] then
                e:SetPoint("BOTTOM", e.anchor, "BOTTOM", x / sc, (4 + rise) / sc)  -- rises inside its box
            else
                e:SetPoint("BOTTOM", e.anchor, "TOP", x / sc, (6 + rise) / sc)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Combat log
--------------------------------------------------------------------------------
local myGUID
local MISS_LABEL = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist", IMMUNE = "Immune",
                     ABSORB = "Absorb", REFLECT = "Reflect", DEFLECT = "Deflect" }
local MISS_LABEL_OUT = { MISS = "Miss", DODGE = "Dodged", PARRY = "Parried", BLOCK = "Blocked", RESIST = "Resisted", IMMUNE = "Immune",
                         ABSORB = "Absorbed", REFLECT = "Reflected", DEFLECT = "Deflected" }

local function Num(n)
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(floor(n + 0.5))
end

local function OnEvent()
    local db = DB()
    myGUID = myGUID or UnitGUID("player")
    local _, sub, _, sGUID, _, sFlags, _, dGUID, _, dFlags, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21 =
        CombatLogGetCurrentEventInfo()
    local toMe = dGUID == myGUID
    local fromMe = sGUID == myGUID
    local fromPet = not fromMe and sFlags and band(sFlags, 0x1) ~= 0 and band(sFlags, 0x1000) ~= 0
    if not toMe and not fromMe and not fromPet then return end

    -- damage ------------------------------------------------------------------------
    local amount, crit, blocked
    if sub == "SWING_DAMAGE" then amount, blocked, crit = a12, a16, a18
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "DAMAGE_SHIELD" then
        amount, blocked, crit = a15, a19, a21
    elseif sub == "ENVIRONMENTAL_DAMAGE" then amount = a13
    end
    if amount then
        if amount <= 0 then return end
        if toMe then
            if db.incoming then
                local text = "-" .. Num(amount)
                if blocked and blocked > 0 then text = text .. " (" .. Num(blocked) .. " blocked)" end
                if crit then Spawn("in", text .. "!", 1, 0.3, 0.3, { scale = 1.3, pop = 0.5, drift = -20, x = -28, rise = 62 })
                else Spawn("in", text, 1, 0.45, 0.45, { drift = -20, x = -28 }) end
            end
        elseif fromMe and db.outgoing then
            if crit then Spawn("out", Num(amount) .. "!", 1, 0.82, 0.1, { scale = 1.4, pop = 0.55, drift = 24, x = 26, rise = 66 })
            else Spawn("out", Num(amount), 1, 1, 1, { drift = 24, x = 26 }) end
        elseif fromPet and db.outgoing and db.pets then
            Spawn("out", Num(amount), 0.8, 0.8, 0.8, { scale = 0.75, drift = 30, x = 34, rise = 45 })
        end
        return
    end

    -- healing -----------------------------------------------------------------------------
    if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        local eff = (a15 or 0) - (a16 or 0)
        if eff <= 0 then return end
        local hcrit = a18
        if toMe then
            if db.healsIn then
                Spawn("in", "+" .. Num(eff) .. (hcrit and "!" or ""), 0.35, 1, 0.45,
                    { scale = hcrit and 1.3 or 1, pop = hcrit and 0.5 or 0.35, drift = 22, x = 28 })
            end
        elseif fromMe and db.outHeals then
            Spawn("out", "+" .. Num(eff) .. (hcrit and "!" or ""), 0.35, 1, 0.45, { scale = hcrit and 1.3 or 0.9, drift = 24, x = 26 })
        end
        return
    end

    -- attacks that missed -----------------------------------------------------------------------
    local missType
    if sub == "SWING_MISSED" then missType = a12
    elseif sub == "SPELL_MISSED" or sub == "RANGE_MISSED" or sub == "SPELL_PERIODIC_MISSED" then missType = a15 end
    if missType then
        if toMe and db.avoid then
            local label = MISS_LABEL[missType]
            if label then Spawn("avoid", label .. "!", 1, 0.85, 0.2, { scale = 1.25, pop = 0.5, rise = 48, dur = 1.3 }) end
        elseif fromMe and db.myMisses then
            local label = MISS_LABEL_OUT[missType]
            if label then Spawn("out", label, 0.7, 0.7, 0.75, { scale = 0.85, drift = 24, x = 26, rise = 42 }) end
        end
    end
end

local ev
local function Enable()
    if ev then return end
    DB()
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", Step)
    driver:Hide()
    ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            myGUID = UnitGUID("player")
            ApplyBlizzard()
        else
            OnEvent()
        end
    end)
    ApplyBlizzard()
    -- the boxes take their first position from the unit frames, which are placed at login too
    C_Timer.After(1, MakeHolders)
end

local function Example()
    Enable()
    Spawn("in", "-142", 1, 0.45, 0.45, { drift = -20, x = -28 })
    Spawn("avoid", "Dodge!", 1, 0.85, 0.2, { scale = 1.25, pop = 0.5, rise = 48, dur = 1.3 })
    Spawn("in", "+96", 0.35, 1, 0.45, { drift = 22, x = 28 })
    Spawn("out", "211", 1, 1, 1, { drift = 24, x = 26 })
    Spawn("out", "534!", 1, 0.82, 0.1, { scale = 1.4, pop = 0.55, drift = 24, x = 26, rise = 66 })
    Spawn("out", "Parried", 0.7, 0.7, 0.75, { scale = 0.85, drift = 24, x = 26, rise = 42 })
end

CUI:RegisterModule({
    key = "combattext",
    name = "Combat Numbers",
    addon = "CysUI",
    desc = "Floating numbers on your own frames: damage taken, healing received and Miss / Dodge / Parry / Block on the player frame; your damage, heals and misses on the target frame.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Combat Numbers") end,
})

CUI:RegisterPage("Combat Numbers", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Combat numbers", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34); intro:SetWidth(width - 8); intro:SetJustifyV("TOP"); intro:SetSpacing(3)
    intro:SetText("Numbers rise near your player and target frames. Each side has its own box in layout mode (Combat Numbers: you / target), so you can put them anywhere, even right on the frames.")

    local y = -92
    local function Check(label, key, after)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on; if after then after() end end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    W.Header(page, "On the player frame", width):SetPoint("TOPLEFT", 0, y); y = y - 26
    Check("Damage I take", "incoming")
    Check("Healing I receive", "healsIn")
    Check("Attacks I avoid (Miss, Dodge, Parry, Block, Resist...)", "avoid")
    y = y - 6
    W.Header(page, "On the target frame", width):SetPoint("TOPLEFT", 0, y); y = y - 26
    Check("My damage", "outgoing")
    Check("My pet's damage (smaller)", "pets")
    Check("My heals on other people", "outHeals")
    Check("My attacks that miss, are dodged or parried", "myMisses")
    y = y - 6
    W.Header(page, "Look", width):SetPoint("TOPLEFT", 0, y); y = y - 26
    local st = W.Stepper(page, "Text size", function() return db.size end, function(v) db.size = v end, 12, 36, 2, "")
    st:SetPoint("TOPLEFT", 4, y); y = y - 30
    Check("Flash in place: no movement, just fade in and out (good when the boxes sit on the frames)", "inPlace")
    Check("Turn off the game's own floating numbers", "hideBlizzard", ApplyBlizzard)
    y = y - 6
    local test = W.Button(page, 150, 22, "Show an example", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", Example)
    W.Notes(page, 4, y - 40, width, "", {
        "Damage you take and heals you receive show on the left and right of your box; crits pop in bigger with a ! after them.",
        "Use Show an example while layout mode is open to see where they land.",
        "The game's own numbers come back when you untick the last box.",
    })
end)
