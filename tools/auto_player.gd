extends RefCounted
## A stand-in player for headless runs and balancing. It reads WorldState and acts
## only through the same bus commands the UI sends (command_set_job,
## command_set_policy, command_move_base, decision_made), so it plays by the
## player's rules. Strategies:
##   balanced     stay in the start house, fortify it, scavenge by need
##   fortress     move into the police station, fortify, two guards, guns
##   hoard_water  move into a school with a big tank, stockpile water first
##   keep_moving  never dig in: move every few days to a fresh, quiet building

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Jobs := preload("res://systems/jobs.gd")

const STRATEGIES: Array[StringName] = [&"balanced", &"fortress", &"hoard_water", &"keep_moving"]
const STRATEGY_BASE: Dictionary = {&"fortress": "police_station_01", &"hoard_water": "school_02"}
const KEEP_MOVING_EVERY_DAYS: int = 4
## Plan the coming shift ten minutes before it starts.
const PLAN_DAY_MINUTE: int = 5 * 60 + 50
const PLAN_NIGHT_MINUTE: int = 17 * 60 + 50
const KCAL_PER_DAY: float = 2800.0
const WATER_L_PER_DAY: float = 4.0
## Value of a kg of each item when the group needs it (scaled by need below).
const VALUE_PER_KG: Dictionary = {
	"antibiotics": 400.0, "tourniquet": 60.0, "ors": 40.0, "bandages": 40.0, "painkillers": 20.0,
	"ammo": 30.0, "rifle": 6.0, "machete": 4.0, "water_bottled": 2.0, "packaged_food": 2.5,
	"rice": 1.5, "dal": 1.5, "atta": 1.2, "fresh_produce": 0.3, "fuel": 0.8, "cooking_gas": 2.0,
	"materials": 1.0, "water_drum": 8.0, "generator": 1.5,
}

var strategy: StringName
var _last_move_day: int = 0
var _last_night_guards: Array = []


func _init(strategy_name: StringName = &"balanced") -> void:
	strategy = strategy_name
	EventBus.event.connect(_on_event)


## Call right after SimRun.start(): sets the opening moves for the chosen strategy.
func begin() -> void:
	EventBus.emit_event(&"command_set_policy", {"key": &"use_guns", "value": strategy == &"fortress"})
	if STRATEGY_BASE.has(strategy):
		EventBus.emit_event(&"command_move_base", {"building": STRATEGY_BASE[strategy]})
	_plan_shift(&"day")
	_plan_shift(&"night")


func _on_event(event_name: StringName, payload: Dictionary) -> void:
	if not WorldState.is_running():
		return
	match event_name:
		&"decision_needed":
			_decide(int(payload["id"]))
		&"tick":
			var minute: int = WorldState.minute_of_day()
			if minute == PLAN_DAY_MINUTE:
				_rations()
				_maybe_move()
				_plan_shift(&"day")
			elif minute == PLAN_NIGHT_MINUTE:
				_plan_shift(&"night")


# --- Decisions ---

func _decide(id: int) -> void:
	var decision: Dictionary = {}
	for d: Dictionary in WorldState.pending_decisions:
		if int(d["id"]) == id:
			decision = d
	if decision.is_empty():
		return
	var choice: StringName
	match decision["kind"]:
		&"bite":
			choice = &"quarantine"
		&"antibiotics":
			var strips: float = Stores.total(WorldState.stores, "antibiotics")
			var worse_than_local: bool = not String(decision["text"]).contains("red and swelling")
			choice = &"give" if worse_than_local or strips >= 3.0 else &"wait"
		&"event":
			choice = &"accept" if _food_days() > 8.0 else &"refuse"
		_:
			choice = StringName(decision["options"][0]["id"])
	EventBus.emit_event(&"decision_made", {"id": id, "option": choice})


# --- Orders ---

func _rations() -> void:
	var days: float = _food_days()
	var ration: StringName = &"full" if days >= 6.0 else (&"reduced" if days >= 3.0 else (&"half" if days >= 1.5 else &"minimal"))
	if WorldState.policies.get(&"food_ration") != ration:
		EventBus.emit_event(&"command_set_policy", {"key": &"food_ration", "value": ration})


func _maybe_move() -> void:
	if strategy != &"keep_moving" or WorldState.day() - _last_move_day < KEEP_MOVING_EVERY_DAYS:
		return
	_last_move_day = WorldState.day()
	var best: Dictionary = {}
	var best_score: float = 0.0
	for b: Dictionary in WorldState.buildings:
		if b["id"] == WorldState.base["building"] or b["stripped"] or float(b["danger"]) > 0.5:
			continue
		var zone: float = float(WorldState.zones[Geo.zone_index_at(Geo.building_center_m(b))]["infected"])
		var score: float = _loot_value(b) / (1.0 + zone / 300.0)
		if score > best_score:
			best_score = score
			best = b
	if not best.is_empty():
		EventBus.emit_event(&"command_move_base", {"building": best["id"]})


func _plan_shift(shift: StringName) -> void:
	var able: Array = WorldState.group().filter(func(s: Dictionary) -> bool:
		return not s["quarantined"] and not Body.is_incapacitated(s))
	var jobs: Dictionary = {}
	for s: Dictionary in WorldState.group():
		jobs[s["id"]] = &"rest"
	if shift == &"night":
		var guards: int = 2 if strategy == &"fortress" or int(WorldState.base.get("breaches", 0)) > 0 else 1
		able.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Body.skill(a, "combat") > Body.skill(b, "combat"))
		_last_night_guards = []
		for s: Dictionary in able:
			if _last_night_guards.size() >= guards:
				break
			if float(s["sleep_debt_h"]) < 10.0:
				jobs[s["id"]] = &"guard"
				_last_night_guards.append(s["id"])
		_send(jobs, shift)
		return
	# Day: last night's guards sleep; everyone else is given the most needed job.
	var pool: Array = able.filter(func(s: Dictionary) -> bool: return not _last_night_guards.has(s["id"]))
	if pool.is_empty():
		pool = able
	if _anyone_needs_care():
		_assign(pool, jobs, &"treat", "medicine")
	if _needs_cooking():
		_assign_lowest(pool, jobs, &"cook", "scavenging")
	var water_jobs: int = 2 if strategy == &"hoard_water" else 1
	for i: int in water_jobs:
		if _needs_water():
			_assign_lowest(pool, jobs, &"collect_water", "scavenging")
	if strategy != &"keep_moving" and _can_fortify():
		_assign_lowest(pool, jobs, &"fortify", "scavenging")
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Body.skill(a, "scavenging") > Body.skill(b, "scavenging"))
	var taken: Array = []
	for s: Dictionary in pool.slice(0, 2):
		var target: Dictionary = _best_target(taken)
		if target.is_empty():
			break
		taken.append(target["id"])
		jobs[s["id"]] = &"scavenge"
		EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": shift, "job": &"scavenge", "target": target["id"]})
		jobs.erase(s["id"])
	_send(jobs, shift)


func _send(jobs: Dictionary, shift: StringName) -> void:
	for id: String in jobs:
		EventBus.emit_event(&"command_set_job", {"survivor": id, "shift": shift, "job": jobs[id]})


func _assign(pool: Array, jobs: Dictionary, job: StringName, best_skill: String) -> void:
	if pool.is_empty():
		return
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Body.skill(a, best_skill) > Body.skill(b, best_skill))
	jobs[pool[0]["id"]] = job
	pool.remove_at(0)


## Gives the job to whoever is worst at `skill`, keeping the good scavengers free.
func _assign_lowest(pool: Array, jobs: Dictionary, job: StringName, skill: String) -> void:
	if pool.size() <= 1:
		return
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Body.skill(a, skill) < Body.skill(b, skill))
	jobs[pool[0]["id"]] = job
	pool.remove_at(0)


# --- Needs ---

func _food_days() -> float:
	return Stores.food_kcal(WorldState.stores) / (KCAL_PER_DAY * maxf(1.0, WorldState.group().size()))


func _water_days() -> float:
	var base: Dictionary = WorldState.building(String(WorldState.base["building"]))
	var litres: float = Stores.total(WorldState.stores, "water_bottled") + Stores.stored_water_l(WorldState.stores)
	if not WorldState.infrastructure.get("mains_on", false):
		litres += float(base.get("tank_l", 0.0))
	return litres / (WATER_L_PER_DAY * maxf(1.0, WorldState.group().size()))


func _anyone_needs_care() -> bool:
	return WorldState.group().any(func(s: Dictionary) -> bool:
		return not s["injuries"].is_empty() or not s["illness"].is_empty())


func _needs_cooking() -> bool:
	var staples: float = Stores.total(WorldState.stores, "rice") + Stores.total(WorldState.stores, "dal") + Stores.total(WorldState.stores, "atta")
	var ready: float = Stores.total(WorldState.stores, "packaged_food") + Stores.total(WorldState.stores, "fresh_produce")
	return staples > 1000.0 and ready < KCAL_PER_DAY * WorldState.group().size() * 3.0


func _needs_water() -> bool:
	var room: float = Stores.water_capacity_l(WorldState.stores) - Stores.stored_water_l(WorldState.stores)
	if WorldState.infrastructure.get("mains_on", false):
		return room > 20.0
	return room > 20.0 and _water_days() < (6.0 if strategy == &"hoard_water" else 3.0)


func _can_fortify() -> bool:
	var base: Dictionary = WorldState.building(String(WorldState.base["building"]))
	var cap: float = float(Data.entry("buildings", String(base["type"]))["max_barricade"])
	return Stores.total(WorldState.stores, "materials") >= 3.0 and float(base["barricade"]) < cap - 1.0


# --- Scavenging targets ---

func _best_target(taken: Array) -> Dictionary:
	var home: Vector2 = Geo.base_center_m()
	var best: Dictionary = {}
	var best_score: float = 0.0
	for b: Dictionary in WorldState.buildings:
		if b["id"] == WorldState.base["building"] or taken.has(b["id"]):
			continue
		var zone: float = float(WorldState.zones[Geo.zone_index_at(Geo.building_center_m(b))]["infected"])
		var risk: float = (0.5 + 2.0 * float(b["danger"])) * (1.0 + zone / 800.0)
		var hours: float = Geo.street_distance_m(home, Geo.building_center_m(b)) / Jobs.SPEED_OUT_M_PER_H * 2.0 + Jobs.SEARCH_HOURS
		if hours > 6.0:
			continue
		var score: float = _loot_value(b) / (risk * (1.0 + hours / 3.0))
		if score > best_score:
			best_score = score
			best = b
	return best


## What a full pack from this building is worth to the group right now.
func _loot_value(b: Dictionary) -> float:
	var value: float = 0.0
	var carry: float = Jobs.CARRY_KG
	for item: String in Stores.snapshot(b["loot"]):
		var row: Dictionary = Data.entry("items", item)
		var kg: float = minf(Stores.weight_kg(item, Stores.total(b["loot"], item) * 0.6),
			float(Jobs.CATEGORY_KG_CAP.get(String(row["category"]), 10.0)))
		value += minf(kg, carry) * float(VALUE_PER_KG.get(item, 0.5)) * _need(item)
	return value


func _need(item: String) -> float:
	var stores: Dictionary = WorldState.stores
	match Data.entry("items", item).get("category", ""):
		"food":
			if item in ["rice", "dal", "atta"] and Stores.total(stores, "cooking_gas") + Stores.total(stores, "materials") < 1.0:
				return 0.2
			return 2.0 if _food_days() < 10.0 else 0.4
		"water":
			return 2.0 if not WorldState.infrastructure.get("mains_on", false) and _water_days() < 4.0 else 0.4
		"medicine":
			return 2.0 if Stores.total(stores, "antibiotics") < 3.0 else 0.7
		"materials":
			return 1.5 if _can_fortify_more() else 0.1
		"fuel":
			if item == "cooking_gas":
				return 2.0 if Stores.total(stores, "cooking_gas") < 3.0 else 0.3
			return 1.0 if Stores.total(stores, "generator") >= 1.0 else 0.1
		"gear":
			if item == "water_drum":
				return 1.5 if Stores.total(stores, "water_drum") < 4.0 else 0.0
			return 0.5 if Stores.total(stores, item) < 1.0 else 0.0
		"weapon":
			return 1.0 if strategy == &"fortress" or item == "machete" else 0.3
	return 0.5


func _can_fortify_more() -> bool:
	if strategy == &"keep_moving":
		return false
	var base: Dictionary = WorldState.building(String(WorldState.base["building"]))
	var cap: float = float(Data.entry("buildings", String(base["type"]))["max_barricade"])
	return float(base["barricade"]) + Stores.total(WorldState.stores, "materials") < cap
