--------------------------------------------------------------------------------
-- CysChangelog - a "What's New" window that pops up once after an addon updates.
--
-- The same file lives in every Cys addon folder. Whichever addon loads first sets it up;
-- the others just register with it, so you never get duplicate popups. If several addons
-- updated, their windows show one after another.
--
-- In an addon (this file must be listed BEFORE the addon's own Lua in the .toc):
--
--   if CysChangelog then
--       CysChangelog:Register({
--           name    = "Cys's Bags",
--           version = "2.0.0",                       -- the version you're running now
--           db      = function() return CysBagsDB end, -- any saved table; remembers what you've seen
--           entries = {                               -- newest first
--               { version = "2.0.0", date = "2026-10-17",
--                 added    = { "New thing" },
--                 improved = { "Better thing" },
--                 fixed    = { "Fixed thing" } },
--           },
--       })
--   end
--
-- To ship an update: add a new entry at the TOP of `entries` and raise `version`
-- (and the Version line in the .toc). The popup appears at the next login or /reload.
-- CysChangelog:Show("Cys's Bags") reopens it on demand (the /... changelog commands).
--------------------------------------------------------------------------------
local MODULE_VERSION = 1

CysChangelog = CysChangelog or { packs = {}, order = {}, queue = {} }
local M = CysChangelog
if (M.moduleVersion or 0) >= MODULE_VERSION then return end -- an up-to-date copy is already loaded
M.moduleVersion = MODULE_VERSION

local max, min = math.max, math.min

--------------------------------------------------------------------------------
-- Style (same palette as the other Cys addons)
--------------------------------------------------------------------------------
local C = {
    bg     = { 0.067, 0.067, 0.067 },
    gold   = { 0.851, 0.643, 0.129 },
    accent = { 1, 0.82, 0 },
    line   = { 0.165, 0.165, 0.165 },
    text   = { 0.88, 0.88, 0.88 },
    dim    = { 0.47, 0.47, 0.47 },
    dark   = { 0.067, 0.067, 0.067 },
}

local WIDTH = 440
local GOLD = "|cFFFFD100"

local SECTIONS = {
    { key = "added",    title = "|cFF4FD66BAdded|r" },
    { key = "improved", title = "|cFF6CB6FFImproved|r" },
    { key = "fixed",    title = "|cFFFF9F43Fixed|r" },
}

local function Texture(parent, layer, color, alpha)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

--------------------------------------------------------------------------------
-- Versions
--------------------------------------------------------------------------------
local function ParseVersion(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function IsNewer(v, than)
    local a1, b1, c1 = ParseVersion(v)
    local a2, b2, c2 = ParseVersion(than)
    if a1 ~= a2 then return a1 > a2 end
    if b1 ~= b2 then return b1 > b2 end
    return c1 > c2
end

-- Which entries to show: everything newer than the last version you saw (up to 5).
-- First time ever (nothing saved yet): just the newest entry. `force` = on demand: newest 3.
local function EntriesToShow(pack, force)
    local db = pack.db and pack.db()
    local seen = db and db.changelogSeen
    local list = {}
    for _, e in ipairs(pack.entries) do
        if force then
            if #list < 3 then list[#list + 1] = e end
        elseif seen == nil then
            if #list < 1 then list[#list + 1] = e end
        elseif IsNewer(e.version, seen) and #list < 5 then
            list[#list + 1] = e
        end
    end
    return list
end

local function BuildText(entries)
    local out = {}
    for i, e in ipairs(entries) do
        if i > 1 then out[#out + 1] = "" end
        out[#out + 1] = GOLD .. "Version " .. e.version .. "|r" .. (e.date and (" |cFF777777" .. e.date .. "|r") or "")
        for _, section in ipairs(SECTIONS) do
            local items = e[section.key]
            if items and #items > 0 then
                out[#out + 1] = section.title
                for _, line in ipairs(items) do out[#out + 1] = "  - " .. line end
            end
        end
    end
    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function MarkSeen(item)
    if item and item.mark then
        local db = item.pack.db and item.pack.db()
        if db then db.changelogSeen = item.pack.version end
    end
end

local function UpdateThumb(f)
    local range = f.scroll:GetVerticalScrollRange()
    if not range or range <= 0 then f.thumb:Hide(); return end
    local viewH = f.scroll:GetHeight()
    local thumbH = max(24, viewH * viewH / (viewH + range))
    local y = (f.scroll:GetVerticalScroll() / range) * (viewH - thumbH)
    f.thumb:ClearAllPoints()
    f.thumb:SetSize(3, thumbH)
    f.thumb:SetPoint("TOPLEFT", f.scroll, "TOPRIGHT", 6, -y)
    f.thumb:Show()
end

local function CreateWindow()
    local f = CreateFrame("Frame", "CysChangelogFrame", UIParent)
    f:SetSize(WIDTH, 300)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    Texture(f, "BACKGROUND", C.bg, 0.98):SetAllPoints()
    local edges = {}
    for i = 1, 4 do edges[i] = Texture(f, "BORDER", C.gold) end
    edges[1]:SetPoint("TOPLEFT");     edges[1]:SetPoint("TOPRIGHT");     edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT");  edges[2]:SetPoint("BOTTOMRIGHT");  edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT");   edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");    edges[4]:SetPoint("BOTTOMRIGHT");  edges[4]:SetWidth(1)

    f.title = Text(f, 14, C.accent, "CENTER")
    f.title:SetPoint("TOP", 0, -14)
    f.subtitle = Text(f, 11, C.dim, "CENTER")
    f.subtitle:SetPoint("TOP", 0, -34)

    local div = Texture(f, "BORDER", C.line)
    div:SetPoint("TOPLEFT", 16, -54)
    div:SetPoint("TOPRIGHT", -16, -54)
    div:SetHeight(1)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.text = Text(close, 14, { 1, 1, 1 }, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("X")
    close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", 20, -64)
    f.scroll:SetPoint("BOTTOMRIGHT", -30, 52)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(s, delta)
        s:SetVerticalScroll(max(0, min(s:GetVerticalScroll() - delta * 40, s:GetVerticalScrollRange())))
    end)
    f.scroll:SetScript("OnVerticalScroll", function() UpdateThumb(f) end)
    f.scroll:SetScript("OnScrollRangeChanged", function() UpdateThumb(f) end)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(WIDTH - 54, 1)
    f.scroll:SetScrollChild(f.content)

    f.body = Text(f.content, 11, C.text)
    f.body:SetPoint("TOPLEFT", 0, 0)
    f.body:SetWidth(WIDTH - 54)
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(3)

    f.thumb = Texture(f, "ARTWORK", C.gold, 0.5)
    f.thumb:Hide()

    -- "Got it": the one gold-filled button
    local ok = CreateFrame("Button", nil, f)
    ok:SetSize(110, 26)
    ok:SetPoint("BOTTOM", 0, 14)
    ok.bg = Texture(ok, "BACKGROUND", C.gold)
    ok.bg:SetAllPoints()
    ok.label = Text(ok, 12, C.dark, "CENTER")
    ok.label:SetPoint("CENTER", 0, 0)
    ok.label:SetText("Got it")
    ok:SetScript("OnEnter", function(s) s.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1) end)
    ok:SetScript("OnLeave", function(s) s.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end)
    ok:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnHide", function(self)
        MarkSeen(self.current)
        self.current = nil
        C_Timer.After(0.3, function() M:ShowNext() end) -- next addon's notes, if any
    end)
    tinsert(UISpecialFrames, "CysChangelogFrame")

    M.window = f
    return f
end

local function Display(item)
    local f = M.window or CreateWindow()
    MarkSeen(f.current) -- replacing a window that was still open
    f.current = item
    f.title:SetText(item.pack.name .. " - What's New")
    f.subtitle:SetText("You're now on version " .. item.pack.version)
    f.body:SetText(BuildText(item.entries))
    local textH = f.body:GetStringHeight()
    f.content:SetHeight(max(textH, 1))
    f:SetHeight(min(max(textH + 130, 240), 540)) -- grows with the text, scrolls past 540
    f.scroll:SetVerticalScroll(0)
    f:Show()
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------
function M:Register(pack)
    if type(pack) ~= "table" or not pack.name or not pack.version or not pack.entries then return end
    if not self.packs[pack.name] then self.order[#self.order + 1] = pack.name end
    self.packs[pack.name] = pack
end

function M:ShowNext()
    if self.window and self.window:IsShown() then return end
    local item = table.remove(self.queue, 1)
    if item then Display(item) end
end

-- Reopen an addon's notes on demand (newest 3 entries), whether or not you've seen them.
function M:Show(name)
    local pack = self.packs[name]
    if not pack then return end
    Display({ pack = pack, entries = EntriesToShow(pack, true), mark = false })
end

-- Queue every addon that has something you haven't seen, then start showing them.
function M:QueueUnseen()
    for _, name in ipairs(self.order) do
        local pack = self.packs[name]
        local entries = EntriesToShow(pack, false)
        if #entries > 0 then
            self.queue[#self.queue + 1] = { pack = pack, entries = entries, mark = true }
        end
    end
    self:ShowNext()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN") -- fires on login and on /reload
events:SetScript("OnEvent", function()
    C_Timer.After(3, function() M:QueueUnseen() end) -- let the UI finish loading first
end)
