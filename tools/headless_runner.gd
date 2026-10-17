extends SceneTree
## Runs the simulation with no UI and prints a summary.
## godot --headless --script res://tools/headless_runner.gd -- --seed=42 --days=3 [--strategy=balanced] [--verbose=1]
## godot --headless --script res://tools/headless_runner.gd -- --games=100 --strategy=all
##
## A --script file is compiled before the autoload names (WorldState, EventBus,
## ...) are registered, so the work lives in headless_run.gd, loaded at runtime.


func _initialize() -> void:
	var run_script: GDScript = load("res://tools/headless_run.gd")
	quit(run_script.new().run())
