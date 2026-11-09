extends RefCounted
## Shared by the hint card, the Getting started list and the HUD: turns bus events
## into the named triggers that data/tutorial.json speaks, and reads that file.
## Triggers that are not bus events (speed_used, building_selected, planner_opened, tab_<Name>,
## overlay_set, alerts_first) are sent by the HUD. UI-only; the simulation never reads it.


static func hints() -> Dictionary:
	return Data.table("tutorial")["hints"]


static func steps() -> Array:
	return Data.table("tutorial")["steps"]


static func guide() -> Array:
	return Data.table("tutorial")["guide"]


## The triggers an event raises (usually just its own name).
static func triggers(event_name: StringName, payload: Dictionary) -> Array[String]:
	match event_name:
		&"command_set_job":
			if String(payload.get("job", "")) == "guard" and String(payload.get("shift", "")) == "night":
				return ["guard_set"]
			return []
		&"tick", &"noise":
			return []
	return [String(event_name)]


## Whether a hint's own conditions hold right now.
static func applies(hint: Dictionary) -> bool:
	var day: int = WorldState.day()
	if day > int(hint.get("max_day", 9999)) or day < int(hint.get("min_day", 0)):
		return false
	if String(hint.get("when", "")) == "night" and WorldState.phase() != WorldState.PHASE_NIGHT:
		return false
	return true
