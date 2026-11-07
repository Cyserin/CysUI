--------------------------------------------------------------------------------
-- Cys's UI - Minimap
--
-- Restyles Blizzard's minimap (it doesn't replace it, so tracking, mail, battlefield and
-- the rest keep working):
--   * a square map with a flat gold edge, the round art and zoom buttons gone
--   * a zone bar above it (colored by zone type, click for the world map)
--   * coordinates on the map
--   * mouse-wheel zoom
--   * movable and resizable with layout mode (/cui layout); it stays square
--
-- Every step is guarded, and the whole module can be switched off under /cui > Modules.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min

local MM = {}
CUI.Minimap = MM

local function DB() return CysUIDB.minimap end

local hidden = CreateFrame("Frame")
hidden:Hide()

-- Park a Blizzard frame / texture where it can never be shown again.
local function Kill(obj)
    if not obj then return end
    if obj.UnregisterAllEvents then pcall(obj.UnregisterAllEvents, obj) end
    if obj.SetParent then obj:SetParent(hidden) end
    if obj.Hide then obj:Hide() end
end

-- The round-minimap decorations (names differ a little between client versions)
local DECORATIONS = { "MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut",
                      "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapZoneTextButton",
                      "MinimapCompassTexture", "GameTimeFrame" }

-- Status icons keep working but move to tidy spots on the square map's edges, all the same
-- size. { frame name, corner, x, y }. Several icons share the left edge, stacked top to bottom.
local ICON_SIZE = 22
local ICONS = {
    { "MiniMapMailFrame",          "TOPRIGHT",    -3,  -3 },
    { "MiniMapTrackingFrame",      "TOPLEFT",      3,  -3 },
    { "MiniMapTracking",           "TOPLEFT",      3,  -3 },
    { "QueueStatusMinimapButton",  "TOPLEFT",      3, -28 },
    { "MiniMapLFGFrame",           "TOPLEFT",      3, -28 },
    { "MiniMapMeetingStoneFrame",  "TOPLEFT",      3, -28 },
    { "MiniMapBattlefieldFrame",   "BOTTOMRIGHT", -3,   3 },
}

local ZONE_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 }, friendly = { 0.3, 0.85, 0.4 }, contested = { 1, 0.62, 0.26 },
    hostile = { 0.9, 0.2, 0.2 }, combat = { 0.9, 0.2, 0.2 }, arena = { 0.9, 0.2, 0.2 },
}

local zoneBar, coordsText

--------------------------------------------------------------------------------
-- Right-click tracking menu
--
-- Classic Era tracking (Find Herbs, Track Beasts...) is a spell, one at a time. Addons can't cast
-- spells by themselves, so each row is one of the game's secure spell buttons: your click casts it.
-- Clients with the newer tracking list (C_Minimap tracking types) use that instead.
--------------------------------------------------------------------------------
local TRACKING_SPELLS = {
    2383, 2580, 2481,                       -- Find Herbs, Find Minerals, Find Treasure (Dwarf)
    1494, 19883, 19884, 19885, 19880,       -- Hunter: Beasts, Humanoids, Undead, Hidden, Elementals
    19878, 19882, 19879,                    -- Hunter: Demons, Giants, Dragonkin
    5225, 5502, 5500,                       -- Druid Track Humanoids (cat), Paladin Sense Undead, Warlock Sense Demons
}

local trackMenu
local function CloseTracking() if trackMenu then trackMenu:Hide() end end

local function MenuRow(parent, secure)
    local b = CreateFrame("Button", nil, parent, secure and "SecureActionButtonTemplate" or nil)
    b:SetSize(200, 22)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.hl = W.Texture(b, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.18 })
    b.hl:SetAllPoints()
    b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = W.Text(b, 12, T.text)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.check = W.Text(b, 12, T.accent, "RIGHT")
    b.check:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnEnter", function(s) s.hl:Show() end)
    b:SetScript("OnLeave", function(s) s.hl:Hide() end)
    return b
end

local function OpenTracking(anchor)
    if InCombatLockdown() then CUI:Print("Tracking can be changed once combat ends.") return end
    if not trackMenu then
        trackMenu = CreateFrame("Frame", "CysUITrackingMenu", UIParent)
        trackMenu:SetFrameStrata("DIALOG")
        trackMenu:SetClampedToScreen(true)
        trackMenu:EnableMouse(true)
        W.Texture(trackMenu, "BACKGROUND", T.bg):SetAllPoints()
        W.Border(trackMenu, 1, T.border, "BORDER")
        trackMenu.title = W.Text(trackMenu, 12, T.accent)
        trackMenu.title:SetPoint("TOPLEFT", 10, -8)
        trackMenu.title:SetText("Tracking")
        trackMenu.rows = {}
        trackMenu:Hide()
        tinsert(UISpecialFrames, "CysUITrackingMenu") -- Escape closes it
        -- a click anywhere else closes it
        local watch = CreateFrame("Frame")
        pcall(watch.RegisterEvent, watch, "GLOBAL_MOUSE_DOWN")
        watch:SetScript("OnEvent", function()
            if trackMenu:IsShown() and not trackMenu:IsMouseOver() and not Minimap:IsMouseOver() then
                C_Timer.After(0.05, CloseTracking)
            end
        end)
    end
    for _, r in pairs(trackMenu.rows) do r:Hide() end

    local entries = {}
    local CM = C_Minimap
    local current = GetTrackingTexture and GetTrackingTexture()
    -- spell tracking (Find Herbs, Track Beasts...): cast through secure rows
    if CancelTrackingBuff then
        entries[#entries + 1] = { name = "None", icon = "Interface\\Minimap\\Tracking\\None", active = current == nil,
            click = function() CancelTrackingBuff() end }
        for _, id in ipairs(TRACKING_SPELLS) do
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                local name, _, icon = GetSpellInfo(id)
                if name then
                    entries[#entries + 1] = { name = name, icon = icon, spell = name, active = current == icon }
                end
            end
        end
    end
    -- the game's own tracking list, on clients that have one (mailbox, trainers, flight masters,
    -- innkeepers, auctioneers, banks...): every type it offers, switched on and off like Blizzard's menu
    if CM and CM.GetNumTrackingTypes then
        local ok, count = pcall(CM.GetNumTrackingTypes)
        local town = {}
        for i = 1, (ok and count or 0) do
            local info = CM.GetTrackingInfo(i)
            -- spell types are already listed above when the client tracks with spells
            if info and not (CancelTrackingBuff and info.type == "spell") then
                town[#town + 1] = { name = info.name, icon = info.texture, active = info.active,
                    click = function() CM.SetTracking(i, not info.active) end }
            end
        end
        table.sort(town, function(a, b) return (a.name or "") < (b.name or "") end)
        if #town > 0 and not CancelTrackingBuff then
            table.insert(entries, 1, { name = "Uncheck all", icon = "Interface\\Minimap\\Tracking\\None", active = false,
                click = function() if CM.ClearAllTracking then CM.ClearAllTracking() end end })
        end
        for _, e in ipairs(town) do entries[#entries + 1] = e end
    end

    local y = -28
    local width = 200
    for i, e in ipairs(entries) do
        -- secure rows and plain rows are kept apart (a button can't switch between the two)
        local key = e.spell and ("s" .. i) or ("p" .. i)
        trackMenu.rows[key] = trackMenu.rows[key] or MenuRow(trackMenu, e.spell ~= nil)
        local r = trackMenu.rows[key]
        r.icon:SetTexture(e.icon)
        r.text:SetText(e.name)
        r.check:SetText(e.active and "on" or "")
        if e.spell then
            r:SetAttribute("type", "spell")
            r:SetAttribute("spell", e.spell)
            if not r.cysHooked then
                r.cysHooked = true
                r:HookScript("PostClick", function() C_Timer.After(0.05, CloseTracking) end)
            end
        else
            r:SetScript("OnClick", function() e.click(); CloseTracking() end)
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, y)
        width = math.max(width, r.text:GetStringWidth() + 70)
        r:Show()
        y = y - 22
    end
    if #entries <= 1 then
        local r = trackMenu.rows.none or MenuRow(trackMenu, false)
        trackMenu.rows.none = r
        r.icon:SetTexture(nil)
        r.text:SetText("You don't know any tracking yet")
        r.check:SetText("")
        r:SetScript("OnClick", CloseTracking)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, y)
        r:Show()
        y = y - 22
    end
    for _, r in pairs(trackMenu.rows) do if r:IsShown() then r:SetWidth(width - 8) end end
    trackMenu:SetSize(width, -y + 6)
    trackMenu:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    trackMenu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    trackMenu:Show()
end

--------------------------------------------------------------------------------
-- Readouts
--------------------------------------------------------------------------------
function MM:UpdateZone()
    if not (zoneBar and zoneBar:IsShown()) then return end
    local text = (GetMinimapZoneText and GetMinimapZoneText()) or GetZoneText() or ""
    local pvp = GetZonePVPInfo and GetZonePVPInfo()
    local c = ZONE_COLORS[pvp or ""] or T.accent
    zoneBar.text:SetText(text)
    zoneBar.text:SetTextColor(c[1], c[2], c[3])
end

function MM:UpdateCoords()
    if not (coordsText and coordsText:IsShown()) then return end
    local text = ""
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            if x and y and (x > 0 or y > 0) then text = format("%.1f, %.1f", x * 100, y * 100) end
        end
    end
    coordsText:SetText(text)
end

function MM:ApplyClock()
    -- Blizzard's own clock under the map (the Info Bar has one)
    local clock = _G.TimeManagerClockButton
    if clock then
        local show = DB().clock and true or false
        clock:SetAlpha(show and 1 or 0)
        clock:EnableMouse(show)
    end
end

function MM:Apply()
    local db = DB()
    self:ApplyClock()
    if zoneBar then zoneBar:SetShown(db.zoneText and true or false) end
    if coordsText then coordsText:SetShown(db.coords and true or false) end
    self:UpdateZone()
    self:UpdateCoords()
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
local function Step(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then CUI:Print("|cFFFF9F43Minimap: " .. label .. " skipped (" .. tostring(err) .. ")|r") end
end

function MM.Enable()
    if not Minimap then return end
    local size = 180 -- same width as the info bar under it

    -- our own holder so the map can be moved and resized by layout mode
    local holder = CreateFrame("Frame", "CysUIMinimap", UIParent)
    holder:SetSize(size, size)
    MM.holder = holder

    Step("square map", function()
        Minimap:SetParent(holder)
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", holder, "CENTER", 0, 0)
        Minimap:SetSize(size, size)
        Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground") -- square
    end)
    Step("layout", function()
        CUI:RegisterMovable(holder, "minimap", "Minimap", {
            point = "TOPRIGHT", x = -24, y = -28,
            resizable = true, keepSquare = true, minW = 100, maxW = 320,
            onResize = function(_, w)
                Minimap:SetSize(w, w)
                -- the game keeps drawing the map at the old size until it is nudged (the black edge)
                if C_Timer and Minimap.GetZoom then
                    C_Timer.After(0.05, function()
                        local z = Minimap:GetZoom()
                        Minimap:SetZoom(z > 0 and z - 1 or z + 1)
                        Minimap:SetZoom(z)
                    end)
                end
            end,
        })
    end)

    for _, name in ipairs(DECORATIONS) do Step(name, Kill, _G[name]) end
    -- leftover Blizzard art: the cluster frame behind the old zone bar and the minimap backdrop
    Step("cluster art", function()
        for _, parent in ipairs({ MinimapCluster, MinimapBackdrop }) do
            if parent and parent.GetRegions then
                for _, region in ipairs({ parent:GetRegions() }) do
                    if region.Hide then region:Hide() end
                end
            end
        end
        if MinimapCluster then
            for _, k in ipairs({ "BorderTop", "ZoneTextButton", "Background", "Border" }) do Kill(MinimapCluster[k]) end
        end
        Kill(_G.MinimapZoneText)
    end)
    for _, icon in ipairs(ICONS) do
        local f = _G[icon[1]]
        if f then
            Step(icon[1], function()
                f:ClearAllPoints()
                f:SetPoint(icon[2], Minimap, icon[2], icon[3], icon[4])
                -- one size for every status icon, above the map's own gold edge
                local w = f:GetWidth()
                if w and w > 0 then f:SetScale(max(0.4, min(1.2, ICON_SIZE / w))) end
                f:SetFrameStrata(Minimap:GetFrameStrata())
                f:SetFrameLevel(Minimap:GetFrameLevel() + 8)
            end)
        end
    end

    -- WoW Forever: the tracking button and the Addon Compartment (the numbered AddOns button) sit inside the
    -- map's top corners instead of floating beside it. Blizzard re-anchors them on its own layout, so put them
    -- back whenever that happens. Only position and size change.
    local FOREVER_ICONS = {
        { function() return MinimapCluster and (MinimapCluster.Tracking or MinimapCluster.TrackingFrame) end, "TOPLEFT", 3, -3 },
        { function() return _G.AddonCompartmentFrame end, "TOPRIGHT", -3, -28 },
    }
    for _, icon in ipairs(FOREVER_ICONS) do
        local okF, f = pcall(icon[1])
        if okF and f and f.SetPoint then
            Step("forever icon", function()
                local placing = false
                local function Place()
                    if placing or InCombatLockdown() then return end
                    placing = true
                    f:ClearAllPoints()
                    f:SetPoint(icon[2], Minimap, icon[2], icon[3], icon[4])
                    f:SetFrameStrata(Minimap:GetFrameStrata())
                    f:SetFrameLevel(Minimap:GetFrameLevel() + 8)
                    placing = false
                end
                local w = f:GetWidth()
                if w and w > 0 then f:SetScale(max(0.4, min(1.2, ICON_SIZE / w))) end
                Place()
                hooksecurefunc(f, "SetPoint", function() if not placing then C_Timer.After(0, Place) end end)
            end)
        end
    end

    -- gold edge + overlay for coordinates (children of the map so they draw above it)
    Step("border", function()
        local overlay = CreateFrame("Frame", nil, Minimap)
        overlay:SetAllPoints(Minimap)
        overlay:SetFrameLevel(Minimap:GetFrameLevel() + 3)
        W.Border(overlay, 1, T.border, "OVERLAY")
        coordsText = overlay:CreateFontString(nil, "OVERLAY")
        coordsText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        coordsText:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        coordsText:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 4)
    end)

    -- zone bar above the map
    Step("zone bar", function()
        zoneBar = CreateFrame("Button", nil, holder)
        zoneBar:SetHeight(20)
        zoneBar:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 3)
        zoneBar:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, 3)
        -- flat: a soft dark strip with a thin line under it, no box (the zone name carries the color)
        W.Texture(zoneBar, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.65 }):SetAllPoints()
        local underline = zoneBar:CreateTexture(nil, "BORDER")
        underline:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.35)
        underline:SetPoint("BOTTOMLEFT"); underline:SetPoint("BOTTOMRIGHT"); underline:SetHeight(1)
        zoneBar.text = W.Text(zoneBar, 11, T.accent, "CENTER")
        zoneBar.text:SetPoint("CENTER", 0, 0)
        zoneBar.text:SetWidth(size - 8)
        zoneBar:SetScript("OnClick", function() if ToggleWorldMap then ToggleWorldMap() end end)
    end)

    -- right-click: tracking menu (left-click still pings)
    Step("tracking menu", function()
        Minimap:HookScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if trackMenu and trackMenu:IsShown() then CloseTracking() else OpenTracking(self) end
            end
        end)
    end)

    -- mouse-wheel zoom (the +/- buttons are gone)
    Step("zoom", function()
        Minimap:EnableMouseWheel(true)
        Minimap:SetScript("OnMouseWheel", function(self, delta)
            if not DB().wheelZoom then return end
            self:SetZoom(max(0, min(5, self:GetZoom() + (delta > 0 and 1 or -1))))
        end)
    end)

    local events = CreateFrame("Frame")
    for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    events:SetScript("OnEvent", function() MM:UpdateZone() end)
    C_Timer.NewTicker(0.5, function() MM:UpdateCoords() end)

    MM:Apply()
end

CUI:RegisterModule({
    key = "minimap",
    name = "Minimap",
    addon = "CysUI",
    desc = "Square gold-edged minimap with a zone bar, coordinates, mouse-wheel zoom and layout-mode positioning.",
    onEnable = MM.Enable,
    open = function() CUI:OpenConfig("Minimap") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Minimap", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Minimap", width):SetPoint("TOPLEFT", 0, -4)

    local function Check(label, key, y)
        local cb = W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; MM:Apply() end)
        cb:SetPoint("TOPLEFT", 4, y)
    end
    Check("Show the zone bar above the map", "zoneText", -34)
    Check("Show coordinates on the map", "coords", -60)
    Check("Zoom with the mouse wheel", "wheelZoom", -86)
    Check("Show Blizzard's clock under the map", "clock", -112)

    local note = W.Notes(page, 4, -152, width, "", {
            "Right-click the map for the tracking menu (Find Herbs, Find Minerals, Track Beasts...).",
            "The map stays square when you resize it.",
            "Tracking, mail, battleground and other status icons move to the map's corners. The calendar and zoom buttons are hidden.",
            "If the minimap ever looks wrong, untick Minimap under Modules and reload: the round Blizzard one comes right back.",
        })
end)
