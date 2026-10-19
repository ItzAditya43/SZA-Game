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
	var scale_label: Label = Label.new()
	scale_label.text = "Interface size: %d%%" % roundi(Settings.ui_scale() * 100.0)
	_column.add_child(scale_label)
	var slider: HSlider = HSlider.new()
	slider.min_value = Settings.MIN_SCALE * 100.0
	slider.max_value = Settings.MAX_SCALE * 100.0
	slider.step = 10.0
	slider.value = Settings.ui_scale() * 100.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(300, 24)
	slider.value_changed.connect(func(v: float) -> void:
		scale_label.text = "Interface size: %d%%" % roundi(v)
		Settings.set_ui_scale(v / 100.0, get_tree()))
	_column.add_child(slider)
	var pause_label: Label = Label.new()
	pause_label.text = "Pause the game when one of these appears:"
	pause_label.theme_type_variation = "MutedLabel"
	_column.add_child(pause_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_column.add_child(grid)
	for type: String in Alerts.TYPES:
		var box: CheckBox = CheckBox.new()
		box.focus_mode = Control.FOCUS_NONE
		box.text = Alerts.TYPES[type]
		box.button_pressed = Settings.autopause(type)
		box.toggled.connect(func(on: bool) -> void: Settings.set_autopause(type, on))
		grid.add_child(box)
	_add_button("Show the first-day hints again", func() -> void:
		Settings.reset_hints()
		_message.text = "Hints will show again.")
	_add_button("Back", open_pause)
	_show()


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
