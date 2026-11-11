--------------------------------------------------------------------------------
-- Cys's Damage Meter (WoW Forever) - our own meter window, fed by the game's built-in damage meter
--
-- WoW Forever counts damage, healing, interrupts and the rest itself (addons no longer get a combat log), and
-- hands the finished, already sorted lists to the interface. This window is ours - flat dark panel, gold edge,
-- class-colored bars - and only asks the game for those lists. No combat log parsing, no per-hit work: it
-- repaints at most a few times a second, and only while there is something new to show.
--
-- During combat the game locks the numbers: they may go straight onto a bar or a text, but an addon can't
-- compare or add them. So nothing here does math on an amount; bars are filled with the game's own values and
-- the order is the game's own. The spell breakdown (hover a row) is read out of combat, when it is unlocked.
--
-- The game's own meter window is only faded out (never hidden, moved or re-parented).
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "meter", name = "Cys's Damage Meter", foreverOnly = true, defaultOff = true,
    desc = "WoW Forever: a damage meter window in the Cys look, fed by the game's built-in meter - damage, healing, damage taken, interrupts, dispels; current fight, overall or an earlier fight. Light on the CPU: no combat log reading.",
    open = function() CysUI:OpenConfig("Damage Meter") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType) then return end
local W = CUI.W
local T = W.T
local Secret = CysUICompat.Secret

CysUIDB.meter = CysUIDB.meter or {}
local db = CysUIDB.meter
local DEFAULTS = { width = 220, rows = 6, rowH = 18, fontSize = 11, mode = "damage", segment = "current", show = "always",
    hideGame = true, classColors = true, rank = true, rate = 0.5 }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MOVER = "meter"
local HEAD = 18
local DT, ST = Enum.DamageMeterType, Enum.DamageMeterSessionType or {}
local MODES = {}
for _, m in ipairs({
    { key = "damage",     label = "Damage",             type = DT.DamageDone,       per = true },
    { key = "healing",    label = "Healing",            type = DT.HealingDone,      per = true },
    { key = "taken",      label = "Damage taken",       type = DT.DamageTaken },
    { key = "absorbs",    label = "Absorbs",            type = DT.Absorbs },
    { key = "interrupts", label = "Interrupts",         type = DT.Interrupts },
    { key = "dispels",    label = "Dispels",            type = DT.Dispels },
    { key = "enemy",      label = "Enemy damage taken", type = DT.EnemyDamageTaken },
}) do
    if m.type ~= nil then MODES[#MODES + 1] = m end
end
local function Mode()
    for _, m in ipairs(MODES) do if m.key == db.mode then return m end end
    return MODES[1]
end
local segmentID, segmentName -- an earlier fight picked from the menu (this session only)

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local holder = CreateFrame("Frame", "CysMeterFrame", UIParent)
holder:SetSize(db.width, HEAD + db.rows * (db.rowH + 1) + 1)
holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -30, 180)
holder:SetFrameStrata("LOW")
W.Texture(holder, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.88 }):SetAllPoints()
local edgeFrame = CreateFrame("Frame", nil, holder)
edgeFrame:SetAllPoints()
edgeFrame:SetFrameLevel(holder:GetFrameLevel() + 6)
W.Border(edgeFrame, 1, T.border, "OVERLAY") -- follows the Border color setting
CUI:RegisterMovable(holder, MOVER, "Damage Meter", { point = "BOTTOMRIGHT", x = -30, y = 180 })

local head = CreateFrame("Button", nil, holder)
head:SetPoint("TOPLEFT", 1, -1)
head:SetPoint("TOPRIGHT", -1, -1)
head:SetHeight(HEAD)
head:RegisterForClicks("AnyUp")
local headLine = W.Texture(head, "ARTWORK", T.line)
headLine:SetHeight(1)
headLine:SetPoint("BOTTOMLEFT", 0, 0)
headLine:SetPoint("BOTTOMRIGHT", 0, 0)
local title = W.Text(head, 11, T.accent)
title:SetPoint("LEFT", 6, 0)
local sub = W.Text(head, 10, { 0.7, 0.7, 0.7 }, "RIGHT")
sub:SetPoint("RIGHT", -6, 0)
local empty = W.Text(holder, 11, { 0.6, 0.6, 0.6 }, "CENTER")
empty:SetPoint("LEFT", 8, -HEAD / 2)
empty:SetPoint("RIGHT", -8, -HEAD / 2)
empty:SetWordWrap(true)

local rows = {}
local offset = 0
local shownCount = 0
local Paint, Queue

-- one row's spell list, read when you point at it. Out of combat only: in combat the game keeps who-did-what locked.
local function Abbrev(v)
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, v)
        if ok and text ~= nil then return text, "%s" end
    end
    return v, "%d"
end
local function SessionSource(src)
    local mode = Mode()
    if segmentID and C_DamageMeter.GetCombatSessionSourceFromID then
        return pcall(C_DamageMeter.GetCombatSessionSourceFromID, segmentID, mode.type, src.sourceGUID, src.sourceCreatureID)
    end
    return pcall(C_DamageMeter.GetCombatSessionSourceFromType, db.segment == "overall" and ST.Overall or ST.Current, mode.type,
        src.sourceGUID, src.sourceCreatureID)
end
local function RowTip(row)
    local src = row.src
    if not src then return end
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", -4, 0)
    if not pcall(GameTooltip.SetText, GameTooltip, src.name, 1, 1, 1) then GameTooltip:SetText(Mode().label, 1, 1, 1) end
    if InCombatLockdown() or Secret(src.sourceGUID) or Secret(src.totalAmount) then
        GameTooltip:AddLine("The spell list shows here out of combat.", T.accent[1], T.accent[2], T.accent[3], true)
    else
        local ok, detail = SessionSource(src)
        local spells = ok and type(detail) == "table" and detail.combatSpells
        if type(spells) == "table" and #spells > 0 then
            local total = detail.totalAmount
            for i = 1, math.min(12, #spells) do
                local sp = spells[i]
                local name = (type(sp.spellID) == "number" and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sp.spellID))
                    or sp.creatureName or "?"
                local amount = Abbrev(sp.totalAmount)
                local right = tostring(amount)
                if type(total) == "number" and type(sp.totalAmount) == "number" and total > 0 then
                    right = string.format("%s  %d%%", right, sp.totalAmount / total * 100 + 0.5)
                end
                GameTooltip:AddDoubleLine(name, right, 1, 1, 1, T.accent[1], T.accent[2], T.accent[3])
            end
            if #spells > 12 then GameTooltip:AddLine("... and " .. (#spells - 12) .. " more", 0.6, 0.6, 0.6) end
        else
            GameTooltip:AddLine("No spell list for this row.", 0.6, 0.6, 0.6)
        end
    end
    GameTooltip:Show()
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, holder)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetAllPoints()
    r.bar:SetStatusBarTexture(FLAT)
    local back = r.bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.16, 0.16, 0.16, 0.6)
    r.mark = r.bar:CreateTexture(nil, "OVERLAY") -- thin gold strip: this row is you
    r.mark:SetWidth(2)
    r.mark:SetPoint("TOPLEFT", 0, 0)
    r.mark:SetPoint("BOTTOMLEFT", 0, 0)
    r.mark:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    r.value = r.bar:CreateFontString(nil, "OVERLAY")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = r.bar:CreateFontString(nil, "OVERLAY")
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", RowTip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local lastW, lastH
local function Layout()
    local w, h = db.width, HEAD + db.rows * (db.rowH + 1) + 2
    if w ~= lastW or h ~= lastH then
        lastW, lastH = w, h
        holder:SetSize(w, h)
        CUI:ApplyLayout(MOVER) -- the Layout mode box follows
    end
    for i = 1, db.rows do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -(HEAD + 1) - (i - 1) * (db.rowH + 1))
        r:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -1, -(HEAD + 1) - (i - 1) * (db.rowH + 1))
        r:SetHeight(db.rowH)
        r.name:SetFont(STANDARD_TEXT_FONT, db.fontSize, "")
        r.value:SetFont(STANDARD_TEXT_FONT, db.fontSize, "")
        r.name:SetTextColor(1, 1, 1)
        r.value:SetTextColor(1, 1, 1)
        r.name:SetShadowOffset(1, -1)
        r.value:SetShadowOffset(1, -1)
    end
    for i = db.rows + 1, #rows do rows[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local function GameOn()
    if C_CVar and C_CVar.GetCVarBool then
        local ok, v = pcall(C_CVar.GetCVarBool, "damageMeterEnabled")
        if ok and v == false then return false end
    end
    return true
end
local function Fetch()
    local mode = Mode()
    local ok, session
    if segmentID then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, segmentID, mode.type)
    else
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, db.segment == "overall" and ST.Overall or ST.Current, mode.type)
    end
    if ok and type(session) == "table" then return session end
    return nil
end
local function SegmentLabel()
    if segmentID then return segmentName or "Earlier fight" end
    return db.segment == "overall" and "Overall" or "Current"
end

function Paint()
    local mode = Mode()
    local session = Fetch()
    local sources = session and session.combatSources
    local n = type(sources) == "table" and #sources or 0
    shownCount = n
    offset = max(0, math.min(offset, n - db.rows))

    title:SetText(mode.label)
    local label = SegmentLabel()
    local secs = session and session.durationSeconds
    if type(secs) == "number" and not Secret(secs) and secs > 0 then
        label = string.format("%s  %d:%02d", label, math.floor(secs / 60), math.floor(secs % 60))
    end
    sub:SetText(label)

    for i = 1, db.rows do
        local r = Row(i)
        local src = n > 0 and sources[offset + i]
        if src then
            r.src = src
            local cr, cg, cb = T.accent[1] * 0.8, T.accent[2] * 0.8, T.accent[3] * 0.8
            if db.classColors then
                local class = src.classFilename
                local cc = type(class) == "string" and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if cc then cr, cg, cb = cc.r, cc.g, cc.b else cr, cg, cb = 0.55, 0.45, 0.35 end -- creatures, pets without a class
            end
            r.bar:SetStatusBarColor(cr, cg, cb, 0.72)
            -- straight from the game into the bar: locked or not, the bar can show it
            if not pcall(r.bar.SetMinMaxValues, r.bar, 0, session.maxAmount) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, src.totalAmount) then r.bar:SetValue(0) end
            local okN
            if db.rank then
                okN = pcall(r.name.SetFormattedText, r.name, "%d. %s", offset + i, src.name)
            else
                okN = pcall(r.name.SetText, r.name, src.name)
            end
            if not okN then r.name:SetText(tostring(offset + i)) end
            local total, fT = Abbrev(src.totalAmount)
            local okV
            if mode.per then
                local per, fP = Abbrev(src.amountPerSecond)
                okV = pcall(r.value.SetFormattedText, r.value, fT .. " (" .. fP .. ")", total, per)
            else
                okV = pcall(r.value.SetFormattedText, r.value, fT, total)
            end
            if not okV then r.value:SetText("") end
            r.mark:SetShown(src.isLocalPlayer == true)
            r:Show()
        else
            r.src = nil
            r:Hide()
        end
    end

    if n == 0 then
        if not GameOn() then
            empty:SetText("The game's damage meter is off. Turn it on from /cui, Damage Meter.")
        else
            empty:SetText("No " .. mode.label:lower() .. " yet")
        end
        empty:Show()
    else
        empty:Hide()
    end
end

-- repaint at most once per Rate, and not at all while the window is faded out
local waiting, dirty
local function Visible() return holder:GetAlpha() > 0 end
function Queue()
    if not Visible() then dirty = true return end
    if waiting then dirty = true return end
    waiting = true
    dirty = false
    Paint()
    C_Timer.After(db.rate or 0.5, function()
        waiting = false
        if dirty then Queue() end
    end)
end

local function UpdateShown()
    local show = true
    if db.show == "combat" then show = InCombatLockdown() and true or false
    elseif db.show == "group" then show = (IsInGroup and IsInGroup()) and true or false end
    if CUI.layoutMode then show = true end
    holder:SetAlpha(show and 1 or 0) -- faded, not hidden, so its Layout mode box keeps working
    holder:EnableMouse(show)
    head:EnableMouse(show)
    for _, r in ipairs(rows) do r:EnableMouse(show) end
    if show and dirty then Queue() end
end

holder:EnableMouseWheel(true)
holder:SetScript("OnMouseWheel", function(_, delta)
    local was = offset
    offset = max(0, math.min(offset - delta, shownCount - db.rows))
    if offset ~= was then Paint() end
end)

--------------------------------------------------------------------------------
-- The game's own meter window: faded out and deaf to the mouse while ours is on (never hidden or moved - it is
-- an Edit Mode piece). Its data keeps flowing; that is what this window shows.
--------------------------------------------------------------------------------
local quietHooked
local function Deafen(frame, depth)
    if depth > 6 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.EnableMouse then pcall(child.EnableMouse, child, false) end
        Deafen(child, depth + 1)
    end
end
local function QuietGame()
    local dm = _G.DamageMeter
    if not (db.hideGame and dm and dm.SetAlpha) then return end
    if not quietHooked then
        quietHooked = true
        local busy
        hooksecurefunc(dm, "SetAlpha", function()
            if busy then return end
            busy = true
            dm:SetAlpha(0)
            busy = false
        end)
    end
    dm:SetAlpha(0)
    if not InCombatLockdown() then pcall(Deafen, dm, 0) end
end

--------------------------------------------------------------------------------
-- Menu (click the title strip): what to show, which fight, reset
--------------------------------------------------------------------------------
local menu, catcher
local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
local function MenuRow(i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu)
    r:SetSize(188, 20)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
    r.hl:Hide()
    r.dot = r:CreateTexture(nil, "ARTWORK") -- the current choice
    r.dot:SetSize(5, 5)
    r.dot:SetPoint("LEFT", 5, 0)
    r.dot:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    r.text = W.Text(r, 12, T.text)
    r.text:SetPoint("LEFT", 16, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) self.hl:Show() end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() end)
    menu.rows[i] = r
    return r
end
local function OpenMenu()
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        W.Texture(menu, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
        W.Border(menu, 1, T.border, "BORDER")
        menu.rows, menu.heads = {}, {}
    end
    for _, r in ipairs(menu.rows) do r:Hide() end
    for _, h in ipairs(menu.heads) do h:Hide() end
    local y, n, nh = -6, 0, 0
    local function Heading(text)
        nh = nh + 1
        local h = menu.heads[nh]
        if not h then h = W.Text(menu, 11, T.accent); menu.heads[nh] = h end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 8, y - 2)
        h:SetText(text)
        h:Show()
        y = y - 18
    end
    local function Item(text, current, fn)
        n = n + 1
        local r = MenuRow(n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r.text:SetText(text)
        r.dot:SetShown(current and true or false)
        r:SetScript("OnClick", function() CloseMenu(); fn(); offset = 0; Paint() end)
        r:Show()
        y = y - 20
    end
    Heading("Show")
    for _, m in ipairs(MODES) do
        Item(m.label, m.key == Mode().key, function() db.mode = m.key end)
    end
    y = y - 4
    Heading("Fight")
    Item("Current fight", not segmentID and db.segment ~= "overall", function() segmentID = nil; db.segment = "current" end)
    Item("Overall", not segmentID and db.segment == "overall", function() segmentID = nil; db.segment = "overall" end)
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if ok and type(list) == "table" then
        local added = 0
        for i = #list, 1, -1 do -- newest first, a handful
            local s = list[i]
            if added < 6 and type(s) == "table" and type(s.sessionID) == "number" and not Secret(s.sessionID) then
                added = added + 1
                local name = (type(s.name) == "string" and not Secret(s.name) and s.name ~= "" and s.name) or ("Fight " .. s.sessionID)
                local secs = s.durationSeconds
                local shown = name
                if type(secs) == "number" and not Secret(secs) then
                    shown = string.format("%s  %d:%02d", name, math.floor(secs / 60), math.floor(secs % 60))
                end
                Item(shown, segmentID == s.sessionID, function() segmentID = s.sessionID; segmentName = name end)
            end
        end
    end
    y = y - 4
    Heading("Data")
    Item("Reset all fights", false, function()
        segmentID = nil
        if C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
    end)
    menu:SetSize(200, -y + 6)
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", head, "TOPLEFT", -1, 3)
    catcher:Show()
    menu:Show()
end
head:SetScript("OnClick", function()
    if menu and menu:IsShown() then CloseMenu() else OpenMenu() end
end)
head:SetScript("OnEnter", function(self)
    title:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", -4, 0)
    GameTooltip:SetText("Damage Meter", 1, 1, 1)
    GameTooltip:AddLine("Click: what to show, which fight, reset.", T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:AddLine("Mouse wheel over the rows: scroll.", T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:Show()
end)
head:SetScript("OnLeave", function()
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    GameTooltip:Hide()
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function Refresh()
    Layout()
    UpdateShown()
    Paint()
end
CUI.MeterRefresh = Refresh
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", UpdateShown) end

local ev = CreateFrame("Frame")
for _, event in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, event)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "DAMAGE_METER_RESET" then
        segmentID = nil
        offset = 0
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then
        UpdateShown()
        if event == "PLAYER_REGEN_ENABLED" then QuietGame() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function() QuietGame(); Refresh() end)
    end
    Queue()
end)

Refresh()
QuietGame()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Damage Meter", function(page)
    local width = 480
    W.Header(page, "Damage Meter", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local status = W.Text(page, 12, T.text)
    status:SetPoint("TOPLEFT", 4, y)
    status:SetWidth(width - 8)
    status:SetJustifyH("LEFT")
    local function Status()
        if GameOn() then
            status:SetText("The game is counting: Cys's meter window shows its numbers. Click the window's title strip to pick what it shows.")
        else
            status:SetText("|cFFFF4040The game's damage meter is switched off|r, so there is nothing to show yet. Use the button below, or turn it on in the game's Options.")
        end
    end
    Status()
    y = y - 40
    local on = W.Button(page, 260, 24, "Turn on the game's damage meter", true)
    on:SetPoint("TOPLEFT", 4, y)
    on:SetScript("OnClick", function()
        if InCombatLockdown() then CUI:Print("Damage Meter: try again out of combat.") return end
        if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, "damageMeterEnabled", "1") end
        C_Timer.After(0.2, function()
            Status()
            QuietGame()
            Paint()
            if not GameOn() then CUI:Print("Damage Meter: the game did not take the switch. Turn Damage Meter on in the game's Options.") end
        end)
    end)
    y = y - 38

    local function Check(text, key, fn)
        W.Checkbox(page, text, function() return db[key] end, function(v) db[key] = v; (fn or Refresh)() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    local function Step(text, key, lo, hi, step, suffix)
        W.Stepper(page, text, function() return db[key] end, function(v) db[key] = v; Refresh() end, lo, hi, step, suffix)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    Step("Width", "width", 120, 500, 10, " px")
    Step("Rows", "rows", 3, 25, 1)
    Step("Row height", "rowH", 12, 30, 1, " px")
    Step("Text size", "fontSize", 8, 18, 1)
    y = y - 6
    Check("Class-colored bars", "classColors")
    Check("Number each row (1. 2. 3.)", "rank")
    Check("Fade out the game's own meter window (reload to bring it back)", "hideGame", QuietGame)
    y = y - 6

    local lab = W.Text(page, 12, T.accent)
    lab:SetPoint("TOPLEFT", 4, y - 4)
    lab:SetText("Show")
    W.Dropdown(page, 230, { { "always", "always" }, { "combat", "only in combat" }, { "group", "only in a group" } },
        function() return db.show end, function(v) db.show = v; Refresh() end):SetPoint("TOPLEFT", 120, y)
    y = y - 32
    local lab2 = W.Text(page, 12, T.accent)
    lab2:SetPoint("TOPLEFT", 4, y - 4)
    lab2:SetText("Updates")
    W.Dropdown(page, 230, { { 0.25, "4 times a second" }, { 0.5, "twice a second" }, { 1, "once a second" } },
        function() return db.rate end, function(v) db.rate = v end):SetPoint("TOPLEFT", 120, y)
    y = y - 40

    local note = W.Notes(page, 4, y, width, "", {
        { "The window", "click its title strip for the menu: damage, healing, damage taken, absorbs, interrupts, dispels; the current fight, overall, or an earlier fight; reset. Mouse wheel scrolls the rows. Move it in Layout mode (Damage Meter)." },
        { "Spell list", "point at a row out of combat to see that player's spells. In combat the game keeps who-did-what locked, so the list waits until the fight is over." },
        { "Where the numbers come from", "WoW Forever counts everything itself; this window only shows it. Nothing reads a combat log, so it stays light even in a raid." },
        { "The game's own window", "is only faded out. You can also set it to Hidden in the game's Edit Mode." },
        { "Details!", "has its own page (Damage Meters) for the Cys skin, if you still use it." },
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 150) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
