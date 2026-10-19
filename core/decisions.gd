extends RefCounted
## Helpers for decisions that wait on the player. A system creates one with
## create(); the UI (or the headless auto-player) answers by emitting
## `decision_made` {"id", "option"}; the creating system listens, applies the
## choice and calls resolve(). TickLoop auto-pauses on `decision_needed`.


## options: Array from option(). data may carry "unknowns": Array of strings the
## group can't know yet. Returns the decision id.
static func create(kind: StringName, text: String, options: Array, data: Dictionary = {}) -> int:
	var id: int = WorldState.new_id()
	var decision: Dictionary = {"id": id, "kind": kind, "text": text, "options": options, "tick": WorldState.tick}
	decision.merge(data)
	WorldState.pending_decisions.append(decision)
	EventBus.emit_event(&"decision_needed", {"id": id, "kind": kind, "text": text})
	return id


static func find(id: int) -> Dictionary:
	for decision: Dictionary in WorldState.pending_decisions:
		if int(decision["id"]) == id:
			return decision
	return {}


static func resolve(id: int) -> void:
	WorldState.pending_decisions = WorldState.pending_decisions.filter(
		func(d: Dictionary) -> bool: return int(d["id"]) != id)


## `consequence` is what the group knows will follow; `irreversible` options never
## get default focus in the UI.
static func option(id: StringName, label: String, consequence: String = "", irreversible: bool = false) -> Dictionary:
	return {"id": id, "label": label, "consequence": consequence, "irreversible": irreversible}
