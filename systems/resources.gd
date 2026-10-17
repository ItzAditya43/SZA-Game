extends "res://core/sim_system.gd"
## Resources: the group's stores and what flows in and out of them. Survivors at
## base drink through the day and eat at meal times, under the player's rationing
## orders; perishable food ages faster in the heat and spoils. Player orders
## arrive as `command_set_policy` {"key", "value"} on the bus.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")

const TICK_DAYS: float = 1.0 / 144.0

## Daily food per person under each ration order, in kcal.
const FOOD_RATIONS: Dictionary = {&"full": 2500.0, &"reduced": 1800.0, &"half": 1200.0, &"minimal": 600.0}
## Daily drinking water per person under each ration order, in litres.
const WATER_RATIONS: Dictionary = {&"as_needed": INF, &"4L": 4.0, &"3L": 3.0, &"2L": 2.0, &"1L": 1.0}
const POLICY_VALUES: Dictionary = {
	&"food_ration": [&"full", &"reduced", &"half", &"minimal"],
	&"water_ration": [&"as_needed", &"4L", &"3L", &"2L", &"1L"],
	&"boil_water": [true, false],
	&"generator": [&"off", &"evening", &"night"],
	&"use_guns": [false, true],
}
const DEFAULT_POLICIES: Dictionary = {
	&"food_ration": &"full", &"water_ration": &"as_needed", &"boil_water": true,
	&"generator": &"off", &"use_guns": false,
}

const MEAL_MINUTES: Array[int] = [8 * 60, 13 * 60, 20 * 60]
## Eaten first to last. Raw staples (rice, dal, atta) must be cooked first.
const EATING_ORDER: Array[String] = ["cooked_meal", "fresh_produce", "packaged_food"]
## A hot cooked meal eases stress; dry packaged food does not.
const COOKED_MEAL_STRESS_RELIEF: float = 2.0
## Survivors drink when they are this far behind, a few sips at a time.
const DRINK_AT_DEFICIT_L: float = 0.25
## Untreated water is drunk only this thirsty, unless boiling is switched off.
const DESPERATE_DEFICIT_L: float = 2.0
const SAFE_WATER_ORDER: Array[String] = ["water_boiled", "water_bottled"]
## A day counts as fully rationed when everyone ate at least this share of the full ration.
const FULL_RATION_SHARE: float = 0.9
## Stores sit indoors, out of the sun.
const STORE_SHADE_C: float = 3.0


func setup() -> void:
	listen(&"command_set_policy", _on_set_policy)
	WorldState.policies = DEFAULT_POLICIES.duplicate()
	WorldState.stats["full_ration_days"] = 0
	var start: Dictionary = Data.table("scenario")["start_stores"]
	for item: String in start:
		Stores.add(WorldState.stores, item, float(start[item]))


func tick() -> void:
	var minute: int = WorldState.minute_of_day()
	if WorldState.tick % WorldState.TICKS_PER_DAY == 0 and WorldState.tick > 0:
		_close_day()
	_spoil()
	var meal_time: bool = MEAL_MINUTES.has(minute)
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok":
			continue
		if s["location"] != &"base":
			if meal_time:
				s["meals_missed"] = int(s["meals_missed"]) + 1
			continue
		_drink(s)
		if meal_time:
			_eat(s, 1)
		elif int(s["meals_missed"]) > 0:
			_eat(s, mini(int(s["meals_missed"]), 2))
			s["meals_missed"] = 0


func _drink(s: Dictionary) -> void:
	var deficit: float = float(s["water_deficit_l"])
	if deficit < DRINK_AT_DEFICIT_L:
		return
	var allowance: float = float(WATER_RATIONS[WorldState.policies[&"water_ration"]]) - float(s["drunk_today_l"])
	var wanted: float = minf(deficit, allowance)
	if wanted <= 0.0:
		return
	var drunk: float = 0.0
	if WorldState.infrastructure.get("mains_on", false):
		drunk = wanted
	else:
		for item: String in SAFE_WATER_ORDER:
			drunk += Stores.take(WorldState.stores, item, wanted - drunk)
		var boiling: bool = WorldState.policies[&"boil_water"]
		if drunk < wanted and (not boiling or deficit >= DESPERATE_DEFICIT_L):
			var untreated: float = Stores.take(WorldState.stores, "water_untreated", wanted - drunk)
			if untreated > 0.0:
				s["drank_untreated_today"] = true
				drunk += untreated
	s["water_deficit_l"] = deficit - drunk
	s["drunk_today_l"] = float(s["drunk_today_l"]) + drunk


func _eat(s: Dictionary, meals: int) -> void:
	var wanted: float = float(FOOD_RATIONS[WorldState.policies[&"food_ration"]]) / float(MEAL_MINUTES.size()) * meals
	var eaten: float = 0.0
	for item: String in EATING_ORDER:
		var got: float = Stores.take(WorldState.stores, item, wanted - eaten)
		if got > 0.0 and item == "cooked_meal":
			s["stress"] = maxf(0.0, float(s["stress"]) - COOKED_MEAL_STRESS_RELIEF * got / (wanted / meals))
		eaten += got
		if eaten >= wanted - Stores.EPSILON:
			break
	s["kcal_debt"] = maxf(0.0, float(s["kcal_debt"]) - eaten)
	s["kcal_eaten_today"] = float(s["kcal_eaten_today"]) + eaten


func _spoil() -> void:
	var temp: float = float(WorldState.climate.get("temperature_c", 30.0)) - STORE_SHADE_C
	var spoiled: Dictionary = Stores.age_and_spoil(WorldState.stores, TICK_DAYS, temp)
	for item: String in spoiled:
		var row: Dictionary = Data.entry("items", item)
		EventBus.emit_event(&"food_spoiled", {"item": item, "qty": spoiled[item],
			"text": "%s spoiled in the heat (%s %s lost)." % [row["name"], _fmt(float(spoiled[item])), row["unit"]]})


## At 06:00: score yesterday's rations, then reset the daily intake counters.
func _close_day() -> void:
	var group: Array = WorldState.group()
	var full: float = float(FOOD_RATIONS[&"full"]) * FULL_RATION_SHARE
	if not group.is_empty() and group.all(func(s: Dictionary) -> bool: return float(s["kcal_eaten_today"]) >= full):
		WorldState.stats["full_ration_days"] = int(WorldState.stats["full_ration_days"]) + 1
	for s: Dictionary in WorldState.survivors:
		s["drunk_today_l"] = 0.0
		s["kcal_eaten_today"] = 0.0


func _on_set_policy(payload: Dictionary) -> void:
	var key: StringName = StringName(payload["key"])
	var value: Variant = payload["value"]
	if value is String:
		value = StringName(value)
	if not POLICY_VALUES.has(key) or not POLICY_VALUES[key].has(value):
		push_error("Resources: bad command_set_policy %s" % payload)
		return
	WorldState.policies[key] = value
	EventBus.emit_event(&"policy_changed", {"key": key, "value": value})


static func _fmt(qty: float) -> String:
	return str(snappedf(qty, 0.1)) if qty < 100.0 else str(roundi(qty))
