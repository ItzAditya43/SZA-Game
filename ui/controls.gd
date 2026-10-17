extends Control
## Clock, speed buttons and the event log. Reads WorldState and TickLoop and
## listens to EventBus. Its only effect on the simulation is through TickLoop speed
## calls and the test-event button.
## Keys: Space toggles pause, 1/2/3 set 1×/3×/10×, T fires a test event.

const LOG_LINES: int = 20
const ACTIVE_SPEED_COLOR: Color = Color(1.0, 0.82, 0.3)

var _clock_label: Label
var _phase_label: Label
var _speed_buttons: Dictionary = {}  # TickLoop.Speed -> Button
var _log_view: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 32)
	column.add_child(_clock_label)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", 18)
	column.add_child(_phase_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	for speed: TickLoop.Speed in [TickLoop.Speed.PAUSED, TickLoop.Speed.X1, TickLoop.Speed.X3, TickLoop.Speed.X10]:
		var button: Button = _make_button(TickLoop.SPEED_LABELS[speed])
		button.toggle_mode = true
		button.add_theme_color_override("font_pressed_color", ACTIVE_SPEED_COLOR)
		button.add_theme_color_override("font_hover_pressed_color", ACTIVE_SPEED_COLOR)
		button.pressed.connect(_on_speed_pressed.bind(speed))
		buttons.add_child(button)
		_speed_buttons[speed] = button
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	buttons.add_child(spacer)
	var test_button: Button = _make_button("Fire test event")
	test_button.pressed.connect(_fire_test_event)
	buttons.add_child(test_button)

	var hint: Label = Label.new()
	hint.text = "Space: pause/resume · 1 / 2 / 3: 1× / 3× / 10× · T: test event"
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)

	var log_title: Label = Label.new()
	log_title.text = "Event log (last %d)" % LOG_LINES
	column.add_child(log_title)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = false
	_log_view.scroll_following = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.focus_mode = Control.FOCUS_NONE
	var monospace: SystemFont = SystemFont.new()
	monospace.font_names = PackedStringArray(["monospace"])
	_log_view.add_theme_font_override("normal_font", monospace)
	column.add_child(_log_view)

	EventBus.event.connect(_on_bus_event)
	_refresh_clock()
	_refresh_speed()
	_refresh_log()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
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
	button.custom_minimum_size = Vector2(72, 36)
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
	match event_name:
		&"tick":
			_refresh_clock()
			return
		&"speed_changed":
			_refresh_speed()
		&"run_started":
			_refresh_clock()
	_refresh_log()


func _refresh_clock() -> void:
	_clock_label.text = WorldState.clock_string()
	_phase_label.text = "Phase: %s" % ("Day" if WorldState.phase() == WorldState.PHASE_DAY else "Night")


func _refresh_speed() -> void:
	for speed: TickLoop.Speed in _speed_buttons:
		var button: Button = _speed_buttons[speed]
		button.set_pressed_no_signal(speed == TickLoop.speed)


func _refresh_log() -> void:
	var lines: PackedStringArray = []
	for entry: Dictionary in EventBus.recent(LOG_LINES):
		var at_tick: int = entry["tick"]
		lines.append("t%-6d %s   %-14s %s" % [at_tick, WorldState.clock_string_at(at_tick), entry["name"], entry["payload"]])
	_log_view.text = "\n".join(lines)
