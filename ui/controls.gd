extends PanelContainer
## Top bar: clock and phase, date and temperature, speed, the state of power, taps
## and phones, the alert counter and the menu. Reads WorldState and TickLoop; its
## only effects on the simulation are speed changes and the test event.
## Keys: Space pause/resume, 1/2/3 speed, T test event, ? shortcuts, H guide.

signal alerts_pressed
signal menu_pressed
signal shortcuts_pressed
signal guide_pressed
signal speed_used
signal panel_toggled

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")

var _clock: Label
var _weather: Label
var _speed_buttons: Dictionary = {}  # TickLoop.Speed -> Button
var _utilities: HBoxContainer
var _alerts: Button
var _alert_count: int = -1
var _alert_tier: String = ""


func _ready() -> void:
	theme_type_variation = "TopBar"
	var row: HBoxContainer = Kit.hbox(Tokens.SPACE_M)
	add_child(row)
	_clock = Kit.label("", "ClockLabel")
	_clock.custom_minimum_size = Vector2(200, 0)
	row.add_child(_clock)
	_weather = Kit.label("", "MutedLabel")
	_weather.custom_minimum_size = Vector2(250, 0)
	_weather.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_weather)
	var speeds: HBoxContainer = Kit.hbox(2)
	row.add_child(speeds)
	var names: Dictionary = {TickLoop.Speed.PAUSED: "Pause", TickLoop.Speed.X1: "1×", TickLoop.Speed.X3: "3×", TickLoop.Speed.X10: "10×"}
	var keys: Dictionary = {TickLoop.Speed.PAUSED: "Space", TickLoop.Speed.X1: "1", TickLoop.Speed.X3: "2", TickLoop.Speed.X10: "3"}
	for speed: TickLoop.Speed in names:
		var button: Button = Kit.button(names[speed], _on_speed_pressed.bind(speed), "SpeedButton", "Key: %s" % keys[speed])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(52, 32)
		speeds.add_child(button)
		_speed_buttons[speed] = button
	row.add_child(Kit.spacer())
	_utilities = Kit.hbox(Tokens.SPACE_XS)
	row.add_child(_utilities)
	_alerts = Kit.button("Alerts", func() -> void: alerts_pressed.emit(), "Button", "Warnings: what needs attention now")
	row.add_child(_alerts)
	row.add_child(Kit.button("Guide", func() -> void: guide_pressed.emit(), "GhostButton", "How to play: the goal, the controls and tips (H)"))
	row.add_child(Kit.button("?", func() -> void: shortcuts_pressed.emit(), "GhostButton", "Keyboard shortcuts (?)"))
	row.add_child(Kit.button("Panel", func() -> void: panel_toggled.emit(), "GhostButton", "Show or hide the side panel (Tab)"))
	row.add_child(Kit.button("Menu", func() -> void: menu_pressed.emit(), "GhostButton", "Save, load, settings, new run (Esc)"))
	EventBus.event.connect(_on_bus_event)
	refresh()
	_refresh_speed()


func set_alerts(count: int, worst_tier: String) -> void:
	if count == _alert_count and worst_tier == _alert_tier:
		return
	_alert_count = count
	_alert_tier = worst_tier
	_alerts.text = "Alerts: none" if count == 0 else "Alerts: %d" % count
	_alerts.theme_type_variation = "DangerButton" if worst_tier == "urgent" else ("Button" if count > 0 else "GhostButton")


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if get_tree().get_nodes_in_group(&"modal").any(func(n: Node) -> bool: return (n as Control).visible):
		return
	match key.keycode:
		KEY_SPACE:
			TickLoop.toggle_pause()
			speed_used.emit()
		KEY_1:
			TickLoop.set_speed(TickLoop.Speed.X1)
			speed_used.emit()
		KEY_2:
			TickLoop.set_speed(TickLoop.Speed.X3)
			speed_used.emit()
		KEY_3:
			TickLoop.set_speed(TickLoop.Speed.X10)
			speed_used.emit()
		KEY_T:
			EventBus.emit_event(&"test_event", {"source": "ui"})
		KEY_TAB:
			panel_toggled.emit()
		KEY_H:
			guide_pressed.emit()
		KEY_SLASH, KEY_QUESTION:
			shortcuts_pressed.emit()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_speed_pressed(speed: TickLoop.Speed) -> void:
	speed_used.emit()
	TickLoop.set_speed(speed)
	_refresh_speed()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"speed_changed":
		_refresh_speed()
	elif event_name in [&"tick", &"run_started", &"game_loaded", &"power_failed", &"mains_failed", &"phones_down"]:
		refresh()


func refresh() -> void:
	_clock.text = WorldState.clock_string()
	var climate: Dictionary = WorldState.climate
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	_weather.text = "%s · %.0f °C · %s · %s" % [climate.get("date", ""), float(climate.get("temperature_c", 0.0)),
		"Night" if night else "Day", WorldState.difficulty.get("name", "")]
	var infra: Dictionary = WorldState.infrastructure
	var key: String = "%s%s%s%s" % [infra.get("power_on", false), infra.get("mains_on", false), infra.get("phones_on", false),
		infra.get("generator_running", false)]
	if _utilities.get_meta("key", "") == key:
		return
	_utilities.set_meta("key", key)
	Kit.clear(_utilities)
	if infra.is_empty():
		return
	_utilities.add_child(_utility("Power", infra.get("power_on", false), "Grid power. When it fails, a generator gives light at the cost of fuel and noise."
		if not infra.get("generator_running", false) else "Generator running."))
	_utilities.add_child(_utility("Taps", infra.get("mains_on", false), "Water mains. When they fail, water comes only from tanks, rain or the canal, and must be boiled."))
	_utilities.add_child(_utility("Phones", infra.get("phones_on", false), "Mobile networks."))


func _utility(name: String, on: bool, tooltip: String) -> Label:
	return Kit.chip("%s %s" % [name, "on" if on else "off"], "ok" if on else "muted", tooltip)


func _refresh_speed() -> void:
	for speed: TickLoop.Speed in _speed_buttons:
		(_speed_buttons[speed] as Button).set_pressed_no_signal(speed == TickLoop.speed)
