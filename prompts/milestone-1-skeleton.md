# Handoff: Milestone 1 — Skeleton

Paste this into Claude Code from the project root (the folder containing CLAUDE.md).

---

Read `CLAUDE.md` and `docs/GAME_DESIGN.md` fully before writing any code. Then build **Milestone 1: Skeleton** only. Do not start Milestone 2.

## Context

This is a Godot 4 project using typed GDScript. If there is no `project.godot` yet, create a new Godot 4 project in this folder with a main scene `res://main.tscn`. Assume Godot 4.3 or later.

## What to build

1. **Folder layout** exactly as in `CLAUDE.md`. Empty system files are fine for systems not used yet, each with a one-line comment saying which milestone fills it.

2. **`core/rng.gd`** — autoload `Rng`. Wraps a `RandomNumberGenerator` with one seed per run. Functions: `set_seed(seed: int)`, `randf() -> float`, `randi_range(a: int, b: int) -> int`, `chance(p: float) -> bool`. The seed is printed at run start.

3. **`core/event_bus.gd`** — autoload `EventBus`. One generic signal `event(name: StringName, payload: Dictionary)` plus a helper `emit_event(name, payload := {})`. Keeps an in-memory log of the last 200 events (tick, name, payload) that the UI can read.

4. **`core/world_state.gd`** — autoload `WorldState`. Holds plain data only:
   - `tick: int`, plus derived getters `day() -> int`, `minute_of_day() -> int`, `clock_string() -> String` (e.g. "Day 0 · 06:00"), `phase() -> StringName` (`&"day"` 06:00–18:00, else `&"night"`).
   - Day 0 starts at 06:00, so tick 0 = Day 0 06:00. 144 ticks per day.
   - Empty containers for later milestones: `survivors: Array`, `buildings: Array`, `zones: Array`, `base: Dictionary`, `stores: Dictionary`, `factions: Array` (stays empty in Prototype 1), `region: Dictionary` (stays empty).
   - `reset(seed: int)` that clears everything and sets tick to 0.

5. **`core/data_loader.gd`** — autoload `Data`. Loads every `res://data/*.json` at startup into a dictionary keyed by file stem. Fails loudly (push_error with the file name and parse error line) on bad JSON. Create placeholder files: `items.json`, `buildings.json`, `loot_tables.json`, `survivors.json`, `events.json`, each a valid empty array `[]` except `buildings.json`, which gets the pharmacy example from the spec as its one entry.

6. **`core/tick_loop.gd`** — autoload `TickLoop`.
   - Speeds: paused, 1×, 3×, 10×. At 1×, one tick per 0.5 real seconds (so one in-game day takes 72 seconds). Put that interval in a named constant.
   - Each tick: increment `WorldState.tick`, then call `tick()` on each registered system in a fixed order, then emit `&"tick"` on the bus. Systems register with `TickLoop.register(system)`; order is registration order.
   - Emit `&"day_started"` when a new day begins and `&"phase_changed"` when day/night flips.
   - `auto_pause_on(event_name)` support: if a listed event fires, set speed to paused. (Used later for decisions.)
   - A `run_headless(ticks: int)` function that advances the simulation as fast as possible with no timers, for the headless runner.

7. **`systems/time.gd`** — the first registered system. For now it does nothing in `tick()` except assert the clock is consistent. It exists so the registration pattern is proven.

8. **`ui/controls.gd` + main scene** — a minimal UI: a label showing `WorldState.clock_string()` and phase, four buttons (Pause, 1×, 3×, 10×) with the active one highlighted, and a scrolling event log showing the last 20 bus events with their tick. Keyboard: Space toggles pause, 1/2/3 set speeds.

9. **`tools/headless_runner.gd`** — a script runnable with `godot --headless --script res://tools/headless_runner.gd -- --seed=42 --days=3` that resets the world, runs N days, and prints the final clock string and the number of `day_started` events. No UI nodes are loaded.

10. **`tests/test_milestone_1.gd`** — a headless test script that checks:
    - tick 0 is "Day 0 · 06:00" and phase day
    - tick 72 is "Day 0 · 18:00" and phase night
    - tick 144 is "Day 1 · 06:00"
    - running 3 days headless emits exactly 3 `day_started` events (for days 1, 2, 3)
    - the same seed produces the same sequence of 10 `Rng.randf()` values twice
    - a test event emitted on the bus appears in the event log
    Print PASS/FAIL per check and exit with a non-zero code on any failure.

## Done when

- The main scene runs, the clock advances from Day 0 06:00, shows day/night, and all speed controls work.
- A test event fires on the bus and appears in the on-screen log.
- `tests/test_milestone_1.gd` passes headless.
- The headless runner prints correct results for `--days=3`.
- No file in `core/` or `systems/` references anything in `ui/`.

## Report back with

- The files you created.
- The exact commands to run the game, the tests and the headless runner.
- Test output.
- Any spec ambiguity you resolved and how.
- Anything not working or not verified. Don't round this off.
