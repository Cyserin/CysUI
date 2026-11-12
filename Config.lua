--------------------------------------------------------------------------------
-- Cys's UI - the /cui settings window
--
-- Sidebar of pages on the left, the page on the right. Built-in pages: General and
-- Modules. Addons add their own with CysUI:RegisterPage("Title", function(page) ... end).
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format = string.format
local max = math.max

local WIDTH, HEIGHT = 700, 560
local SIDEBAR_W, HEADER_H, FOOTER_H, PAD = 170, 34, 40, 16
local CONTENT_W = WIDTH - SIDEBAR_W - PAD * 2 - 2
local VIEW_H = HEIGHT - HEADER_H - FOOTER_H - PAD * 2 - 2 -- visible height of a page

-- sidebar grouping: { heading (nil = none), { page titles in order } }
local GROUPS = {
    { nil,               { "General", "Modules", "Conflicts" } },
    { "Interface",       { "UI Scale", "Chat", "Info Bar", "Micro Menu", "Minimap", "Minimap Button", "Tooltip", "Skins", "Friends", "Durability", "Automation" } },
    { "Frames & Combat", { "Unit Frames", "Raid Frames", "Cast Bar", "Nameplates", "Action Bars", "PlayerAuras", "Damage Meter", "Details Skin", "Swing Timer", "Combat Numbers", "Threat Bar" } },
    { "Loot & Items",    { "Vendor", "Consumables", "Loot", "Roll Tracker", "Upgrade" } },
    { "Tracking",        { "Quest Tracker", "Kill Tracker", "XP Bar", "Characters", "Skill Tracker", "Raid Debuffs", "Combat Log", "Taunt Alert", "Missing Buffs" } },
}

-- Class pages live under CLASS: a General page (works for every class), then a heading for your own class
-- (in its class color) with that class's pages under it. Only your own class is listed.
local CLASS_GENERAL = { "Level-Up Spells", "Spell Ranks", "Heal Advisor" }
local LABELS = {} -- sidebar text when it differs from the page title
-- Classic still uses the old pink for Shamans; the game's newer clients use blue, so we do too.
local CLASSES = {
    { "DRUID", "Druid", 1.00, 0.49, 0.04 },     { "HUNTER", "Hunter", 0.67, 0.83, 0.45 },
    { "MAGE", "Mage", 0.41, 0.80, 0.94 },       { "PALADIN", "Paladin", 0.96, 0.55, 0.73 },
    { "PRIEST", "Priest", 1.00, 1.00, 1.00 },   { "ROGUE", "Rogue", 1.00, 0.96, 0.41 },
    { "SHAMAN", "Shaman", 0.00, 0.44, 0.87 },   { "WARLOCK", "Warlock", 0.58, 0.51, 0.79 },
    { "WARRIOR", "Warrior", 0.78, 0.61, 0.43 },
}

local window
local pageButtons, pageFrames = {}, {}
local current

--------------------------------------------------------------------------------
-- Footer: Reload button lights up gold when a change needs a reload
--------------------------------------------------------------------------------
local function UpdateFooter()
    if not window then return end
    local pending = CUI:HasPendingReload()
    window.reload:SetPrimary(pending)
    window.hint:SetText(pending and "|cFFFFD100Changes need a UI reload to take effect.|r" or "")
end

--------------------------------------------------------------------------------
-- General page
--------------------------------------------------------------------------------
local function AddonList()
    local list, seen = { "CysUI" }, { CysUI = true }
    for _, key in ipairs(CUI.order) do
        local addon = CUI.modules[key].addon
        if addon and not seen[addon] and CUI:IsAddonLoaded(addon) then
            seen[addon] = true
            list[#list + 1] = addon
        end
    end
    return list
end

-- memory sizes: KB below 1 MB, then MB with one decimal
local function FmtMem(kb)
    if kb >= 1024 then return format("%.1f MB", kb / 1024) end
    return format("%.0f KB", kb)
end
-- green = light, yellow = getting heavy, red = a lot for a weaker PC (total addon memory, in MB)
local MEM_YELLOW, MEM_RED = 50, 100
local function MemColor(kb)
    local mb = kb / 1024
    if mb >= MEM_RED then return T.danger, "Heavy" end
    if mb >= MEM_YELLOW then return T.accent, "Getting heavy" end
    return T.green, "Light"
end
local function Hex(c) return format("|cFF%02X%02X%02X", c[1] * 255, c[2] * 255, c[3] * 255) end

local function RefreshMemory(page)
    if not (page and page.memNames) then return end
    CUI:UpdateMemory()
    local names, values, total = {}, {}, 0
    for _, addon in ipairs(AddonList()) do
        local kb = CUI:GetMemoryKB(addon)
        names[#names + 1] = addon
        values[#values + 1] = kb and FmtMem(kb) or "-"
        total = total + (kb or 0)
    end
    names[#names + 1] = "|cFFFFD100Total|r"
    values[#values + 1] = "|cFFFFD100" .. FmtMem(total) .. "|r"
    page.memNames:SetText(table.concat(names, "\n"))
    page.memValues:SetText(table.concat(values, "\n"))
    local col, word = MemColor(total)
    page.memStatus:SetText(format("%s%s|r   %s%s|r", Hex(col), FmtMem(total), Hex(col), word))
end

local function ModuleCounts()
    local on, all = 0, 0
    for _, key in ipairs(CUI.order) do
        local def = CUI.modules[key]
        if CUI:ClassAllowed(def) then
            all = all + 1
            if CUI:IsModuleEnabled(key) then on = on + 1 end
        end
    end
    return on, all
end

-- a one-line box with text you can select and copy
local function CopyField(parent, width, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 22)
    W.Texture(f, "BACKGROUND", T.field):SetAllPoints()
    W.Border(f, 1, T.line, "BORDER")
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT", 6, 0)
    eb:SetPoint("BOTTOMRIGHT", -6, 0)
    eb:SetFont(STANDARD_TEXT_FONT, 11, "")
    eb:SetTextColor(T.text[1], T.text[2], T.text[3])
    eb:SetAutoFocus(false)
    eb:SetText(text)
    eb:SetCursorPosition(0)
    eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(text); s:HighlightText() end end)
    eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return f
end

CUI:RegisterPage("General", function(page)
    local title = W.Text(page, 18, T.accent)
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetText("Cys's UI")
    local ver = W.Text(page, 11, T.desc)
    ver:SetPoint("LEFT", title, "RIGHT", 8, -2)
    ver:SetText("v" .. CUI:GetVersion("CysUI")
        .. (CUI.newerVersion and ("   |cFF6CB6FFv" .. CUI.newerVersion .. " is out|r") or ""))

    local desc = W.Text(page, 12, T.text)
    desc:SetPoint("TOPLEFT", 0, -34)
    desc:SetWidth(CONTENT_W)
    desc:SetJustifyV("TOP")
    desc:SetSpacing(3)
    desc:SetText("A light, minimal UI made of small addons that share one look. "
        .. "Turn the pieces you want on or off under |cFFFFD100Modules|r. Type |cFFFFD100/cui|r any time to come back here.")

    local on, all = ModuleCounts()
    local client = W.Text(page, 11, T.desc)
    client:SetPoint("TOPLEFT", 0, -84)
    client:SetText(format("Client: |cFFE0E0E0%s|r (interface %d)    Modules on: |cFFE0E0E0%d of %d|r", CUI.flavor, CUI.interface, on, all))

    local layoutHeader = W.Header(page, "Layout", CONTENT_W)
    layoutHeader:SetPoint("TOPLEFT", 0, -112)
    local unlock = W.Button(page, 200, 22, "Layout mode: move and resize")
    unlock:SetPoint("TOPLEFT", 4, -140)
    unlock:SetScript("OnClick", function() CUI:ToggleLayout() end)
    local resetAll = W.Button(page, 140, 22, "Reset all positions")
    resetAll:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
    resetAll:SetScript("OnClick", function() CUI:ResetAllMovers() end)
    local stack = W.Checkbox(page, "Open windows side by side like Blizzard's (reload)",
        function() return CysUIDB.stackWindows ~= false end,
        function(v) CysUIDB.stackWindows = v and true or false end)
    stack:SetPoint("TOPLEFT", 4, -170)
    local menuBtn = W.Checkbox(page, "Cys's UI button in the Esc menu (reload)",
        function() return CysUIDB.menuButton ~= false end,
        function(v) CysUIDB.menuButton = v and true or false end)
    menuBtn:SetPoint("TOPLEFT", 4, -192)

    local memHeader = W.Header(page, "Memory use", CONTENT_W)
    memHeader:SetPoint("TOPLEFT", 0, -212)
    page.memStatus = W.Text(page, 16, T.text)
    page.memStatus:SetPoint("TOPLEFT", 4, -238)
    local legend = W.Text(page, 10, T.desc)
    legend:SetPoint("TOPLEFT", 4, -262)
    legend:SetWidth(CONTENT_W - 12)
    legend:SetJustifyV("TOP")
    legend:SetSpacing(2)
    legend:SetText(format("|cFF59D959Green|r under %d MB   |cFFFFD100Yellow|r %d-%d MB   |cFFFF4D4DRed|r over %d MB\nAddon memory only; other addons are not counted.", MEM_YELLOW, MEM_YELLOW, MEM_RED, MEM_RED))
    page.memNames = W.Text(page, 11, T.text)
    page.memNames:SetPoint("TOPLEFT", 4, -298)
    page.memNames:SetSpacing(3)
    page.memValues = W.Text(page, 11, T.accent, "RIGHT")
    page.memValues:SetPoint("TOPLEFT", 160, -298)
    page.memValues:SetWidth(90)
    page.memValues:SetSpacing(3)

    -- tools sit below the memory list, wherever it ends
    local tools = W.Header(page, "Tools", CONTENT_W)
    tools:SetPoint("TOPLEFT", page.memNames, "BOTTOMLEFT", -4, -18)
    local b1 = W.Button(page, 150, 22, "Copy debug info")
    b1:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 4, -10)
    b1:SetScript("OnClick", function() CUI:ShowDebugBox() end)
    local b2 = W.Button(page, 130, 22, "Export settings")
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
    b2:SetScript("OnClick", function() CUI:ShowExportBox() end)
    local b3 = W.Button(page, 130, 22, "Import settings")
    b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)
    b3:SetScript("OnClick", function() CUI:ShowImportBox() end)
    local b4 = W.Button(page, 150, 22, "Reset everything")
    b4:SetPoint("TOPLEFT", b1, "BOTTOMLEFT", 0, -8)
    b4:SetScript("OnClick", function() CUI:ResetEverything() end)
    if CysChangelog then
        local b5 = W.Button(page, 130, 22, #CysChangelog.order == 1 and "View changelog" or "Changelogs")
        b5:SetPoint("LEFT", b4, "RIGHT", 8, 0)
        b5:SetScript("OnClick", function()
            local first = CysChangelog.order[1]
            if first then CysChangelog:Show(first) end
        end)
        if #CysChangelog.order > 1 then
            local y = 0
            for i = 2, #CysChangelog.order do
                local name = CysChangelog.order[i]
                local bx = W.Button(page, 150, 22, "Changelog: " .. name)
                bx:SetPoint("LEFT", i == 2 and b5 or page["clog" .. (i - 1)], "RIGHT", 8, 0)
                bx:SetScript("OnClick", function() CysChangelog:Show(name) end)
                page["clog" .. i] = bx
            end
        end
    end

    local links = W.Header(page, "Links and bug reports", CONTENT_W)
    links:SetPoint("TOPLEFT", b4, "BOTTOMLEFT", -4, -20)
    local gh = CopyField(page, 300, "https://github.com/Cyserin/CysUI")
    gh:SetPoint("TOPLEFT", links, "BOTTOMLEFT", 4, -10)
    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", gh, "BOTTOMLEFT", 0, -8)
    note:SetWidth(CONTENT_W - 8)
    note:SetJustifyV("TOP")
    note:SetSpacing(3)
    note:SetText("Found a bug? Press |cFFFFD100Copy debug info|r, then post it with a screenshot at the address above under Issues.")

    local upd = W.Checkbox(page, "Tell me when a newer version is out (via guild and group)",
        function() return CysUIDB.update and CysUIDB.update.enabled ~= false end,
        function(v) CysUIDB.update = CysUIDB.update or {}; CysUIDB.update.enabled = v and true or false end)
    upd:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)

    page.contentHeight = 830
    RefreshMemory(page)
end, RefreshMemory)

--------------------------------------------------------------------------------
-- Modules page
--------------------------------------------------------------------------------
local STATUS = {
    active  = "|cFF4FD66BActive|r",
    enable  = "|cFFFFD100Reload to enable|r",
    disable = "|cFFFFD100Reload to disable|r",
    off     = "|cFF777777Off|r",
}

local function RefreshModules(page)
    if not (page and page.rows) then return end
    for _, row in ipairs(page.rows) do
        local def, key = row.def, row.def.key
        local on = CUI:IsModuleEnabled(key)
        local blocked = def.requires and not CUI:IsModuleEnabled(def.requires)
        row.cb:Refresh()
        row.cb:SetActive(not blocked)

        if blocked then
            local req = CUI.modules[def.requires]
            row.status:SetText("|cFFFF9F43Needs " .. (req and req.name or def.requires) .. "|r")
        elseif on and def.loadedEnabled then
            row.status:SetText(STATUS.active)
        elseif on then
            row.status:SetText(STATUS.enable)
        elseif def.loadedEnabled then
            row.status:SetText(STATUS.disable)
        else
            row.status:SetText(STATUS.off)
        end
        row.open:SetShown(def.open ~= nil and on and def.loadedEnabled and not blocked)
    end
    UpdateFooter()
end

-- Modules page groups, most-used first. Modules not listed land in "Other".
local MODULE_GROUPS = {
    { "Frames & Combat",  { "unitframes", "raidframes", "actionbars", "castbar", "nameplates", "playerAuras", "killtracker", "raiddebuffs", "damagemeters", "meter", "swing", "combattext", "threat" } },
    { "Interface",        { "chat", "minimap", "mmbuttons", "infobar", "xpbar", "characters", "micromenu", "tooltip", "skins", "friends", "scale", "durability", "automation", "questlist" } },
    { "Bags & Loot",      { "bags", "bank", "vendor", "consumables", "grouploot", "rolls", "upgrade" } },
    { "Character & Class", { "armory", "flyout", "skills", "totems", "tremor", "ranks", "healadvisor", "warrior", "shoutremind" } },
}

CUI:RegisterPage("Modules", function(page)
    local intro = W.Text(page, 11, T.desc)
    intro:SetPoint("TOPLEFT", 0, -4)
    intro:SetWidth(CONTENT_W)
    intro:SetText("Untick a module to switch it off - the game's own version takes over again after a reload. Switches are saved for this character only.")

    -- "only the modules that are off" filter. The list is worked out when you tick it (or reopen the page),
    -- so a module you switch back on stays in view instead of jumping away under the mouse.
    local onlyOff, offAtFilter = false, {}
    local Relayout
    local filter = W.Checkbox(page, "Only show modules that are turned off",
        function() return onlyOff end,
        function(v)
            onlyOff = v and true or false
            wipe(offAtFilter)
            for _, row in ipairs(page.rows) do
                if not CUI:IsModuleEnabled(row.def.key) then offAtFilter[row.def.key] = true end
            end
            if Relayout then Relayout() end
        end)
    local allOn = W.Text(page, 11, T.text)
    allOn:SetText("Every module is on.")
    allOn:Hide()

    page.rows = {}
    local stack = {} -- headers and cards in display order (placed by Relayout below)
    local allowed, placed = {}, {}
    for _, key in ipairs(CUI.order) do
        if CUI:ClassAllowed(CUI.modules[key]) then allowed[key] = true end -- other classes' modules stay hidden
    end
    local layout = {} -- flat list of { header = "..." } / { key = "..." }
    for _, g in ipairs(MODULE_GROUPS) do
        local items = {}
        for _, key in ipairs(g[2]) do
            if allowed[key] and not placed[key] then items[#items + 1] = { key = key }; placed[key] = true end
        end
        if #items > 0 then
            layout[#layout + 1] = { header = g[1] }
            for _, it in ipairs(items) do layout[#layout + 1] = it end
        end
    end
    local others = {}
    for _, key in ipairs(CUI.order) do
        if allowed[key] and not placed[key] then others[#others + 1] = { key = key } end
    end
    if #others > 0 then
        layout[#layout + 1] = { header = "Other" }
        for _, it in ipairs(others) do layout[#layout + 1] = it end
    end
    for _, item in ipairs(layout) do
      if item.header then
        local h = W.Text(page, 11, T.accent)
        h:SetText(string.upper(item.header))
        local ln = W.Texture(page, "ARTWORK", T.line)
        ln:SetSize(CONTENT_W, 1)
        stack[#stack + 1] = { header = h, line = ln }
      else
        local key = item.key
        local def = CUI.modules[key]
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(CONTENT_W, 62)
        row.def = def

        W.Texture(row, "BACKGROUND", T.card):SetAllPoints()
        W.Border(row, 1, T.line, "BORDER")

        local version = def.addon and CUI:GetVersion(def.addon) or CUI:GetVersion("CysUI")
        row.cb = W.Checkbox(row, "|cFFFFD100" .. def.name .. "|r  |cFF777777v" .. version .. "|r",
            function() return CUI:IsModuleEnabled(key) end,
            function(on) CUI:SetModuleEnabled(key, on) end)
        row.cb:SetPoint("TOPLEFT", 10, -8)
        row.cb.onChange = function() RefreshModules(page) end

        row.desc = W.Text(row, 11, T.desc)
        row.desc:SetPoint("TOPLEFT", 34, -28)
        row.desc:SetWidth(CONTENT_W - 120)
        row.desc:SetJustifyV("TOP")
        row.desc:SetText(def.desc or "")

        row.status = W.Text(row, 11, T.text, "RIGHT")
        row.status:SetPoint("TOPRIGHT", -10, -10)

        row.open = W.Button(row, 60, 20, "Open")
        row.open:SetPoint("BOTTOMRIGHT", -10, 8)
        row.open:SetScript("OnClick", function() if def.open then def.open() end end)

        page.rows[#page.rows + 1] = row
        stack[#stack + 1] = { row = row }
      end
    end

    -- Stack headers and cards top to bottom. Each card grows with its description so long
    -- text never runs into the next one. Text can only be measured once it is on screen,
    -- so this runs again every time the page is shown.
    Relayout = function()
        local y = -(math.ceil(intro:GetStringHeight() or 12) + 8)
        filter:ClearAllPoints()
        filter:SetPoint("TOPLEFT", 4, y)
        y = y - 28
        -- which cards show, and which headers still have a card under them
        local visible, any = {}, false
        local currentHeader
        for i, it in ipairs(stack) do
            if it.header then
                currentHeader = i
            else
                local show = not onlyOff or offAtFilter[it.row.def.key] == true
                visible[i] = show
                if show then
                    any = true
                    if currentHeader then visible[currentHeader] = true end
                end
            end
        end
        allOn:ClearAllPoints()
        allOn:SetPoint("TOPLEFT", 4, y - 4)
        allOn:SetShown(onlyOff and not any)
        if onlyOff and not any then y = y - 24 end
        for i, it in ipairs(stack) do
            if not visible[i] then
                if it.header then it.header:Hide(); it.line:Hide() else it.row:Hide() end
            elseif it.header then
                it.header:Show(); it.line:Show()
                it.header:ClearAllPoints()
                it.header:SetPoint("TOPLEFT", 2, y - 8)
                it.line:ClearAllPoints()
                it.line:SetPoint("TOPLEFT", 0, y - 24)
                y = y - 32
            else
                local row = it.row
                row:Show()
                local h = math.max(62, 28 + math.ceil(row.desc:GetStringHeight() or 0) + 10)
                row:SetHeight(h)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y)
                y = y - h - 6
            end
        end
        page.contentHeight = -y + 4
        if page:IsShown() and window and window.content then
            window.content:SetHeight(math.max(VIEW_H, page.contentHeight))
        end
    end
    Relayout()
    page:HookScript("OnShow", function()
        if onlyOff then
            -- reopening the page: modules switched back on since last time drop out of the list
            wipe(offAtFilter)
            for _, row in ipairs(page.rows) do
                if not CUI:IsModuleEnabled(row.def.key) then offAtFilter[row.def.key] = true end
            end
        end
        Relayout()
        C_Timer.After(0, Relayout) -- once more after the text has been drawn
    end)
    RefreshModules(page)
end, RefreshModules)

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function EnsurePage(index)
    local page = pageFrames[index]
    if page then return page end
    local def = CUI.pages[index]
    page = CreateFrame("Frame", nil, window.content)
    page:SetAllPoints()
    page:Hide()
    pageFrames[index] = page
    local ok, err = pcall(def.build, page)
    if not ok then
        geterrorhandler()(err) -- one broken page shouldn't take the whole window down
    end
    return page
end

local function SelectPage(index)
    current = index
    for i, f in pairs(pageFrames) do f:Hide() end
    local page = EnsurePage(index)
    window.content:SetHeight(max(VIEW_H, page.contentHeight or 0))
    window.scroll:SetVerticalScroll(0)
    page:Show()
    for i, b in ipairs(pageButtons) do
        local selected = (i == index)
        b.accent:SetShown(selected)
        if selected then b.bg:Show() else b.bg:Hide() end
        local c = selected and T.accent or (b.baseColor or T.text)
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    local def = CUI.pages[index]
    if def.onShow then def.onShow(page) end
    UpdateFooter()
end

local function CreateWindow()
    local f = CreateFrame("Frame", "CysUIConfigFrame", UIParent)
    window = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    -- header
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    W.Texture(header, "BACKGROUND", T.header):SetAllPoints()
    local hline = W.Texture(header, "BORDER", T.border)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = W.Text(header, 13, T.accent)
    title:SetPoint("LEFT", 12, 0)
    title:SetText("Cys's UI")
    local sub = W.Text(header, 11, T.desc)
    sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    sub:SetText("Settings")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -6, 0)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() CUI:HideWindow(f) end)

    -- always-visible way into layout mode; the settings come back when you press Done
    local layoutBtn = W.Button(header, 110, 22, "Layout mode")
    layoutBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    layoutBtn:SetScript("OnClick", function() CUI:ToggleLayout() end)
    layoutBtn:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Layout mode", 1, 0.82, 0)
        GameTooltip:AddLine("Move and resize any Cys's UI frame. Press Done to come back here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    layoutBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- footer
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    W.Texture(footer, "BACKGROUND", T.header):SetAllPoints()
    local fline = W.Texture(footer, "BORDER", T.border)
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    local info = W.Text(footer, 11, T.desc)
    info:SetPoint("LEFT", 12, 0)
    info:SetText("Cys's UI v" .. CUI:GetVersion("CysUI"))
    f.hint = W.Text(footer, 11, T.accent, "RIGHT")
    f.hint:SetPoint("RIGHT", -120, 0)
    f.reload = W.Button(footer, 100, 24, "Reload UI")
    f.reload:SetPoint("RIGHT", -10, 0)
    f.reload:SetScript("OnClick", function() CysUICompat.Reload() end)
    CysUICompat.SecureReload(f.reload, f) -- WoW Forever: the click itself runs /reload

    -- sidebar
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W)
    W.Texture(sidebar, "BACKGROUND", T.sidebar):SetAllPoints()
    local sline = W.Texture(sidebar, "BORDER", T.border)
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)

        -- The sidebar scrolls and groups pages under small headings. Pages not listed in GROUPS
    -- (new modules, other addons) land under "Other" automatically.
    local sideScroll = CreateFrame("ScrollFrame", nil, sidebar)
    sideScroll:SetPoint("TOPLEFT", 0, 0)
    sideScroll:SetPoint("BOTTOMRIGHT", -1, 28)
    sideScroll:EnableMouseWheel(true)
    local side = CreateFrame("Frame", nil, sideScroll)
    side:SetSize(SIDEBAR_W - 1, 100)
    sideScroll:SetScrollChild(side)
    sideScroll:SetScript("OnMouseWheel", function(s2, delta)
        s2:SetVerticalScroll(max(0, math.min(s2:GetVerticalScroll() - delta * 40, s2:GetVerticalScrollRange())))
    end)

    local byTitle, placed = {}, {}
    for i, page in ipairs(CUI.pages) do byTitle[page.title] = i end
    local function Collect(titles)
        local list = {}
        for _, title in ipairs(titles) do
            if byTitle[title] then list[#list + 1] = byTitle[title]; placed[byTitle[title]] = true end
        end
        return list
    end
    -- pages under a heading are listed A to Z by the name shown in the sidebar
    local function SideName(i) local t = CUI.pages[i].title; return (LABELS[t] or t):lower() end
    local function AtoZ(list) table.sort(list, function(a, b) return SideName(a) < SideName(b) end); return list end
    local sections = {}
    for _, g in ipairs(GROUPS) do
        local list = Collect(g[2])
        if g[1] then AtoZ(list) end -- the top three (General, Modules, Conflicts) keep their order
        if #list > 0 then sections[#sections + 1] = { name = g[1], key = g[1], level = 1, pages = list } end
    end
    -- class section: General (tools that work for every class), then every class in its class color (yours first)
    -- with the pages tagged for it. Classes with nothing yet say so, so the section doubles as an overview.
    local _, myClass = UnitClass("player")
    local general = AtoZ(Collect(CLASS_GENERAL))
    local byClass = {}
    for i, page in ipairs(CUI.pages) do
        if page.class then
            byClass[page.class] = byClass[page.class] or {}
            table.insert(byClass[page.class], i)
            placed[i] = true
        end
    end
    sections[#sections + 1] = { name = "Class", key = "Class", level = 1, pages = {} }
    if #general > 0 then
        sections[#sections + 1] = { name = "General", key = "Class/General", level = 2, pages = general,
            color = { r = 0.92, g = 0.92, b = 0.92 } }
    end
    local ordered = {}
    for _, c in ipairs(CLASSES) do if c[1] == myClass then ordered[#ordered + 1] = c end end
    for _, c in ipairs(CLASSES) do if c[1] ~= myClass then ordered[#ordered + 1] = c end end
    for _, c in ipairs(ordered) do
        local list = byClass[c[1]] or {}
        AtoZ(list)
        sections[#sections + 1] = { name = c[2], key = "Class/" .. c[2], level = 2, pages = list,
            color = { r = c[3], g = c[4], b = c[5] }, empty = #list == 0 }
    end
    local other = {}
    for i in ipairs(CUI.pages) do if not placed[i] then other[#other + 1] = i end end
    AtoZ(other)
    if #other > 0 then sections[#sections + 1] = { name = "Other", key = "Other", level = 1, pages = other } end

    -- headings are buttons: click one to fold or unfold its pages (remembered in the saved settings)
    local function Folded()
        CysUIDB.sideFolded = CysUIDB.sideFolded or {}
        return CysUIDB.sideFolded
    end
    local entries = {}
    local Layout
    for _, section in ipairs(sections) do
        if section.name then
            local h = CreateFrame("Button", nil, side)
            h:SetHeight(22)
            h.level = section.level
            local c = section.color and { section.color.r, section.color.g, section.color.b } or (section.level == 1 and T.accent or T.text)
            h.label = W.Text(h, 11, c)
            h.label:SetPoint("LEFT", section.level == 1 and 14 or 24, 0)
            h.label:SetText(section.level == 1 and string.upper(section.name) or (section.name .. (section.empty and "  (soon)" or "")))
            h.sign = W.Text(h, 13, T.accent)
            h.sign:SetPoint("RIGHT", -10, 0)
            h.empty = section.empty
            h:SetScript("OnClick", function()
                if section.empty then return end
                local fold = Folded()
                fold[section.key] = not fold[section.key] or nil
                Layout()
            end)
            entries[#entries + 1] = { head = h, key = section.key, level = section.level }
        end
        for _, i in ipairs(section.pages) do
            local b = CreateFrame("Button", nil, side)
            b:SetHeight(26)
            b.bg = W.Texture(b, "BACKGROUND", T.selected)
            b.bg:SetAllPoints()
            b.bg:Hide()
            b.accent = W.Texture(b, "ARTWORK", T.accent)
            b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(2)
            b.accent:Hide()
            b.baseColor = T.text
            if section.level == 2 and section.color then
                -- a page under a class: indented, with a bullet in the class color and softer text
                b.baseColor = { 0.72, 0.86, 0.80 }
                b.bullet = W.Text(b, 12, { section.color.r, section.color.g, section.color.b })
                b.bullet:SetPoint("LEFT", 24, 0)
                b.bullet:SetText("\226\128\162")
            end
            b.label = W.Text(b, 12, b.baseColor)
            b.label:SetPoint("LEFT", section.level == 2 and 36 or 14, 0)
            b.label:SetText(LABELS[CUI.pages[i].title] or CUI.pages[i].title)
            b:SetScript("OnClick", function()
                SelectPage(i)
                if f.searchHits and f.ShowHit then f.ShowHit(i) end
            end)
            pageButtons[i] = b
            entries[#entries + 1] = { page = b, index = i, level = section.level, hasHead = section.name ~= nil }
        end
    end
    function Layout()
        local fold = Folded()
        local y = -8
        -- while searching: just the matching pages, flat, no headings
        if f.searchHits then
            for _, e in ipairs(entries) do
                if e.head then
                    e.head:Hide()
                elseif f.searchHits[e.index] then
                    e.page:ClearAllPoints()
                    e.page:SetPoint("TOPLEFT", 0, y); e.page:SetPoint("TOPRIGHT", 0, y)
                    e.page:Show()
                    y = y - 27
                else
                    e.page:Hide()
                end
            end
            side:SetHeight(max(-y + 8, 100))
            sideScroll:SetVerticalScroll(0)
            return
        end
        local topFolded, subFolded = false, false
        for _, e in ipairs(entries) do
            if e.head then
                local h = e.head
                if e.level == 1 then
                    topFolded, subFolded = fold[e.key] and true or false, false
                    y = y - 8
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", 0, y); h:SetPoint("TOPRIGHT", 0, y)
                    h:Show()
                    y = y - 24
                else
                    subFolded = fold[e.key] and true or false
                    if topFolded then
                        h:Hide()
                    else
                        h:ClearAllPoints()
                        h:SetPoint("TOPLEFT", 0, y); h:SetPoint("TOPRIGHT", 0, y)
                        h:Show()
                        y = y - 24
                    end
                end
                h.sign:SetText(h.empty and "" or (fold[e.key] and "[+]" or "[-]"))
            else
                local hide = (e.level == 1 and e.hasHead and topFolded) or (e.level == 2 and (topFolded or subFolded))
                local b = e.page
                if hide then
                    b:Hide()
                else
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 0, y); b:SetPoint("TOPRIGHT", 0, y)
                    b:Show()
                    y = y - 27
                end
            end
        end
        side:SetHeight(max(-y + 8, 100))
    end
    Layout()
    f.Layout = Layout

    -- Search: finds pages by their name and by any text on them (setting labels, notes), so a setting can be
    -- found without knowing which page it's on. Every page is built the first time you search.
    local index
    local function BuildIndex()
        index = {}
        for i, def in ipairs(CUI.pages) do
            local page = EnsurePage(i)
            local list = { { text = ((LABELS[def.title] or def.title) .. " " .. def.title):lower() } }
            local function Walk(fr, depth)
                if depth > 8 then return end
                local okR, regions = pcall(function() return { fr:GetRegions() } end)
                if okR then
                    for _, r in ipairs(regions) do
                        if r.GetObjectType and r:GetObjectType() == "FontString" then
                            local okT, t = pcall(r.GetText, r)
                            if okT and type(t) == "string" and t ~= "" then
                                list[#list + 1] = { text = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower(), fs = r }
                            end
                        end
                    end
                end
                local okC, kids = pcall(function() return { fr:GetChildren() } end)
                if okC then for _, c in ipairs(kids) do Walk(c, depth + 1) end end
            end
            Walk(page, 0)
            index[i] = list
        end
    end

    local function Matches(i, q)
        local found
        for _, item in ipairs(index[i] or {}) do
            if item.text:find(q, 1, true) then
                if not item.fs then return true, nil end -- the page name itself
                found = found or item.fs
            end
        end
        return found ~= nil, found
    end

    -- jump to and briefly light up the first matching line on a page
    local function ShowHit(i)
        local q = f.searchText
        if not q then return end
        local _, fs = Matches(i, q)
        local page = pageFrames[i]
        if not (fs and page) then return end
        C_Timer.After(0, function()
            local pt, ft = page:GetTop(), fs:GetTop()
            if pt and ft then
                local range = f.scroll:GetVerticalScrollRange() or 0
                f.scroll:SetVerticalScroll(max(0, math.min(range, pt - ft - 40)))
            end
            local r, g, b = fs:GetTextColor()
            fs:SetTextColor(T.glow[1], T.glow[2], T.glow[3])
            C_Timer.After(2, function() if r then fs:SetTextColor(r, g, b) end end)
        end)
    end
    f.ShowHit = ShowHit

    local box = CreateFrame("EditBox", nil, header)
    box:SetSize(170, 22)
    box:SetPoint("RIGHT", layoutBtn, "LEFT", -8, 0)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextInsets(8, 22, 0, 0)
    box:SetMaxLetters(40)
    W.Texture(box, "BACKGROUND", T.field or T.bg):SetAllPoints()
    box.edges = W.Border(box, 1, T.line, "BORDER")
    local hint = W.Text(box, 11, T.desc)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText("Search settings")
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -2, 0)
    clear.text = W.Text(clear, 12, T.desc, "CENTER")
    clear.text:SetPoint("CENTER")
    clear.text:SetText("x")
    clear:Hide()
    local noHits = W.Text(side, 11, T.desc)
    noHits:SetPoint("TOPLEFT", 14, -14)
    noHits:SetWidth(SIDEBAR_W - 28)
    noHits:SetJustifyH("LEFT")
    noHits:SetText("Nothing matches.")
    noHits:Hide()

    local function Run()
        local q = strtrim(box:GetText() or ""):lower()
        hint:SetShown(q == "" and not box:HasFocus())
        clear:SetShown(q ~= "")
        if #q < 2 then
            f.searchHits, f.searchText = nil, nil
            noHits:Hide()
            Layout()
            return
        end
        if not index then BuildIndex() end
        local hits, first, count = {}, nil, 0
        local function Scan(term)
            for i in ipairs(CUI.pages) do
                if pageButtons[i] and Matches(i, term) then
                    hits[i] = true
                    count = count + 1
                    first = first or i
                end
            end
        end
        Scan(q)
        -- nothing found: forgive a longer word ("percentage" finds "percent") by trimming up to 4 letters
        local cut = 0
        while count == 0 and cut < 4 and #q - cut - 1 >= 4 do
            cut = cut + 1
            local shorter = q:sub(1, #q - cut)
            Scan(shorter)
            if count > 0 then q = shorter end
        end
        f.searchHits, f.searchText = hits, q
        noHits:SetShown(count == 0)
        Layout()
        -- open the first hit unless the page you're on already matches
        if count > 0 then
            if not (current and hits[current]) then SelectPage(first) end
            ShowHit(current)
        end
    end
    box:SetScript("OnTextChanged", Run)
    box:SetScript("OnEditFocusGained", function() hint:Hide(); W.SetBorder(box.edges, T.glow) end)
    box:SetScript("OnEditFocusLost", function() W.SetBorder(box.edges, T.line); Run() end)
    box:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
    f.searchBox = box

    -- Collapse all / Expand all, under the list
    local foldBar = CreateFrame("Frame", nil, sidebar)
    foldBar:SetPoint("BOTTOMLEFT", 0, 0)
    foldBar:SetPoint("BOTTOMRIGHT", -1, 0)
    foldBar:SetHeight(28)
    W.Texture(foldBar, "BACKGROUND", T.sidebar):SetAllPoints()
    local foldLine = W.Texture(foldBar, "BORDER", T.border)
    foldLine:SetPoint("TOPLEFT"); foldLine:SetPoint("TOPRIGHT"); foldLine:SetHeight(1)
    local bw = math.floor((SIDEBAR_W - 1 - 18) / 2)
    local collapseAll = W.Button(foldBar, bw, 18, "Collapse all")
    collapseAll:SetPoint("LEFT", 6, -1)
    collapseAll:SetScript("OnClick", function()
        local fold = Folded()
        for _, e in ipairs(entries) do
            if e.head and not e.head.empty then fold[e.key] = true end
        end
        Layout()
        sideScroll:SetVerticalScroll(0) -- the list is short now: back to the top, or it stays scrolled past its end
    end)
    local expandAll = W.Button(foldBar, bw, 18, "Expand all")
    expandAll:SetPoint("LEFT", collapseAll, "RIGHT", 6, 0)
    expandAll:SetScript("OnClick", function()
        wipe(Folded())
        Layout()
    end)

    -- content
    -- pages scroll (mouse wheel) when they're taller than the window, so adding modules never overflows it
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, -PAD)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -PAD, PAD)
    scroll:EnableMouseWheel(true)
    f.scroll = scroll
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(CONTENT_W, VIEW_H)
    scroll:SetScrollChild(f.content)

    local thumb = W.Texture(f, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.5 })
    thumb:Hide()
    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange()
        if not range or range <= 0 then thumb:Hide() return end
        local viewH = scroll:GetHeight()
        local thumbH = max(24, viewH * viewH / (viewH + range))
        local y = (scroll:GetVerticalScroll() / range) * (viewH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetSize(3, thumbH)
        thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -y)
        thumb:Show()
    end
    scroll:SetScript("OnMouseWheel", function(s, delta)
        s:SetVerticalScroll(max(0, math.min(s:GetVerticalScroll() - delta * 40, s:GetVerticalScrollRange())))
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)

    -- keep the memory numbers fresh while the window is open
    f:SetScript("OnShow", function()
        f.ticker = C_Timer.NewTicker(3, function()
            local page = current and pageFrames[current]
            if page and page.memNames then RefreshMemory(page) end
        end)
        UpdateFooter()
    end)
    f:SetScript("OnHide", function()
        if f.ticker then f.ticker:Cancel(); f.ticker = nil end
    end)
    tinsert(UISpecialFrames, "CysUIConfigFrame")
    CUI:ManageWindow(f, "center", 0) -- opens beside Blizzard's windows instead of on top of them

    SelectPage(1)
end

function CUI:ToggleConfig()
    if not window then CreateWindow() end
    CUI:ToggleWindow(window)
end

-- Open straight to a page by title, e.g. CysUI:OpenConfig("Vendor")
function CUI:OpenConfig(pageTitle)
    if not window then CreateWindow() end
    CUI:ShowWindow(window)
    for i, page in ipairs(CUI.pages) do
        if page.title == pageTitle then SelectPage(i) return end
    end
end

--------------------------------------------------------------------------------
-- An entry under Options > AddOns with a button that opens the /cui window. (WoW Forever only shows the
-- Game / AddOns tabs once some addon has a page there, so without this they were missing.)
--------------------------------------------------------------------------------
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
        local panel = CreateFrame("Frame")
        panel:Hide()
        local title = W.Text(panel, 16, T.accent)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Cys's UI")
        local desc = W.Text(panel, 12, T.text)
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
        desc:SetWidth(520)
        desc:SetJustifyH("LEFT")
        desc:SetText("All of Cys's UI's settings live in its own window. Type /cui any time, or press the button below.")
        local open = W.Button(panel, 220, 26, "Open Cys's UI settings")
        open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
        open:SetScript("OnClick", function()
            if not (window and window:IsShown()) then CUI:ToggleConfig() end
            if window then window:Raise() end
        end)
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Cys's UI")
        if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    end)
end

--------------------------------------------------------------------------------
-- A "Cys's UI" button in the Esc menu (like ElvUI / EllesmereUI), between Shop and AddOns in its own section.
-- WoW Forever (new-style menu): added through the menu's own AddButton each time it builds its buttons, slotted in
-- by layout order. Classic Era (old-style menu): our button takes the AddOns button's spot and AddOns moves below it.
-- The Esc menu skin restyles it with the other buttons. Switch: General page.
--------------------------------------------------------------------------------
do
    local function MenuLabel()
        local c = (CUI.W and CUI.W.T and CUI.W.T.brand) or { 0.85, 0.64, 0.13 }
        return string.format("|cff%02x%02x%02xCys's|r UI", c[1] * 255, c[2] * 255, c[3] * 255)
    end
    local function OpenFromMenu()
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        CUI:OpenConfig()
    end
    local done
    local function Setup()
        local gm = GameMenuFrame
        if done or not gm or (CysUIDB and CysUIDB.menuButton == false) then return end
        done = true
        if gm.InitButtons and gm.AddButton and gm.buttonPool then
            hooksecurefunc(gm, "InitButtons", function(self)
                local addons
                for b in self.buttonPool:EnumerateActive() do
                    if b.GetText and b:GetText() == ADDONS then addons = b end
                end
                local mine = self:AddButton(MenuLabel(), OpenFromMenu)
                if mine and addons and addons.layoutIndex then
                    local k = addons.layoutIndex
                    for b in self.buttonPool:EnumerateActive() do
                        if b ~= mine and b.layoutIndex and b.layoutIndex >= k then b.layoutIndex = b.layoutIndex + 1 end
                    end
                    mine.layoutIndex = k
                    mine.topPadding = addons.topPadding or 20 -- its own section; AddOns keeps its gap below it
                    addons.topPadding = 20
                    if self.MarkDirty then self:MarkDirty() end
                end
            end)
        elseif _G.GameMenuButtonAddons then
            local addons = GameMenuButtonAddons
            local btn = CreateFrame("Button", "CysUIGameMenuButton", gm, "GameMenuButtonTemplate")
            btn:SetText(MenuLabel())
            btn:SetScript("OnClick", OpenFromMenu)
            local p, rel, rp, x, y = addons:GetPoint(1)
            if p then btn:SetPoint(p, rel, rp, x, y) end
            addons:ClearAllPoints()
            addons:SetPoint("TOP", btn, "BOTTOM", 0, -16)
            local extra = (btn:GetHeight() or 21) + 16
            if GameMenuFrame_UpdateVisibleButtons then
                -- Blizzard sets the menu height here every time it opens: add our row on top of it
                hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", function() gm:SetHeight(gm:GetHeight() + extra) end)
            else
                local base
                gm:HookScript("OnShow", function(self)
                    base = base or self:GetHeight()
                    self:SetHeight(base + extra)
                end)
            end
        end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function() pcall(Setup) end)
end
