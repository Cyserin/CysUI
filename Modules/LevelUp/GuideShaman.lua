--------------------------------------------------------------------------------
-- Cys's UI - level-up spell guides: Shaman
--
-- One entry per guide. Each spell line:
--   level    = the level the rank can be trained
--   buyAt    = (optional) the level it is actually worth buying, when later than `level`
--   note     = (optional) the reason shown in the box
--   optional = (optional) true when it is only worth it for some playstyles
-- The levels are a fallback: /cuiscan at your trainer checks them against the real ones.
--------------------------------------------------------------------------------
local CUI = CysUI
CUI.LevelGuides = CUI.LevelGuides or {}
CUI.LevelGuides.SHAMAN = CUI.LevelGuides.SHAMAN or {}

table.insert(CUI.LevelGuides.SHAMAN, {
    key = "earthwarden",
    name = "Earth Warden",
    role = "Tank",  -- "Earth Warden" is a community name, not a spec, so it gets a (Tank) tag; the real specs do not
    spec = "Enhancement",
    client = "Era",
    spells = {
        { level = 1,  spell = "Rockbiter Weapon",        rank = 1 },
        { level = 4,  spell = "Earth Shock",             rank = 1 },
        { level = 4,  spell = "Stoneskin Totem",         rank = 1 },
        { level = 6,  spell = "Earthbind Totem" },
        { level = 8,  spell = "Earth Shock",             rank = 2 },
        { level = 8,  spell = "Rockbiter Weapon",        rank = 2 },
        { level = 8,  spell = "Lightning Shield",        rank = 1 },
        { level = 8,  spell = "Stoneclaw Totem",         rank = 1, note = "Emergency peel only; replaces Stoneskin" },
        { level = 12, spell = "Purge",                   rank = 1 },
        { level = 14, spell = "Earth Shock",             rank = 3 },
        { level = 14, spell = "Stoneskin Totem",         rank = 2 },
        { level = 16, spell = "Lightning Shield",        rank = 2 },
        { level = 16, spell = "Rockbiter Weapon",        rank = 3 },
        { level = 18, spell = "Stoneclaw Totem",         rank = 2 },
        { level = 18, spell = "Tremor Totem",            note = "Breaks fear, charm and sleep" },
        { level = 20, spell = "Frost Shock",             rank = 1, note = "Nature-immune or fleeing mobs" },
        { level = 20, spell = "Lesser Healing Wave",     rank = 1, note = "Emergency self-heal" },
        { level = 20, spell = "Ghost Wolf" },
        { level = 20, spell = "Lightning Bolt",          rank = 4, note = "R4+ all cast in 3.0s. Max rank for packs/elites/bosses; R1 (1.5s) for fast trash pulls" },
        { level = 22, spell = "Poison Cleansing Totem" },
        { level = 24, spell = "Earth Shock",             rank = 4 },
        { level = 24, spell = "Lightning Shield",        rank = 3 },
        { level = 24, spell = "Rockbiter Weapon",        rank = 4 },
        { level = 24, spell = "Stoneskin Totem",         rank = 3 },
        { level = 28, spell = "Stoneclaw Totem",         rank = 3 },
        { level = 30, spell = "Grounding Totem" },
        { level = 30, spell = "Reincarnation" },
        { level = 30, spell = "Astral Recall" },
        { level = 32, spell = "Lightning Shield",        rank = 4 },
        { level = 32, spell = "Chain Lightning",         rank = 1, note = "Multi-pull opener" },
        { level = 32, spell = "Purge",                   rank = 2 },
        { level = 32, spell = "Lightning Bolt",          rank = 6, note = "Opener" },
        { level = 34, spell = "Rockbiter Weapon",        rank = 5 },
        { level = 34, spell = "Stoneskin Totem",         rank = 4 },
        { level = 34, spell = "Frost Shock",             rank = 2 },
        { level = 36, spell = "Earth Shock",             rank = 5 },
        { level = 38, spell = "Stoneclaw Totem",         rank = 4 },
        { level = 40, spell = "Lightning Shield",        rank = 5 },
        { level = 40, spell = "Chain Lightning",         rank = 2, optional = true, note = "Only if you multi-pull often" },
        { level = 42, spell = "Grace of Air Totem",      rank = 1 },
        { level = 42, spell = "Fire Resistance Totem",   rank = 2, buyAt = 52, note = "Buy when you start BRD" },
        { level = 44, spell = "Rockbiter Weapon",        rank = 6 },
        { level = 44, spell = "Stoneskin Totem",         rank = 5 },
        { level = 44, spell = "Lightning Bolt",          rank = 8, note = "Opener" },
        { level = 46, spell = "Frost Shock",             rank = 3 },
        { level = 48, spell = "Earth Shock",             rank = 6 },
        { level = 48, spell = "Lightning Shield",        rank = 6 },
        { level = 48, spell = "Stoneclaw Totem",         rank = 5 },
        { level = 48, spell = "Chain Lightning",         rank = 3, optional = true, note = "Only if you multi-pull often" },
        { level = 54, spell = "Rockbiter Weapon",        rank = 7 },
        { level = 54, spell = "Stoneskin Totem",         rank = 6 },
        { level = 56, spell = "Lightning Shield",        rank = 7 },
        { level = 56, spell = "Grace of Air Totem",      rank = 2 },
        { level = 56, spell = "Lightning Bolt",          rank = 10, note = "Opener" },
        { level = 56, spell = "Chain Lightning",         rank = 4, optional = true, note = "Only if you multi-pull often" },
        { level = 58, spell = "Frost Shock",             rank = 4 },
        { level = 58, spell = "Stoneclaw Totem",         rank = 6 },
        { level = 60, spell = "Earth Shock",             rank = 7 },
        { level = 60, spell = "Grace of Air Totem",      rank = 3 },
    },
})

--------------------------------------------------------------------------------
-- The full Shaman table: one row per trainer level, split by what you play.
--   T = tank (Earth Warden above is the tank list)   D = dungeon DPS   H = healing   Q = questing
--   all = worth buying whatever you play             skip = spells NOT worth the gold, and why
-- More guides (Enhancement, Elemental, Restoration) are built from it below.
--------------------------------------------------------------------------------
local ROWS = {
    { 10, D = "Strength of Earth R1", Q = "Flametongue Weapon R1, Searing Totem R1, Flame Shock R1" },
    { 12, H = "Healing Wave R3", all = "Ancestral Spirit R1",
      skip = { "Fire Nova R1|costs shock mana and breaks CC when tanking; train it if you DPS packs often" } },
    { 14, skip = { "Lightning Bolt R3|pull only" } },
    { 16, all = "Cure Poison" },
    { 18, H = "Healing Wave R4", Q = "Flametongue Weapon R2, Flame Shock R2" },
    { 20, H = "Lesser Healing Wave R1, Healing Stream Totem R1", Q = "Searing Totem R2",
      skip = { "Lightning Bolt R4|pull only", "Frostbrand Weapon R1|Flametongue and Rockbiter are better" } },
    { 22, all = "Cure Disease",
      skip = { "Fire Nova R2|DPS-only, as R1", "Water Breathing|buy when a quest needs it" } },
    { 24, D = "Strength of Earth R2", H = "Healing Wave R5", all = "Ancestral Spirit R2",
      skip = { "Frost Resistance Totem R1|no frost-heavy content" } },
    { 26, H = "Mana Spring Totem R1", Q = "Flametongue Weapon R3",
      skip = { "Lightning Bolt R5|pull only", "Magma Totem R1|pull only, mana-heavy AoE", "Far Sight|no use" } },
    { 28, H = "Lesser Healing Wave R2", Q = "Flame Shock R3",
      skip = { "Fire Resistance Totem R1|wait for BRD", "Frostbrand Weapon R2|not needed", "Flametongue Totem|not needed", "Water Walking|not needed" } },
    { 30, D = "Windfury Weapon R1", Q = "Windfury Weapon R1", H = "Healing Stream Totem R2", all = "Astral Recall, Reincarnation",
      skip = { "Searing Totem R3|Windfury replaces it for questing", "Nature Resistance Totem R1|no nature content yet" } },
    { 32, D = "Windfury Totem R1", H = "Healing Wave R6",
      skip = { "Lightning Bolt R6|pull only", "Fire Nova Totem R3|DPS-only" } },
    { 34, skip = { "Sentry Totem|no use" } },
    { 36, H = "Lesser Healing Wave R3, Mana Spring Totem R2", all = "Ancestral Spirit R3",
      skip = { "Magma Totem R2|replaced or rarely useful", "Flametongue Weapon R4|replaced or rarely useful", "Windwall Totem|rarely useful" } },
    { 38, D = "Strength of Earth R3",
      skip = { "Lightning Bolt R7|not needed", "Frostbrand Weapon R3|not needed", "Disease Cleansing Totem|buy before Strat" } },
    { 40, D = "Windfury Weapon R2", Q = "Windfury Weapon R2", H = "Healing Wave R7, Chain Heal R1, Healing Stream Totem R3",
      skip = { "Chain Lightning R2|R1 still tags 3", "Flame Shock R4|unused", "Searing Totem R4|unused" } },
    { 42, D = "Windfury Totem R2",
      skip = { "Fire Nova Totem R4|DPS-only", "Fire Resistance Totem R2|buy at about level 52 for BRD" } },
    { 44, H = "Lesser Healing Wave R4",
      skip = { "Lightning Bolt R8|not needed", "Nature Resistance Totem R2|not needed" } },
    { 46, H = "Chain Heal R2, Mana Spring Totem R3", skip = { "Magma Totem R3|AoE only" } },
    { 48, H = "Healing Wave R8", all = "Ancestral Spirit R4", skip = { "Chain Lightning R3|optional for multi-pulls" } },
    { 50, D = "Windfury Weapon R3", Q = "Windfury Weapon R3", H = "Healing Stream Totem R4",
      skip = { "Lightning Bolt R9|not needed", "Searing Totem R5|not needed" } },
    { 52, D = "Strength of Earth R4, Windfury Totem R3", H = "Lesser Healing Wave R5",
      skip = { "Fire Nova Totem R5|not needed", "Flame Shock R5|not needed" } },
    { 54, H = "Chain Heal R3", skip = { "Frost Resistance Totem R3|not needed" } },
    { 56, H = "Healing Wave R9, Mana Spring Totem R4",
      skip = { "Chain Lightning R4|buy at 60 if gold allows", "Magma Totem R4|buy at 60 if gold allows", "Lightning Bolt R10|buy at 60 if gold allows" } },
    { 58, skip = { "Fire Resistance Totem R3|raids only" } },
    { 60, D = "Strength of Earth R5, Windfury Weapon R4", Q = "Windfury Weapon R4",
      H = "Healing Wave R10, Lesser Healing Wave R6, Healing Stream Totem R5", all = "Ancestral Spirit R5",
      skip = { "Flame Shock R6|raids only", "Searing Totem R6|raids only", "Nature Resistance Totem R3|raids only" } },
}

local function Parse(list, level, out)
    for raw in (list or ""):gmatch("[^,]+") do
        local item = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local name, rank = item:match("^(.-)%s+R(%d+)$")
        local e = { level = level, spell = name or item, rank = tonumber(rank) }
        out[#out + 1] = e
    end
end

local function Build(key, name, role, spec, tags)
    local g = { key = key, name = name, role = role, spec = spec, client = "Era", spells = {}, skips = {} }
    for _, row in ipairs(ROWS) do
        for _, tag in ipairs(tags) do Parse(row[tag], row[1], g.spells) end
        Parse(row.all, row[1], g.spells)
        for _, s in ipairs(row.skip or {}) do
            local what, why = s:match("^(.-)|(.*)$")
            local sp, rk = what:match("^(.-)%s+R(%d+)$")
            g.skips[#g.skips + 1] = { level = row[1], spell = sp or what, rank = tonumber(rk), why = why }
        end
    end
    -- a spell tagged in more than one column (Windfury Weapon is D and Q) is listed once
    local seen, uniq = {}, {}
    for _, e in ipairs(g.spells) do
        local k = e.spell .. ":" .. (e.rank or 0)
        if not seen[k] then seen[k] = true; uniq[#uniq + 1] = e end
    end
    g.spells = uniq
    return g
end

--------------------------------------------------------------------------------
-- Enhancement, Elemental and Restoration: which spells to buy comes from Wowhead's Classic Era leveling guides for each
-- spec (patch 1.15.8): always keep Rockbiter, Lightning Shield and the damage spells current, take the group totems when
-- you group, the cheap utility spells as early as you can, and skip what the guides say to skip. The rank levels are
-- the ones the trainer scan (/cuiscan) confirmed, not the level lists on the web pages (those disagree with each other).
--------------------------------------------------------------------------------
local RANKS = {
    ["Rockbiter Weapon"]  = { 1, 8, 16, 24, 34, 44, 54 },
    ["Lightning Shield"]  = { 8, 16, 24, 32, 40, 48, 56 },
    ["Earth Shock"]       = { 4, 8, 14, 24, 36, 48, 60 },
    ["Lightning Bolt"]    = { 1, 8, 14, 20, 26, 32, 38, 44, 50, 56 },
    ["Chain Lightning"]   = { 32, 40, 48, 56 },
    ["Flame Shock"]       = { 10, 18, 28, 40, 52, 60 },
    ["Strength of Earth Totem"] = { 10, 24, 38, 52, 60 },
    ["Windfury Totem"]    = { 32, 42, 52 },
    ["Healing Wave"]      = { 1, 6, 12, 18, 24, 32, 40, 48, 56, 60 },
    ["Lesser Healing Wave"] = { 20, 28, 36, 44, 52, 60 },
    ["Chain Heal"]        = { 40, 46, 54 },
    ["Healing Stream Totem"] = { 20, 30, 40, 50, 60 },
    ["Mana Spring Totem"] = { 26, 36, 46, 56 },
    ["Ancestral Spirit"]  = { 12, 24, 36, 48, 60 },
}

local function Add(g, spell, opts)
    opts = opts or {}
    local lv = RANKS[spell]
    for rank, level in ipairs(lv) do
        local e = { level = level, spell = spell, rank = rank, optional = opts.optional }
        if rank == 1 or (opts.noteAll) then e.note = opts.note end
        g.spells[#g.spells + 1] = e
    end
end

local function One(g, spell, level, note, optional)
    g.spells[#g.spells + 1] = { level = level, spell = spell, note = note, optional = optional }
end

local function Skip(g, level, spell, why)
    g.skips[#g.skips + 1] = { level = level, spell = spell, why = why }
end

local function Base(key, name, spec)
    local g = { key = key, name = name, spec = spec, client = "Era", spells = {}, skips = {}, source = "Wowhead" }
    Add(g, "Rockbiter Weapon", { note = "Keep it on at all times; Wowhead: more consistent and higher average damage than Windfury Weapon" })
    Add(g, "Lightning Shield", { note = "One of your most efficient damage sources: always buy the new rank" })
    Add(g, "Earth Shock", { note = "Use on cooldown for kill speed: buy every rank" })
    Add(g, "Strength of Earth Totem", { optional = true, note = "Big when grouped; skip only if you never group" })
    Add(g, "Windfury Totem", { optional = true, note = "Big when grouped (melee); skip only if you never group" })
    One(g, "Frost Shock", 20, "First rank only, for the slow. Higher ranks are for PvP", false)
    g.spells[#g.spells].rank = 1
    One(g, "Ghost Wolf", 20, "Cheap: buy it as soon as you can; it cuts travel time")
    One(g, "Water Breathing", 22, "Cheap: buy it as soon as you can")
    One(g, "Water Walking", 28, "Cheap: buy it as soon as you can")
    One(g, "Reincarnation", 30, "Cheap, and it saves a death")
    One(g, "Astral Recall", 30, "Cheap: buy it as soon as you can")
    One(g, "Cure Poison", 16)
    One(g, "Cure Disease", 22)
    Add(g, "Ancestral Spirit", { note = "Resurrection" })
    Skip(g, 30, "Windfury Weapon", "PvP only while leveling; Rockbiter is the PvE imbue")
    Skip(g, 34, "Frost Shock rank 2 and up", "PvP only")
    return g
end

-- Enhancement: melee. Healing is for dungeons only.
do
    local g = Base("enhancement", "Enhancement", "Enhancement")
    Add(g, "Healing Wave", { optional = true, note = "Only if you run dungeons; downrank to rank 5 for small heals" })
    Add(g, "Chain Heal", { optional = true, note = "Only if you run dungeons: rank 1 when everyone is hurt and close together" })
    Skip(g, 20, "Lesser Healing Wave", "avoid it unless someone would die without it")
    table.insert(CUI.LevelGuides.SHAMAN, g)
end

-- Elemental: casts damage spells, melees to finish.
do
    local g = Base("elemental", "Elemental", "Elemental")
    Add(g, "Lightning Bolt", { note = "Main damage spell: always buy the new rank" })
    Add(g, "Chain Lightning", { note = "Pack damage: always buy the new rank" })
    Add(g, "Flame Shock", { note = "Shocks on cooldown for kill speed" })
    Add(g, "Healing Wave", { optional = true, note = "Only if you run dungeons; downrank to rank 5 for small heals" })
    Add(g, "Chain Heal", { optional = true, note = "Only if you run dungeons" })
    Skip(g, 20, "Lesser Healing Wave", "avoid it unless someone would die without it")
    table.insert(CUI.LevelGuides.SHAMAN, g)
end

-- Restoration: heals dungeons, levels with a Flame Shock / Lightning Bolt rotation.
do
    local g = Base("heal", "Restoration", "Restoration")
    Add(g, "Healing Wave", { note = "Main heal: always buy the new rank, and downrank to rank 5 for small heals" })
    Add(g, "Lesser Healing Wave", { note = "Emergency quick heal" })
    Add(g, "Chain Heal", { note = "Group heal: buy every rank for dungeons" })
    Add(g, "Healing Stream Totem")
    Add(g, "Mana Spring Totem")
    Add(g, "Lightning Bolt", { note = "Main damage while leveling" })
    Add(g, "Chain Lightning")
    Add(g, "Flame Shock", { note = "Put it on the target, then Lightning Bolt, then melee to finish" })
    One(g, "Poison Cleansing Totem", 22)
    One(g, "Tremor Totem", 18, "Breaks fear, charm and sleep")
    -- the old table's skip notes that still apply
    for _, row in ipairs(ROWS) do
        for _, sk in ipairs(row.skip or {}) do
            local what, why = sk:match("^(.-)|(.*)$")
            if not what:find("Lightning Bolt") and not what:find("Chain Lightning") and not what:find("Flame Shock")
               and not what:find("Searing") and not what:find("Magma") and not what:find("Fire Nova") and not what:find("Water") then
                Skip(g, row[1], what, why)
            end
        end
    end
    table.insert(CUI.LevelGuides.SHAMAN, g)
end

--------------------------------------------------------------------------------
-- Quick reference on the settings page for the loaded guide: which spell to use for what.
--------------------------------------------------------------------------------
local TIPS = {
    earthwarden = {
        { "Threat", "Earth Shock (double threat) is your main threat button. Frost Shock if the target is immune or heavily resistant to nature, or fleeing." },
        { "Rotation", "Keep Lightning Shield up and Earth Shock on cooldown. From 40, Stormstrike on cooldown, then Earth Shock in its 20% nature bonus window. Use max-rank Earth Shock until you're safely ahead on threat, then downrank to save mana." },
        { "Weapon imbue", "Rockbiter at every level. It adds bonus threat to every auto-attack on top of normal damage threat. Never swap it out while tanking." },
        { "Pull", "Lightning Bolt. Rank 1 for fast trash pulls; max rank for packs, elites and bosses (every rank from 4 up casts in 3 seconds). Chain Lightning from 32 to tag 2-3 mobs." },
        { "Loose mob", "Earth Shock it. If two or more mobs are on the healer, drop Stoneclaw Totem, then put Stoneskin back once things settle." },
        { "Earth totem", "Stoneskin. Tremor instead on any pull with fear, charm or sleep. Strength of Earth only if another shaman has Stoneskin down." },
        { "Air totem", "Grace of Air from 42. Grounding on caster pulls at any level. Never Windfury Totem: it overwrites your Rockbiter." },
        { "Water totem", "Healing Stream; Mana Spring when you or the healer are low on mana." },
        { "Fire totem", "Searing on single targets. Magma or Fire Nova only on packs you already have threat on and with no crowd control, since they break sheep and sap. Fire Resistance in Blackrock Depths." },
        { "Self-heal", "Lesser Healing Wave in emergencies only. It's slow to cast while being hit, and it costs mana you need for shocks." },
    },
    enhancement = {
        { "Weapon imbue", "Rockbiter solo from 1 to 29; Flametongue against heavily armored mobs, since fire damage ignores armor. Flametongue in dungeons from 10 to 29, because Rockbiter adds threat to every swing. Windfury Weapon from 30, solo and in dungeons." },
        { "Rotation, solo", "Lightning Shield up. Earth Shock on cooldown for damage and interrupts. From 40, Stormstrike on cooldown, then Earth Shock in its nature bonus window. Frost Shock on fleeing humanoids. Let auto-attacks and Windfury procs do the rest to save mana." },
        { "Rotation, dungeons", "Stormstrike on cooldown and Flame Shock for damage. Earth Shock only to interrupt casters, since it deals double threat. Drop Lightning Shield if you're close to pulling aggro." },
        { "Totems, solo", "Strength of Earth always. Searing on tough mobs or 2+ pulls. Grace of Air from 42 on long fights." },
        { "Totems, groups", "Windfury Totem with other melee, but ask rogues first since it replaces their main-hand poison. It also overwrites your own Windfury Weapon with the totem's version. Strength of Earth or Grace of Air otherwise. Stoneskin if the tank is struggling, Mana Spring for casters, Tremor on fear, charm or sleep pulls." },
        { "Weapons", "Highest damage-per-second weapon at any speed before 30. From 30, the slowest strong two-hander you can get, ideally 3.5 speed or slower. Two-handed axes and maces need the Two-Handed Axes and Maces talent." },
        { "Stats", "Strength > Agility > Hit > Stamina > Intellect." },
        { "Level 30", "Windfury Weapon, the biggest power spike Enhancement gets. Train it immediately." },
        { "Level 40", "Stormstrike, mail armor and Windfury Weapon rank 2." },
    },
    elemental = {
        { "Weapon imbue", "Rockbiter from 1 to 9, then Flametongue from 10 on, solo and in dungeons. Your spell damage gear may add a little to Flametongue but does nothing for Rockbiter. Fire also ignores armor, and Flametongue never adds threat in groups." },
        { "Rotation, solo", "Pull with max-rank Lightning Bolt, a second one if the mob is still far, then Flame Shock as it arrives and Earth Shock to finish or interrupt. Chain Lightning from 32 on 2+ mobs. From 40, Elemental Mastery, then Chain Lightning or Lightning Bolt for a guaranteed crit. Downrank Lightning Bolt on easy mobs." },
        { "Rotation, dungeons", "Lightning Bolt and Chain Lightning for damage, plus Flame Shock for its damage over time. Earth Shock only to interrupt." },
        { "Mana", "Use Clearcasting procs on your most expensive spell. Melee-finish mobs below about 10% health to save drinking." },
        { "Totems, solo", "Searing for extra damage, Mana Spring on long sessions, Stoneskin when a mob reaches you." },
        { "Totems, groups", "Mana Spring for casters, Windfury Totem with melee, Grace of Air otherwise, Tremor on fear, charm or sleep pulls." },
        { "Stats", "Spell damage > Intellect > Spell crit > Mp5 > Stamina. Spirit only helps out-of-combat regen while leveling." },
        { "Level 40", "Elemental Mastery and Chain Lightning rank 2." },
    },
    heal = {
        { "Heal priority", "Healing Wave for steady healing, downranked to the smallest rank that covers the damage. Lesser Healing Wave in emergencies. Chain Heal from 40 when several allies are hurt. Nature's Swiftness into max-rank Healing Wave for an instant emergency heal, once you have the talent." },
        { "Cleanse", "Cure Poison (16) and Cure Disease (22). Poison Cleansing and Disease Cleansing Totems on pulls that apply a lot of either." },
        { "Mana", "Mana Spring Totem always down in groups. Mana Tide Totem on long fights once you have the talent. Healing Stream when you have spare mana. Pause casting for 5 seconds when you can, so spirit regen kicks in." },
        { "Weapon imbue", "Rockbiter solo, since healing gear does nothing for Flametongue. Flametongue in dungeons, so your occasional melee swings don't add threat. From 30, Windfury solo if you melee a lot with a two-hander." },
        { "Totems, groups", "Mana Spring (water). Stoneskin for the tank, or Tremor on fear, charm or sleep pulls (earth). Windfury Totem with melee, Grace of Air otherwise (air). Searing or Fire Resistance as needed (fire)." },
        { "Solo leveling", "Flame Shock and Lightning Bolt to pull, then melee. Heal yourself with downranked Healing Wave between pulls." },
        { "Stats", "+Healing > Intellect > Mp5 > Spirit > Stamina." },
        { "Level 40", "Chain Heal and mail armor. Chain Heal becomes your main group heal from here." },
    },
}
for _, g in ipairs(CUI.LevelGuides.SHAMAN) do g.tips = TIPS[g.key] end
