--------------------------------------------------------------------------------
-- Cys's UI - threat bar
--
-- A flat bar under the middle of your screen that shows how much threat you have on your target.
--   * Damage dealer: green when you are safe, yellow when you are close to pulling it, red when it is on you.
--   * Tank: the colors flip - red when you are about to lose it, green when you hold it.
-- Uses the game's threat numbers when the client has them. If it only has the four-step status, the bar
-- shows that instead (Safe / Gaining / Close / Tanking). Settings: /cui -> Threat Bar. Move it in /cui layout.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, max, min = math.floor, math.max, math.min

local DEFAULTS = {
    role = "auto",      -- auto / tank / dps
    onlyGroup = false,  -- only show when you are in a group
    showNumber = true,  -- the percent on the bar
    hideIdle = true,    -- hide when your target has no threat on you
    width = 220,
    height = 16,
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
    if UnitGroupRolesAssigned then
        return UnitGroupRolesAssigned("player") == "TANK"
    end
    return false
end

-- returns percent (0-100 or nil), status (0-3 or nil), tanking (bool)
local function Read()
    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then return nil end
    if UnitDetailedThreatSituation then
        local tanking, status, scaled = UnitDetailedThreatSituation("player", "target")
        if status ~= nil or scaled ~= nil then
            return scaled, status or 0, tanking and true or false
        end
    end
    if UnitThreatSituation then
        local status = UnitThreatSituation("player", "target")
        if status ~= nil then return nil, status, status >= 2 end
    end
    -- last resort: is the target looking at me
    local tt = UnitExists("targettarget") and UnitIsUnit("targettarget", "player")
    return nil, tt and 3 or 0, tt and true or false
end

local STATUS_TEXT = { [0] = "Safe", [1] = "Gaining", [2] = "Close", [3] = "Tanking" }

local function Update()
    if not frame then return end
    local db = DB()
    local pct, status, tanking
    if sample then
        pct, status, tanking = sample.pct, sample.status, sample.status >= 3
    else
        if db.onlyGroup and not IsInGroup() then frame:Hide() return end
        pct, status, tanking = Read()
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
    fill:SetWidth(max(1, (frame:GetWidth() - 2) * value / 100))
    if pct and db.showNumber then
        label:SetText(string.format("%s  %d%%", tanking and (tank and "Tanking" or "Aggro") or "Threat", floor(value + 0.5)))
    else
        label:SetText(tank and tanking and "Tanking" or (STATUS_TEXT[status] or ""))
    end
    frame:Show()
end

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
    ev:SetScript("OnEvent", Update)
    -- the threat events are patchy on Classic, so look a few times a second as well
    C_Timer.NewTicker(0.25, Update)
end

local function Example()
    Build()
    local steps = { { 20, 0 }, { 55, 1 }, { 88, 2 }, { 100, 3 } }
    local i = 0
    local tick
    tick = C_Timer.NewTicker(0.6, function()
        i = i + 1
        local s = steps[i]
        if s then sample = { pct = s[1], status = s[2] } else sample = nil; tick:Cancel() end
        Update()
    end, #steps + 1)
end

CUI:RegisterModule({
    key = "threat",
    name = "Threat Bar",
    addon = "CysUI",
    desc = "A flat bar showing how much threat you have on your target. Colors flip for tanks. Move it in /cui layout.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Threat Bar") end,
})

CUI:RegisterPage("Threat Bar", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Threat bar", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34); intro:SetWidth(width - 8); intro:SetJustifyV("TOP"); intro:SetSpacing(3)
    intro:SetText("Shows how much threat you have on your target. Move and resize it with /cui layout.")

    local y = -76
    local dd = W.Dropdown(page, 220, { { "auto", "Colors for: Automatic" }, { "tank", "Colors for: Tank" }, { "dps", "Colors for: Damage dealer" } },
        function() return db.role end, function(v) db.role = v; Update() end)
    dd:SetPoint("TOPLEFT", 4, y); y = y - 36
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on; Update() end)
        c:SetPoint("TOPLEFT", 4, y); y = y - 26
    end
    Check("Hide the bar when my target has no threat on me", "hideIdle")
    Check("Only show it when I am in a group", "onlyGroup")
    Check("Show the percent number", "showNumber")
    y = y - 8
    local test = W.Button(page, 150, 22, "Show an example", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", Example)
    W.Notes(page, 4, y - 40, width, "", {
        "Automatic uses your group role (set it in a dungeon group) and counts you as a damage dealer if none is set; pick Tank here if you always tank.",
        "Damage dealer: green is safe, yellow is getting close, red means the mob is on you. Tank: green means you hold it, red means you are about to lose it.",
        "Some Classic clients only report a four-step status instead of a percent. Then the bar shows Safe, Gaining, Close or Tanking.",
    })
end)
