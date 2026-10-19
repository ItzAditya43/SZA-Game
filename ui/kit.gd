extends RefCounted
## Small builders shared by every panel, so the whole UI uses the theme's type
## variations (never per-node colour overrides) and every number can explain itself.

const Tokens := preload("res://ui/theme/tokens.gd")
const Tip := preload("res://ui/tip_label.gd")
const Meter := preload("res://ui/meter.gd")


static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A label that shows a breakdown (see core/insight.gd) when hovered.
static func tip_label(text: String, breakdown: Dictionary, variation: String = "") -> Tip:
	var l: Tip = Tip.new()
	l.text = text
	l.breakdown = breakdown
	if variation != "":
		l.theme_type_variation = variation
	return l


## A small rounded word in a state colour: "ok", "warn", "danger", "info" or "muted".
## Colour is never the only signal: the word itself says the state.
static func chip(text: String, state: String = "muted", tooltip: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = "Chip%sLabel" % state.capitalize()
	l.tooltip_text = tooltip
	if tooltip != "":
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


static func button(text: String, action: Callable, variation: String = "", tooltip: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(action)
	return b


static func panel(variation: String, child: Control = null) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = variation
	if child != null:
		p.add_child(child)
	return p


static func vbox(separation: int = Tokens.SPACE_S) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = Tokens.SPACE_S) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func meter(caption: String, fill: float, value_text: String, state: String, breakdown: Dictionary = {}) -> Meter:
	var m: Meter = Meter.new()
	m.caption = caption
	m.fill = fill
	m.value_text = value_text
	m.state = state
	m.breakdown = breakdown
	return m


static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Fixes a number for display: thousands separators, or one decimal below 10.
static func amount(value: float, unit: String = "") -> String:
	var text: String
	if absf(value) >= 10.0 or unit in ["count", "rounds", "units", "strips"]:
		var n: int = roundi(value)
		var digits: String = str(absi(n))
		var out: String = ""
		while digits.length() > 3:
			out = "," + digits.substr(digits.length() - 3) + out
			digits = digits.substr(0, digits.length() - 3)
		text = ("-" if n < 0 else "") + digits + out
	else:
		text = str(snappedf(value, 0.1))
	if unit == "" or unit == "count":
		return text
	return text + " " + unit
