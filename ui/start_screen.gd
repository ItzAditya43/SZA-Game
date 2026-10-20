extends PanelContainer
## The new-run screen: difficulty, seed and the five survivors (picked from the
## pool of 12, "Random 5", or the Default five), plus Continue and Load. Names
## (the town's and everyone's) come from the seed, so they're previewed here and
## change when the seed does; "New world" rolls another seed.
## The main scene acts on the signals.

signal start_requested(difficulty: String, run_seed: int, roster: Array)
signal continue_requested
signal load_list_requested

const Difficulty := preload("res://core/difficulty.gd")
const SaveGame := preload("res://core/save_game.gd")
const Names := preload("res://core/names.gd")

var _choice: String = Difficulty.DEFAULT_ID
var _buttons: Dictionary = {}  # difficulty id -> Button
var _description: Label
var _seed_edit: LineEdit
var _picks: Dictionary = {}  # survivor id -> CheckBox
var _roster_label: Label
var _start: Button
var _continue: Button
var _random_roster: bool = false
var _intro: Label
## The seed used when the field is blank; rolled each time the screen opens.
var _world_seed: int = 0


func _ready() -> void:
	if _description != null:
		return
	theme_type_variation = "Modal"
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(760, 0)
	add_child(column)

	var title: Label = Label.new()
	title.text = "Survival Sim — new run"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_intro = Label.new()
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro.theme_type_variation = "MutedLabel"
	column.add_child(_intro)

	var saves_row: HBoxContainer = HBoxContainer.new()
	saves_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(saves_row)
	_continue = _button("Continue", func() -> void:
		visible = false
		continue_requested.emit())
	saves_row.add_child(_continue)
	saves_row.add_child(_button("Load…", func() -> void: load_list_requested.emit()))

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for preset: Dictionary in Data.table("difficulty"):
		var button: Button = _button(String(preset["name"]), _pick.bind(String(preset["id"])))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(140, 36)
		button.theme_type_variation = "SpeedButton"
		row.add_child(button)
		_buttons[preset["id"]] = button
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(760, 44)
	column.add_child(_description)

	var roster_head: HBoxContainer = HBoxContainer.new()
	column.add_child(roster_head)
	_roster_label = Label.new()
	_roster_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_head.add_child(_roster_label)
	roster_head.add_child(_button("Default five", _set_default))
	roster_head.add_child(_button("Random 5", _set_random))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	for row_data: Dictionary in Data.table("survivors"):
		var pick: CheckBox = CheckBox.new()
		var traits: PackedStringArray = []
		var trait_texts: PackedStringArray = []
		for id: String in row_data.get("traits", []):
			var trait_row: Dictionary = Data.entry("traits", id)
			traits.append(String(trait_row["name"]))
			trait_texts.append("%s: %s" % [trait_row["name"], trait_row["text"]])
		pick.set_meta("traits", ", ".join(traits))
		var skills: Dictionary = row_data["skills"]
		pick.tooltip_text = "%s\nScavenging %d · Medicine %d · Combat %d\n%s" % [row_data.get("background", ""),
			int(skills["scavenging"]), int(skills["medicine"]), int(skills["combat"]), "\n".join(trait_texts)]
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(250, 0)
		pick.toggled.connect(func(_on: bool) -> void:
			_random_roster = false
			_refresh_roster())
		grid.add_child(pick)
		_picks[row_data["id"]] = pick

	var seed_row: HBoxContainer = HBoxContainer.new()
	column.add_child(seed_row)
	var seed_label: Label = Label.new()
	seed_label.text = "World seed:"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_changed.connect(func(_text: String) -> void: _refresh_names())
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_button("New world", func() -> void:
		_seed_edit.text = ""
		_roll_world()))

	_start = _button("Start", _on_start)
	_start.custom_minimum_size = Vector2(0, 42)
	_start.theme_type_variation = "PrimaryButton"
	column.add_child(_start)
	_pick(_choice)
	_set_default()
	_roll_world()


func open() -> void:
	if _description == null:
		_ready()
	_continue.disabled = SaveGame.latest() == ""
	_roll_world()
	visible = true
	_center.call_deferred()


func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _pick(id: String) -> void:
	_choice = id
	for key: String in _buttons:
		var button: Button = _buttons[key]
		button.set_pressed_no_signal(key == id)
	_description.text = Difficulty.preset(id)["description"]


func _set_default() -> void:
	var default_ids: Array = Data.table("scenario")["default_roster"]
	for id: String in _picks:
		(_picks[id] as CheckBox).set_pressed_no_signal(default_ids.has(id))
	_random_roster = false
	_refresh_roster()


func _set_random() -> void:
	for id: String in _picks:
		(_picks[id] as CheckBox).set_pressed_no_signal(false)
	_random_roster = true
	_refresh_roster()


func _chosen() -> Array:
	return _picks.keys().filter(func(id: String) -> bool: return (_picks[id] as CheckBox).button_pressed)


func _refresh_roster() -> void:
	var size: int = int(Data.table("scenario")["roster_size"])
	if _random_roster:
		_roster_label.text = "Survivors: 5 picked at random from the seed when you start"
		_start.disabled = false
		return
	var count: int = _chosen().size()
	_roster_label.text = "Survivors: %d of %d chosen (hover a name for their story and traits)" % [count, size]
	_start.disabled = count != size


## A fresh world for a blank seed field: a new town and new names.
func _roll_world() -> void:
	_world_seed = int(Time.get_unix_time_from_system()) + Time.get_ticks_usec() % 100000
	_seed_edit.placeholder_text = "%d (blank = this one)" % _world_seed
	_refresh_names()


func _seed() -> int:
	var text: String = _seed_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() else _world_seed


## Shows the town and the people as this seed names them.
func _refresh_names() -> void:
	var names: Dictionary = Names.generate(_seed())
	_intro.text = "%s, a small town in the hottest weeks of the year. Five survivors. Thirty days." % names["town"]
	for row_data: Dictionary in Data.table("survivors"):
		var pick: CheckBox = _picks[row_data["id"]]
		pick.text = "%s, %d — %s\n%s" % [names["people"][row_data["id"]], int(row_data["age"]), row_data["profession"], pick.get_meta("traits")]


func _on_start() -> void:
	var run_seed: int = _seed()
	visible = false
	start_requested.emit(_choice, run_seed, ["random"] if _random_roster else _chosen())


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
