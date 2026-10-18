# Handoff 05: Prototype 2 — Day 30 to Day 100

**Run this only after prompts 1–4 are merged and the designer has confirmed the 30-day game is fun.**

Read `CLAUDE.md`, all of `docs/GAME_DESIGN.md` (especially World timeline → Scarcity, Environment, Society and economy, Mutation) and `docs/IMPLEMENTATION_NOTES.md`. Branch `feat/prototype-2` from `main`.

Prototype 2 extends the game through the **Scarcity** phase: easy loot is gone, the infected start dying off, the first monsoon arrives, and other people become the real problem. Make a plan first and split the work into the parts below; each part should leave the game runnable and tested.

## Part A — Calendar and climate

- Make the outbreak start date data-driven. Default: 15 April, so summer heat dominates the first weeks and the monsoon arrives around day 50 (early June onset for a fictional South Indian district).
- **Add `data/climate.json`** with monthly tables: mean max/min temperature, humidity, rain-day probability, rain amount distribution, wind. Use realistic South Indian values. Note your sources in `IMPLEMENTATION_NOTES.md`.
- **Daily weather** is generated from those tables with the seeded RNG. Heat waves and monsoon breaks emerge from the data, not scripts.
- **Spoilage** rate depends on temperature and humidity: food spoils much faster in monsoon humidity.
- The game length options become 30 days (Prototype 1 mode) or 100 days.

## Part B — Water through the monsoon

- **Rain catchment:** roof area × rainfall (1 mm on 1 m² = 1 litre) into tanks with real capacities. Add a first-flush diverter as a buildable item (dirty first rain carries more contamination). Building gutters and tanks takes materials and skill.
- **Wells:** digging takes days, knowledge (Farmer or Construction background helps) and tools. Well water quality depends on distance from latrines.
- **Floods:** low-lying tiles flood in heavy rain weeks. Roads get cut (travel time changes), and stores on ground floors get damaged unless moved up. Use the renderer's water-level hook from prompt 3.

## Part C — Disease in the wet season

- **Malaria and dengue:** risk from standing water near the base (drains, containers, flood pools). Nets and clearing water reduce it. Fever cycles and lost work days; deadly without care.
- **Cholera and typhoid:** from contaminated water sources, spreading through shared water. Outbreaks inside the group are possible.
- **Scurvy** shows up now if vitamin C stayed low (tracked since prompt 4).

## Part D — Infected populations and natural-selection mutation

- Infected continue dying off from hunger, wounds, heat and floods (monsoon floods drown and scatter them).
- **Mutation by selection, not scripts:** each zone's infected population carries a distribution of traits: heat tolerance, noise made, aggression, stamina.
  - Deaths are weighted by traits: noisy ones find less food, heat-intolerant ones die in heat waves, and so on.
  - Infected don't reproduce. The distribution shifts only through who survives.
  - Newly turned humans enter with baseline traits.
- So by Day 60–100 the surviving infected are measurably tougher and quieter: the "Survivors" stage and the start of "Hunters" from the spec. Expose trait averages to `PlayerKnowledge` only through observation ("they seem quieter near the canal").
- Add a debug/headless report of trait distributions over time.

## Part E — One simulated rival group

- **The Market Gang** (or a camp remnant, chosen from data) is simulated off-screen each day: population, food days, water days, weapons, morale, leader, goal.
- **Behaviours** emerge from those numbers: scavenge (they compete for the same buildings, which replaces part of the abstract looted rate), trade, demand tribute, raid when hungry, recruit, split if morale collapses.
- **Diplomacy:** trade, tribute, alliance, hostility, plus a reputation value that remembers broken deals.
- **Raids** are resolved realistically: attackers weigh your defense, your apparent wealth (attention again) and their hunger.
- Add a hook for more groups later (`factions: Array` already exists).

## Part F — Barter economy

- No money. Item values come from scarcity, season and need: water is cheap in monsoon and precious in May, antibiotics are always precious, salt and seeds rise over time.
- A **trade screen** shows offered and wanted items, the group's estimate of a fair rate, and trust. Price memory: they remember what you paid last time.

## Part G — Growing the settlement

- **Recruiting** up to 15 people from events (lone survivors, families). Carriers among them per prompt 4.
- **Rooms and zones** inside the base: sleeping, kitchen, store, clinic, latrine. Crowding effects from prompt 4 apply.
- **Gardens:** planting windows by season; realistic growth times (leafy greens about 30–45 days, others longer); need water, seeds and protection from animals (abstract monkeys/goats for now).
- **Cooking and production:** drying and salting food for preservation, ORS, simple medicine kits.

## Part H — Win, saves and balance

- **New 100-day win condition:** survive to Day 100 with a settlement stability score (people alive, food and water security, morale, relations). Keep the 30-day mode working.
- **Bump `SAVE_VERSION`** and migrate Prototype 1 saves, or refuse them clearly.
- **Balance:** 40 games per difficulty per strategy for both modes. Add one new strategy: "trader" (allies and trades with the rival group).
- Report deaths by cause across the whole 100 days; it should show the timeline shift from infected to hunger and disease.

## Done when

- Every part works with tests.
- 30-day mode results are unchanged within noise.
- 100-day mode is completable on all difficulties by a sensible strategy.
- The deaths-by-cause curve shifts over time as the World timeline says it should.

## Report back with

- What changed, by part.
- Balance tables for both modes.
- Deaths by cause per 10-day block.
- Mutation trait drift charts (data is fine).
- The rival group's typical story in 3 seeds (one paragraph each).
- Anything unrealistic you compromised on.
- Anything not working.
