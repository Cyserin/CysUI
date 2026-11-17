--------------------------------------------------------------------------------
-- Cys's UI - Click-Casting
--
-- Bind mouse buttons (with Shift / Ctrl / Alt) on Cys's unit frames to spells, macros or Target. Click a party
-- member's frame with Shift + right button and your heal lands on them, no targeting needed.
--
-- How: every Cys unit frame is a secure unit button. Out of combat we write the binding into the frame's own
-- attributes (shift-type2 = "spell", shift-spell2 = "Healing Wave"); the game then casts it on that frame's unit.
-- Frames are found through the ClickCastFrames table (the same one Clique uses), so raid frames that appear later
-- are picked up too. Bindings are saved per character. Changes made during a fight wait until it ends.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local CC = {}
CUI.ClickCast = CC

local BUTTONS = { "Left", "Right", "Middle", "Button 4", "Button 5" }
local MOUSE = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }

local function DB()
    CysUICharDB = CysUICharDB or {}
    local db = CysUICharDB.clickcast
    if type(db) ~= "table" then
        db = { binds = {}, down = false }
        CysUICharDB.clickcast = db
    end
    db.binds = db.binds or {}
    -- the game's two built-in clicks, as fixed rows at the top: give them another click to free left / right
    if not db.defaults then
        db.defaults = true
        table.insert(db.binds, 1, { kind = "menu", btn = 2, mods = "", fixed = true })
        table.insert(db.binds, 1, { kind = "target", btn = 1, mods = "", fixed = true })
    end
    return db
end

-- Clique does the same job: if it is running, we stay out of its way
local function CliqueLoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return f and f("Clique") and true or false
end

-- "alt-ctrl-shift-" in the order the game builds it
local function ModsNow()
    local m = ""
    if IsAltKeyDown() then m = m .. "alt-" end
    if IsControlKeyDown() then m = m .. "ctrl-" end
    if IsShiftKeyDown() then m = m .. "shift-" end
    return m
end

local function ComboText(b)
    local t = {}
    if b.mods:find("alt%-") then t[#t + 1] = "Alt" end
    if b.mods:find("ctrl%-") then t[#t + 1] = "Ctrl" end
    if b.mods:find("shift%-") then t[#t + 1] = "Shift" end
    t[#t + 1] = (BUTTONS[b.btn] or "?") .. (b.btn <= 3 and " click" or "")
    return table.concat(t, " + ")
end

local function SpellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not n and GetSpellInfo then n = GetSpellInfo(id) end
    return n
end

local function SpellRank(id)
    local s = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if (not s or s == "") and GetSpellSubtext then s = GetSpellSubtext(id) end
    return s ~= "" and s or nil
end

local function SpellIcon(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
end

--------------------------------------------------------------------------------
-- Writing the bindings into the frames
--------------------------------------------------------------------------------
local pending = false
local frames -- the ClickCastFrames table

-- attribute name -> value for one binding (nil when the binding sets nothing)
--
-- How a click reaches us on Forever: the game first reads the plain click's type. On a modified click with
-- nothing there it falls back to target / menu and, with no click binding of its own for that, stops. So every
-- modified click gets a harmless placeholder; then the game swaps the button for one of our made-up names
-- (helpbutton on units you can help, harmbutton on enemies) and reads the real action from that.
local function AttrsFor(b, out)
    local sfx = tostring(b.btn)
    local plain = b.mods == "" and b.btn <= 2 -- the game's own left / right clicks
    local nav = b.kind == "target" or b.kind == "menu"
    -- target on plain left / menu on plain right: that is what the game does already
    if nav and plain and ((b.kind == "target" and b.btn == 1) or (b.kind == "menu" and b.btn == 2)) then return end
    local alias = (nav and "cys" .. b.kind or "cyshelp") .. sfx
    local key = "-" .. alias
    out[b.mods .. "helpbutton" .. sfx] = alias
    if nav then out[b.mods .. "harmbutton" .. sfx] = alias end -- target / menu work on enemies too
    if not plain and out[b.mods .. "type" .. sfx] == nil then
        if b.kind == "target" then
            -- neutral units (neither friend nor foe) get no swap: target them with a one-line macro
            out[b.mods .. "type" .. sfx] = "macro"
            out[b.mods .. "macrotext" .. sfx] = "/target [@mouseover]"
        else
            out[b.mods .. "type" .. sfx] = "spell"
        end
    end
    if b.kind == "spell" and b.id then
        out[b.mods .. "type" .. key] = "spell"
        out[b.mods .. "spell" .. key] = (b.max ~= false and b.name) or b.id
    elseif b.kind == "macro" and b.macro then
        out[b.mods .. "type" .. key] = "macro"
        out[b.mods .. "macro" .. key] = b.macro
    elseif b.kind == "target" then
        out[b.mods .. "type" .. key] = "target"
    elseif b.kind == "menu" then
        out[b.mods .. "type" .. key] = "togglemenu"
    end
end

local function Wanted()
    local out = {}
    if not CUI:IsModuleEnabled("clickcast") or CliqueLoaded() then return out, false end
    local any = false
    for _, b in ipairs(DB().binds) do
        if b.btn then AttrsFor(b, out); any = true end
    end
    return out, any
end

local function ApplyFrame(f, want, any)
    if type(f) ~= "table" or not f.SetAttribute or (f.IsForbidden and f:IsForbidden()) then return end
    local had = f.cysCC
    if had then for name in pairs(had) do f:SetAttribute(name, nil) end end
    local set = {}
    for name, v in pairs(want) do f:SetAttribute(name, v); set[name] = true end
    f.cysCC = set
    if f.RegisterForClicks then
        if any then
            -- one press, one cast: the frames used to listen to both the press and the release
            f:RegisterForClicks(DB().down and "AnyDown" or "AnyUp")
            f.cysCCClicks = true
        elseif f.cysCCClicks then
            f:RegisterForClicks("AnyUp", "AnyDown")
            f.cysCCClicks = nil
        end
    end
end

function CC.Apply()
    if InCombatLockdown() then pending = true; return end
    pending = false
    if not frames then return end
    local want, any = Wanted()
    for f, v in pairs(frames) do if v then pcall(ApplyFrame, f, want, any) end end
    if CC.Repaint then CC.Repaint() end
end

local function Watch()
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    frames = _G.ClickCastFrames
    if getmetatable(frames) then return end -- someone else (Clique) already manages it
    setmetatable(frames, { __newindex = function(t, f, v)
        rawset(t, f, v)
        -- a frame made later (raid members): set it up once its own setup has finished
        C_Timer.After(0, function()
            if InCombatLockdown() then pending = true return end
            local want, any = Wanted()
            pcall(ApplyFrame, f, want, any)
        end)
    end })
end

function CC.Enable()
    Watch()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then CC.Apply() end
        elseif event == "SPELLS_CHANGED" then
            -- names stay the same across ranks, so only a fresh look at "highest rank" spells is needed
            if not InCombatLockdown() then CC.Apply() else pending = true end
        else
            CC.Apply()
        end
    end)
    CC.Apply()
    if CC.AttachIfLoaded then CC.AttachIfLoaded() end
end

CUI:RegisterModule({
    key = "clickcast",
    name = "Click-Casting",
    addon = "CysUI",
    foreverOnly = true,
    desc = "Click Cys's unit frames with a mouse button (plus Shift, Ctrl or Alt) to cast a spell or macro on that unit.",
    onEnable = CC.Enable,
    open = function() CUI:OpenConfig("Click-Casting") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local ROW_H = 34

local function NewBind(kind)
    local db = DB()
    local b = { kind = kind, mods = "", max = true }
    db.binds[#db.binds + 1] = b
    return b
end

-- a spell or macro on the cursor becomes a new binding (no mouse button yet)
local function TakeCursor()
    local kind, a, _, d = GetCursorInfo()
    if kind == "spell" then
        local id = type(d) == "number" and d or nil
        if not id and type(a) == "number" and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local info = C_SpellBook.GetSpellBookItemInfo(a, Enum.SpellBookSpellBank.Player)
            id = info and info.spellID
        end
        if not id then return false end
        local b = NewBind("spell")
        b.id, b.name = id, SpellName(id)
        ClearCursor()
        return true
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        if not name then return false end
        local b = NewBind("macro")
        b.macro = name
        ClearCursor()
        return true
    end
    return false
end

local editors = {} -- every open editor (settings page, spellbook panel) repaints after a change
CC.Repaint = function() for _, f in ipairs(editors) do f() end end

-- The editor itself: used on the settings page and in the panel beside the spellbook (compact = no notes)
local function BuildEditor(page, width, compact)
    local db = DB()

    local warn = W.Text(page, 11, { 1, 0.4, 0.3 })
    warn:SetPoint("TOPLEFT", 4, -28)
    warn:SetWidth(width)
    warn:SetJustifyH("LEFT")

    -- add: drop box + Target
    local drop = CreateFrame("Button", nil, page)
    drop:SetSize(200, 30)
    drop:SetPoint("TOPLEFT", 4, -48)
    W.Texture(drop, "BACKGROUND", T.field):SetAllPoints()
    drop.edges = W.Border(drop, 1, T.border, "BORDER")
    local dropText = W.Text(drop, 11, T.accent, "CENTER")
    dropText:SetPoint("CENTER")
    dropText:SetText("+ Drop a spell or macro here")
    local Rebuild
    local function Take() if TakeCursor() then Rebuild(); CC.Apply() end end
    drop:SetScript("OnReceiveDrag", Take)
    drop:SetScript("OnClick", Take)
    drop:SetScript("OnEnter", function(self)
        W.SetBorder(self.edges, T.glow)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Add a binding", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Drag a spell from your spellbook or a macro from the macro window and drop it here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    drop:SetScript("OnLeave", function(self) W.SetBorder(self.edges, T.border); GameTooltip:Hide() end)


    local downBox = W.Checkbox(page, "Cast when the mouse button goes down (faster)", function() return db.down end,
        function(on) db.down = on; CC.Apply() end)
    downBox:SetPoint("TOPLEFT", 4, -88)

    local listTop = -120
    local rows = {}

    local function MakeRow(i)
        local r = CreateFrame("Frame", nil, page)
        r:SetSize(width, ROW_H)
        W.Texture(r, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.6 }):SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(26, 26)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = W.Text(r, 11, T.text)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
        r.name:SetWidth(140)
        r.name:SetWordWrap(false)
        r.sub = W.Text(r, 9, T.dim)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        r.sub:SetWidth(140)
        r.sub:SetWordWrap(false)

        -- the binding: click this button with the mouse button and keys you want
        r.combo = W.Button(r, 200, 24, "", true)
        r.combo:SetPoint("LEFT", 186, 0)
        r.combo:RegisterForClicks("AnyUp")
        r.combo:SetScript("OnClick", function(self, mouse)
            local b = self:GetParent().bind
            local n = MOUSE[mouse]
            if not (b and n) then return end
            b.btn, b.mods = n, ModsNow()
            Rebuild(); CC.Apply()
        end)
        r.combo:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Set the click", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Click here with the mouse button you want, holding Shift, Ctrl or Alt if you want those too.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r.combo:HookScript("OnLeave", function() GameTooltip:Hide() end)

        r.del = W.Button(r, 24, 24, "x")
        r.del:SetPoint("LEFT", r.combo, "RIGHT", 6, 0)
        r.del:SetScript("OnClick", function(self)
            local b = self:GetParent().bind
            for k, v in ipairs(db.binds) do if v == b then table.remove(db.binds, k) break end end
            Rebuild(); CC.Apply()
        end)

        -- spells: click the name area to switch between highest rank and the rank you dropped
        r.rank = CreateFrame("Button", nil, r)
        r.rank:SetPoint("TOPLEFT", r.icon, "TOPLEFT")
        r.rank:SetPoint("BOTTOMRIGHT", r.sub, "BOTTOMRIGHT")
        r.rank:SetScript("OnClick", function(self)
            local b = self:GetParent().bind
            if b.kind ~= "spell" then return end
            b.max = (b.max == false)
            Rebuild(); CC.Apply()
        end)
        r.rank:SetScript("OnEnter", function(self)
            local b = self:GetParent().bind
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if b.kind == "spell" and b.id then
                GameTooltip:SetSpellByID(b.id)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to switch between your highest rank and this exact rank.", 0.6, 0.6, 0.6, true)
            elseif b.kind == "macro" then
                GameTooltip:AddLine("Macro: " .. tostring(b.macro), 1, 1, 1)
                GameTooltip:AddLine("Use [@mouseover] in it to aim at the frame you click.", 0.6, 0.6, 0.6, true)
            elseif b.kind == "menu" then
                GameTooltip:AddLine("Opens the unit's right-click menu.", 1, 1, 1)
                GameTooltip:AddLine("The game's default. Give it another click to free that one for a spell.", 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine("Targets the unit you click.", 1, 1, 1)
                if b.fixed then GameTooltip:AddLine("The game's default. Give it another click to free that one for a spell.", 0.6, 0.6, 0.6, true) end
            end
            GameTooltip:Show()
        end)
        r.rank:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
        return r
    end

    local empty = W.Text(page, 11, T.desc)
    empty:SetText("No bindings yet. Drop a spell above to make one.")

    local notes
    function Rebuild()
        local seen, dup = {}, {}
        for _, b in ipairs(db.binds) do
            if b.btn then
                local k = b.mods .. b.btn
                if seen[k] then dup[k] = true end
                seen[k] = true
            end
        end
        for i, b in ipairs(db.binds) do
            local r = rows[i] or MakeRow(i)
            r.bind = b
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, listTop - (i - 1) * (ROW_H + 4))
            r:Show()
            if b.kind == "spell" then
                r.icon:SetTexture(SpellIcon(b.id) or 134400)
                r.name:SetText(b.name or SpellName(b.id) or ("Spell " .. tostring(b.id)))
                local rk = SpellRank(b.id)
                r.sub:SetText(b.max ~= false and "Highest rank" or (rk or "This rank"))
            elseif b.kind == "macro" then
                local _, icon = GetMacroInfo(b.macro or "")
                r.icon:SetTexture(icon or 134400)
                r.name:SetText(b.macro or "?")
                r.sub:SetText(icon and "Macro" or "Macro (not found)")
            elseif b.kind == "menu" then
                r.icon:SetTexture(134331)
                r.name:SetText("Open Context Menu")
                r.sub:SetText("Default")
            else
                r.icon:SetTexture(132212)
                r.name:SetText(b.fixed and "Target Unit Frame" or "Target")
                r.sub:SetText(b.fixed and "Default" or "Target the unit")
            end
            r.del:SetShown(not b.fixed) -- the two defaults stay; only their click changes
            if b.btn then
                local k = b.mods .. b.btn
                r.combo:SetLabel(dup[k] and ("|cFFFF6650" .. ComboText(b) .. "|r") or ComboText(b))
            else
                r.combo:SetLabel("Click here to set")
            end
        end
        for i = #db.binds + 1, #rows do rows[i]:Hide(); rows[i].bind = nil end
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", 8, listTop - 8)
        empty:SetShown(#db.binds == 0)
        local bottom = listTop - math.max(1, #db.binds) * (ROW_H + 4) - 12
        if notes then notes:ClearAllPoints(); notes:SetPoint("TOPLEFT", 4, bottom) end
        page.contentHeight = -bottom + (notes and notes:GetHeight() or 0) + 20
        if page.OnHeight then page.OnHeight(page.contentHeight) end

        local msg
        if CliqueLoaded() then
            msg = "Clique is running, so Cys's click-casting stays off. Turn one of them off."
        elseif not CUI:IsModuleEnabled("clickcast") then
            msg = "Click-Casting is switched off in Modules."
        elseif InCombatLockdown() or pending then
            msg = "Changes apply when this fight ends."
        elseif next(dup) then
            msg = "Two bindings use the same click (red): only one of them will work."
        end
        warn:SetText(msg or "")
    end
    editors[#editors + 1] = function() if page:IsVisible() then Rebuild() end end

    if not compact then notes = W.Notes(page, 4, listTop - ROW_H - 12, width, "", {
        { "Add", "drop a spell or macro on the box, then click the gold button on its row with the mouse button you want (hold Shift, Ctrl or Alt for those)." },
        { "Defaults", "Target Unit Frame and Open Context Menu are the game's left and right click. Give them another click (for example Shift + left) to use plain left or right for a heal." },
        { "Where", "works on Cys's player, target, focus, pet, party and raid frames." },
        { "Ranks", "spells cast your highest rank. Click a spell's name to cast exactly the rank you dropped instead." },
        { "Friendly only", "spells and macros work on frames of units you can help. On an enemy (your target frame) plain left and right still target and open the menu." },
        { "Game bindings", "spells bound in the game's own Click Casting window win over these on the same click." },
        { "Combat", "you can edit any time; changes made in a fight apply when it ends." },
        { "Spellbook", "a Click-casting button beside the spellbook opens this list there too (or type /cuiclick)." },
    }) end
    Rebuild()
    page:HookScript("OnShow", Rebuild)
    return Rebuild
end

CUI:RegisterPage("Click-Casting", function(page)
    W.Header(page, "Click-Casting", 500):SetPoint("TOPLEFT", 0, -4)
    BuildEditor(page, 500)
end)

--------------------------------------------------------------------------------
-- Beside the spellbook: a Click-casting button, and the list in a panel docked to the spellbook's right (or to
-- the right of the Spell Ranks window when that is open). Blizzard's frames are only used as anchors.
--------------------------------------------------------------------------------
local PANEL_W = 524
local panel, opener, bookUp, hookedBook, hookedRanks

local function BuildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "CysClickCastFrame", UIParent)
    panel:SetSize(PANEL_W, 200)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    W.Texture(panel, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(panel, 2, T.border, "BORDER")
    local strip = W.Texture(panel, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(24)
    local line = W.Texture(panel, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -26)
    line:SetPoint("TOPRIGHT", -2, -26)
    line:SetHeight(2)
    local title = W.Text(panel, 12, T.accent)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("CLICK-CASTING")
    local close = W.Button(panel, 18, 18, "x")
    close:SetPoint("TOPRIGHT", -6, -5)
    close:SetScript("OnClick", function() DB().panel = false; CC.Sync() end)
    local more = W.Button(panel, 70, 18, "Settings")
    more:SetPoint("RIGHT", close, "LEFT", -6, 0)
    more:SetScript("OnClick", function() CUI:OpenConfig("Click-Casting") end)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 6, -30)
    body:SetSize(PANEL_W - 12, 160)
    body.OnHeight = function(h)
        body:SetHeight(h)
        panel:SetHeight(h + 34)
    end
    BuildEditor(body, PANEL_W - 24, true)
end

local function BuildOpener()
    if opener then return end
    opener = W.Button(UIParent, 96, 22, "Click-casting")
    opener:SetFrameStrata("HIGH")
    opener:Hide()
    opener:SetScript("OnClick", function() DB().panel = true; CC.Sync() end)
end

-- where we dock: right of Spell Ranks' window if it is up, else right of the spellbook (under Spell Ranks' button)
local function Dock()
    local host = _G.PlayerSpellsFrame
    local rk = _G.CysRanksFrame
    if rk and not hookedRanks and rk.HookScript then
        hookedRanks = true
        rk:HookScript("OnShow", function() CC.Sync() end)
        rk:HookScript("OnHide", function() CC.Sync() end)
    end
    if rk and rk:IsShown() then return rk, 0 end
    local ranksOn = CUI.modules and CUI.modules.ranks and CUI:IsModuleEnabled("ranks")
    return host, ranksOn and -28 or 0
end

function CC.Sync()
    local host = _G.PlayerSpellsFrame
    if not (bookUp and host) then
        if panel then panel:Hide() end
        if opener then opener:Hide() end
        return
    end
    local anchor, y = Dock()
    if DB().panel then
        BuildPanel()
        if opener then opener:Hide() end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, y)
        panel:Show()
    else
        BuildOpener()
        if panel then panel:Hide() end
        opener:ClearAllPoints()
        opener:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, y - 2)
        opener:Show()
    end
end

local function AttachBook()
    if hookedBook then return end
    local host = _G.PlayerSpellsFrame
    local book = host and host.SpellBookFrame
    if not (book and book.HookScript) then return end
    hookedBook = true
    -- a frame later, so Spell Ranks has placed itself first
    book:HookScript("OnShow", function() bookUp = true; DB().panel = false; C_Timer.After(0, CC.Sync) end)
    -- closed again each time the spellbook closes: it opens with just the button, the panel on request
    book:HookScript("OnHide", function() bookUp = false; DB().panel = false; CC.Sync() end)
    local ok, vis = pcall(function() return book:IsVisible() and true or false end)
    bookUp = ok and vis or false
    CC.Sync()
end

local bookEv = CreateFrame("Frame")
bookEv:RegisterEvent("ADDON_LOADED")
bookEv:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_PlayerSpells" and CUI:IsModuleEnabled("clickcast") then AttachBook() end
end)
function CC.AttachIfLoaded()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded and loaded("Blizzard_PlayerSpells") then AttachBook() end
end

SLASH_CYSUICLICK1 = "/cuiclick"
SlashCmdList.CYSUICLICK = function() CUI:OpenConfig("Click-Casting") end
