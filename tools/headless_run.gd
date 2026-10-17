extends RefCounted
## Runs the simulation with no UI, as fast as possible, and prints a summary.
## Started by tools/headless_runner.gd.
# LATER (Milestone 6): run 100 games and print average survival.

const SimRun := preload("res://core/sim_run.gd")

var _days_started: int = 0
var _clock_errors: int = 0


## Returns the process exit code.
func run() -> int:
	var run_seed: int = SimRun.int_arg("seed", 42)
	var days: int = SimRun.int_arg("days", 30)
	if not Data.errors.is_empty():
		printerr("Data failed to load; see errors above.")
		return 1
	SimRun.start(run_seed)
	EventBus.event.connect(_on_bus_event)
	TickLoop.run_headless(days * WorldState.TICKS_PER_DAY)
	print("Ran %d days (%d ticks) with seed %d" % [days, WorldState.tick, run_seed])
	print("Final clock: %s" % WorldState.clock_string())
	print("day_started events: %d" % _days_started)
	if _clock_errors > 0:
		printerr("clock_error events: %d" % _clock_errors)
		return 1
	return 0


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"day_started":
		_days_started += 1
	elif event_name == &"clock_error":
		_clock_errors += 1
