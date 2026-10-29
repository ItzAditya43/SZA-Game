# Survival Sim: game guide

What the game is, how it plays, the numbers behind it, and the commands to run it.

This is a reference. It describes what's in the build now (branch `feat/neutral-setting`). The design intent and future plans are in [GAME_DESIGN.md](GAME_DESIGN.md). Every design call and balance result is in [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md). If a number here disagrees with `data/*.json`, the data file is right.

## Contents

1. [Running the game](#1-running-the-game)
2. [The game in brief](#2-the-game-in-brief)
3. [The town](#3-the-town)
4. [The survivors](#4-the-survivors)
5. [Bodies and minds](#5-bodies-and-minds)
6. [Bites and the infected](#6-bites-and-the-infected)
7. [Jobs](#7-jobs)
8. [Scavenging](#8-scavenging)
9. [Supplies](#9-supplies)
10. [The base: defense, attention, moving](#10-the-base-defense-attention-moving)
11. [The town falls apart](#11-the-town-falls-apart)
12. [Events and decisions](#12-events-and-decisions)
13. [Winning, losing and score](#13-winning-losing-and-score)
14. [Difficulty](#14-difficulty)
15. [How a run tends to go](#15-how-a-run-tends-to-go)
16. [The screen](#16-the-screen)
17. [For developers](#17-for-developers)

---

## 1. Running the game

You need Godot 4.3 or later; the game is built and tested on 4.7.2. Run every command from the project folder. On a fresh clone, run `godot --headless --import` once first.

### Play

| What | Command |
| --- | --- |
| Play (start screen: difficulty, survivors, seed, Continue, Load) | `godot` |
| Start a run straight away | `godot -- --difficulty=normal --seed=42` |
| …with five random survivors | `godot -- --difficulty=hard --seed=42 --roster=random` |
| …with a chosen five (survivor ids, see section 4) | `godot -- --difficulty=easy --roster=nurse,mechanic,officer,chef,veteran` |
| Open the project in the Godot editor | `godot -e` |

- **`--difficulty`:** `easy`, `normal` or `hard`.
- **`--seed`:** any whole number. The same seed always gives the same town names, the same people's names and the same run, as long as you make the same choices.
- **Saves:** written to `~/.local/share/godot/app_userdata/Survival Sim/saves/` on Linux. The game autosaves at every dawn and keeps the last 3 autosaves. Settings (interface size, alerts that pause, hints) are in `settings.cfg` in the folder above.

### Test and measure

| What | Command |
| --- | --- |
| Every test suite | `bash tools/run_tests.sh` |
| One suite | `godot --headless --script res://tests/test_ui.gd` |
| One run with no UI, told as a story | `godot --headless --script res://tools/headless_runner.gd -- --difficulty=normal --seed=7 --days=30 --strategy=balanced --verbose=1` |
| Balance batch (auto-player) | `godot --headless --script res://tools/headless_runner.gd -- --games=40 --difficulty=all --strategy=all` |

- **Test suites:** `test_milestone_1`…`6`, `test_difficulty`, `test_stabilize` and `test_ui`.
- **Strategies:** `balanced`, `fortress`, `hoard_water`, `keep_moving` or `all`.
- **Balance batch timing:** 20 games per cell takes about 10 minutes, and 40 per cell about 20.

### Screenshots

Use `godot res://tools/screenshot.tscn -- [options] --out=/path/shot.png`.

| Option | Meaning |
| --- | --- |
| *(no `--difficulty`)* | Shows the start screen |
| `--difficulty=normal --seed=5 --hours=30` | Starts a run and fast-forwards 30 in-game hours (30 h is Day 1 at 12:00) |
| `--size=1280x720` / `--size=1920x1080` | Renders as a window of that size would (the default is 1600×900) |
| `--tab=0..4` | Side tab: People, Stores, Base, Log, Stats |
| `--select=grocery_02` | Selects a building on the map |
| `--open=planner\|alerts\|shortcuts\|move\|end` | Opens that window |
| `--menu=pause\|load\|settings` | Opens that menu |
| `--overlay=noise\|light\|smell\|attention\|disease` | Map layer |
| `--decide-later=1` / `--hints=0` | Puts waiting decisions aside / hides the tip card |
| `--zoom=3` | Zooms in on the base |
| `--rain=1` | Shows rain (visual only) |
| `--generator=1` | Gives the group a running generator (for night shots) |
| `--quality=low\|medium\|high` | Graphics preset for this shot only |

### Graphics and audio tools

| What | Command |
| --- | --- |
| Frames per second for each graphics preset (night, generator, rain, 3× speed, zoomed in) | `godot res://tools/fps_bench.tscn -- --size=1920x1080` |
| Re-cut a new sprite sheet into `assets/sprites/` | `python3 tools/slice_sheet.py assets/source/sheet_v1.png assets/sprites` then `godot --headless --import` |
| Regenerate every sound | `python3 tools/make_sounds.py` |

---

## 2. The game in brief

A realistic, strategic zombie survival simulation. The infected are **sick living people**, not the undead. You lead a group of five survivors in a small town after an outbreak, and you win by keeping anyone alive in the group until **06:00 on Day 30**.

You don't walk anyone around. You:
- give each person a day job and a night job
- choose where to scavenge and when
- set the base's standing orders (rations, boiling water, generator, firearms)
- make the hard calls: bites, antibiotics, strangers at the gate

The world keeps running on its own whether you look or not:
- the outbreak spreads
- other survivors (never seen) strip the shops
- the power and water fail
- the heat climbs

Everything is in **real units**: water in litres, food in kcal, fuel in litres, distance in metres, time in 10-minute ticks.

---

## 3. The town

- **Size:** about 2 km × 2 km, drawn as 64 × 64 tiles of 31.25 m and split into 16 zones (4 × 4) of 500 m. Each zone tracks how many infected are in it.
- **Landmarks:** the market, the bus station, the highway (east–west), the main road (north–south, bridging the canal), the canal, and fields to the south.
- **Names:** the town's name and every building's name are rolled from the seed, from mixed pools in `data/names.json` ("Corner Shop (Bridge Street)", "Okafor house", "Ashford General Hospital"…). The layout is the same every run; only the names change.
- **Climate:** a hot, dry season. The run starts on 15 April. Daily highs climb from 37 °C to 40 °C over the month and lows from 26 °C to 28 °C. The hottest hour is about 14:30 and the coolest about 05:30. Heat waves add +3 °C for 4 days.

### Buildings

| Type | Count | Danger inside | Base defense | Roof tank | Lost to other looters each day | Main loot |
| --- | --- | --- | --- | --- | --- | --- |
| House | 30 | low (0.15) | 10 | 1,000 L | 2% | rice, lentils, flour, a little medicine, cigarettes |
| Grocery store | 6 | medium (0.40) | 12 | – | 8% | packaged food, bottled water, rehydration salts, cigarettes |
| Pharmacy | 2 | high (0.70) | 15 | – | 15% | antibiotics, bandages, painkillers, rehydration salts |
| Fuel station | 2 | medium (0.40) | 8 | – | 10% | fuel, snacks |
| Hardware shop | 2 | low (0.15) | 15 | – | 3% | materials, tools, water drums |
| School | 2 | medium (0.40) | 25 | 5,000 L | | materials (benches), kitchen stores |
| Hospital | 1 | very high (0.95) | 30 | 10,000 L | | large medical stock |
| Police station | 1 | high (0.60) | 50 | 2,000 L | | weapons, ammunition, strong walls |
| Water tower | 2 | low (0.10) | 5 | 50,000 L | | water |
| Factory or warehouse | 2 | medium (0.40) | 20 | 3,000 L | | materials, bulk food |

- Loot is **finite**. What other survivors take is gone, so waiting costs you.
- Many doors are locked. Forcing one makes noise that carries about 50 m.

---

## 4. The survivors

A pool of 12 people. You pick 5 on the start screen, take the **Default five**, or press **Random 5**. Each person has a profession, an age, three skills from 1 to 10 (scavenging, medicine, combat), one or two traits and a short background. **Their names are rolled from the seed each run.**

| Id | Profession | Age | Scav | Med | Combat | Traits | Default five |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `nurse` | Nurse | 34 | 4 | 8 | 3 | Handles gore, Light sleeper | ✔ |
| `electrician` | Electrician | 29 | 6 | 2 | 5 | Strong back | ✔ |
| `mechanic` | Mechanic | 41 | 7 | 1 | 6 | Smoker, Knows the town | ✔ |
| `farmer` | Farmer | 46 | 5 | 3 | 4 | Heat-acclimatised | ✔ |
| `officer` | Police officer | 38 | 4 | 2 | 8 | Steady nerves, Night owl | ✔ |
| `teacher` | School teacher | 27 | 5 | 4 | 3 | Anxious, Knows the town | |
| `chef` | Cook | 52 | 3 | 2 | 3 | Frugal cook, Heat-acclimatised | |
| `pharmacist` | Pharmacist | 31 | 4 | 6 | 2 | Knows medicines, Squeamish | |
| `cabbie` | Taxi driver | 44 | 6 | 1 | 4 | Driver, Smoker | |
| `student` | College student | 20 | 6 | 3 | 3 | Night owl, Anxious | |
| `builder` | Construction worker | 35 | 5 | 1 | 5 | Strong back, Builder | |
| `veteran` | Retired soldier | 61 | 3 | 4 | 9 | Steady nerves, Light sleeper | |

### Traits

| Trait | Effect |
| --- | --- |
| Light sleeper | Needs 2 h more sleep in a noisy base, but adds +6 base defense (wakes everyone at the first scrape) |
| Heat-acclimatised | Needs less extra water in the heat (×0.6) and heats up more slowly |
| Smoker | A pack a day; without cigarettes, +8 stress a day |
| Handles gore | Half the stress from deaths and wounds |
| Strong back | Carries 30% more on trips and moves |
| Squeamish | Treats wounds as if 3 medicine points lower; own wounds stress them ×1.5 |
| Night owl | Works 20% better on the night shift, 10% worse by day |
| Steady nerves | Stress from fights ×0.6 |
| Anxious | Every stress gain ×1.25 |
| Knows the town | Travels 15% faster and finds a little more |
| Frugal cook | 40% less cooking fuel, 30% faster cooking |
| Knows medicines | Finds 50% more medicine; better odds of saving a septic patient |
| Driver | The only one who can drive a found vehicle |
| Builder | Barricades go up 40% faster |

---

## 5. Bodies and minds

Each person's body is simulated in real units. The survivor card shows four meters (water, food, sleep, stress). Hover a meter to see what makes it up.

### Water and food
- **Water:** each person needs 3–6 L a day. The amount rises with heat, hard work and illness.
  - 3 L behind: thirsty
  - 6 L behind: confused
  - 9 L behind: collapses
- **Food:** about 1,900–2,400 kcal a day, depending on body weight and work.
  - 4,000 kcal short: hungry
  - 12,000 kcal short: weak
  - 25,000 kcal short: starving

### Sleep and heat
- **Sleep:** each person needs about 7 h. A sleep debt of 6 h or more brings mistakes and accidents. Night-shift workers sleep by day.
- **Heat:** body temperature rises with hard work in the sun. Above 38.5 °C is heat exhaustion. Working outdoors at midday is risky for your own people.

### Wounds
- **Types:** cuts, deep wounds, fractures and bites.
- **Bleeding:** wounds bleed in litres per hour. Blood loss below 70% of normal collapses a person, and below 60% kills them. Arterial bleeds need a tourniquet fast.
- **Infection chain:** an untreated wound can go red and swell, then bring fever, then sepsis. Sepsis kills within days without antibiotics.
- **Treatment:** a medic on the Treat job cleans, stitches and bandages wounds.
- **Infection is not certain.** An untreated cut usually heals; a deep wound is a real risk.

### Illness
Dysentery or cholera comes from drinking untreated water, a ~30% chance per day. Rehydration salts cut the fluid loss.

### Stress (0–100)
- **Raised by:**
  - deaths and wounds
  - fights and attacks
  - hunger and thirst
  - smokers going without cigarettes
  - bad news
  - moving base
- **Eased by:** rest, hot meals and painkillers.
- **At 80** a person refuses jobs. **At 95** they may leave the group.

---

## 6. Bites and the infected

### A bite
- Carries the pathogen. There is no cure. The person turns in **24–72 hours**, depending on where the bite is.
- People **sometimes hide a bite**. It shows as a "cut" until a fever starts; after that they turn within hours.
- When the group knows, you decide:
  - **Quarantine them:** locked away safely; they can't work.
  - **Keep working and watch for fever:** they stay useful, at a risk.
  - **Send them away:** irreversible.
  - **End it before they turn:** irreversible.
- Someone who turns inside the base hurts people before they're put down.

### The infected
- **Numbers:** the outbreak starts at about 6,000 and grows by 1,200 a day until Day 5. It starts thick at the hospital, the bus station and the market.
- **From Day 15** each zone loses about 2% a day: the infected starve and their wounds rot.
- **Activity:**
  - lowest in the midday heat (12:00–16:00)
  - higher at dawn and dusk
  - highest at night
- **Noise pulls them in:**

  | Source | Reach |
  | --- | --- |
  | Gunshot | about 600 m |
  | Generator | about 150 m |
  | Hammering | about 80 m |
  | Forcing a door | about 50 m |
  | Walking voices | about 15 m |
  | Quiet searching | about 10 m |

- **Encounter outcomes:** slipped past, fought off, injured, bitten or killed.
- **What decides an encounter:**
  - how many infected are in the zone, and how many are met at once
  - day or night
  - the survivor's scavenging skill (stealth) and combat skill
  - their weapon (a machete helps; a rifle helps a lot but is loud)
  - their existing wounds

---

## 7. Jobs

Everyone has a **day job (06:00–18:00) and a night job (18:00–06:00)**. Set them on the People tab: drag a name to a job, or use the pickers on a card.

| Job | What it does |
| --- | --- |
| **Rest** | Sleep and recover. |
| **Scavenge** | Walk to a building, search for about 2 h, carry back up to 25 kg. Risk of meeting infected. |
| **Guard** | +10 defense, +2 per combat point. Most important at night. |
| **Fortify** | Turns materials into barricades (+defense). Noisy. |
| **Quick barricade** | Fast, weaker barricades for a new base (up to 40% of the building's maximum). |
| **Collect water** | Fills containers from a roof tank, water tower or the canal. It needs boiling. |
| **Cook** | Turns raw rice, lentils and flour into meals, using cooking gas or firewood. Hot meals ease stress. |
| **Treat the hurt** | Bandaging, stitching, painkillers, rehydration salts, antibiotics. Medicine skill matters. |

The job board warns about unwise assignments, such as an exhausted guard, nobody treating someone who's bleeding, or no one on guard at night.

---

## 8. Scavenging

- **Walking speed** is about 1.8 km/h out and 1.4 km/h back (loaded). It's slower when hurt, hungry or exhausted.
- **A search takes about 2 h** and finds 35% of what's there, plus 7% per scavenging point, up to 90%.
- **Night trips are worse:** infected are more active, searching takes 1.5× as long and finds 70% as much.
- **Carrying:** 25 kg on foot (+30% with a strong back). A handcart carries 150 kg; a vehicle 600 kg but is loud.
- **The trip planner** (click a building, then "Plan a scavenging trip"):
  - choose who goes and when to leave: now, midday (12:00), dusk (17:30) or night (20:00)
  - set what to bring back first
  - it shows the return time, carry limit, noise and the **chance of getting hurt**, all worked out with the simulation's own rules
- **Midday is the safest time to be out**, but it's the hottest, so it's hard on your own people's bodies.

---

## 9. Supplies

| Supply | Notes |
| --- | --- |
| Bottled water | Safe; keeps forever |
| Tap water | Free while the mains run, then gone |
| Tank, tower and canal water | Must be **boiled** (fuel) or carries a ~30% daily chance of illness |
| Rice, lentils, flour | Keep for months; must be **cooked** |
| Packaged food | Keeps for months to years; eaten as is |
| Fresh produce | Spoils in 3–5 days without a fridge |
| Cooked meals | Last about a day |
| Antibiotics | The scarce lifeline: they clear wound infection and fever, and sometimes sepsis |
| Bandages, painkillers, rehydration salts, tourniquets | Treating wounds, pain and illness |
| Fuel (gasoline/diesel) | For the generator and a vehicle |
| Cooking gas | For cooking; materials can burn as firewood instead |
| Materials | For barricades and repairs |
| Cigarettes | Keep smokers calm |
| Generator, handcart, vehicle, water drums | Gear. A water drum holds 200 L. |
| Machetes, rifles, ammunition | Weapons |

**Starting stores** (Normal):
- 46 L bottled water
- 12,000 kcal packaged food and 4,000 kcal fresh produce
- 10,000 kcal rice and 5,000 kcal lentils
- 12 L fuel and 6 kg cooking gas
- 4 bandages, 2 painkillers, 2 rehydration salts
- 6 materials and 5 packs of cigarettes

**Standing orders** (Base tab):

| Order | Choices |
| --- | --- |
| Food ration | full (3,000 kcal), reduced (2,000), half (1,500), minimal (800) |
| Water ration | as needed, 4 L, 3 L, 2 L, 1 L |
| Boil water | yes or no |
| Generator | off, evenings, all night: light and a working fridge, for 1 L of fuel an hour, at the cost of noise and light |
| Firearms | hold fire (quiet) or shoot (wins fights; draws infected from 600 m) |

---

## 10. The base: defense, attention, moving

### Defense
Defense adds up from:
- the building (police station 50, school 25, hospital 30, house 10…)
- barricades (up to the building's maximum)
- guards (+10 each, +2 per combat point)
- weapons (rifle +10, machete +3)
- light sleepers (+6)
- everyone else awake at base (+2 each)

### Night attacks
- Infected near the base may attack at night. The chance rises with:
  - infected numbers in the zone
  - the base's **attention**
- The attack's strength is about 3.5 per infected.
- If it beats your defense, they **break in**: people get hurt or killed (worse if asleep).
- Barricades wear with every attack.

### Attention
A place the group lives in gets noticed. Attention builds per hour from:
- people (voices, foot traffic)
- waste
- cooking smoke and, at night, firelight
- hammering
- the generator's noise and light
- unburied bodies (for 3 days)

Its effect on attacks:
- Attacks scale with 0.4 + attention ÷ 120, so a well-known site is attacked several times as often as a new one.
- Attention halves every **10 days** while you stay, and every **3 days** once you leave.

### Moving the base
Click a building, then "Move base here". The confirmation window lists the consequences.
- Everyone walks there carrying what they can: 25 kg each on foot, more with a handcart or vehicle.
- Whatever won't fit can be hidden in a **cache** to collect later. Other survivors may find it.
- Barricades stay behind; the new place starts with only its own building defense.
- Moving costs everyone 6 stress, and arriving is seen and heard.
- Whatever is left inside the new building becomes yours.

---

## 11. The town falls apart

| When | What fails | Warning |
| --- | --- | --- |
| Day 2 | Phones and internet | – |
| Day 3–6 | **Power.** Fridges stop, so fresh food spoils. A generator still works. | Lights flicker about 6 h before |
| Day 7–12 | **Water mains.** After this, water only comes from bottles, tanks, the towers or the canal. | Taps sputter about 12 h before: fill every container |

---

## 12. Events and decisions

Twelve hand-written events, each with a cause in the world:

| Event | When | What happens |
| --- | --- | --- |
| Lockdown | Day 0, 07:00 | Radio orders everyone indoors; checkpoints go up |
| Panic buying | Day 0, 11:00 | Grocery stores lose 40% of their stock |
| Gunshots at the bus station | Day 1, 19:00 | A 600 m noise pulls infected toward the centre |
| Pharmacy raided | Day 2–5 night (35%/day) | One pharmacy loses half its stock; gunshots |
| Relief camp | Day 3 | A camp opens at a school with food, water and medicine |
| Camp overrun | Day 8–10 (if the camp opened) | It falls; 400 infected there, supplies left behind |
| Checkpoint abandoned | Day 10–12 | Rifle and ammunition left at the police station |
| The radio goes silent | Day 12–14 | Nobody is coming; stress for everyone |
| A stranger at the gate | Day 4–20, if the group has 5 or fewer | Someone from the pool asks to join. They may be hiding a bite. |
| Market fire | Day 6–28, on hot days | Burns market buildings' loot; kills some infected |
| Heat wave | Day 16–26 | +3 °C for 4 days |
| Summer storm | Day 18–29 | 25 mm of rain fills roof tanks and open containers |

**Decision windows** list for each option:
- what the group knows will follow
- what nobody can know yet
- irreversible options, marked in red and never pre-selected

"Decide later" leaves a decision waiting in Alerts.

---

## 13. Winning, losing and score

- **Win:** anyone still in the group at 06:00 on Day 30.
- **Lose:** everyone is dead, turned or gone, or everyone's morale breaks and the group scatters.
- **Score:** 100 per person alive, plus 10 per day on full rations, plus points for supplies stored.
- **The end screen** shows the score breakdown, everyone's fate, charts of the run and a timeline of decisions, losses, moves and attacks.

---

## 14. Difficulty

The same rules at every level; the size and hostility of the world change.

| Multiplier | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Infected (outbreak size and growth) | 0.85 | 1.0 | 1.15 |
| Encounters outside | 0.85 | 1.0 | 1.15 |
| Night attacks (chance and size) | 0.85 | 1.0 | 1.08 |
| Looting by others | 0.8 | 1.0 | 1.2 |
| Loot in buildings | 1.15 | 1.0 | 0.85 |
| Starting stores | 1.3 | 1.0 | 0.8 |
| Stress gains | 0.9 | 1.0 | 1.08 |
| Disease (wound infection, bad water) | 0.85 | 1.0 | 1.15 |

**How the automated player does on Normal** (it is a simple rule-based bot; a thoughtful player should beat it):

| Strategy | Win rate |
| --- | --- |
| Fortress (police station, two guards) | about 95% |
| Keep moving | about 75% |
| Stay in the start house and fortify | about 70% |
| Hoard water at a school with a big tank | about 70–80% |

On Hard these drop sharply.

---

## 15. How a run tends to go

1. **Days 0–5, the grab:**
   - Shelves are full and the infected are still multiplying.
   - Get the pharmacy before it's raided, and get water containers ready.
   - Midday trips are the safest.
2. **Days 3–12, the failures:**
   - The power goes, then the taps. Water becomes the main problem.
   - Boiling needs fuel.
   - Attacks grow as attention builds.
3. **Days 10–20, the slow costs:**
   - Untreated wounds turn septic, stress piles up, and smokers run out.
   - Attention at the base peaks: harden the base or move.
4. **Days 15–30, the long tail:**
   - The infected start dying off, but stores are thin.
   - Hunger, disease and morale kill more people than the infected do.

---

## 16. The screen

- **Top bar:**
  - day and clock; date, temperature, phase and difficulty
  - speed: Pause, 1× (a day in 72 s), 3×, 10×
  - power, taps and phones status
  - **Alerts** (red when urgent; click for the list and auto-pause choices)
  - `?` for keys, Panel to hide the side panel, Menu
- **Map:**
  - drawn from the sprite sheet, lit by the time of day (cool dawn, harsh noon, golden dusk, dark night)
  - lamps, cooking fires and the generator glow at night and are blocked by buildings, which shows why lights draw attention
  - rain, heat shimmer, smoke from fires, weeds creeping over roads as the days pass
  - buildings show their state: boarded, forced open, burned, a tarp on a base that has been broken into
  - the infected are dots clustered per zone, leaning towards a base that has drawn attention
  - the fog of knowledge: dark where nobody has been, grey where it was seen a while ago, clear near the base and anyone out
  - **scroll to zoom, drag (any mouse button) or WASD to move**; zoomed far out it shows simple blocks and zone tints
  - click a building for its card: what's inside, danger, last visit, plan a trip, move base
  - layer bar: infected, noise, light at night, smell and wind, attention, disease risk, plain map, each with a legend
  - survivors out on trips show as dots with dashed routes
- **Side tabs:**
  - **People:** the job board and a card per survivor
  - **Stores:** days left for water, food, gas and medicine, with trends
  - **Base:** defense, attention and standing orders
  - **Log:** filters for danger, supplies and town; click a line to see it on the map
  - **Stats:** daily charts
- **Ticker:** the last three events; click one to see where it happened.
- **Hover any number** to see what it's made of and where it's heading.

### Keys

| Key | Action |
| --- | --- |
| Space | pause / resume |
| W A S D | move the map (scroll to zoom) |
| 1 / 2 / 3 | 1×, 3×, 10× |
| Tab | side panel |
| Esc | menu (save, load, settings, new run) |
| Ctrl+S | quick save |
| Ctrl+L | load |
| ? | all keys |

**Settings** (Esc → Settings), in four tabs:
- **General:** interface size, 80–150%; show the first-day hints again
- **Alerts:** which alerts pause the game
- **Graphics:** quality Low / Medium / High, or each of lights, shadows, particles and screen effects on its own; Reduce motion
- **Audio:** volumes for master, music (none yet), ambience, sound effects and interface

**Sound:**
- ambience changes with day, night, rain and midday heat, and is muffled while paused or deciding
- distant gunshots are louder the nearer they are to the base
- forced doors, night attacks and hammering at the base
- the generator hums while it runs, and fires crackle louder as the camera nears them
- alert chimes by tier, and clicks

---

## 17. For developers

**Layout:** see [CLAUDE.md](../CLAUDE.md).
- `data/`: all content (JSON)
- `core/`: autoloads and plain-data helpers
- `systems/`: the simulation, one system per file
- `ui/`: the screen
- `tools/`: the runner, auto-player and screenshot tool
- `tests/`: one suite per milestone or prompt

**Rules the code keeps:**
- the simulation never touches the UI
- systems talk only through `WorldState` and the `EventBus`
- content is data
- units are real
- all randomness is seeded through `core/rng.gd`

**Names:** `core/names.gd` rolls the town, the 12-person pool and every building from `data/names.json`.
- It uses `Rng.stream(seed, "names")`, a separate random stream, so names never change an outcome. The balance batch is identical with or without them.
- Names are stored in `WorldState.names` and saved with the run.
- Event text can use `{town}` or a building id such as `{school_01}`.

**Saves:** JSON in `user://saves/`, versioned.
- Version 3 (this branch) changed ids: survivors are `nurse`, `mechanic`…; items `lentils`, `flour`, `rehydration_salts`; building types `grocery`, `fuel_station`.
- Older saves are refused with a clear message.

**Branches** (none merged to `main`):

| Branch | What it adds |
| --- | --- |
| `feat/stabilize` | Phase 2 prompt 1: attention, moving, saves, survivor pool |
| `feat/ui-ux` | Prompt 2: the new UI |
| `feat/neutral-setting` | Neutral setting with names rolled per run |

**Bugs and playtest notes** go in [PLAYTEST_LOG.md](PLAYTEST_LOG.md).
