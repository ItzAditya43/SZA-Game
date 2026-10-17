extends "res://core/sim_system.gd"
## Resources: the group's stores and what flows in and out of them. Survivors at
## base drink through the day and eat at meal times, under the player's rationing
## orders; perishable food ages faster in the heat and spoils. Player orders
## arrive as `command_set_policy` {"key", "value"} on the bus.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Difficulty := preload("res://core/difficulty.gd")

const TICK_DAYS: float = 1.0 / 144.0

## Most a person eats in a day under each ration order, in kcal. Full covers hard
## physical work (3,000-3,500 kcal); people eat only what their body is short of.
const FOOD_RATIONS: Dictionary = {&"full": 3000.0, &"reduced": 2000.0, &"half": 1500.0, &"minimal": 800.0}
## Eat up to this much beyond today's shortfall, so nobody starts the day empty.
const MEAL_HEADROOM_KCAL: float = 500.0
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
## A day counts as fully rationed when the order was "full" and nobody went to bed hungry.
const FULL_RATION_MAX_DEBT_KCAL: float = 2000.0
## Stores sit indoors, out of the sun.
const STORE_SHADE_C: float = 3.0
## Smaller losses spoil quietly.
const SPOILAGE_REPORT_KG: float = 1.0
## A fridge runs while there is power or the generator is on.
const FRIDGE_C: float = 8.0

# --- Cooking (the cook job) ---
const COOK_KCAL_PER_HOUR: float = 6000.0
## Per 1,000 kcal of rice/dal/atta: about 0.55 L of water and 0.1 kg of LPG per kg cooked.
const COOK_WATER_L_PER_1000_KCAL: float = 0.6
const COOK_GAS_KG_PER_1000_KCAL: float = 0.03
## Without gas, materials burn as firewood.
const COOK_WOOD_PER_1000_KCAL: float = 0.3
## Cooked meals keep a day, so cook no more than a day ahead.
const COOKED_STOCK_DAYS: float = 1.0
## Atta first: it keeps least well.
const STAPLES: Array[String] = ["atta", "rice", "dal"]

# --- Boiling (the boil_water order) ---
const BOIL_L_PER_HOUR: float = 40.0
## Boiling 10 L takes about 0.15 kg of LPG, or one unit of materials burned as firewood
## (the spec's "1 unit of fuel per 10 litres").
const BOIL_GAS_KG_PER_10L: float = 0.15
const BOIL_WOOD_PER_10L: float = 1.0
## Keep this much safe drinking water per person boiled ahead.
const SAFE_WATER_TARGET_L: float = 6.0


func setup() -> void:
	listen(&"command_set_policy", _on_set_policy)
	WorldState.policies = DEFAULT_POLICIES.duplicate()
	WorldState.stats["full_ration_days"] = 0
	var start: Dictionary = Data.table("scenario")["start_stores"]
	for item: String in start:
		var qty: float = float(start[item]) * Difficulty.mult("start_stores")
		if String(Data.entry("items", item).get("unit", "")) in ["count", "rounds", "units"]:
			qty = float(roundi(qty))
		Stores.add(WorldState.stores, item, qty)


func tick() -> void:
	var minute: int = WorldState.minute_of_day()
	if WorldState.is_new_day():
		_close_day()
	_spoil()
	_cook()
	if WorldState.tick % 6 == 0:
		_boil()
	var meal_time: bool = MEAL_MINUTES.has(minute)
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok":
			continue
		if s["location"] != &"base":
			if meal_time:
				s["meals_missed"] = int(s["meals_missed"]) + 1
			_drink_on_trip(s)
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
			var untreated: float = _take_untreated(wanted - drunk)
			if untreated > 0.0:
				s["drank_untreated_today"] = true
				drunk += untreated
	s["water_deficit_l"] = deficit - drunk
	s["drunk_today_l"] = float(s["drunk_today_l"]) + drunk


## Away from base, survivors sip from the bottle they carried out.
func _drink_on_trip(s: Dictionary) -> void:
	var deficit: float = float(s["water_deficit_l"])
	if deficit < DRINK_AT_DEFICIT_L * 2.0:
		return
	var drunk: float = 0.0
	for item: String in SAFE_WATER_ORDER:
		drunk += Stores.take(s["carried"], item, deficit - drunk)
	s["water_deficit_l"] = deficit - drunk
	s["drunk_today_l"] = float(s["drunk_today_l"]) + drunk


func _eat(s: Dictionary, meals: int) -> void:
	var allowance: float = float(FOOD_RATIONS[WorldState.policies[&"food_ration"]]) / float(MEAL_MINUTES.size()) * meals
	var wanted: float = minf(allowance, float(s["kcal_debt"]) + MEAL_HEADROOM_KCAL)
	if wanted <= 0.0:
		return
	var eaten: float = 0.0
	for item: String in EATING_ORDER:
		var got: float = Stores.take(WorldState.stores, item, wanted - eaten)
		if got > 0.0 and item == "cooked_meal":
			s["stress"] = maxf(0.0, float(s["stress"]) - COOKED_MEAL_STRESS_RELIEF * minf(1.0, got / (allowance / meals)))
		eaten += got
		if eaten >= wanted - Stores.EPSILON:
			break
	s["kcal_debt"] = maxf(0.0, float(s["kcal_debt"]) - eaten)
	s["kcal_eaten_today"] = float(s["kcal_eaten_today"]) + eaten


## Untreated water: stored first, then the base building's own tank.
func _take_untreated(litres: float) -> float:
	var got: float = Stores.take(WorldState.stores, "water_untreated", litres)
	var tank: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	if got < litres and not tank.is_empty() and not WorldState.infrastructure.get("mains_on", false):
		var from_tank: float = minf(litres - got, float(tank["tank_l"]))
		tank["tank_l"] = float(tank["tank_l"]) - from_tank
		got += from_tank
	return got


## Stored water plus the base tank, all needing boiling.
func _untreated_available() -> float:
	var tank: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	var in_tank: float = 0.0 if tank.is_empty() or WorldState.infrastructure.get("mains_on", false) else float(tank["tank_l"])
	return Stores.total(WorldState.stores, "water_untreated") + in_tank


## Takes fuel for a fire: LPG by the kg first, then materials as firewood.
## Returns the share of the job the fuel covers (0..1).
func _burn(gas_kg: float, wood_units: float) -> float:
	var gas: float = Stores.take(WorldState.stores, "cooking_gas", gas_kg)
	var share: float = gas / gas_kg if gas_kg > 0.0 else 1.0
	if share < 1.0:
		var wood: float = Stores.take(WorldState.stores, "materials", wood_units * (1.0 - share))
		share += wood / wood_units if wood_units > 0.0 else 0.0
	return clampf(share, 0.0, 1.0)


@warning_ignore("integer_division")
func _cook() -> void:
	var group_size: int = WorldState.group().size()
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base" or s["job_now"] != &"cook" or s["activity"] != &"light_work":
			continue
		var target: float = FOOD_RATIONS[&"full"] * group_size * COOKED_STOCK_DAYS - Stores.total(WorldState.stores, "cooked_meal")
		var kcal: float = minf(COOK_KCAL_PER_HOUR * Body.work_speed(s) / 6.0, target)
		var staples: float = 0.0
		for item: String in STAPLES:
			staples += Stores.total(WorldState.stores, item)
		kcal = minf(kcal, staples)
		if kcal <= 1.0:
			continue
		var water_needed: float = kcal / 1000.0 * COOK_WATER_L_PER_1000_KCAL
		var water: float = _take_untreated(water_needed)
		for item: String in ["water_boiled", "water_bottled"]:
			water += Stores.take(WorldState.stores, item, water_needed - water)
		kcal *= water / water_needed
		var fuel_share: float = _burn(kcal / 1000.0 * COOK_GAS_KG_PER_1000_KCAL, kcal / 1000.0 * COOK_WOOD_PER_1000_KCAL)
		kcal *= fuel_share
		if kcal <= 1.0:
			if int(s.get("cook_warned_shift", -1)) != WorldState.tick / 72:
				s["cook_warned_shift"] = WorldState.tick / 72
				EventBus.emit_event(&"job_blocked", {"survivor": s["id"],
					"text": "%s can't cook: no %s." % [s["name"], "water" if water < water_needed * 0.1 else "gas or firewood"]})
			continue
		var cooked: float = 0.0
		for item: String in STAPLES:
			cooked += Stores.take(WorldState.stores, item, kcal - cooked)
		Stores.add(WorldState.stores, "cooked_meal", cooked)


## Hourly, under the boil order, anyone awake at base boils water ahead of need.
func _boil() -> void:
	if not WorldState.policies[&"boil_water"]:
		return
	var awake: bool = WorldState.group().any(func(s: Dictionary) -> bool: return s["location"] == &"base" and not s["asleep"])
	if not awake:
		return
	var target: float = SAFE_WATER_TARGET_L * WorldState.group().size() - Stores.total(WorldState.stores, "water_boiled")
	var stored_untreated: float = Stores.total(WorldState.stores, "water_untreated")
	var room: float = Stores.water_capacity_l(WorldState.stores) - Stores.stored_water_l(WorldState.stores) + stored_untreated
	var litres: float = minf(minf(BOIL_L_PER_HOUR, target), minf(_untreated_available(), room))
	if litres <= 0.5:
		return
	litres *= _burn(litres / 10.0 * BOIL_GAS_KG_PER_10L, litres / 10.0 * BOIL_WOOD_PER_10L)
	if litres <= 0.5:
		if int(WorldState.flags.get("boil_warned_day", -1)) != WorldState.day():
			WorldState.flags["boil_warned_day"] = WorldState.day()
			EventBus.emit_event(&"boiling_blocked", {"text": "No gas or firewood to boil water. Untreated water means sickness."})
		return
	Stores.add(WorldState.stores, "water_boiled", _take_untreated(litres))


func _spoil() -> void:
	var temp: float = float(WorldState.climate.get("temperature_c", 30.0)) - STORE_SHADE_C
	var infra: Dictionary = WorldState.infrastructure
	var fridge: float = FRIDGE_C if infra.get("power_on", false) or infra.get("generator_running", false) else INF
	var spoiled: Dictionary = Stores.age_and_spoil(WorldState.stores, TICK_DAYS, temp, fridge)
	for item: String in spoiled:
		var row: Dictionary = Data.entry("items", item)
		if Stores.weight_kg(item, float(spoiled[item])) < SPOILAGE_REPORT_KG:
			continue
		EventBus.emit_event(&"food_spoiled", {"item": item, "qty": spoiled[item],
			"text": "%s spoiled in the heat (%s %s lost)." % [row["name"], _fmt(float(spoiled[item])), row["unit"]]})


## At midnight: score yesterday's rations, then reset the daily intake counters.
func _close_day() -> void:
	var group: Array = WorldState.group()
	var full: bool = WorldState.policies[&"food_ration"] == &"full"
	if full and not group.is_empty() and group.all(func(s: Dictionary) -> bool: return float(s["kcal_debt"]) < FULL_RATION_MAX_DEBT_KCAL):
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
