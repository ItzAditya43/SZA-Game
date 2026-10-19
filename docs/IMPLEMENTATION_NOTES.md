# Prototype 1: implementation notes

What was built for the six milestones in GAME_DESIGN.md, how each check was verified, every place the spec was unclear and how that was resolved, the balance results, and what is not done. The checkboxes in GAME_DESIGN.md are left for the designer to tick.

All of it was built in one pass (milestones 1 to 6 in order). Each milestone is a commit on its own stacked branch (`milestone-1` to `milestone-6`); nothing is merged to `main` yet.

## The milestone checks

Every check runs headless: `bash tools/run_tests.sh` runs all eight suites (156 checks; about 8 minutes, most of it auto-played batches). The suites also cover behaviour the checkboxes imply but don't name.

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

## Balance: 100 games per strategy (Normal)

`godot --headless --script res://tools/headless_runner.gd -- --games=100 --strategy=all` (11.5 minutes):

| Strategy | Runs won | Survivors alive at the end | Breaches per game | Main losses |
| --- | --- | --- | --- | --- |
| Fortress: police station, barricades, two guards, guns | 93% | 72% | 0.0 | turned 129, left 14, scattered 13 |
| Balanced: stay in the start house, fortify it | 70% | 52% | 1.6 | turned 169, scattered 55, left 38 |
| Hoard water: St. Mary's school and its 5,000 L tank | 67% | 48% | 1.5 | turned 213, scattered 54, left 24 |
| Keep moving: relocate every 4 days | 17% | 12% | 1.6 | turned 168, scattered 153, left 126 |

These numbers measure the auto-player as much as the game. It is a simple rule-based player (`tools/auto_player.gd`); a thoughtful human should do better.

## Difficulty

Three presets in `data/difficulty.json`, chosen on the start screen (or `--difficulty=` on the command line). All three keep the same rules and realism: the power still fails on day 3–6, a bite still turns someone in 24–72 hours. What changes is how big and how hostile the world is. Each preset is a set of multipliers on the Normal numbers:

| Multiplier | Easy | Normal | Hard | What it scales |
| --- | --- | --- | --- | --- |
| infected | 0.85 | 1.0 | 1.15 | outbreak size and growth (5,100 / 6,000 / 6,900 at the start) |
| encounters | 0.85 | 1.0 | 1.15 | chance of meeting infected outside |
| attacks | 0.85 | 1.0 | 1.08 | night attack chance and size (both, so it compounds) |
| looted_by_others | 0.8 | 1.0 | 1.2 | how fast other survivors strip buildings |
| loot | 1.15 | 1.0 | 0.85 | what each building holds at the start |
| start_stores | 1.3 | 1.0 | 0.8 | the group's starting supplies |
| stress | 0.9 | 1.0 | 1.08 | every stress gain |
| disease | 0.85 | 1.0 | 1.15 | wound infection and waterborne illness chances |

Results of 40 auto-played games per cell:

| | Balanced: won / survivors alive | Fortress: won / survivors alive |
| --- | --- | --- |
| Easy | 98% / 81% | 95% / 83% |
| Normal | 68% / 48% | 95% / 71% |
| Hard | 25% / 20% | 78% / 60% |

A first try at Hard (×1.3 on everything) was a wall: 0% for balanced, groups collapsing around day 7. Attack chance and attack size both scale, so 1.3 became 1.69. The table above is the second pass.

## Phase 2, prompt 1: Stabilize (branch `feat/stabilize`)

Built from `prompts/phase2/01-stabilize.md`. All 156 checks pass (`bash tools/run_tests.sh`; the new suite is `tests/test_stabilize.gd`, 28 checks).

### Part A: location attention, and making "keep moving" work

**Attention** is a new system, `systems/attention.gd`. Its numbers are in `data/attention.json`.
- **What builds it.** A site the group lives in accumulates attention from its signals:
  - voices and foot traffic, latrine and rubbish smell
  - cooking smoke, and firelight at night
  - generator noise, and generator light at night
  - hammering, unburied bodies (for 3 days)
  - one-off noises reaching it, such as gunshots and forced doors
- **How it fades.** Half-life is 10 days while people stay and 3 days after they leave. A group arriving at a new site starts it on 25 points: they were seen carrying their loads in.
- **What it does:**
  - **Infected drift.** Each hour, infected in zones within 1 km edge toward the site, in proportion to its attention.
  - **Night attacks.** Their chance scales with `0.4 + attention / 120`. An unknown new site sees about a third of the attacks of an old one, and a site that has drawn 120 points sees about 1.4 times the old rate. Attack size depends only on how many infected are in the zone.
- **What it replaced.** Base "alert" is gone. Continuous noise and light (generator, hammering) now act only through attention. One-off loud noises (gunshots, doors, events) still pull infected from nearby zones instantly, as before.
- **Where it shows.** The Base tab reads "Attention: low / rising / high (n)", with thresholds at 60 and 150.

**Moving** (`data/mobility.json`):
- **Carrying:**
  - on foot, 25 kg per person (×1.3 for a strong back)
  - a handcart (hardware shops, godowns), 150 kg, at 0.8× speed and 30 m of noise
  - a found vehicle (petrol pumps, police station), 600 kg at 4× speed, but 300 m of noise, 0.12 L of fuel per km, and someone with the Driver trait
- **Packing.** Each category gets a share of the load first: 45% food, 30% water, plus medicine, fuel, gear and materials. The rest fills in priority order.
- **The move itself.** The group walks the route exposed to encounters. On arrival it clears its new building for an hour, exposed like a search to anything trapped inside. Each person gains 6 stress for uprooting.
- **Moving in.** Whatever is still inside the new base becomes the group's. Before, a base's own contents were unreachable.
- **Quick barricade.** A new job: 4.8 points an hour from 3 materials, capped at 40% of the building's maximum. That's a quarter of the time and materials of full barricading, for 40% of the protection.
- **Hidden caches.** What can't be carried is hidden at the old site (1 hour by default; quality 0.3 + 0.3 per hour of hiding, up to 0.9). Each day there's a chance others find it: the building's looted rate × 0.3 × (1 − quality). A survivor sent back there digs it out.

**Rule changes found while tuning:**
- **Guards only fire when needed.** They open fire only when an attack could break in without the guns. Before, every attack meant gunshots, gunshots meant attention, and attention brought more attacks.

**The bot.** Its "keep moving" strategy now:
- leaves at dawn once the base panel shows high attention, for a quiet, defensible building it hasn't used in 8 days, within 1.4 km
- hides the surplus and quick-barricades on arrival
- looks for handcarts and, if it has a driver, a vehicle

It reads only what the player sees: zone counts on the map, the attention level, its own memory of where it's been.

### Part B: save and load

The code is in `core/save_game.gd`.
- **Format.** JSON in `user://saves/`:
  - `save_version` (1), difficulty, seed, roster, day, survivors alive, real-world time
  - the RNG state, as text
  - the whole `WorldState` and event log
- **Encoding.** The world uses a small encoder: dictionaries keep their key order, ints, StringNames and vectors are tagged, and floats are stored as their exact 64-bit pattern.
  - Key order matters because systems roll dice while looping over dictionaries.
  - Godot's own JSON writer and its text format both lose float precision or key order, so either would make a reload drift.
- **Autosave** at every dawn, rotating through 3 slots. Ctrl+S quick-saves, Ctrl+L opens the load list, and Esc opens a pause menu (Resume, Save game, Load…, New run…, Quit).
- **The start screen** has Continue (latest save) and Load… (day, difficulty, survivors alive, save time).
- **Determinism check.** A save at day 10, loaded and run to day 20, gives the same state hash as an uninterrupted run, with scripted decisions.
- **Old or damaged saves** give a clear message, never a crash.
- **A bug found here.** An inline-function bus listener kept finished runs' systems alive and listening. In batches, old games were still acting on new ones. Systems now disconnect from the bus when a run is reset, and `listen()` documents that it needs a method, not a lambda.

### Part C: survivor pool with traits

- **The pool.** `data/survivors.json` now has 12 people, one for each job in the brief, each with a background, 3 skills and 1–2 traits.
- **The traits.** `data/traits.json` has 14 traits, each a set of data-driven effects read through `core/traits.gd`:
  - light sleeper
  - heat-acclimatised
  - smoker (cigarettes are now loot, and the group starts with 5 packs)
  - handles gore
  - strong back
  - squeamish
  - night owl
  - steady nerves
  - anxious
  - knows the town
  - frugal cook
  - knows medicines
  - driver (needed for vehicles)
  - builder

  Vegetarian and Can't swim from the brief's examples were left out: there's no meat or flooding yet, so they wouldn't change any decision.
- **Choosing the group.** The start screen picks 5 of the 12, or "Random 5" (seeded), or "Default five" (the original group, used by all tests and balance runs). The headless runner takes `--roster=default|random|id,id,...`.
- **The stranger at the gate** is now whoever from the pool isn't in the group.
- **Stress.** Every stress gain now goes through one function, which applies difficulty and personality together.

### Part D: map as data, and export

- **The map.** The town is hand-authored in `data/town_layout.json`: terrain rectangles, the 50 buildings, landmarks and zone settings. The game paints the grid at load, and `tools/make_town.py` and `data/town.json` are gone. That settles the open question: the map is hand-made, as data.
- **Export presets.** `export_presets.cfg` has presets for Linux and Windows Desktop. They include `data/*.json` and leave out tests, tools, prompts and docs.
- **Export templates aren't installed on this machine,** so no build was made. The export fails cleanly: "No export template found at ~/.local/share/godot/export_templates/4.7.2.stable/". To install them, open the editor (`godot -e`), then Editor → Manage Export Templates → Download and Install (about 1 GB). Then:

  ```
  godot --headless --export-release "Linux" build/linux/SurvivalSim.x86_64
  godot --headless --export-release "Windows Desktop" build/windows/SurvivalSim.exe
  ```

### Balance: before and after (40 games per cell, default five)

| Difficulty | Strategy | Won before → after | Survivors alive before → after | Median first loss day before → after |
| --- | --- | --- | --- | --- |
| Easy | Stay and fortify | 98% → 100% | 81% → 79% | 21.8 → 13.7 |
| Easy | Police fortress | 95% → 100% | 83% → 91% | 21.3 → none |
| Easy | Keep moving | 68% → 100% | 45% → 76% | 12.0 → 14.0 |
| Easy | Hoard water | 98% → 98% | 80% → 73% | 13.2 → 10.4 |
| Normal | Stay and fortify | 68% → 73% | 48% → 52% | 8.0 → 9.8 |
| Normal | Police fortress | 95% → 93% | 71% → 75% | 10.4 → 17.8 |
| Normal | **Keep moving** | **20% → 75%** | 13% → 47% | 10.7 → 10.1 |
| Normal | Hoard water | 53% → 80% | 37% → 49% | 7.0 → 8.8 |
| Hard | Stay and fortify | 25% → 35% | 20% → 21% | 7.0 → 7.8 |
| Hard | Police fortress | 78% → 78% | 60% → 55% | 13.1 → 10.8 |
| Hard | Keep moving | 0% → 20% | 0% → 12% | 7.8 → 6.8 |
| Hard | Hoard water | 20% → 35% | 14% → 19% | 6.0 → 9.2 |

A first loss "day none" means the median run lost nobody.

Hoard water now bases at the inland Government school, not St. Mary's. In the heat the infected gather by the canal beside St. Mary's, and with attention driving attacks that site won only 3% on Normal. A player would see the crowd on the map.

**Random 5 roster, Normal:**

| Strategy | Won | Survivors alive |
| --- | --- | --- |
| Stay and fortify | 48% | 30% |
| Police fortress | 95% | 70% |
| Hoard water | 78% | 48% |
| Keep moving | 58% | 32% |

Random groups are weaker than the default five, which has a nurse, a fighter and two scavengers, but no combination breaks the game.

**Deaths by cause on Normal (all four strategies, 160 games):**

| Cause | Before | After |
| --- | --- | --- |
| Turned | 287 | 235 |
| Left the group | 87 | 116 |
| Group scattered | 119 | 44 |
| Arterial bleed | 7 | 5 |
| Killed when the base was overrun | 6 | 1 |
| Blood loss | 2 | 0 |
| Sepsis | 0 | 0 |

The after figures use hoard water from the inland school.

### Numbers tuned in this prompt, and where they live

| Number | Value | Where |
| --- | --- | --- |
| Attention signals | per source | `data/attention.json` |
| Half-lives | 10 days occupied, 3 days empty | `data/attention.json` |
| Arrival attention | 25 | `data/attention.json` |
| Attack scaling | 0.4 + attention / 120 | `data/attention.json` |
| Infected drift | 0.0004 per hour per 100 attention | `data/attention.json` |
| Carry, handcart, vehicle | see Part A | `data/mobility.json` |
| Quick barricade, caches | see Part A | `data/mobility.json` |
| Stress per move | 6 | `data/mobility.json` |
| Encounter rate | 2.4e-5 → 3.2e-5 | `systems/infected.gd` `ENCOUNTER_K` |
| Packing shares | see Part A | `systems/base.gd` `MOVE_SHARE` |
| Stress from a repelled attack | scaled by how close it came | `systems/base.gd` |
| Starting cigarettes | 5 | `data/scenario.json` |

The bot's keep-moving rules are constants at the top of `tools/auto_player.gd`.

### Not working, not verified, or uncertain

- **No exported build.** The export templates aren't installed.
- **The new menus aren't checked by hand.** The start screen, load list and pause menu were checked by screenshot and headless tests, not clicked through.
- **Keep moving sits at the top of its target** (75%). It's sensitive to the bot's moving rules, which shows how much the outcome depends on judgement.
- **Hard is very hard for mobile groups** (20%), because every move starts with weak quick barricades.
- **The default five's traits made the group stronger,** so the Easy/Normal/Hard multipliers were tuned before traits existed and would deserve a second look.
- **The brief's balance-report rule asks for 1280×720 and 1920×1080 screenshots.** This prompt's screenshots were taken at the game's 1600×900 base size, which scales to any window.

## Phase 2, prompt 2: UI/UX (branch `feat/ui-ux`)

Built from `prompts/phase2/02-ui-ux.md`. The designer's note was playtest log #2: "I can't understand anything." The screenshots are in `docs/screenshots/` at 1280×720 and 1920×1080. They cover Day 1, Day 10 and Day 25, every tab, the planner, the decision, move and alerts windows, the menus, the start and end screens, and every map layer. The new suite `tests/test_ui.gd` has 13 checks.

### The simulation: read-only additions, no balance change

The 240-game batch (20 games per difficulty and strategy) is byte-identical before and after.
- **Causes.** The simulation records causes it used to throw away:
  - stress changes are kept per survivor for 3 days (`stress_causes`), labelled by reason
  - hours slept last night
  - map positions on death, trip, door and story events
- **History.** `systems/history.gd` (registered last) takes a daily snapshot for the charts and keeps a timeline of decisions, losses, moves, attacks and story events. The save is now version 2; version 1 saves migrate.
- **Planned trips.** `command_plan_trip` (Jobs) leaves now, at midday, dusk or night, and loots in the player's priority order.
- **Warnings the group can know about.** The taps sputter 12 h before the mains fail, and the lights flicker 6 h before the power fails. Alerts use only these cues, never the simulation's clocks.
- **Decision options.** Each option carries its consequence text and an irreversible flag, and the decision carries a list of unknowns.
- **Shared formulas.** Temperature by hour, infected activity by minute and encounter chance moved into static functions that the systems and the UI share.

### Parts A–K

- **A, theme.** There is one theme, `ui/theme/main_theme.tres`, generated by `tools/build_theme.gd` from `ui/theme/tokens.gd`.
  - It uses Noto Sans with a 13 px minimum, a spacing scale and type variations (chips, cards, buttons).
  - State is never shown by colour alone: a chip has a word, and a meter adds "!" or "!!".
  - The interface size runs from 80% to 150% in Settings.
- **B, layout.**
  - Top bar: clock, weather, speed, utilities and an alerts button.
  - Map in the centre with a layer bar.
  - Side tabs (Tab hides them): People, Stores, Base, Log, Stats.
  - A three-line ticker at the bottom; click a line to jump to it.
  - Esc menu: save, load, settings, new run.
- **C, survivor cards.** Each card has 4 meters (water, food, sleep, stress) and condition chips. Click a card for the cause breakdowns, injuries and job pickers. The job board takes drag and drop and warns about unwise assignments, such as an exhausted guard, the medic away while someone bleeds, or no one guarding at night.
- **D, breakdowns.** `core/insight.gd` builds `{value, unit, label, contributions, forecast}` from the systems' own constants. Hovering a number shows it. Tests check that the attention and water breakdowns sum to what the simulation does.
- **E, trip planner.**
  - Choose who goes, when to leave, and what to bring back first (drag to reorder).
  - It shows travel and return time, carry kg, noise, and the chance of getting hurt.
  - The estimate steps through the trip tick by tick using the infected system's own encounter, avoid and fight rules. A test checks that departure and return match the simulated trip to within 10 minutes.
- **F, alerts.**
  - Stores show days left with a trend.
  - Alerts come in three tiers (info, caution, urgent) and use only what the group knows: a hidden bite raises nothing.
  - The player chooses which alert types pause the game (Settings or the Alerts panel).
- **G, decisions.**
  - Each option shows what follows and what's unknown; irreversible options are red. No button has focus, so a stray key never picks one.
  - "Decide later" leaves it waiting.
  - The move-base confirmation lists the walk, the carry, what stays behind, attention and stress.
- **H, map.**
  - Hovering a building shows its info; clicking opens its card.
  - One layer at a time, each with a legend.
  - Survivors on trips are drawn with dashed routes.
  - Log events with a position pulse on the map when clicked.
- **I, charts.** The Stats tab has six line charts (water, food, people, stress, infected, attention). The end screen has the same charts, the score breakdown and a decision timeline.
- **J, hints and keys.** Five Day 0–2 hints, each dismissable, or turn them all off. The setting is saved in `user://settings.cfg`. `?` shows every key.
- **K, self-check.** Screenshots at both sizes. The self-check found and fixed these: the empty move dialog, the planner calling every trip "severe", the Log opening on old lines, the tip covering the base, "0.0 h" sleep before the first night, and alerts about people already dead (playtest log #3–#7).

### What still feels cluttered or unverified

- **The People tab is long.** The job board takes the top half and the cards scroll below it. The "Hide job board" toggle helps, but a real playthrough will show whether the cards should come first.
- **Each map zone shows its infected number** (16 labels). That's useful, but it's busy; a "hover only" mode may be better.
- **The planner's risk is per person** and treats a team as independent walkers. The simulation does the same today.
- **Some things the screenshot tool can't show:** drag and drop, hover tooltips and keyboard shortcuts were checked in code and in the headless build test, not by a person using a mouse.
- **The map is square,** so on 16:9 screens the building card sits in the space to its right. A 4:3 window overlaps the card onto the map.

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

## Status

### Done
- All six milestones of Prototype 1, every row of the "Prototype 1 (upgraded)" column of the Fidelity map, and the 12 checks in GAME_DESIGN.md (verified by tests; the designer ticks the boxes).
- Three difficulty levels (Easy, Normal, Hard), a start screen to choose one, and a replayable seed.
- Headless batch balancing with four auto-played strategies; 128 automated checks.

### Remaining before Prototype 1 is truly done
- **A human playthrough.** Nobody has played a full run by hand yet. The spec's "Done means" asks whether a 30-day run takes 45–60 minutes and whether the loop is fun. At 1× a 30-day run is about 36 minutes plus pauses for decisions; only play can answer the fun question.
- **Keep moving is not yet a viable strategy** (17% on Normal), though the spec names it as one that should succeed.
- **Confirm the two provisional answers to the spec's open questions:** the map is hand-laid in a script, and the five survivors are fixed.
- **UI clarity.**
  - Tooltips explaining numbers.
  - Compact survivor cards.
  - Loot priorities and water-source choice.
  - Clearer warnings before the taps fail.
- **Export settings** (add `*.json` to the export filter) if the game is to be built as an executable.
- **Small spec items not modelled:** petrol going stale (after day 30, so outside this run) and generator "charging" (nothing needs charge yet).

### To brainstorm
- **How difficulty should feel.** Is Easy forgiving enough? Should harder levels also hide information (exact infected counts, wound types) rather than only scale numbers?
- **What kills people.** Bites and broken morale dominate. Hunger, disease and heat rarely kill a decent group in 30 days, which matches the spec's timeline (they take over after day 30). Should some of that pressure arrive earlier?
- **Morale.** Survivors can stay "too shaken to work" for days. Ideas:
  - purpose and routine
  - rest days
  - a leader's choices
  - friendships (Prototype 2–3 in the spec)
- **Making a mobile group work.** Handcarts or abandoned vehicles to carry more, quick temporary barricades, caches left behind on purpose.
- **What the player knows.**
  - Exact numbers versus rough estimates (realism rule 7).
  - Infected counts per zone shown exactly versus only through scouting.
- **The roster.** A fixed five, a pick from a pool, or random each run, with traits and relationships.
- **Save and load** for sessions of 45 minutes or more.
- **Prototype 2 scope from the timeline:** days 30–100, the first monsoon, rain catchment, carriers, one rival group, barter.
- **Art and sound direction** once the systems feel right.

## Where to look

- Story of one run: `godot --headless --script res://tools/headless_runner.gd -- --seed=7 --days=30 --strategy=balanced --verbose=1`
- Tuning: constants at the top of each file in `systems/`, plus `data/scenario.json`, `buildings.json`, `loot_tables.json`, `events.json`.
- The town: edit `tools/make_town.py` and run `python3 tools/make_town.py`.
