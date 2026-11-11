--------------------------------------------------------------------------------
-- Cys's Cooldowns (WoW Forever) - the Cys look for Blizzard's built-in Cooldown Manager
--
-- Stage 1: looks only. The game keeps running its own cooldown, utility and buff icons (and buff bars); this
-- gives each one the Cys look: square icon, trimmed icon art, a thin edge in the Border color, a square
-- cooldown sweep, and timer and stack numbers in the UI font at sizes you choose.
--
-- Safety: nothing here moves, sizes, shows or hides a Blizzard frame, replaces a Blizzard function or reads a
-- locked value. It only changes art on the icons (texture trim, mask, alpha, fonts) and adds our own edge on
-- top. Which spells show, where the rows sit, icon size, spacing, rows and visibility all stay in Blizzard's
-- own settings (Edit Mode and the Cooldown Manager window), so the two never fight.
-- State is kept in our own weak table, never written onto Blizzard's frames.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "cooldowns", name = "Cys's Cooldowns", foreverOnly = true,
    desc = "WoW Forever: gives Blizzard's Cooldown Manager (cooldown, utility and buff icons, buff bars) the Cys look - square icons with a thin edge in your Border color, and timer and stack numbers at your size.",
    open = function() CysUI:OpenConfig("Cooldown Manager") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T

CysUIDB.cooldowns = CysUIDB.cooldowns or {}
local db = CysUIDB.cooldowns
local DEFAULTS = { look = true, bars = true, timerBig = 18, timerSmall = 12, stacks = 12, gap = 2, shade = true,
    own = false, grey = true, gcd = false, tips = false, carry = false, pack = true, range = true,
    stance = false, stanceAll = false, stanceSize = 32, auraTime = true, auraSize = 12 }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local OVERLAY_ATLAS = "ui-hud-cooldownmanager-iconoverlay"
local TRIM = 0.08 -- cuts the icon art's own baked-in border

-- viewer global name -> kind
local VIEWERS = {
    EssentialCooldownViewer = "big",
    UtilityCooldownViewer = "small",
    BuffIconCooldownViewer = "buff",
    BuffBarCooldownViewer = "bar",
}

-- another addon that rebuilds the Cooldown Manager is in charge when it is loaded
local function OtherManager()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if loaded and loaded("EllesmereUICooldownManager") then return "EllesmereUI Cooldown Manager" end
    return nil
end

--------------------------------------------------------------------------------
-- Fonts: one font object per number kind, so a size change reaches every icon at once
--------------------------------------------------------------------------------
local fontBig = CreateFont("CysCooldownTimerBig")
local fontSmall = CreateFont("CysCooldownTimerSmall")
local fontStack = CreateFont("CysCooldownStacks")
local fontAura = CreateFont("CysCooldownAuraTime") -- buff / debuff time on Cys's own icons
local function ApplyFonts()
    fontBig:SetFont(STANDARD_TEXT_FONT, db.timerBig, "OUTLINE")
    fontSmall:SetFont(STANDARD_TEXT_FONT, db.timerSmall, "OUTLINE")
    fontStack:SetFont(STANDARD_TEXT_FONT, db.stacks, "OUTLINE")
    for _, f in ipairs({ fontBig, fontSmall, fontStack }) do
        f:SetTextColor(1, 1, 1)
        f:SetShadowColor(0, 0, 0, 1)
        f:SetShadowOffset(1, -1)
    end
    fontAura:SetFont(STANDARD_TEXT_FONT, db.auraSize, "OUTLINE")
    fontAura:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    fontAura:SetShadowColor(0, 0, 0, 1)
    fontAura:SetShadowOffset(1, -1)
end
ApplyFonts()

--------------------------------------------------------------------------------
-- One icon
--------------------------------------------------------------------------------
local done = setmetatable({}, { __mode = "k" })
local icons = setmetatable({}, { __mode = "k" }) -- item -> { holder, tex, cd, oor }: the pieces the gap setting moves

-- Gap between icons. The game packs the icons edge to edge (its own rounded ring used to hide that), and its row
-- layout is not ours to change, so the gap is made inside each icon's slot: the picture, its sweep and our edge
-- are drawn a little smaller than the slot. Half the gap on each side of every icon.
local function ApplyGap(rec)
    local i = (db.gap or 0) / 2
    local tex, holder = rec.tex, rec.holder
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", holder, "TOPLEFT", i, -i)
    tex:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -i, i)
    if rec.cd then rec.cd:ClearAllPoints(); rec.cd:SetAllPoints(tex) end
    if rec.oor then rec.oor:ClearAllPoints(); rec.oor:SetAllPoints(tex) end
end
local function ApplyGaps()
    for _, rec in pairs(icons) do pcall(ApplyGap, rec) end
end

-- The game shades an icon yellow while that ability's effect is running (your Rend on the target, a buff on you)
-- and black while it is on cooldown. It sets the color again on every update, so the yellow one is caught right
-- after and softened, or cleared when the shade is switched off. The colors are the game's fixed ones (plain
-- numbers); anything locked is left alone.
local function WatchShade(cd)
    if not cd.SetSwipeColor then return end
    local busy
    hooksecurefunc(cd, "SetSwipeColor", function(self, r, g, b)
        if busy or type(r) ~= "number" or type(b) ~= "number" then return end
        if CysUICompat.Secret(r) or CysUICompat.Secret(b) then return end
        if r > 0.9 and b > 0.3 then
            busy = true
            self:SetSwipeColor(r, g, b, db.shade and 0.3 or 0)
            busy = false
        end
    end)
end

-- holder: the frame that owns the icon's art; tex: the icon texture; above: a frame our edge must sit over
local function SquareIcon(holder, tex, above)
    for _, r in ipairs({ holder:GetRegions() }) do
        if r ~= tex and r.IsObjectType then
            if r:IsObjectType("MaskTexture") then
                if tex.RemoveMaskTexture then pcall(tex.RemoveMaskTexture, tex, r) end -- the rounded corners
            elseif r:IsObjectType("Texture") and r.GetAtlas then
                local atlas = r:GetAtlas()
                if type(atlas) == "string" and atlas:lower() == OVERLAY_ATLAS then r:SetAlpha(0) end -- the bevel ring
            end
        end
    end
    tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)

    local back = holder:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(tex)
    back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)

    local edge = CreateFrame("Frame", nil, holder)
    edge:SetAllPoints(tex)
    edge:SetFrameLevel(((above and above:GetFrameLevel()) or holder:GetFrameLevel()) + 1)
    W.Border(edge, 1, T.border, "OVERLAY") -- follows the Border color setting
    return edge
end

local function StackFont(fs)
    if fs and fs.SetFontObject then fs:SetFontObject(fontStack) end
end

local function SkinItem(item, kind)
    if done[item] or not item then return end
    done[item] = true
    if kind == "bar" then
        local iconFrame = item.Icon
        local tex = iconFrame and iconFrame.Icon
        if tex then
            SquareIcon(iconFrame, tex)
            StackFont(iconFrame.Applications)
        end
        local bar = item.Bar
        if bar and db.bars then
            bar:SetStatusBarTexture(FLAT)
            local fill = bar:GetStatusBarTexture()
            if fill then
                fill:SetVertexColor(T.brand[1], T.brand[2], T.brand[3], 0.85)
            end
            if bar.BarBG then bar.BarBG:SetAlpha(0) end
            local back = bar:CreateTexture(nil, "BACKGROUND")
            back:SetAllPoints(bar)
            back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.85)
            local edge = CreateFrame("Frame", nil, bar)
            edge:SetAllPoints(bar)
            edge:SetFrameLevel(bar:GetFrameLevel() + 1)
            W.Border(edge, 1, T.line, "OVERLAY")
            if bar.Name then bar.Name:SetFontObject(fontSmall) end
            if bar.Duration then bar.Duration:SetFontObject(fontSmall) end
        end
        return
    end

    local tex = item.Icon
    if not (tex and tex.SetTexCoord) then return end
    local cd = item.Cooldown
    SquareIcon(item, tex, cd)
    local rec = { holder = item, tex = tex, cd = cd, oor = item.OutOfRange }
    icons[item] = rec
    pcall(ApplyGap, rec)
    if cd then
        if kind ~= "buff" then pcall(WatchShade, cd) end
        if cd.SetSwipeTexture then cd:SetSwipeTexture(FLAT) end -- a square sweep to match the square icon
        if cd.SetCountdownFont then cd:SetCountdownFont(kind == "big" and "CysCooldownTimerBig" or "CysCooldownTimerSmall") end
    end
    StackFont(item.ChargeCount and item.ChargeCount.Current)
    StackFont(item.Applications and item.Applications.Applications)
end

--------------------------------------------------------------------------------
-- Stage 2: Cys's own cooldown bars
--
-- The game's cooldown and utility rows are replaced by two bars of our own. They show the same spells in the
-- same order (still chosen in the game's Cooldown Manager), but the frames are ours: they move in Layout mode,
-- take their size, gap and row length from this page, and each spell can be hidden in stances you pick.
--
-- How it stays safe: we never move or re-parent the game's icons. We only read which cooldown sits in which
-- slot (after the game has laid its rows out), fade the game's two rows to nothing, and draw our own icons.
-- Cooldowns come from the game's own timer objects (C_Spell.GetSpellCooldownDuration), which a Cooldown frame
-- can show in combat without us ever reading a locked number.
--------------------------------------------------------------------------------
local OWN = {
    { key = "main",    name = "Main bar",    label = "Cooldowns: main",    viewer = "EssentialCooldownViewer", font = "CysCooldownTimerBig",   y = -150 },
    { key = "utility", name = "Utility bar", label = "Cooldowns: utility", viewer = "UtilityCooldownViewer",   font = "CysCooldownTimerSmall", y = -196 },
}
db.bar = db.bar or {}
db.bar.main = db.bar.main or { size = 40, perRow = 12 }
db.bar.utility = db.bar.utility or { size = 30, perRow = 12 }
-- Bars you make yourself (Your bars, New bar): db.custom = { { key = "c1", name = "Bar 3" }, ... }. A bar of your own
-- has no row in the game behind it; it only holds the spells you put on it, per class like the two above.
db.custom = db.custom or {}
local function CustomDef(c, i)
    db.bar[c.key] = db.bar[c.key] or { size = 30, perRow = 12 }
    return { key = c.key, name = c.name or ("Bar " .. (i + 2)), label = "Cooldowns: " .. (c.name or ("Bar " .. (i + 2))),
        font = "CysCooldownTimerSmall", y = -196 - 40 * i, custom = c }
end
for i, c in ipairs(db.custom) do OWN[#OWN + 1] = CustomDef(c, i) end
db.stanceHide = db.stanceHide or {} -- [spellID] = { [stance key] = true } : hidden in that stance
db.order = db.order or {} -- (0.58.7 test builds) old drag order; only used once to seed db.layout
-- Your bars, per class: db.layout[CLASS][bar key] = { spellID, ... } in your order, plus .seen = spells already
-- offered to you (so a spell you took off a bar stays off, while a newly tracked one still shows up by itself).
db.layout = db.layout or {}
local CLASS = select(2, UnitClass("player")) or "ALL"
db.layout[CLASS] = db.layout[CLASS] or {}
local mine = db.layout[CLASS]
mine.seen = mine.seen or {}
local avail = {} -- spellID -> entry: every spell you know that the game can track (these can show on a bar)
local universe = {} -- spellID -> entry: the same plus spells you have not learned yet (entry.known = false)

local Secret = CysUICompat.Secret
local ownBars = {}
local ownActive = false
local SaveOrder, Unplaced
local AddSpell, Waiting, DropWaiting
local NewBar, DeleteBar, LayoutOwn
local AttachAuras, RefreshTargetAuras

-- which stance / form is up: the stance's own spell ID when the game gives one, else its position on the bar
local function StanceKey(i)
    if not i or i == 0 then return 0 end
    local _, _, _, spellID = GetShapeshiftFormInfo(i)
    if type(spellID) == "number" and not Secret(spellID) and spellID > 0 then return spellID end
    return i
end
local function CurrentStance()
    local i = GetShapeshiftForm and GetShapeshiftForm()
    if type(i) ~= "number" or Secret(i) then return 0 end
    return StanceKey(i)
end

local function MakeIcon(bar)
    local f = CreateFrame("Frame", nil, bar.holder)
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetAllPoints()
    f.back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetDrawEdge(false)
    f.cd:SetSwipeTexture(FLAT)
    f.cd:SetSwipeColor(0, 0, 0, 0.7)
    f.cd:SetHideCountdownNumbers(false)
    if f.cd.SetCountdownFont then f.cd:SetCountdownFont(bar.def.font) end
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    W.Border(top, 1, T.border, "OVERLAY")
    f.count = top:CreateFontString(nil, "OVERLAY")
    f.count:SetFontObject(fontStack)
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    f:SetScript("OnEnter", function(self)
        if not (db.tips and self.entry) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then pcall(GameTooltip.SetSpellByID, GameTooltip, self.entry.spell) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- Range. The game tells us when a spell goes in or out of range of the current target, once we ask it to watch
-- that spell (the same service its own cooldown rows use). Nothing is polled.
local rangeWatched, outOfRange = {}, {}
local function WatchRange(spell)
    if rangeWatched[spell] or not (C_Spell.EnableSpellRangeCheck and C_Spell.IsSpellInRange) then return end
    rangeWatched[spell] = true
    local ok, has = pcall(C_Spell.SpellHasRange, spell)
    if not ok or Secret(has) or not has then return end
    pcall(C_Spell.EnableSpellRangeCheck, spell, true) -- never switched off again: the game's own rows share it
    local ok2, inRange = pcall(C_Spell.IsSpellInRange, spell)
    outOfRange[spell] = ok2 and not Secret(inRange) and inRange == false or nil
end
local function RecheckRange()
    for spell in pairs(rangeWatched) do
        local ok, inRange = pcall(C_Spell.IsSpellInRange, spell)
        outOfRange[spell] = ok and not Secret(inRange) and inRange == false or nil
    end
end

-- one icon's picture, cooldown, count and usable tint. Every game answer that could be locked goes straight
-- into a widget (or through pcall); none is compared or used in math here.
local function UpdateIcon(f)
    local e = f.entry
    if not e then return end
    local spell = e.spell
    local tex = C_Spell.GetSpellTexture(spell)
    if tex then f.tex:SetTexture(tex) end

    local dur
    if e.charges and C_Spell.GetSpellChargeDuration then dur = C_Spell.GetSpellChargeDuration(spell) end
    if not dur and C_Spell.GetSpellCooldownDuration then dur = C_Spell.GetSpellCooldownDuration(spell, not db.gcd) end
    if dur and f.cd.SetCooldownFromDurationObject then
        pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur, true)
    else
        f.cd:Clear()
    end

    -- grey while it is really on cooldown (the global cooldown is left out of the timer above unless switched on)
    -- The global cooldown never counts as "on cooldown" here, also when its sweep is switched on: that is asked
    -- for separately, so a bar full of ready abilities does not go grey on every global cooldown.
    local real = dur
    if db.gcd and dur and not e.charges then real = C_Spell.GetSpellCooldownDuration(spell, true) end
    local greyed = false
    if db.grey and real and not e.charges and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local ok, zero = pcall(real.IsZero, real)
        if ok then
            local ok2, v = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, zero, 0, 1)
            if ok2 and pcall(f.tex.SetDesaturation, f.tex, v) then greyed = true end
        end
    end
    if not greyed then f.tex:SetDesaturation(0) end

    if e.charges and C_Spell.GetSpellDisplayCount then
        local ok, text = pcall(C_Spell.GetSpellDisplayCount, spell)
        if ok then pcall(f.count.SetText, f.count, text) else f.count:SetText("") end
    else
        f.count:SetText("")
    end

    local r, g, b = 1, 1, 1
    WatchRange(spell)
    if db.range and (outOfRange[spell] or outOfRange[e.base]) then
        r, g, b = 0.9, 0.2, 0.2 -- target out of range for this spell
    elseif C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, spell)
        if ok and not Secret(usable) and not Secret(noPower) then
            if noPower then r, g, b = 0.45, 0.45, 1
            elseif usable == false then r, g, b = 0.45, 0.45, 0.45 end
        end
    end
    f.tex:SetVertexColor(r, g, b)
end

local function LayoutBar(bar)
    local set = db.bar[bar.def.key]
    local size, gap = set.size, db.gap or 0
    local perRow = max(1, set.perRow)
    local stance = CurrentStance()
    local shown = 0
    for _, e in ipairs(bar.list) do
        local hide = db.stanceHide[e.base]
        if not (hide and hide[stance]) then
            shown = shown + 1
            local f = bar.icons[shown]
            if not f then f = MakeIcon(bar); bar.icons[shown] = f end
            f.entry = e
        end
    end
    for i = shown + 1, #bar.icons do bar.icons[i]:Hide(); bar.icons[i].entry = nil end

    local cols = math.min(max(shown, 1), perRow)
    local rows = max(1, math.ceil(shown / perRow))
    local w = cols * size + (cols - 1) * gap
    bar.holder:SetSize(w, rows * size + (rows - 1) * gap)
    for i = 1, shown do
        local f = bar.icons[i]
        local row = math.floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        local inRow = math.min(perRow, shown - row * perRow)
        local rowW = inRow * size + (inRow - 1) * gap
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", (w - rowW) / 2 + col * (size + gap), -row * (size + gap)) -- short rows sit centered
        f:SetMouseClickEnabled(false)
        f:SetMouseMotionEnabled(db.tips and true or false)
        f:Show()
        UpdateIcon(f)
    end
    AttachAuras(bar, shown, size)
    CUI:ApplyLayout("cooldowns_" .. bar.def.key) -- the Layout mode box follows the bar's size
end

function LayoutOwn()
    for _, bar in ipairs(ownBars) do LayoutBar(bar) end
end

--------------------------------------------------------------------------------
-- Buff / debuff time on Cys's own icons
--
-- While an ability's own effect is running (your Rend on the target, Battle Shout on you) the icon shows how long
-- is left: a small gold number at the top and a thin gold line draining along the bottom. The cooldown keeps the
-- middle of the icon, so the two never fight for the same spot.
--
-- Addons can't read buffs or debuffs in combat, so the game draws these itself: each icon that has an effect gets
-- a tiny one-slot aura container (the game's own widget) limited to that ability's spells. It only shows your own
-- effects: helpful ones on you, harmful ones on your target. We never read a value from it.
--------------------------------------------------------------------------------
local auraHosts = {} -- [base spell] = { frame, size, bar, containers }
local function AuraIDs(info, base, spell)
    local ids, n = {}, 0
    if type(info.linkedSpellIDs) == "table" then
        for _, id in ipairs(info.linkedSpellIDs) do
            if type(id) == "number" and not Secret(id) then ids[id] = true; n = n + 1 end
        end
    end
    if n == 0 and info.hasAura == false and info.selfAura == false then return nil end -- the game says: no effect to time
    ids[base] = true
    ids[spell] = true
    local units
    if info.selfAura == true then units = { "player" } elseif info.selfAura == false then units = { "target" } else units = { "player", "target" } end
    return { ids = ids, units = units }
end
local function AuraButton(size)
    return function(button)
        pcall(button.SetSize, button, size, size) -- the group layout only spaces the slot, it never sizes it
        pcall(button.EnableMouse, button, false)
        local line = CreateFrame("StatusBar", nil, button)
        line:SetPoint("BOTTOMLEFT", 1, 1)
        line:SetPoint("BOTTOMRIGHT", -1, 1)
        line:SetHeight(max(2, math.floor(size / 12)))
        line:SetStatusBarTexture(FLAT)
        line:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3], 1)
        local under = line:CreateTexture(nil, "BACKGROUND")
        under:SetAllPoints()
        under:SetColorTexture(0, 0, 0, 0.85)
        local left = button:CreateFontString(nil, "OVERLAY")
        left:SetFontObject(fontAura)
        left:SetPoint("TOP", 0, -2)
        local stacks = button:CreateFontString(nil, "OVERLAY")
        stacks:SetFontObject(fontStack)
        stacks:SetPoint("BOTTOMLEFT", 2, 5)
        local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        if not (button.SetDurationBar and pcall(button.SetDurationBar, button, line, { direction = dir })) then line:Hide() end
        if not (button.SetDurationText and pcall(button.SetDurationText, button, left, {})) then left:Hide() end
        if not (button.SetApplicationCount and pcall(button.SetApplicationCount, button, stacks, {})) then stacks:Hide() end
    end
end
local function AuraContainer(host, unit, ids, size)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0) -- placed and sized before any group, so it can draw at once
    c:SetSize(1, 1)
    local dirs = AnchorUtil and AnchorUtil.FlowDirection
    pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
    if dirs then pcall(c.SetFlowLayoutGrowthDirection, c, dirs.Right, dirs.Down) end
    local okG, err = pcall(c.AddAuraGroup, c, "cys", unit == "player" and "HELPFUL|PLAYER" or "HARMFUL|PLAYER", {
        maxFrameCount = 1,
        initializeFrame = AuraButton(size),
        candidateFilters = { includeSpellIDs = ids },
        layout = { elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 },
    })
    if not okG then
        CysUICompat.errors[#CysUICompat.errors + 1] = "Cooldown aura time: " .. tostring(err)
        c:Hide()
        return nil
    end
    pcall(c.SetEnabled, c, true) -- a new container reads nothing until it is switched on
    pcall(c.SetUnit, c, unit)
    pcall(c.UpdateAllAuras, c)
    c.cysUnit = unit
    return c
end
local function AuraHost(e, size)
    local h = auraHosts[e.base]
    if h and h.size == size then return h end
    if h then -- icon size changed: the slot is rebuilt at the new size
        for _, c in ipairs(h.containers) do pcall(c.SetEnabled, c, false); c:Hide() end
        h.frame:Hide()
    end
    h = { size = size, containers = {}, frame = CreateFrame("Frame", nil, UIParent) }
    auraHosts[e.base] = h
    for _, unit in ipairs(e.aura.units) do
        local c = AuraContainer(h.frame, unit, e.aura.ids, size)
        if c then h.containers[#h.containers + 1] = c end
    end
    return h
end
function AttachAuras(bar, shown, size)
    local able = db.auraTime and CysUICompat.HasAuraContainers and CysUICompat.HasAuraContainers()
    local used = {}
    if able then
        for i = 1, shown do
            local f = bar.icons[i]
            local e = f.entry
            if e and e.aura then
                local ok, h = pcall(AuraHost, e, size)
                if ok and h then
                    used[h] = true
                    h.bar = bar
                    h.frame:SetParent(f)
                    h.frame:ClearAllPoints()
                    h.frame:SetAllPoints(f)
                    h.frame:SetFrameLevel(f:GetFrameLevel() + 8)
                    h.frame:Show()
                end
            end
        end
    end
    for _, h in pairs(auraHosts) do
        if h.bar == bar and not used[h] then h.frame:Hide() end
    end
end
function RefreshTargetAuras()
    for _, h in pairs(auraHosts) do
        for _, c in ipairs(h.containers) do
            if c.cysUnit == "target" then pcall(c.UpdateAllAuras, c) end
        end
    end
end

-- read which cooldown the game put in which slot of its row
local function ReadRow(bar)
    if not bar.def.viewer then return end -- a bar of your own: no game row behind it
    local viewer = _G[bar.def.viewer]
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return end
    local slots = {}
    for item in pool:EnumerateActive() do
        local id, index = item.cooldownID, item.layoutIndex
        if type(id) == "number" and type(index) == "number" and not Secret(id) and not Secret(index) then
            slots[#slots + 1] = { id = id, index = index }
        end
    end
    if #slots == 0 and (#bar.game > 0) and not viewer:IsShown() then return end -- row not filled right now: keep what we have
    table.sort(slots, function(a, b) return a.index < b.index end)
    local list = {}
    for _, s in ipairs(slots) do
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, s.id)
        if ok and type(info) == "table" and type(info.spellID) == "number" and not Secret(info.spellID) then
            local spell = info.overrideSpellID
            if type(spell) ~= "number" or Secret(spell) or spell == 0 then spell = info.spellID end
            list[#list + 1] = { id = s.id, base = info.spellID, spell = spell, charges = info.charges == true,
                aura = AuraIDs(info, info.spellID, spell) }
        end
    end
    bar.game = list
end

-- put your bars together from the game's rows and your saved layout
local function Compose()
    wipe(avail)
    wipe(universe)
    -- everything the game can track for this class in its cooldown and utility groups, learned or not. Our icons
    -- only need the spell, so a spell does not have to be shown in the game's own rows to sit on one of yours.
    if C_CooldownViewer.GetCooldownViewerCategorySet then
        for cat = 0, 1 do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                    if ok2 and type(info) == "table" and type(info.spellID) == "number" and not Secret(info.spellID) then
                        local spell = info.overrideSpellID
                        if type(spell) ~= "number" or Secret(spell) or spell == 0 then spell = info.spellID end
                        local e = { id = id, base = info.spellID, spell = spell, charges = info.charges == true, known = info.isKnown == true,
                            aura = AuraIDs(info, info.spellID, spell) }
                        universe[e.base] = e
                        if e.known then avail[e.base] = e end
                    end
                end
            end
        end
    end
    for _, bar in ipairs(ownBars) do
        for _, e in ipairs(bar.game) do e.known = true; avail[e.base] = e; universe[e.base] = e end
    end
    for _, bar in ipairs(ownBars) do
        local key = bar.def.key
        local ids = mine[key]
        if not ids and bar.def.custom then ids = {}; mine[key] = ids end -- a bar of your own starts empty
        if not ids then
            if #bar.game > 0 then -- first time on this class: start from the game's row as it is
                ids = {}
                local rank = db.order[key]
                local start = {}
                for i, e in ipairs(bar.game) do start[i] = e; e.sort = (rank and rank[e.base]) or (1000 + i) end
                table.sort(start, function(a, b) return a.sort < b.sort end)
                for _, e in ipairs(start) do ids[#ids + 1] = e.base; mine.seen[e.base] = true end
                mine[key] = ids
            end
        else
            for _, e in ipairs(bar.game) do -- a spell the game started tracking since: goes on the end by itself
                if not mine.seen[e.base] then mine.seen[e.base] = true; ids[#ids + 1] = e.base end
            end
        end
        local list, on = {}, {}
        for _, id in ipairs(ids or {}) do
            local e = avail[id]
            if e and not on[id] then on[id] = true; list[#list + 1] = e end
        end
        bar.list = list
    end
end

-- after an edit on the settings page: the bar's list is the new truth. Spells saved for this bar that the game
-- is not tracking right now (unlearned, untracked) keep their place at the end for when they come back.
function SaveOrder(bar)
    local key = bar.def.key
    local ids, on = {}, {}
    for _, e in ipairs(bar.list) do ids[#ids + 1] = e.base; on[e.base] = true; mine.seen[e.base] = true end
    for _, id in ipairs(mine[key] or {}) do
        if not on[id] and not avail[id] then ids[#ids + 1] = id end
    end
    mine[key] = ids
end

-- trackable spells that are on none of your bars: the ones you know first, then the ones not learned yet
function Unplaced()
    local on = {}
    for _, def in ipairs(OWN) do
        for _, id in ipairs(mine[def.key] or {}) do on[id] = true end
    end
    local free = {}
    for id, e in pairs(universe) do
        if not on[id] then free[#free + 1] = e end
    end
    table.sort(free, function(a, b)
        if a.known ~= b.known then return a.known end
        return (C_Spell.GetSpellName(a.spell) or "") < (C_Spell.GetSpellName(b.spell) or "")
    end)
    return free
end

-- spells saved for a bar that you have not learned yet (they wait at the end of the bar)
function Waiting(bar)
    local out, on = {}, {}
    for _, e in ipairs(bar.list) do on[e.base] = true end
    for _, id in ipairs(mine[bar.def.key] or {}) do
        local e = universe[id]
        if e and not on[id] and not avail[id] then on[id] = true; out[#out + 1] = e end
    end
    return out
end
function DropWaiting(bar, e)
    local ids = mine[bar.def.key] or {}
    for i = #ids, 1, -1 do
        if ids[i] == e.base then table.remove(ids, i) end
    end
end

-- put a spell on a bar. One you have not learned yet is saved for the bar and shows up by itself once you know it.
function AddSpell(bar, e)
    local key = bar.def.key
    mine.seen[e.base] = true
    if avail[e.base] then
        bar.list[#bar.list + 1] = avail[e.base]
        SaveOrder(bar)
    else
        mine[key] = mine[key] or {}
        table.insert(mine[key], e.base)
    end
end

local syncQueued, updateQueued
local function SyncOwn()
    syncQueued = false
    if not ownActive then return end
    for _, bar in ipairs(ownBars) do pcall(ReadRow, bar) end
    Compose()
    LayoutOwn()
end
local function QueueSync()
    if syncQueued or not ownActive then return end
    syncQueued = true
    C_Timer.After(0, SyncOwn) -- after the game has finished filling its rows
end
local function QueueUpdate()
    if updateQueued or not ownActive then return end
    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        for _, bar in ipairs(ownBars) do
            for _, f in ipairs(bar.icons) do
                if f.entry then UpdateIcon(f) end
            end
        end
    end)
end

-- the game's row: faded out and deaf to the mouse, never hidden or moved (it is an Edit Mode piece)
local function QuietRow(viewer)
    local busy
    local function Fade()
        if busy then return end
        busy = true
        viewer:SetAlpha(0)
        busy = false
    end
    local function Mouse()
        local pool = viewer.itemFramePool
        if not (pool and pool.EnumerateActive) then return end
        for item in pool:EnumerateActive() do
            if item.SetMouseMotionEnabled then item:SetMouseMotionEnabled(false) end
        end
    end
    Fade(); Mouse()
    hooksecurefunc(viewer, "SetAlpha", Fade)
    if type(viewer.RefreshLayout) == "function" then
        hooksecurefunc(viewer, "RefreshLayout", function() Mouse(); QueueSync() end)
    end
    if type(viewer.RefreshData) == "function" then hooksecurefunc(viewer, "RefreshData", QueueSync) end
    if type(viewer.SetTooltipsShown) == "function" then hooksecurefunc(viewer, "SetTooltipsShown", Mouse) end
end

local function MakeBar(def)
    local holder = CreateFrame("Frame", "CysCooldownBar_" .. def.key, UIParent)
    holder:SetSize(200, db.bar[def.key].size)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, def.y)
    holder:SetFrameStrata("MEDIUM")
    local bar = { def = def, holder = holder, icons = {}, list = {}, game = {} }
    ownBars[#ownBars + 1] = bar
    CUI:RegisterMovable(holder, "cooldowns_" .. def.key, def.label, { point = "CENTER", x = 0, y = def.y })
    return bar
end

-- a new bar of your own: empty, placed under the others, ready for spells from the + box
function NewBar()
    if not ownActive then return end
    db.customSeq = (db.customSeq or 0) + 1
    local c = { key = "c" .. db.customSeq, name = "Bar " .. (#db.custom + 3) }
    db.custom[#db.custom + 1] = c
    local def = CustomDef(c, #db.custom)
    OWN[#OWN + 1] = def
    local bar = MakeBar(def)
    Compose()
    LayoutOwn()
    return bar
end
-- remove a bar of your own for good: its spells go back to the unplaced list
function DeleteBar(bar)
    local def = bar and bar.def
    if not (def and def.custom) then return end
    for i = #db.custom, 1, -1 do if db.custom[i] == def.custom then table.remove(db.custom, i) end end
    for i = #OWN, 1, -1 do if OWN[i] == def then table.remove(OWN, i) end end
    for i = #ownBars, 1, -1 do if ownBars[i] == bar then table.remove(ownBars, i) end end
    for _, perClass in pairs(db.layout) do perClass[def.key] = nil end
    db.bar[def.key] = nil
    for _, h in pairs(auraHosts) do if h.bar == bar then h.frame:Hide() end end
    bar.holder:Hide()
    -- its Layout mode box goes too
    local mkey = "cooldowns_" .. def.key
    local m = CUI.movers and CUI.movers[mkey]
    if m then
        if m.mover then m.mover:Hide() end
        CUI.movers[mkey] = nil
        for i = #(CUI.moverOrder or {}), 1, -1 do if CUI.moverOrder[i] == mkey then table.remove(CUI.moverOrder, i) end end
        if CysUIDB.layout then CysUIDB.layout[mkey] = nil end
    end
    LayoutOwn()
end

local function StartOwn()
    if ownActive or not db.own or OtherManager() then return end
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo and C_Spell and C_Spell.GetSpellCooldownDuration) then return end
    for _, def in ipairs(OWN) do
        if def.viewer and not _G[def.viewer] then return end -- the game's Cooldown Manager isn't loaded yet
    end
    ownActive = true
    for _, def in ipairs(OWN) do
        MakeBar(def)
        if def.viewer then pcall(QuietRow, _G[def.viewer]) end
    end
    local oe = CreateFrame("Frame")
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
        "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "COOLDOWN_VIEWER_DATA_LOADED", "SPELL_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED" }) do
        pcall(oe.RegisterEvent, oe, event)
    end
    oe:SetScript("OnEvent", function(_, event, spellID, inRange, checksRange)
        if event == "SPELL_RANGE_CHECK_UPDATE" then
            if type(spellID) == "number" and not Secret(spellID) and not Secret(inRange) and not Secret(checksRange) then
                outOfRange[spellID] = (checksRange == true and inRange == false) or nil
                QueueUpdate()
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            RecheckRange()
            RefreshTargetAuras()
            QueueUpdate()
        elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "SPELL_UPDATE_USABLE"
            or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            QueueUpdate()
        elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
            LayoutOwn() -- our own frames: free to re-arrange in combat
        else
            QueueSync()
        end
    end)
    QueueSync()
end

--------------------------------------------------------------------------------
-- Tracked buffs and buff bars: moved with Cys's Layout mode
--
-- Buffs can't be rebuilt as our own icons (addons can't read them in combat), so these two rows stay the game's.
-- To still place them in Layout mode, each icon is carried over to a holder of ours right after the game lays its
-- row out: same anchor, same offsets, only measured from our holder instead of the game's row. The game's row
-- frame itself (an Edit Mode piece) is never moved, and how the icons sit next to each other is still the
-- game's own layout - including closing the gaps as buffs come and go.
--------------------------------------------------------------------------------
local CARRY = {
    { key = "buffs",    label = "Cooldowns: buffs",     viewer = "BuffIconCooldownViewer", x = 0,   y = -104, pack = true },
    { key = "buffbars", label = "Cooldowns: buff bars", viewer = "BuffBarCooldownViewer",  x = 260, y = -104 },
}
local carryActive = false
local function CarryRow(def)
    local viewer = _G[def.viewer]
    if not viewer or type(viewer.Layout) ~= "function" then return end
    local key = "cooldowns_" .. def.key
    local holder = CreateFrame("Frame", "CysCooldownBar_" .. def.key, UIParent)
    holder:SetSize(120, 30)
    holder:SetPoint("CENTER", UIParent, "CENTER", def.x, def.y)
    CUI:RegisterMovable(holder, key, def.label, { point = "CENTER", x = def.x, y = def.y })
    local lastW, lastH
    local hookedItems = setmetatable({}, { __mode = "k" })
    local queued
    local Carry
    local function Queue()
        if queued then return end
        queued = true
        C_Timer.After(0, function() queued = false; pcall(Carry) end)
    end
    local function Size(w, h)
        w, h = max(w, 1), max(h, 1)
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            holder:SetSize(w, h)
            CUI:ApplyLayout(key)
        end
    end
    -- Buff icons, packed: the game keeps an empty slot for a tracked buff that is not up. Here the icons that are
    -- showing are lined up side by side, centered on the Layout mode box, in the game's order, and re-packed
    -- every time one appears or runs out.
    local function Pack(pool)
        local shown = {}
        for item in pool:EnumerateActive() do
            if not hookedItems[item] then
                hookedItems[item] = true
                item:HookScript("OnShow", Queue)
                item:HookScript("OnHide", Queue)
            end
            local ok, vis = pcall(item.IsShown, item)
            if ok and not Secret(vis) and vis and type(item.layoutIndex) == "number" and not Secret(item.layoutIndex) then
                shown[#shown + 1] = item
            end
        end
        if #shown == 0 then return end
        table.sort(shown, function(a, b) return a.layoutIndex < b.layoutIndex end)
        local hs = holder:GetEffectiveScale() or 1
        -- Same spacing as Cys's own bars: Gap between icons. With the Cys look on, that gap is already drawn inside
        -- each icon's slot (half on each side), so the slots sit edge to edge; without the look it goes between them.
        -- (The game's own padding can be negative, which made the square icons overlap.)
        local pad = db.look and 0 or (db.gap or 0)
        local total, tall = 0, 1
        local wide, ratio = {}, {} -- kept here, never written onto the game's frames
        for i, item in ipairs(shown) do
            local r = (item:GetEffectiveScale() or 1) / hs
            wide[i], ratio[i] = item:GetWidth() * r, r
            total = total + wide[i] + (i > 1 and pad or 0)
            tall = max(tall, item:GetHeight() * r)
        end
        Size(total, tall)
        local x = -total / 2
        for i, item in ipairs(shown) do
            item:ClearAllPoints()
            item:SetPoint("LEFT", holder, "CENTER", x / ratio[i], 0)
            x = x + wide[i] + pad
        end
    end
    Carry = function()
        local pool = viewer.itemFramePool
        if not (pool and pool.EnumerateActive) then return end
        if def.pack and db.pack then
            Pack(pool)
            return
        end
        local w, h = viewer:GetSize()
        if type(w) ~= "number" or type(h) ~= "number" or Secret(w) or Secret(h) then return end
        local ratio = (viewer:GetEffectiveScale() or 1) / (holder:GetEffectiveScale() or 1)
        Size(w * ratio, h * ratio) -- same size as the game's row, so the row stays centered on its Layout mode box
        for item in pool:EnumerateActive() do
            local point, rel, relPoint, x, y = item:GetPoint(1)
            -- only icons the game has just placed (still anchored to its own row); ours are left alone
            if rel == viewer and type(x) == "number" and type(y) == "number" and not Secret(x) and not Secret(y) then
                item:ClearAllPoints()
                item:SetPoint(point, holder, relPoint, x, y)
            end
        end
    end
    hooksecurefunc(viewer, "Layout", function() pcall(Carry) end)
    if def.pack then
        local pe = CreateFrame("Frame")
        pe:RegisterUnitEvent("UNIT_AURA", "player")
        pe:SetScript("OnEvent", Queue)
    end
    pcall(Carry)
end
local function StartCarry()
    if carryActive or not db.carry or OtherManager() then return end
    for _, def in ipairs(CARRY) do
        if not _G[def.viewer] then return end
    end
    carryActive = true
    for _, def in ipairs(CARRY) do pcall(CarryRow, def) end
end

--------------------------------------------------------------------------------
-- Stance / form icon: your current stance as its own piece
--
-- For classes with stances or forms (Warrior, Druid, Rogue stealth, Priest Shadowform...). Our own frame, placed
-- in Layout mode, so the stance no longer has to be tracked as a buff in the game's buff row. Either just the
-- stance you are in, or all of them with the current one lit. Which stance is up is a plain value the game lets
-- addons read, in or out of combat.
--------------------------------------------------------------------------------
local stanceBar
local function LayoutStance()
    if not stanceBar then return end
    local size, gap = db.stanceSize, db.gap or 0
    local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    local current = GetShapeshiftForm and GetShapeshiftForm() or 0
    if type(current) ~= "number" or Secret(current) then current = 0 end
    local shown = 0
    for i = 1, count do
        if db.stanceAll or i == current then
            shown = shown + 1
            local f = stanceBar.icons[shown]
            if not f then
                f = CreateFrame("Frame", nil, stanceBar.holder)
                f.back = f:CreateTexture(nil, "BACKGROUND")
                f.back:SetAllPoints()
                f.back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)
                f.tex = f:CreateTexture(nil, "ARTWORK")
                f.tex:SetAllPoints()
                f.tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
                f.edges = W.Border(f, 1, T.border, "OVERLAY")
                stanceBar.icons[shown] = f
            end
            f.tex:SetTexture((GetShapeshiftFormInfo(i)))
            local lit = i == current
            f.tex:SetDesaturated(not lit)
            f.tex:SetAlpha(lit and 1 or 0.45)
            W.SetBorder(f.edges, lit and T.border or T.line)
            f:SetSize(size, size)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", stanceBar.holder, "TOPLEFT", (shown - 1) * (size + gap), 0)
            f:Show()
        end
    end
    for i = shown + 1, #stanceBar.icons do stanceBar.icons[i]:Hide() end
    -- with only the current stance shown the box keeps one icon's size, even in no stance at all
    local cols = max(shown, 1)
    stanceBar.holder:SetSize(cols * size + (cols - 1) * gap, size)
    CUI:ApplyLayout("cooldowns_stance")
end
local function StartStance()
    if stanceBar or not db.stance or OtherManager() then return end
    if not (GetNumShapeshiftForms and GetNumShapeshiftForms() > 0) then return end -- this class has none (checked again later)
    local holder = CreateFrame("Frame", "CysCooldownBar_stance", UIParent)
    holder:SetSize(db.stanceSize, db.stanceSize)
    holder:SetPoint("CENTER", UIParent, "CENTER", -260, -60)
    holder:SetFrameStrata("MEDIUM")
    stanceBar = { holder = holder, icons = {} }
    CUI:RegisterMovable(holder, "cooldowns_stance", "Stance", { point = "CENTER", x = -260, y = -60 })
    local se = CreateFrame("Frame")
    for _, event in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        pcall(se.RegisterEvent, se, event)
    end
    se:SetScript("OnEvent", LayoutStance)
    LayoutStance()
end

--------------------------------------------------------------------------------
-- The viewers: skin what is there, then every icon the game hands out later
--------------------------------------------------------------------------------
local hooked = {}
local function SetupViewer(name, kind)
    local viewer = _G[name]
    if not viewer or hooked[name] then return end
    hooked[name] = true
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for item in pool:EnumerateActive() do pcall(SkinItem, item, kind) end
    end
    if type(viewer.OnAcquireItemFrame) == "function" then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item) pcall(SkinItem, item, kind) end)
    end
end

local function Setup()
    if OtherManager() then return end
    if db.look then
        for name, kind in pairs(VIEWERS) do pcall(SetupViewer, name, kind) end
    end
    StartOwn()
    StartCarry()
    StartStance()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_CooldownViewer" then return end
    Setup()
end)
Setup()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Cooldown Manager", function(page)
    local width = 480
    W.Header(page, "Cooldown Manager", width):SetPoint("TOPLEFT", 0, -4)

    local y = -34
    local status = W.Text(page, 12, T.text)
    status:SetPoint("TOPLEFT", 4, y)
    status:SetWidth(width - 8)
    status:SetJustifyH("LEFT")
    local other = OtherManager()
    local gameOn = true
    if C_CVar and C_CVar.GetCVarBool then
        local ok, v = pcall(C_CVar.GetCVarBool, "cooldownViewerEnabled")
        if ok and v == false then gameOn = false end
    end
    if other then
        status:SetText("|cFFFF4040" .. other .. " is loaded|r, so it styles the cooldown icons and Cys's UI leaves them alone.")
    elseif not gameOn then
        status:SetText("|cFFFF4040The game's Cooldown Manager is switched off.|r Turn it on in the game's Options, then the Cys look shows here.")
    else
        status:SetText("The Cys look is on the game's own cooldown, utility and buff icons.")
    end
    y = y - 34

    -- the game's own window for choosing which spells sit in which row. The player has to open it (see
    -- CysUICompat.SecureClick), so the click runs the game's slash command instead of addon code.
    local slash = _G.SLASH_COOLDOWNMANAGER1 or "/cdm"
    local open = W.Button(page, 300, 24, "Choose spells (the game's Cooldown Manager)", true)
    open:SetPoint("TOPLEFT", 4, y)
    open:SetScript("OnClick", function()
        CUI:Print("Type " .. slash .. " to open the game's Cooldown Manager (not while in combat).")
    end)
    CysUICompat.SecureClick(open, slash)
    y = y - 36

    ----------------------------------------------------------------------------
    -- Your bars: each bar as a strip of boxes. Drag a box to move the spell, click it for its options (stances,
    -- remove), click + to add a spell the game is tracking. Works for every class; stance options only show for
    -- classes that have stances or forms. Kept at the top of the page and compact however many spells there are.
    ----------------------------------------------------------------------------
    local editorTop = y
    local body = CreateFrame("Frame", nil, page) -- everything under the editor; slides down as the editor grows
    body:SetSize(width, 10)
    local bodyH = 0
    local BOX, BGAP = 30, 4
    local PER = math.floor((width - 8 + BGAP) / (BOX + BGAP))
    local edHead = W.Header(page, "Your bars", width)
    edHead:SetPoint("TOPLEFT", 0, editorTop)
    local edHint = W.Text(page, 12, T.text)
    edHint:SetPoint("TOPLEFT", 4, editorTop - 28)
    edHint:SetWidth(width - 8)
    edHint:SetJustifyH("LEFT")
    local strips = {}
    local held -- { bar, index, x, y, moved } while a box is pressed
    local driver = CreateFrame("Frame", nil, page)
    local menu, catcher
    local Refresh

    local function Forms()
        -- stances / forms of this character. Classes that can be in no form at all (a Druid out of form) get a
        -- "no form" entry first; a Warrior is always in a stance.
        local forms = {}
        local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
        if count > 0 and select(2, UnitClass("player")) ~= "WARRIOR" then
            forms[1] = { key = 0, icon = "Interface\\Icons\\INV_Misc_QuestionMark", name = "no form" }
        end
        for i = 1, count do
            local icon, _, _, spellID = GetShapeshiftFormInfo(i)
            local name = type(spellID) == "number" and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
            forms[#forms + 1] = { key = StanceKey(i), icon = icon, name = name or ("Stance " .. i) }
        end
        return forms
    end
    local function HasRule(e)
        local hide = db.stanceHide[e.base]
        return hide and next(hide) ~= nil
    end

    -- the popup: one small window reused for a spell's options and for the add list
    local function CloseMenu()
        if menu then menu:Hide() end
        if catcher then catcher:Hide() end
    end
    local function Menu()
        if menu then return menu end
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        catcher:Hide()
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        W.Texture(menu, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
        W.Border(menu, 1, T.border, "BORDER")
        menu.title = W.Text(menu, 12, T.accent)
        menu.title:SetPoint("TOPLEFT", 8, -8)
        menu.note = W.Text(menu, 12, T.text)
        menu.note:SetJustifyH("LEFT")
        menu.rows, menu.toggles = {}, {}
        menu:Hide()
        return menu
    end
    local function MenuRow(i)
        local r = menu.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, menu)
        r:SetSize(200, 22)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
        r.hl:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
        r.text = W.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", 28, 0)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        menu.rows[i] = r
        return r
    end
    local function MenuToggle(j)
        local b = menu.toggles[j]
        if b then return b end
        b = CreateFrame("Button", nil, menu)
        b:SetSize(24, 24)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
        b.edges = W.Border(b, 1, T.line, "OVERLAY")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((self.shown and "Shown in " or "Hidden in ") .. (self.stanceName or "this stance"), 1, 1, 1)
            GameTooltip:AddLine("Click to change.", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        menu.toggles[j] = b
        return b
    end
    local function PaintToggle(b)
        b.tex:SetDesaturated(not b.shown)
        b.tex:SetAlpha(b.shown and 1 or 0.35)
        W.SetBorder(b.edges, b.shown and T.border or T.line)
    end
    local function ShowMenu(anchor, h)
        menu:SetSize(216, h)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        catcher:Show()
        menu:Show()
    end
    local function ClearMenu()
        Menu()
        for _, r in ipairs(menu.rows) do r:Hide() end
        for _, b in ipairs(menu.toggles) do b:Hide() end
        for _, b in ipairs(menu.cells or {}) do b:Hide() end
        menu.note:Hide()
    end

    -- a spell's options: which stances it shows in, and taking it off the bar
    local function SpellMenu(bar, index, anchor, waiting)
        local e = waiting or bar.list[index]
        if not e then return end
        ClearMenu()
        menu.title:SetText(C_Spell.GetSpellName(e.spell) or "Spell")
        local my = -30
        local forms = Forms()
        if #forms > 0 then
            menu.note:ClearAllPoints()
            menu.note:SetPoint("TOPLEFT", 8, my)
            menu.note:SetWidth(200)
            menu.note:SetText("Show in (click to change):")
            menu.note:Show()
            my = my - 20
            for j, form in ipairs(forms) do
                local b = MenuToggle(j)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 8 + ((j - 1) % 7) * 28, my - math.floor((j - 1) / 7) * 28)
                b.tex:SetTexture(form.icon)
                b.stanceName = form.name
                local hide = db.stanceHide[e.base]
                b.shown = not (hide and hide[form.key])
                PaintToggle(b)
                b:SetScript("OnClick", function(self)
                    local h = db.stanceHide[e.base] or {}
                    db.stanceHide[e.base] = h
                    if self.shown then h[form.key] = true else h[form.key] = nil end
                    self.shown = not self.shown
                    PaintToggle(self)
                    LayoutOwn()
                    Refresh()
                    if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
                end)
                b:Show()
            end
            my = my - math.ceil(#forms / 7) * 28 - 6
        end
        local r = MenuRow(1)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 8, my)
        r.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        r.text:SetText("Take off this bar")
        r:SetScript("OnClick", function()
            if waiting then
                DropWaiting(bar, waiting)
            else
                table.remove(bar.list, index)
                SaveOrder(bar)
            end
            CloseMenu()
            LayoutOwn()
            Refresh()
        end)
        r:Show()
        ShowMenu(anchor, -my + 22 + 8)
    end

    -- the add list: every spell the game can track that is on none of your bars, as a grid of icons.
    -- Greyed icons are spells you have not learned yet: they can be added now and appear once you know them.
    local function Cell(i)
        menu.cells = menu.cells or {}
        local b = menu.cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, menu)
        b:SetSize(28, 28)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
        b.edges = W.Border(b, 1, T.line, "OVERLAY")
        b:SetScript("OnEnter", function(self)
            W.SetBorder(self.edges, T.border)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(C_Spell.GetSpellName(e.spell) or "Spell", 1, 1, 1)
            if e.known then
                GameTooltip:AddLine("Click to add it to this bar.", T.accent[1], T.accent[2], T.accent[3])
            else
                GameTooltip:AddLine("Not learned yet. Click to add it now; it shows on the bar once you learn it.", T.accent[1], T.accent[2], T.accent[3], true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) W.SetBorder(self.edges, T.line); GameTooltip:Hide() end)
        menu.cells[i] = b
        return b
    end
    local function AddMenu(bar, anchor)
        ClearMenu()
        menu.title:SetText("Add to: " .. (bar.def.name or "bar"))
        local free = Unplaced()
        local my = -30
        menu.note:ClearAllPoints()
        menu.note:SetPoint("TOPLEFT", 8, my)
        menu.note:SetWidth(200)
        if #free == 0 then
            menu.note:SetText("Every spell the game can track for your class is already on a bar.")
        else
            menu.note:SetText("Greyed = not learned yet. It can be added now and appears once you learn it.")
        end
        menu.note:Show()
        my = my - (menu.note:GetStringHeight() or 28) - 8
        local COLS = 6
        for i, e in ipairs(free) do
            local b = Cell(i)
            b.entry = e
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + ((i - 1) % COLS) * 33, my - math.floor((i - 1) / COLS) * 33)
            b.tex:SetTexture(C_Spell.GetSpellTexture(e.spell))
            b.tex:SetDesaturated(not e.known)
            b.tex:SetAlpha(e.known and 1 or 0.55)
            b:SetScript("OnClick", function()
                AddSpell(bar, e)
                GameTooltip:Hide()
                CloseMenu()
                LayoutOwn()
                Refresh()
            end)
            b:Show()
        end
        my = my - math.ceil(#free / COLS) * 33
        ShowMenu(anchor, -my + 8)
    end

    local function Release()
        if not held then return end
        local h = held
        held = nil
        driver:SetScript("OnUpdate", nil)
        if not h.moved then
            local strip = strips[h.bar.def.key]
            local box = strip and strip.boxes[h.index]
            if box then SpellMenu(h.bar, h.index, box) end
        end
        Refresh()
    end
    local function Cursor()
        local cx, cy = GetCursorPosition()
        local s = page:GetEffectiveScale() or 1
        return cx / s, cy / s
    end
    local function Box(strip, i)
        local b = strip.boxes[i]
        if b then return b end
        b = CreateFrame("Button", nil, strip.frame)
        b:SetSize(BOX, BOX)
        b.back = b:CreateTexture(nil, "BACKGROUND")
        b.back:SetAllPoints()
        b.back:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
        b.edges = W.Border(b, 1, T.line, "OVERLAY")
        b.mark = b:CreateTexture(nil, "OVERLAY") -- small corner mark: this spell has a stance rule
        b.mark:SetSize(7, 7)
        b.mark:SetPoint("TOPRIGHT", -2, -2)
        b.mark:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        b:SetScript("OnEnter", function(self)
            W.SetBorder(self.edges, T.border)
            local e = self.waiting or (self.bar and self.bar.list[self.index])
            if not e or held then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(C_Spell.GetSpellName(e.spell) or "Spell", 1, 1, 1)
            if self.waiting then
                GameTooltip:AddLine("Not learned yet: it shows on the bar once you learn it. Click for options.", T.accent[1], T.accent[2], T.accent[3], true)
            else
                GameTooltip:AddLine("Drag to move. Click for options.", T.accent[1], T.accent[2], T.accent[3])
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            if not (held and held.bar == self.bar and held.index == self.index) then W.SetBorder(self.edges, T.line) end
            GameTooltip:Hide()
        end)
        b:SetScript("OnMouseUp", Release)
        b:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or not self.bar then return end
            if self.waiting then -- not on the bar yet, so nothing to drag: just its options
                local open = menu and menu:IsShown()
                CloseMenu()
                GameTooltip:Hide()
                if not open then SpellMenu(self.bar, nil, self, self.waiting) end
                return
            end
            CloseMenu()
            GameTooltip:Hide()
            local cx, cy = Cursor()
            held = { bar = self.bar, index = self.index, x = cx, y = cy }
            driver:SetScript("OnUpdate", function()
                if not held then driver:SetScript("OnUpdate", nil) return end
                if not IsMouseButtonDown("LeftButton") then Release() return end
                local x, yy = Cursor()
                if not held.moved and (math.abs(x - held.x) > 6 or math.abs(yy - held.y) > 6) then held.moved = true end
                if not held.moved then return end
                local frame = strips[held.bar.def.key].frame
                local left, top = frame:GetLeft(), frame:GetTop()
                if not (left and top) then return end
                local list = held.bar.list
                local col = max(0, math.min(PER - 1, math.floor((x - left) / (BOX + BGAP))))
                local row = max(0, math.floor((top - yy) / (BOX + BGAP)))
                local to = max(1, math.min(#list, row * PER + col + 1))
                if to ~= held.index then
                    local e = table.remove(list, held.index)
                    table.insert(list, to, e)
                    held.index = to
                    SaveOrder(held.bar)
                    LayoutOwn()
                    Refresh()
                end
            end)
        end)
        strip.boxes[i] = b
        return b
    end
    local function Strip(bar)
        local key = bar.def.key
        local s = strips[key]
        if s then return s end
        s = { boxes = {} }
        s.label = W.Text(page, 12, T.accent)
        s.frame = CreateFrame("Frame", nil, page)
        s.plus = W.Button(s.frame, BOX, BOX, "+")
        s.plus:SetScript("OnClick", function(self)
            if menu and menu:IsShown() then CloseMenu() return end
            AddMenu(bar, self)
        end)
        if bar.def.custom then -- a bar of your own: name, size, row length and Delete sit with it
            local c = bar.def.custom
            s.name = CreateFrame("EditBox", nil, page)
            s.name:SetSize(150, 20)
            s.name:SetAutoFocus(false)
            s.name:SetMaxLetters(24)
            s.name:SetFont(STANDARD_TEXT_FONT, 12, "")
            s.name:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
            s.name:SetTextInsets(5, 5, 0, 0)
            W.Texture(s.name, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
            W.Border(s.name, 1, T.line, "BORDER")
            local function SaveName(self)
                local text = strtrim(self:GetText() or "")
                if text == "" then text = c.name or "Bar" end
                c.name = text
                bar.def.name = text
                self:SetText(text)
                self:ClearFocus()
            end
            s.name:SetScript("OnEnterPressed", SaveName)
            s.name:SetScript("OnEscapePressed", function(self) self:SetText(c.name or ""); self:ClearFocus() end)
            s.name:SetScript("OnEditFocusLost", SaveName)
            s.name:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Click to rename this bar", 1, 1, 1)
                GameTooltip:AddLine("Its Layout mode box shows the new name after a reload.", T.accent[1], T.accent[2], T.accent[3], true)
                GameTooltip:Show()
            end)
            s.name:SetScript("OnLeave", function() GameTooltip:Hide() end)
            s.del = W.Button(page, 64, 20, "Delete")
            s.del:SetScript("OnClick", function(self)
                if not self.armed then -- second click within a few seconds deletes
                    self.armed = true
                    self.label:SetText("Sure?")
                    C_Timer.After(3, function() self.armed = nil; self.label:SetText("Delete") end)
                    return
                end
                CloseMenu()
                s.label:Hide(); s.frame:Hide(); s.name:Hide(); s.del:Hide(); s.size:Hide(); s.per:Hide()
                strips[key] = nil
                DeleteBar(bar)
                Refresh()
            end)
            local set = db.bar[key]
            s.size = W.Stepper(page, "Icon size", function() return set.size end, function(v) set.size = v; LayoutOwn() end, 16, 64, 1, " px")
            s.per = W.Stepper(page, "Icons per row", function() return set.perRow end, function(v) set.perRow = v; LayoutOwn() end, 1, 24, 1)
        end
        strips[key] = s
        return s
    end
    local newBar = W.Button(page, 110, 22, "+ New bar")
    newBar:SetScript("OnClick", function()
        CloseMenu()
        if #db.custom >= 8 then CUI:Print("Cooldown Manager: 8 bars of your own is the limit.") return end
        NewBar()
        Refresh()
    end)
    newBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("A new bar of your own", 1, 1, 1)
        GameTooltip:AddLine("It starts empty: click its + to put spells on it, then place it in Layout mode.", T.accent[1], T.accent[2], T.accent[3], true)
        GameTooltip:Show()
    end)
    newBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function Place(h)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, editorTop - h - 14)
        page.contentHeight = -editorTop + h + 14 + bodyH
    end
    Refresh = function()
        local yy = editorTop - 28
        if not ownActive then
            edHint:SetText("Turn on Cys's own bars below (and reload) to arrange your cooldown icons here: drag to reorder, click to set stances, + to add.")
            for _, s in pairs(strips) do s.label:Hide(); s.frame:Hide() end
            newBar:Hide()
            Place(-(yy - editorTop) + 34)
            return
        end
        edHint:SetText("Drag an icon to move it. Click an icon for its options. Click + to add any spell the game can track. Greyed = not learned yet. New bar makes another bar of your own.")
        yy = yy - 38
        for _, bar in ipairs(ownBars) do
            local s = Strip(bar)
            s.label:ClearAllPoints()
            s.label:SetPoint("TOPLEFT", 4, yy)
            if s.name then -- a bar of your own: its name can be typed over, with Delete at the far right
                s.label:Hide()
                s.name:ClearAllPoints()
                s.name:SetPoint("TOPLEFT", 4, yy + 3)
                if not s.name:HasFocus() then s.name:SetText(bar.def.name or "") end
                s.name:Show()
                s.del:ClearAllPoints()
                s.del:SetPoint("TOPRIGHT", page, "TOPLEFT", width - 4, yy + 3)
                s.del:Show()
                yy = yy - 24
                s.size:ClearAllPoints(); s.size:SetPoint("TOPLEFT", 4, yy); s.size:Refresh(); s.size:Show()
                yy = yy - 26
                s.per:ClearAllPoints(); s.per:SetPoint("TOPLEFT", 4, yy); s.per:Refresh(); s.per:Show()
                yy = yy - 28
            else
                s.label:SetText(bar.def.name or "Bar")
                s.label:Show()
                yy = yy - 18
            end
            local n = #bar.list
            local wait = Waiting(bar)
            local all = n + #wait
            local rowsN = math.floor(all / PER) + 1 -- the + box always has a place
            s.frame:ClearAllPoints()
            s.frame:SetPoint("TOPLEFT", 4, yy)
            s.frame:SetSize(PER * (BOX + BGAP), rowsN * (BOX + BGAP))
            s.frame:Show()
            for i = 1, n do
                local e = bar.list[i]
                local b = Box(s, i)
                b.bar, b.index, b.waiting = bar, i, nil
                b.tex:SetDesaturated(false)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ((i - 1) % PER) * (BOX + BGAP), -math.floor((i - 1) / PER) * (BOX + BGAP))
                b.tex:SetTexture(C_Spell.GetSpellTexture(e.spell))
                b.mark:SetShown(HasRule(e) and true or false)
                local isHeld = held and held.bar == bar and held.index == i
                W.SetBorder(b.edges, isHeld and T.glow or T.line)
                b.tex:SetAlpha((held and held.moved and not isHeld) and 0.6 or 1)
                b:Show()
            end
            -- spells you added but have not learned yet: greyed, after the others, so they can be taken off again
            for k, e in ipairs(wait) do
                local i = n + k
                local b = Box(s, i)
                b.bar, b.index, b.waiting = bar, nil, e
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ((i - 1) % PER) * (BOX + BGAP), -math.floor((i - 1) / PER) * (BOX + BGAP))
                b.tex:SetTexture(C_Spell.GetSpellTexture(e.spell))
                b.tex:SetDesaturated(true)
                b.tex:SetAlpha(0.5)
                b.mark:SetShown(HasRule(e) and true or false)
                W.SetBorder(b.edges, T.line)
                b:Show()
            end
            for i = all + 1, #s.boxes do s.boxes[i]:Hide(); s.boxes[i].bar = nil; s.boxes[i].waiting = nil end
            s.plus:ClearAllPoints()
            s.plus:SetPoint("TOPLEFT", (all % PER) * (BOX + BGAP), -math.floor(all / PER) * (BOX + BGAP))
            yy = yy - rowsN * (BOX + BGAP) - 8
        end
        newBar:ClearAllPoints()
        newBar:SetPoint("TOPLEFT", 4, yy)
        newBar:Show()
        yy = yy - 30
        Place(-(yy - editorTop))
    end
    page.RefreshStances = Refresh
    page:HookScript("OnHide", function() CloseMenu(); held = nil; driver:SetScript("OnUpdate", nil) end)

    y = 0 -- from here on everything sits in the body frame under the editor

    local function Check(label, key)
        W.Checkbox(body, label, function() return db[key] end, function(on) db[key] = on end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    ----------------------------------------------------------------------------
    -- Cys's own bars
    ----------------------------------------------------------------------------
    W.Header(body, "Cys's own bars", width):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    Check("Use Cys's own bars for the cooldown and utility rows (reload)", "own")
    Check("Move the tracked buffs and buff bars in Layout mode too (reload)", "carry")
    W.Checkbox(body, "Close the gap when a tracked buff is not up (reload)", function() return db.pack end,
        function(on) db.pack = on end):SetPoint("TOPLEFT", 24, y)
    y = y - 26
    local function BarStep(label, key, field, lo, hi, suffix)
        W.Stepper(body, label, function() return db.bar[key][field] end, function(v) db.bar[key][field] = v; LayoutOwn() end, lo, hi, 1, suffix)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    BarStep("Main: icon size", "main", "size", 20, 64, " px")
    BarStep("Main: icons per row", "main", "perRow", 1, 24)
    BarStep("Utility: icon size", "utility", "size", 16, 64, " px")
    BarStep("Utility: icons per row", "utility", "perRow", 1, 24)
    local function OwnCheck(label, key)
        W.Checkbox(body, label, function() return db[key] end, function(on) db[key] = on; LayoutOwn() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Show your stance or form as its own icon (reload)", "stance")
    W.Checkbox(body, "Show every stance, with the current one lit", function() return db.stanceAll end,
        function(on) db.stanceAll = on; LayoutStance() end):SetPoint("TOPLEFT", 24, y)
    y = y - 26
    W.Stepper(body, "Stance icon size", function() return db.stanceSize end, function(v) db.stanceSize = v; LayoutStance() end, 16, 64, 1, " px")
        :SetPoint("TOPLEFT", 24, y)
    y = y - 30
    OwnCheck("Grey out an icon while it is on cooldown", "grey")
    OwnCheck("Red icon when your target is out of range for it", "range")
    OwnCheck("Show the global cooldown sweep", "gcd")
    OwnCheck("Tooltips on hover", "tips")
    OwnCheck("Buff and debuff time on the icon (gold number and line)", "auraTime")
    W.Stepper(body, "Buff and debuff time: number size", function() return db.auraSize end, function(v) db.auraSize = v; ApplyFonts() end, 8, 24, 1)
        :SetPoint("TOPLEFT", 24, y)
    y = y - 30
    y = y - 6
    local ownNote = W.Notes(body, 4, y, width, "", {
        { "Moving them", "open Layout mode (top of this window) and drag Cooldowns: main, utility, buffs and buff bars, and Stance." },
        { "Stance icon", "for classes with stances or forms. With it on you can take the stance out of the game's Tracked Buffs (Choose spells) so it is not shown twice." },
        { "The game's rows", "the cooldown and utility rows are faded out while Cys's bars are on. The tracked buffs and buff bars stay the game's own icons (addons can't read buffs in combat); the second switch only lets you place them in Layout mode. Their icon size is still in Edit Mode." },
        { "Tracked buffs", "to place them, tick the second switch above and drag Cooldowns: buffs in Layout mode. Which buffs are tracked, and their order, is set in the game's own window (Choose spells, Tracked Buffs) - they are the game's icons, so they can't be edited here." },
        { "Bars of your own", "New bar (under Your bars) adds an empty bar: fill it from its + box, set its size beside it, and drag it in Layout mode like the others. Rename it by typing over its name. A spell sits on one bar at a time." },
        { "Buff and debuff time", "while an ability's own effect is running (your Rend on the target, Battle Shout on you) its icon shows the time left as a small gold number at the top and a gold line along the bottom. The cooldown keeps the middle of the icon." },
        { "Gap", "uses Gap between icons below." },
    })
    y = y - ((ownNote and ownNote.GetHeight and ownNote:GetHeight() or 96) + 14)

    y = y - 10
    W.Header(body, "Look of the game's rows", width):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    Check("Cys look on the cooldown icons (reload)", "look")
    Check("Flat buff bars in your Border color (reload)", "bars")
    Check("Yellow shade while its buff or debuff is running", "shade")
    y = y - 4
    W.Stepper(body, "Gap between icons", function() return db.gap end, function(v) db.gap = v; ApplyGaps(); LayoutOwn(); LayoutStance() end, 0, 12, 1, " px")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 28

    y = y - 10
    W.Header(body, "Numbers", width):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    local function Step(label, key, lo, hi)
        W.Stepper(body, label, function() return db[key] end, function(v) db[key] = v; ApplyFonts() end, lo, hi, 1)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    Step("Timer: main cooldowns", "timerBig", 10, 32)
    Step("Timer: utility and buffs", "timerSmall", 8, 24)
    Step("Stacks and charges", "stacks", 8, 24)

    y = y - 12
    local topNote = W.Notes(body, 4, y, width, "", {
        { "Which spells show", "the Choose spells button above opens the game's Cooldown Manager - drag spells between Essential, Utility and Tracked Buffs there." },
        { "Yellow shade", "the game tints an icon while that ability's debuff is on your target or its buff is on you (Rend, for example). Off: only the timer shows. It applies to the game's rows, not to Cys's own bars." },
        { "The game's rows", "position, icon size, rows and visibility are in the game's Edit Mode (Esc, then Edit Mode). Cys's own bars replace that." },
    })
    y = y - ((topNote and topNote.GetHeight and topNote:GetHeight() or 84) + 12)

    bodyH = -y + 24
    body:SetHeight(bodyH)
    Refresh()
end, function(page) if page and page.RefreshStances then page.RefreshStances() end end)


    end,
})
