extends Node
## Autoload `EventBus`. The only channel between systems, and from the simulation
## to the UI. Whoever changes the world announces it here; anyone interested
## listens to `event`.

signal event(event_name: StringName, payload: Dictionary)

const LOG_SIZE: int = 200
## Broadcast every tick (or nearly), so kept out of the log to leave room for real events.
const UNLOGGED_EVENTS: Array[StringName] = [&"tick", &"noise"]

## Most recent last. Each entry: {"tick": int, "name": StringName, "payload": Dictionary}.
var event_log: Array[Dictionary] = []


func emit_event(event_name: StringName, payload: Dictionary = {}) -> void:
	if not UNLOGGED_EVENTS.has(event_name):
		event_log.append({"tick": WorldState.tick, "name": event_name, "payload": payload.duplicate(true)})
		if event_log.size() > LOG_SIZE:
			event_log.pop_front()
	event.emit(event_name, payload)


## The last `count` log entries, oldest first.
func recent(count: int) -> Array[Dictionary]:
	return event_log.slice(maxi(event_log.size() - count, 0))


func clear_log() -> void:
	event_log.clear()
