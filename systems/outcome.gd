extends "res://core/sim_system.gd"
## Win, lose and score. The run is won when day 30 dawns with at least one
## survivor still in the group; lost when everyone is dead, turned or gone, or
## when every survivor's morale has fallen below 5 and the group scatters.
## Score: survivors alive, days on full rations, and supplies stored.

const Stores := preload("res://core/stores.gd")
const Body := preload("res://core/body.gd")

const POINTS_PER_SURVIVOR: float = 100.0
const POINTS_PER_FULL_RATION_DAY: float = 10.0
## Supplies are scored in person-days: one point per day of food (2,500 kcal) or
## water (4 L) for one person, plus 5 per antibiotic strip.
const KCAL_PER_PERSON_DAY: float = 2500.0
const WATER_L_PER_PERSON_DAY: float = 4.0
const POINTS_PER_ANTIBIOTIC: float = 5.0
## Morale below 5 is stress above 95.
const SCATTER_STRESS: float = 100.0 - 5.0


func setup() -> void:
	WorldState.outcome = {"state": &"running"}


func tick() -> void:
	# Sandbox runs (tests, experiments) never end.
	if not WorldState.is_running() or WorldState.flags.get("sandbox", false):
		return
	var group: Array = WorldState.group()
	var end_tick: int = int(Data.table("scenario")["days_to_survive"]) * WorldState.TICKS_PER_DAY
	if group.is_empty():
		_finish(&"lost", "Nobody is left.")
	elif group.all(func(s: Dictionary) -> bool: return float(s["stress"]) > SCATTER_STRESS):
		for s: Dictionary in group:
			s["status"] = &"left"
			s["cause"] = "the group scattered"
		_finish(&"lost", "Every survivor's morale broke. The group scattered.")
	elif WorldState.tick >= end_tick:
		_finish(&"won", "%d of the group saw day %d." % [group.size(), WorldState.day()])


func _finish(state: StringName, reason: String) -> void:
	var alive: int = WorldState.group().size()
	var stores: Dictionary = WorldState.stores
	var water: float = Stores.total(stores, "water_bottled") + Stores.stored_water_l(stores)
	var supplies: float = Stores.food_kcal(stores) / KCAL_PER_PERSON_DAY + water / WATER_L_PER_PERSON_DAY \
		+ Stores.total(stores, "antibiotics") * POINTS_PER_ANTIBIOTIC
	var full_days: int = int(WorldState.stats.get("full_ration_days", 0))
	var score: float = alive * POINTS_PER_SURVIVOR + full_days * POINTS_PER_FULL_RATION_DAY + supplies
	var fates: Dictionary = {}
	for s: Dictionary in WorldState.survivors:
		fates[s["name"]] = "alive" if s["status"] == &"ok" else String(s["cause"])
	WorldState.outcome = {
		"state": state, "reason": reason, "tick": WorldState.tick, "day": WorldState.day(),
		"alive": alive, "started": WorldState.survivors.size(), "full_ration_days": full_days,
		"supplies_points": supplies, "score": score, "fates": fates,
	}
	EventBus.emit_event(&"run_won" if state == &"won" else &"run_lost", {"score": score, "alive": alive,
		"text": "%s %s Score %d." % ["You survived." if state == &"won" else "The run is over.", reason, roundi(score)]})
