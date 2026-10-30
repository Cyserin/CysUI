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
    role = "Tank",
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
-- More guides (Enhancement DPS, Elemental DPS, Healer, Questing) are built from it below.
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

local function Build(key, name, role, spec, tag)
    local g = { key = key, name = name, role = role, spec = spec, client = "Era", spells = {}, skips = {} }
    for _, row in ipairs(ROWS) do
        Parse(row[tag], row[1], g.spells)
        Parse(row.all, row[1], g.spells)
        for _, s in ipairs(row.skip or {}) do
            local what, why = s:match("^(.-)|(.*)$")
            local sp, rk = what:match("^(.-)%s+R(%d+)$")
            g.skips[#g.skips + 1] = { level = row[1], spell = sp or what, rank = tonumber(rk), why = why }
        end
    end
    -- Windfury Weapon is tagged for both D and Q in two columns; keep each guide free of repeats
    local seen, uniq = {}, {}
    for _, e in ipairs(g.spells) do
        local k = e.spell .. ":" .. (e.rank or 0)
        if not seen[k] then seen[k] = true; uniq[#uniq + 1] = e end
    end
    g.spells = uniq
    return g
end

table.insert(CUI.LevelGuides.SHAMAN, Build("enhancement", "Enhancement DPS", "Enhancement, dungeon DPS", "Enhancement", "D"))

-- Elemental: only the shared DPS list exists so far, so this one is a draft. Windfury Weapon is a melee
-- spell and the table's skip notes assume an Enhancement pull, so both are left out until there is an Elemental list.
do
    local g = Build("elemental", "Elemental DPS (draft)", "Elemental, dungeon DPS", "Elemental", "D")
    local keep = {}
    for _, e in ipairs(g.spells) do
        if e.spell ~= "Windfury Weapon" then keep[#keep + 1] = e end
    end
    g.spells, g.skips, g.draft = keep, {}, true
    table.insert(CUI.LevelGuides.SHAMAN, g)
end
table.insert(CUI.LevelGuides.SHAMAN, Build("heal", "Healer", "Restoration", "Restoration", "H"))
table.insert(CUI.LevelGuides.SHAMAN, Build("quest", "Questing", "Any spec", "any", "Q"))

-- quick reference shown on the settings page: which spell to use for what
CUI.LevelTips = CUI.LevelTips or {}
CUI.LevelTips.SHAMAN = {
    { "Threat", "Earth Shock; Frost Shock if the target resists nature or is fleeing" },
    { "Pull", "Lightning Bolt; Chain Lightning (level 32+) to tag 2-3 mobs" },
    { "Questing imbue", "Flametongue Weapon (10-29), Windfury Weapon (30+); Rockbiter when tanking" },
    { "Big heal", "Healing Wave; Lesser Healing Wave when a 3-second cast would land too late" },
    { "Earth totem", "Stoneskin; Strength of Earth if you DPS or another shaman has Stoneskin" },
    { "Air totem", "Grace of Air (42+); Windfury Totem or Grounding for melee DPS or caster packs" },
    { "Water totem", "Healing Stream; Mana Spring when someone is low on mana" },
    { "Fire totem", "Searing; Magma or Fire Nova on packs you already have threat on" },
    { "Loose mob", "Earth Shock, then Stoneclaw Totem when two or more mobs are on the healer" },
}
