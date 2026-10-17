extends Node
## Entry point for an interactive run. Opens on the start screen (difficulty and
## seed) over a paused world; `-- --difficulty=easy [--seed=N]` on the command
## line skips it. The clock stops by itself whenever a decision is waiting and
## when the run ends; "New run" on the end screen returns to the start screen.

const SimRun := preload("res://core/sim_run.gd")


func _ready() -> void:
	TickLoop.auto_pause_on(&"decision_needed")
	TickLoop.auto_pause_on(&"run_won")
	TickLoop.auto_pause_on(&"run_lost")
	$HUD.end_screen.new_run_requested.connect($HUD.start_screen.open)
	$HUD.start_screen.start_requested.connect(_start)
	var run_seed: int = SimRun.int_arg("seed", int(Time.get_unix_time_from_system()))
	var difficulty: String = SimRun.string_arg("difficulty", "")
	if difficulty != "":
		_start(difficulty, run_seed)
	else:
		# A paused world to look at behind the start screen.
		SimRun.start(run_seed)
		$HUD.start_screen.open()


func _start(difficulty: String, run_seed: int) -> void:
	SimRun.start(run_seed, difficulty)
	TickLoop.set_speed(TickLoop.Speed.X1)
