extends "res://core/sim_system.gd"
## Time. Registered first. In Milestone 1 it only checks that the clock advanced
## by exactly one tick and that the derived clock values agree with each other.
## Problems are reported as `clock_error` on the bus rather than assert(): a failed
## assert in a headless run halts waiting for a debugger instead of failing.

var _last_tick: int = -1


func tick() -> void:
	var now: int = WorldState.tick
	if _last_tick != -1 and now != _last_tick + 1:
		_report("Clock jumped from tick %d to %d" % [_last_tick, now])
	if WorldState.day() * WorldState.TICKS_PER_DAY + now % WorldState.TICKS_PER_DAY != now:
		_report("Day %d does not match tick %d" % [WorldState.day(), now])
	var minute: int = WorldState.minute_of_day()
	if minute % WorldState.MINUTES_PER_TICK != 0 or minute < 0 or minute >= WorldState.MINUTES_PER_DAY:
		_report("Minute of day %d is off the 10-minute grid" % minute)
	_last_tick = now


func _report(message: String) -> void:
	push_error("Time: " + message)
	EventBus.emit_event(&"clock_error", {"message": message})
