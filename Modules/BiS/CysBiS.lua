--------------------------------------------------------------------------------
-- Cys's UI - Cys's BiS (WoW Forever)
--
-- A window beside the character panel with the best item for every slot, scored with Cys's Upgrade's
-- stat weights for the profile you use. Nothing is shipped with it: the items it weighs come from
--   * what you wear and carry
--   * the DungeonJournal addon by Exehn, when it is installed (every boss's loot and the dungeon quests' rewards)
--   * every gear item Cys's Auction House has seen on your realm, when it is installed
--   * gear you have seen yourself: loot, roll windows, quest rewards and vendors (remembered)
-- Only items your class can use and that need no more than "Levels ahead" levels over yours are weighed.
-- What you wear always competes, so it never asks you to wear something worse.
-- The dropdown swaps in Wowhead's level 60 pre-raid list for one of your specs (CysBiSWowhead.lua), still
-- scored with your weights; those items get a "Wowhead pre-raid BiS" line on their tooltips.
--
--   /cuibis    open or close the window (it shows with the character panel)
--   /cuibis wowhead   check every Wowhead item for your class against its name in game
--------------------------------------------------------------------------------
CysUI:RegisterModule({
    key = "bis", name = "Cys's BiS", foreverOnly = true,
    desc = "WoW Forever: a window beside the character panel with your best item for every slot and where it comes from, scored with Cys's Upgrade's weights. Uses DungeonJournal and Cys's Auction House when they are installed.",
    open = function() CysUI:OpenConfig("BiS List") end,
    body = function()
local CUI = CysUI
if not CUI.isForever then return end
local W = CUI.W
local T = W.T

CysUIDB.bis = CysUIDB.bis or {}
local db = CysUIDB.bis
if db.ahead == nil or not db.aheadV then db.ahead = 0; db.aheadV = 1 end -- levels over yours an item may need (0 = wearable now)
if db.tipMark == nil then db.tipMark = true end  -- "Cys BiS: #1 Head" on item tooltips
if db.alert == nil then db.alert = true end      -- a BiS item in a loot or roll window (a message on your screen only)
if db.journal == nil then db.journal = true end
if db.ah == nil then db.ah = true end
db.filter = db.filter or "all"
if db.armorBest == nil then db.armorBest = true end   -- body armor: only your best armor type...
if db.armorBelow == nil then db.armorBelow = true end -- ...and the one below it (mail while a warrior moves to plate)
db.seen = db.seen or {}
db.saved = db.saved or {} -- per character: the last list and what it was worked out from
db.pins = db.pins or {}

local _, CLASS = UnitClass("player")
CLASS = CLASS or "?"
local CHARKEY = (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
db.pins[CHARKEY] = db.pins[CHARKEY] or {}
local pins = db.pins[CHARKEY]

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local IsCached = C_Item and C_Item.IsItemDataCachedByID
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local WIDTH, HEIGHT, ROW_H, ROWS = 560, 540, 22, 18
local LIST_TOP = -112
local QUESTION = 134400
local GREY = { 0.55, 0.55, 0.55 }
local MAX_SEEN = 3000

local win, opener, rows, view, offset = nil, nil, {}, {}, 0
local expanded = {}
local Refresh, Sync, Recompute, RankPicks

local function Hex(c) return string.format("|cff%02x%02x%02x", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255) end
local function MyLevel() return UnitLevel("player") or 1 end
local function Up() return CysUpgrade and CysUpgrade.GetItemEP and true or false end
local function IDOf(link) return tonumber(string.match(link or "", "item:(%d+)") or "") end

--------------------------------------------------------------------------------
-- Slots and what fits them
--------------------------------------------------------------------------------
local SLOTS = {
    { k = "head", label = "Head", inv = 1, group = 1, locs = { INVTYPE_HEAD = true } },
    { k = "neck", label = "Neck", inv = 2, group = 1, locs = { INVTYPE_NECK = true } },
    { k = "shoulder", label = "Shoulder", inv = 3, group = 1, locs = { INVTYPE_SHOULDER = true } },
    { k = "back", label = "Back", inv = 15, group = 1, locs = { INVTYPE_CLOAK = true } },
    { k = "chest", label = "Chest", inv = 5, group = 1, locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { k = "wrist", label = "Wrist", inv = 9, group = 1, locs = { INVTYPE_WRIST = true } },
    { k = "hands", label = "Hands", inv = 10, group = 1, locs = { INVTYPE_HAND = true } },
    { k = "waist", label = "Waist", inv = 6, group = 1, locs = { INVTYPE_WAIST = true } },
    { k = "legs", label = "Legs", inv = 7, group = 1, locs = { INVTYPE_LEGS = true } },
    { k = "feet", label = "Feet", inv = 8, group = 1, locs = { INVTYPE_FEET = true } },
    { k = "ring1", label = "Ring 1", inv = 11, group = 2, locs = { INVTYPE_FINGER = true }, pair = "ring", n = 1 },
    { k = "ring2", label = "Ring 2", inv = 12, group = 2, locs = { INVTYPE_FINGER = true }, pair = "ring", n = 2 },
    { k = "trinket1", label = "Trinket 1", inv = 13, group = 2, locs = { INVTYPE_TRINKET = true }, pair = "trinket", n = 1 },
    { k = "trinket2", label = "Trinket 2", inv = 14, group = 2, locs = { INVTYPE_TRINKET = true }, pair = "trinket", n = 2 },
    { k = "main", label = "Main Hand", inv = 16, group = 3, locs = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true } },
    { k = "off", label = "Off Hand", inv = 17, group = 3, locs = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true } },
    { k = "ranged", label = "Ranged", inv = 18, group = 3, locs = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
}
local GROUPS = { "ARMOR", "JEWELRY", "WEAPONS" }
local ANY_LOC = {}
for _, s in ipairs(SLOTS) do for loc in pairs(s.locs) do ANY_LOC[loc] = true end end
local BODY = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WRIST = true,
               INVTYPE_HAND = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true }

-- Classic proficiencies (item subclass IDs). Weapons: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace,
-- 6 polearm, 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
local function Set(...) local t = {} for i = 1, select("#", ...) do t[select(i, ...)] = true end return t end
local WEAPONS = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER  = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE   = Set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST  = Set(4, 10, 15, 19),
    SHAMAN  = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE    = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID   = Set(4, 5, 10, 13, 15),
}
-- Armor: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem. The value is the level it is
-- learned at (mail for hunters and shamans, plate for warriors and paladins at 40).
local ARMOR = {
    WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER  = { [1] = 1, [2] = 1, [3] = 40 },
    ROGUE   = { [1] = 1, [2] = 1 },
    PRIEST  = { [1] = 1 },
    SHAMAN  = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    MAGE    = { [1] = 1 },
    WARLOCK = { [1] = 1 },
    DRUID   = { [1] = 1, [2] = 1, [8] = 1 },
}

-- Can my class ever use it? (by item class / subclass; minLevel gates mail and plate)
local function Usable(classID, subID, loc, minLevel)
    if classID == 2 then
        local w = WEAPONS[CLASS]
        return w and w[subID] and true or false
    elseif classID == 4 then
        if subID == 0 then return true end -- necks, rings, trinkets, held in off-hand
        if loc == "INVTYPE_CLOAK" then return true end
        local learnAt = ARMOR[CLASS] and ARMOR[CLASS][subID]
        if not learnAt then return false end
        local at = math.max(MyLevel(), minLevel or 0)
        if at < learnAt then return false end
        if db.armorBest and BODY[loc] and subID >= 1 and subID <= 4 then
            local best = 1 -- the heaviest of cloth / leather / mail / plate known at that level
            for t = 4, 1, -1 do local l = ARMOR[CLASS][t] if l and at >= l then best = t break end end
            if subID < best - (db.armorBelow and 1 or 0) then return false end
        end
        return true
    end
    return false
end

local function CanDualWield()
    return (IsPlayerSpell and IsPlayerSpell(674)) or (IsSpellKnown and IsSpellKnown(674)) or false
end
local function ProfileName() return (CysUpgrade and CysUpgrade.activeProfileName) or "" end
local function IsTank()
    local p = string.lower(ProfileName())
    return string.find(p, "tank") ~= nil or string.find(p, "mitigation") ~= nil
end
local SHIELD_CLASS = { WARRIOR = true, PALADIN = true, SHAMAN = true }

--------------------------------------------------------------------------------
-- Where items come from
--------------------------------------------------------------------------------
local cand = {}    -- itemID -> { srcs = { ... }, link = (your own copy) }
local srcCount = { journal = 0, ah = 0, seen = 0 }

local function AddSrc(id, s)
    if not id then return end
    local c = cand[id]
    if not c then c = { srcs = {} }; cand[id] = c end
    if #c.srcs < 4 then c.srcs[#c.srcs + 1] = s end
end

local function JournalDB()
    if not db.journal then return nil end
    local ns = _G.ForeverDungeonJournal_NS
    return type(ns) == "table" and type(ns.DB) == "table" and ns.DB or nil
end

local function GatherJournal()
    local jdb = JournalDB()
    if not jdb then return end
    local faction = UnitFactionGroup("player")
    local n = 0
    local top, low = MyLevel() + (tonumber(db.ahead) or 0), MyLevel() - 12
    for dname, d in pairs(jdb) do
        local lo, hi = string.match(type(d) == "table" and tostring(d.level or "") or "", "(%d+)%D+(%d+)")
        lo, hi = tonumber(lo), tonumber(hi)
        local near = not lo or (lo <= top and (hi or lo) >= low) -- dungeons far below or above you are skipped
        if type(d) == "table" and near then
            n = n + 1
            for _, boss in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
                for _, e in ipairs(type(boss.loot) == "table" and boss.loot or {}) do
                    if type(e) == "table" and type(e[1]) == "number" then
                        AddSrc(e[1], { k = "drop", a = boss.name, b = dname })
                    end
                end
            end
            for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
                if type(q) == "table" and (q.faction == nil or q.faction == "Both" or q.faction == faction) then
                    for _, e in ipairs(type(q.rewardItems) == "table" and q.rewardItems or {}) do
                        if type(e) == "table" and type(e[1]) == "number" then
                            AddSrc(e[1], { k = "quest", a = q.name, b = dname })
                        end
                    end
                end
            end
        end
    end
    srcCount.journal = n
end

local function AH() return db.ah and type(_G.CysAH) == "table" and _G.CysAH or nil end
local ahList -- the AH's gear item IDs, sorted out once (rebuilt after an AH visit)
local function GatherAH()
    local ah = AH()
    local items = ah and type(ah.realm) == "table" and type(ah.realm.items) == "table" and ah.realm.items
    if not items then return end
    if not ahList then
        ahList = {}
        for id in pairs(items) do
            if type(id) == "number" then
                local _, _, _, loc = GetItemInfoInstant(id)
                if loc and ANY_LOC[loc] then ahList[#ahList + 1] = id end
            end
        end
    end
    for _, id in ipairs(ahList) do AddSrc(id, { k = "ah" }) end
    srcCount.ah = #ahList
end

local function GatherSeen()
    local n = 0
    for id, s in pairs(db.seen) do
        if type(id) == "number" and type(s) == "table" then AddSrc(id, { k = s.k or "seen", a = s.a, b = s.b }); n = n + 1 end
    end
    srcCount.seen = n
end

-- what you wear and carry, by link (keeps suffixes and enchants)
local CC = C_Container or { GetContainerNumSlots = GetContainerNumSlots, GetContainerItemLink = GetContainerItemLink }
local function GatherOwn()
    for inv = 1, 18 do
        local link = GetInventoryItemLink("player", inv)
        local id = IDOf(link)
        if id then AddSrc(id, { k = "worn" }); cand[id].link = cand[id].link or link end
    end
    for bag = 0, 4 do
        for slot = 1, (CC.GetContainerNumSlots(bag) or 0) do
            local link = CC.GetContainerItemLink(bag, slot)
            local id = IDOf(link)
            if id then
                local _, _, _, loc = GetItemInfoInstant(id)
                if loc and ANY_LOC[loc] then AddSrc(id, { k = "bag" }); cand[id].link = cand[id].link or link end
            end
        end
    end
end

-- remember gear you meet in the world
local SEEN_RANK = { worn = 0, bag = 0, drop = 1, quest = 2, vendor = 3, loot = 4, roll = 4, seen = 5, ah = 6 }
local function Remember(link, k, a, b)
    local id = IDOf(link)
    if not id then return end
    local _, _, _, loc = GetItemInfoInstant(id)
    if not (loc and ANY_LOC[loc]) then return end
    local old = db.seen[id]
    if old and (SEEN_RANK[old.k] or 9) <= (SEEN_RANK[k] or 9) then return end
    if not old then
        local n = 0
        for _ in pairs(db.seen) do n = n + 1; if n >= MAX_SEEN then return end end
    end
    db.seen[id] = { k = k, a = a, b = b }
end

local function ZoneName()
    local name, kind = GetInstanceInfo()
    if kind and kind ~= "none" and name then return name end
    return GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or nil
end

--------------------------------------------------------------------------------
-- Scoring (in small steps so the game never hitches)
--------------------------------------------------------------------------------
local info = {}      -- itemID -> { loc, classID, subID, minLevel, quality, icon, name, link }
local scores = {}    -- sig -> itemID -> EP
local picks = {}     -- slot key -> { { id, ep, link, pinned }, ... }
local pickRank = {}  -- itemID -> { slot label, rank }
local state = { loading = 0, total = 0, busy = false, sig = "" }
local tries = {}     -- itemID -> load requests made (items that never load stop being asked for)
local asked = {}     -- itemID -> true while we wait for the game to load it
local MAX_ASK = 150  -- load requests per pass (the rest wait for the next pass)

local function WeightSig()
    local t = { ProfileName() }
    for _, r in ipairs((CysUpgrade and CysUpgrade.statRows) or {}) do t[#t + 1] = tostring(r.key) .. "=" .. tostring(r.weight) end
    return table.concat(t, ";")
end

local function ReadInfo(id)
    local i = info[id]
    if i and i.minLevel then return i end
    local _, _, _, loc, icon, classID, subID = GetItemInfoInstant(id)
    if not loc then return nil end
    i = i or {}
    i.loc, i.icon, i.classID, i.subID = loc, icon, classID, subID
    local name, link, quality, ilvl, minLevel = GetItemInfo(id)
    if name then i.name, i.link, i.quality, i.minLevel, i.ilvl = name, link, quality, minLevel or 0, tonumber(ilvl) or 0 end
    info[id] = i
    return i
end

local function Score(id, link)
    local sig = state.sig
    scores[sig] = scores[sig] or {}
    local key = link or id
    local s = scores[sig][key]
    if s == nil then
        local ok, ep = pcall(CysUpgrade.GetItemEP, CysUpgrade, link or ("item:" .. id))
        s = (ok and tonumber(ep)) or 0
        if s > 0 then scores[sig][key] = s end -- a 0 can be an item the game had not loaded yet
    end
    return s
end

local function Worn(inv)
    local link = GetInventoryItemLink("player", inv)
    return link, IDOf(link)
end

local function PickFor(slotKey, id)
    for _, p in ipairs(picks[slotKey] or {}) do if p.id == id then return p end end
end

function RankPicks()
    wipe(pickRank)
    for _, s in ipairs(SLOTS) do
        for r, p in ipairs(picks[s.k] or {}) do
            if not pickRank[p.id] or pickRank[p.id].rank > r then pickRank[p.id] = { label = s.label, rank = r } end
        end
    end
end

local function BuildPicks(list)
    wipe(picks)
    wipe(pickRank)
    local myLevel, ahead = MyLevel(), tonumber(db.ahead) or 0
    local tank = IsTank() and SHIELD_CLASS[CLASS]
    local dw = CanDualWield()
    local bySlot = {}
    for _, s in ipairs(SLOTS) do bySlot[s.k] = {} end
    for _, e in ipairs(list) do
        local i = info[e.id]
        local loc = i and i.loc
        if loc and e.ep > 0 and (i.minLevel or 0) <= myLevel + ahead then
            for _, s in ipairs(SLOTS) do
                local fits = s.locs[loc]
                if s.k == "off" and loc == "INVTYPE_WEAPON" and dw and not tank then fits = true end
                if s.k == "main" and tank and loc == "INVTYPE_2HWEAPON" then fits = false end
                if s.k == "off" and tank and loc ~= "INVTYPE_SHIELD" then fits = false end
                if fits and not (s.n == 2) then -- the pair's second slot is filled from the first's list
                    local l = bySlot[s.k]
                    l[#l + 1] = e
                end
            end
        end
    end
    -- equal scores always land in the same order (higher item level, then item ID), so picks never flip
    local function Before(a, b, va, vb)
        if va ~= vb then return va > vb end
        local la, lb = info[a.id] and info[a.id].ilvl or 0, info[b.id] and info[b.id].ilvl or 0
        if la ~= lb then return la > lb end
        return a.id < b.id
    end
    -- off-hand first: the main hand compares a two-hander with one-hander + best off-hand
    local function Sort(l) table.sort(l, function(a, b) return Before(a, b, a.ep, b.ep) end) end
    Sort(bySlot.off)
    local bestOff = bySlot.off[1] and bySlot.off[1].ep or 0
    for _, e in ipairs(bySlot.main) do
        local i = info[e.id]
        e.eff = (i and i.loc == "INVTYPE_2HWEAPON") and e.ep or (e.ep + bestOff)
    end
    table.sort(bySlot.main, function(a, b) return Before(a, b, a.eff or a.ep, b.eff or b.ep) end)
    for _, s in ipairs(SLOTS) do if s.k ~= "main" and s.k ~= "off" and not s.n then Sort(bySlot[s.k]) end end
    Sort(bySlot.ring1); Sort(bySlot.trinket1)

    local function Take(slotKey, l, skip)
        local out = {}
        local pin = pins[slotKey]
        if pin then
            for _, e in ipairs(l) do if e.id == pin then out[1] = { id = e.id, ep = e.ep, link = e.link, pinned = true } break end end
            if not out[1] and info[pin] then out[1] = { id = pin, ep = Score(pin, nil), pinned = true } end
        end
        for _, e in ipairs(l) do
            if #out >= 3 then break end
            if not (skip and skip[e.id]) and not (out[1] and out[1].id == e.id) then
                out[#out + 1] = { id = e.id, ep = e.ep, link = e.link }
            end
        end
        return out
    end
    for _, s in ipairs(SLOTS) do
        if s.n == 1 then
            picks[s.k] = Take(s.k, bySlot[s.k])
            local skip = {}
            if picks[s.k][1] then skip[picks[s.k][1].id] = true end
            local second = s.pair == "ring" and "ring2" or "trinket2"
            picks[second] = Take(second, bySlot[s.k], skip)
        elseif not s.n then
            picks[s.k] = Take(s.k, bySlot[s.k])
        end
    end
    -- a two-hander on top leaves the off-hand empty
    local top = picks.main[1]
    picks.twoHand = top and info[top.id] and info[top.id].loc == "INVTYPE_2HWEAPON" or false
    RankPicks()
end

-- Everything the list depends on. While it matches the saved list's, nothing is weighed again.
local function StateKey()
    local t = { MyLevel(), WeightSig(), tostring(db.ahead), tostring(db.armorBest), tostring(db.armorBelow),
                tostring(db.journal), tostring(db.ah) }
    local ah = AH()
    t[#t + 1] = tostring(ah and type(ah.realm) == "table" and ah.realm.lastFull or "")
    local n = 0
    for _ in pairs(db.seen) do n = n + 1 end
    t[#t + 1] = n
    for inv = 1, 18 do t[#t + 1] = IDOf(GetInventoryItemLink("player", inv)) or 0 end
    local bag = {}
    for b = 0, 4 do
        for slot = 1, (CC.GetContainerNumSlots(b) or 0) do
            local id = IDOf(CC.GetContainerItemLink(b, slot))
            if id then local _, _, _, loc = GetItemInfoInstant(id) if loc and ANY_LOC[loc] then bag[#bag + 1] = id end end
        end
    end
    table.sort(bag)
    t[#t + 1] = table.concat(bag, ",")
    local pinned = {}
    for k, v in pairs(pins) do pinned[#pinned + 1] = k .. "=" .. tostring(v) end
    table.sort(pinned)
    t[#t + 1] = table.concat(pinned, ",")
    return table.concat(t, "|")
end

local function Save()
    local snap = { key = state.key, complete = state.loading == 0, twoHand = picks.twoHand, picks = {}, items = {},
                   total = state.total, journal = srcCount.journal, ah = srcCount.ah, seen = srcCount.seen }
    for _, sl in ipairs(SLOTS) do
        local out = {}
        for r, p in ipairs(picks[sl.k] or {}) do
            out[r] = { id = p.id, ep = p.ep, link = p.link, pinned = p.pinned }
            local i, c = info[p.id], cand[p.id]
            if i and not snap.items[p.id] then
                snap.items[p.id] = { loc = i.loc, icon = i.icon, classID = i.classID, subID = i.subID, name = i.name, link = i.link,
                                     quality = i.quality, minLevel = i.minLevel, ilvl = i.ilvl, srcs = c and c.srcs or nil }
            end
        end
        snap.picks[sl.k] = out
    end
    db.saved[CHARKEY] = snap
end

-- show the saved list right away; the login check decides whether it needs weighing again
local function LoadSaved()
    local snap = db.saved[CHARKEY]
    if type(snap) ~= "table" or type(snap.picks) ~= "table" then return end
    for id, it in pairs(snap.items or {}) do
        if type(it) == "table" then
            info[id] = info[id] or { loc = it.loc, icon = it.icon, classID = it.classID, subID = it.subID, name = it.name,
                                     link = it.link, quality = it.quality, minLevel = it.minLevel, ilvl = it.ilvl }
            if it.srcs then cand[id] = { srcs = it.srcs } end
        end
    end
    for k, l in pairs(snap.picks) do picks[k] = l end
    picks.twoHand = snap.twoHand
    RankPicks()
    state.total = snap.total or 0
    srcCount.journal, srcCount.ah, srcCount.seen = snap.journal or 0, snap.ah or 0, snap.seen or 0
    state.savedKey = snap.complete and snap.key or nil
end

local runToken = 0
function Recompute(force)
    if not Up() then return end
    local key = StateKey()
    if not force and key == (state.key or state.savedKey) then -- nothing changed since the list was made
        state.key = key
        state.sig = WeightSig()
        return
    end
    state.key = key
    runToken = runToken + 1
    local token = runToken
    local sig = WeightSig()
    if sig ~= state.sig then wipe(scores) end
    state.sig = sig
    wipe(cand)
    pcall(GatherJournal)
    pcall(GatherAH)
    pcall(GatherSeen)
    pcall(GatherOwn)
    -- keep what can fit a slot and my class can use; ask the game to load anything it has not yet
    local todo, loading, total, askedNow = {}, 0, 0, 0
    wipe(asked)
    for id, c in pairs(cand) do
        local i = ReadInfo(id)
        if i and ANY_LOC[i.loc] and Usable(i.classID, i.subID, i.loc, i.minLevel) then
            total = total + 1
            local cached = IsCached and IsCached(id)
            if IsCached == nil then cached = i.minLevel ~= nil end
            if cached and i.minLevel then
                if i.minLevel <= MyLevel() + (tonumber(db.ahead) or 0) then todo[#todo + 1] = { id = id, link = c.link } end
            elseif (tries[id] or 0) < 3 then
                loading = loading + 1
                if askedNow < MAX_ASK then
                    askedNow = askedNow + 1
                    tries[id] = (tries[id] or 0) + 1
                    asked[id] = true
                    if RequestLoad then pcall(RequestLoad, id) end
                end
            end
        end
    end
    state.loading, state.total, state.busy = loading, total, true
    local list, i = {}, 1
    local function Step()
        if token ~= runToken then return end
        local t0 = debugprofilestop and debugprofilestop() or 0
        while i <= #todo do -- about 3 ms a frame: reading an item's tooltip the first time is the slow part
            local e = todo[i]
            list[#list + 1] = { id = e.id, ep = Score(e.id, e.link), link = e.link }
            i = i + 1
            if debugprofilestop and debugprofilestop() - t0 > 3 then break end
        end
        if i <= #todo then C_Timer.After(0, Step) return end
        BuildPicks(list)
        state.busy = false
        pcall(Save)
        if win and win:IsShown() then pcall(Refresh) end
    end
    C_Timer.After(0, Step)
end

local recomputeQueued, forceNext
local function QueueRecompute(delay, force)
    if force then forceNext = true end
    if recomputeQueued then return end
    recomputeQueued = true
    C_Timer.After(delay or 1, function()
        recomputeQueued = false
        local f = forceNext
        forceNext = nil
        local ok, err = pcall(Recompute, f)
        if not ok and CUI.debug then CUI:Print("BiS: " .. tostring(err)) end
    end)
end

--------------------------------------------------------------------------------
-- What a pick says about itself
--------------------------------------------------------------------------------
local function Money(c)
    local ah = _G.CysAH
    if ah and ah.Money then local ok, s = pcall(ah.Money, c) if ok and s then return s end end
    c = tonumber(c) or 0
    local g, s = math.floor(c / 10000), math.floor((c % 10000) / 100)
    return g > 0 and (g .. "g " .. s .. "s") or (s .. "s")
end

local KIND_ORDER = { worn = 1, bag = 2, drop = 3, quest = 4, vendor = 5, loot = 6, roll = 6, ah = 7, seen = 8 }
local function SourceText(id)
    local c = cand[id]
    local best
    for _, s in ipairs(c and c.srcs or {}) do
        if not best or (KIND_ORDER[s.k] or 9) < (KIND_ORDER[best.k] or 9) then best = s end
    end
    if not best then return "" end
    local k = best.k
    if k == "worn" then return "Equipped"
    elseif k == "bag" then return "In your bags"
    elseif k == "drop" then return (best.a or "?") .. " · " .. (best.b or "?")
    elseif k == "quest" then return "Quest · " .. (best.a or best.b or "?")
    elseif k == "vendor" then return "Vendor · " .. (best.a or "?") .. (best.b and (" · " .. best.b) or "")
    elseif k == "loot" or k == "roll" then return "Dropped · " .. (best.b or best.a or "?")
    elseif k == "ah" then
        local ah = AH()
        local ok, p = false, nil
        if ah and ah.GetPrice then ok, p = pcall(ah.GetPrice, id) end
        return "Auction House" .. ((ok and tonumber(p)) and (" · " .. Money(p)) or "")
    end
    return "Seen"
end

-- your own copies: worn / in bags / to get
local function Status(id)
    for inv = 1, 18 do if select(2, Worn(inv)) == id then return "worn" end end
    local n = 0
    local ok, c = pcall(GetItemCount, id)
    if ok then n = tonumber(c) or 0 end
    return n > 0 and "bag" or "get"
end

-- what a slot's pick is measured against
local function EPOf(link) return link and Score(IDOf(link), link) or 0 end
local function Is2H(id) local i = id and ReadInfo(id) return i and i.loc == "INVTYPE_2HWEAPON" or false end

local function Gain(s, p, from)
    from = from or picks
    local base, has, val = 0, false, p.ep
    if s.k == "main" then
        local mh, oh = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17)
        has = (mh or oh) ~= nil
        local pick2H, worn2H = Is2H(p.id), Is2H(IDOf(mh))
        if pick2H == worn2H then
            base = EPOf(mh)
        else -- a two-hander against main hand + off-hand (or the other way round)
            base = worn2H and EPOf(mh) or (EPOf(mh) + EPOf(oh))
            if not pick2H then local o = from.off and from.off[1] val = p.ep + (o and o.ep or 0) end
        end
    elseif s.pair then
        local first = s.pair == "ring" and 11 or 13
        local l1, l2 = GetInventoryItemLink("player", first), GetInventoryItemLink("player", first + 1)
        local e1, e2 = EPOf(l1), EPOf(l2)
        if e1 < e2 then e1, e2 = e2, e1 end
        if s.n == 1 then base, has = e1, (l1 or l2) ~= nil else base, has = e2, (l1 and l2) ~= nil end
    else
        local l = GetInventoryItemLink("player", s.inv)
        base, has = EPOf(l), l ~= nil
    end
    if not has or base <= 0 then return (val > 0) and "new" or nil end
    local pct = (val - base) / base * 100
    if pct < 0.5 then return nil end
    return string.format("+%d%%", math.floor(pct + 0.5))
end

--------------------------------------------------------------------------------
-- Wowhead's pre-raid lists (CysBiSWowhead.lua): a second list in the same window, picked in the dropdown.
-- Items are still scored with Cys's Upgrade, so the gain column means the same thing in both lists.
--------------------------------------------------------------------------------
db.list = db.list or {} -- per character: "cys" (the scored picks) or a Wowhead spec key
local FACTION = (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
local WH_KEYS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
                  "ring1", "ring2", "trinket1", "trinket2", "main", "off", "two", "ranged" }
local whPicks, whAsked = {}, {}

local function WHData() return type(_G.CysUI_BiSWowhead) == "table" and _G.CysUI_BiSWowhead or nil end
local function WHSpecs() local d = WHData() return d and d[CLASS] or {} end
local function WHSpec()
    local k = db.list[CHARKEY]
    if not k or k == "cys" then return nil end
    for _, sp in ipairs(WHSpecs()) do if sp.key == k then return sp end end
end
-- one slot's entry, with the Horde item swapped in for Horde characters
local function WHEntry(sp, key)
    local e = sp and sp[key]
    if type(e) ~= "table" then return nil end
    if e.h and FACTION == "Horde" then return { id = e.h[1], name = e.h[2], src = e[3] } end
    return { id = e[1], name = e[2], src = e[3] }
end
-- Forever re-made some items under new IDs and a guide can still link the old one, so a name match counts too
-- (a prefix match, for random-suffix items like "Master's Leggings of Shadow Wrath")
local function SameName(full, short) return full and short and full:find(short, 1, true) == 1 or false end
local function WHStatus(e)
    local st = Status(e.id)
    if st ~= "get" then return st end
    for inv = 1, 18 do
        local l = GetInventoryItemLink("player", inv)
        if SameName(l and l:match("%[(.-)%]"), e.name) then return "worn" end
    end
    local ok, c = pcall(GetItemCount, e.name)
    if ok and (tonumber(c) or 0) > 0 then return "bag" end
    return "get"
end
local function WHPick(e)
    local i = ReadInfo(e.id)
    if not (i and i.name) then
        whAsked[e.id] = true
        if RequestLoad then pcall(RequestLoad, e.id) end
    end
    return { id = e.id, ep = (i and i.name) and Score(e.id, i.link) or 0, wh = e }
end
-- the guide's item ID shows another name in game: worth a look before farming it
local function WHMismatch(p)
    local i = p and p.wh and info[p.id]
    return i and i.name and not SameName(i.name, p.wh.name) or false
end

local function BuildWHView(sp)
    wipe(view)
    wipe(whPicks)
    local counts, done = { 0, 0, 0 }, { 0, 0, 0 }
    local slotRows = { {}, {}, {} }
    local two, mainE = WHEntry(sp, "two"), WHEntry(sp, "main")
    local twoOnly = two ~= nil and mainE == nil
    local function Shows(st) return db.filter == "all" or (db.filter == "get" and st == "get") or (db.filter == "bag" and st == "bag") end
    for _, s in ipairs(SLOTS) do
        local e = WHEntry(sp, s.k)
        if s.k == "main" and twoOnly then e = two end
        local p = e and WHPick(e)
        whPicks[s.k] = p and { p } or {}
        local st = e and WHStatus(e)
        local skipOff = s.k == "off" and twoOnly
        if e then
            counts[s.group] = counts[s.group] + 1
            if st == "worn" or st == "bag" then done[s.group] = done[s.group] + 1 end
        end
        local g = slotRows[s.group]
        if skipOff then
            if db.filter == "all" then g[#g + 1] = { kind = "slot", s = s, skipOff = true, wh = true } end
        elseif (e and Shows(st)) or (not e and db.filter == "all") then
            g[#g + 1] = { kind = "slot", s = s, p = p, st = st, wh = true }
        end
        if s.k == "main" and two and not twoOnly then -- the guide's two-hander, as the other way to fill both hands
            local st2 = WHStatus(two)
            if Shows(st2) then g[#g + 1] = { kind = "alt", s = s, p = WHPick(two), r = "2H", st = st2, wh = true } end
        end
    end
    local yours, all = 0, 0
    for g = 1, 3 do
        yours, all = yours + done[g], all + counts[g]
        if #slotRows[g] > 0 then
            view[#view + 1] = { kind = "head", text = GROUPS[g], right = done[g] .. " of " .. counts[g] .. " yours" }
            for _, r in ipairs(slotRows[g]) do view[#view + 1] = r end
        end
    end
    return yours, all
end

-- item ID / name -> "Enhancement, Elemental" for the tooltip line (your class's lists only)
local whIndex, whNames
local function WHFor(id)
    if not whIndex then
        whIndex, whNames = {}, {}
        local function Add(t, k, label)
            if not k then return end
            t[k] = t[k] or {}
            for _, v in ipairs(t[k]) do if v == label then return end end
            t[k][#t[k] + 1] = label
        end
        for _, sp in ipairs(WHSpecs()) do
            for _, key in ipairs(WH_KEYS) do
                local e = WHEntry(sp, key)
                if e then Add(whIndex, e.id, sp.label); Add(whNames, e.name, sp.label) end
            end
        end
    end
    local l = whIndex[id]
    if not l then
        local n = GetItemInfo(id)
        if n then
            for name, specs in pairs(whNames) do if SameName(n, name) then l = specs break end end
        end
    end
    return l and table.concat(l, ", ") or nil
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function BuildView()
    wipe(view)
    local counts, done = { 0, 0, 0 }, { 0, 0, 0 }
    local slotRows = { {}, {}, {} }
    for _, s in ipairs(SLOTS) do
        local list = picks[s.k] or {}
        local p = list[1]
        local st = p and Status(p.id)
        local skipOff = (s.k == "off" and picks.twoHand)
        if not skipOff then
            counts[s.group] = counts[s.group] + 1
            if st == "worn" or st == "bag" then done[s.group] = done[s.group] + 1 end
        end
        local show = db.filter == "all" or (db.filter == "get" and st == "get") or (db.filter == "bag" and st == "bag")
        if skipOff then show = db.filter == "all" end
        if show then
            local g = slotRows[s.group]
            g[#g + 1] = { kind = "slot", s = s, p = p, st = st, skipOff = skipOff }
            if expanded[s.k] and not skipOff then
                for r = 2, #list do g[#g + 1] = { kind = "alt", s = s, p = list[r], r = r, st = Status(list[r].id) } end
            end
        end
    end
    local yours, all = 0, 0
    for g = 1, 3 do
        yours, all = yours + done[g], all + counts[g]
        if #slotRows[g] > 0 then
            view[#view + 1] = { kind = "head", text = GROUPS[g], right = done[g] .. " of " .. counts[g] .. " yours" }
            for _, r in ipairs(slotRows[g]) do view[#view + 1] = r end
        end
    end
    return yours, all
end

local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return { c.r, c.g, c.b } end
    return T.text
end

local function PaintRows()
    local maxOff = math.max(0, #view - ROWS)
    if offset > maxOff then offset = maxOff end
    if offset < 0 then offset = 0 end
    for n = 1, ROWS do
        local row, v = rows[n], view[n + offset]
        row.v = v
        if not v then
            row:Hide()
        else
            row:Show()
            local head = v.kind == "head"
            row.rule:SetShown(head)
            row.icon:SetShown(not head)
            row.gain:SetShown(not head)
            row.src:SetShown(not head)
            row.mark:SetShown(false)
            if head then
                row.slot:SetText(Hex(T.accent) .. v.text .. "|r")
                row.name:SetText("")
                row.more:SetText("")
                row.src:Show()
                row.src:SetText(Hex(GREY) .. v.right .. "|r")
            else
                local s, p = v.s, v.p
                local altLabel = v.r == "2H" and "   or 2H" or ("   #" .. tostring(v.r))
                row.slot:SetText(v.kind == "alt" and (Hex(GREY) .. altLabel .. "|r") or (Hex(GREY) .. s.label .. "|r"))
                if v.skipOff then
                    row.icon:SetTexture(QUESTION)
                    row.icon:SetDesaturated(true)
                    row.name:SetText(Hex(GREY) .. "Two-hander in the main hand|r")
                    row.gain:SetText("")
                    row.src:SetText("")
                    row.more:SetText("")
                elseif not p then
                    row.icon:SetTexture(QUESTION)
                    row.icon:SetDesaturated(true)
                    row.name:SetText(Hex(GREY) .. (v.wh and "Not on Wowhead's list yet" or (state.busy and "Weighing items..." or "Nothing found yet")) .. "|r")
                    row.gain:SetText("")
                    row.src:SetText("")
                    row.more:SetText("")
                else
                    local i = info[p.id] or {}
                    row.icon:SetTexture(i.icon or QUESTION)
                    row.icon:SetDesaturated(false)
                    local c = QualityColor(i.quality)
                    row.name:SetText(Hex(c) .. (i.name or (p.wh and p.wh.name) or ("item " .. p.id)) .. "|r"
                        .. (p.pinned and (" " .. Hex(T.accent) .. "(pinned)|r") or "")
                        .. (WHMismatch(p) and (" " .. Hex(T.danger) .. "?|r") or ""))
                    local g = Gain(s, p, v.wh and whPicks or nil)
                    if v.st == "worn" then row.gain:SetText(Hex(T.green) .. "worn|r")
                    elseif g then row.gain:SetText(Hex(T.green) .. g .. "|r")
                    else row.gain:SetText("") end
                    local src = v.wh and (p.wh.src or "") or SourceText(p.id)
                    if (i.minLevel or 0) > MyLevel() then src = src .. " · " .. Hex(T.danger) .. "Level " .. i.minLevel .. "|r" end
                    if v.st == "bag" and v.kind == "slot" and src ~= "In your bags" then src = Hex(T.green) .. "In bags|r · " .. src end
                    row.src:SetText(Hex(GREY) .. src .. "|r")
                    row.mark:SetShown(v.kind == "slot" and (v.st == "worn" or v.st == "bag"))
                    if v.kind == "slot" and not v.wh then
                        local n = #(picks[s.k] or {})
                        row.more:SetText(n > 1 and (Hex(GREY) .. (expanded[s.k] and "-" or "+") .. n .. "|r") or "")
                    else
                        row.more:SetText("")
                    end
                end
            end
        end
    end
    if #view > ROWS then
        local track = ROWS * ROW_H
        local size = math.max(24, track * ROWS / #view)
        win.thumb:SetHeight(size)
        win.thumb:ClearAllPoints()
        win.thumb:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, LIST_TOP - (track - size) * (offset / maxOff))
        win.thumb:Show()
    else
        win.thumb:Hide()
    end
end

local function BlendText()
    local b = CysUpgrade and CysUpgrade.GetTankBlend and CysUpgrade.GetTankBlend()
    if type(b) == "number" then
        return "Survival " .. b .. "%  ·  Threat " .. (100 - b) .. "%", b
    elseif b == false then
        return "Tank profile with its own weights", nil
    end
    return "Weights: Cys's Upgrade", nil
end

function Refresh()
    if not win then return end
    if state.sig ~= WeightSig() then QueueRecompute(0.1) end
    local sp = WHSpec()
    local yours, all
    if sp then yours, all = BuildWHView(sp) else yours, all = BuildView() end
    for _, b in ipairs(win.tabs) do b:SetPrimary(b.key == db.filter) end
    if win.list then win.list:Refresh() end
    if sp then
        win.sum1:SetText(Hex(T.accent) .. yours .. "/" .. all .. "|r " .. Hex(T.text) .. "Wowhead BiS yours|r   " .. Hex(GREY) .. "pre-raid " .. sp.label .. "|r")
        win.sum2:SetText("Wowhead's Forever guide (" .. (WHData().date or "?") .. ")" .. (sp.partial and ", still being written" or "") .. " · gain uses your Upgrade weights")
        win.minus:Hide()
        win.plus:Hide()
        local waiting = 0
        for id in pairs(whAsked) do if info[id] and info[id].name then whAsked[id] = nil else waiting = waiting + 1 end end
        win.foot:SetText(waiting > 0 and ("Loading " .. waiting .. " items from the game...")
            or (Hex(T.danger) .. "?|r = the guide's item shows another name in game; check it before farming. Pins work in Cys's picks."))
        PaintRows()
        return
    end
    local prof = ProfileName()
    win.sum1:SetText(Hex(T.accent) .. yours .. "/" .. all .. "|r " .. Hex(T.text) .. "BiS yours|r   " .. Hex(GREY) .. (prof ~= "" and prof or "no Cys's Upgrade profile") .. "|r")
    local text, b = BlendText()
    win.sum2:SetText(text)
    win.minus:SetShown(b ~= nil)
    win.plus:SetShown(b ~= nil)
    local parts = {}
    if JournalDB() then parts[#parts + 1] = "DungeonJournal " .. srcCount.journal .. " dungeons" end
    if AH() then parts[#parts + 1] = "Auction House " .. srcCount.ah .. " items" end
    parts[#parts + 1] = srcCount.seen .. " seen"
    if state.loading > 0 then
        win.foot:SetText("Loading " .. state.loading .. " items in the background; the list fills in as they arrive.")
    elseif not Up() then
        win.foot:SetText("Turn on Cys's Upgrade: BiS uses its weights.")
    else
        win.foot:SetText("Weighed " .. state.total .. ": " .. table.concat(parts, " · "))
    end
    PaintRows()
end

local function RowTip(self)
    local v = self.v
    if not v or v.kind == "head" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if v.p and v.wh then
        local i = info[v.p.id] or {}
        GameTooltip:SetHyperlink(v.p.link or i.link or ("item:" .. v.p.id))
        GameTooltip:AddLine(" ")
        local sp = WHSpec()
        GameTooltip:AddLine("Wowhead pre-raid BiS" .. (sp and (": " .. sp.label) or ""), T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine(v.p.wh.src or "", 1, 1, 1, true)
        GameTooltip:AddDoubleLine("Cys's Upgrade score", string.format("%.1f EP", v.p.ep or 0), T.accent[1], T.accent[2], T.accent[3], 1, 1, 1)
        if WHMismatch(v.p) then
            GameTooltip:AddLine("The guide names this " .. v.p.wh.name .. ", but this item ID is " .. (i.name or "?") .. " in game.", T.danger[1], T.danger[2], T.danger[3], true)
        end
    elseif v.p then
        local i = info[v.p.id] or {}
        GameTooltip:SetHyperlink(v.p.link or i.link or ("item:" .. v.p.id))
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Cys BiS score", string.format("%.1f EP", v.p.ep or 0), T.accent[1], T.accent[2], T.accent[3], 1, 1, 1)
        local c = cand[v.p.id]
        for _, s in ipairs(c and c.srcs or {}) do
            if s.k == "drop" then GameTooltip:AddLine("Drops from " .. (s.a or "?") .. " in " .. (s.b or "?"), 1, 1, 1)
            elseif s.k == "quest" then GameTooltip:AddLine("Quest reward: " .. (s.a or "?") .. (s.b and (" (" .. s.b .. ")") or ""), 1, 1, 1) end
        end
        if v.kind == "slot" then
            GameTooltip:AddLine("Click: the other picks. Drop an item here to pin it; right-click to unpin.", GREY[1], GREY[2], GREY[3], true)
        end
    elseif v.wh then
        GameTooltip:SetText(v.s.label, T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine(v.skipOff and "The guide's two-hander fills both hands." or "Wowhead's guide lists nothing here yet.", 1, 1, 1, true)
    else
        GameTooltip:SetText(v.s.label, T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Drop an item here to pin it as this slot's BiS.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function SlotFits(s, id)
    local i = ReadInfo(id)
    if not i then return false end
    if s.locs[i.loc] then return true end
    return s.k == "off" and i.loc == "INVTYPE_WEAPON" and CanDualWield()
end

local function DropOnRow(self)
    local v = self.v
    if not (v and v.s) or v.wh then return end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    if not SlotFits(v.s, id) then CUI:Print("BiS: that item does not fit " .. v.s.label .. ".") return end
    pins[v.s.k] = id
    QueueRecompute(0.05)
end

local function BuildWindow()
    if win then return end
    win = CreateFrame("Frame", "CysBiSFrame", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:EnableMouseWheel(true)
    win:Hide()
    W.Texture(win, "BACKGROUND", T.bg):SetAllPoints()
    W.Border(win, 2, T.border, "BORDER")
    local strip = W.Texture(win, "ARTWORK", T.header)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(24)
    local line = W.Texture(win, "ARTWORK", T.brand)
    line:SetPoint("TOPLEFT", 2, -26)
    line:SetPoint("TOPRIGHT", -2, -26)
    line:SetHeight(2)
    local title = W.Text(win, 12, T.accent)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("CYS'S BIS")
    local sub = W.Text(win, 10, T.dim)
    sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    sub:SetText("your best gear for every slot, and where it comes from")

    local close = W.Button(win, 18, 18, "x")
    close:SetPoint("TOPRIGHT", -6, -5)
    close:SetScript("OnClick", function() db.open = false; Sync() end)

    win.sum1 = W.Text(win, 14, T.text)
    win.sum1:SetPoint("TOPLEFT", 14, -38)
    win.sum1:SetPoint("RIGHT", -14, 0)
    win.sum1:SetWordWrap(false)
    win.sum2 = W.Text(win, 11, T.desc)
    win.sum2:SetPoint("TOPLEFT", 14, -60)
    win.sum2:SetWordWrap(false)
    win.minus = W.Button(win, 20, 18, "-")
    win.minus:SetPoint("LEFT", win.sum2, "RIGHT", 10, 0)
    win.plus = W.Button(win, 20, 18, "+")
    win.plus:SetPoint("LEFT", win.minus, "RIGHT", 4, 0)
    local function Nudge(d)
        local b = CysUpgrade.GetTankBlend()
        if type(b) ~= "number" then b = CysUpgrade.TANK_DEFAULT or 60 end
        CysUpgrade.SetTankBlend(b + d)
        QueueRecompute(0.05)
        Refresh()
    end
    win.minus:SetScript("OnClick", function() Nudge(-10) end)
    win.plus:SetScript("OnClick", function() Nudge(10) end)
    for _, b in ipairs({ win.minus, win.plus }) do
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Survival / Threat", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("+ leans on Stamina, Defense, Armor, Dodge and Parry; - on Strength, Hit, Crit and weapon damage. Changes this tank profile's weights in Cys's Upgrade.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    win.tabs = {}
    local TABS = { { "all", "All" }, { "get", "To get" }, { "bag", "In bags" } }
    for n, t in ipairs(TABS) do
        local b = W.Button(win, 70, 20, t[2])
        b.key = t[1]
        b:SetPoint("TOPRIGHT", -14 - (#TABS - n) * 74, -82)
        b:SetScript("OnClick", function() db.filter = t[1]; offset = 0; Refresh() end)
        win.tabs[n] = b
    end

    -- which list: Cys's picks (scored with your weights) or one of Wowhead's pre-raid guides for your class
    local lists = { { "cys", "Cys's picks (your weights)" } }
    for _, sp in ipairs(WHSpecs()) do lists[#lists + 1] = { sp.key, "Wowhead pre-raid: " .. sp.label } end
    if #lists > 1 then
        win.list = W.Dropdown(win, 236, lists, function() return db.list[CHARKEY] or "cys" end,
            function(v) db.list[CHARKEY] = v; offset = 0; Refresh() end)
        win.list:SetPoint("TOPLEFT", 14, -81)
        win.list:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Which BiS list", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Cys's picks: the best items found for you, scored with Cys's Upgrade weights.", 1, 1, 1, true)
            GameTooltip:AddLine("Wowhead pre-raid: the level 60 list from Wowhead's WoW Forever guide for that spec. The gain column still uses your weights.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        win.list:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    for n = 1, ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 8, LIST_TOP - (n - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -12, LIST_TOP - (n - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.hl = W.Texture(row, "BACKGROUND", T.selected)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.mark = W.Texture(row, "ARTWORK", T.green)
        row.mark:SetPoint("TOPLEFT", 0, -3)
        row.mark:SetPoint("BOTTOMLEFT", 0, 3)
        row.mark:SetWidth(2)
        row.rule = W.Texture(row, "ARTWORK", T.line)
        row.rule:SetPoint("BOTTOMLEFT", 4, 1)
        row.rule:SetPoint("BOTTOMRIGHT", -4, 1)
        row.rule:SetHeight(1)
        row.slot = W.Text(row, 11, T.text)
        row.slot:SetPoint("LEFT", 6, 0)
        row.slot:SetWidth(66)
        row.slot:SetWordWrap(false)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 74, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.more = W.Text(row, 10, T.text, "RIGHT")
        row.more:SetPoint("RIGHT", -4, 0)
        row.more:SetWidth(22)
        row.src = W.Text(row, 10, T.text, "RIGHT")
        row.src:SetPoint("RIGHT", row.more, "LEFT", -4, 0)
        row.src:SetWidth(190)
        row.src:SetWordWrap(false)
        row.gain = W.Text(row, 11, T.text, "RIGHT")
        row.gain:SetPoint("RIGHT", row.src, "LEFT", -6, 0)
        row.gain:SetWidth(46)
        row.name = W.Text(row, 12, T.text)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.gain, "LEFT", -6, 0)
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if self.v and self.v.kind ~= "head" then self.hl:Show() end
            RowTip(self)
        end)
        row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        row:SetScript("OnReceiveDrag", DropOnRow)
        row:SetScript("OnClick", function(self, button)
            local v = self.v
            if not (v and v.s) then return end
            if GetCursorInfo() then DropOnRow(self) return end
            if button == "RightButton" then
                if not v.wh and pins[v.s.k] then pins[v.s.k] = nil; QueueRecompute(0.05) end
                return
            end
            if IsModifiedClick and IsModifiedClick() and v.p then
                local i = info[v.p.id] or {}
                local link = v.p.link or i.link
                if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
                return
            end
            if v.kind == "slot" and not v.wh then expanded[v.s.k] = not expanded[v.s.k]; Refresh() end
        end)
        rows[n] = row
    end

    win.thumb = W.Texture(win, "OVERLAY", T.brand)
    win.thumb:SetWidth(3)
    win.thumb:Hide()

    win.foot = W.Text(win, 10, T.dim)
    win.foot:SetPoint("BOTTOMLEFT", 14, 10)
    win.foot:SetPoint("RIGHT", -14, 0)
    win.foot:SetWordWrap(false)

    win:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        PaintRows()
    end)
end

local function BuildOpener()
    if opener then return end
    opener = W.Button(UIParent, 44, 20, "BiS")
    opener:SetFrameStrata("HIGH")
    opener:Hide()
    opener:SetScript("OnClick", function() db.open = not db.open; Sync() end)
    opener:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Cys's BiS", T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddLine("Your best item for every slot.", 1, 1, 1)
        GameTooltip:Show()
    end)
    opener:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Our frames follow the character panel; Blizzard's frame is only used as an anchor.
local charUp = false
local armoryHooked
function Sync()
    local host = _G.CharacterFrame
    local panel = _G.CysArmoryFrame
    if panel and not armoryHooked and panel.HookScript then -- the Armory builds its panel late; follow it once it exists
        armoryHooked = true
        panel:HookScript("OnShow", function() if charUp then Sync() end end)
        panel:HookScript("OnHide", function() if charUp then Sync() end end)
    end
    if not (charUp and host) then
        if win then win:Hide() end
        if opener then opener:Hide() end
        return
    end
    BuildOpener()
    opener:ClearAllPoints()
    local armoryBtn = CysArmory and CysArmory.toggleButton
    if armoryBtn and armoryBtn:IsShown() then
        opener:SetPoint("RIGHT", armoryBtn, "LEFT", -4, 0)
    else -- the title row, left of the panel's close button (the stat pane's tabs sit lower)
        local x = host.CloseButton or _G.CharacterFrameCloseButton
        if x then opener:SetPoint("RIGHT", x, "LEFT", -6, 0)
        else opener:SetPoint("TOPRIGHT", host, "TOPRIGHT", -30, -4) end
    end
    opener:Show()
    if db.open then
        BuildWindow()
        win:ClearAllPoints()
        local armory = _G.CysArmoryFrame
        if armory and armory:IsShown() then
            win:SetPoint("TOPLEFT", armory, "TOPRIGHT", 4, 0)
        else
            win:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
        end
        win:Show()
        if state.sig == "" then QueueRecompute(0.05) end
        local ok, err = pcall(Refresh)
        if not ok and CUI.debug then CUI:Print("BiS: " .. tostring(err)) end
    elseif win then
        win:Hide()
    end
end

local hooked
local function Attach()
    if hooked then return end
    local host = _G.CharacterFrame
    if not (host and host.HookScript) then return end
    hooked = true
    host:HookScript("OnShow", function() charUp = true; Sync() end)
    host:HookScript("OnHide", function() charUp = false; Sync() end)
    local ok, vis = pcall(function() return host:IsVisible() and true or false end)
    charUp = ok and vis or false
    Sync()
end

--------------------------------------------------------------------------------
-- Tooltip mark and drop alert
--------------------------------------------------------------------------------
local function OnTip(tooltip, data)
    if not db.tipMark or not (tooltip == GameTooltip or tooltip == ItemRefTooltip) then return end
    if win and tooltip:GetOwner() and tooltip:GetOwner():GetParent() == win then return end
    local id = data and data.id
    if not id then return end
    local r = pickRank[id]
    if r then
        local prof = ProfileName()
        tooltip:AddLine(string.format("Cys BiS: #%d for %s%s", r.rank, r.label, prof ~= "" and (" (" .. prof .. ")") or ""), T.accent[1], T.accent[2], T.accent[3])
    end
    local specs = WHFor(id)
    if specs then tooltip:AddLine("Wowhead pre-raid BiS: " .. specs, T.accent[1], T.accent[2], T.accent[3], true) end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data) pcall(OnTip, tooltip, data) end)
end

local alerted = {}
local function Alert(link, how)
    local id = IDOf(link)
    local r = id and pickRank[id]
    if not (db.alert and r) then return end
    if Status(id) ~= "get" then return end
    local now = GetTime()
    if alerted[id] and now - alerted[id] < 60 then return end
    alerted[id] = now
    CUI:Print(string.format("BiS %s: %s - #%d for %s.", how, link, r.rank, r.label))
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, "BiS " .. how .. ": " .. link, { r = 1, g = 0.82, b = 0 })
    end
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
                     "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "LOOT_OPENED", "START_LOOT_ROLL",
                     "QUEST_DETAIL", "QUEST_COMPLETE", "MERCHANT_SHOW", "CHARACTER_POINTS_CHANGED",
                     "ACTIVE_TALENT_GROUP_CHANGED", "AUCTION_HOUSE_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local loadQueued, whQueued
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_LOGIN" then
        pcall(LoadSaved)
        Attach()
        QueueRecompute(6)
    elseif event == "ADDON_LOADED" then
        Attach()
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if whAsked[a1] and not whQueued and win and win:IsShown() then -- the Wowhead list fills in as its items arrive
            whQueued = true
            C_Timer.After(0.5, function() whQueued = false; if win and win:IsShown() then Refresh() end end)
        end
        if asked[a1] and not loadQueued then
            loadQueued = true
            C_Timer.After(8, function() loadQueued = false; QueueRecompute(0.05, true) end) -- batches of arrivals, not one refresh each
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahList = nil
        QueueRecompute(3)
    elseif event == "LOOT_OPENED" then
        local zone = ZoneName()
        for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
            local link = GetLootSlotLink(slot)
            if link then Remember(link, "loot", nil, zone); Alert(link, "drop") end
        end
    elseif event == "START_LOOT_ROLL" then
        local link = GetLootRollItemLink and GetLootRollItemLink(a1)
        if link then Remember(link, "roll", nil, ZoneName()); Alert(link, "roll") end
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        local title = GetTitleText and GetTitleText() or nil
        for n = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do Remember(GetQuestItemLink("choice", n), "quest", title) end
        for n = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do Remember(GetQuestItemLink("reward", n), "quest", title) end
        QueueRecompute(2)
    elseif event == "MERCHANT_SHOW" then
        local who, zone = UnitName("npc"), ZoneName()
        for n = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do Remember(GetMerchantItemLink(n), "vendor", who, zone) end
        QueueRecompute(2)
    else
        local open = win and win:IsShown()
        QueueRecompute(open and (event == "BAG_UPDATE_DELAYED" and 2 or 1) or 20)
    end
end)
Attach()

--------------------------------------------------------------------------------
-- /cuibis
--------------------------------------------------------------------------------
SLASH_CYSBIS1 = "/cuibis"
SlashCmdList["CYSBIS"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "check" then
        local n = 0
        for _ in pairs(cand) do n = n + 1 end
        CUI:Print(string.format("BiS: %d candidates, %d usable, %d loading. DungeonJournal: %s (%d dungeons). Auction House: %s (%d items). Seen: %d. Profile: %s.",
            n, state.total, state.loading, JournalDB() and "yes" or "no", srcCount.journal, AH() and "yes" or "no", srcCount.ah,
            srcCount.seen, ProfileName() ~= "" and ProfileName() or "none"))
        return
    elseif msg == "wowhead" then -- every Wowhead item for your class: does its ID show the guide's name in game?
        local bad, waiting, total = 0, 0, 0
        for _, sp in ipairs(WHSpecs()) do
            for _, key in ipairs(WH_KEYS) do
                local e = WHEntry(sp, key)
                if e then
                    total = total + 1
                    local n = GetItemInfo(e.id)
                    if not n then
                        waiting = waiting + 1
                        if RequestLoad then pcall(RequestLoad, e.id) end
                    elseif not SameName(n, e.name) then
                        bad = bad + 1
                        CUI:Print(string.format("BiS: %s %s - guide says %s, item %d is %s.", sp.label, key, e.name, e.id, n))
                    end
                end
            end
        end
        CUI:Print(string.format("BiS: %d Wowhead items for your class, %d with another name in game, %d still loading%s.",
            total, bad, waiting, waiting > 0 and " (run it again in a few seconds)" or ""))
        return
    end
    db.open = not db.open
    if not charUp and db.open and ToggleCharacter then
        CUI:Print("BiS: open your character panel (C) to see the list.")
    end
    Sync()
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("BiS List", function(page)
    local width = 480
    W.Header(page, "Cys's BiS", width):SetPoint("TOPLEFT", 0, -4)

    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34)
    intro:SetWidth(width - 8)
    intro:SetJustifyV("TOP")
    intro:SetSpacing(3)
    intro:SetText("A window beside the character panel with your best item for every slot, scored with Cys's Upgrade's weights for the profile you use, and where each item comes from. Open it with the BiS button on the character panel. Its dropdown also shows Wowhead's level 60 pre-raid list for each of your specs.")

    local y = -100
    local function Box(label, get, set)
        local c = W.Checkbox(page, label, get, set)
        c:SetPoint("TOPLEFT", 4, y)
        y = y - 28
        return c
    end
    Box("Mark BiS items on their tooltips", function() return db.tipMark end, function(on) db.tipMark = on end)
    Box("Tell me when a BiS item is in a loot or roll window", function() return db.alert end, function(on) db.alert = on end)
    Box("Use DungeonJournal's dungeon loot (when it is installed)", function() return db.journal end,
        function(on) db.journal = on; QueueRecompute(0.1) end)
    Box("Use the items Cys's Auction House has seen", function() return db.ah end,
        function(on) db.ah = on; QueueRecompute(0.1) end)
    Box("Body armor: only my best armor type (plate, mail...)", function() return db.armorBest end,
        function(on) db.armorBest = on; QueueRecompute(0.1) end)
    Box("Also allow the type below it (mail while moving to plate)", function() return db.armorBelow end,
        function(on) db.armorBelow = on; QueueRecompute(0.1) end)
    local st = W.Stepper(page, "Levels ahead", function() return db.ahead end,
        function(v) db.ahead = v; QueueRecompute(0.1) end, 0, 15, 1)
    st:SetPoint("TOPLEFT", 4, y - 4)
    y = y - 40

    W.Notes(page, 4, y, width, "", {
        "Weights come from Cys's Upgrade: pick or edit a profile there. Tank profiles get a Survival / Threat blend you set with the - and + buttons in the window (SixtyUpgrades' WoW Forever presets).",
        "Items weighed: what you wear and carry, DungeonJournal's dungeon loot and quest rewards, the gear Cys's Auction House has seen on your realm, and gear you meet in loot, roll windows, quest rewards and vendors.",
        "Levels ahead: items may need up to this many levels over yours; those show their level in red. Dungeons far below or above your level are skipped.",
        "Armor type: warriors and paladins get plate (and mail) from 40, hunters and shamans mail (and leather). Cloaks, rings, necks and trinkets are never limited.",
        "Drop an item on a slot to pin it as that slot's BiS; right-click the slot to unpin. Click a slot for its other picks.",
        "Dungeon loot data: the DungeonJournal addon by Exehn. Thank you!",
        { "/cuibis", "open or close the window; /cuibis check prints what was read" },
    })
end)

    end,
})
