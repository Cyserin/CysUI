--------------------------------------------------------------------------------
-- Cys's UI - Action Bars
--
-- Keeps Blizzard's own action buttons (so paging, forms / stances, cooldowns, range
-- coloring, proc glows, drag and drop, macros and keybinds all keep working exactly as
-- the game does them) and takes over how they LOOK and WHERE they are. (The micro menu
-- and bag buttons belong to the Micro Menu / Info Bar / Bags addons, not this module.)
--
--   * every bar is a movable block (layout mode: /cui layout): Action Bars 1-8, Pet bar,
--     Stance bar
--   * buttons per row, button size and spacing per bar (1 row, 2 rows, a column...)
--   * flat dark buttons with a thin edge, short keybind text (S1, C2, A-F5, WU...),
--     optional hidden macro names, optional cooldown numbers
--   * optional "show only on mouseover" fade per bar (shown while you drag a spell too)
--   * Blizzard's gryphons and bar art hidden
--
-- Secure buttons can only be moved out of combat, so changes made during a fight wait
-- until it ends. Which bars exist is still the game's setting (Interface options >
-- Action Bars); a bar the game has switched off stays off.
--
-- If anything looks wrong: untick Action Bars under /cui > Modules and /reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local AB = {}
CUI.ActionBars = AB
AB.bars = {}
AB.pending = {}

--------------------------------------------------------------------------------
-- Settings (this module carries its own defaults)
--------------------------------------------------------------------------------
local function BarCfg(perRow, size, spacing)
    return { enabled = true, perRow = perRow, size = size, spacing = spacing or 4, fade = false }
end

local DEFAULTS = {
    art = true,            -- hide Blizzard's gryphons / bar art
    shortKeys = true,      -- S1 instead of s-1, WU instead of Mouse Wheel Up
    hideNames = true,      -- hide macro names on the buttons
    cooldownNumbers = true,
    showEmpty = true,      -- draw a dark slot behind every button, even empty ones
    goldBorders = true,    -- Cys gold edge on every slot (off = a quiet dark edge)
    blockEditMode = true,  -- Blizzard's HUD Edit Mode is switched off (it puts the old bars back); use /cui layout
    hideStatusBars = true, -- hide Blizzard's experience / reputation bars (Cys's XP bar replaces them)
    hideBagButtons = true, -- hide Blizzard's backpack / bag slot buttons (Cys's Bags has its own bag bar)
    bars = {
        main   = BarCfg(12, 36), bl = BarCfg(12, 36), br = BarCfg(12, 36),
        right  = BarCfg(1, 36),  right2 = BarCfg(1, 36),
        bar6   = BarCfg(12, 36), bar7 = BarCfg(12, 36), bar8 = BarCfg(12, 36),
        pet    = BarCfg(10, 30), stance = BarCfg(10, 30),
    },
}

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function EnsureDB()
    local firstRun = CysUIDB.actionbars == nil or CysUIDB.actionbars.bars == nil
    CysUIDB.actionbars = CysUIDB.actionbars or {}
    MergeDefaults(CysUIDB.actionbars, DEFAULTS)
    if firstRun then
        -- a fresh install starts like a fresh game: only the bars the game itself has switched on are shown
        local bars = CysUIDB.actionbars.bars
        local ok, bl, br, right, right2 = pcall(function() return GetActionBarToggles() end)
        if not ok then bl, br, right, right2 = false, false, false, false end
        bars.bl.enabled, bars.br.enabled = bl and true or false, br and true or false
        bars.right.enabled, bars.right2.enabled = right and true or false, right2 and true or false
        bars.bar6.enabled, bars.bar7.enabled, bars.bar8.enabled = false, false, false
    end
    return CysUIDB.actionbars
end

local function DB() return CysUIDB.actionbars end

--------------------------------------------------------------------------------
-- The bars: which Blizzard buttons, and where they start out
--------------------------------------------------------------------------------
local ORDER = { "main", "bl", "br", "right", "right2", "bar6", "bar7", "bar8", "pet", "stance" }
local DEFS = {
    main   = { label = "Action Bar 1", short = "Bar 1", prefix = "ActionButton", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 40 },
    bl     = { label = "Action Bar 2", short = "Bar 2", prefix = "MultiBarBottomLeftButton", blizz = "MultiBarBottomLeft", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 82 },
    br     = { label = "Action Bar 3", short = "Bar 3", prefix = "MultiBarBottomRightButton", blizz = "MultiBarBottomRight", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 124 },
    right  = { label = "Action Bar 4", short = "Bar 4", prefix = "MultiBarRightButton", blizz = "MultiBarRight", n = 12, skin = true,
               point = "RIGHT", x = -8, y = 0 },
    right2 = { label = "Action Bar 5", short = "Bar 5", prefix = "MultiBarLeftButton", blizz = "MultiBarLeft", n = 12, skin = true,
               point = "RIGHT", x = -52, y = 0 },
    bar6   = { label = "Action Bar 6", short = "Bar 6", prefix = "MultiBar5Button", blizz = "MultiBar5", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 208 },
    bar7   = { label = "Action Bar 7", short = "Bar 7", prefix = "MultiBar6Button", blizz = "MultiBar6", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 250 },
    bar8   = { label = "Action Bar 8", short = "Bar 8", prefix = "MultiBar7Button", blizz = "MultiBar7", n = 12, skin = true,
               point = "BOTTOM", x = 0, y = 292 },
    pet    = { label = "Pet Bar", short = "Pet", prefix = "PetActionButton", pet = true, n = 10, skin = true,
               point = "BOTTOM", x = 0, y = 166 },
    stance = { label = "Stance Bar", short = "Stance", prefix = "ShapeshiftButton", alt = "StanceButton", n = 10,
               skin = true, point = "BOTTOM", x = -330, y = 166 },
}

local function ButtonsFor(def)
    local list = {}
    if def.names then
        for _, name in ipairs(def.names) do
            if _G[name] then list[#list + 1] = _G[name] end
        end
    else
        for i = 1, def.n do
            local b = _G[def.prefix .. i] or (def.alt and _G[def.alt .. i])
            if b then list[#list + 1] = b end
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()

-- Park a Blizzard frame or texture where it can't be seen. The game (Edit Mode in particular) re-parents and
-- re-shows its bar pieces, so keep them parked: put them back if anything moves or shows them again.
local function Kill(obj)
    if not obj then return end
    if obj.UnregisterAllEvents then pcall(obj.UnregisterAllEvents, obj) end
    if obj.SetParent then obj:SetParent(hidden) end
    if obj.Hide then obj:Hide() end
    if not obj.cysKilled and hooksecurefunc and obj.SetParent and obj.Show then
        obj.cysKilled = true
        local function safe(self, fn)
            if InCombatLockdown() and self.IsProtected and self:IsProtected() then return end
            pcall(fn)
        end
        pcall(hooksecurefunc, obj, "SetParent", function(self, parent)
            if parent ~= hidden then safe(self, function() self:SetParent(hidden) end) end
        end)
        pcall(hooksecurefunc, obj, "Show", function(self) safe(self, function() self:Hide() end) end)
    end
end

-- A named piece of a Blizzard button ("Icon", "HotKey", "Count", "Name"...)
local function Part(button, suffix)
    local name = button:GetName()
    return (name and _G[name .. suffix]) or button[suffix] or button[suffix:lower()]
end

local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        AB.problems = (AB.problems or 0) + 1
        if AB.problems <= 3 then CUI:Print("|cFFFF9F43Action Bars: " .. label .. " skipped (" .. tostring(err) .. ")|r") end
    end
    return ok
end

--------------------------------------------------------------------------------
-- Keybind text
--------------------------------------------------------------------------------
local KEY_NAMES = {
    ["Mouse Wheel Up"] = "WU", ["Mouse Wheel Down"] = "WD", ["Middle Mouse"] = "M3", ["Mouse Button "] = "M",
    ["Num Pad "] = "N", ["Page Up"] = "PU", ["Page Down"] = "PD", ["Spacebar"] = "Sp", ["Insert"] = "Ins",
    ["Delete"] = "Del", ["Home"] = "Hm", ["End"] = "En",
}

local function Shorten(text)
    for long, short in pairs(KEY_NAMES) do text = text:gsub(long, short) end
    text = text:gsub("s%-", "S"):gsub("c%-", "C"):gsub("a%-", "A")
    text = text:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
    return text
end

local function UpdateKeyText(button)
    local hk = Part(button, "HotKey")
    if not hk then return end
    local text = hk:GetText()
    if text and text ~= "" and text ~= RANGE_INDICATOR then hk:SetText(Shorten(text)) end
end

--------------------------------------------------------------------------------
-- Button look
--------------------------------------------------------------------------------
local function SkinButton(b)
    if b.cysSkinned then return end
    b.cysSkinned = true

    local normal = b.GetNormalTexture and b:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    local icon = Part(b, "Icon")
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end

    local hk = Part(b, "HotKey")
    if hk then
        hk:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        hk:ClearAllPoints()
        hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -2)
    end
    local count = Part(b, "Count")
    if count then
        count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    end

    -- Blizzard's red "attack" flash (auto-attack and /startattack macros) becomes a gold pulse on the slot's edge
    local flash = Part(b, "Flash")
    if flash and hooksecurefunc then
        flash:SetAlpha(0)
        hooksecurefunc(flash, "Show", function()
            local s = b.cysSlot
            if s then W.SetBorder(s.edges, T.accent) end
        end)
        hooksecurefunc(flash, "Hide", function()
            local s = b.cysSlot
            if s then W.SetBorder(s.edges, DB().goldBorders and T.border or T.line) end
        end)
    end

    local pushed = b.GetPushedTexture and b:GetPushedTexture()
    if pushed then pushed:SetColorTexture(1, 1, 1, 0.25) end
    local checked = b.GetCheckedTexture and b:GetCheckedTexture()
    if checked then checked:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.3) end
    local highlight = b.GetHighlightTexture and b:GetHighlightTexture()
    if highlight then highlight:SetColorTexture(1, 1, 1, 0.18) end

    if DB().hideNames then
        local name = Part(b, "Name")
        if name then name:Hide() end
    end
    if DB().shortKeys then UpdateKeyText(b) end
end

--------------------------------------------------------------------------------
-- Laying a bar out
--------------------------------------------------------------------------------
-- Blizzard's buttons live inside frames that can have their own scale; give each button the
-- scale that makes it the same size as everything else on screen.
local function NormalScale(b)
    local parent = b:GetParent()
    local parentScale = parent and parent:GetEffectiveScale() or 1
    if not parentScale or parentScale <= 0 then return 1 end
    return UIParent:GetEffectiveScale() / parentScale
end

-- Re-apply every slot edge whenever the Border color setting changes, so Gold (and every other choice) always lands on the bars
W.OnBorderStyle(function()
    for _, bar in pairs(AB.bars) do
        for _, slot in ipairs(bar.slots or {}) do
            W.SetBorder(slot.edges, DB().goldBorders and T.border or T.line)
        end
    end
end)

function AB:LayoutBar(key)
    local bar = self.bars[key]
    if not bar then return end
    if InCombatLockdown() then
        self.pending[key] = true
        return
    end
    local def, cfg = bar.def, DB().bars[key]
    if not cfg.enabled then return end
    local list = ButtonsFor(def)
    local n = #list
    if def.alt then
        -- stance bar: only as many buttons as you have stances / forms (none for most classes)
        n = min(n, GetNumShapeshiftForms and GetNumShapeshiftForms() or n)
        if n == 0 then
            bar.container:SetSize(cfg.size, cfg.size) -- keep a small box to grab in layout mode
            bar.container:Hide()
            for _, s in ipairs(bar.slots) do s:Hide() end
            CUI:ApplyLayout("bar_" .. key)
            return
        end
        bar.container:Show()
    elseif def.pet then
        -- pet bar: only while you have a pet
        if UnitExists and not UnitExists("pet") then
            bar.container:SetSize(cfg.size, cfg.size) -- keep a small box to grab in layout mode
            bar.container:Hide()
            for _, s in ipairs(bar.slots) do s:Hide() end
            CUI:ApplyLayout("bar_" .. key)
            return
        end
        bar.container:Show()
    end
    if n == 0 then return end

    local perRow = max(1, min(cfg.perRow, n))
    local rows = ceil(n / perRow)
    local w, h, gap
    if def.keepSize then
        w, h = list[1]:GetWidth(), list[1]:GetHeight() -- micro / bag buttons keep their own shape
        gap = cfg.spacing
    else
        w, h, gap = cfg.size, cfg.size, cfg.spacing
    end
    bar.container:SetSize(perRow * w + (perRow - 1) * gap, rows * h + (rows - 1) * gap)

        for i = 1, n do
        local b = list[i]
        local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetScale(NormalScale(b))
        if not def.keepSize then b:SetSize(w, h) end
        b:SetPoint("TOPLEFT", bar.container, "TOPLEFT", col * (w + gap), -row * (h + gap))
        if def.skin then Guard(key .. " button", SkinButton, b) end
        if (def.blizz or key == "main") and DB().showEmpty and not b.cysGrid then
            b.cysGrid = true -- ask the game to draw empty slots too
            b:SetAttribute("showgrid", 1)
            if ActionButton_ShowGrid then pcall(ActionButton_ShowGrid, b) end
        end

        -- a dark slot behind the button, owned by us, so empty slots stay visible
        local slot = bar.slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, bar.container)
            slot:SetFrameStrata("BACKGROUND")
            W.Texture(slot, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.85 }):SetAllPoints()
            -- the edge sits one pixel outside the slot so it stays two pixels thick around the icon
            local host = CreateFrame("Frame", nil, slot)
            host:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1)
            host:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
            slot.edges = W.Border(host, 2, DB().goldBorders and T.border or T.line, "BORDER")
            bar.slots[i] = slot
        end
        b.cysSlot = slot
        slot:ClearAllPoints()
        slot:SetSize(w, h)
        slot:SetPoint("TOPLEFT", bar.container, "TOPLEFT", col * (w + gap), -row * (h + gap))
        W.SetBorder(slot.edges, DB().goldBorders and T.border or T.line)
        slot:SetShown(def.skin and DB().showEmpty)
    end
    for i = n + 1, #bar.slots do bar.slots[i]:Hide() end
    bar.buttons = list
    CUI:ApplyLayout("bar_" .. key) -- resize the layout-mode box to match
    self:SetupFade(key)
end

--------------------------------------------------------------------------------
-- Mouseover fade
--------------------------------------------------------------------------------
local function SetBarAlpha(bar, alpha)
    bar.alpha = alpha
    for _, b in ipairs(bar.buttons or {}) do b:SetAlpha(alpha) end
    for _, s in ipairs(bar.slots or {}) do s:SetAlpha(alpha) end
end

local function MouseIsOverBar(bar)
    local c = bar.container
    if c.IsMouseOver then return c:IsMouseOver() end
    return MouseIsOver and MouseIsOver(c) or false
end

local function FadeTick(bar)
    -- stay visible while the mouse is on the bar, or while you're carrying a spell / item / macro
    local show = MouseIsOverBar(bar) or (GetCursorInfo and GetCursorInfo() ~= nil)
    local target = show and 1 or 0
    local current = bar.alpha or 1
    if math.abs(target - current) < 0.05 then current = target else current = current + (target - current) * 0.5 end
    if current ~= bar.alpha then SetBarAlpha(bar, current) end
end

function AB:SetupFade(key)
    local bar = self.bars[key]
    if not bar then return end
    if DB().bars[key].fade then
        bar.acc = 0
        bar.container:SetScript("OnUpdate", function(_, elapsed)
            bar.acc = bar.acc + elapsed
            if bar.acc < 0.05 then return end
            bar.acc = 0
            FadeTick(bar)
        end)
    else
        bar.container:SetScript("OnUpdate", nil)
        SetBarAlpha(bar, 1)
    end
end

--------------------------------------------------------------------------------
-- Global switches
--------------------------------------------------------------------------------
-- Blizzard's Edit Mode draws a blue selection box over each of its bars and keeps the bars' own frames
-- around at their old spots. CysUI's layout mode replaces all of it, so these are switched off: no selection
-- boxes, and the old bar frames no longer take mouse clicks away from the real buttons.
local EDIT_FRAMES = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
                      "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar",
                      "MainMenuBarArtFrame", "OverrideActionBar", "ExtraAbilityContainer", "MicroMenu",
                      "MicroMenuContainer", "BagsBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
                      "SecondaryStatusTrackingBarContainer", "MultiCastActionBarFrame" }
local function Noop() end
function AB:NeutralizeEditMode()
    for _, name in ipairs(EDIT_FRAMES) do
        local f = _G[name]
        if f then
            pcall(function()
                f.HighlightSystem = Noop
                f.SelectSystem = Noop
                local sel = f.Selection
                if sel then
                    sel:Hide()
                    if sel.EnableMouse then sel:EnableMouse(false) end
                    if not sel.cysQuiet and hooksecurefunc then
                        sel.cysQuiet = true
                        hooksecurefunc(sel, "Show", function(self) self:Hide() end)
                    end
                end
                if not InCombatLockdown() and f.EnableMouse then f:EnableMouse(false) end
            end)
        end
    end
end

local STATUS_BARS = { "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "ExhaustionTick",
                      "StatusTrackingBarManager" }

function AB:HideStatusBars()
    for _, name in ipairs(STATUS_BARS) do Kill(_G[name]) end
end
local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                      "CharacterBag3Slot", "KeyRingButton" }

function AB:HideBagButtons()
    for _, name in ipairs(BAG_BUTTONS) do Kill(_G[name]) end
end
local ART = { "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarTexture0", "MainMenuBarTexture1",
              "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarPageNumber", "ActionBarUpButton",
              "ActionBarDownButton", "MainMenuBarPerformanceBarFrame", "ShapeshiftBarLeft", "ShapeshiftBarMiddle",
              "ShapeshiftBarRight", "StanceBarLeft", "StanceBarMiddle", "StanceBarRight", "SlidingActionBarTexture0",
              "SlidingActionBarTexture1" }

-- Blizzard's page arrows, page number and end caps sit in different places on different client
-- versions. Look through the main bar's frames for anything named like them and tuck it away.
local ART_WORDS = { "PageNumber", "UpButton", "DownButton", "EndCap", "BorderArt" }
local function LooksLikeArt(name)
    if type(name) ~= "string" then return false end
    for _, w in ipairs(ART_WORDS) do if name:find(w) then return true end end
    return false
end
local function SweepFrame(frame, depth)
    if not frame or depth > 3 or not frame.GetChildren then return end
    for key, value in pairs(frame) do
        if LooksLikeArt(key) and type(value) == "table" and value.GetObjectType then Kill(value) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local name = child.GetName and child:GetName()
        if LooksLikeArt(name) then
            Kill(child)
        elseif not (name and (name:find("^ActionButton") or name:find("^MultiBar"))) then
            SweepFrame(child, depth + 1)
        end
    end
end
function AB:SweepArt()
    if not DB().art or InCombatLockdown() then return end
    for _, parent in ipairs({ _G.MainMenuBar, _G.MainMenuBarArtFrame }) do SweepFrame(parent, 0) end
end

function AB:ApplyCooldownNumbers()
    pcall(SetCVar, "countdownForCooldowns", DB().cooldownNumbers and "1" or "0")
end

function AB:ApplyNames()
    for _, bar in pairs(self.bars) do
        for _, b in ipairs(bar.buttons or {}) do
            local name = Part(b, "Name")
            if name then
                if DB().hideNames then name:Hide() else name:Show() end
            end
        end
    end
end

function AB:RefreshKeys()
    for _, bar in pairs(self.bars) do
        for _, b in ipairs(bar.buttons or {}) do
            if ActionButton_UpdateHotkeys then pcall(ActionButton_UpdateHotkeys, b, b.buttonType) end
            if DB().shortKeys then UpdateKeyText(b) end
        end
    end
end
-- Turn a bar on or off right now (no reload). Off = its buttons are tucked away in a hidden
-- frame and handed back to Blizzard's bar when you turn it on again.
function AB:ApplyEnabled(key)
    local bar = self.bars[key]
    if not bar then return end
    if InCombatLockdown() then
        self.pending[key] = true
        return
    end
    local on = DB().bars[key].enabled
    local m = CUI.movers and CUI.movers["bar_" .. key]
    if m then
        m.disabled = not on
        if m.mover and CUI.layoutMode then m.mover:SetShown(on) end
    end
    local list = ButtonsFor(bar.def)
    if on then
        for _, b in ipairs(list) do
            b.cysOrig = b.cysOrig or b:GetParent()
            if bar.def.blizz then
                -- Bars 2-8 become ours: we show them ourselves, so it no longer matters whether
                -- they are ticked in the game's own Action Bars options.
                b:SetParent(bar.container)
                b:Show()
            else
                b:SetParent(b.cysOrig) -- bar 1 / pet / stance must stay with Blizzard's bar (paging)
            end
        end
        bar.container:Show()
        self:LayoutBar(key)
    else
        bar.container:Hide()
        for _, slot in ipairs(bar.slots) do slot:Hide() end
        for _, b in ipairs(list) do
            b.cysOrig = b.cysOrig or b:GetParent()
            b:SetParent(hidden)
        end
    end
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
local function BuildBar(key)
    local def = DEFS[key]
    local container = CreateFrame("Frame", "CysUIBar_" .. key, UIParent)
    container:SetSize(def.n and (def.n * 40) or 200, 40)
    AB.bars[key] = { def = def, container = container, buttons = {}, slots = {}, alpha = 1 }
        -- the same sliders as the settings page, right in layout mode
    local function Field(name, label, lo, hi)
        return { label = label, min = lo, max = hi,
                 get = function() return DB().bars[key][name] end,
                 set = function(v) DB().bars[key][name] = v; AB:LayoutBar(key) end }
    end
    CUI:RegisterMovable(container, "bar_" .. key, def.label,
        { point = def.point, x = def.x, y = def.y, scalable = false,
          extras = { Field("perRow", "Buttons per row", 1, def.n or 12), Field("size", "Button size", 20, 64),
                     Field("spacing", "Spacing", 0, 16) } })
    AB:LayoutBar(key)
end

function AB.Enable()
    local db = EnsureDB()
    if InCombatLockdown() then
        CUI:Print("|cFFFF9F43Action Bars: can't start in combat. Reload out of combat.|r")
        return
    end

    for _, key in ipairs(ORDER) do
        Guard(key, BuildBar, key)
        Guard(key, function() AB:ApplyEnabled(key) end)
    end
    if db.art then
        for _, name in ipairs(ART) do Kill(_G[name]) end
        -- the stance bar's own dark background art (shows as two empty boxes on classes with no stances)
        if _G.StanceBar then
            for _, k in ipairs({ "BackgroundArtLeft", "BackgroundArtMiddle", "BackgroundArtRight" }) do Kill(_G.StanceBar[k]) end
        end
        -- newer client layouts keep the gryphons, background and page arrows as parts of the main bar
        for _, parent in ipairs({ _G.MainMenuBar, _G.MainMenuBarArtFrame, _G.MainActionBar }) do
            if parent then
                for _, k in ipairs({ "ActionBarPageNumber", "PageNumber", "UpButton", "DownButton", "EndCaps",
                                     "ActionBarUpButton", "ActionBarDownButton",
                                     "LeftEndCap", "RightEndCap", "BorderArt", "Background" }) do
                    Kill(parent[k])
                end
            end
        end
    end
    if db.hideStatusBars then AB:HideStatusBars() end
    AB:SweepArt()
    -- Blizzard's HUD Edit Mode redraws every old bar (and the page number and stance slots) over the screen
    -- and takes clicks from the real buttons. CysUI has its own layout mode, so Edit Mode just closes again.
    if EditModeManagerFrame and EditModeManagerFrame.HookScript and not AB.editHooked then
        AB.editHooked = true
        EditModeManagerFrame:HookScript("OnShow", function(self)
            if not DB().blockEditMode or InCombatLockdown() then return end
            if AB.editBlockedAt and GetTime() - AB.editBlockedAt < 2 then return end
            AB.editBlockedAt = GetTime()
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                local ok = pcall(function() if self.ExitEditMode then self:ExitEditMode() end end)
                if self:IsShown() then pcall(HideUIPanel, self) end
                if self:IsShown() then self:Hide() end
                CUI:Print("Blizzard's Edit Mode is turned off by Cys's UI. Use |cFFFFD100/cui layout|r to move things "
                    .. "(Action Bars page: untick the Edit Mode option to bring it back).")
            end)
        end)
    end
    AB:NeutralizeEditMode()
    C_Timer.After(2, function() if not InCombatLockdown() then AB:NeutralizeEditMode() end end)
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnShow", function()
            if not InCombatLockdown() then AB:NeutralizeEditMode() end
        end)
    end
    if db.hideBagButtons then AB:HideBagButtons() end
    AB:ApplyCooldownNumbers()

    -- Blizzard re-applies its own button art and key text when a button updates
    if ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(self)
            if self.cysSkinned then
                local normal = self:GetNormalTexture()
                if normal then normal:SetAlpha(0) end
            end
        end)
    end
    if ActionButton_UpdateHotkeys then
        hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
            if self.cysSkinned and DB().shortKeys then UpdateKeyText(self) end
        end)
    end
    if PetActionBar_Update then
        hooksecurefunc("PetActionBar_Update", function()
            for _, b in ipairs(ButtonsFor(DEFS.pet)) do
                if b.cysSkinned then
                    local normal = b:GetNormalTexture()
                    if normal then normal:SetAlpha(0) end
                end
            end
        end)
    end

    -- Stance / form changes and the first moments after login can leave button icons un-drawn until the mouse
    -- passes over them (macros that name stance spells especially). Ask each action button to redraw itself.
    local refreshQueued
    local function RefreshButtons()
        refreshQueued = false
        -- the game's own "redraw every action bar" routine, when this client has it
        if ActionBarController_UpdateAll then pcall(ActionBarController_UpdateAll, true) end
        for _, def in pairs(DEFS) do
            if def.prefix and def.skin and not def.pet and not def.alt then
                for _, b in ipairs(ButtonsFor(def)) do
                    -- newer clients give each button its own methods; older ones use global functions
                    if b.UpdateAction then pcall(b.UpdateAction, b, true)
                    elseif ActionButton_UpdateAction then pcall(ActionButton_UpdateAction, b, true) end
                    if b.Update then pcall(b.Update, b)
                    elseif ActionButton_Update then pcall(ActionButton_Update, b) end
                end
            end
        end
    end
    local function QueueRefresh(delay)
        if C_Timer and C_Timer.After then
            if delay then C_Timer.After(delay, RefreshButtons)
            elseif not refreshQueued then refreshQueued = true; C_Timer.After(0.05, RefreshButtons) end
        end
    end

    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE", "UNIT_PET", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
                          "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_BONUS_ACTIONBAR" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
            QueueRefresh()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            QueueRefresh(0.5); QueueRefresh(1.5); QueueRefresh(4)
        end
        if event == "PLAYER_REGEN_ENABLED" then
            for key in pairs(AB.pending) do
                AB.pending[key] = nil
                AB:ApplyEnabled(key)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, function() for _, key in ipairs(ORDER) do AB:LayoutBar(key) end; AB:SweepArt() end)
        else
            C_Timer.After(0.2, function() AB:LayoutBar("stance"); AB:LayoutBar("pet") end)
        end
    end)
end

CUI:RegisterModule({
    key = "actionbars",
    name = "Action Bars",
    addon = "CysUI",
    desc = "Movable, resizable flat action bars 1-8, pet and stance bars, using Blizzard's own buttons.",
    onEnable = AB.Enable,
    open = function() CUI:OpenConfig("Action Bars") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Action Bars", function(page)
    local db = EnsureDB()
    local width = 480
    local selected = "main"

    W.Header(page, "Bars", width):SetPoint("TOPLEFT", 0, -4)
    local picks = {}
    local controls = {}
    local function Cfg() return db.bars[selected] end

    local function Apply()
        if InCombatLockdown() then CUI:Print("In combat: the change will apply when it ends.") end
        AB:LayoutBar(selected)
    end
    local function Refresh()
        for key, b in pairs(picks) do b:SetPrimary(key == selected) end
        for _, c in ipairs(controls) do c:Refresh() end  
    end

    for i, key in ipairs(ORDER) do
        local b = W.Button(page, 80, 22, DEFS[key].short)
        b:SetPoint("TOPLEFT", ((i - 1) % 5) * 84, -32 - floor((i - 1) / 5) * 26)
        b:SetScript("OnClick", function() selected = key; Refresh() end)
        picks[key] = b
    end

    local enabled = W.Button(page, 260, 22, "")
    function enabled:Refresh()
        self:SetLabel(Cfg().enabled and "This bar is ON  (click to turn off)" or "This bar is OFF  (click to turn on)")
        self:SetPrimary(Cfg().enabled)
    end
    enabled:SetPoint("TOPLEFT", 4, -98)
    enabled:SetScript("OnClick", function()
        Cfg().enabled = not Cfg().enabled
        if InCombatLockdown() then CUI:Print("In combat: the change will apply when it ends.") end
        AB:ApplyEnabled(selected)
        Refresh()
    end)
    local fade = W.Checkbox(page, "Show only on mouseover", function() return Cfg().fade end,
        function(on) Cfg().fade = on; AB:SetupFade(selected) end)
    fade:SetPoint("TOPLEFT", 4, -124)
    local perRow = W.Stepper(page, "Buttons per row", function() return Cfg().perRow end,
        function(v) Cfg().perRow = v; Apply() end, 1, 13, 1)
    perRow:SetPoint("TOPLEFT", 4, -154)
    local size = W.Stepper(page, "Button size", function() return Cfg().size end,
        function(v) Cfg().size = v; Apply() end, 20, 64, 2)
    size:SetPoint("TOPLEFT", 4, -182)
    local spacing = W.Stepper(page, "Spacing", function() return Cfg().spacing end,
        function(v) Cfg().spacing = v; Apply() end, 0, 16, 1)
    spacing:SetPoint("TOPLEFT", 4, -210)
    controls[1], controls[2], controls[3], controls[4], controls[5] = enabled, fade, perRow, size, spacing
    controls.size = size

    W.Header(page, "All bars", width):SetPoint("TOPLEFT", 0, -262)
    local y = -292
    local function Check(label, key, onSet)
        local cb = W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; if onSet then onSet() end end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    Check("Short key text (S1, C2, WU)", "shortKeys", function() AB:RefreshKeys() end)
    Check("Show empty slots", "showEmpty", function() for key in pairs(AB.bars) do AB:LayoutBar(key) end end)
    Check("Gold borders", "goldBorders", function() for key in pairs(AB.bars) do AB:LayoutBar(key) end end)
    Check("Hide the experience and reputation bars (turning off needs a /reload)", "hideStatusBars",
        function() if DB().hideStatusBars then AB:HideStatusBars() end end)
    Check("Hide Blizzard's bag buttons (turning off needs a /reload)", "hideBagButtons",
        function() if DB().hideBagButtons then AB:HideBagButtons() end end)
    Check("Turn off Blizzard's Edit Mode (use /cui layout instead)", "blockEditMode")
    Check("Hide macro names", "hideNames", function() AB:ApplyNames() end)
    Check("Show cooldown numbers", "cooldownNumbers", function() AB:ApplyCooldownNumbers() end)
    Check("Hide Blizzard's gryphons and bar art (needs a /reload)", "art")

    local move = W.Button(page, 240, 22, "Move the bars (layout mode)")
    move:SetPoint("TOPLEFT", 4, y - 10)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)

    -- one click to do what a fresh install does: show only the bars the game itself has switched on
    local match = W.Button(page, 330, 22, "Match the game's bars (turns off the rest)")
    match:SetPoint("TOPLEFT", 4, y - 38)
    match:SetScript("OnClick", function()
        local ok, bl, br, right, right2 = pcall(function() return GetActionBarToggles() end)
        if not ok then CUI:Print("Could not read the game's action bar settings.") return end
        local want = { bl = bl, br = br, right = right, right2 = right2, bar6 = false, bar7 = false, bar8 = false }
        for key, on in pairs(want) do
            if DB().bars[key] then
                DB().bars[key].enabled = on and true or false
                AB:ApplyEnabled(key)
            end
        end
        CUI:Print("Action bars now match the game's own Action Bars settings. Turn any bar back on from the list on the left.")
        Refresh()
    end)

    local note = W.Notes(page, 4, y - 82, width, "These are still Blizzard's own buttons, so everything the game does with them keeps working.", {
            "Changes made in combat apply when it ends.",
            "New installs start with only the bars the game itself has switched on; the button above does the same for an existing setup.",
            "To go back to Blizzard's layout, untick Action Bars under Modules and reload.",
        })
    Refresh()
end)

--------------------------------------------------------------------------------
-- /cuiab: prints what the first action buttons hold, for tracking down bars that stay blank after login
--------------------------------------------------------------------------------
SLASH_CUIAB1 = "/cuiab"
SlashCmdList["CUIAB"] = function()
    local function P(...) print("|cFFFFD100CysUI bars:|r", ...) end
    P("stance form", tostring(GetShapeshiftForm and GetShapeshiftForm()), "bonus offset", tostring(GetBonusBarOffset and GetBonusBarOffset()),
      "bar page", tostring(GetActionBarPage and GetActionBarPage()))
    for i = 1, 4 do
        local b = _G["ActionButton" .. i]
        if b then
            local calc = ActionButton_CalculateAction and ActionButton_CalculateAction(b)
            local act = b.action
            local par = b:GetParent()
            P("ActionButton" .. i, "attr action=" .. tostring(b:GetAttribute("action")), "b.action=" .. tostring(act),
              "calc=" .. tostring(calc), "icon=" .. tostring(act and GetActionTexture and GetActionTexture(act)),
              "calcIcon=" .. tostring(calc and GetActionTexture and GetActionTexture(calc)),
              "parent=" .. tostring(par and (par:GetName() or "?")), "shown=" .. tostring(b:IsShown()),
              "useparent=" .. tostring(b:GetAttribute("useparent-actionpage")), "parentPage=" .. tostring(par and par:GetAttribute("actionpage")))
        end
    end
end
