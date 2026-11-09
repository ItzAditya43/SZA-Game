extends PanelContainer
## The How to play guide (H, the Guide button, the pause menu and the start screen):
## a few short pages, text in data/tutorial.json. Opening it pauses the game.

signal closed

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Tutorial := preload("res://ui/tutorial.gd")

var _title: Label
var _body: Label
var _counter: Label
var _back: Button
var _next: Button
var _page: int = 0


func _ready() -> void:
	theme_type_variation = "Modal"
	visible = false
	var column: VBoxContainer = Kit.vbox(Tokens.SPACE_M)
	column.custom_minimum_size = Vector2(640, 0)
	add_child(column)
	column.add_child(Kit.label("How to play", "MutedLabel"))
	_title = Kit.label("", "TitleLabel")
	column.add_child(_title)
	_body = Kit.label("", "", true)
	_body.custom_minimum_size = Vector2(620, 250)
	column.add_child(_body)
	var row: HBoxContainer = Kit.hbox()
	column.add_child(row)
	_back = Kit.button("Back", func() -> void: show_page(_page - 1), "Button")
	row.add_child(_back)
	_counter = Kit.label("", "MutedLabel")
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_counter)
	_next = Kit.button("Next", func() -> void:
		if _page >= Tutorial.guide().size() - 1:
			close()
		else:
			show_page(_page + 1), "PrimaryButton")
	row.add_child(_next)
	row.add_child(Kit.button("Close", close, "GhostButton"))


func open() -> void:
	if visible:
		return
	show_page(0)
	visible = true
	_center()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_page(index: int) -> void:
	var pages: Array = Tutorial.guide()
	_page = clampi(index, 0, pages.size() - 1)
	_title.text = String(pages[_page]["title"])
	_body.text = String(pages[_page]["body"])
	_counter.text = "%d of %d" % [_page + 1, pages.size()]
	_back.disabled = _page == 0
	_next.text = "Done" if _page == pages.size() - 1 else "Next"
	_center()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_RIGHT:
			show_page(_page + 1)
		KEY_LEFT:
			show_page(_page - 1)
		KEY_H, KEY_ESCAPE:
			close()
		_:
			return
	get_viewport().set_input_as_handled()


func _center() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()
