# Handoff 03: Graphics and audio

Read `CLAUDE.md`, `docs/GAME_DESIGN.md` and `docs/IMPLEMENTATION_NOTES.md`. Branch `feat/graphics-audio` from the reviewed `feat/ui-ux`.

## Direction

A **readable, grounded top-down 2D look**: think a city map at dusk, not a cartoon. The world should feel like a real South Indian district town: narrow lanes, flat concrete roofs with black water tanks, tiled and tin roofs, a market street with stalls, open drains, a temple and other places of worship, coconut and neem trees, a canal.

**Be honest about art.** Don't try to hand-draw detailed sprites. Use:
1. **CC0 asset packs:** Kenney.nl packs are CC0. Check others individually (OpenGameArt, itch.io) and use only CC0 or CC-BY.
2. **Procedural shapes, shaders, lighting and particles** for everything else.

Consistency beats detail. If assets don't match, use clean procedural shapes for everything instead. Record every asset in `CREDITS.md` (path, author, URL, licence). If the licence is unclear, don't use it. If you can't download assets from this machine, write `docs/ASSETS_TODO.md` listing exactly which packs to download and where to put them, build with procedural fallbacks, and tell me.

## Architecture

- New folder `res://render/` for the map renderer, lighting, weather, fx and camera. It only reads `WorldState`/`PlayerKnowledge` and listens to `EventBus`.
- `res://assets/{tiles,sprites,fx,audio,fonts}`.
- Headless runs must not load any of it. Prove it with the existing headless tests and a balance run that matches the previous one exactly.
- **Performance budget:** 60 fps at 1920×1080 on integrated graphics with all effects on. Add a settings panel with quality presets (Low/Medium/High) and toggles for lights, shadows, particles and screen effects. Add a "Reduce motion" option.

## Part A — The map

- **Move the map to `TileMapLayer`s:** ground (soil, grass, paved), roads and lanes, water (canal, drains, later flood), buildings, vegetation.
- **Buildings** are footprints with roofs. Colour and material come from the building type and its data (concrete, tile, tin, thatch). Landmarks (hospital, police station, school, temple, market) get distinct silhouettes so they're recognisable at a glance.
- **A camera** with smooth pan and zoom (mouse wheel, drag, WASD), bounded to the map. **Level of detail:** zoomed out shows simplified blocks and zone tints; zoomed in shows roof details, trees and tokens.

## Part B — Living tokens

- **Survivors** are small, distinct tokens in your group's colour, with an initial. When scavenging they visibly walk the route along roads, interpolated per tick with tweens, not teleporting.
- **The infected** are shown per zone as clustered dots, based on knowledge rather than truth (so they're fuzzy on Normal/Hard after prompt 4). They drift toward attention sources.
- **Noise events** spawn expanding rings whose radius matches the real noise distance.

## Part C — Time of day and lighting

- A `CanvasModulate` driven by minute of day: cool blue before dawn, warm orange sunrise, harsh pale noon, golden dusk, deep blue night. Put the colour stops in data.
- **`PointLight2D`** for fires, cooking, lamps and the generator. **`LightOccluder2D`** on buildings, so light spills down lanes and is blocked by walls. Lights at night should visibly show why they draw attention.
- **Blackout curtains,** when built, visibly reduce light spill.

## Part D — Weather and season

- **Rain** uses `GPUParticles2D`, with a slight darkening and wet-ground sheen on roads (shader). The heavier the rain, the more particles.
- **Summer midday:** a subtle heat-shimmer shader and a bleached tint.
- **Winter dawn:** low fog.
- **Wind:** drifting leaves and smoke whose direction matches the simulation's wind. Prompt 4 adds simulated wind; until then, use a fixed direction.
- **Floods** come in Prototype 2. Leave a water-level hook in the renderer.

## Part E — Decay and state you can see

- A building's look reflects its state: doors broken after looting, scorch marks after fire, boarded windows when barricaded, a blue tarp on damaged roofs.
- Grass and weeds creep over roads with days since the outbreak, via a shader noise threshold.
- Fires get flame particles and a smoke column visible from far away. Smoke drifts with the wind.
- Bodies (abstract dark marks, not gore) appear where people died, until buried or burned.

## Part F — Fog of knowledge

- **Never-seen tiles** are dark. **Seen but stale** ones are desaturated, and stronger the older the info. **Currently observed** areas (near survivors) are full colour.
- This visualises `PlayerKnowledge` from prompt 4. If prompt 4 hasn't run yet, build it on a simple "visited / near survivors" model and leave a clear hook.

## Part G — Audio

- **Audio buses:** Master, Music, Ambient, SFX, UI, each with a settings slider.
- **Ambient beds by phase and season:** day (crows, distant traffic gone silent, dogs), night (crickets, distant howls, wind), rain (different strengths), summer heat (cicadas).
- **SFX:** UI clicks, notifications by tier, distant gunshot, a generator loop while running, a fire crackle positioned in 2D, doors and barricades.
- When paused or in a decision modal, apply a low-pass filter to ambience.
- Prefer CC0 sounds. Freesound has mixed licences; check each file and credit it.
- No music required. If you add any, it must be CC0/CC-BY and quiet.

## Part H — Visual self-check

Use `tools/screenshot.gd` to capture Day 1 noon, Day 5 night with the generator on, Day 15 rain, and Day 28 dusk, at 1280×720 and 1920×1080. Look at every image and fix anything muddy, unreadable or inconsistent. Save them in `docs/screenshots/graphics/`. Report the fps measured on this machine for each quality preset.

## Done when

- Every part works.
- The headless and balance results are identical to before.
- Screenshots exist.
- `CREDITS.md` is complete.
- 60 fps holds on the High preset on this machine, or you report the measured numbers honestly.

## Report back with

- Screenshots.
- Assets used and their licences.
- What's procedural.
- Measured fps for each preset.
- What still looks weak and what kind of asset would fix it.
- Anything not working.
