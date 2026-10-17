extends SceneTree
## Difficulty tests. Prints PASS/FAIL per check and exits 1 if any fail.
## godot --headless --script res://tests/test_difficulty.gd
## (Checks load at runtime; see test_milestone_1.gd for why.)


func _initialize() -> void:
	var checks: Object = load("res://tests/difficulty_checks.gd").new()
	checks.set("tree", self)
	quit(checks.call("run"))
