extends PanelContainer
## A yes/no question with its consequences spelled out. Neither button has focus.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")

var _column: VBoxContainer


func _ready() -> void:
	theme_type_variation = "Modal"
	visible = false
	_column = Kit.vbox(Tokens.SPACE_M)
	_column.custom_minimum_size = Vector2(540, 0)
	add_child(_column)


func ask(title: String, lines: Array, confirm_text: String, on_confirm: Callable) -> void:
	Kit.clear(_column)
	_column.add_child(Kit.label(title, "TitleLabel"))
	for line: String in lines:
		var text: Label = Kit.label("• " + line, "", true)
		text.custom_minimum_size = Vector2(520, 0)
		_column.add_child(text)
	var row: HBoxContainer = Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(row)
	row.add_child(Kit.button("Cancel", func() -> void: visible = false, "GhostButton"))
	row.add_child(Kit.button(confirm_text, func() -> void:
		visible = false
		on_confirm.call(), "PrimaryButton"))
	visible = true
	_center.call_deferred()


func _center() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()
