extends Node
## Opens the game screen, fast-forwards the simulation, and saves a screenshot.
## godot res://tools/screenshot.tscn -- --difficulty=normal --seed=42 --hours=30 --tab=0 --out=/tmp/shot.png
## Without --difficulty the shot shows the start screen.
## Used to check the UI without clicking through it by hand.

const SimRun := preload("res://core/sim_run.gd")

const SIZE: Vector2i = Vector2i(1600, 900)

var _frames: int = 0
var _hud: Control
var _viewport: SubViewport


func _ready() -> void:
	# Render offscreen at a fixed size, whatever the window manager does to the window.
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var main: Node = load("res://main.tscn").instantiate()
	_viewport.add_child(main)
	_hud = main.get_node("HUD")
	TickLoop.set_speed(TickLoop.Speed.PAUSED)
	TickLoop.run_headless(SimRun.int_arg("hours", 0) * 6)
	var tabs: TabContainer = _hud.get("tabs")
	tabs.current_tab = clampi(SimRun.int_arg("tab", 0), 0, tabs.get_tab_count() - 1)
	var building: String = _string_arg("select", "")
	if building != "":
		_hud.get("ui_state").select_building(building)
	EventBus.emit_event(&"tick", {"tick": WorldState.tick})


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		var path: String = _string_arg("out", "user://screenshot.png")
		_viewport.get_texture().get_image().save_png(path)
		print("Saved %s at %s" % [path, WorldState.clock_string()])
		get_tree().quit()


static func _string_arg(arg_name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % arg_name):
			return arg.trim_prefix("--%s=" % arg_name)
	return fallback
