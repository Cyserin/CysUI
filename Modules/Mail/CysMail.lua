CysUI:RegisterModule({
    key = "mail", name = "Cys's Mail",
    desc = "Tick mails in the inbox (shift-click to tick a whole range), then Open or Return the ticked ones. Open All is Blizzard's. Replaces Postal's select feature.",
    body = function(...)
local CUI = CysUI
local W = CUI.W
local T = W.T

-- Postal adds its own checkboxes and buttons in the same place; two of them at once would clash.
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
if IsLoaded and IsLoaded("Postal") then
    CUI:Print("Cys's Mail is waiting: Postal is loaded. Disable Postal (or switch Cys's Mail off in /cui > Modules) to avoid doubled buttons.")
    return
end

local PER_PAGE = INBOXITEMS_TO_DISPLAY or 7
local selected, lastClicked = {}, nil
local checks = {}
local openBtn, returnBtn

local function Say(msg) CUI:Print("|cFFFFD100Mail:|r " .. msg) end

local function MailIndex(row)
    local page = (InboxFrame and InboxFrame.pageNum) or 1
    return (page - 1) * PER_PAGE + row
end

local function CountSelected()
    local n, total = 0, GetInboxNumItems() or 0
    for idx in pairs(selected) do
        if idx <= total then n = n + 1 else selected[idx] = nil end
    end
    return n
end

local function Refresh()
    for i, cb in ipairs(checks) do
        cb.tick:SetShown(selected[MailIndex(i)] and true or false)
    end
    local n = CountSelected()
    if openBtn then
        openBtn.label:SetText(n > 0 and ("Open (" .. n .. ")") or "Open")
        returnBtn.label:SetText(n > 0 and ("Return (" .. n .. ")") or "Return")
    end
end

--------------------------------------------------------------------------------
-- Working through the ticked mails, one at a time, highest number first so the
-- numbers of the ones still waiting don't shift when a mail disappears.
--------------------------------------------------------------------------------
local run = { token = 0, queue = {}, active = false }
local stats

local function Finish(reason)
    run.active, run.waiting = false, false
    run.token = run.token + 1
    wipe(selected)
    lastClicked = nil
    if openBtn then openBtn:Enable(); returnBtn:Enable() end
    Refresh()
    if stats then
        local parts = {}
        if stats.done > 0 then parts[#parts + 1] = stats.done .. " " .. stats.verb end
        if stats.cod > 0 then parts[#parts + 1] = stats.cod .. " skipped (cash on delivery)" end
        if stats.skip > 0 then parts[#parts + 1] = stats.skip .. " skipped (nothing to " .. stats.noun .. ")" end
        if reason then parts[#parts + 1] = reason end
        Say(#parts > 0 and table.concat(parts, ", ") .. "." or "nothing to do.")
    end
    stats = nil
end

-- returns true when it asked the server to do something (and so should wait for the inbox to update)
local function Act(idx)
    local _, _, sender, _, money, cod, _, itemCount, _, wasReturned, _, canReply = GetInboxHeaderInfo(idx)
    if not sender and not money then return false end
    if run.mode == "open" then
        if (cod or 0) > 0 then stats.cod = stats.cod + 1; return false end
        if (money or 0) > 0 or (itemCount or 0) > 0 then
            AutoLootMailItem(idx)
            stats.done = stats.done + 1
            return true
        end
        stats.skip = stats.skip + 1
        return false
    else
        if canReply and not wasReturned then
            ReturnInboxItem(idx)
            stats.done = stats.done + 1
            return true
        end
        stats.skip = stats.skip + 1
        return false
    end
end

local function Step(token)
    if token ~= run.token or not run.active then return end
    local idx = table.remove(run.queue, 1)
    if not idx then return Finish() end
    if idx > (GetInboxNumItems() or 0) or not Act(idx) then return Step(token) end
    run.waiting = true
    run.token = run.token + 1
    local t = run.token
    C_Timer.After(1.2, function() if run.token == t then Step(t) end end) -- the server didn't answer in time: carry on
end

local function Start(mode)
    if run.active then return end
    if not MailFrame or not MailFrame:IsShown() then return end
    local list = {}
    for idx in pairs(selected) do list[#list + 1] = idx end
    if #list == 0 then Say("tick some mails on the left first (shift-click to tick a range).") return end
    table.sort(list, function(a, b) return a > b end)
    run.queue, run.mode, run.active = list, mode, true
    stats = { done = 0, cod = 0, skip = 0,
              verb = mode == "open" and "opened" or "returned",
              noun = mode == "open" and "take" or "return" }
    openBtn:Disable(); returnBtn:Disable()
    run.token = run.token + 1
    Step(run.token)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MAIL_INBOX_UPDATE")
ev:RegisterEvent("UI_ERROR_MESSAGE")
ev:RegisterEvent("MAIL_CLOSED")
ev:SetScript("OnEvent", function(_, event, a, b)
    if event == "MAIL_INBOX_UPDATE" then
        if run.active and run.waiting then
            run.waiting = false
            run.token = run.token + 1
            local t = run.token
            C_Timer.After(0.15, function() Step(t) end)
        end
        Refresh()
    elseif event == "UI_ERROR_MESSAGE" then
        if run.active and (b == ERR_INV_FULL or a == ERR_INV_FULL) then
            run.queue = {}
            Finish("stopped - your bags are full")
        end
    elseif event == "MAIL_CLOSED" then
        if run.active then Finish("stopped - mailbox closed") end
        wipe(selected)
        lastClicked = nil
    end
end)

--------------------------------------------------------------------------------
-- The tick boxes beside each mail, and the Open / Return buttons
--------------------------------------------------------------------------------
local function Click(i)
    local idx = MailIndex(i)
    if IsShiftKeyDown() and lastClicked then
        local a, b = math.min(lastClicked, idx), math.max(lastClicked, idx)
        for k = a, b do selected[k] = true end
    else
        selected[idx] = (not selected[idx]) or nil
    end
    lastClicked = idx
    Refresh()
end

local function Build()
    if checks[1] or not InboxFrame then return end
    for i = 1, PER_PAGE do
        local row = _G["MailItem" .. i]
        if row then
            local cb = CreateFrame("Button", "CysMailCheck" .. i, row)
            cb:SetSize(16, 16)
            cb:SetPoint("RIGHT", row, "LEFT", -6, 0)
            W.Texture(cb, "BACKGROUND", T.field):SetAllPoints()
            cb.edges = W.Border(cb, 1, T.line, "BORDER")
            cb.tick = W.Texture(cb, "ARTWORK", T.brand)
            cb.tick:SetPoint("TOPLEFT", 3, -3)
            cb.tick:SetPoint("BOTTOMRIGHT", -3, 3)
            cb.tick:Hide()
            cb:SetScript("OnEnter", function(s) W.SetBorder(s.edges, T.accent) end)
            cb:SetScript("OnLeave", function(s) W.SetBorder(s.edges, T.line) end)
            cb:SetScript("OnClick", function() Click(i) end)
            checks[i] = cb
        end
    end
    -- the tick boxes sit left of each row, outside the window: move the rows right (and narrower) so the boxes are inside it
    local SHIFT = 24
    local first = _G.MailItem1
    if first and first.GetPoint and not first.cysShifted then
        first.cysShifted = true
        local p, rel, rp, x, y = first:GetPoint(1)
        if p then
            first:ClearAllPoints()
            first:SetPoint(p, rel, rp, (x or 0) + SHIFT, y or 0)
        end
        for i = 1, PER_PAGE do
            local row = _G["MailItem" .. i]
            if row then row:SetWidth(row:GetWidth() - SHIFT) end
        end
    end
    openBtn = W.Button(InboxFrame, 130, 24, "Open")
    openBtn:SetPoint("TOPRIGHT", MailFrame, "TOP", -4, -38)
    openBtn:SetScript("OnClick", function() Start("open") end)
    returnBtn = W.Button(InboxFrame, 130, 24, "Return")
    returnBtn:SetPoint("TOPLEFT", MailFrame, "TOP", 4, -38)
    returnBtn:SetScript("OnClick", function() Start("return") end)
    openBtn:SetFrameLevel(InboxFrame:GetFrameLevel() + 3)
    returnBtn:SetFrameLevel(InboxFrame:GetFrameLevel() + 3)
    if hooksecurefunc and InboxFrame_Update then hooksecurefunc("InboxFrame_Update", Refresh) end
    InboxFrame:HookScript("OnShow", Refresh)
    Refresh()
end

Build()
end,
})
