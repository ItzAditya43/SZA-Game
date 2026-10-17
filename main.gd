extends Node
## Entry point for an interactive run. Starts a run with the seed from
## `-- --seed=N` on the command line, or the current time, then runs at 1×.
## The clock stops by itself whenever a decision is waiting and when the run ends.

const SimRun := preload("res://core/sim_run.gd")


func _ready() -> void:
	TickLoop.auto_pause_on(&"decision_needed")
	TickLoop.auto_pause_on(&"run_won")
	TickLoop.auto_pause_on(&"run_lost")
	$HUD.end_screen.new_run_requested.connect(_new_run)
	_start(SimRun.int_arg("seed", int(Time.get_unix_time_from_system())))


func _start(run_seed: int) -> void:
	SimRun.start(run_seed)
	TickLoop.set_speed(TickLoop.Speed.X1)


func _new_run() -> void:
	_start(int(Time.get_unix_time_from_system()))
