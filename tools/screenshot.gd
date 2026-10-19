extends Node
## Opens the game screen, fast-forwards the simulation, and saves a screenshot.
## godot res://tools/screenshot.tscn -- --difficulty=normal --seed=42 --hours=30 --tab=0 --out=/tmp/shot.png
## Without --difficulty the shot shows the start screen. --menu=pause|load opens a menu,
## --decide-later=1 puts waiting decisions aside, --hints=0 hides the tip card,
## --overlay=noise (etc.) picks the map overlay.
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
	# --size=1280x720 renders the way a real window of that size shows the game:
	# the 1600x900 layout stretched to fit (Project Settings > Display > Stretch).
	var wanted: String = _string_arg("size", "")
	if wanted.contains("x"):
		var real: Vector2i = Vector2i(int(wanted.get_slice("x", 0)), int(wanted.get_slice("x", 1)))
		_viewport.size = real
		var scale: float = float(real.y) / float(SIZE.y)
		_viewport.size_2d_override = Vector2i(roundi(real.x / scale), SIZE.y)
		_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var main: Node = load("res://main.tscn").instantiate()
	main.set("autosave_enabled", false)
	_viewport.add_child(main)
	_hud = main.get_node("HUD")
	TickLoop.set_speed(TickLoop.Speed.PAUSED)
	TickLoop.run_headless(SimRun.int_arg("hours", 0) * 6)
	var tabs: TabContainer = _hud.get("tabs")
	tabs.current_tab = clampi(SimRun.int_arg("tab", 0), 0, tabs.get_tab_count() - 1)
	var building: String = _string_arg("select", "")
	if building != "":
		_hud.get("ui_state").select_building(building)
	if _string_arg("decide-later", "") == "1":
		var modal: Node = _hud.get("decision_modal")
		modal.set("_later", WorldState.pending_decisions.map(func(d: Dictionary) -> int: return int(d["id"])))
		modal.call("refresh")
	if _string_arg("hints", "") == "0":
		(_hud.get("hints") as Control).visible = false
	var overlay: String = _string_arg("overlay", "")
	if overlay != "":
		_hud.call("set_overlay", overlay)
	match _string_arg("open", ""):
		"planner":
			_hud.get("planner").call("open", building)
		"alerts":
			var panel: Node = _hud.get("alerts_panel")
			panel.set("alerts", _hud.call("_current_alerts"))
			panel.call("toggle")
		"shortcuts":
			_hud.get("shortcuts").call("toggle")
		"move":
			_hud.call("_confirm_move", building)
		"end":
			_hud.get("end_screen").call("show_outcome")
	match _string_arg("menu", ""):
		"pause":
			_hud.get("save_menu").open_pause()
		"settings":
			_hud.get("save_menu").open_settings()
		"load":
			_hud.get("save_menu").open_load()

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
