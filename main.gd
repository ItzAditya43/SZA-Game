extends Node
## Entry point for an interactive run. Starts a run with the seed from
## `-- --seed=N` on the command line, or the current time, then runs at 1×.

const SimRun := preload("res://core/sim_run.gd")


func _ready() -> void:
	SimRun.start(SimRun.int_arg("seed", int(Time.get_unix_time_from_system())))
	# Decisions need the player: stop the clock until they answer.
	TickLoop.auto_pause_on(&"decision_needed")
	TickLoop.set_speed(TickLoop.Speed.X1)
