# Survival Sim — Prototype 1

A realistic, strategic zombie/mutant apocalypse survival simulation set in a fictional South Indian district town, built in Godot 4 (typed GDScript). One town, five survivors, thirty days after the outbreak. Art-free: coloured tiles and text panels.

The design lives in [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md). What was built, every design call made along the way and the balance results are in [docs/IMPLEMENTATION_NOTES.md](docs/IMPLEMENTATION_NOTES.md).

## Run it

Needs Godot 4.3 or later (built and tested on 4.7.2). From this folder:

| What | Command |
| --- | --- |
| Play | `godot` (opens on the start screen: pick Easy, Normal or Hard) |
| Play straight into a run | `godot -- --difficulty=hard --seed=42` |
| Open in the editor | `godot -e` |
| All tests | `bash tools/run_tests.sh` |
| One test suite | `godot --headless --script res://tests/test_milestone_4.gd` |
| One headless run, told as a story | `godot --headless --script res://tools/headless_runner.gd -- --difficulty=normal --seed=7 --days=30 --strategy=balanced --verbose=1` |
| Balance batch (100 games per strategy and difficulty) | `godot --headless --script res://tools/headless_runner.gd -- --games=100 --difficulty=all --strategy=all` |
| Screenshot of the game screen | `godot res://tools/screenshot.tscn -- --difficulty=normal --seed=3 --hours=48 --tab=2 --out=/tmp/shot.png` |

On a fresh clone, run `godot --headless --import` once first.

## How to play

You are the group's leader. You don't walk anyone around; you give orders and decide.

- **Top bar:** clock, date, temperature, day/night, speed (Space pauses, 1/2/3 for 1×/3×/10×), and whether power, taps and phones still work. At 1× a day takes 72 seconds.
- **Map (left):** the 2 km town. Buildings are coloured by type; the green outline is your base; blue dots are survivors out on trips; the red tint and numbers are infected per zone. Click a building to inspect it.
- **Group tab:** each survivor's body in real units (water deficit in litres, energy debt in kcal, blood volume, core temperature, fatigue, sleep debt, stress), their wounds, and their day and night jobs. Jobs: rest, scavenge, guard, fortify, collect water, cook, treat.
- **Building tab:** what is inside the selected building, how dangerous it is, how long a trip takes, and buttons to send someone to scavenge it or to move your base there.
- **Base tab:** defense and what it is made of, stores, and standing orders: food and water rations, boiling, generator, firearms.
- **Decisions tab:** bites, antibiotics and strangers at the gate. The clock stops until you answer.
- **Log (bottom):** what happened and why.

Win by reaching day 30 with anyone still in the group. You lose if everyone is dead, turned or gone, or if every survivor's morale breaks.

## Layout

```
data/      items, buildings, loot tables, survivors, events, town map, scenario (all JSON)
core/      autoloads (Rng, EventBus, WorldState, Data, TickLoop) and shared helpers
systems/   time, infrastructure, town, base, jobs, infected, survivors, resources, events, outcome
ui/        HUD, map, panels, log, end screen
tools/     headless runner, auto-player, screenshot tool, town generator, test runner
tests/     one headless test suite per milestone
```

The rules the code keeps are in [CLAUDE.md](CLAUDE.md): the simulation never touches the UI, systems talk only through WorldState and the EventBus, content is data, units are real, randomness is seeded.
