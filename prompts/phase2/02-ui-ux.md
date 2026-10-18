# Handoff 02: UI/UX overhaul

Read `CLAUDE.md`, `docs/GAME_DESIGN.md`, `docs/IMPLEMENTATION_NOTES.md` and open `docs/world-scrubber.html` in a browser for the intended feel. Branch `feat/ui-ux` from the reviewed `feat/stabilize`.

**Designer's playtest notes (read first, they take priority over the list below):**

> [PASTE YOUR NOTES FROM YOUR OWN PLAYTHROUGH HERE — what confused you, what was boring, what you kept looking for]

## Goals

1. You can read the state of the group in about 3 seconds.
2. Every number explains its cause when you hover it (realism rule 4: the player can always trace why).
3. You see the consequence of a choice before you commit.
4. Fewer walls of text. Use icons plus short words, with details on demand.

The simulation must not change in this prompt, except for adding read-only helper functions (forecasts, breakdowns) that the UI needs. Balance numbers must be identical before and after; prove it with a balance run.

## Part A — Visual foundation

- A single Godot `Theme` at `res://ui/theme/main_theme.tres`. Every Control uses it, with no per-node colour overrides.
- **Font:** Noto Sans (or Inter), plus Noto Sans Tamil/Kannada/Malayalam/Telugu if any place names use those scripts. Minimum on-screen size 13 px at 1080p.
- **Spacing scale:** 4/8/12/16/24/32. **Colour tokens:** background layers, text primary/secondary, ok/warn/danger/info, and one colour each for your group, infected, rival groups and water.
- **Colour-blind safe:** never use red vs green alone. Every state also has an icon or a word.
- **UI scale setting:** 80–150%. Test at 1280×720 and 1920×1080.

## Part B — Layout

- **Top bar:** day, clock and phase; weather and temperature; speed controls; an alert counter that opens the alerts list.
- **Centre:** the map.
- **Right panel with tabs:** People · Stores · Base · Log. Collapsible.
- **Bottom ticker:** the last 3 events, each clickable to jump to it on the map.
- **Pause menu:** save, load, settings, quit.

## Part C — Survivor cards

- **Compact card:** name, current job, 4 mini meters (water today vs need, kcal today vs need, sleep last night, stress), and condition icons (bleeding, infected wound, fever, suspected bite, exhausted, heat illness, too shaken to work).
- **Click to expand:** full stats, skills, traits, and a cause breakdown for each meter, e.g. "Stress 68: +20 saw a death (day 11), +12 night attack, −6 hot meal, −4 slept 7 h".
- **Drag a card onto a job slot** to assign it. Show a warning if the assignment is unwise (exhausted person on night guard, fever and scavenging).

## Part D — Tooltips with causes

Add a helper to the systems that returns a breakdown for any displayed number: `{value, unit, contributions: [{label, amount}], forecast}`. Every number in the UI uses it. For example, hovering "Water 46 L" shows usage per day by person, days left at the current rate, and where the water came from.

## Part E — Scavenge planner

When you send people out, a planner panel shows:
- the target building (name, type, last scouted, estimated loot, danger)
- the team, and when to leave: now, midday heat, dusk or night
- **live estimates:** travel time, noise made, encounter risk band (low/moderate/high/severe), carry capacity in kg
- **priorities:** drag to order water / food / medicine / fuel / materials / tools; scavengers fill their capacity in that order
- the expected return time

These estimates must come from the same formulas the simulation uses. No separate guesses that drift out of sync.

## Part F — Forecasts and warnings

- **A Stores forecast:** water, food, fuel and medicine in days left at current use, with a small trend arrow.
- **Warnings by tier:** info / caution / urgent. Examples: "Water lasts 2.1 days", "Arjun's wound is reddening", "Attention at base is high", "Generator fuel for 9 hours".
- **The player can choose which warning types auto-pause the game.**
- **Warnings only state what the group could know.** "The mains will fail soon" appears only after an in-world cue (dropping pressure, a radio message). Don't leak hidden timers.

## Part G — Decisions

- Decision modals show each option with known consequences, plus clearly marked unknowns ("Unknown: whether the Market Gang keeps the deal").
- Default focus never sits on an irreversible option.

## Part H — Map interaction

- **Hover a building:** name, type, estimated loot, danger, last scouted day.
- **Overlay toggles,** matching the world scrubber: infected density, noise, light at night, smell and wind, attention, disease risk. One active overlay at a time, plus a small legend.
- **Click an event** in the log to jump to its location and highlight it.

## Part I — Stats and end screen

- **A Stats tab:** line charts over days for water, food, survivors alive, average stress, infected estimate and attention. Use Godot `Line2D` or a small custom draw; no plugins.
- **The end screen** shows the same charts, the cause of each death, and the key decisions on a timeline.

## Part J — Onboarding and controls

- Dismissible hints on Day 0–2 (first scavenge, first night, first water warning). Never show them again once dismissed. Saved in settings.
- A shortcuts overlay on `?`. Rebindable keys are optional; at least document them.

## Part K — Visual self-check

Add `tools/screenshot.gd` to load a saved game at a given day and capture the main screen to PNG. Run it with a display, or with xvfb if headless rendering isn't available, at 1280×720 and 1920×1080 for Day 1, Day 10 and Day 25 saves. Look at every screenshot and fix clipping, overlap and unreadable text before reporting. Include the screenshots in `docs/screenshots/`.

## Done when

- Every part works.
- The balance run is identical to before (same seed, same results).
- Screenshots exist and look clean at both resolutions.
- No UI code reads simulation internals except through `WorldState` and the breakdown helpers.

## Report back with

- Screenshots.
- What changed, by part.
- Which designer notes you addressed and which you didn't, with reasons.
- Anything that still feels cluttered.
- Anything not working or not verified.
