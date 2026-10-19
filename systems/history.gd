extends "res://core/sim_system.gd"
## History. Bookkeeping only, for the Stats charts and the end screen: a snapshot
## of the group's situation every midnight (and at the start and end), plus a
## timeline of decisions taken, losses and moves. It never changes the world.

const Stores := preload("res://core/stores.gd")
const Infected := preload("res://systems/infected.gd")

const TIMELINE_EVENTS: Dictionary = {
	&"survivor_died": "loss", &"survivor_turned": "loss", &"survivor_left": "loss", &"survivor_exiled": "loss",
	&"base_moved": "move", &"base_breached": "attack", &"story_event": "event", &"survivor_joined": "event",
}

var _asked: Dictionary = {}  # decision id -> {"text", "options"}


func setup() -> void:
	WorldState.stats["history"] = []
	WorldState.stats["timeline"] = []
	listen(&"decision_needed", _on_decision_needed)
	listen(&"decision_made", _on_decision_made)
	listen(&"run_won", _on_run_end)
	listen(&"run_lost", _on_run_end)
	for event_name: StringName in TIMELINE_EVENTS:
		listen(event_name, _on_timeline_event.bind(event_name))
	_snapshot()


func tick() -> void:
	if WorldState.is_new_day():
		_snapshot()


func _snapshot() -> void:
	var history: Array = WorldState.stats.get("history", [])
	var group: Array = WorldState.group()
	var stress: float = 0.0
	for s: Dictionary in group:
		stress += float(s["stress"])
	var base: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	var tank: float = 0.0 if base.is_empty() or WorldState.infrastructure.get("mains_on", false) else float(base["tank_l"])
	var row: Dictionary = {
		"day": WorldState.day(), "tick": WorldState.tick,
		"water_l": Stores.total(WorldState.stores, "water_bottled") + Stores.stored_water_l(WorldState.stores) + tank,
		"food_kcal": Stores.food_kcal(WorldState.stores),
		"alive": group.size(),
		"avg_stress": stress / maxf(1.0, group.size()),
		"infected": Infected.total(),
		"attention": float(WorldState.base.get("attention", 0.0)),
		"fuel_l": Stores.total(WorldState.stores, "fuel"),
		"antibiotics": Stores.total(WorldState.stores, "antibiotics"),
	}
	if not history.is_empty() and int(history[-1]["tick"]) == WorldState.tick:
		history[-1] = row
	else:
		history.append(row)
	WorldState.stats["history"] = history


func _on_decision_needed(payload: Dictionary) -> void:
	for decision: Dictionary in WorldState.pending_decisions:
		if int(decision["id"]) == int(payload["id"]):
			_asked[int(decision["id"])] = {"text": decision["text"], "options": decision["options"]}


func _on_decision_made(payload: Dictionary) -> void:
	var asked: Dictionary = _asked.get(int(payload["id"]), {})
	if asked.is_empty():
		return
	_asked.erase(int(payload["id"]))
	var label: String = String(payload["option"])
	for option: Dictionary in asked["options"]:
		if option["id"] == StringName(payload["option"]):
			label = option["label"]
	_add("decision", "%s → %s" % [asked["text"], label])


func _on_timeline_event(payload: Dictionary, event_name: StringName) -> void:
	_add(TIMELINE_EVENTS[event_name], String(payload.get("text", event_name)))


func _on_run_end(_payload: Dictionary) -> void:
	_snapshot()


func _add(kind: String, text: String) -> void:
	WorldState.stats["timeline"].append({"tick": WorldState.tick, "kind": kind, "text": text})
