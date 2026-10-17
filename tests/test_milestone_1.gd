extends SceneTree
## Milestone 1 tests. Prints PASS/FAIL per check and exits 1 if any fail.
## godot --headless --script res://tests/test_milestone_1.gd
##
## A --script file is compiled before the autoload names (WorldState, EventBus,
## ...) are registered, so the checks live in milestone_1_checks.gd, loaded at runtime.


func _initialize() -> void:
	var checks_script: GDScript = load("res://tests/milestone_1_checks.gd")
	quit(checks_script.new().run())
