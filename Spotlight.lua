--------------------------------------------------------------------------------
-- Cys's UI - New features spotlight
--
-- So new things are easy to find after an update:
--   * a "New" page at the top of the settings: one card per new feature, what it does, where its settings
--     are, and a button that takes you there (or turns the module on);
--   * a small NEW tag beside those pages in the settings sidebar until you open them;
--   * a one-time pop-up after the update (after the What's New window, if that is showing).
-- Each release: replace SPOTLIGHT below with that version's new features. Bug-fix releases can leave it alone
-- (the pop-up only shows once per spotlight version).
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local SPOTLIGHT = {
    version = "0.58.16",
    items = {
        { title = "Gold and currencies on all your characters", page = "Characters", module = "characters",
          icon = "Interface\\Icons\\INV_Misc_Coin_02",
          text = "The Your Characters window now has Gold and Currencies tabs: the gold on every character with the total, and the currencies each character holds.",
          where = "Click the Your Characters minimap button or type /cuichars gold." },
        { title = "Spot other Cys's UI users", page = "Cys's UI Users", module = "hello",
          icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
          text = "Players in your group or guild who also run Cys's UI get a Cys's UI line on their tooltip, with their version. Only the version is shared.",
          where = "Interface > Cys's UI Users. /cuiusers lists who has been seen." },
    },
}

local function SeenDB()
    CysUIDB.spotlight = CysUIDB.spotlight or {}
    local s = CysUIDB.spotlight
    if s.version ~= SPOTLIGHT.version then
        s.version, s.pages, s.popup = SPOTLIGHT.version, {}, false
    end
    s.pages = s.pages or {}
    return s
end

local newPages = { New = true }
for _, it in ipairs(SPOTLIGHT.items) do if it.page then newPages[it.page] = true end end

-- for the settings sidebar (Config.lua)
function CUI:IsNewPage(title) return newPages[title] and not SeenDB().pages[title] end
function CUI:MarkPageSeen(title) if newPages[title] then SeenDB().pages[title] = true end end

--------------------------------------------------------------------------------
-- The "New" page
--------------------------------------------------------------------------------
CUI:RegisterPage("New", function(page)
    local width = 480
    W.Header(page, "New in Cys's UI " .. SPOTLIGHT.version, width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 11, T.desc)
    intro:SetPoint("TOPLEFT", 4, -32)
    intro:SetWidth(width - 8)
    intro:SetText("What this update adds and where to find it. Everything has its own switch; the full list of changes is under General > View changelog.")
    local y = -32 - intro:GetStringHeight() - 14

    for _, it in ipairs(SPOTLIGHT.items) do
        local card = CreateFrame("Frame", nil, page)
        card:SetPoint("TOPLEFT", 0, y)
        card:SetWidth(width)
        W.Texture(card, "BACKGROUND", T.card):SetAllPoints()
        W.Border(card, 1, T.line, "BORDER")
        local stripe = W.Texture(card, "ARTWORK", T.border)
        stripe:SetPoint("TOPLEFT", 1, -1); stripe:SetPoint("BOTTOMLEFT", 1, 1); stripe:SetWidth(2)

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT", 12, -10)
        icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if (it.icon or ""):find("Icons\\") then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

        local title = W.Text(card, 13, T.accent)
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
        title:SetText(it.title)
        local text = W.Text(card, 11, T.desc)
        text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        text:SetWidth(width - 70)
        text:SetSpacing(2)
        text:SetText(it.text)
        local where = W.Text(card, 10, T.dim)
        where:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -5)
        where:SetWidth(width - 70)
        where:SetText(it.where or "")

        local btn = W.Button(card, 130, 22, "Open settings", true)
        local function Paint()
            if it.module and not CUI:IsModuleEnabled(it.module) then
                btn:SetLabel(btn.turned and "On after /reload" or "Turn it on")
            else
                btn:SetLabel("Open settings")
            end
        end
        btn:SetScript("OnClick", function()
            if it.module and not CUI:IsModuleEnabled(it.module) then
                CUI:SetModuleEnabled(it.module, true)
                btn.turned = true
                Paint()
            elseif it.page then
                CUI:OpenConfig(it.page)
            end
        end)
        Paint()

        local h = 10 + 18 + text:GetStringHeight() + 5 + where:GetStringHeight() + 8 + 22 + 10
        card:SetHeight(math.max(h, 70))
        btn:SetPoint("BOTTOMRIGHT", -10, 10)
        y = y - card:GetHeight() - 10
    end
    page.contentHeight = -y + 20
end)

--------------------------------------------------------------------------------
-- One-time pop-up after an update
--------------------------------------------------------------------------------
local popup
local function ShowPopup()
    local s = SeenDB()
    if s.popup or InCombatLockdown() then return end
    s.popup = true
    if not popup then
        local f = CreateFrame("Frame", "CysUINewFeaturesFrame", UIParent)
        popup = f
        f:SetSize(340, 80)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        W.Texture(f, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.97 }):SetAllPoints()
        W.Border(f, 1, T.border, "BORDER")
        local title = W.Text(f, 14, T.accent)
        title:SetPoint("TOP", 0, -14)
        title:SetText("New in Cys's UI " .. SPOTLIGHT.version)
        local y = -42
        for _, it in ipairs(SPOTLIGHT.items) do
            if it.module then -- the headline features
                local icon = f:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                icon:SetPoint("TOPLEFT", 24, y)
                icon:SetTexture(it.icon)
                if (it.icon or ""):find("Icons\\") then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                local t = W.Text(f, 12, T.text)
                t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                t:SetText(it.title)
                y = y - 26
            end
        end
        local more = W.Text(f, 10, T.dim, "CENTER")
        more:SetPoint("TOP", 0, y - 4)
        more:SetText("and more: see the New page in /cui")
        y = y - 24
        local show = W.Button(f, 120, 24, "Show me", true)
        show:SetPoint("TOPRIGHT", f, "TOP", -6, y - 6)
        show:SetScript("OnClick", function() f:Hide(); CUI:OpenConfig("New") end)
        local close = W.Button(f, 120, 24, "Close")
        close:SetPoint("TOPLEFT", f, "TOP", 6, y - 6)
        close:SetScript("OnClick", function() f:Hide() end)
        f:SetHeight(-y + 44)
        tinsert(UISpecialFrames, "CysUINewFeaturesFrame")
    end
    popup:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(4, function()
        if SeenDB().popup then return end
        -- wait for the What's New window to be closed, if it is up
        local cl = _G.CysChangelogFrame
        if cl and cl:IsShown() then
            local hooked = false
            cl:HookScript("OnHide", function()
                if hooked then return end
                hooked = true
                C_Timer.After(0.3, ShowPopup)
            end)
        else
            ShowPopup()
        end
    end)
end)
