# Heal Advisor test cases

Each case gives the ranks the character knows (heal / mana / cast, after talents) and the picks the rules in
`Modules/HealAdvisor/CysHealAdvisor.lua` must produce. Shaman cases are checked against the rules. The other classes
are filled in once a guildie of that class has confirmed the picks in game.

## Rules in one place
- main = the slow efficient single-target ladder, fast = the quick single-target heal. Several spells in one family form one ladder.
- best = highest heal per mana across both families. eff(rank) = its heal per mana / best.
- Heavy = biggest main rank with eff >= 0.90. General = biggest main rank smaller than Heavy with eff >= 0.90 (ties: shorter cast, then less mana).
- Small = smallest main rank with eff >= 0.80 that heals at least 20% of Heavy.
- Emergency = biggest heal in the fast family. With no fast heal: biggest heal that casts in 1.5s or less (Druid 2.0s) and heals at least 20% of Heavy.
- Left out of these four rows: heal-over-time spells and parts, absorbs, group heals, cooldowns.
- Paladin (to confirm): Small and General read from Flash of Light (eff measured inside that family), Heavy from Holy Light, Emergency from Flash of Light.

## Shaman (rules checked)
| Level | Bonus | Ranks (heal/mana/cast) | Heavy | General | Small | Emergency |
|---|---|---|---|---|---|---|
| 23 | 11 | HW1 42/25/1.5, HW2 78/45/2.0, HW3 154/80/2.5, HW4 312/155/3.0, LHW1 184/105/1.5 | Healing Wave 4 | Healing Wave 3 | Healing Wave 2 | Lesser Healing Wave 1 |
| 24 | 11 | as above plus HW5 417/200/3.0 | Healing Wave 5 | Healing Wave 4 | Healing Wave 3 | Lesser Healing Wave 1 |
| 40 | 0 | HW1-4 as above, HW5 408/200, HW6 579/265, HW7 797/340, LHW1 184/105, LHW3 359/185 | Healing Wave 7 | Healing Wave 6 | Healing Wave 4 | Lesser Healing Wave 3 |

## Priest, Druid, Paladin (to confirm with a guildie)
Add a row per confirmed character: level, bonus healing, the rank list from Copy report, and the four picks the guildie agrees with.

## What to ask each guildie for
1. Equip the gear they normally heal in.
2. Type /cuiheal. It scans by itself and opens the Heal Test box.
3. Cast each known rank once on anyone, even themselves at full health (the log records the full amount and the overheal separately). Critical heals do not count; cast that rank again.
4. When the box says All ranks logged, click Copy report. In the cysui-feedback channel in Discord they type /bug, pick their class under area, and paste the report into text (it comes in parts of up to 1400 characters; Next part shows the next one).
5. Note their level, talent points in the trees above, and bonus healing.

The report puts each rank's real heal next to the advisor's number. If they differ by more than about 5%, fix the coefficient or talent math for that spell.
