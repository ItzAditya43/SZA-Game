extends SceneTree
## Tutorial tests: the data is consistent, and the tips, the Getting started list and
## the guide work on the real main screen. Exits 1 if any check fails.
## godot --headless --script res://tests/test_tutorial.gd
## Frame 2 runs the screen checks, 4 the launch order, 6 what the first real run did.

var _checks: Object
var _main: Node
var _frames: int = 0


func _initialize() -> void:
	_checks = load("res://tests/tutorial_checks.gd").new()
	_checks.set("tree", self)
	_checks.call("run_checks")
	_main = load("res://main.tscn").instantiate()
	_main.set("autosave_enabled", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_checks.call("check_screen", _main)
	elif _frames == 4:
		_checks.call("check_launch", _main)
	elif _frames == 6:
		quit(_checks.call("check_after", _main))
	return false
