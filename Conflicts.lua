--------------------------------------------------------------------------------
-- Cys's UI - Addon conflicts
--
-- Some addons do the same job as one of Cys's UI's modules (ElvUI, Plater, Postal, Bagnon...).
-- Running both doubles things up, so when one is loaded this asks, once: use Cys's version
-- (the other addon is switched off, not deleted) or keep theirs (the matching Cys's module is
-- switched off). Either way it takes one reload. Change the answer later in /cui > Conflicts.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local AddOns = C_AddOns
local IsLoaded = (AddOns and AddOns.IsAddOnLoaded) or IsAddOnLoaded
local DisableAddOn = (AddOns and AddOns.DisableAddOn) or DisableAddOn
local EnableAddOn = (AddOns and AddOns.EnableAddOn) or EnableAddOn
local NumAddOns = (AddOns and AddOns.GetNumAddOns) or GetNumAddOns
local AddOnInfo = (AddOns and AddOns.GetAddOnInfo) or GetAddOnInfo

local ALL_ELVUI = { "unitframes", "castbar", "nameplates", "actionbars", "chat", "minimap", "infobar", "bags", "bank",
    "tooltip", "skins", "micromenu", "xpbar", "playerAuras", "grouploot", "scale", "raidframes" }

-- addon = the folder to look for; match = also switch off every folder starting like this (plugins, options);
-- modules = the Cys's UI modules it overlaps
local LIST = {
    { addon = "ElvUI",              label = "ElvUI",              match = "^ElvUI", modules = ALL_ELVUI },
    { addon = "Plater",             label = "Plater",             modules = { "nameplates" } },
    { addon = "Platynator",         label = "Platynator",         modules = { "nameplates" } },
    { addon = "TidyPlates",         label = "TidyPlates",         match = "^TidyPlates", modules = { "nameplates" } },
    { addon = "Postal",             label = "Postal",             modules = { "mail" } },
    { addon = "Bagnon",             label = "Bagnon",             match = "^Bagnon", modules = { "bags", "bank" } },
    { addon = "ArkInventory",       label = "ArkInventory",       match = "^ArkInventory", modules = { "bags", "bank" } },
    { addon = "AdiBags",            label = "AdiBags",            match = "^AdiBags", modules = { "bags", "bank" } },
    { addon = "Baganator",          label = "Baganator",          match = "^Baganator", modules = { "bags", "bank" } },
    { addon = "ShadowedUnitFrames", label = "Shadowed Unit Frames", match = "^ShadowedUnitFrames", modules = { "unitframes" } },
    { addon = "ZPerl",              label = "Z-Perl",             match = "^ZPerl", modules = { "unitframes" } },
    { addon = "PitBull4",           label = "PitBull Unit Frames", match = "^PitBull4", modules = { "unitframes" } },
    { addon = "Grid2",              label = "Grid2",              match = "^Grid2", modules = { "raidframes" } },
    { addon = "VuhDo",              label = "VuhDo",              modules = { "raidframes" } },
    { addon = "Healbot",            label = "HealBot",            match = "^HealBot", modules = { "raidframes" } },
    { addon = "Bartender4",         label = "Bartender4",         modules = { "actionbars" } },
    { addon = "Dominos",            label = "Dominos",            match = "^Dominos", modules = { "actionbars" } },
    { addon = "Chatter",            label = "Chatter",            modules = { "chat" } },
    { addon = "Prat-3.0",           label = "Prat",               match = "^Prat", modules = { "chat" } },
    { addon = "Quartz",             label = "Quartz",             modules = { "castbar" } },
    { addon = "MinimapButtonButton", label = "MinimapButtonButton", match = "^MinimapButtonButton", modules = { "mmbuttons" } },
    { addon = "MBB",                label = "Minimap Button Bag", modules = { "mmbuttons" } },
    { addon = "SexyMap",            label = "SexyMap",            modules = { "minimap" } },
    { addon = "TipTac",             label = "TipTac",             match = "^TipTac", modules = { "tooltip" } },
    { addon = "TitanClassic",       label = "Titan Panel",        match = "^Titan", modules = { "infobar" } },
}

local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.conflicts = CysUIDB.conflicts or {}
    return CysUIDB.conflicts
end

local function Found()
    local out = {}
    for _, c in ipairs(LIST) do
        if IsLoaded and IsLoaded(c.addon) then out[#out + 1] = c end
    end
    return out
end

local function ModuleNames(c)
    local names = {}
    for _, key in ipairs(c.modules) do
        local def = CUI.modules[key]
        if def and CUI:ClassAllowed(def) then names[#names + 1] = def.name end
    end
    return table.concat(names, ", ")
end

-- every installed folder this entry covers (the addon itself plus its plugins / options)
local function Folders(c)
    local out = { c.addon }
    if c.match and NumAddOns and AddOnInfo then
        for i = 1, NumAddOns() do
            local name = AddOnInfo(i)
            if name and name ~= c.addon and name:find(c.match) then out[#out + 1] = name end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Applying the answers
--------------------------------------------------------------------------------
local function Apply(found, choice)
    local covered, off = {}, {}
    for _, c in ipairs(found) do
        local pick = choice[c.addon] or "cys"
        DB()[c.addon] = pick
        for _, key in ipairs(c.modules) do
            covered[key] = true
            if pick == "theirs" then off[key] = true end
        end
        if pick == "cys" then
            local me = UnitName("player")
            for _, folder in ipairs(Folders(c)) do pcall(DisableAddOn, folder, me) end
        end
    end
    for key in pairs(covered) do CUI:SetModuleEnabled(key, not off[key]) end
    ReloadUI()
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local frame

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "CysUIConflicts", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(560, 200)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    W.Texture(frame, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(frame, 1, T.border, "BORDER")
    local band = W.Texture(frame, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.10 }, 1)
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(30)

    frame.title = W.Text(frame, 13, T.accent, "CENTER")
    frame.title:SetPoint("TOP", 0, -9)
    frame.title:SetText("Cys's UI - other addons found")

    frame.intro = W.Text(frame, 11, T.text)
    frame.intro:SetPoint("TOPLEFT", 16, -42)
    frame.intro:SetWidth(528)
    frame.intro:SetJustifyV("TOP")
    frame.intro:SetSpacing(3)
    frame.intro:SetText("These addons do the same job as parts of Cys's UI. Pick one for each so they don't fight. "
        .. "Nothing is deleted - switched-off addons stay installed, and you can change your mind in /cui > Conflicts.")

    frame.rows = {}
    frame.apply = W.Button(frame, 170, 26, "Apply and reload", true)
    frame.later = W.Button(frame, 130, 26, "Ask me later")
    frame.later:SetScript("OnClick", function() frame:Hide() end)
    frame.never = W.Button(frame, 130, 26, "Don't ask again")
    frame.never:SetScript("OnClick", function()
        CysUIDB.conflictsSnoozed = true
        frame:Hide()
        CUI:Print("Conflict window turned off. Reopen it any time in /cui > Conflicts.")
    end)
    tinsert(UISpecialFrames, "CysUIConflicts")
    return frame
end

local function Show(found)
    found = found or Found()
    if #found == 0 then
        CUI:Print("No conflicting addons found.")
        return
    end
    if InCombatLockdown() then CUI:Print("Conflict check waits until you leave combat.") return end
    local f = Build()
    local choice = {}
    for _, row in ipairs(f.rows) do row:Hide() end
    local y = -88
    for i, c in ipairs(found) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetSize(528, 62)
            W.Texture(row, "BACKGROUND", T.field):SetAllPoints()
            row.edges = W.Border(row, 1, T.line, "BORDER")
            row.name = W.Text(row, 13, T.accent)
            row.name:SetPoint("TOPLEFT", 10, -8)
            row.info = W.Text(row, 11, T.desc)
            row.info:SetPoint("TOPLEFT", 10, -26)
            row.info:SetWidth(330)
            row.info:SetJustifyV("TOP")
            row.cys = W.Button(row, 150, 24, "Use Cys's version")
            row.cys:SetPoint("TOPRIGHT", -170, -8)
            row.theirs = W.Button(row, 150, 24, "Keep theirs")
            row.theirs:SetPoint("TOPRIGHT", -10, -8)
            f.rows[i] = row
        end
        row.name:SetText(c.label)
        row.info:SetText("Replaces Cys's: " .. ModuleNames(c))
        row:SetHeight(math.max(62, row.info:GetStringHeight() + 40))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, y)
        y = y - row:GetHeight() - 6
        choice[c.addon] = DB()[c.addon] or "cys"
        local function Paint()
            row.cys:SetPrimary(choice[c.addon] == "cys")
            row.theirs:SetPrimary(choice[c.addon] == "theirs")
        end
        row.cys.label:SetText("Use Cys's version")
        row.theirs.label:SetText("Keep " .. c.label)
        row.cys:SetScript("OnClick", function() choice[c.addon] = "cys"; Paint() end)
        row.theirs:SetScript("OnClick", function() choice[c.addon] = "theirs"; Paint() end)
        Paint()
        row:Show()
    end
    f:SetHeight(-y + 56)
    f.apply:ClearAllPoints()
    f.apply:SetPoint("BOTTOMRIGHT", -16, 14)
    f.later:ClearAllPoints()
    f.later:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)
    f.never:ClearAllPoints()
    f.never:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
    f.apply:SetScript("OnClick", function() Apply(found, choice) end)
    f:Show()
end

CUI.Conflicts = { Show = Show, Found = Found }

--------------------------------------------------------------------------------
-- On login: apply earlier "keep theirs" answers quietly, ask about anything new
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(8, function()
        if not CysUIDB then return end
        local ask = {}
        for _, c in ipairs(Found()) do
            local pick = DB()[c.addon]
            if pick == "theirs" then
                -- keep their version: make sure the matching Cys's modules stay off
                for _, key in ipairs(c.modules) do CUI:SetModuleEnabled(key, false) end
            else
                ask[#ask + 1] = c -- undecided, or chose Cys's but it is still switched on for this character
            end
        end
        if #ask > 0 and not CysUIDB.conflictsSnoozed then Show(ask) end
    end)
end)

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Conflicts", function(page)
    local width = 480
    W.Header(page, "Addon conflicts", width):SetPoint("TOPLEFT", 0, -4)
    local info = W.Text(page, 12, T.text)
    info:SetPoint("TOPLEFT", 4, -34)
    info:SetWidth(width)
    info:SetJustifyV("TOP")
    info:SetSpacing(4)
    local btn = W.Button(page, 190, 24, "Review conflicts now", true)
    btn:SetScript("OnClick", function() CysUIDB.conflictsSnoozed = nil; Show(Found()) end)
    page.refresh = function()
        local found = Found()
        local lines = {}
        for _, c in ipairs(found) do
            local pick = DB()[c.addon]
            lines[#lines + 1] = format("|cFFFFD100%s|r - %s", c.label,
                pick == "theirs" and "you kept theirs (Cys's matching modules are off)"
                or pick == "cys" and "you chose Cys's (this addon should be switched off - reload if it is still running)"
                or "not decided yet")
        end
        info:SetText(#found == 0 and "No addons that overlap with Cys's UI are running right now."
            or ("Running now that overlap with Cys's UI:\n" .. table.concat(lines, "\n")))
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 4, -(info:GetStringHeight() + 52))
    end
    page.refresh()
end, function(page) if page.refresh then page.refresh() end end)
