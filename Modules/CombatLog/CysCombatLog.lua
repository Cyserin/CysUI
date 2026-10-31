--------------------------------------------------------------------------------
-- Cys's logs - full dungeon / raid runs, kept between sessions
--
-- One RUN is everything that happens from walking into a group instance until you leave it (walking out to
-- run back after a death does not end it; it ends after 15 minutes outside, or when you enter another
-- instance). A run holds:
--   bosses[]  one entry per boss attempt (kill or wipe), each with its own per-player tables
--   trash     everything that was not a boss, summed up (pulls, time, per-player tables)
--   players   every group member for the whole run: damage, healing, damage taken, casts, hits, crits,
--             per-ability tables, who they took damage from
--   deaths[]  every player death with the last 10 events that hit that player (damage, heals, aura changes)
-- The newest runs are kept in SavedVariables (3 to 10 of them, your choice). Open it with /cuilog.
--------------------------------------------------------------------------------
local CUI = CysUI
local W = CUI.W
local T = W.T

local band = bit.band
local max, min, floor = math.max, math.min, math.floor

local DEFAULTS = { record = true, keepRuns = 5, autoLog = false }
local function DB()
    CysUIDB = CysUIDB or {}
    CysUIDB.combatLog = CysUIDB.combatLog or {}
    local db = CysUIDB.combatLog
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.runs = db.runs or {}
    db.avoidable = db.avoidable or {}   -- spell ids you added with /cuilog avoid
    db.learned = db.learned or {}      -- boss npc id -> name (learned from your game, or /cuilog boss)
    db.fights = nil                    -- the old 15-fight list is gone
    db.keep = nil
    return db
end

local IDLE_END = 6          -- seconds with nothing happening end a pull
local RESUME_GRACE = 900    -- seconds outside the instance before a run is closed
local RING = 10             -- events kept per player for the death recap

------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Known bosses (npc id -> name) for the 15-60 dungeons, from the CMaNGOS Classic database (names matched to
-- ids one by one; Stratholme's Malor and Galford agree with BigWigs/LittleWigs). There is no raid data here
-- on purpose. Add any boss that is missing with /cuilog boss on it once; the game remembers it.
--------------------------------------------------------------------------------
local BOSS_IDS = {
    -- Ragefire Chasm
    [11517] = "Oggleflint", [11520] = "Taragaman the Hungerer", [11518] = "Jergosh the Invoker",
    [11519] = "Bazzalan",
    -- Wailing Caverns
    [3669] = "Lord Cobrahn", [3671] = "Lady Anacondra", [3653] = "Kresh", [3670] = "Lord Pythas", [3674] = "Skum",
    [3673] = "Lord Serpentis", [5775] = "Verdan the Everliving", [3654] = "Mutanus the Devourer",
    -- Deadmines
    [644] = "Rhahk'Zor", [642] = "Sneed's Shredder", [643] = "Sneed", [1763] = "Gilnid", [646] = "Mr. Smite",
    [647] = "Captain Greenskin", [639] = "Edwin VanCleef", [645] = "Cookie",
    -- Shadowfang Keep
    [3914] = "Rethilgore", [3886] = "Razorclaw the Butcher", [3887] = "Baron Silverlaine",
    [4278] = "Commander Springvale", [4279] = "Odo the Blindwatcher", [4274] = "Fenrus the Devourer",
    [3927] = "Wolf Master Nandos", [4275] = "Archmage Arugal",
    -- Blackfathom Deeps
    [4887] = "Ghamoo-ra", [4831] = "Lady Sarevess", [6243] = "Gelihast", [12876] = "Baron Aquanis",
    [4832] = "Twilight Lord Kelris", [4830] = "Old Serra'kis", [4829] = "Aku'mai",
    -- Stockade
    [1696] = "Targorr the Dread", [1666] = "Kam Deepfury", [1717] = "Hamhock", [1663] = "Dextren Ward",
    [1716] = "Bazil Thredd",
    -- Gnomeregan
    [7361] = "Grubbis", [7079] = "Viscous Fallout", [6235] = "Electrocutioner 6000", [6229] = "Crowd Pummeler 9-60",
    [6228] = "Dark Iron Ambassador", [7800] = "Mekgineer Thermaplugg",
    -- Razorfen Kraul
    [6168] = "Roogug", [4424] = "Aggem Thorncurse", [4428] = "Death Speaker Jargba", [4420] = "Overlord Ramtusk",
    [4422] = "Agathelos the Raging", [4421] = "Charlga Razorflank",
    -- Scarlet Monastery
    [3983] = "Interrogator Vishas", [4543] = "Bloodmage Thalnos", [3974] = "Houndmaster Loksey",
    [6487] = "Arcanist Doan", [3975] = "Herod", [4542] = "High Inquisitor Fairbanks",
    [3976] = "Scarlet Commander Mograine", [3977] = "High Inquisitor Whitemane",
    -- Razorfen Downs
    [7355] = "Tuten'kash", [7357] = "Mordresh Fire Eye", [8567] = "Glutton", [7354] = "Ragglesnout",
    [7358] = "Amnennar the Coldbringer", [7356] = "Plaguemaw the Rotting",
    -- Uldaman
    [6910] = "Revelosh", [6906] = "Baelog", [6907] = "Eric \"The Swift\"", [6908] = "Olaf", [7228] = "Ironaya",
    [7023] = "Obsidian Sentinel", [7206] = "Ancient Stone Keeper", [7291] = "Galgann Firehammer", [4854] = "Grimlok",
    [2748] = "Archaedas",
    -- Zul'Farrak
    [8127] = "Antu'sul", [7272] = "Theka the Martyr", [7271] = "Witch Doctor Zum'rah", [7796] = "Nekrum Gutchewer",
    [7275] = "Shadowpriest Sezz'ziz", [10081] = "Dustwraith", [7604] = "Sergeant Bly",
    [7795] = "Hydromancer Velratha", [7273] = "Gahz'rilla", [7267] = "Chief Ukorz Sandscalp",
    -- Maraudon
    [13282] = "Noxxion", [12258] = "Razorlash", [12236] = "Lord Vyletongue", [12225] = "Celebras the Cursed",
    [12203] = "Landslide", [13601] = "Tinkerer Gizlock", [13596] = "Rotgrip", [12201] = "Princess Theradras",
    -- Sunken Temple
    [8580] = "Atal'alarion", [5721] = "Dreamscythe", [5720] = "Weaver", [5710] = "Jammal'an the Prophet",
    [5711] = "Ogom the Wretched", [5719] = "Morphaz", [5722] = "Hazzas", [5709] = "Shade of Eranikus",
    [8443] = "Avatar of Hakkar",
    -- Blackrock Depths
    [9025] = "Lord Roccor", [9018] = "High Interrogator Gerstahn", [9319] = "Houndmaster Grebmar",
    [9031] = "Anub'shiah", [9029] = "Eviscerator", [9027] = "Gorosh the Dervish", [9028] = "Grizzle",
    [9032] = "Hedrum the Creeper", [9030] = "Ok'thor the Breaker", [9024] = "Pyromancer Loregrain",
    [9041] = "Warder Stilgiss", [9042] = "Verek", [9056] = "Fineous Darkvire", [9017] = "Lord Incendius",
    [9016] = "Bael'Gar", [9033] = "General Angerforge", [8983] = "Golem Lord Argelmach",
    [9537] = "Hurley Blackbreath", [9502] = "Phalanx", [9543] = "Ribbly Screwspigot", [9499] = "Plugger Spazzring",
    [9156] = "Ambassador Flamelash", [9938] = "Magmus", [9019] = "Emperor Dagran Thaurissan",
    [8929] = "Princess Moira Bronzebeard", [9039] = "Doom'rel", [9037] = "Gloom'rel",
    -- Lower Blackrock Spire
    [9196] = "Highlord Omokk", [9236] = "Shadow Hunter Vosh'gajin", [9237] = "War Master Voone",
    [10596] = "Mother Smolderweb", [10584] = "Urok Doomhowl", [9736] = "Quartermaster Zigris",
    [10268] = "Gizrul the Slavener", [10220] = "Halycon", [9568] = "Overlord Wyrmthalak",
    -- Upper Blackrock Spire
    [9816] = "Pyroguard Emberseer", [10264] = "Solakar Flamewreath", [10509] = "Jed Runewatcher",
    [10899] = "Goraluk Anvilcrack", [10429] = "Warchief Rend Blackhand", [10430] = "The Beast",
    [10363] = "General Drakkisath",
    -- Stratholme
    [10393] = "Skul", [10558] = "Hearthsinger Forresten", [10808] = "Timmy the Cruel", [11032] = "Malor the Zealous",
    [10997] = "Cannon Master Willey", [10811] = "Archivist Galford", [10813] = "Balnazzar",
    [10812] = "Grand Crusader Dathrohan", [10436] = "Baroness Anastari", [10437] = "Nerub'enkan",
    [10438] = "Maleki the Pallid", [10435] = "Magistrate Barthilas", [10439] = "Ramstein the Gorger",
    [10440] = "Baron Rivendare", [10516] = "The Unforgiven", [11143] = "Postmaster Malown", [11058] = "Fras Siabi",
    -- Scholomance
    [14861] = "Blood Steward of Kirtonos", [10506] = "Kirtonos the Herald", [10503] = "Jandice Barov",
    [11622] = "Rattlegore", [10433] = "Marduk Blackpool", [10432] = "Vectus", [10508] = "Ras Frostwhisper",
    [10505] = "Instructor Malicia", [11261] = "Doctor Theolen Krastinov", [10901] = "Lorekeeper Polkelt",
    [10507] = "The Ravenian", [10504] = "Lord Alexei Barov", [10502] = "Lady Illucia Barov",
    [1853] = "Darkmaster Gandling",
    -- Dire Maul
    [11490] = "Zevrim Thornhoof", [13280] = "Hydrospawn", [14327] = "Lethtendris", [11492] = "Alzzin the Wildshaper",
    [11489] = "Tendris Warpwood", [11488] = "Illyanna Ravenoak", [11487] = "Magister Kalendris",
    [11496] = "Immol'thar", [11486] = "Prince Tortheldrin", [14326] = "Guard Mol'dar", [14322] = "Stomper Kreeg",
    [14321] = "Guard Fengus", [14323] = "Guard Slip'kik", [14325] = "Captain Kromcrush",
    [14324] = "Cho'Rush the Observer", [11501] = "King Gordok",
}

--------------------------------------------------------------------------------
-- Phase 2 lookups
--------------------------------------------------------------------------------
-- Damage that standing in the right place avoids. Checked against the CMaNGOS database: 11990 is the Sandfury
-- Firecaller's Rain of Fire (Zul'Farrak). Add more in game with /cuilog avoid <spell id>.
local AVOIDABLE = { [11990] = "Rain of Fire" }
-- Dungeon mechanics that punish a group when they land on a player (counted as "mechanics hit" on the
-- Mistakes tab). Ids and casters checked against the same database.
local MECH_AURAS = {
    [8040] = "Druid's Slumber",        -- Druid of the Fang (Wailing Caverns)
    [7967] = "Naralex's Nightmare",    -- Mutanus the Devourer (Wailing Caverns)
    [7621] = "Arugal's Curse",         -- Shadowfang Keep
    [8377] = "Earthgrab",              -- Razorfen Totemic's Earthgrab Totem (Razorfen Kraul)
    [9256] = "Deep Sleep",             -- High Inquisitor Whitemane (Scarlet Monastery)
    [11641] = "Hex",                   -- Sandfury Shadowhunter (Zul'Farrak)
    [12890] = "Deep Slumber",          -- Shade of Eranikus (Sunken Temple)
}
-- Enemy casts that mean the group did not stop something (counted once per run on the Mistakes tab)
local MECH_CASTS = { [3605] = "Remote-Controlled Golem summoned (Goblin Engineer, Deadmines)" }
-- debuffs whose uptime on a boss is measured (matched by name, so every rank counts)
local BOSS_DEBUFFS = {
    ["Sunder Armor"] = "Sunder Armor", ["Faerie Fire"] = "Faerie Fire", ["Faerie Fire (Feral)"] = "Faerie Fire",
    ["Curse of Recklessness"] = "Curse of Recklessness", ["Demoralizing Shout"] = "Demoralizing Shout",
    ["Thunder Clap"] = "Thunder Clap",
}
-- buffs measured on each group member (seconds of combat they had it)
local PLAYER_BUFFS = { ["Shield Block"] = true, ["Stoneskin"] = true, ["Windfury Totem"] = true, ["Strength of Earth"] = true }
-- totems measured by how long they stood (seconds): name -> lifetime
local TOTEM_LIFE = { ["Tremor Totem"] = 120, ["Windfury Totem"] = 120, ["Stoneskin Totem"] = 120, ["Grace of Air Totem"] = 120,
                     ["Mana Spring Totem"] = 120, ["Healing Stream Totem"] = 120, ["Strength of Earth Totem"] = 120,
                     ["Searing Totem"] = 60, ["Fire Nova Totem"] = 6 }
local rockOn, myGUID = false, nil   -- own weapon carries Rockbiter (read from its tooltip once a second)
local TAUNTS = { ["Taunt"] = true, ["Growl"] = true, ["Mocking Blow"] = true, ["Challenging Shout"] = true, ["Challenging Roar"] = true }
local AREA_TAUNTS = { ["Challenging Shout"] = true, ["Challenging Roar"] = true }

local debuffs, pbuffs, totems, totByOwner = {}, {}, {}, {}   -- open timers, see AuraEvent / Totem handling

local function Overlap(a1, a2, b1, b2) return max(0, min(a2, b2) - max(a1, b1)) end
local function Credit(map, guid, name, secs)
    if secs <= 0 then return end
    local m = map[guid]
    if not m then m = {}; map[guid] = m end
    m[name] = (m[name] or 0) + secs
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local run            -- the active run (also saved in SavedVariables as db.active)
local pull           -- the pull being recorded (not saved)
local ringBy = {}    -- player guid -> ring of the last events that hit them
local petOwner = {}  -- pet guid -> owner player guid
local classBy = {}   -- player guid -> class token
local bossCache = {} -- creature guid -> boss info | false
local CL = {}
CUI.CombatLog = CL

local function NpcID(guid)
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

local function BossInfo(guid)
    if not guid then return nil end
    local c = bossCache[guid]
    if c ~= nil then return c or nil end
    c = false
    if guid:find("^Creature") or guid:find("^Vehicle") then
        local id = NpcID(guid)
        local db = DB()
        if id and (BOSS_IDS[id] or db.learned[id]) then c = { id = id, name = BOSS_IDS[id] or db.learned[id] } end
    end
    bossCache[guid] = c
    return c or nil
end

--------------------------------------------------------------------------------
-- Players and their tables
--------------------------------------------------------------------------------
local NUM_FIELDS = { "damage", "healing", "overheal", "taken", "casts", "hits", "crits", "healHits", "healCrits",
                     "deaths", "interrupts", "dispels", "avoidDamage", "avoidHits", "taunts", "tauntsLanded", "tauntsMissed",
                     "mechHits", "blocks", "blockedDmg", "swingsIn", "rockDamage" }
local MAP_FIELDS = { "avoidSpells", "uptime", "stopped", "dispelled", "tauntMiss", "hitBy" }

local function NewPlayer(guid, name, class)
    return { guid = guid, name = name, class = class, damage = 0, healing = 0, overheal = 0, taken = 0, casts = 0,
             hits = 0, crits = 0, healHits = 0, healCrits = 0, deaths = 0, interrupts = 0, dispels = 0,
             avoidDamage = 0, avoidHits = 0, taunts = 0, tauntsLanded = 0, tauntsMissed = 0,
             mechHits = 0, blocks = 0, blockedDmg = 0, swingsIn = 0, rockDamage = 0,
             spells = {}, takenFrom = {}, avoidSpells = {}, uptime = {}, stopped = {}, dispelled = {}, tauntMiss = {}, hitBy = {} }
end

-- p for an actor in a players table (created from what the run already knows about them)
local function GetP(tbl, key)
    local p = tbl[key]
    if not p then
        local base = run and run.players[key]
        p = NewPlayer(key, base and base.name or "?", base and base.class or classBy[key])
        tbl[key] = p
    end
    return p
end

local function Spell(p, name)
    local s = p.spells[name]
    if not s then
        s = { damage = 0, healing = 0, overheal = 0, casts = 0, hits = 0, crits = 0, max = 0 }
        p.spells[name] = s
    end
    return s
end

-- who gets the credit: the player, or the owner of a pet (spell shows as "Pet: ...")
local function Actor(guid, name, spell)
    if guid:find("^Player") then return guid, spell end
    local owner = petOwner[guid]
    if owner then return owner, "Pet: " .. spell end
    local tot = totems[guid]
    if tot then return tot.owner, "Totem: " .. spell end
    -- an unowned guardian or totem: listed under its own name
    if run and not run.players[guid] then
        run.players[guid] = NewPlayer(guid, name or "?", nil)
        run.players[guid].isPet = true
    end
    return guid, spell
end

local function EnsurePlayer(guid, name, class)
    if not run or not guid then return end
    local p = run.players[guid]
    if not p then
        run.players[guid] = NewPlayer(guid, name, class)
    else
        p.name = name or p.name
        p.class = class or p.class
    end
end

local function RefreshRoster()
    wipe(petOwner)
    local function Add(unit)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        local _, class = UnitClass(unit)
        classBy[guid] = class
        EnsurePlayer(guid, UnitName(unit), class)
        local pg = UnitGUID(unit == "player" and "pet" or (unit .. "pet"))
        if pg then petOwner[pg] = guid end
    end
    Add("player")
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    elseif IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i) end
    end
end

--------------------------------------------------------------------------------
-- Recording into a players table
--------------------------------------------------------------------------------
local function AddDamage(tbl, key, spell, amount, crit)
    local p = GetP(tbl, key)
    p.damage = p.damage + amount
    p.hits = p.hits + 1
    local s = Spell(p, spell)
    s.damage = s.damage + amount
    s.hits = s.hits + 1
    if crit then p.crits = p.crits + 1; s.crits = s.crits + 1 end
    if amount > s.max then s.max = amount end
end

local function AddHeal(tbl, key, spell, eff, over, crit)
    local p = GetP(tbl, key)
    p.healing = p.healing + eff
    p.overheal = p.overheal + over
    p.healHits = p.healHits + 1
    local s = Spell(p, spell)
    s.healing = s.healing + eff
    s.overheal = s.overheal + over
    s.hits = s.hits + 1
    if crit then p.healCrits = p.healCrits + 1; s.crits = s.crits + 1 end
    if eff > s.max then s.max = eff end
end

local function AddTaken(tbl, key, from, amount)
    local p = GetP(tbl, key)
    p.taken = p.taken + amount
    p.takenFrom[from] = (p.takenFrom[from] or 0) + amount
end

local function AddCast(tbl, key, spell)
    local p = GetP(tbl, key)
    p.casts = p.casts + 1
    local s = Spell(p, spell)
    s.casts = s.casts + 1
end

local function AddCount(tbl, key, field)
    local p = GetP(tbl, key)
    p[field] = p[field] + 1
end

-- sum one players table into another
local function MergePlayers(dst, src)
    for key, p in pairs(src) do
        local d = dst[key]
        if not d then
            d = NewPlayer(key, p.name, p.class)
            d.isPet = p.isPet
            dst[key] = d
        end
        for _, f in ipairs(NUM_FIELDS) do d[f] = d[f] + (p[f] or 0) end
        for name, s in pairs(p.spells) do
            local ds = d.spells[name]
            if not ds then
                ds = { damage = 0, healing = 0, overheal = 0, casts = 0, hits = 0, crits = 0, max = 0 }
                d.spells[name] = ds
            end
            ds.damage = ds.damage + s.damage
            ds.healing = ds.healing + s.healing
            ds.overheal = ds.overheal + s.overheal
            ds.casts = ds.casts + s.casts
            ds.hits = ds.hits + s.hits
            ds.crits = ds.crits + s.crits
            if s.max > ds.max then ds.max = s.max end
        end
        for from, amt in pairs(p.takenFrom) do d.takenFrom[from] = (d.takenFrom[from] or 0) + amt end
        for _, f in ipairs(MAP_FIELDS) do
            if p[f] then
                d[f] = d[f] or {}
                for k, v in pairs(p[f]) do d[f][k] = (d[f][k] or 0) + v end
            end
        end
    end
end
CL.MergePlayers = MergePlayers

-- keep saved data small: drop abilities that did next to nothing, keep the biggest damage sources
local function Prune(players)
    for _, p in pairs(players) do
        local total = p.damage + p.healing
        for name, s in pairs(p.spells) do
            if s.casts == 0 and (s.damage + s.healing) < total * 0.001 then p.spells[name] = nil end
        end
        local list = {}
        for from, amt in pairs(p.takenFrom) do list[#list + 1] = { from, amt } end
        if #list > 14 then
            table.sort(list, function(a, b) return a[2] > b[2] end)
            for i = 15, #list do p.takenFrom[list[i][1]] = nil end
        end
    end
end

--------------------------------------------------------------------------------
-- Death recap: a ring of the last events that hit each player
--------------------------------------------------------------------------------
local function Push(guid, kind, amt, src, spell, extra)
    local r = ringBy[guid]
    if not r then r = { i = 0, n = 0 }; ringBy[guid] = r end
    r.i = r.i % RING + 1
    if r.n < RING then r.n = r.n + 1 end
    local e = r[r.i]
    if not e then e = {}; r[r.i] = e end
    e.t, e.k, e.amt, e.src, e.spell, e.extra = GetTime(), kind, amt, src, spell, extra
end

local function Freeze(guid)
    local r, out = ringBy[guid], {}
    if not r then return out end
    local now = GetTime()
    local start = r.n < RING and 1 or (r.i % RING + 1)
    for n = 0, r.n - 1 do
        local e = r[(start - 1 + n) % RING + 1]
        out[#out + 1] = { ago = now - e.t, k = e.k, amt = e.amt, src = e.src, spell = e.spell, extra = e.extra }
    end
    return out
end

local function RecordDeath(guid, name)
    local ev = Freeze(guid)
    local taken, healed, killer, kspell, over = 0, 0, nil, nil, nil
    for _, e in ipairs(ev) do
        if e.k == "d" then taken = taken + (e.amt or 0); killer, kspell, over = e.src, e.spell, e.extra
        elseif e.k == "h" then healed = healed + (e.amt or 0) end
    end
    local d = { guid = guid, name = name, class = classBy[guid], t = time() - run.startTime, pullId = pull and pull.id,
                killer = killer, spell = kspell, overkill = over, taken = taken, healed = healed, events = ev }
    run.deaths[#run.deaths + 1] = d
    AddCount(run.players, guid, "deaths")
    if pull then AddCount(pull.players, guid, "deaths") end
    ringBy[guid] = nil
    if guid == UnitGUID("player") then
        CUI:Print("You died" .. (killer and (" - last hit: " .. tostring(killer) .. "'s " .. tostring(kspell)) or "") .. ". Open /cuilog for the full recap.")
    end
end

--------------------------------------------------------------------------------
-- Pulls: boss attempts and trash
--------------------------------------------------------------------------------
local function StartPull()
    run.pullCounter = (run.pullCounter or 0) + 1
    pull = { id = run.pullCounter, startTime = time(), t0 = GetTime(), last = GetTime(), players = {}, enemies = {},
             bossGUIDs = {}, boss = nil, killed = false, bossUp = {}, pbUp = {}, totUp = {} }
    RefreshRoster()
end

local function MarkBoss(info, guid)
    if not pull then return end
    if not pull.boss then pull.boss = info end
    if guid then pull.bossGUIDs[guid] = true end
end

local function FinishPull()
    if not pull or not run then pull = nil; return end
    local p = pull
    pull = nil
    local dur = max(1, p.last - p.t0)
    local any = false
    for _, pl in pairs(p.players) do
        if pl.damage > 0 or pl.taken > 0 or pl.healing > 0 then any = true; break end
    end
    if not any then return end
    -- timers still open at the end of the pull count up to its last event
    local t0, lim = p.t0, p.last
    for guid, t in pairs(debuffs) do
        if p.bossGUIDs[guid] then
            for name, rec in pairs(t) do Credit(p.bossUp, guid, name, Overlap(rec.since, lim, t0, lim)) end
        end
    end
    for guid, t in pairs(pbuffs) do
        for name, rec in pairs(t) do Credit(p.pbUp, guid, name, Overlap(rec.since, lim, t0, lim)) end
    end
    for _, rec in pairs(totems) do
        Credit(p.totUp, rec.owner, rec.name, Overlap(rec.since, min(lim, rec.since + rec.life), t0, lim))
    end
    for _, map in ipairs({ p.pbUp, p.totUp }) do
        for guid, m in pairs(map) do
            for name, secs in pairs(m) do
                local u = GetP(p.players, guid).uptime
                u[name] = (u[name] or 0) + secs
                local ru = GetP(run.players, guid).uptime
                ru[name] = (ru[name] or 0) + secs
            end
        end
    end
    local ups = {}
    for _, m in pairs(p.bossUp) do
        for name, secs in pairs(m) do ups[name] = max(ups[name] or 0, min(secs, dur)) end
    end
    run.combatTime = (run.combatTime or 0) + dur
    if p.boss then
        local attempt = 1
        for _, b in ipairs(run.bosses) do if b.name == p.boss.name then attempt = attempt + 1 end end
        Prune(p.players)
        run.bosses[#run.bosses + 1] = { name = p.boss.name, id = p.boss.id, attempt = attempt, pullId = p.id,
            startTime = p.startTime, endTime = time(), dur = dur, result = p.killed and "kill" or "wipe",
            players = p.players, enemies = p.enemies, uptimes = ups }
    else
        local tr = run.trash
        tr.pulls = tr.pulls + 1
        tr.time = tr.time + dur
        MergePlayers(tr.players, p.players)
        for name, amt in pairs(p.enemies) do tr.enemies[name] = (tr.enemies[name] or 0) + amt end
    end
end

--------------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------------
local function NewRun(zone, mapID, manual)
    return { zoneName = zone, mapID = mapID, startTime = time(), endTime = nil, manual = manual or nil,
             bosses = {}, trash = { pulls = 0, time = 0, players = {}, enemies = {} }, players = {}, deaths = {},
             combatTime = 0, pullCounter = 0 }
end

local loggingByUs = false
local function StartRun(zone, mapID, manual)
    local db = DB()
    pull = nil
    wipe(ringBy); wipe(bossCache); wipe(debuffs); wipe(pbuffs); wipe(totems); wipe(totByOwner)
    run = NewRun(zone, mapID, manual)
    db.active = run
    RefreshRoster()
    if db.autoLog and LoggingCombat and not LoggingCombat() then
        LoggingCombat(true); loggingByUs = true
        CUI:Print("Cys's logs: started a run in " .. zone .. " (the game's own combat log is on too).")
    else
        CUI:Print("Cys's logs: started a run in " .. zone .. ". /cuilog to view it.")
    end
    if CL.Refresh then CL.Refresh() end
end

local function FinalizeRun()
    if not run then return end
    FinishPull()
    local db = DB()
    run.endTime = time()
    run.dur = run.endTime - run.startTime
    Prune(run.players)
    Prune(run.trash.players)
    local nBoss = #run.bosses
    local r = run
    run = nil
    db.active = nil
    wipe(ringBy)
    if loggingByUs and LoggingCombat then LoggingCombat(false); loggingByUs = false end
    -- a run with nothing in it is not worth keeping
    if (r.combatTime or 0) < 5 then return end
    table.insert(db.runs, 1, r)
    while #db.runs > (db.keepRuns or 5) do table.remove(db.runs) end
    CUI:Print(string.format("Cys's logs: saved %s (%d boss attempt%s, %d trash pull%s, %d death%s).", r.zoneName,
        nBoss, nBoss == 1 and "" or "s", r.trash.pulls, r.trash.pulls == 1 and "" or "s", #r.deaths, #r.deaths == 1 and "" or "s"))
    if CL.Refresh then CL.Refresh() end
end

local expireTimer
local function CheckExpire()
    local db = DB()
    local a = db.active
    if not a or a.manual or not a.leftAt then return end
    if time() - a.leftAt >= RESUME_GRACE then
        run = a
        FinalizeRun()
    end
end

-- entering or leaving a group instance (ZONE_CHANGED_NEW_AREA / PLAYER_ENTERING_WORLD)
local function CheckZone()
    local db = DB()
    if not db.record then return end
    local name, itype, _, _, _, _, _, mapID = GetInstanceInfo()
    local inGroupInstance = IsInInstance() and (itype == "party" or itype == "raid")
    local a = db.active
    if a and a.manual then run = a; return end
    if inGroupInstance then
        if a and a.mapID == mapID then
            a.leftAt = nil                      -- back in (reload, or ran back after dying)
            if not run then run = a; RefreshRoster() end
        else
            if a then run = a; FinalizeRun() end
            StartRun(name, mapID)
        end
    else
        if a then
            if not run then run = a end
            if not a.leftAt then
                a.leftAt = time()
                FinishPull()
                if C_Timer then C_Timer.After(RESUME_GRACE + 5, CheckExpire) end
            else
                CheckExpire()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Combat log
--------------------------------------------------------------------------------
local HANDLED = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true, SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true, SPELL_CAST_SUCCESS = true,
    SPELL_INTERRUPT = true, SPELL_DISPEL = true, SPELL_AURA_REMOVED = true, SPELL_AURA_APPLIED = true, UNIT_DIED = true,
    SPELL_AURA_REFRESH = true, SPELL_MISSED = true, SPELL_SUMMON = true, UNIT_DESTROYED = true, SWING_MISSED = true }

local function CloseTotem(guid, now)
    local rec = totems[guid]
    if not rec then return end
    totems[guid] = nil
    if totByOwner[rec.owner .. rec.name] == guid then totByOwner[rec.owner .. rec.name] = nil end
    if pull then
        Credit(pull.totUp, rec.owner, rec.name, Overlap(rec.since, min(now, rec.since + rec.life), pull.t0, now))
    end
end

-- buff / debuff timers: boss debuffs, a few buffs on group members, and group members' taunts landing
local function Each(guid, fn)
    fn(GetP(run.players, guid))
    if pull then fn(GetP(pull.players, guid)) end
end

local function AuraEvent(sub, now, sGUID, sGroup, dGUID, dGroup, dPlayer, spell, spellId)
    local removed = sub == "SPELL_AURA_REMOVED"
    if sub == "SPELL_AURA_APPLIED" and dPlayer and spellId and MECH_AURAS[spellId] then
        local label = MECH_AURAS[spellId]
        Each(dGUID, function(mp)
            mp.mechHits = mp.mechHits + 1
            mp.hitBy[label] = (mp.hitBy[label] or 0) + 1
        end)
    end
    local key = BOSS_DEBUFFS[spell]
    if key and not dGroup and BossInfo(dGUID) then
        local t = debuffs[dGUID]
        if not t then t = {}; debuffs[dGUID] = t end
        if removed then
            local rec = t[key]
            if rec then
                if pull then Credit(pull.bossUp, dGUID, key, Overlap(rec.since, now, pull.t0, now)) end
                t[key] = nil
            end
        elseif not t[key] then
            t[key] = { since = now }
        end
    end
    if PLAYER_BUFFS[spell] and dPlayer then
        local t = pbuffs[dGUID]
        if not t then t = {}; pbuffs[dGUID] = t end
        if removed then
            local rec = t[spell]
            if rec then
                if pull then Credit(pull.pbUp, dGUID, spell, Overlap(rec.since, now, pull.t0, now)) end
                t[spell] = nil
            end
        elseif not t[spell] then
            t[spell] = { since = now }
        end
    end
    -- a single-target taunt that lands puts its debuff on the mob
    if sub == "SPELL_AURA_APPLIED" and TAUNTS[spell] and not AREA_TAUNTS[spell] and sGroup and not dGroup and sGUID then
        local owner = Actor(sGUID, nil, spell)
        AddCount(run.players, owner, "tauntsLanded")
        if pull then AddCount(pull.players, owner, "tauntsLanded") end
    end
end

local function OnCombatLog()
    if not run or run.leftAt then return end
    local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, dFlags, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21 =
        CombatLogGetCurrentEventInfo()
    if not HANDLED[sub] then return end
    local sGroup = sFlags and band(sFlags, 0x7) ~= 0
    local dGroup = dFlags and band(dFlags, 0x7) ~= 0
    if sub == "SPELL_CAST_SUCCESS" and MECH_CASTS[a12] then
        run.mechCasts = run.mechCasts or {}
        local label = MECH_CASTS[a12]
        run.mechCasts[label] = (run.mechCasts[label] or 0) + 1
        return
    end
    if sub ~= "UNIT_DIED" and not sGroup and not dGroup then return end   -- (a boss dying has no group flags)

    local now = GetTime()
    local dPlayer = dGroup and dGUID and dGUID:find("^Player")

    -- damage ---------------------------------------------------------------
    local amount, spell, crit, over, blocked
    if sub == "SWING_DAMAGE" then amount, spell, over, crit, blocked = a12, "Melee", a13, a18, a16
    elseif sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then
        amount, spell, over, crit, blocked = a15, a13, a16, a21, a19
    end
    if amount then
        if amount <= 0 then return end
        if not pull then StartPull() end
        pull.last = now
        local bi = (not sGroup and BossInfo(sGUID)) or (not dGroup and BossInfo(dGUID))
        if bi then MarkBoss(bi, (not sGroup) and sGUID or dGUID) end
        if sGroup and not dGroup then
            local key, sp = Actor(sGUID, sName, spell or "?")
            AddDamage(run.players, key, sp, amount, crit)
            AddDamage(pull.players, key, sp, amount, crit)
            if sub == "SWING_DAMAGE" and rockOn and sGUID == myGUID then
                GetP(run.players, key).rockDamage = GetP(run.players, key).rockDamage + amount
                GetP(pull.players, key).rockDamage = GetP(pull.players, key).rockDamage + amount
            end
            local en = dName or "?"
            pull.enemies[en] = (pull.enemies[en] or 0) + amount
        end
        if dPlayer then
            local from = tostring(sName or "?") .. ": " .. tostring(spell or "?")
            AddTaken(run.players, dGUID, from, amount)
            AddTaken(pull.players, dGUID, from, amount)
            Each(dGUID, function(bp)
                if sub == "SWING_DAMAGE" then bp.swingsIn = bp.swingsIn + 1 end
                if blocked and blocked > 0 then bp.blocks = bp.blocks + 1; bp.blockedDmg = bp.blockedDmg + blocked end
            end)
            if sub ~= "SWING_DAMAGE" and (AVOIDABLE[a12] or DB().avoidable[a12]) then
                local label = AVOIDABLE[a12] or spell or "?"
                for _, tbl in ipairs({ run.players, pull.players }) do
                    local ap = GetP(tbl, dGUID)
                    ap.avoidDamage = ap.avoidDamage + amount
                    ap.avoidHits = ap.avoidHits + 1
                    ap.avoidSpells[label] = (ap.avoidSpells[label] or 0) + amount
                end
            end
            Push(dGUID, "d", amount, sName, spell, (over and over > 0) and over or nil)
        end
        return
    end

    -- healing --------------------------------------------------------------
    if sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        local overheal = a16 or 0
        local eff = (a15 or 0) - overheal
        if sGroup and (eff > 0 or overheal > 0) and pull then
            local key, sp = Actor(sGUID, sName, a13 or "?")
            AddHeal(run.players, key, sp, max(eff, 0), overheal, a18)
            AddHeal(pull.players, key, sp, max(eff, 0), overheal, a18)
        end
        if dPlayer and eff > 0 then Push(dGUID, "h", eff, sName, a13) end
        return
    end

    -- casts ----------------------------------------------------------------
    if sub == "SPELL_CAST_SUCCESS" then
        if sGroup and sGUID and a13 then
            if not pull then
                if not UnitAffectingCombat("player") then return end
                StartPull()
            end
            local key, sp = Actor(sGUID, sName, a13)
            AddCast(run.players, key, sp)
            AddCast(pull.players, key, sp)
            if TAUNTS[a13] then
                AddCount(run.players, key, "taunts")
                AddCount(pull.players, key, "taunts")
            end
        end
        return
    end

    -- a taunt that missed ------------------------------------------------------
    if sub == "SWING_MISSED" then
        if dPlayer then
            Each(dGUID, function(bp)
                bp.swingsIn = bp.swingsIn + 1
                if a12 == "BLOCK" then bp.blocks = bp.blocks + 1 end
            end)
        end
        return
    end
    if sub == "SPELL_MISSED" then
        if dPlayer and a15 == "BLOCK" then
            Each(dGUID, function(bp) bp.blocks = bp.blocks + 1 end)
        end
        if sGroup and not dGroup and TAUNTS[a13] and not AREA_TAUNTS[a13] then
            local owner = Actor(sGUID, sName, a13)
            for _, tbl in ipairs({ run.players, pull and pull.players }) do
                if tbl then
                    local tp = GetP(tbl, owner)
                    tp.tauntsMissed = tp.tauntsMissed + 1
                    local why = tostring(a15 or "MISS")
                    tp.tauntMiss[why] = (tp.tauntMiss[why] or 0) + 1
                end
            end
        end
        return
    end

    -- totems standing (Tremor, Windfury, ...) ------------------------------------
    if sub == "SPELL_SUMMON" then
        local life = dName and TOTEM_LIFE[dName]
        if sGroup and life and sGUID:find("^Player") and dGUID then
            local k = sGUID .. dName
            if totByOwner[k] then CloseTotem(totByOwner[k], now) end
            totems[dGUID] = { owner = sGUID, name = dName, since = now, life = life }
            totByOwner[k] = dGUID
        end
        return
    elseif sub == "UNIT_DESTROYED" then
        if dGUID and totems[dGUID] then CloseTotem(dGUID, now) end
        return
    end

    -- auras that hit a player (kept for the death recap) -----------------------
    if sub == "SPELL_AURA_REMOVED" or sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
        if a13 then AuraEvent(sub, now, sGUID, sGroup, dGUID, dGroup, dPlayer, a13, a12) end
        if sub == "SPELL_AURA_REMOVED" then
            if dPlayer and a15 == "BUFF" then Push(dGUID, "a-", nil, sName, a13) end
        elseif sub == "SPELL_AURA_APPLIED" then
            if dPlayer and a15 == "DEBUFF" then Push(dGUID, "a+", nil, sName, a13) end
        end
        return
    end

    -- interrupts, dispels --------------------------------------------------------
    if sub == "SPELL_INTERRUPT" and sGroup then
        local key = Actor(sGUID, sName, "x")
        AddCount(run.players, key, "interrupts")
        if pull then AddCount(pull.players, key, "interrupts") end
        local what = tostring(a16 or "?")
        for _, tbl in ipairs({ run.players, pull and pull.players }) do
            if tbl then local ip = GetP(tbl, key); ip.stopped[what] = (ip.stopped[what] or 0) + 1 end
        end
        run.interrupts = run.interrupts or {}
        if #run.interrupts < 400 then
            run.interrupts[#run.interrupts + 1] = { t = time() - run.startTime, who = sName, target = dName, spell = a13, stopped = a16 }
        end
        return
    elseif sub == "SPELL_DISPEL" and sGroup then
        local key = Actor(sGUID, sName, "x")
        AddCount(run.players, key, "dispels")
        if pull then AddCount(pull.players, key, "dispels") end
        local what = (dGroup and "" or "Purge: ") .. tostring(a16 or "?")
        for _, tbl in ipairs({ run.players, pull and pull.players }) do
            if tbl then local dp = GetP(tbl, key); dp.dispelled[what] = (dp.dispelled[what] or 0) + 1 end
        end
        return
    end

    -- deaths ---------------------------------------------------------------
    if sub == "UNIT_DIED" then
        if dGUID and totems[dGUID] then CloseTotem(dGUID, now) end
        if dPlayer then
            RecordDeath(dGUID, dName)
        elseif pull and not dGroup then
            local bi = BossInfo(dGUID)
            if bi then MarkBoss(bi, dGUID); pull.killed = true end
            if pull.bossGUIDs[dGUID] then pull.killed = true end
        end
    end
end

-- boss found by encounter events (when the game sends them) or a skull-level unit in a raid
local function OnEncounter(event, id, name, _, _, success)
    if not run then return end
    if event == "ENCOUNTER_START" then
        if not pull then StartPull() end
        MarkBoss({ id = id, name = name })
    elseif event == "ENCOUNTER_END" and pull then
        MarkBoss({ id = id, name = name })
        if success == 1 then pull.killed = true end
        pull.last = GetTime() - (IDLE_END - 1)    -- close the pull a moment after the encounter ends
    end
end

local function ScanForBoss()
    if not (run and pull) or pull.boss then return end
    local _, itype = GetInstanceInfo()
    if itype ~= "raid" then return end
    local function Look(unit)
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit) then
            local lvl = UnitLevel(unit)
            if lvl == -1 or UnitClassification(unit) == "worldboss" then
                local guid = UnitGUID(unit)
                local id = guid and NpcID(guid)
                if id then
                    local nm = UnitName(unit)
                    DB().learned[id] = nm
                    bossCache[guid] = nil
                    MarkBoss({ id = id, name = nm }, guid)
                end
            end
        end
    end
    Look("target")
    for i = 1, 4 do Look("party" .. i .. "target") end
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do Look("raid" .. i .. "target") end
    end
    for i = 1, 40 do Look("nameplate" .. i) end
end

-- Rockbiter on the main hand: read from the weapon's tooltip (own character only)
local rockTip
local function ScanRock()
    if not rockTip then
        rockTip = CreateFrame("GameTooltip", "CysLogRockTip", nil, "GameTooltipTemplate")
    end
    rockTip:SetOwner(UIParent, "ANCHOR_NONE")
    rockTip:ClearLines()
    local ok = pcall(rockTip.SetInventoryItem, rockTip, "player", 16)
    if not ok then return false end
    for i = 2, rockTip:NumLines() do
        local fs = _G["CysLogRockTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text:find("Rockbiter") then return true end
    end
    return false
end

local ev
local function Enable()
    if ev then return end
    DB()
    ev = CreateFrame("Frame")
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("UNIT_PET")
    ev:RegisterEvent("PLAYER_LOGOUT")
    pcall(ev.RegisterEvent, ev, "ENCOUNTER_START")
    pcall(ev.RegisterEvent, ev, "ENCOUNTER_END")
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            if C_Timer then C_Timer.After(1, function() CheckExpire(); CheckZone() end) else CheckZone() end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
            if run then RefreshRoster() end
        elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
            OnEncounter(event, ...)
        end
    end)
    C_Timer.NewTicker(1, function()
        if pull then
            ScanForBoss()
            if GetTime() - pull.last >= IDLE_END and not UnitAffectingCombat("player") then FinishPull() end
        end
        myGUID = myGUID or UnitGUID("player")
        local _, cls = UnitClass("player")
        if cls == "SHAMAN" and run then
            rockOn = ScanRock()
            if rockOn and pull and myGUID then
                Each(myGUID, function(rp) rp.uptime["Rockbiter Weapon"] = (rp.uptime["Rockbiter Weapon"] or 0) + 1 end)
            end
        else
            rockOn = false
        end
        if CL.win and CL.win:IsShown() and run then CL.Tick() end
    end)
    C_Timer.NewTicker(5, function() if run and pull then RefreshRoster() end end)
    -- picking up a run that was open when the game was reloaded
    local a = DB().active
    if a then
        if a.manual then run = a else CheckExpire() end
    end
end

-- API used by the window and the slash command ---------------------------------------
function CL.Active() return run end
function CL.Pull() return pull end
function CL.StartManual()
    if run then FinalizeRun() end
    StartRun("Manual run", -1, true)
end
function CL.EndRun() if run then FinalizeRun() else CUI:Print("Cys's logs: no run is open.") end end
function CL.Clear()
    DB().runs = {}
    if CL.Refresh then CL.Refresh() end
    CUI:Print("Cys's logs: all saved runs cleared.")
end
function CL.ToggleBoss()
    if not UnitExists("target") or UnitIsPlayer("target") then CUI:Print("Cys's logs: target a mob first."); return end
    local guid = UnitGUID("target")
    local id = guid and NpcID(guid)
    if not id then return end
    local db = DB()
    if db.learned[id] or BOSS_IDS[id] then
        db.learned[id] = nil
        bossCache[guid] = nil
        CUI:Print("Cys's logs: " .. UnitName("target") .. (BOSS_IDS[id] and " is on the built-in boss list and stays a boss." or " is no longer a boss."))
    else
        db.learned[id] = UnitName("target")
        bossCache[guid] = nil
        CUI:Print("Cys's logs: " .. UnitName("target") .. " will count as a boss from now on.")
    end
end


--------------------------------------------------------------------------------
-- Viewer
--------------------------------------------------------------------------------
local MAXROWS, ROWH = 40, 22
local SIDE = 206   -- width of the left column
-- flat charcoal palette
local PAL = {
    bg = { 0.085, 0.09, 0.10, 0.97 }, side = { 0.065, 0.07, 0.08, 1 }, head = { 0.13, 0.135, 0.15, 1 },
    border = { 0.27, 0.28, 0.31, 1 }, stripe = { 1, 1, 1, 0.025 }, hover = { 1, 1, 1, 0.07 },
}
local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
-- tooltip colours: spell names white, damage red, healing green, dispels green, headings gold
local C_WHITE, C_DMG, C_HEAL, C_GOLD = { 1, 1, 1 }, { 1, 0.4, 0.4 }, { 0.4, 1, 0.4 }, { 1, 0.82, 0.2 }
local function TipLine(tt, left, right, rc)
    tt:AddDoubleLine(left, right, 1, 1, 1, rc[1], rc[2], rc[3])
end
local TABS = { "Damage", "Healing", "Taken", "Player", "Deaths", "Mistakes", "Uptimes", "Utility", "Class" }
local view = { run = 1, seg = "all", tab = "Damage", player = nil, mode = "damage", offset = 0, segOffset = 0 }

local function Fmt(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.2fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return tostring(floor(n + 0.5))
end
local function Clock(sec)
    sec = max(0, floor((sec or 0) + 0.5))
    if sec >= 3600 then return string.format("%d:%02d:%02d", floor(sec / 3600), floor(sec / 60) % 60, sec % 60) end
    return string.format("%d:%02d", floor(sec / 60), sec % 60)
end
local function ClassRGB(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

local function RunList()
    local list = {}
    if run then list[1] = run end
    for _, r in ipairs(DB().runs) do list[#list + 1] = r end
    return list
end

local mergedCache = {}
-- the players table, the time it covers, and a title for the chosen run + segment
local function Segment(r)
    local seg = view.seg
    local live = (r == run) and pull
    if seg == "all" then
        local dur = (r.combatTime or 0) + (live and max(1, GetTime() - pull.t0) or 0)
        return r.players, dur, "Whole run"
    elseif seg == "trash" then
        return r.trash.players, r.trash.time, "Trash (" .. r.trash.pulls .. " pulls)"
    elseif seg == "bosses" then
        local key = tostring(r) .. #r.bosses
        local c = mergedCache[key]
        if not c then
            c = { players = {}, dur = 0 }
            for _, b in ipairs(r.bosses) do MergePlayers(c.players, b.players); c.dur = c.dur + b.dur end
            wipe(mergedCache); mergedCache[key] = c
        end
        return c.players, c.dur, "All bosses"
    else
        local b = r.bosses[seg]
        if b then return b.players, b.dur, b.name .. " #" .. b.attempt .. " (" .. b.result .. ")" end
    end
    return r.players, r.combatTime or 0, "Whole run"
end

local function Sorted(players, field)
    local out = {}
    for _, p in pairs(players) do
        if (p[field] or 0) > 0 then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a[field] > b[field] end)
    return out
end

local win
local rowFrames = {}
local runBtns, segBtns, tabBtns = {}, {}, {}

local function SetRow(row, cols, ratio, r, g, b, tip)
    row:Show()
    for i = 1, 7 do
        local fs = row.cols[i]
        if cols[i] ~= nil then fs:SetText(cols[i]); fs:Show() else fs:Hide() end
    end
    row.bar:SetVertexColor(r or 0.5, g or 0.5, b or 0.5, 0.55)
    row.bar:SetWidth(max(1, (win.rowW or 600) * min(1, ratio or 0)))
    row.bar:SetShown((ratio or 0) > 0)
    row.tip = tip
end

local function ColumnsFor(tab)
    if tab == "Damage" then return { { "Player Name", 8, 170, "LEFT" }, { "Damage", 180, 80, "RIGHT" }, { "Share", 265, 50, "RIGHT" }, { "DPS", 320, 70, "RIGHT" }, { "Crit %", 395, 60, "RIGHT" }, { "Casts", 460, 60, "RIGHT" } }
    elseif tab == "Healing" then return { { "Player Name", 8, 170, "LEFT" }, { "Healing", 180, 80, "RIGHT" }, { "Share", 265, 50, "RIGHT" }, { "HPS", 320, 70, "RIGHT" }, { "Overheal %", 395, 80, "RIGHT" }, { "Casts", 480, 60, "RIGHT" } }
    elseif tab == "Taken" then return { { "Player Name", 8, 170, "LEFT" }, { "Taken", 180, 80, "RIGHT" }, { "Share", 265, 50, "RIGHT" }, { "DTPS", 320, 70, "RIGHT" }, { "Deaths", 395, 60, "RIGHT" } }
    elseif tab == "Player" then return { { "Ability", 8, 220, "LEFT" }, { "Total", 230, 80, "RIGHT" }, { "Share", 315, 50, "RIGHT" }, { "Casts", 370, 55, "RIGHT" }, { "Per min", 430, 60, "RIGHT" }, { "Avg", 495, 65, "RIGHT" }, { "Crit %", 565, 55, "RIGHT" } }
    elseif tab == "Deaths" then return { { "Time", 8, 55, "LEFT" }, { "Player", 68, 120, "LEFT" }, { "Killing blow", 195, 220, "LEFT" }, { "Overkill", 420, 65, "RIGHT" }, { "Taken", 490, 70, "RIGHT" }, { "Healed", 565, 70, "RIGHT" } }
    elseif tab == "Mistakes" then return { { "Player Name", 8, 170, "LEFT" }, { "Avoidable Dmg", 180, 95, "RIGHT" }, { "Total Hits", 280, 60, "RIGHT" }, { "Share of Taken", 345, 90, "RIGHT" }, { "Mechanics Hit", 440, 100, "RIGHT" } }
    elseif tab == "Class" then return { { "Player Name", 8, 150, "LEFT" }, { "Ability", 165, 230, "LEFT" }, { "Total", 400, 90, "RIGHT" }, { "Detail", 495, 170, "RIGHT" } }
    elseif tab == "Uptimes" then return { { "Aura / Totem", 8, 380, "LEFT" }, { "Uptime", 395, 70, "RIGHT" }, { "Seconds", 470, 70, "RIGHT" } }
    else return { { "Player Name", 8, 170, "LEFT" }, { "Interrupts", 180, 75, "RIGHT" }, { "Dispels", 260, 60, "RIGHT" }, { "Taunts", 325, 55, "RIGHT" }, { "Landed", 385, 60, "RIGHT" }, { "Missed", 450, 60, "RIGHT" }, { "Deaths", 515, 55, "RIGHT" } } end
end

local function Header(tab)
    local cols = ColumnsFor(tab)
    for i = 1, 7 do
        local h = win.heads[i]
        local c = cols[i]
        if c then
            h:ClearAllPoints()
            h:SetPoint("LEFT", win.headRow, "LEFT", c[2], 0)
            h:SetWidth(c[3]); h:SetJustifyH(c[4]); h:SetText(c[1]); h:Show()
        else h:Hide() end
    end
    for _, row in ipairs(rowFrames) do
        for i = 1, 7 do
            local fs, c = row.cols[i], cols[i]
            if c then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", c[2], 0)
                fs:SetWidth(c[3]); fs:SetJustifyH(c[4])
            end
        end
    end
end

local function FillRows(entries)
    local total = #entries
    local vis = win.rowCount or 20
    win.total = total
    view.offset = max(0, min(view.offset, max(0, total - vis)))
    for i = 1, MAXROWS do
        local e = entries[view.offset + i]
        local row = rowFrames[i]
        if e and i <= vis then SetRow(row, e.cols, e.ratio, e.r, e.g, e.b, e.tip); row.onClick = e.onClick
        else row:Hide() end
    end
    win.scrollText:SetText(total > vis and string.format("%d-%d of %d  (mouse wheel)", view.offset + 1, min(total, view.offset + vis), total) or "")
end

local function Redraw()
    if not win or not win:IsShown() then return end
    local list = RunList()
    if view.run > #list then view.run = max(1, #list) end
    local r = list[view.run]

    -- runs
    for i, b in ipairs(runBtns) do
        local rr = list[i]
        if rr then
            local label = rr.zoneName .. (rr == run and " (live)" or "")
            b:SetLabel(label); b:SetPrimary(i == view.run); b:Show()
            b.label:SetWidth(176)
        else b:Hide() end
    end
    if not r then
        for _, b in ipairs(segBtns) do b:Hide() end
        for _, row in ipairs(rowFrames) do row:Hide() end
        win.title:SetText("No runs yet")
        win.sub:SetText("Walk into a dungeon or raid and the run starts by itself. /cuilog start begins one by hand.")
        win.scrollText:SetText("")
        return
    end

    -- segments
    local segs = { { "all", "Whole run" }, { "bosses", "All bosses (" .. #r.bosses .. ")" }, { "trash", "Trash (" .. r.trash.pulls .. ")" } }
    for i, b in ipairs(r.bosses) do
        segs[#segs + 1] = { i, string.format("%s #%d  %s  %s", b.name, b.attempt, b.result == "kill" and "Kill" or "Wipe", Clock(b.dur)) }
    end
    local segVis = win.segVisible or 12
    view.segOffset = max(0, min(view.segOffset, max(0, #segs - segVis)))
    for i, b in ipairs(segBtns) do
        local sg = segs[view.segOffset + i]
        if sg and i <= segVis then
            b:SetLabel(sg[2]); b:SetPrimary(view.seg == sg[1]); b.seg = sg[1]; b:Show(); b.label:SetWidth(176)
        else b:Hide() end
    end

    for _, t in ipairs(tabBtns) do t:SetPrimary(t.tab == view.tab) end

    local players, dur, segName = Segment(r)
    dur = max(dur, 1)
    local live = (r == run) and " - recording" or ""
    win.title:SetText(r.zoneName .. live)
    local when = date("%d %b %H:%M", r.startTime)
    win.sub:SetText(string.format("%s  |  %s  |  %s run, %s in combat  |  %d boss attempts, %d deaths", segName, when, Clock(r.dur or (time() - r.startTime)), Clock(r.combatTime or 0), #r.bosses, #r.deaths))
    Header(view.tab)

    local tab = view.tab
    local entries = {}
    local function Pick(p) view.player = p.guid; view.tab = "Player"; view.offset = 0; Redraw() end
    if tab == "Damage" or tab == "Healing" or tab == "Taken" then
        local field = tab == "Damage" and "damage" or tab == "Healing" and "healing" or "taken"
        local list2 = Sorted(players, field)
        local sum, top = 0, 0
        for _, p in ipairs(list2) do sum = sum + p[field]; top = max(top, p[field]) end
        for _, p in ipairs(list2) do
            local rr, gg, bb = ClassRGB(p.class)
            local cols
            if tab == "Damage" then
                cols = { p.name, Fmt(p.damage), string.format("%.1f", p.damage / max(sum, 1) * 100), Fmt(p.damage / dur), string.format("%.0f", p.hits > 0 and p.crits / p.hits * 100 or 0), tostring(p.casts) }
            elseif tab == "Healing" then
                local raw = p.healing + p.overheal
                cols = { p.name, Fmt(p.healing), string.format("%.1f", p.healing / max(sum, 1) * 100), Fmt(p.healing / dur), string.format("%.0f", raw > 0 and p.overheal / raw * 100 or 0), tostring(p.casts) }
            else
                cols = { p.name, Fmt(p.taken), string.format("%.1f", p.taken / max(sum, 1) * 100), Fmt(p.taken / dur), tostring(p.deaths) }
            end
            entries[#entries + 1] = { cols = cols, ratio = p[field] / max(top, 1), r = rr, g = gg, b = bb, onClick = function() Pick(p) end,
                tip = function(tt)
                    tt:AddLine(p.name, rr, gg, bb)
                    local sp = {}
                    for nm, s in pairs(p.spells) do
                        local v = tab == "Healing" and s.healing or tab == "Damage" and s.damage or 0
                        if v > 0 then sp[#sp + 1] = { nm, v } end
                    end
                    if tab == "Taken" then
                        for from, amt in pairs(p.takenFrom) do sp[#sp + 1] = { from, amt } end
                    end
                    table.sort(sp, function(a, b) return a[2] > b[2] end)
                    for i = 1, min(8, #sp) do TipLine(tt, sp[i][1], Fmt(sp[i][2]), tab == "Healing" and C_HEAL or C_DMG) end
                    tt:AddLine("Click for the full ability table", 0.6, 0.6, 0.6)
                end }
        end
    elseif tab == "Player" then
        local p = view.player and players[view.player]
        if not p then
            -- default to the top damage dealer
            local l = Sorted(players, "damage")
            p = l[1]; view.player = p and p.guid
        end
        if p then
            local useHeal = view.mode == "healing"
            local list2, sum, top = {}, 0, 0
            for nm, s in pairs(p.spells) do
                local v = useHeal and s.healing or s.damage
                if v > 0 or (s.casts > 0 and not useHeal) then list2[#list2 + 1] = { nm = nm, s = s, v = v }; sum = sum + v; top = max(top, v) end
            end
            table.sort(list2, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.s.casts > b.s.casts end)
            local rr, gg, bb = ClassRGB(p.class)
            win.title:SetText(p.name .. " - " .. (useHeal and "healing" or "damage") .. "  (" .. Fmt(useHeal and p.healing or p.damage) .. ", " .. Fmt((useHeal and p.healing or p.damage) / dur) .. " per second)")
            for _, e in ipairs(list2) do
                local s = e.s
                entries[#entries + 1] = { ratio = e.v / max(top, 1), r = rr, g = gg, b = bb,
                    cols = { e.nm, Fmt(e.v), string.format("%.1f", e.v / max(sum, 1) * 100), tostring(s.casts), s.casts > 0 and string.format("%.1f", s.casts / (dur / 60)) or "-",
                             s.hits > 0 and Fmt(e.v / s.hits) or "-", s.hits > 0 and string.format("%.0f", s.crits / s.hits * 100) or "-" } }
            end
        end
    elseif tab == "Deaths" then
        local topT = 1
        for _, d in ipairs(r.deaths) do topT = max(topT, d.taken or 0) end
        for i, d in ipairs(r.deaths) do
            local rr, gg, bb = ClassRGB(d.class)
            entries[#entries + 1] = { ratio = (d.taken or 0) / topT, r = rr, g = gg, b = bb,
                cols = { Clock(d.t), d.name or "?", (d.killer or "?") .. ": " .. (d.spell or "?"), d.overkill and Fmt(d.overkill) or "-", Fmt(d.taken), Fmt(d.healed) },
                tip = function(tt)
                    tt:AddLine((d.name or "?") .. " died at " .. Clock(d.t), rr, gg, bb)
                    for _, e in ipairs(d.events) do
                        local ago = string.format("-%.1fs", e.ago)
                        if e.k == "d" then tt:AddDoubleLine(ago .. "  " .. tostring(e.src) .. ": " .. tostring(e.spell), "-" .. Fmt(e.amt), 1, 0.4, 0.4, 1, 0.4, 0.4)
                        elseif e.k == "h" then tt:AddDoubleLine(ago .. "  " .. tostring(e.src) .. ": " .. tostring(e.spell), "+" .. Fmt(e.amt), 0.4, 1, 0.4, 0.4, 1, 0.4)
                        elseif e.k == "a+" then tt:AddLine(ago .. "  gained " .. tostring(e.spell) .. " (" .. tostring(e.src) .. ")", 0.9, 0.6, 1)
                        else tt:AddLine(ago .. "  lost " .. tostring(e.spell), 0.7, 0.7, 0.7) end
                    end
                end }
        end
    elseif tab == "Mistakes" then
        local list2, top = {}, 0
        for _, p in pairs(players) do
            if (p.avoidDamage or 0) > 0 or (p.mechHits or 0) > 0 then list2[#list2 + 1] = p; top = max(top, p.avoidDamage or 0) end
        end
        table.sort(list2, function(a, b) return ((a.avoidDamage or 0) + (a.mechHits or 0) * 1e6) > ((b.avoidDamage or 0) + (b.mechHits or 0) * 1e6) end)
        for _, p in ipairs(list2) do
            local rr, gg, bb = ClassRGB(p.class)
            entries[#entries + 1] = { ratio = top > 0 and (p.avoidDamage or 0) / top or min(1, (p.mechHits or 0) / 5), r = rr, g = gg, b = bb,
                cols = { p.name, Fmt(p.avoidDamage or 0), tostring(p.avoidHits or 0), string.format("%.0f", (p.avoidDamage or 0) / max(p.taken, 1) * 100), tostring(p.mechHits or 0) },
                tip = function(tt)
                    tt:AddLine(p.name .. " - mistakes", rr, gg, bb)
                    local sp = {}
                    for nm, amt in pairs(p.avoidSpells or {}) do sp[#sp + 1] = { nm, Fmt(amt) } end
                    table.sort(sp, function(a, b) return a[1] < b[1] end)
                    for _, e in ipairs(sp) do TipLine(tt, "Avoidable: " .. e[1], e[2], C_DMG) end
                    for nm, n in pairs(p.hitBy or {}) do TipLine(tt, nm, n .. "x", C_GOLD) end
                end }
        end
        for label, n in pairs(r.mechCasts or {}) do
            entries[#entries + 1] = { cols = { "Group", label .. "  x" .. n }, ratio = 0, r = 0.8, g = 0.4, b = 0.3 }
        end
        if #entries == 0 then
            entries[1] = { cols = { "Nothing recorded. Add avoidable spells with /cuilog avoid <spell id>." }, ratio = 0, r = 0.5, g = 0.5, b = 0.5 }
        end
    elseif tab == "Class" then
        local names = {}
        for _, p in pairs(players) do names[#names + 1] = p end
        table.sort(names, function(a, b) return a.name < b.name end)
        for _, p in ipairs(names) do
            local rr, gg, bb = ClassRGB(p.class)
            local function Row(what, value, detail, num)
                entries[#entries + 1] = { cols = { p.name, what, value, detail or "" }, ratio = 0, num = num or 0, what = what, r = rr, g = gg, b = bb }
            end
            local sp = p.spells or {}
            if (p.blocks or 0) > 0 then
                Row("Attacks blocked (shield)", tostring(p.blocks), string.format("of %d melee swings, %s blocked", p.swingsIn or 0, Fmt(p.blockedDmg)), p.blocks)
            end
            local br = sp["Bloodrage"]
            if br and br.casts > 0 then Row("Bloodrage casts", tostring(br.casts), string.format("%.1f per min", br.casts / (dur / 60)), br.casts) end
            local es = sp["Earth Shock"]
            if es and (es.casts > 0 or es.damage > 0) then
                Row("Earth Shock damage", Fmt(es.damage), string.format("%d casts, avg %s", es.casts, es.hits > 0 and Fmt(es.damage / es.hits) or "-"), es.damage)
            end
            if (p.rockDamage or 0) > 0 then
                local melee = sp["Melee"]
                local pct = melee and melee.damage > 0 and (p.rockDamage / melee.damage * 100) or 0
                Row("Melee damage with Rockbiter", Fmt(p.rockDamage), string.format("%.0f%% of melee, %s", pct, Clock((p.uptime or {})["Rockbiter Weapon"] or 0)), p.rockDamage)
            end
            local st = sp["Searing Totem"]
            local sb = sp["Totem: Searing Bolt"]
            if (st and st.casts > 0) or sb then
                Row("Searing Totem", st and (st.casts .. " casts") or "-", sb and (Fmt(sb.damage) .. " damage") or "no damage seen", sb and sb.damage or 0)
            end
            local fn = sp["Fire Nova Totem"]
            local fd = sp["Totem: Fire Nova"]
            if (fn and fn.casts > 0) or fd then
                Row("Fire Nova Totem", fn and (fn.casts .. " casts") or "-", fd and (Fmt(fd.damage) .. " damage") or "no damage seen", fd and fd.damage or 0)
            end
        end
        local topBy = {}
        for _, e in ipairs(entries) do topBy[e.what] = max(topBy[e.what] or 1, e.num or 0) end
        for _, e in ipairs(entries) do e.ratio = (e.num or 0) / topBy[e.what] end
        if #entries == 0 then
            entries[1] = { cols = { "Nothing yet. Shows shield blocks, Bloodrage, Earth Shock, Rockbiter melee and Searing / Fire Nova Totems." }, ratio = 0, r = 0.5, g = 0.5, b = 0.5 }
        end
    elseif tab == "Uptimes" then
        local function Row(label, secs, base, r2, g2, b2)
            local frac = base > 0 and min(1, secs / base) or 0
            entries[#entries + 1] = { cols = { label, string.format("%.0f%%", frac * 100), Clock(secs) }, ratio = frac, r = r2, g = g2, b = b2 }
        end
        if view.seg ~= "trash" then
            local keys = { "Sunder Armor", "Faerie Fire", "Curse of Recklessness", "Demoralizing Shout", "Thunder Clap" }
            for i, b in ipairs(r.bosses) do
                if view.seg == "all" or view.seg == "bosses" or view.seg == i then
                    if b.uptimes then
                        for _, k in ipairs(keys) do
                            Row(string.format("%s #%d (%s) - %s on the boss", b.name, b.attempt, b.result, k), b.uptimes[k] or 0, b.dur, 0.9, 0.7, 0.2)
                        end
                    end
                end
            end
        end
        local names = {}
        for _, p in pairs(players) do
            if p.uptime and next(p.uptime) then names[#names + 1] = p end
        end
        table.sort(names, function(a, b) return a.name < b.name end)
        for _, p in ipairs(names) do
            local rr, gg, bb = ClassRGB(p.class)
            local ks = {}
            for k in pairs(p.uptime) do ks[#ks + 1] = k end
            table.sort(ks)
            for _, k in ipairs(ks) do Row(p.name .. " - " .. k, p.uptime[k], dur, rr, gg, bb) end
        end
        if #entries == 0 then
            entries[1] = { cols = { "Nothing recorded yet. Boss debuffs show for boss attempts; totems and Shield Block per player." }, ratio = 0, r = 0.5, g = 0.5, b = 0.5 }
        end
    else -- Utility
        local list2 = {}
        for _, p in pairs(players) do
            if p.interrupts > 0 or p.dispels > 0 or (p.taunts or 0) > 0 or (p.tauntsLanded or 0) > 0 or (p.tauntsMissed or 0) > 0 or p.deaths > 0 then list2[#list2 + 1] = p end
        end
        table.sort(list2, function(a, b) return (a.interrupts + a.dispels) > (b.interrupts + b.dispels) end)
        local topU = 1
        for _, p in ipairs(list2) do topU = max(topU, p.interrupts + p.dispels + (p.tauntsLanded or 0)) end
        for _, p in ipairs(list2) do
            local rr, gg, bb = ClassRGB(p.class)
            entries[#entries + 1] = { ratio = (p.interrupts + p.dispels + (p.tauntsLanded or 0)) / max(1, topU), r = rr, g = gg, b = bb,
                cols = { p.name, tostring(p.interrupts), tostring(p.dispels), tostring(p.taunts or 0), tostring(p.tauntsLanded or 0), tostring(p.tauntsMissed or 0), tostring(p.deaths) },
                tip = function(tt)
                    tt:AddLine(p.name, rr, gg, bb)
                    local function List(title, map, color)
                        if not map or not next(map) then return end
                        tt:AddLine(title, 1, 0.82, 0.2)
                        local l = {}
                        for k, v in pairs(map) do l[#l + 1] = { k, v } end
                        table.sort(l, function(a, b) return a[2] > b[2] end)
                        for i = 1, min(8, #l) do TipLine(tt, l[i][1], tostring(l[i][2]), color or C_WHITE) end
                    end
                    List("Interrupted", p.stopped, C_GOLD)
                    List("Dispelled", p.dispelled, C_HEAL)
                    List("Taunt misses", p.tauntMiss, C_DMG)
                end }
        end
    end
    FillRows(entries)

    win.modeBtn:SetShown(tab == "Player")
    win.prevBtn:SetShown(tab == "Player")
    win.nextBtn:SetShown(tab == "Player")
    win.modeBtn:SetLabel(view.mode == "healing" and "Showing healing" or "Showing damage")
end
CL.Refresh = Redraw
function CL.Tick() Redraw() end

local function CyclePlayer(dir)
    local list = RunList()
    local r = list[view.run]
    if not r then return end
    local players = Segment(r)
    local l = Sorted(players, view.mode == "healing" and "healing" or "damage")
    for i, p in ipairs(l) do
        if p.guid == view.player then
            local n = l[(i - 1 + dir) % #l + 1]
            view.player = n.guid
            Redraw()
            return
        end
    end
    if l[1] then view.player = l[1].guid; Redraw() end
end

local function SaveWindow()
    if not win then return end
    local db = DB()
    local point, _, rel, x, y = win:GetPoint()
    db.window = { w = floor(win:GetWidth() + 0.5), h = floor(win:GetHeight() + 0.5), point = point, rel = rel, x = x, y = y }
end

-- called whenever the window changes size: how many rows and fight buttons fit
local function Layout()
    if not win then return end
    local w, h = win:GetWidth(), win:GetHeight()
    win.rowW = w - (SIDE + 16) - 14
    win.rowCount = max(5, min(MAXROWS, floor((h - 176) / ROWH)))
    win.segVisible = max(4, min(#segBtns, floor((h - 300) / 22)))
    win.sub:SetWidth(w - 60)
    Redraw()
end

local function ShowTip(row)
    if not row.tip then return end
    GameTooltip:SetOwner(win, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if (win:GetRight() or 0) + 330 < (UIParent:GetRight() or 10000) then
        GameTooltip:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
    else
        GameTooltip:SetPoint("TOPRIGHT", win, "TOPLEFT", -6, 0)
    end
    GameTooltip:ClearLines()
    row.tip(GameTooltip)
    GameTooltip:Show()
end

local function BuildWindow()
    local saved = DB().window
    win = CreateFrame("Frame", "CysLogWindow", UIParent)
    CL.win = win
    win:SetSize(saved and saved.w or 900, saved and saved.h or 600)
    if saved and saved.point then
        win:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
    else
        win:SetPoint("CENTER")
    end
    win:SetFrameStrata("HIGH")
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(880, 460, 1400, 940)
    elseif win.SetMinResize then win:SetMinResize(880, 460) end
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SaveWindow() end)

    -- flat charcoal panels, one-pixel border
    local bg = W.Texture(win, "BACKGROUND", PAL.bg); bg:SetAllPoints()
    local side = W.Texture(win, "BACKGROUND", PAL.side, 1)
    side:SetPoint("TOPLEFT", 1, -1); side:SetPoint("BOTTOMLEFT", 1, 1); side:SetWidth(SIDE)
    local div = W.Texture(win, "BORDER", PAL.border)
    div:SetWidth(1); div:SetPoint("TOPLEFT", SIDE + 1, -1); div:SetPoint("BOTTOMLEFT", SIDE + 1, 1)
    W.Border(win, 1, PAL.border, "BORDER")
    tinsert(UISpecialFrames, "CysLogWindow")

    -- title strip over the right panel
    win.title = W.Text(win, 15, T.accent); win.title:SetPoint("TOPLEFT", SIDE + 16, -12)
    win.sub = W.Text(win, 11, T.desc); win.sub:SetPoint("TOPLEFT", SIDE + 16, -34)
    local close = W.Button(win, 22, 22, "x"); close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)

    -- left column: runs, then the fights of the chosen run
    local brand = W.Text(win, 13, T.accent); brand:SetPoint("TOPLEFT", 14, -12); brand:SetText("Cys's logs")
    local lh = W.Text(win, 10, T.dim); lh:SetPoint("TOPLEFT", 14, -42); lh:SetText("RUNS")
    for i = 1, 8 do
        local b = W.Button(win, SIDE - 20, 20, "")
        b:SetPoint("TOPLEFT", 12, -56 - (i - 1) * 22)
        b:SetScript("OnClick", function() view.run = i; view.seg = "all"; view.offset = 0; view.segOffset = 0; view.player = nil; Redraw() end)
        runBtns[i] = b
    end
    local sh = W.Text(win, 10, T.dim); sh:SetPoint("TOPLEFT", 14, -244); sh:SetText("FIGHTS  (mouse wheel to scroll)")
    for i = 1, 30 do
        local b = W.Button(win, SIDE - 20, 20, "")
        b:SetPoint("TOPLEFT", 12, -258 - (i - 1) * 22)
        b:SetScript("OnClick", function(s) view.seg = s.seg; view.offset = 0; Redraw() end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, d) view.segOffset = max(0, view.segOffset - d); Redraw() end)
        segBtns[i] = b
    end

    -- tabs across the top of the right panel
    for i, name in ipairs(TABS) do
        local t = W.Button(win, 72, 22, name)
        t:SetPoint("TOPLEFT", SIDE + 16 + (i - 1) * 75, -58)
        t.tab = name
        t:SetScript("OnClick", function() view.tab = name; view.offset = 0; Redraw() end)
        tabBtns[i] = t
    end
    win.modeBtn = W.Button(win, 130, 20, "Showing damage")
    win.modeBtn:SetPoint("TOPLEFT", SIDE + 16, -88)
    win.modeBtn:SetScript("OnClick", function() view.mode = view.mode == "damage" and "healing" or "damage"; view.offset = 0; Redraw() end)
    win.prevBtn = W.Button(win, 70, 20, "< Prev"); win.prevBtn:SetPoint("LEFT", win.modeBtn, "RIGHT", 8, 0)
    win.prevBtn:SetScript("OnClick", function() CyclePlayer(-1) end)
    win.nextBtn = W.Button(win, 70, 20, "Next >"); win.nextBtn:SetPoint("LEFT", win.prevBtn, "RIGHT", 6, 0)
    win.nextBtn:SetScript("OnClick", function() CyclePlayer(1) end)

    -- column header strip
    local hb = W.Texture(win, "ARTWORK", PAL.head)
    hb:SetPoint("TOPLEFT", SIDE + 16, -114); hb:SetPoint("TOPRIGHT", -14, -114); hb:SetHeight(22)
    win.headRow = CreateFrame("Frame", nil, win)
    win.headRow:SetPoint("TOPLEFT", SIDE + 16, -114); win.headRow:SetPoint("TOPRIGHT", -14, -114); win.headRow:SetHeight(22)
    win.heads = {}
    for i = 1, 7 do
        local hfs = W.Text(win.headRow, 11, T.accent)
        win.heads[i] = hfs
    end

    for i = 1, MAXROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetHeight(ROWH - 2)
        row:SetPoint("TOPLEFT", SIDE + 16, -138 - (i - 1) * ROWH)
        row:SetPoint("TOPRIGHT", -14, -138 - (i - 1) * ROWH)
        if i % 2 == 0 then local st = W.Texture(row, "BACKGROUND", PAL.stripe); st:SetAllPoints() end
        row.bar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.bar:SetTexture(BAR_TEX)
        row.bar:SetPoint("TOPLEFT"); row.bar:SetPoint("BOTTOMLEFT")
        row.hl = W.Texture(row, "HIGHLIGHT", PAL.hover); row.hl:SetAllPoints()
        row.cols = {}
        for c = 1, 7 do
            local fs = W.Text(row, 12, T.text)
            fs:SetPoint("LEFT", 8, 0)
            row.cols[c] = fs
        end
        row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        row:SetScript("OnEnter", ShowTip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        rowFrames[i] = row
    end
    win.scrollText = W.Text(win, 10, T.dim); win.scrollText:SetPoint("BOTTOMLEFT", SIDE + 16, 10)

    -- resize grip, bottom right
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SaveWindow(); Layout() end)

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d) view.offset = max(0, view.offset - d * 3); Redraw() end)
    win:SetScript("OnSizeChanged", Layout)
    win:SetScript("OnShow", Layout)
    win:Hide()
end

function CL.SetTab(tab) view.tab = tab; view.offset = 0; Redraw() end

function CL.Toggle()
    DB()
    if not win then BuildWindow() end
    if win:IsShown() then win:Hide() else win:Show() end
end

SLASH_CYSLOG1 = "/cuilog"
SLASH_CYSLOG2 = "/cyslog"
SlashCmdList["CYSLOG"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "start" then CL.StartManual()
    elseif msg == "end" then CL.EndRun()
    elseif msg == "boss" then CL.ToggleBoss()
    elseif msg:match("^avoid") then
        local id = tonumber(msg:match("avoid%s+(%d+)"))
        if not id then CUI:Print("Usage: /cuilog avoid <spell id>  (adds or removes a spell from the avoidable damage list)")
        else
            local av = DB().avoidable
            if av[id] then av[id] = nil; CUI:Print("Cys's logs: spell " .. id .. " is no longer counted as avoidable.")
            else av[id] = true; CUI:Print("Cys's logs: spell " .. id .. " now counts as avoidable damage.") end
        end
    elseif msg == "reset" then
        DB().window = nil
        if win then win:ClearAllPoints(); win:SetPoint("CENTER"); win:SetSize(900, 600) end
        CUI:Print("Cys's logs: window put back in the middle at its default size.")
    elseif msg == "clear" then CL.Clear()
    elseif msg == "help" then CUI:Print("/cuilog (window)  /cuilog start  /cuilog end  /cuilog boss (mark or unmark your target as a boss)  /cuilog avoid <spell id>  /cuilog reset (window)  /cuilog clear")
    else CL.Toggle() end
end

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------
CUI:RegisterPage("Combat Log", function(page)
    local db = DB()
    local width = 480
    W.Header(page, "Combat log (Cys's logs)", width):SetPoint("TOPLEFT", 0, -4)
    local intro = W.Text(page, 12, T.text)
    intro:SetPoint("TOPLEFT", 4, -34); intro:SetWidth(width - 8); intro:SetJustifyV("TOP"); intro:SetSpacing(3)
    intro:SetText("Records every dungeon and raid you enter as one run: bosses, trash, each player's damage, healing, damage taken, casts and deaths with a recap of the last hits. Walking out to run back does not end it.")
    local y = -104
    local c = W.Checkbox(page, "Record runs", function() return db.record end, function(on) db.record = on end)
    c:SetPoint("TOPLEFT", 4, y); y = y - 28
    local c2 = W.Checkbox(page, "Also turn on the game's own combat log during a run (for Warcraft Logs uploads)", function() return db.autoLog end, function(on) db.autoLog = on end)
    c2:SetPoint("TOPLEFT", 4, y); y = y - 32
    local st = W.Stepper(page, "Runs to keep", function() return db.keepRuns end, function(v)
        db.keepRuns = v
        while #db.runs > v do table.remove(db.runs) end
    end, 3, 10, 1, "")
    st:SetPoint("TOPLEFT", 4, y); y = y - 36
    local open = W.Button(page, 130, 22, "Open the log", true)
    open:SetPoint("TOPLEFT", 4, y)
    open:SetScript("OnClick", CL.Toggle)
    local clr = W.Button(page, 130, 22, "Clear saved runs")
    clr:SetPoint("LEFT", open, "RIGHT", 8, 0)
    clr:SetScript("OnClick", CL.Clear)
    y = y - 40
    W.Notes(page, 4, y, width - 8, "Commands", {
        { "/cuilog", "open or close the window" },
        { "/cuilog start / end", "begin or close a run by hand" },
        { "/cuilog boss", "mark or unmark your target as a boss (remembered)" },
        { "Bosses", "found from the built-in list, encounter events, skull-level units in raids, or /cuilog boss" },
    })
end)

CUI:RegisterModule({
    key = "combatlog",
    name = "Combat Log (Cys's logs)",
    addon = "CysUI",
    desc = "Records whole dungeon and raid runs (bosses, trash, every player's damage, healing, casts and deaths with a recap) and keeps the last few. View them with /cuilog.",
    onEnable = Enable,
    open = function() CUI:OpenConfig("Combat Log") end,
})
