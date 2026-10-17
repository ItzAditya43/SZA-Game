extends SceneTree
## Milestone 6 tests. Prints PASS/FAIL per check and exits 1 if any fail.
## godot --headless --script res://tests/test_milestone_6.gd
## (Checks load at runtime; see test_milestone_1.gd for why.)


func _initialize() -> void:
	var checks: Object = load("res://tests/milestone_6_checks.gd").new()
	checks.set("tree", self)
	quit(checks.call("run"))
