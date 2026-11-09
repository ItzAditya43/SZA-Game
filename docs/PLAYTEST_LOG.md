# Playtest log

Every bug, confusion or wish found while playing, in the order it was found. Each entry stays here after it's fixed, so nothing reported gets lost. Unfixed items are the to-do list; the designer's notes for prompt 2 (UI/UX) can be pulled from here.

Status: **open**, **fixed** (with the commit), or **noted for prompt N** (a design change, not a bug).

| # | Date | Found | What happened | Cause | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-10-19 | Start screen, first launch | The new-run panel sat low on the screen with the bottom (including Start) cut off, so a game couldn't be started. | The panel centred itself using its size before its contents were laid out, then grew downward. | fixed: start, end and pause/load panels now anchor to the screen centre and grow both ways |
| 2 | 2026-10-19 | First real attempt to play | "The UI/UX is so bad I can't understand anything." Walls of text, no sense of what matters or what to do next. | The Prototype 1 UI was a debugging view of the simulation, not a player's view. | addressed on branch `feat/ui-ux` (prompt 2): new layout, cards with 4 meters, hover breakdowns, trip planner, decision windows, alerts, overlays, hints. Needs the designer's replay to confirm |
| 3 | 2026-10-19 | Screenshot self-check (prompt 2) | The move-base confirmation opened as an empty dark column. | Wrapped text had no width when the window sized itself. | fixed on `feat/ui-ux` |
| 4 | 2026-10-19 | Screenshot self-check | The trip planner rated every departure "severe", even midday. | It rated the chance of *meeting* infected, which is near-certain on any long trip; most meetings end with slipping past. | fixed on `feat/ui-ux`: rated by chance of getting hurt (midday ~23%, night ~78% on a test trip) |
| 5 | 2026-10-19 | Screenshot self-check | The Log tab opened scrolled to old entries. | It scrolled to the end before it had a size. | fixed on `feat/ui-ux`: stays pinned to the newest line unless you scroll up |
| 6 | 2026-10-19 | Screenshot self-check | The Day 0 tip covered the base on the map, and Sleep read "0.0 / 7 h" before anyone had slept. | Layout / no night yet. | fixed on `feat/ui-ux`: tip sits bottom-right; Sleep reads "rested" until the first dawn |
| 7 | 2026-10-19 | Screenshot self-check | On Day 10 the Alerts list still asked what to do about Farhan's bite, though he had turned on Day 5. | Decisions put off with "Decide later" stay pending after the person they're about is gone. | fixed in the UI on `feat/ui-ux` (moot decisions are hidden). The simulation still keeps them; clearing them on death is a small simulation change for a later prompt |
| 8 | 2026-11-09 | Request: "make a tutorial everywhere it is needed" | Only five tips existed and they stopped after Day 2. Nothing explained the tabs, the planner, map layers, the job board or the late game, and the first tip said the clock was paused when new runs start at 1×. | The first-day hints were a stopgap. | fixed on `feat/tutorial`: data-driven tips (29), Getting started list, nine-page How to play guide (H), first-run guide, explanatory tip on every tab; tests in `test_tutorial` |
