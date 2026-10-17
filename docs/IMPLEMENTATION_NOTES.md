# Prototype 1: implementation notes

What was built for the six milestones in GAME_DESIGN.md, how each check was verified, every place the spec was unclear and how that was resolved, the balance results, and what is not done. The checkboxes in GAME_DESIGN.md are left for the designer to tick.

All of it was built in one pass (milestones 1 to 6 in order). Each milestone is a commit on its own stacked branch (`milestone-1` to `milestone-6`); nothing is merged to `main` yet.

## The milestone checks

Every check runs headless: `bash tools/run_tests.sh` runs all six suites (118 checks; about 5 minutes, most of it the milestone 6 batch). The suites also cover behaviour the checkboxes imply but don't name.

| Milestone | Check in GAME_DESIGN.md | How it is verified | Result |
| --- | --- | --- | --- |
| 1 Skeleton | Clock runs from Day 0 06:00 and shows day, time and phase | `test_milestone_1`: tick 0/72/144 clock strings and phases; 3 headless days give exactly 3 `day_started`. On screen: screenshots of the running game | Pass |
| 1 | A test event fires on the bus and is logged | `test_milestone_1`, plus the Test event button and T key in the game | Pass |
| 2 Survivors | With no water, a survivor dies on about day 3 | `test_milestone_2`: all water removed; resting survivors die of dehydration at 3.1 days, hard outdoor workers at 2.6 | Pass |
| 2 | Fatigue and sleep cycle work over a full day | `test_milestone_2`: fatigue 10 → 56 over a fortifying day, back to 0 after the night, no sleep debt; a night guard builds 6.8 h of debt and sleeps it off next day | Pass |
| 3 Town | Click a building to see its type and remaining loot | `test_milestone_3` clicks the real map widget and reads the building panel; also seen in screenshots | Pass |
| 3 | Pharmacy loot visibly drains over the first week | `test_milestone_3`: pharmacy medicine falls to 19% by day 7 (houses to 87%) | Pass |
| 4 Infected | A gunshot shifts infected counts in nearby zones | `test_milestone_4`: neighbours within 600 m lose infected to the gunshot zone, zones beyond are untouched; quiet searching moves nobody | Pass |
| 4 | A bitten survivor turns within 24–72 hours | `test_milestone_4`: 24 bites (neck/torso/arm/leg) all turn in 32–67 h; neck fastest (36 h), legs slowest (58 h) | Pass |
| 5 Base | Power fails between day 3 and 6 in every run | `test_milestone_5`: 100 seeds, failure days spread over 3, 4, 5 and 6, never outside | Pass |
| 5 | An unguarded base with no barricades falls to a night attack | `test_milestone_5`: 10 of 10 crowded unguarded houses breached within 5 nights; a barricaded police station with two guards held all 12 attacks against the same crowd | Pass |
| 6 Events | A full 30-day run is completable | `test_milestone_6`: auto-played runs end won or lost by day 30, the end screen shows the score, time stops after | Pass |
| 6 | The batch run shows survival is neither near 0% nor near 100% | `test_milestone_6` (40 games) and the 100-game batch below | Pass |

## Balance: 100 games per strategy

`godot --headless --script res://tools/headless_runner.gd -- --games=100 --strategy=all` (11.5 minutes):

| Strategy | Runs won | Survivors alive at the end | Breaches per game | Main losses |
| --- | --- | --- | --- | --- |
| Fortress: police station, barricades, two guards, guns | 93% | 72% | 0.0 | turned 129, left 14, scattered 13 |
| Balanced: stay in the start house, fortify it | 70% | 52% | 1.6 | turned 169, scattered 55, left 38 |
| Hoard water: St. Mary's school and its 5,000 L tank | 67% | 48% | 1.5 | turned 213, scattered 54, left 24 |
| Keep moving: relocate every 4 days | 17% | 12% | 1.6 | turned 168, scattered 153, left 126 |

These numbers measure the auto-player as much as the game. It is a simple rule-based player (`tools/auto_player.gd`); a thoughtful human should do better.

## Spec ambiguities and how they were resolved

Each was settled by the realism rules or the simplest option that keeps the architecture intact. Every one is cheap to change.

**Time and calendar**
- Day numbers change at midnight, like a calendar. Day 0 therefore runs 06:00–23:50 (18 hours). It started as "days change at 06:00", but then 05:20 the next morning showed as the same day, which read wrong in the log. All milestone 1 checks hold either way.
- The calendar starts on 15 April (from the world scrubber), so all 30 days are peak summer: 26–28 °C nights, 37–40 °C afternoons, with daily jitter.
- A run is won at Day 30 06:00, after 30 full days.

**Survivors and the body**
- Five fixed survivors from `survivors.json`: Meera (nurse), Arjun (electrician), Farhan (mechanic) and Lakshmi (farmer) from the scrubber, plus Ravi (police constable). Kavya (teacher) is the stranger who can join. This answers the open question "does the player pick?" with "no, not yet".
- The 0–100 need bars in the Systems section are replaced by the Fidelity map's real units:
  - water deficit in litres
  - energy debt in kcal
  - blood volume in litres
  - core temperature in °C
- Health, fatigue and stress stay 0–100.
- Morale is shown as 100 − stress. So "morale below 20 refuses jobs" is stress ≥ 80, and "below 5 may leave" is stress ≥ 95.
- Water need is 3 L a day at 25 °C, +4% per °C above that, and up to ~6.5 L for hard outdoor work in 40 °C heat.
- Dehydration: thirsty at 3 L behind, confused and losing health at 6 L, collapsing at 9 L. That gives death on about day 3, as the spec asks.
- Energy: 2,000 kcal a day at rest for a 70 kg adult, scaled by body weight; heavy work burns 1.7× that.
  - The full ration is 3,000 kcal.
  - People eat only what their body is short of, plus a little; a resting day saves food.
  - A "full ration day" means the order was full and nobody went to bed hungry.
- Fractures are left out. The Systems section lists them, but the Fidelity map puts them in Prototype 2–3, and the Fidelity map wins.
- Wounds are cut, deep laceration, arterial bleed and bite:
  - bleed rates follow the body section
  - an arterial bleed is fatal unless a tourniquet is to hand
- The infection chain runs local → fever (48–72 h) → sepsis (36–60 h), with daily infection chances of 5% (cut) and 20% (wound) from the spec.
- Antibiotics are always the player's call. They cure local infections and fever; for sepsis, success depends on the medic's skill.
- Bites incubate faster nearer the brain, plus a 6–12 h prodrome:
  - neck: 24–42 h in total
  - torso: 30–60 h
  - limbs: 42–72 h
  
  That keeps the 24–72 h check while honouring "longer for limb bites".
- A bite is reported, or hidden, when the survivor gets back to base. The chance of hiding it rises with stress (15–40%). A hidden bite shows as a cut until the fever gives it away.
- Waterborne illness: each day someone drinks untreated water carries a 30% chance (the spec's figure).
  - 80% of cases are dysentery (2 L/day fluid loss); 20% are cholera (6 L/day).
  - ORS cuts the loss by 60%.
- Heat exhaustion at 38.5 °C core forces rest. Heatstroke is left for Prototype 2–3.
- Painkillers, which the spec places under pain (Prototype 2–3), are used in a small way: a medic gives one to ease the stress of a fresh wound.

**Town and loot**
- The town has 50 buildings, not "about 60". The spec's own building table adds up to 50, so the table was followed.
- The map is hand-laid in `tools/make_town.py`, which validates it and writes `data/town.json`. This answers the open question "hand-made or generated?" with "hand-made, by a script you can edit".
- Loot lives only in `loot_tables.json`; `buildings.json` points to it. The spec's example had pharmacy loot inside `buildings.json` as well as a separate loot table file, so there were two places for the same data. The pharmacy entry otherwise keeps the example's values.
- Food is stored in kcal, as rule 5 says. Its weight comes from kcal per kg, for carrying.
- A survivor carries 25 kg, with per-category caps so one trip isn't all rice. Medicine is packed first, then gear the group lacks (a generator, water drums).
- Trips walk the street grid at 1.8 km/h out and 1.4 km/h back loaded, plus a 2-hour search. That gives 2.5 h to the nearest shop and 5.7 h to the farthest building, matching "2–6 hours".
- Locked doors are forced once, with 50 m of noise. Searching at night takes longer and finds less.
- Looted-by-others rates for types the spec doesn't name:

  | Building | Daily rate |
  | --- | --- |
  | Petrol pump | 10% |
  | Hospital | 10% |
  | Police station | 5% |
  | Factory | 4% |
  | Hardware shop | 3% |
  | Water tower | 3% |
  | School | 2% |

- Once the taps fail, every roof tank except your base's loses 8% a day to other people drawing water.

**Infected**
- The infected numbers follow the world scrubber:
  - 6,000 at the start, concentrated at the hospital, bus stand and market
  - +1,200 a day until day 5, then holding near 12,000
  - −2% a day from day 15
- Die-off is slower in zones with water and faster on 40 °C days. They drift slowly between zones and move toward the canal in afternoon heat.
- Activity: 1.0 at night, 0.75 at dawn and dusk, 0.5 by day, and down to ~0.25 in 38 °C midday heat. Encounter risk at night is therefore about 4× midday.
- Noise pulls infected from zones its radius reaches. Gunshots reach 600 m, the generator 150 m, hammering 80 m, a forced door 50 m, searching 10 m.
- Light at night (a running generator) pulls weakly from 1 km.
- Encounter outcomes are avoided, fought off, injured, bitten or killed. They depend on:
  - zone density, noise and time of day
  - scavenging skill (stealth) and combat skill
  - weapon, fatigue and sleep debt
- Firing a rifle helps the fight but makes a 600 m gunshot.

**Base and infrastructure**
- Phones go down on day 2, power on day 3–6, mains on day 7–12.
- A generator burns 1 L of fuel an hour, makes 150 m of noise, and shows 1 km of light at night.
- Fridges: while there is power (grid or generator), food that keeps a week or less is kept at 8 °C. This is a small realism addition the spec doesn't mention.
- "1 unit of fuel per 10 litres" for boiling was ambiguous next to fuel in litres. Resolved as:
  - cooking gas (LPG, which Indian homes cook on): 0.15 kg per 10 L, which is realistic
  - otherwise one unit of materials burned as firewood per 10 L, the spec's number
  
  Cooking rice, dal and atta uses the same fuels. Raw staples can't be eaten without a cook.
- Before the mains fail, "collect water" fills containers from the tap: 200 L of basic containers plus 200 L per water drum found. After, it ferries jerry cans from the nearest roof tank or the canal, out in the open.
- Defense is:
  - the building's base defense (house 10, school 25, police station 50, as specified)
  - plus barricades (3 materials an hour on the fortify job, up to a cap per building type)
  - plus guards (10 + 2 × combat each, less when tired)
  - plus weapons, plus 2 for each other able survivor
- Night attacks are rolled hourly. The chance rises with infected in the base's zone and with the noise/light "alert" level, and falls with defense. An attack held wears the barricades down; a breach halves them and can wound, bite or kill people inside.
- Moving base: the group carries 25 kg each, medicine and food first. The rest stays in the old building to be scavenged later, and barricades stay with the building. The opening "pick a base" is handled as "you start in a house; move whenever you like".

**Events and outcome**
- There are 12 events in `events.json`, each with a cause in the world:
  - lockdown and panic buying
  - police gunshots at the bus stand
  - a night raid on a pharmacy
  - a relief camp that opens at the Govt. school, then is overrun when an evacuee who hid a bite turns
  - an abandoned checkpoint that leaves the police armoury open
  - the last radio broadcast
  - a stranger at the gate (who may be hiding a bite)
  - a market fire from a cooking fire left in a looted shop
  - a heat wave
  - a pre-monsoon storm that refills tanks by roof area
- "Survivor hides a bite" and "sick from bad water" come out of the survivor systems rather than event cards.
- Score = 100 per survivor alive + 10 per full-ration day + supplies stored, in person-days of food and water plus 5 per antibiotic strip.

**Architecture**
- Extra core files beyond the spec's folder list:
  - `sim_run.gd`: starts a run the same way everywhere
  - `sim_system.gd`: the system base class
  - `stores.gd`, `body.gd`, `geo.gd`, `decisions.gd`: shared plain-data helpers
- `systems/outcome.gd` was added for win/lose.
- Player orders and decisions travel as bus events (`command_*`, `decision_made`). The UI and the headless auto-player use the same path.
- Headless scripts (`--script`) are thin wrappers that load the real code at runtime. Godot compiles them before the autoload names exist.
- The Time system reports a broken clock as a `clock_error` event, not `assert`: in a headless run a failed assert waits for a debugger forever.
- Untyped GDScript declarations are compile errors (project setting), so the typed-code rule enforces itself.
- Tests run in "sandbox" mode (`WorldState.flags.sandbox`), so a run never ends while a check is still looking at it.
- The UI reads two tuning constants from `systems/jobs.gd` (trip speeds) for its trip estimate, rather than duplicating them.

## Not done, or not verified

- **Not played by hand end to end.** The UI was checked by scripted clicks and key presses, headless UI tests and screenshots, and the simulation by tests, story runs and batches.
- **Keep moving is the weakest strategy (17% won).** Each move abandons whatever can't be carried and leaves barricades behind, so hunger and stress break the group. The spec wants it to be a viable strategy. It may need cheaper moves (carts, handcarts, vehicles), quick barricading, or a better auto-player. Worth discussing.
- **Losses are mostly bites and broken morale.** Starvation, sepsis, illness and heat rarely kill a decently run group in 30 days. That matches the spec's timeline, where hunger and disease take over after day 30, but it is a design question.
- **The auto-player is basic.** It never uses the generator, only fires guns as the fortress, never chooses rationing beyond food stocks, and answers bites with quarantine every time.
- **The UI is functional rather than friendly.** The survivor cards are tall and text-heavy. There are no tooltips explaining numbers, and no way to set loot priorities or pick a water source.
- **Not modelled from the Prototype 1 column:**
  - petrol going stale after ~30 days (beyond the run)
  - generator "charging" (nothing needs charging yet)
- **Exported builds** need `*.json` added to the export filter (the data folder isn't a Godot resource).
- **Every balance number is a starting value.** Rule 7 has them in data files or named constants at the top of each system.

## Where to look

- Story of one run: `godot --headless --script res://tools/headless_runner.gd -- --seed=7 --days=30 --strategy=balanced --verbose=1`
- Tuning: constants at the top of each file in `systems/`, plus `data/scenario.json`, `buildings.json`, `loot_tables.json`, `events.json`.
- The town: edit `tools/make_town.py` and run `python3 tools/make_town.py`.
