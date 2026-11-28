--------------------------------------------------------------------------------
-- Cys's UI - Micro Menu & Bag Bar Panel
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local floor, max, min = math.floor, math.max, math.min

local MM = {}
CUI.MicroMenu = MM

local function DB()
    if not CysUIDB then CysUIDB = {} end
    if not CysUIDB.micromenu then
        CysUIDB.micromenu = {
            enable = true,
            hideBlizz = true,
        }
    end
    if CysUIDB.micromenu.hideBlizz == nil then CysUIDB.micromenu.hideBlizz = true end
    return CysUIDB.micromenu
end

local holder

-- Newer clients (Forever) replaced the old spellbook, talent and quest log windows. The Era way is tried
-- first, so Era behaves exactly as before; otherwise the newer call, and last of all a click on Blizzard's
-- own (hidden) micro button, which still opens the right window.
local function ClickBlizz(...)
    for i = 1, select("#", ...) do
        local b = _G[select(i, ...)]
        if b and b.Click then b:Click() return true end
    end
    return false
end

local function OpenSpells()
    if SpellBookFrame then ToggleFrame(SpellBookFrame) return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then PlayerSpellsUtil.ToggleSpellBookFrame() return end
    if ClickBlizz("SpellbookMicroButton", "PlayerSpellsMicroButton") then return end
    if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end
end

local function OpenTalents()
    if ToggleTalentFrame then ToggleTalentFrame() return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() return end
    ClickBlizz("TalentMicroButton", "PlayerSpellsMicroButton")
end

local function OpenQuests()
    if QuestLogFrame then ToggleFrame(QuestLogFrame) return end
    if ToggleQuestLog then ToggleQuestLog() return end
    ClickBlizz("QuestLogMicroButton")
end

local function OpenMenu()
    if GameMenuFrame then ToggleFrame(GameMenuFrame) return end
    ClickBlizz("MainMenuMicroButton")
end

local function FriendsOurs()
    return CysUI.Friends and CysUI.Friends.IsActive and CysUI.Friends.IsActive()
end

local function OpenBags()
    if _G.CysBagsFrame and CysBags and CysBags.Toggle then CysBags:Toggle() return end
    if ToggleAllBags then ToggleAllBags() end
end

-- secure = Blizzard's own micro button to click on WoW Forever. Opening Blizzard windows from addon code
-- leaves taint in the game's window manager, and then the world map's quest pins get blocked
-- (SetPassThroughButtons). A secure click on Blizzard's button opens the window the game's own way.
local buttons = {
    { text = "Character", func = function() ToggleCharacter("PaperDollFrame") end, secure = "CharacterMicroButton" },
    { text = "Spells",    func = OpenSpells,  secure = "SpellbookMicroButton" },
    { text = "Talents",   func = OpenTalents, secure = "TalentMicroButton" },
    { text = "Quests",    func = OpenQuests,  secure = "QuestLogMicroButton" },
    { text = "Social",    func = function()
        if FriendsOurs() then CysUI.Friends:Toggle() else ToggleFriendsFrame() end
    end, secure = "QuickJoinToastButton", unlessOurs = FriendsOurs },
    { text = "Guild",     func = function() ToggleGuildFrame() end, secure = "GuildMicroButton" },
    { text = "Bags",      func = OpenBags },
    { text = "Menu",      func = OpenMenu },
}

-- Blizzard's own micro buttons (Character, Spellbook, Talents, Quests, Social, Guild / Communities,
-- Group Finder, Help, the "!" chat button...). Tucked away in a hidden frame: invisible and unclickable,
-- and the game can't bring them back by showing them.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local BLIZZ_MICRO = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton", "WorldMapMicroButton", "LFGMicroButton",
    "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
    "PVPMicroButton", "LFDMicroButton", "RaidMicroButton", "QuickJoinToastButton",
    "ProfessionMicroButton", "PlayerSpellsMicroButton", "HousingMicroButton",
    "MicroButtonAndBagsBar", "MicroMenu", "MicroMenuContainer",
}

function MM:HideBlizzard()
    local seen = {}
    if CysUICompat and CysUICompat.isForever then
        -- WoW Forever: alpha and mouse only. Replacing the micro bar's Layout or moving its buttons to another
        -- parent spreads taint into Edit Mode and the window manager, so Blizzard's bar stays where it is,
        -- just invisible and unclickable. Our panel clicks its buttons securely.
        local function Fade(frame)
            if not frame or seen[frame] then return end
            seen[frame] = true
            if frame.SetAlpha then frame:SetAlpha(0) end
            if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
        end
        for _, name in ipairs(BLIZZ_MICRO) do Fade(_G[name]) end
        if type(MICRO_BUTTONS) == "table" then
            for _, name in ipairs(MICRO_BUTTONS) do Fade(_G[name]) end
        end
        -- every button on Blizzard's micro bar, also ones not named above (like Professions): a faded button
        -- that still takes the mouse shows its tooltip over whatever sits there (our right-hand bars)
        for _, name in ipairs({ "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" }) do
            local bar = _G[name]
            if bar and bar.GetChildren then
                for _, child in ipairs({ bar:GetChildren() }) do
                    if child ~= _G.QueueStatusButton then Fade(child) end -- keep the queue (LFG) eye
                end
            end
        end
        return
    end
    -- Blizzard re-runs the micro bar's Layout whenever a button is moved out of it, and with the buttons
    -- gone that layout compares nil positions and errors. Nobody needs it once the bar is hidden.
    for _, name in ipairs({ "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" }) do
        local f = _G[name]
        if f then
            f.Layout = function() end
            f.UpdateHelpTicketButtonAnchor = function() end
        end
    end
    local function Hide(frame)
        if not frame or seen[frame] then return end
        seen[frame] = true
        if frame.SetParent then pcall(frame.SetParent, frame, hiddenParent) end
        if frame.Hide then frame:Hide() end
    end
    for _, name in ipairs(BLIZZ_MICRO) do Hide(_G[name]) end
    if type(MICRO_BUTTONS) == "table" then
        for _, name in ipairs(MICRO_BUTTONS) do Hide(_G[name]) end
    end
end

function MM.Enable()
    local db = DB()
    if not db.enable then return end

    if db.hideBlizz then MM:HideBlizzard() end

    -- Create Container Panel
    local numButtons = #buttons
    local padding = 2
    holder = CreateFrame("Frame", "CysUI_MicroMenuPanel", UIParent)
    MM.holder = holder
    holder:SetSize(numButtons * 55 + (numButtons + 1) * padding, 18 + padding * 2)

    local btns, seps = {}, {}
    -- buttons share the panel's width, so the panel can be resized in layout mode
    local function Relayout()
        -- the panel holds secure buttons on Forever, so it can't be resized in combat: catch up afterwards
        if InCombatLockdown() then holder.cysPending = true return end
        holder.cysPending = nil
        local w, h = holder:GetWidth(), holder:GetHeight()
        if DB().popup then
            -- popup: a short vertical list over the Menu button, like a dropdown
            local rowH = floor((h - padding * 2) / numButtons)
            for i, btn in ipairs(btns) do
                btn:SetSize(w - padding * 2, rowH)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", holder, "TOPLEFT", padding, -padding - (i - 1) * rowH)
                btn.label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(11), "OUTLINE")
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", btn, "LEFT", 10, 0)
                if seps[i] then seps[i]:Hide() end
            end
            return
        end
        local bh = max(h - padding * 2, 8)
        local function Edge(i) return floor((i - 1) * w / numButtons + 0.5) end -- whole pixels: every cell the same, text dead centre
        local size = max(8, min(10, floor(bh * 0.5 + 0.5)))
        -- one size for every label: the largest that still fits the longest word
        for i, btn in ipairs(btns) do
            local cell = Edge(i + 1) - Edge(i)
            btn.label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "OUTLINE")
            while size > 8 and btn.label:GetStringWidth() > cell - 6 do
                size = size - 1
                btn.label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "OUTLINE")
            end
        end
        for i, btn in ipairs(btns) do
            local cell = Edge(i + 1) - Edge(i)
            btn:SetSize(cell, bh)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", holder, "LEFT", Edge(i), 0)
            btn.label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(size), "OUTLINE")
            btn.label:ClearAllPoints()
            btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            if seps[i] then
                seps[i]:Show()
                seps[i]:SetSize(1, max(bh - 4, 4))
                seps[i]:ClearAllPoints()
                seps[i]:SetPoint("LEFT", holder, "LEFT", Edge(i + 1), 0)
            end
        end
    end

    CUI:RegisterMovable(holder, "micromenu", "Micro Menu", {
        point = "BOTTOMRIGHT", x = -180, y = 30,
        scalable = false,
        resizable = true, minW = 220, maxW = 900, minH = 14, maxH = 40,
        onResize = function() Relayout() end,
    })

    -- Solid Dark Background matching CysUI theme
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(holder)
    bg:SetColorTexture(T.bg[1] or 0.08, T.bg[2] or 0.08, T.bg[3] or 0.08, 0.9)
    if W and W.Border then W.Border(holder, 1, T.border, "OVERLAY") end

    local forever = CysUICompat and CysUICompat.isForever
    local secureBtns = {}
    for i, info in ipairs(buttons) do
        local blizz = forever and info.secure and _G[info.secure]
        local btn
        if blizz then
            btn = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
            btn:RegisterForClicks("AnyUp")
            btn:SetAttribute("useOnKeyDown", false)
            btn:SetAttribute("type", "click")
            btn:SetAttribute("clickbutton", blizz)
            btn.cysInfo = info
            secureBtns[#secureBtns + 1] = btn
            -- a button that sometimes opens our own window (Social with Cys's Friends on) drops its secure
            -- click then (set out of combat) and runs ours instead
            if info.unlessOurs then
                btn:HookScript("OnClick", function(self)
                    if self:GetAttribute("type") ~= "click" then pcall(info.func) end
                end)
            end
        else
            btn = CreateFrame("Button", nil, holder)
            btn:SetScript("OnClick", info.func)
        end
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(CysUICompat.Font(), CysUICompat.FontSize(9), "OUTLINE")
        label:SetText(info.text)
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.label = label
        label:SetTextColor(1, 1, 1, 1)
        local hl = btn:CreateTexture(nil, "BACKGROUND")
        hl:SetPoint("TOPLEFT", 1, 0)
        hl:SetPoint("BOTTOMRIGHT", -1, 0)
        hl:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.22)
        hl:Hide()
        -- opened from the data panel's Menu button: picking something closes it again (out of combat)
        btn:HookScript("OnClick", function()
            if DB().popup and not InCombatLockdown() then
                holder:Hide()
                if CUI.InfoBar then CUI.InfoBar:UpdateItem("menu") end
            end
        end)
        btn:SetScript("OnEnter", function() label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1); hl:Show() end)
        btn:SetScript("OnLeave", function() label:SetTextColor(1, 1, 1, 1); hl:Hide() end)
        btns[i] = btn

        -- a thin gold separator to the right of each button except the last
        if i < numButtons then
            local sep = holder:CreateTexture(nil, "ARTWORK")
            local c = T.border or { 1, 0.82, 0, 1 }
            sep:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            if W and W.TrackEdge then W.TrackEdge(sep) end
            seps[i] = sep
        end
    end
    MM.Relayout = Relayout
    Relayout()
    if db.popup then holder:Hide() end
    -- popup: Layout mode puts the panel back on its own box; pin it over the Menu button again
    hooksecurefunc(CUI, "ApplyLayout", function(_, key)
        if key == "micromenu" and DB().popup and MM.anchorBtn then MM.PlaceAbove(MM.anchorBtn) end
    end)

    local function SyncSecure()
        if InCombatLockdown() then return end
        for _, btn in ipairs(secureBtns) do
            local ours = btn.cysInfo.unlessOurs and btn.cysInfo.unlessOurs()
            btn:SetAttribute("type", (not ours) and "click" or nil)
        end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and holder.cysPending then Relayout() end
        -- Blizzard can add micro buttons after we load: fade them too (alpha/mouse only, out of combat)
        if event == "PLAYER_ENTERING_WORLD" and db.hideBlizz and not InCombatLockdown() then MM:HideBlizzard() end
        C_Timer.After(0, SyncSecure)
    end)
end

-- Popup: the panel stays hidden and opens just above the data panel's Menu button (Info Bar > Micro menu button).
-- Its box is pinned there out of combat; its own saved Layout spot is kept for when popup goes off again.
function MM.PlaceAbove(btn)
    MM.anchorBtn = btn
    local m = CUI.movers and CUI.movers.micromenu
    if not (holder and m and btn and DB().popup) or InCombatLockdown() then return end
    -- a compact list on a high layer, so bars and icon columns near the button never cover it
    local rows = #buttons
    holder:SetSize(120, rows * 20 + 4)
    holder:SetFrameStrata("DIALOG")
    m.mover:SetSize(120, rows * 20 + 4)
    m.mover:ClearAllPoints()
    m.mover:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 4)
    if MM.Relayout then MM.Relayout() end
end

function MM.SetPopup(on)
    local db = DB()
    db.popup = on and true or false
    if not holder or InCombatLockdown() then return end
    if on then
        holder:Hide()
        if MM.anchorBtn then MM.PlaceAbove(MM.anchorBtn) end
    else
        holder:SetFrameStrata("MEDIUM")
        holder:Show()
        CUI:ApplyLayout("micromenu")
    end
    if CUI.InfoBar then
        local ib = CysUIDB.infobar
        if ib and ib.enabled then ib.enabled.menu = on and true or ib.enabled.menu end
        CUI.InfoBar:Apply()
    end
end

CUI:RegisterModule({
    key = "micromenu",
    name = "Micro Menu",
    addon = "CysUI",
    desc = "Sleek text-based Micro Menu panel for quick access to character, bags, spellbook, and menus.",
    onEnable = MM.Enable,
    open = function() CUI:OpenConfig("Micro Menu") end,
})

CUI:RegisterPage("Micro Menu", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Micro Menu", width):SetPoint("TOPLEFT", 0, -4)

    local cb = W.Checkbox(page, "Show the Micro Menu panel (needs a /reload)", function() return db.enable end,
        function(on) db.enable = on end)
    cb:SetPoint("TOPLEFT", 4, -34)
    local hide = W.Checkbox(page, "Hide Blizzard's micro buttons (turning off needs a /reload)",
        function() return db.hideBlizz end,
        function(on) db.hideBlizz = on; if on then MM:HideBlizzard() end end)
    hide:SetPoint("TOPLEFT", 4, -60)
    local pop = W.Checkbox(page, "Keep it hidden; open it from the Menu button on the Info Bar / data panel",
        function() return db.popup end, function(on) MM.SetPopup(on) end)
    pop:SetPoint("TOPLEFT", 4, -86)

end)