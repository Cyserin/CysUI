# What Cys's UI does

Every item below has its own switch in `/cui`. Anything marked *(layout)* can be moved and resized in `/cui layout`.

## Frames and combat
- **Action bars** *(layout)*: bars 1-8, pet bar and stance bar, flat and resizable, using Blizzard's own buttons so keybinds and macros behave. Rarity and gold edges.
- **Unit frames** *(layout)*: player (with a mana number on the mana bar), target, target-of-target, pet and party, with auras and combo points.
- **Raid frames** *(layout)*: 10, 20 and 40-player layouts (auto-picked or forced), class colors, missing health, incoming heals, debuff icons with colored borders (only the ones you can dispel, optional), range fade, role icons, a preview mode.
- **Nameplates**: class and reaction colors, "mob is on you" coloring, your debuffs, a small cast bar, a gold target frame.
- **Cast bars** *(layout)*: for you and your target, with icon, spell name, time left and an interrupt flag.
- **Player auras** *(layout)*: movable buff and debuff rows with gold borders; right-click to cancel.
- **Group loot boxes** *(layout)*: skins Blizzard's Need / Greed roll boxes.

## Interface
- **Chat** *(layout)*: flat, gold-edged windows with a Copy button, class-colored names and timestamps.
- **Tooltips** *(layout)*: flat gold-edged, rarity borders, class-colored names, vendor sell price, movable.
- **Minimap** *(layout)*: square, zone bar, coordinates, mouse-wheel zoom. **Minimap Button** gathers every other addon's minimap button behind one Cys button.
- **Info bar** *(layout)*: combat timer, guild and friends online, durability, bag slots, gold, FPS and latency, clock. Can be split across a main bar and a bar under the minimap.
- **Micro menu** *(layout)*: a text menu for Character, Spells, Talents, Quests, Social, Guild, Bags, Menu.
- **XP bar** *(layout)*: slim gold-edged bar with a rested overlay and a detailed tooltip.
- **UI scale**: pixel-perfect scale for your resolution.
- **Friends window** *(layout)*: game and Battle.net friends grouped by what they're playing, Who, Guild and Ignore, search, whisper and invite. `/cfriends`.
- **Layout mode**: drag and resize everything, snap to a grid, reset one or all.

## Cys's modules
- **Bags** *(layout)*: one categorized window with a sidebar, search, sort, an "All slots" view, drag to recategorize. **Bank** does the same at any banker.
- **Armory**: save gear as named sets and put them back on in one click; bind sets to a spec. **Equipment flyout**: hold Alt over a character slot to see bag items that fit it.
- **Upgrade**: scores gear with stat weights you choose, shows the score and Upgrade / Downgrade on item tooltips, marks bag items that beat what you wear. SixtyUpgrades CSV import, weapon speed counts, profiles switch with your talent spec.
- **Skills** *(layout)*: weapon skill and profession tracker for the gear you have equipped.
- **Mail**: tick mails, shift-click for a range, Open or Return the ticked ones.
- **Roll Tracker** *(layout)*: tracks /roll and pass results for loot and announces the winner; in raids only the leader, assistants and master looter announce.
- **Raid Debuffs** *(layout)*: tracks the key debuffs on your target (armor, fire, shadow, attack power, Hunter's Mark, Judgements and more) and only shows the ones your group can apply.
- **Combat Log (Cys's logs)**: `/cuilog` opens a persistent run viewer. Each dungeon or raid is one run with bosses (kills and wipes), trash and every player's damage, healing, damage taken, casts and per-ability tables, plus a deaths list with a recap of the last hits. The last 3 to 10 runs are saved between sessions. Extra tabs show avoidable damage (Mistakes), boss debuff / Shield Block / totem uptimes (Uptimes) interrupts, dispels and taunts (Utility), and shield blocks, Bloodrage, Earth Shock, Rockbiter and totem damage (Class). Boss list covers the 15-60 dungeons.
- **Taunt Alert**: tells you when someone else or a pet taunts a mob you were tanking, and when your own taunt is resisted.
- **Missing Buffs**: icons for Fortitude, Mark of the Wild, Arcane Intellect and Divine Spirit when your group lacks them, only for classes that need them. Out of combat only.
- **Kill Tracker**: learns your average XP per kill and shows how many more kills it takes to level.
- **Heal Advisor** (Druid, Paladin, Priest, Shaman): `/cuirank` opens a window that reads your stats, healing talents and heal ranks and says which rank to use for small hits, general healing, heavy damage, emergencies and group healing (only spells you know). Scan saves your stats; a popup says when learning something changes the advice. Preview shows a sample healer and Copy report makes text to paste into a bug report.
- **Tremor Alert** (Shaman): a Tremor Totem icon with mob - ability lines when a mob that fears, charms or sleeps is in the pack. Ships with a dungeon list and learns new NPC casters as you play (never players, never in battlegrounds or arenas).
- **Level-Up Spells**: when you level up or open your trainer, a box lists the spells worth buying now and why; spells you skipped stay on the list. `/cuilevel` shows it (`/cuilevel 24 restoration` previews any guide), `/cuiscan` checks the guide against your trainer. Shaman guides so far (Earth Warden tank, Enhancement, Elemental, Restoration); it asks which guide to follow at level 10 and when you get a second talent spec, see Class support below; it also lists what to skip and why.
- **Interrupt announcer**: says "Interrupted <target>'s <spell>!" to your group (or just you) when you interrupt a cast. Any class.
- **Waypoints**: a TomTom-style arrow with distance and time left. Ctrl + left-click the world map, `/way 45 62 Name`, or mark a Questie quest. *(layout)*
- **Vendor**: Sell Junk button, optional auto-sell of grey items, auto-repair.
- **Damage Meters**: a Cys skin for Details! (flat bars with gold edges).
- **Class modules** (shown only for that class): **Totems** for Shaman (a totem bar with timers, Drop All, loadouts, expiry alerts, action-bar macros and a weapon-imbue button) and **Warrior** (Battle Shout missing alert).

## Skins
Gold-and-dark look for the Blizzard windows: Esc menu, character, reputation, skills, honor, spellbook, talents, macros, quest log and dialogs, gossip, loot, vendor, bank, mail, class trainer, trade, professions, enchanting, inspect, dressing room, battleground queue and scoreboard, world map, flight map, friends / Who / Guild, raid tab, LFG, guild and communities, options and key bindings, chat settings, AddOn list, pop-ups, right-click menus, dropdowns, pet stable, tabard and charters, clock and stopwatch. Also **Questie**'s tracker and the Details! meter, and the stock-looking widgets on other addons' pages inside the options window. Each skin has its own switch.

## Tools (`/cui` -> General)
- **Memory light**: shows addon memory in KB or MB with a green / yellow / red status.
- **Copy debug info**, **Export / Import settings** (one pasteable line), **Reset everything**, **View changelog**.
- **Conflicts**: lists addons that overlap with Cys's UI so you can turn one side off.

## Class support
What each class-dependent module covers today (Classic Era). Guides and class modules are added as they are made.

| Module | Supported | To add |
| --- | --- | --- |
| Level-Up Spells | Shaman: Earth Warden (tank), Enhancement, Elemental, Restoration | every other class |
| Totems | Shaman | |
| Heal Advisor | Shaman, Priest, Druid, Paladin (healing spells) | Paladin Judgement/Holy Shock extras |
| Tremor Alert | Shaman | |
| Battle Shout alert | Warrior | |
| Raid Debuffs, Interrupts, Waypoints, Upgrade, Combat Log, Taunt Alert, Missing Buffs | all classes | |

WoW Forever: the level-up guides are a work in progress, because no leveling guides for Forever's classes exist yet.
