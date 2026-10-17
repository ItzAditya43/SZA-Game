extends PanelContainer
## Top bar: clock, date, temperature, phase, speed buttons and utilities status.
## Reads WorldState and TickLoop and listens to EventBus. Its only effects on the
## simulation are TickLoop speed calls and the test-event button.
## Keys: Space toggles pause, 1/2/3 set 1×/3×/10×, T fires a test event.

const ACTIVE_SPEED_COLOR: Color = Color(1.0, 0.82, 0.3)

var _clock_label: Label
var _weather_label: Label
var _utilities_label: Label
var _speed_buttons: Dictionary = {}  # TickLoop.Speed -> Button


func _ready() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 26)
	_clock_label.custom_minimum_size = Vector2(230, 0)
	row.add_child(_clock_label)

	_weather_label = Label.new()
	_weather_label.custom_minimum_size = Vector2(320, 0)
	row.add_child(_weather_label)

	for speed: TickLoop.Speed in [TickLoop.Speed.PAUSED, TickLoop.Speed.X1, TickLoop.Speed.X3, TickLoop.Speed.X10]:
		var button: Button = _make_button(TickLoop.SPEED_LABELS[speed])
		button.toggle_mode = true
		button.add_theme_color_override("font_pressed_color", ACTIVE_SPEED_COLOR)
		button.add_theme_color_override("font_hover_pressed_color", ACTIVE_SPEED_COLOR)
		button.pressed.connect(_on_speed_pressed.bind(speed))
		row.add_child(button)
		_speed_buttons[speed] = button

	var test_button: Button = _make_button("Test event")
	test_button.tooltip_text = "Fires a test event on the bus (T)"
	test_button.pressed.connect(_fire_test_event)
	row.add_child(test_button)

	_utilities_label = Label.new()
	_utilities_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_utilities_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_utilities_label)

	EventBus.event.connect(_on_bus_event)
	_refresh()
	_refresh_speed()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# No time controls while the start or end screen is up.
	if get_tree().get_nodes_in_group(&"modal").any(func(n: Node) -> bool: return (n as Control).visible):
		return
	match key.keycode:
		KEY_SPACE:
			TickLoop.toggle_pause()
		KEY_1:
			TickLoop.set_speed(TickLoop.Speed.X1)
		KEY_2:
			TickLoop.set_speed(TickLoop.Speed.X3)
		KEY_3:
			TickLoop.set_speed(TickLoop.Speed.X10)
		KEY_T:
			_fire_test_event()
		_:
			return
	get_viewport().set_input_as_handled()


func _make_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(56, 32)
	# Keeps Space for pause instead of re-pressing the last clicked button.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_speed_pressed(speed: TickLoop.Speed) -> void:
	TickLoop.set_speed(speed)
	# Clicking the active toggle button unpresses it, so always resync.
	_refresh_speed()


func _fire_test_event() -> void:
	EventBus.emit_event(&"test_event", {"source": "ui"})


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"speed_changed":
		_refresh_speed()
	else:
		_refresh()


func _refresh() -> void:
	_clock_label.text = WorldState.clock_string()
	var climate: Dictionary = WorldState.climate
	var phase: String = "Day" if WorldState.phase() == WorldState.PHASE_DAY else "Night"
	_weather_label.text = "%s · %.1f °C · %s · %s" % [climate.get("date", ""), float(climate.get("temperature_c", 0.0)), phase,
		WorldState.difficulty.get("name", "")]
	var infra: Dictionary = WorldState.infrastructure
	if infra.is_empty():
		_utilities_label.text = ""
	else:
		_utilities_label.text = "Power %s · Water mains %s · Phones %s" % [
			"on" if infra.get("power_on", false) else "OFF",
			"on" if infra.get("mains_on", false) else "OFF",
			"on" if infra.get("phones_on", false) else "OFF"]


func _refresh_speed() -> void:
	for speed: TickLoop.Speed in _speed_buttons:
		var button: Button = _speed_buttons[speed]
		button.set_pressed_no_signal(speed == TickLoop.speed)
