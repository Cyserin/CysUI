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

local buttons = {
    { text = "Character", func = function() ToggleCharacter("PaperDollFrame") end },
    { text = "Spells",    func = function() ToggleFrame(SpellBookFrame) end },
    { text = "Talents",   func = function() ToggleTalentFrame() end },
    { text = "Quests",    func = function() ToggleFrame(QuestLogFrame) end },
    { text = "Social",    func = function()
        if CysUI.Friends and CysUI.Friends.IsActive and CysUI.Friends.IsActive() then CysUI.Friends:Toggle() else ToggleFriendsFrame() end
    end },
    { text = "Guild",     func = function() ToggleGuildFrame() end },
    { text = "Bags",      func = function() ToggleAllBags() end },
    { text = "Menu",      func = function() ToggleFrame(GameMenuFrame) end },
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
    "MicroButtonAndBagsBar", "MicroMenu", "MicroMenuContainer",
}

function MM:HideBlizzard()
    local seen = {}
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
    holder:SetSize(numButtons * 55 + (numButtons + 1) * padding, 18 + padding * 2)

    local btns, seps = {}, {}
    -- buttons share the panel's width, so the panel can be resized in layout mode
    local function Relayout()
        local w, h = holder:GetWidth(), holder:GetHeight()
        local bh = max(h - padding * 2, 8)
        local function Edge(i) return floor((i - 1) * w / numButtons + 0.5) end -- whole pixels: every cell the same, text dead centre
        local size = max(8, min(10, floor(bh * 0.5 + 0.5)))
        -- one size for every label: the largest that still fits the longest word
        for i, btn in ipairs(btns) do
            local cell = Edge(i + 1) - Edge(i)
            btn.label:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
            while size > 8 and btn.label:GetStringWidth() > cell - 6 do
                size = size - 1
                btn.label:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
            end
        end
        for i, btn in ipairs(btns) do
            local cell = Edge(i + 1) - Edge(i)
            btn:SetSize(cell, bh)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", holder, "LEFT", Edge(i), 0)
            btn.label:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
            if seps[i] then
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

    for i, info in ipairs(buttons) do
        local btn = CreateFrame("Button", nil, holder)
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        label:SetText(info.text)
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.label = label
        label:SetTextColor(1, 1, 1, 1)
        local hl = btn:CreateTexture(nil, "BACKGROUND")
        hl:SetPoint("TOPLEFT", 1, 0)
        hl:SetPoint("BOTTOMRIGHT", -1, 0)
        hl:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.22)
        hl:Hide()
        btn:SetScript("OnEnter", function() label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1); hl:Show() end)
        btn:SetScript("OnLeave", function() label:SetTextColor(1, 1, 1, 1); hl:Hide() end)
        btn:SetScript("OnClick", info.func)
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
    Relayout()
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

    local move = W.Button(page, 240, 22, "Move micro menu panel (layout mode)")
    move:SetPoint("TOPLEFT", 4, -96)
    move:SetScript("OnClick", function() CUI:ToggleLayout() end)
end)