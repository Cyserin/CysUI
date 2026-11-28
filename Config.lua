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

local WIDTH, HEIGHT = 760, 600
local SIDEBAR_W, HEADER_H, FOOTER_H, PAD = 180, 60, 36, 16
local CONTENT_W = WIDTH - SIDEBAR_W - PAD * 2 - 2
local VIEW_H = HEIGHT - HEADER_H - FOOTER_H - PAD * 2 - 2 -- visible height of a page
local CARD_PAD = 8 -- room left of each page for the section cards

-- sidebar grouping: { heading (nil = none), { page titles in order } }
local GROUPS = {
    { nil,                { "General", "Profiles", "New", "Modules", "Conflicts" } },
    { "Interface",        { "Automation", "UI Scale", "Skins", "Tooltip", "Minimap", "Data Panels",
                            "Chat", "Friends", "Guild Recruiter", "Cys's UI Users" } },
    { "Frames & Combat",  { "Unit Frames", "Raid Frames", "Cast Bar", "PlayerAuras", "Nameplates", "Action Bars", "Click-Casting",
                            "Damage Meter", "Details Skin", "Combat Numbers", "Combat Log",
                            "Swing Timer", "Threat", "Taunt Alert", "Missing Buffs", "Buff Helper", "Raid Debuffs", "Alerts", "Mana Tick",
                            "Marker Wheel", "Weapon Swap", "Trinkets", "Vehicle Exit", "Flight Timer", "Quest Starter" } },
    { "Items & Leveling", { "Vendor", "Bags", "Consumables", "Durability", "Loot", "Roll Tracker", "Crate Tracker", "Tracked Recipes", "Upgrade",
                            "Quest Tracker", "XP Bar", "Kill Tracker", "Dungeon Runs", "Skill Tracker", "Characters" } },
}

-- Related pages share one sidebar entry and show as tabs along the top of the page (first tab = the
-- sidebar entry). A group whose pages aren't all loaded keeps the ones that are; one page left = no tabs.
local MERGED = {
    { "Look",           { "UI Scale", "Skins", "Tooltip" } },
    { "Minimap & Bars", { "Minimap", "Data Panels" } },
    { "Social",         { "Chat", "Friends", "Guild Recruiter", "Cys's UI Users" } },
    { "Unit Frames",    { "Unit Frames", "Raid Frames", "Cast Bar", "PlayerAuras" } },
    { "Damage Meter",   { "Damage Meter", "Details Skin", "Combat Numbers", "Combat Log" } },
    { "Combat Helpers", { "Swing Timer", "Threat", "Taunt Alert", "Missing Buffs", "Buff Helper", "Raid Debuffs", "Alerts", "Mana Tick" } },
    { "Handy Extras",   { "Marker Wheel", "Weapon Swap", "Trinkets", "Vehicle Exit", "Flight Timer", "Quest Starter" } },
    { "Vendor & Bags",  { "Vendor", "Bags", "Consumables", "Durability" } },
    { "Loot",           { "Loot", "Roll Tracker", "Crate Tracker" } },
    { "Leveling",       { "Quest Tracker", "XP Bar", "Kill Tracker", "Dungeon Runs", "Skill Tracker", "Characters" } },
}
local TAB_NAMES = { PlayerAuras = "Player Auras", ["Cys's UI Users"] = "Cys's UI Users" }
local TAB_H = 30


-- Class pages live under CLASS: a General page (works for every class), then a heading for your own class
-- (in its class color) with that class's pages under it. Only your own class is listed.
local CLASS_GENERAL = { "Level-Up Spells", "Spell Ranks", "Talent Planner", "Heal Advisor" }
local LABELS = { General = "Home" } -- sidebar text when it differs from the page title
local tabGroup = {} -- page index -> { name, pages = { indices } } for pages shown as tabs
-- Pages shown as one: their settings stack on one page (one card per section), in this order. The parts'
-- titles still open it (CysUI:OpenConfig("Micro Menu") lands on Data Panels).
local COMBINED = {
    { "Minimap",     { "Minimap", "Minimap Button" } },
    { "Data Panels", { "Info Bar", "Micro Menu" } },
}
local function CombinePages()
    if CUI.pagesCombined then return end
    CUI.pagesCombined = true
    for _, c in ipairs(COMBINED) do
        local parts, at = {}, nil
        for _, title in ipairs(c[2]) do
            for i, p in ipairs(CUI.pages) do
                if p.title == title then parts[#parts + 1] = p; at = at and math.min(at, i) or i break end
            end
        end
        if #parts >= 2 then
            for _, p in ipairs(parts) do
                for i = #CUI.pages, 1, -1 do if CUI.pages[i] == p then table.remove(CUI.pages, i) end end
            end
            local aliases = {}
            for _, p in ipairs(parts) do aliases[p.title] = true end
            table.insert(CUI.pages, math.min(at, #CUI.pages + 1), {
                title = c[1], aliases = aliases, class = parts[1].class,
                build = function(page)
                    page.cysStack = {}
                    for k, p in ipairs(parts) do
                        local sub = CreateFrame("Frame", nil, page)
                        sub:SetPoint("TOPLEFT", 0, 0)
                        sub:SetPoint("RIGHT", page, "RIGHT", 0, 0)
                        sub:SetHeight(VIEW_H)
                        sub.cysSettingsPage, sub.cysSubPage = true, true
                        local ok, err = pcall(p.build, sub)
                        if not ok then geterrorhandler()(err) end
                        page.cysStack[k] = sub
                    end
                end,
                onShow = function(page)
                    for k, p in ipairs(parts) do
                        if p.onShow and page.cysStack and page.cysStack[k] then pcall(p.onShow, page.cysStack[k]) end
                    end
                end,
            })
        end
    end
end

local function BuildTabGroups()
    wipe(tabGroup)
    local byT = {}
    for i, p in ipairs(CUI.pages) do byT[p.title] = i end
    for _, m in ipairs(MERGED) do
        local list = {}
        for _, t in ipairs(m[2]) do if byT[t] then list[#list + 1] = byT[t] end end
        if #list > 1 then
            local g = { name = m[1], pages = list }
            for _, i in ipairs(list) do tabGroup[i] = g end
            LABELS[CUI.pages[list[1]].title] = m[1]
        end
    end
end
local function TabName(i) local t = CUI.pages[i].title; return TAB_NAMES[t] or t end
-- a sidebar entry is new while its page, or any tab under it, hasn't been opened yet
local function AnyNew(i)
    if not (CUI.IsNewPage) then return false end
    local g = tabGroup[i]
    for _, pi in ipairs(g and g.pages or { i }) do
        if CUI:IsNewPage(CUI.pages[pi].title) then return true end
    end
    return false
end
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
    local prof = CUI.ProfilePending and CUI:ProfilePending()
    local pending = CUI:HasPendingReload() or prof ~= nil
    window.reload:SetPrimary(pending)
    window.hint:SetText(prof and ("|cFFFFD100Reload to load the " .. prof .. " profile.|r")
        or (pending and "|cFFFFD100Changes need a UI reload to take effect.|r" or ""))
    if window.profileDD then window.profileDD:Refresh() end
end
CUI.UpdateSettingsFooter = UpdateFooter

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
    if not (page and page.memTile) then return end
    CUI:UpdateMemory()
    local lines, total = {}, 0
    for _, addon in ipairs(AddonList()) do
        local kb = CUI:GetMemoryKB(addon)
        lines[#lines + 1] = { addon, kb and FmtMem(kb) or "-" }
        total = total + (kb or 0)
    end
    page.memLines = lines
    local col, word = MemColor(total)
    local t = page.memTile
    t.value:SetText(FmtMem(total))
    t.sub:SetText(Hex(col) .. word .. "|r  |cFFA8A196under " .. MEM_YELLOW .. " MB is light|r")
    t.fill:SetVertexColor(col[1], col[2], col[3], 1)
    t.fill:SetWidth(math.max(2, math.min(1, (total / 1024) / MEM_RED) * (t:GetWidth() - 24)))
    if page.RefreshTiles then page:RefreshTiles() end
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
    eb:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "")
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
    local W2 = CONTENT_W
    local title = W.Text(page, 18, T.text)
    title:SetPoint("TOPLEFT", 4, -4)
    title:SetText("Welcome back, |cFFFFD100" .. (UnitName("player") or "friend") .. "|r")
    local ver = W.Text(page, 11, T.desc)
    ver:SetPoint("LEFT", title, "RIGHT", 10, -1)
    ver:SetText((CUI.newerVersion and ("|cFF6CB6FFv" .. CUI.newerVersion .. " is out|r") or ""))
    local desc = W.Text(page, 12, T.desc)
    desc:SetPoint("TOPLEFT", 4, -30)
    desc:SetWidth(W2 - 8)
    desc:SetJustifyH("LEFT")
    desc:SetText("A light, minimal UI built from small modules that share one look. Type |cFFFFD100/cui|r any time to come back here.")

    -- four tiles: memory, modules, profile, what's new
    local gap = 8
    local tileW = math.floor((W2 - 8 - gap * 3) / 4)
    local function Tile(i, label, onClick)
        local t = CreateFrame("Button", nil, page)
        t:SetSize(tileW, 66)
        t:SetPoint("TOPLEFT", 4 + (i - 1) * (tileW + gap), -56)
        W.Texture(t, "BACKGROUND", T.card):SetAllPoints()
        t.edges = W.Border(t, 1, T.line, "BORDER")
        t.label = W.Text(t, 10, T.desc)
        t.label:SetPoint("TOPLEFT", 10, -9)
        t.label:SetText(label)
        t.value = W.Text(t, 17, T.text)
        t.value:SetPoint("TOPLEFT", 10, -23)
        t.value:SetPoint("RIGHT", -8, 0)
        t.value:SetJustifyH("LEFT")
        t.value:SetWordWrap(false)
        t.sub = W.Text(t, 10, T.desc)
        t.sub:SetPoint("BOTTOMLEFT", 10, 8)
        t.sub:SetPoint("RIGHT", -6, 0)
        t.sub:SetJustifyH("LEFT")
        t.sub:SetWordWrap(false)
        if onClick then
            t:SetScript("OnClick", onClick)
            t:SetScript("OnEnter", function(s) W.SetBorder(s.edges, T.glow); if s.tip then s.tip(s) end end)
            t:SetScript("OnLeave", function(s) W.SetBorder(s.edges, T.line); GameTooltip:Hide() end)
        end
        return t
    end
    local mem = Tile(1, "MEMORY", function() RefreshMemory(page) end)
    mem.track = W.Texture(mem, "ARTWORK", T.line)
    mem.track:SetPoint("BOTTOMLEFT", 10, 23); mem.track:SetPoint("BOTTOMRIGHT", -14, 23); mem.track:SetHeight(3)
    mem.fill = mem:CreateTexture(nil, "ARTWORK", nil, 1)
    mem.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    mem.fill:SetPoint("LEFT", mem.track, "LEFT"); mem.fill:SetHeight(3); mem.fill:SetWidth(2)
    mem.tip = function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Addon memory", 1, 0.82, 0)
        for _, l in ipairs(page.memLines or {}) do GameTooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 0.82, 0) end
        GameTooltip:AddLine(format("Green under %d MB, yellow %d-%d MB, red over %d MB. Other addons are not counted. Click to measure again.", MEM_YELLOW, MEM_YELLOW, MEM_RED, MEM_RED), 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end
    page.memTile = mem
    local mods = Tile(2, "MODULES", function() CUI:OpenConfig("Modules") end)
    local prof = Tile(3, "PROFILE", function() CUI:OpenConfig("Profiles") end)
    local news = Tile(4, "WHAT'S NEW", function()
        if CysChangelog and CysChangelog.order[1] then CysChangelog:Show(CysChangelog.order[1]) end
    end)
    function page:RefreshTiles()
        local on, all = ModuleCounts()
        mods.value:SetText(on .. " |cFFA8A196of " .. all .. " on|r")
        mods.sub:SetText("|cFFFFD100Manage modules|r")
        local active = CUI.ActiveProfile and CUI:ActiveProfile() or "Default"
        prof.value:SetText(active)
        local pend = CUI.ProfilePending and CUI:ProfilePending()
        prof.sub:SetText(pend and ("|cFFFFD100" .. pend .. " after reload|r") or "|cFFFFD100Swap or share|r")
        news.value:SetText("v" .. CUI:GetVersion("CysUI"))
        news.sub:SetText("|cFFFFD100View the changelog|r")
    end

    local y = -138
    W.Header(page, "Windows and input", W2):SetPoint("TOPLEFT", 0, y)
    y = y - 30
    local function Check(label, get, set)
        local c = W.Checkbox(page, label, get, set)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 26
        return c
    end
    Check("Open windows side by side like Blizzard's (reload)",
        function() return CysUIDB.stackWindows ~= false end,
        function(v) CysUIDB.stackWindows = v and true or false end)
    Check("Cys's UI button in the Esc menu (reload)",
        function() return CysUIDB.menuButton ~= false end,
        function(v) CysUIDB.menuButton = v and true or false end)
    Check("Mouse wheel changes sliders (off: the wheel only scrolls the page)",
        function() return CysUIDB.wheelSliders == true end,
        function(v) CysUIDB.wheelSliders = v and true or false end)
    Check("Tell me when a newer version is out (via guild and group)",
        function() return CysUIDB.update and CysUIDB.update.enabled ~= false end,
        function(v) CysUIDB.update = CysUIDB.update or {}; CysUIDB.update.enabled = v and true or false end)

    y = y - 14
    W.Header(page, "Tools", W2):SetPoint("TOPLEFT", 0, y)
    y = y - 32
    local bw = math.floor((W2 - 8 - 16) / 3)
    local tools = {
        { "Layout mode", function() CUI:ToggleLayout() end, true },
        { "Reset all positions", function() CUI:ResetAllMovers() end },
        { "Profiles and sharing", function() CUI:OpenConfig("Profiles") end },
        { "Copy debug info", function() CUI:ShowDebugBox() end },
        { "View changelog", function() if CysChangelog and CysChangelog.order[1] then CysChangelog:Show(CysChangelog.order[1]) end end },
        { "Reset everything", function() CUI:ResetEverything() end },
    }
    if CysChangelog then
        for i = 2, #CysChangelog.order do
            local name = CysChangelog.order[i]
            tools[#tools + 1] = { "Changelog: " .. name, function() CysChangelog:Show(name) end }
        end
    end
    for i, t in ipairs(tools) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local b = W.Button(page, bw, 26, t[1], t[3])
        b:SetPoint("TOPLEFT", 4 + col * (bw + 8), y - row * 34)
        b:SetScript("OnClick", t[2])
        if t[1] == "Reset everything" then b.danger = true; b:SetPrimary(false) end
    end
    y = y - math.ceil(#tools / 3) * 34 - 12

    W.Header(page, "Links and bug reports", W2):SetPoint("TOPLEFT", 0, y)
    local gh = CopyField(page, 300, "https://github.com/Cyserin/CysUI")
    gh:SetPoint("TOPLEFT", 4, y - 32)
    local note = W.Text(page, 11, T.desc)
    note:SetPoint("TOPLEFT", gh, "BOTTOMLEFT", 0, -8)
    note:SetWidth(W2 - 12)
    note:SetJustifyH("LEFT")
    note:SetText("Found a bug? Press |cFFFFD100Copy debug info|r, then post it with a screenshot at the address above under Issues.")
    page.contentHeight = -y + 100
    RefreshMemory(page)
    if CUI.OnProfilesChanged then CUI:OnProfilesChanged(function() if page.RefreshTiles then page:RefreshTiles() end end) end
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
    { "Frames & Combat",  { "unitframes", "raidframes", "actionbars", "castbar", "nameplates", "playerAuras", "killtracker", "raiddebuffs", "damagemeters", "meter", "swing", "combattext", "threat", "markwheel", "weaponswap", "trinkets", "clickcast", "vehicleexit", "alerts", "manatick" } },
    { "Interface",        { "chat", "minimap", "mmbuttons", "infobar", "xpbar", "runs", "characters", "micromenu", "tooltip", "skins", "friends", "recruit", "hello", "scale", "durability", "automation", "questlist", "flight" } },
    { "Bags & Loot",      { "bags", "bank", "vendor", "consumables", "grouploot", "rolls", "upgrade", "queststart", "crates", "recipes" } },
    { "Character & Class", { "armory", "flyout", "skills", "totems", "tremor", "ranks", "talentplan", "healadvisor", "warrior", "shoutremind" } },
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
    -- the page starts CARD_PAD in from the scroll area, so the cards drawn behind sections have room on the left
    page:SetPoint("TOPLEFT", CARD_PAD, 0)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    page.cysSettingsPage = true -- W.Header draws card titles here
    page:Hide()
    pageFrames[index] = page
    local ok, err = pcall(def.build, page)
    if not ok then
        geterrorhandler()(err) -- one broken page shouldn't take the whole window down
    end
    return page
end

-- NEW tags on sidebar headings: shown while any page under the heading is still new (Spotlight.lua)
local headTags = {}
local function RefreshHeadTags()
    for _, h in ipairs(headTags) do
        local any = false
        for _, i in ipairs(h.pages) do
            if AnyNew(i) then any = true break end
        end
        h.tag:SetShown(any)
    end
end

--------------------------------------------------------------------------------
-- Cards: every section of a page (a header and everything under it, down to the next header) sits on a
-- softly lit panel with a thin edge. Worked out from where things really are once the page is laid out,
-- so pages don't have to do anything; called again whenever the page is shown or changes size.
--------------------------------------------------------------------------------
-- combined pages: each part sits under the one before it, as tall as its own content
local function StackParts(page)
    local y = 0
    for _, sub in ipairs(page.cysStack) do
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        sub:SetPoint("RIGHT", page, "RIGHT", 0, 0)
        local top = sub:GetTop()
        if not top then return end
        local low = top - (sub.contentHeight or 0)
        for _, c in ipairs({ sub:GetChildren() }) do
            local b = c:IsShown() and c:GetBottom()
            if b and b < low then low = b end
        end
        for _, r in ipairs({ sub:GetRegions() }) do
            local b = r:IsShown() and r:GetBottom()
            if b and b < low then low = b end
        end
        local h = math.max(top - low, 10)
        sub:SetHeight(h)
        y = y + h + 22
    end
    page.contentHeight = y
end

local function LayCards(page)
    if page and page.cysStack and page:IsShown() then
        StackParts(page)
        if window and window.content and pageFrames[current] == page then
            window.content:SetHeight(max(VIEW_H, page.contentHeight or 0))
        end
    end
    local allHeads = {}
    for _, h in ipairs(page and page.cysHeaders or {}) do allHeads[#allHeads + 1] = h end
    for _, sub in ipairs(page and page.cysStack or {}) do
        for _, h in ipairs(sub.cysHeaders or {}) do allHeads[#allHeads + 1] = h end
    end
    if not (page and page:IsShown() and #allHeads > 0) then return end
    local pTop, pLeft, pBottom = page:GetTop(), page:GetLeft(), page:GetBottom()
    if not (pTop and pLeft and pBottom) then return end
    local heads = {}
    for _, h in ipairs(allHeads) do
        if h:IsShown() and h:GetTop() then heads[#heads + 1] = h end
    end
    table.sort(heads, function(a, b)
        local ta, tb = a:GetTop(), b:GetTop()
        if ta ~= tb then return ta > tb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    -- everything on the page that could belong to a section
    local items = {}
    local function Collect(fr)
        for _, c in ipairs({ fr:GetChildren() }) do
            if c:IsShown() and not c.isCardTitle then
                if c.cysSubPage then Collect(c) else items[#items + 1] = c end
            end
        end
        for _, r in ipairs({ fr:GetRegions() }) do
            if r:IsShown() and not r.isCard then items[#items + 1] = r end
        end
    end
    Collect(page)
    page.cards = page.cards or {}
    local lowest = 0
    for i, h in ipairs(heads) do
        local top = h:GetTop()
        local nextTop = heads[i + 1] and heads[i + 1]:GetTop() or -math.huge
        local bottom = h:GetBottom() or top
        for _, it in ipairs(items) do
            local t, b = it:GetTop(), it:GetBottom()
            -- (frames stretched to the page's bottom edge are containers, not content)
            if t and b and t <= top + 1 and t > nextTop + 1 and b < bottom and b > pBottom + 1 then bottom = b end
        end
        local card = page.cards[i]
        if not card then
            card = {}
            card.bg = page:CreateTexture(nil, "BACKGROUND", nil, -6)
            card.bg.isCard = true
            card.edges = {}
            for k = 1, 4 do
                local t = page:CreateTexture(nil, "BACKGROUND", nil, -5)
                t:SetColorTexture(T.line[1], T.line[2], T.line[3], 1)
                t.isCard = true
                card.edges[k] = t
            end
            page.cards[i] = card
        end
        local x = (h:GetLeft() or pLeft) - pLeft - CARD_PAD
        local w = (h:GetWidth() or 300) + CARD_PAD + 2
        local y1 = math.min(top - pTop + 6, 0) -- never above the page (the scroll area would cut it off)
        local hgt = (pTop + y1) - bottom + 12
        card.bg:ClearAllPoints()
        card.bg:SetPoint("TOPLEFT", page, "TOPLEFT", x, y1)
        card.bg:SetSize(w, hgt)
        card.bg:SetColorTexture(T.card[1] + 0.012, T.card[2] + 0.01, T.card[3] + 0.006, 0.92)
        card.bg:Show()
        local e = card.edges
        for k = 1, 4 do e[k]:ClearAllPoints() end
        e[1]:SetPoint("TOPLEFT", card.bg, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", card.bg, "TOPRIGHT"); e[1]:SetHeight(1)
        e[2]:SetPoint("BOTTOMLEFT", card.bg, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", card.bg, "BOTTOMRIGHT"); e[2]:SetHeight(1)
        e[3]:SetPoint("TOPLEFT", card.bg, "TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT", card.bg, "BOTTOMLEFT"); e[3]:SetWidth(1)
        e[4]:SetPoint("TOPRIGHT", card.bg, "TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT", card.bg, "BOTTOMRIGHT"); e[4]:SetWidth(1)
        for k = 1, 4 do e[k]:Show() end
        lowest = math.max(lowest, -(y1 - hgt))
    end
    for i = #heads + 1, #page.cards do
        local card = page.cards[i]
        card.bg:Hide()
        for k = 1, 4 do card.edges[k]:Hide() end
    end
    -- keep the page scrollable down to the last card
    if lowest + 8 > (page.contentHeight or 0) then
        page.contentHeight = lowest + 8
        if window and window.content and pageFrames[current] == page then
            window.content:SetHeight(max(VIEW_H, page.contentHeight))
        end
    end
end
CUI.RelayoutSettingsPage = function(page)
    if C_Timer then C_Timer.After(0, function() pcall(LayCards, page) end) end
end

local CreateTab -- defined after SelectPage (its click selects a page)
local function SelectPage(index)
    current = index
    for i, f in pairs(pageFrames) do f:Hide() end
    local page = EnsurePage(index)
    window.content:SetHeight(max(VIEW_H, page.contentHeight or 0))
    window.scroll:SetVerticalScroll(0)
    page:Show()
    local g = tabGroup[index]
    for i, b in pairs(pageButtons) do
        local selected = (i == index) or (g ~= nil and g.pages[1] == i)
        b.accent:SetShown(selected)
        if selected then b.bg:Show(); if b.hover then b.hover:Hide() end else b.bg:Hide() end
        local c = selected and T.accent or (b.baseColor or T.text)
        b.label:SetTextColor(c[1], c[2], c[3])
        if selected and b.newTag then
            if CUI.MarkPageSeen then CUI:MarkPageSeen(CUI.pages[index].title) end
            b.newTag:SetShown(AnyNew(i))
            RefreshHeadTags()
        end
    end
    local def = CUI.pages[index]
    -- tabs along the top for merged pages; the page area moves down under them
    local bar = window.tabBar
    if bar then
        local n = 0
        if g then
            local size, padX = 12, 24
            local total = 0
            for _, pi in ipairs(g.pages) do total = total + #TabName(pi) * 7 + padX + 2 end
            if total > CONTENT_W then size, padX = 11, 14 end
            for k, pi in ipairs(g.pages) do
                n = k
                local tb = bar.btns[k]
                if not tb then tb = CreateTab(bar); bar.btns[k] = tb end
                tb.index = pi
                tb.label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "")
                tb.label:SetText(TabName(pi))
                tb:SetWidth(tb.label:GetStringWidth() + padX)
                tb:ClearAllPoints()
                if k == 1 then tb:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 1)
                else tb:SetPoint("BOTTOMLEFT", bar.btns[k - 1], "BOTTOMRIGHT", 2, 0) end
                tb.sel = (pi == index)
                local c = tb.sel and T.accent or T.text
                tb.label:SetTextColor(c[1], c[2], c[3])
                tb.bg:SetShown(tb.sel)
                tb.under:SetShown(tb.sel)
                tb.newTag:SetShown(not tb.sel and CUI.IsNewPage and CUI:IsNewPage(CUI.pages[pi].title) or false)
                tb:Show()
            end
        end
        for k = n + 1, #bar.btns do bar.btns[k]:Hide() end
        bar:SetShown(g ~= nil)
        local top = -PAD - (g and (TAB_H + 8) or 0)
        window.scroll:ClearAllPoints()
        window.scroll:SetPoint("TOPLEFT", window.sidebar, "TOPRIGHT", PAD - CARD_PAD, top)
        window.scroll:SetPoint("BOTTOMRIGHT", window.footer, "TOPRIGHT", -PAD, PAD)
    end
    if window.where then
        local b = pageButtons[g and g.pages[1] or index]
        local sec = b and b.section
        local name = g and (g.name .. "  >  " .. TabName(index)) or (LABELS[def.title] or def.title)
        window.where:SetText(sec and ("|cFF9A9A9A" .. sec .. "  >|r  |cFFFFD100" .. name .. "|r") or ("|cFFFFD100" .. name .. "|r"))
    end
    if def.onShow then def.onShow(page) end
    UpdateFooter()
    CUI.RelayoutSettingsPage(page)
end

CreateTab = function(bar)
    local tb = CreateFrame("Button", nil, bar)
    tb:SetHeight(TAB_H - 4)
    tb.bg = W.Texture(tb, "BACKGROUND", T.selected)
    tb.bg:SetAllPoints()
    tb.hover = W.Texture(tb, "BACKGROUND", T.hover, 1)
    tb.hover:SetAllPoints()
    tb.hover:Hide()
    tb.under = W.Texture(tb, "ARTWORK", T.accent)
    tb.under:SetPoint("BOTTOMLEFT"); tb.under:SetPoint("BOTTOMRIGHT"); tb.under:SetHeight(2)
    tb.label = W.Text(tb, 12, T.text, "CENTER")
    tb.label:SetPoint("CENTER", 0, 1)
    tb.newTag = W.Text(tb, 8, T.green)
    tb.newTag:SetFont(CysUICompat.Font(), CysUICompat.FontSize(8), "OUTLINE")
    tb.newTag:SetPoint("TOPRIGHT", -2, -1)
    tb.newTag:SetText("NEW")
    tb:SetScript("OnEnter", function(s) if not s.sel then s.hover:Show() end end)
    tb:SetScript("OnLeave", function(s) s.hover:Hide() end)
    tb:SetScript("OnClick", function(s)
        s.hover:Hide()
        SelectPage(s.index)
        if window.searchHits and window.ShowHit then window.ShowHit(s.index) end
    end)
    return tb
end

local function CreateWindow()
    CombinePages()
    BuildTabGroups()
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
    -- a brighter gold line under the crest that fades out toward the right
    local hglow = header:CreateTexture(nil, "BORDER", nil, 2)
    hglow:SetTexture("Interface\\Buttons\\WHITE8X8")
    hglow:SetPoint("BOTTOMLEFT", 0, 0); hglow:SetHeight(2); hglow:SetWidth(360)
    local gl = T.glow
    if not (CreateColor and pcall(hglow.SetGradient, hglow, "HORIZONTAL",
        CreateColor(gl[1], gl[2], gl[3], 0.9), CreateColor(gl[1], gl[2], gl[3], 0))) then
        hglow:Hide()
    end
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    -- brand banner: a soft gold wash from the left, the round Cys crest, a big title and the client / version line
    local wash = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    wash:SetPoint("TOPLEFT"); wash:SetPoint("BOTTOMLEFT"); wash:SetWidth(420)
    local br = T.brand
    if not (CreateColor and pcall(wash.SetGradient, wash, "HORIZONTAL",
        CreateColor(br[1], br[2], br[3], 0.16), CreateColor(br[1], br[2], br[3], 0))) then
        wash:SetColorTexture(br[1], br[2], br[3], 0.05)
    end
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetTexture("Interface\\AddOns\\CysUI\\Media\\CysLogo")
    crest:SetSize(50, 50)
    crest:SetPoint("LEFT", 10, 0)
    local title = header:CreateFontString(nil, "OVERLAY")
    if not title:SetFont("Fonts\\MORPHEUS.TTF", 26, "") then title:SetFont(CysUICompat.Font(), CysUICompat.FontSize(22), "OUTLINE") end
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, -4)
    title:SetText("Cys's UI")
    local sub = W.Text(header, 10, T.brand)
    sub:SetFont(CysUICompat.Font(), CysUICompat.FontSize(10), "")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
    local flavor = tostring(CUI.flavor or ""):upper():gsub("(%S)", "%1 "):gsub(" +$", "")
    sub:SetText(flavor .. "    |cFF9A9A9Av" .. CUI:GetVersion("CysUI") .. "|r")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -6, 0)
    close.hl = close:CreateTexture(nil, "BACKGROUND")
    close.hl:SetAllPoints()
    close.hl:SetColorTexture(1, 0.3, 0.3, 0.14)
    close.hl:Hide()
    close.text = W.Glyph(close, "close", 10, T.desc, 2)
    close.text:SetPoint("CENTER", 0, 0)
    close:SetScript("OnEnter", function(s) s.hl:Show(); s.text:SetColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function(s) s.hl:Hide(); s.text:SetColor(T.desc) end)
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
    -- where you are: "Interface  >  Chat" (set by SelectPage)
    f.where = W.Text(footer, 11, T.desc)
    f.where:SetPoint("LEFT", 12, 0)
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
            local i = byTitle[title]
            if i then
                placed[i] = true
                local g = tabGroup[i]
                if not g or g.pages[1] == i then list[#list + 1] = i end
            end
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
    for i in ipairs(CUI.pages) do if not placed[i] and not tabGroup[i] then other[#other + 1] = i end end
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
            local tag = W.Text(h, 9, T.green)
            tag:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
            tag:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
            tag:SetText("NEW")
            headTags[#headTags + 1] = { tag = tag, pages = section.pages }
            h.sign = W.Glyph(h, "down", 7, T.accent, 1.5)
            h.sign:SetPoint("RIGHT", -12, 0)
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
            if AnyNew(i) then
                -- a small gold NEW tag until the page is opened once (Spotlight.lua)
                b.newTag = W.Text(b, 9, T.accent)
                b.newTag:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
                b.newTag:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
                b.newTag:SetText("NEW")
            end
            b.hover = W.Texture(b, "BACKGROUND", T.hover, 1)
            b.hover:SetAllPoints()
            b.hover:Hide()
            b:SetScript("OnEnter", function(s) if current ~= i then s.hover:Show() end end)
            b:SetScript("OnLeave", function(s) s.hover:Hide() end)
            b.section = section.level == 2 and ("Class  >  " .. section.name) or section.name
            b:SetScript("OnClick", function()
                -- while searching, a merged entry opens its first matching tab
                local target = i
                if f.searchHits and tabGroup[i] and not f.searchHits[i] then
                    for _, pi in ipairs(tabGroup[i].pages) do
                        if f.searchHits[pi] then target = pi break end
                    end
                end
                SelectPage(target)
                if f.searchHits and f.ShowHit then f.ShowHit(target) end
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
                elseif f.searchHits[e.index] or (tabGroup[e.index] and (function()
                    for _, pi in ipairs(tabGroup[e.index].pages) do if f.searchHits[pi] then return true end end
                end)()) then
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
                h.sign:SetKind(h.empty and "none" or (fold[e.key] and "right" or "down"))
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
            local alias = ""
            for a in pairs(def.aliases or {}) do alias = alias .. " " .. a end
            local list = { { text = ((LABELS[def.title] or def.title) .. " " .. def.title .. " " .. (tabGroup[i] and tabGroup[i].name or "") .. alias):lower() } }
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
    -- profile switcher beside the search box (Profile.lua); the swap happens on the next reload
    if CUI.ProfileOptions then
        local pdd = W.Dropdown(header, 128, CUI.ProfileOptions, function() return CUI:NextProfile() end,
            function(v) CUI:SwitchProfile(v) end, "Profile: ")
        pdd:SetPoint("RIGHT", box, "LEFT", -8, 0)
        pdd:HookScript("OnEnter", function(s)
            if s.label.IsTruncated and s.label:IsTruncated() then return end
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Profile", 1, 0.82, 0)
            GameTooltip:AddLine("Pick a saved setup; it loads when you press Reload UI. Manage them on the Profiles page.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        pdd:HookScript("OnLeave", function() GameTooltip:Hide() end)
        f.profileDD = pdd
    end
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "")
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
    clear.text = W.Glyph(clear, "close", 7, T.desc, 1.5)
    clear.text:SetPoint("CENTER")
    clear:SetScript("OnEnter", function(s) s.text:SetColor(T.accent) end)
    clear:SetScript("OnLeave", function(s) s.text:SetColor(T.desc) end)
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
                if (pageButtons[i] or tabGroup[i]) and Matches(i, term) then
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
    scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD - CARD_PAD, -PAD)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -PAD, PAD)
    scroll:EnableMouseWheel(true)
    f.scroll = scroll
    f.sidebar, f.footer = sidebar, footer
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, -PAD + 4)
    tabBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -HEADER_H - PAD + 4)
    tabBar:SetHeight(TAB_H)
    local tline = W.Texture(tabBar, "BORDER", T.line)
    tline:SetPoint("BOTTOMLEFT"); tline:SetPoint("BOTTOMRIGHT"); tline:SetHeight(1)
    tabBar.btns = {}
    tabBar:Hide()
    f.tabBar = tabBar
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(CONTENT_W + CARD_PAD, VIEW_H)
    scroll:SetScrollChild(f.content)

    local thumb = W.Texture(f, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.5 })
    thumb:Hide()
    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange()
        if not range or range <= 0 then
            thumb:Hide()
            if f.scrollGrab and not f.scrollGrab.dragging then f.scrollGrab:Hide() end
            return
        end
        local viewH = scroll:GetHeight()
        local thumbH = max(24, viewH * viewH / (viewH + range))
        local y = (scroll:GetVerticalScroll() / range) * (viewH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetSize(f.scrollGrab and (f.scrollGrab.hot and 5 or 3) or 3, thumbH)
        thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -y)
        thumb:Show()
        if f.scrollGrab then f.scrollGrab:Show() end
    end

    -- the scroll bar can be dragged: grab the thumb, or click anywhere along its track to jump there
    local grab = CreateFrame("Frame", nil, f)
    grab:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 1, 0)
    grab:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 1, 0)
    grab:SetWidth(PAD - 2)
    grab:SetFrameLevel(scroll:GetFrameLevel() + 5)
    grab:EnableMouse(true)
    grab:Hide()
    f.scrollGrab = grab
    local function ThumbHeight(range)
        local viewH = scroll:GetHeight()
        return max(24, viewH * viewH / (viewH + range)), viewH
    end
    local function DragTo()
        local range = scroll:GetVerticalScrollRange()
        local top = scroll:GetTop()
        if not (range and range > 0 and top) then return end
        local thumbH, viewH = ThumbHeight(range)
        local _, cy = GetCursorPosition()
        cy = cy / scroll:GetEffectiveScale()
        local frac = (top - cy - (grab.offset or thumbH / 2)) / max(1, viewH - thumbH)
        scroll:SetVerticalScroll(max(0, math.min(1, frac)) * range)
    end
    local function Paint()
        thumb:SetAlpha((grab.hot or grab.dragging) and 0.95 or 0.5)
        UpdateThumb()
    end
    grab:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local range = scroll:GetVerticalScrollRange()
        local top = scroll:GetTop()
        if not (range and range > 0 and top) then return end
        local thumbH, viewH = ThumbHeight(range)
        local _, cy = GetCursorPosition()
        cy = cy / scroll:GetEffectiveScale()
        local off = top - (scroll:GetVerticalScroll() / range) * (viewH - thumbH) - cy
        self.offset = (off >= 0 and off <= thumbH) and off or thumbH / 2 -- on the thumb: keep the grip point
        self.dragging = true
        self:SetScript("OnUpdate", DragTo)
        DragTo()
        Paint()
    end)
    local function Drop(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        Paint()
    end
    grab:SetScript("OnMouseUp", Drop)
    grab:SetScript("OnHide", function(self) self.hot = nil; Drop(self) end)
    grab:SetScript("OnEnter", function(self) self.hot = true; Paint() end)
    grab:SetScript("OnLeave", function(self) self.hot = nil; Paint() end)
    grab:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(max(0, math.min(scroll:GetVerticalScroll() - delta * 40, scroll:GetVerticalScrollRange())))
    end)
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

    RefreshHeadTags()
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
        if page.title == pageTitle or (page.aliases and page.aliases[pageTitle]) then SelectPage(i) return end
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
        -- a plain Hide: HideUIPanel from addon code taints Blizzard's window manager (on WoW Forever the map's
        -- quest pins then get blocked the next time it opens)
        if GameMenuFrame and GameMenuFrame:IsShown() then GameMenuFrame:Hide() end
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
