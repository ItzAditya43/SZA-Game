extends "res://tests/checks_base.gd"
## Phase 2, prompt 1: attention and moving, save/load, the survivor pool, map as data, export.

const Geo := preload("res://core/geo.gd")
const SaveGame := preload("res://core/save_game.gd")
const Traits := preload("res://core/traits.gd")
const BaseSystem := preload("res://systems/base.gd")
const Attention := preload("res://systems/attention.gd")

const PROFESSIONS: Array[String] = ["Nurse", "Electrician", "Mechanic", "Farmer", "School teacher", "Cook",
	"Police constable", "Pharmacist", "Auto-rickshaw driver", "College student", "Construction worker", "Retired soldier"]


func run_checks() -> void:
	_check_attention_builds_and_fades()
	_check_attention_drives_attacks()
	_check_continuous_noise_feeds_attention()
	_check_quick_barricade()
	_check_handcart_and_vehicle()
	_check_caches()
	_check_save_load_identical()
	_check_save_versions()
	_check_pool_and_traits()
	_check_rosters()
	_check_map_and_export()


# --- A: attention ---

func _check_attention_builds_and_fades() -> void:
	start(500)
	_quiet()
	var site: String = WorldState.base["building"]
	TickLoop.run_headless(5 * WorldState.TICKS_PER_DAY)
	var built: float = float(WorldState.attention.get(site, 0.0))
	expect("a group staying in one place builds attention (voices, waste, cooking, hammering)", built > 30.0, "%.0f after 5 days" % built)
	EventBus.emit_event(&"command_move_base", {"building": "house_20", "hide_hours": 0.0})
	TickLoop.run_headless(3 * WorldState.TICKS_PER_DAY)
	var left: float = float(WorldState.attention.get(site, 0.0))
	expect("once the group leaves, the old site's attention halves in about 3 days", left > built * 0.35 and left < built * 0.6,
		"%.0f -> %.0f" % [built, left])
	expect("the base panel's level reads low / rising / high", Attention.level(10.0) == &"low"
		and Attention.level(80.0) == &"rising" and Attention.level(200.0) == &"high")


func _check_attention_drives_attacks() -> void:
	var counts: Array[int] = []
	for attention: float in [0.0, 300.0]:
		var attacks: int = 0
		for trial: int in 6:
			start(510 + trial)
			_quiet()
			WorldState.zones[Geo.zone_index_at(Geo.base_center_m())]["infected"] = 800.0
			for night: int in 4:
				WorldState.attention[WorldState.base["building"]] = attention
				TickLoop.run_headless(WorldState.TICKS_PER_DAY)
			attacks += events_named(&"night_attack").size() + events_named(&"base_breached").size()
		counts.append(attacks)
	expect("a base that has drawn attention is attacked far more often than an unknown one", counts[1] > counts[0] * 3,
		"%d attacks at attention 0, %d at 300 (24 nights each)" % [counts[0], counts[1]])


func _check_continuous_noise_feeds_attention() -> void:
	start(520)
	_quiet()
	var before: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	var pos: Vector2 = Geo.base_center_m()
	EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": 150.0, "source": &"generator", "continuous": true})
	var after: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	expect("continuous noise (generator, hammering) no longer yanks infected instantly; it works through attention", before == after)
	var site: String = WorldState.base["building"]
	var att: float = float(WorldState.attention.get(site, 0.0))
	EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": 600.0, "source": &"gunshot"})
	expect("a gunshot at the base adds attention at once", float(WorldState.attention.get(site, 0.0)) > att + 5.0)


# --- A: moving ---

func _check_quick_barricade() -> void:
	start(530)
	_quiet()
	Stores.add(WorldState.stores, "materials", 100.0)
	var building: Dictionary = WorldState.building(WorldState.base["building"])
	var cap: float = float(Data.entry("buildings", String(building["type"]))["max_barricade"])
	EventBus.emit_event(&"command_set_job", {"survivor": "arjun", "shift": &"day", "job": &"quick_fortify"})
	var materials: float = Stores.total(WorldState.stores, "materials")
	TickLoop.run_headless(12 * 6)
	var quick_points: float = float(building["barricade"])
	var used: float = materials - Stores.total(WorldState.stores, "materials")
	expect("quick barricades reach about 40% of the building's cap and stop there", absf(quick_points - 0.4 * cap) < 1.0,
		"%.0f of %.0f" % [quick_points, cap])
	expect("...for about a quarter of the materials a full barricade costs", absf(used - 0.25 * cap) < 1.5, "%.1f materials" % used)


func _check_handcart_and_vehicle() -> void:
	start(540)
	_quiet()
	Stores.add(WorldState.stores, "rice", 600000.0)  # ~167 kg
	EventBus.emit_event(&"command_move_base", {"building": "house_10", "hide_hours": 0.0})
	var on_foot: float = _carried_kg()
	start(540)
	_quiet()
	Stores.add(WorldState.stores, "rice", 600000.0)
	Stores.add(WorldState.stores, "handcart", 1.0)
	EventBus.emit_event(&"command_move_base", {"building": "house_10", "hide_hours": 0.0})
	var with_cart: float = _carried_kg() - 30.0  # the cart itself comes along
	expect("a handcart carries about 150 kg more on a move", absf(with_cart - on_foot - 150.0) < 10.0,
		"%.0f kg on foot, %.0f kg with a cart" % [on_foot, with_cart])
	start(541)
	_quiet()
	Stores.add(WorldState.stores, "vehicle", 1.0)
	Stores.add(WorldState.stores, "fuel", 20.0)
	EventBus.emit_event(&"command_move_base", {"building": "house_20", "hide_hours": 0.0})
	var moved: Dictionary = events_named(&"base_moved")[0]["payload"]
	expect("a vehicle is useless without a driver in the group", not String(moved["text"]).contains("by vehicle"), moved["text"])
	start(542, ["murugan", "meera", "arjun", "lakshmi", "ravi"])
	_quiet()
	Stores.add(WorldState.stores, "vehicle", 1.0)
	Stores.add(WorldState.stores, "fuel", 20.0)
	EventBus.emit_event(&"command_move_base", {"building": "house_20", "hide_hours": 0.0})
	moved = events_named(&"base_moved")[0]["payload"]
	expect("with a driver it moves the group fast and loud, burning fuel", String(moved["text"]).contains("by vehicle")
		and float(moved["noise_m"]) >= 300.0 and Stores.total(WorldState.stores, "fuel") < 20.0 + 1.0)


func _check_caches() -> void:
	start(550)
	_quiet()
	Stores.add(WorldState.stores, "materials", 200.0)  # a tonne: most must be left
	var old: String = WorldState.base["building"]
	var in_the_open: float = Stores.total(WorldState.building(old)["loot"], "materials")
	EventBus.emit_event(&"command_move_base", {"building": "house_10", "hide_hours": 2.0})
	expect("what the group can't carry is hidden in a cache, not left in the open", WorldState.caches.size() == 1
		and is_equal_approx(Stores.total(WorldState.building(old)["loot"], "materials"), in_the_open)
		and Stores.total(WorldState.caches[0]["items"], "materials") > 150.0 and float(WorldState.caches[0]["quality"]) > 0.8)
	var lost: int = 0
	for trial: int in 40:
		start(600 + trial)
		WorldState.caches = [{"id": 1, "building": "pharmacy_01", "items": {"bandages": [{"qty": 5.0, "age_days": 0.0}]}, "quality": 0.0, "tick": 0}]
		WorldState.infrastructure["mains_on"] = true
		TickLoop.run_headless(WorldState.TICKS_PER_DAY * 5)
		lost += 1 if WorldState.caches.is_empty() else 0
	expect("a badly hidden cache at a pharmacy is often found by others within 5 days", lost >= 5 and lost <= 30, "%d of 40 lost" % lost)
	start(560)
	_quiet()
	WorldState.caches = [{"id": 1, "building": "kirana_06", "items": {"antibiotics": [{"qty": 3.0, "age_days": 0.0}]}, "quality": 0.9, "tick": 0}]
	WorldState.building("kirana_06")["loot"] = {}
	EventBus.emit_event(&"command_set_job", {"survivor": "farhan", "shift": &"day", "job": &"scavenge", "target": "kirana_06"})
	TickLoop.run_headless(12 * 6)
	expect("a survivor sent back to the site digs the cache out", WorldState.caches.is_empty()
		and Stores.total(WorldState.stores, "antibiotics") >= 2.0)


# --- B: save and load ---

func _check_save_load_identical() -> void:
	EventBus.event.connect(_answer_first)
	start(570)
	TickLoop.run_headless(_tick_of_day(20))
	var straight: String = SaveGame.state_hash()
	start(570)
	TickLoop.run_headless(_tick_of_day(10))
	var path: String = SaveGame.save("test_day10")
	TickLoop.run_headless(200)  # wander off, then come back
	var problem: String = SaveGame.load_game(path)
	TickLoop.run_headless(_tick_of_day(20) - _tick_of_day(10))
	EventBus.event.disconnect(_answer_first)
	expect("a save at day 10, loaded and run to day 20, matches the uninterrupted run exactly", problem == "" and straight == SaveGame.state_hash(),
		"hashes %s vs %s" % [straight.substr(0, 10), SaveGame.state_hash().substr(0, 10)])
	var listed: Array = SaveGame.list().filter(func(e: Dictionary) -> bool: return e["slot"] == "test_day10")
	expect("the load list shows day, difficulty and survivors alive", not listed.is_empty() and int(listed[0]["day"]) == 10
		and listed[0]["difficulty"] == "normal" and int(listed[0]["alive"]) > 0, str(listed))
	DirAccess.remove_absolute(path)


func _check_save_versions() -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.SAVE_DIR)
	var path: String = SaveGame.SAVE_DIR.path_join("test_old.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 0, "seed": 1}))
	file.close()
	var problem: String = SaveGame.load_game(path)
	expect("an older save version gives a clear message instead of crashing", problem.contains("different version"), problem)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not json at all")
	file.close()
	expect("a damaged file gives a clear message too", SaveGame.load_game(path) != "")
	DirAccess.remove_absolute(path)
	start(580)
	TickLoop.run_headless(WorldState.TICKS_PER_DAY)
	var autosave: String = SaveGame.autosave()
	expect("autosaves rotate through 3 slots", autosave.contains("autosave_%d" % (WorldState.day() % 3)))
	DirAccess.remove_absolute(autosave)


# --- C: survivor pool ---

func _check_pool_and_traits() -> void:
	var pool: Array = Data.table("survivors")
	var jobs: Array = pool.map(func(row: Dictionary) -> String: return row["profession"])
	jobs.sort()
	var expected: Array = PROFESSIONS.duplicate()
	expected.sort()
	expect("the pool has 12 survivors, one per pre-outbreak job in the brief", pool.size() == 12 and jobs == expected, str(jobs))
	var known: Array = Data.table("traits").map(func(t: Dictionary) -> String: return t["id"])
	expect("everyone has 1-2 traits, all defined in data/traits.json", pool.all(func(row: Dictionary) -> bool:
		return row["traits"].size() >= 1 and row["traits"].size() <= 2 and row["traits"].all(func(t: String) -> bool: return known.has(t))))
	start(590, ["raju", "imran", "selvi", "thomas", "divya"])
	var raju: Dictionary = WorldState.survivor("raju")
	var imran: Dictionary = WorldState.survivor("imran")
	expect("traits change what people can do: a strong back carries 30% more", is_equal_approx(Traits.mult(raju, "carry_kg_mult"), 1.3))
	expect("a squeamish pharmacist treats wounds as if 3 points less skilled", is_equal_approx(Body.skill(imran, "medicine"), 3.0))
	start(591, ["farhan", "meera", "arjun", "lakshmi", "ravi"])
	_quiet()
	WorldState.stores.erase("cigarettes")
	var farhan: Dictionary = WorldState.survivor("farhan")
	var meera: Dictionary = WorldState.survivor("meera")
	TickLoop.run_headless(2 * WorldState.TICKS_PER_DAY)
	expect("a smoker without cigarettes gets more stressed than a non-smoker", farhan["craving"]
		and float(farhan["stress"]) - 62.0 > float(meera["stress"]) - 45.0 + 5.0,
		"Farhan %.0f (from 62), Meera %.0f (from 45)" % [float(farhan["stress"]), float(meera["stress"])])


func _check_rosters() -> void:
	start(600)
	expect("the default roster is the original five", WorldState.survivors.map(func(s: Dictionary) -> String: return s["id"])
		== ["meera", "arjun", "farhan", "lakshmi", "ravi"])
	start(601, ["random"])
	var first: Array = WorldState.survivors.map(func(s: Dictionary) -> String: return s["id"])
	start(601, ["random"])
	var again: Array = WorldState.survivors.map(func(s: Dictionary) -> String: return s["id"])
	start(602, ["random"])
	var other: Array = WorldState.survivors.map(func(s: Dictionary) -> String: return s["id"])
	expect("Random 5 picks five from the pool, the same five for the same seed", first.size() == 5 and first == again and first != other,
		"%s / %s" % [first, other])


# --- D: map and export ---

func _check_map_and_export() -> void:
	var layout: Dictionary = Data.table("town_layout")
	expect("the town is hand-authored data (data/town_layout.json), with no generator script",
		layout["buildings"].size() == 50 and not FileAccess.file_exists("res://tools/make_town.py"))
	var presets: ConfigFile = ConfigFile.new()
	var loaded: Error = presets.load("res://export_presets.cfg")
	var names: Array = []
	for section: String in presets.get_sections():
		if presets.has_section_key(section, "name"):
			names.append(presets.get_value(section, "name"))
	expect("export presets exist for Linux and Windows and ship the JSON data", loaded == OK and names.has("Linux")
		and names.has("Windows Desktop") and String(presets.get_value("preset.0", "include_filter")).contains("json"), str(names))


# --- Helpers ---

func start(run_seed: int, roster: Array = []) -> void:
	SimRun.start(run_seed, "normal", roster)
	WorldState.flags["sandbox"] = true
	captured.clear()


## No scavenging, no infected nearby: the base on its own.
func _quiet() -> void:
	for s: Dictionary in WorldState.survivors:
		for shift: StringName in [&"day", &"night"]:
			EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": shift, "job": &"rest"})
	Stores.add(WorldState.stores, "water_bottled", 300.0)
	Stores.add(WorldState.stores, "packaged_food", 100000.0)


func _carried_kg() -> float:
	var kg: float = 0.0
	for s: Dictionary in WorldState.survivors:
		for item: String in Stores.snapshot(s["carried"]):
			kg += Stores.weight_kg(item, Stores.total(s["carried"], item))
	return kg


@warning_ignore("integer_division")
func _tick_of_day(day: int) -> int:
	return (day * WorldState.MINUTES_PER_DAY - WorldState.DAY_START_MINUTE) / WorldState.MINUTES_PER_TICK


## Scripted, deterministic answers: always the first option.
func _answer_first(event_name: StringName, payload: Dictionary) -> void:
	if event_name != &"decision_needed":
		return
	for d: Dictionary in WorldState.pending_decisions:
		if int(d["id"]) == int(payload["id"]):
			EventBus.emit_event(&"decision_made", {"id": d["id"], "option": d["options"][0]["id"]})
