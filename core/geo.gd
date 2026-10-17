extends RefCounted
## Town geometry in metres. The map is a grid of square tiles; zones are 4 x 4
## blocks of it. Distances follow the street grid (east-west plus north-south),
## which is how people actually walk through a town.

const ZONE_COLS: int = 4


static func tile_m() -> float:
	return float(WorldState.town.get("tile_m", 31.25))


static func building_center_m(building: Dictionary) -> Vector2:
	var tile: float = tile_m()
	return Vector2((float(building["x"]) + float(building["w"]) / 2.0) * tile,
		(float(building["y"]) + float(building["h"]) / 2.0) * tile)


static func base_center_m() -> Vector2:
	var base: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	return building_center_m(base) if not base.is_empty() else Vector2.ZERO


## Walking distance along the street grid.
static func street_distance_m(a: Vector2, b: Vector2) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)


static func zone_size_m() -> float:
	return float(WorldState.town.get("zone_size_tiles", 16)) * tile_m()


static func zone_index_at(pos_m: Vector2) -> int:
	var size: float = zone_size_m()
	var col: int = clampi(floori(pos_m.x / size), 0, ZONE_COLS - 1)
	var row: int = clampi(floori(pos_m.y / size), 0, ZONE_COLS - 1)
	return row * ZONE_COLS + col


@warning_ignore("integer_division")
static func zone_center_m(index: int) -> Vector2:
	var size: float = zone_size_m()
	return Vector2((float(index % ZONE_COLS) + 0.5) * size, (float(index / ZONE_COLS) + 0.5) * size)


## The building whose footprint covers this tile, or {}.
static func building_at_tile(tile: Vector2i) -> Dictionary:
	for building: Dictionary in WorldState.buildings:
		var x: int = int(building["x"])
		var y: int = int(building["y"])
		if tile.x >= x and tile.x < x + int(building["w"]) and tile.y >= y and tile.y < y + int(building["h"]):
			return building
	return {}
