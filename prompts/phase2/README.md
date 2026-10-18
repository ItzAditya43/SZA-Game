# Survival Sim — next handoff pack

Five prompts for Claude Code, run in order. Each one is a separate branch and a separate review. Don't paste them all at once.

| # | Prompt | What it does | Size |
| --- | --- | --- | --- |
| 1 | `prompts/01-stabilize.md` | Make "keep moving" work (location attention model), save/load, survivor pool with traits, export fix, map as data | Medium |
| 2 | `prompts/02-ui-ux.md` | Theme, layout, compact survivor cards, tooltips that explain causes, scavenge planner, forecasts and warnings, map overlays, stats graphs | Large |
| 3 | `prompts/03-graphics-audio.md` | Tile map, day/night lighting, weather, fog of war, decay visuals, moving tokens, ambient sound | Large |
| 4 | `prompts/04-realism-depth.md` | Difficulty-based information fog, morale recovery, fractures/burns/sanitation/ORS, blood transmission, smell and wind, hordes, fire spread | Large |
| 5 | `prompts/05-prototype-2-world.md` | Day 30–100: climate model, monsoon, rain catchment, vector disease, natural-selection mutation, one simulated rival group, barter, gardens | Very large |

Also copy `CLAUDE-md-addendum.md` into the bottom of your project's `CLAUDE.md` before running prompt 1.

## Order and why

1. **Stabilize first.** A broken strategy and no saves make every later playtest worse.
2. **Play one full Normal game yourself** before prompt 2. Note every moment you were confused, bored or annoyed. Paste those notes at the top of prompt 2. This matters more than anything in the prompt.
3. **UI/UX before graphics.** Graphics on top of a confusing UI just make a prettier confusing game.
4. **Realism depth after the UI**, because information fog and new conditions need the UI to show them clearly.
5. **Prototype 2 last**, and only if the 30-day game is fun.

## How to run each prompt

- Start Claude Code in the project folder. For prompts 2–5, ask it to make a plan first (plan mode), check the plan, then let it build.
- Each prompt is split into parts. If you want to review as it goes, add "Stop after each part and report" to the top.
- Every prompt ends with a report. Read the "not working / not verified" section first.
- Merge to `main` only after you've played the branch.

## Decisions made for Claude Code (change any you disagree with before running)

These answer the brainstorm list from the last report.

1. **Difficulty feel:** Hard also hides information, not just numbers. Easy shows exact values, Normal shows estimates that sharpen when scouted, and Hard shows vague words unless recently scouted (it also can't always tell a bite from a cut). The simulation stays identical across levels. (Prompt 4)
2. **What kills people:** keep the infected and morale as the main killers within 30 days, per the timeline. Hunger, disease and heat cause more non-fatal trouble earlier (lost work days, illness) instead of more deaths. (Prompt 4)
3. **Morale:** add exit paths: routine, rest days, shared hot meals, leader actions, friendships, and rites for the dead. (Prompt 4)
4. **Keep moving:** fix it realistically with a location attention model. Staying put builds up noise, smell and light that draw the infected; moving resets that, but costs carry capacity, exposure and fortifications. Add handcarts, quick barricades and hidden caches. (Prompt 1)
5. **What the player sees:** depends on difficulty (see 1).
6. **Survivors:** a pool of 12 with backgrounds and traits. Pick 5, or choose "Random 5". The current five stay as a default preset for tests. (Prompt 1)
7. **Save/load:** yes, with autosave at each dawn. (Prompt 1)
8. **Prototype 2 scope:** as written in prompt 5.
9. **Art and sound:** CC0 asset packs plus lighting, shaders and particles. Claude Code can't paint good art itself, but it can integrate free packs well and do the effects work. (Prompt 3)
