# Handoff 01: Stabilize — keep moving, saves, survivor pool, export

Read `CLAUDE.md` (including the rules added after Prototype 1), `docs/GAME_DESIGN.md` and `docs/IMPLEMENTATION_NOTES.md` before writing code.

Create branch `feat/stabilize` from the current difficulty branch (it isn't merged into `main` yet). All 128 existing checks must keep passing. Add new tests for everything below.

## Part A — Location attention model (fixes "keep moving")

**Problem:** the "keep moving" strategy wins 17% of runs on Normal. The spec says it should be one of at least three viable strategies. Don't fix this by nerfing the other strategies or by special-casing the bot. Fix the missing realism.

**Realistic cause:** a group that stays in one place builds up signals: generator and hammering noise, cooking smoke and smell, light at night, latrine and rubbish smell, foot traffic. The infected (and later, other people) home in on that. Moving resets it, at a cost.

Build `systems/attention.gd`:

1. **Attention per site.** Every building/tile cluster the group uses has an `attention` value. Each tick, add attention from the signals the group makes there. Noise uses the spec's distances: generator ~150 m, hammering ~80 m, gunshot ~600 m, talking ~15 m. Light at night (fire, lamp, generator light) counts unless blackout is set up. Smell comes from cooking, unburied bodies, the latrine and rubbish. Every source's weights go in `data/attention.json`.
2. **Decay.** Attention decays over time, with a half-life of about 3 days when nobody is there and much slower while people remain. Tune it, but keep it in data.
3. **Effects.** Infected drift toward high-attention sites from nearby zones, and the night-attack chance and size scale with the base's attention. This should replace or feed the existing noise-attraction logic, not run alongside it as a second system.
4. **Show it.** Expose attention in `WorldState` so the UI can show it later (prompt 2 adds the overlay). For now, a single "Attention: low / rising / high" line in the base panel is enough.

**Make moving a real option with real costs:**

- **Carry capacity:** on foot about 20–25 kg per person, a handcart about 150 kg (found at hardware shops or godowns, slow, a little noisy), a found vehicle much more but loud and fuel-hungry. All figures go in data.
- **The move itself** takes time and exposes the group: an encounter risk based on route zones and time of day. Night moves are quieter but more dangerous.
- **The new site** starts with zero fortification. Add a **quick barricade** job: about a quarter of the time and materials of a normal barricade, giving about 40% of the defense. Data-driven.
- **Hidden caches:** the group can leave supplies hidden at a site. Each day there's a chance other survivors find them, using the existing looted-rate concept scaled down, and modified by how well it's hidden (time spent hiding it).
- **Update the bot's "keep moving" strategy** so it plays sensibly: move when attention gets high, carry the essentials, cache the surplus, quick-barricade on arrival, move at dawn or dusk. It must use only information the player would have.

**Target (Normal, 40 games):** keep moving wins 55–75% of runs. Stay-and-fortify and police-station fortress should stay roughly where they are (±10 points). Report the full table for all three difficulties and all three strategies, plus how attention changed the other two strategies.

## Part B — Save and load

- Save to `user://saves/` as JSON with `save_version`, difficulty, seed, the full `WorldState`, the RNG state, and the event log.
- Autosave at every in-game dawn, keeping 3 rotating autosave slots, plus manual saves from a pause menu. Use Ctrl+S for quick save and Ctrl+L to open the load list.
- The start screen gets a "Continue" button (latest save) and a "Load" list showing day, difficulty, survivors alive and real-world save time.
- **Determinism test:** with the same seed and the same scripted decisions, save at day 10, load, and run to day 20. The result must match an uninterrupted run to day 20. Compare a hash of the serialized state.
- Unknown or older `save_version` values: show a clear message, never crash.

## Part C — Survivor pool with traits

- `data/survivors.json` becomes a pool of 12 survivors from a South Indian town. Each has a name, age, pre-outbreak job (nurse, electrician, mechanic, farmer, school teacher, cook, police constable, pharmacist, auto-rickshaw driver, college student, construction worker, retired soldier), 3 skills, and 1–2 traits.
- **Traits must be realistic and must change decisions, not just stats.** Put the effects in data. Examples (pick or improve on these):
  - "Light sleeper": +2 h sleep needed in noisy bases, wakes others to threats sooner.
  - "Heat-acclimatised": less water need and heat-illness risk above 35 °C.
  - "Smoker": stress rises without cigarettes; cigarettes are now a loot item and barter good.
  - "Vegetarian": won't eat meat; morale drops if forced.
  - "Handles gore": less stress from bodies and wounds.
  - "Can't swim": serious risk in floods (matters more in Prototype 2).
  - "Strong back": +30% carry capacity.
  - "Squeamish": can't do treatment jobs well.
- **Start screen:** pick 5 from the pool with a short card per survivor, or press "Random 5". A "Default" preset keeps the current five, so the existing tests and balance runs stay reproducible.
- Balance runs keep using the Default preset, plus one extra run on Normal with Random 5 to check that no trait combination breaks the game.

## Part D — Map as data, and export

- If the town layout lives in a script, move it to `data/town_layout.json` (data, not code). Keep it hand-authored. That settles the open question in the design doc; note the decision in `IMPLEMENTATION_NOTES.md`.
- Fix the settings issue blocking export. Add `export_presets.cfg` for Windows Desktop and Linux, and document the export commands in `IMPLEMENTATION_NOTES.md`. Export a Linux build headlessly as a smoke test if export templates are installed. If they aren't, say so and give the install step.

## Done when

- All old and new tests pass.
- The balance table shows keep moving at 55–75% on Normal without breaking the others.
- A save at day 10 reloads identically.
- The start screen shows difficulty, seed, survivor selection, Continue and Load.
- An export preset exists and the steps are documented.

## Report back with

- What changed, by part.
- The full balance table, before and after.
- Deaths by cause, before and after.
- Every number you tuned, and where it lives.
- Anything not working, not verified, or that you're unsure is realistic.
