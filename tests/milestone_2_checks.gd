extends "res://tests/checks_base.gd"
## Milestone 2: survivors and needs.

const EXPECTED_NAMES: Array[String] = ["Meera", "Arjun", "Farhan", "Lakshmi", "Ravi"]


func run_checks() -> void:
	_check_roster()
	_check_meals_and_drinking()
	_check_death_from_thirst()
	_check_plenty_of_water()
	_check_fatigue_and_sleep_day()
	_check_night_guard_sleep()
	_check_spoilage()
	_check_heat()


func _check_roster() -> void:
	start(2)
	var names: Array = WorldState.survivors.map(func(s: Dictionary) -> String: return s["name"])
	expect("5 survivors load from data/survivors.json", names == EXPECTED_NAMES, str(names))
	var meera: Dictionary = WorldState.survivor("meera")
	expect("skills and stats come from data (Meera: medicine 8, stress 45)",
		int(meera["skills"]["medicine"]) == 8 and is_equal_approx(float(meera["stress"]), 45.0))
	expect("starting stores come from scenario.json (46 L bottled water, 31,000 kcal food)",
		is_equal_approx(Stores.total(WorldState.stores, "water_bottled"), 46.0)
		and is_equal_approx(Stores.food_kcal(WorldState.stores), 31000.0),
		"%.0f L, %.0f kcal" % [Stores.total(WorldState.stores, "water_bottled"), Stores.food_kcal(WorldState.stores)])


func _check_meals_and_drinking() -> void:
	start(2)
	TickLoop.run_headless(ticks_for_hours(2.0) + 1)  # through the 08:00 meal
	var at_base: Array = WorldState.survivors.filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	var ate: bool = at_base.size() >= 4 and at_base.all(func(s: Dictionary) -> bool: return float(s["kcal_eaten_today"]) > 800.0)
	expect("everyone at base eats about a third of the full ration at 08:00", ate,
		str(WorldState.survivors.map(func(s: Dictionary) -> int: return roundi(float(s["kcal_eaten_today"])))))
	var farhan: Dictionary = WorldState.survivor("farhan")
	TickLoop.run_headless(ticks_for_hours(10.0))
	expect("a scavenger out at mealtime eats the missed meal on return", farhan["location"] == &"base"
		and float(farhan["kcal_eaten_today"]) > 800.0, "%d kcal" % roundi(float(farhan["kcal_eaten_today"])))
	var drank: bool = WorldState.survivors.all(func(s: Dictionary) -> bool: return float(s["drunk_today_l"]) > 0.5 and float(s["water_deficit_l"]) < 1.0)
	expect("survivors drink through the day and stay hydrated while there is water", drank,
		str(WorldState.survivors.map(func(s: Dictionary) -> String: return "%.1f L" % float(s["drunk_today_l"]))))
	expect("bottled water is used up from stores", Stores.total(WorldState.stores, "water_bottled") < 46.0,
		"%.1f L left" % Stores.total(WorldState.stores, "water_bottled"))


func _check_death_from_thirst() -> void:
	start(3)
	_remove_water()
	_set_all_jobs(&"rest", &"rest")
	var deaths: Dictionary = _run_until_all_dead(6)
	var in_range: bool = deaths.size() == 5
	for id: String in deaths:
		var days: float = deaths[id]["days"]
		in_range = in_range and days >= 2.5 and days <= 3.6 and deaths[id]["cause"] == "dehydration"
	expect("with no water, resting survivors die of dehydration on about day 3 (2.5-3.6 days)", in_range, _death_summary(deaths))

	start(3)
	_remove_water()
	_set_all_jobs(&"fortify", &"rest")
	var worker_deaths: Dictionary = _run_until_all_dead(6)
	var earlier: bool = worker_deaths.size() == 5
	for id: String in worker_deaths:
		earlier = earlier and float(worker_deaths[id]["days"]) < float(deaths[id]["days"])
	expect("hard outdoor work in the heat makes it come sooner", earlier, _death_summary(worker_deaths))


func _check_plenty_of_water() -> void:
	start(4)
	_set_all_jobs(&"rest", &"rest")
	Stores.add(WorldState.stores, "water_bottled", 500.0)
	Stores.add(WorldState.stores, "packaged_food", 100000.0)
	TickLoop.run_headless(6 * WorldState.TICKS_PER_DAY)
	var fine: bool = WorldState.survivors.all(func(s: Dictionary) -> bool: return s["status"] == &"ok" and float(s["health"]) > 90.0)
	expect("with enough water and food, everyone is alive and healthy after 6 days", fine,
		str(WorldState.survivors.map(func(s: Dictionary) -> String: return "%s %s %.0f" % [s["name"], s["status"], float(s["health"])])))


func _check_fatigue_and_sleep_day() -> void:
	start(5)
	Stores.add(WorldState.stores, "water_bottled", 100.0)
	var arjun: Dictionary = WorldState.survivor("arjun")
	var start_fatigue: float = float(arjun["fatigue"])
	TickLoop.run_headless(ticks_for_hours(10.0))  # to 16:00, end of the work day
	var after_work: float = float(arjun["fatigue"])
	TickLoop.run_headless(ticks_for_hours(14.0))  # to 06:00 next day
	expect("a day of fortifying raises fatigue by 30+ points by 16:00",
		after_work >= start_fatigue + 30.0, "%.0f -> %.0f" % [start_fatigue, after_work])
	expect("a night's sleep brings fatigue back down by 06:00", float(arjun["fatigue"]) <= 5.0,
		"%.0f at %s" % [float(arjun["fatigue"]), WorldState.clock_string()])
	expect("he slept enough (no sleep debt after the night)", float(arjun["sleep_debt_h"]) == 0.0,
		"debt %.1f h" % float(arjun["sleep_debt_h"]))


func _check_night_guard_sleep() -> void:
	start(5)
	Stores.add(WorldState.stores, "water_bottled", 100.0)
	var ravi: Dictionary = WorldState.survivor("ravi")
	TickLoop.run_headless(WorldState.TICKS_PER_DAY)  # day 0 resting, night 0 on guard
	var debt_after_guard: float = float(ravi["sleep_debt_h"])
	var slept_by_day: int = 0
	for i: int in 72:
		TickLoop.step()
		if ravi["activity"] == &"sleeping":
			slept_by_day += 1
	expect("a night on guard leaves sleep debt", debt_after_guard >= 6.0, "%.1f h" % debt_after_guard)
	expect("the guard sleeps the next day to catch up", slept_by_day >= 6 * 6, "%.1f h asleep" % (slept_by_day / 6.0))


func _check_spoilage() -> void:
	# Nobody to eat it, and no power for the fridge.
	start(6)
	WorldState.survivors.clear()
	WorldState.infrastructure["power_fail_tick"] = 0
	TickLoop.run_headless(5 * WorldState.TICKS_PER_DAY)
	expect("without a fridge, fresh produce spoils within 5 days in April heat", Stores.total(WorldState.stores, "fresh_produce") < 1.0
		and not events_named(&"food_spoiled").is_empty(), "%.0f kcal left" % Stores.total(WorldState.stores, "fresh_produce"))
	expect("rice and dal keep", is_equal_approx(Stores.total(WorldState.stores, "rice"), 10000.0))
	start(6)
	WorldState.survivors.clear()
	WorldState.infrastructure["power_fail_tick"] = 100000
	TickLoop.run_headless(5 * WorldState.TICKS_PER_DAY)
	expect("with the power on, the fridge keeps it 5 days", is_equal_approx(Stores.total(WorldState.stores, "fresh_produce"), 4000.0))


func _check_heat() -> void:
	start(7)
	Stores.add(WorldState.stores, "water_bottled", 100.0)
	_set_all_jobs(&"fortify", &"rest")
	var peak: float = 37.0
	var peak_air: float = 0.0
	for i: int in ticks_for_hours(10.0):
		TickLoop.step()
		peak = maxf(peak, float(WorldState.survivor("arjun")["core_temp_c"]))
		peak_air = maxf(peak_air, float(WorldState.climate["temperature_c"]))
	expect("air temperature peaks in the high 30s °C in mid-April", peak_air > 35.0 and peak_air < 41.0, "%.1f °C" % peak_air)
	expect("outdoor work in the afternoon heat raises core temperature", peak > 37.3, "peak %.2f °C" % peak)


## No water anywhere: stores, taps or the base's own tank. No infected nearby
## either, so thirst is the only thing that can kill them.
func _remove_water() -> void:
	for item: String in ["water_bottled", "water_boiled", "water_untreated"]:
		WorldState.stores.erase(item)
	WorldState.infrastructure["mains_on"] = false
	WorldState.infrastructure["mains_fail_tick"] = 0
	WorldState.building(WorldState.base["building"])["tank_l"] = 0.0
	for zone: Dictionary in WorldState.zones:
		zone["infected"] = 0.0


func _set_all_jobs(day_job: StringName, night_job: StringName) -> void:
	for s: Dictionary in WorldState.survivors:
		EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": &"day", "job": day_job})
		EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": &"night", "job": night_job})


## Runs until everyone is dead or `max_days` pass. id -> {"days", "cause"}.
func _run_until_all_dead(max_days: int) -> Dictionary:
	var deaths: Dictionary = {}
	for i: int in max_days * WorldState.TICKS_PER_DAY:
		TickLoop.step()
		for s: Dictionary in WorldState.survivors:
			if s["status"] == &"dead" and not deaths.has(s["id"]):
				deaths[s["id"]] = {"days": float(WorldState.tick) / WorldState.TICKS_PER_DAY, "cause": s["cause"]}
		if deaths.size() == WorldState.survivors.size():
			break
	return deaths


func _death_summary(deaths: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in deaths:
		parts.append("%s %.2f d (%s)" % [id, float(deaths[id]["days"]), deaths[id]["cause"]])
	return ", ".join(parts)
