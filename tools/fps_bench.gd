extends Node
## Measures frames per second for each graphics preset on this machine, in a real
## window, with the heaviest scene the game has: night, the generator lit,
## rain on, time running at 3×, the camera zoomed in on the base.
## godot res://tools/fps_bench.tscn -- [--size=1920x1080] [--seconds=6]
## Prints one line per preset; settings are overridden in memory, never saved.

const Settings := preload("res://ui/settings.gd")
const SimRun := preload("res://core/sim_run.gd")
const PRESETS: Array[String] = ["low", "medium", "high"]
const WARMUP_S: float = 2.0

var _hud: Node
var _preset: int = -1
var _elapsed: float = 0.0
var _frames: int = 0
var _measuring: bool = false
var _seconds: float = 6.0
var _results: PackedStringArray = []


func _ready() -> void:
	var wanted: String = SimRun.string_arg("size", "1920x1080")
	get_window().size = Vector2i(int(wanted.get_slice("x", 0)), int(wanted.get_slice("x", 1)))
	_seconds = float(SimRun.int_arg("seconds", 6))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://main.tscn").instantiate()
	main.set("autosave_enabled", false)
	add_child(main)
	_hud = main.get_node("HUD")
	SimRun.start(5, "easy")
	var stores: Script = load("res://core/stores.gd")
	stores.call("add", WorldState.stores, "generator", 1.0)
	stores.call("add", WorldState.stores, "fuel", 500.0)
	EventBus.emit_event(&"command_set_policy", {"key": &"generator", "value": &"night"})
	TickLoop.run_headless(5 * 144 + 96)  # day 5, 22:00
	for modal: Node in get_tree().get_nodes_in_group("modal"):
		(modal as CanvasItem).visible = false
	_hud.get("start_screen").set("visible", false)
	var view: Node = _hud.get("world_view")
	view.set("force_rain", true)
	_zoom.call_deferred(view)
	TickLoop.set_speed(TickLoop.Speed.X3)
	_next()


func _zoom(view: Node) -> void:
	await get_tree().process_frame
	view.call("zoom_at", 3.0, (view as Control).size / 2.0)
	view.call("look_at_m", load("res://core/geo.gd").call("base_center_m"))


func _next() -> void:
	_preset += 1
	if _preset >= PRESETS.size():
		for line: String in _results:
			print(line)
		get_tree().quit()
		return
	Settings.overrides["graphics/preset"] = PRESETS[_preset]
	Settings.changed()
	_elapsed = 0.0
	_frames = 0
	_measuring = false


func _process(delta: float) -> void:
	if _preset < 0 or _preset >= PRESETS.size():
		return
	# Decisions would pause time; keep it running.
	if TickLoop.speed == TickLoop.Speed.PAUSED:
		TickLoop.set_speed(TickLoop.Speed.X3)
	_elapsed += delta
	if not _measuring and _elapsed >= WARMUP_S:
		_measuring = true
		_elapsed = 0.0
		_frames = 0
		return
	if _measuring:
		_frames += 1
		if _elapsed >= _seconds:
			_results.append("%-6s %5.1f fps (%d frames in %.1f s, %s)" % [PRESETS[_preset], _frames / _elapsed, _frames, _elapsed,
				SimRun.string_arg("size", "1920x1080")])
			_next()
