--------------------------------------------------------------------------------
-- Cys's UI - Class Macros
--
-- Your character-specific macros, shared with every character of the same class on your account. Make a macro
-- on one Paladin and your other Paladins get it too. (The game's General macros are already shared by every
-- character; this is for the Character tab.)
--
-- Saved in CysUIDB.macros.classes[CLASS][name] = { icon, body, from, t }. A macro is matched by its name.
-- Only macros you change on a character are saved from it, so an older copy on an alt never overwrites the
-- newer one in the class list. Macros are never deleted from a character; take one off the class list on
-- the settings page.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "classmacros", name = "Class Macros",
    desc = "Shares your character macros with every character of the same class: make a macro on one and your other characters of that class get it too.",
    open = function() CysUI:OpenConfig("Class Macros") end,
    body = function()
local CUI = CysUI
local W = CUI.W
local T = W.T
local min = math.min

CysUIDB.macros = CysUIDB.macros or {}
local db = CysUIDB.macros
db.classes = db.classes or {}
if db.mode == nil then db.mode = "ask" end -- "sync", "ask" or "manual"

local _, CLASS = UnitClass("player")
local className = UnitClass("player")
db.classes[CLASS] = db.classes[CLASS] or {}
local function Set() return db.classes[CLASS] end

local ACCOUNT = MAX_ACCOUNT_MACROS or 120
local PERCHAR = MAX_CHARACTER_MACROS or 18
local QUESTION = 134400 -- INV_Misc_QuestionMark

local function Seen()
    CysUICharDB = CysUICharDB or {}
    CysUICharDB.macroSeen = CysUICharDB.macroSeen or {}
    return CysUICharDB.macroSeen
end

-- How two copies of a macro are compared. The text is tidied first (line endings, trailing spaces and blank
-- lines) so tiny differences the game adds don't count. A macro with #show or #showtooltip gets its icon from
-- the spell, so the game reports that icon instead of the saved one and the icon is left out of the compare;
-- otherwise those macros would look "changed" on every login even right after adding them.
local function Tidy(body)
    body = (body or ""):gsub("\r\n?", "\n"):gsub("[ \t]+\n", "\n"):gsub("%s+$", "")
    return body
end
local function Key(icon, body)
    body = Tidy(body)
    local lower = body:lower()
    if lower:find("^#show") or lower:find("\n#show") then return "\1" .. body end
    return tostring(icon or "") .. "\1" .. body
end

-- this character's macros: name -> { index, icon, body }
local function Mine()
    local out, count = {}, 0
    local _, numChar = GetNumMacros()
    for i = 1, numChar or 0 do
        local idx = ACCOUNT + i
        local name, icon, body = GetMacroInfo(idx)
        if name and not out[name] then out[name] = { index = idx, icon = icon, body = body or "" } end
        count = count + 1
    end
    return out, count
end

local listeners = {}
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

-- remember what this character has now, so the next change can tell what you edited here
local function Remember()
    local seen = Seen()
    wipe(seen)
    for name, m in pairs(Mine()) do seen[name] = Key(m.icon, m.body) end
end

-- save into the class list: all = every macro here, otherwise only the ones you changed since last seen
local function Save(all)
    local set, seen, n = Set(), Seen(), 0
    local me = UnitName("player")
    for name, m in pairs(Mine()) do
        local k = Key(m.icon, m.body)
        local s = set[name]
        if (all or seen[name] ~= k) and not (s and Key(s.icon, s.body) == k) then
            set[name] = { icon = m.icon, body = m.body, from = me, t = time() }
            n = n + 1
        end
    end
    Remember()
    if n > 0 then Changed() end
    return n
end

-- class macros that are missing here or different
local function Pending()
    local mine, out = Mine(), {}
    for name, s in pairs(Set()) do
        local m = mine[name]
        if not m or Key(m.icon, m.body) ~= Key(s.icon, s.body) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

local busy, waiting = false, false
local ready = false -- set after the login check, so saving never runs before the class list is applied

local function Load(quiet)
    if InCombatLockdown() then
        waiting = true
        if not quiet then CUI:Print("Class Macros: in combat, adding them when the fight ends.") end
        return
    end
    local names = Pending()
    if #names == 0 then
        if not quiet then CUI:Print("Class Macros: this character already has all your " .. className .. " macros.") end
        ready = true Remember()
        return
    end
    busy = true
    local added, updated, full = 0, 0, {}
    local mine, count = Mine()
    -- edits first: a new macro can shift the indexes of the ones after it
    for _, name in ipairs(names) do
        local s, m = Set()[name], mine[name]
        if m and pcall(EditMacro, m.index, name, s.icon or QUESTION, s.body or "") then updated = updated + 1 end
    end
    for _, name in ipairs(names) do
        local s = Set()[name]
        if mine[name] then
            -- done above
        elseif count < PERCHAR then
            if pcall(CreateMacro, name, s.icon or QUESTION, s.body or "", true) then
                added, count = added + 1, count + 1
            end
        else
            full[#full + 1] = name
        end
    end
    busy = false
    ready = true
    Remember()
    if not quiet or added + updated > 0 or #full > 0 then
        CUI:Print(format("Class Macros: %d added, %d updated from your other %s characters.", added, updated, className))
    end
    if #full > 0 then
        CUI:Print(format("    No room for %d (character macros are full, %d max): %s", #full, PERCHAR, table.concat(full, ", ")))
    end
    Changed()
end

StaticPopupDialogs["CYSUI_CLASSMACROS"] = {
    text = "Cys's UI: %s",
    button1 = "Add them", button2 = "Not now",
    OnAccept = function() Load() end,
    OnCancel = function() ready = true Remember() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function LoginCheck()
    if db.mode == "manual" then ready = true Remember() return end
    local names = Pending()
    if #names == 0 then ready = true Remember() return end
    if db.mode == "sync" then
        Load(true)
    else
        local shown = {}
        for i = 1, min(#names, 6) do shown[i] = names[i] end
        local more = #names > 6 and format(" and %d more", #names - 6) or ""
        StaticPopup_Show("CYSUI_CLASSMACROS", format("%d %s macro%s from your other characters %s new or changed here:\n%s%s",
            #names, className, #names == 1 and "" or "s", #names == 1 and "is" or "are", table.concat(shown, ", "), more))
    end
end

local pendingSave
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_MACROS")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, e, isLogin, isReload)
    if e == "PLAYER_ENTERING_WORLD" then
        if isLogin or isReload then C_Timer.After(3, LoginCheck) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if waiting then waiting = false Load() end
    elseif e == "UPDATE_MACROS" then
        if busy or not ready or db.mode == "manual" or pendingSave then return end
        pendingSave = true
        C_Timer.After(1, function() pendingSave = nil if ready and not busy and db.mode ~= "manual" then Save() end end)
    end
end)

SLASH_CYSUICLASSMACROS1 = "/cuimacros"
SlashCmdList.CYSUICLASSMACROS = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "save" then
        CUI:Print(format("Class Macros: %d saved to your %s macros.", Save(true), className))
    elseif msg == "load" then
        Load()
    elseif msg == "list" then
        local names = {}
        for name in pairs(Set()) do names[#names + 1] = name end
        table.sort(names)
        CUI:Print(format("Your %s macros (%d): %s", className, #names, #names > 0 and table.concat(names, ", ") or "none yet"))
    else
        CUI:Print("/cuimacros save - save all this character's macros, load - add the class macros here, list - show them.")
    end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local rows, emptyText, moreText = {}, nil, nil
local ROWS = 14
local function PaintList()
    local names = {}
    for name in pairs(Set()) do names[#names + 1] = name end
    table.sort(names)
    local mine = Mine()
    for i = 1, ROWS do
        local row, name = rows[i], names[i]
        if not row then break end
        if name then
            local s = Set()[name]
            row.macro = name
            row.icon:SetTexture(s.icon or QUESTION)
            row.name:SetText(name)
            row.from:SetText(s.from and ("from " .. s.from) or "")
            local m = mine[name]
            local here = not m and "|cffff9f43not here|r" or (Key(m.icon, m.body) ~= Key(s.icon, s.body) and "|cffff9f43different here|r" or "|cff4fd66bhere|r")
            row.state:SetText(here)
            row:Show()
        else
            row:Hide()
        end
    end
    if emptyText then emptyText:SetShown(#names == 0) end
    if moreText then
        moreText:SetShown(#names > ROWS)
        moreText:SetText(format("and %d more (/cuimacros list)", #names - ROWS))
    end
end
listeners[#listeners + 1] = function() if rows[1] and rows[1]:GetParent():IsVisible() then PaintList() end end

CUI:RegisterPage("Class Macros", function(page)
    local width = 480
    W.Header(page, "Class Macros", width):SetPoint("TOPLEFT", 0, -4)

    local lbl = W.Text(page, 12, T.text)
    lbl:SetPoint("TOPLEFT", 4, -38)
    lbl:SetText("Share macros")
    local dd = W.Dropdown(page, 300, {
        { "sync",   "Automatically" },
        { "ask",    "Automatically, but ask before adding" },
        { "manual", "Only when I click the buttons below" },
    }, function() return db.mode end, function(v) db.mode = v end)
    dd:SetPoint("TOPLEFT", 110, -34)

    local save = W.Button(page, 170, 22, "Save my macros now")
    save:SetPoint("TOPLEFT", 4, -70)
    save:SetScript("OnClick", function()
        CUI:Print(format("Class Macros: %d saved to your %s macros.", Save(true), className))
        PaintList()
    end)
    local load = W.Button(page, 170, 22, "Add class macros here")
    load:SetPoint("LEFT", save, "RIGHT", 8, 0)
    load:SetScript("OnClick", function() Load() PaintList() end)

    local head = W.Text(page, 12, T.brand)
    head:SetPoint("TOPLEFT", 4, -108)
    head:SetText("Your " .. className .. " macros")
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(width, 20)
        row:SetPoint("TOPLEFT", 4, -128 - (i - 1) * 20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = W.Text(row, 11, T.text)
        row.name:SetPoint("LEFT", 22, 0)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.from = W.Text(row, 11, T.desc)
        row.from:SetPoint("LEFT", 176, 0)
        row.from:SetWidth(130)
        row.from:SetJustifyH("LEFT")
        row.from:SetWordWrap(false)
        row.state = W.Text(row, 11, T.desc)
        row.state:SetPoint("LEFT", 310, 0)
        local x = W.Button(row, 20, 18, "x")
        x:SetPoint("RIGHT", -4, 0)
        x:SetScript("OnClick", function()
            if row.macro then Set()[row.macro] = nil PaintList() end
        end)
        x:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Take off the class list")
            GameTooltip:AddLine("Characters that have it keep it.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", GameTooltip_Hide)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local s = self.macro and Set()[self.macro]
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.macro)
            GameTooltip:AddLine(s.body or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        rows[i] = row
    end
    emptyText = W.Text(page, 11, T.desc)
    emptyText:SetPoint("TOPLEFT", 4, -128)
    emptyText:SetText("None yet. Make or change a macro on the Character tab, or click Save my macros now.")
    moreText = W.Text(page, 11, T.desc)
    moreText:SetPoint("TOPLEFT", 4, -128 - ROWS * 20)

    W.Notes(page, 4, -128 - ROWS * 20 - 24, width, "", {
        "Only the Character tab of the macro window is shared, per class. General macros are already on every character.",
        "Macros are matched by name. Rename one and it counts as a new macro.",
        "Deleting a macro on a character doesn't take it off the class list: use the x here, or it comes back on your next login.",
        "Put the macros on your action bars yourself on each character. /cuimacros save, load and list do the same from chat.",
    })
    PaintList()
end, function() PaintList() end)

    end,
})
