extends PanelContainer
## The new-run screen: pick a difficulty (from data/difficulty.json) and,
## optionally, a seed to replay. "Start" asks the main scene to begin the run.

signal start_requested(difficulty: String, run_seed: int)

const Difficulty := preload("res://core/difficulty.gd")

var _choice: String = Difficulty.DEFAULT_ID
var _buttons: Dictionary = {}  # difficulty id -> Button
var _description: Label
var _seed_edit: LineEdit


func _ready() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 1.0)
	style.border_color = Color(1, 1, 1, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(560, 0)
	add_child(column)

	var title: Label = Label.new()
	title.text = "Survival Sim — new run"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var intro: Label = Label.new()
	intro.text = "A district town in South India, mid-April. Five survivors. Thirty days."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.modulate = Color(1, 1, 1, 0.7)
	column.add_child(intro)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for preset: Dictionary in Data.table("difficulty"):
		var button: Button = Button.new()
		button.text = preset["name"]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(140, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.3))
		button.pressed.connect(_pick.bind(String(preset["id"])))
		row.add_child(button)
		_buttons[preset["id"]] = button

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(560, 70)
	column.add_child(_description)

	var seed_row: HBoxContainer = HBoxContainer.new()
	column.add_child(seed_row)
	var seed_label: Label = Label.new()
	seed_label.text = "Seed (blank for a new world):"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "random"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)

	var start: Button = Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(0, 44)
	start.add_theme_font_size_override("font_size", 20)
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(_start)
	column.add_child(start)
	_pick(_choice)


func open() -> void:
	visible = true
	_center.call_deferred()


func _pick(id: String) -> void:
	_choice = id
	for key: String in _buttons:
		var button: Button = _buttons[key]
		button.set_pressed_no_signal(key == id)
	_description.text = Difficulty.preset(id)["description"]


func _start() -> void:
	var text: String = _seed_edit.text.strip_edges()
	var run_seed: int = text.to_int() if text.is_valid_int() else int(Time.get_unix_time_from_system())
	visible = false
	start_requested.emit(_choice, run_seed)


func _center() -> void:
	reset_size()
	position = ((get_parent_area_size() - size) / 2.0).floor()
