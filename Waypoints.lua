--------------------------------------------------------------------------------
-- Cys's UI - Waypoints (a TomTom-style arrow)
--
--   * Ctrl + left-click anywhere on the world map to drop a waypoint.
--   * A small gold arrow shows which way to walk, how far it is and roughly how long it takes.
--   * /way 45.2 62.1 Some name     sets one in the zone you are in.
--   * /way clear                   removes them all.   Right-click the arrow to clear the current one.
--
-- Settings: /cui -> Waypoints.  Move the arrow with /cui layout.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local WP = {}
local ARROW = "Interface\\AddOns\\CysUI\\Media\\Arrow"

local function AddonLoaded(name)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return f and f(name) and true or false
end
CUI.Waypoints = WP

local floor, abs, sqrt, atan2, pi = math.floor, math.abs, math.sqrt, math.atan2 or function(y, x) return math.atan(y, x) end, math.pi

local function DB()
    CysUIDB.waypoints = CysUIDB.waypoints or {}
    local db = CysUIDB.waypoints
    if db.arrow == nil then db.arrow = true end
    if db.mapPin == nil then db.mapPin = true end
    if db.autoClear == nil then db.autoClear = true end
    if not db.clearAtV2 then db.clearAt = 5; db.clearAtV2 = true end
    if db.eta == nil then db.eta = true end
    if db.keep == nil then db.keep = true end
    if db.questie == nil then db.questie = false end
    db.points = db.points or {}
    return db
end

local frame, arrowTex, titleText, distText, etaText
local pin
local points = {}      -- the waypoints, newest last; the arrow follows the last one
local NewWorldMapPin

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------
local function MapName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or "?"
end

local function PlayerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

-- World position (in yards) of a map point. Returns instanceID, wx, wy, or nil.
local function World(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not pos then return nil end
    local wx, wy = pos:GetXY()
    return instance, wx, wy
end

-- How the map's east and south directions point in world coordinates (so any axis order works)
local axisCache = {}
local function Axes(mapID)
    local a = axisCache[mapID]
    if a ~= nil then return a or nil end
    local i0, x0, y0 = World(mapID, 0, 0)
    local i1, x1, y1 = World(mapID, 1, 0)
    local i2, x2, y2 = World(mapID, 0, 1)
    if i0 and i1 and i2 then
        a = { ex = x1 - x0, ey = y1 - y0, sx = x2 - x0, sy = y2 - y0, instance = i0 }
        a.el = a.ex * a.ex + a.ey * a.ey
        a.sl = a.sx * a.sx + a.sy * a.sy
        if a.el == 0 or a.sl == 0 then a = nil end
    end
    axisCache[mapID] = a or false
    return a
end

-- yards east, yards south and whether it is exact, from you to the point
local function Offset(wp)
    local pm, px, py = PlayerMap()
    if not pm then return nil end
    local axes = Axes(pm)
    if axes then
        local pi_, pwx, pwy = World(pm, px, py)
        local ti, twx, twy = World(wp.map, wp.x, wp.y)
        if pi_ and ti and pi_ == ti then
            local dx, dy = twx - pwx, twy - pwy
            local east = (dx * axes.ex + dy * axes.ey) / axes.el * sqrt(axes.el)
            local south = (dx * axes.sx + dy * axes.sy) / axes.sl * sqrt(axes.sl)
            return east, south, true
        end
        if pi_ and ti and pi_ ~= ti then return nil end
    end
    if pm == wp.map then -- no yard data: guess a typical zone size so the arrow still works
        return (wp.x - px) * 1000, (wp.y - py) * 700, false
    end
    return nil
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------
local function Save()
    local db = DB()
    if not db.keep then db.points = {}; return end
    local out = {}
    for i, p in ipairs(points) do out[i] = { map = p.map, x = p.x, y = p.y, title = p.title } end
    db.points = out
end

local Refresh

function WP:Add(mapID, x, y, title, silent)
    if not (mapID and x and y) then return end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    if x < 0 or y < 0 or x > 1 or y > 1 then return end
    for i = #points, 1, -1 do -- same spot again: replace it
        local p = points[i]
        if p.map == mapID and abs(p.x - x) < 0.0005 and abs(p.y - y) < 0.0005 then table.remove(points, i) end
    end
    local wp = { map = mapID, x = x, y = y, title = (title and title ~= "") and title or nil }
    points[#points + 1] = wp
    Save()
    Refresh()
    if not silent then
        CUI:Print(format("Waypoint set: %s (%.1f, %.1f)%s", MapName(mapID), x * 100, y * 100,
            wp.title and (" - " .. wp.title) or ""))
    end
    return wp
end

function WP:Remove(wp)
    for i = #points, 1, -1 do
        if points[i] == wp then table.remove(points, i) end
    end
    Save()
    Refresh()
end

function WP:Clear()
    wipe(points)
    Save()
    Refresh()
end

function WP:List() return points end

--------------------------------------------------------------------------------
-- The arrow
--------------------------------------------------------------------------------
local function Distance(yards)
    return format("%d yd", yards + 0.5)
end

local function Time(sec)
    if sec >= 3600 then return format("%dh %dm", sec / 3600, (sec % 3600) / 60) end
    if sec >= 60 then return format("%d:%02d", sec / 60, sec % 60) end
    return format("%ds", sec)
end

local lastDist, lastTime, speed
local current

local function UpdateArrow(_, elapsed)
    local wp = points[#points]
    if not wp then return end
    if wp ~= current then current = wp; lastDist, lastTime, speed = nil, nil, nil end
    local east, south, exact = Offset(wp)
    if not east then
        arrowTex:SetVertexColor(0.5, 0.5, 0.5)
        titleText:SetText(wp.title or MapName(wp.map))
        distText:SetText("not in this area")
        etaText:SetText("")
        return
    end
    local dist = sqrt(east * east + south * south)
    local db = DB()
    if db.autoClear and exact and dist <= db.clearAt then
        CUI:Print("You have arrived" .. (wp.title and (": " .. wp.title) or "."))
        WP:Remove(wp)
        return
    end
    local bearing = atan2(east, -south)          -- clockwise from north
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    arrowTex:SetRotation(-(bearing + facing))
    -- close = green, far = gold
    if dist < 40 then arrowTex:SetVertexColor(0.3, 1, 0.3)
    elseif dist < 120 then arrowTex:SetVertexColor(1, 0.9, 0.2)
    else arrowTex:SetVertexColor(1, 0.82, 0) end
    titleText:SetText(wp.title or MapName(wp.map))
    distText:SetText((exact and "" or "~") .. Distance(dist))

    -- ETA from how fast you have actually been closing in
    local now = GetTime()
    if lastDist and now - lastTime >= 1 then
        local s = (lastDist - dist) / (now - lastTime)
        speed = speed and (speed * 0.7 + s * 0.3) or s
        lastDist, lastTime = dist, now
    elseif not lastDist then
        lastDist, lastTime = dist, now
    end
    if db.eta and speed and speed > 0.5 then
        etaText:SetText(Time(dist / speed))
    else
        etaText:SetText("")
    end
end

function Refresh()
    if not frame then return end
    local db = DB()
    local wp = points[#points]
    if wp and db.arrow then
        frame:Show()
    else
        frame:Hide()
    end
    if pin then pin:Refresh() end
end

local function BuildArrow()
    frame = CreateFrame("Frame", "CysWaypointArrow", UIParent)
    frame:SetSize(120, 84)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            local wp = points[#points]
            if wp then WP:Remove(wp) end
        end
    end)

    arrowTex = frame:CreateTexture(nil, "ARTWORK")
    arrowTex:SetSize(34, 34)
    arrowTex:SetPoint("TOP", 0, -2)
    arrowTex:SetTexture(ARROW)
    arrowTex:SetVertexColor(1, 0.82, 0)

    titleText = W.Text(frame, 11, T.text, "CENTER")
    titleText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    titleText:SetPoint("TOP", arrowTex, "BOTTOM", 0, -2)
    titleText:SetWidth(116)
    distText = W.Text(frame, 13, T.accent, "CENTER")
    distText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    distText:SetPoint("TOP", titleText, "BOTTOM", 0, -2)
    etaText = W.Text(frame, 10, T.desc, "CENTER")
    etaText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    etaText:SetPoint("TOP", distText, "BOTTOM", 0, -1)

    local acc = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.04 then return end
        UpdateArrow(self, acc)
        acc = 0
    end)

    CUI:RegisterMovable(frame, "waypoint", "Waypoint arrow", { point = "TOP", x = 0, y = -180, scalable = true })
    frame:Hide()
end

--------------------------------------------------------------------------------
-- Pin on the world map + Ctrl+click
--------------------------------------------------------------------------------

local function MapID(map)
    if map.GetMapID then
        local ok, id = pcall(map.GetMapID, map)
        if ok and id then return id end
    end
    return map.mapID or (C_Map and C_Map.GetBestMapForUnit and nil)
end

local function FindCanvas(map)
    local scroll = map.ScrollContainer
    return (scroll and scroll.Child) or (map.GetCanvas and map:GetCanvas()) or WorldMapDetailFrame or WorldMapButton
end

local function HookWorldMap()
    local map = WorldMapFrame
    if not map or WP.hooked then return end
    local canvas = FindCanvas(map)
    if not canvas then WP.err = "no map canvas found"; return end
    WP.hooked = true
    WP.canvasName = canvas:GetName() or "Child"

    local function Cursor()
        local cx, cy = GetCursorPosition()
        local es = canvas:GetEffectiveScale()
        local l, t, w, h = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
        if not (cx and l and t and w and h) or w == 0 or h == 0 or not es or es == 0 then return nil end
        return (cx / es - l) / w, (t - cy / es) / h
    end

    -- Ctrl + left-click is detected by watching the mouse while the map is open, so it does not depend
    -- on which frame the map puts on top.
    local wasDown = false
    local function Poll()
        local down = IsMouseButtonDown("LeftButton") and IsControlKeyDown()
        if down and not wasDown then
            local area = map.ScrollContainer or canvas
            if MouseIsOver(area) then
                local x, y = Cursor()
                local mapID = MapID(map)
                if x and y and mapID and x >= 0 and y >= 0 and x <= 1 and y <= 1 then
                    local ok, err = pcall(WP.Add, WP, mapID, x, y)
                    if not ok then CUI:Print("Waypoint failed: " .. tostring(err)) end
                end
            end
        end
        wasDown = down and true or false
    end
    WP.poll = Poll
    WP.Cursor, WP.canvas, WP.map = Cursor, canvas, map

    pin = CreateFrame("Frame", nil, map)
    pin:SetSize(22, 22)
    pin:SetFrameStrata("FULLSCREEN_DIALOG")
    pin:SetFrameLevel(200)
    pin:SetSize(26, 26)
    pin.shadow = pin:CreateTexture(nil, "ARTWORK")
    pin.shadow:SetPoint("CENTER", 0, 0)
    pin.shadow:SetSize(34, 34)
    pin.shadow:SetTexture(ARROW)
    pin.shadow:SetVertexColor(0, 0, 0, 0.95)
    pin.shadow:SetRotation(pi)
    pin.tex = pin:CreateTexture(nil, "OVERLAY")
    pin.tex:SetAllPoints()
    pin.tex:SetTexture(ARROW)
    pin.tex:SetVertexColor(1, 1, 1)
    pin.tex:SetRotation(pi) -- point down at the spot
    pin.label = pin:CreateFontString(nil, "OVERLAY")
    pin.label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    pin.label:SetTextColor(1, 1, 1)
    pin.label:SetPoint("LEFT", pin, "RIGHT", 2, 0)
    pin:Hide()
    function pin:Refresh()
        local db = DB()
        local wp = points[#points]
        local mapID = map:IsShown() and MapID(map)
        if not (db.mapPin and wp and mapID == wp.map) then self:Hide(); return end
        local cES, pES = canvas:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local l, t, w, h = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
        if not (l and t and w and h and cES and pES and pES > 0) then self:Hide(); return end
        local sx, sy = (l + wp.x * w) * cES, (t - wp.y * h) * cES
        local own = self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", sx / own, sy / own)
        self.label:SetText(wp.title or "")
        self:Show()
    end
    map:HookScript("OnShow", function() pin:Refresh() end)
    local acc = 0
    map:HookScript("OnUpdate", function(_, e)
        acc = acc + e
        Poll()
        if acc > 0.2 then acc = 0; pin:Refresh() end
    end)
    pin:Refresh()
end

--------------------------------------------------------------------------------
-- /way
--------------------------------------------------------------------------------
local function Way(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    if lower == "clear" or lower == "reset" or lower == "off" then
        WP:Clear()
        CUI:Print("Waypoints cleared.")
        return
    end
    if lower == "debug" then
        CUI:Print(format("map frame: %s, hooked: %s, canvas: %s, points: %d, error: %s",
            tostring(WorldMapFrame ~= nil), tostring(WP.hooked), tostring(WP.canvasName), #points, tostring(WP.err)))
        if WP.map then
            local wp = points[#points]
            local l, t, w, h = WP.canvas:GetLeft(), WP.canvas:GetTop(), WP.canvas:GetWidth(), WP.canvas:GetHeight()
            CUI:Print(format("map shown: %s, map id: %s, waypoint map: %s, pin shown: %s, canvas: %s %s %s %s, cursor: %s",
                tostring(WP.map:IsShown()), tostring(WP.map.GetMapID and WP.map:GetMapID()), tostring(wp and wp.map),
                tostring(pin and pin:IsShown()), tostring(l), tostring(t), tostring(w), tostring(h),
                tostring(select(1, WP.Cursor()))))
        end
        return
    end
    if msg == "" or lower == "help" then
        CUI:Print("/way 45.2 62.1 [name]  sets a waypoint in this zone.  /way clear  removes them.  Ctrl+click the world map to drop one.")
        return
    end
    local x, y, name = msg:match("^(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*(.*)$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then
        CUI:Print("Try: /way 45.2 62.1 Name   (or /way clear)")
        return
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then CUI:Print("I can't tell which zone you're in."); return end
    WP:Add(mapID, x / 100, y / 100, name)
end

--------------------------------------------------------------------------------
-- Optional: answer other addons that talk to TomTom (Questie). Off by default.
--------------------------------------------------------------------------------
local function InstallTomTom()
    if _G.TomTom or AddonLoaded("TomTom") then return end
    local TT = {}
    local function Parse(...)
        local a = { ... }
        if a[1] == TT then table.remove(a, 1) end
        local mapID, x, y, opts = a[1], a[2], a[3], a[4]
        if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
        if x > 1 or y > 1 then x, y = x / 100, y / 100 end
        return mapID, x, y, type(opts) == "table" and opts or {}
    end
    function TT:AddWaypoint(...)
        local mapID, x, y, opts = Parse(TT, ...)
        if not mapID then return nil end
        return WP:Add(mapID, x, y, opts.title, true)
    end
    TT.AddZWaypoint = function(self, ...) return TT:AddWaypoint(...) end
    function TT:RemoveWaypoint(uid) if type(uid) == "table" then WP:Remove(uid) end end
    function TT:ClearWaypoint(uid) TT:RemoveWaypoint(uid) end
    function TT:SetCrazyArrow() end
    function TT:GetDistanceToWaypoint() return nil end
    _G.TomTom = TT
end

--------------------------------------------------------------------------------
-- Enable
--------------------------------------------------------------------------------
function WP.Enable()
    local db = DB()
    if db.keep then
        for _, p in ipairs(db.points) do
            if p.map and p.x and p.y then points[#points + 1] = { map = p.map, x = p.x, y = p.y, title = p.title } end
        end
    end
    BuildArrow()
    Refresh()

    if not AddonLoaded("TomTom") then
        SLASH_CYSWAY1 = "/way"
        SLASH_CYSWAY2 = "/cway"
        SlashCmdList["CYSWAY"] = Way
    else
        SLASH_CYSWAY1 = "/cway"
        SlashCmdList["CYSWAY"] = Way
    end

    if db.questie then InstallTomTom() end

    local function TryHook()
        if WP.hooked or not WorldMapFrame then return end
        local ok, err = pcall(HookWorldMap)
        if not ok then WP.hooked = false; WP.err = err; CUI:Print("Waypoints: world map hookup failed: " .. tostring(err)) end
    end
    TryHook()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", function(_, e)
        if e == "ZONE_CHANGED_NEW_AREA" then wipe(axisCache); return end
        TryHook()
    end)
end

CUI:RegisterModule({
    key = "waypoints",
    name = "Waypoints",
    addon = "CysUI",
    desc = "A TomTom-style arrow: Ctrl+click the world map (or type /way 45 62) and an arrow shows the way, the distance and the time left.",
    onEnable = WP.Enable,
    open = function() CUI:OpenConfig("Waypoints") end,
})

CUI:RegisterPage("Waypoints", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Waypoints", width):SetPoint("TOPLEFT", 0, -4)

    local how = W.Text(page, 12, T.text)
    how:SetPoint("TOPLEFT", 4, -34)
    how:SetWidth(width - 8)
    how:SetJustifyV("TOP")
    how:SetSpacing(3)
    how:SetText("|cFFFFD100Ctrl + left-click|r the world map to set a waypoint, or type |cFFFFD100/way 45.2 62.1 Name|r. "
        .. "Right-click the arrow to clear it, |cFFFFD100/way clear|r clears everything.")

    local y = -84
    local function Check(label, key, after)
        local c = W.Checkbox(page, label, function() return db[key] end, function(on) db[key] = on; if after then after() end end)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
        return c
    end
    Check("Show the arrow", "arrow", Refresh)
    Check("Show a pin on the world map", "mapPin", Refresh)
    Check("Show the time left", "eta")
    Check("Clear a waypoint when I get there", "autoClear")
    Check("Remember waypoints after I log out", "keep", Save)
    local arrive = W.Button(page, 300, 22, "")
    local STEPS = { 3, 5, 10, 20, 40 }
    local function ArriveLabel() arrive:SetLabel("Clear it when I'm within: " .. db.clearAt .. " yd (click to change)") end
    ArriveLabel()
    arrive:SetPoint("TOPLEFT", 4, y)
    arrive:SetScript("OnClick", function()
        local nxt = STEPS[1]
        for i, v in ipairs(STEPS) do if v == db.clearAt then nxt = STEPS[i % #STEPS + 1] end end
        db.clearAt = nxt
        ArriveLabel()
    end)
    y = y - 30
    local q = Check("Answer other addons' TomTom requests, like Questie's (needs a /reload)", "questie")

    local list = W.Text(page, 12, T.accent)
    list:SetPoint("TOPLEFT", 4, y - 8)
    list:SetText("Your waypoints")
    local rows = {}
    local rowTop = y - 32
    local function Rebuild()
        for _, r in ipairs(rows) do r:Hide() end
        local pts = WP:List()
        if #pts == 0 then
            rows.empty = rows.empty or W.Text(page, 11, T.desc)
            rows.empty:ClearAllPoints()
            rows.empty:SetPoint("TOPLEFT", 4, rowTop)
            rows.empty:SetText("None yet.")
            rows.empty:Show()
        elseif rows.empty then
            rows.empty:Hide()
        end
        for i = #pts, math.max(1, #pts - 7), -1 do
            local wp = pts[i]
            local n = #pts - i + 1
            local row = rows[n]
            if not row then
                row = CreateFrame("Frame", nil, page)
                row:SetSize(width - 8, 22)
                row.text = W.Text(row, 12, T.text)
                row.text:SetPoint("LEFT", 0, 0)
                row.btn = W.Button(row, 70, 20, "Remove")
                row.btn:SetPoint("RIGHT", 0, 0)
                rows[n] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, rowTop - (n - 1) * 24)
            row.text:SetText(format("%s %.1f, %.1f%s", MapName(wp.map), wp.x * 100, wp.y * 100,
                wp.title and (" - " .. wp.title) or ""))
            row.btn:SetScript("OnClick", function() WP:Remove(wp); Rebuild() end)
            row:Show()
        end
    end
    Rebuild()

    local clear = W.Button(page, 130, 22, "Clear all")
    clear:SetPoint("TOPLEFT", 4, rowTop - 8 * 24 - 8)
    clear:SetScript("OnClick", function() WP:Clear(); Rebuild() end)
    local move = W.Button(page, 220, 22, "Move the arrow (layout mode)")
    move:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
    page:HookScript("OnShow", Rebuild)
    page.contentHeight = 600
end)
