extends Node
## All of the game's sound, driven by the world. Buses Master, Music, Ambient,
## SFX and UI (each with a volume in Settings). Ambient beds crossfade with the
## time of day, rain and midday heat, and are muffled (low-pass) while the game
## is paused or a decision is open. Sounds for what happens: distant gunshots,
## doors forced, night attacks, hammering at the base, a generator loop while it
## runs, fire crackle nearer or farther from the camera, alert chimes by tier and
## button clicks. A reader of WorldState and the EventBus, like the rest of render/.
## The sounds are synthesised by tools/make_sounds.py.

const Settings := preload("res://ui/settings.gd")
const Geo := preload("res://core/geo.gd")

const DIR: String = "res://assets/audio/"
const BUSES: Array[String] = ["Music", "Ambient", "SFX", "UI"]
const FADE_PER_S: float = 0.6
const MUFFLE_HZ: float = 900.0
## Heard from this far (metres) a gunshot is faint; beyond it, silent.
const GUNSHOT_HEARD_M: float = 1500.0
const HAMMER_EVERY_S: float = 6.0

var world_view: Node = null  # for the camera position (fire loudness)

var _ambient: Dictionary = {}  # name -> AudioStreamPlayer
var _ambient_target: Dictionary = {}  # name -> 0..1
var _generator: AudioStreamPlayer
var _fire: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _hammer_wait: float = 0.0
var _streams: Dictionary = {}


func _ready() -> void:
	_make_buses()
	for name: String in ["amb_day", "amb_night", "amb_rain", "amb_heat"]:
		var p: AudioStreamPlayer = _player(name, "Ambient", true)
		p.volume_db = -80.0
		_ambient[name] = p
		_ambient_target[name] = 0.0
	_generator = _player("sfx_generator", "SFX", true)
	_generator.volume_db = -80.0
	_fire = _player("sfx_fire", "SFX", true)
	_fire.volume_db = -80.0
	EventBus.event.connect(_on_bus_event)
	Settings.listen(apply_volumes)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	for button: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(button)


func _make_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var ambient: int = AudioServer.get_bus_index("Ambient")
	if AudioServer.get_bus_effect_count(ambient) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = MUFFLE_HZ
		AudioServer.add_bus_effect(ambient, _lowpass)
	else:
		_lowpass = AudioServer.get_bus_effect(ambient, 0)
	AudioServer.set_bus_effect_enabled(ambient, 0, false)


func apply_volumes() -> void:
	for bus: String in ["Master"] + BUSES:
		var i: int = AudioServer.get_bus_index(bus)
		var level: float = Settings.volume(bus)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level, 0.0001)))
		AudioServer.set_bus_mute(i, level <= 0.001)


func _stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path: String = DIR + name + ".wav"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[name] = stream
	return stream


func _player(name: String, bus: String, loop: bool) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = bus
	var stream: AudioStream = _stream(name)
	if stream is AudioStreamWAV and loop:
		var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		stream = wav
	p.stream = stream
	add_child(p)
	if loop and stream != null:
		p.play()
	return p


## A one-shot sound on a bus, at a loudness 0..1.
func play(name: String, bus: String = "SFX", loudness: float = 1.0) -> void:
	var stream: AudioStream = _stream(name)
	if stream == null or loudness <= 0.01:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	p.volume_db = linear_to_db(loudness)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## The chime for a new alert of this tier (info, caution, urgent).
func alert(tier: String) -> void:
	play({"info": "ui_info", "caution": "ui_caution", "urgent": "ui_urgent"}.get(tier, "ui_info"), "UI", 0.8)


func _on_node_added(node: Node) -> void:
	var button: BaseButton = node as BaseButton
	if button != null and not button.pressed.is_connected(_click):
		button.pressed.connect(_click)


func _click() -> void:
	play("ui_click", "UI", 0.6)


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	if not is_inside_tree():
		return
	match event_name:
		&"noise":
			if payload.get("source", &"") == &"gunshot":
				play("sfx_gunshot", "SFX", _heard(payload, GUNSHOT_HEARD_M))
		&"door_forced":
			play("sfx_door", "SFX", 0.5)
		&"night_attack", &"base_breached":
			play("sfx_attack", "SFX", 1.0 if event_name == &"base_breached" else 0.7)
		&"tick":
			_on_tick()


## Loudness of a sound at a position, as heard at the base.
func _heard(payload: Dictionary, reach_m: float) -> float:
	if not payload.has("x_m") or WorldState.base.is_empty():
		return 0.6
	var d: float = Vector2(float(payload["x_m"]), float(payload["y_m"])).distance_to(Geo.base_center_m())
	return clampf(1.0 - d / reach_m, 0.0, 1.0) * 0.9 + 0.1


func _on_tick() -> void:
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	var minute: int = WorldState.minute_of_day()
	var raining: bool = world_view != null and bool(world_view.get("_raining"))
	var temp: float = float(WorldState.climate.get("temperature_c", 30.0))
	_ambient_target["amb_day"] = 0.0 if night or raining else 1.0
	_ambient_target["amb_night"] = 1.0 if night and not raining else 0.0
	_ambient_target["amb_rain"] = 1.0 if raining else 0.0
	_ambient_target["amb_heat"] = clampf((temp - 34.0) / 4.0, 0.0, 1.0) if minute >= 600 and minute < 1020 and not raining else 0.0


func _process(delta: float) -> void:
	var paused: bool = TickLoop.speed == TickLoop.Speed.PAUSED
	var modal: bool = get_tree().get_nodes_in_group("modal").any(func(n: Node) -> bool: return (n as CanvasItem).visible)
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Ambient"), 0, paused or modal)
	for name: String in _ambient:
		var p: AudioStreamPlayer = _ambient[name]
		var now: float = db_to_linear(p.volume_db)
		var goal: float = float(_ambient_target[name])
		now = move_toward(now, goal, FADE_PER_S * delta)
		p.volume_db = linear_to_db(maxf(now, 0.0001))
	var running: bool = WorldState.infrastructure.get("generator_running", false)
	_generator.volume_db = linear_to_db(0.45) if running else -80.0
	_fire.volume_db = linear_to_db(maxf(_fire_loudness(), 0.0001))
	# Hammering while someone fortifies at the base and time is running.
	_hammer_wait -= delta
	if _hammer_wait <= 0.0 and not paused:
		_hammer_wait = HAMMER_EVERY_S
		var hammering: bool = WorldState.group().any(func(s: Dictionary) -> bool:
			return s["location"] == &"base" and s["job_now"] in [&"fortify", &"quick_fortify"] and s["activity"] == &"heavy_work")
		if hammering:
			play("sfx_hammer", "SFX", 0.35)


## Fires are louder the closer the camera is to them.
func _fire_loudness() -> float:
	if world_view == null:
		return 0.0
	var actors: Node = world_view.get("actors")
	var fires: Dictionary = actors.get("_fires") if actors != null else {}
	if fires.is_empty():
		return 0.0
	var camera: Camera2D = world_view.get("camera")
	var best: float = 0.0
	for fire: Node2D in fires.values():
		var d: float = camera.position.distance_to(fire.position) * camera.zoom.x
		best = maxf(best, clampf(1.0 - d / 900.0, 0.0, 1.0))
	return best * 0.7
