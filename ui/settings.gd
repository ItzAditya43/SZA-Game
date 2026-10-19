extends RefCounted
## Player settings that survive between runs (user://settings.cfg): UI scale,
## which alert types pause the game, and which hints have been dismissed.
## UI-only; the simulation never reads it.

const PATH: String = "user://settings.cfg"
const MIN_SCALE: float = 0.8
const MAX_SCALE: float = 1.5
## Alert types that pause the game by default: the ones where minutes matter.
const DEFAULT_AUTOPAUSE: Array[String] = ["decision", "bleeding", "bite", "infection", "water", "mains"]

static var _cfg: ConfigFile = null


static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


static func value(section: String, key: String, fallback: Variant) -> Variant:
	return _config().get_value(section, key, fallback)


static func store(section: String, key: String, data: Variant) -> void:
	_config().set_value(section, key, data)
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
		_config().save(PATH)
