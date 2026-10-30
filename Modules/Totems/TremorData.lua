-- Tremor Totem recommendation data for WoW Classic Era (1.15.x)
-- Mobs whose abilities Tremor Totem can break (Fear, Charm, Sleep).
--
-- type     = "fear" | "sleep" | "charm"
-- boss     = true for bosses, false for trash
-- verified = true when the ability was confirmed from a dungeon journal or wiki
--            source; false means "reported, confirm in game before relying on it"
-- note     = optional extra context for the tooltip/alert
--
-- Names are English (enUS). Mobs the alert learns in game are saved separately (CysUIDB.tremor.learned).

local D = {}
CysUI.Tremor = D

D.Dungeons = {
    ["Wailing Caverns"] = {
        { npc = "Lady Anacondra",        spell = "Druid's Slumber",     type = "sleep", boss = true,  verified = true },
        { npc = "Lord Pythas",           spell = "Druid's Slumber",     type = "sleep", boss = true,  verified = true },
        { npc = "Lord Cobrahn",          spell = "Druid's Slumber",     type = "sleep", boss = true,  verified = true },
        { npc = "Lord Serpentis",        spell = "Druid's Slumber",     type = "sleep", boss = true,  verified = true },
        { npc = "Mutanus the Devourer",  spell = "Terrify",             type = "fear",  boss = true,  verified = true },
        { npc = "Mutanus the Devourer",  spell = "Naralex's Nightmare", type = "sleep", boss = true,  verified = true },
        { npc = "Druid of the Fang",     spell = "Sleep",               type = "sleep", boss = false, verified = true,
          note = "Trash druids that sleep party members" },
    },

    ["Blackfathom Deeps"] = {
        { npc = "Twilight Lord Kelris",  spell = "Sleep",               type = "sleep", boss = true,  verified = true },
    },

    ["Razorfen Kraul"] = {
        { npc = "Death Speaker Jargba",  spell = "Dominate Mind",       type = "charm", boss = true,  verified = true },
    },

    ["Scarlet Monastery"] = {
        { npc = "High Inquisitor Whitemane", spell = "Deep Sleep",      type = "sleep", boss = true,  verified = true,
          note = "Sleeps the whole party, then resurrects Mograine" },
        { npc = "High Inquisitor Fairbanks", spell = "Sleep",           type = "sleep", boss = true,  verified = true },
        { npc = "High Inquisitor Fairbanks", spell = "Fear",            type = "fear",  boss = true,  verified = true },
    },

    ["Zul'Farrak"] = {
        { npc = "Shadowpriest Sezz'ziz", spell = "Psychic Scream",      type = "fear",  boss = true,  verified = true },
    },

    ["The Temple of Atal'Hakkar"] = {
        { npc = "Shade of Eranikus",     spell = "Deep Slumber",        type = "sleep", boss = true,  verified = true },
        { npc = "Jammal'an the Prophet", spell = "Hex of Jammal'an",    type = "charm", boss = true,  verified = false,
          note = "Confirm Tremor breaks it" },
    },

    ["Blackrock Depths"] = {
        { npc = "High Interrogator Gerstahn", spell = "Psychic Scream", type = "fear",  boss = true,  verified = true },
    },

    ["Blackrock Spire"] = {
        { npc = "The Beast",             spell = "Terrifying Roar",     type = "fear",  boss = true,  verified = true,
          note = "Upper Blackrock Spire" },
    },

    ["Dire Maul"] = {
        { npc = "Magister Kalendris",    spell = "Dominate Mind",       type = "charm", boss = true,  verified = true,
          note = "Dire Maul West" },
        { npc = "Captain Kromcrush",     spell = "Frightening Shout",   type = "fear",  boss = true,  verified = true,
          note = "Dire Maul North" },
    },

    ["Stratholme"] = {
        { npc = "Balnazzar",             spell = "Psychic Scream",      type = "fear",  boss = true,  verified = true },
        { npc = "Balnazzar",             spell = "Sleep",               type = "sleep", boss = true,  verified = true },
        { npc = "Balnazzar",             spell = "Domination",          type = "charm", boss = true,  verified = true },
        { npc = "Baroness Anastari",     spell = "Possess",             type = "charm", boss = true,  verified = true,
          note = "Confirm Tremor breaks Possess" },
        { npc = "Rockwing Screecher",    spell = "Fear",                type = "fear",  boss = false, verified = true,
          note = "Undead side trash; AoE fear" },
    },

    ["Scholomance"] = {
        { npc = "Lady Illucia Barov",    spell = "Fear",                type = "fear",  boss = true,  verified = true },
        { npc = "Lady Illucia Barov",    spell = "Mind Control",        type = "charm", boss = true,  verified = false },
    },
}

-- Fast lookup: npc name -> list of entries (built once on load)
D.ByNPC = {}
for dungeon, list in pairs(D.Dungeons) do
    for _, entry in ipairs(list) do
        entry.dungeon = dungeon
        D.ByNPC[entry.npc] = D.ByNPC[entry.npc] or {}
        table.insert(D.ByNPC[entry.npc], entry)
    end
end

function D.GetThreats(npcName)
    return D.ByNPC[npcName]
end
