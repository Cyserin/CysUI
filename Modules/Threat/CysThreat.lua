--------------------------------------------------------------------------------
-- Cys's UI - threat bar, group threat list and pull warning
--
-- Threat bar: a flat bar under the middle of your screen that shows how much threat you have on your target.
--   * Damage dealer: green when you are safe, yellow when you are close to pulling it, red when it is on you.
--   * Tank: the colors flip - red when you are about to lose it, green when you hold it.
-- Group threat list: everyone in your group (or raid) on your target's threat list, highest first, in class
--   colors. Your own line is always shown. Only while you are in a group and fighting.
-- Pull warning: a big note in the middle of the screen (and a sound) when your threat passes a set percent of
--   what it takes to pull your target off the tank. Skipped for tanks unless you want it.
--
-- WoW Forever: the game hides ("secret") threat numbers on bosses during an encounter. A secret number can
-- still fill a bar and show as text, so the list keeps working there, but it can't be sorted (it stays in
-- group order, tanks first). The pull warning then uses the game's own threat step instead ("you have more
-- threat than the tank"), which stays readable for you on your own target.
-- Settings: /cui -> Threat Bar. Move the pieces in /cui layout.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, max, min = math.floor, math.max, math.min

local DEFAULTS = {
    role = "auto",      -- auto / tank / dps
    bar = true,         -- show the bar for my own threat
    onlyGroup = false,  -- only show when you are in a group
    showNumber = true,  -- the percent on the bar
    hideIdle = true,    -- hide when your target has no threat on you
    width = 220,
    height = 16,
    list = true,        -- group threat list
    listSolo = false,   -- ... also when not in a group
    listRows = 5,
    listPets = false,   -- pets on the list
    warn = true,        -- pull warning
    warnPct = 90,
    warnSound = true,
    warnTank = false,   -- warn tanks too
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.threat = CysUIDB.threat or {}
    local db = CysUIDB.threat
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local frame, fill, label
local sample   -- when set, the example is showing: { pct, status }

local function IsTank()
    local role = DB().role
    if role == "tank" then return true end
    if role == "dps" then return false end
    -- Automatic: the same role the nameplates work out (group role in a group; solo: Protection talents,
    -- Bear Form or Rockbiter Weapon)
    local NP = CUI.Nameplates
    if NP and NP.autoRole then return NP.autoRole == "tank" end
    if UnitGroupRolesAssigned then
        return UnitGroupRolesAssigned("player") == "TANK"
    end
    return false
end

-- WoW Forever can hand any of these back as a locked ("secret") value. Plain() turns a locked value into nil and
-- Flag() a locked true/false into false, so nothing below tests or does math on one. On Era both pass through.
local Plain, Flag, Secret = CysUICompat.Plain, CysUICompat.Flag, CysUICompat.Secret

local function HostileTarget()
    return Flag(UnitExists("target")) and Flag(UnitCanAttack("player", "target")) and not Flag(UnitIsDead("target"))
end

-- returns percent (0-100 or nil), status (0-3 or nil), tanking (bool)
local function Read()
    if not HostileTarget() then return nil end
    if UnitDetailedThreatSituation then
        local tanking, status, scaled = UnitDetailedThreatSituation("player", "target")
        tanking, status, scaled = Flag(tanking), Plain(status), Plain(scaled)
        if status ~= nil or scaled ~= nil then
            return scaled, status or 0, tanking
        end
    end
    if UnitThreatSituation then
        local status = Plain(UnitThreatSituation("player", "target"))
        if status ~= nil then return nil, status, status >= 2 end
    end
    -- last resort: is the target looking at me
    local tt = Flag(UnitExists("targettarget")) and Flag(UnitIsUnit("targettarget", "player"))
    return nil, tt and 3 or 0, tt and true or false
end

--------------------------------------------------------------------------------
-- Pull warning
--------------------------------------------------------------------------------
local warnFrame, warnText
local warnEnds = 0
local armed, lastMob = true, nil

local function BuildWarn()
    if warnFrame then return end
    warnFrame = CreateFrame("Frame", "CysThreatWarnFrame", UIParent)
    warnFrame:SetSize(320, 34)
    warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    warnFrame:SetFrameStrata("HIGH")
    warnText = warnFrame:CreateFontString(nil, "OVERLAY")
    warnText:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
    warnText:SetPoint("CENTER")
    warnText:SetTextColor(1, 0.3, 0.2)
    warnFrame:Hide()
    warnFrame:SetScript("OnUpdate", function(self)
        local left = warnEnds - GetTime()
        if left <= 0 then self:Hide() return end
        self:SetAlpha(left < 0.6 and left / 0.6 or 1)
    end)
    CUI:RegisterMovable(warnFrame, "pullwarn", "Pull Warning", { point = "CENTER", x = 0, y = 150 })
end

local function ShowWarn(pct)
    BuildWarn()
    if pct then
        warnText:SetFormattedText("Pull warning - %d%% threat", floor(pct + 0.5))
    else
        warnText:SetText("Pull warning - more threat than the tank")
    end
    warnEnds = GetTime() + 2.5
    warnFrame:SetAlpha(1)
    warnFrame:Show()
    if DB().warnSound and PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end

-- pct / status / tanking: what Read() gave for me on my target
local function CheckWarn(pct, status, tanking)
    local db = DB()
    if not db.warn or not IsInGroup() or status == nil then return end
    if not db.warnTank and IsTank() then return end
    local mob = Plain(UnitGUID("target"))
    if mob ~= lastMob then lastMob, armed = mob, true end
    local over
    if pct then
        over = pct >= db.warnPct
        if pct < db.warnPct - 15 then armed = true end
    else
        -- no number: step 1 = more threat than the tank but not pulled yet
        over = status == 1
        if status == 0 then armed = true end
    end
    if tanking then armed = false return end -- it's on me already; the bar says so
    if over and armed then
        armed = false
        ShowWarn(pct)
    end
end

--------------------------------------------------------------------------------
-- Group threat list
--------------------------------------------------------------------------------
local list, listHead, rows = nil, nil, {}
local listSample
local ROW_H = 16
local MAX_ROWS = 10

local entries, pool = {}, {}

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    class = Plain(class)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6 -- pets
end

local function Collect()
    wipe(entries)
    local db = DB()
    local secretSeen = false
    local function Add(unit, order)
        if not Flag(UnitExists(unit)) then return end
        local ok, tanking, _, scaled, _, raw = pcall(UnitDetailedThreatSituation, unit, "target")
        if not ok then return end
        local secret = Secret(scaled)
        if not secret and scaled == nil then return end -- not on this mob's threat list
        if secret then secretSeen = true end
        local e = tremove(pool) or {}
        e.unit, e.scaled, e.secret, e.order = unit, scaled, secret, order
        e.raw = Plain(raw) or 0
        e.tanking = Flag(tanking)
        e.tankRole = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "TANK" or false
        e.player = Flag(UnitIsUnit(unit, "player"))
        entries[#entries + 1] = e
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            Add("raid" .. i, i)
            if db.listPets then Add("raidpet" .. i, 100 + i) end
        end
    else
        Add("player", 0)
        if db.listPets then Add("pet", 100) end
        for i = 1, GetNumSubgroupMembers() do
            Add("party" .. i, i)
            if db.listPets then Add("partypet" .. i, 100 + i) end
        end
    end
    if secretSeen then
        -- secret numbers can't be compared: tanks first, then group order
        table.sort(entries, function(a, b)
            local ta, tb = a.tanking or a.tankRole, b.tanking or b.tankRole
            if ta ~= tb then return ta end
            return a.order < b.order
        end)
    else
        table.sort(entries, function(a, b)
            if a.scaled ~= b.scaled then return a.scaled > b.scaled end
            if a.raw ~= b.raw then return a.raw > b.raw end
            return a.order < b.order
        end)
    end
    return secretSeen
end

local function Recycle()
    for i = #entries, 1, -1 do pool[#pool + 1] = entries[i]; entries[i] = nil end
end

local function MakeRow(i)
    local r = CreateFrame("StatusBar", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -18 - (i - 1) * (ROW_H + 1))
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -18 - (i - 1) * (ROW_H + 1))
    r:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    r:SetMinMaxValues(0, 100)
    W.Texture(r, "BACKGROUND", { 1, 1, 1, 0.05 }):SetAllPoints()
    r.role = r:CreateTexture(nil, "OVERLAY")
    r.role:SetSize(12, 12)
    r.role:SetPoint("LEFT", 3, 0)
    r.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    r.role:SetTexCoord(0, 19 / 64, 22 / 64, 41 / 64)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    r.name:SetPoint("LEFT", 18, 0)
    r.name:SetJustifyH("LEFT")
    r.pct = r:CreateFontString(nil, "OVERLAY")
    r.pct:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    r.pct:SetPoint("RIGHT", -4, 0)
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -4, 0)
    r.mark = W.Texture(r, "OVERLAY", { T.accent[1], T.accent[2], T.accent[3], 1 })
    r.mark:SetPoint("TOPLEFT", -1, 0); r.mark:SetPoint("BOTTOMLEFT", -1, 0); r.mark:SetWidth(2)
    rows[i] = r
    return r
end

local function BuildList()
    if list then return end
    list = CreateFrame("Frame", "CysThreatListFrame", UIParent)
    list:SetSize(200, 18 + 5 * (ROW_H + 1))
    list:SetPoint("CENTER", UIParent, "CENTER", 360, -120)
    list:SetFrameStrata("MEDIUM")
    W.Texture(list, "BACKGROUND", { 0.08, 0.085, 0.1, 0.85 }):SetAllPoints()
    W.Border(list, 1, T.border, "BORDER")
    listHead = list:CreateFontString(nil, "OVERLAY")
    listHead:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    listHead:SetPoint("TOPLEFT", 5, -3)
    listHead:SetPoint("TOPRIGHT", -5, -3)
    listHead:SetJustifyH("LEFT")
    listHead:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    local line = W.Texture(list, "BORDER", T.line)
    line:SetPoint("TOPLEFT", 1, -16); line:SetPoint("TOPRIGHT", -1, -16); line:SetHeight(1)
    list:Hide()
    CUI:RegisterMovable(list, "threatlist", "Group Threat", { point = "CENTER", x = 360, y = -120, resizable = true, minW = 140 })
end

local function FillRow(r, name, nr, ng, nb, value, secret, tank, mine)
    r:SetStatusBarColor(nr, ng, nb, 0.75)
    r:SetValue(value)
    if secret then r.pct:SetFormattedText("%.0f%%", value)
    else r.pct:SetFormattedText("%d%%", floor(value + 0.5)) end
    r.name:SetText(name)
    r.role:SetShown(tank)
    r.name:SetPoint("LEFT", tank and 18 or 5, 0)
    r.mark:SetShown(mine)
    r:Show()
end

local SAMPLE_LIST = {
    { "Tank", "WARRIOR", 100, true }, { "You", nil, 92, false, true }, { "Mage", "MAGE", 71 },
    { "Rogue", "ROGUE", 58 }, { "Healer", "SHAMAN", 24 },
}

local function UpdateList()
    if not list then return end
    local db = DB()
    if not db.list then list:Hide() return end
    local shown = 0
    if listSample then
        listHead:SetText("Example mob")
        for i, s in ipairs(SAMPLE_LIST) do
            if i > db.listRows then break end
            local r = rows[i] or MakeRow(i)
            local cr, cg, cb
            if s[2] then local c = RAID_CLASS_COLORS[s[2]]; cr, cg, cb = c.r, c.g, c.b
            else cr, cg, cb = ClassColor("player") end
            FillRow(r, s[1], cr, cg, cb, s[3], false, s[4], s[5])
            shown = i
        end
    else
        if not (IsInGroup() or db.listSolo) or not HostileTarget() or not UnitDetailedThreatSituation then list:Hide() return end
        local secret = Collect()
        local n = min(#entries, db.listRows)
        -- my own line always shows: swap it into the last row when it would be cut off
        local mine
        for i, e in ipairs(entries) do if e.player then mine = i break end end
        if mine and mine > n and n > 0 then entries[n], entries[mine] = entries[mine], entries[n] end
        for i = 1, n do
            local e = entries[i]
            local r = rows[i] or MakeRow(i)
            local cr, cg, cb = ClassColor(e.unit)
            FillRow(r, UnitName(e.unit), cr, cg, cb, e.scaled, e.secret, e.tanking or (secret and e.tankRole), e.player)
        end
        shown = n
        Recycle()
        if shown == 0 then list:Hide() return end
        listHead:SetText((UnitName("target")))
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    list:SetHeight(18 + shown * (ROW_H + 1))
    list:Show()
end

--------------------------------------------------------------------------------
-- Threat bar
--------------------------------------------------------------------------------
local STATUS_TEXT = { [0] = "Safe", [1] = "Gaining", [2] = "Close", [3] = "Tanking" }

local function UpdateBar(pct, status, tanking)
    if not frame then return end
    local db = DB()
    if sample then
        pct, status, tanking = sample.pct, sample.status, sample.status >= 3
    else
        if not db.bar then frame:Hide() return end
        if db.onlyGroup and not IsInGroup() then frame:Hide() return end
        if status == nil then frame:Hide() return end
        if db.hideIdle and status == 0 and (not pct or pct <= 0) then frame:Hide() return end
    end
    local value
    if pct then value = max(0, min(100, pct))
    else value = ({ [0] = 8, [1] = 55, [2] = 85, [3] = 100 })[status] or 0 end
    if tanking then value = 100 end

    local tank = IsTank()
    local r, g, b
    if tank then
        if tanking then r, g, b = 0.3, 0.85, 0.35
        elseif value >= 80 then r, g, b = 1, 0.35, 0.25
        else r, g, b = 1, 0.8, 0.2 end
    else
        if tanking then r, g, b = 1, 0.25, 0.2
        elseif value >= 80 then r, g, b = 1, 0.65, 0.2
        elseif value >= 50 then r, g, b = 1, 0.9, 0.25
        else r, g, b = 0.3, 0.85, 0.35 end
    end
    fill:SetColorTexture(r, g, b, 0.9)
    -- our own frame's width can come back locked on Forever: fall back to the saved width
    local fw = Plain(frame:GetWidth()) or db.width
    fill:SetWidth(max(1, (fw - 2) * value / 100))
    if pct and db.showNumber then
        label:SetText(string.format("%s  %d%%", tanking and (tank and "Tanking" or "Aggro") or "Threat", floor(value + 0.5)))
    else
        label:SetText(tank and tanking and "Tanking" or (STATUS_TEXT[status] or ""))
    end
    frame:Show()
end

local function Update()
    local pct, status, tanking = Read()
    UpdateBar(pct, status, tanking)
    UpdateList()
    if not sample then CheckWarn(pct, status, tanking) end
end
Update = CysUICompat.Guard("Threat", Update) -- WoW Forever: a locked value skips one update instead of erroring

local function Build()
    if frame then return end
    local db = DB()
    frame = CreateFrame("Frame", "CysThreatFrame", UIParent)
    frame:SetSize(db.width, db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    frame:SetFrameStrata("MEDIUM")
    W.Texture(frame, "BACKGROUND", { 0.08, 0.085, 0.1, 0.85 }):SetAllPoints()
    W.Border(frame, 1, T.border, "BORDER")
    fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(0.3, 0.85, 0.35, 0.9)
    fill:SetWidth(1)
    label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    label:SetPoint("CENTER")
    frame:Hide()
    CUI:RegisterMovable(frame, "threat", "Threat Bar", { point = "CENTER", x = 0, y = -170, resizable = true, minW = 100 })
    BuildList()
    BuildWarn()
end

local ev
local function Enable()
    if ev then return end
    Build()
    ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function() Update() end)
    -- the threat events are patchy on Classic, so look a few times a second as well
    C_Timer.NewTicker(0.25, Update)
end

local function Example()
    Build()
    local steps = { { 20, 0 }, { 55, 1 }, { 88, 2 }, { 100, 3 } }
    local i = 0
    local tick
    listSample = true
    tick = C_Timer.NewTicker(0.6, function()
        i = i + 1
        local s = steps[i]
        if s then sample = { pct = s[1], status = s[2] } else sample = nil; listSample = nil; tick:Cancel() end
        if i == 3 and DB().warn then ShowWarn(92) end
        Update()
    end, #steps + 1)
end

CUI:RegisterModule({
    key = "threat",
    name = "Threat Bar",
    defaultOff = true, -- the nameplates already color by threat; tick it on if you want the bar too
    addon = "CysUI",
    desc = "A bar for your threat on your target (colors flip for tanks), a group threat list and a pull warning. Move them in /cui layout.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Threat Bar") end,
})

CUI:RegisterPage("Threat Bar", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Threat", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34); intro:SetWidth(width - 8); intro:SetJustifyV("TOP"); intro:SetSpacing(3)
    intro:SetText("Your threat on your target, the whole group's threat and a warning before you pull. Move and resize them with /cui layout.")

    local y = -76
    local dd = W.Dropdown(page, 220, { { "auto", "Colors for: Automatic" }, { "tank", "Colors for: Tank" }, { "dps", "Colors for: Damage dealer" } },
        function() return db.role end, function(v) db.role = v; Update() end)
    dd:SetPoint("TOPLEFT", 4, y); y = y - 36
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on; Update() end)
        c:SetPoint("TOPLEFT", 4, y); y = y - 26
    end
    local function Sub(text)
        y = y - 6
        W.Header(page, text, width):SetPoint("TOPLEFT", 0, y)
        y = y - 32
    end

    Sub("Threat bar")
    Check("Show the bar for my threat", "bar")
    Check("Hide the bar when my target has no threat on me", "hideIdle")
    Check("Only show it when I am in a group", "onlyGroup")
    Check("Show the percent number", "showNumber")

    Sub("Group threat list")
    Check("Show the group threat list", "list")
    Check("Also show it when I am not in a group", "listSolo")
    Check("List pets too", "listPets")
    W.Stepper(page, "Lines", function() return db.listRows end, function(v) db.listRows = v; Update() end, 2, MAX_ROWS, 1)
        :SetPoint("TOPLEFT", 4, y)
    y = y - 34

    Sub("Pull warning")
    Check("Warn me before I pull my target off the tank", "warn")
    Check("Play a sound with the warning", "warnSound")
    Check("Warn me while I am the tank too", "warnTank")
    W.Stepper(page, "Warn at", function() return db.warnPct end, function(v) db.warnPct = v end, 50, 100, 5, "%")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 40

    local test = W.Button(page, 150, 22, "Show an example", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", Example)
    W.Notes(page, 4, y - 40, width, "", {
        "Automatic uses your group role while you are in a group. Solo (or with no role set) it counts you as a tank with most talent points in Protection (Warrior, Paladin), in Bear Form, or with Rockbiter Weapon on (Shaman), the same as the nameplates.",
        "Damage dealer: green is safe, yellow is getting close, red means the mob is on you. Tank: green means you hold it, red means you are about to lose it.",
        "The percent is how close you are to pulling: 100% means the mob comes for you (the tank shows 100%). Melee pull at 110% of the tank's threat, ranged at 130%; the game works that out for you.",
        "The group list shows only in a group while someone has threat on your target. Your own line is always on it, marked in gold.",
        "WoW Forever hides threat numbers on bosses during a fight. The list still shows everyone's bar but in group order (tanks first), and the pull warning fires when the game says you have more threat than the tank.",
        "Some Classic clients only report a four-step status instead of a percent. Then the bar shows Safe, Gaining, Close or Tanking.",
    })
end)
