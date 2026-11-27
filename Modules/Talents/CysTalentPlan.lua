--------------------------------------------------------------------------------
-- Cys's UI - Talent Planner (WoW Forever)
--
-- A planner mode inside the talents window (Planner button next to Primary / Secondary) where you plan your whole leveling path: click a talent to add its
-- next point, right-click to take one off. The Level plan underneath lists every pick with the level it
-- comes at (the first talent point arrives at level 10, then one per level). With "Learn these talents as
-- I level" on, each new point is learned for you as you level, after a Learn / Not now question that names the
-- spec (out of combat; in a fight it waits).
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
local WIN_W = 300 -- width used by the Save / Load / Export box

local TP = {}
CUI.TalentPlan = TP

local Tree           -- built from the game's data, see Build
local win, opener    -- our frames
local Paint, Learn, Sync, QueueLearn -- defined below

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
-- Auto learning asks first (dual spec: the plan could be for the other spec). approved = the player said Learn;
-- declinedKey = "spec:level" the player said Not now to, so it is not asked again until the next level or spec.
local approved, declinedKey, askText = false, nil, nil

local function SpecGroup()
    local ok, g = pcall(function() return GetActiveTalentGroup and GetActiveTalentGroup() end)
    return (ok and type(g) == "number") and g or 1
end
local function AskKey() return SpecGroup() .. ":" .. (UnitLevel("player") or 0) end

-- "Name (2)" style list in the order the points go in
local function Merge(list)
    local times, order, out = {}, {}, {}
    for _, name in ipairs(list) do
        if not times[name] then order[#order + 1] = name end
        times[name] = (times[name] or 0) + 1
    end
    for _, name in ipairs(order) do out[#out + 1] = times[name] > 1 and (name .. " (" .. times[name] .. ")") or name end
    return out
end

StaticPopupDialogs["CYSUI_TALENT_LEARN"] = {
    text = "Talent Planner: learn your planned talents in your %s talents now?\n\n%s",
    button1 = "Learn",
    button2 = "Not now",
    OnAccept = function() approved = true; declinedKey = nil; C_Timer.After(0.1, function() QueueLearn(0) end) end,
    OnCancel = function() approved = false; declinedKey = AskKey() end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}
local function HideAsk()
    askText = nil
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "CYSUI_TALENT_LEARN") end
end

local function Unspent()
    local ok, info = pcall(C_Traits.GetTreeCurrencyInfo, Tree.configID, Tree.treeID, false)
    local c = ok and info and info[1]
    if c and c.quantity then return c.quantity end
    return 99 -- unknown: let the game decide
end

-- manual = the Learn now button; otherwise (as you level) it asks first
function Learn(manual)
    if not plan.auto and not manual and not approved then return end
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
    if not manual and not approved then
        -- what would go in, for the question (nothing is learned yet)
        local have, seen, list = {}, {}, {}
        for i, id in ipairs(plan.points) do
            if not bad[i] then
                if have[id] == nil then have[id] = Learned(id) end
                seen[id] = (seen[id] or 0) + 1
                if have[id] < seen[id] then
                    if #list >= free then break end
                    have[id] = have[id] + 1
                    list[#list + 1] = Tree.nodes[id].name
                end
            end
        end
        if #list == 0 or declinedKey == AskKey() then return end
        local text = table.concat(Merge(list), ", ")
        if askText == text and StaticPopup_Visible and StaticPopup_Visible("CYSUI_TALENT_LEARN") then return end
        HideAsk()
        askText = text
        StaticPopup_Show("CYSUI_TALENT_LEARN", SpecGroup() == 2 and "Secondary" or "Primary", text)
        return
    end
    approved, askText = false, nil
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
        CUI:Print("Talent Planner: learned " .. table.concat(Merge(bought), ", ") .. ".")
    else
        C_Traits.RollbackConfig(cfg)
        CUI:Print("Talent Planner: the game did not let the planned talents be learned right now.")
    end
end

function QueueLearn(delay)
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
-- Looks: the Level plan is a fourth card beside the three trees, on the same class artwork, with its title in
-- the same header band as the tree names. Learned picks fold into one line; the next pick is a gold card.
local buttons, lines = {}, {}
local listOff = 0
local treeFrames = {}
local SIDE_W = 300
local SIDE_MIN = 26    -- the folded Level plan: a thin strip you click to open again
local HEAD_Y = -27     -- middle of the header band (tree icon 30 px tall, 12 px down)
local HEAD_H = 52
if plan.side == nil then plan.side = true end
if plan.showLearned == nil then plan.showLearned = false end

local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREEN = { 0.31, 0.84, 0.42, 1 }
local LEARNED_EDGE = { 0.50, 0.43, 0.28, 1 }
local ITEM_H = { head = 26, done = 20, next = 52, row = 24 }

local function Tip(owner, n, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT") -- the plan sits on the right: keep its tooltips inside the window
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
    local treeW = math.floor((areaW - (nG - 1) * 10) / nG)
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
            -- the tree icon in a gold frame with a thin dark gap, like the talent buttons
            tf.iconRing = CreateFrame("Frame", nil, tf)
            tf.iconRing:SetSize(32, 32)
            W.Texture(tf.iconRing, "BACKGROUND", { 0, 0, 0, 1 }):SetAllPoints()
            W.Border(tf.iconRing, 1, T.border)
            tf.icon = tf.iconRing:CreateTexture(nil, "ARTWORK")
            tf.icon:SetPoint("TOPLEFT", 2, -2)
            tf.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            tf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tf.name = W.Text(tf, 15, T.text)
            tf.name:SetShadowOffset(1, -1)
            tf.name:SetShadowColor(0, 0, 0, 1)
            tf.name:SetPoint("LEFT", tf.iconRing, "RIGHT", 7, 0)
            tf.lines = {}
            treeFrames[gi] = tf
        end
        tf:SetSize(treeW, areaH)
        tf:ClearAllPoints()
        tf:SetPoint("TOPLEFT", win.trees, "TOPLEFT", (gi - 1) * (treeW + 10), 0)
        tf.icon:SetTexture(g.icon)
        tf.iconRing:ClearAllPoints()
        tf.iconRing:SetPoint("TOP", tf, "TOP", -50, -11)
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
                -- the next talent the plan learns: a soft gold glow that breathes
                b.glow = b:CreateTexture(nil, "OVERLAY", nil, 2)
                b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                b.glow:SetBlendMode("ADD")
                b.glow:SetVertexColor(1, 0.82, 0)
                b.glow:SetPoint("CENTER")
                b.glow:Hide()
                b.pulse = b.glow:CreateAnimationGroup()
                b.pulse:SetLooping("BOUNCE")
                local a = b.pulse:CreateAnimation("Alpha")
                a:SetFromAlpha(0.35)
                a:SetToAlpha(1)
                a:SetDuration(0.8)
                if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
                b.rankBg = W.Texture(b, "OVERLAY", { 0, 0, 0, 0.8 }, 3)
                b.rankBg:SetSize(16, 13)
                b.rankBg:SetPoint("BOTTOMRIGHT", 4, -4)
                b.rank = W.Text(b, 10, T.accent, "CENTER")
                b.rank:SetDrawLayer("OVERLAY", 4)
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
            b.glow:SetSize(icon * 1.85, icon * 1.85)
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

-- What the list shows: a "Learned" line (opens to the learned picks), the next pick as a card, then the rest
local function Items()
    local done, todo, live = {}, {}, {}
    for _, d in ipairs(PlanLines()) do
        if live[d.id] == nil then live[d.id] = Learned(d.id) end
        if not d.bad and live[d.id] >= d.rankTo then
            done[#done + 1] = d
        elseif not d.bad and live[d.id] >= d.rankFrom then
            -- part of this run is learned already: show only the rest ("Enrage 4-5/5, levels 55-56")
            local skip = live[d.id] - d.rankFrom + 1
            todo[#todo + 1] = { id = d.id, from = d.from + skip, to = d.to, first = d.first, last = d.last,
                                rankFrom = d.rankFrom + skip, rankTo = d.rankTo }
        else
            todo[#todo + 1] = d
        end
    end
    local items = {}
    if #done > 0 then
        items[1] = { kind = "head", count = #done, from = done[1].from, to = done[#done].to }
        if plan.showLearned then
            for _, d in ipairs(done) do items[#items + 1] = { kind = "done", d = d } end
        end
    end
    local first = true
    for _, d in ipairs(todo) do
        if first and not d.bad then
            items[#items + 1] = { kind = "next", d = d }
            first = false
        else
            items[#items + 1] = { kind = "row", d = d }
        end
    end
    return items
end

local function LevelText(d) return d.from == d.to and tostring(d.from) or (d.from .. "-" .. d.to) end
local function RankText(d, n)
    if not n or n.max <= 1 then return "" end
    return (d.rankFrom == d.rankTo and d.rankTo or (d.rankFrom .. "-" .. d.rankTo)) .. "/" .. n.max
end
local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function MakeLine()
    local l = CreateFrame("Button", nil, win.list)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l.hl = l:CreateTexture(nil, "BACKGROUND", nil, 1)
    l.hl:SetColorTexture(1, 1, 1, 0.05)
    l.hl:SetAllPoints()
    l.hl:Hide()
    -- the Next card: a faint gold fill with a gold edge
    l.card = CreateFrame("Frame", nil, l)
    l.card:SetPoint("TOPLEFT", 8, -4)
    l.card:SetPoint("BOTTOMRIGHT", -8, 4)
    l.card.bg = l.card:CreateTexture(nil, "BACKGROUND")
    l.card.bg:SetAllPoints()
    l.card.bg:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.13)
    W.Border(l.card, 1, T.glow)
    l.sep = l:CreateTexture(nil, "BORDER")
    l.sep:SetColorTexture(1, 1, 1, 0.06)
    l.sep:SetPoint("BOTTOMLEFT", 8, 0)
    l.sep:SetPoint("BOTTOMRIGHT", -8, 0)
    l.sep:SetHeight(1)
    l.tag = W.Text(l, 9, T.brand, "CENTER")
    l.tag:SetText("NEXT")
    l.lvl = W.Text(l, 11, T.accent, "RIGHT")
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.name = W.Text(l, 12, T.text)
    l.name:SetWordWrap(false)
    l.rank = W.Text(l, 11, T.dim, "RIGHT")
    l.tick = l:CreateTexture(nil, "ARTWORK")
    l.tick:SetSize(12, 12)
    l.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    l.pips = {}
    for i = 1, 5 do
        local p = l:CreateTexture(nil, "ARTWORK")
        p:SetSize(8, 8)
        if i == 1 then p:SetPoint("BOTTOMLEFT", l.icon, "BOTTOMRIGHT", 10, 2)
        else p:SetPoint("LEFT", l.pips[i - 1], "RIGHT", 3, 0) end
        l.pips[i] = p
    end
    l:SetScript("OnEnter", function(s)
        s.hl:SetShown(s.item and s.item.kind ~= "next")
        local d = s.item and s.item.d
        local n = d and Tree and Tree.nodes[d.id]
        if n then Tip(s, n, { "|cffffffffRight-click: take its last point off the plan.|r" })
        elseif s.item and s.item.kind == "head" then
            GameTooltip:SetOwner(s, "ANCHOR_LEFT")
            GameTooltip:SetText(plan.showLearned and "Hide the learned picks" or "Show the learned picks")
            GameTooltip:Show()
        end
    end)
    l:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    l:SetScript("OnClick", function(s, btn)
        local it = s.item
        if not it then return end
        if it.kind == "head" then
            plan.showLearned = not plan.showLearned
            listOff = 0
            Paint()
            return
        end
        if btn ~= "RightButton" or not it.d then return end
        table.remove(plan.points, it.d.last)
        TP.status = nil
        Paint()
    end)
    return l
end

local function ShowLine(l, it, y, h)
    l.item = it
    l:SetHeight(h)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    l:SetPoint("TOPRIGHT", 0, -y)
    l.card:Hide(); l.tag:Hide(); l.tick:Hide(); l.icon:Hide(); l.sep:Show()
    for _, p in ipairs(l.pips) do p:Hide() end
    for _, fs in ipairs({ l.lvl, l.name, l.rank }) do fs:ClearAllPoints(); fs:SetText("") end
    l.lvl:SetFont(STANDARD_TEXT_FONT, 11, "")
    l.lvl:SetJustifyH("RIGHT")
    l.lvl:SetWidth(44)
    l.icon:SetAlpha(1)
    local k, d = it.kind, it.d
    local n = d and Tree.nodes[d.id]

    if k == "head" then
        l.lvl:SetJustifyH("LEFT")
        l.lvl:SetWidth(12)
        l.lvl:SetPoint("LEFT", 12, 0)
        l.lvl:SetText(plan.showLearned and "-" or "+")
        Color(l.lvl, T.dim)
        l.tick:SetPoint("LEFT", 26, 0)
        l.tick:Show()
        l.name:SetPoint("LEFT", 44, 0)
        l.name:SetPoint("RIGHT", -10, 0)
        l.name:SetFont(STANDARD_TEXT_FONT, 11, "")
        l.name:SetText(("Learned  -  %d %s, levels %d-%d"):format(it.count, it.count == 1 and "step" or "steps", it.from, it.to))
        Color(l.name, T.dim)
        return
    end

    l.icon:SetTexture(n and n.icon or 134400)
    l.icon:Show()
    l.name:SetFont(STANDARD_TEXT_FONT, k == "done" and 11 or 12, "")

    if k == "next" then
        l.card:Show()
        l.sep:Hide()
        l.tag:SetPoint("TOP", l, "TOPLEFT", 38, -12)
        l.tag:Show()
        l.lvl:SetFont(STANDARD_TEXT_FONT, 14, "")
        l.lvl:SetJustifyH("CENTER")
        l.lvl:SetPoint("TOP", l.tag, "BOTTOM", 0, -2)
        l.lvl:SetWidth(52)
        l.lvl:SetText(LevelText(d))
        Color(l.lvl, T.accent)
        l.icon:SetSize(30, 30)
        l.icon:SetPoint("LEFT", 66, 0)
        l.name:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, 0)
        l.name:SetPoint("RIGHT", -16, 0)
        l.name:SetText(n and n.name or "?")
        Color(l.name, WHITE)
        -- rank pips: learned = solid gold, this pick = soft gold, the rest = empty
        local have = Learned(d.id)
        local last
        if n and n.max <= 5 then
            for i = 1, n.max do
                local p = l.pips[i]
                if i <= have then p:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 1)
                elseif i <= d.rankTo then p:SetColorTexture(T.glow[1], T.glow[2], T.glow[3], 0.35)
                else p:SetColorTexture(0.25, 0.25, 0.25, 1) end
                p:Show()
                last = p
            end
        end
        if last then l.rank:SetPoint("LEFT", last, "RIGHT", 8, 0)
        else l.rank:SetPoint("BOTTOMLEFT", l.icon, "BOTTOMRIGHT", 10, 0) end
        l.rank:SetJustifyH("LEFT")
        l.rank:SetText(RankText(d, n))
        Color(l.rank, T.dim)
        return
    end

    -- "done" (a learned pick, dim) and "row" (still to come)
    local sz = k == "done" and 14 or 18
    l.lvl:SetPoint("LEFT", 8, 0)
    l.icon:SetSize(sz, sz)
    l.icon:SetPoint("LEFT", 62, 0)
    l.name:SetPoint("LEFT", l.icon, "RIGHT", 8, 0)
    l.name:SetPoint("RIGHT", -56, 0)
    l.rank:SetJustifyH("RIGHT")
    l.rank:SetPoint("RIGHT", -14, 0)
    l.rank:SetText(RankText(d, n))
    Color(l.rank, T.dim)
    if k == "done" then
        l.lvl:SetText(LevelText(d))
        Color(l.lvl, T.dim)
        l.icon:SetAlpha(0.55)
        l.name:SetText(n and n.name or "?")
        Color(l.name, T.dim)
    elseif d.bad then
        l.lvl:SetText("--")
        Color(l.lvl, T.danger)
        l.name:SetText((n and n.name or "?") .. " (can't go here)")
        Color(l.name, T.danger)
    else
        l.lvl:SetText(LevelText(d))
        Color(l.lvl, T.accent)
        l.name:SetText(n and n.name or "?")
        Color(l.name, T.text)
    end
end

function Paint()
    if not win or not win:IsShown() then return end
    if not Ensure() then
        win.summary:SetText("Talent data is not ready yet.")
        return
    end
    local count, spent, bad, _, valid = Simulate(plan.points)

    -- the next point the plan learns (it glows on the tree)
    local nextId
    do
        local have, seen = {}, {}
        for i, id in ipairs(plan.points) do
            if not bad[i] then
                if have[id] == nil then have[id] = Learned(id) end
                seen[id] = (seen[id] or 0) + 1
                if have[id] < seen[id] then nextId = id; break end
            end
        end
    end
    local learnedBy, inPlan = {}, 0
    for id, n in pairs(Tree.nodes) do
        local l = Learned(id)
        learnedBy[n.group] = (learnedBy[n.group] or 0) + l
        inPlan = inPlan + math.min(l, count[id] or 0)
    end

    -- tree headers: "Fury  19 -> 28" (learned, then where the plan takes it)
    for _, tf in ipairs(treeFrames) do
        if tf:IsShown() and tf.group then
            local have, want = learnedBy[tf.group] or 0, spent[tf.group] or 0
            local txt = ("%s  %s%d|r"):format(tf.group.name, have > 0 and "|cffff9933" or "|cff8a8a8a", have)
            if want > have then txt = txt .. ("  |cff777777->|r  |cffffd100%d|r"):format(want) end
            tf.name:SetText(txt)
        end
    end

    -- talents: learned = plain, planned ahead = faded with a gold edge, next = glowing, can take a point = green
    for id, b in pairs(buttons) do
        if b:IsShown() then
            local n = b.node
            local planned, learned = count[id] or 0, Learned(id)
            b.planned = planned
            local isNext = id == nextId
            local open = planned < n.max and CanAdd(n) == nil
            local rank, rc, edge, desat, alpha
            if isNext then
                desat, alpha, edge = false, 1, T.accent
                rank, rc = learned .. "/" .. planned, GOLD
            elseif planned > learned then
                desat, alpha, edge = true, 0.9, T.glow
                rank, rc = learned .. "/" .. planned, GOLD
            elseif learned > 0 then
                desat, alpha, edge = false, 1, LEARNED_EDGE
                rank, rc = tostring(learned), learned >= n.max and GOLD or WHITE
            elseif open then
                desat, alpha, edge = false, 0.9, GREEN
            else
                desat, alpha, edge = true, 0.4, T.line
            end
            b.icon:SetDesaturated(desat)
            b.icon:SetAlpha(alpha)
            if rank then
                b.rank:SetText(rank)
                b.rank:SetTextColor(rc[1], rc[2], rc[3])
                b.rankBg:SetWidth(math.max(16, b.rank:GetStringWidth() + 6))
                b.rankBg:Show()
            else
                b.rank:SetText("")
                b.rankBg:Hide()
            end
            W.SetBorder(b.edges, edge)
            b.glow:SetShown(isNext)
            if isNext then
                if not b.pulse:IsPlaying() then b.pulse:Play() end
            elseif b.pulse:IsPlaying() then
                b.pulse:Stop()
            end
        end
    end

    -- progress: points of the plan learned so far
    local needs = valid > 0 and (FIRST_LEVEL + valid - 1) or nil
    win.summary:SetText(("|cffffffff%d|r / %d points learned"):format(inPlan, valid))
    win.goal:SetText(needs and ("done at level " .. needs) or "")
    local frac = valid > 0 and math.min(1, inPlan / valid) or 0
    local bw = (win.bar:GetWidth() or 0) - 2
    win.bar.fill:SetShown(frac > 0 and bw > 0)
    if bw > 0 then win.bar.fill:SetWidth(math.max(1, bw * frac)) end
    win.status:SetText(TP.status or "Click a talent to plan its next point. Right-click to take one off.")

    -- the list
    local items = Items()
    local listH = win.list:GetHeight() or 0
    if listOff > #items - 1 then listOff = math.max(0, #items - 1) end
    local y, used, i = 4, 0, listOff
    while i < #items do
        local it = items[i + 1]
        local h = ITEM_H[it.kind]
        if used > 0 and y + h > listH - 16 then break end
        used = used + 1
        lines[used] = lines[used] or MakeLine()
        ShowLine(lines[used], it, y, h)
        lines[used]:Show()
        y, i = y + h, i + 1
    end
    for k = used + 1, #lines do lines[k].item = nil; lines[k]:Hide() end
    local more = #items - i
    if more > 0 then win.listInfo:SetText(("%d more below - scroll"):format(more))
    elseif listOff > 0 then win.listInfo:SetText("scroll up for more")
    else win.listInfo:SetText("") end
    win.empty:SetShown(#items == 0)
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

-- Profiles: Save / Load / Import / Export in one small menu that opens above its button
local function ProfilesMenu(anchor)
    local opts = { { "Save this plan...", "save" }, { "Load a saved plan", "load" },
                   { "Import from text", "import" }, { "Export as text", "export" } }
    local ROW, MW = 22, 160
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(50)
    m:SetClampedToScreen(true)
    m:SetSize(MW, #opts * ROW + 6)
    m:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 3)
    W.Texture(m, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 0.98 }):SetAllPoints()
    W.Border(m, 1, T.border, "BORDER")
    m:Hide()
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(40)
    catcher:Hide()
    catcher:SetScript("OnClick", function() m:Hide() end)
    m:SetScript("OnShow", function() catcher:Show() end)
    m:SetScript("OnHide", function() catcher:Hide() end)
    for i, o in ipairs(opts) do
        local r = CreateFrame("Button", nil, m)
        r:SetSize(MW - 8, ROW)
        r:SetPoint("TOPLEFT", 4, -3 - (i - 1) * ROW)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.label = W.Text(r, 12, T.text)
        r.label:SetPoint("LEFT", 10, 0)
        r.label:SetText(o[1])
        r:SetScript("OnEnter", function(s) s.hl:Show(); Color(s.label, T.accent) end)
        r:SetScript("OnLeave", function(s) s.hl:Hide(); Color(s.label, T.text) end)
        r:SetScript("OnClick", function() m:Hide(); Box(o[2]) end)
    end
    anchor:HookScript("OnHide", function() m:Hide() end)
    return m
end

-- "Auto-learn as I level": a small gold checkbox (fits the plan card better than the big switch)
local function AutoCheck(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(18)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(13, 13)
    c.box:SetPoint("LEFT")
    W.Texture(c.box, "BACKGROUND", T.field):SetAllPoints()
    c.edges = W.Border(c.box, 1, T.border)
    c.check = c.box:CreateTexture(nil, "ARTWORK")
    c.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c.check:SetSize(18, 18)
    c.check:SetPoint("CENTER", 1, 0)
    c.label = W.Text(c, 12, T.text)
    c.label:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
    c.label:SetText("Auto-learn as I level")
    c:SetWidth(13 + 8 + c.label:GetStringWidth() + 4)
    function c:Refresh()
        self.check:SetShown(plan.auto and true or false)
        Color(self.label, self.hot and T.accent or T.text)
        W.SetBorder(self.edges, self.hot and T.glow or T.border)
    end
    c:SetScript("OnClick", function(s)
        plan.auto = not plan.auto
        declinedKey = nil
        if plan.auto then QueueLearn(0.2) else HideAsk() end
        s:Refresh()
    end)
    c:SetScript("OnEnter", function(s)
        s.hot = true; s:Refresh()
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Auto-learn as I level")
        GameTooltip:AddLine("When you level up, asks first and then learns the next planned talents (out of combat).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(s) s.hot = false; s:Refresh(); GameTooltip:Hide() end)
    return c
end

-- open or fold the Level plan (folded: a thin strip, and the trees take the room). animate = slide it
-- (eased, about a fifth of a second); the plan's contents keep their full width and are clipped by the card.
local SLIDE_TIME = 0.18
local function ApplySide(animate)
    if not win then return end
    local side = win.side
    local open = plan.side and true or false
    local target = open and SIDE_W or SIDE_MIN
    if box and not open then box:Hide() end
    local function Finish()
        side:SetScript("OnUpdate", nil)
        win.sliding = nil
        side:SetWidth(target)
        side.content:SetShown(open); side.content:SetAlpha(1)
        side.strip:SetShown(not open); side.strip:SetAlpha(1)
    end
    if not animate or not side:IsVisible() then Finish() return end
    local from, t = side:GetWidth(), 0
    win.sliding = true
    side.content:Show()
    side.strip:Show()
    side:SetScript("OnUpdate", function(s, elapsed)
        t = math.min(SLIDE_TIME, t + elapsed)
        local p = 1 - (1 - t / SLIDE_TIME) ^ 3 -- ease out
        s:SetWidth(from + (target - from) * p)
        local shown = open and p or (1 - p)
        s.content:SetAlpha(shown)
        s.strip:SetAlpha(1 - shown)
        if t >= SLIDE_TIME then
            Finish()
            LayoutTrees()
            Paint()
        end
    end)
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

    -- the Level plan card on the right (made first: the trees are anchored to it)
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPRIGHT", -12, -12)
    side:SetPoint("BOTTOMRIGHT", -12, 34)
    side:SetWidth(SIDE_W)
    local sbg = side:CreateTexture(nil, "BACKGROUND", nil, 4)
    sbg:SetAllPoints()
    sbg:SetColorTexture(0, 0, 0, 0.35) -- a plain dark card: the class artwork stays behind the trees only
    W.Border(side, 1, T.line)
    win.side = side

    -- trees: everything left of the plan card
    win.trees = CreateFrame("Frame", nil, win)
    win.trees:SetPoint("TOPLEFT", 12, -12)
    win.trees:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -10, 0)

    -- the game's own class artwork behind the trees only: it is three spec pictures side by side, so it has to
    -- span exactly the three trees or a picture's edge lands inside a tree (stretched over the plan card, the
    -- Fury / Protection seam showed up inside the Protection tree)
    win.art = win:CreateTexture(nil, "BACKGROUND", nil, 2)
    win.art:SetAllPoints(win.trees)
    local atlas
    local specVis = _G.SpecializationVisuals
    if specVis then
        for _, v in pairs(specVis) do
            if v.background and v.background:lower():find(CLASS:lower(), 1, true) then atlas = v.background; break end
        end
    end
    atlas = atlas or ("talent-background-" .. CLASS:lower())
    -- Don't ask C_Texture.GetAtlasInfo first: on this client its result table needs
    -- Vector2DMixin, which isn't always loaded yet, and it throws. SetAtlas itself
    -- returns whether the atlas exists, so just try it (guarded) and check.
    local okArt = false
    local okCall, res = pcall(win.art.SetAtlas, win.art, atlas)
    if okCall and res ~= false and win.art:GetAtlas() then okArt = true end
    if not okArt then
        win.art:SetColorTexture(0, 0, 0, 0)
    end
    -- a soft dark wash at the top so the tree names read well
    win.shade = win:CreateTexture(nil, "BACKGROUND", nil, 3)
    win.shade:SetPoint("TOPLEFT", win.trees, "TOPLEFT")
    win.shade:SetPoint("TOPRIGHT", side, "TOPRIGHT")
    win.shade:SetHeight(60)
    win.shade:SetColorTexture(1, 1, 1, 1)
    if win.shade.SetGradient and CreateColor then
        win.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    else
        win.shade:SetColorTexture(0, 0, 0, 0.3)
    end

    -- bottom strip: what the colours mean (right) and tips / messages (left)
    local legend = { { "Learned", LEARNED_EDGE }, { "Planned", T.glow }, { "Next", T.accent }, { "Can take a point", GREEN } }
    local prev
    for i = #legend, 1, -1 do
        local e = legend[i]
        local t = W.Text(win, 10, T.dim)
        t:SetText(e[1])
        if prev then t:SetPoint("RIGHT", prev, "LEFT", -12, 0) else t:SetPoint("BOTTOMRIGHT", -14, 13) end
        local sw = CreateFrame("Frame", nil, win)
        sw:SetSize(10, 10)
        sw:SetPoint("RIGHT", t, "LEFT", -5, 0)
        local fill = e[1] == "Next" and { 1, 0.82, 0, 0.55 } or { 0.12, 0.12, 0.12, 1 }
        W.Texture(sw, "BACKGROUND", fill):SetAllPoints()
        W.Border(sw, 1, e[2])
        prev = sw
    end
    win.status = W.Text(win, 11, T.dim)
    win.status:SetPoint("BOTTOMLEFT", 14, 12)
    win.status:SetPoint("RIGHT", prev, "LEFT", -16, 0)
    win.status:SetWordWrap(false)

    -- the plan card's contents (hidden while it is folded)
    local c = CreateFrame("Frame", nil, side)
    c:SetPoint("TOPLEFT")
    c:SetPoint("BOTTOMLEFT")
    c:SetWidth(SIDE_W) -- full width always; while sliding the card clips it
    if side.SetClipsChildren then side:SetClipsChildren(true) end
    side.content = c

    local title = W.Text(c, 15, T.text)
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetPoint("LEFT", c, "TOPLEFT", 12, HEAD_Y)
    title:SetText("Level Plan")
    local fold = W.Button(c, 22, 22, ">")
    fold:SetPoint("RIGHT", c, "TOPRIGHT", -8, HEAD_Y)
    fold:SetScript("OnClick", function() GameTooltip:Hide(); plan.side = false; ApplySide(true) end)
    fold:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Fold the Level plan")
        GameTooltip:Show()
    end)
    fold:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local now = W.Button(c, 80, 22, "Learn now", true)
    now:SetPoint("RIGHT", fold, "LEFT", -6, 0)
    now:SetScript("OnClick", function() Learn(true); C_Timer.After(0.5, Paint) end)
    now:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Learn the next planned talents now")
        GameTooltip:AddLine("Uses any talent points you have left.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    now:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local hl = c:CreateTexture(nil, "BORDER")
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:SetPoint("TOPLEFT", 1, -HEAD_H)
    hl:SetPoint("TOPRIGHT", -1, -HEAD_H)
    hl:SetHeight(1)

    -- progress
    win.summary = W.Text(c, 11, { 0.78, 0.74, 0.64 })
    win.summary:SetPoint("TOPLEFT", 12, -62)
    win.goal = W.Text(c, 11, T.dim, "RIGHT")
    win.goal:SetPoint("TOPRIGHT", -12, -62)
    local bar = CreateFrame("Frame", nil, c)
    bar:SetPoint("TOPLEFT", 12, -80)
    bar:SetPoint("TOPRIGHT", -12, -80)
    bar:SetHeight(7)
    W.Texture(bar, "BACKGROUND", T.field):SetAllPoints()
    W.Border(bar, 1, T.line)
    bar.fill = W.Texture(bar, "ARTWORK", T.brand)
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetWidth(1)
    win.bar = bar
    bar:SetScript("OnSizeChanged", function() if win:IsShown() then Paint() end end)

    win.auto = AutoCheck(c)
    win.auto:SetPoint("TOPLEFT", 12, -95)
    local hl2 = c:CreateTexture(nil, "BORDER")
    hl2:SetColorTexture(1, 1, 1, 0.08)
    hl2:SetPoint("TOPLEFT", 1, -121)
    hl2:SetPoint("TOPRIGHT", -1, -121)
    hl2:SetHeight(1)

    -- the list: no box of its own, rows straight on the card
    win.list = CreateFrame("Frame", nil, c)
    win.list:SetPoint("TOPLEFT", 0, -122)
    win.list:SetPoint("BOTTOMRIGHT", 0, 41)
    win.listInfo = W.Text(win.list, 10, T.dim, "CENTER")
    win.listInfo:SetPoint("BOTTOM", 0, 3)
    win.empty = W.Text(win.list, 11, T.dim)
    win.empty:SetPoint("TOPLEFT", 14, -14)
    win.empty:SetWidth(SIDE_W - 28)
    win.empty:SetText("No plan yet. Click talents on the left in the order you want them, or use From my talents to start from what you have.")
    win.list:EnableMouseWheel(true)
    win.list:SetScript("OnMouseWheel", function(_, delta)
        listOff = math.max(0, listOff - delta * 2)
        Paint()
    end)
    win.list:SetScript("OnSizeChanged", function() if win:IsShown() then Paint() end end)

    -- footer: From my talents  |  Profiles v  |  Clear
    local fl = c:CreateTexture(nil, "BORDER")
    fl:SetColorTexture(1, 1, 1, 0.08)
    fl:SetPoint("BOTTOMLEFT", 1, 40)
    fl:SetPoint("BOTTOMRIGHT", -1, 40)
    fl:SetHeight(1)
    local clear = W.Button(c, 58, 24, "Clear")
    clear:SetPoint("BOTTOMRIGHT", -8, 8)
    clear:SetScript("OnClick", function(s)
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
    end)
    local prof = W.Button(c, 86, 24, "Profiles  v")
    prof:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    local menu = ProfilesMenu(prof)
    prof:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
    local from = W.Button(c, 10, 24, "From my talents")
    from:SetPoint("BOTTOMLEFT", 8, 8)
    from:SetPoint("RIGHT", prof, "LEFT", -6, 0)
    from:SetScript("OnClick", function(s)
        if #plan.points > 0 and not s.armed then
            s.armed = true; s:SetLabel("Replace plan?")
            C_Timer.After(3, function() s.armed = nil; s:SetLabel("From my talents") end)
            return
        end
        s.armed = nil; s:SetLabel("From my talents")
        TP.FromCurrent()
    end)

    -- folded: a thin strip, click it to open the plan again
    local strip = CreateFrame("Button", nil, side)
    strip:SetAllPoints()
    strip.hl = strip:CreateTexture(nil, "BACKGROUND", nil, 5)
    strip.hl:SetAllPoints()
    strip.hl:SetColorTexture(1, 1, 1, 0.05)
    strip.hl:Hide()
    local arrow = W.Text(strip, 14, T.accent, "CENTER")
    arrow:SetPoint("TOP", 0, -20)
    arrow:SetText("<")
    local word = W.Text(strip, 11, T.accent, "CENTER")
    word:SetPoint("TOP", arrow, "BOTTOM", 0, -12)
    word:SetSpacing(2)
    word:SetText("P\nL\nA\nN")
    strip:SetScript("OnClick", function() GameTooltip:Hide(); plan.side = true; ApplySide(true) end)
    strip:SetScript("OnEnter", function(s)
        s.hl:Show()
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Open the Level plan")
        GameTooltip:Show()
    end)
    strip:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
    side.strip = strip
    ApplySide()

    win:SetScript("OnShow", function()
        C_Timer.After(0, function() -- sizes are known after the first layout pass
            if not win:IsShown() then return end
            Tree = nil
            Ensure()
            LayoutTrees()
            Paint()
        end)
    end)
    win.trees:SetScript("OnSizeChanged", function()
        if not win:IsShown() then return end
        LayoutTrees()
        if not win.sliding then Paint() end -- while sliding only the layout moves; one Paint at the end
    end)
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

-- true while the talents window shows another player's talents (View Talents / inspect)
local function Inspecting(host)
    local ok, v = pcall(function() return host.IsInspecting and host:IsInspecting() and true or false end)
    return ok and v or false
end

function Sync()
    local host = _G.PlayerSpellsFrame
    if not (talentsUp and host) or Inspecting(host) then
        if win then win:Hide() end
        if opener then opener:Hide() end
        return
    end
    BuildOpener()
    opener:Show()
    if plan.open then
        BuildWindow()
        win:ClearAllPoints()
        -- the talents area below the tabs
        win:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -70)
        win:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
        win:Show()
        opener:SetLabel("Planner")
        opener:SetPrimary(true) -- gold edge while the planner is up
    else
        if win then win:Hide() end
        opener:SetLabel("Planner")
        opener:SetPrimary(false)
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
    -- step aside while the window shows someone else's talents
    if host.SetInspectUnit then hooksecurefunc(host, "SetInspectUnit", function() Sync() end) end
    if host.ClearInspectUnit then hooksecurefunc(host, "ClearInspectUnit", function() Sync() end) end
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
        approved = false; HideAsk() -- a new spec gets its own question
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
        function() return plan.auto end, function(v) plan.auto = v; declinedKey = nil; if v then QueueLearn(0.2) else HideAsk() end end)
    auto:SetPoint("TOPLEFT", 4, -36)
    local show = W.Checkbox(page, "Open the talents window in planner mode",
        function() return plan.open end, function(v) plan.open = v; Sync() end)
    show:SetPoint("TOPLEFT", 4, -62)
    W.Notes(page, 4, -98, width, "", {
        "Open your talents (N) and click Planner (next to Primary / Secondary): the talents area turns into the planner, and clicking Planner again brings the normal talents back. Click a talent to plan its next point, right-click to take one off. Learned talents look normal, planned ones are faded with a gold edge, the next one to learn glows, and green means it can take a point now. The Level plan on the right shows your progress, folds the picks you have learned into one line, and shows the next pick as a gold card with the level it comes at (the first point at level 10, then one per level). The > button folds the plan into a thin strip so the trees get the room.",
        "With Learn these talents as I level on, a window asks before anything is learned when you level up (it names your Primary or Secondary talents, so a plan made for your other spec is never spent by mistake). Not now waits until your next level. In a fight it waits until the fight ends. Learn now uses any points you have left.",
        "From my talents starts a plan from what you have learned now. The Profiles menu has Save and Load (plans by name for every character of your class; Load shows the points per tree) and Export and Import (share a plan as text).",
        "A pick that breaks the rules (5 points per tier in that tree, or a talent its arrow comes from not filled yet) shows in red and is skipped until you fix the plan.",
        "/cuitalents switches planner mode on or off.",
    })
end, function() end)

    end,
})
