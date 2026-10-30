--------------------------------------------------------------------------------
-- Cys's UI - interrupt announcer
--
-- Tells your group (or just you) when one of YOUR spells interrupts an enemy cast:
--   "Interrupted Defias Pillager's Shadow Bolt!"
-- Works for any class (Earth Shock, Pummel, Kick, Counterspell...). Settings: /cui -> Interrupts.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local DEFAULTS = {
    channel = "auto",                          -- auto / say / yell / party / raid / self
    message = "Interrupted %t's %s!",          -- %t = their name, %s = the spell, %m = your spell
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.interrupt = CysUIDB.interrupt or {}
    local db = CysUIDB.interrupt
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local CHANNELS = { "auto", "say", "yell", "party", "raid", "self" }
local CHANNEL_LABEL = {
    auto  = "Group chat (party or raid)",
    say   = "Say",
    yell  = "Yell",
    party = "Party",
    raid  = "Raid",
    self  = "Only show it to me",
}

local function Format(db, target, spell, mine)
    local out = db.message or DEFAULTS.message
    out = out:gsub("%%([tsm])", function(c)
        if c == "t" then return target or "?" end
        if c == "s" then return spell or "?" end
        return mine or "?"
    end)
    return out
end

local function Deliver(db, text)
    local ch = db.channel
    if ch == "auto" then
        if IsInRaid and IsInRaid() then ch = "RAID"
        elseif IsInGroup and IsInGroup() then ch = "PARTY"
        else ch = nil end
    elseif ch == "self" then
        ch = nil
    elseif ch == "party" then
        if not (IsInGroup and IsInGroup()) then ch = nil else ch = "PARTY" end
    elseif ch == "raid" then
        if not (IsInRaid and IsInRaid()) then
            ch = (IsInGroup and IsInGroup()) and "PARTY" or nil
        else ch = "RAID" end
    elseif ch == "say" then ch = "SAY"
    elseif ch == "yell" then ch = "YELL" end
    if ch then
        pcall(SendChatMessage, text, ch)
    else
        CUI:Print(text)
    end
end

local lastSent = 0
local function OnInterrupt(db)
    local _, sub, _, sourceGUID, _, _, _, _, destName, _, _, spellId, spellName, _, extraId, extraName = CombatLogGetCurrentEventInfo()
    if sub ~= "SPELL_INTERRUPT" or sourceGUID ~= UnitGUID("player") then return end
    local now = GetTime()
    if now - lastSent < 0.5 then return end -- one line per interrupt
    lastSent = now
    Deliver(db, Format(db, destName, extraName, spellName))
end

local frame
local function Enable()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:SetScript("OnEvent", function() OnInterrupt(DB()) end)
end

CUI:RegisterModule({
    key = "interrupt",
    name = "Interrupt Announcer",
    addon = "CysUI",
    desc = "Says when you interrupt an enemy cast (to your party or raid, or just to you). Works for every class.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Interrupts") end,
})

CUI:RegisterPage("Interrupts", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Interrupt announcer", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("When a spell of yours interrupts an enemy cast, a line is sent to the place you choose below.")

    local chLabel = W.Text(page, 12, T.accent)
    chLabel:SetPoint("TOPLEFT", 4, -78)
    chLabel:SetText("Where to say it")
    local chOpts = {}
    for _, c in ipairs(CHANNELS) do chOpts[#chOpts + 1] = { c, CHANNEL_LABEL[c] } end
    local chBtn = W.Dropdown(page, 260, chOpts, function() return db.channel end, function(v) db.channel = v end)
    chBtn:SetPoint("TOPLEFT", 4, -98)

    local msgLabel = W.Text(page, 12, T.accent)
    msgLabel:SetPoint("TOPLEFT", 4, -138)
    msgLabel:SetText("What to say")
    local box = CreateFrame("EditBox", nil, page)
    box:SetSize(width - 8, 22)
    box:SetPoint("TOPLEFT", 4, -158)
    box:SetAutoFocus(false)
    box:SetMaxLetters(120)
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextColor(1, 1, 1)
    box:SetTextInsets(8, 8, 0, 0)
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    W.Border(box, 1, T.border, "BORDER")
    box:SetText(db.message or DEFAULTS.message)
    box:SetScript("OnEnterPressed", function(self)
        local t = strtrim(self:GetText() or "")
        if t == "" then t = DEFAULTS.message; self:SetText(t) end
        db.message = t
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(db.message or DEFAULTS.message); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self)
        local t = strtrim(self:GetText() or "")
        if t ~= "" then db.message = t end
    end)

    local keys = W.Text(page, 11, T.desc)
    keys:SetPoint("TOPLEFT", 4, -188)
    keys:SetWidth(width - 8)
    keys:SetJustifyV("TOP")
    keys:SetSpacing(3)
    keys:SetText("|cFFFFD100%t|r = who you interrupted   |cFFFFD100%s|r = the spell you stopped   |cFFFFD100%m|r = your spell   (press Enter to save)")

    local test = W.Button(page, 150, 22, "Show an example")
    test:SetPoint("TOPLEFT", 4, -224)
    test:SetScript("OnClick", function()
        CUI:Print("Example: " .. Format(db, "Defias Pillager", "Shadow Bolt", "Earth Shock"))
    end)

    W.Notes(page, 4, -264, width, "", {
        "It only reports your own interrupts, not other players'.",
        "Turn the whole thing off under Modules (needs a /reload).",
    })
end)
