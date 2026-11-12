--------------------------------------------------------------------------------
-- Cys's Quest Tracker (WoW Forever) - the quests you track, grouped by zone
--
-- A quest list of our own in place of the game's tracker: a gold header per zone (the zone you are in comes
-- first), each with its own collapse, and a "this zone only" switch so the list stays short. Objective
-- counts sit on the right and are colored by progress; a sound plays when a quest's objectives are done.
-- Quest items get a button beside their quest. It can fade in combat or while the mouse is away, and hide
-- in raids.
--
-- It reads the game's own watch list, so tracking a quest anywhere (quest log, map) shows it here, and
-- Shift-click here stops tracking it for the game as well. The game's tracker is only faded (alpha and
-- mouse), never hidden, moved or changed, so nothing of Blizzard's runs from our code.
--
-- Combat: quest item buttons are secure, so the list can only be rebuilt out of combat. In combat the
-- numbers and colors still update; a quest that is added or removed mid-fight shows after the fight.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "questlist", name = "Cys's Quest Tracker", foreverOnly = true, defaultOff = true,
    desc = "WoW Forever: your tracked quests grouped by zone (the zone you are in first), with a This zone only switch, counts colored by progress, a sound when a quest is done, quest item buttons, and fading. Replaces the game's tracker while on.",
    open = function() CysUI:OpenConfig("Quest Tracker") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T
local Secret = CysUICompat.Secret

CysUIDB.questlist = CysUIDB.questlist or {}
local db = CysUIDB.questlist
local DEFAULTS = { width = 250, maxHeight = 480, zoneOnly = false, group = true, alsoZone = false, level = true,
    sound = true, hideDone = false, fade = "none", fadePct = 35, hideRaid = false, hideGame = true,
    titleSize = 12, lineSize = 11, items = true, bg = true, allCollapsed = false }
for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
db.collapsed = db.collapsed or {} -- [zone name] = true
db.zones = db.zones or {}         -- [questID] = zone name, remembered for quests under collapsed log headers

local MOVER = "questlist"
local PAD = 8
local INDENT = 10      -- objectives sit under the title
local ITEM = 22        -- quest item button size
local FLAT = "Interface\\Buttons\\WHITE8X8"
local OTHER = "Other"

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------
-- holder = fixed box (width x max height) for Layout mode; the list grows down from its top inside it
local holder = CreateFrame("Frame", "CysQuestTracker", UIParent)
holder:SetSize(db.width, db.maxHeight)
holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -250)
holder:SetFrameStrata("MEDIUM")
holder:SetFrameLevel(20)
CUI:RegisterMovable(holder, MOVER, "Quest Tracker", { point = "TOPRIGHT", x = -40, y = -250 })

local panel = CreateFrame("Frame", nil, holder) -- background, sized to what is showing
panel:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
panel:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
panel:SetHeight(30)
panel.bg = W.Texture(panel, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.82 })
panel.bg:SetAllPoints()
panel.edges = W.Border(panel, 1, T.border, "BORDER")

local content = CreateFrame("Frame", nil, holder)
content:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
content:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
content:SetHeight(30)
content:SetFrameLevel(panel:GetFrameLevel() + 2)

local function Font(fs, size, outline)
    fs:SetFont(STANDARD_TEXT_FONT, size, outline and "OUTLINE" or "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

-- header: QUESTS  n/max          [Zone] [-]
local head = CreateFrame("Button", nil, content)
head:SetHeight(20)
head:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -4)
head:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -4)
head:RegisterForClicks("LeftButtonUp")
head.title = W.Text(head, 11, T.accent)
head.title:SetPoint("LEFT", 0, 0)
head.count = W.Text(head, 10, T.dim)
head.count:SetPoint("LEFT", head.title, "RIGHT", 6, 0)
head.line = head:CreateTexture(nil, "ARTWORK")
head.line:SetTexture(FLAT)
head.line:SetHeight(1)
head.line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, -1)
head.line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, -1)

local function SmallButton(text, tip)
    local b = CreateFrame("Button", nil, head)
    b:SetSize(18, 16)
    b.text = W.Text(b, 10, T.dim, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.Paint then self:Paint() end
    end)
    return b
end
head.fold = SmallButton("-", "Fold / unfold every zone")
head.fold:SetPoint("RIGHT", head, "RIGHT", 2, 0)
head.zone = SmallButton("Zone", "This zone only: show just the quests for the zone you are in")
head.zone:SetWidth(34)
head.zone:SetPoint("RIGHT", head.fold, "LEFT", -2, 0)

-- pools -----------------------------------------------------------------------
local zoneRows, questRows, lineRows, itemButtons = {}, {}, {}, {}
local used = { zone = 0, quest = 0, line = 0, item = 0 }

local function ZoneRow(i)
    local r = zoneRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetHeight(16)
    r:RegisterForClicks("LeftButtonUp")
    r.sign = W.Text(r, 10, T.dim)
    r.sign:SetPoint("LEFT", 0, 0)
    r.sign:SetWidth(10)
    r.name = W.Text(r, 10, T.accent)
    r.name:SetPoint("LEFT", r.sign, "RIGHT", 2, 0)
    r.num = W.Text(r, 10, T.dim, "RIGHT")
    r.num:SetPoint("RIGHT", 0, 0)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetTexture(FLAT)
    r.line:SetHeight(1)
    r.line:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.line:SetPoint("RIGHT", r.num, "LEFT", -6, 0)
    r:SetScript("OnEnter", function(self) self.name:SetTextColor(1, 1, 1) end)
    r:SetScript("OnLeave", function(self) self:Paint() end)
    zoneRows[i] = r
    return r
end

local OnQuestClick, OnQuestEnter -- set below
local function QuestRow(i)
    local r = questRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.focus = r:CreateTexture(nil, "ARTWORK")
    r.focus:SetTexture(FLAT)
    r.focus:SetWidth(2)
    r.focus:SetPoint("TOPLEFT", r, "TOPLEFT", -6, -1)
    r.focus:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", -6, 1)
    r.title = r:CreateFontString(nil, "OVERLAY")
    Font(r.title, db.titleSize)
    r.title:SetPoint("TOPLEFT", 0, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r.hl:Hide()
    r:SetScript("OnClick", function(self, button) OnQuestClick(self, button) end)
    r:SetScript("OnEnter", function(self) self.hl:Show(); OnQuestEnter(self) end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    questRows[i] = r
    return r
end

local function LineRow(i)
    local r = lineRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r.dash = r:CreateFontString(nil, "OVERLAY")
    Font(r.dash, db.lineSize) -- a font before any text, or SetText errors
    r.dash:SetPoint("TOPLEFT", 0, 0)
    r.text = r:CreateFontString(nil, "OVERLAY")
    Font(r.text, db.lineSize)
    r.text:SetPoint("TOPLEFT", 8, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    r.num = r:CreateFontString(nil, "OVERLAY")
    Font(r.num, db.lineSize)
    r.num:SetPoint("TOPRIGHT", 0, 0)
    r.num:SetJustifyH("RIGHT")
    lineRows[i] = r
    return r
end

-- quest item buttons: secure (they use the item), so only set up out of combat
local function ItemButton(i)
    local b = itemButtons[i]
    if b then return b end
    b = CreateFrame("Button", "CysQuestItem" .. i, holder, "SecureActionButtonTemplate")
    b:SetSize(ITEM, ITEM)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false) -- Forever presses secure buttons on key down by default
    b:SetAttribute("type", "item")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.Texture(b, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(b, 1, T.border, "OVERLAY")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.count = W.Text(b, 10, T.text, "RIGHT")
    Font(b.count, 10, true)
    b.count:SetPoint("BOTTOMRIGHT", -1, 2)
    b:SetHighlightTexture(FLAT)
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    itemButtons[i] = b
    return b
end

local function ItemCooldown(b)
    if not (b.itemID and b:IsShown()) then return end
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not get then return end
    local ok, start, dur, enable = pcall(get, b.itemID)
    if not ok or Secret(start) or Secret(dur) or type(start) ~= "number" or type(dur) ~= "number" then return end
    if dur > 1.5 and enable ~= 0 and enable ~= false then
        b.cd:SetCooldown(start, dur)
    else
        b.cd:Clear()
    end
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local function Lower(s) return type(s) == "string" and s:lower() or nil end

-- the names the zone you are in goes by (quest log headers use the zone name)
local function HereNames()
    local names = {}
    local function Add(s) s = Lower(s); if s and s ~= "" then names[s] = true end end
    Add(GetRealZoneText and GetRealZoneText())
    Add(GetZoneText and GetZoneText())
    local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
    if okM and type(map) == "number" then
        local okI, info = pcall(C_Map.GetMapInfo, map)
        if okI and info then Add(info.name) end
    end
    return names
end

local function Objectives(questID)
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(list) == "table" then return list end
    return {}
end

-- complete = every objective done (a delivery quest with no objectives is never "complete" here)
local function IsDone(questID, objs)
    if #objs == 0 then return false end
    local ok, done = pcall(C_QuestLog.IsComplete, questID)
    return ok and done == true
end

local function Watched()
    local set, order = {}, {}
    local n = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
    for i = 1, n do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if id and not set[id] then set[id] = true; order[#order + 1] = id end
    end
    return set, order
end

-- one pass over the quest log: every quest with its zone header, title and level, in log order
local function ScanLog()
    local quests, zoneOrder, header = {}, {}, nil
    local seenZone = {}
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif info.questID and info.questID > 0 and not info.isHidden then
                local zone = header or db.zones[info.questID] or OTHER
                db.zones[info.questID] = zone
                quests[#quests + 1] = { id = info.questID, title = info.title, level = info.level,
                    zone = zone, onMap = info.isOnMap, index = i }
                if not seenZone[zone] then seenZone[zone] = true; zoneOrder[#zoneOrder + 1] = zone end
            end
        end
    end
    return quests, zoneOrder
end

local function MaxQuests()
    local f = C_QuestLog.GetMaxNumQuestsCanAccept or C_QuestLog.GetMaxNumQuests
    local ok, n = pcall(f or function() end)
    if ok and type(n) == "number" and n > 0 then return n end
end

-- "Kobold Vermin slain: 6/10" or "6/10 Kobold Vermin slain" -> "Kobold Vermin slain", "6/10"
local function SplitObjective(o)
    local text = o.text or ""
    local have, need = o.numFulfilled, o.numRequired
    local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    if name == "" then name = text end
    if type(have) == "number" and type(need) == "number" and need > 1 then
        return name, have .. "/" .. need, have, need
    end
    return text, nil, nil, nil
end

local function ProgressColor(have, need, finished)
    if finished or (have and need and have >= need) then return 0.45, 0.62, 0.45 end
    if not (have and need and need > 0) then return T.text[1], T.text[2], T.text[3] end
    local p = have / need
    if p < 0.34 then return 0.92, 0.48, 0.42 end
    if p < 0.67 then return 0.95, 0.72, 0.36 end
    return 0.86, 0.86, 0.45
end

local function TitleColor(level, done, watched)
    if done then return 0.40, 0.85, 0.45 end
    local r, g, b = 1, 0.82, 0
    if level and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c then r, g, b = c.r, c.g, c.b end
    end
    if not watched then r, g, b = r * 0.7, g * 0.7, b * 0.7 end
    return r, g, b
end

--------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------
local function IsWatched(questID)
    local ok, t = pcall(C_QuestLog.GetQuestWatchType, questID)
    return ok and t ~= nil
end

local function OpenOnMap(questID)
    if InCombatLockdown() or type(QuestMapFrame_OpenToQuestDetails) ~= "function" then
        C_SuperTrack.SetSuperTrackedQuestID(questID) -- in combat: focus it instead (the map can't open then)
        return
    end
    QuestMapFrame_OpenToQuestDetails(questID)
end

local function Share(questID)
    if QuestUtil and QuestUtil.ShareQuest then QuestUtil.ShareQuest(questID); return end
    if C_QuestLog.SetSelectedQuest and QuestLogPushQuest then C_QuestLog.SetSelectedQuest(questID); QuestLogPushQuest() end
end

OnQuestClick = function(row, button)
    local id = row.questID
    if not id then return end
    if button == "LeftButton" then
        if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID and ChatFrameUtil.TryInsertQuestLinkForQuestID(id) then return end
        if IsShiftKeyDown() then
            if IsWatched(id) then C_QuestLog.RemoveQuestWatch(id) else C_QuestLog.AddQuestWatch(id) end
            return
        end
        OpenOnMap(id)
        return
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(C_QuestLog.GetTitleForQuestID(id) or "")
        if C_SuperTrack.GetSuperTrackedQuestID() ~= id then
            root:CreateButton("Focus this quest", function() C_SuperTrack.SetSuperTrackedQuestID(id) end)
        else
            root:CreateButton("Stop focusing", function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
        end
        root:CreateButton("Show in the quest log", function() OpenOnMap(id) end)
        if IsWatched(id) then
            root:CreateButton("Stop tracking", function() C_QuestLog.RemoveQuestWatch(id) end)
        else
            root:CreateButton("Track", function() C_QuestLog.AddQuestWatch(id) end)
        end
        local okP, push = pcall(C_QuestLog.IsPushableQuest, id)
        if okP and push and IsInGroup() then
            root:CreateButton("Share with party", function() Share(id) end)
        end
    end)
end

OnQuestEnter = function(row)
    local id = row.questID
    if not id then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(id) or "", 1, 0.82, 0)
    if row.zone then GameTooltip:AddLine(row.zone, 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: show in the quest log", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: " .. (IsWatched(id) and "stop tracking" or "track"), 1, 1, 1)
    GameTooltip:AddLine("Right-click: more", 1, 1, 1)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local wasDone = {}   -- [questID] = true once its objectives were all done (for the sound)
local primed = false -- no sounds from the first look after login
local dirty = false  -- something changed in combat that needs a rebuild
local shape = ""     -- what is on screen, so combat updates know whether they can just repaint

local shownZones = {} -- zone headers in the last build, for the fold-all button
local function AnyZoneOpen()
    for _, z in ipairs(shownZones) do if not db.collapsed[z] then return true end end
    return false
end
local function PaintHeader()
    head.line:SetVertexColor(T.border[1], T.border[2], T.border[3], 0.55)
    head.zone.Paint = function(self)
        local c = db.zoneOnly and T.accent or T.dim
        self.text:SetTextColor(c[1], c[2], c[3])
    end
    head.fold.Paint = function(self)
        self.text:SetText(AnyZoneOpen() and "-" or "+")
        self.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    end
    head.zone:Paint()
    head.fold:Paint()
end

-- what to show: { { zone, here, quests = { { id, title, level, objs, done, watched } } } }, total tracked, hidden elsewhere
local function Collect()
    local watched = Watched()
    local quests, zoneOrder = ScanLog()
    local here = HereNames()
    local byZone = {}
    local shown, elsewhere, total = 0, 0, 0
    -- a tracked quest the log scan did not list (its log header is collapsed): add it with its remembered zone
    local listed = {}
    for _, q in ipairs(quests) do listed[q.id] = true end
    for id in pairs(watched) do
        if not listed[id] then
            local zone = db.zones[id] or OTHER
            local okL, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
            quests[#quests + 1] = { id = id, title = C_QuestLog.GetTitleForQuestID(id), level = okL and lvl or nil, zone = zone }
            local known = false
            for _, z in ipairs(zoneOrder) do if z == zone then known = true end end
            if not known then zoneOrder[#zoneOrder + 1] = zone end
        end
    end
    for _, q in ipairs(quests) do
        local isWatched = watched[q.id] and true or false
        local inHere = here[Lower(q.zone)] or false
        if isWatched then total = total + 1 end
        local want = isWatched or (db.alsoZone and inHere)
        if want and db.zoneOnly and not inHere then
            want = false
            elsewhere = elsewhere + 1
        end
        if want then
            local objs = Objectives(q.id)
            q.objs, q.done, q.watched, q.here = objs, IsDone(q.id, objs), isWatched, inHere
            local g = byZone[q.zone]
            if not g then g = { zone = q.zone, here = inHere, quests = {} }; byZone[q.zone] = g end
            g.quests[#g.quests + 1] = q
            shown = shown + 1
        end
    end
    -- the zone you are in first, then the rest in quest log order
    local groups = {}
    for _, z in ipairs(zoneOrder) do if byZone[z] and byZone[z].here then groups[#groups + 1] = byZone[z] end end
    for _, z in ipairs(zoneOrder) do if byZone[z] and not byZone[z].here then groups[#groups + 1] = byZone[z] end end
    if not db.group and #groups > 1 then -- one flat list, still in that order
        local flat = { zone = nil, here = true, quests = {} }
        for _, g in ipairs(groups) do for _, q in ipairs(g.quests) do flat.quests[#flat.quests + 1] = q end end
        groups = { flat }
    end
    return groups, total, elsewhere, #quests
end

local function Sounds(groups)
    for _, g in ipairs(groups) do
        for _, q in ipairs(g.quests) do
            if q.done and not wasDone[q.id] and primed and db.sound then
                PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 878)
            end
            wasDone[q.id] = q.done or nil
        end
    end
    primed = true
end

local function Shape(groups)
    local parts = { db.allCollapsed and "C" or "O" }
    for _, g in ipairs(groups) do
        parts[#parts + 1] = (g.zone or "") .. (db.collapsed[g.zone or ""] and "-" or "+")
        for _, q in ipairs(g.quests) do
            local n = 0
            for _, o in ipairs(q.objs) do if not (db.hideDone and o.finished) then n = n + 1 end end
            parts[#parts + 1] = q.id .. ":" .. (q.done and "d" or n)
        end
    end
    return table.concat(parts, ",")
end

-- one objective line (text, number, colors); returns its height
local function FillLine(r, o, q, w)
    local name, num, have, need = SplitObjective(o)
    if o.type == "progressbar" and GetQuestProgressBarPercent then
        local okP, pct = pcall(GetQuestProgressBarPercent, q.id)
        if okP and type(pct) == "number" then num, have, need = floor(pct) .. "%", pct, 100 end
    end
    local cr, cg, cb = ProgressColor(have, need, o.finished)
    Font(r.dash, db.lineSize); Font(r.text, db.lineSize); Font(r.num, db.lineSize)
    r.dash:SetText("-")
    r.dash:SetTextColor(cr, cg, cb)
    r.num:SetText(num or "")
    r.num:SetTextColor(cr, cg, cb)
    if o.finished then r.text:SetTextColor(0.45, 0.62, 0.45) else r.text:SetTextColor(T.text[1], T.text[2], T.text[3]) end
    local numW = num and (r.num:GetStringWidth() + 8) or 0
    r.text:SetWidth(max(40, w - 8 - numW))
    r.text:SetText(name)
    return max(r.text:GetStringHeight(), db.lineSize) + 2
end

local function ReadyLine(r)
    Font(r.dash, db.lineSize); Font(r.text, db.lineSize); Font(r.num, db.lineSize)
    r.dash:SetText("-")
    r.dash:SetTextColor(0.40, 0.85, 0.45)
    r.text:SetTextColor(0.40, 0.85, 0.45)
    r.num:SetText("")
    r.text:SetText("Ready to turn in")
    return db.lineSize + 2
end

local function Visible(groups)
    if CUI.layoutMode then return true end
    if db.hideRaid and IsInRaid() then return false end
    return #groups > 0 or db.zoneOnly
end

local function Fade()
    local a = 1
    if not CUI.layoutMode then
        if db.fade == "combat" and UnitAffectingCombat("player") then a = db.fadePct / 100 end
        if db.fade == "idle" and not panel:IsMouseOver() then a = db.fadePct / 100 end
    end
    holder:SetAlpha(a)
end

-- full rebuild (out of combat only)
local function Build(groups, total, elsewhere, logCount)
    used.zone, used.quest, used.line, used.item = 0, 0, 0, 0
    local w = db.width
    local inner = w - PAD * 2
    local y = -4

    head.title:SetText("QUESTS")
    local maxQ = MaxQuests()
    head.count:SetText(maxQ and (logCount .. "/" .. maxQ) or tostring(logCount))
    wipe(shownZones)
    if db.group then for _, g in ipairs(groups) do if g.zone then shownZones[#shownZones + 1] = g.zone end end end
    head.fold:SetShown(#shownZones > 0)
    PaintHeader()
    y = y - 22

    local limit = db.maxHeight - 10
    local more = 0
    local function Room(h) return -(y - h) <= limit end

    if not db.allCollapsed then
        for _, g in ipairs(groups) do
            local collapsed = g.zone and db.collapsed[g.zone]
            if g.zone and db.group then
                if not Room(18) then more = more + #g.quests else
                    used.zone = used.zone + 1
                    local r = ZoneRow(used.zone)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y - 2)
                    r:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y - 2)
                    r.zoneName = g.zone
                    r.name:SetText(g.zone:upper())
                    r.sign:SetText(collapsed and "+" or "-")
                    r.num:SetText(#g.quests)
                    r.line:SetVertexColor(T.line[1] * 1.6, T.line[2] * 1.6, T.line[3] * 1.6, 1)
                    r.Paint = function(self)
                        local c = g.here and T.accent or { T.accent[1] * 0.72, T.accent[2] * 0.72, T.accent[3] * 0.72 }
                        self.name:SetTextColor(c[1], c[2], c[3])
                    end
                    r:Paint()
                    r:SetScript("OnClick", function(self)
                        db.collapsed[self.zoneName] = not db.collapsed[self.zoneName] or nil
                        CUI.QuestTracker.Refresh()
                    end)
                    r:Show()
                    y = y - 20
                end
            end
            if not collapsed then
                for _, q in ipairs(g.quests) do
                    local titleH = db.titleSize + 4
                    if not Room(titleH + db.lineSize + 2) then more = more + 1 else
                        used.quest = used.quest + 1
                        local r = QuestRow(used.quest)
                        r.questID, r.zone = q.id, g.zone
                        r:ClearAllPoints()
                        r:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, y)
                        r:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
                        r:SetHeight(titleH)
                        Font(r.title, db.titleSize)
                        r.title:SetWidth(inner - 4)
                        local title = q.title or C_QuestLog.GetTitleForQuestID(q.id) or "?"
                        if db.level and q.level and q.level > 0 then title = "[" .. q.level .. "] " .. title end
                        r.title:SetText(title)
                        r.title:SetTextColor(TitleColor(q.level, q.done, q.watched))
                        local focused = C_SuperTrack.GetSuperTrackedQuestID() == q.id
                        r.focus:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
                        r.focus:SetShown(focused)
                        r:Show()

                        -- quest item, left of the title, outside the panel
                        local logIndex = C_QuestLog.GetLogIndexForQuestID(q.id)
                        if db.items and logIndex and GetQuestLogSpecialItemInfo then
                            local okI, link, tex, charges, showDone = pcall(GetQuestLogSpecialItemInfo, logIndex)
                            if okI and link and (not q.done or showDone) then
                                used.item = used.item + 1
                                local b = ItemButton(used.item)
                                b.link = link
                                b.itemID = tonumber(link:match("item:(%d+)"))
                                b:SetAttribute("item", b.itemID and ("item:" .. b.itemID) or link)
                                b.icon:SetTexture(tex)
                                b.count:SetText((type(charges) == "number" and charges > 1) and charges or "")
                                b:ClearAllPoints()
                                b:SetPoint("TOPRIGHT", content, "TOPLEFT", -4, y + 2)
                                b:Show()
                                ItemCooldown(b)
                            end
                        end
                        y = y - titleH

                        local lines = 0
                        if q.done then
                            used.line = used.line + 1
                            local lr = LineRow(used.line)
                            lr:ClearAllPoints()
                            lr:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4 + INDENT, y)
                            lr:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
                            local h = ReadyLine(lr)
                            lr:SetHeight(h)
                            lr:Show()
                            y = y - h
                        else
                            for _, o in ipairs(q.objs) do
                                if not (db.hideDone and o.finished) and Room(db.lineSize + 2) then
                                    used.line = used.line + 1
                                    local lr = LineRow(used.line)
                                    lr:ClearAllPoints()
                                    lr:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4 + INDENT, y)
                                    lr:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
                                    local h = FillLine(lr, o, q, inner - 4 - INDENT)
                                    lr:SetHeight(h)
                                    lr:Show()
                                    y = y - h
                                    lines = lines + 1
                                end
                            end
                        end
                        y = y - 5
                    end
                end
            end
        end

        -- nothing here: say so, and how many wait in other zones
        if (#groups == 0 or more > 0 or (db.zoneOnly and elsewhere > 0)) then
            used.line = used.line + 1
            local lr = LineRow(used.line)
            lr:ClearAllPoints()
            lr:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, y - 2)
            lr:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y - 2)
            Font(lr.dash, 10); Font(lr.text, 10); Font(lr.num, 10)
            lr.dash:SetText("")
            lr.num:SetText("")
            lr.text:SetWidth(inner - 4)
            lr.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
            local msg
            if more > 0 then msg = "+" .. more .. " more (raise Max height on the settings page)"
            elseif #groups == 0 and db.zoneOnly then
                local zn = (GetRealZoneText and GetRealZoneText()) or ""
                if type(zn) ~= "string" or zn == "" then zn = "this zone" end
                msg = "No tracked quests in " .. zn .. "." .. (elsewhere > 0 and (" " .. elsewhere .. " in other zones - click Zone to see them.") or "")
            elseif db.zoneOnly then msg = elsewhere .. " more in other zones"
            else msg = "No quests tracked. Shift-click a quest in the quest log to track it." end
            lr.text:SetText(msg)
            local h = lr.text:GetStringHeight() + 4
            lr:SetHeight(h)
            lr:Show()
            y = y - h
        end
    end

    -- free what is left over
    for i = used.zone + 1, #zoneRows do zoneRows[i]:Hide() end
    for i = used.quest + 1, #questRows do questRows[i]:Hide(); questRows[i].questID = nil end
    for i = used.line + 1, #lineRows do lineRows[i]:Hide() end
    for i = used.item + 1, #itemButtons do itemButtons[i]:Hide(); itemButtons[i].itemID = nil end

    local h = -y + 4
    content:SetHeight(h)
    panel:SetHeight(h)
    panel.bg:SetShown(db.bg)
    W.ShowBorder(panel.edges, db.bg)
    holder:SetShown(Visible(groups))
    shape = Shape(groups)
    dirty = false
    Fade()
end

-- in combat: repaint numbers and colors on what is already there; anything bigger waits for the fight to end
local function Repaint(groups)
    local li, qi = 0, 0
    for _, g in ipairs(groups) do
        if not (g.zone and db.group and db.collapsed[g.zone]) and not db.allCollapsed then
            for _, q in ipairs(g.quests) do
                qi = qi + 1
                local r = questRows[qi]
                if r and r.questID == q.id then
                    r.title:SetTextColor(TitleColor(q.level, q.done, q.watched))
                    r.focus:SetShown(C_SuperTrack.GetSuperTrackedQuestID() == q.id)
                end
                if q.done then
                    li = li + 1
                    if lineRows[li] then ReadyLine(lineRows[li]) end
                else
                    for _, o in ipairs(q.objs) do
                        if not (db.hideDone and o.finished) then
                            li = li + 1
                            local lr = lineRows[li]
                            if lr and lr:IsShown() then FillLine(lr, o, q, db.width - PAD * 2 - 4 - INDENT) end
                        end
                    end
                end
            end
        end
    end
end

local function Refresh()
    local groups, total, elsewhere, logCount = Collect()
    Sounds(groups)
    if InCombatLockdown() then
        if Shape(groups) == shape then Repaint(groups) else dirty = true; Repaint(groups) end
        return
    end
    holder:SetSize(db.width, db.maxHeight)
    local ok, err = pcall(Build, groups, total, elsewhere, logCount)
    if not ok then
        for i = used.zone + 1, #zoneRows do zoneRows[i]:Hide() end
        for i = used.quest + 1, #questRows do questRows[i]:Hide() end
        for i = used.line + 1, #lineRows do lineRows[i]:Hide() end
        geterrorhandler()(err)
    end
end

local pending = false
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; Refresh() end)
end

CUI.QuestTracker = { Refresh = function() Later() end }

head:SetScript("OnClick", function() db.allCollapsed = not db.allCollapsed; Later() end)
head.fold:SetScript("OnClick", function()
    local fold = AnyZoneOpen()
    for _, z in ipairs(shownZones) do db.collapsed[z] = fold or nil end
    Later()
end)
head.zone:SetScript("OnClick", function() db.zoneOnly = not db.zoneOnly; Later() end)

--------------------------------------------------------------------------------
-- The game's tracker: faded and deaf while ours is on (alpha and mouse only)
--------------------------------------------------------------------------------
local deafened = setmetatable({}, { __mode = "k" })
local guard = false
local function Deafen(frame, depth)
    if depth > 8 or not frame then return end
    local okP, prot = pcall(frame.IsProtected, frame)
    if not (okP and prot) then
        local okM, on = pcall(frame.IsMouseEnabled, frame)
        if okM and on == true then
            pcall(frame.EnableMouse, frame, false)
            deafened[frame] = true
        end
    end
    local okC, kids = pcall(function() return { frame:GetChildren() } end)
    if okC then for _, k in ipairs(kids) do Deafen(k, depth + 1) end end
end

local deafPending = false
local function FadeGame()
    local ot = _G.ObjectiveTrackerFrame
    if not ot then return end
    if db.hideGame then
        guard = true; ot:SetAlpha(0); guard = false
        if not InCombatLockdown() and not deafPending then
            deafPending = true
            C_Timer.After(0, function() deafPending = false; if db.hideGame and not InCombatLockdown() then Deafen(ot, 0) end end)
        end
    else
        guard = true; ot:SetAlpha(1); guard = false
        if not InCombatLockdown() then
            for f in pairs(deafened) do pcall(f.EnableMouse, f, true) end
            wipe(deafened)
        end
    end
end

local gameHooked = false
local function HookGame()
    local ot = _G.ObjectiveTrackerFrame
    if gameHooked or not ot then return end
    gameHooked = true
    hooksecurefunc(ot, "SetAlpha", function(_, a)
        if guard or not db.hideGame or Secret(a) then return end
        if type(a) == "number" and a > 0 then guard = true; ot:SetAlpha(0); guard = false end
    end)
    ot:HookScript("OnShow", FadeGame)
    if type(ot.Update) == "function" then hooksecurefunc(ot, "Update", FadeGame) end
    FadeGame()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local fadeTicker
local function UpdateFadeTicker()
    if db.fade == "idle" and not fadeTicker then
        fadeTicker = C_Timer.NewTicker(0.2, Fade)
    elseif db.fade ~= "idle" and fadeTicker then
        fadeTicker:Cancel(); fadeTicker = nil
    end
    Fade()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED",
    "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "SUPER_TRACKING_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "BAG_UPDATE_COOLDOWN", "ADDON_LOADED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_ObjectiveTracker" then HookGame() end
        return
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(itemButtons) do ItemCooldown(b) end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        Fade()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        Fade()
        FadeGame()
        if dirty then Refresh() end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookGame()
        C_Timer.After(1, Refresh)
    end
    Later()
end)

if type(CUI.SetLayoutMode) == "function" then hooksecurefunc(CUI, "SetLayoutMode", function() Later() end) end
HookGame()
UpdateFadeTicker()
Later()

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
local function Apply() FadeGame(); UpdateFadeTicker(); Later() end

CUI:RegisterPage("Quest Tracker", function(page)
    local width = 480
    W.Header(page, "Quest Tracker", width):SetPoint("TOPLEFT", 0, -4)
    local y = -34
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, y)
    intro:SetWidth(width - 8)
    intro:SetJustifyH("LEFT")
    intro:SetText("Your tracked quests grouped by zone, the zone you are in first. Move it in Layout mode (Quest Tracker).")
    y = y - 34

    local function Check(text, key)
        W.Checkbox(page, text, function() return db[key] end, function(on) db[key] = on; Apply() end):SetPoint("TOPLEFT", 4, y)
        y = y - 26
    end
    local function Step(text, key, lo, hi, step, suffix)
        W.Stepper(page, text, function() return db[key] end, function(v) db[key] = v; Apply() end, lo, hi, step, suffix)
            :SetPoint("TOPLEFT", 4, y)
        y = y - 28
    end
    local function Pick(text, key, options)
        local lab = W.Text(page, 12, T.accent)
        lab:SetPoint("TOPLEFT", 4, y - 4)
        lab:SetText(text)
        W.Dropdown(page, 230, options, function() return db[key] end, function(v) db[key] = v; Apply() end):SetPoint("TOPLEFT", 150, y)
        y = y - 32
    end

    Check("Group quests under a header per zone", "group")
    Check("This zone only (also the Zone button on the tracker)", "zoneOnly")
    Check("Also list untracked quests from the zone you are in", "alsoZone")
    Check("Show the quest level before the name", "level")
    Check("Hide objectives that are done", "hideDone")
    Check("Play a sound when a quest is ready to turn in", "sound")
    Check("Quest item buttons beside their quest", "items")
    Check("Dark background with the border color", "bg")
    Check("Hide in raids", "hideRaid")
    Check("Hide the game's own quest tracker", "hideGame")
    y = y - 6
    Pick("Fade", "fade", { { "none", "never" }, { "combat", "in combat" }, { "idle", "when the mouse is away" } })
    Step("Faded opacity", "fadePct", 10, 90, 5, "%")
    Step("Width", "width", 180, 420, 10, " px")
    Step("Max height", "maxHeight", 150, 900, 10, " px")
    Step("Quest name size", "titleSize", 9, 16, 1)
    Step("Objective size", "lineSize", 8, 15, 1)
    y = y - 6

    local note = W.Notes(page, 4, y, width, "", {
        { "Click", "a quest to open it in the quest log; Shift-click stops tracking it; right-click to focus, share or untrack." },
        { "Zone headers", "collapse when clicked; click the QUESTS header to fold the whole list." },
        { "In combat", "numbers keep updating; a quest added or removed mid-fight shows when the fight ends." },
        "It reads the game's own tracked quests, so tracking from the quest log or map shows up here.",
    })
    y = y - ((note and note.GetHeight and note:GetHeight() or 80) + 12)
    page.contentHeight = -y + 20
end, function() end)

    end,
})
