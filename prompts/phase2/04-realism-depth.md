# Handoff 04: Realism depth and difficulty scaling

Read `CLAUDE.md`, `docs/GAME_DESIGN.md` (especially the Realism rules, The body, The pathogen, Environment and the Fidelity map) and `docs/IMPLEMENTATION_NOTES.md`. Branch `feat/realism-depth` from the reviewed `feat/graphics-audio`. If prompt 3 hasn't been merged, branch from `feat/ui-ux` and say so.

This prompt deepens the 30-day game. It pulls the items from the Fidelity map's "Prototype 2–3" column that make sense within 30 days. Stay within Day 0–30; Prototype 2 comes later.

**Principle:** difficulty never changes the rules of the world. It changes how big and hostile the world is (already done) and **how much the group knows** (new here).

## Part A — Truth vs knowledge, and information fog by difficulty

1. **Add `core/player_knowledge.gd`.** For each building, zone, survivor condition and store, it records the last observed value, the tick it was observed, and who observed it (their skill affects accuracy).
2. **Observations happen** when survivors are present, scout, do inventory, treat someone, or hear the radio. Each observation has error based on skill, light (night is worse) and distance.
3. **Add an `info` block to `data/difficulty.json`:**
   - **Easy:** exact values everywhere, and every wound correctly identified.
   - **Normal:** infected counts shown as ranges (e.g. "40–60") that narrow with recent scouting and widen as info ages. Stores are exact. Wounds are identified correctly only by someone with Medicine ≥ 4; otherwise "unclear wound".
   - **Hard:** infected shown as words (none / few / many / horde) unless scouted within 1 day. Stores are exact only after an inventory job; otherwise estimates. A bite vs an ordinary wound can't be told apart without an inspection by Medicine ≥ 6 in daylight. Radio info is sometimes wrong.
4. **The UI and renderer read knowledge,** except where the difficulty says exact. Update every place that currently reads truth.
5. **The automated player must decide using knowledge only.** Add a test that fails if any bot code reads hidden truth.
6. **Hidden bites become a real event:** a survivor may hide a bite (more likely when stress is high and trust is low). On Hard this is genuinely hard to catch.

## Part B — Morale and the mind

Survivors currently stay "too shaken to work" for days. Add realistic recovery paths, all with costs and data-driven numbers:

- **Routine:** the same useful job 3+ days in a row slowly lowers stress.
- **Rest days:** a full day off. Costs labour.
- **Shared hot meals:** cooking together, which costs fuel and time, lowers stress for everyone present.
- **Leader action:** once a day the leader (player-chosen survivor) can talk someone through it. It works better with high trust; costs the leader energy.
- **Friendships:** pairs who work together build a bond. A friend nearby softens stress; losing a friend hits hard.
- **Rites for the dead:** burial or cremation (cremation costs wood/fuel, and both take time) cuts grief faster than leaving the body. Unburied bodies raise stress, smell and disease risk.
- **Trauma** (from the spec): seeing a horde up close, or killing someone who turned, may leave a lasting trait (nightmares, freezing in combat, refusing night guard).
- **"Too shaken to work"** gets a clear duration estimate and visible recovery progress in the UI.

**Target:** on Normal (median over 40 games), no survivor spends more than 40% of days unable to work. Report the distribution.

## Part C — The body

- **Fractures:** can't use that limb for 6–8 weeks; a splint is needed; open fractures risk infection. They come from falls and fights.
- **Burns:** from fire or cooking accidents; fluid loss and high infection risk; need clean dressings.
- **Pain and shock:** severe pain lowers work speed and aim; painkillers are finite.
- **Heatstroke** beyond the existing heat exhaustion: heavy work above 40 °C without water or shade can kill. Shade and working at dawn or dusk are real strategies.
- **Sanitation:** the group must dig a latrine. Its distance from the water source changes contamination risk. Rubbish piles attract rats and dogs (abstract for now).
- **Crowding:** more people in a small base raises respiratory and skin infection risk.
- **Nutrition tracking:** track protein and vitamin C intake now. Low protein slows healing within 30 days; scurvy itself takes 4–8 weeks, so it only matters in Prototype 2, but the tracking starts now.
- **ORS:** oral rehydration salts can be made from salt, sugar and boiled water. Survivors with Medicine skill know the recipe. This is the realistic counter to dysentery deaths.

## Part D — Pathogen and the infected

- **Blood and fluid transmission in melee:** gloves, goggles and long weapons (spears, lathis) reduce the risk. These become loot and craft items.
- **Carriers:** about 1–2% of recruited strangers carry the pathogen and turn weeks later, so in a 30-day game only those recruited early can turn. They can't be detected in Prototype 1.
- **Wind:** a simulated daily wind direction and strength. Smell (cooking, bodies, latrine) spreads downwind and draws infected from that side. Feed it into the attention model from prompt 1.
- **Hordes:** when attention stays high, infected from several zones merge into a horde with a direction of travel. Hordes are slower, louder and can break weak barricades. They need a warning cue the group can observe (sound at a distance, birds scattering).

## Part E — Fire

- **Fire spreads** by building material (thatch and stocked shops burn fast, concrete resists), wind, and dryness (summer is worse).
- **Causes** are always traceable: a cooking fire, candles or lamps, the generator, a gunshot near fuel, rarely lightning. Never random from nowhere.
- **Fighting fire** needs water and people; it makes noise and light.

## Part F — What kills people

- Keep the infected and morale as the main killers within 30 days (per the timeline). Hunger, disease, heat and injury should cause more **non-fatal** trouble earlier: lost work days, illness, slower healing.
- **Report deaths by cause, and lost work days by cause,** for each difficulty. The goal is that disease and heat clearly shape decisions even when they rarely kill.

## Balance targets (40 games each)

| Difficulty | Best strategy win rate | Weakest sensible strategy | Careless play |
| --- | --- | --- | --- |
| Easy | ≥ 95% | ≥ 80% | ≥ 50% |
| Normal | 80–95% | 50–70% | ≤ 30% |
| Hard | 55–75% | 20–40% | ≤ 10% |

"Careless play" is a new bot strategy: drinks unboiled water, runs the generator all night, never buries the dead, scavenges at night, ignores warnings. It shows that realism punishes carelessness.

## Done when

- Every part works with tests.
- The bot uses knowledge only (enforced by a test).
- The balance table meets or is close to the targets, with the gaps explained.
- Deaths and lost work days are reported by cause.

## Report back with

- What changed, by part.
- Balance tables before and after.
- Deaths and lost work days by cause.
- What the information fog feels like in practice on each difficulty (describe a Day 10 screen).
- Anything unrealistic you had to compromise on.
- Anything not working.
