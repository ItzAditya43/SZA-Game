# Survival Sim — project guide for Claude Code

A realistic, strategic zombie/mutant apocalypse survival simulation set in a fictional South Indian district town. Built in Godot 4 with GDScript. The world is the main character: systems keep running whether or not the player looks.

## Read these first

- `docs/GAME_DESIGN.md` — the full design spec and the single source of truth. Every number, rule and milestone is there.
- `docs/world-scrubber.html` — an interactive reference mock showing how the world changes from Day 0 to Day 1000. It is a visual reference only, not code to port. Open it in a browser if you need to see the intended feel; read its data arrays if you need example values.

## Current goal

Prototype 1: one town, 4–6 survivors, survive 30 in-game days. Art-free (coloured tiles, text panels). Built milestone by milestone, in the order in `GAME_DESIGN.md` → "Build milestones". Do not start a milestone until the previous one's checks pass.

## Hard rules

1. **Scope.** Only build what the current milestone asks for. Anything in the "Later" column of the scope table, or in the "Prototype 2–3" / "Early access" columns of the Fidelity map, is out. If something would be easy to add, leave a `# LATER:` comment instead.
2. **Simulation never touches UI.** Code in `core/` and `systems/` must not reference any Node in `ui/`, call `get_tree()` for UI, or print to on-screen labels. The UI reads `WorldState` and listens to `EventBus`. This keeps headless runs possible.
3. **Systems never call each other.** They read and write `WorldState` and emit/listen on `EventBus`. No `systems/a.gd` calling a function in `systems/b.gd`.
4. **Data, not code.** Buildings, loot tables, items, survivors and events live in `res://data/*.json`. Never hard-code content lists in GDScript.
5. **Real units.** Store water in litres, food in kcal, fuel in litres, distance in metres, time in ticks (1 tick = 10 in-game minutes). UI bars are derived views.
6. **Seeded randomness.** All randomness goes through `core/rng.gd` with one seed per run. Never call `randi()`/`randf()` directly.
7. **Tunable numbers.** Every balance number from the spec goes into a data file or a clearly named constant at the top of the system, never buried inline.
8. **Typed GDScript.** Use static types (`var x: int`, `func f(a: float) -> void`) everywhere.

## Folder layout

```
res://
  data/     buildings.json, loot_tables.json, items.json, survivors.json, events.json
            + town.json (from tools/make_town.py), scenario.json (start state, timings)
  core/     tick_loop.gd, world_state.gd, event_bus.gd, data_loader.gd, rng.gd
            + sim_run.gd (starts a run), sim_system.gd (system base class),
              stores.gd, body.gd, geo.gd, decisions.gd (plain-data helpers any system may use)
  systems/  time.gd, survivors.gd, jobs.gd, town.gd, resources.gd,
            infrastructure.gd, infected.gd, base.gd, events.gd, + outcome.gd
  ui/       map_grid.gd, survivor_panel.gd, building_panel.gd, controls.gd
            + hud.gd, event_log.gd, base_panel.gd, decision_panel.gd, end_screen.gd, ui_state.gd
  tools/    headless_runner.gd (+ headless_run.gd), auto_player.gd, screenshot.tscn,
            make_town.py, run_tests.sh
  tests/    test_milestone_N.gd (entry) + milestone_N_checks.gd, checks_base.gd
```

Run every test with `bash tools/run_tests.sh`. Scripts started with `--script` must not name autoloads directly (they are compiled first): keep them as thin wrappers that `load()` the real code. Player orders reach the simulation only as `command_*` / `decision_made` bus events. See docs/IMPLEMENTATION_NOTES.md for every design call made in Prototype 1.

## How to finish a milestone

1. Implement only that milestone.
2. Make every checkbox under it in `GAME_DESIGN.md` verifiable, with a test script in `tests/` or a headless run where possible.
3. Report back: what was built, how each check was verified, any spec ambiguity you resolved and how, and anything left unresolved. Be honest about what is not working.
4. Do not tick the checkboxes in `GAME_DESIGN.md` yourself; the designer does that after checking.

## When the spec is unclear

Follow the seven Realism rules in `GAME_DESIGN.md`. If it is still unclear, pick the simplest option that keeps the architecture rules intact, note it in your report, and move on. Ask only if the choice would be expensive to undo.
