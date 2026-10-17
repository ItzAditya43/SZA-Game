extends "res://core/sim_system.gd"
## Town and loot. Builds the buildings from data/town.json, each with finite loot
## rolled from its type's loot table. Every morning each building loses its daily
## "looted" share to other survivors (not simulated, so abstracted as a rate),
## and food in it ages and spoils like anywhere else.

const Stores := preload("res://core/stores.gd")
const Difficulty := preload("res://core/difficulty.gd")

## Whole-unit items (antibiotic strips, rifles) are lost one by one, by chance;
## bulk items (kcal, litres) lose an exact share.
const COUNTED_UNITS: Array[String] = ["count", "rounds", "units"]
## A building is announced as stripped when its loot falls below this share of the start.
const STRIPPED_SHARE: float = 0.1
## Buildings are shuttered and shaded: this much cooler than the day's mean air.
const INDOOR_COOLING_C: float = 3.0
## Once the taps fail, other survivors draw on every roof tank in town.
const TANK_DRAWN_BY_OTHERS_PER_DAY: float = 0.08


func setup() -> void:
	var town: Dictionary = Data.table("town")
	WorldState.town = {
		"width": int(town["width"]), "height": int(town["height"]), "tile_m": float(town["tile_m"]),
		"rows": town["rows"], "landmarks": town["landmarks"],
		"zone_size_tiles": int(town["zones"]["size_tiles"]),
	}
	for row: Dictionary in town["buildings"]:
		WorldState.buildings.append(_new_building(row))


func tick() -> void:
	if not WorldState.is_new_day():
		return
	var climate: Dictionary = WorldState.climate
	var indoor_c: float = (float(climate["today_min_c"]) + float(climate["today_max_c"])) / 2.0 - INDOOR_COOLING_C
	for building: Dictionary in WorldState.buildings:
		if building["id"] == WorldState.base.get("building", ""):
			continue
		_looted_by_others(building)
		if not WorldState.infrastructure.get("mains_on", true):
			building["tank_l"] = float(building["tank_l"]) * (1.0 - TANK_DRAWN_BY_OTHERS_PER_DAY)
		Stores.age_and_spoil(building["loot"], 1.0, indoor_c)
		_check_stripped(building)


func _new_building(row: Dictionary) -> Dictionary:
	var type: Dictionary = Data.entry("buildings", String(row["type"]))
	var loot: Dictionary = {}
	for entry: Dictionary in Data.entry("loot_tables", String(type["loot_table"]))["loot"]:
		if not Rng.chance(float(entry.get("chance", 1.0))):
			continue
		var item: String = entry["item"]
		var qty: float
		if _counted(item):
			qty = float(roundi(Rng.randi_range(int(entry["min"]), int(entry["max"])) * Difficulty.mult("loot")))
		else:
			qty = lerpf(float(entry["min"]), float(entry["max"]), Rng.randf()) * Difficulty.mult("loot")
		Stores.add(loot, item, qty)
	return {
		"id": String(row["id"]), "type": String(row["type"]), "name": String(row["name"]),
		"x": int(row["x"]), "y": int(row["y"]), "w": int(row["w"]), "h": int(row["h"]),
		"loot": loot, "start_loot": Stores.snapshot(loot),
		"tank_l": float(type.get("water_tank_l", 0.0)), "tank_start_l": float(type.get("water_tank_l", 0.0)),
		"danger": float(type["danger"]), "locked": Rng.chance(float(type.get("locked_chance", 0.0))),
		"barricade": 0.0, "stripped": false, "visits": 0,
	}


func _looted_by_others(building: Dictionary) -> void:
	var rate: float = minf(1.0, float(Data.entry("buildings", String(building["type"]))["daily_looted_rate"]) * Difficulty.mult("looted_by_others"))
	for item: String in Stores.snapshot(building["loot"]):
		var qty: float = Stores.total(building["loot"], item)
		var lost: float = 0.0
		if _counted(item):
			for unit: int in roundi(qty):
				if Rng.chance(rate):
					lost += 1.0
		else:
			lost = qty * rate
		Stores.take(building["loot"], item, lost)


func _check_stripped(building: Dictionary) -> void:
	if building["stripped"]:
		return
	var start: Dictionary = building["start_loot"]
	if start.is_empty():
		return
	var share: float = 0.0
	for item: String in start:
		share += Stores.total(building["loot"], item) / float(start[item])
	if share / start.size() >= STRIPPED_SHARE:
		return
	building["stripped"] = true
	var event_name: StringName = &"pharmacy_looted" if building["type"] == "pharmacy" else &"building_stripped"
	EventBus.emit_event(event_name, {"building": building["id"],
		"text": "%s has been stripped almost bare by other survivors." % building["name"]})


static func _counted(item: String) -> bool:
	return COUNTED_UNITS.has(String(Data.entry("items", item).get("unit", "")))
