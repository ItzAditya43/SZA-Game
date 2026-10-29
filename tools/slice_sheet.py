#!/usr/bin/env python3
"""Cuts a magenta-background sprite sheet into one transparent PNG per asset.

    python3 tools/slice_sheet.py assets/source/sheet_v1.png assets/sprites

Finds rows and then cells by the magenta gaps between them (so the sheet need
not be an exact grid), keys out magenta (with a soft edge for anti-aliasing),
crops each asset to its content and names it from NAMES, row by row.
"""
import sys
from pathlib import Path
from PIL import Image

NAMES = [
    ["ground_dirt", "ground_road", "ground_plaza", "ground_field", "ground_canal", "ground_grass", "ground_rubble", "ground_burnt"],
    ["bld_house", "bld_grocery", "bld_pharmacy", "bld_fuel_station", "bld_hardware", "bld_school", "bld_hospital", "bld_police_station"],
    ["bld_water_tower", "bld_factory", "map_barricade", "map_cache", "map_handcart", "map_vehicle", "map_fire", "map_ruin"],
    ["tok_survivor", "tok_survivor_pack", "tok_survivor_guard", "tok_survivor_rest", "tok_infected", "tok_infected_group", "tok_body", "tok_survivor_bitten"],
    ["item_water_bottled", "item_water_drum", "item_cooked_meal", "item_grain", "item_packaged_food", "item_bandages", "item_antibiotics", "item_rehydration_salts"],
    ["item_fuel", "item_cooking_gas", "item_materials", "item_cigarettes", "item_generator", "item_machete", "item_rifle", "item_ammo"],
    ["job_rest", "job_scavenge", "job_guard", "job_fortify", "job_quick_fortify", "job_collect_water", "job_cook", "job_treat"],
    ["cond_bleeding", "cond_bitten", "cond_fever", "cond_hungry", "cond_thirsty", "cond_exhausted", "cond_stressed", "util_power", "util_taps", "util_phones"],
]


def is_key(p):
    r, g, b = p[:3]
    return r > 200 and b > 200 and g < 80


def runs(flags, min_len=20):
    out, start = [], None
    for i, f in enumerate(flags + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            if i - start >= min_len:
                out.append((start, i))
            start = None
    return out


def main(src, dst):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    px = im.load()
    row_has = [any(not is_key(px[x, y]) for x in range(0, w, 2)) for y in range(h)]
    rows = runs(row_has)
    assert len(rows) == len(NAMES), f"found {len(rows)} rows, expected {len(NAMES)}"
    Path(dst).mkdir(parents=True, exist_ok=True)
    for (y0, y1), names in zip(rows, NAMES):
        col_has = [any(not is_key(px[x, y]) for y in range(y0, y1, 2)) for x in range(w)]
        cols = runs(col_has)
        assert len(cols) == len(names), f"row {names[0]}: found {len(cols)} cells, expected {len(names)}"
        for (x0, x1), name in zip(cols, names):
            cell = im.crop((x0, y0, x1, y1))
            cp = cell.load()
            for y in range(cell.height):
                for x in range(cell.width):
                    r, g, b, a = cp[x, y]
                    # Distance from pure magenta: 0 = background, fade the fringe.
                    d = max(255 - r, g, 255 - b)
                    if d < 60:
                        cp[x, y] = (r, g, b, 0)
                    elif d < 140:
                        alpha = int(255 * (d - 60) / 80)
                        # Pull the magenta tint out of the edge colour.
                        cp[x, y] = (min(r, g + 40), g, min(b, g + 40), alpha)
                    # Despill: soft shadows blended into magenta come out purple.
                    # Anything with both red and blue well above green gets its
                    # tint pulled back towards neutral grey.
                    r, g, b, a = cp[x, y]
                    if a and r > g + 18 and b > g + 18:
                        v = int(g * 0.7)
                        cp[x, y] = (v, v, v, a)
            cell = cell.crop(cell.getbbox())
            cell.save(Path(dst) / f"{name}.png")
    print(f"wrote {sum(len(n) for n in NAMES)} sprites to {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
