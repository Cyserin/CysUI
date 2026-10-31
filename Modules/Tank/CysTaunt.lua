--------------------------------------------------------------------------------
-- Cys's UI - taunt alert (for tanks)
--
-- Tells you when someone else (a player, or a pet) taunts a mob you were tanking, and when your own taunt
-- is resisted. Works for any class. Settings: /cui -> Taunt Alert. Move it in layout mode.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = { others = true, resisted = true, sound = true }

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.taunt = CysUIDB.taunt or {}
    local db = CysUIDB.taunt
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- Taunt, Growl, Mocking Blow, Challenging Shout, Challenging Roar, Righteous Defense, Distracting Shot
local TAUNT_IDS = { 355, 6795, 694, 1161, 5209, 31789, 20736 }
local TAUNTS = {}
local FALLBACK = { "Taunt", "Growl", "Mocking Blow", "Challenging Shout", "Challenging Roar", "Righteous Defense", "Distracting Shot" }
for i, id in ipairs(TAUNT_IDS) do
    TAUNTS[(GetSpellInfo and GetSpellInfo(id)) or FALLBACK[i]] = true
end
for _, n in ipairs(FALLBACK) do TAUNTS[n] = true end

local lastAlert = 0
local tanked = {}      -- mob guid -> last time it was attacking me
local frame, text

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "CysTauntFrame", UIParent)
    frame:SetSize(360, 30)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    frame:SetFrameStrata("HIGH")
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    text:SetPoint("CENTER")
    frame:Hide()
    CUI:RegisterMovable(frame, "taunt", "Taunt Alert", { point = "CENTER", x = 0, y = 200 })
    frame:SetScript("OnUpdate", function(self, e)
        self.t = (self.t or 0) + e
        if self.t > 3.5 then self:Hide() elseif self.t > 2.5 then self:SetAlpha(3.5 - self.t) end
    end)
end

local function Show(msg, r, g, b)
    Build()
    text:SetText(msg)
    text:SetTextColor(r, g, b)
    frame.t = 0
    frame:SetAlpha(1)
    frame:Show()
    if DB().sound and PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end
CUI.ShowTauntAlert = Show

-- remember which mobs are on me (so only mobs you were tanking raise an alert)
local function ScanTanked()
    local now = GetTime()
    local function Look(unit)
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
            local tt = unit .. "target"
            if UnitExists(tt) and UnitIsUnit(tt, "player") then
                local g = UnitGUID(unit)
                if g then tanked[g] = now end
            end
        end
    end
    Look("target"); Look("focus"); Look("mouseover")
    for i = 1, 40 do Look("nameplate" .. i) end
    for g, t in pairs(tanked) do
        if now - t > 15 then tanked[g] = nil end
    end
end

local function OnCombatLog()
    local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, _, _, _, spellName, _, miss = CombatLogGetCurrentEventInfo()
    if not spellName or not TAUNTS[spellName] then return end
    local db = DB()
    local mine = sGUID == UnitGUID("player")
    if sub == "SPELL_MISSED" and mine and db.resisted then
        Show(string.format("Your %s missed %s (%s)", spellName, dName or "the target", tostring(miss or "missed"):lower()), 1, 0.4, 0.2)
        return
    end
    if mine or not db.others then return end
    if sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_AURA_APPLIED" then return end
    if bit.band(sFlags or 0, 0x7) == 0 then return end        -- not someone in my group
    local single = dGUID and dGUID ~= "" and dGUID ~= "0x0000000000000000" and dName and dName ~= "nil"
    if single and not tanked[dGUID] and UnitGUID("target") ~= dGUID then return end
    local now = GetTime()
    if now - lastAlert < 1 then return end                   -- cast and aura events arrive together
    lastAlert = now
    local who = sName or "Someone"
    if single then
        Show(string.format("%s taunted %s!", who, dName), 1, 0.85, 0.1)
    else
        Show(string.format("%s used %s!", who, spellName), 1, 0.85, 0.1)
    end
end

local ev
local function Enable()
    if ev then return end
    Build()
    ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:SetScript("OnEvent", OnCombatLog)
    C_Timer.NewTicker(0.5, ScanTanked)
end

CUI:RegisterModule({
    key = "taunt",
    name = "Taunt Alert",
    addon = "CysUI",
    desc = "Tells you when someone else (or a pet) taunts a mob you were tanking, and when your own taunt is resisted. Works for every class.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Taunt Alert") end,
})

CUI:RegisterPage("Taunt Alert", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Taunt alert", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("A message across the screen when another tank, a Hunter pet or a Druid taunts a mob that was on you, so you know why you lost it. Move it with /cui layout.")

    local y = -96
    local function Check(label, key)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Tell me when someone else taunts a mob I was tanking", "others")
    Check("Tell me when my own taunt is resisted or misses", "resisted")
    Check("Play a sound", "sound")

    y = y - 8
    local test = W.Button(page, 150, 22, "Show an example", true)
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", function() Show("Shatank taunted Defias Pillager!", 1, 0.85, 0.1) end)

    W.Notes(page, 4, y - 40, width, "", {
        "It only reacts to mobs that were attacking you in the last 15 seconds, or your current target.",
        "Taunts it knows: Taunt, Growl (pets too), Mocking Blow, Challenging Shout and Roar, Righteous Defense, Distracting Shot.",
    })
end)
