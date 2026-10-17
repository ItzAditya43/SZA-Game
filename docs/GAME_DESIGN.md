# Prototype 1: Survival Sim Build Spec

Design spec for a realistic, strategic zombie/mutant apocalypse survival sim. Source of truth for all implementation work.

## What we're building now

Prototype 1 is a playable, art-free simulation: one small town, one group of 5 survivors, survive 30 in-game days after the outbreak. It proves two things before any art or story gets built: the core loop (scavenge → survive → fortify) is fun, and the systems affect each other in believable ways.

- **Engine:** Godot 4 with GDScript (Python-like syntax, free, light). Everything built here carries over into the full game.
- **Look:** top-down tile grid. Coloured squares, icons and text panels only. No models, no animation.
- **Setting:** a fictional small Indian district town, roughly 2 km × 2 km, shown as a 64 × 64 tile map. Real building types, real infrastructure, realistic failure timing.
- **Player role:** group leader. You assign jobs, choose where to scavenge, decide rationing and who gets medicine. You don't control a single character directly.
- **Effort:** roughly 70–90 hours of focused work with the realism upgrades (see Fidelity map), so about 8–10 weeks part-time.
- **Who builds what:** the designer sets the rules and tunes the numbers; Claude Code writes most of the GDScript from this spec, one milestone at a time.

## Scope: in now vs later

Anything not in the "Now" column is out of Prototype 1, however tempting. The architecture leaves hooks for it, nothing more.

| Feature | Prototype 1 (now) | Later |
| --- | --- | --- |
| Map | One town, 64 × 64 tiles, hand-made in a data file | Multiple towns, region map, procedural layout |
| Survivors | One group of 5, named, with stats and 3 skills | Recruiting, families, relationships, traits |
| Time | 30 days, 10-minute ticks, day/night | Day 100+, seasons, monsoon and summer heat |
| Resources | Water, food, medicine, fuel, materials | Ammo crafting, trade goods, farming, livestock |
| Infrastructure | Power and water mains fail on a timer | Repairable grid, wells, solar, radio network |
| Infected | Zone populations, noise attraction, slow die-off | Mutation and evolution, special late-stage forms |
| Base | One chosen building, barricades, defense score | Multiple zones, walls, rooms, production chains |
| Other humans | None (only an abstract "looted" rate) | Factions with goals, raids, trade, diplomacy |
| Off-screen world | Not simulated | Abstract simulation of the whole region |
| Events | ~12 small hand-written events | Large event deck, story arcs |
| Combat | Auto-resolved by numbers, no tactics screen | Tactical encounters, stealth |
| Art and audio | None | Asset packs, sound design |

## Systems spec

Eight systems, each a separate module. All numbers below are starting values to tune by playtesting, not final. Where the Fidelity map section lists a Prototype 1 upgrade, the upgrade replaces the simpler version here.

### 1. Time

- 1 tick = 10 in-game minutes, so 144 ticks per day. Day 0 starts at 06:00.
- Phases: day 06:00–18:00, night 18:00–06:00. Night halves visibility and doubles the risk of moving outside.
- Speed controls: pause, 1×, 3×, 10×. The game auto-pauses on any event that needs a decision.

### 2. Survivors

Each survivor has needs and condition stats from 0 to 100, plus three skills from 1 to 10.

| Stat | Rises or falls by | Effect at the bad end |
| --- | --- | --- |
| Thirst | +33 per day without water | At 100: health −20 per day, death in about 3 days |
| Hunger | +10 per day without food | Above 70: work speed −30%; at 100: health −5 per day |
| Fatigue | +5 per working hour, −12 per hour of sleep | Above 80: injury chance ×2, skill checks −2 |
| Health | Falls from injuries, illness, starvation | At 0: death |
| Morale | Events, food quality, deaths, safety | Below 20: refuses jobs; below 5: may leave the group |

- **Skills:** Scavenging (loot found, noise made), Medicine (treatment success), Combat (survival when infected are met).
- **Injuries:** cut, deep wound, fracture, bite. Untreated cuts and wounds roll for infection each day (cut 5%, wound 20%). Infected wounds cost health every day until antibiotics are used. Fractures halve work speed for 30 days.
- **Bites:** a bite carries the pathogen. Incubation 24–72 hours, then the survivor turns. There is no cure in Prototype 1, so the player must decide what to do with them.

### 3. Jobs

Each survivor gets one job per shift (day shift, night shift).

- **Scavenge:** go to a chosen building. Returns loot after 2–6 hours depending on distance. Risk of meeting infected.
- **Guard:** raises base defense. Without a guard, night attacks are much more dangerous.
- **Fortify:** turns materials into barricades (+defense).
- **Collect water:** from rain tanks or the canal; the water needs boiling (fuel) or it risks illness.
- **Cook / treat / rest:** cooking turns raw food into meals (+morale), treating uses Medicine skill and supplies, resting recovers fatigue and health.

### 4. Town and loot

The town has about 60 buildings of 10 types. Each type has a loot table, and every building's loot is finite.

| Building type | Count | Main loot | Danger |
| --- | --- | --- | --- |
| House | 30 | Rice, dal, utensils, a little medicine | Low |
| Kirana store | 6 | Packaged food, bottled water, matches | Medium |
| Pharmacy | 2 | Antibiotics, bandages, painkillers | High (looted early) |
| Petrol pump | 2 | Fuel, a few snacks | Medium |
| Hardware shop | 2 | Tools, wire, sheets, nails | Low |
| School | 2 | Space, benches (materials), a water tank | Medium |
| Hospital | 1 | Large medical stock | Very high |
| Police station | 1 | Rare weapons and ammo, strong walls | High |
| Water tank tower | 2 | Thousands of litres of water until it empties | Low |
| Factory or godown | 2 | Materials, bulk food sacks | Medium |

- **Looted rate:** other survivors are not simulated, so every building loses a share of its loot per day (pharmacies 15%, stores 8%, houses 2%). This makes waiting costly.

### 5. Resources and spoilage

- **Water:** bottled water keeps forever. Tank and canal water must be boiled (1 unit of fuel per 10 litres) or carries a 30% chance of illness per day of drinking.
- **Food:** fresh food spoils in 3–5 days, cooked meals in 1 day, rice and dal keep for months, packaged food for months to years.
- **Medicine:** bandages, antibiotics, painkillers. Antibiotics are the scarce lifeline.
- **Fuel:** petrol and diesel for a generator or cooking. Petrol starts degrading after about 30 days.
- **Materials:** generic units for barricades and repairs.

### 6. Infrastructure collapse

- **Power:** fails at random between day 3 and day 6. After that, a generator gives light and charging, at the cost of fuel and noise.
- **Water mains:** pressure fails between day 7 and day 12. After that, water comes only from tanks, rain or the canal.
- **Phones and internet:** down from day 2. This only matters for the event text and atmosphere in Prototype 1.

### 7. Infected

The infected are sick living people, not undead. That is what makes the world change over 30 days.

- **Populations:** the map is split into 16 zones (4 × 4). Each zone holds an infected count, starting high near the hospital, market and bus stand.
- **Noise attraction:** noise events pull infected from nearby zones. Gunshot reaches about 600 m, a generator about 150 m, breaking a door about 50 m, quiet searching about 10 m.
- **Activity:** less active in the midday heat (12:00–16:00), most active at night. This gives the player a reason to scavenge at the hottest time.
- **Die-off:** the infected don't eat well or treat wounds. From day 15, each zone loses about 2% of its infected per day. By day 30 the town is noticeably emptier.
- **Encounters:** resolved by numbers using zone density, noise made, time of day and Combat skill. Outcomes: avoided, fought off, injured, bitten, or killed.

### 8. Base and events

- **Base:** at the start, pick one building as your base. Each building type has a base defense value (house 10, school 25, police station 50) plus barricades.
- **Attacks:** each night, nearby infected may attack. The chance rises with noise from the base and falls with defense and guards.
- **Events:** about 12 hand-written events, triggered by conditions. Examples: a stranger asks to join, heavy rain refills the tanks, a fire spreads in the market, a survivor hides a bite, someone gets sick from bad water.

### Win and lose

- **Win:** at least one survivor is alive and the group hasn't broken up on day 30.
- **Lose:** everyone is dead, or all morale is below 5 and the group scatters.
- **Score:** survivors alive, days with full rations, supplies stored. This makes balancing measurable.

## Realism rules

Every system in the game, from Prototype 1 to release, follows these seven rules. When a design choice is unclear, these decide it.

1. **Real units, not abstract bars.** Water is litres, food is kilocalories, fuel is litres, distance is metres, time is minutes. Bars in the UI are views of real quantities.
2. **Nothing is magic.** The infected are sick living humans. Medicine works only if the right drug meets the right condition. Walls hold only as long as their material does.
3. **Everything decays.** Food spoils by temperature and humidity, fuel goes stale, batteries drain, wounds worsen, buildings rot in the monsoon, knowledge is lost when the person who has it dies.
4. **Causes before effects.** No random disasters from nowhere. A fire starts from a candle, a cooking stove or lightning. Cholera starts from a contaminated water source. The player can always trace why.
5. **The world runs without you.** Other survivors, the infected, animals and weather all keep acting off-screen.
6. **Time is the real enemy.** Early on, the infected kill people. Later, hunger, disease, weather and other humans kill far more.
7. **Realism serves decisions.** If a realistic detail never forces a choice, it stays in the simulation but out of the player's face. No chores for the sake of realism.

## World timeline

Hunger, disease and people overtake the infected as the main threat over time.

| Phase | Days | What happens | Main threat | Built in |
| --- | --- | --- | --- | --- |
| Collapse | 0–7 | Outbreak spreads, lockdowns, panic buying; hospitals overrun, power and phones still on; checkpoints and first relief camps | Infected, panic | Prototype 1 |
| Breakdown | 7–30 | Power fails day 3–6, water mains day 7–12; broadcasts stop, camps fall, shops looted; groups form at schools and police stations | Infected, injuries | Prototype 1 |
| Scarcity | 30–100 | Easy loot gone, infected start dying off; first monsoon brings floods, cholera, malaria; groups trade, raid and fight over food | Hunger, disease | Prototype 2–3 |
| Adaptation | 100–365 | Farming, rain catchment, real bases; first mutation stages appear; summer heat and fights over water | Other people | Early access |
| Rebuilding | 365–1000+ | Settlements, laws, leaders, trade routes; a mutated ecosystem the world adapts to; children born after the outbreak | Politics, mutation | Full game |

Each later stage of development extends the simulation one phase further, so the game grows along the same timeline the world does.

## The body

Each survivor is a small physiology model, not a set of bars. Figures are real-world baselines to start from, then tuned for play.

### Energy and water

- **Calories:** about 2,000 kcal/day at rest, 3,000–3,500 kcal for heavy work like hauling or building walls. A deficit draws on body fat first, then muscle (strength and work speed drop).
- **Water:** about 3 litres/day to drink, up to 6 litres in 40 °C heat or hard labour, plus 2–5 litres for cooking and washing. Under 1 litre/day: confusion within 2 days, death in about 3–4.
- **Nutrition:** a rice-only diet keeps people alive but not healthy. No vitamin C for 4–8 weeks leads to scurvy (bleeding gums, slow healing). No protein slows recovery from injuries.

### Injuries

Every wound has a location, a bleed rate and a contamination level.

| Injury | What happens untreated | Treatment |
| --- | --- | --- |
| Cut | Small bleed, infection chance rises daily | Clean water, bandage |
| Deep laceration | Bleeds about 0.1–0.5 L/hour; collapse after losing about 1.5 L | Pressure, stitches, antibiotics |
| Arterial bleed | Death in minutes | Tourniquet within 2–3 minutes, then a skilled medic |
| Fracture | Can't walk or work on that limb for 6–8 weeks; open fractures get infected | Splint, rest, antibiotics if open |
| Burn | Fluid loss and high infection risk | Cool water, clean dressings |
| Bite (infected) | Pathogen exposure plus wound infection | No cure; quarantine and watch |

- **Infection chain:** contaminated wound → local infection (2–3 days) → fever → sepsis (death in days without antibiotics). This chain makes clean water and antibiotics the most valuable things in the world.
- **Pain and shock:** severe pain lowers work speed and aim; painkillers help but are finite.

### Disease

- **Waterborne:** cholera, typhoid and dysentery from unboiled water or bad sanitation. Severe diarrhoea can kill through dehydration in 1–2 days; oral rehydration salts save lives.
- **Vector-borne:** malaria and dengue rise sharply in the monsoon when stagnant water breeds mosquitoes. Nets and clearing standing water matter.
- **Crowding:** respiratory infections and skin infections spread faster in packed, unwashed shelters.
- **Sanitation:** no latrine or one too close to the water source means outbreaks. Rubbish piles attract rats and dogs.

### Heat, cold and sleep

- **Body temperature:** heavy work in 42 °C summer heat causes heat exhaustion, then heatstroke. Shade, water and working at dawn or dusk are real strategies.
- **Cold and wet:** rare in most of India, but monsoon soaking plus no dry shelter causes illness and lowers morale.
- **Sleep:** under 5 hours a night stacks up a sleep debt. After 2–3 bad nights, mistakes, accidents and bad decisions rise.

### The mind

- **Stress** comes from danger, hunger, loss, noise at night and seeing the infected up close.
- **Trauma:** killing an infected person who used to be human, or losing family, can leave a lasting effect: nightmares, panic in combat, refusing certain jobs.
- **Relief:** safety, routine, decent food, rest days, friendship and purpose bring stress down. A survivor with nothing to do gets worse, not better.
- **Breakdowns:** high stress can lead to hoarding, fights, running away, or freezing in danger.

## The pathogen

The outbreak is a fictional neurological pathogen built from real disease behaviour: rabies-like transmission and aggression, prion-like brain damage, and fungal-like adaptation over time. It is never fully explained, but it is always consistent.

### Transmission

- **Bite:** the main route. Risk depends on depth and location; a bite to the neck or face progresses faster than one to the hand.
- **Blood and fluids:** infected blood in an open wound or the eyes can transmit. Melee fighting without protection carries risk; this is why gloves, goggles and spears matter.
- **Not airborne** at the start. A later mutation could change that, which is one of the biggest late-game threats.
- **Carriers:** a small share of people (around 1–2%) carry the pathogen without turning for weeks. They can't be spotted without testing equipment, which creates paranoia and hard choices.

### Progression in a person

1. **Incubation (1–3 days, longer for limb bites):** looks normal, maybe a mild fever. This is when people hide bites.
2. **Prodrome (6–12 hours):** fever, sweating, sensitivity to light and sound, irritability.
3. **Turning:** loss of higher brain function, extreme aggression, a strong drive to bite. The body is still alive.

### Infected biology

The infected are living bodies running on damage, so they follow physical rules:

- They need water and food. Without it they weaken and die over weeks, so populations fall after the first month.
- They don't treat wounds. Infections, broken bones and blood loss kill many of them.
- They overheat in 40 °C+ summer days and slow down. They are more active at dawn, dusk and night.
- Senses: hearing and smell are sharp, eyesight is poor. Light at night draws them from far away.
- They cluster around noise and the smell of blood or food, forming hordes.
- Monsoon flooding drowns and scatters them; heat waves kill weakened ones.

### Mutation (Early access onward)

Mutation follows natural selection, not sudden monsters. Slow, believable changes appear in the infected who survive longest:

| Stage | Rough timing | Change | Why it appears |
| --- | --- | --- | --- |
| Survivors | Day 30–100 | Tougher, more heat-tolerant infected | The weak have died off |
| Hunters | Day 100–250 | Quieter, ambush near water and food | Noisy infected starve |
| Sleepers | Day 150+ | Dormant in buildings, wake to noise | Saves energy when food is scarce |
| Packs | Day 250+ | Move in loose groups | Groups find food more often |
| Airborne strain | Rare, late | Spread by close breathing in enclosed spaces | Rare mutation the world must adapt to |

Players learn about new stages from observation, notes and other survivors, never from a pop-up encyclopedia.

## Environment

The setting is a fictional district in South India, so the climate drives the year. Each season changes what is dangerous and what is possible.

| Season | Months | Conditions | What changes in play |
| --- | --- | --- | --- |
| Summer | Mar–May | 35–44 °C, dry, heat waves | Water need doubles, infected slow at midday, fires spread fast, tanks run dry |
| Monsoon | Jun–Sep | Heavy rain, flooding, humidity | Rain refills tanks, roads flood, food spoils faster, malaria and dengue rise, buildings leak |
| Post-monsoon | Oct–Nov | Warm, cyclones possible | Best planting window, storms can wreck walls |
| Winter | Dec–Feb | 15–28 °C, dry, cool nights | Easiest season to work and scavenge, harvest time |

### Weather and disasters

- **Rain:** a real rain model fills tanks by roof area (1 mm on 1 m² = 1 litre). A 100 m² roof in a 20 mm storm collects about 2,000 litres.
- **Floods:** low-lying tiles flood in heavy monsoon weeks, cutting roads and drowning stored food on ground floors.
- **Fire:** spreads by wind, dry material and building type. Thatch and shops full of goods burn fast; concrete houses resist. Market fires in summer can burn whole blocks.
- **Lightning and cyclones:** rare, but damaging to walls, roofs and generators.

### Animals

- **Stray dogs:** packs grow as people disappear. Dangerous at night, rabies risk, but can be befriended as guards.
- **Monkeys:** steal food from poorly sealed stores.
- **Snakes:** more common in monsoon and around overgrown buildings; a cobra or krait bite needs antivenom, which only hospitals stock.
- **Rats:** follow rubbish and stored grain; spread disease and eat stockpiles.
- **Livestock:** abandoned cows, goats and chickens can be caught and kept for milk, eggs and meat.

### Sound, light and smell

These three signals decide what finds you.

- **Sound** travels by distance and is blocked by walls. Gunshot about 600 m (1–2 km in open quiet ground), generator about 150 m, vehicle engine about 300 m, hammering about 80 m, talking about 15 m. Rain masks sound.
- **Light** at night is visible far away: a fire or electric light can be seen for over a kilometre in a dark town. Blackout curtains become a resource.
- **Smell** from cooking, blood, bodies and rubbish spreads downwind. Wind direction matters for where you cook and where you bury the dead.

### The decaying town

- Grass and weeds take over roads in months; trees crack walls in years.
- Unmaintained buildings leak and rot after one or two monsoons; some collapse.
- Abandoned vehicles block roads, which makes routes and travel time change over the game.

## Society and economy

Other people are the long-term story. They follow the same needs as your survivors, so their choices make sense.

### Authority collapse

- **Day 0–3:** police and district administration impose lockdowns and checkpoints. Hospitals overflow. Radio and TV give official instructions.
- **Day 3–10:** evacuation convoys and relief camps form at schools and stadiums. Some are overrun, leaving supplies, vehicles and weapons behind.
- **Day 10–30:** official broadcasts thin out, then stop. Abandoned checkpoints become loot sites; camps become the first large survivor groups.
- **Later:** occasional radio signals, a rumoured safe zone, a supply drop that may or may not be real. Hope is a resource too.

### Survivor groups and factions

Each group is simulated with a population, food and water days, weapons, morale, a leader and a goal. Groups grow, split, merge, trade and raid based on those numbers, not a script.

| Group type | Typical origin | Behaviour |
| --- | --- | --- |
| Family clusters | Neighbours who stayed | Defensive, trade small goods, want safety |
| Camp remnants | Failed relief camps | Large, organised, short of food |
| Armed group | Police or security remnants | Controls weapons, demands tribute, enforces order |
| Raiders | Desperate or opportunistic | Raid weak groups, especially in hungry months |
| Religious or community group | Temple, mosque, church or community hall | Strong morale and cohesion, cautious with outsiders |
| Lone survivors | Anyone | Can be recruited, can carry knowledge, can be carriers |

### Inside your settlement

- **Roles and fairness:** people compare their workload and rations. Unequal rationing raises tension even if it is efficient.
- **Leadership:** decisions cost or earn legitimacy. A leader who exiles a sick child loses it; one who keeps everyone fed gains it.
- **Crime:** theft from stores, hidden bites, fights, desertion. Rules and punishments are player choices with consequences.
- **Relationships:** friendships, couples and rivalries affect morale, who works well together, and who leaves with whom.
- **Births and children:** later in the game, children need care and protection but are the settlement's future.

### Barter economy

- Money is worthless within weeks. Value comes from scarcity: antibiotics, clean water, fuel, salt, ammunition, seeds and batteries become currencies.
- Each item's value changes with supply and season. Water is cheap in the monsoon and precious in May; medicine is precious always.
- Trade needs trust. Traders travel with risk, and a broken deal changes how a group treats you.

### Knowledge and skills

- Skills come from real jobs before the outbreak: nurse, electrician, farmer, mechanic, teacher, cook, police constable.
- Knowledge can be taught, written down or found in books. A settlement that loses its only doctor loses that capability until someone learns.
- Long-term projects need knowledge: repairing a solar panel, digging a well, purifying water at scale, building a clinic.

## Fidelity map

Hyper-realism is the target for the full game. Prototype 1 takes the realistic parts that are cheap to code and decide whether the game is fun; the rest waits. The Systems spec above is the minimum; these upgrades replace its simpler versions.

| Area | Prototype 1 (upgraded) | Prototype 2–3 | Early access and full game |
| --- | --- | --- | --- |
| Food and water | kcal and litres, spoilage by temperature, boiling | Vitamin and protein deficits, rain catchment by roof area | Farming, livestock, preservation (drying, salting) |
| Injuries | Bleed rate, tourniquet, infection chain to sepsis | Fractures, burns, pain and shock | Surgery, prosthetics, long-term disability |
| Disease | Waterborne illness from unboiled water | Sanitation, latrines, crowding | Malaria and dengue, epidemics between groups |
| Heat and sleep | Heat exhaustion, sleep debt | Heatstroke, wet and cold exposure | Full climate year |
| Mind | Stress from danger, hunger and loss | Trauma, breakdowns, relationships | Leadership legitimacy, faith and culture |
| Pathogen | Bite, incubation, hidden bites, prodrome | Blood transmission, carriers | Mutation stages, airborne strain |
| Infected | Need water, overheat, die off, sound and light attraction | Smell and wind, hordes | Ecosystem of mutated forms |
| Environment | Day and night, summer heat | Monsoon, floods, fire spread | Animals, cyclones, building decay over years |
| Society | Authority-collapse timeline as events and loot sites | One rival group, barter | Many factions, trade routes, crime and law |

The upgraded Prototype 1 adds roughly 20–25 hours to the original estimate, so plan for about 70–90 hours in total.

## Architecture

```
 [Tick loop]                                   [Data files (JSON)]
 runs each system in order                     buildings, loot, items, events
      |                                                 | loaded at start
      | every tick                                      v
      |                      +-----------------------------------+
      |                      |           WORLD STATE             |
      |                      | survivors, town, zones, base, clock|
      |                      +-----------------------------------+
      |                                  ^  | read / write
      v                                  |  v
 +--------------------------------------------------------------------+
 | SYSTEMS (each reads and writes the world state)                    |
 |  Time | Survivors | Jobs | Town and loot                           |
 |  Resources | Infrastructure | Infected and noise | Base and events |
 +--------------------------------------------------------------------+
                                  ^  | publish / listen
                                  |  v
 +--------------------------------------------------------------------+
 | EVENT BUS: power_failed, bite_received, pharmacy_looted, ...       |
 +--------------------------------------------------------------------+
            |                                        |
            v                                        v
 [UI: map grid, side panels, controls]    [Headless runner: 100 games, prints stats]
```

Systems never call each other directly. They change the world state and announce what happened on the event bus, so later systems (factions, mutation, off-screen world) plug in without rewriting old ones. The UI only reads the world state and listens to events.

### Rules that keep it expandable

- **Data, not code:** buildings, loot tables, items, survivors and events live in JSON. Adding content means adding data.
- **Seeded randomness:** every run uses one random seed, so any bug or strange run can be replayed exactly.
- **Headless first:** simulation code never touches UI nodes, so the same game can run 100 times in seconds for balancing.
- **Hooks for later:** the world state already has an empty factions list and a region object, so off-screen simulation can be added without restructuring.

### Folder layout

```
res://
  data/     buildings.json, loot_tables.json, items.json, survivors.json, events.json
  core/     tick_loop.gd, world_state.gd, event_bus.gd, data_loader.gd, rng.gd
  systems/  time.gd, survivors.gd, jobs.gd, town.gd, resources.gd,
            infrastructure.gd, infected.gd, base.gd, events.gd
  ui/       map_grid.gd, survivor_panel.gd, building_panel.gd, controls.gd
  tools/    headless_runner.gd
```

### Example data entry

```json
{
  "id": "pharmacy",
  "count": 2,
  "danger": 0.7,
  "daily_looted_rate": 0.15,
  "base_defense": 15,
  "loot": [
    { "item": "antibiotics", "min": 2, "max": 6 },
    { "item": "bandages",    "min": 5, "max": 15 },
    { "item": "painkillers", "min": 3, "max": 10 }
  ]
}
```

## Build milestones

Six milestones, each ending in something you can run and check. Each one is a separate handoff to Claude Code, and none starts until the one before it works.

1. **Skeleton (about 6 h):** Godot project, folder layout, tick loop with pause and speed controls, event bus, data loader that reads JSON.
   - [ ] Clock runs from Day 0 06:00 and shows day, time and phase
   - [ ] A test event fires on the bus and is logged
2. **Survivors and needs (about 10 h):** 5 survivors loaded from data, needs decaying per tick, death from thirst, a side panel showing stats.
   - [ ] With no water, a survivor dies on about day 3
   - [ ] Fatigue and sleep cycle work over a full day
3. **Town, loot and scavenging (about 12 h):** 64 × 64 grid, 60 buildings from a data file, loot tables, the daily looted rate, the scavenge job with travel time.
   - [ ] Click a building to see its type and remaining loot
   - [ ] Pharmacy loot visibly drains over the first week
4. **Infected, noise and encounters (about 12 h):** 16 zone populations, noise events pulling infected between zones, heat and night activity, encounter rolls, injuries and bites.
   - [ ] A gunshot shifts infected counts in nearby zones
   - [ ] A bitten survivor turns within 24–72 hours
5. **Base, jobs and infrastructure (about 12 h):** base selection, barricades, guard and fortify jobs, night attacks, power and water failure timers, spoilage, boiling water.
   - [ ] Power fails between day 3 and 6 in every run
   - [ ] An unguarded base with no barricades falls to a night attack
6. **Events, win/lose and balance (about 10 h):** the 12 events, end screen with score, and a headless mode that runs 100 games and prints average survival.
   - [ ] A full 30-day run is completable
   - [ ] The batch run shows survival is neither near 0% nor near 100%

### Done means

Prototype 1 is done when a full 30-day run takes about 45–60 minutes of play, at least three different strategies can succeed (police station fortress, keep moving, hoard water), and the town on day 30 feels clearly different from day 1.

### Open questions

- [ ] Town map: draw it by hand in a spreadsheet, or generate it from simple rules?
- [ ] Does the player pick the 5 survivors, or are they random each run?
