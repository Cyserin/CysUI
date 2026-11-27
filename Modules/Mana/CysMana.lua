--------------------------------------------------------------------------------
-- Cys's Mana Tick - the five-second rule and druid mana
--
--   * A spark runs along your mana bar: gold for the five seconds after you spend mana (no spirit regen yet),
--     then white, once per regen tick (every two seconds) while your mana is not full. Shows on Cys's player
--     frame, on Cys's Resource Bar, or both.
--   * Druids: while in Bear or Cat Form a thin blue bar under the player frame shows your mana and how many
--     times you can shift back into the form.
--
-- Only your own mana is read. The spark never measures a bar: it rides the end of a hidden bar of our own.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "manatick", name = "Cys's Mana Tick",
    desc = "A spark on your mana bar for the five-second rule (gold) and each regen tick after it (white). Druids also get their mana while shifted, with how many shifts are left.",
    open = function() CysUI:OpenConfig("Mana Tick") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local Secret = CysUICompat and CysUICompat.Secret or function() return false end

CysUIDB.manatick = CysUIDB.manatick or {}
local db = CysUIDB.manatick
local DEFAULTS = { spark = true, where = "player", ticks = true, druid = true, druidText = true }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local RULE, TICK = 5, 2
local _, CLASS = UnitClass("player")

--------------------------------------------------------------------------------
-- Reading your mana
--------------------------------------------------------------------------------
local lastMana, lastSpend, lastTick = nil, 0, nil
local function Mana()
    local cur, mx = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    if Secret(cur) or Secret(mx) then return nil end
    return cur, mx
end
local function UsesMana()
    local pt = UnitPowerType("player")
    if Secret(pt) then return false end
    return pt == MANA
end

--------------------------------------------------------------------------------
-- Sparks: one per bar it sits on. Each is a hidden StatusBar over the target; the spark rides its fill edge.
--------------------------------------------------------------------------------
local sparks = {}
local function MakeSpark(target)
    local s = CreateFrame("StatusBar", nil, target)
    s:SetAllPoints(target)
    s:SetFrameLevel(target:GetFrameLevel() + 3)
    s:SetStatusBarTexture(FLAT)
    s:GetStatusBarTexture():SetAlpha(0)
    s:SetMinMaxValues(0, 1)
    s.line = s:CreateTexture(nil, "OVERLAY")
    s.line:SetTexture(FLAT)
    s.line:SetWidth(2)
    s.line:SetPoint("TOP", s:GetStatusBarTexture(), "TOPRIGHT", 0, 1)
    s.line:SetPoint("BOTTOM", s:GetStatusBarTexture(), "BOTTOMRIGHT", 0, -1)
    s:Hide()
    return s
end

local function Targets()
    local list = {}
    local pf = _G.CysUIPlayerFrame
    local rb = _G.CysResourceBar
    if (db.where == "player" or db.where == "both") and pf and pf.power then list[#list + 1] = pf.power end
    if (db.where == "resource" or db.where == "both") and rb then list[#list + 1] = rb end
    if #list == 0 and db.where == "player" and rb then list[1] = rb end -- no player frame: the resource bar
    return list
end

local function AttachSparks()
    for _, s in pairs(sparks) do s:Hide(); s.used = false end
    if not db.spark then return end
    for _, target in ipairs(Targets()) do
        sparks[target] = sparks[target] or MakeSpark(target)
        sparks[target].used = true
    end
end

local driver = CreateFrame("Frame")
local function SparkUpdate()
    local now = GetTime()
    local cur, mx = Mana()
    local frac, r, g, b, a
    if cur and mx and mx > 0 and UsesMana() then
        local since = now - lastSpend
        if since < RULE then
            frac, r, g, b, a = since / RULE, T.accent[1], T.accent[2], T.accent[3], 1
        elseif db.ticks and cur < mx then
            local base = lastTick or (lastSpend + RULE)
            frac, r, g, b, a = ((now - base) % TICK) / TICK, 1, 1, 1, 0.75
        end
    end
    for _, s in pairs(sparks) do
        if s.used and frac and s:GetParent():IsVisible() then
            s:SetValue(frac)
            s.line:SetVertexColor(r, g, b, a)
            s:Show()
        else
            s:Hide()
        end
    end
    if not frac then driver:Hide() end
end
driver:SetScript("OnUpdate", SparkUpdate)
driver:Hide()

local function Wake()
    if db.spark and next(sparks) then driver:Show() end
end

--------------------------------------------------------------------------------
-- Druid mana while shifted
--------------------------------------------------------------------------------
local dm
local function FormCost()
    if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
    local form = GetShapeshiftForm()
    if not form or form == 0 then return nil end
    local _, _, _, spellID = GetShapeshiftFormInfo(form)
    if not spellID then return nil end
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not get then return nil end
    local ok, costs = pcall(get, spellID)
    if not ok or type(costs) ~= "table" then return nil end
    for _, c in ipairs(costs) do
        if c.type == MANA and type(c.cost) == "number" and not Secret(c.cost) and c.cost > 0 then return c.cost end
    end
    return nil
end

local function BuildDruid()
    if dm then return dm end
    dm = CreateFrame("Frame", "CysDruidManaBar", UIParent)
    dm:SetSize(200, 9)
    W.Texture(dm, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 }):SetAllPoints()
    dm.bar = CreateFrame("StatusBar", nil, dm)
    dm.bar:SetPoint("TOPLEFT", 1, -1)
    dm.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    dm.bar:SetStatusBarTexture(FLAT)
    local c = PowerBarColor and PowerBarColor.MANA
    dm.bar:SetStatusBarColor(c and c.r or 0.3, c and c.g or 0.5, c and c.b or 1)
    local top = CreateFrame("Frame", nil, dm)
    top:SetAllPoints()
    top:SetFrameLevel(dm.bar:GetFrameLevel() + 1)
    W.Border(top, 1, T.border, "OVERLAY")
    dm.text = top:CreateFontString(nil, "OVERLAY")
    dm.text:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
    dm.text:SetPoint("RIGHT", dm, "BOTTOMRIGHT", -3, -6)
    dm.text:SetJustifyH("RIGHT")
    local pf = _G.CysUIPlayerFrame
    if pf then
        dm:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, -2)
        dm:SetPoint("TOPRIGHT", pf, "BOTTOMRIGHT", 0, -2)
    else
        dm:SetPoint("CENTER", UIParent, "CENTER", -260, -190)
        CUI:RegisterMovable(dm, "druidmana", "Druid Mana", { point = "CENTER", x = -260, y = -190 })
    end
    dm:Hide()
    return dm
end

local function UpdateDruid()
    if CLASS ~= "DRUID" then return end
    if not db.druid or UsesMana() then if dm then dm:Hide() end return end
    BuildDruid()
    local cur, mx = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    pcall(dm.bar.SetMinMaxValues, dm.bar, 0, mx)
    pcall(dm.bar.SetValue, dm.bar, cur)
    if db.druidText then
        if Secret(cur) or Secret(mx) then
            pcall(dm.text.SetFormattedText, dm.text, "%s", cur)
        else
            local cost = FormCost()
            if cost then
                local n = math.floor(cur / cost)
                dm.text:SetFormattedText("%d  |cFFFFD100%d %s|r", cur, n, n == 1 and "shift" or "shifts")
            else
                dm.text:SetFormattedText("%d / %d", cur, mx)
            end
        end
        dm.text:Show()
    else
        dm.text:Hide()
    end
    dm:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXPOWER", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_DISPLAYPOWER", "player")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, _, powerType)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function() AttachSparks(); Wake(); UpdateDruid() end)
        lastMana = Mana()
        return
    end
    if event == "UNIT_POWER_UPDATE" and powerType ~= nil and powerType ~= "MANA" then
        if CLASS == "DRUID" then UpdateDruid() end
        return
    end
    local cur = Mana()
    if cur and lastMana then
        local now = GetTime()
        if cur < lastMana then
            lastSpend = now
        elseif cur > lastMana and now - lastSpend >= RULE then
            lastTick = now -- a regen tick: later ticks are timed from here
        end
    end
    if cur then lastMana = cur end
    Wake()
    UpdateDruid()
end)

CUI.ManaTickRefresh = function() AttachSparks(); Wake(); UpdateDruid() end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Mana Tick", function(page)
    local width = 480
    W.Header(page, "Mana Tick", width):SetPoint("TOPLEFT", 0, -4)
    local y = -36
    local function Check(text, key)
        W.Checkbox(page, text, function() return db[key] end, function(v) db[key] = v; CUI.ManaTickRefresh() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Spark on the mana bar (five-second rule)", "spark")
    Check("Keep the spark running for each regen tick after it", "ticks")
    y = y - 6
    local lab = W.Text(page, 12, T.accent)
    lab:SetPoint("TOPLEFT", 4, y - 4)
    lab:SetText("Show on")
    W.Dropdown(page, 230, { { "player", "player frame" }, { "resource", "Resource Bar" }, { "both", "both" } },
        function() return db.where end, function(v) db.where = v; CUI.ManaTickRefresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 40
    Check("Druids: mana bar under the player frame while in a form", "druid")
    Check("Druids: mana and shifts left on that bar", "druidText")
    y = y - 10
    local note = W.Notes(page, 4, y, width, "", {
        { "Five-second rule", "after you spend mana, spirit regen stops for five seconds. The gold spark runs across the bar in those five seconds; when it reaches the end, regen is back." },
        { "Regen ticks", "mana comes back every two seconds. The white spark reaches the end of the bar when the next tick lands, so you can time a cast just after it." },
        { "Where", "Cys's player frame (Unit Frames module) or Cys's Resource Bar. With neither, nothing is drawn." },
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 100) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
