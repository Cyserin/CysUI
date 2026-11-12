--------------------------------------------------------------------------------
-- Cys's Damage Meter (WoW Forever) - our own meter windows, fed by the game's built-in damage meter
--
-- WoW Forever counts damage, healing, interrupts and the rest itself (addons no longer get a combat log), and
-- hands the finished, already sorted lists to the interface. These windows are ours - flat dark panel, gold edge,
-- class-colored bars - and only ask the game for those lists. No combat log parsing, no per-hit work: they
-- repaint at most a few times a second, and only while there is something new to show.
--
-- Several windows can be open at once, each showing its own thing (damage here, healing per second there, the
-- overall total in a third). Everything about a window is set on the window: click its title strip.
--
-- During combat the game locks the numbers: they may go straight onto a bar or a text, but an addon can't
-- compare or add them. So nothing here does math on a locked amount; bars are filled with the game's own values
-- and the order is the game's own.
--
-- The game's own meter window is only faded out (never hidden, moved or re-parented).
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "meter", name = "Cys's Damage Meter", foreverOnly = true, defaultOff = true,
    desc = "WoW Forever: damage meter windows in the Cys look, fed by the game's built-in meter - damage, DPS, healing, HPS, damage taken, interrupts, dispels; current fight, overall or an earlier fight; as many windows as you like. Light on the CPU: no combat log reading.",
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
local DEFAULTS = { rowH = 18, fontSize = 11, show = "always", hideGame = true, classColors = true, rank = true, rate = 0.5,
    icons = true, pinMe = true, hover = true, more = false, autoCurrent = true }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
-- one entry per window: what it shows and its size. (0.58.10 test builds kept a single window's settings flat.)
if not db.windows then
    db.windows = { { id = 1, mode = db.mode or "damage", segment = db.segment or "current", width = db.width or 220, rows = db.rows or 6 } }
    db.winSeq = 1
end
local MAX_WINDOWS = 5

local FLAT = "Interface\\Buttons\\WHITE8X8"
local HEAD = 18
local DT, ST = Enum.DamageMeterType, Enum.DamageMeterSessionType or {}
local MODES = {}
for _, m in ipairs({
    { key = "damage",     label = "Damage",             type = DT.DamageDone,       per = true },
    { key = "dps",        label = "DPS",                type = DT.Dps,              per = true, first = true },
    { key = "healing",    label = "Healing",            type = DT.HealingDone,      per = true },
    { key = "hps",        label = "HPS",                type = DT.Hps,              per = true, first = true },
    { key = "taken",      label = "Damage taken",       type = DT.DamageTaken },
    { key = "avoidable",  label = "Avoidable damage taken", type = DT.AvoidableDamageTaken },
    { key = "absorbs",    label = "Absorbs",            type = DT.Absorbs },
    { key = "interrupts", label = "Interrupts",         type = DT.Interrupts },
    { key = "dispels",    label = "Dispels",            type = DT.Dispels },
    { key = "enemy",      label = "Enemy damage taken", type = DT.EnemyDamageTaken },
}) do
    if m.type ~= nil then MODES[#MODES + 1] = m end
end
local function Mode(win)
    for _, m in ipairs(MODES) do if m.key == win.cfg.mode then return m end end
    return MODES[1]
end

local wins = {}
local Paint, Queue, CreateWindow, CloseWindow, UpdateShown, OpenMenu, CloseMenu, NewWindow, ResetAll, PaintAll

--------------------------------------------------------------------------------
-- Numbers. A plain number is shortened here (397, 1.2K, 12K, 3.4M). A locked one (in combat) can't be compared
-- or rounded by an addon, so the game shortens it with the same rules; the text it hands back can only be shown.
--------------------------------------------------------------------------------
local SHORT = { breakpointData = {
    { breakpoint = 1000000, abbreviation = "M", significandDivisor = 100000, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 10000,   abbreviation = "K", significandDivisor = 1000,   fractionDivisor = 1,  abbreviationIsGlobal = false },
    { breakpoint = 1000,    abbreviation = "K", significandDivisor = 100,    fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1,       abbreviation = "",  significandDivisor = 1,      fractionDivisor = 1,  abbreviationIsGlobal = false },
} }
local function Short(v)
    if type(v) == "number" and not Secret(v) then
        if v >= 1000000 then return string.format("%.1fM", v / 1000000), "%s" end
        if v >= 10000 then return string.format("%dK", v / 1000 + 0.5), "%s" end
        if v >= 1000 then return string.format("%.1fK", v / 1000), "%s" end
        return string.format("%d", v + 0.5), "%s"
    end
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, v, SHORT)
        if ok and text ~= nil then return text, "%s" end
        ok, text = pcall(AbbreviateNumbers, v)
        if ok and text ~= nil then return text, "%s" end
    end
    return v, "%d"
end

local function SessionKind(win) return win.cfg.segment == "overall" and ST.Overall or ST.Current end
local function SessionSource(win, src)
    local mode = Mode(win)
    if win.segmentID and C_DamageMeter.GetCombatSessionSourceFromID then
        return pcall(C_DamageMeter.GetCombatSessionSourceFromID, win.segmentID, mode.type, src.sourceGUID, src.sourceCreatureID)
    end
    return pcall(C_DamageMeter.GetCombatSessionSourceFromType, SessionKind(win), mode.type, src.sourceGUID, src.sourceCreatureID)
end
local function Fetch(win)
    local mode = Mode(win)
    local ok, session
    if win.segmentID then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, win.segmentID, mode.type)
    else
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, SessionKind(win), mode.type)
    end
    if ok and type(session) == "table" then return session end
    return nil
end
-- Can the game's meter be used at all on this character right now? (Its own on/off setting only governs the
-- game's window; the counting behind it runs regardless, so that setting is not looked at.)
local function GameOn()
    if C_DamageMeter.IsDamageMeterAvailable then
        local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if ok and available == false then return false, reason end
    end
    return true
end

--------------------------------------------------------------------------------
-- Breakdown: point at a row and its spells open in a small panel beside the window - icon, name, a bar and the
-- amount for each. It is our own panel (not the game tooltip), so it can show locked values during combat too:
-- your own row always, other players whenever the game hands their list out (otherwise it says so and shows
-- them once the fight is over). It follows the fight while you keep pointing.
--------------------------------------------------------------------------------
local bd
local function BreakRow(i)
    local r = bd.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, bd)
    r:SetHeight(18)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", 19, 0)
    r.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    r.bar:SetStatusBarTexture(FLAT)
    local back = r.bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.16, 0.16, 0.16, 0.6)
    r.value = r.bar:CreateFontString(nil, "OVERLAY")
    r.value:SetFont(STANDARD_TEXT_FONT, 11, "")
    r.value:SetPoint("RIGHT", -4, 0)
    r.name = r.bar:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(STANDARD_TEXT_FONT, 11, "")
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    bd.rows[i] = r
    return r
end
-- force = close it even when it was pinned open by a click
local function HideBreakdown(force)
    if not bd then return end
    if bd.locked and force ~= true then
        if bd.row ~= bd.locked then bd.row = bd.locked; if Paint and bd.locked.win then Paint(bd.locked.win) end end
        return
    end
    bd.locked = nil
    bd:Hide()
    bd.row = nil
end
local function ShowBreakdown(row)
    local src, win = row and row.src, row and row.win
    if not (src and win and (db.hover or (bd and bd.locked == row))) then return HideBreakdown() end
    if not bd then
        bd = CreateFrame("Frame", nil, UIParent)
        bd:SetFrameStrata("TOOLTIP")
        bd:SetClampedToScreen(true)
        W.Texture(bd, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.96 }):SetAllPoints()
        W.Border(bd, 1, T.border, "BORDER")
        bd.title = W.Text(bd, 12, T.accent)
        bd.title:SetPoint("TOPLEFT", 8, -7)
        bd.total = W.Text(bd, 11, { 1, 1, 1 }, "RIGHT")
        bd.total:SetPoint("TOPRIGHT", -8, -8)
        bd.title:SetPoint("RIGHT", bd.total, "LEFT", -6, 0)
        bd.title:SetWordWrap(false)
        bd.note = W.Text(bd, 11, { 0.7, 0.7, 0.7 })
        bd.note:SetWordWrap(true)
        bd.rows = {}
    end
    bd.row = row
    local mode = Mode(win)
    if not pcall(bd.title.SetText, bd.title, src.name) then bd.title:SetText(mode.label) end
    local total, fT = Short(src.totalAmount)
    if not pcall(bd.total.SetFormattedText, bd.total, fT, total) then bd.total:SetText("") end
    local cr, cg, cb = T.accent[1] * 0.8, T.accent[2] * 0.8, T.accent[3] * 0.8
    local class = src.classFilename
    local cc = db.classColors and type(class) == "string" and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then cr, cg, cb = cc.r, cc.g, cc.b end

    local ok, detail = SessionSource(win, src)
    local spells = ok and type(detail) == "table" and detail.combatSpells
    local n = type(spells) == "table" and #spells or 0
    local shown = math.min(n, db.more and 15 or 8)
    for i = 1, shown do
        local sp = spells[i]
        local r = BreakRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 19)
        r:SetPoint("TOPRIGHT", -8, -26 - (i - 1) * 19)
        local okI, icon = pcall(C_Spell.GetSpellTexture, sp.spellID)
        if not (okI and icon and pcall(r.icon.SetTexture, r.icon, icon)) then r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
        local okN, name = pcall(C_Spell.GetSpellName, sp.spellID)
        if not (okN and name ~= nil and pcall(r.name.SetText, r.name, name)) then
            if not pcall(r.name.SetText, r.name, sp.creatureName) then r.name:SetText("?") end
        end
        r.bar:SetStatusBarColor(cr, cg, cb, 0.6)
        if not pcall(r.bar.SetMinMaxValues, r.bar, 0, detail.maxAmount) then r.bar:SetMinMaxValues(0, 1) end
        if not pcall(r.bar.SetValue, r.bar, sp.totalAmount) then r.bar:SetValue(0) end
        local amount, fA = Short(sp.totalAmount)
        local whole, part = detail.totalAmount, sp.totalAmount
        local okV
        if type(whole) == "number" and type(part) == "number" and not Secret(whole) and not Secret(part) and whole > 0 then
            okV = pcall(r.value.SetFormattedText, r.value, fA .. "  %d%%", amount, part / whole * 100 + 0.5) -- unlocked: our own math is fine
        else
            okV = pcall(r.value.SetFormattedText, r.value, fA, amount)
        end
        if not okV then r.value:SetText("") end
        r:Show()
    end
    for i = shown + 1, #bd.rows do bd.rows[i]:Hide() end
    local h = 30 + shown * 19
    bd.note:ClearAllPoints()
    bd.note:SetPoint("TOPLEFT", 8, -28 - shown * 19)
    bd.note:SetPoint("RIGHT", -8, 0)
    if shown == 0 then
        bd.note:SetText(InCombatLockdown() and "The game keeps this player's spells locked during the fight. They show here once it is over."
            or "No spell list for this row.")
        bd.note:Show()
        h = 34 + max(14, bd.note:GetStringHeight() or 14)
    elseif n > shown then
        bd.note:SetText("... and " .. (n - shown) .. " more")
        bd.note:Show()
        h = h + 16
    else
        bd.note:Hide()
    end
    bd:SetSize(240, h)
    -- beside the window, on the side with more room
    bd:ClearAllPoints()
    local cx = win.holder:GetCenter()
    local half = (UIParent:GetWidth() or 0) / 2
    if cx and cx * (win.holder:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1) > half then
        bd:SetPoint("BOTTOMRIGHT", win.holder, "BOTTOMLEFT", -4, 0)
    else
        bd:SetPoint("BOTTOMLEFT", win.holder, "BOTTOMRIGHT", 4, 0)
    end
    bd:Show()
end

--------------------------------------------------------------------------------
-- A window
--------------------------------------------------------------------------------
local function Row(win, i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win.holder)
    r.win = win
    r.icon = r:CreateTexture(nil, "ARTWORK") -- class icon
    r.icon:SetPoint("TOPLEFT", 0, 0)
    r.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    r.bar = CreateFrame("StatusBar", nil, r)
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
    r:SetScript("OnEnter", ShowBreakdown)
    r:SetScript("OnLeave", function() HideBreakdown() end)
    -- click a row: its breakdown stays open (and keeps following the fight) until you click the row again
    r:SetScript("OnMouseUp", function(self)
        if bd and bd.locked == self then
            HideBreakdown(true)
        else
            if bd then bd.locked = nil end
            ShowBreakdown(self)
            if bd and bd:IsShown() then bd.locked = self end
        end
    end)
    win.rows[i] = r
    return r
end

local function Layout(win)
    local cfg = win.cfg
    local w, h = cfg.width, HEAD + cfg.rows * (db.rowH + 1) + 2
    if w ~= win.lastW or h ~= win.lastH then
        win.lastW, win.lastH = w, h
        win.holder:SetSize(w, h)
        CUI:ApplyLayout(win.mover) -- the Layout mode box follows
    end
    for i = 1, cfg.rows do
        local r = Row(win, i)
        local y = -(HEAD + 1) - (i - 1) * (db.rowH + 1)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", win.holder, "TOPLEFT", 1, y)
        r:SetPoint("TOPRIGHT", win.holder, "TOPRIGHT", -1, y)
        r:SetHeight(db.rowH)
        r.icon:SetSize(db.rowH, db.rowH)
        r.icon:SetShown(db.icons)
        r.bar:ClearAllPoints()
        r.bar:SetPoint("TOPLEFT", db.icons and (db.rowH + 1) or 0, 0)
        r.bar:SetPoint("BOTTOMRIGHT", 0, 0)
        for _, fs in ipairs({ r.name, r.value }) do
            fs:SetFont(STANDARD_TEXT_FONT, db.fontSize, "")
            fs:SetTextColor(1, 1, 1)
            fs:SetShadowOffset(1, -1)
        end
    end
    for i = cfg.rows + 1, #win.rows do win.rows[i]:Hide() end
end

local function SegmentLabel(win)
    if win.segmentID then return win.segmentName or "Earlier fight" end
    return win.cfg.segment == "overall" and "Overall" or "Current"
end

function Paint(win)
    local cfg = win.cfg
    local mode = Mode(win)
    local session = Fetch(win)
    local sources = session and session.combatSources
    local n = type(sources) == "table" and #sources or 0
    win.count = n
    win.offset = max(0, math.min(win.offset, n - cfg.rows))
    local offset = win.offset

    win.title:SetText(mode.label)
    local label = SegmentLabel(win)
    local secs = session and session.durationSeconds
    if type(secs) == "number" and not Secret(secs) and secs > 0 then
        label = string.format("%s  %d:%02d", label, math.floor(secs / 60), math.floor(secs % 60))
    end
    win.sub:SetText(label)

    -- your own row stays in sight: when you are scrolled out of the window, the last line shows you
    local mine
    if db.pinMe and n > cfg.rows then
        for i = 1, n do
            if sources[i].isLocalPlayer == true then mine = i break end
        end
        if mine and mine > offset and mine <= offset + cfg.rows then mine = nil end
    end

    for i = 1, cfg.rows do
        local r = Row(win, i)
        local index = offset + i
        if mine and i == cfg.rows then index = mine end
        local src = n > 0 and sources[index]
        if src then
            r.src = src
            local class = src.classFilename
            local plainClass = type(class) == "string" and not Secret(class) and class or nil
            local coords = db.icons and plainClass and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[plainClass]
            if coords then
                r.icon:SetTexCoord(coords[1] + 0.01, coords[2] - 0.01, coords[3] + 0.01, coords[4] - 0.01)
                r.icon:SetAlpha(1)
            else
                r.icon:SetAlpha(0)
            end
            local cr, cg, cb = T.accent[1] * 0.8, T.accent[2] * 0.8, T.accent[3] * 0.8
            if db.classColors then
                local cc = plainClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[plainClass]
                if cc then cr, cg, cb = cc.r, cc.g, cc.b else cr, cg, cb = 0.55, 0.45, 0.35 end -- creatures, pets without a class
            end
            r.bar:SetStatusBarColor(cr, cg, cb, 0.72)
            -- straight from the game into the bar: locked or not, the bar can show it
            if not pcall(r.bar.SetMinMaxValues, r.bar, 0, session.maxAmount) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, src.totalAmount) then r.bar:SetValue(0) end
            local okN
            if db.rank then
                okN = pcall(r.name.SetFormattedText, r.name, "%d. %s", index, src.name)
            else
                okN = pcall(r.name.SetText, r.name, src.name)
            end
            if not okN then r.name:SetText(tostring(index)) end
            local total, fT = Short(src.totalAmount)
            local okV
            if mode.per then
                local per, fP = Short(src.amountPerSecond)
                if mode.first then -- DPS / HPS: the per-second figure leads
                    okV = pcall(r.value.SetFormattedText, r.value, fP .. " (" .. fT .. ")", per, total)
                else
                    okV = pcall(r.value.SetFormattedText, r.value, fT .. " (" .. fP .. ")", total, per)
                end
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

    if bd and bd:IsShown() and bd.row and bd.row.win == win then -- the open breakdown follows the fight
        if bd.row.src and bd.row:IsShown() then ShowBreakdown(bd.row) else HideBreakdown(true) end
    end

    if n == 0 then
        if not GameOn() then
            win.empty:SetText("The game's damage meter is not available right now")
        else
            win.empty:SetText("No " .. mode.label:lower() .. " yet")
        end
        win.empty:Show()
    else
        win.empty:Hide()
    end
end
function PaintAll()
    for _, win in ipairs(wins) do Paint(win) end
end
function ResetAll()
    for _, w in ipairs(wins) do w.segmentID = nil; w.offset = 0 end
    if C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
    PaintAll()
end

-- repaint at most once per Rate, and not at all while the windows are faded out
local waiting, dirty, visible = false, false, true
function Queue()
    if not visible or waiting then dirty = true return end
    waiting = true
    dirty = false
    PaintAll()
    C_Timer.After(db.rate or 0.5, function()
        waiting = false
        if dirty then Queue() end
    end)
end

function UpdateShown()
    local show = true
    if db.show == "combat" then show = InCombatLockdown() and true or false
    elseif db.show == "group" then show = (IsInGroup and IsInGroup()) and true or false end
    if CUI.layoutMode then show = true end
    visible = show
    for _, win in ipairs(wins) do
        win.holder:SetAlpha(show and 1 or 0) -- faded, not hidden, so its Layout mode box keeps working
        win.holder:EnableMouse(show)
        win.head:EnableMouse(show)
        for _, r in ipairs(win.rows) do r:EnableMouse(show) end
        for _, b in ipairs(win.quick or {}) do b:EnableMouse(show) end
        if win.lock then win.lock:EnableMouse(show) end
        if win.grip then win.grip:EnableMouse(show) end
    end
    if not show then HideBreakdown(true); if CloseMenu then CloseMenu() end end
    if show and dirty then Queue() end
end

function CreateWindow(cfg)
    local index = #wins + 1
    local first = cfg.id == 1
    local win = { cfg = cfg, rows = {}, offset = 0, count = 0, mover = first and "meter" or ("meter_" .. cfg.id) }
    local holder = CreateFrame("Frame", first and "CysMeterFrame" or ("CysMeterFrame" .. cfg.id), UIParent)
    win.holder = holder
    local y = 180 + (index - 1) * 150
    holder:SetSize(cfg.width, HEAD + cfg.rows * (db.rowH + 1) + 2)
    holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -30, y)
    -- above the game's own bottom-right pieces (its bag bar keeps taking the mouse even while it is faded out),
    -- so the window's buttons get the click wherever the window is parked
    holder:SetFrameStrata("MEDIUM")
    holder:SetFrameLevel(200) -- the game's bag slots sit at level 54 there (seen with /fstack)
    W.Texture(holder, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.88 }):SetAllPoints()
    local edgeFrame = CreateFrame("Frame", nil, holder)
    edgeFrame:SetAllPoints()
    edgeFrame:SetFrameLevel(holder:GetFrameLevel() + 6)
    W.Border(edgeFrame, 1, T.border, "OVERLAY") -- follows the Border color setting
    CUI:RegisterMovable(holder, win.mover, first and "Damage Meter" or ("Damage Meter " .. index), { point = "BOTTOMRIGHT", x = -30, y = y })

    local head = CreateFrame("Button", nil, holder)
    win.head = head
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD)
    head:RegisterForClicks("AnyUp")
    local line = W.Texture(head, "ARTWORK", T.line)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    win.title = W.Text(head, 11, T.accent)
    win.title:SetPoint("LEFT", 6, 0)
    -- buttons on the strip, right to left: new window, reset, this window, which fight, what to show
    local function Quick(icon, tip, x, fn)
        local b = CreateFrame("Button", nil, head)
        b:SetSize(16, HEAD)
        b:SetPoint("RIGHT", x, 0)
        if icon:find("\\") then
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetSize(12, 12)
            b.tex:SetPoint("CENTER", 0, 0)
            b.tex:SetTexture(icon)
            b.tex:SetDesaturated(true)
            b.tex:SetVertexColor(0.75, 0.75, 0.75)
        else
            b.text = W.Text(b, 13, { 0.75, 0.75, 0.75 }, "CENTER")
            b.text:SetPoint("CENTER", 0, 0)
            b.text:SetText(icon)
        end
        function b:Tint(r, g, bl)
            if self.tex then self.tex:SetVertexColor(r, g, bl) else self.text:SetTextColor(r, g, bl) end
        end
        b:SetScript("OnEnter", function(self)
            self:Tint(T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self:Tint(0.75, 0.75, 0.75); GameTooltip:Hide() end)
        b:SetScript("OnClick", fn)
        return b
    end
    win.quick = {
        Quick("+", "New window", -3, function() CloseMenu(); NewWindow(win) end),
        Quick("Interface\\Buttons\\UI-RefreshButton", "Reset all fights (click twice)", -19, function(self)
            if not self.armed then
                self.armed = true
                self:Tint(1, 0.25, 0.25)
                C_Timer.After(2.5, function() self.armed = nil; self:Tint(0.75, 0.75, 0.75) end)
                return
            end
            self.armed = nil
            ResetAll()
        end),
        Quick("Interface\\Buttons\\UI-OptionsButton", "This window: size, lock, close, settings", -35, function() OpenMenu(win, "window") end),
        Quick("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Which fight", -51, function() OpenMenu(win, "fight") end),
        Quick("Interface\\CURSOR\\Attack", "What to show", -67, function() OpenMenu(win, "show") end),
    }
    win.sub = W.Text(head, 10, { 0.7, 0.7, 0.7 }, "RIGHT")
    win.sub:SetPoint("RIGHT", -88, 0)
    win.title:SetPoint("RIGHT", win.sub, "LEFT", -4, 0)
    win.title:SetWordWrap(false)

    -- lock: bottom-right corner. Unlocked, the window drags by its title strip or its background.
    local lock = CreateFrame("Button", nil, holder)
    win.lock = lock
    lock:SetSize(16, 16)
    lock:SetPoint("BOTTOMRIGHT", -16, 0)
    lock:SetFrameLevel(holder:GetFrameLevel() + 8)
    lock.tex = lock:CreateTexture(nil, "OVERLAY")
    lock.tex:SetAllPoints()
    lock.tex:SetTexCoord(0.2, 0.8, 0.2, 0.8) -- the art sits small in the middle of its file: show just the padlock
    function win.PaintLock()
        lock.tex:SetTexture(cfg.locked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
        lock.tex:SetAlpha(cfg.locked and 0.6 or 1)
    end
    lock:SetScript("OnClick", function() cfg.locked = not cfg.locked and true or nil; win.PaintLock() end)
    lock:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(cfg.locked and "Locked in place" or "Unlocked: drag the title strip to move", 1, 1, 1)
        GameTooltip:AddLine("Click to " .. (cfg.locked and "unlock." or "lock."), T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", function() win.PaintLock(); GameTooltip:Hide() end)
    win.PaintLock()
    -- resize: drag the bottom-right corner. Width follows the mouse, height snaps to whole rows, and the top-left
    -- corner stays where it is. Off while the window is locked.
    local grip = CreateFrame("Button", nil, holder)
    win.grip = grip
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(holder:GetFrameLevel() + 8)
    grip.tex = grip:CreateTexture(nil, "OVERLAY")
    grip.tex:SetAllPoints()
    grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip.tex:SetAlpha(0.6)
    local sizing
    local function StopSizing()
        sizing = nil
        grip:SetScript("OnUpdate", nil)
    end
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or cfg.locked or CUI.layoutMode then return end
        local scale = holder:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        local left, top = holder:GetLeft(), holder:GetTop()
        if not (left and top) then return end
        CloseMenu(); HideBreakdown(true)
        sizing = { x = cx / scale, y = cy / scale, w = cfg.width, rows = cfg.rows, left = left, top = top }
        self:SetScript("OnUpdate", function()
            if not sizing or not IsMouseButtonDown("LeftButton") then StopSizing() return end
            local mx, my = GetCursorPosition()
            mx, my = mx / scale, my / scale
            local w = max(120, math.min(500, math.floor((sizing.w + mx - sizing.x) / 2 + 0.5) * 2))
            local rowsN = max(2, math.min(25, sizing.rows + math.floor((sizing.y - my) / (db.rowH + 1) + 0.5)))
            if w == cfg.width and rowsN == cfg.rows then return end
            cfg.width, cfg.rows = w, rowsN
            -- keep the top-left corner in place: the saved spot is the window's middle, so it moves with the size
            local h = HEAD + rowsN * (db.rowH + 1) + 2
            local ux, uy = UIParent:GetCenter()
            local s = scale / (UIParent:GetEffectiveScale() or 1)
            CysUIDB.layout = CysUIDB.layout or {}
            local e = CysUIDB.layout[win.mover] or {}
            CysUIDB.layout[win.mover] = e
            e.point = "CENTER"
            e.x = math.floor((sizing.left + w / 2) * s - ux + 0.5)
            e.y = math.floor((sizing.top - h / 2) * s - uy + 0.5)
            Layout(win)
            Paint(win)
        end)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(cfg.locked and "Locked: unlock to resize" or "Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.6); GameTooltip:Hide() end)

    local function DragStart() if not cfg.locked then CloseMenu(); HideBreakdown(true); CUI:StartWindowDrag(win.mover) end end
    local function DragStop() CUI:StopWindowDrag(win.mover) end
    for _, handle in ipairs({ head, holder }) do
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", DragStart)
        handle:SetScript("OnDragStop", DragStop)
    end

    win.empty = W.Text(holder, 11, { 0.6, 0.6, 0.6 }, "CENTER")
    win.empty:SetPoint("LEFT", 8, -HEAD / 2)
    win.empty:SetPoint("RIGHT", -8, -HEAD / 2)
    win.empty:SetWordWrap(true)

    head:SetScript("OnClick", function() OpenMenu(win, "show") end)
    head:SetScript("OnEnter", function() win.title:SetTextColor(1, 1, 1) end)
    head:SetScript("OnLeave", function() win.title:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        local was = win.offset
        win.offset = max(0, math.min(win.offset - delta, win.count - cfg.rows))
        if win.offset ~= was then Paint(win) end
    end)

    wins[index] = win
    Layout(win)
    return win
end

function CloseWindow(win)
    if #wins <= 1 then return end
    for i = #wins, 1, -1 do if wins[i] == win then table.remove(wins, i) end end
    for i = #db.windows, 1, -1 do if db.windows[i] == win.cfg then table.remove(db.windows, i) end end
    HideBreakdown(true)
    win.holder:Hide()
    local m = CUI.movers and CUI.movers[win.mover]
    if m then -- its Layout mode box goes too
        if m.mover then m.mover:Hide() end
        CUI.movers[win.mover] = nil
        for i = #(CUI.moverOrder or {}), 1, -1 do if CUI.moverOrder[i] == win.mover then table.remove(CUI.moverOrder, i) end end
        if CysUIDB.layout then CysUIDB.layout[win.mover] = nil end
    end
end

function NewWindow(from)
    if #db.windows >= MAX_WINDOWS then
        CUI:Print("Damage Meter: " .. MAX_WINDOWS .. " windows is the limit.")
        return
    end
    db.winSeq = (db.winSeq or 1) + 1
    -- a new window starts on something the others are not showing yet
    local taken = {}
    for _, c in ipairs(db.windows) do taken[c.mode] = true end
    local mode = "healing"
    for _, m in ipairs(MODES) do if not taken[m.key] then mode = m.key break end end
    local cfg = { id = db.winSeq, mode = mode, segment = "current", width = from and from.cfg.width or 220, rows = from and from.cfg.rows or 6 }
    db.windows[#db.windows + 1] = cfg
    local win = CreateWindow(cfg)
    UpdateShown()
    Paint(win)
    CUI:Print("Damage Meter: new window added. Drag it in Layout mode (" .. (CUI.movers[win.mover] and CUI.movers[win.mover].label or "Damage Meter") .. ").")
end

--------------------------------------------------------------------------------
-- The game's own meter window: faded out and deaf to the mouse while ours is on (never hidden or moved - it is
-- an Edit Mode piece). Its data keeps flowing; that is what these windows show.
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
-- The window's own options (click its title strip): what it shows, which fight, its size, more windows, reset
--------------------------------------------------------------------------------
local menu, catcher
function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
local function MenuRow(i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu)
    r:SetSize(188, 19)
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
-- a size line: label, minus, value, plus. The menu stays open while you click.
local function MenuSize(i)
    local s = menu.sizes[i]
    if s then return s end
    s = CreateFrame("Frame", nil, menu)
    s:SetSize(188, 20)
    s.text = W.Text(s, 12, T.text)
    s.text:SetPoint("LEFT", 16, 0)
    s.plus = W.Button(s, 20, 18, "+")
    s.plus:SetPoint("RIGHT", 0, 0)
    s.value = W.Text(s, 12, T.accent, "CENTER")
    s.value:SetPoint("RIGHT", s.plus, "LEFT", -4, 0)
    s.value:SetWidth(40)
    s.minus = W.Button(s, 20, 18, "-")
    s.minus:SetPoint("RIGHT", s.value, "LEFT", -4, 0)
    menu.sizes[i] = s
    return s
end
-- Report the top of a window to chat (out of combat only: in a fight the numbers are locked and can't be sent)
local function Report(win, channel, count)
    if InCombatLockdown() or UnitAffectingCombat("player") then
        CUI:Print("The meter can be reported once the fight is over (the game locks the numbers during it).")
        return
    end
    local mode = Mode(win)
    local session = Fetch(win)
    local sources = session and session.combatSources
    if type(sources) ~= "table" or #sources == 0 then CUI:Print("Nothing to report yet.") return end
    local function Plain(v) return type(v) == "number" and not Secret(v) and v or nil end
    local lines = { string.format("%s - %s:", mode.label, SegmentLabel(win)) }
    for i = 1, math.min(count, #sources) do
        local s = sources[i]
        local name = type(s.name) == "string" and not Secret(s.name) and s.name or nil
        local total, per = Plain(s.totalAmount), Plain(s.amountPerSecond)
        if name and total then
            local value = Short(total)
            if mode.per and per then
                if mode.first then value = Short(per) .. " (" .. value .. ")" else value = value .. " (" .. Short(per) .. "/s)" end
            end
            lines[#lines + 1] = string.format("%d. %s  %s", i, name, value)
        end
    end
    if #lines == 1 then CUI:Print("Nothing to report yet.") return end
    for _, line in ipairs(lines) do
        if channel then pcall(SendChatMessage, line, channel) else CUI:Print(line) end
    end
end

function OpenMenu(win, which)
    if menu and menu:IsShown() and menu.win == win and menu.which == which then CloseMenu() return end
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
        menu.rows, menu.heads, menu.sizes = {}, {}, {}
    end
    menu.win, menu.which = win, which
    local cfg = win.cfg
    for _, r in ipairs(menu.rows) do r:Hide() end
    for _, h in ipairs(menu.heads) do h:Hide() end
    for _, s in ipairs(menu.sizes) do s:Hide() end
    local y, n, nh, ns = -6, 0, 0, 0
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
        r:SetScript("OnClick", function() CloseMenu(); fn() end)
        r:Show()
        y = y - 19
    end
    local function Size(text, key, lo, hi, step)
        ns = ns + 1
        local s = MenuSize(ns)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 6, y)
        s.text:SetText(text)
        s.value:SetText(tostring(cfg[key]))
        local function Set(v)
            cfg[key] = max(lo, math.min(hi, v))
            s.value:SetText(tostring(cfg[key]))
            Layout(win)
            Paint(win)
        end
        s.minus:SetScript("OnClick", function() Set(cfg[key] - step) end)
        s.plus:SetScript("OnClick", function() Set(cfg[key] + step) end)
        s:Show()
        y = y - 21
    end
    local function Show(fn) return function() fn(); win.offset = 0; Paint(win) end end

    if which == "show" then
        Heading("Show")
        for _, m in ipairs(MODES) do
            Item(m.label, m.key == Mode(win).key, Show(function() cfg.mode = m.key end))
        end
    elseif which == "fight" then
        Heading("Fight")
        Item("Current fight", not win.segmentID and cfg.segment ~= "overall", Show(function() win.segmentID = nil; cfg.segment = "current" end))
        Item("Overall", not win.segmentID and cfg.segment == "overall", Show(function() win.segmentID = nil; cfg.segment = "overall" end))
        local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if ok and type(list) == "table" then
            local added = 0
            for i = #list, 1, -1 do -- newest first, a handful
                local s = list[i]
                if added < 12 and type(s) == "table" and type(s.sessionID) == "number" and not Secret(s.sessionID) then
                    added = added + 1
                    local name = (type(s.name) == "string" and not Secret(s.name) and s.name ~= "" and s.name) or ("Fight " .. s.sessionID)
                    local secs = s.durationSeconds
                    local shown = name
                    if type(secs) == "number" and not Secret(secs) then
                        shown = string.format("%s  %d:%02d", name, math.floor(secs / 60), math.floor(secs % 60))
                    end
                    Item(shown, win.segmentID == s.sessionID, Show(function() win.segmentID = s.sessionID; win.segmentName = name end))
                end
            end
        end
    else
        Heading("This window")
        Size("Rows", "rows", 2, 25, 1)
        Size("Width", "width", 120, 500, 10)
        Item(cfg.locked and "Unlock (drag to move)" or "Lock in place", false, function() cfg.locked = not cfg.locked and true or nil; win.PaintLock() end)
        Item("New window", false, function() NewWindow(win) end)
        if #wins > 1 then Item("Close this window", false, function() CloseWindow(win) end) end
        Item("Reset all fights", false, ResetAll)
        Heading("Report the top 5 to")
        if IsInRaid and IsInRaid() then Item("Raid", false, function() Report(win, "RAID", 5) end)
        elseif IsInGroup and IsInGroup() then Item("Party", false, function() Report(win, "PARTY", 5) end) end
        if IsInGuild and IsInGuild() then Item("Guild", false, function() Report(win, "GUILD", 5) end) end
        Item("Say", false, function() Report(win, "SAY", 5) end)
        Item("Just me", false, function() Report(win, nil, 5) end)
        Item("More settings", false, function() CUI:OpenConfig("Damage Meter") end)
    end
    menu:SetSize(200, -y + 6)
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", win.head, "TOPLEFT", -1, 3)
    catcher:Show()
    menu:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function Refresh()
    for _, win in ipairs(wins) do Layout(win) end
    UpdateShown()
    PaintAll()
end
CUI.MeterRefresh = Refresh
if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", UpdateShown) end

for _, cfg in ipairs(db.windows) do CreateWindow(cfg) end

local ev = CreateFrame("Frame")
for _, event in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, event)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "DAMAGE_METER_RESET" then
        for _, win in ipairs(wins) do win.segmentID = nil; win.offset = 0 end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then
        if event == "PLAYER_REGEN_DISABLED" and db.autoCurrent then -- a new fight: windows looking at an old one come back
            for _, win in ipairs(wins) do
                if win.segmentID then win.segmentID = nil; win.offset = 0 end
            end
        end
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
-- Settings page (what all windows share; each window's own options are on its title strip)
--------------------------------------------------------------------------------
CUI:RegisterPage("Damage Meter", function(page)
    local width = 480
    W.Header(page, "Damage Meter", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local status = W.Text(page, 12, T.text)
    status:SetPoint("TOPLEFT", 4, y)
    status:SetWidth(width - 8)
    status:SetJustifyH("LEFT")
    local okOn, why = GameOn()
    if okOn then
        status:SetText("Cys's meter windows show the game's own counts. Everything about a window is on its title strip.")
    else
        status:SetText("|cFFFF4040The game's damage meter is not available right now|r" .. ((type(why) == "string" and why ~= "") and (": " .. why) or "."))
    end
    y = y - 40
    local add = W.Button(page, 130, 24, "New window", true)
    add:SetPoint("TOPLEFT", 4, y)
    add:SetScript("OnClick", function() NewWindow(wins[1]) end)
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
    Step("Row height", "rowH", 12, 30, 1, " px")
    Step("Text size", "fontSize", 8, 18, 1)
    y = y - 6
    Check("Class-colored bars", "classColors")
    Check("Class icons", "icons")
    Check("Number each row (1. 2. 3.)", "rank")
    Check("Keep my own row in sight (last line when I am scrolled out)", "pinMe")
    Check("Spell breakdown when pointing at a row", "hover")
    Check("Breakdown shows 15 spells instead of 8", "more")
    Check("Jump back to the current fight when combat starts", "autoCurrent")
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
        { "On the window", "everything about a window is on its title strip. Clicking the title itself also opens what to show." },
        { "More windows", "each window keeps its own choice - damage in one, HPS in another, the overall total in a third. Up to " .. MAX_WINDOWS .. ". Each has its own box in Layout mode." },
        { "Buttons on the strip", "what to show, which fight, this window (rows, width, lock, close), reset all fights (click twice), and + for another window." },
        { "Moving and sizing", "drag a window by its title strip or its background; drag its bottom-right corner to make it wider or longer. The padlock beside the corner fixes it in place. Layout mode still works too." },
        { "Spell breakdown", "click a row to keep its breakdown open while you fight; click it again to close. Or just point at a row and that player's spells open beside the window: icon, name, bar and amount, with each spell's share once the fight is over. Your own row works during a fight; for other players the game decides - if it keeps their list locked the panel says so and fills in after the fight." },
        { "Where the numbers come from", "WoW Forever counts everything itself; these windows only show it. Nothing reads a combat log, so it stays light even in a raid." },
        { "The game's own window", "is only faded out. You can also set it to Hidden in the game's Edit Mode." },
        { "Details!", "its Cys skin has its own page (Details Skin), if you still use it." },
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 150) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
