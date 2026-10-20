# Survival Sim — Prototype 1

A realistic, strategic zombie/mutant apocalypse survival simulation set in a fictional small town, built in Godot 4 (typed GDScript). One town, five survivors, thirty days after the outbreak. The town and everyone in it get new names each run, from the seed. Art-free: coloured tiles and text panels.

The player's and developer's reference (rules, numbers, commands) is [docs/GAME_GUIDE.md](docs/GAME_GUIDE.md). The design lives in [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md). What was built, every design call made along the way and the balance results are in [docs/IMPLEMENTATION_NOTES.md](docs/IMPLEMENTATION_NOTES.md).

## Run it

Needs Godot 4.3 or later (built and tested on 4.7.2). From this folder:

| What | Command |
| --- | --- |
| Play | `godot` (opens on the start screen: difficulty, your five survivors, Continue or Load) |
| Play straight into a run | `godot -- --difficulty=hard --seed=42` |
| Open in the editor | `godot -e` |
| All tests | `bash tools/run_tests.sh` |
| One test suite | `godot --headless --script res://tests/test_milestone_4.gd` |
| One headless run, told as a story | `godot --headless --script res://tools/headless_runner.gd -- --difficulty=normal --seed=7 --days=30 --strategy=balanced --verbose=1` |
| Balance batch (100 games per strategy and difficulty) | `godot --headless --script res://tools/headless_runner.gd -- --games=100 --difficulty=all --strategy=all` |
| Screenshot of the game screen | `godot res://tools/screenshot.tscn -- --difficulty=normal --seed=3 --hours=48 --tab=2 --out=/tmp/shot.png` |

On a fresh clone, run `godot --headless --import` once first.

## How to play

You are the group's leader. You don't walk anyone around; you give orders and decide. Press **?** in game for every key.

- **Top bar:** day and clock, date, temperature and phase, speed (Space pauses, 1/2/3 for 1×/3×/10×; at 1× a day takes 72 seconds), whether power, taps and phones still work, and **Alerts** (red when something is urgent; click it for the list and to choose what pauses the game).
- **Map (centre):** the 2 km town. Click a building for its card: what's inside, danger, last visit, and buttons to plan a trip or move the base there. The bar above the map switches one layer at a time (infected, noise, light at night, smell and wind, attention, disease risk), each with a legend.
- **Side panel (Tab hides it):** People (who does which job by day and night; drag a name to another job; each card shows water, food, sleep and stress, click it for the causes), Stores (how many days water, food, gas and medicine last), Base (defense, attention, standing orders), Log (filterable; click a line to find it on the map) and Stats (charts by day).
- **Hover any number** to see what makes it up and where it's heading.
- **Planning a trip:** pick who goes, when (now, midday, dusk, night) and what to bring back first. The planner shows the return time, how much they can carry and the chance of getting hurt, from the same rules the simulation uses.
- **Decisions** (bites, antibiotics, strangers) open in a window that spells out what each choice does and what nobody can know yet. Irreversible choices are marked red and never pre-selected.
- **Ticker (bottom):** the last three things that happened; click one to see where.
- **Saving:** autosave every dawn; Ctrl+S quick-saves, Ctrl+L loads, Esc opens the menu (save, load, settings, new run). Settings has interface size (80–150%) and which alerts pause the game.

Win by reaching day 30 with anyone still in the group. You lose if everyone is dead, turned or gone, or if every survivor's morale breaks.

## Layout

```
data/      items, buildings, loot tables, survivors, traits, events, town layout, attention, mobility, difficulty, scenario (all JSON)
core/      autoloads (Rng, EventBus, WorldState, Data, TickLoop) and shared helpers
systems/   time, infrastructure, town, base, jobs, infected, survivors, resources, events, outcome
ui/        HUD, map, panels, planner, modals, log, charts, end screen; ui/theme/ holds the one theme
tools/     headless runner, auto-player, screenshot tool, town generator, test runner
tests/     one headless test suite per milestone
```

The rules the code keeps are in [CLAUDE.md](CLAUDE.md): the simulation never touches the UI, systems talk only through WorldState and the EventBus, content is data, units are real, randomness is seeded.
