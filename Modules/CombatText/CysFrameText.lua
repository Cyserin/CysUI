--------------------------------------------------------------------------------
-- Cys's Frame Combat Text (WoW Forever) - one still number on the player and target frames
--
-- The last hit on you sits in the middle of your player frame, the last hit on your target in the middle of the
-- target frame: a damage number, a heal, or Miss / Dodge / Parry / Block... Nothing floats, scrolls or pops; each
-- new one simply replaces the one before and it clears after a moment.
--
-- WoW Forever hides the combat log from addons, so this uses the per-unit hit event the game still sends
-- (UNIT_COMBAT). The amount can be locked: it goes straight into the text and is never compared or added up.
-- That event does not say who dealt the hit, so the target frame shows every hit your target takes.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "frametext", name = "Frame Combat Text", foreverOnly = true,
    desc = "WoW Forever: the last hit shown as one still number in the middle of your player and target frames - damage, heals, Miss / Dodge / Parry / Block. Nothing floats or scrolls; each new one replaces the last.",
    open = function() CysUI:OpenConfig("Frame Combat Text") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T
local Secret = CysUICompat.Secret

CysUIDB.frameText = CysUIDB.frameText or {}
local db = CysUIDB.frameText
local DEFAULTS = { player = true, target = true, heals = true, misses = true, size = 22, hold = 10 } -- hold: tenths of a second
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

-- what the game calls each result -> the word shown (the game's own translated word when it has one)
local WORDS = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist", IMMUNE = "Immune",
    ABSORB = "Absorb", DEFLECT = "Deflect", REFLECT = "Reflect", EVADE = "Evade" }
local function Word(key)
    if not WORDS[key] then return nil end -- only the results listed above
    local g = _G[key]
    if type(g) == "string" and g ~= "" then return g end
    return WORDS[key]
end

local FADE = 0.2
local texts = {} -- unit -> our text holder on that unit frame

local function Holder(unit)
    local h = texts[unit]
    if h then return h end
    local UF = CUI.UnitFrames
    local frame = UF and UF.frames and UF.frames[unit]
    if not frame then return nil end
    h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameLevel(frame:GetFrameLevel() + 20)
    h.text = h:CreateFontString(nil, "OVERLAY")
    h.text:SetPoint("CENTER", h, "CENTER", 0, 0)
    h:Hide()
    h:SetScript("OnUpdate", function(self, elapsed)
        self.left = self.left - elapsed
        if self.left <= 0 then
            self:Hide()
        elseif self.left < FADE then
            self:SetAlpha(self.left / FADE)
        end
    end)
    texts[unit] = h
    return h
end

-- put one line on a frame; big = a crit / crushing blow
local function Show(unit, r, g, b, big, fmt, value)
    local h = Holder(unit)
    if not h then return end
    h.text:SetFont(STANDARD_TEXT_FONT, math.floor(db.size * (big and 1.35 or 1) + 0.5), "OUTLINE")
    h.text:SetTextColor(r, g, b)
    local ok
    if fmt then
        ok = pcall(h.text.SetFormattedText, h.text, fmt, value) -- the amount goes straight in, locked or not
    else
        ok = pcall(h.text.SetText, h.text, value)
    end
    if not ok then h:Hide() return end
    h.left = db.hold / 10 + FADE
    h:SetAlpha(1)
    h:Show()
end

local function OnHit(unit, action, flag, amount, school)
    if unit ~= "player" and unit ~= "target" then return end
    if not db[unit] then return end
    if type(action) ~= "string" or Secret(action) then return end
    if Secret(flag) then flag = nil end
    local big = flag == "CRITICAL" or flag == "CRUSHING"
    if action == "WOUND" then
        -- a hit that did nothing (fully absorbed, blocked or resisted) arrives as 0 with the reason in the flag
        if not Secret(amount) and amount == 0 then
            local word = flag and Word(flag)
            if word and db.misses then Show(unit, 0.9, 0.9, 0.9, false, nil, word) end
            return
        end
        if unit == "player" then
            Show(unit, 1, 0.25, 0.25, big, "%d", amount)
        elseif not Secret(school) and school == 1 then
            Show(unit, 1, 1, 1, big, "%d", amount)       -- physical
        else
            Show(unit, 1, 0.9, 0.3, big, "%d", amount)   -- spells
        end
    elseif action == "HEAL" then
        if db.heals then Show(unit, 0.3, 1, 0.3, big, "+%d", amount) end
    elseif action ~= "ENERGIZE" then
        local word = Word(action)
        if word and db.misses then Show(unit, 0.9, 0.9, 0.9, false, nil, word) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("UNIT_COMBAT")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        Holder("player"); Holder("target") -- built up front, out of combat
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if texts.target then texts.target:Hide() end -- the old target's number has no place on the new one
        return
    end
    pcall(OnHit, ...)
end)

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Frame Combat Text", function(page)
    local width = 480
    W.Header(page, "Frame Combat Text", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local function Check(label, key)
        W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("On your player frame (hits on you)", "player")
    Check("On the target frame (hits on your target)", "target")
    Check("Show heals", "heals")
    Check("Show Miss, Dodge, Parry, Block and the like", "misses")
    y = y - 4
    W.Stepper(page, "Text size", function() return db.size end, function(v) db.size = v end, 10, 48, 1):SetPoint("TOPLEFT", 4, y)
    y = y - 28
    W.Stepper(page, "How long it stays (tenths of a second)", function() return db.hold end, function(v) db.hold = v end, 3, 40, 1)
        :SetPoint("TOPLEFT", 4, y)
    y = y - 36
    local test = W.Button(page, 160, 24, "Show a test number")
    test:SetPoint("TOPLEFT", 4, y)
    test:SetScript("OnClick", function()
        Show("player", 1, 0.25, 0.25, false, "%d", 123)
        Show("target", 1, 1, 1, true, "%d", 456)
    end)
    y = y - 40
    W.Notes(page, 4, y, width, "", {
        { "How it looks", "one number in the middle of the frame. A new hit replaces it; nothing floats, scrolls or pops. Crits are a little bigger." },
        { "Colors", "red = damage you take, white = physical damage on your target, yellow = spell damage, green = heals." },
        { "On the target frame", "WoW Forever does not tell addons who dealt a hit, so you see every hit your target takes - yours, your pet's and other players'." },
        { "Needs", "Cys's unit frames (the Unit Frames module) for the frame it is shown on." },
    })
    page.contentHeight = -y + 150
end, function() end)

    end,
})
