--------------------------------------------------------------------------------
-- CysBugs - Cys's UI bug catcher (built-in BugGrabber / BugSack)
--
-- Catches Lua errors (and "addon tried to call a protected function" blocks) from every addon instead of the
-- game's error popup, keeps the last 50 with how often each happened, and shows them in a small window where
-- the whole report can be copied (Ctrl+A, Ctrl+C) and pasted to whoever made the addon.
-- Loaded right after Compat.lua so it catches errors in the rest of Cys's UI too.
-- With BugGrabber installed it takes over the game's error handler, so CysBugs listens to BugGrabber instead
-- and still shows everything here.
-- Minimap icon (like BugSack's): green = no errors this session, red with a count = errors caught. Click opens
-- the window, Shift-click clears, drag moves it around the map's edge.
-- /cysbugs (or /cuibugs) opens the window; /cuibugs clear empties it; /cuibugs off | on turns catching off or on;
-- /cysbugs icon shows or hides the minimap icon.
--------------------------------------------------------------------------------

local MAX_BUGS, CHAT_GAP = 50, 10
local floor, max, min = math.floor, math.max, math.min

local Bugs = {}
CysUIBugs = Bugs

local pending = {}  -- caught before the saved variables loaded
local db            -- CysUIDB.bugs = { off, session, list = { { msg, stack, locals, count, time, session } } }
local session = 0
local busy = false
local lastChat = 0
local origHandler = geterrorhandler and geterrorhandler()

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100CysBugs|r " .. msg) end

-- shorter paths: "Interface/AddOns/CysUI/Core.lua" -> "CysUI/Core.lua"
local function Tidy(s)
    s = tostring(s or "")
    s = s:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%[string \"@([^\"]+)\"%]", "%1")
    return s
end

-- which addon the error came from (first folder name in the message, else in the stack)
local function AddonOf(e)
    local a = (e.msg or ""):match("^([%w_%-!%.]+)[/\\]") or (e.stack or ""):match("([%w_%-!%.]+)[/\\][^\n]-%.lua")
    return a or "an addon"
end

local function Store(msg, stack, locals)
    local list = db and db.list or pending
    for i, e in ipairs(list) do
        if e.msg == msg and (e.stack or ""):sub(1, 300) == (stack or ""):sub(1, 300) then
            e.count = (e.count or 1) + 1
            e.time = time and time() or e.time
            e.session = session
            if i > 1 then table.remove(list, i); table.insert(list, 1, e) end
            if Bugs.Refresh then Bugs.Refresh() end
            if Bugs.UpdateIcon then Bugs.UpdateIcon() end
            return e, false
        end
    end
    local e = { msg = msg, stack = stack, locals = locals, count = 1, time = time and time() or 0, session = session }
    table.insert(list, 1, e)
    while #list > MAX_BUGS do table.remove(list) end
    if Bugs.Refresh then Bugs.Refresh() end
    if Bugs.UpdateIcon then Bugs.UpdateIcon() end
    return e, true
end

local function Announce(e)
    if not db or not DEFAULT_CHAT_FRAME then return end
    local now = GetTime and GetTime() or 0
    if now - lastChat < CHAT_GAP then return end
    lastChat = now
    Print("caught a Lua error from " .. AddonOf(e) .. ". Type |cFFFFD100/cysbugs|r to see it.")
end

local function Catch(err)
    if busy then return end
    if db and db.off then
        if origHandler then return origHandler(err) end
        return
    end
    busy = true
    -- read the stack and locals right here (level 3 = the code that raised the error), before any pcall
    local rawStack = debugstack and debugstack(3) or ""
    local rawLocals = debuglocals and debuglocals(3) or ""
    pcall(function()
        local msg = Tidy(err)
        local stack = Tidy(rawStack)
        local locals = Tidy(rawLocals):sub(1, 3000)
        local e, new = Store(msg, stack, locals)
        if new then Announce(e) end
    end)
    busy = false
end

-- BugGrabber (if installed) owns the error handler; otherwise CysBugs does
if seterrorhandler and not _G.BugGrabber then seterrorhandler(Catch) end

-- a note from Cys's own addons (not a Lua error, but worth seeing in the list)
function Bugs.Note(msg, stack)
    local _, new = Store(Tidy(msg), Tidy(stack), "")
    if new then Announce({ msg = Tidy(msg), stack = Tidy(stack) }) end
end

-- BugGrabber installed: copy each error it grabs into CysBugs
local function HookBugGrabber()
    local BG = _G.BugGrabber
    if not BG or Bugs.bgHooked then return end
    if BG.setupCallbacks then pcall(BG.setupCallbacks) end
    if not BG.RegisterCallback then return end
    Bugs.bgHooked = true
    BG.RegisterCallback(Bugs, "BugGrabber_BugGrabbed", function(_, err)
        if type(err) ~= "table" or (db and db.off) then return end
        local _, new = Store(Tidy(err.message), Tidy(err.stack), Tidy(err.locals):sub(1, 3000))
        if new then Announce({ msg = Tidy(err.message), stack = Tidy(err.stack) }) end
    end)
    -- errors BugGrabber caught while the addons were loading
    local list = BG.GetDB and BG:GetDB()
    local cur = BG.GetSessionId and BG:GetSessionId()
    if type(list) == "table" then
        for _, err in ipairs(list) do
            if err.session == cur then Store(Tidy(err.message), Tidy(err.stack), Tidy(err.locals):sub(1, 3000)) end
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables, blocked actions
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(ev.RegisterEvent, ev, "LUA_WARNING") -- warnings (bad anchors, etc.) never reach the error handler
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if e == "ADDON_LOADED" then
        if a1 ~= "CysUI" then return end
        CysUIDB = CysUIDB or {}
        CysUIDB.bugs = CysUIDB.bugs or {}
        db = CysUIDB.bugs
        db.list = db.list or {}
        db.session = (db.session or 0) + 1
        session = db.session
        -- what was caught before now goes on top
        for i = #pending, 1, -1 do
            local p = pending[i]
            p.session = session
            local _, new = Store(p.msg, p.stack, p.locals)
            if not new then
                -- Store bumped an old copy by one; add the rest of this one's count
                db.list[1].count = db.list[1].count + (p.count or 1) - 1
            end
        end
        wipe(pending)
    elseif e == "PLAYER_LOGIN" then
        pcall(HookBugGrabber)
        if Bugs.BuildIcon then pcall(Bugs.BuildIcon) end
        -- tell once at login when this session already caught something (errors while loading)
        if db and not db.off then
            for _, b in ipairs(db.list) do
                if b.session == session then lastChat = 0; Announce(b); break end
            end
        end
    elseif e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN" then
        if db and db.off then return end
        local what = e == "ADDON_ACTION_FORBIDDEN" and "was not allowed to call" or "tried to call"
        local msg = string.format("%s %s the protected function %s.", tostring(a1 or "An addon"), what, tostring(a2 or "?"))
        local _, new = Store(Tidy(msg), debugstack and Tidy(debugstack(2)) or "", "")
        if new then Announce({ msg = tostring(a1 or "") .. "/" }) end
    elseif e == "LUA_WARNING" then
        if db and db.off then return end
        -- newer clients pass (type, text), older ones just the text; the text may carry its own stack
        local text = type(a2) == "string" and a2 or (type(a1) == "string" and a1) or nil
        if not text or text == "" then return end
        local msg, stack = text:match("^(.-)\n[Ss]tack:?\n?(.*)$")
        msg, stack = Tidy(msg or text), Tidy(stack or "")
        local _, new = Store("Warning: " .. msg, stack, "")
        if new then Announce({ msg = msg, stack = stack }) end
    end
end)

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local frame, index = nil, 1

local function Current() local l = db and db.list or pending; return l, l[index] end

local function Report(e)
    if not e then return "" end
    local when = date and e.time and date("%Y-%m-%d %H:%M:%S", e.time) or "?"
    local s = e.msg .. "\n\n" .. "x" .. (e.count or 1) .. "  |  " .. when .. "  |  session " .. tostring(e.session or "?")
    if e.stack and e.stack ~= "" then s = s .. "\n\nStack:\n" .. e.stack end
    if e.locals and e.locals ~= "" then s = s .. "\nLocals:\n" .. e.locals end
    return s
end

local function Build()
    local W = CysUI and CysUI.W
    local T = W and W.T
    local f = CreateFrame("Frame", "CysUIBugsFrame", UIParent)
    frame = f
    f:SetSize(560, 380)
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
    tinsert(UISpecialFrames, "CysUIBugsFrame") -- Escape closes it

    local function Tex(parent, layer, c, a)
        local t = parent:CreateTexture(nil, layer)
        t:SetColorTexture(c[1], c[2], c[3], a or 1)
        return t
    end
    local function Txt(parent, size, c, j)
        if W then return W.Text(parent, size, c, j) end
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, size, ""); fs:SetTextColor(c[1], c[2], c[3]); fs:SetJustifyH(j or "LEFT")
        return fs
    end
    local function Btn(w, label)
        if W then return W.Button(f, w, 22, label) end
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetText(label)
        function b:SetActive(on) if on then self:Enable() else self:Disable() end end
        return b
    end
    local bg = T and T.bg or { 0.067, 0.067, 0.067 }
    local gold = T and T.accent or { 1, 0.82, 0 }
    local line = T and T.line or { 0.165, 0.165, 0.165 }
    Tex(f, "BACKGROUND", bg, 0.96):SetAllPoints()
    if W then W.Border(f, 1, T.border, "BORDER") end

    f.title = Txt(f, 12, gold)
    f.title:SetPoint("TOPLEFT", 10, -9)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -4, -4)
    close.text = Txt(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)
    local hl = Tex(f, "BORDER", line); hl:SetPoint("TOPLEFT", 8, -30); hl:SetPoint("TOPRIGHT", -8, -30); hl:SetHeight(1)

    -- the report: a read-only box you can select and copy from
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -38)
    sf:SetPoint("BOTTOMRIGHT", -30, 40)
    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(510)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus(); f:Hide() end)
    box:SetScript("OnTextChanged", function(s, user) if user then s:SetText(s.report or "") end end) -- read only
    box:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    sf:SetScrollChild(box)
    f.box = box

    f.prev = Btn(70, "< Newer")
    f.prev:SetPoint("BOTTOMLEFT", 10, 10)
    f.prev:SetScript("OnClick", function() index = max(1, index - 1); Bugs.Refresh() end)
    f.next = Btn(70, "Older >")
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
    f.next:SetScript("OnClick", function() local l = Current(); index = min(#l, index + 1); Bugs.Refresh() end)
    f.pos = Txt(f, 11, T and T.dim or { 0.6, 0.6, 0.6 }, "CENTER")
    f.pos:SetPoint("LEFT", f.next, "RIGHT", 10, 0)
    f.clear = Btn(70, "Clear all")
    f.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    f.clear:SetScript("OnClick", function() Bugs.Clear() end)
    f.copy = Btn(90, "Select all")
    f.copy:SetPoint("RIGHT", f.clear, "LEFT", -6, 0)
    f.copy:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)
    local hint = Txt(f, 10, T and T.dim or { 0.6, 0.6, 0.6 }, "RIGHT")
    hint:SetPoint("RIGHT", f.copy, "LEFT", -8, 0)
    hint:SetText("Ctrl+C to copy")
end

function Bugs.Refresh()
    if not frame or not frame:IsShown() then return end
    local list, e = Current()
    if not e and #list > 0 then index = 1; e = list[1] end
    local here = 0
    for _, b in ipairs(list) do if b.session == session then here = here + 1 end end
    frame.title:SetText("CysBugs  |cFF999999" .. #list .. (#list == 1 and " error" or " errors")
        .. ", " .. here .. " this session|r")
    local text = e and Report(e) or "No errors caught. Nice."
    frame.box.report = text
    frame.box:SetText(text)
    frame.box:SetCursorPosition(0)
    frame.pos:SetText(#list > 0 and (index .. " / " .. #list) or "")
    frame.prev:SetActive(index > 1)
    frame.next:SetActive(index < #list)
    frame.clear:SetActive(#list > 0)
end

function Bugs.Show()
    if not frame then Build() end
    index = 1
    frame:Show()
    Bugs.Refresh()
end

function Bugs.Clear()
    if db then wipe(db.list) end
    wipe(pending)
    index = 1
    Bugs.Refresh()
    Bugs.UpdateIcon()
end

--------------------------------------------------------------------------------
-- Minimap icon
--------------------------------------------------------------------------------
local icon
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function SessionCount()
    local n = 0
    for _, b in ipairs(db and db.list or pending) do if b.session == session then n = n + 1 end end
    return n
end

local function IsSquare()
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then return true end
    return CysUI and CysUI.IsModuleEnabled and CysUI:IsModuleEnabled("minimap") and true or false
end

local function PlaceIcon()
    if not icon then return end
    local a = math.rad(db.icon.angle or 225)
    local x, y = math.cos(a), math.sin(a)
    -- just inside the map's edge (3 px gap), never sitting on its border
    local inset = icon:GetWidth() / 2 + 3
    local w, h = Minimap:GetWidth() / 2 - inset, Minimap:GetHeight() / 2 - inset
    if IsSquare() then
        local m = max(math.abs(x), math.abs(y)) -- along the square's edge
        x, y = x / m, y / m
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

function Bugs.UpdateIcon()
    if not icon then return end
    if db.icon.hide then icon:Hide(); return end
    icon:Show()
    local n = SessionCount()
    if n > 0 then
        icon.dot:SetVertexColor(0.9, 0.15, 0.15)
        icon.dot:SetSize(14, 14)
        icon.num:SetText(n > 99 and "99+" or n)
    else
        icon.dot:SetVertexColor(0.25, 0.85, 0.35)
        icon.dot:SetSize(8, 8)
        icon.num:SetText("")
    end
end

function Bugs.BuildIcon()
    if icon or not db or not Minimap then return end
    db.icon = db.icon or {}
    local W = CysUI and CysUI.W
    local T = W and W.T
    icon = CreateFrame("Button", "CysUIBugsMinimapButton", Minimap) -- "CysUI..." names stay out of the button panel
    icon:SetSize(18, 18)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    icon:RegisterForDrag("LeftButton")
    -- a dark round backing with a thin gold ring, the colored dot on top
    local ring = icon:CreateTexture(nil, "BACKGROUND")
    ring:SetTexture(CIRCLE)
    ring:SetAllPoints()
    local g = T and T.border or { 0.851, 0.643, 0.129 }
    ring:SetVertexColor(g[1], g[2], g[3], 0.9)
    local bg = icon:CreateTexture(nil, "BORDER")
    bg:SetTexture(CIRCLE)
    bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
    local c = T and T.bg or { 0.067, 0.067, 0.067 }
    bg:SetVertexColor(c[1], c[2], c[3], 0.95)
    icon.dot = icon:CreateTexture(nil, "ARTWORK")
    icon.dot:SetTexture(CIRCLE)
    icon.dot:SetPoint("CENTER")
    icon.num = icon:CreateFontString(nil, "OVERLAY")
    icon.num:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    icon.num:SetPoint("CENTER", 0, 0)
    icon.num:SetTextColor(1, 1, 1)
    local hl = icon:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(CIRCLE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.15)

    icon:SetScript("OnClick", function()
        if IsShiftKeyDown() then Bugs.Clear(); Print("cleared.")
        elseif frame and frame:IsShown() then frame:Hide()
        else Bugs.Show() end
    end)
    icon:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local sc = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            db.icon.angle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
            PlaceIcon()
        end)
    end)
    icon:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    icon:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("CysBugs", 1, 0.82, 0)
        local n, list = SessionCount(), db.list
        if n > 0 then
            GameTooltip:AddLine(n .. (n == 1 and " error" or " errors") .. " this session", 1, 0.3, 0.3)
            local first = (list[1] and list[1].msg or ""):match("^[^\n]*") or ""
            if #first > 120 then first = first:sub(1, 120) .. "..." end
            GameTooltip:AddLine(first, 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No errors this session", 0.3, 0.9, 0.4)
        end
        if #list > n then GameTooltip:AddLine(#list .. " saved in all", 0.6, 0.6, 0.6) end
        if db.off then GameTooltip:AddLine("Catching is off (/cysbugs on)", 1, 0.6, 0.2) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: open   Shift-click: clear   Drag: move", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Minimap:HookScript("OnSizeChanged", PlaceIcon)
    PlaceIcon()
    C_Timer.After(1, PlaceIcon) -- after Cys's UI has squared and sized the map
    Bugs.UpdateIcon()
end

SLASH_CYSUIBUGS1 = "/cysbugs"
SLASH_CYSUIBUGS2 = "/cuibugs"
SlashCmdList.CYSUIBUGS = function(msg)
    msg = strtrim(string.lower(msg or ""))
    if msg == "clear" then Bugs.Clear(); Print("cleared.")
    elseif msg == "off" then if db then db.off = true end; Print("off (the game handles errors again).")
    elseif msg == "on" then if db then db.off = nil end; Print("on.")
    elseif msg == "icon" then
        if db then
            db.icon = db.icon or {}
            db.icon.hide = not db.icon.hide or nil
            Bugs.UpdateIcon()
            Print("minimap icon " .. (db.icon.hide and "hidden (/cysbugs icon brings it back)." or "shown."))
        end
    else Bugs.Show() end
end
