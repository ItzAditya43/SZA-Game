extends "res://tests/checks_base.gd"
## Milestone 4: infected, noise and encounters.

const Geo := preload("res://core/geo.gd")
const InfectedSystem := preload("res://systems/infected.gd")
const Decisions := preload("res://core/decisions.gd")

const TRIALS: int = 4000


func run_checks() -> void:
	_check_zones()
	_check_population_curve()
	_check_gunshot()
	_check_quiet_noise()
	_check_activity()
	_check_encounter_rates()
	_check_fight_outcomes()
	_check_turning_time()
	_check_hidden_bite()


func _check_zones() -> void:
	start(20)
	var counts: Array = WorldState.zones.map(func(z: Dictionary) -> int: return roundi(float(z["infected"])))
	expect("16 zones start with 6,000 infected in all", WorldState.zones.size() == 16 and roundi(InfectedSystem.total()) == 6000, str(counts))
	var hospital: int = Geo.zone_index_at(Geo.building_center_m(WorldState.building("hospital_01")))
	var bus_stand: int = Geo.zone_index_at(Vector2(34, 34) * Geo.tile_m())
	var quiet: int = Geo.zone_index_at(Geo.base_center_m())
	expect("they are concentrated at the hospital and the bus stand/market, thin at the base",
		counts[hospital] > 1000 and counts[bus_stand] > 1000 and counts[quiet] < 300,
		"hospital %d, bus stand %d, base zone %d" % [counts[hospital], counts[bus_stand], counts[quiet]])


func _check_population_curve() -> void:
	start(21)
	_set_all_rest()
	var by_day: Dictionary = {}
	for day: int in 31:
		by_day[day] = InfectedSystem.total()
		TickLoop.run_headless(WorldState.TICKS_PER_DAY)
	expect("the outbreak grows to about 12,000 by day 6", absf(float(by_day[6]) - 12000.0) < 600.0, "%d" % roundi(by_day[6]))
	expect("numbers hold until day 15, then die off: day 30 is noticeably emptier (under 85% of day 15)",
		float(by_day[30]) < 0.85 * float(by_day[15]) and float(by_day[15]) > 0.95 * float(by_day[6]),
		"day 15: %d, day 30: %d" % [roundi(by_day[15]), roundi(by_day[30])])


func _check_gunshot() -> void:
	start(22)
	_set_all_rest()
	WorldState.tick = 90  # 21:00, infected fully active
	var target: int = 5
	var before: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	var pos: Vector2 = Geo.zone_center_m(target)
	captured.clear()
	EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": 600.0, "source": &"gunshot"})
	var after: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	var neighbours_lost: bool = true
	for n: int in [1, 4, 6, 9]:
		neighbours_lost = neighbours_lost and float(after[n]) < float(before[n]) * 0.99
	var far_same: bool = is_equal_approx(float(after[15]), float(before[15])) and is_equal_approx(float(after[3]), float(before[3]))
	expect("a gunshot pulls infected out of the neighbouring zones", neighbours_lost,
		"zone %s before/after: %s" % [InfectedSystem.zone_name(1), "%d -> %d" % [roundi(before[1]), roundi(after[1])]])
	expect("...into the zone where it was fired", float(after[target]) > float(before[target]) + 20.0,
		"%d -> %d" % [roundi(before[target]), roundi(after[target])])
	expect("...while zones beyond 600 m are untouched", far_same)
	expect("...and the log says so", not events_named(&"noise_drew_infected").is_empty())


func _check_quiet_noise() -> void:
	start(23)
	var before: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	var pos: Vector2 = Geo.zone_center_m(5)
	EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": 10.0, "source": &"search"})
	var after: Array = WorldState.zones.map(func(z: Dictionary) -> float: return float(z["infected"]))
	expect("quiet searching (10 m) moves no one between zones", before == after)


func _check_activity() -> void:
	start(24)
	var at: Dictionary = {}
	for hour: int in [3, 10, 14, 17]:
		WorldState.tick = posmod(hour * 60 - WorldState.DAY_START_MINUTE, WorldState.MINUTES_PER_DAY) / 10 + WorldState.TICKS_PER_DAY
		WorldState.climate["temperature_c"] = 38.0 if hour == 14 else 30.0
		at[hour] = InfectedSystem.activity()
	expect("infected are most active at night, least in the midday heat",
		float(at[3]) == 1.0 and float(at[14]) < float(at[10]) and float(at[10]) < float(at[17]) and float(at[17]) < float(at[3]),
		"03:00 %.2f, 10:00 %.2f, 14:00 (38 °C) %.2f, 17:00 %.2f" % [at[3], at[10], at[14], at[17]])


func _check_encounter_rates() -> void:
	start(25)
	var system: Object = InfectedSystem.new()
	var zone: int = 10  # bus stand: dense
	var night: int = _count_encounters(system, zone, 90, 30.0)
	var midday: int = _count_encounters(system, zone, 48, 38.0)
	var quiet_zone: int = _count_encounters(system, 0, 90, 30.0)
	expect("encounters are far likelier at night than in the midday heat",
		night > midday * 3, "night %d vs midday %d per %d ticks outside" % [night, midday, TRIALS])
	expect("and far likelier in a dense zone than a quiet one", night > quiet_zone * 3,
		"bus stand %d vs quiet corner %d" % [night, quiet_zone])


func _count_encounters(system: Object, zone: int, at_tick: int, temp: float) -> int:
	WorldState.tick = at_tick
	WorldState.climate["temperature_c"] = temp
	var s: Dictionary = WorldState.survivor("farhan")
	var count: int = 0
	for i: int in TRIALS:
		_reset(s)
		s["exposure"] = {"outdoors": true, "building": "", "noise_m": 15.0, "zone": zone}
		captured.clear()
		system.call("_roll_encounter", s)
		if not events_named(&"encounter").is_empty():
			count += 1
	return count


func _check_fight_outcomes() -> void:
	start(26)
	var system: Object = InfectedSystem.new()
	WorldState.tick = 90
	var strong: Dictionary = _outcomes(system, 8, "rifle")
	var weak: Dictionary = _outcomes(system, 2, "")
	var strong_hurt: int = int(strong.get(&"injured", 0)) + int(strong.get(&"bitten", 0)) + int(strong.get(&"killed", 0))
	var weak_hurt: int = int(weak.get(&"injured", 0)) + int(weak.get(&"bitten", 0)) + int(weak.get(&"killed", 0))
	expect("an armed fighter (combat 8, rifle) gets hurt far less than an unarmed one (combat 2)", strong_hurt * 2 < weak_hurt,
		"armed %s / unarmed %s" % [strong, weak])
	expect("all five outcomes occur: avoided, fought off, injured, bitten, killed",
		weak.has(&"avoided") and weak.has(&"fought_off") and weak.has(&"injured") and weak.has(&"bitten") and weak.has(&"killed"))
	captured.clear()
	var s: Dictionary = WorldState.survivor("ravi")
	_reset(s)
	s["skills"]["scavenging"] = 1
	s["weapon"] = "rifle"
	s["ammo"] = 10
	for i: int in 50:
		system.call("_resolve", s, WorldState.zones[10], 3)
		s["ammo"] = 10
		_reset(s)
	expect("firing a rifle makes a 600 m gunshot", events_named(&"noise").any(
		func(e: Dictionary) -> bool: return e["payload"]["source"] == &"gunshot" and float(e["payload"]["radius_m"]) == 600.0))


func _outcomes(system: Object, combat: int, weapon: String) -> Dictionary:
	var s: Dictionary = WorldState.survivor("arjun")
	var tally: Dictionary = {}
	for i: int in TRIALS:
		_reset(s)
		s["skills"]["combat"] = combat
		s["weapon"] = weapon
		s["ammo"] = 50
		captured.clear()
		system.call("_resolve", s, WorldState.zones[10], 2)
		var outcome: StringName = events_named(&"encounter")[0]["payload"]["outcome"]
		tally[outcome] = int(tally.get(outcome, 0)) + 1
	return tally


func _check_turning_time() -> void:
	var hours: Array[float] = []
	var by_location: Dictionary = {}
	for trial: int in 24:
		start(300 + trial)
		_set_all_rest()
		Stores.add(WorldState.stores, "water_bottled", 300.0)
		var s: Dictionary = WorldState.survivor("arjun")
		var location: String = ["neck", "torso", "arm", "leg"][trial % 4]
		s["injuries"].append(Body.new_injury(&"bite", location, 0.05))
		s["stress"] = 0.0  # tells the group rather than hiding it
		var bitten_at: int = WorldState.tick
		for i: int in 5 * WorldState.TICKS_PER_DAY:
			TickLoop.step()
			for d: Dictionary in WorldState.pending_decisions.duplicate():
				EventBus.emit_event(&"decision_made", {"id": d["id"], "option": &"quarantine"})
			if s["status"] != &"ok":
				break
		var h: float = float(WorldState.tick - bitten_at) / 6.0
		hours.append(h if s["status"] == &"turned" else -1.0)
		if not by_location.has(location):
			by_location[location] = []
		by_location[location].append(h)
	var all_in_range: bool = hours.all(func(h: float) -> bool: return h >= 24.0 and h <= 72.0)
	expect("a bitten survivor turns within 24-72 hours (24 bites)", all_in_range,
		"%.0f-%.0f h" % [hours.min(), hours.max()])
	var mean: Callable = func(xs: Array) -> float: return xs.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / xs.size()
	expect("neck bites turn faster than limb bites", float(mean.call(by_location["neck"])) < float(mean.call(by_location["arm"])),
		"neck %.0f h, torso %.0f h, arm %.0f h, leg %.0f h" % [mean.call(by_location["neck"]), mean.call(by_location["torso"]),
			mean.call(by_location["arm"]), mean.call(by_location["leg"])])


func _check_hidden_bite() -> void:
	var hidden_once: bool = false
	var revealed: bool = false
	for trial: int in 30:
		start(400 + trial)
		_set_all_rest()
		Stores.add(WorldState.stores, "water_bottled", 300.0)
		var s: Dictionary = WorldState.survivor("farhan")
		s["stress"] = 100.0
		s["injuries"].append(Body.new_injury(&"bite", "arm", 0.05))
		TickLoop.step()
		if not s["pathogen"]["hidden"]:
			continue
		hidden_once = true
		expect("a hidden bite shows the group a cut, and asks them nothing",
			Body.visible_wound_type(s["injuries"][0]) == &"cut" and WorldState.pending_decisions.is_empty())
		for i: int in 4 * WorldState.TICKS_PER_DAY:
			TickLoop.step()
			if not events_named(&"hidden_bite_found").is_empty():
				revealed = true
				break
		break
	expect("a very stressed survivor sometimes hides a bite", hidden_once)
	expect("the fever gives a hidden bite away before they turn", revealed)


func _set_all_rest() -> void:
	for s: Dictionary in WorldState.survivors:
		for shift: StringName in [&"day", &"night"]:
			EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": shift, "job": &"rest"})


func _reset(s: Dictionary) -> void:
	s["health"] = 100.0
	s["injuries"] = []
	s["stress"] = 30.0
	s["status"] = &"ok"
	s.erase("death_hint")
