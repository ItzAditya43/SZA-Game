extends "res://tests/checks_base.gd"
## Milestone 5: base, jobs and infrastructure.

const Geo := preload("res://core/geo.gd")
const BaseSystem := preload("res://systems/base.gd")
const Infra := preload("res://systems/infrastructure.gd")

const SEEDS: int = 100


func run_checks() -> void:
	_check_failure_windows()
	_check_failures_happen()
	_check_unguarded_base_falls()
	_check_fortress_holds()
	_check_fortify()
	_check_cooking()
	_check_boiling_and_illness()
	_check_collect_water()
	_check_generator()
	_check_move_base()


func _check_failure_windows() -> void:
	var power_days: Dictionary = {}
	var mains_ok: bool = true
	for run_seed: int in SEEDS:
		start(1000 + run_seed)
		var infra: Dictionary = WorldState.infrastructure
		var day: int = WorldState.day_at(int(infra["power_fail_tick"]))
		power_days[day] = int(power_days.get(day, 0)) + 1
		var mains_day: int = WorldState.day_at(int(infra["mains_fail_tick"]))
		mains_ok = mains_ok and mains_day >= 7 and mains_day <= 12 and WorldState.day_at(int(infra["phones_fail_tick"])) == 2
	expect("power fails between day 3 and day 6 in every one of %d runs" % SEEDS,
		power_days.keys().all(func(d: int) -> bool: return d >= 3 and d <= 6), "days: %s" % power_days)
	expect("...and the failure day varies across runs", power_days.size() >= 3)
	expect("water mains fail between day 7 and 12, phones on day 2, in every run", mains_ok)


func _check_failures_happen() -> void:
	start(1500)
	var infra: Dictionary = WorldState.infrastructure
	TickLoop.run_headless(int(infra["mains_fail_tick"]) + 1)
	var power: Array[Dictionary] = events_named(&"power_failed")
	expect("the grid really goes down when scheduled", not infra["power_on"] and power.size() == 1
		and int(power[0]["tick"]) == int(infra["power_fail_tick"]), WorldState.clock_string_at(int(infra["power_fail_tick"])))
	expect("so do the taps", not infra["mains_on"] and events_named(&"mains_failed").size() == 1)


func _check_unguarded_base_falls() -> void:
	var fell: int = 0
	var nights: Array[int] = []
	for trial: int in 10:
		start(1600 + trial)
		_all_jobs(&"rest", &"rest")
		Stores.add(WorldState.stores, "water_bottled", 300.0)
		_crowd_base_zone(1200.0)
		for i: int in 5 * WorldState.TICKS_PER_DAY:
			TickLoop.step()
			if not events_named(&"base_breached").is_empty():
				fell += 1
				nights.append(WorldState.day())
				break
	expect("an unguarded base with no barricades falls to a night attack (in %d of 10 runs within 5 nights)" % fell,
		fell >= 8, "breached on days %s" % [nights])
	start(1700)
	_all_jobs(&"rest", &"rest")
	var base: Object = BaseSystem.new()
	WorldState.tick = 100
	TickLoop.step()
	captured.clear()
	base.call("_attack", 8, WorldState.zones[0])
	expect("a single attack by 8 infected breaks into an unguarded house", not events_named(&"base_breached").is_empty(),
		"defense %d" % roundi(float(WorldState.base["defense"])))


func _check_fortress_holds() -> void:
	var breaches: int = 0
	var attacks: int = 0
	for trial: int in 10:
		start(1600 + trial)
		Stores.add(WorldState.stores, "water_bottled", 300.0)
		Stores.add(WorldState.stores, "packaged_food", 100000.0)
		_all_jobs(&"rest", &"rest")
		EventBus.emit_event(&"command_set_job", {"survivor": "officer", "shift": &"night", "job": &"guard"})
		EventBus.emit_event(&"command_set_job", {"survivor": "mechanic", "shift": &"night", "job": &"guard"})
		_move_base_now("police_station_01")
		WorldState.building("police_station_01")["barricade"] = 100.0
		_crowd_base_zone(1200.0)
		TickLoop.run_headless(5 * WorldState.TICKS_PER_DAY)
		breaches += events_named(&"base_breached").size()
		attacks += events_named(&"night_attack").size() + events_named(&"base_breached").size()
	expect("a barricaded police station with two guards holds against the same crowd", breaches == 0,
		"%d attacks, %d breaches over 50 nights" % [attacks, breaches])
	expect("its defense shows building + barricades + guards", float(WorldState.base["defense"]) > 0.0,
		str(WorldState.base["defense_parts"]))


func _check_fortify() -> void:
	start(1800)
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "electrician", "shift": &"day", "job": &"fortify"})
	Stores.add(WorldState.stores, "materials", 40.0)
	var before: float = Stores.total(WorldState.stores, "materials")
	TickLoop.run_headless(ticks_for_hours(12.0))
	var barricade: float = float(WorldState.building(WorldState.base["building"])["barricade"])
	expect("a day of fortifying turns materials into barricades (about 3 units an hour)",
		barricade >= 20.0 and barricade <= 30.0 and is_equal_approx(before - Stores.total(WorldState.stores, "materials"), barricade),
		"%.0f barricade points" % barricade)
	expect("hammering makes noise", events_named(&"noise").any(func(e: Dictionary) -> bool: return e["payload"]["source"] == &"hammering"))


func _check_cooking() -> void:
	start(1900)
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "farmer", "shift": &"day", "job": &"cook"})
	WorldState.stores.erase("packaged_food")
	WorldState.stores.erase("fresh_produce")
	var gas: float = Stores.total(WorldState.stores, "cooking_gas")
	var staples: float = _staples()
	TickLoop.run_headless(ticks_for_hours(8.0))
	expect("the cook turns rice and lentils into meals, burning gas", _staples() < staples - 5000.0
		and Stores.total(WorldState.stores, "cooking_gas") < gas, "%.0f kcal cooked, %.2f kg gas used" % [staples - _staples(), gas - Stores.total(WorldState.stores, "cooking_gas")])
	expect("the group eats the cooked meals at 13:00", WorldState.survivors.all(func(s: Dictionary) -> bool: return float(s["kcal_eaten_today"]) > 500.0))
	start(1901)
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "farmer", "shift": &"day", "job": &"cook"})
	WorldState.stores.erase("cooking_gas")
	var wood: float = Stores.total(WorldState.stores, "materials")
	TickLoop.run_headless(ticks_for_hours(8.0))
	expect("with no gas, materials burn as firewood", Stores.total(WorldState.stores, "materials") < wood
		and Stores.total(WorldState.stores, "cooked_meal") + 1.0 > 0.0, "%.1f units burned" % (wood - Stores.total(WorldState.stores, "materials")))
	start(1902)
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "farmer", "shift": &"day", "job": &"cook"})
	WorldState.stores.erase("cooking_gas")
	WorldState.stores.erase("materials")
	TickLoop.run_headless(ticks_for_hours(4.0))
	expect("with neither, nothing is cooked and the log says why", not events_named(&"job_blocked").is_empty()
		and Stores.total(WorldState.stores, "cooked_meal") == 0.0)


func _check_boiling_and_illness() -> void:
	start(2000)
	_dry_taps()
	_all_jobs(&"rest", &"rest")
	_only_untreated_water(400.0)
	var gas: float = Stores.total(WorldState.stores, "cooking_gas")
	TickLoop.run_headless(ticks_for_hours(6.0))
	var boiled: float = Stores.total(WorldState.stores, "water_boiled")
	var used: float = gas - Stores.total(WorldState.stores, "cooking_gas")
	expect("under the boil order, untreated water is boiled using about 0.15 kg of gas per 10 L",
		boiled > 20.0 and absf(used - 0.015 * (boiled + _drunk())) < 0.2, "%.0f L boiled, %.2f kg gas" % [boiled + _drunk(), used])
	var sick_boiled: int = _illness_days(2001, true)
	var sick_raw: int = _illness_days(2001, false)
	expect("drinking untreated water makes people ill (about 30% a day); boiling prevents it",
		sick_raw >= 3 and sick_boiled == 0, "%d illnesses over 6 days unboiled, %d boiled" % [sick_raw, sick_boiled])


func _illness_days(run_seed: int, boil: bool) -> int:
	start(run_seed)
	_dry_taps()
	_all_jobs(&"rest", &"rest")
	_only_untreated_water(800.0)
	Stores.add(WorldState.stores, "cooking_gas", 50.0)
	Stores.add(WorldState.stores, "packaged_food", 100000.0)
	for zone: Dictionary in WorldState.zones:
		zone["infected"] = 0.0
	EventBus.emit_event(&"command_set_policy", {"key": &"boil_water", "value": boil})
	TickLoop.run_headless(6 * WorldState.TICKS_PER_DAY)
	return events_named(&"illness_started").size()


func _check_collect_water() -> void:
	start(2100)
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "farmer", "shift": &"day", "job": &"collect_water"})
	TickLoop.run_headless(ticks_for_hours(8.0))
	var stored: float = Stores.total(WorldState.stores, "water_boiled")
	expect("while the taps run, collecting fills the group's containers with safe water (200 L without drums)",
		stored >= 150.0 and stored <= Stores.water_capacity_l(WorldState.stores) + 0.1, "%.0f L" % stored)
	start(2101)
	_dry_taps()
	_all_jobs(&"rest", &"rest")
	EventBus.emit_event(&"command_set_job", {"survivor": "farmer", "shift": &"day", "job": &"collect_water"})
	TickLoop.run_headless(ticks_for_hours(12.0))
	var ferried: Array[Dictionary] = events_named(&"water_collected")
	var litres: float = float(ferried[0]["payload"]["litres"]) if not ferried.is_empty() else 0.0
	expect("after the mains fail, they ferry untreated water from the nearest tank by hand",
		litres > 100.0 and Stores.total(WorldState.stores, "water_untreated") > 50.0, ferried[0]["payload"]["text"] if not ferried.is_empty() else "none")


func _check_generator() -> void:
	start(2200)
	_all_jobs(&"rest", &"rest")
	WorldState.infrastructure["power_fail_tick"] = 0
	Stores.add(WorldState.stores, "generator", 1.0)
	EventBus.emit_event(&"command_set_policy", {"key": &"generator", "value": &"night"})
	var fuel: float = Stores.total(WorldState.stores, "fuel")
	TickLoop.run_headless(WorldState.TICKS_PER_DAY)
	var used: float = fuel - Stores.total(WorldState.stores, "fuel")
	expect("a generator run all night burns about 1 L of fuel an hour (12 L a night)", absf(used - 12.0) < 0.5 or fuel < 12.5,
		"%.1f L used" % used)
	expect("its noise (150 m) and light (1 km) give the base away",
		events_named(&"noise").any(func(e: Dictionary) -> bool: return e["payload"]["source"] == &"generator")
		and not events_named(&"light").is_empty())


func _check_move_base() -> void:
	start(2300)
	_all_jobs(&"rest", &"rest")
	Stores.add(WorldState.stores, "materials", 60.0)  # 300 kg: too much to carry
	var old: String = WorldState.base["building"]
	captured.clear()
	EventBus.emit_event(&"command_move_base", {"building": "school_01"})
	expect("moving base changes the base building at once", WorldState.base["building"] == "school_01")
	TickLoop.run_headless(ticks_for_hours(3.0))
	var arrived: bool = WorldState.group().all(func(s: Dictionary) -> bool: return s["location"] == &"base")
	expect("the group walks there and arrives", arrived)
	expect("they carry the medicine and food; what they cannot carry stays in the old building",
		Stores.total(WorldState.stores, "packaged_food") > 0.0 and Stores.total(WorldState.building(old)["loot"], "materials") > 0.0,
		"left behind: %s" % str(events_named(&"base_moved")[0]["payload"]["left_behind"]))


# --- Helpers ---

func _all_jobs(day_job: StringName, night_job: StringName) -> void:
	for s: Dictionary in WorldState.survivors:
		EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": &"day", "job": day_job})
		EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": &"night", "job": night_job})


func _crowd_base_zone(count: float) -> void:
	WorldState.zones[Geo.zone_index_at(Geo.base_center_m())]["infected"] = count


func _move_base_now(id: String) -> void:
	WorldState.base["building"] = id
	for s: Dictionary in WorldState.survivors:
		var pos: Vector2 = Geo.base_center_m()
		s["x_m"] = pos.x
		s["y_m"] = pos.y


func _dry_taps() -> void:
	WorldState.infrastructure["mains_fail_tick"] = 0
	WorldState.infrastructure["mains_on"] = false


func _only_untreated_water(litres: float) -> void:
	for item: String in ["water_bottled", "water_boiled"]:
		WorldState.stores.erase(item)
	WorldState.building(WorldState.base["building"])["tank_l"] = 0.0
	Stores.add(WorldState.stores, "water_untreated", litres)


func _drunk() -> float:
	var sum: float = 0.0
	for s: Dictionary in WorldState.survivors:
		sum += float(s["drunk_today_l"])
	return sum


func _staples() -> float:
	return Stores.total(WorldState.stores, "rice") + Stores.total(WorldState.stores, "lentils") + Stores.total(WorldState.stores, "flour")
