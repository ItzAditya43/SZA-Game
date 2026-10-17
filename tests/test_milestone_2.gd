extends SceneTree
## Milestone 2 tests. Prints PASS/FAIL per check and exits 1 if any fail.
## godot --headless --script res://tests/test_milestone_2.gd
## (Checks load at runtime; see test_milestone_1.gd for why.)


func _initialize() -> void:
	var checks_script: GDScript = load("res://tests/milestone_2_checks.gd")
	quit(checks_script.new().run())
