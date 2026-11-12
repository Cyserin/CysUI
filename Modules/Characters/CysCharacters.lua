--------------------------------------------------------------------------------
-- Cys's UI - Your Characters
--
-- A small window, opened from its own minimap button (or /cuichars), with what Cys's UI knows about every
-- character on your account. First view: rested XP, how rested each one is now and when it will be full.
-- Built as views so more can be added later (gold, currencies...): add an entry to VIEWS.
--
-- Rested XP: each character saves its own rested XP, level, whether it is resting and the time, when it
-- logs out and whenever these change. The others are worked out from that time: 5% of a level every
-- 8 hours while resting in an inn or city, a quarter of that elsewhere, up to 1.5 levels.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local Chars = {}
CUI.Characters = Chars

local floor, min, max = math.floor, math.min, math.max
local LEVEL_CAP = 60
local RATE_RESTING = 0.05 / (8 * 3600) -- share of a level gained per second while resting
local RESTED_CAP = 1.5
local RESTING_ICON = "|TInterface\\CharacterFrame\\UI-StateIcon:12:12:0:0:64:64:0:32:0:27|t"
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore" -- a little party: all your characters
if GetFileIDFromPath and not GetFileIDFromPath(ICON) then ICON = "Interface\\Icons\\INV_Misc_GroupLooking" end
local ROWS, ROW_H, WIDTH = 14, 20, 400

local function DB()
    CysUIDB.characters = CysUIDB.characters or {}
    local db = CysUIDB.characters
    if db.minimap == nil then db.minimap = true end
    if db.showMax == nil then db.showMax = false end
    db.angle = db.angle or 215
    return db
end

local function RestDB()
    CysUIDB.rested = CysUIDB.rested or {}
    CysUIDB.rested.chars = CysUIDB.rested.chars or {}
    return CysUIDB.rested
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local function Now() return (GetServerTime and GetServerTime()) or time() end

local function MyKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    return (UnitName("player") or "?") .. "-" .. realm, realm
end

function Chars.Save()
    local name = UnitName("player")
    if not name or name == UNKNOWNOBJECT then return end
    local maxXP = UnitXPMax("player") or 0
    if maxXP <= 0 then return end
    local key, realm = MyKey()
    local _, class = UnitClass("player")
    RestDB().chars[key] = {
        name = name, realm = realm, class = class,
        level = UnitLevel("player") or 1,
        rest = GetXPExhaustion() or 0, max = maxXP,
        resting = IsResting() and true or false,
        time = Now(),
    }
end

-- rested XP now and seconds until it is full
local function Estimate(c, now)
    local maxXP = c.max or 0
    if maxXP <= 0 then return 0, 0 end
    local cap = maxXP * RESTED_CAP
    local rate = RATE_RESTING * (c.resting and 1 or 0.25) * maxXP
    local rest = min(cap, (c.rest or 0) + max(0, now - (c.time or now)) * rate)
    return rest, rest >= cap and 0 or (cap - rest) / rate
end

function Chars.List()
    local showMax = DB().showMax
    Chars.Save() -- the character you are on uses live numbers
    local myKey = MyKey()
    local now = Now()
    local list = {}
    for key, c in pairs(RestDB().chars) do
        if showMax or (c.level or 0) < LEVEL_CAP then
            local rest, left = Estimate(c, now)
            list[#list + 1] = { key = key, c = c, left = left, me = key == myKey,
                                pct = (c.max or 0) > 0 and rest / c.max * 100 or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end -- the character you are on is always first
        if a.pct ~= b.pct then return a.pct > b.pct end
        return (a.c.name or "") < (b.c.name or "")
    end)
    return list
end

local function FormatLeft(sec)
    if sec <= 0 then return "|cFF40D040full|r" end
    local h = sec / 3600
    if h >= 48 then return format("full in %dd", floor(h / 24 + 0.5)) end
    if h >= 1 then return format("full in %dh", floor(h + 0.5)) end
    return format("full in %dm", max(1, floor(sec / 60 + 0.5)))
end

local function ClassColor(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b end
    return 1, 1, 1
end

local function NameText(e, myRealm)
    local c = e.c
    local r, g, b = ClassColor(c.class)
    local realm = (c.realm and c.realm ~= myRealm) and ("-" .. c.realm) or ""
    return format("|cFF%02X%02X%02X%s%s|r  |cFFBBBBBB%d|r%s", floor(r * 255 + 0.5), floor(g * 255 + 0.5),
        floor(b * 255 + 0.5), c.name or "?", realm, c.level or 0, c.resting and ("  " .. RESTING_ICON) or "")
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local frame, rows, offset = nil, {}, 0
local current = {} -- the list the rows show

local function Paint()
    if not frame or not frame:IsShown() then return end
    current = Chars.List()
    local _, myRealm = MyKey()
    offset = max(0, min(offset, #current - ROWS))
    for i = 1, ROWS do
        local row, e = rows[i], current[i + offset]
        if e then
            row.entry = e
            row.name:SetText(NameText(e, myRealm))
            row.bar:SetValue(min(e.pct, RESTED_CAP * 100))
            row.pct:SetText(format("%d%%", floor(e.pct + 0.5)))
            row.left:SetText(FormatLeft(e.left))
            row.mine:SetShown(e.me)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    local shown = min(ROWS, #current)
    frame.empty:SetShown(#current == 0)
    frame:SetHeight(26 + 22 + max(1, shown) * ROW_H + 30)
end
Chars.Refresh = Paint

local function MakeRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 16, ROW_H)
    row:SetPoint("TOPLEFT", 8, -(26 + 22 + (i - 1) * ROW_H))
    row:RegisterForClicks("RightButtonUp")
    local hl = W.Texture(row, "BACKGROUND", T.hover)
    hl:SetAllPoints()
    hl:Hide()
    -- the character you are on: a faint gold wash with a gold tick on the left
    row.mine = CreateFrame("Frame", nil, row)
    row.mine:SetAllPoints()
    local wash = W.Texture(row.mine, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.08 })
    wash:SetAllPoints()
    local tick = W.Texture(row.mine, "ARTWORK", T.border)
    tick:SetPoint("TOPLEFT", 0, -3)
    tick:SetPoint("BOTTOMLEFT", 0, 3)
    tick:SetWidth(2)

    row.name = W.Text(row, 11)
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(150)
    row.name:SetWordWrap(false)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(96, 8)
    row.bar:SetPoint("LEFT", 162, 0)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetStatusBarColor(0.25, 0.55, 1, 0.9)
    row.bar:SetMinMaxValues(0, RESTED_CAP * 100)
    W.Texture(row.bar, "BACKGROUND", { 0.02, 0.02, 0.02, 0.9 }):SetAllPoints()
    W.Border(row.bar, 1, T.line, "OVERLAY")
    -- a mark at 100% (one full level of rested XP)
    local mark = W.Texture(row.bar, "OVERLAY", { 1, 1, 1, 0.35 }, 1)
    mark:SetSize(1, 8)
    mark:SetPoint("LEFT", 96 / RESTED_CAP - 1, 0)

    row.pct = W.Text(row, 11, { 0.45, 0.7, 1 }, "RIGHT")
    row.pct:SetPoint("LEFT", row.bar, "RIGHT", 4, 0)
    row.pct:SetWidth(38)
    row.left = W.Text(row, 11, { 0.45, 0.7, 1 }, "RIGHT")
    row.left:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnEnter", function(self)
        hl:Show()
        local e = self.entry
        if not e then return end
        local c = e.c
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(c.name .. (c.realm and (" - " .. c.realm) or ""), ClassColor(c.class))
        GameTooltip:AddDoubleLine("Level", tostring(c.level or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Rested", format("%d%% of a level", floor(e.pct + 0.5)), 0.8, 0.8, 0.8, 0.45, 0.7, 1)
        if not e.me then
            GameTooltip:AddDoubleLine("Logged out", c.resting and "resting (inn or city)" or "not resting",
                0.8, 0.8, 0.8, 1, 1, 1)
            local ago = Now() - (c.time or Now())
            GameTooltip:AddDoubleLine("Last seen", ago >= 86400 and format("%d days ago", floor(ago / 86400))
                or format("%d hours ago", floor(ago / 3600)), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift + right-click to forget this character", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() hl:Hide(); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and not e.me and IsShiftKeyDown() then
            RestDB().chars[e.key] = nil
            GameTooltip:Hide()
            Paint()
        end
    end)
    return row
end

local function BuildWindow()
    local db = DB()
    local f = CreateFrame("Frame", "CysCharactersFrame", UIParent)
    frame = f
    f:SetSize(WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    if db.pos then
        f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -220)
    end
    tinsert(UISpecialFrames, "CysCharactersFrame")
    W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.96 }):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    W.Texture(header, "BACKGROUND", T.header):SetAllPoints()
    local hline = W.Texture(header, "BORDER", T.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if point then db.pos = { point, relPoint, x, y } end
    end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = W.Text(header, 12, T.accent)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Your Characters - Rested XP")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- column headings
    local function Heading(text, point, x, justify)
        local h = W.Text(f, 10, T.dim, justify)
        h:SetPoint(point, f, "TOPLEFT", x, -34)
        h:SetText(text)
    end
    Heading("CHARACTER", "LEFT", 16)
    Heading("RESTED", "LEFT", 170)
    local fullH = W.Text(f, 10, T.dim, "RIGHT")
    fullH:SetPoint("TOPRIGHT", -14, -29)
    fullH:SetText("FULL")
    local cline = W.Texture(f, "BORDER", T.line)
    cline:SetPoint("TOPLEFT", 8, -45); cline:SetPoint("TOPRIGHT", -8, -45); cline:SetHeight(1)

    for i = 1, ROWS do rows[i] = MakeRow(f, i) end

    f.empty = W.Text(f, 11, T.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -56)
    f.empty:SetText("Nothing saved yet - log in on your characters once.")

    local foot = W.Text(f, 10, T.dim)
    foot:SetPoint("BOTTOMLEFT", 10, 10)
    foot:SetText(RESTING_ICON .. " logged out resting.   Shift + right-click a row to forget it.")

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Paint()
    end)
    f:SetScript("OnShow", function() offset = 0; Paint() end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 30 then acc = 0; Paint() end
    end)
end

function Chars:Toggle()
    if not frame then BuildWindow() end
    frame:SetShown(not frame:IsShown())
end

SLASH_CYSCHARS1 = "/cuichars"
SLASH_CYSCHARS2 = "/cuirested"
SlashCmdList.CYSCHARS = function() Chars:Toggle() end

--------------------------------------------------------------------------------
-- Minimap button (Cys's minimap button panel picks it up when it collects buttons)
--------------------------------------------------------------------------------
local mmb

local function PlaceButton()
    if not mmb then return end
    local a = math.rad(DB().angle)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    mmb:ClearAllPoints()
    mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "CysCharactersMinimapButton", Minimap)
    mmb = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then CUI:OpenConfig("Characters") else Chars:Toggle() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Your Characters", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Click: rested XP on all your characters", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- drag around the minimap edge (does nothing once the Cys button panel has collected it)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            DB().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceButton()
    b:SetShown(DB().minimap)
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
function Chars.Enable()
    DB()
    local saver = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION",
                          "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE" }) do
        saver:RegisterEvent(ev)
    end
    saver:SetScript("OnEvent", function() Chars.Save() end)
    BuildMinimapButton()
end

CUI:RegisterModule({
    key = "characters",
    name = "Your Characters",
    addon = "CysUI",
    desc = "A minimap button and window with the rested XP of all your characters and when each will be full.",
    onEnable = Chars.Enable,
    open = function() CUI:OpenConfig("Characters") end,
})

CUI:RegisterPage("Characters", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Your Characters", width):SetPoint("TOPLEFT", 0, -4)
    local mm = W.Checkbox(page, "Show the minimap button", function() return db.minimap end,
        function(on) db.minimap = on; if mmb then mmb:SetShown(on) end end)
    mm:SetPoint("TOPLEFT", 4, -34)
    local sm = W.Checkbox(page, "Also list characters at level 60", function() return db.showMax end,
        function(on) db.showMax = on; Paint() end)
    sm:SetPoint("TOPLEFT", 4, -60)
    local open = W.Button(page, 130, 22, "Open the window", true)
    open:SetPoint("TOPLEFT", 4, -96)
    open:SetScript("OnClick", function() if not (frame and frame:IsShown()) then Chars:Toggle() end end)
    local clear = W.Button(page, 130, 22, "Clear the list")
    clear:SetPoint("LEFT", open, "RIGHT", 10, 0)
    clear:SetScript("OnClick", function() wipe(RestDB().chars); Chars.Save(); Paint() end)
    W.Notes(page, 4, -134, width, "", {
        "Each character is added when you log in on it, and saved again when you log out.",
        "Rested XP of the others is worked out from when they logged out: 5% of a level every 8 hours in an inn or city, a quarter of that elsewhere, up to 1.5 levels.",
        "The bar is full at 150% (one and a half levels); the thin mark is one level. /cuichars opens the window too.",
    })
end)
