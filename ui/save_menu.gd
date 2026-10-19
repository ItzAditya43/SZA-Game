extends PanelContainer
## The pause menu (Esc) and the list of saves (Ctrl+L, or Load… on the start
## screen). Saving and loading go through core/save_game.gd; the main scene
## starts new runs.

signal new_run_requested
signal load_requested(path: String)

const SaveGame := preload("res://core/save_game.gd")

var _column: VBoxContainer
var _message: Label


func _ready() -> void:
	if _column != null:
		return
	visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 1.0)
	style.border_color = Color(1, 1, 1, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)
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
			label.modulate = Color(1, 0.6, 0.5)
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
	heading.add_theme_font_size_override("font_size", 22)
	_column.add_child(heading)
	_message = Label.new()
	_message.modulate = Color(1, 0.85, 0.5)
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


func _center() -> void:
	reset_size()
	position = ((get_parent_area_size() - size) / 2.0).floor()
