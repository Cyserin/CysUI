--------------------------------------------------------------------------------
-- Cys's UI - Chat
--
-- Restyles Blizzard's own chat windows (it doesn't replace them, so everything the game
-- does with chat keeps working) and adds a few things people expect from a UI:
--
--   * flat dark windows with a gold edge, a matching edit box, plain tabs
--   * optional: hide the little scroll / menu buttons
--   * class-colored names, timestamps, chat font size
--   * a Copy button on each window: opens the recent lines in a box you can select
--   * chat window 1 is movable and resizable with layout mode (/cui layout)
--
-- Every step is wrapped so that if the game changes a frame this touches, the rest still
-- works. If chat ever misbehaves, untick Chat under /cui > Modules and /reload.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local format, floor, max, min = string.format, math.floor, math.max, math.min

local Chat = {}
CUI.Chat = Chat

local NUM_WINDOWS = NUM_CHAT_WINDOWS or 10
local COPY_LINES = 250 -- how many recent lines the Copy window keeps per chat window

local function DB() return CysUIDB.chat end

local hidden = CreateFrame("Frame")
hidden:Hide()

-- Park a Blizzard texture / frame somewhere it can never be shown again.
local function Kill(obj)
    if not obj then return end
    if obj.UnregisterAllEvents then pcall(obj.UnregisterAllEvents, obj) end
    if obj.SetParent then obj:SetParent(hidden) end
    if obj.Hide then obj:Hide() end
end

local function Guarded(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        Chat.problems = (Chat.problems or 0) + 1
        if Chat.problems <= 3 then CUI:Print("|cFFFF9F43Chat: " .. label .. " skipped (" .. tostring(err) .. ")|r") end
    end
end

--------------------------------------------------------------------------------
-- Copy window
--------------------------------------------------------------------------------
local buffers = {}
local copyFrame

local function Clean(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|K.-|k", "")
    return text
end

local function BuildCopyFrame()
    local f = CreateFrame("Frame", "CysUIChatCopyFrame", UIParent)
    f:SetSize(580, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
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

    local title = W.Text(f, 13, T.accent)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Copy chat")
    local hint = W.Text(f, 11, T.desc)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText("Click in the box, Ctrl+A to select all, Ctrl+C to copy.")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.text = W.Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local div = W.Texture(f, "BORDER", T.line)
    div:SetPoint("TOPLEFT", 14, -36)
    div:SetPoint("TOPRIGHT", -14, -36)
    div:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 16, -46)
    scroll:SetPoint("BOTTOMRIGHT", -26, 14)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        s:SetVerticalScroll(max(0, min(s:GetVerticalScroll() - delta * 40, s:GetVerticalScrollRange())))
    end)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(STANDARD_TEXT_FONT, 12, "")
    edit:SetTextColor(T.text[1], T.text[2], T.text[3])
    edit:SetWidth(530)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)

    f.edit, f.scroll = edit, scroll
    tinsert(UISpecialFrames, "CysUIChatCopyFrame")
    return f
end

function Chat:ShowCopy(i)
    copyFrame = copyFrame or BuildCopyFrame()
    local lines, estimate = {}, 0
    for _, line in ipairs(buffers[i or 1] or {}) do
        local clean = Clean(line)
        lines[#lines + 1] = clean
        estimate = estimate + max(1, math.ceil(#clean / 70)) -- room for wrapped lines
    end
    if #lines == 0 then lines[1] = "(nothing to copy yet)" end
    copyFrame.edit:SetHeight(max(estimate * 15 + 20, 300))
    copyFrame.edit:SetText(table.concat(lines, "\n"))
    copyFrame:Show()
    copyFrame.scroll:SetVerticalScroll(copyFrame.scroll:GetVerticalScrollRange())
end

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------
local FRAME_PARTS = { "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
                      "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }
local EDIT_PARTS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local TAB_PARTS = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
                    "HighlightLeft", "HighlightMiddle", "HighlightRight", "Glow" }

local function Panel(parent, anchorTo, grow, fill, alpha)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -grow, grow)
    p:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", grow, -grow)
    p:SetFrameLevel(max(parent:GetFrameLevel() - 1, 0))
    W.Texture(p, "BACKGROUND", { fill[1], fill[2], fill[3], alpha }):SetAllPoints()
    p.edges = W.Border(p, 1, T.border, "BORDER")
    return p
end

local tabLift = 15 -- how far the tab row floats above the window (more while the combat log's button bar is up)
local liftTargets = {}
local function ReliftTabs()
    for _, t in ipairs(liftTargets) do
        local p, rel, relPoint, x, y = t.f:GetPoint(1)
        if p then t.raise(t.f, p, rel, relPoint, x, y) end
    end
end

-- Short channel names: [1. General - Westfall] -> [Gen], [2. Trade - City] -> [T], [Guild] -> [G] ...
-- Other channels keep their name without the number and zone. Unknown/locked text is left alone.
local SHORT = {
    general = "Gen", trade = "T", localdefense = "LD", worlddefense = "WD", lookingforgroup = "LFG",
    guildrecruitment = "GR", guild = "G", officer = "O", party = "P", partyleader = "PL", raid = "R",
    raidleader = "RL", raidwarning = "RW", instance = "I", instanceleader = "IL",
    battleground = "BG", battlegroundleader = "BGL",
}
local function ShortChannels(text)
    return (text:gsub("(|Hchannel:[^|]*|h)%[([^%]]*)%](|h)", function(open, label, close)
        local name = label:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
        local short = SHORT[(name:lower():gsub("%s", ""))] or name
        return open .. "[" .. short .. "]" .. close
    end))
end

local function SkinWindow(i)
    local cf = _G["ChatFrame" .. i]
    if not cf or cf.cysSkinned then return end
    cf.cysSkinned = true
    local db = DB()

    -- short channel names (switch: Chat page). Chat windows are not protected, so wrapping their AddMessage is
    -- safe (it is how chat addons rename channels); locked Forever lines pass through untouched.
    local origAdd = cf.AddMessage
    cf.AddMessage = function(self, text, ...)
        if DB().shortChannels and not CysUICompat.Secret(text) and type(text) == "string" then
            local ok, s = pcall(ShortChannels, text)
            if ok and s then text = s end
        end
        return origAdd(self, text, ...)
    end

    -- capture lines for the Copy window (works even if the skin is off)
    buffers[i] = {}
    hooksecurefunc(cf, "AddMessage", function(_, text)
        local buf = buffers[i]
        -- WoW Forever: chat in instances reaches addons locked; it still shows in chat, just not in the Copy window
        if CysUICompat.Secret(text) then text = "(a line the game keeps from addons)" end
        buf[#buf + 1] = tostring(text)
        if #buf > COPY_LINES then table.remove(buf, 1) end
    end)

    if not db.skin then return end

    -- window: remove Blizzard's background art, draw ours
    if FCF_SetWindowAlpha then Guarded("window alpha", FCF_SetWindowAlpha, cf, 0) end
    for _, part in ipairs(FRAME_PARTS) do Kill(_G["ChatFrame" .. i .. part]) end
    cf.cysPanel = Panel(cf, cf, 5, T.bg, 0.82)

    -- edit box
    local eb = _G["ChatFrame" .. i .. "EditBox"]
    if eb then
        for _, part in ipairs(EDIT_PARTS) do Kill(_G["ChatFrame" .. i .. "EditBox" .. part]) end
        eb.cysPanel = Panel(eb, eb, 2, T.field, 0.95)
        -- only while typing (on WoW Forever the input box stays on screen faded, which left a faint box)
        local function ShowPanel() if eb.cysPanel then eb.cysPanel:SetShown(eb:HasFocus() and true or false) end end
        eb:HookScript("OnEditFocusGained", ShowPanel)
        eb:HookScript("OnEditFocusLost", ShowPanel)
        ShowPanel()
        if eb.SetAltArrowKeyMode then pcall(eb.SetAltArrowKeyMode, eb, false) end -- arrow keys walk chat history
    end

    -- tab
    local tab = _G["ChatFrame" .. i .. "Tab"]
    if tab then
        for _, part in ipairs(TAB_PARTS) do Kill(_G["ChatFrame" .. i .. "Tab" .. part]) end
        if db.tabsSolid ~= false and not tab.cysSolid then
            tab.cysSolid = true
            -- tabs stay fully visible (the game fades them out when the mouse leaves)...
            local fixing = false
            hooksecurefunc(tab, "SetAlpha", function(self, a)
                if fixing or a == 1 or DB().tabsSolid == false then return end
                fixing = true
                self:SetAlpha(1)
                fixing = false
            end)
            tab:SetAlpha(1)
            -- ...and sit above the window's border instead of on top of it
            local placing = false
            local function Raise(self, point, rel, relPoint, x, y)
                if placing or DB().tabsSolid == false then return end
                if rel == cf and type(point) == "string" and point:find("^BOTTOM") and type(relPoint) == "string"
                    and relPoint:find("^TOP") and y ~= tabLift then
                    placing = true
                    -- re-set every point the frame has, with the lifted offset on the ones that hug the window
                    local pts = {}
                    for n = 1, self:GetNumPoints() do pts[n] = { self:GetPoint(n) } end
                    self:ClearAllPoints()
                    for _, q in ipairs(pts) do
                        local qy = q[5]
                        if q[2] == cf and type(q[1]) == "string" and q[1]:find("^BOTTOM") and type(q[3]) == "string" and q[3]:find("^TOP") then qy = tabLift end
                        self:SetPoint(q[1], q[2], q[3], q[4] or 0, qy or 0)
                    end
                    placing = false
                end
            end
            -- the tab may hang off the window directly or off the chat dock that sits on the window
            local targets = { tab }
            local dock = cf == ChatFrame1 and _G.GeneralDockManager
            if dock then targets[#targets + 1] = dock end
            for _, f in ipairs(targets) do
                if not f.cysRaise then
                    f.cysRaise = true
                    hooksecurefunc(f, "SetPoint", Raise)
                    liftTargets[#liftTargets + 1] = { f = f, raise = Raise }
                end
                local p, rel, relPoint, x, y = f:GetPoint(1)
                if p then Raise(f, p, rel, relPoint, x, y) end
            end
        end
    end

    -- the scroll / menu buttons
    if db.hideButtons then
        local bf = _G["ChatFrame" .. i .. "ButtonFrame"] or cf.buttonFrame
        if bf then
            bf:Hide()
            bf:HookScript("OnShow", function(self) self:Hide() end)
        end
    end

    -- Copy button (top-right corner, faint until you hover it)
    local copy = CreateFrame("Button", nil, cf)
    copy:SetSize(34, 14)
    copy:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 2, 2)
    copy:SetFrameLevel(cf:GetFrameLevel() + 5)
    copy:SetAlpha(0.35)
    copy.bg = W.Texture(copy, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.9 })
    copy.bg:SetAllPoints()
    copy.edges = W.Border(copy, 1, T.line, "BORDER")
    copy.label = W.Text(copy, 10, T.accent, "CENTER")
    copy.label:SetPoint("CENTER", 0, 0)
    copy.label:SetText("Copy")
    copy:SetScript("OnEnter", function(s) s:SetAlpha(1); W.SetBorder(s.edges, T.glow) end)
    copy:SetScript("OnLeave", function(s) s:SetAlpha(0.35); W.SetBorder(s.edges, T.line) end)
    copy:SetScript("OnClick", function() Chat:ShowCopy(i) end)
end

--------------------------------------------------------------------------------
-- Settings that apply live
--------------------------------------------------------------------------------
local COLOR_GROUPS = { "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT", "WHISPER",
                       "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND",
                       "BATTLEGROUND_LEADER" }

function Chat:ApplyColors(on)
    if not ToggleChatColorNamesByClassGroup then return end
    for _, group in ipairs(COLOR_GROUPS) do pcall(ToggleChatColorNamesByClassGroup, on, group) end
    for i = 1, 10 do pcall(ToggleChatColorNamesByClassGroup, on, "CHANNEL" .. i) end
end

function Chat:ApplyTimestamps()
    local db = DB()
    local fmt = db.timestamps and (db.use24h and "%H:%M " or "%I:%M %p ") or "none"
    pcall(SetCVar, "showTimestamps", fmt)
    CHAT_TIMESTAMP_FORMAT = (fmt ~= "none") and fmt or nil
end

function Chat:ApplyFontSize()
    if not FCF_SetChatWindowFontSize then return end
    for i = 1, NUM_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(FCF_SetChatWindowFontSize, nil, cf, DB().fontSize) end
    end
end

--------------------------------------------------------------------------------
-- Layout mode: chat window 1 follows a mover
--------------------------------------------------------------------------------
-- Blizzard keeps every chat window 35px in from the left edge and 50px up from the bottom (room for the edit box)
-- by padding its clamp rectangle. That is why the window could not reach the screen's edge. Remove the padding,
-- and keep it removed when the game puts it back.
local function Unclamp(cf)
    if not cf or cf.cysUnclamped then return end
    cf.cysUnclamped = true
    pcall(cf.SetClampRectInsets, cf, 0, 0, 0, 0)
    pcall(hooksecurefunc, cf, "SetClampRectInsets", function(self, l, r, t, b)
        if l ~= 0 or r ~= 0 or t ~= 0 or b ~= 0 then pcall(self.SetClampRectInsets, self, 0, 0, 0, 0) end
    end)
end

-- the edit box sits under its window; when the window is at the bottom of the screen it goes on top instead
local function PlaceEditBox(cf, eb)
    if not (cf and eb) then return end
    local bottom = cf:GetBottom()
    local scale = cf:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local above = bottom and (bottom * scale < (eb:GetHeight() + 10))
    eb:ClearAllPoints()
    if above then
        -- above the tab row, not on it: the box takes clicks even while it is faded, so sitting on the tabs
        -- made them unclickable
        local lift = tabLift + 30
        pcall(function()
            local tab = _G[cf:GetName() .. "Tab"]
            local tt, ct = tab:GetTop(), cf:GetTop()
            local ts, cs = tab:GetEffectiveScale(), cf:GetEffectiveScale()
            if tt and ct and ts and cs and cs > 0 then lift = math.max(6, tt * ts / cs - ct + 4) end
        end)
        eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, lift)
        eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, lift)
    else
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -6)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -6)
    end
end

-- a thin gold line under the name of the tab that is showing
local function UpdateTabLines()
    if DB().tabsSolid == false then return end
    local selected = _G.SELECTED_CHAT_FRAME
    if _G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK then
        local ok, w = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and w then selected = w end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local tab, cf = _G["ChatFrame" .. i .. "Tab"], _G["ChatFrame" .. i]
        if tab and cf then
            if not tab.cysFlat then
                -- Cys tabs: Blizzard's tab art faded out, a flat dark plate behind the name instead
                tab.cysFlat = true
                for _, r in ipairs({ tab:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= tab.glow and r ~= tab.cysLine then r:SetAlpha(0) end
                end
                local plate = tab:CreateTexture(nil, "BACKGROUND", nil, -8)
                plate:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.82)
                plate:SetPoint("TOPLEFT", 2, -4)
                plate:SetPoint("BOTTOMRIGHT", -2, 0)
                local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
                if hl then hl:SetAlpha(0) end
            end
            if not tab.cysLine then
                local line = tab:CreateTexture(nil, "OVERLAY")
                line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
                W.TrackEdge(line)
                line:SetHeight(1)
                local text = _G["ChatFrame" .. i .. "TabText"] or tab.Text
                if text then
                    line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -1)
                    line:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 2, -1)
                else
                    line:SetPoint("BOTTOMLEFT", 4, 2)
                    line:SetPoint("BOTTOMRIGHT", -4, 2)
                end
                tab.cysLine = line
            end
            tab.cysLine:SetShown(cf == selected and tab:IsShown())
        end
    end
    -- lift the tab row clear of the combat log's button bar while the Log tab is showing
    local bar = _G.CombatLogQuickButtonFrame_Custom
    local lift = 15
    if bar and bar:IsShown() and selected == _G.ChatFrame2 then lift = 15 + math.floor((bar:GetHeight() or 24) + 2) end
    if lift ~= tabLift then
        tabLift = lift
        ReliftTabs()
    end
end
-- The combat log's "My actions / What happened to me?" bar belongs above the window, under the tab names
local function PlaceLogBar()
    local bar, cf = _G.CombatLogQuickButtonFrame_Custom, _G.ChatFrame2
    if not (bar and cf) or DB().tabsSolid == false then return end
    if not bar.cysPlaced then
        bar.cysPlaced = true
        local busy = false
        hooksecurefunc(bar, "SetPoint", function(self, _, rel)
            if busy or rel == cf then return end
            busy = true
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 6)
            self:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, 6)
            busy = false
        end)
        bar:HookScript("OnShow", function() C_Timer.After(0, function() UpdateTabLines(); ReliftTabs() end) end)
        bar:HookScript("OnHide", function() C_Timer.After(0, function() UpdateTabLines(); ReliftTabs() end) end)
    end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 6)
    bar:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, 6)
    bar:SetFrameLevel(cf:GetFrameLevel() + 3)
end

local function SetupTabLines()
    UpdateTabLines()
    for _, fn in ipairs({ "FCF_Tab_OnClick", "FCF_SelectDockFrame", "FCFDock_SelectWindow", "FCF_DockUpdate", "FCF_OpenNewWindow", "FCF_Close" }) do
        if _G[fn] then hooksecurefunc(fn, function() C_Timer.After(0, UpdateTabLines) end) end
    end
    C_Timer.After(1, function() PlaceLogBar(); UpdateTabLines() end)
    C_Timer.After(3, function() PlaceLogBar(); UpdateTabLines() end)
end

local function SetupMover()
    SetupTabLines()
    local cf = ChatFrame1
    if not (cf and CUI.RegisterMovable) then return end
    Unclamp(cf)
    local eb = _G.ChatFrame1EditBox
    if eb then
        eb:HookScript("OnShow", function(self) PlaceEditBox(cf, self) end)
        eb:HookScript("OnEditFocusGained", function(self) PlaceEditBox(cf, self) end)
        C_Timer.After(2, function() PlaceEditBox(cf, eb) end) -- once the tabs have settled into place
        PlaceEditBox(cf, eb)
    end
    if cf.SetUserPlaced then pcall(cf.SetUserPlaced, cf, true) end
    if FCF_SetLocked then pcall(FCF_SetLocked, cf, true) end -- no dragging by the tab; use layout mode
    local m = CUI:RegisterMovable(cf, "chat", "Chat", {
        point = "BOTTOMLEFT", x = 30, y = 110,
        resizable = true, minW = 240, maxW = 900, minH = 90, maxH = 600,
    })
    -- Blizzard re-anchors chat on some events; put it back on our mover
    local busy = false
    hooksecurefunc(cf, "SetPoint", function(self, _, relativeTo)
        if busy or relativeTo == m.mover then return end
        busy = true
        self:ClearAllPoints()
        self:SetPoint("CENTER", m.mover, "CENTER", 0, 0)
        busy = false
    end)
    -- the game may restore its own saved layout a moment after login
    C_Timer.After(1, function() CUI:ApplyLayout("chat") end)
    -- Battle.net pop-ups (friend online / offline) sit on Blizzard's alert holder, which hangs off the chat side
    -- buttons left of the chat; with the chat near the screen edge they went partly off screen. Hang the holder
    -- above our chat tabs instead (it is only placed once by Blizzard, at load).
    local alerts = _G.ChatAlertFrame
    if alerts then
        Guarded("toast spot", function()
            alerts:ClearAllPoints()
            alerts:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 34)
        end)
    end
end

--------------------------------------------------------------------------------
-- Battle.net pop-ups (friend online / offline, invites) in the Cys look: a dark flat plate, the theme edge
-- with a gold stripe on the left, and the friend's name in gold. Art only: Blizzard's backdrop pieces are
-- faded, nothing of theirs is moved, replaced or re-scripted (OnShow is only hooked).
--------------------------------------------------------------------------------
local TOAST_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                       "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local toastDone = setmetatable({}, { __mode = "k" })

local function FadeToastArt(toast)
    for _, key in ipairs(TOAST_PIECES) do
        local t = toast[key]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
end

-- the name line: drop Blizzard's blue color code and show it in gold (the text is set before the pop-up shows)
local function GoldName(toast)
    local line = toast.TopLine
    if not (line and line:IsShown()) then return end
    local txt = line:GetText()
    if type(txt) ~= "string" or txt == "" then return end
    local plain = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if plain ~= txt then line:SetText(plain) end
    line:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
end

local function SkinToast(toast)
    if not toast or toastDone[toast] then return end
    toastDone[toast] = true
    FadeToastArt(toast)
    W.Texture(toast, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.94 }, -8):SetAllPoints()
    W.Border(toast, 1, T.border, "ARTWORK", 7)
    local stripe = W.Texture(toast, "ARTWORK", T.border, 7)
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(2)
    if toast.glow and toast.glow.SetVertexColor then toast.glow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3]) end
    toast:HookScript("OnShow", function(self)
        FadeToastArt(self)
        pcall(GoldName, self)
    end)
end

local TOASTS = { "BNToastFrame", "TimeAlertFrame", "ShardTransferImminentFrame" }
function Chat.SkinToasts()
    local missing = false
    for _, name in ipairs(TOASTS) do
        if _G[name] then Guarded(name, SkinToast, _G[name]) else missing = true end
    end
    -- on some clients the pop-ups come with a Blizzard add-on that loads a little later
    if missing and not Chat.toastWatch then
        local f = CreateFrame("Frame")
        Chat.toastWatch = f
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(_, _, name)
            if name == "Blizzard_BNet" or name == "Blizzard_SocialToast" then
                for _, n in ipairs(TOASTS) do
                    if _G[n] then Guarded(n, SkinToast, _G[n]) end
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Start-up
--------------------------------------------------------------------------------
function Chat.Enable()
    local db = DB()
    for i = 1, NUM_WINDOWS do Guarded("window " .. i, SkinWindow, i) end
    for i = 2, NUM_WINDOWS do Guarded("unclamp " .. i, Unclamp, _G["ChatFrame" .. i]) end

    if db.skin and db.hideButtons then
        for _, name in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
                                "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
            local b = _G[name]
            if b then Guarded(name, function() b:Hide(); b:HookScript("OnShow", function(self) self:Hide() end) end) end
        end
    end
    Guarded("font size", Chat.ApplyFontSize, Chat)
    if db.classColors then Guarded("class colors", Chat.ApplyColors, Chat, true) end
    if db.timestamps then Guarded("timestamps", Chat.ApplyTimestamps, Chat) end
    Guarded("layout", SetupMover)
    if db.toastSkin ~= false then Guarded("toast skin", Chat.SkinToasts) end
end

CUI:RegisterModule({
    key = "chat",
    name = "Chat",
    addon = "CysUI",
    desc = "Flat gold-edged chat windows with a Copy button, class-colored names, timestamps and layout-mode positioning.",
    onEnable = Chat.Enable,
    open = function() CUI:OpenConfig("Chat") end,
})

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Chat", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Chat", width):SetPoint("TOPLEFT", 0, -4)

    local function Check(label, key, y, onSet)
        local cb = W.Checkbox(page, label, function() return db[key] end,
            function(on) db[key] = on; if onSet then onSet(on) end end)
        cb:SetPoint("TOPLEFT", 4, y)
        return cb
    end
    Check("Class-colored names", "classColors", -34, function(on) Chat:ApplyColors(on) end)
    Check("Show timestamps", "timestamps", -60, function() Chat:ApplyTimestamps() end)
    Check("24-hour timestamps", "use24h", -86, function() if db.timestamps then Chat:ApplyTimestamps() end end)
    Check("Short channel names: [Gen], [T], [G] instead of the full names", "shortChannels", -112)

    local size = W.Stepper(page, "Font size", function() return db.fontSize end,
        function(v) db.fontSize = v; Chat:ApplyFontSize() end, 9, 22, 1)
    size:SetPoint("TOPLEFT", 4, -144)

    W.Header(page, "Look (needs a /reload)", width):SetPoint("TOPLEFT", 0, -184)
    Check("Restyle the chat windows", "skin", -214)
    Check("Hide the scroll and menu buttons", "hideButtons", -240)
    Check("Chat tabs always visible, gold line under the active one", "tabsSolid", -266)
    local toast = W.Checkbox(page, "Battle.net pop-ups in the Cys look", function() return db.toastSkin ~= false end,
        function(on) db.toastSkin = on end)
    toast:SetPoint("TOPLEFT", 4, -292)

    local copy = W.Button(page, 110, 22, "Copy chat")
    copy:SetPoint("TOPLEFT", 4, -332)
    copy:SetScript("OnClick", function() Chat:ShowCopy(1) end)

    local note = W.Notes(page, 4, -370, width, "", {
            "Chat window 1 can be moved and resized in layout mode.",
            "Every chat window also has a small Copy button in its top-right corner.",
            "If anything looks off, untick Chat under Modules and reload: the game's own chat comes straight back.",
        })
end)
