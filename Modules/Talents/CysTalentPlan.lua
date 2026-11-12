--------------------------------------------------------------------------------
-- Cys's UI - Talent Planner (WoW Forever)
--
-- A planner mode inside the talents window (Planner button next to Primary / Secondary) where you plan your whole leveling path: click a talent to add its
-- next point, right-click to take one off. The Level plan underneath lists every pick with the level it
-- comes at (the first talent point arrives at level 10, then one per level). With "Learn these talents as
-- I level" on, each new point is learned for you as you level (out of combat; in a fight it waits).
--
-- Forever's talents are the game's trait system: one tree with three groups (the three specs). The plan is
-- a list of node IDs in the order the points go in. Our window only reads the tree; the talents window
-- itself is used as an anchor and never changed.
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "talentplan", name = "Talent Planner", foreverOnly = true,
    desc = "WoW Forever: plan your leveling talents in a window beside the talents window, see the level each pick comes at, and have them learned for you as you level.",
    open = function() CysUI:OpenConfig("Talent Planner") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T

CysUICharDB = CysUICharDB or {}
CysUICharDB.talentPlan = CysUICharDB.talentPlan or {}
local plan = CysUICharDB.talentPlan
plan.points = plan.points or {} -- node IDs in the order the points go in
if plan.auto == nil then plan.auto = false end
if plan.open == nil then plan.open = true end

local _, CLASS = UnitClass("player")
CysUIDB.talentPlans = CysUIDB.talentPlans or {}
CysUIDB.talentPlans[CLASS] = CysUIDB.talentPlans[CLASS] or {}
local saved = CysUIDB.talentPlans[CLASS] -- [name] = { node IDs }

local FIRST_LEVEL = 10 -- the first talent point
local LINE_H = 18
local WIN_W = 300 -- width used by the Save / Load / Export box

local TP = {}
CUI.TalentPlan = TP

local Tree           -- built from the game's data, see Build
local win, opener    -- our frames
local Paint, Learn, Sync -- defined below

--------------------------------------------------------------------------------
-- Reading the tree
--------------------------------------------------------------------------------
local function ConfigID()
    return C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
end

-- Positions to grid steps: values a few units apart are the same row / column; the step is the smallest
-- gap between those groups (so an empty tier still counts as a tier)
local function Grid(values)
    local l = {}
    for v in pairs(values) do l[#l + 1] = v end
    table.sort(l)
    local maxGap = 0
    for i = 2, #l do maxGap = math.max(maxGap, l[i] - l[i - 1]) end
    local tol = maxGap * 0.35
    local centers, of = {}, {}
    local cur, sum, n = nil, 0, 0
    local members = {}
    local function Close()
        if cur then
            local c = sum / n
            centers[#centers + 1] = c
            for _, v in ipairs(members) do of[v] = c end
        end
    end
    for _, v in ipairs(l) do
        if cur and v - cur <= tol then
            sum, n = sum + v, n + 1
            members[#members + 1] = v
        else
            Close()
            cur, sum, n, members = v, v, 1, { v }
        end
    end
    Close()
    local step
    for i = 2, #centers do
        local d = centers[i] - centers[i - 1]
        if d > 0 and (not step or d < step) then step = d end
    end
    step = step or 1
    local c0 = centers[1] or 0
    return function(v) return math.floor(((of[v] or v) - c0) / step + 0.5) end
end

local function Build()
    local configID = ConfigID()
    if not configID then return nil end
    local ci = C_Traits.GetConfigInfo(configID)
    local treeID = ci and ci.treeIDs and ci.treeIDs[1]
    if not treeID then return nil end
    local groups, byGroup = {}, {}
    for _, d in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
        local g = { id = d.groupID, name = d.displayName, icon = d.icon, order = d.orderIndex or 0, nodes = {} }
        groups[#groups + 1] = g
        byGroup[d.groupID] = g
    end
    table.sort(groups, function(a, b) return a.order < b.order end)
    local nodes = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.isVisible and (info.maxRanks or 0) > 0 then
            local g
            for _, gid in ipairs(info.groupIDs or {}) do
                if byGroup[gid] then g = byGroup[gid]; break end
            end
            if g then
                local entryID = info.entryIDs and info.entryIDs[1]
                local e = entryID and C_Traits.GetEntryInfo(configID, entryID)
                local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                local spellID = def and (def.spellID or def.overriddenSpellID)
                local n = {
                    id = nodeID, group = g, x = info.posX, y = info.posY, max = info.maxRanks, spellID = spellID,
                    name = (def and def.overrideName) or (spellID and C_Spell.GetSpellName(spellID)) or "?",
                    icon = (def and def.overrideIcon) or (spellID and C_Spell.GetSpellTexture(spellID)) or 134400,
                    prereq = {}, edges = info.visibleEdges,
                }
                nodes[nodeID] = n
                g.nodes[#g.nodes + 1] = n
            end
        end
    end
    -- arrows: an edge from A to B means B needs A filled first
    for id, n in pairs(nodes) do
        for _, e in ipairs(n.edges or {}) do
            local t = nodes[e.targetNode]
            if t then t.prereq[#t.prereq + 1] = id end
        end
        n.edges = nil
    end
    -- grid positions per group (row = tier: 5 points in that tree per tier, like Classic)
    for _, g in ipairs(groups) do
        local xs, ys = {}, {}
        for _, n in ipairs(g.nodes) do xs[n.x] = true; ys[n.y] = true end
        local ColOf, RowOf = Grid(xs), Grid(ys)
        g.cols, g.rows = 1, 1
        for _, n in ipairs(g.nodes) do
            n.col = ColOf(n.x)
            n.row = RowOf(n.y)
            g.cols = math.max(g.cols, n.col + 1)
            g.rows = math.max(g.rows, n.row + 1)
        end
    end
    return { configID = configID, treeID = treeID, groups = groups, nodes = nodes }
end

local function Ensure()
    local cfg = ConfigID()
    if not Tree or Tree.configID ~= cfg then
        local ok, t = pcall(Build)
        Tree = ok and t or nil
        if TP.OnTreeBuilt then TP.OnTreeBuilt() end
    end
    return Tree
end

local function Learned(id)
    local info = Tree and C_Traits.GetNodeInfo(Tree.configID, id)
    return info and info.ranksPurchased or 0
end

-- Walk the plan in order with Classic's rules: ranks up to the max, 5 points in the tree per tier,
-- arrows need the talent they come from filled. Returns count[node], spent[group], bad[index], level[index]
local function Simulate(points)
    local count, spent, bad, level = {}, {}, {}, {}
    local valid = 0
    for i, id in ipairs(points) do
        local n = Tree and Tree.nodes[id]
        local ok = n ~= nil
        if ok and (count[id] or 0) >= n.max then ok = false end
        if ok and (spent[n.group] or 0) < 5 * n.row then ok = false end
        if ok then
            for _, p in ipairs(n.prereq) do
                local pn = Tree.nodes[p]
                if pn and (count[p] or 0) < pn.max then ok = false; break end
            end
        end
        if ok then
            count[id] = (count[id] or 0) + 1
            spent[n.group] = (spent[n.group] or 0) + 1
            valid = valid + 1
            level[i] = FIRST_LEVEL + valid - 1
        else
            bad[i] = true
        end
    end
    return count, spent, bad, level, valid
end

-- Why a talent can't take another planned point (nil = it can)
local function CanAdd(n)
    local test = {}
    for i, id in ipairs(plan.points) do test[i] = id end
    test[#test + 1] = n.id
    local count, spent, bad = Simulate(test)
    if not bad[#test] then return nil end
    if (count[n.id] or 0) >= n.max then return "Already planned to its last rank." end
    if (spent[n.group] or 0) < 5 * n.row then
        return ("Needs %d points in %s first (planned: %d)."):format(5 * n.row, n.group.name, spent[n.group] or 0)
    end
    for _, p in ipairs(n.prereq) do
        local pn = Tree.nodes[p]
        if pn and (count[p] or 0) < pn.max then return "Needs " .. pn.name .. " filled first." end
    end
    return "Can't be planned yet."
end

function TP.Add(id)
    local n = Tree and Tree.nodes[id]
    if not n then return end
    local why = CanAdd(n)
    if why then
        TP.status = "|cffff6060" .. why .. "|r"
    else
        plan.points[#plan.points + 1] = id
        TP.status = nil
    end
    Paint()
end

-- take off the last planned point of a talent
function TP.Remove(id)
    for i = #plan.points, 1, -1 do
        if plan.points[i] == id then
            table.remove(plan.points, i)
            break
        end
    end
    TP.status = nil
    Paint()
end

-- Plan from what you have learned now: every rank, tree by tree, tier by tier
function TP.FromCurrent()
    if not Ensure() then return end
    local list = {}
    for _, g in ipairs(Tree.groups) do
        local sorted = {}
        for _, n in ipairs(g.nodes) do sorted[#sorted + 1] = n end
        table.sort(sorted, function(a, b) if a.row ~= b.row then return a.row < b.row end return a.col < b.col end)
        for _, n in ipairs(sorted) do
            for _ = 1, Learned(n.id) do list[#list + 1] = n.id end
        end
    end
    plan.points = list
    TP.status = "Plan started from the talents you have now (" .. #list .. " points). Add the rest."
    Paint()
end

--------------------------------------------------------------------------------
-- Learning as you level
--------------------------------------------------------------------------------
local waitCombat, learnQueued = false, false

local function Unspent()
    local ok, info = pcall(C_Traits.GetTreeCurrencyInfo, Tree.configID, Tree.treeID, false)
    local c = ok and info and info[1]
    if c and c.quantity then return c.quantity end
    return 99 -- unknown: let the game decide
end

-- manual = the Learn now button
function Learn(manual)
    if not plan.auto and not manual then return end
    if #plan.points == 0 then return end
    if InCombatLockdown() then
        waitCombat = true
        if manual then CUI:Print("Talent Planner: the next talents are learned when the fight ends.") end
        return
    end
    if not Ensure() then return end
    local cfg = Tree.configID
    if C_ClassTalents.CanChangeTalents then
        local can = C_ClassTalents.CanChangeTalents()
        if not can then return end
    end
    if C_Traits.ConfigHasStagedChanges(cfg) then
        if manual then CUI:Print("Talent Planner: apply or undo the changes in the talents window first.") end
        return
    end
    local free = Unspent()
    if free <= 0 then return end
    local _, _, bad = Simulate(plan.points)
    local have, seen, bought = {}, {}, {}
    for i, id in ipairs(plan.points) do
        if not bad[i] then
            if have[id] == nil then have[id] = Learned(id) end
            seen[id] = (seen[id] or 0) + 1
            if have[id] < seen[id] then
                if free <= 0 then break end
                if not C_Traits.PurchaseRank(cfg, id) then break end -- keep the order: stop at the first one that can't go in
                have[id] = have[id] + 1
                free = free - 1
                bought[#bought + 1] = Tree.nodes[id].name
            end
        end
    end
    if #bought == 0 then return end
    if C_Traits.CommitConfig(cfg) then
        local merged, times, order = {}, {}, {}
        for _, name in ipairs(bought) do
            if not times[name] then order[#order + 1] = name end
            times[name] = (times[name] or 0) + 1
        end
        for _, name in ipairs(order) do merged[#merged + 1] = times[name] > 1 and (name .. " (" .. times[name] .. ")") or name end
        CUI:Print("Talent Planner: learned " .. table.concat(merged, ", ") .. ".")
    else
        C_Traits.RollbackConfig(cfg)
        CUI:Print("Talent Planner: the game did not let the planned talents be learned right now.")
    end
end

local function QueueLearn(delay)
    if learnQueued then return end
    learnQueued = true
    C_Timer.After(delay or 1, function()
        learnQueued = false
        local ok, err = pcall(Learn, false)
        if not ok and CUI.debug then CUI:Print("Talent Planner: " .. tostring(err)) end
        if win and win:IsShown() then Paint() end
    end)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local buttons, lines = {}, {}
local listOff = 0
local treeFrames = {}
local numLines = 0
local SIDE_W = 300

local function Tip(owner, n, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if n.spellID then GameTooltip:SetSpellByID(n.spellID) else GameTooltip:SetText(n.name) end
    if extra then for _, l in ipairs(extra) do GameTooltip:AddLine(l, 1, 0.82, 0) end end
    GameTooltip:Show()
end

-- Trees fill the left part of the planner; icon size follows the space
local function LayoutTrees()
    if not (Tree and win) then return end
    for _, b in pairs(buttons) do b:Hide() end
    for _, tf in ipairs(treeFrames) do tf:Hide() end
    local areaW = win.trees:GetWidth()
    local areaH = win.trees:GetHeight()
    if not areaW or areaW < 100 then return end
    local nG = math.max(1, #Tree.groups)
    local rows, cols = 1, 1
    for _, g in ipairs(Tree.groups) do rows = math.max(rows, g.rows); cols = math.max(cols, g.cols) end
    local treeW = math.floor((areaW - (nG - 1) * 12) / nG)
    local pitch = math.floor(math.min((treeW - 24) / cols, (areaH - 56) / rows, 66))
    local icon = math.floor(pitch * 0.72)
    for gi, g in ipairs(Tree.groups) do
        local tf = treeFrames[gi]
        if not tf then
            tf = CreateFrame("Frame", nil, win.trees)
            tf.bg = tf:CreateTexture(nil, "BACKGROUND", nil, 4)
            tf.bg:SetAllPoints()
            tf.bg:SetColorTexture(0, 0, 0, 0.18) -- see-through: the class artwork shows behind
            W.Border(tf, 1, T.line)
            tf.icon = tf:CreateTexture(nil, "ARTWORK")
            tf.icon:SetSize(30, 30)
            tf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tf.name = W.Text(tf, 15, T.text)
            tf.name:SetShadowOffset(1, -1)
            tf.name:SetShadowColor(0, 0, 0, 1)
            tf.name:SetPoint("LEFT", tf.icon, "RIGHT", 6, 0)
            tf.lines = {}
            treeFrames[gi] = tf
        end
        tf:SetSize(treeW, areaH)
        tf:ClearAllPoints()
        tf:SetPoint("TOPLEFT", win.trees, "TOPLEFT", (gi - 1) * (treeW + 12), 0)
        tf.icon:SetTexture(g.icon)
        tf.icon:ClearAllPoints()
        tf.icon:SetPoint("TOP", tf, "TOP", -50, -12)
        tf.group = g
        tf:Show()
        -- center the grid in the tree
        local gridW = g.cols * pitch
        local ox = math.floor((treeW - gridW) / 2 + (pitch - icon) / 2)
        -- and vertically in the space under the header, so the card has no empty band at the bottom
        local free = (areaH - 56) - (g.rows * pitch - (pitch - icon))
        local oy = -56 - math.max(0, math.floor(free / 2 - 8))
        for _, ln in ipairs(tf.lines) do ln:Hide() end
        local li = 0
        for _, n in ipairs(g.nodes) do
            local b = buttons[n.id]
            if not b then
                b = CreateFrame("Button", nil, win.trees)
                b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetPoint("TOPLEFT", 1, -1)
                b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.edges = W.Border(b, 1, T.line, "OVERLAY")
                b.rankBg = W.Texture(b, "OVERLAY", { 0, 0, 0, 0.75 }, 1)
                b.rankBg:SetSize(16, 13)
                b.rankBg:SetPoint("BOTTOMRIGHT", 3, -3)
                b.rank = W.Text(b, 10, T.accent, "CENTER")
                b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)
                b:SetScript("OnClick", function(s, btn)
                    if btn == "RightButton" then TP.Remove(s.node.id) else TP.Add(s.node.id) end
                end)
                b:SetScript("OnEnter", function(s)
                    local n = s.node
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    if n.spellID then GameTooltip:SetSpellByID(n.spellID) else GameTooltip:SetText(n.name) end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(("Rank %d/%d"):format(Learned(n.id), n.max), 1, 0.62, 0.29)
                    GameTooltip:AddLine(("Planned %d/%d"):format(s.planned or 0, n.max), 1, 0.82, 0)
                    local why = (s.planned or 0) < n.max and CanAdd(n) or nil
                    if why then GameTooltip:AddLine(why, 1, 0.25, 0.25, true) end
                    GameTooltip:AddLine("Click: plan the next point.  Right-click: take one off.", 0.6, 0.6, 0.6, true)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                buttons[n.id] = b
            end
            b.node = n
            b:SetParent(tf)
            b:SetSize(icon, icon)
            b.icon:SetTexture(n.icon)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", tf, "TOPLEFT", ox + n.col * pitch, oy - n.row * pitch)
            b:Show()
            for _, p in ipairs(n.prereq) do
                local pn = Tree.nodes[p]
                if pn and pn.col == n.col and pn.row < n.row then
                    li = li + 1
                    local ln = tf.lines[li]
                    if not ln then ln = W.Texture(tf, "ARTWORK", { 0.85, 0.68, 0.25, 0.75 }); tf.lines[li] = ln end -- arrows in soft gold
                    ln:ClearAllPoints()
                    ln:SetWidth(2)
                    ln:SetPoint("TOP", tf, "TOPLEFT", ox + pn.col * pitch + icon / 2, oy - pn.row * pitch - icon)
                    ln:SetPoint("BOTTOM", tf, "TOPLEFT", ox + n.col * pitch + icon / 2, oy - n.row * pitch)
                    ln:Show()
                end
            end
        end
    end
end
TP.OnTreeBuilt = function() if win and win:IsShown() then LayoutTrees() end end

-- one line per run of picks on the same talent: "26-27  Defiance"
local function PlanLines()
    local _, _, bad, level = Simulate(plan.points)
    local out = {}
    local rankSeen = {}
    for i, id in ipairs(plan.points) do
        rankSeen[id] = (rankSeen[id] or 0) + 1
        local last = out[#out]
        if last and last.id == id and not bad[i] and not last.bad then
            last.to = level[i]
            last.last = i
            last.rankTo = rankSeen[id]
        else
            out[#out + 1] = { id = id, from = level[i], to = level[i], bad = bad[i], first = i, last = i,
                              rankFrom = rankSeen[id], rankTo = rankSeen[id] }
        end
    end
    return out
end

local function MakeLine(i)
    local l = CreateFrame("Button", nil, win.list)
    l:SetHeight(LINE_H)
    l:SetPoint("TOPLEFT", 4, -26 - (i - 1) * LINE_H)
    l:SetPoint("TOPRIGHT", -4, -26 - (i - 1) * LINE_H)
    l:RegisterForClicks("RightButtonUp")
    l.hl = W.Texture(l, "BACKGROUND", T.cardHover)
    l.hl:SetAllPoints()
    l.hl:Hide()
    l.lvl = W.Text(l, 11, T.accent)
    l.lvl:SetPoint("LEFT", 4, 0)
    l.lvl:SetWidth(42)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(15, 15)
    l.icon:SetPoint("LEFT", 48, 0)
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.name = W.Text(l, 11, T.text)
    l.name:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
    l.name:SetWidth(SIDE_W - 110)
    l.name:SetWordWrap(false)
    l.tick = l:CreateTexture(nil, "ARTWORK")
    l.tick:SetSize(14, 14)
    l.tick:SetPoint("RIGHT", -6, 0)
    l.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    l:SetScript("OnEnter", function(s)
        s.hl:Show()
        local n = s.data and Tree and Tree.nodes[s.data.id]
        if n then Tip(s, n, { "|cffffffffRight-click: take its last point off the plan.|r" }) end
    end)
    l:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    l:SetScript("OnClick", function(s)
        local d = s.data
        if not d then return end
        table.remove(plan.points, d.last)
        TP.status = nil
        Paint()
    end)
    return l
end

local function SizeList()
    local h = win.list:GetHeight() or 0
    numLines = math.max(1, math.floor((h - 30) / LINE_H))
    for i = 1, numLines do if not lines[i] then lines[i] = MakeLine(i) end end
    for i = numLines + 1, #lines do lines[i]:Hide() end
end

function Paint()
    if not win or not win:IsShown() then return end
    if not Ensure() then
        win.summary:SetText("Talent data is not ready yet.")
        return
    end
    local count, spent, bad, level, valid = Simulate(plan.points)
    for _, tf in ipairs(treeFrames) do
        if tf:IsShown() and tf.group then
            local pts = spent[tf.group] or 0
            tf.name:SetText(("%s  %s%d|r"):format(tf.group.name, pts > 0 and "|cffff9933" or "|cff8a8a8a", pts))
        end
    end
    for id, b in pairs(buttons) do
        if b:IsShown() then
            local planned = count[id] or 0
            local learned = Learned(id)
            b.planned = planned
            -- like the game's own trees: green = can take a point now, gold = planned, grey = locked
            local open = planned < b.node.max and CanAdd(b.node) == nil
            local shown = math.max(planned, learned)
            local lit = open or shown > 0
            b.icon:SetDesaturated(not lit)
            b.icon:SetAlpha(lit and 1 or 0.45)
            if lit then
                b.rank:SetText(shown .. "")
                b.rankBg:Show()
                if shown >= b.node.max then b.rank:SetTextColor(1, 0.82, 0)
                elseif open then b.rank:SetTextColor(0.31, 0.84, 0.42)
                else b.rank:SetTextColor(1, 0.82, 0) end
            else
                b.rank:SetText("")
                b.rankBg:Hide()
            end
            if planned > 0 then W.SetBorder(b.edges, T.glow)
            elseif open then W.SetBorder(b.edges, { 0.31, 0.84, 0.42, 1 })
            else W.SetBorder(b.edges, T.line) end
        end
    end
    local needs = valid > 0 and (FIRST_LEVEL + valid - 1) or nil
    local learnedTotal = 0
    for id in pairs(Tree.nodes) do learnedTotal = learnedTotal + Learned(id) end
    win.summary:SetText(("Planned |cffffffff%d|r  -  learned |cffffffff%d|r%s"):format(valid, learnedTotal,
        needs and ("  -  needs level |cffffffff" .. needs .. "|r") or ""))
    win.status:SetText(TP.status or "Click a talent to plan its next point. Right-click to take one off.")

    SizeList()
    local data = PlanLines()
    local max = math.max(0, #data - numLines)
    if listOff > max then listOff = max end
    local live = {}
    for i = 1, numLines do
        local l, d = lines[i], data[listOff + i]
        l.data = d
        if d then
            local n = Tree.nodes[d.id]
            l.icon:SetTexture(n and n.icon or 134400)
            if d.bad then
                l.lvl:SetText("|cffff6060--|r")
                l.name:SetText("|cffff6060" .. (n and n.name or "?") .. " (can't go here)|r")
                l.tick:Hide()
            else
                l.lvl:SetText(d.from == d.to and tostring(d.from) or (d.from .. "-" .. d.to))
                local ranks = n and n.max > 1 and (" |cff8a8a8a" .. (d.rankFrom == d.rankTo and d.rankTo or (d.rankFrom .. "-" .. d.rankTo)) .. "/" .. n.max .. "|r") or ""
                l.name:SetText((n and n.name or "?") .. ranks)
                if live[d.id] == nil then live[d.id] = Learned(d.id) end
                l.tick:SetShown(live[d.id] >= d.rankTo)
            end
            l:Show()
        else
            l:Hide()
        end
    end
    if #data == 0 then
        win.listInfo:SetText("")
        win.empty:Show()
    else
        win.empty:Hide()
        win.listInfo:SetText(#data > numLines and ("%d-%d of %d"):format(listOff + 1, math.min(listOff + numLines, #data), #data) or "")
    end
    win.auto:Refresh()
end

local box
local function Box(mode)
    if not box then
        box = CreateFrame("Frame", nil, win)
        box:SetPoint("TOPLEFT", win.list, "TOPLEFT")
        box:SetPoint("BOTTOMRIGHT", win.list, "BOTTOMRIGHT")
        box:SetFrameLevel(win.list:GetFrameLevel() + 20)
        box:EnableMouse(true)
        W.Texture(box, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
        W.Border(box, 1, T.border)
        box.title = W.Text(box, 12, T.accent)
        box.title:SetPoint("TOPLEFT", 10, -10)
        box.note = W.Text(box, 10, T.dim)
        box.note:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
        box.note:SetWidth(WIN_W - 50)
        local sf = CreateFrame("ScrollFrame", nil, box)
        sf:SetPoint("TOPLEFT", 10, -48)
        sf:SetPoint("BOTTOMRIGHT", -10, 40)
        W.Texture(sf, "BACKGROUND", T.field):SetAllPoints()
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont(STANDARD_TEXT_FONT, 11, "")
        eb:SetWidth(WIN_W - 60)
        eb:SetTextInsets(6, 6, 6, 6)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        sf:SetScrollChild(eb)
        box.sf, box.eb = sf, eb
        local nm = CreateFrame("EditBox", nil, box)
        nm:SetSize(WIN_W - 30, 24)
        nm:SetPoint("TOPLEFT", 10, -52)
        nm:SetAutoFocus(false)
        nm:SetFont(STANDARD_TEXT_FONT, 12, "")
        nm:SetTextInsets(6, 6, 0, 0)
        nm:SetMaxLetters(40)
        W.Texture(nm, "BACKGROUND", T.field):SetAllPoints()
        W.Border(nm, 1, T.border)
        nm:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        nm:SetScript("OnEnterPressed", function() box.ok:Click() end)
        box.name = nm
        box.ok = W.Button(box, 100, 22, "OK", true)
        box.ok:SetPoint("BOTTOMRIGHT", -10, 10)
        box.cancel = W.Button(box, 80, 22, "Close")
        box.cancel:SetPoint("RIGHT", box.ok, "LEFT", -6, 0)
        box.cancel:SetScript("OnClick", function() box:Hide() end)
        box.rows = {}
    end
    for _, r in ipairs(box.rows) do r:Hide() end
    -- Save only needs a name: a short box at the top of the list; the others use the whole list area
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", win.list, "TOPLEFT")
    if mode == "save" then
        box:SetPoint("TOPRIGHT", win.list, "TOPRIGHT")
        box:SetHeight(122)
    else
        box:SetPoint("BOTTOMRIGHT", win.list, "BOTTOMRIGHT")
    end
    box.name:Hide()
    box.sf:Show()
    box.ok:Show()
    box.eb:SetText("")
    if mode == "export" then
        box.title:SetText("Export")
        box.note:SetText("Copy this text (Ctrl+C) to share the plan or keep it.")
        box.eb:SetText("CYSTP1:" .. CLASS .. ":" .. table.concat(plan.points, ","))
        box.eb:SetFocus()
        box.eb:HighlightText()
        box.ok:Hide()
    elseif mode == "import" then
        box.title:SetText("Import")
        box.note:SetText("Paste a plan (Ctrl+V) and press OK. It replaces your current plan.")
        box.eb:SetFocus()
        box.ok:SetLabel("Import")
        box.ok:SetScript("OnClick", function()
            local text = (box.eb:GetText() or ""):gsub("%s", "")
            local class, list = text:match("^CYSTP1:(%u+):([%d,]*)$")
            if not class then CUI:Print("Talent Planner: that is not a plan from Cys's UI."); return end
            if class ~= CLASS then CUI:Print("Talent Planner: that plan is for another class (" .. class .. ")."); return end
            local pts = {}
            for id in list:gmatch("%d+") do pts[#pts + 1] = tonumber(id) end
            plan.points = pts
            TP.status = "Plan imported (" .. #pts .. " points)."
            box:Hide()
            Paint()
        end)
    elseif mode == "save" then
        box.title:SetText("Save plan")
        box.note:SetText("Type a name and press Save (or Enter). A plan with the same name is replaced.")
        box.sf:Hide()
        box.name:Show()
        box.name:SetText(plan.name or "")
        box.name:SetFocus()
        box.name:HighlightText()
        box.ok:SetLabel("Save")
        box.ok:SetScript("OnClick", function()
            local name = (box.name:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local copy = {}
            for i, id in ipairs(plan.points) do copy[i] = id end
            saved[name] = copy
            plan.name = name
            TP.status = "Saved as " .. name .. "."
            box:Hide()
            Paint()
        end)
    elseif mode == "load" then
        box.title:SetText("Saved plans")
        box.note:SetText("Your saved plans for this class (shared by all your characters).")
        box.sf:Hide()
        box.ok:Hide()
        local names = {}
        for name in pairs(saved) do names[#names + 1] = name end
        table.sort(names)
        if #names == 0 then box.note:SetText("No saved plans yet. Use Save to keep the current plan.") end
        for i, name in ipairs(names) do
            local r = box.rows[i]
            if not r then
                r = CreateFrame("Frame", nil, box)
                r:SetSize(WIN_W - 40, 22)
                r.label = W.Text(r, 11, T.text)
                r.label:SetPoint("LEFT", 4, 0)
                r.del = W.Button(r, 60, 20, "Delete")
                r.del:SetPoint("RIGHT")
                r.load = W.Button(r, 60, 20, "Load", true)
                r.load:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
                box.rows[i] = r
            end
            r:SetPoint("TOPLEFT", 10, -48 - (i - 1) * 24)
            local split = ""
            if Tree then
                local _, spent = Simulate(saved[name])
                local parts = {}
                for _, g in ipairs(Tree.groups) do parts[#parts + 1] = tostring(spent[g] or 0) end
                split = table.concat(parts, "/")
            else
                split = #saved[name] .. " points"
            end
            r.label:SetText(name .. "  |cff8a8a8a" .. split .. "|r")
            r.load:SetScript("OnClick", function()
                local copy = {}
                for k, id in ipairs(saved[name]) do copy[k] = id end
                plan.points, plan.name = copy, name
                TP.status = "Loaded " .. name .. "."
                box:Hide()
                Paint()
            end)
            r.del:SetScript("OnClick", function(s)
                if s.armed then saved[name] = nil; Box("load") return end
                s.armed = true
                s:SetLabel("Sure?")
                C_Timer.After(3, function() s.armed = nil; s:SetLabel("Delete") end)
            end)
            r:Show()
            if i >= 9 then break end
        end
    end
    box:Show()
end

local function BuildWindow()
    if win then return end
    local host = _G.PlayerSpellsFrame
    win = CreateFrame("Frame", "CysTalentPlanFrame", host)
    win:SetFrameStrata("HIGH") -- over the talent buttons, whatever layers they use
    win:SetFrameLevel(10)
    win:EnableMouse(true)
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function() end)
    W.Texture(win, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    W.Border(win, 1, T.border)

    -- trees: left part, over the game's own class artwork (the same picture the talents window shows)
    win.trees = CreateFrame("Frame", nil, win)
    win.trees:SetPoint("TOPLEFT", 12, -12)
    win.trees:SetPoint("BOTTOMRIGHT", -(SIDE_W + 24), 34)
    win.art = win:CreateTexture(nil, "BACKGROUND", nil, 2)
    win.art:SetAllPoints(win.trees)
    local atlas
    local specVis = _G.SpecializationVisuals
    local classID = select(3, UnitClass("player"))
    if specVis then
        for _, v in pairs(specVis) do
            if v.background and v.background:lower():find(CLASS:lower(), 1, true) then atlas = v.background; break end
        end
    end
    atlas = atlas or ("talent-background-" .. CLASS:lower())
    local okArt = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if okArt then
        win.art:SetAtlas(atlas)
    else
        win.art:SetColorTexture(0, 0, 0, 0)
    end
    -- a soft dark wash at the top so the tree names read well
    win.shade = win:CreateTexture(nil, "BACKGROUND", nil, 3)
    win.shade:SetPoint("TOPLEFT", win.trees, "TOPLEFT")
    win.shade:SetPoint("TOPRIGHT", win.trees, "TOPRIGHT")
    win.shade:SetHeight(60)
    win.shade:SetColorTexture(1, 1, 1, 1)
    if win.shade.SetGradient and CreateColor then
        win.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    else
        win.shade:SetColorTexture(0, 0, 0, 0.3)
    end
    win.status = W.Text(win, 11, T.dim)
    win.status:SetPoint("BOTTOMLEFT", 14, 12)
    win.status:SetPoint("RIGHT", win.trees, "RIGHT", 0, 0)

    -- side: the Level plan
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPRIGHT", -12, -12)
    side:SetPoint("BOTTOMRIGHT", -12, 12)
    side:SetWidth(SIDE_W)
    W.Texture(side, "BACKGROUND", T.card):SetAllPoints()
    W.Border(side, 1, T.line)
    win.side = side

    local title = W.Text(side, 14, T.accent)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("Level plan")
    win.summary = W.Text(side, 10, T.text)
    win.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    win.summary:SetWidth(SIDE_W - 20)
    win.auto = W.Checkbox(side, "Learn these talents as I level",
        function() return plan.auto end,
        function(v) plan.auto = v; if v then QueueLearn(0.2) end end)
    win.auto:SetPoint("TOPLEFT", win.summary, "BOTTOMLEFT", 0, -8)
    local now = W.Button(side, 86, 20, "Learn now")
    now:SetPoint("TOPRIGHT", -10, -8)
    now:SetScript("OnClick", function() Learn(true); C_Timer.After(0.5, Paint) end)
    now:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText("Learn the next planned talents now")
        GameTooltip:AddLine("Uses any talent points you have left.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    now:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win.list = CreateFrame("Frame", nil, side)
    win.list:SetPoint("TOPLEFT", 6, -76)
    win.list:SetPoint("BOTTOMRIGHT", -6, 62)
    W.Texture(win.list, "BACKGROUND", T.field):SetAllPoints()
    win.listInfo = W.Text(win.list, 10, T.dim, "RIGHT")
    win.listInfo:SetPoint("TOPRIGHT", -6, -6)
    local lh = W.Text(win.list, 10, T.dim)
    lh:SetPoint("TOPLEFT", 8, -6)
    lh:SetText("Level   Talent")
    win.empty = W.Text(win.list, 11, T.dim)
    win.empty:SetPoint("TOPLEFT", 10, -30)
    win.empty:SetWidth(SIDE_W - 40)
    win.empty:SetText("No plan yet. Click talents on the left in the order you want them, or use From my talents to start from what you have.")
    win.list:EnableMouseWheel(true)
    win.list:SetScript("OnMouseWheel", function(_, delta)
        listOff = math.max(0, listOff - delta * 3)
        Paint()
    end)

    -- buttons: two rows of three
    local defs = {
        { "From my talents", function(s)
            if #plan.points > 0 and not s.armed then
                s.armed = true; s:SetLabel("Replace plan?")
                C_Timer.After(3, function() s.armed = nil; s:SetLabel("From my talents") end)
                return
            end
            s.armed = nil; s:SetLabel("From my talents")
            TP.FromCurrent()
        end },
        { "Save", function() Box("save") end },
        { "Load", function() Box("load") end },
        { "Export", function() Box("export") end },
        { "Import", function() Box("import") end },
        { "Clear", function(s)
            if not s.armed then
                s.armed = true; s:SetLabel("Sure?")
                C_Timer.After(3, function() s.armed = nil; s:SetLabel("Clear") end)
                return
            end
            s.armed = nil; s:SetLabel("Clear")
            wipe(plan.points)
            plan.name = nil
            TP.status = "Plan cleared."
            Paint()
        end },
    }
    local bw = math.floor((SIDE_W - 12 - 8) / 3)
    for i, d in ipairs(defs) do
        local b = W.Button(side, bw, 22, d[1])
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        b:SetPoint("BOTTOMLEFT", 6 + col * (bw + 4), 32 - row * 26)
        b:SetScript("OnClick", d[2])
    end

    win:SetScript("OnShow", function()
        C_Timer.After(0, function() -- sizes are known after the first layout pass
            if not win:IsShown() then return end
            Tree = nil
            Ensure()
            LayoutTrees()
            Paint()
        end)
    end)
    win:SetScript("OnSizeChanged", function() if win:IsShown() then LayoutTrees(); Paint() end end)
    win:Hide()
end

-- The Planner button sits next to the Primary / Secondary tabs; it switches the talents area to the planner
local talentsUp = false
local function BuildOpener()
    if opener then return end
    local host = _G.PlayerSpellsFrame
    local tal = host.TalentsFrame
    opener = W.Button(tal, 120, 26, "Planner")
    opener:SetFrameStrata("HIGH")
    opener:SetFrameLevel(20)
    if tal.TabSystem then
        opener:SetPoint("LEFT", tal.TabSystem, "RIGHT", 12, 0)
    else
        opener:SetPoint("TOPLEFT", host, "TOPLEFT", 390, -50)
    end
    opener:SetScript("OnClick", function() plan.open = not plan.open; Sync() end)
    opener:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Talent Planner")
        GameTooltip:AddLine("Plan your talents for every level and have them learned as you level. Click again for the normal talents.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    opener:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Sync()
    local host = _G.PlayerSpellsFrame
    if not (talentsUp and host) then
        if win then win:Hide() end
        return
    end
    BuildOpener()
    if plan.open then
        BuildWindow()
        win:ClearAllPoints()
        -- the talents area below the tabs
        win:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -70)
        win:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
        win:Show()
        opener:SetLabel("Planner  |cff4fd66bActive|r")
        W.SetBorder(opener.edges, T.glow)
    else
        if win then win:Hide() end
        opener:SetLabel("Planner")
        W.SetBorder(opener.edges, T.line)
    end
end
TP.Sync = Sync

function TP.Toggle()
    plan.open = not plan.open
    Sync()
    if not talentsUp then CUI:Print("Talent Planner: open your talents (N) to see the planner.") end
end

local hooked
local function Attach()
    if hooked then return end
    local host = _G.PlayerSpellsFrame
    local tal = host and host.TalentsFrame
    if not (tal and tal.HookScript) then return end
    hooked = true
    tal:HookScript("OnShow", function() talentsUp = true; Sync() end)
    tal:HookScript("OnHide", function() talentsUp = false; Sync() end)
    local ok, vis = pcall(function() return tal:IsVisible() and true or false end)
    talentsUp = ok and vis or false
    Sync()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
                     "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED",
                     "CONFIG_COMMIT_FAILED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "Blizzard_PlayerSpells" then Attach() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if waitCombat then waitCombat = false; QueueLearn(1) end
    elseif event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        Tree = nil
        if win and win:IsShown() then Ensure(); LayoutTrees(); Paint() end
        QueueLearn(2)
    elseif event == "CONFIG_COMMIT_FAILED" then
        -- try again a little later (e.g. it was interrupted)
        C_Timer.After(5, function() QueueLearn(0) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        QueueLearn(4)
    else
        QueueLearn(event == "PLAYER_LEVEL_UP" and 1.5 or 1)
    end
end)
Attach()

SLASH_CYSTALENTPLAN1 = "/cuitalents"
SlashCmdList.CYSTALENTPLAN = function() TP.Toggle() end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Talent Planner", function(page)
    local width = 480
    W.Header(page, "Talent Planner", width):SetPoint("TOPLEFT", 0, -4)
    local auto = W.Checkbox(page, "Learn my planned talents as I level",
        function() return plan.auto end, function(v) plan.auto = v; if v then QueueLearn(0.2) end end)
    auto:SetPoint("TOPLEFT", 4, -36)
    local show = W.Checkbox(page, "Open the talents window in planner mode",
        function() return plan.open end, function(v) plan.open = v; Sync() end)
    show:SetPoint("TOPLEFT", 4, -62)
    W.Notes(page, 4, -98, width, "", {
        "Open your talents (N) and click Planner (next to Primary / Secondary): the talents area turns into the planner, and clicking Planner again brings the normal talents back. Click a talent to plan its next point, right-click to take one off. Green means it can take a point now, gold means planned, grey means locked. The Level plan on the right lists every pick with the level it comes at (the first point at level 10, then one per level).",
        "With Learn these talents as I level on, each new point is learned for you when you level up. In a fight it waits until the fight ends. Learn now uses any points you have left.",
        "From my talents starts a plan from what you have learned now. Save and Load keep plans by name for every character of your class (Load shows the points per tree). Export and Import share a plan as text.",
        "A pick that breaks the rules (5 points per tier in that tree, or a talent its arrow comes from not filled yet) shows in red and is skipped until you fix the plan.",
        "/cuitalents switches planner mode on or off.",
    })
end, function() end)

    end,
})
