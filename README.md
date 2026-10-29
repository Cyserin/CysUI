# Cys's UI

A light, flat, gold-and-dark replacement UI for **WoW Classic Era** — one addon instead of a stack of them. Built to take over from ElvUI without the weight: every piece is a module you can switch on or off, and everything can be moved and resized.

> **Status: public test.** Built and played on Classic Era (1.15.9). It is also being prepared for **WoW Forever** (interface 16001, launching Nov 4, 2026) — that side is untested until launch. Bug reports from both are very welcome (see [Reporting a bug](#reporting-a-bug)).

## Install

1. Download the latest zip from the [Releases](../../releases) page.
2. Unzip it so the folder is named exactly **`CysUI`** and sits in `World of Warcraft\_classic_era_\Interface\AddOns\`.
3. Start the game and type **`/cui`**.

Running ElvUI too? Type `/cui` and open the **Conflicts** page — it lists what overlaps so you can turn one side off. Don't run both versions of the same piece (two action bars, two chat windows) at once.

## Commands

| Command | What it does |
| --- | --- |
| `/cui` | Settings window — a page per module, every feature has a switch |
| `/cui layout` | Layout mode — drag and resize every frame, snap to the grid |
| `/cui debug` | Prints client version and feature checks (include this in bug reports) |
| `/cui reload` | Reload the UI |
| `/cfriends` | Friends window |

## What's inside

**Core UI**
- Action bars 1–8, pet and stance bars (Blizzard's own buttons, so keybinds and macros behave)
- Unit frames (player, target, target-of-target, pet, party), raid frames for 10/20/40, nameplates
- Cast bars, player buffs/debuffs, group loot roll boxes
- Chat with copy button, class-colored names and timestamps; tooltips with rarity borders and vendor prices
- Minimap with zone bar and coordinates, a single button that gathers every other addon's minimap button
- Info bar, micro menu, slim XP bar, pixel-perfect UI scale
- Friends window (game + Battle.net friends, Who, Guild, Ignore)

**Cys's modules** (each can be turned off)
- **Bags & Bank** — categorized, searchable, sortable, drag to recategorize
- **Armory** — save gear sets, one-click swap; Alt-hover equipment flyout
- **Upgrade** — scores gear with stat weights you choose and marks bag items that beat what you wear
- **Skills** — weapon skill and profession tracker
- **Mail** — tick mails, then Open or Return the ticked ones
- **Roll Tracker** — tracks /roll and pass results and announces the winner
- **Raid Debuffs** — key raid debuffs on your target, only the ones your group can apply
- **Kill Tracker** — kills left to level
- **Totems** (Shaman) and **Warrior** helpers — class modules, shown only for that class
- **Damage Meters** — a Cys skin for [Details!](https://www.curseforge.com/wow/addons/details)

**Skins** — the Blizzard windows you actually use get the same look: character, reputation, skills, honor, spellbook, talents, macros, quest log and dialogs, gossip, loot, vendor, bank, mail, trainer, trade, professions, inspect, dressing room, battleground queue and scoreboard, world map, flight map, options and key bindings, chat settings, AddOn list, pop-ups and menus. Also skins for **Questie**'s tracker, the Details! meter and others' stock-looking options pages.

## Settings are per feature

Nothing is all-or-nothing. `/cui` has a switch for each module and for each skin, so if one thing doesn't suit you (or clashes with another addon) turn just that off.

## Reporting a bug

Open an [issue](../../issues) with:
1. What you did and what you expected
2. The red error text, if any (a BugSack/BugGrabber screenshot is perfect)
3. The output of **`/cui debug`**
4. Whether you're on Classic Era or WoW Forever

Screenshots of anything that looks off are the fastest way to get it fixed.

## Notes

- Saved variables: `CysUIDB` and one per module (`CysBagsDB`, `CysArmoryDB`, …). To start fresh, delete them from `WTF\Account\<name>\SavedVariables` with the game closed.
- Optional companions it plays well with: Details!, Questie, Postal, Plater / Platynator.
- The Auction House module is not part of this release.

## Credits & license

Made by **Randon** (Cys). Released under the [MIT license](LICENSE).
