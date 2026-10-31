--------------------------------------------------------------------------------
-- Cys's UI - welcome window
--
-- Shown once, the first time Cys's UI loads on an account (and again on /cui welcome). Steps people
-- actually need, then a pointer to the settings: 1) action bars and Blizzard's XP bar, 2) screen size and UI scale, 3) border color.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local WELCOME_VERSION = 1   -- raise it to show the window again to everyone

local win

local function Build()
    local f = CreateFrame("Frame", "CysUIWelcomeFrame", UIParent)
    f:SetSize(460, 330)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.Texture(f, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(f, 1, T.border, "BORDER")

    local title = W.Text(f, 16, T.accent)
    title:SetPoint("TOPLEFT", 16, -14)
    f.title = title
    local count = W.Text(f, 11, T.dim, "RIGHT")
    count:SetPoint("TOPRIGHT", -16, -18)
    f.count = count
    local line = W.Texture(f, "BORDER", T.border)
    line:SetPoint("TOPLEFT", 12, -40); line:SetPoint("TOPRIGHT", -12, -40); line:SetHeight(1)

    -- three pages, each a plain frame
    local pages = {}
    local function NewPage()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 16, -52)
        p:SetPoint("BOTTOMRIGHT", -16, 52)
        p:Hide()
        pages[#pages + 1] = p
        return p
    end

    ---------------------------------------------------------------- 1: bars
    local p1 = NewPage()
    local t1 = W.Text(p1, 12, T.desc)
    t1:SetPoint("TOPLEFT", 0, 0)
    t1:SetWidth(420); t1:SetJustifyV("TOP"); t1:SetSpacing(3)
    t1:SetText("Cys's UI replaces the default look with flat gold-and-dark frames. Two things to check first:")
    local h1 = W.Header(p1, "Action bars", 420)
    h1:SetPoint("TOPLEFT", 0, -44)
    local t1b = W.Text(p1, 11, T.desc)
    t1b:SetPoint("TOPLEFT", 4, -72)
    t1b:SetWidth(416); t1b:SetJustifyV("TOP"); t1b:SetSpacing(3)
    t1b:SetText("Cys's UI can show up to eight bars. This button shows only the bars your game already has switched on (Esc > Options > Action Bars) and hides the rest. You can turn any bar back on later under Action Bars in the settings.")
    local match = W.Button(p1, 300, 24, "Match the game's bars (turns off the rest)")
    match:SetPoint("TOPLEFT", 4, -126)
    match:SetScript("OnClick", function()
        if CUI.ActionBars and CUI.ActionBars.MatchGameBars then CUI.ActionBars:MatchGameBars() end
    end)
    local h2 = W.Header(p1, "Experience bar", 420)
    h2:SetPoint("TOPLEFT", 0, -166)
    local hide = W.Checkbox(p1, "Hide Blizzard's experience and reputation bars (Cys's XP bar replaces them)",
        function()
            local ab = CysUIDB.actionbars
            return not ab or ab.hideStatusBars ~= false
        end,
        function(on)
            CysUIDB.actionbars = CysUIDB.actionbars or {}
            CysUIDB.actionbars.hideStatusBars = on
            if on and CUI.ActionBars and CUI.ActionBars.HideStatusBars then CUI.ActionBars:HideStatusBars() end
        end)
    hide:SetPoint("TOPLEFT", 4, -196)
    local t1c = W.Text(p1, 10, T.dim)
    t1c:SetPoint("TOPLEFT", 4, -220)
    t1c:SetWidth(416); t1c:SetJustifyV("TOP")
    t1c:SetText("Turning this off needs a /reload. Cys's XP bar has its own page in the settings.")

    ---------------------------------------------------------------- 2: your screen
    local ps = NewPage()
    local ts = W.Text(ps, 12, T.desc)
    ts:SetPoint("TOPLEFT", 0, 0)
    ts:SetWidth(420); ts:SetJustifyV("TOP"); ts:SetSpacing(3)
    local tsb = W.Text(ps, 11, T.desc)
    tsb:SetPoint("TOPLEFT", 4, -118)
    tsb:SetWidth(416); tsb:SetJustifyV("TOP"); tsb:SetSpacing(3)
    local scaleBtns = {}
    local function ScaleMode(mode)
        local db = CysUIDB.scale
        if not db then return end
        db.mode = mode
        db.prompted = true
        if StaticPopup_Hide then StaticPopup_Hide("CYSUI_SCALE") end
        if CUI.Scale then CUI.Scale:Apply() end
        f.refreshScreen()
    end
    scaleBtns.pixel = W.Button(ps, 200, 24, "Pixel perfect")
    scaleBtns.pixel:SetPoint("TOPLEFT", 4, -78)
    scaleBtns.pixel:SetScript("OnClick", function() ScaleMode("pixel") end)
    scaleBtns.layout = W.Button(ps, 200, 24, "Match the 1080p layout")
    scaleBtns.layout:SetPoint("LEFT", scaleBtns.pixel, "RIGHT", 8, 0)
    scaleBtns.layout:SetScript("OnClick", function() ScaleMode("layout") end)
    f.refreshScreen = function()
        local S = CUI.Scale
        if not S or not CysUIDB.scale then ts:SetText("The UI Scale module is switched off, so the game keeps its own scale."); return end
        local w, h = S:ScreenSize()
        local aspect = w / h
        local wide = aspect >= 2.2
        local kind = wide and (aspect >= 3 and "super ultrawide" or "ultrawide") or "standard widescreen"
        local rec = (h > 1080) and "layout" or "pixel"
        ts:SetText(string.format("Your screen is |cFFFFD100%d x %d|r (%s). Cys's UI is designed around a 1920 x 1080 screen, so the right scale depends on yours.", w, h, kind))
        local msg
        if rec == "pixel" then
            msg = "Recommended for you: |cFFFFD100Pixel perfect|r. One UI unit is one real pixel, which keeps every line sharp (this is what ElvUI does)."
        else
            msg = "Recommended for you: |cFFFFD100Match the 1080p layout|r. Frames keep the size and positions they have on a 1080p screen, just sharper. Pixel perfect is also fine, but everything gets physically smaller on a screen this big."
        end
        if wide then
            msg = msg .. "\n\nYour screen is very wide, so frames pinned to the edges sit far apart. Use |cFFFFD100/cui layout|r to pull the bars and frames in toward the middle."
        end
        tsb:SetText(msg)
        local mode = CysUIDB.scale.mode
        for key, b in pairs(scaleBtns) do b:SetPrimary(mode == key) end
    end

    ---------------------------------------------------------------- 3: border color
    local p2 = NewPage()
    local t2 = W.Text(p2, 12, T.desc)
    t2:SetPoint("TOPLEFT", 0, 0)
    t2:SetWidth(420); t2:SetJustifyV("TOP"); t2:SetSpacing(3)
    t2:SetText("Pick a border color. It changes right now, on this window and on every Cys's UI frame and skinned Blizzard window.")
    local swatches = {}
    local function Refresh()
        local cur = CysUIDB.borderColor or "gold"
        for key, b in pairs(swatches) do W.SetBorder(b.edges, key == cur and T.accent or T.line) end
    end
    local styles = W.AvailableBorderStyles()
    for i, st in ipairs(styles) do
        local b = CreateFrame("Button", nil, p2)
        b:SetSize(100, 28)
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        b:SetPoint("TOPLEFT", 4 + col * 106, -60 - row * 36)
        W.Texture(b, "BACKGROUND", T.button):SetAllPoints()
        b.edges = W.Border(b, 1, T.line, "BORDER")
        local sw = W.Texture(b, "ARTWORK", W.BorderStyleColor(st.key))
        sw:SetSize(14, 14)
        sw:SetPoint("LEFT", 7, 0)
        local label = W.Text(b, 11, T.text)
        label:SetPoint("LEFT", 26, 0)
        label:SetText(st.label)
        b:SetScript("OnClick", function()
            CysUIDB.borderColor = st.key
            W.ApplyBorderStyle()
            Refresh()
        end)
        b:SetScript("OnEnter", function() W.SetBorder(b.edges, T.accent) end)
        b:SetScript("OnLeave", Refresh)
        swatches[st.key] = b
    end
    Refresh()
    f.refreshSwatches = Refresh
    local t2b = W.Text(p2, 11, T.desc)
    t2b:SetPoint("TOPLEFT", 4, -60 - (math.floor((#styles - 1) / 4) + 1) * 36 - 12)
    t2b:SetWidth(416); t2b:SetJustifyV("TOP"); t2b:SetSpacing(3)
    t2b:SetText("You can change it any time under Skins in the settings. If a window keeps its old color, type /reload.")

    ---------------------------------------------------------------- 4: explore
    local p3 = NewPage()
    local t3 = W.Text(p3, 12, T.desc)
    t3:SetPoint("TOPLEFT", 0, 0)
    t3:SetWidth(420); t3:SetJustifyV("TOP"); t3:SetSpacing(4)
    t3:SetText("That is all you need to get going. I encourage you to explore the Cys's UI settings with |cFFFFD100/cui|r: every part of the UI can be switched on or off, and almost everything has its own options.\n\n"
        .. "|cFFFFD100/cui layout|r moves and resizes any frame.\n"
        .. "The Class section has tools for your class, like Level-Up Spells and the Heal Advisor.\n"
        .. "The Upgrade page scores gear with stat weights; SixtyUpgrades has ready-made weights you can paste into its Import / Export box.\n"
        .. "/cui welcome shows this window again.")
    local open = W.Button(p3, 180, 26, "Open the settings", true)
    open:SetPoint("BOTTOMLEFT", 4, 4)
    open:SetScript("OnClick", function() f:Hide(); CUI:OpenConfig("General") end)

    ---------------------------------------------------------------- navigation
    local titles = { "Welcome to Cys's UI", "Your screen", "Border color", "Make it yours" }
    local idx = 1
    local back = W.Button(f, 80, 24, "Back")
    back:SetPoint("BOTTOMLEFT", 16, 14)
    local nextb = W.Button(f, 90, 24, "Next", true)
    nextb:SetPoint("BOTTOMRIGHT", -16, 14)
    local skip = W.Button(f, 90, 24, "Skip")
    skip:SetPoint("RIGHT", nextb, "LEFT", -8, 0)

    local function Show(i)
        idx = math.max(1, math.min(#pages, i))
        for n, p in ipairs(pages) do p:SetShown(n == idx) end
        f.title:SetText(titles[idx])
        f.count:SetText(idx .. " / " .. #pages)
        back:SetShown(idx > 1)
        local last = idx == #pages
        nextb.label:SetText(last and "Finish" or "Next")
        skip:SetShown(not last)
    end
    f.Show1 = function() Show(1) end
    back:SetScript("OnClick", function() Show(idx - 1) end)
    nextb:SetScript("OnClick", function()
        if idx == #pages then f:Hide() else Show(idx + 1) end
    end)
    skip:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() Show(1); f.refreshSwatches(); f.refreshScreen() end)
    tinsert(UISpecialFrames, "CysUIWelcomeFrame")
    return f
end

function CUI:ShowWelcome()
    if InCombatLockdown() then self:Print("Try /cui welcome again once combat ends."); return end
    win = win or Build()
    win:Show()
    win:Raise()
end

-- first run: show it once, a moment after the world loads
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not CysUIDB or (CysUIDB.welcomeSeen or 0) >= WELCOME_VERSION then return end
    C_Timer.After(3, function()
        if InCombatLockdown() then return end
        CysUIDB.welcomeSeen = WELCOME_VERSION
        CUI:ShowWelcome()
    end)
end)
