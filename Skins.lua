--------------------------------------------------------------------------------
-- Cys's UI - Skins
--
-- Gives Blizzard's own windows the gold-and-dark Cys look: the stone art is removed,
-- a flat dark panel with a gold edge goes behind it, and the buttons, tabs and close
-- buttons are restyled. Each window has its own switch on the Skins page. Every skin
-- runs inside pcall, so a window that looks different on another game version is
-- simply skipped instead of breaking anything.
--
-- Windows from load-on-demand Blizzard addons (Talents, Macros) are skinned the
-- moment they load. "/cysskin <FrameName>" lists a frame's art and children, which is
-- how new windows get added.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local Skins = {}
CUI.Skins = Skins

local max = math.max
local min = math.min

local function DB()
    CysUIDB.skins = CysUIDB.skins or {}
    local db = CysUIDB.skins
    for _, f in ipairs(Skins.list or {}) do
        if db[f.key] == nil then db[f.key] = true end
    end
    return db
end

--------------------------------------------------------------------------------
-- Helpers
--
-- Blizzard art is hidden by setting its alpha to 0 (not by Hide / SetTexture(nil)):
-- the game's own scripts re-show and re-texture these pieces whenever a window
-- opens, a tab is picked or a button is pressed, but they never touch the alpha.
--------------------------------------------------------------------------------
local function Get(name) return name and _G[name] end

local function Own(obj) obj.cysOwn = true; return obj end

local firstError
local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not firstError then
        firstError = true
        CUI:Print("|cFFFF4040A skin step failed:|r " .. tostring(err) .. "  (tell Claude this line)")
    end
end

-- Children of a frame, skipping anything that is not a normal frame (some windows hold odd objects
-- that make GetObjectType / GetChildren error out)
local function Kids(f)
    local out = {}
    local ok, list = pcall(function() return { f:GetChildren() } end)
    if not ok or type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        local okT = pcall(c.GetObjectType, c)
        if okT then out[#out + 1] = c end
    end
    return out
end

-- Fade out every texture on a frame (portraits included), except ours
local function Blank(f, keep)
    if not f or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and not r.cysOwn and not (keep and keep(r)) then
            r:SetAlpha(0)
        end
    end
end

-- A button's own state art (normal / pushed / highlight / disabled) plus its background pieces
local function BlankButtonArt(b)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[getter] and b[getter](b)
        if t then t:SetAlpha(0) end
    end
    Blank(b)
end

-- Hide the usual art children that newer frame templates use (nine-slices, title bars...)
local ART_KEYS = { "NineSlice", "Border", "Bg", "BG", "TopTileStreaks", "TitleBg", "Inset", "InsetBorderTop",
    "PortraitContainer", "portrait", "Portrait" }
local function StripArtChildren(f)
    for _, k in ipairs(ART_KEYS) do
        local c = f[k]
        if type(c) == "table" and c.SetAlpha then c:SetAlpha(0) end
    end
end

-- Remove a window's own art: its textures, its template art children and its portrait
local function Strip(f, keep)
    if not f then return end
    Blank(f, keep)
    StripArtChildren(f)
    local n = f.GetName and f:GetName()
    local p = n and _G[n .. "Portrait"]
    if p and p.SetAlpha then p:SetAlpha(0) end
end

-- Flat dark panel with a gold edge, sitting behind the frame. l/t/r/b move it in from the frame's edges.
local function Panel(f, l, t, r, b)
    if f.cysPanel then return f.cysPanel end
    local bd = Own(CreateFrame("Frame", nil, f))
    bd:SetPoint("TOPLEFT", f, "TOPLEFT", l or 0, t or 0)
    bd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", r or 0, b or 0)
    bd:SetFrameLevel(max(f:GetFrameLevel() - 1, 0))
    W.Texture(bd, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(bd, 1, T.border, "BORDER")
    f.cysPanel = bd
    return bd
end

-- Flat box (dark fill, edge in `color`) sitting just under `owner`'s own text
local function Box(owner, color, insetX, insetY)
    local box = Own(CreateFrame("Frame", nil, owner))
    box:SetPoint("TOPLEFT", insetX or 0, -(insetY or 0))
    box:SetPoint("BOTTOMRIGHT", -(insetX or 0), insetY or 0)
    box:SetFrameLevel(max(owner:GetFrameLevel() - 1, 0))
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    box.edges = W.Border(box, 1, color or T.border, "BORDER")
    return box
end

local function HasStoneParts(b)
    local n = b.GetName and b:GetName()
    local function part(k) return b[k] or (n and _G[n .. k]) end
    if part("LeftDisabled") or part("LeftActive") then return false end -- tabs are handled separately
    return part("Left") and part("Right") and (part("Middle") or part("Center")) and true or false
end

-- Blizzard's red stone button -> flat dark button with a gold edge that lights up on hover
local function FlatButton(b, edge)
    if not b or b.cysSkinned then return end
    b.cysSkinned = true
    BlankButtonArt(b)
    local box = Box(b, edge or T.border, 0, 0)
    local hl = W.Texture(box, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.22 })
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:Hide()
    b:HookScript("OnEnter", function() W.SetBorder(box.edges, T.accent); hl:Show() end)
    b:HookScript("OnLeave", function() W.SetBorder(box.edges, edge or T.border); hl:Hide() end)
end

-- Any button at all (even text-only ones like the Esc menu's): flat box, gold edge, lit on hover
local function BoxButton(b, insetX, insetY)
    if not b or b.cysBoxed then return end
    b.cysBoxed = true
    if HasStoneParts(b) then b.cysSkinned = true; BlankButtonArt(b) end
    local box = Own(CreateFrame("Frame", nil, b))
    box:SetPoint("TOPLEFT", insetX or 0, -(insetY or 0))
    box:SetPoint("BOTTOMRIGHT", -(insetX or 0), insetY or 0)
    box:SetFrameLevel(b:GetFrameLevel())
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    local edges = W.Border(box, 1, T.border, "BORDER")
    local hl = W.Texture(box, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.22 })
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:Hide()
    b:HookScript("OnEnter", function() W.SetBorder(edges, T.accent); hl:Show() end)
    b:HookScript("OnLeave", function() W.SetBorder(edges, T.border); hl:Hide() end)
end

-- The red-X close button becomes a plain "X" in the panel's corner
local function SkinClose(btn, panel)
    if not btn or btn.cysSkinned then return end
    btn.cysSkinned = true
    BlankButtonArt(btn)
    btn:SetSize(22, 22)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    local label = btn.GetFontString and btn:GetFontString()
    if label then -- some close buttons carry the word "Close"; the X replaces it, and it stays hidden
        label:SetAlpha(0); label:Hide()
        if label.SetText then label:SetText("") end
        hooksecurefunc(label, "Show", function(self) self:Hide() end)
    end
    -- some close buttons draw their red X from a child frame or a texture that gets set again later: hide those too
    local function Clean()
        BlankButtonArt(btn)
        for _, c in ipairs(Kids(btn)) do
            if not c.cysOwn and c.SetAlpha then c:SetAlpha(0) end
        end
        if label then label:SetAlpha(0) end
        -- loose pictures and words on the button itself (a hover "Close" and red X): hide every one that isn't our own X
        for _, r in ipairs({ btn:GetRegions() }) do
            if not r.cysOwn and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    Clean()
    btn:HookScript("OnShow", Clean)
    btn:HookScript("OnEnter", Clean)
    btn:HookScript("OnLeave", Clean)
    local x = W.Text(btn, 14, T.text, "CENTER")
    x:SetPoint("CENTER", 0, 0)
    x:SetText("X")
    x.cysOwn = true
    btn:HookScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    btn:HookScript("OnLeave", function() x:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
end

-- Bottom tabs: flat dark tab with a hairline edge; gold text and edge when selected
local function PaintTab(tab, selected)
    if not tab.cysSkinned then return end
    Blank(tab)
    local n = tab:GetName()
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled",
        "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
        local t = tab[k] or (n and _G[n .. k])
        if t and t.SetAlpha and not t.cysOwn then t:SetAlpha(0) end
    end
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    local fs = tab.Text or (n and _G[n .. "Text"]) or (tab.GetFontString and tab:GetFontString())
    if fs then
        local c = selected and T.accent or T.text
        fs:SetTextColor(c[1], c[2], c[3])
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab.cysBox, "CENTER", 0, 0) -- Blizzard re-offsets it on every select; we re-centre it
    end
    W.SetBorder(tab.cysBox.edges, selected and T.border or T.line)
    tab.cysFill:SetColorTexture((selected and T.card or T.field)[1], (selected and T.card or T.field)[2], (selected and T.card or T.field)[3], 1)
end

-- Tabs hang off the bottom edge of the panel. Blizzard's tab frame is 32 tall and its top sits 2px above the
-- panel's bottom edge, so a box from 2px under the top down to 8px above the bottom touches the panel.
local BOTTOM_TAB = { 2, -2, -2, 8 }
local function SkinTab(tab, geo)
    if not tab or tab.cysSkinned then return end
    tab.cysSkinned = true
    geo = geo or BOTTOM_TAB
    tab.cysBox = Own(CreateFrame("Frame", nil, tab))
    tab.cysBox:SetPoint("TOPLEFT", geo[1], geo[2])
    tab.cysBox:SetPoint("BOTTOMRIGHT", geo[3], geo[4])
    tab.cysBox:SetFrameLevel(max(tab:GetFrameLevel() - 1, 0))
    tab.cysFill = W.Texture(tab.cysBox, "BACKGROUND", T.field)
    tab.cysFill:SetAllPoints()
    tab.cysBox.edges = W.Border(tab.cysBox, 1, T.line, "BORDER")
    PaintTab(tab, false)
end

-- Lay the row out ourselves so the boxes sit edge to edge under the panel (Blizzard's spacing leaves
-- uneven dark gaps). Hidden tabs (e.g. Pet for non-hunters) are skipped.
local function LayoutRow(row)
    local prev
    for _, tab in ipairs(row.tabs) do
        if tab:IsShown() then
            tab:ClearAllPoints()
            if prev then
                tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", -3, 0)
            else
                tab:SetPoint("TOPLEFT", row.panel, "BOTTOMLEFT", 2, 2)
            end
            prev = tab
        end
    end
end

local function SkinTabs(prefix, count, selected, geo, panel)
    local row = panel and { panel = panel, tabs = {} }
    for i = 1, count do
        local tab = Get(prefix .. i)
        if tab then
            Safe(SkinTab, tab, geo)
            Safe(PaintTab, tab, selected and selected() == i)
            if row then
                row.tabs[#row.tabs + 1] = tab
                tab.cysRow = row
                tab:HookScript("OnShow", function() Safe(LayoutRow, row) end)
            end
        end
    end
    if row then Safe(LayoutRow, row) end
end

-- Blizzard re-shows the stone tab art whenever a tab is selected; repaint after it does
local tabHooked
local function HookTabs()
    if tabHooked or not hooksecurefunc then return end
    tabHooked = true
    if PanelTemplates_TabResize then
        hooksecurefunc("PanelTemplates_TabResize", function(tab)
            if tab and tab.cysRow then Safe(LayoutRow, tab.cysRow) end
        end)
    end
    if PanelTemplates_SelectTab then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab) Safe(PaintTab, tab, true) end)
    end
    if PanelTemplates_DeselectTab then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab) Safe(PaintTab, tab, false) end)
    end
end

-- Scrollbars: thin dark track, flat gold thumb, plain ^ / v arrows
local function SkinArrow(btn, glyph)
    if not btn or btn.cysSkinned then return end
    btn.cysSkinned = true
    BlankButtonArt(btn)
    local fs = W.Text(btn, 11, T.text, "CENTER")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(glyph)
    btn:HookScript("OnEnter", function() fs:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    btn:HookScript("OnLeave", function() fs:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
end

local SkinMinimalScrollBar -- defined further down
local function SkinScrollBar(sb)
    if sb.cysSkinned then return end
    sb.cysSkinned = true
    local n = sb:GetName() or ""
    Blank(sb)
    SkinArrow(sb.ScrollUpButton or _G[n .. "ScrollUpButton"], "^")
    SkinArrow(sb.ScrollDownButton or _G[n .. "ScrollDownButton"], "v")
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    if thumb then
        thumb:SetAlpha(0)
        local mine = sb:CreateTexture(nil, "OVERLAY")
        mine.cysOwn = true
        mine:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.7)
        mine:SetPoint("TOPLEFT", thumb, "TOPLEFT", 4, -1)
        mine:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -4, 1)
    end
    local track = W.Texture(sb, "BACKGROUND", T.field)
    track.cysOwn = true
    track:SetPoint("TOPLEFT", 3, 0)
    track:SetPoint("BOTTOMRIGHT", -3, 0)
end

-- Reputation rows: drop the chunky stone frame, keep a hairline box around the bar itself
local function SkinRepBar(bar)
    if bar.cysSkinned then return end
    bar.cysSkinned = true
    local n = bar:GetName()
    for _, k in ipairs({ "ReputationBarLeft", "ReputationBarRight" }) do
        local t = n and _G[n .. k]
        if t then t:SetAlpha(0) end
    end
    Box(bar, T.line, 0, 0)
    -- flat fill instead of Blizzard's glossy bar; the standing colour is kept
    local r, g, b = bar:GetStatusBarColor()
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    if r then bar:SetStatusBarColor(r, g, b) end
end

-- Walk a window's children (a few levels deep) and restyle the stone parts found there
local function Walk(f, fn, depth, skip)
    for _, c in ipairs(Kids(f)) do
        if not c.cysOwn and not (skip and skip(c)) then
            Safe(fn, c)
            if depth > 1 then Walk(c, fn, depth - 1, skip) end
        end
    end
end

local function SkinTree(f, depth, skip)
    Walk(f, function(c)
        local okT, t = pcall(c.GetObjectType, c)
        if not okT then return end
        if t == "Slider" then
            local n = c:GetName() or ""
            if c.ScrollUpButton or n:find("ScrollBar") then SkinScrollBar(c) end
        elseif t == "ScrollFrame" then
            Blank(c)
        elseif t == "Button" then
            if not c.cysSkinned and HasStoneParts(c) then FlatButton(c) end
        elseif t == "StatusBar" then
            local n = c:GetName()
            if n and n:find("^ReputationBar%d") then SkinRepBar(c) end
        end
    end, depth or 3, skip)
end

local function TitleText(fs)
    if fs and fs.SetTextColor then fs:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end
end

--------------------------------------------------------------------------------
-- The windows
--------------------------------------------------------------------------------
local function SkinMenu()
    local f = Get("GameMenuFrame")
    if not f then return end
    Strip(f)
    Panel(f, 0, 0, 0, 0)
    local header = f.Header
    if header then
        Strip(header)
        local txt = header.Text or Get("GameMenuFrameHeaderText")
        if txt then
            txt:ClearAllPoints()
            txt:SetPoint("TOP", f, "TOP", 0, -12)
            TitleText(txt)
        end
    end
    local function BoxAll(self)
        for _, c in ipairs(Kids(self)) do
            if c.GetObjectType and c:GetObjectType() == "Button" and not c.cysOwn then Safe(BoxButton, c, 6, 1) end
        end
    end
    BoxAll(f)
    f:HookScript("OnShow", BoxAll) -- buttons some versions add later
end

-- Character window: the name / level / guild lines sit on the middle of Blizzard's wider frame, not of our panel
local function CenterCharacterTexts(f, panel)
    local list = {}
    for _, n in ipairs({ "CharacterNameText", "CharacterLevelText", "CharacterGuildText" }) do
        local fs = Get(n)
        if fs and fs.SetPoint then list[#list + 1] = fs end
    end
    local busy
    local function Place()
        for _, fs in ipairs(list) do
            if not fs.cysDY then
                local t, pt = fs:GetTop(), panel:GetTop()
                if t and pt then fs.cysDY = t - pt end
            end
            if fs.cysDY then
                busy = true
                fs:ClearAllPoints()
                fs:SetPoint("TOP", panel, "TOP", 0, fs.cysDY)
                fs:SetJustifyH("CENTER")
                busy = false
            end
        end
    end
    for _, fs in ipairs(list) do
        hooksecurefunc(fs, "SetPoint", function(self)
            if busy or not self.cysDY then return end
            Place()
        end)
    end
    f:HookScript("OnShow", Place)
    if PaperDollFrame then PaperDollFrame:HookScript("OnShow", Place) end
    Place()
end

-- Equipment slots: flat dark boxes with a thin edge that takes the colour of the item, like the rest of the UI
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
    "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local function PaintSlot(b)
    local id = b:GetID()
    local q = id and GetInventoryItemQuality and GetInventoryItemQuality("player", id)
    local col = T.line -- plain items and empty slots: a quiet edge; green and better take the item colour
    local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then col = { c.r, c.g, c.b } end
    b.cysSlotColor = col
    if b.cysSlotBox then W.SetBorder(b.cysSlotBox.edges, col) end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if b.IconBorder and b.IconBorder.SetAlpha then b.IconBorder:SetAlpha(0) end
end
local function SkinSlots(f)
    local slots = {}
    for _, n in ipairs(SLOT_NAMES) do
        local b = Get("Character" .. n .. "Slot")
        if b and not b.cysSlotSkinned then
            b.cysSlotSkinned = true
            local icon = b.icon or b.Icon or Get("Character" .. n .. "SlotIconTexture")
            Blank(b, function(r) return r == icon end)
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            b.cysSlotBox = Box(b, T.line, -1, -1) -- the edge sits just outside the icon, which would otherwise cover it
            b:HookScript("OnEnter", function() W.SetBorder(b.cysSlotBox.edges, T.accent) end)
            b:HookScript("OnLeave", function() W.SetBorder(b.cysSlotBox.edges, b.cysSlotColor or T.line) end)
        end
        if b and b.cysSlotSkinned then slots[#slots + 1] = b end
    end
    local function PaintAll() for _, b in ipairs(slots) do PaintSlot(b) end end
    if hooksecurefunc and PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(btn) if btn and btn.cysSlotSkinned then PaintSlot(btn) end end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ev:SetScript("OnEvent", PaintAll)
    f:HookScript("OnShow", PaintAll)
    PaintAll()
end

-- Skills tab: flat gold-brown bars in a hairline box instead of the blue glossy ones
local function SkinSkillBars()
    for i = 1, 40 do
        local bar = Get("SkillRankFrame" .. i)
        if bar and not bar.cysSkinned then
            bar.cysSkinned = true
            local n = bar:GetName()
            for _, k in ipairs({ "Border", "Background" }) do
                local t = Get(n .. k)
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local busy
            local function Tint(self)
                if busy then return end
                busy = true
                self:SetStatusBarColor(T.brand[1] * 0.55, T.brand[2] * 0.55, T.brand[3] * 0.4)
                busy = false
            end
            Tint(bar)
            hooksecurefunc(bar, "SetStatusBarColor", Tint)
            Box(bar, T.line, 0, 0)
        end
    end
end

-- Skills tab: the list only filled the top half of the window; spread its 12 rows down to the Close button
local function LayoutSkills(sf)
    if sf.cysLaid or not sf:IsShown() then return end
    local first = Get("SkillRankFrame1") or Get("SkillTypeLabel1")
    local cf = Get("CharacterFrame")
    local panel = cf and cf.cysPanel
    if not (first and first:GetTop() and sf:GetTop() and panel and panel:GetBottom()) then return end
    local close = Get("SkillFrameCancelButton")
    local limit = (close and close:GetTop() and (close:GetTop() + 8)) or (panel:GetBottom() + 40)
    local second = Get("SkillRankFrame2") or Get("SkillTypeLabel2")
    local base = (second and second:GetTop()) and (first:GetTop() - second:GetTop()) or 16
    local rows = 12
    local spacing = (first:GetTop() - limit) / rows
    spacing = math.min(spacing, 30)
    if spacing < base + 2 then sf.cysLaid = true return end
    sf.cysLaid = true
    local fl, ft = sf:GetLeft(), sf:GetTop()
    for _, prefix in ipairs({ "SkillTypeLabel", "SkillRankFrame" }) do
        local row1 = Get(prefix .. "1")
        if row1 and row1:GetTop() then
            local y0 = ft - row1:GetTop()
            for i = 1, rows do
                local row = Get(prefix .. i)
                if row and row:GetLeft() then
                    local x = row:GetLeft() - fl
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", sf, "TOPLEFT", x, -(y0 + (i - 1) * spacing))
                end
            end
        end
    end
    -- the scroll bar follows the taller list
    local scroll = Get("SkillListScrollFrame")
    local extra = (spacing - base) * rows
    if scroll and extra > 0 then
        local pts = {}
        for i = 1, scroll:GetNumPoints() do pts[i] = { scroll:GetPoint(i) } end
        if #pts == 1 then
            scroll:SetHeight(scroll:GetHeight() + extra)
        else
            scroll:ClearAllPoints()
            for _, pt in ipairs(pts) do
                local y = pt[5] or 0
                if string.find(pt[1], "BOTTOM", 1, true) then y = y - extra end
                scroll:SetPoint(pt[1], pt[2], pt[3], pt[4] or 0, y)
            end
        end
    end
end

local function SkinCharacter()
    local f = Get("CharacterFrame")
    if not f then return end
    for _, name in ipairs({ "CharacterFrame", "PaperDollFrame", "ReputationFrame", "SkillFrame", "HonorFrame", "TokenFrame" }) do
        Strip(Get(name))
    end
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("CharacterFrameCloseButton"), panel)
    TitleText(Get("CharacterNameText"))
    HookTabs()
    SkinTabs("CharacterFrameTab", tonumber(f.numTabs) or 5, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)
    SkinTree(f, 3)
    Safe(CenterCharacterTexts, f, panel)
    Safe(SkinSlots, f)
    Safe(SkinSkillBars)
    -- Honor tab: the progress bar becomes flat, in a hairline box
    local hb = Get("HonorFrameProgressBar")
    if hb and not hb.cysSkinned then
        hb.cysSkinned = true
        Blank(hb)
        local r, g, b = hb:GetStatusBarColor()
        Box(hb, T.line, 0, 0)
        hb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if r then hb:SetStatusBarColor(r, g, b) end
    end
    local sf = Get("SkillFrame")
    if sf then
        sf:HookScript("OnShow", function(self)
            Safe(SkinSkillBars)
            if C_Timer and C_Timer.After then C_Timer.After(0, function() Safe(LayoutSkills, self) end) else Safe(LayoutSkills, self) end
        end)
    end
end

-- Rank / subtext under spell names is dark grey by default; make it easy to read
local function PaintSpellText()
    for i = 1, 12 do
        local sub = Get("SpellButton" .. i .. "SubSpellName")
        if sub then sub:SetTextColor(0.9, 0.9, 0.9) end
        -- the brown stone "empty slot" square becomes a plain dark box, shown only while the slot is empty
        local b = Get("SpellButton" .. i)
        local empty = b and (b.EmptySlot or Get("SpellButton" .. i .. "Background"))
        if empty then
            empty:SetAlpha(0)
            if not b.cysEmpty then
                b.cysEmpty = Box(b, T.line, 0, 0)
            end
            b.cysEmpty:SetShown(empty:IsShown())
        end
    end
end

-- The skill-line tabs down the right edge (and addon tabs like Clique's): square gold-edged icons
local function PaintSideTabs()
    local f = Get("SpellBookFrame")
    if not f then return end
    local function Paint(c)
        if c.cysBox then
            local on = c.GetChecked and c:GetChecked()
            W.SetBorder(c.cysBox.edges, on and T.accent or T.border)
        end
    end
    local function Consider(c)
        if c.cysOwn or c.GetObjectType == nil or c:GetObjectType() ~= "CheckButton" then return end
        local n = c:GetName()
        if not n or not n:lower():find("tab") then return end
        if not c.cysBox then
            local icon, glow = c:GetNormalTexture(), c:GetHighlightTexture()
            Blank(c, function(r) return r == icon or r == glow end) -- keep the icon; only the stone wedge goes
            local ch = c.GetCheckedTexture and c:GetCheckedTexture()
            if ch then ch:SetAlpha(0) end
            c.cysBox = Box(c, T.border, -2, -2)
            c.cysBox:SetFrameLevel(max(c:GetFrameLevel() - 1, 0))
            c:HookScript("OnEnter", function() W.SetBorder(c.cysBox.edges, T.accent) end)
            c:HookScript("OnLeave", function() Paint(c) end)
            c:HookScript("OnClick", function() PaintSideTabs() end)
        end
        Paint(c)
    end
    for _, c in ipairs(Kids(f)) do
        Consider(c)
        for _, cc in ipairs(Kids(c)) do Consider(cc) end
    end
end

local function SkinSpellbook()
    local f = Get("SpellBookFrame")
    if not f then return end
    Strip(f)
    PaintSpellText()
    PaintSideTabs()
    f:HookScript("OnShow", function() PaintSpellText(); PaintSideTabs() end) -- addon tabs appear late
    if hooksecurefunc then
        if SpellBookFrame_Update then hooksecurefunc("SpellBookFrame_Update", function() PaintSpellText(); PaintSideTabs() end) end
        for i = 1, 12 do
            local b = Get("SpellButton" .. i)
            if b and b.UpdateButton then hooksecurefunc(b, "UpdateButton", PaintSpellText) end
        end
    end
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("SpellBookCloseButton"), panel)
    HookTabs()
    SkinTabs("SpellBookFrameTabButton", 3, function() return f.selectedTab end, nil, panel)
    SkinTree(f, 3)
end

-- Blizzard's own class art for the open talent tree, drawn dim behind the talent buttons
local TALENT_ART = { -- fallback file names per class and tab, in tab order
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
}
local function TalentArt(f, panel)
    if f.cysArt then return end
    local art = Own(CreateFrame("Frame", nil, panel))
    art:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2) -- the whole window, behind the title, header and bottom row
    art:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    art:SetFrameLevel(panel:GetFrameLevel() + 1)
    f.cysArt = art
    local pieces = {
        -- the pictures hold 256 + 128 rows but only about 76 of the lower 128 are drawn on; crop the empty rest
        -- so the art fills the whole window
        TopLeft = { "TOPLEFT", 0.8, 256 / 332 }, TopRight = { "TOPRIGHT", 0.2, 256 / 332 },
        BottomLeft = { "BOTTOMLEFT", 0.8, 76 / 332, 76 / 128 }, BottomRight = { "BOTTOMRIGHT", 0.2, 76 / 332, 76 / 128 },
    }
    local tex = {}
    for name, d in pairs(pieces) do
        local t = art:CreateTexture(nil, "ARTWORK")
        t:SetPoint(d[1])
        t:SetVertexColor(0.62, 0.62, 0.62)
        t:SetAlpha(0.8)
        if d[4] then t:SetTexCoord(0, 1, 0, d[4]) end
        tex[name] = t
    end
    local lastTab, lastW, lastH
    local function Selected()
        local tab = f.selectedTab
        if not tab and PanelTemplates_GetSelectedTab then tab = PanelTemplates_GetSelectedTab(f) end
        return tonumber(tab) or 1
    end
    local function FileFor(tab)
        local _, class = UnitClass("player")
        if GetTalentTabInfo then
            local ok, a, b, c, d, e, g = pcall(GetTalentTabInfo, tab)
            if ok then
                for _, v in ipairs({ a, b, c, d, e, g }) do
                    if type(v) == "string" and class and string.find(string.lower(v), string.lower(class), 1, true) == 1 then return v end
                end
            end
        end
        local list = class and TALENT_ART[class]
        return list and list[tab]
    end
    local function Refresh()
        local tab = Selected()
        local w, h = art:GetWidth(), art:GetHeight()
        if tab ~= lastTab then
            lastTab = tab
            local file = FileFor(tab)
            for name, t in pairs(tex) do
                if file then t:SetTexture("Interface\\TalentFrame\\" .. file .. "-" .. name); t:Show() else t:Hide() end
            end
            lastW = nil
        end
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            for name, d in pairs(pieces) do tex[name]:SetSize(max(w * d[2], 1), max(h * d[3], 1)) end
        end
    end
    art:SetScript("OnUpdate", Refresh) -- every frame: only compares a few numbers, and the art swaps with the tab at once
    art:HookScript("OnShow", Refresh)
    Refresh()
end

local function SkinTalents()
    local f = Get("TalentFrame") or Get("PlayerTalentFrame")
    if not f then return end
    Strip(f, function(r) -- keep the talent-tree background art, only the window frame goes
        local n = r:GetName()
        return n and n:find("Background") ~= nil
    end)
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("TalentFrameCloseButton") or Get("PlayerTalentFrameCloseButton"), panel)
    HookTabs()
    SkinTabs("TalentFrameTab", 4, nil, nil, panel)
    SkinTabs("PlayerTalentFrameTab", 4, nil, nil, panel)
    SkinTree(f, 3)
    TalentArt(f, panel)
end

local function SkinMacros()
    local f = Get("MacroFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 0, 3, 26, -8) -- reaches down past the Delete / New / Exit row
    SkinClose(Get("MacroFrameCloseButton"), panel)
    -- the macro list's scroll bar, and the box around the macro text
    local sel = f.MacroSelector
    if sel and sel.ScrollBar then Safe(SkinMinimalScrollBar, sel.ScrollBar) end
    local tb = Get("MacroFrameTextBackground")
    if tb and not tb.cysBox then
        tb.cysBox = true
        if tb.NineSlice then tb.NineSlice:SetAlpha(0) end
        Blank(tb)
        Box(tb, T.line, 0, 0)
    end
    if sel and sel.ScrollBar then
        for _, k in ipairs({ "Background", "Backplate" }) do
            local part = sel.ScrollBar[k]
            if part and part.SetAlpha then part:SetAlpha(0) end
        end
    end
    HookTabs()
    SkinTabs("MacroFrameTab", 2, nil, { 4, -3, -4, 3 })
    SkinTree(f, 4)
    local pop = Get("MacroPopupFrame")
    if pop then
        Strip(pop)
        Panel(pop, 6, -6, -6, 6)
        SkinTree(pop, 3)
    end

    -- The icon slots (the macro list, the selected macro and the icon picker) keep the stone slot art.
    -- The list is recycled by its scroll box, so look again now and then while the window is open.
    local function SkinSlot(btn)
        if not btn or btn.cysSlot or btn.cysOwn then return end
        local okT, typ = pcall(btn.GetObjectType, btn)
        if not okT or (typ ~= "Button" and typ ~= "CheckButton") then return end
        local name = btn.GetName and btn:GetName()
        local icon = btn.Icon or btn.icon or (name and _G[name .. "Icon"])
        if not (icon and icon.SetTexCoord) then return end
        btn.cysSlot = true
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        local ck = btn.GetCheckedTexture and btn:GetCheckedTexture()
        Blank(btn, function(r)
            return r == icon or r == hl or r == ck or r == btn.SelectedTexture or r == btn.Selected
        end)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        Box(btn, T.line, 0, 0)
    end
    local function Each(root, depth)
        if not root then return end
        for _, c in ipairs(Kids(root)) do
            Safe(SkinSlot, c)
            if depth > 1 then Each(c, depth - 1) end
        end
    end
    local function SlotPass()
        Each(f.MacroSelector, 5)
        Safe(SkinSlot, Get("MacroFrameSelectedMacroButton"))
        Each(Get("MacroPopupFrame"), 6)
    end
    SlotPass()
    if not f.cysSlotHook then
        f.cysSlotHook = true
        local ticker
        f:HookScript("OnShow", function()
            SlotPass()
            if ticker then ticker:Cancel() end
            ticker = C_Timer.NewTicker(0.4, SlotPass)
        end)
        f:HookScript("OnHide", function()
            if ticker then ticker:Cancel(); ticker = nil end
        end)
        if f:IsShown() then
            ticker = C_Timer.NewTicker(0.4, SlotPass)
        end
    end
end

-- The quest text is dark ink meant for parchment; recolour it for the dark panel
local QUEST_TITLES = { "QuestLogQuestTitle", "QuestLogDescriptionTitle", "QuestLogRewardTitleText" }
local QUEST_BODY = { "QuestLogObjectivesText", "QuestLogQuestDescription", "QuestLogItemChooseText",
    "QuestLogItemReceiveText", "QuestLogSpellLearnText", "QuestLogRequiredMoneyText", "QuestLogTimerText" }
local function PaintQuestText()
    for _, n in ipairs(QUEST_TITLES) do
        local fs = Get(n)
        if fs then fs:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end
    end
    for _, n in ipairs(QUEST_BODY) do
        local fs = Get(n)
        if fs then fs:SetTextColor(0.88, 0.88, 0.88) end
    end
    for i = 1, 10 do -- objectives: Blizzard colours finished ones 0.2 grey and open ones black
        local fs = Get("QuestLogObjective" .. i)
        if fs then
            local r = fs:GetTextColor()
            if type(r) == "number" and r > 0.1 and r < 0.5 then
                fs:SetTextColor(0.40, 0.85, 0.40) -- done
            else
                fs:SetTextColor(0.95, 0.95, 0.95)
            end
        end
    end
end

local function SkinQuestLog()
    local f = Get("QuestLogFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -35, 74)
    SkinClose(Get("QuestLogFrameCloseButton"), panel)
    for _, n in ipairs({ "QuestLogExpandTabLeft", "QuestLogExpandTabMiddle", "QuestLogExpandTabRight" }) do
        local t = Get(n)
        if t then t:SetAlpha(0) end
    end
    TitleText(Get("QuestLogTitleText"))
    -- the "All" (collapse everything) button keeps its +/- icon but loses the stone tab and its bracket
    for _, n in ipairs({ "QuestLogExpandButtonFrame", "QuestLogCollapseAllButton" }) do
        local fr = Get(n)
        if fr then
            local icon = fr.GetNormalTexture and fr:GetNormalTexture()
            local glow = fr.GetHighlightTexture and fr:GetHighlightTexture()
            Blank(fr, function(r) return r == icon or r == glow end)
        end
    end
    SkinTree(f, 3)
    PaintQuestText()
    if hooksecurefunc and QuestLog_UpdateQuestDetails then
        hooksecurefunc("QuestLog_UpdateQuestDetails", function() Safe(PaintQuestText) end)
    end
    f:HookScript("OnShow", function() Safe(PaintQuestText) end)
end

-- Loot window (the "Items" box): flat panel that shrinks to fit the items, plain X, full-width flat rows
-- Where the loot window opens: Blizzard's own spot, under the mouse (the game's own "loot at mouse" option),
-- or a fixed spot you move in /cui layout.
local function ApplyLootCursorSetting()
    local mode = DB().lootPos or "fixed"
    pcall(SetCVar, "lootUnderMouse", mode == "cursor" and "1" or "0")
end

-- the loot window position buttons live on the Loot page (GroupLoot.lua)
Skins.DB = DB
Skins.ApplyLootCursorSetting = ApplyLootCursorSetting

local function SetupLootPosition(f)
    ApplyLootCursorSetting()
    local holder = CreateFrame("Frame", "CysUILootAnchor", UIParent)
    holder:SetSize(190, 80)
    CUI:RegisterMovable(holder, "lootwindow", "Loot Window\n(when set to Fixed spot)", { point = "CENTER", x = 0, y = 120 })
    local busy = false
    -- Blizzard's panel system moves the window to the left edge when it opens, so we move it back
    -- right after, and again one frame later.
    local function Place()
        local mode = DB().lootPos or "fixed"
        if mode == "default" or busy then return end
        busy = true
        f:ClearAllPoints()
        if mode == "cursor" then
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local fw, fh = f:GetWidth() or 190, f:GetHeight() or 120
            x, y = x / s - 40, y / s + 30
            x = max(0, min(x, UIParent:GetWidth() - fw))
            y = max(fh, min(y, UIParent:GetHeight()))
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        else
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        end
        busy = false
    end
    f:HookScript("OnShow", function()
        Place()
        C_Timer.After(0, Place)
    end)
    hooksecurefunc(f, "SetPoint", function(_, _, relativeTo)
        if (DB().lootPos or "fixed") == "fixed" and relativeTo ~= holder then Place() end
    end)
end

local function SkinLoot()
    local f = Get("LootFrame")
    if not f then return end
    Safe(SetupLootPosition, f)
    Strip(f)
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(f.CloseButton or Get("LootFrameCloseButton"), panel)
    TitleText(f.TitleContainer and f.TitleContainer.TitleText)

    local rows = {}
    for i = 1, 4 do
        local b = Get("LootButton" .. i)
        if b then
            local nf = Get("LootButton" .. i .. "NameFrame")
            if nf then nf:SetAlpha(0) end
            -- Blizzard parks the first row 68px down to clear its stone title; with that gone, pull the rows up
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -(36 + (i - 1) * 41))
            local box = Own(CreateFrame("Frame", nil, b))
            box:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
            W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
            W.Border(box, 1, T.line, "BORDER")
            rows[i] = { b = b, box = box }
        end
    end

    -- Blizzard's own title is inset off-center and re-laid-out by the game, so hide it and draw our own
    local ownTitle = W.Text(panel, 12, T.accent, "CENTER")
    ownTitle:SetPoint("TOP", panel, "TOP", -4, -10)
    ownTitle:SetText(ITEMS or "Items")
    local function HideOrigTitle()
        local c = f.TitleContainer
        if c and c.TitleText then c.TitleText:SetAlpha(0) end
        if f.TitleText then f.TitleText:SetAlpha(0) end
        local t = Get("LootFrameTitleText"); if t then t:SetAlpha(0) end
        for _, host in ipairs({ f, c }) do
            if host and host.GetRegions then
                for _, rg in ipairs({ host:GetRegions() }) do
                    if rg.GetObjectType and rg:GetObjectType() == "FontString" and rg ~= ownTitle and rg:GetText() == (ITEMS or "Items") then
                        rg:SetAlpha(0)
                    end
                end
            end
        end
    end
    -- rows run from the icon to the panel's right edge; the panel ends just under the last item
    local function Refit()
        HideOrigTitle()
        -- the game re-parks the first row 68px down every time the window updates; pull the rows back up
        for i, r in ipairs(rows) do
            r.b:ClearAllPoints()
            r.b:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -(36 + (i - 1) * 41))
        end
        local top, lastBottom = panel:GetTop(), nil
        if not top then return end
        for _, r in ipairs(rows) do
            if r.b:IsShown() and r.b:GetTop() then
                r.box:ClearAllPoints()
                r.box:SetPoint("TOPLEFT", r.b, "TOPLEFT", -2, 2)
                r.box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, r.b:GetTop() - top + 2)
                r.box:SetHeight(r.b:GetHeight() + 4)
                lastBottom = r.b:GetBottom()
            end
        end
        local paged = (LootFrameDownButton and LootFrameDownButton:IsShown()) or (LootFrameUpButton and LootFrameUpButton:IsShown())
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        if lastBottom and not paged and f:GetBottom() then
            panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, max(lastBottom - f:GetBottom() - 14, 0))
        else
            panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        end
    end
    f:HookScript("OnShow", function()
        Safe(Refit)
        if C_Timer and C_Timer.After then C_Timer.After(0.05, function() Safe(Refit) end) end
    end)
    if hooksecurefunc and LootFrame_Update then hooksecurefunc("LootFrame_Update", function() Safe(Refit) end) end
    SkinTree(f, 2)
end

-- Quest dialog (accept / progress / turn in) and the shared QuestInfo text: dark ink -> light text
local function SetColor(fs, c)
    if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end
local LIGHT = { 0.88, 0.88, 0.88 }

local function PaintQuestDialog()
    local gold = T.accent
    local rf = Get("QuestInfoRewardsFrame")
    for _, fs in ipairs({ Get("QuestInfoTitleHeader"), Get("QuestInfoDescriptionHeader"), Get("QuestInfoObjectivesHeader"),
        rf and rf.Header, Get("QuestProgressTitleText"), Get("QuestProgressRequiredItemsText"),
        Get("CurrentQuestsText"), Get("AvailableQuestsText"), Get("QuestFrameNpcNameText") }) do
        SetColor(fs, gold)
    end
    for _, fs in ipairs({ Get("QuestInfoDescriptionText"), Get("QuestInfoObjectivesText"), Get("QuestInfoGroupSize"),
        Get("QuestInfoRewardText"), Get("QuestInfoSpellObjectiveLearnLabel"), Get("QuestInfoRequiredMoneyText"),
        rf and rf.ItemChooseText, rf and rf.ItemReceiveText, rf and rf.PlayerTitleText,
        rf and rf.XPFrame and rf.XPFrame.ReceiveText, Get("QuestProgressText"), Get("QuestProgressRequiredMoneyText"),
        Get("GreetingText") }) do
        SetColor(fs, LIGHT)
    end
    if rf and rf.spellHeaderPool then
        rf.spellHeaderPool.textR, rf.spellHeaderPool.textG, rf.spellHeaderPool.textB = LIGHT[1], LIGHT[2], LIGHT[3]
    end
    for i = 1, 10 do -- objectives: Blizzard paints finished ones 0.2 grey and open ones black
        local fs = Get("QuestInfoObjective" .. i)
        if fs then
            local r = fs:GetTextColor()
            if type(r) == "number" and r > 0.1 and r < 0.5 then SetColor(fs, { 0.40, 0.85, 0.40 }) else SetColor(fs, { 0.95, 0.95, 0.95 }) end
        end
    end
    for i = 1, 32 do -- the list of quests an NPC offers / wants back
        local b = Get("QuestTitleButton" .. i)
        local fs = b and b.GetFontString and b:GetFontString()
        if fs then SetColor(fs, LIGHT) end
    end
end

-- The quest names in gossip / quest lists carry a built-in black colour (made for the old parchment), which vanishes on a dark panel
local function LightQuestTitles()
    NORMAL_QUEST_DISPLAY = "|cffffffff%s|r"
    TRIVIAL_QUEST_DISPLAY = "|cff9d9d9d%s|r"
    IGNORED_QUEST_DISPLAY = "|cff8a8a8a%s|r"
end

local function SkinQuestDialog()
    local f = Get("QuestFrame")
    if not f then return end
    LightQuestTitles()
    Strip(f)
    for _, n in ipairs({ "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameDetailPanel", "QuestFrameGreetingPanel" }) do
        local p = Get(n)
        if p then
            Strip(p)
            p:HookScript("OnShow", function() Safe(PaintQuestDialog) end)
        end
    end
    local panel = Panel(f, 11, -12, -30, 60)
    SkinClose(Get("QuestFrameCloseButton"), panel)
    SkinTree(f, 3)
    PaintQuestDialog()
    if hooksecurefunc then
        if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function() Safe(PaintQuestDialog) end) end
        if QuestInfo_ShowObjectives then hooksecurefunc("QuestInfo_ShowObjectives", function() Safe(PaintQuestDialog) end) end
    end
end

-- NPC gossip window. Its text lives in a scrolling list built on demand, so repaint after each update.
local function SkinGossip()
    local f = Get("GossipFrame")
    if not f then return end
    LightQuestTitles()
    Strip(f)
    Blank(f.GreetingPanel)
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(f.CloseButton or Get("GossipFrameCloseButton"), panel)
    local sb = f.GreetingPanel and f.GreetingPanel.ScrollBar
    if sb then sb:SetAlpha(0.35) end
    SkinTree(f, 3)
    local function Paint()
        local box = f.GreetingPanel and f.GreetingPanel.ScrollBox
        local target = box and box.GetScrollTarget and box:GetScrollTarget()
        if not target then return end
        for _, c in ipairs(Kids(target)) do
            SetColor(c.GreetingText, LIGHT)
            local fs = c.GetFontString and c:GetFontString()
            SetColor(fs, LIGHT)
        end
    end
    local function Later() Safe(Paint); if C_Timer and C_Timer.After then C_Timer.After(0.05, function() Safe(Paint) end) end end
    f:HookScript("OnShow", Later)
    if hooksecurefunc then
        if f.Update then hooksecurefunc(f, "Update", Later) end
        if f.UpdateScrollBox then hooksecurefunc(f, "UpdateScrollBox", Later) end
    end
end

-- Friends / Who / Guild (the social window). Its tabs and sub-tabs are named FriendsFrameTabN / FriendsTabHeaderTabN.
local function SkinFriends()
    local f = Get("FriendsFrame")
    if not f then return end
    for _, name in ipairs({ "FriendsFrame", "FriendsListFrame", "IgnoreListFrame", "WhoFrame", "GuildFrame",
        "GuildPlayerStatusFrame", "GuildStatusFrame", "FriendsTabHeader", "WhoFrameListInset", "RaidFrame", "QuickJoinFrame" }) do
        Strip(Get(name))
    end
    local icon = Get("FriendsFrameIcon")
    if icon then icon:SetAlpha(0) end
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(Get("FriendsFrameCloseButton") or f.CloseButton, panel)
    TitleText(Get("FriendsFrameTitleText"))
    HookTabs()
    SkinTabs("FriendsFrameTab", 5, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)
    SkinTabs("FriendsTabHeaderTab", 3, function()
        local h = Get("FriendsTabHeader")
        return h and PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(h)
    end, { 2, -2, -2, 4 })
    SkinTree(f, 4)
    -- column headers (Who / Guild) and the action buttons that are not stone-styled
    for _, prefix in ipairs({ "WhoFrameColumnHeader", "GuildFrameColumnHeader", "GuildFrameGuildStatusColumnHeader" }) do
        for i = 1, 6 do
            local b = Get(prefix .. i)
            if b then Safe(FlatButton, b) end
        end
    end
    for _, name in ipairs({ "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton", "FriendsFrameIgnorePlayerButton",
        "FriendsFrameUnsquelchButton", "WhoFrameGroupInviteButton", "WhoFrameAddFriendButton", "WhoFrameWhoButton",
        "GuildFrameControlButton", "GuildFrameAddMemberButton", "GuildFrameGuildInformationButton" }) do
        local b = Get(name)
        if b then Safe(FlatButton, b) end
    end
    for _, name in ipairs({ "FriendsFrameFriendsScrollFrame", "FriendsFrameIgnoreScrollFrame", "WhoListScrollFrame", "GuildListScrollFrame" }) do
        local sf = Get(name)
        if sf then
            Blank(sf)
            local sb = sf.ScrollBar or Get(name .. "ScrollBar")
            if sb then Safe(SkinScrollBar, sb) end
        end
    end
    -- rows keep their text; hide the stone highlight bars
    local function Rows(self)
        for _, c in ipairs(Kids(self)) do
            if c.GetObjectType and c:GetObjectType() == "Button" and not c.cysOwn then
                local n = c:GetName() or ""
                if n:find("^FriendsFrameFriendsScrollFrameButton") or n:find("^WhoFrameButton") or n:find("^GuildFrame") then
                    local bg = c.background or Get(n .. "Background")
                    if bg and bg.SetAlpha and not bg.cysOwn then bg:SetAlpha(0) end
                end
            end
        end
    end
    f:HookScript("OnShow", function() Safe(Rows, Get("FriendsListFrame") or f) end)
end

-- BetterFriendlist ships its own dark theme (already gold-edged), so we leave its tabs, buttons and lists alone
-- and only match the window's close button. Skinning them a second time doubled every border.
local function SkinBetterFriends()
    local f = Get("BetterFriendsFrame")
    if not f then return end
    SkinClose(f.CloseButton or Get("BetterFriendsFrameCloseButton"), f)
    local ig = f.IgnoreListWindow
    if ig then SkinClose(ig.CloseButton, ig) end
    local si = Get("BetterSavedInstancesFrame")
    if si then SkinClose(si.CloseButton, si) end
end

-- Guild & Communities (the big Blizzard guild panel). Its art is spread over many keyed children, so besides the usual
-- strip we fade anything on a frame whose key names it as an inset / background / border / filigree.
local ART_PATTERNS = { "Inset", "Bg", "Background", "Border", "Streak", "Marble", "Shadow", "Filigree", "Filligree" }
local function FadeKeyedArt(w)
    if type(w) ~= "table" then return end
    for k, v in pairs(w) do
        if type(k) == "string" and type(v) == "table" and v.SetAlpha and not v.cysOwn and v ~= w then
            for _, p in ipairs(ART_PATTERNS) do
                if k:find(p) then v:SetAlpha(0) break end
            end
        end
    end
end

-- Blizzard's slim scrollbars (Back / Track / Thumb / Forward): flat gold thumb on a dark track, ^ and v arrows
function SkinMinimalScrollBar(sb)
    if not sb or sb.cysSkinned or not sb.Track then return end
    sb.cysSkinned = true
    local tr = sb.Track
    Blank(tr)
    local track = W.Texture(tr, "BACKGROUND", T.field)
    track.cysOwn = true
    track:SetAllPoints()
    local th = tr.Thumb
    if th then
        Blank(th)
        local mine = W.Texture(th, "OVERLAY", { T.brand[1], T.brand[2], T.brand[3], 0.75 })
        mine.cysOwn = true
        mine:SetAllPoints()
    end
    if sb.Back then SkinArrow(sb.Back, "^") end
    if sb.Forward then SkinArrow(sb.Forward, "v") end
    -- the ornate end caps and backplate of the "trim" style bar (macro list and others)
    for _, k in ipairs({ "Background", "Backplate" }) do
        local part = sb[k]
        if part and part.SetAlpha then part:SetAlpha(0) end
    end
end

local function SkinDropdown(dd)
    if not dd or dd.cysSkinned then return end
    dd.cysSkinned = true
    Blank(dd, function(r) return r == dd.Arrow end)
    Box(dd, T.border, 0, 0)
end

local function SkinCommunities()
    local f = Get("CommunitiesFrame")
    if not f then return end
    Strip(f)
    FadeKeyedArt(f)
    if f.PortraitOverlay then f.PortraitOverlay:SetAlpha(0) end
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(f.CloseButton or Get("CommunitiesFrameCloseButton"), panel)
    local tc = f.TitleContainer
    TitleText(tc and tc.TitleText or Get("CommunitiesFrameTitleText"))
    local mm = f.MaximizeMinimizeFrame
    if mm then
        SkinArrow(mm.MaximizeButton, "+")
        SkinArrow(mm.MinimizeButton, "-")
    end

    local tabs = {}
    for _, k in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        if f[k] then tabs[#tabs + 1] = f[k] end
    end

    local function Pass()
        for _, k in ipairs({ "Chat", "MemberList", "CommunitiesList", "ApplicantList", "InvitationFrame", "ClubFinderInvitationFrame",
            "GuildBenefitsFrame", "GuildDetailsFrame", "GuildFinderFrame", "CommunityFinderFrame", "TicketFrame" }) do
            local w = f[k]
            if w then
                Safe(Strip, w)
                Safe(FadeKeyedArt, w)
                if w.ScrollBar then Safe(SkinMinimalScrollBar, w.ScrollBar) end
            end
        end
        for _, k in ipairs({ "MemberList", "CommunitiesList" }) do
            -- keep the scrolling rows inside the new border instead of running under it
            local w = f[k]
            local sbx = w and w.ScrollBox
            if sbx and not sbx.cysInset then
                sbx.cysInset = true
                sbx:ClearAllPoints()
                sbx:SetPoint("TOPLEFT", w, "TOPLEFT", 2, -3)
                sbx:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 4)
            end
        end
        for _, k in ipairs({ "Chat", "MemberList" }) do
            local w = f[k]
            if w and not w.cysFieldBox then
                w.cysFieldBox = true
                Safe(Box, w, T.border, 0, 0)
            end
        end
        local cl = f.CommunitiesList
        if cl and not cl.cysFieldBox then
            cl.cysFieldBox = true
            local ok, b = pcall(Box, cl, T.border, 0, 0)
            if ok then cl.cysListBox = b end
        end
        local eb = f.ChatEditBox
        if eb then
            Safe(Strip, eb)
            if not eb.cysFieldBox then eb.cysFieldBox = true; Safe(Box, eb, T.border, 0, 0) end
        end
        for _, k in ipairs({ "StreamDropdown", "GuildMemberListDropdown", "CommunityMemberListDropdown", "CommunitiesListDropdown" }) do
            Safe(SkinDropdown, f[k])
        end
        -- Roster tab: column headers and the "Show Offline Members" box
        local ml = f.MemberList
        if ml then
            local cd = ml.ColumnDisplay
            if cd then
                Safe(Strip, cd)
                Safe(FadeKeyedArt, cd)
                for _, b in ipairs(Kids(cd)) do
                    if b.GetObjectType and b:GetObjectType() == "Button" then Safe(FlatButton, b) end
                end
            end
            local so = ml.ShowOfflineButton
            if so and not so.cysCheck then
                so.cysCheck = true
                local checked = so.GetCheckedTexture and so:GetCheckedTexture()
                for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
                    local t = so[getter] and so[getter](so)
                    if t and t ~= checked then t:SetAlpha(0) end
                end
                local box = Own(CreateFrame("Frame", nil, so))
                box:SetSize(16, 16)
                box:SetPoint("CENTER", so, "CENTER", 0, 0)
                box:SetFrameLevel(max(so:GetFrameLevel() - 1, 0))
                W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
                W.Border(box, 1, T.border, "BORDER")
            end
        end
        -- Info tab: message of the day, guild information and news (the brown parchment lives on these children)
        local d = f.GuildDetailsFrame
        if d then
            for _, k in ipairs({ "Info", "News" }) do
                local w = d[k]
                if w then Safe(Strip, w); Safe(FadeKeyedArt, w) end
            end
            Walk(d, function(c)
                if c.Track then
                    SkinMinimalScrollBar(c)
                elseif c.GetObjectType and (c:GetObjectType() == "Frame" or c:GetObjectType() == "ScrollFrame") then
                    Strip(c)
                    FadeKeyedArt(c)
                end
            end, 4)
            -- the stock layout is built around fixed pixel sizes for the old parchment art, so lay it out to fill the panel
            local info = d.Info
            if info then
                local function FieldBox(w, r)
                    if w.cysFieldBox then return end
                    local box = Own(CreateFrame("Frame", nil, w))
                    box:SetPoint("TOPLEFT", -4, 4)
                    box:SetPoint("BOTTOMRIGHT", r or 4, -4)
                    box:SetFrameLevel(max(w:GetFrameLevel() - 1, 0))
                    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
                    W.Border(box, 1, T.border, "BORDER")
                    w.cysFieldBox = box
                end
                local m, det = info.MOTDScrollFrame, info.DetailsFrame
                if m then FieldBox(m, 26) end
                if det then FieldBox(det, 26) end
                info.cysLayout = function()
                    if not (m and det and info:GetHeight() > 100) then return end
                    local h3 = _G[(info:GetName() or "") .. "Header3"]
                    local mh = max(60, floor((info:GetHeight() - 90) * 0.4))
                    m:ClearAllPoints()
                    m:SetPoint("TOPLEFT", info.Header1, "BOTTOMLEFT", 14, -10)
                    m:SetSize(222, mh)
                    if m.MOTD then m.MOTD:SetWidth(218) end
                    if h3 then
                        h3:ClearAllPoints()
                        h3:SetPoint("TOPLEFT", m, "BOTTOMLEFT", -14, -16)
                    end
                    det:ClearAllPoints()
                    det:SetPoint("TOPLEFT", h3 or m, "BOTTOMLEFT", h3 and 14 or 0, -10)
                    det:SetPoint("BOTTOMRIGHT", info, "BOTTOMLEFT", 240, 14)
                    local c = det:GetScrollChild()
                    if c then
                        c:SetWidth(218)
                        if c.Details then c.Details:SetWidth(218) end
                    end
                end
                info.cysLayout()
            end
            if d.News and not d.News.cysFieldBox then
                d.News.cysFieldBox = true
                local box = Own(CreateFrame("Frame", nil, d.News))
                box:SetPoint("TOPLEFT", 4, 0)
                box:SetPoint("BOTTOMRIGHT", -2, 0)
                box:SetFrameLevel(max(d.News:GetFrameLevel() - 1, 0))
                W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
                W.Border(box, 1, T.border, "BORDER")
            end
        end
        if f.InviteButton then f.InviteButton:SetSize(96, 20) end -- the stock one is wider than it needs to be
        for _, t in ipairs(tabs) do
            if not t.cysBox then
                local glow = t.GetHighlightTexture and t:GetHighlightTexture()
                Blank(t, function(r) return r == t.Icon or r == t.IconOverlay or r == glow end)
                local ch = t.GetCheckedTexture and t:GetCheckedTexture()
                if ch then ch:SetAlpha(0) end
                t.cysBox = Box(t, T.border, -2, -2)
                t.cysBox:SetFrameLevel(max(t:GetFrameLevel() - 1, 0))
            end
        end
        SkinTree(f, 5)
    end

    -- the community list and its rows are rebuilt by Blizzard as you click around, so poll while the window is open
    local function PaintLive()
        local list = f.CommunitiesList
        local box = list and list.ScrollBox
        local target = box and box.GetScrollTarget and box:GetScrollTarget()
        if target then
            for _, c in ipairs(Kids(target)) do
                if not c.cysOwn then
                    if not c.cysEntry then
                        c.cysEntry = true
                        if c.Background then c.Background:SetAlpha(0) end
                        if c.Selection then c.Selection:SetAlpha(0) end
                        c.cysEntryBox = Box(c, T.line, 7, 1)
                        c.cysEntryBox:SetFrameLevel(max(c:GetFrameLevel() - 1, 0))
                    end
                    local sel = c.Selection and c.Selection:IsShown()
                    W.SetBorder(c.cysEntryBox.edges, sel and T.accent or T.line)
                end
            end
        end
        -- one gold rule from the community list's top edge across the whole window, so the left list and the panel beside it read as one frame
        local list2 = f.CommunitiesList
        if list2 and list2:GetLeft() and f:GetRight() then
            if not f.cysTopRule then
                f.cysTopRule = Own(CreateFrame("Frame", nil, f))
                f.cysTopRule:SetHeight(1)
                W.Texture(f.cysTopRule, "BORDER", T.border):SetAllPoints()
            end
            -- the list's edge and the rule share the window border's line instead of sitting a couple of pixels inside it
            local dx = min(0, f:GetLeft() - list2:GetLeft())
            f.cysTopRule:ClearAllPoints()
            f.cysTopRule:SetPoint("TOPLEFT", list2, "TOPLEFT", dx, 0)
            f.cysTopRule:SetWidth(max(1, f:GetRight() - f:GetLeft() - 1))
            local lb = list2.cysListBox
            if lb then
                lb:ClearAllPoints()
                lb:SetPoint("TOPLEFT", list2, "TOPLEFT", dx, 0)
                lb:SetPoint("BOTTOMRIGHT", list2, "BOTTOMRIGHT", 0, 0)
            end
        end
        local d = f.GuildDetailsFrame
        if d and d:IsVisible() then
            if d.Info and d.Info.cysLayout then d.Info.cysLayout() end
            local nb = d.News and d.News.ScrollBox
            if nb and nb.ForEachFrame then
                nb:ForEachFrame(function(b) if b.header then b.header:SetAlpha(0) end end) -- the brown date bars
            end
        end
        for _, t in ipairs(tabs) do
            if t.cysBox then
                local on = t.GetChecked and t:GetChecked()
                W.SetBorder(t.cysBox.edges, on and T.accent or T.border)
            end
        end
    end

    Pass()
    local acc = 0
    local poll = CreateFrame("Frame", nil, f)
    poll:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 0.25 then acc = 0; Safe(PaintLive) end
    end)
    f:HookScript("OnShow", function() Safe(Pass) end)
end

-- World map: Blizzard's brown stone border becomes a flat dark panel with a gold edge, like the other windows.
-- (CysMap also frames this window; both draw at the same size so they just overlap.)
-- World map position and size (this replaces the separate CysMap addon)
local function MapAddonLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn("CysMap")
end

local function MapDB()
    CysUIDB = CysUIDB or {}
    if not CysUIDB.map then
        local m = {}
        if type(CysMapDB) == "table" then m.point, m.x, m.y, m.scale = CysMapDB.point, CysMapDB.x, CysMapDB.y, CysMapDB.scale end
        CysUIDB.map = m
    end
    return CysUIDB.map
end

local function PlaceMap(map)
    local db = MapDB()
    map:SetScale(db.scale or 0.75)
    map:ClearAllPoints()
    if db.point and db.x and db.y then
        map:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    else
        map:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function SkinWorldMap()
    local f = Get("WorldMapFrame")
    if not f then return end
    local panel = Panel(f, -4, 4, 4, -4)
    -- Movable map with a drag handle outside the top-left corner, remembered position and a flicker-free show
    if not f.cysMove and not MapAddonLoaded() then
        f.cysMove = true
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        local mover = Own(CreateFrame("Button", nil, f))
        mover:SetSize(16, 24)
        mover:SetPoint("TOPRIGHT", panel, "TOPLEFT", -2, 0)
        mover:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        local tex = W.Texture(mover, "OVERLAY", T.border)
        tex:SetAllPoints()
        mover:SetScript("OnMouseDown", function() f:StartMoving() end)
        mover:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            local point, _, _, x, y = f:GetPoint()
            local db = MapDB()
            db.point, db.x, db.y = point, x, y
        end)
        mover:SetScript("OnEnter", function() tex:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 1) end)
        mover:SetScript("OnLeave", function() tex:SetColorTexture(T.border[1], T.border[2], T.border[3], 1) end)
        f:HookScript("OnShow", function(self)
            self:SetAlpha(0)
            PlaceMap(self)
            C_Timer.After(0.02, function() PlaceMap(self); self:SetAlpha(1) end)
        end)
        PlaceMap(f)
        SLASH_CYSUIMAP1 = "/cysmap"
        SLASH_CYSUIMAP2 = "/cuimap"
        SlashCmdList["CYSUIMAP"] = function(msg)
            local db = MapDB()
            local n = tonumber(msg and msg:match("scale%s+([%d%.]+)"))
            if n then
                db.scale = math.max(0.4, math.min(1.2, n))
                print("|cFFFFD100Cys's UI:|r Map scale set to " .. db.scale)
            else
                db.point, db.x, db.y, db.scale = nil, nil, nil, 0.75
                print("|cFFFFD100Cys's UI:|r Map position and scale reset. Use /cysmap scale 0.8 to resize it.")
            end
            PlaceMap(f)
        end
    end
    -- Blizzard shows/hides these as you switch between the full and small map, so fade them rather than hide them
    for _, k in ipairs({ "BorderFrame", "MiniBorderFrame", "BlackoutFrame" }) do
        if f[k] then f[k]:SetAlpha(0) end
    end
    SkinDropdown(f.ContinentDropdown)
    SkinDropdown(f.ZoneDropdown)
    SkinDropdown(f.MinimapDropdown)
    FlatButton(Get("WorldMapZoomOutButton"))
    local close = Get("WorldMapFrameCloseButton")
    SkinClose(close, panel)
    local mm = f.MaximizeMinimizeFrame
    if mm then
        SkinArrow(mm.MaximizeButton, "+")
        SkinArrow(mm.MinimizeButton, "-")
    end
    local sc = f.ScrollContainer
    if sc and not sc.cysEdge then
        sc.cysEdge = true
        local edge = Own(CreateFrame("Frame", nil, f))
        edge:SetPoint("TOPLEFT", sc, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 1, -1)
        edge:SetFrameLevel(sc:GetFrameLevel())
        W.Border(edge, 1, T.border, "BORDER")
    end
    -- The canvas turns the mouse position into a map position without allowing for the map's own scale (it only works at 100%),
    -- so with the map scaled down (CysMap uses 75%) the hover highlight and coordinates land on the wrong zone. Allow for it.
    if sc and not sc.cysCursor then
        sc.cysCursor = true
        sc.GetCursorPosition = function(self)
            local x, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            if scale and scale > 0 then return x / scale, y / scale end
            return x, y
        end
    end
    -- Coordinates strip along the bottom of the map: where you are and where the mouse is
    if sc and not f.cysCoords then
        local bar = Own(CreateFrame("Frame", nil, f))
        bar:SetFrameLevel(sc:GetFrameLevel() + 20)
        bar:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
        bar:SetHeight(18)
        W.Texture(bar, "BACKGROUND", { 0, 0, 0, 0.55 }):SetAllPoints()
        local txt = bar:CreateFontString(nil, "OVERLAY")
        txt:SetFont(STANDARD_TEXT_FONT, 11, "")
        txt:SetPoint("CENTER")
        txt:SetTextColor(T.text[1], T.text[2], T.text[3])
        f.cysCoords = bar
        local acc = 0
        bar:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.05 then return end
            acc = 0
            local pl, cu = "--", "--"
            local mapID = f.GetMapID and f:GetMapID()
            if mapID and C_Map and C_Map.GetPlayerMapPosition then
                local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                if pos then pl = string.format("%.1f, %.1f", pos.x * 100, pos.y * 100) end
            end
            if sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
                local x, y = sc:GetNormalizedCursorPosition()
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then cu = string.format("%.1f, %.1f", x * 100, y * 100) end
            end
            txt:SetText("Player: " .. pl .. "     Cursor: " .. cu)
        end)
    end
    -- Blizzard re-anchors the close button every time the map changes size, so keep ours in the corner
    local function Place()
        -- hug the map canvas (the frame itself can be the whole screen); leave room on top for the dropdowns when they show
        if sc then
            local top = (f.ContinentDropdown and f.ContinentDropdown:IsShown()) and 54 or 28
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", sc, "TOPLEFT", -6, top)
            panel:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 6, -6)
        end
        if close then
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
        end
        if mm and close then
            mm:ClearAllPoints()
            mm:SetPoint("RIGHT", close, "LEFT", -2, 0)
        end
        for _, k in ipairs({ "BorderFrame", "MiniBorderFrame", "BlackoutFrame" }) do
            if f[k] and f[k]:GetAlpha() > 0 then f[k]:SetAlpha(0) end
        end
    end
    if not f.cysPoll then
        local acc = 0
        f.cysPoll = CreateFrame("Frame", nil, f)
        f.cysPoll:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc > 0.25 then acc = 0; Safe(Place) end
        end)
        f:HookScript("OnShow", function() Safe(Place) end)
    end
    Place()
end

-- Vendor window: dark panel, framed item cells, flat repair / page buttons and tabs
local function SkinMerchant()
    local f = Get("MerchantFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(f.CloseButton or Get("MerchantFrameCloseButton"), panel)
    TitleText(Get("MerchantNameText"))
    HookTabs()
    SkinTabs("MerchantFrameTab", 2, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)

    local cells = {}
    for i = 1, 12 do cells[#cells + 1] = Get("MerchantItem" .. i) end
    cells[#cells + 1] = Get("MerchantBuyBackItem")
    for _, cell in ipairs(cells) do
        if not cell.cysCell then
            cell.cysCell = true
            Blank(cell) -- the empty-slot picture and the name plate
            -- the stock layout hangs the price below the cell and presses the icon into the corner; pull both inside the box
            local cn = cell:GetName()
            local buyback = cn == "MerchantBuyBackItem"
            if buyback then cell:SetHeight(44) end
            local name = cell.Name or (cn and _G[cn .. "Name"])
            local plate = cn and _G[cn .. "NameFrame"]
            if name then
                name:ClearAllPoints()
                name:SetPoint("TOPLEFT", cell, "TOPLEFT", 46, -5)
                name:SetJustifyV("TOP")
            end
            if plate then -- the (hidden) name plate is what the price is anchored to
                plate:ClearAllPoints()
                plate:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", buyback and 46 or 44, buyback and -21 or -27)
            end
            if cell.ItemButton then
                cell.ItemButton:ClearAllPoints()
                cell.ItemButton:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -4)
            end
            local b = Box(cell, T.line, 0, 0)
            b:SetFrameLevel(max(cell:GetFrameLevel() - 1, 0))
            cell.cysCellBox = b
        end
    end

    -- the money strips along the bottom
    for _, n in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do Strip(Get(n)) end
    for _, n in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do
        local w = Get(n)
        if w and not w.cysBoxed then
            w.cysBoxed = true
            Strip(w)
            Box(w, T.border, 0, 0)
        end
    end

    -- repair buttons: keep the icon, add a gold-edged square behind it
    for _, n in ipairs({ "MerchantRepairAllButton", "MerchantRepairItemButton", "MerchantGuildBankRepairButton" }) do
        local b = Get(n)
        if b and not b.cysBox then
            b.cysBox = Box(b, T.border, 0, 0)
            b.cysBox:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
            b:HookScript("OnEnter", function() W.SetBorder(b.cysBox.edges, T.accent) end)
            b:HookScript("OnLeave", function() W.SetBorder(b.cysBox.edges, T.border) end)
        end
    end

    SkinArrow(Get("MerchantPrevPageButton"), "<")
    SkinArrow(Get("MerchantNextPageButton"), ">")

    -- Blizzard re-textures the item buttons and enables / disables the page buttons on every refresh
    local function Paint()
        for i = 1, 12 do
            local ib = Get("MerchantItem" .. i .. "ItemButton")
            local nt = ib and ib.GetNormalTexture and ib:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end
        local bb = Get("MerchantBuyBackItemItemButton")
        local nt = bb and bb.GetNormalTexture and bb:GetNormalTexture()
        if nt then nt:SetAlpha(0) end
        -- with nothing sold yet the buyback cell would be an empty box floating above the money strip
        local have = (GetNumBuybackItems and GetNumBuybackItems() or 0) > 0
        local bcell = Get("MerchantBuyBackItem")
        if bcell and bcell.cysCellBox then bcell.cysCellBox:SetShown(have) end
        if bb then bb:SetAlpha(have and 1 or 0) end
        for _, n in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton" }) do
            local b = Get(n)
            if b then b:SetAlpha(b:IsEnabled() and 1 or 0.35) end
        end
    end
    if hooksecurefunc and MerchantFrame_Update and not f.cysHooked then
        f.cysHooked = true
        hooksecurefunc("MerchantFrame_Update", function() Safe(Paint) end)
    end
    f:HookScript("OnShow", function() Safe(Paint) end)
    Paint()
end

-- Mailbox: inbox rows, the send tab and the open-letter window
local function SkinMail()
    local f = Get("MailFrame")
    if not f then return end
    local function Edit(eb, ex, ey)
        if not eb or eb.cysBoxed then return end
        eb.cysBoxed = true
        Blank(eb)
        local b = Box(eb, T.line, ex or -3, ey or -2)
        b:SetFrameLevel(max(eb:GetFrameLevel() - 1, 0))
    end
    local function ItemBox(b)
        if not b or b.cysItemBox then return end
        b.cysItemBox = Box(b, T.line, 0, 0)
        b.cysItemBox:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
        b:HookScript("OnEnter", function() W.SetBorder(b.cysItemBox.edges, T.accent) end)
        b:HookScript("OnLeave", function() W.SetBorder(b.cysItemBox.edges, T.line) end)
    end
    -- a gold-tinted title band with a rule under it, so the window isn't one flat slab
    local function Band(p)
        if p.cysBand then return end
        local band = W.Texture(p, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.10 }, 1)
        band:SetPoint("TOPLEFT", 1, -1)
        band:SetPoint("TOPRIGHT", -1, -1)
        band:SetHeight(30)
        local rule = W.Texture(p, "BACKGROUND", T.border, 2)
        rule:SetPoint("TOPLEFT", 1, -31)
        rule:SetPoint("TOPRIGHT", -1, -31)
        rule:SetHeight(1)
        p.cysBand = band
    end
    -- a lighter fill inside a boxed area, so typing / slot areas read as such
    local function Lift(box)
        if not box or box.cysLift then return end
        box.cysLift = W.Texture(box, "BACKGROUND", T.card, 1)
        box.cysLift:SetPoint("TOPLEFT", 1, -1)
        box.cysLift:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    -- the parchment letter text is dark brown: make it readable on the dark panel
    for _, n in ipairs({ "MailTextFontNormal", "InvoiceTextFontNormal", "InvoiceTextFontSmall" }) do
        local fo = Get(n)
        if fo and fo.SetTextColor then fo:SetTextColor(T.text[1], T.text[2], T.text[3]) end
    end

    ---------------------------------------------------------------- main window
    Strip(f)
    local panel = Panel(f, 0, 0, 0, 0)
    Band(panel)
    SkinClose(f.CloseButton or Get("MailFrameCloseButton"), panel)
    -- Blizzard centres these on the whole 384-wide art, which sits right of the visible window; centre them in our title band
    for _, n in ipairs({ "InboxTitleText", "SendMailTitleText" }) do
        local fs = Get(n)
        TitleText(fs)
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", panel, "TOP", 0, -15)
        end
    end
    HookTabs()
    SkinTabs("MailFrameTab", 2, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)

    ---------------------------------------------------------------- inbox
    local inbox = Get("InboxFrame")
    if inbox then
        Blank(inbox)
        Strip(Get("InboxTooMuchMail"))
    end
    for i = 1, 7 do
        local row = Get("MailItem" .. i)
        if row and not row.cysRow then
            row.cysRow = true
            Blank(row) -- the parchment row art
            local b = Box(row, T.line, 0, 1)
            b:SetFrameLevel(max(row:GetFrameLevel() - 1, 0))
            local btn = row.Button or Get("MailItem" .. i .. "Button")
            if btn then
                local slot = Get("MailItem" .. i .. "ButtonSlot")
                if slot then slot:SetAlpha(0) end
                ItemBox(btn)
            end
        end
    end
    SkinArrow(Get("InboxPrevPageButton"), "<")
    SkinArrow(Get("InboxNextPageButton"), ">")
    FlatButton(Get("OpenAllMail"))

    ---------------------------------------------------------------- send tab
    local send = Get("SendMailFrame")
    if send then
        local coin = Get("SendMailErrorCoin")
        Blank(send, function(r) return r == coin end)
        Edit(Get("SendMailNameEditBox"))
        Edit(Get("SendMailSubjectEditBox"))
        for _, n in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do Edit(Get(n), -2, -1) end
        local body = Get("MailEditBox")
        if body and not body.cysBoxed then
            body.cysBoxed = true
            Blank(body)
            for _, n in ipairs({ "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight" }) do
                local t = Get(n)
                if t then t:SetAlpha(0) end
            end
            local b = Box(body, T.line, -6, -6)
            b:SetFrameLevel(max(body:GetFrameLevel() - 1, 0))
            Lift(b)
            local eb = body.GetEditBox and body:GetEditBox()
            if eb and eb.SetTextColor then eb:SetTextColor(T.text[1], T.text[2], T.text[3]) end
            if body.SetTextColor then pcall(body.SetTextColor, body, T.text[1], T.text[2], T.text[3]) end
        end
        local sb = Get("MailEditBoxScrollBar")
        if sb then
            if sb.Track then SkinMinimalScrollBar(sb) elseif sb.GetObjectType and sb:GetObjectType() == "Slider" then SkinScrollBar(sb) end
        end
        for i = 1, 16 do
            local a = Get("SendMailAttachment" .. i)
            if a and not a.cysItemBox then
                Blank(a, function(r) return r == a.IconBorder or r == a.IconOverlay end)
                ItemBox(a)
                Lift(a.cysItemBox)
            end
        end
        for _, n in ipairs({ "SendMailMoneyInset" }) do Strip(Get(n)) end
        local bg = Get("SendMailMoneyBg")
        if bg and not bg.cysBoxed then bg.cysBoxed = true; Strip(bg); Box(bg, T.border, 0, 0) end
        FlatButton(Get("SendMailMailButton"))
        FlatButton(Get("SendMailCancelButton"))
    end

    -- thin gold rules splitting the send tab into recipient / message / attachments / money
    if send and not send.cysRules then
        send.cysRules = true
        local rules = {}
        for i = 1, 2 do
            local r = W.Texture(send, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.35 })
            r:SetHeight(1)
            rules[i] = r
        end
        local function Place()
            local a1, mb = Get("SendMailAttachment1"), Get("SendMailMoneyButton")
            local l, w = panel:GetLeft(), panel:GetWidth()
            for i, anchor in ipairs({ a1, mb }) do
                local r = rules[i]
                if anchor and l and anchor:GetLeft() and w then
                    r:ClearAllPoints()
                    r:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", l - anchor:GetLeft() + 10, i == 1 and 8 or 6)
                    r:SetWidth(w - 20)
                    r:Show()
                else
                    r:Hide()
                end
            end
        end
        send:HookScript("OnShow", function() C_Timer.After(0, function() Safe(Place) end) end)
    end

    ---------------------------------------------------------------- Postal (if installed) adds its own checkboxes, buttons and menus
    local function SkinPostal()
        for i = 1, 7 do
            local cb = Get("PostalInboxCB" .. i)
            if cb and not cb.cysSkinned then
                cb.cysSkinned = true
                for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                    local t = cb[getter] and cb[getter](cb)
                    if t then t:SetAlpha(0) end
                end
                local box = Box(cb, T.line, 4, 4)
                box:SetFrameLevel(max(cb:GetFrameLevel() - 1, 0))
                cb:HookScript("OnEnter", function() W.SetBorder(box.edges, T.accent) end)
                cb:HookScript("OnLeave", function() W.SetBorder(box.edges, T.line) end)
                local ck = cb.GetCheckedTexture and cb:GetCheckedTexture()
                if ck then ck:SetVertexColor(T.accent[1], T.accent[2], T.accent[3]) end
            end
        end
        FlatButton(Get("PostalSelectOpenButton"))
        FlatButton(Get("PostalSelectReturnButton"))
        SkinArrow(Get("Postal_ModuleMenuButton"), "v")
        SkinArrow(Get("Postal_OpenAllMenuButton"), "v")
    end
    f:HookScript("OnShow", function() Safe(SkinPostal) end)
    C_Timer.After(2, function() Safe(SkinPostal) end)
    Safe(SkinPostal)

    ---------------------------------------------------------------- open letter
    local om = Get("OpenMailFrame")
    if om then
        Strip(om)
        local op = Panel(om, 0, 0, 0, 0)
        Band(op)
        SkinClose(om.CloseButton or Get("OpenMailFrameCloseButton"), op)
        TitleText(Get("OpenMailTitleText"))
        local ot = Get("OpenMailTitleText")
        if ot then
            ot:ClearAllPoints()
            ot:SetPoint("CENTER", op, "TOP", 0, -15)
        end
        local sf = Get("OpenMailScrollFrame")
        if sf then
            Blank(sf)
            local sbar = Get("OpenMailScrollFrameScrollBar")
            if sbar then SkinScrollBar(sbar) end
            for _, n in ipairs({ "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight" }) do
                local t = Get(n)
                if t then t:SetAlpha(0) end
            end
            local b = Box(sf, T.line, -4, -4)
            b:SetFrameLevel(max(sf:GetFrameLevel() - 1, 0))
        end
        for _, n in ipairs({ "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton", "OpenMailReportSpamButton" }) do
            FlatButton(Get(n))
        end
        local items = { Get("OpenMailLetterButton"), Get("OpenMailMoneyButton") }
        for i = 1, 16 do items[#items + 1] = Get("OpenMailAttachmentButton" .. i) end
        for _, b in ipairs(items) do ItemBox(b) end
        -- Blizzard re-textures these when the letter changes; keep the stock frame art off them
        local function Paint()
            for _, b in ipairs(items) do
                local nt = b.GetNormalTexture and b:GetNormalTexture()
                if nt then nt:SetAlpha(0) end
            end
            local body = Get("OpenMailBodyText")
            if body and body.SetTextColor then
                for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do pcall(body.SetTextColor, body, tag, T.text[1], T.text[2], T.text[3]) end
            end
        end
        if hooksecurefunc and OpenMail_Update and not om.cysHooked then
            om.cysHooked = true
            hooksecurefunc("OpenMail_Update", function() Safe(Paint) end)
        end
        om:HookScript("OnShow", function() Safe(Paint) end)
        Paint()
    end
end

-- Class trainer: dark panel, flat buttons and scrollbars, framed skill icon
local function SkinTrainer()
    local f = Get("ClassTrainerFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("ClassTrainerFrameCloseButton"), panel)
    TitleText(Get("ClassTrainerNameText"))
    Strip(Get("ClassTrainerExpandButtonFrame"))
    SkinTree(f, 4)
    SkinDropdown(f.FilterDropdown)
    local icon = Get("ClassTrainerSkillIcon")
    if icon and not icon.cysItemBox then
        Blank(icon) -- the empty-slot picture; the spell icon is the button's own texture
        icon.cysItemBox = Box(icon, T.line, 0, 0)
        icon.cysItemBox:SetFrameLevel(max(icon:GetFrameLevel() - 1, 0))
    end
end

-- Profession (trade skill) window: Alchemy, Blacksmithing, Cooking...
local function SkinTradeSkill()
    local f = Get("TradeSkillFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("TradeSkillFrameCloseButton"), panel)
    TitleText(Get("TradeSkillFrameTitleText"))
    for _, n in ipairs({ "TradeSkillRankFrameBorder", "TradeSkillExpandButtonFrame", "TradeSkillListScrollFrame",
        "TradeSkillDetailScrollFrame", "TradeSkillDetailScrollChildFrame" }) do
        local x = Get(n)
        if x then Blank(x) end
    end
    -- skill rank bar: flat, in the same gold-brown as the Skills tab
    local rank = Get("TradeSkillRankFrame")
    if rank and not rank.cysSkinned then
        rank.cysSkinned = true
        Box(rank, T.line, 0, 0)
        rank:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        rank:SetStatusBarColor(T.brand[1] * 0.55, T.brand[2] * 0.55, T.brand[3] * 0.55)
        if hooksecurefunc then
            hooksecurefunc(rank, "SetStatusBarColor", function(self, r, g, b)
                if self.cysFix then return end
                self.cysFix = true
                self:SetStatusBarColor(T.brand[1] * 0.55, T.brand[2] * 0.55, T.brand[3] * 0.55)
                self.cysFix = false
            end)
        end
    end
    SkinTree(f, 4)
    SkinDropdown(f.InvSlotDropdown)
    SkinDropdown(f.SubClassDropdown)
    SkinDropdown(f.FilterDropdown)
    -- the selected recipe's icon and reagent icons sit in small hairline boxes
    local function IconBox(owner, target)
        if not owner or owner.cysIconBox then return end
        owner.cysIconBox = true
        local box = Own(CreateFrame("Frame", nil, owner))
        box:SetAllPoints(target or owner)
        box:SetFrameLevel(max(owner:GetFrameLevel() - 1, 0))
        W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
        box.edges = W.Border(box, 1, T.line, "BORDER")
    end
    local skillIcon = Get("TradeSkillSkillIcon")
    if skillIcon then
        local nt = skillIcon.GetNormalTexture and skillIcon:GetNormalTexture()
        if nt then nt:SetAlpha(0) end
        IconBox(skillIcon)
    end
    for i = 1, 8 do
        local r = Get("TradeSkillReagent" .. i)
        if r then
            if r.NameFrame then r.NameFrame:SetAlpha(0) end
            local nf = Get("TradeSkillReagent" .. i .. "NameFrame")
            if nf then nf:SetAlpha(0) end
            local icon = r.Icon or Get("TradeSkillReagent" .. i .. "IconTexture")
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            IconBox(r, icon)
        end
    end
    local hl = Get("TradeSkillHighlight")
    if hl and hl.SetColorTexture then hl:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.25) end
    local input = Get("TradeSkillInputBox")
    if input and not input.cysSkinned then
        input.cysSkinned = true
        Blank(input)
        Box(input, T.line, -2, 0)
    end
end

-- Fit a panel to a window's real contents: edges taken from the named frames, plus padding
local function FitPanel(panel, f, left, right, top, bottom, pad)
    local function Fit()
        local L, R, TT, B = left and left:GetLeft(), right and right:GetRight(), top and top:GetTop(), bottom and bottom:GetBottom()
        local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (L and R and TT and B and fl and fr and ft and fb) then return end
        pad = pad or 12
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", f, "TOPLEFT", L - pad - fl, TT + pad - ft)
        panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", R + pad - fr, B - pad - fb)
    end
    f:HookScript("OnShow", function() Fit(); if C_Timer and C_Timer.After then C_Timer.After(0.05, Fit) end end)
    Fit()
end

-- Hairline box behind an icon (used for item and reagent pictures)
local function IconBoxFor(owner, target, color)
    if not owner or owner.cysIconBox then return end
    owner.cysIconBox = Own(CreateFrame("Frame", nil, owner))
    local box = owner.cysIconBox
    box:SetAllPoints(target or owner)
    box:SetFrameLevel(max(owner:GetFrameLevel() - 1, 0))
    W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
    box.edges = W.Border(box, 1, color or T.line, "BORDER")
end

-- Enchanting (and other "craft" windows): same layout as the profession window
local function SkinCraft()
    local f = Get("CraftFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("CraftFrameCloseButton"), panel)
    TitleText(Get("CraftFrameTitleText"))
    for _, n in ipairs({ "CraftRankFrameBorder", "CraftExpandButtonFrame", "CraftListScrollFrame",
        "CraftDetailScrollFrame", "CraftDetailScrollChildFrame" }) do
        local x = Get(n)
        if x then Blank(x) end
    end
    local rank = Get("CraftRankFrame")
    if rank and not rank.cysSkinned then
        rank.cysSkinned = true
        Box(rank, T.line, 0, 0)
        rank:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        rank:SetStatusBarColor(T.brand[1] * 0.55, T.brand[2] * 0.55, T.brand[3] * 0.55)
        if hooksecurefunc then
            hooksecurefunc(rank, "SetStatusBarColor", function(self)
                if self.cysFix then return end
                self.cysFix = true
                self:SetStatusBarColor(T.brand[1] * 0.55, T.brand[2] * 0.55, T.brand[3] * 0.55)
                self.cysFix = false
            end)
        end
    end
    SkinTree(f, 4)
    SkinDropdown(f.Dropdown)
    local icon = Get("CraftIcon")
    if icon then
        local nt = icon.GetNormalTexture and icon:GetNormalTexture()
        if nt then nt:SetAlpha(0) end
        IconBoxFor(icon)
    end
    for i = 1, 8 do
        local r = Get("CraftReagent" .. i)
        if r then
            if r.NameFrame then r.NameFrame:SetAlpha(0) end
            local nf = Get("CraftReagent" .. i .. "NameFrame")
            if nf then nf:SetAlpha(0) end
            local ic = r.Icon or Get("CraftReagent" .. i .. "IconTexture")
            if ic and ic.SetTexCoord then ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            IconBoxFor(r, ic)
        end
    end
    local hl = Get("CraftHighlight")
    if hl and hl.SetColorTexture then hl:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.25) end
    local req = Get("CraftRequirements")
    if req and req.SetTextColor then req:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end
end

-- Player-to-player trade window
local function SkinTrade()
    local f = Get("TradeFrame")
    if not f then return end
    Strip(f)
    for _, n in ipairs({ "TradeFramePlayerPortrait", "TradeFrameRecipientPortrait" }) do
        local p = Get(n)
        if p and p.SetAlpha then p:SetAlpha(0) end
    end
    local panel = Panel(f, 0, 0, 0, 0)
    SkinClose(Get("TradeFrameCloseButton"), panel)
    TitleText(Get("TradeFramePlayerNameText"))
    TitleText(Get("TradeFrameRecipientNameText"))
    for _, n in ipairs({ "TradeRecipientItemsInset", "TradePlayerItemsInset", "TradePlayerInputMoneyInset",
        "TradePlayerEnchantInset", "TradeRecipientEnchantInset", "TradeRecipientMoneyInset", "TradeRecipientMoneyBg" }) do
        local x = Get(n)
        if x then
            if x.SetAlpha then x:SetAlpha(0) end
            if x.GetRegions then Blank(x); StripArtChildren(x) end
        end
    end
    for _, who in ipairs({ "TradePlayerItem", "TradeRecipientItem" }) do
        for i = 1, 7 do
            local item = Get(who .. i)
            if item then
                Blank(item) -- the name plate art
                local btn = Get(who .. i .. "ItemButton")
                local icon = Get(who .. i .. "ItemButtonIconTexture")
                if btn and not btn.cysItemBox then
                    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
                    if nt then nt:SetAlpha(0) end
                    if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                    btn.cysItemBox = Box(btn, T.line, -1, -1)
                end
                -- one dark row around the slot and the name beside it, so each row reads as a unit
                local plate = Get(who .. i .. "NameFrame")
                if btn and plate and not item.cysRowBox then
                    local row = Own(CreateFrame("Frame", nil, item))
                    item.cysRowBox = row
                    row:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
                    row:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 2, 14)
                    row:SetFrameLevel(max(btn:GetFrameLevel() - 2, 0))
                    W.Texture(row, "BACKGROUND", T.field):SetAllPoints()
                    row.edges = W.Border(row, 1, T.line, "BORDER")
                end
            end
        end
    end
    -- the "Announce Trade" tick box in the same flat style as the /cui ones
    for _, c in ipairs(Kids(f)) do
        local okT, typ = pcall(function() return c:GetObjectType() end)
        if okT and typ == "CheckButton" and not c.cysCheck then
            c.cysCheck = true
            for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
                local t = c[g] and c[g](c)
                if t then t:SetAlpha(0) end
            end
            local box = Box(c, T.line, 4, 4)
            box:SetFrameLevel(max(c:GetFrameLevel() - 1, 0))
            local ct = c.GetCheckedTexture and c:GetCheckedTexture()
            if ct then
                ct:SetTexture("Interface\\Buttons\\WHITE8X8")
                ct:SetVertexColor(T.brand[1], T.brand[2], T.brand[3])
                ct:ClearAllPoints()
                ct:SetPoint("TOPLEFT", c, "TOPLEFT", 7, -7)
                ct:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -7, 7)
            end
            local cn = c:GetName()
            local txt = c.Text or (cn and _G[cn .. "Text"])
            if txt and txt.SetTextColor then txt:SetTextColor(T.desc[1], T.desc[2], T.desc[3]) end
        end
    end
    SkinTree(f, 3)
    FlatButton(Get("TradeFrameTradeButton"))
    FlatButton(Get("TradeFrameCancelButton"))
    local function Reflat()
        for _, n in ipairs({ "TradeFrameTradeButton", "TradeFrameCancelButton" }) do
            local b = Get(n)
            if b then BlankButtonArt(b) end
        end
    end
    f:HookScript("OnShow", Reflat)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("TRADE_ACCEPT_UPDATE")
    ev:RegisterEvent("TRADE_UPDATE")
    ev:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
    ev:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
    ev:SetScript("OnEvent", function() if f:IsShown() then Reflat() end end)
end

-- Inspect window (another player's gear, talents and honor)
local function SkinInspect()
    local f = Get("InspectFrame")
    if not f then return end
    for _, n in ipairs({ "InspectFrame", "InspectPaperDollFrame", "InspectHonorFrame", "InspectTalentFrame", "InspectPVPFrame", "InspectGuildFrame" }) do
        local x = Get(n)
        if x then Strip(x) end
    end
    local panel = Panel(f, 11, -12, -32, 76)
    local lo = Get("InspectMainHandSlot") or Get("InspectRangedSlot")
    FitPanel(panel, f, Get("InspectHeadSlot"), Get("InspectHandsSlot"), Get("InspectNameText"), lo, 10)
    SkinClose(Get("InspectFrameCloseButton"), panel)
    TitleText(Get("InspectNameText"))
    HookTabs()
    SkinTabs("InspectFrameTab", tonumber(f.numTabs) or 3, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)
    SkinTree(f, 4)
    local m = Get("InspectModelFrame")
    if m then
        Blank(m)
        for _, c in ipairs(Kids(m)) do if c.GetObjectType and c:GetObjectType() ~= "Model" then Blank(c) end end
    end
    -- equipment slots: flat boxes whose edge takes the item colour
    local slots = {}
    for _, n in ipairs(SLOT_NAMES) do
        local b = Get("Inspect" .. n .. "Slot")
        if b and not b.cysSlotSkinned then
            b.cysSlotSkinned = true
            local icon = b.icon or b.Icon or Get("Inspect" .. n .. "SlotIconTexture")
            Blank(b, function(r) return r == icon end)
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            b.cysSlotBox = Box(b, T.line, -1, -1)
            b:HookScript("OnEnter", function() W.SetBorder(b.cysSlotBox.edges, T.accent) end)
            b:HookScript("OnLeave", function() W.SetBorder(b.cysSlotBox.edges, b.cysSlotColor or T.line) end)
        end
        if b and b.cysSlotSkinned then slots[#slots + 1] = b end
    end
    local function Paint()
        local unit = f.unit or "target"
        for _, b in ipairs(slots) do
            local id = b:GetID()
            local q = id and GetInventoryItemQuality and GetInventoryItemQuality(unit, id)
            local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            local col = c and { c.r, c.g, c.b } or T.line
            b.cysSlotColor = col
            if b.cysSlotBox then W.SetBorder(b.cysSlotBox.edges, col) end
            local nt = b.GetNormalTexture and b:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end
    end
    f:HookScript("OnShow", function() if C_Timer and C_Timer.After then C_Timer.After(0.2, function() Safe(Paint) end) end Safe(Paint) end)
    if hooksecurefunc and InspectPaperDollItemSlotButton_Update then
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", function() Safe(Paint) end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("INSPECT_READY")
    ev:SetScript("OnEvent", function() if C_Timer and C_Timer.After then C_Timer.After(0.1, function() Safe(Paint) end) end end)
    Paint()
end

-- Battleground queue window and the end-of-match scoreboard
local function SkinBattleground()
    local f = Get("BattlefieldFrame")
    if f then
        Strip(f)
        local panel = Panel(f, 11, -12, -32, 76)
        SkinClose(Get("BattlefieldFrameCloseButton"), panel)
        TitleText(Get("BattlefieldFrameFrameLabel"))
        local sl = Get("BattlefieldListScrollFrame")
        if sl then Blank(sl) end
        SkinTree(f, 3)
        for _, n in ipairs({ "BattlefieldFrameCancelButton", "BattlefieldFrameJoinButton", "BattlefieldFrameGroupJoinButton" }) do
            FlatButton(Get(n))
        end
        local z = Get("BattlefieldFrameZoneDescription")
        if z and z.SetTextColor then z:SetTextColor(T.desc[1], T.desc[2], T.desc[3]) end
    end
    local s = Get("WorldStateScoreFrame")
    if s then
        Strip(s)
        local panel = Panel(s, 0, -12, -102, 25)
        SkinClose(Get("WorldStateScoreFrameCloseButton"), panel)
        local sf = Get("WorldStateScoreScrollFrame")
        if sf then Blank(sf) end
        SkinTree(s, 3)
        FlatButton(Get("WorldStateScoreFrameLeaveButton"))
        HookTabs()
        SkinTabs("WorldStateScoreFrameTab", 3, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(s) end, nil, panel)
    end
end

-- Dressing room (ctrl-click an item)
local function SkinDressUp()
    local f = Get("DressUpFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -32, 76)
    SkinClose(Get("DressUpFrameCloseButton"), panel)
    local cancel = Get("DressUpFrameCancelButton")
    -- the title may be named differently in this client: look in the frame and its title container
    local titles = {}
    local function Collect(o)
        if not o then return end
        if o.GetObjectType and o:GetObjectType() == "FontString" then titles[#titles + 1] = o return end
        if o.GetRegions then
            for _, r in ipairs({ o:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText and r:GetText() and r:GetText() ~= "" then titles[#titles + 1] = r end
            end
        end
    end
    Collect(Get("DressUpFrameTitleText")); Collect(f.TitleText); Collect(f.TitleContainer); Collect(f.TitleContainer and f.TitleContainer.TitleText)
    local function Layout()
        -- the panel wraps the model, the text and the Reset / Close buttons
        local b, fb, r, fr = cancel and cancel:GetBottom(), f:GetBottom(), cancel and cancel:GetRight(), f:GetRight()
        if b and fb and r and fr then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -12)
            panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", max(r + 12 - fr, -32), b - 12 - fb)
        end
        for _, t in ipairs(titles) do
            TitleText(t)
            t:ClearAllPoints()
            t:SetPoint("TOP", panel, "TOP", 0, -8)
        end
    end
    f:HookScript("OnShow", function() Layout(); if C_Timer and C_Timer.After then C_Timer.After(0.05, Layout) end end)
    Layout()
    local bg = Get("DressUpBackgroundTopLeft")
    for _, n in ipairs({ "DressUpBackgroundTopLeft", "DressUpBackgroundTopRight", "DressUpBackgroundBotLeft", "DressUpBackgroundBotRight" }) do
        local x = Get(n)
        if x and x.SetAlpha then x:SetAlpha(0) end
    end
    SkinTree(f, 3)
    FlatButton(Get("DressUpFrameResetButton"))
    FlatButton(Get("DressUpFrameCancelButton"))
end

-- Questie's quest tracker: a dark panel with the gold edge
local function SkinQuestie()
    local function Try(ticker)
        local base = _G.Questie_BaseFrame
        if base and not base.cysQuestie then
            base.cysQuestie = true
            local bd = Own(CreateFrame("Frame", nil, base))
            bd:SetPoint("TOPLEFT", base, "TOPLEFT", -4, 4)
            bd:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", 4, -4)
            bd:SetFrameLevel(max(base:GetFrameLevel() - 1, 0))
            W.Texture(bd, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.8 }):SetAllPoints()
            W.Border(bd, 1, T.border, "BORDER")
            base.cysPanel = bd
            if ticker then ticker:Cancel() end
            CUI:Print("Questie tracker skinned.")
        end
    end
    if _G.Questie_BaseFrame then Try() elseif C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, Try) end
end

-- Flat tick box (Blizzard's check button) in the /cui style
local function SkinCheck(c)
    if not c or c.cysCheck then return end
    c.cysCheck = true
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
        local t = c[g] and c[g](c)
        if t then t:SetAlpha(0) end
    end
    local box = Box(c, T.line, 4, 4)
    box:SetFrameLevel(max(c:GetFrameLevel() - 1, 0))
    local ct = c.GetCheckedTexture and c:GetCheckedTexture()
    if ct then
        ct:SetTexture("Interface\\Buttons\\WHITE8X8")
        ct:SetVertexColor(T.brand[1], T.brand[2], T.brand[3])
        ct:ClearAllPoints()
        ct:SetPoint("TOPLEFT", c, "TOPLEFT", 7, -7)
        ct:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -7, 7)
    end
    local cn = c.GetName and c:GetName()
    local txt = c.Text or (cn and _G[cn .. "Text"])
    if txt and txt.SetTextColor then txt:SetTextColor(T.desc[1], T.desc[2], T.desc[3]) end
end

-- Walk a window's children and flatten tick boxes, stone buttons and scroll bars (also the ones made later)
local function SkinWidgets(f, depth, skip)
    SkinTree(f, depth or 4, skip)
    Walk(f, function(c)
        if c.GetObjectType and c:GetObjectType() == "CheckButton" then SkinCheck(c) end
    end, depth or 4, skip)
end

-- One recipe for the simpler windows. o = { panel = {l,t,r,b}, close, title, buttons = {...}, tabs = "Prefix", ntabs, depth, live, dropdowns = {...} }
local function GenericWindow(name, o)
    local f = Get(name)
    if not f then return end
    o = o or {}
    Strip(f, o.keep)
    local p = o.panel or { 0, 0, 0, 0 }
    local panel = Panel(f, p[1], p[2], p[3], p[4])
    SkinClose(o.close and Get(o.close) or f.CloseButton or Get(name .. "CloseButton"), panel)
    if o.title then TitleText(Get(o.title)) end
    for _, n in ipairs(o.buttons or {}) do
        local b = Get(n) or (f[n])
        if b then FlatButton(b) end
    end
    for _, n in ipairs(o.dropdowns or {}) do SkinDropdown(Get(n) or f[n]) end
    if o.tabs then
        HookTabs()
        SkinTabs(o.tabs, o.ntabs or 3, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end, nil, panel)
    end
    Safe(SkinWidgets, f, o.depth or 4, o.skip)
    if o.live then
        -- windows whose rows are made on demand: look again now and then while shown
        local acc = 0
        f:HookScript("OnUpdate", function(self, dt)
            acc = acc + dt
            if acc < 0.5 then return end
            acc = 0
            Safe(SkinWidgets, self, o.depth or 4, o.skip)
        end)
    end
    return f, panel
end

-- Slider: a thin dark track with a flat gold handle, and flat arrows on its ends
local function FlatSlider(sl)
    if not sl or sl.cysFlat then return end
    sl.cysFlat = true
    local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
    Blank(sl, function(r) return r == thumb end)
    local track = Own(CreateFrame("Frame", nil, sl))
    track:SetPoint("LEFT", sl, "LEFT", 0, 0)
    track:SetPoint("RIGHT", sl, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetFrameLevel(max(sl:GetFrameLevel() - 1, 0))
    W.Texture(track, "BACKGROUND", T.field):SetAllPoints()
    track.edges = W.Border(track, 1, T.line, "BORDER")
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(T.brand[1], T.brand[2], T.brand[3])
        thumb:SetSize(8, 16)
    end
    local parent = sl:GetParent()
    if parent then
        if parent.Back then SkinArrow(parent.Back, "<") end
        if parent.Forward then SkinArrow(parent.Forward, ">") end
    end
end

-- Dropdown buttons with < > steppers beside them (the options window's choice rows)
local function FlatChoice(c)
    if c.cysChoice then return end
    c.cysChoice = true
    if c.DecrementButton then SkinArrow(c.DecrementButton, "<") end
    if c.IncrementButton then SkinArrow(c.IncrementButton, ">") end
    local dd = c.Dropdown
    if dd and not dd.cysFlatDD then
        dd.cysFlatDD = true
        Blank(dd, function(r) return r == dd.Arrow or r == dd.Text end)
        if dd.Arrow then dd.Arrow:SetAlpha(0.9) end
        W.Texture(dd, "BACKGROUND", T.field):SetAllPoints()
        Box(dd, T.border, 0, 0)
    end
end

-- Game options and key bindings (the newer Settings window, or the older Interface Options on older clients)
local function SkinOptions()
    -- other addons put their own option pages inside this window: leave anything with a non-Blizzard name alone
    local function ThirdParty(c)
        local n = c.GetName and c:GetName()
        return n ~= nil and not n:find("^Settings") and not n:find("^Blizzard") and not n:find("^CysUI")
    end
    local f, panel = GenericWindow("SettingsPanel", { depth = 6, live = true, close = "SettingsPanelCloseButton", skip = ThirdParty,
        buttons = { "SettingsPanel.ApplyButton" } })
    if f then
        -- a second stock close button (the red X) can sit under ours: hide it, ours closes the window too
        local second = f.ClosePanelButton or f.CloseX
        if second and second ~= f.CloseButton and not second.cysSkinned and second.SetAlpha then
            second:SetAlpha(0); second:EnableMouse(false)
            if second.Hide then second:Hide(); hooksecurefunc(second, "Show", function(self) self:Hide() end) end
        end
        for _, k in ipairs({ "ApplyButton", "DefaultsButton", "OkayButton", "CancelButton" }) do
            if f[k] and not f[k].cysSkinned then FlatButton(f[k]) end
        end
        -- remove the leftover stock borders and boxes: the category list's side lines, its header bars and the settings list frame
        local function Clear(o, depth)
            if not o or not o.GetChildren then return end
            if o.cysOwn then return end
            Blank(o)
            StripArtChildren(o)
            for _, k in ipairs({ "Background", "Bg", "BG", "Border", "Left", "Right", "Middle", "Highlight" }) do
                local c = o[k]
                if type(c) == "table" and c.SetAlpha and k ~= "Highlight" then c:SetAlpha(0) end
            end
            if depth > 0 then
                for _, c in ipairs(Kids(o)) do
                    if not ThirdParty(c) then Clear(c, depth - 1) end
                end
            end
        end
        local function Tidy()
            local cl = f.CategoryList
            if cl then
                Clear(cl, 4)
                -- header rows ("Gameplay", "Accessibility", "System"): gold text over a thin gold underline
                local sb = cl.ScrollBox
                if sb and sb.ForEachFrame then
                    sb:ForEachFrame(function(row)
                        local bg = row.Background
                        if bg and bg.SetAlpha then bg:SetAlpha(0) end
                        if row.Toggle and row.Toggle.SetAlpha then row.Toggle:SetAlpha(0) end
                        if bg and not row.cysLine then
                            row.cysLine = true
                            local ln = W.Texture(row, "BORDER", T.border)
                            ln:SetHeight(1)
                            ln:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2)
                            ln:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
                            ln.cysOwn = true
                        end
                    end)
                end
            end
            Clear(f.Container, 1)
            Clear(f.SettingsList, 1)
            -- Blizzard's red-X close art: find it by its picture name wherever it sits in the window and hide it
            local function KillRedX(o, d)
                if not o or not o.GetRegions then return end
                for _, r in ipairs({ o:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" and not r.cysOwn and r.GetAtlas then
                        local ok, at = pcall(r.GetAtlas, r)
                        if ok and type(at) == "string" and (at:find("redx") or at:find("RedX") or at:lower():find("closebutton")) then
                            r:SetAlpha(0)
                        end
                    end
                end
                for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                    local t = o[g] and o[g](o)
                    if t and t.GetAtlas then
                        local ok, at = pcall(t.GetAtlas, t)
                        if ok and type(at) == "string" and (at:find("redx") or at:lower():find("closebutton")) then t:SetAlpha(0) end
                    end
                end
                if d > 0 then
                    for _, c in ipairs(Kids(o)) do
                        if not ThirdParty(c) and not c.cysOwn then KillRedX(c, d - 1) end
                    end
                end
            end
            KillRedX(f, 3)
            -- the Game / AddOns tabs: label centred in its box, same size as the rest
            for _, k in ipairs({ "GameTab", "AddOnsTab" }) do
                local tab = f[k]
                local fs = tab and (tab.Text or (tab.GetFontString and tab:GetFontString()))
                if fs and fs.ClearAllPoints and not tab.cysTabText then
                    tab.cysTabText = true
                    fs:ClearAllPoints()
                    fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
                    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
                    local face = fs:GetFont()
                    if face then fs:SetFont(face, 12) end
                end
            end
            -- other addons' pages draw near-black boxes: bring them to the panel colour so they sit in it
            local function Tint(o, d)
                if not o or not o.GetChildren then return end
                if o.GetBackdropColor and not o.cysTinted then
                    local ok, r, g, b, a = pcall(o.GetBackdropColor, o)
                    if ok and r and a and a > 0 and r < 0.12 and g < 0.12 and b < 0.12 then
                        o.cysTinted = true
                        o:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], a)
                    end
                end
                if d > 0 then for _, c in ipairs(Kids(o)) do Tint(c, d - 1) end end
            end
            Tint(f.Container, 9)
            Walk(f.Container or f, function(c)
                if c.GetObjectType and c:GetObjectType() == "Slider" and not (c.GetName and (c:GetName() or ""):find("ScrollBar")) and not c.ScrollUpButton then
                    FlatSlider(c)
                end
                if c.DecrementButton and c.IncrementButton then FlatChoice(c) end
                if c.Control and c.Control.DecrementButton then FlatChoice(c.Control) end
                -- key binding rows: the "Not Bound" buttons
                for _, k in ipairs({ "Button1", "Button2", "Button3", "Button4" }) do
                    local b = c[k]
                    if type(b) == "table" and b.GetObjectType and not b.cysFlatKey then
                        local okT, typ = pcall(function() return b:GetObjectType() end)
                        if okT and typ == "Button" then b.cysFlatKey = true; FlatButton(b) end
                    end
                end
            end, 9, ThirdParty)
        end
        -- other addons' pages: only the stock-looking widgets get the flat look (tick boxes, sliders, old-style dropdowns, stone buttons)
        local function Uniform(c)
            local okT, typ = pcall(function() return c:GetObjectType() end)
            if not okT then return end
            local n = c.GetName and c:GetName()
            if typ == "CheckButton" then
                SkinCheck(c)
            elseif typ == "Slider" then
                if not (n and n:find("ScrollBar")) and not c.ScrollUpButton then pcall(FlatSlider, c) end
            elseif typ == "Frame" and n and _G[n .. "Button"] and _G[n .. "Middle"] and not c.cysSkinned then
                SkinDropdown(c)
                local ab = _G[n .. "Button"]
                if ab and ab.GetObjectType then pcall(SkinArrow, ab, "v") end
            elseif typ == "Button" and c.Left and c.Middle and c.Right and not c.cysSkinned then
                FlatButton(c)
            end
        end
        local function TidyOthers()
            if f.Container then Walk(f.Container, function(c) pcall(Uniform, c) end, 9, nil) end
        end
        Safe(Tidy)
        Safe(TidyOthers)
        f:HookScript("OnShow", function() Safe(Tidy); Safe(TidyOthers) end)
        local acc, acc2 = 0, 0
        f:HookScript("OnUpdate", function(_, dt)
            acc = acc + dt; acc2 = acc2 + dt
            if acc > 0.7 then acc = 0; Safe(Tidy) end
            if acc2 > 1.5 then acc2 = 0; Safe(TidyOthers) end
        end)
    end
    GenericWindow("InterfaceOptionsFrame", { depth = 5, buttons = { "InterfaceOptionsFrameOkay", "InterfaceOptionsFrameCancel", "InterfaceOptionsFrameDefaults" }, live = true })
    GenericWindow("VideoOptionsFrame", { depth = 5, live = true, buttons = { "VideoOptionsFrameOkay", "VideoOptionsFrameCancel", "VideoOptionsFrameDefaults", "VideoOptionsFrameApply" } })
    GenericWindow("KeyBindingFrame", { depth = 5, live = true })
end

local function SkinChatConfig()
    GenericWindow("ChatConfigFrame", { depth = 6, live = true, buttons = { "ChatConfigFrameOkayButton", "ChatConfigFrameDefaultButton", "ChatConfigFrameRedockButton" } })
    for _, n in ipairs({ "ChatConfigCategoryFrame", "ChatConfigBackgroundFrame", "ChatConfigChatSettingsLeft", "ChatConfigChannelSettingsLeft",
        "ChatConfigOtherSettingsCombat", "ChatConfigOtherSettingsPVP", "ChatConfigOtherSettingsSystem", "ChatConfigOtherSettingsCreature" }) do
        local x = Get(n)
        if x then Blank(x); StripArtChildren(x) end
    end
end

-- The flight map
local function SkinTaxi()
    local f = Get("TaxiFrame")
    if not f then return end
    -- the flight map picture is a texture of the window itself: keep it
    local function KeepMap(r)
        local n = r.GetName and r:GetName()
        return r == _G.TaxiMap or (n and n:find("^TaxiMap") ~= nil)
    end
    GenericWindow("TaxiFrame", { panel = { 11, -12, -32, 76 }, close = "TaxiCloseButton", title = "TaxiMerchant", keep = KeepMap })
    local p = Get("TaxiPortrait")
    if p and p.SetAlpha then p:SetAlpha(0) end
    -- the stock layout leaves a tall empty band above the map: start the panel lower and put the title inside it
    local panel = f.cysPanel
    if panel then
        local function Fit()
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -46)
            panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 76)
            local t = Get("TaxiMerchant")
            if t then t:ClearAllPoints(); t:SetPoint("TOP", panel, "TOP", 0, -8) end
        end
        f:HookScript("OnShow", function() Fit(); if C_Timer and C_Timer.After then C_Timer.After(0.05, Fit) end end)
        Fit()
    end
end

-- Small pop-ups: stack split, ready check, color picker, and the breath / fatigue bars
local function SkinSmallWindows()
    Safe(GenericWindow, "StackSplitFrame", { buttons = { "StackSplitOkayButton", "StackSplitCancelButton" } })
    Safe(GenericWindow, "ReadyCheckListenerFrame", { buttons = { "ReadyCheckFrameYesButton", "ReadyCheckFrameNoButton" } })
    Safe(GenericWindow, "PVPReadyDialog", { buttons = { "PVPReadyDialogEnterBattleButton", "PVPReadyDialogHideButton", "PVPReadyDialogLeaveQueueButton" } })
    Safe(GenericWindow, "ColorPickerFrame", { buttons = { "ColorPickerOkayButton", "ColorPickerCancelButton" } })
    for i = 1, 3 do
        local bar = Get("MirrorTimer" .. i)
        if bar and not bar.cysMirror then
            bar.cysMirror = true
            Blank(bar)
            local sb = Get("MirrorTimer" .. i .. "StatusBar") or bar.StatusBar
            if sb and sb.SetStatusBarTexture then
                sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                Box(sb, T.line, 0, 0)
            end
            local txt = Get("MirrorTimer" .. i .. "Text") or bar.Text
            if txt and txt.ClearAllPoints then
                txt:ClearAllPoints()
                txt:SetPoint("CENTER", sb or bar, "CENTER", 0, -2)
            end
            local border = Get("MirrorTimer" .. i .. "Border")
            if border and border.SetAlpha then border:SetAlpha(0) end
        end
    end
end

-- Pet stable, tabard designer, guild and arena charters
local function SkinExtras()
    Safe(GenericWindow, "PetStableFrame", { panel = { 11, -12, -32, 76 } })
    Safe(GenericWindow, "TabardFrame", { panel = { 11, -12, -32, 76 }, buttons = { "TabardFrameCancelButton", "TabardFrameAcceptButton" } })
    Safe(GenericWindow, "GuildRegistrarFrame", { panel = { 11, -12, -32, 76 }, buttons = { "GuildRegistrarFramePurchaseButton", "GuildRegistrarFrameCancelButton", "GuildRegistrarFrameGoodbyeButton" } })
    Safe(GenericWindow, "PetitionFrame", { panel = { 11, -12, -32, 76 }, buttons = { "PetitionFrameSignButton", "PetitionFrameRequestButton", "PetitionFrameRenameButton", "PetitionFrameCancelButton" } })
end

local function SkinTimeManager()
    Safe(GenericWindow, "TimeManagerFrame", { panel = { 0, 0, 0, 0 } })
    local s = Get("StopwatchFrame")
    if s then
        Safe(GenericWindow, "StopwatchFrame", { panel = { 0, -17, 0, 2 }, close = "StopwatchCloseButton" })
        local tab = Get("StopwatchTabFrame")
        if tab then Blank(tab) end
    end
end

local function SkinAddonList()
    GenericWindow("AddonList", { panel = { 0, 0, 0, 0 }, depth = 5, live = true, buttons = { "EnableAllButton", "DisableAllButton", "OkayButton", "CancelButton" } })
end

-- Blizzard's bank window (Cys's Bags' own bank replaces it when that module is on)
local function SkinBank()
    local f = Get("BankFrame")
    if not f then return end
    Strip(f)
    local panel = Panel(f, 11, -12, -30, 70)
    SkinClose(Get("BankCloseButton"), panel)
    TitleText(Get("BankFrameTitleText"))
    local btns = {}
    for i = 1, 28 do btns[#btns + 1] = Get("BankFrameItem" .. i) or (BankSlotsFrame and BankSlotsFrame["Item" .. i]) end
    for i = 1, 6 do btns[#btns + 1] = BankSlotsFrame and BankSlotsFrame["Bag" .. i] end
    for _, b in ipairs(btns) do
        if b and not b.cysItemBox then
            b.cysItemBox = Box(b, T.line, 0, 0)
            b.cysItemBox:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
        end
    end
    FlatButton(Get("BankFramePurchaseButton"))
    -- Blizzard re-textures the slots as the bank changes; keep the stock slot art off them
    local function Paint()
        for _, b in ipairs(btns) do
            local nt = b and b.GetNormalTexture and b:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end
    end
    if hooksecurefunc and BankFrameItemButton_Update and not f.cysHooked then
        f.cysHooked = true
        hooksecurefunc("BankFrameItemButton_Update", function() Safe(Paint) end)
    end
    f:HookScript("OnShow", function() Safe(Paint) end)
    Paint()
end

-- The combat log's "My actions / What happened to me?" bar above the Log chat tab (Blizzard_CombatLog)
local function SkinCombatLogBar()
    for _, name in ipairs({ "CombatLogQuickButtonFrame_Custom", "CombatLogQuickButtonFrame" }) do
        local f = Get(name)
        if f and not f.cysLogSkinned then
            f.cysLogSkinned = true
            Blank(f)
            for _, key in ipairs({ "Background", "Bg", "BG", "Texture" }) do
                local c = f[key]
                if type(c) == "table" and c.SetAlpha then c:SetAlpha(0) end
            end
            local panel = Panel(f, 0, 0, 0, 0)
            panel:SetFrameLevel(max(f:GetFrameLevel() - 1, 0))
            -- its buttons: plain text in the Cys colours
            for _, c in ipairs(Kids(f)) do
                if c.GetObjectType and c:GetObjectType() == "Button" then
                    local fs = c.GetFontString and c:GetFontString()
                    if fs then fs:SetTextColor(T.text[1], T.text[2], T.text[3]) end
                end
            end
        end
    end
end

-- Looking For Group (Blizzard_GroupFinder_VanillaStyle): the eye window with Create Listing / Group Browser tabs
local function SkinLFG()
    local f = Get("LFGParentFrame")
    if not f then return end
    local panel = Panel(f, 0, 0, -30, 74)
    -- the back of the window: a soft gold glow from the top and a faint line under the role row,
    -- so the empty space reads as a designed surface
    if panel and panel.CreateTexture and not panel.cysGlow then
        panel.cysGlow = true
        local g = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
        g:SetPoint("TOPLEFT", 1, -1)
        g:SetPoint("TOPRIGHT", -1, -1)
        g:SetHeight(150)
        g:SetColorTexture(1, 1, 1, 1)
        local c = T.brand or { 1, 0.82, 0 }
        if g.SetGradient then
            pcall(g.SetGradient, g, "VERTICAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 0.12))
        else
            g:SetGradientAlpha("VERTICAL", c[1], c[2], c[3], 0, c[1], c[2], c[3], 0.12)
        end
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT", 14, -118)
        d:SetPoint("TOPRIGHT", -14, -118)
        d:SetHeight(1)
        d:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    -- the window's own close button has no name: find it among the children
    for _, c in ipairs(Kids(f)) do
        if c.GetObjectType and c:GetObjectType() == "Button" and not c:GetName() and c.GetNormalTexture then
            local nt = c:GetNormalTexture()
            local path = nt and nt.GetTexture and nt:GetTexture()
            if type(path) == "string" and path:lower():find("minimize") then Safe(SkinClose, c, panel) end
        end
    end
    HookTabs()
    SkinTabs("LFGParentFrameTab", 2, function() return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) end,
        nil, panel)

    for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame" }) do
        local page = Get(name)
        if page then
            Blank(page) -- the stone background, the background art
            TitleText(Get(name .. "FrameTitle"))
            for _, key in ipairs({ "BackButton", "PostButton", "SendMessageButton", "GroupInviteButton" }) do
                if page[key] then Safe(FlatButton, page[key]) end
            end
            SkinTree(page, 4)
        end
    end

    local listing = Get("LFGListingFrame")
    if listing then
        local gr = listing.GroupRoleButtons
        if gr and gr.RolePollButton then Safe(FlatButton, gr.RolePollButton) end
        if gr and gr.RoleDropdown then Safe(SkinDropdown, gr.RoleDropdown) end
        local av = listing.ActivityView
        if av then
            Blank(av) -- the horizontal bars across the list
            if av.ScrollBar then Safe(SkinMinimalScrollBar, av.ScrollBar) end
            local comment = av.Comment
            if comment and not comment.cysBoxed then
                comment.cysBoxed = true
                Blank(comment)
                for _, c in ipairs(Kids(comment)) do Blank(c) end
                for k, v in pairs(comment) do
                    if type(k) == "string" and type(v) == "table" and v.SetAlpha and k:find("Border") then v:SetAlpha(0) end
                end
                local box = Own(CreateFrame("Frame", nil, comment))
                box:SetPoint("TOPLEFT", -4, 4)
                box:SetPoint("BOTTOMRIGHT", 4, -4)
                box:SetFrameLevel(max(comment:GetFrameLevel() - 1, 0))
                W.Texture(box, "BACKGROUND", T.field):SetAllPoints()
                W.Border(box, 1, T.line, "BORDER")
            end
        end
        -- the category buttons (Dungeons, Quests & Zones...): flat boxes without the painted art
        local function Categories()
            local cv = listing.CategoryView
            for _, b in ipairs(cv and cv.CategoryButtons or {}) do
                if not b.cysBoxed then
                    if b.Cover then b.Cover:SetAlpha(0) end
                    if b.Icon then b.Icon:SetAlpha(0.3) end
                    Safe(BoxButton, b, 0, 0)
                end
            end
        end
        Safe(Categories)
        listing:HookScript("OnShow", function() Safe(Categories) end)
    end

    local browse = Get("LFGBrowseFrame")
    if browse then
        Safe(SkinDropdown, browse.CategoryDropdown)
        Safe(SkinDropdown, browse.ActivityDropdown)
        if browse.RefreshButton then Safe(BoxButton, browse.RefreshButton, 0, 0) end
        if browse.ScrollBar then Safe(SkinMinimalScrollBar, browse.ScrollBar) end
        -- the painted result bars: flatten as rows are created
        if browse.ScrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
            pcall(ScrollUtil.AddAcquiredFrameCallback, browse.ScrollBox, function(_, row)
                if row.ResultBG then row.ResultBG:SetAlpha(0) end
            end, nil, true)
        end
    end
end

-- The Raid tab of the friends window (Blizzard_RaidUI loads when it is first needed): eight group boxes, class counters,
-- Ready Check / Raid Info / Convert buttons and the Raid Info pop-out.
local function SkinRaidTab()
    local rf = Get("RaidFrame")
    if not rf then return end
    Strip(rf)
    Strip(Get("RaidFrameNotInRaid"))
    for g = 1, 8 do
        local grp = Get("RaidGroup" .. g)
        if grp and not grp.cysGroupBox then
            Blank(grp)
            grp.cysGroupBox = Box(grp, T.line, 0, 0)
            grp.cysGroupBox:SetFrameLevel(max(grp:GetFrameLevel() - 1, 0))
            local label = Get("RaidGroup" .. g .. "Label")
            if label then BlankButtonArt(label) end
            for slot = 1, 5 do
                local sb = Get("RaidGroup" .. g .. "Slot" .. slot)
                if sb then Blank(sb, function(r) return r == sb:GetHighlightTexture() end) end
            end
        end
    end
    -- the 40 member buttons: flat dark bar instead of the stone strip
    for i = 1, 40 do
        local b = Get("RaidGroupButton" .. i)
        if b and not b.cysItemBox then
            local nt = b.GetNormalTexture and b:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
            b.cysItemBox = Box(b, T.line, 0, 0)
            b.cysItemBox:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
        end
    end
    for _, name in ipairs({ "RaidFrameReadyCheckButton", "RaidFrameRaidInfoButton", "RaidFrameConvertToRaidButton" }) do
        Safe(FlatButton, Get(name))
    end
    for i = 1, 15 do
        local b = Get("RaidClassButton" .. i)
        if b and not b.cysItemBox then
            b.cysItemBox = Box(b, T.line, 0, 0)
            b.cysItemBox:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
        end
    end
    local info = Get("RaidInfoFrame")
    if info and not info.cysPanel then
        Strip(info)
        Blank(info)
        for _, n in ipairs({ "RaidInfoDetailHeader", "RaidInfoDetailCorner" }) do
            local t = Get(n)
            if t then t:SetAlpha(0) end
        end
        local panel = Panel(info, 0, 0, 0, 0)
        SkinClose(Get("RaidInfoCloseButton"), panel)
        if info.ScrollBar then Safe(SkinMinimalScrollBar, info.ScrollBar) end
    end
end

-- Pop-up dialogs (logout countdown, confirmations): flat dark box, gold edge, flat buttons
local function SkinPopups()
    for i = 1, 4 do
        local f = Get("StaticPopup" .. i)
        if f and not f.cysPopup then
            f.cysPopup = true
            Strip(f)
            Panel(f, 0, 0, 0, 0)
            for j = 1, 4 do FlatButton(Get("StaticPopup" .. i .. "Button" .. j)) end
            FlatButton(Get("StaticPopup" .. i .. "ExtraButton"))
            SkinTree(f, 2)
        end
    end
end

-- Right-click menus and other dropdown lists (unit menus, the Totems dropdown...)
local function SkinDropdowns()
    local function PaintButtons(list)
        local n = list:GetName()
        for i = 1, 32 do
            local b = Get(n .. "Button" .. i)
            if not b then break end
            local hl = b.GetHighlightTexture and b:GetHighlightTexture()
            if hl and not hl.cysFlat then
                hl.cysFlat = true
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(T.brand[1], T.brand[2], T.brand[3], 0.25)
            end
        end
    end
    local function FlatBackdrop(bd)
        if not (bd and bd.SetBackdrop) or bd.cysFlat then return end
        bd.cysFlat = true
        bd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        bd:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.97)
        local function Edge() local c = T.border; bd:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
        Edge()
        W.OnBorderStyle(Edge)
    end
    local function SkinList(L)
        local list = Get("DropDownList" .. L)
        if not list or list.cysDD then return end
        list.cysDD = true
        FlatBackdrop(Get("DropDownList" .. L .. "Backdrop") or list.Backdrop)
        FlatBackdrop(Get("DropDownList" .. L .. "MenuBackdrop") or list.MenuBackdrop)
        StripArtChildren(list)
        list:HookScript("OnShow", function(self) Safe(PaintButtons, self) end)
    end
    -- the newer menu system (Blizzard_Menu): frames are made on the fly, so look for their background art when a menu opens
    local function IsMenuBg(tex)
        local ok, atlas = pcall(tex.GetAtlas, tex)
        return ok and type(atlas) == "string" and string.find(atlas, "^common%-dropdown%-classic") ~= nil
    end
    local menuHits = 0
    local function SkinMenuFrame(fr, depth)
        if not fr or not fr.GetRegions then return end
        for _, r in ipairs({ fr:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and not r.cysOwn and IsMenuBg(r) then
                -- darken Blizzard's own background texture instead of covering it with a frame of ours:
                -- a cover frame can sit above the menu entries and hide their text
                if not r.cysTinted then
                    r.cysTinted = true
                    pcall(r.SetDesaturated, r, true)
                    pcall(r.SetVertexColor, r, 0.10, 0.10, 0.10, 1)
                end
                if not fr.cysMenuBg then
                    fr.cysMenuBg = true
                    menuHits = menuHits + 1
                    local edge = CreateFrame("Frame", nil, fr)
                    edge.cysOwn = true
                    edge:SetAllPoints(fr)
                    edge:SetFrameLevel(fr:GetFrameLevel() + 30)
                    W.Border(edge, 1, T.border, "OVERLAY")
                end
            end
        end
        if depth > 1 then
            for _, c in ipairs(Kids(fr)) do SkinMenuFrame(c, depth - 1) end
        end
    end
    -- some frames other addons make answer to nothing useful ("bad self"), so every look at a frame is guarded
    local function Candidate(fr)
        local ok, shown, strata = pcall(function() return fr:IsShown(), fr:GetFrameStrata() end)
        return ok and shown and strata == "FULLSCREEN_DIALOG"
    end
    local function ScanMenus()
        for _, c in ipairs(Kids(UIParent)) do
            if Candidate(c) then pcall(SkinMenuFrame, c, 3) end
        end
    end
    local menusHooked
    -- the menu frames can sit anywhere in the frame tree, so after a menu opens look through every frame once
    local function ScanAll()
        local fr = EnumerateFrames()
        while fr do
            if Candidate(fr) then pcall(SkinMenuFrame, fr, 1) end
            fr = EnumerateFrames(fr)
        end
    end
    local function Kick()
        Safe(ScanMenus)
        Safe(ScanAll)
        if C_Timer and C_Timer.After then
            for _, t in ipairs({ 0, 0.1, 0.3 }) do C_Timer.After(t, function() Safe(ScanAll) end) end
        end
    end
    -- a click anywhere may open a menu (or one of its submenus): look right after it
    do
        local clicks = CreateFrame("Frame")
        if pcall(clicks.RegisterEvent, clicks, "GLOBAL_MOUSE_UP") then
            clicks:SetScript("OnEvent", function() Kick() end)
        end
    end
    SLASH_CYSMENU1 = "/cysmenu"
    SlashCmdList["CYSMENU"] = function()
        CUI:Print("menu skin: Menu=" .. tostring(Menu ~= nil) .. "  manager=" .. tostring(Menu and Menu.GetManager and Menu.GetManager() ~= nil)
            .. "  hooked=" .. tostring(menusHooked) .. "  menus skinned so far=" .. menuHits)
        CUI:Print("Open a right-click menu, then type /cysmenu again.")
        ScanAll()
        CUI:Print("after a full scan: menus skinned=" .. menuHits)
    end
    local function HookNewMenus()
        if menusHooked or not (Menu and Menu.GetManager) then return end
        local manager = Menu.GetManager()
        if not manager then return end
        menusHooked = true
        for _, fn in ipairs({ "OpenMenu", "OpenContextMenu" }) do
            if manager[fn] then hooksecurefunc(manager, fn, Kick) end
        end
        -- submenus open as you hover, so keep looking while a menu is up
        local watcher, acc = CreateFrame("Frame"), 0
        watcher:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.2 then return end
            acc = 0
            if manager.GetOpenMenu and manager:GetOpenMenu() then Safe(ScanAll) end
        end)
    end
    HookNewMenus()
    if not menusHooked then
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("ADDON_LOADED")
        ev:SetScript("OnEvent", function(self, _, name)
            if name == "Blizzard_Menu" then HookNewMenus(); self:UnregisterEvent("ADDON_LOADED") end
        end)
    end

    for L = 1, 3 do SkinList(L) end
    if hooksecurefunc and UIDropDownMenu_CreateFrames then
        hooksecurefunc("UIDropDownMenu_CreateFrames", function() for L = 1, 3 do Safe(SkinList, L) end end)
    end
end

Skins.list = {
    { key = "popups",    label = "Pop-up dialogs (logout, confirmations)", apply = SkinPopups },
    { key = "dropdowns", label = "Right-click menus and dropdown lists", apply = SkinDropdowns },
    { key = "menu",      label = "Main Menu (Esc menu)", apply = SkinMenu },
    { key = "character", label = "Character, Reputation and Skills", apply = SkinCharacter },
    { key = "spellbook", label = "Spellbook", apply = SkinSpellbook },
    { key = "talents",   label = "Talents",   apply = SkinTalents, addon = "Blizzard_TalentUI" },
    { key = "macros",    label = "Macros",    apply = SkinMacros,  addon = "Blizzard_MacroUI" },
    { key = "quests",    label = "Quest Log", apply = SkinQuestLog },
    { key = "loot",      label = "Loot window", apply = SkinLoot },
    { key = "questnpc",  label = "Quest dialogs (accept / turn in)", apply = SkinQuestDialog },
    { key = "gossip",    label = "NPC gossip window", apply = SkinGossip },
    { key = "friends",   label = "Friends, Who and Guild", apply = SkinFriends },
    { key = "combatlog", label = "Combat log button bar", apply = SkinCombatLogBar, addon = "Blizzard_CombatLog" },
    { key = "lfg",       label = "Looking For Group window", apply = SkinLFG, addon = "Blizzard_GroupFinder_VanillaStyle" },
    { key = "raidtab",   label = "Raid tab (groups and Raid Info)", apply = SkinRaidTab, addon = "Blizzard_RaidUI" },
    { key = "betterfriends", label = "BetterFriendlist addon window", apply = SkinBetterFriends, addon = "BetterFriendlist" },
    { key = "communities", label = "Guild & Communities window", apply = SkinCommunities, addon = "Blizzard_Communities" },
    { key = "worldmap",  label = "World map", apply = SkinWorldMap },
    { key = "mail",      label = "Mailbox",   apply = SkinMail },
    { key = "trainer",   label = "Class trainer", apply = SkinTrainer, addon = "Blizzard_TrainerUI" },
    { key = "tradeskill", label = "Profession windows (Alchemy, Cooking...)", apply = SkinTradeSkill, addon = "Blizzard_TradeSkillUI" },
    { key = "trade",     label = "Player trade window", apply = SkinTrade },
    { key = "craft",     label = "Enchanting window", apply = SkinCraft, addon = "Blizzard_CraftUI" },
    { key = "inspect",   label = "Inspect window", apply = SkinInspect, addon = "Blizzard_InspectUI" },
    { key = "battleground", label = "Battleground queue and scoreboard", apply = SkinBattleground },
    { key = "dressup",   label = "Dressing room", apply = SkinDressUp },
    { key = "questie",   label = "Questie quest tracker", apply = SkinQuestie, addon = "Questie" },
    { key = "options",   label = "Game options and key bindings", apply = SkinOptions },
    { key = "chatconfig", label = "Chat settings window", apply = SkinChatConfig },
    { key = "taxi",      label = "Flight map", apply = SkinTaxi },
    { key = "smallwin",  label = "Small windows (stack split, ready check, color picker, breath bar)", apply = SkinSmallWindows },
    { key = "extras",    label = "Pet stable, tabard and charters", apply = SkinExtras },
    { key = "timemanager", label = "Clock and stopwatch", apply = SkinTimeManager, addon = "Blizzard_TimeManager" },
    { key = "addonlist", label = "AddOn list", apply = SkinAddonList, addon = "Blizzard_AddOnList" },
    { key = "bank",      label = "Bank window (Blizzard's)", apply = SkinBank },
    { key = "merchant",  label = "Vendor window", apply = SkinMerchant },
}

--------------------------------------------------------------------------------
-- Enable: skin what is already loaded, and skin load-on-demand windows when they arrive
--------------------------------------------------------------------------------
local function IsLoaded(addon)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn(addon)
end

local function Apply(entry)
    local ok, err = pcall(entry.apply)
    if not ok then CUI:Print("|cFFFF4040Skin '" .. entry.label .. "' failed:|r " .. tostring(err)) end
end

function Skins.Enable()
    local db = DB()
    for _, entry in ipairs(Skins.list) do
        if db[entry.key] and (not entry.addon or IsLoaded(entry.addon)) then Apply(entry) end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(_, _, addon)
        for _, entry in ipairs(Skins.list) do
            if entry.addon == addon and db[entry.key] then Apply(entry) end
        end
    end)
end

CUI:RegisterModule({
    key = "skins",
    name = "Skins",
    addon = "CysUI",
    desc = "Gold-and-dark look for Blizzard windows: Main Menu, Character, Spellbook, Talents, Macros, Quest Log, Loot window, NPC dialogs, Friends, BetterFriendlist and the Guild window.",
    onEnable = Skins.Enable,
    open = function() CUI:OpenConfig("Skins") end,
})

CUI:RegisterPage("Skins", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Border color", width):SetPoint("TOPLEFT", 0, -4)
    local swatches = {}
    local function RefreshSwatches()
        local cur = CysUIDB.borderColor or "gold"
        for key, b in pairs(swatches) do W.SetBorder(b.edges, key == cur and T.accent or T.line) end
    end
    for i, st in ipairs(W.AvailableBorderStyles()) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(90, 26)
        b:SetPoint("TOPLEFT", 4 + (i - 1) * 94, -34)
        W.Texture(b, "BACKGROUND", T.button):SetAllPoints()
        b.edges = W.Border(b, 1, T.line, "BORDER")
        local sw = W.Texture(b, "ARTWORK", W.BorderStyleColor(st.key))
        sw:SetSize(12, 12)
        sw:SetPoint("LEFT", 6, 0)
        local label = W.Text(b, 10, T.text)
        label:SetPoint("LEFT", 22, 0)
        label:SetText(st.label)
        b:SetScript("OnClick", function()
            CysUIDB.borderColor = st.key
            W.ApplyBorderStyle()
            RefreshSwatches()
        end)
        b:SetScript("OnEnter", function() W.SetBorder(b.edges, T.accent) end)
        b:SetScript("OnLeave", RefreshSwatches)
        swatches[st.key] = b
    end
    RefreshSwatches()
    local bnote = W.Text(page, 11, T.desc)
    bnote:SetPoint("TOPLEFT", 4, -70)
    bnote:SetWidth(width)
    bnote:SetText("Applies right away to every frame edge in Cys's UI and the skinned windows. If something keeps its old color, type /reload.")
    W.Header(page, "Skins", width):SetPoint("TOPLEFT", 0, -100)
    local y = -130
    for _, entry in ipairs(Skins.list) do
        local cb = W.Checkbox(page, entry.label, function() return db[entry.key] end,
            function(on) db[entry.key] = on end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end

    local note = W.Notes(page, 4, y - 8, width, "", {
            "Changes apply after a UI reload.",
            "A window that is skinned but looks wrong can simply be switched off here.",
            "Where the loot window opens is set on the Loot page.",
            "More windows (Map, vendors...) are added as they are tuned.",
            "Type /cysskin <FrameName> to list a window's art and children - handy when reporting one that needs work.",
        })
    page.contentHeight = -y + 120
end)

--------------------------------------------------------------------------------
-- /cysskin <FrameName>: dump a frame's textures and children (for tuning skins)
--------------------------------------------------------------------------------
SLASH_CYSSKIN1 = "/cysskin"
SlashCmdList["CYSSKIN"] = function(msg)
    local f = Get(strtrim and strtrim(msg or "") or msg)
    if not f or not f.GetRegions then
        CUI:Print("Usage: /cysskin FrameName   (use /fstack to find a window's name)")
        return
    end
    CUI:Print("Textures on " .. (f:GetName() or "?") .. ":")
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            print("  " .. tostring(r:GetName() or "(unnamed)") .. "  " .. tostring(r:GetTexture()))
        end
    end
    CUI:Print("Children:")
    for _, c in ipairs(Kids(f)) do
        print("  " .. tostring(c:GetName() or "(unnamed)") .. "  [" .. tostring(c:GetObjectType()) .. "]")
    end
end
