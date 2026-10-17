extends RefCounted
## Difficulty presets from data/difficulty.json. Each preset is a set of
## multipliers on the tuned (Normal) numbers; a system asks for its own with
## Difficulty.mult("encounters"). Keys: infected, encounters, attacks,
## looted_by_others, loot, start_stores, stress, disease.

const DEFAULT_ID: String = "normal"


static func mult(key: String) -> float:
	return float(WorldState.difficulty.get("multipliers", {}).get(key, 1.0))


static func preset(id: String) -> Dictionary:
	var row: Dictionary = Data.entry("difficulty", id)
	if row.is_empty():
		push_error("Difficulty: no preset '%s', using %s" % [id, DEFAULT_ID])
		row = Data.entry("difficulty", DEFAULT_ID)
	return row


static func ids() -> Array:
	return Data.table("difficulty").map(func(row: Dictionary) -> String: return row["id"])
