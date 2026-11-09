extends RefCounted
## Player settings that survive between runs (user://settings.cfg): UI scale,
## which alert types pause the game, which hints have been dismissed, graphics
## quality and audio volumes. Anything that should react to a change registers
## with listen(); changed() calls them.
## UI-only; the simulation never reads it.

const PATH: String = "user://settings.cfg"
const MIN_SCALE: float = 0.8
const MAX_SCALE: float = 1.5
## Alert types that pause the game by default: the ones where minutes matter.
const DEFAULT_AUTOPAUSE: Array[String] = ["decision", "bleeding", "bite", "infection", "water", "mains"]

const GRAPHICS_TOGGLES: Array[String] = ["lights", "shadows", "particles", "screen_effects"]
const AUDIO_BUSES: Array[String] = ["Master", "Music", "Ambient", "SFX", "UI"]

static var _cfg: ConfigFile = null
static var _listeners: Array[Callable] = []


static func listen(callback: Callable) -> void:
	_listeners.append(callback)


static func changed() -> void:
	_listeners = _listeners.filter(func(c: Callable) -> bool: return c.is_valid())
	for c: Callable in _listeners:
		c.call()


static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


## Values set here win over the file and are never saved (screenshots, benchmarks).
static var overrides: Dictionary = {}


static func value(section: String, key: String, fallback: Variant) -> Variant:
	var k: String = section + "/" + key
	if overrides.has(k):
		return overrides[k]
	return _config().get_value(section, key, fallback)


## Headless runs (tests) and the screenshot tool change settings in memory only,
## so they never touch the player's own settings file.
static var persist: bool = DisplayServer.get_name() != "headless"


static func store(section: String, key: String, data: Variant) -> void:
	_config().set_value(section, key, data)
	_save()


static func _save() -> void:
	if persist:
		_config().save(PATH)


static func ui_scale() -> float:
	return clampf(float(value("display", "ui_scale", 1.0)), MIN_SCALE, MAX_SCALE)


static func set_ui_scale(scale: float, tree: SceneTree) -> void:
	store("display", "ui_scale", clampf(scale, MIN_SCALE, MAX_SCALE))
	apply_ui_scale(tree)


static func apply_ui_scale(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale()


static func autopause(alert_type: String) -> bool:
	return bool(value("autopause", alert_type, DEFAULT_AUTOPAUSE.has(alert_type)))


static func set_autopause(alert_type: String, on: bool) -> void:
	store("autopause", alert_type, on)


static func hint_dismissed(id: String) -> bool:
	return bool(value("hints", id, false))


static func dismiss_hint(id: String) -> void:
	store("hints", id, true)


static func reset_hints() -> void:
	if _config().has_section("hints"):
		_config().erase_section("hints")
		_save()


# --- Graphics ---

static func quality_preset() -> String:
	return String(value("graphics", "preset", "high"))


## Picking a preset resets the individual toggles to the preset's values.
static func set_quality_preset(preset: String) -> void:
	store("graphics", "preset", preset)
	for key: String in GRAPHICS_TOGGLES:
		if _config().has_section_key("graphics", key):
			_config().erase_section_key("graphics", key)
	_save()
	changed()


## A toggle's value: set on its own, or from the preset.
static func graphics(key: String) -> bool:
	var presets: Dictionary = Data.table("render")["quality"]
	var from_preset: bool = bool(presets.get(quality_preset(), presets["high"]).get(key, true))
	return bool(value("graphics", key, from_preset))


static func set_graphics(key: String, on: bool) -> void:
	store("graphics", key, on)
	changed()


static func reduce_motion() -> bool:
	return bool(value("graphics", "reduce_motion", false))


static func set_reduce_motion(on: bool) -> void:
	store("graphics", "reduce_motion", on)
	changed()


# --- Audio ---

## 0..1 per bus; Ambient and SFX a little under full so UI sounds sit on top.
static func volume(bus: String) -> float:
	return clampf(float(value("audio", bus, {"Music": 0.5, "Ambient": 0.6}.get(bus, 0.8))), 0.0, 1.0)


static func set_volume(bus: String, level: float) -> void:
	store("audio", bus, clampf(level, 0.0, 1.0))
	changed()
