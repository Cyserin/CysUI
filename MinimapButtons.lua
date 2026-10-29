--------------------------------------------------------------------------------
-- Cys's UI - Minimap Button
--
-- One round Cys button for the minimap. Click it and a small panel opens with every other
-- addon's minimap button tidied into a grid. Right-click opens the CysUI settings.
-- Addon buttons are found by name (LibDBIcon and similar "...Minimap..." buttons); Blizzard's own
-- status icons (mail, tracking, queue) are never touched. Anything can be left out in the settings.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local max, min, floor, ceil = math.max, math.min, math.floor, math.ceil

local MB = {}
CUI.MinimapButtons = MB

local LOGO_ROUND = "Interface\\AddOns\\CysUI\\Media\\CysLogo"
local LOGO_SQUARE = "Interface\\AddOns\\CysUI\\Media\\CysLogoSquare"

local function DB()
    if not CysUIDB then CysUIDB = {} end
    local db = CysUIDB.mmbuttons
    if not db then db = {}; CysUIDB.mmbuttons = db end
    if db.enable == nil then db.enable = true end
    if db.collect == nil then db.collect = true end
    db.columns = db.columns or 5
    db.cell = db.cell or 30
    db.skip = db.skip or {}
    return db
end

-- Blizzard frames and our own pieces are never collected
local NEVER = {
    MiniMapMailFrame = true, MiniMapTrackingFrame = true, MiniMapTracking = true, QueueStatusMinimapButton = true,
    MiniMapLFGFrame = true, MiniMapBattlefieldFrame = true, MiniMapMeetingStoneFrame = true,
    MinimapZoomIn = true, MinimapZoomOut = true, GameTimeFrame = true, TimeManagerClockButton = true,
    MiniMapWorldMapButton = true, MinimapZoneTextButton = true, MinimapToggleButton = true,
    MiniMapInstanceDifficulty = true, MinimapBackdrop = true, MinimapCluster = true,
}

local button, panel
MB.entries = {}   -- { btn, name, plate, hidden }
MB.byName = {}
MB.seen = {}      -- names found, for the settings list

local function Looks(name, f)
    if not name or NEVER[name] or name:find("^CysUI") then return false end
    if not (f.IsObjectType and f:IsObjectType("Button")) then return false end
    if name:find("^LibDBIcon10_") then return true end
    -- older style buttons: "SomethingMinimapButton", "MinimapButton_X"...
    local lower = name:lower()
    if lower:find("minimapbutton") or lower:find("minimap_button") or lower:find("minimapicon") then
        local w, h = f:GetSize()
        return w and h and w >= 16 and w <= 50 and h >= 16 and h <= 50
    end
    return false
end

--------------------------------------------------------------------------------
-- Layout of the panel
--------------------------------------------------------------------------------
local PAD, GAP = 6, 4

function MB:Layout()
    if not panel then return end
    local db = DB()
    local cell, cols = db.cell, db.columns
    local list = {}
    for _, e in ipairs(MB.entries) do
        if not e.hidden and not db.skip[e.name] then list[#list + 1] = e
        else e.plate:Hide(); e.btn:SetAlpha(0); e.btn:EnableMouse(false) end
    end
    local n = #list
    local rows = max(1, ceil(n / cols))
    local usedCols = max(1, min(cols, n))
    panel:SetSize(PAD * 2 + usedCols * cell + (usedCols - 1) * GAP, PAD * 2 + rows * cell + (rows - 1) * GAP)
    for i, e in ipairs(list) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        e.plate:ClearAllPoints()
        e.plate:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + c * (cell + GAP), -(PAD + r * (cell + GAP)))
        e.plate:SetSize(cell, cell)
        e.plate:Show()
        e.btn:SetAlpha(1); e.btn:EnableMouse(true)
        e.raise()
        local w = (e.baseW and e.baseW > 8) and e.baseW or 31
        -- size by the icon itself (the old round art around it is gone), and keep the click area to the icon
        local icon = e.btn.icon or e.btn.Icon
        local iw = (icon and icon.GetWidth and icon:GetWidth() or 0)
        if iw < 8 then iw = w * 0.6 end
        e.btn:SetScale((cell - 9) / iw)
        local inset = max(0, (w - iw) / 2)
        e.btn:SetHitRectInsets(inset, inset, inset, inset)
        -- the icon sits a little off-centre inside most buttons; centre the icon, not the button
        local dx, dy = 0, 0
        if icon and icon.GetPoint then
            local p, rel, _, px, py = icon:GetPoint(1)
            if p == "TOPLEFT" and rel == e.btn and px and py then
                dx = (px + iw / 2) - e.btn:GetWidth() / 2
                dy = (py - (icon:GetHeight() or iw) / 2) + e.btn:GetHeight() / 2
            end
        end
        e.setPoint(e.btn, "CENTER", e.plate, "CENTER", -dx, -dy) -- offsets are in the button's own (scaled) units
    end
    if n == 0 then
        panel.empty:Show()
        panel:SetSize(190, 40)
    else
        panel.empty:Hide()
    end
end

local function Reanchor()
    if not (panel and button) then return end
    local bx, by = button:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not bx then return end
    panel:ClearAllPoints()
    local below = by > sh / 2
    local right = bx > sw / 2
    local pt = (below and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")
    local rel = (below and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    panel:SetPoint(pt, button, rel, 0, below and -4 or 4)
end

function MB:Toggle(force)
    if not panel then return end
    local show = force
    if show == nil then show = not panel:IsShown() end
    if show then MB:Layout(); Reanchor() end
    panel:SetShown(show)
end

--------------------------------------------------------------------------------
-- Collecting addon buttons
--------------------------------------------------------------------------------
local BORDER_IDS = { [136430] = true, [136467] = true, [136477] = true }

local function StripArt(btn)
    -- drop the round gold ring / dark disc the old-style buttons draw; the icon stays
    for _, key in ipairs({ "border", "background", "Border", "Background" }) do
        local t = btn[key]
        if t and t.Hide and t.GetObjectType and t:GetObjectType() == "Texture" then t:Hide() end
    end
    for _, region in ipairs({ btn:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            local tex = region:GetTexture()
            if (type(tex) == "number" and BORDER_IDS[tex])
                or (type(tex) == "string" and (tex:find("TrackingBorder") or tex:find("Minimap%-Background"))) then
                region:Hide()
                region.Show = function() end
            end
        end
    end
end

local function Capture(name, btn)
    local plate = CreateFrame("Frame", nil, panel)
    plate:SetFrameLevel(panel:GetFrameLevel() + 1)
    W.Texture(plate, "BACKGROUND", { 0.03, 0.03, 0.03, 0.95 }):SetAllPoints()
    local edges = W.Border(plate, 1, T.border, "BORDER")

    -- the game's own methods, not whatever an addon put on its button
    local mt = getmetatable(btn)
    local base = (mt and type(mt.__index) == "table") and mt.__index or btn
    local e = { btn = btn, name = name, plate = plate, edges = edges, hidden = not btn:IsShown(),
                setPoint = base.SetPoint, setStrata = base.SetFrameStrata, setLevel = base.SetFrameLevel,
                baseW = btn:GetWidth() }
    MB.entries[#MB.entries + 1] = e
    MB.byName[name] = e

    btn:SetParent(panel)
    -- the panel sits on a higher strata than the minimap, so the button must follow it or hide behind it
    local function Raise(f, level)
        f:SetFrameStrata(panel:GetFrameStrata())
        f:SetFrameLevel(level)
        for _, c in ipairs({ f:GetChildren() }) do Raise(c, level + 1) end
    end
    e.raise = function()
        e.setStrata(btn, panel:GetFrameStrata())
        e.setLevel(btn, 8)
        for _, c in ipairs({ btn:GetChildren() }) do Raise(c, 9) end
    end
    e.raise()
    -- LibDBIcon puts its buttons back on the minimap's layer; keep them above the panel
    btn.SetFrameStrata = function() end
    btn.SetFrameLevel = function() end
    -- addons keep re-anchoring their button to the minimap; ignore that from now on
    btn.SetPoint = function() end
    btn.ClearAllPoints = function() end
    btn.SetParent = function() end
    if btn.RegisterForDrag then pcall(btn.RegisterForDrag, btn) end
    btn:SetMovable(false)
    StripArt(btn)

    hooksecurefunc(btn, "Hide", function() e.hidden = true end)
    hooksecurefunc(btn, "Show", function() e.hidden = false end)
    btn:HookScript("OnEnter", function() W.SetBorder(edges, T.accent) end)
    btn:HookScript("OnLeave", function() W.SetBorder(edges, T.border) end)
    -- a dropdown or window an addon opens from its button should close the panel first
    btn:HookScript("OnClick", function() if DB().closeOnClick then MB:Toggle(false) end end)
end

function MB:Scan()
    if not panel then return end
    local db = DB()
    local added = false
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop, _G.MinimapCluster }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                local name = child.GetName and child:GetName()
                if name and not MB.byName[name] and Looks(name, child) then
                    MB.seen[name] = true
                    if db.collect and not db.skip[name] then
                        local ok, err = pcall(Capture, name, child)
                        if ok then added = true
                        else CUI:Print("|cFFFF9F43Minimap Button: could not take " .. name .. " (" .. tostring(err) .. ")|r") end
                    end
                end
            end
        end
    end
    if added then MB:Layout() end
end

-- /cuimmb: what the panel holds, for troubleshooting
SLASH_CUIMMB1 = "/cuimmb"
SlashCmdList["CUIMMB"] = function()
    CUI:Print("Minimap Button: " .. #MB.entries .. " captured")
    for _, e in ipairs(MB.entries) do
        local b = e.btn
        local left, bottom, w, h = b:GetRect()
        CUI:Print(string.format("%s shown=%s hidden=%s alpha=%.1f scale=%.2f size=%.0fx%.0f at=%s,%s strata=%s lvl=%d regions=%d",
            e.name, tostring(b:IsShown()), tostring(e.hidden), b:GetAlpha(), b:GetScale(), b:GetWidth(), b:GetHeight(),
            left and floor(left) or "-", bottom and floor(bottom) or "-", b:GetFrameStrata(), b:GetFrameLevel(), #{ b:GetRegions() }))
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
function MB.Enable()
    local db = DB()
    if not db.enable then return end

    button = CreateFrame("Button", "CysUIMinimapButton", UIParent)
    button:SetSize(34, 34)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(30)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local LOGO = db.roundLogo and LOGO_ROUND or LOGO_SQUARE
    local logo = button:CreateTexture(nil, "ARTWORK")
    logo:SetAllPoints()
    logo:SetTexture(LOGO)
    if not db.roundLogo then
        logo:SetPoint("TOPLEFT", 1, -1)
        logo:SetPoint("BOTTOMRIGHT", -1, 1)
        W.Border(button, 1, T.border, "OVERLAY")
    end
    button.logo = logo
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetTexture(LOGO)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.35)

    -- starts in the lower left corner of the minimap; move it in layout mode
    CUI:RegisterMovable(button, "mmbutton", "Minimap Button", { point = "TOPRIGHT", x = -170, y = -174, scalable = false })

    panel = CreateFrame("Frame", "CysUIMinimapPanel", UIParent)
    -- LibDBIcon pins its buttons to MEDIUM / level 8, so the panel sits just under that
    -- and the buttons draw on top of it whatever the addons do
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(4)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    W.Texture(panel, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.96 }):SetAllPoints()
    W.Border(panel, 1, T.border, "BORDER")
    panel.empty = W.Text(panel, 11, T.desc, "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetText("No addon buttons found yet")
    panel.empty:Hide()
    tinsert(UISpecialFrames, "CysUIMinimapPanel")

    -- clicking anywhere outside the panel closes it
    local was = false
    panel:SetScript("OnUpdate", function(self)
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if down and not was and not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
        was = down
    end)

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            CUI:OpenConfig("Minimap Button")
        else
            MB:Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Cys's UI", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: addon buttons", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- addons add their buttons at different times, so look a few times while the game loads
    for _, t in ipairs({ 1, 3, 6, 10, 20 }) do C_Timer.After(t, function() MB:Scan() end) end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() C_Timer.After(2, function() MB:Scan() end) end)
end

CUI:RegisterModule({
    key = "mmbuttons",
    name = "Minimap Button",
    addon = "CysUI",
    desc = "A Cys logo button on the minimap that gathers every other addon's minimap button into one neat panel.",
    onEnable = MB.Enable,
    open = function() CUI:OpenConfig("Minimap Button") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Minimap Button", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Minimap Button", width):SetPoint("TOPLEFT", 0, -4)

    local y = -34
    local function Add(w) w:SetPoint("TOPLEFT", 4, y); y = y - 30 end

    Add(W.Checkbox(page, "Show the Cys button (needs a /reload)", function() return db.enable end,
        function(on) db.enable = on end))
    Add(W.Checkbox(page, "Gather addon minimap buttons into the panel (turning off needs a /reload)",
        function() return db.collect end, function(on) db.collect = on end))
    Add(W.Checkbox(page, "Close the panel after clicking one of its buttons",
        function() return db.closeOnClick end, function(on) db.closeOnClick = on end))

    local cols = W.Stepper(page, "Buttons per row", function() return db.columns end,
        function(v) db.columns = v; MB:Layout() end, 2, 8, 1, "")
    cols:SetPoint("TOPLEFT", 4, y - 4); y = y - 32
    local size = W.Stepper(page, "Button size", function() return db.cell end,
        function(v) db.cell = v; MB:Layout() end, 22, 44, 2, " px")
    size:SetPoint("TOPLEFT", 4, y - 4); y = y - 38

    Add(W.Checkbox(page, "Round logo instead of the square one (needs a /reload)",
        function() return db.roundLogo end, function(on) db.roundLogo = on end))
    local move = W.Button(page, 240, 22, "Move the Cys button (layout mode)")
    move:SetPoint("TOPLEFT", 4, y)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    y = y - 40

    W.Header(page, "Keep on the minimap instead of the panel (needs a /reload)", width):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    local names = {}
    for n in pairs(MB.seen) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then
        local none = W.Text(page, 11, T.desc)
        none:SetPoint("TOPLEFT", 4, y)
        none:SetWidth(width)
        none:SetText("No addon buttons found yet. Open this page again once the game has finished loading.")
    else
        for _, n in ipairs(names) do
            local label = n:gsub("^LibDBIcon10_", "")
            local cb = W.Checkbox(page, label, function() return db.skip[n] end,
                function(on) db.skip[n] = on or nil end)
            cb:SetPoint("TOPLEFT", 4, y); y = y - 26
        end
    end
end)
