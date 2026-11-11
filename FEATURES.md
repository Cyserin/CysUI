# What Cys's UI does

Every item below has its own switch in `/cui`. Anything marked *(layout)* can be moved and resized in `/cui layout`. Windows (Bags, Bank, Friends, Roll Tracker, Level-up spells) are not in layout mode: drag them by their title bar, and resize Bags, Bank and Friends by the grip in their bottom-right corner.

## Frames and combat
- **Action bars** *(layout)*: bars 1-8, pet bar and stance bar, flat and resizable, using Blizzard's own buttons so keybinds and macros behave. Rarity and gold edges.
- **Unit frames** *(layout)*: player (with a mana number on the mana bar), target, target-of-target, pet and party, with auras and combo points. Small corner names, an Elite / Rare / Boss tag beside the name, a soft gold line on the target frame.
- **Raid frames** *(layout)*: 10, 20 and 40-player layouts (auto-picked or forced), class colors, missing health, incoming heals, debuff icons with colored borders (only the ones you can dispel, optional), range fade, role icons, a preview mode.
- **Nameplates**: class and reaction colors, "mob is on you" coloring, your debuffs, a small cast bar, a gold target frame, a sword on mobs you still need for a quest.
- **Cast bars** *(layout)*: for you and your target, with icon, spell name, time left and an interrupt flag. The target's bar can be joined to the bottom of the target frame.
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
- **Skills** *(layout)*: when a weapon skill, Defense or profession goes up, a short line like "Axes 13 / 85" floats up above the player frame and fades. Classic Era and WoW Forever.
- **Mail**: tick mails, shift-click for a range, Open or Return the ticked ones.
- **Roll Tracker** *(layout)*: tracks /roll and pass results for loot and announces the winner; in raids only the leader, assistants and master looter announce.
- **Raid Debuffs** *(layout)*: tracks the key debuffs on your target (armor, fire, shadow, attack power, Hunter's Mark, Judgements and more) and only shows the ones your group can apply.
- **Threat Bar**: a flat bar for your threat on your target, colors flip for tanks, movable.
- **Combat Numbers**: floating numbers on your own frames. Damage taken, healing received and Miss / Dodge / Parry / Block on the player frame; your damage, pet damage, heals and misses on the target frame. Every kind can be switched off; the game's own numbers can be hidden.
- **Combat Log (Cys's logs)**: `/cuilog` opens a persistent run viewer. Each dungeon or raid is one run with bosses (kills and wipes), trash and every player's damage, healing, damage taken, casts and per-ability tables, plus a deaths list with a recap of the last hits. The last 3 to 10 runs are saved between sessions. Extra tabs show avoidable damage (Mistakes), boss debuff / Shield Block / totem uptimes (Uptimes) interrupts, dispels and taunts (Utility), and shield blocks, Bloodrage, Earth Shock, Rockbiter and totem damage (Class). Boss list covers the 15-60 dungeons. The window is resizable and remembers its size and place.
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
- **Cooldowns** (WoW Forever): the Cys look for the game's Cooldown Manager - square icons with a thin edge in your Border color, flat buff bars, and timer and stack numbers at your size. Optional own bars for the cooldown and utility rows: move them in Layout mode, set size and row length, and hide spells by stance.
- **Resource Bar**: your rage, energy or mana as its own movable, resizable bar for every class; can match the main cooldown bar's width.
- **Interrupt-ready cast bars**: enemy casts (target cast bar and nameplates) are grey while your interrupt is on cooldown, tick where it comes ready, green when it is up.
- **Swing Timer** (WoW Forever): your auto attack as a thin movable bar that fills from swing to swing, with lines for an off hand and a ranged weapon; can match the main cooldown bar's width.
- **Damage Meter** (WoW Forever): our own meter window in the Cys look, fed by the game's built-in damage meter (damage, healing, damage taken, absorbs, interrupts, dispels; current, overall or an earlier fight; spell list on hover out of combat). No combat log reading.
- **Frame Combat Text** (WoW Forever): the last hit as one still number in the middle of the player and target health bars (damage, heals, Miss / Dodge / Parry / Block), with an up / down setting.
- **Class modules** (shown only for that class): **Totems** for Shaman (a totem bar with timers, Drop All, loadouts, expiry alerts, action-bar macros and a weapon-imbue button) and **Warrior** (Battle Shout missing alert).

## Skins
Gold-and-dark look for the Blizzard windows: Esc menu, character, reputation, skills, honor, spellbook, talents, macros, quest log and dialogs, gossip, loot, vendor, bank, mail, class trainer, trade, professions, enchanting, inspect, dressing room, battleground queue and scoreboard, world map, flight map, friends / Who / Guild, raid tab, LFG, guild and communities, options and key bindings, chat settings, AddOn list, pop-ups, right-click menus, dropdowns, pet stable, tabard and charters, clock and stopwatch. Also **Questie**'s tracker and the Details! meter, and the stock-looking widgets on other addons' pages inside the options window. Each skin has its own switch.

## Tools (`/cui` -> General)
- **Memory light**: shows addon memory in KB or MB with a green / yellow / red status.
- **Copy debug info**, **Export / Import settings** (one pasteable line), **Reset everything**, **View changelog**.
- **Conflicts**: lists addons that overlap with Cys's UI so you can turn one side off.

## Added in 0.58.3
- **Forever target and nameplate auras in combat**, drawn by the game into Cys's UI icons; **icon size settings** for target buffs/debuffs and nameplate debuffs.

## Added in 0.58.2
- **Window stacking**: the settings, Friends and Heal Advisor windows open side by side with Blizzard's windows and push or close each other like Blizzard's own (switch under General).
- **Forever debuffs in combat**: target frame buffs and debuffs and your debuffs on nameplates keep working while the game locks aura details. **Raid Debuffs** is Era only (Forever hides other players' debuff names in combat).

## Added in 0.58.1
- **Forever map and quest log** fully skinned; **weapon imbue timer** on the Totem Bar; **Rockbiter counts as tank** for nameplate threat colors.
- **Upgrade leveling profiles (Forever only)** for every spec, shown only for your class, that switch by level; **Follow my talents** picks the set for your main talent tree. **Expertise** and **Armor Penetration** stats added.
- **Forever unit frames**: health and mana numbers and percentages, plus the **mana cost** of the spell you are casting.
- **Forever cast bars**: target and nameplate cast bars run off the game's own cast timer.
- **Kill Tracker** and **dropped totems** work in combat on Forever; skin errors link to **GitHub issues** with a click-to-copy box; settings search forgives longer words.

## Added in 0.58.0
- **WoW Forever support**: runs on the Forever client; modules that need the combat log (hidden from addons there) switch themselves off, and everything else works around Forever's locked values.
- **Forever skins**: the new character window and Blizzard's built-in damage meter, plus Forever's right-click menus.
- **Settings search** in the `/cui` top bar, and a **Cys's UI page under Options > AddOns**.
- **Heal prediction** on Forever uses real incoming heals from every healer.
- **Totem Bar**: macros option on its settings page; missing macros come back by themselves.

## Added in 0.57.0
- **Consumables**: self-updating Food, Drink, HP Potion, MP Potion, Bandage and Healthstone macros (conjured first), plus a per-character restock list bought at vendors.
- **Automation** (all off until ticked): fast loot, auto quests (Shift to pause), auto release in battlegrounds, Ding message, decline duels and guild charters, combat cursor ring, group level check (LFG listing and inside dungeons).
- **Durability**: a small movable warning box in place of Blizzard's armor figure.
- **Minimap tracking menu**: right-click the minimap.
- **Quest reward coin**, **Kill Tracker** level-up alerts, **Combat Numbers** boxes with a Flash in place style.
- **Trainer recording** for building level-up guides.
- Module switches are **per character**; highlights and hover glows follow the **Border color**.

## Class support
What each class-dependent module covers today (Classic Era). Guides and class modules are added as they are made.

| Module | Supported | To add |
| --- | --- | --- |
| Level-Up Spells | Shaman: Earth Warden (tank), Enhancement, Elemental, Restoration | every other class |
| Totems | Shaman | |
| Heal Advisor | Shaman, Priest, Druid, Paladin (healing spells) | Paladin Judgement/Holy Shock extras |
| Tremor Alert | Shaman | |
| Battle Shout alert | Warrior | |
| Raid Debuffs, Interrupts, Waypoints, Upgrade, Combat Log, Taunt Alert, Missing Buffs, Consumables, Automation, Durability | all classes | |

WoW Forever: the level-up guides are a work in progress, because no leveling guides for Forever's classes exist yet.
