--------------------------------------------------------------------------------
-- Cys's UI - core
--
-- The small hub the other Cys addons plug into:
--   * a module registry, so every addon shows up in /cui with an on/off switch
--   * saved settings (CysUIDB)
--   * client detection (Classic Era vs WoW Forever) and /cui debug for compatibility checks
--   * shared widgets (Widgets.lua), the settings window (Config.lua), Vendor module
--
-- A module addon (bags, armory, rolls...) starts its main file with:
--
--   if CysUI then
--       CysUI:RegisterModule({ key = "bags", name = "Cys's Bags", addon = "CysBags",
--                              desc = "What it does", open = function() ... end })
--       if not CysUI:IsModuleEnabled("bags") then return end   -- switched off in /cui
--   end
--
-- and lists `## OptionalDeps: CysUI` in its .toc (so this addon loads first).
-- Without CysUI installed the module simply runs on its own.
--------------------------------------------------------------------------------
local ADDON = ...

CysUI = CysUI or {}
local CUI = CysUI
CUI.modules = CUI.modules or {}
CUI.order = CUI.order or {}
CUI.pages = CUI.pages or {}

local format = string.format

--------------------------------------------------------------------------------
-- Client detection
--------------------------------------------------------------------------------
local _, buildNumber, _, interface = GetBuildInfo()
interface = tonumber(interface) or 0
CUI.interface, CUI.build = interface, buildNumber
if interface >= 16000 and interface < 17000 then
    CUI.flavor, CUI.isForever = "WoW Forever", true
elseif interface >= 11000 and interface < 12000 then
    CUI.flavor, CUI.isEra = "Classic Era", true
else
    CUI.flavor = "Unknown client"
end

--------------------------------------------------------------------------------
-- AddOn API wrappers (these moved into C_AddOns on newer clients)
--------------------------------------------------------------------------------
local AddOns = C_AddOns
local GetMeta = (AddOns and AddOns.GetAddOnMetadata) or GetAddOnMetadata
local IsLoaded = (AddOns and AddOns.IsAddOnLoaded) or IsAddOnLoaded
local UpdateMemory = (AddOns and AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
local GetMemory = (AddOns and AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage

function CUI:GetVersion(addon)
    return (GetMeta and GetMeta(addon, "Version")) or "?"
end

function CUI:IsAddonLoaded(addon)
    return IsLoaded and IsLoaded(addon) and true or false
end

function CUI:UpdateMemory()
    if UpdateMemory then UpdateMemory() end
end

function CUI:GetMemoryKB(addon)
    if not GetMemory then return nil end
    return GetMemory(addon)
end

function CUI:Print(msg)
    print("|cFFFFD100[Cys's UI]|r " .. msg)
end

--------------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------------
local DEFAULTS = {
    borderColor = "gold", -- gold / class / black / grey
    modules = {}, -- [key] = false when switched off; missing = on
    vendor = { autoRepair = true, autoSell = false, showButton = true },
    tooltip = { skin = true, qualityBorder = true, sellPrice = true, classColors = true, healthBar = true,
                targetLine = true, anchorCursor = false, cursorLift = 20, cursorShift = 160, scale = 100,
                showIDs = false, hideUnitInCombat = false },
    minimap = { zoneText = true, coords = true, wheelZoom = true },
    unitframes = { player = true, target = true, targettarget = true, pet = true, party = true,
                   classColors = true, healthText = "both" },
    castbar = { player = true, target = true, icon = true, time = true },
    update = { enabled = true, notified = "0.0.0" },
    scale = { mode = "off", percent = 100, prompted = false },
    nameplates = { width = 112, height = 10, showLevel = true, healthText = true, classColors = true,
                   targetHighlight = true, myDebuffs = true, castBar = true, threat = "auto" },
    chat = { skin = true, hideButtons = true, tabsSolid = true, classColors = true, timestamps = false, use24h = false, fontSize = 14 },
    layout = {},      -- saved positions / sizes / scales from layout mode
    snap = true,      -- snap dragged elements to a grid
    snapSize = 8,
    infobar = {
        shown = true,
        use24h = false,
        order = { "combat", "guild", "friends", "durability", "bags", "gold", "fps", "clock" },
        enabled = { combat = true, guild = true, friends = true, durability = true,
                    bags = true, gold = true, fps = true, clock = true },
    },
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

--------------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------------
function CUI:IsModuleEnabled(key)
    local db = CysUIDB
    if not (db and db.modules) then return true end
    return db.modules[key] ~= false
end

function CUI:SetModuleEnabled(key, enabled)
    if not (CysUIDB and CysUIDB.modules) then return end
    CysUIDB.modules[key] = enabled and true or false
end

-- def: key, name, desc, addon (the addon folder), requires (another module key),
--      open (function), onEnable (function, for modules that live inside this addon),
--      body (function: the module's whole file, run once settings are loaded), class (e.g. "SHAMAN")
function CUI:RegisterModule(def)
    if type(def) ~= "table" or not def.key then return end
    if not self.modules[def.key] then self.order[#self.order + 1] = def.key end
    self.modules[def.key] = def
    -- remember what state this session started in, so the menu can tell when a reload is needed
    if CysUIDB then def.loadedEnabled = self:IsModuleEnabled(def.key) end
end

-- A module can be limited to a class: class = "SHAMAN" (or a list of class tokens).
function CUI:ClassAllowed(def)
    local want = def and def.class
    if not want then return true end
    local _, mine = UnitClass("player")
    if type(want) == "table" then
        for _, c in ipairs(want) do if c == mine then return true end end
        return false
    end
    return want == mine
end

function CUI:HasPendingReload()
    for _, key in ipairs(self.order) do
        local def = self.modules[key]
        if def.loadedEnabled ~= nil and def.loadedEnabled ~= self:IsModuleEnabled(key) then return true end
    end
    return false
end

-- Settings pages for the /cui window: build(parent) runs the first time the page is shown.
function CUI:RegisterPage(title, build, onShow)
    self.pages[#self.pages + 1] = { title = title, build = build, onShow = onShow }
end

--------------------------------------------------------------------------------
-- /cui debug: handy when checking a new client (Forever) - paste the output to me
--------------------------------------------------------------------------------
local API_CHECKS = {
    "C_Container", "C_AddOns", "C_Timer", "C_EquipmentSet", "TooltipDataProcessor",
    "GetItemInfoInstant", "EquipItemByName", "PutItemInBag", "PickupBagFromSlot",
    "CharacterFrame", "CharacterHeadSlot", "PaperDollFrame", "BankFrame", "MerchantFrame",
    "ContainerFrame1", "ContainerFrameCombinedBags", "GetRepairAllCost", "UnitIsGroupLeader",
    "GetSpellInfo", "GetSpellPowerCost", "GetItemInfo", "UnitAura", "UnitBuff", "UnitGetIncomingHeals",
    "GetNumSkillLines", "GetSkillLineInfo", "GetSpellBonusHealing", "BankButtonIDToInvSlotID", "LootFrame",
    "UIDropDownMenu_Initialize", "SetItemRef", "HandleModifiedItemClick", "GetMouseFoci",
    "C_Item", "C_Spell", "C_UnitAuras", "C_Map", "C_NamePlate", "C_CVar",
}

function CUI:DebugLines()
    local L = {}
    local version, build = GetBuildInfo()
    L[#L + 1] = format("%s - client %s (build %s), interface %d, Cys's UI %s",
        self.flavor, tostring(version), tostring(build), self.interface, self:GetVersion(ADDON))
    for _, key in ipairs(self.order) do
        local def = self.modules[key]
        local on = self:IsModuleEnabled(key)
        local note = (def.loadedEnabled ~= nil and def.loadedEnabled ~= on) and "  (reload pending)" or ""
        L[#L + 1] = format("  %-8s %s%s", key, on and "on" or "OFF", note)
    end
    local present, missing = {}, {}
    for _, name in ipairs(API_CHECKS) do
        if _G[name] ~= nil then present[#present + 1] = name else missing[#missing + 1] = name end
    end
    L[#L + 1] = "  present: " .. table.concat(present, ", ")
    L[#L + 1] = "  missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none")
    local sh = CysUICompat and CysUICompat.shimmed or {}
    L[#L + 1] = "  filled in by Compat.lua: " .. (#sh > 0 and table.concat(sh, ", ") or "nothing (all old functions exist)")
    -- which other addons are loaded (clashes are often visible here)
    local names = {}
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if getNum and getInfo then
        for i = 1, getNum() do
            local name = getInfo(i)
            if name and self:IsAddonLoaded(name) then names[#names + 1] = name end
        end
    end
    L[#L + 1] = format("  addons loaded (%d): %s", #names, table.concat(names, ", "))
    return L
end

function CUI:Debug()
    local L = self:DebugLines()
    self:Print(L[1])
    for i = 2, #L do print(L[i]) end
end

--------------------------------------------------------------------------------
-- Events + slash commands
--------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        CysUIDB = CysUIDB or {}
        CopyDefaults(CysUIDB, DEFAULTS)
        CUI.db = CysUIDB
        if CUI.W and CUI.W.ApplyBorderStyle then CUI.W.ApplyBorderStyle() end
        -- modules registered before the settings existed (the ones living in this addon)
        for _, key in ipairs(CUI.order) do
            local def = CUI.modules[key]
            if def.loadedEnabled == nil then def.loadedEnabled = CUI:IsModuleEnabled(key) end
        end
        -- Modules whose code lives in Modules\... files (def.body) start now that the saved settings
        -- exist. Switched-off modules, other classes' modules and modules missing a requirement are skipped.
        for _, key in ipairs(CUI.order) do
            local def = CUI.modules[key]
            if def.body and def.loadedEnabled and CUI:ClassAllowed(def) then
                local req = def.requires and CUI.modules[def.requires]
                if not def.requires or (req and req.ran) then
                    local ok, err = pcall(def.body, ADDON, CUI)
                    def.ran = ok
                    if not ok then CUI:Print("|cFFFF4040" .. key .. " failed to load:|r " .. tostring(err)) end
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if CUI.W and CUI.W.ApplyBorderStyle then CUI.W.ApplyBorderStyle() end -- the class is known by now
        for _, key in ipairs(CUI.order) do
            local def = CUI.modules[key]
            if def.onEnable and def.loadedEnabled then
                local ok, err = pcall(def.onEnable)
                if not ok then CUI:Print("|cFFFF4040" .. key .. " failed to start:|r " .. tostring(err)) end
            end
        end
    end
end)

SLASH_CYSUI1 = "/cui"
SLASH_CYSUI2 = "/cysui"
SlashCmdList["CYSUI"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        CUI:Debug()
    elseif msg == "reload" then
        ReloadUI()
    elseif msg == "hit" then
        -- which frame is under the mouse? Hover the button that won't react, then wait 4 seconds
        CUI:Print("Put the mouse over the thing that won't react. Reading in 4 seconds...")
        C_Timer.After(4, function()
            local foci = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
            if not foci[1] then CUI:Print("Nothing under the mouse.") return end
            for _, f in ipairs(foci) do
                local chain, p = {}, f
                for _ = 1, 6 do
                    if not p then break end
                    chain[#chain + 1] = (p.GetDebugName and p:GetDebugName()) or (p.GetName and p:GetName()) or tostring(p)
                    p = p.GetParent and p:GetParent()
                end
                CUI:Print("Mouse is on: " .. table.concat(chain, "  <  ") .. "  [" .. tostring(f.GetFrameStrata and f:GetFrameStrata()) .. " " .. tostring(f.GetFrameLevel and f:GetFrameLevel()) .. "]")
            end
        end)
    elseif msg == "layout" or msg == "move" or msg == "unlock" then
        if CUI.ToggleLayout then CUI:ToggleLayout() end
    elseif msg == "" or msg == "config" or msg == "options" then
        if CUI.ToggleConfig then CUI:ToggleConfig() end
    else
        CUI:Print("Commands: /cui (settings)  /cui layout (move and resize)  /cui debug  /cui reload")
    end
end

--------------------------------------------------------------------------------
-- What's New
--------------------------------------------------------------------------------
if CysChangelog then
    CysChangelog:Register({
        name = "Cys's UI",
        version = CUI:GetVersion(ADDON) ~= "?" and CUI:GetVersion(ADDON) or "0.39.4",
        db = function() return CysUIDB end,
        entries = {
            { version = "0.39.4", date = "2026-10-30",
              added = {
                  "Take off gear: Alt-hover a slot on the character window for 'Take off' (this slot) and 'All' (everything that can lose durability; Shift also takes rings, trinkets and the rest). Handy for death runs. The Armory panel has Take off and Put back buttons, and /armory unequip, /armory putback.",
                  "Armory sets remember the Upgrade profile you were using when you saved them. Wearing the set switches to that profile, so you stop seeing tank upgrades while healing. Change it with /armory profile <set> <profile|none>.",
              },
            },
            { version = "0.39.3", date = "2026-10-30",
              added = {
                  "Update notice: Cys's UI shares its version with your guild, party and raid. If someone has a newer one, you get one line in chat with the download address. Switch it off in /cui -> General.",
              },
              fixed = {
                  "Trade window skin: odd child objects of the window no longer stop the skin (the 'GetObjectType on bad self' error).",
              },
            },
            { version = "0.39.2", date = "2026-10-29",
              fixed = {
                  "Upgrade page: the Guide button and the weight rows no longer sit under the scrollbar.",
              },
            },
            { version = "0.39.1", date = "2026-10-29",
              improved = {
                  "General page: the memory legend wraps onto two lines instead of being cut off.",
              },
            },
            { version = "0.39.0", date = "2026-10-29",
              improved = {
                  "General page reworked: memory shows in MB above 1 MB, with a green / yellow / red light (under 50 MB, 50-100 MB, over 100 MB).",
                  "New Tools: Copy debug info (for bug reports), Export / Import settings as one pasteable line, and Reset everything.",
                  "General page: modules-on count, a GitHub link, one changelog button; the footer now shows the version.",
                  "/cui debug now also lists the other addons you have loaded.",
              },
            },
            { version = "0.38.37", date = "2026-10-29",
              improved = {
                  "Battleground 'ready to enter' pop-up now has the Cys look.",
              },
            },
            { version = "0.38.36", date = "2026-10-29",
              improved = {
                  "Options window: the stock 'Close' word no longer shows over the X on hover.",
              },
            },
            { version = "0.38.35", date = "2026-10-29",
              improved = {
                  "Friends window: each person sits on a soft card with a status stripe, headers have a gold bar, and the title and footer have dividers. Names and details are a touch bigger.",
              },
            },
            { version = "0.38.34", date = "2026-10-29",
              improved = {
                  "Options window: hovering the X no longer shows the stock 'Close' word and red X.",
                  "Options window, AddOns tab: other addons' pages now get flat tick boxes, sliders, dropdown boxes and buttons so they match.",
              },
            },
            { version = "0.38.33", date = "2026-10-29",
              improved = {
                  "Options window: the Game and AddOns tab labels sit centred in their boxes.",
              },
            },
            { version = "0.38.32", date = "2026-10-29",
              improved = {
                  "Key bindings page: the 'Not Bound' buttons are flat like the rest.",
              },
            },
            { version = "0.38.31", date = "2026-10-29",
              improved = {
                  "Fixed the error when right-clicking a chat tab (the menu background no longer draws on the menu itself).",
                  "Fixed the 'Player trade window' skin failing when another addon adds odd frames to it.",
              },
            },
            { version = "0.38.30", date = "2026-10-29",
              improved = {
                  "Options window: choice rows (Chat Style, New Whispers and the like) have flat < > arrows and a flat dropdown button.",
              },
            },
            { version = "0.38.29", date = "2026-10-29",
              improved = {
                  "Options window: sliders are flat now - a thin dark track, a gold handle and flat end arrows.",
                  "Character window: the Honor tab's progress bar is flat in a hairline box, like the Reputation and Skills bars.",
              },
            },
            { version = "0.38.28", date = "2026-10-29",
              fixed = {
                  "Options window: Blizzard's red X close art is now found by its picture name and hidden, so only our X shows.",
              },
            },
            { version = "0.38.27", date = "2026-10-29",
              fixed = {
                  "Options window: the close button no longer shows Blizzard's red X underneath ours.",
              },
            },
            { version = "0.38.26", date = "2026-10-29",
              fixed = {
                  "Mailbox: the tick boxes next to each mail are now inside the window (the rows are moved right and made slightly narrower).",
                  "Breath bar: the text sits slightly lower.",
                  "Options window: near-black boxes drawn by other addons' option pages are brought to the panel colour.",
              },
            },
            { version = "0.38.25", date = "2026-10-29",
              fixed = {
                  "Options window: other addons' option pages (the AddOns tab) are left in their own style instead of being flattened half-way.",
                  "Flight map: the empty band between the title and the map is gone; the panel starts just above the map with the title inside it.",
              },
            },
            { version = "0.38.24", date = "2026-10-29",
              improved = {
                  "Options window: the leftover stock lines and boxes around the category list and settings area are removed, and the Gameplay / Accessibility / System headers become gold text over a thin gold line.",
              },
            },
            { version = "0.38.23", date = "2026-10-29",
              fixed = {
                  "Flight map: the map picture is kept again (it was being hidden along with the stock window art).",
                  "Close buttons that carry the word \"Close\" (like the one in the options window) no longer show the word on top of the X.",
              },
            },
            { version = "0.38.22", date = "2026-10-29",
              added = {
                  "Skins: second batch - game options and key bindings, the chat settings window, the flight map, small windows (stack split, ready check, color picker, breath bar), pet stable / tabard / charters, the clock and stopwatch, and the AddOn list. Each has its own switch on the Skins page.",
              },
              fixed = {
                  "Trade window: the Trade and Cancel buttons no longer turn red after Blizzard re-textures them.",
              },
            },
            { version = "0.38.21", date = "2026-10-29",
              improved = {
                  "Trade window: each item row (slot plus name) now sits in one dark box, and the Announce Trade tick box matches the ones in /cui.",
              },
            },
            { version = "0.38.20", date = "2026-10-29",
              fixed = {
                  "Dressing room: the title now sits inside the panel and the panel is wide enough to include the Reset / Close buttons.",
              },
            },
            { version = "0.38.19", date = "2026-10-29",
              fixed = {
                  "Inspect window: the dark panel now fits the whole window (name, gear slots and weapons) instead of stopping short.",
                  "Dressing room: the panel now includes the Reset / Close buttons and the title sits inside it.",
                  "Questie tracker: the skin keeps looking for the tracker until it exists and prints a line in chat when it has been applied.",
              },
            },
            { version = "0.38.18", date = "2026-10-29",
              added = {
                  "Skins: six more windows in the Cys style - the player trade window, the Enchanting window, the Inspect window, the battleground queue and scoreboard, the dressing room, and Questie's quest tracker (dark panel with the gold edge). Each has its own switch on the Skins page.",
              },
            },
            { version = "0.38.17", date = "2026-10-29",
              added = {
                  "Skins: the profession window (Alchemy, Blacksmithing, Cooking, First Aid...) now matches the rest of the UI: flat dark panel with a gold edge, flat skill bar, hairline icon boxes and flat buttons. It has its own switch on the Skins page.",
              },
              improved = {
                  "Layout mode: the Loot Window box name now wraps onto two lines.",
              },
            },
            { version = "0.38.16", date = "2026-10-29",
              improved = {
                  "Layout mode: the names on the gold boxes are white with an outline, so they read on any background.",
                  "Menu bar: buttons get a soft gold highlight when you hover them, like the Esc menu.",
              },
            },
            { version = "0.38.15", date = "2026-10-29",
              improved = {
                  "Experience bar: smaller text (10 at most), and the second line of the bar text now follows the same size as the first.",
              },
            },
            { version = "0.38.14", date = "2026-10-29",
              improved = {
                  "Menu bar (Character, Spells, Talents...): every button now uses the same, slightly smaller text size instead of \"Character\" shrinking on its own.",
              },
            },
            { version = "0.38.13", date = "2026-10-29",
              fixed = {
                  "Damage Meters: the percentage on the right of each bar no longer touches the window edge.",
              },
            },
            { version = "0.38.12", date = "2026-10-29",
              improved = {
                  "Damage Meters: bars now run edge to edge inside the gold border (the edge sits outside the window now, so the extra inset is no longer needed).",
              },
            },
            { version = "0.38.11", date = "2026-10-29",
              fixed = {
                  "Damage Meters: every Details window using the skin now gets the same bar inset and icon position, so the second window (Healing Done) matches the first.",
              },
            },
            { version = "0.38.10", date = "2026-10-29",
              fixed = {
                  "Character window: item slot edges now show. Green and better items glow in their item colour; plain items and empty slots get a quiet dark edge.",
                  "Damage Meters: the gold edge now sits fully outside the window, so nothing (like the class icon) can overlap it.",
              },
            },
            { version = "0.38.9", date = "2026-10-29",
              fixed = {
                  "Damage Meters: the spec/class icon on each bar is moved in 3 pixels so it no longer sits on the window edge. Press the skin button again to apply.",
              },
            },
            { version = "0.38.8", date = "2026-10-29",
              fixed = {
                  "Damage Meters: the gold edge around the title strip is now one even line (Details' toolbar no longer covers part of it).",
                  "Damage Meters: the Cys's UI skin is installed as soon as Details loads, so the default Details window should no longer flash for a moment at login or reload.",
              },
            },
            { version = "0.38.7", date = "2026-10-29",
              improved = {
                  "Damage Meters: gold edge around the title strip (\"Damage Done\" / \"Healing Done\"), fainter bar colours, and white names and numbers on the bars. Press the skin button again to apply the bar and text changes.",
              },
            },
            { version = "0.38.6", date = "2026-10-29",
              improved = {
                  "Damage Meters: taller title strip, bars are inset 3 pixels from the window edge so the spec icon no longer touches it, and each bar now has a subtle dark track behind it. Press the skin button again to apply.",
              },
            },
            { version = "0.38.5", date = "2026-10-29",
              fixed = {
                  "Damage Meters: removed the black squares above the Details! windows; the title strip now has a dark background of its own.",
              },
            },
            { version = "0.38.4", date = "2026-10-29",
              improved = {
                  "Border color: Gold is now a brighter gold so it stands out on bright zones.",
                  "Damage Meters: the Details! title strip (\"Damage Done\", \"Healing Done\") now gets the dark Cys's UI background, and the window edge is two pixels thick (which also makes a clear gold line between two side-by-side windows).",
              },
            },
            { version = "0.38.3", date = "2026-10-29",
              improved = {
                  "Action bars: slot borders are now two pixels thick so the gold (or class/blue) edge is easier to see.",
                  "Damage Meters: the Details! title strip now has a dark background with a gold line under it, and the bars are slightly taller with a 1 pixel gap. Pick the skin again (button on the Damage Meters page) to apply the bar changes.",
              },
            },
            { version = "0.38.2", date = "2026-10-29",
              fixed = {
                  "Action bars: slot borders now re-apply whenever the Border color changes, so Gold (and every other choice) always shows on the bars.",
              },
            },
            { version = "0.38.1", date = "2026-10-29",
              improved = {
                  "Damage Meters: the Details! skin now uses the game's normal font (bars and the gold window title) instead of Details' pixel font. Use the skin button again (or reselect the skin) to apply it.",
              },
            },
            { version = "0.38.0", date = "2026-10-29",
              added = {
                  "Damage Meters: a \"Cys's UI\" skin for the Details! damage meter (flat dark window, gold edge, flat class-coloured bars). It installs into Details' skin list; the new Damage Meters page has a button to use it on all windows and a switch for the gold edge. Nothing in Details changes until you pick the skin. Blizzard's own meter will follow after Forever.",
              },
            },
            { version = "0.37.5", date = "2026-10-29",
              fixed = {
                  "Skins: fixed an error (\"calling IsShown on bad self\") in the right-click menu search, caused by an odd frame from another addon; every frame is now checked safely, so the menu skin and its gold border should apply reliably.",
              },
            },
            { version = "0.37.4", date = "2026-10-29",
              improved = {
                  "Skins: skinned buttons (Esc menu, pop-ups and others) now light up gold under the mouse, not just brighten their edge; the right-click menu's gold border is drawn on top so nothing covers it.",
              },
            },
            { version = "0.37.3", date = "2026-10-29",
              improved = {
                  "Skins: the right-click menu skin now searches every frame right after any click (the menu's frames do not sit where first guessed) and /cysmenu reports what it found.",
              },
            },
            { version = "0.37.2", date = "2026-10-29",
              fixed = {
                  "Skins: fixed an error when the right-click menu skin started (\"attempt to index upvalue HookNewMenus\"), which stopped the new menu skin from working.",
              },
            },
            { version = "0.37.1", date = "2026-10-29",
              improved = {
                  "Skins: the right-click menu on unit frames uses the game's newer menu system, so it now gets the flat dark look too (its background art is hidden and replaced as the menu and its submenus open).",
              },
            },
            { version = "0.37.0", date = "2026-10-29",
              added = {
                  "Skins: pop-up dialogs (the logout countdown, confirmations) and right-click / dropdown menus now use the flat dark look with gold edges, and each has its own switch on the Skins page.",
              },
              improved = {
                  "Character window: the Reputation bars are flat (the standing colors stay) and the Skills bars are flat gold-brown in a thin box instead of glossy blue.",
                  "Character window, Skills tab: the skill list now spreads down toward the Close button instead of using only the top half of the window.",
              },
            },
            { version = "0.36.4", date = "2026-10-29",
              improved = {
                  "Settings window: the long grey paragraphs on the Action Bars, Unit Frames, Raid Frames, Scale, Cast Bar, Chat, Minimap, Friends, Vendor, Roll Tracker and Skins pages are now short bulleted lists, with the key words in gold.",
              },
            },
            { version = "0.36.3", date = "2026-10-29",
              improved = {
                  "Nameplates: the bulleted Auto threat explanation now indents its bullets and lines up wrapped lines under their own text.",
              },
            },
            { version = "0.36.2", date = "2026-10-29",
              improved = {
                  "Nameplates: the Auto threat coloring description is now a short bulleted list (Tank, Damage, Healer, No role set), and the settings below it move with the text so nothing overlaps.",
              },
            },
            { version = "0.36.1", date = "2026-10-29",
              improved = {
                  "Nameplates: Auto threat coloring now follows only the role you set for your group (Tank = tank colors, Damage or Healer = DPS colors, nothing set = DPS); the Upgrade profile and stance checks are gone. Tank, DPS and Off are still there to force a mode.",
                  "Settings window: descriptions and notes that were dark grey are now white, and a few section labels (like Threat coloring and the Upgrade stat/weight columns) are gold.",
              },
            },
            { version = "0.36.0", date = "2026-10-29",
              added = {
                  "Nameplates: threat coloring can be Auto (the new default). It follows your role: the role you set for your group, then your active Upgrade profile (a name with Tank, Prot or Defense counts as tank), then Defensive Stance, Bear Form or Righteous Fury; DPS otherwise. It switches by itself when that changes. Tank, DPS and Off are still there.",
              },
              improved = {
                  "Nameplates: the threat coloring setting is now a row of four buttons with a line under it saying what the choice means and which role Auto is using right now.",
              },
            },
            { version = "0.35.9", date = "2026-10-29",
              improved = {
                  "Character window: the equipment slots are flat dark boxes with a thin edge in the item's quality colour (gold when empty or plain), instead of Blizzard's stone slot art.",
                  "Character window: the name, level/class and guild lines are centred on the window (they sat to the right, which pushed the guild line under the Sets button).",
              },
            },
            { version = "0.35.8", date = "2026-10-29",
              added = {
                  "Talents: the open talent tree now has Blizzard's own class background art, dimmed, behind the talent icons and covering the whole window from top to bottom; it changes the moment you switch tab (part of the Talents window skin).",
              },
            },
            { version = "0.35.7", date = "2026-10-29",
              improved = {
                  "Upgrade: the damage-and-healing stat is listed as Spell Power in the Replaces list, the same name SixtyUpgrades uses.",
              },
            },
            { version = "0.35.6", date = "2026-10-29",
              improved = {
                  "Upgrade: the score and Upgrade/Downgrade number are now whole numbers like SixtyUpgrades (162 EP, +15 Upgrade), and Weapon Speed is listed as a plain change (-1 Weapon Speed) with the site's colors; the per-stat EP stays in grey.",
              },
            },
            { version = "0.35.5", date = "2026-10-29",
              improved = {
                  "Upgrade: the \"Replaces\" list now shows gains first and losses after, each in alphabetical order like SixtyUpgrades, and lists the weapon's Damage (Min) and (Max) change too.",
              },
            },
            { version = "0.35.4", date = "2026-10-29",
              fixed = {
                  "Upgrade: a shield's base Block Value (the \"13 Block\" line) is now counted, so shields score and show the change like SixtyUpgrades does (listed as Block Value (Base)).",
              },
            },
            { version = "0.35.3", date = "2026-10-29",
              fixed = {
                  "Upgrade: Weapon Speed now scores exactly like SixtyUpgrades (speed x weight), so the same weights give the same numbers on the site and in game. A NEGATIVE speed weight now favors fast weapons and a positive one slow weapons; your saved weights were converted automatically, so nothing changes in practice.",
                  "Upgrade: Export now writes SixtyUpgrades' own CSV format (a Stat,Value header, then lines like attackPower,1 and speed,50), so it pastes straight into the site's Point Configuration. Import also accepts that CSV.",
              },
            },
            { version = "0.35.2", date = "2026-10-29",
              added = {
                  "/cuiab prints what the first action buttons hold (stance, bonus bar, action slots, icons) so a bar that stays blank after login can be tracked down.",
              },
              improved = {
                  "Raid Debuffs: shorter category names under the icons (A.P., A.S., Judge) and tighter spacing so a full raid's ten boxes stay compact; the tooltip and settings page keep the full names, with the short form in brackets.",
                  "Raid Debuffs: boxes hide when the target is dead; the settings page says it covers your party or raid and explains what is tracked and how boxes are chosen.",
              },
              fixed = {
                  "Action bar 1 now fills in right after login or /reload in any stance (the redraw was skipping bar 1, and this client has no global redraw function, so each button now redraws itself).",
                  "Raid Debuffs: category names have room (wider spacing) and no longer run into each other; a second cooldown counter behind the timer is switched off.",
              },
            },
            { version = "0.35.1", date = "2026-10-29",
              improved = {
                  "Warrior: the debuff icons were removed; Cys's Raid Debuffs does the same job for every class and only shows effects your group can apply. The Battle Shout alert is now hidden while resting (towns and inns) by default, with an option to show it only in combat.",
              },
              fixed = {
                  "Action bars: buttons now redraw their icons after login and whenever you change stance or bar page, so bars no longer stay blank until you mouse over them.",
              },
            },
            { version = "0.35.0", date = "2026-10-29",
              added = {
                  "New module, Cys's Raid Debuffs (any class): one box per key raid debuff on your target - Armor (Sunder / Expose / Faerie Fire / Recklessness), Fire (Improved Scorch), Frost (Winter's Chill), Shadow (Improved Shadow Bolt), Curses (Elements / Shadow), Attack Power, Attack Speed (Thunder Clap), Miss (Insect Swarm), Hunter's Mark and Judgements. Grey when missing, colored with stacks and timer when up, with tooltips. Only effects someone in your group can apply are shown. Settings: Raid Debuffs page.",
              },
            },
            { version = "0.34.0", date = "2026-10-29",
              fixed = {
                  "Warrior: the Battle Shout missing alert now works with higher ranks of the spell (it only recognised rank 1).",
              },
              improved = {
                  "Warrior debuffs narrowed to the important effects: armor reduction, Thunder Clap and Demoralizing Shout (Rend, Hamstring and Mortal Strike removed).",
                  "Conflicts: MinimapButtonButton and Minimap Button Bag are detected and can be switched off in favor of Cys's Minimap Button.",
                  "Warrior debuffs: when several armor / attack-power debuffs are up, the strongest one is shown (Expose Armor, then Sunder, then Faerie Fire...), not just yours.",
              },
              added = {
                  "New warrior-only module, Cys's Warrior: a \"Battle Shout missing\" alert, and a row of icons on your target for the debuffs you put on it (one icon per effect: armor reduction shows Sunder Armor, or another class's Expose Armor / Faerie Fire / Curse of Recklessness; plus Rend, Thunder Clap, Demoralizing Shout/Roar/Curse of Weakness, Hamstring and Mortal Strike) with countdown timers. Settings are on the new Warrior page; both can be moved in layout mode.",
              },
            },
            { version = "0.33.16", date = "2026-10-29",
              added = {
                  "Forever readiness: new Compat.lua fills in old functions (spell, item and aura lookups) from their new names if the client drops them. It does nothing on today's client.",
                  "/cui debug now checks more game functions and lists anything Compat had to fill in.",
              },
              fixed = {
                  "Upgrade tooltips also work on clients that moved item tooltips to TooltipDataProcessor.",
                  "Skill Tracker and the junk-drop helper no longer error if a game function is missing.",
              },
            },
            { version = "0.33.15", date = "2026-10-29",
              fixed = {
                  "Action bars: the two empty dark boxes next to the bars on classes without stances (Blizzard's stance bar background) are hidden.",
              },
              improved = {
                  "Heal estimate now adds your bonus healing (cast time / 3.5, trimmed for low-level spells and low ranks). With no +healing it changes nothing.",
                  "Heal prediction: Classic Era gives no incoming-heal data, so the unit frames and raid frames now estimate your own heal from the spell's description while you cast it (the green segment, and the overheal sliver when it would be wasted).",
              },
            },
            { version = "0.33.14", date = "2026-10-29",
              added = {
                  "/cuiheal: logs the heal prediction, spell rank and mana cost next to the real heal, for checking the previews.",
                  "Player frame: while you cast, a white segment at the end of the mana bar shows how much mana the spell will use.",
              },
              fixed = {
                  "Bank: items in the bank now show their tooltips.",
              },
            },
            { version = "0.33.13", date = "2026-10-29",
              fixed = {
                  "Loot window: the \"Items\" title is centered on the panel (Blizzard\'s own title is hidden and ours is drawn instead, so the game can\'t move it).",
              },
            },
            { version = "0.33.12", date = "2026-10-29",
              improved = {
                  "Loot: the loot window position (Blizzard's spot / at the mouse / fixed spot) and the group loot roll boxes now share one settings page, \"Loot\", under Loot & Items.",
              },
            },
            { version = "0.33.11", date = "2026-10-29",
              fixed = {
                  "Cys's Bags: the Sort button works again (it called a function that was missing, so nothing happened). Click it again to stop a sort.",
                  "Vendor: Sell Junk is only on the vendor window now; the second one hiding behind the bag's Junk button is gone.",
              },
            },
            { version = "0.33.10", date = "2026-10-29",
              fixed = {
                  "Upgrade: weapon speed is also found by scanning all of the tooltip's text, and the doubled \"Damage Per Second\" line in the comparison is gone.",
              },
            },
            { version = "0.33.9", date = "2026-10-29",
              fixed = {
                  "Upgrade: weapon speed now counts. The game shows it in the tooltip's right-hand column, which was never read, so the Weapon Speed weight did nothing. Positive weight favors fast weapons, negative favors slow ones, and the tooltip shows the speed change with its EP.",
                  "Loot window: the empty space above the first item is gone (the game kept putting the rows back 68px down).",
              },
            },
            { version = "0.33.8", date = "2026-10-29",
              fixed = {
                  "Upgrade: items with a suffix (of the Eagle, Owl, Monkey...) are now scored and compared by the stats they really have. The game's own stat lookup ignores suffix stats, which made the tooltip list stats you already had as gains and hid the ones you lose.",
                  "Upgrade: importing weights works with the exported text (it never could read it), and saving a profile under a new name no longer links it to the old one.",
              },
              added = {
                  "Upgrade: the tooltip shows Side-grade when two items score the same, lists only the stats that differ, biggest effect first, with what each is worth in EP, and says when the stats are identical.",
              },
              improved = {
                  "Upgrade: the settings page, the stat picker, and the import / export and guide windows now use the Cys theme.",
              },
            },
            { version = "0.33.7", date = "2026-10-29",
              fixed = {
                  "Minimap Button: addon icons are centered in their boxes (they sat slightly high).",
              },
            },
            { version = "0.33.6", date = "2026-10-29",
              improved = {
                  "Minimap Button: addon icons a touch smaller, with a little more room inside their boxes.",
              },
            },
            { version = "0.33.5", date = "2026-10-29",
              improved = {
                  "Minimap Button: the addon icons fill their boxes instead of floating small in the middle.",
              },
            },
            { version = "0.33.4", date = "2026-10-29",
              fixed = {
                  "Minimap Button: the panel now sits just under the addon buttons' own layer (MEDIUM, level 8) instead of trying to lift them above it, which some addons undo.",
              },
            },
            { version = "0.33.3", date = "2026-10-29",
              fixed = {
                  "Minimap Button: addon buttons now show in the panel (they were being drawn behind it, because the addons kept putting them back on the minimap's layer).",
              },
            },
            { version = "0.33.2", date = "2026-10-29",
              fixed = {
                  "Totems: the weapon button sits at the same spacing as the totem slots.",
                  "Minimap Button: reports any addon button it cannot take, and /cuimmb lists what the panel holds.",
              },
            },
            { version = "0.33.1", date = "2026-10-29",
              added = {
                  "Tooltip: where the tooltip appears is now set separately for action bars, bags and frames, and for NPCs and players in the world (follow the mouse, lift, shift left / right).",
                  "Minimap Button: a square gold-edged logo (the round one is a checkbox).",
              },
              fixed = {
                  "Minimap Button: the addon buttons were hidden behind the panel.",
              },
            },
            { version = "0.33.0", date = "2026-10-29",
              added = {
                  "Minimap Button: a round Cys logo button on the minimap. Left-click opens a panel with every other addon's minimap button tidied into a grid; right-click opens these settings. Move it in layout mode, set buttons per row and size, and leave any addon's button on the minimap.",
              },
            },
            { version = "0.32.12", date = "2026-10-29",
              improved = {
                  "Totems: each totem and the weapon button now sit on a black plate with the UI's border; the colored status rings (range, imbue, missing) stay inside it.",
              },
            },
            { version = "0.32.11", date = "2026-10-29",
              improved = {
                  "Tooltip: new installs start with the follow-the-mouse tooltip lifted 20 px and shifted 160 px right, so it doesn't cover the icon under the mouse. Existing settings are untouched.",
              },
            },
            { version = "0.32.10", date = "2026-10-29",
              added = {
                  "Tooltip: \"Shift left / right\" next to \"Lift above the mouse\" moves a mouse-following tooltip sideways (negative = left, positive = right).",
              },
            },
            { version = "0.32.9", date = "2026-10-29",
              added = {
                  "Combat log: the \"My actions / What happened to me?\" bar above the Log tab is restyled flat dark with a gold edge to match the chat window, and sits above the window under the tab names instead of on top of the first lines. Toggle it on the Skins page (Combat log button bar).",
              },
              fixed = {
                  "Group Loot Boxes: the real roll boxes are laid out properly for the size you pick. The item name stays on one line beside the icon, the Need / Greed / Pass buttons sit in a row on the right (no longer stacked over each other), and the timer runs along the bottom.",
                  "Nameplates: the game's own nameplate no longer flashes through from underneath ours (a red sliver above the name, a grey bar under the plate on mouse-over). Its transparency, and that of every piece inside it, is held at zero.",
                  "Chat: the combat log's button bar sits above the window under the tab names, and the tab row lifts clear of it while the Log tab is showing.",
              },
            },
            { version = "0.32.4", date = "2026-10-29",
              added = {
                  "Chat: a thin gold line under the name of the active chat tab, so you can see which one is showing.",
              },
            },
            { version = "0.32.3", date = "2026-10-29",
              improved = {
                  "Tooltip: when it follows the mouse it now sits above it instead of covering what is under it (0.32.3: the game ignored the lift on its own mouse anchor, so the tooltip now follows the mouse itself). Change the distance with \"Lift above the mouse\" on the Tooltip page.",
                  "Chat: the tabs are raised by moving the chat dock the tabs hang from, so they really sit above the window's border.",
              },
            },
            { version = "0.32.1", date = "2026-10-29",
              improved = {
                  "Chat: the tabs (General, Log, Loot, Whisper...) no longer fade out, and they sit clear above the window's top border instead of on top of it. Switch it off with \"Chat tabs always visible\" on the Chat page (needs a /reload).",
              },
            },
            { version = "0.31.9", date = "2026-10-29",
              fixed = {
                  "Action Bars: Blizzard's HUD Edit Mode is now turned off by default (it redrew the old bars, the page number and the stance slots over your bars and blocked clicks). Use /cui layout to move things; the Action Bars page has a checkbox to bring Edit Mode back.",
                  "Action Bars: Blizzard's old bar frames now stop taking mouse clicks even though they are secure frames (they were skipped before). New: /cui hit shows which frame is under the mouse after 4 seconds, handy for tracking down a button that will not react.",
                  "Action Bars: the page up/down arrows and page number on the new client's main bar are hidden too.",
              },
            },
            { version = "0.31.6", date = "2026-10-29",
              improved = {
                  "Cys's Armory: a shorter panel (scroll the list if you have many sets), a soft gold glow in the header, a set count, a warm tint on the set you are wearing, and a Spec 1 / Spec 2 tag on bound sets.",
                  "Cys's Armory and the Skill Tracker are a little shorter so the stack clears the action bars at the bottom of the screen. Skill Tracker: new default, Beside Character window. It sits right under the Armory panel (same width) when the Armory is open, and beside the Character window when it is not. The other choices (my own spot, always, hidden) are still under Tracking > Skill Tracker.",
              },
            },
            { version = "0.31.4", date = "2026-10-29",
              improved = {
                  "Skill Tracker: the box is now only as wide as its text, and by default it shows only while the Character window is open. Choose With the Character window, Always or Hidden under Tracking > Skill Tracker. /cysws still shows or hides it by hand.",
              },
            },
            { version = "0.31.3", date = "2026-10-29",
              added = {
                  "Looking For Group window skin (Create Listing and Group Browser tabs) in the CysUI look. Toggle it on the Skins page.",
                  "Loot window position: a fixed spot you can move in /cui layout (the default), at the mouse, or Blizzard's spot. Choose it on the Skins page. (0.31.1: the fixed spot and at-the-mouse choices now hold instead of snapping back to the left edge.)",
              },
              fixed = {
                  "Experience bar: the text sits a little lower so it looks centered in the bar.",
              },
              improved = {
                  "Heal prediction: the overheal bar now reaches out past the player and target frames in proportion to how much of the heal would be wasted, and changes colour (teal, yellow, red) the more of it is wasted. It also shows when the unit is at full health.",
              },
            },
            { version = "0.30.0", date = "2026-10-29",
              fixed = {
                  "Heal prediction on the player, target, target-of-target and party frames: the incoming-heal colour now starts where your health ends and covers only the missing health, instead of washing over the whole frame. A heal that would overheal shows as a thin sliver just outside the frame.",
                  "Chat: the window can now be moved all the way to the left and bottom edges of the screen (Blizzard kept it 35 and 50 pixels away). The edit box goes above the window when the window sits at the very bottom.",
                  "Info bars, Micro Menu and XP bar: text is centred on whole pixels, sized from the bar's height, and shrinks to fit when a readout is too long for its slot (the XP bar's quest and rested text now counts towards the centring).",
                  "Action Bars: Blizzard's page arrows and bar art stay hidden even when Edit Mode re-shows them.",
              } },
            { version = "0.29.2", date = "2026-10-29",
              fixed = {
                  "Tooltip settings page: it failed to build (a typo in the size slider), so none of the tooltip toggles showed. They all work now, and the move button no longer sits on top of the note.",
              },
              added = {
                  "Tooltip: new options to show item and spell IDs and to hide unit tooltips while you are in combat.",
              } },
            { version = "0.29.1", date = "2026-10-29",
              fixed = {
                  "Player Auras: right-clicking a buff now cancels it (the icons are plain buttons now, like Blizzard's own, and work in combat too). Weapon enchants cancel as well.",
                  "Group Loot Boxes: the sample box no longer pops a blank real roll frame when it is switched on, and it steps aside when a real roll appears.",
              },
              added = {
                  "Player Auras settings page: toggles for right-click cancel, timers on or under the icons, and how many buffs and debuffs to show. Timers show hours, turn red under 10 seconds and update smoothly.",
                  "Group Loot Boxes: the border and timer bar take the colour of the item being rolled on (switch off on the settings page). The settings page uses the same +/- steppers as the rest of /cui.",
              } },
            { version = "0.29.0", date = "2026-10-29",
              added = {
                  "Raid Frames: role icons (tank shield, healer cross, damage sword) beside each name. A role set by the game's role check wins, then your Main Tank from the Raid tab, then a guess by class (priests heal, the rest damage). Set anyone by hand with /cysraid role [name] tank|healer|dps|clear (uses your target without a name), which is how to mark a tanking Shaman. A new button in /cui > Raid Frames switches icons between all roles, tank and healer only, or off.",
              } },
            { version = "0.28.4", date = "2026-10-29",
              improved = {
                  "Raid Frames: the \"only debuffs my class can dispel\" borders now check which cleansing spells you have actually learned (Cure Disease, Dispel Magic, Remove Curse, Cleanse and so on), so a low-level character only sees what it can remove. Warlocks get Magic borders while a Felhunter is out.",
              } },
            { version = "0.28.3", date = "2026-10-29",
              added = {
                  "Raid Frames: new option \"Only borders for debuffs my class can dispel\" (on by default). Priests see Magic and Disease, Paladins Magic / Poison / Disease, Druids Curse and Poison, Shamans Poison and Disease, Mages Curse. Debuff icons are unchanged.",
              } },
            { version = "0.28.2", date = "2026-10-29",
              improved = {
                  "Raid Frames: 40-man now wraps into two rows of four groups (groups 1-4 on top, 5-8 below) instead of one very wide row.",
              } },
            { version = "0.28.1", date = "2026-10-29",
              added = {
                  "Raid Frames: the preview now shows a full made-up raid (up to 40 players) in the layout you picked, so you can compare 10, 20 and 40-man while solo. Press Preview again (or /cysraid test) to turn it off.",
              },
              improved = {
                  "Raid Frames moved to the Frames & Combat group in the settings window and the Modules list.",
              } },
            { version = "0.28.0", date = "2026-10-29",
              added = {
                  "New module: Raid Frames. Flat, class-colored raid frames for 10, 20 and 40 player raids (groups sit side by side, 2 / 4 / 8 columns). Auto picks the size from your raid; or choose 10, 20 or 40 yourself in /cui > Raid Frames. Shows missing health, incoming heals, debuff-type borders and icons, range fade, raid markers and the leader star. Click-casting (Clique) works. Move it in /cui layout. Blizzard's raid frames are hidden while it is on. \"Preview\" (or /cysraid test) shows it while solo or in a party.",
                  "The Raid tab of the friends window (groups, class counters, Raid Info) is now skinned.",
              } },
            { version = "0.27.1", date = "2026-10-29",
              added = {
                  "Addon conflicts: a \"Don't ask again\" button on the window. The window can still be reopened from /cui > Conflicts.",
              } },
            { version = "0.27.0", date = "2026-10-29",
              added = {
                  "Addon conflicts: if an addon that does the same job as part of Cys's UI is running (ElvUI, Plater, Platynator, Postal, Bagnon and others), a window asks whether to use Cys's version (the other addon is switched off, not deleted) or keep theirs (the matching Cys's modules are switched off). One reload applies it. Review or change it any time in /cui > Conflicts.",
              } },
            { version = "0.26.0", date = "2026-10-29",
              added = {
                  "New module: Cys's Mail. Tick mails in the inbox (shift-click to tick everything between two mails), then press Open to take the money and items from them, or Return to send them back. Cash-on-delivery mails are skipped, and it stops if your bags fill up. Open All is Blizzard's own button. It stays out of the way while the Postal addon is loaded, so disable Postal to use it.",
              } },
            { version = "0.25.2", date = "2026-10-29",
              fixed = {
                  "Skins: Mailbox - the Inbox / Send Mail / Open Mail titles are centred in the window.",
              } },
            { version = "0.25.1", date = "2026-10-29",
              fixed = {
                  "Skins: Mailbox - gold-tinted title band and divider lines on the send tab, lighter message box and attachment slots (gold edge on hover), and the Postal addon's checkboxes, buttons and menu arrows now match.",
              } },
            { version = "0.25.0", date = "2026-10-29",
              added = {
                  "Skins: Class trainer window and Blizzard's bank window now use the dark and gold style (Cys's Bags' own bank is unchanged and follows the Border color setting). Switch them off in Settings > Skins.",
              } },
            { version = "0.24.0", date = "2026-10-29",
              added = {
                  "Skins: Mailbox - inbox rows, the send tab (name / subject / message / money boxes, attachment slots) and the open-letter window now use the dark and gold style, with readable letter text. Switch it off in Settings > Skins.",
              } },
            { version = "0.23.0", date = "2026-10-29",
              added = {
                  "UI Scale: new \"Match the 1080p layout\" option for 1440p and 4K screens. The UI keeps the same size and positions as on a 1080p screen instead of shrinking; pixel perfect is still there too.",
              } },
            { version = "0.22.2", date = "2026-10-29",
              fixed = {
                  "World map: the full-size map no longer blacks out the rest of the screen.",
              } },
            { version = "0.22.1", date = "2026-10-29",
              fixed = {
                  "World map: the frame now wraps the map itself instead of the whole map window, so it is no longer huge on the full-size map.",
              } },
            { version = "0.22.0", date = "2026-10-29",
              added = {
                  "World map: a strip along the bottom shows your coordinates and the mouse cursor's coordinates.",
              } },
            { version = "0.21.1", date = "2026-10-29",
              fixed = {
                  "Settings > Skins: the border color buttons are a bit narrower so Shaman blue fits inside the window.",
              } },
            { version = "0.21.0", date = "2026-10-28",
              added = {
                  "Border color: new Shaman blue option (only shown on Shaman characters).",
                  "Border color now also recolors Cys's Bags, Bank, Armory, Armory flyout, Roll Tracker, Skill Tracker and Upgrade windows.",
                  "World map: the drag handle, saved position and 75% size from the CysMap addon are now built in. CysMap can be disabled and deleted - your saved position carries over. /cysmap resets it, /cysmap scale 0.8 resizes it.",
              } },
            { version = "0.20.0", date = "2026-10-28",
              added = {
                  "Border color: pick gold (default), class color, black or grey for every frame edge in Cys's UI and the skinned windows - Settings > Skins. Applies right away.",
              } },
            { version = "0.19.2", date = "2026-10-28",
              fixed = {
                  "Skins: vendor window - the empty buyback box above the money strip only shows once you have something to buy back.",
              } },
            { version = "0.19.1", date = "2026-10-28",
              fixed = {
                  "Skins: vendor window - item icons, names and prices now sit inside their boxes instead of pressing into the corner / hanging below.",
              } },
            { version = "0.19.0", date = "2026-10-28",
              added = {
                  "Skins: vendor window - dark panel with a gold edge, framed item cells, gold-edged repair buttons and money strip, simple < > page buttons and flat tabs. Toggle it under Skins.",
              } },
            { version = "0.18.2", date = "2026-10-28",
              fixed = {
                  "Skins: quest names in the NPC gossip window and the quest dialog's quest list are readable again (white; grey for low-level quests) instead of black on dark.",
              } },
            { version = "0.18.1", date = "2026-10-28",
              fixed = {
                  "Skins: world map - the zone highlight (and the cursor coordinates) now follow the mouse when the map is scaled down; before, hovering one zone could light up another.",
              } },
            { version = "0.18.0", date = "2026-10-28",
              added = {
                  "Skins: world map - the brown stone border is gone for a flat dark panel with a gold edge, gold-edged Continent / Zone / Battle Map dropdowns, a flat Zoom Out button and a plain close / maximize pair. Toggle it under Skins.",
              } },
            { version = "0.17.7", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities - the community rows (your guild, Join or Create Group) sit a little in from the window edge instead of touching it.",
              } },
            { version = "0.17.6", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities - the left list and top line now share the window's own border instead of doubling it, the Info tab labels line up with their boxes, and the Guild Information scrollbar no longer overlaps its box edge.",
              } },
            { version = "0.17.5", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities - a gold line now runs from the community list's top edge across the whole window so the left list and the panel beside it connect.",
              } },
            { version = "0.17.4", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities Info tab re-laid out - the message of the day and guild information boxes now fill the panel, their scrollbars sit inside the box, and the news dates lose the brown bar.",
              } },
            { version = "0.17.3", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities - the Roster tab (flat column headers, Show Offline box) and the Info tab (no more brown parchment, gold-edged message / information / news panels, slim scrollbars).",
              } },
            { version = "0.17.2", date = "2026-10-28",
              fixed = {
                  "Skins: in the Guild & Communities window the last roster name (and the last community) no longer runs over the bottom border.",
              } },
            { version = "0.17.1", date = "2026-10-28",
              fixed = {
                  "Skins: Guild & Communities window is sleeker - gold borders on the chat, member list, community list and chat box, flat rows for your communities, the side tabs framed like the spellbook's, slim gold scrollbars, flat dropdowns, no corner ornaments and a smaller Invite Member button.",
              } },
            { version = "0.17.0", date = "2026-10-28",
              added = {
                  "Skins: first pass at the Guild & Communities window (guild chat, roster, benefits and info) in the dark Cys look. It has its own switch on the Skins page.",
              } },
            { version = "0.16.1", date = "2026-10-28",
              added = {
                  "Friends window: the Guild tab has a Guild Window button that opens Blizzard's full Guild & Communities panel for chat, invites and ranks. The tab itself stays a quick roster.",
              } },
            { version = "0.16.0", date = "2026-10-28",
              added = {
                  "Friends window: new Guild tab. Shows the guild message of the day (hover for all of it) and the roster, online members first by rank with class-coloured names, level, zone and notes, offline members with how long ago they were on. Search by name, rank, note or zone, hide offline members with the button at the bottom, and whisper, invite or add friends from the right-click menu.",
              } },
            { version = "0.15.1", date = "2026-10-28",
              fixed = {
                  "Friends: searching on the Who tab no longer pops Blizzard's own Who panel open on top, and /who (with or without a search) now opens the Cys Who tab. Both follow the Friends page option, so switching it off gives you Blizzard's behaviour back.",
              } },
            { version = "0.15.0", date = "2026-10-28",
              added = {
                  "Friends window: new Who tab. Type a name, level range, class or zone and press Enter (empty = everyone in your zone). Results are class-coloured with level, race, zone and guild; double-click or right-click to whisper, invite or add as a friend.",
              } },
            { version = "0.14.2", date = "2026-10-28",
              fixed = {
                  "Friends: game names now have their own colours (WoW blue, Diablo red, Hearthstone orange...), the grey text is lighter so it reads on the dark panel, and rows have a little more breathing room.",
              } },
            { version = "0.14.1", date = "2026-10-28",
              added = {
                  "Friends: online friends are now grouped by what they are playing (WoW Classic, other WoW versions, other games, Battle.net App and Mobile) and each row names the game, e.g. Hearthstone or Diablo IV. Turn the grouping off on the Friends page for a single Online list.",
              } },
            { version = "0.14.0", date = "2026-10-28",
              added = {
                  "New Friends window (/cfriends, or the Social key and micro menu button): game and Battle.net friends grouped into Favorites / Online / Offline with class-coloured names, level and zone, search, whisper, invite and remove, plus an Ignore tab. Move and resize it in /cui layout; switch it off on the Modules page. Blizzard's own friends window is untouched.",
              } },
            { version = "0.13.2", date = "2026-10-28",
              fixed = {
                  "Skins: BetterFriendlist no longer gets its tabs and buttons skinned a second time (that doubled the borders and blanked its menu/settings icons). It already has its own dark theme, so only its close button is matched now.",
              } },
            { version = "0.13.1", date = "2026-10-28",
              added = {
                  "Skins: the BetterFriendlist addon's window (friends list, Who, Guild, Raid, Ignore list and Saved Instances) now gets the dark Cys look too. It has its own switch on the Skins page.",
              } },
            { version = "0.13.0", date = "2026-10-28",
              added = {
                  "Skins: the Friends / Who / Guild window now uses the dark Cys look (panel, tabs, sub-tabs, buttons, scrollbars and column headers).",
              } },
            { version = "0.12.0", date = "2026-10-28",
              added = {
                  "Skins: the quest dialogs (accepting, progress and turn-in windows, plus the quest list an NPC offers) and the NPC gossip window now use the dark Cys look, with the dark ink text recoloured (gold headings, light body text, green finished objectives).",
              } },
            { version = "0.11.4", date = "2026-10-28",
              fixed = {
                  "Loot window skin: the item rows moved up under the title instead of sitting low in the panel.",
              } },
            { version = "0.11.3", date = "2026-10-28",
              fixed = {
                  "Loot window skin: the panel now shrinks to fit the items you are looting, and each item row spans the full width instead of just boxing the icon.",
              } },
            { version = "0.11.2", date = "2026-10-28",
              added = {
                  "Skins: the Loot window (the 'Items' box when you loot a corpse) gets the flat dark panel, plain X and flat item rows.",
              },
              fixed = {
                  "Action bars: the red flash on the auto-attack slot is replaced by a gold pulse on the slot's edge.",
                  "Quest Log skin: the leftover bracket next to the 'All' button is gone.",
              } },
            { version = "0.11.1", date = "2026-10-28",
              fixed = {
                  "Quest Log skin: the dark panel no longer runs a long way past the Abandon / Share / Exit buttons.",
              } },
            { version = "0.11.0", date = "2026-10-28",
              added = {
                  "Skins: the Quest Log now has the gold-and-dark look - flat panel, plain X, flat Abandon / Share / Exit buttons, a slim scrollbar, and the quest text is recoloured (gold titles, light body text, green finished objectives) so it reads on the dark background instead of the old parchment.",
              } },
            { version = "0.10.4", date = "2026-10-28",
              improved = {
                  "Window tabs now sit edge to edge under the panel with an even 1px seam instead of uneven black gaps.",
                  "Spellbook: the brown empty-slot squares are replaced by plain dark boxes.",
              } },
            { version = "0.10.3", date = "2026-10-28",
              improved = {
                  "Window tabs (Character, Reputation, Skills, Honor...) are re-fitted: flat boxes that sit right under the panel with the label centred.",
                  "Spellbook: the rank / subtext under spell names is now light grey-white instead of dark, and the skill-line tabs down the right edge (including addon tabs like Clique's) are square gold-edged icons.",
              },
              fixed = {
                  "Action Bar 1's page up/down arrows and page number are hidden again (the newer game layout keeps them on MainActionBar).",
              } },
            { version = "0.10.2", date = "2026-10-28",
              improved = {
                  "Skins redone from Blizzard's own frame definitions: the portrait at the top-left of the Character, Talents and Macro windows is gone, close buttons are a plain X, tabs are flat with a gold edge when selected, and the red stone buttons (Close, Save, Delete...) are flat gold-edged buttons.",
                  "Scrollbars (Skills, Talents, Macros) get a thin dark track with a flat gold thumb, and Reputation rows lose their chunky stone frames.",
                  "Blizzard art is now faded out instead of hidden, so the game can no longer bring it back when a window opens or a tab changes.",
              } },
            { version = "0.10.1", date = "2026-10-28",
              improved = {
                  "Esc menu: every option now sits in its own gold-edged box, so they are easy to tell apart.",
                  "Skins: the red stone buttons (Close, Save, Delete, Check Hotbar Ranks...) are now flat gold-edged buttons too, and the Macro window's panel covers its bottom buttons.",
              },
              fixed = {
                  "Fixed a Lua error ('attempt to compare nil with number' in MicroMenuContainer) caused by hiding Blizzard's micro menu.",
              } },
            { version = "0.10.0", date = "2026-10-28",
              added = {
                  "New Skins module: the Main Menu (Esc), Character (with Reputation and Skills), Spellbook, Talents and Macro windows get the gold-and-dark look - flat panel, gold edge, restyled buttons, tabs and close buttons. Each window has its own switch on the new Skins page, and one that looks off on a game version is skipped safely.",
              },
              improved = {
                  "Experience bar: the numbers are now exactly centred, with the Rested / Quests percentages trailing beside them.",
                  "The Modules page is now grouped under gold headings (Frames & Combat, Interface, Bags & Loot, Character & Class), most-used first, with gold module names.",
                  "Experience bar: the text is white with an outline and a little larger, the fills are slightly dimmed, and rested XP is a thin strip along the bottom of the bar so quest XP can no longer hide it.",
              } },
            { version = "0.9.0", date = "2026-10-28",
              added = {
                  "Cys's Bags, Bank, Armory (with the Equipment Flyout), Skills, Totems and Roll Tracker now live inside Cys's UI, so it is one download. Each has its own switch under Modules, and Cys's Totems only appears for Shamans. Your bag categories, armory sets and the other settings carry over.",
                  "Bags and Bank: a new All Slots view that shows every real slot in bag order (empty ones included), width and height resizing in layout mode, Sort and Junk buttons in the footer, and they reopen on the tab you used last.",
                  "The Skill Tracker and Totem Tracker are now moved in layout mode (/cui layout) like everything else.",
                  "Experience bar: your XP is purple, rested XP is a blue segment ahead of it, and XP from quests you have completed is a gold segment. Pick the colors on the XP Bar page.",
              },
              improved = {
                  "Cys's Upgrade: the upgrade arrows now actually show on items in your bags and bank (they were looking for the wrong button names), the module switch works, and the profile save errors and the debug message are gone.",
                  "Modules for other classes are hidden from the Modules list, so a warrior never sees shaman tools. Class modules like this are the way future warrior features will be added.",
              } },
            { version = "0.8.0", date = "2026-10-28",
              added = {
                  "Kill Tracker and XP Bar modules, each with its own settings page: kills and XP per kill, XP bar text, quest XP, hide at max level.",
                  "Micro Menu module: a slim gold button bar that replaces Blizzard's micro buttons. Player Auras module: your buffs and debuffs in movable gold boxes in place of Blizzard's. Group Loot boxes.",
                  "A second Info Bar under the minimap (guild, friends and clock by default) with gold dividers between items on both bars. Each item can go on either bar.",
                  "Width and height in layout mode (/cui layout) for the Kill Tracker, Micro Menu, Group Loot boxes, Party Frames and Cys's Bags and Bank. Buffs and debuffs get icons per row, icon size and spacing.",
                  "Tooltips show a mob's level in its difficulty color and a player's guild.",
              },
              improved = {
                  "The settings window groups its pages under gold headings and scrolls, so nothing runs off the bottom.",
                  "Action Bars hide Blizzard's XP bar, reputation bar, bag buttons and page arrows, and bars 2-8 turn on and off instantly without a reload.",
                  "The minimap defaults to 180x180, matching the info bar under it, tucks tracking, mail and queue icons into its corners and can hide Blizzard's clock.",
                  "The player and target cast bars now match the width of their unit frames by default.",
              },
              fixed = {
                  "A black border that appeared on the minimap after resizing it, and leftover Blizzard frames behind the zone name.",
              } },
            { version = "0.7.0", date = "2026-10-28",
              added = {
                  "Action Bars module: Action Bars 1-8, the pet bar and the stance bar become flat, movable blocks that always show their empty slots. Choose buttons per row, size and spacing for each, fade a bar until mouseover, shorten keybind text and hide macro names. Uses Blizzard's own buttons, so everything the game does with them keeps working. Move them in /cui layout. Turn off ElvUI's Action Bars while using it.",
              } },
            { version = "0.6.0", date = "2026-10-24",
              added = {
                  "UI Scale: Cys's UI is designed for a pixel-perfect screen (at 1920x1080, one UI unit is one pixel), which is what ElvUI sets up for you and why everything looks huge without it. It asks once whether to switch; change it any time in /cui > UI Scale.",
                  "Nameplates module: flat nameplates with class and reaction colors, a gold frame on your target, level and name, health percent, orange coloring when a mob is on you (or Tank mode), your own debuffs on the mob, a small cast bar and raid markers.",
              } },
            { version = "0.5.0", date = "2026-10-22",
              added = {
                  "Unit Frames module: flat player, target, target-of-target, pet and party frames with class and reaction colors, power bars, health text, target buffs and debuffs, and combo points. Built on the game's secure frames so clicking and targeting work in combat. Raid frames are still Blizzard's.",
                  "Cast Bar module: flat cast bars for you and your target with spell icon, name, time left and an interrupt flash.",
                  "Every one of these frames moves, resizes and scales in layout mode (/cui layout).",
              } },
            { version = "0.4.0", date = "2026-10-19",
              added = {
                  "Tooltip module: flat gold-edged tooltips with rarity-colored borders on items, class-colored names, a slim colored health bar, a Targeting line, the vendor sell price, and a movable default position (or follow the mouse).",
                  "Minimap module: a square gold-edged map with a zone bar (click for the world map), coordinates, mouse-wheel zoom, tidy status icons, and layout-mode move and resize.",
              } },
            { version = "0.3.0", date = "2026-10-18",
              added = {
                  "Chat module: flat, gold-edged chat windows with matching edit box and tabs, a Copy button on every window, class-colored names, timestamps and a font size setting. Chat window 1 moves and resizes in layout mode.",
                  "The bags, the bank and the roll tracker now use layout mode too: position and scale them with /cui layout.",
              } },
            { version = "0.2.0", date = "2026-10-18",
              added = {
                  "Layout mode (/cui layout): drag, resize and scale any Cys UI element, with grid snapping, exact X / Y fields and per-element reset. New elements get it automatically.",
                  "Info Bar module: a slim bar with combat timer, guild and friends online, durability, bag slots, gold, FPS / latency and a clock. Choose which show and their order under /cui > Info Bar.",
              } },
            { version = "0.1.1", date = "2026-10-18",
              fixed = {
                  "The settings window is taller and its pages scroll, so nothing runs off the bottom (the Modules list and the What's New buttons were cut off).",
              } },
            { version = "0.1.0", date = "2026-10-17",
              added = {
                  "The /cui settings window: switch each Cys addon on or off, see memory use, and reopen What's New.",
                  "Vendor module: a Sell Junk button at vendors (also in your bags), optional auto-sell of junk, and auto-repair.",
                  "/cui debug prints the client version and which game features exist (handy when checking WoW Forever).",
              } },
        },
    })
end
