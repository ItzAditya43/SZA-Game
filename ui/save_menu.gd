extends PanelContainer
## The pause menu (Esc) and the list of saves (Ctrl+L, or Load… on the start
## screen). Saving and loading go through core/save_game.gd; the main scene
## starts new runs.

signal new_run_requested
signal load_requested(path: String)

const SaveGame := preload("res://core/save_game.gd")
const Settings := preload("res://ui/settings.gd")
const Alerts := preload("res://ui/alerts.gd")

var _column: VBoxContainer
var _message: Label


func _ready() -> void:
	if _column != null:
		return
	visible = false
	theme_type_variation = "Modal"
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	_column.custom_minimum_size = Vector2(520, 0)
	add_child(_column)


## The pause menu: resume, save, load, new run, quit.
func open_pause() -> void:
	_clear("Paused")
	_add_button("Resume", close)
	_add_button("Save game", func() -> void:
		var slot: String = "save_" + Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		_message.text = "Saved." if SaveGame.save(slot) != "" else "Could not save; see the log.")
	_add_button("Load…", open_load)
	_add_button("Settings…", open_settings)
	_add_button("New run…", func() -> void:
		close()
		new_run_requested.emit())
	_add_button("Quit", func() -> void: get_tree().quit())
	_show()


## Every save, newest first, each with a Load button.
func open_load() -> void:
	_clear("Load a saved game")
	var saves: Array = SaveGame.list()
	if saves.is_empty():
		var none: Label = Label.new()
		none.text = "No saves yet. The game autosaves every dawn; Ctrl+S saves now."
		_column.add_child(none)
	for entry: Dictionary in saves:
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry["ok"]:
			label.text = "%s — %s · %s · %d alive · saved %s" % [String(entry["slot"]).replace("_", " "), entry["clock"],
				String(entry["difficulty"]).capitalize(), int(entry["alive"]), entry["saved_at"]]
		else:
			label.text = "%s — can't be loaded: %s" % [entry["slot"], entry["error"]]
			label.theme_type_variation = "DangerLabel"
		row.add_child(label)
		var load_button: Button = Button.new()
		load_button.text = "Load"
		load_button.focus_mode = Control.FOCUS_NONE
		load_button.disabled = not entry["ok"]
		load_button.pressed.connect(func() -> void: load_requested.emit(String(entry["path"])))
		row.add_child(load_button)
		_column.add_child(row)
	_add_button("Back", close)
	_show()


## UI scale, alerts that pause the game, and the first-day hints.
func open_settings() -> void:
	_clear("Settings")
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 380)
	_column.add_child(tabs)
	tabs.add_child(_settings_general())
	tabs.add_child(_settings_alerts())
	tabs.add_child(_settings_graphics())
	tabs.add_child(_settings_audio())
	_add_button("Back", open_pause)
	_show()


func _tab(title: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 8)
	return box


func _slider(box: VBoxContainer, caption: String, lo: float, hi: float, step: float, now: float, on_change: Callable) -> void:
	var label: Label = Label.new()
	label.text = caption % roundi(now)
	box.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = now
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(300, 24)
	slider.value_changed.connect(func(v: float) -> void:
		label.text = caption % roundi(v)
		on_change.call(v))
	box.add_child(slider)


func _check(parent: Control, text: String, on: bool, on_toggle: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.focus_mode = Control.FOCUS_NONE
	box.text = text
	box.button_pressed = on
	box.toggled.connect(on_toggle)
	parent.add_child(box)
	return box


func _settings_general() -> Control:
	var box: VBoxContainer = _tab("General")
	_slider(box, "Interface size: %d%%", Settings.MIN_SCALE * 100.0, Settings.MAX_SCALE * 100.0, 10.0, Settings.ui_scale() * 100.0,
		func(v: float) -> void: Settings.set_ui_scale(v / 100.0, get_tree()))
	var hints: Button = Button.new()
	hints.text = "Show the first-day hints again"
	hints.focus_mode = Control.FOCUS_NONE
	hints.pressed.connect(func() -> void:
		Settings.reset_hints()
		_message.text = "Hints will show again.")
	box.add_child(hints)
	return box


func _settings_alerts() -> Control:
	var box: VBoxContainer = _tab("Alerts")
	var pause_label: Label = Label.new()
	pause_label.text = "Pause the game when one of these appears:"
	pause_label.theme_type_variation = "MutedLabel"
	box.add_child(pause_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for type: String in Alerts.TYPES:
		_check(grid, Alerts.TYPES[type], Settings.autopause(type), func(on: bool) -> void: Settings.set_autopause(type, on))
	return box


func _settings_graphics() -> Control:
	var box: VBoxContainer = _tab("Graphics")
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var label: Label = Label.new()
	label.text = "Quality:"
	row.add_child(label)
	var toggles: Dictionary = {}
	for preset: String in ["low", "medium", "high"]:
		var b: Button = Button.new()
		b.text = preset.capitalize()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "SpeedButton"
		b.button_pressed = Settings.quality_preset() == preset
		b.pressed.connect(func() -> void:
			Settings.set_quality_preset(preset)
			for other: Button in row.get_children().filter(func(n: Node) -> bool: return n is Button):
				other.set_pressed_no_signal(other == b)
			for key: String in toggles:
				(toggles[key] as CheckBox).set_pressed_no_signal(Settings.graphics(key)))
		row.add_child(b)
	var names: Dictionary = {"lights": "Lights (lamps, fires, generator)", "shadows": "Shadows (buildings block light)",
		"particles": "Particles (rain, smoke, dust)", "screen_effects": "Screen effects (heat shimmer, heavy rain)"}
	for key: String in Settings.GRAPHICS_TOGGLES:
		toggles[key] = _check(box, names[key], Settings.graphics(key), func(on: bool) -> void: Settings.set_graphics(key, on))
	_check(box, "Reduce motion (no gliding, drifting or shimmer)", Settings.reduce_motion(),
		func(on: bool) -> void: Settings.set_reduce_motion(on))
	return box


func _settings_audio() -> Control:
	var box: VBoxContainer = _tab("Audio")
	var names: Dictionary = {"Master": "Master", "Music": "Music (none yet)", "Ambient": "Ambience", "SFX": "Sound effects", "UI": "Interface"}
	for bus: String in Settings.AUDIO_BUSES:
		_slider(box, names[bus] + ": %d%%", 0.0, 100.0, 5.0, Settings.volume(bus) * 100.0,
			func(v: float) -> void: Settings.set_volume(bus, v / 100.0))
	return box


## Shows a problem (such as an incompatible save) without closing the menu.
func show_message(text: String) -> void:
	_message.text = text


func close() -> void:
	visible = false


func _clear(title: String) -> void:
	if _column == null:
		_ready()
	for child: Node in _column.get_children():
		child.queue_free()
	var heading: Label = Label.new()
	heading.text = title
	heading.theme_type_variation = "TitleLabel"
	_column.add_child(heading)
	_message = Label.new()
	_message.theme_type_variation = "WarnLabel"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_message)


func _add_button(text: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(action)
	_column.add_child(button)


func _show() -> void:
	visible = true
	_center.call_deferred()


## Anchored to the middle of the screen and growing both ways, so the panel stays
## centred however tall its contents turn out once laid out.
func _center() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()
