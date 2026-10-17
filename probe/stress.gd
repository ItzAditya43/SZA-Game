extends SceneTree
func _initialize() -> void:
	var b: Object = load("res://probe/stress_body.gd").new()
	b.call("go")
	quit(0)
