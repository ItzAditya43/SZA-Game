extends "res://tests/checks_base.gd"
## Milestone 3: town, loot and scavenging.

const Geo := preload("res://core/geo.gd")
const UiState := preload("res://ui/ui_state.gd")
const MapGrid := preload("res://ui/map_grid.gd")
const BuildingPanel := preload("res://ui/building_panel.gd")

const PHARMACY_ITEMS: Array[String] = ["antibiotics", "bandages", "painkillers"]


func run_checks() -> void:
	_check_town_layout()
	_check_loot_rolled()
	_check_click_shows_building()
	_check_pharmacy_drains()
	_check_scavenge_trip_near()
	_check_scavenge_trip_far()


func _check_town_layout() -> void:
	start(10)
	var counts: Dictionary = {}
	for b: Dictionary in WorldState.buildings:
		counts[b["type"]] = int(counts.get(b["type"], 0)) + 1
	var types_ok: bool = counts.size() == 10
	for type: Dictionary in Data.table("buildings"):
		types_ok = types_ok and int(counts.get(type["id"], 0)) == int(type["count"])
	expect("the town has the 10 building types in the counts from buildings.json (%d buildings)" % WorldState.buildings.size(),
		types_ok, str(counts))
	var rows: Array = WorldState.town["rows"]
	expect("the map is 64 x 64 tiles, 2 km across", rows.size() == 64 and String(rows[0]).length() == 64
		and is_equal_approx(Geo.tile_m() * 64.0, 2000.0))
	var bad: Array[String] = []
	var taken: Dictionary = {}
	for b: Dictionary in WorldState.buildings:
		for y: int in range(int(b["y"]), int(b["y"]) + int(b["h"])):
			for x: int in range(int(b["x"]), int(b["x"]) + int(b["w"])):
				if String(rows[y])[x] != "." or taken.has(Vector2i(x, y)):
					bad.append(b["id"])
				taken[Vector2i(x, y)] = true
	expect("every building sits on open ground without overlapping roads, canal or another building", bad.is_empty(), str(bad))


func _check_loot_rolled() -> void:
	start(10)
	var pharmacy: Dictionary = WorldState.building("pharmacy_01")
	var ok: bool = true
	for item: String in PHARMACY_ITEMS:
		var qty: float = Stores.total(pharmacy["loot"], item)
		var rule: Dictionary = {}
		for entry: Dictionary in Data.entry("loot_tables", "pharmacy")["loot"]:
			if entry["item"] == item:
				rule = entry
		ok = ok and qty >= float(rule["min"]) and qty <= float(rule["max"])
	expect("a pharmacy holds antibiotics, bandages and painkillers within its loot table's ranges", ok,
		str(Stores.snapshot(pharmacy["loot"])))
	var hospital: Dictionary = WorldState.building("hospital_01")
	expect("the hospital has a large medical stock (10+ antibiotic strips)", Stores.total(hospital["loot"], "antibiotics") >= 10.0)
	var first: Dictionary = Stores.snapshot(WorldState.building("house_01")["loot"])
	start(10)
	var same: Dictionary = Stores.snapshot(WorldState.building("house_01")["loot"])
	start(11)
	var other: Dictionary = Stores.snapshot(WorldState.building("house_01")["loot"])
	expect("loot is rolled from the seed: same seed, same loot; new seed, new loot", first == same and first != other)


func _check_click_shows_building() -> void:
	start(12)
	var ui_state: UiState = UiState.new()
	var map: MapGrid = MapGrid.new()
	map.ui_state = ui_state
	tree.root.add_child(map)
	map.size = Vector2(640, 640)
	var pharmacy: Dictionary = WorldState.building("pharmacy_01")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(float(pharmacy["x"]) + 0.5, float(pharmacy["y"]) + 0.5) * map.tile_px() + map.map_origin()
	map._gui_input(click)
	expect("clicking a building on the map selects it", ui_state.selected_building == "pharmacy_01", ui_state.selected_building)
	var shown: String = BuildingPanel.describe(WorldState.building(ui_state.selected_building))
	expect("the building panel shows its type and remaining loot",
		shown.contains("Pharmacy") and shown.contains("Antibiotics") and shown.contains("Remaining loot"))
	map.queue_free()


func _check_pharmacy_drains() -> void:
	start(13)
	var pharmacies: Array = WorldState.buildings.filter(func(b: Dictionary) -> bool: return b["type"] == "pharmacy")
	var houses: Array = WorldState.buildings.filter(func(b: Dictionary) -> bool: return b["type"] == "house")
	var start_meds: float = _meds(pharmacies)
	var start_rice: float = _rice(houses)
	var by_day: PackedStringArray = []
	for day: int in 7:
		TickLoop.run_headless(WorldState.TICKS_PER_DAY)
		by_day.append("%d" % roundi(_meds(pharmacies)))
	var share: float = _meds(pharmacies) / start_meds
	expect("pharmacy medicine visibly drains over the first week (to under 45%)", share < 0.45,
		"%d at start, by day: %s (%d%% left)" % [roundi(start_meds), ", ".join(by_day), roundi(share * 100.0)])
	var house_share: float = _rice(houses) / start_rice
	expect("houses drain much more slowly (80-95% left after a week)", house_share > 0.8 and house_share < 0.95,
		"%d%% left" % roundi(house_share * 100.0))


func _check_scavenge_trip_near() -> void:
	start(14)
	var farhan: Dictionary = WorldState.survivor("farhan")
	var shop: Dictionary = WorldState.building("kirana_06")
	shop["locked"] = true
	var shop_food: float = Stores.food_kcal(shop["loot"])
	var home_food: float = Stores.food_kcal(WorldState.stores)
	TickLoop.run_headless(ticks_for_hours(12.0))
	var returned: Array[Dictionary] = events_named(&"scavenge_returned")
	var hours: float = float(returned[0]["payload"]["hours"]) if not returned.is_empty() else -1.0
	expect("a scavenger walks to a nearby shop and back in 2-3 hours", hours >= 2.0 and hours <= 3.0, "%.1f h" % hours)
	expect("forcing the shop's locked door makes noise", not events_named(&"door_forced").is_empty())
	var kg: float = float(returned[0]["payload"]["kg"]) if not returned.is_empty() else 0.0
	expect("they carry home at most 25 kg", kg > 5.0 and kg <= 25.0, "%.1f kg" % kg)
	var taken: float = shop_food - Stores.food_kcal(shop["loot"])
	expect("the food they bring home is taken from the building's finite loot",
		taken > 1000.0 and Stores.food_kcal(WorldState.stores) > home_food, "%d kcal taken" % roundi(taken))
	expect("Farhan is back at base afterwards", farhan["location"] == &"base")


func _check_scavenge_trip_far() -> void:
	start(15)
	var farthest: Dictionary = {}
	var best: float = 0.0
	for b: Dictionary in WorldState.buildings:
		var d: float = Geo.street_distance_m(Geo.base_center_m(), Geo.building_center_m(b))
		if d > best:
			best = d
			farthest = b
	EventBus.emit_event(&"command_set_job", {"survivor": "farhan", "shift": &"day", "job": &"scavenge", "target": farthest["id"]})
	TickLoop.run_headless(ticks_for_hours(12.0))
	var returned: Array[Dictionary] = events_named(&"scavenge_returned")
	var hours: float = float(returned[0]["payload"]["hours"]) if not returned.is_empty() else -1.0
	expect("the farthest building (%s, %.1f km) takes 4-6 hours" % [farthest["name"], best / 1000.0],
		hours >= 4.0 and hours <= 6.0, "%.1f h" % hours)


## Rice left in houses nobody has visited (the base excepted).
func _rice(houses: Array) -> float:
	var sum: float = 0.0
	for b: Dictionary in houses:
		if b["id"] != WorldState.base["building"]:
			sum += Stores.total(b["loot"], "rice")
	return sum


func _meds(pharmacies: Array) -> float:
	var sum: float = 0.0
	for b: Dictionary in pharmacies:
		for item: String in PHARMACY_ITEMS:
			sum += Stores.total(b["loot"], item)
	return sum
