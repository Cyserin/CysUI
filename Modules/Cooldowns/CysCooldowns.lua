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
local DEFAULTS = { look = true, bars = true, timerBig = 18, timerSmall = 12, stacks = 12, gap = 2, shade = true }
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
local function ApplyFonts()
    fontBig:SetFont(STANDARD_TEXT_FONT, db.timerBig, "OUTLINE")
    fontSmall:SetFont(STANDARD_TEXT_FONT, db.timerSmall, "OUTLINE")
    fontStack:SetFont(STANDARD_TEXT_FONT, db.stacks, "OUTLINE")
    for _, f in ipairs({ fontBig, fontSmall, fontStack }) do
        f:SetTextColor(1, 1, 1)
        f:SetShadowColor(0, 0, 0, 1)
        f:SetShadowOffset(1, -1)
    end
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
    if not db.look or OtherManager() then return end
    for name, kind in pairs(VIEWERS) do pcall(SetupViewer, name, kind) end
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

    local function Check(label, key)
        W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Cys look on the cooldown icons (reload)", "look")
    Check("Flat buff bars in your Border color (reload)", "bars")
    Check("Yellow shade while its buff or debuff is running", "shade")
    y = y - 4
    W.Stepper(page, "Gap between icons", function() return db.gap end, function(v) db.gap = v; ApplyGaps() end, 0, 12, 1, " px")
        :SetPoint("TOPLEFT", 4, y)
    y = y - 28

    y = y - 10
    W.Header(page, "Numbers", width):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    local function Step(label, key, lo, hi)
        W.Stepper(page, label, function() return db[key] end, function(v) db[key] = v; ApplyFonts() end, lo, hi, 1)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    Step("Timer: main cooldowns", "timerBig", 10, 32)
    Step("Timer: utility and buffs", "timerSmall", 8, 24)
    Step("Stacks and charges", "stacks", 8, 24)

    y = y - 12
    W.Notes(page, 4, y, width, "", {
        { "Which spells show", "the Choose spells button above opens the game's Cooldown Manager - drag spells between Essential, Utility and Tracked Buffs there." },
        { "Position, icon size, rows, visibility", "the game's Edit Mode (Esc, then Edit Mode) - click a cooldown row for its options." },
        { "Gap between icons", "is made inside each icon's slot, so it works together with Edit Mode's own Icon Padding." },
        { "Yellow shade", "the game tints an icon while that ability's debuff is on your target or its buff is on you (Rend, for example). Off: only the timer shows." },
        { "This page", "the look only. Glows, your own bars and ready-made class setups come in later stages." },
    })
    page.contentHeight = 600
end, function() end)

    end,
})
