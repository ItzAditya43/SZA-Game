extends SceneTree
## Prompt 2 (UI/UX) tests. Prints PASS/FAIL per check and exits 1 if any fail.
## godot --headless --script res://tests/test_ui.gd
## (Checks load at runtime; see test_milestone_1.gd for why.) The simulation
## checks run first; the main screen is checked after it has had a frame to build.

var _checks: Object
var _main: Node
var _frames: int = 0


func _initialize() -> void:
	_checks = load("res://tests/ui_checks.gd").new()
	_checks.set("tree", self)
	_checks.call("run_checks")
	_main = load("res://main.tscn").instantiate()
	_main.set("autosave_enabled", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		quit(_checks.call("check_screen", _main))
	return false
