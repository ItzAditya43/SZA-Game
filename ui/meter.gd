extends Control
## A small labelled bar: caption, fill 0..1, a value, and a state colour that is
## always paired with a marker word ("low", "!") so it reads without colour.
## Hover shows the breakdown behind it.

const Tokens := preload("res://ui/theme/tokens.gd")
const TipPanel := preload("res://ui/tip_panel.gd")

const BAR_HEIGHT: float = 6.0

var caption: String = ""
var fill: float = 0.0
var value_text: String = ""
var state: String = "ok"
var breakdown: Dictionary = {}
var extra: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(90, 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = " "
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_values(new_fill: float, new_text: String, new_state: String, new_breakdown: Dictionary, new_extra: String = "") -> void:
	fill = new_fill
	value_text = new_text
	state = new_state
	breakdown = new_breakdown
	extra = new_extra
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var small: int = Tokens.FONT_SMALL
	var marker: String = "" if state == "ok" else (" !" if state == "warn" else " !!")
	draw_string(font, Vector2(0, small), caption + marker, HORIZONTAL_ALIGNMENT_LEFT, size.x, small,
		Tokens.TEXT_MUTED if state == "ok" else Tokens.state_color(state))
	draw_string(font, Vector2(0, small * 2 + 3), value_text, HORIZONTAL_ALIGNMENT_LEFT, size.x, small, Tokens.TEXT)
	var bar: Rect2 = Rect2(0, size.y - BAR_HEIGHT - 2, size.x, BAR_HEIGHT)
	draw_rect(bar, Tokens.BG_HOVER)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fill, 0.0, 1.0), BAR_HEIGHT)), Tokens.state_color(state))


func _make_custom_tooltip(_for_text: String) -> Object:
	var tip: Control = TipPanel.build(breakdown)
	if extra != "":
		var note: Label = Label.new()
		note.text = extra
		note.theme_type_variation = "MutedLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(280, 0)
		tip.add_child(note)
	return tip
