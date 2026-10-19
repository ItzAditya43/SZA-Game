extends RefCounted
## Builds the hover card for a breakdown: what the number is, each cause with its
## size, and what it means next. Shared by tip labels, meters and the map.

const Tokens := preload("res://ui/theme/tokens.gd")


static func build(breakdown: Dictionary) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Tokens.SPACE_XS)
	box.custom_minimum_size = Vector2(280, 0)
	if breakdown.is_empty():
		return box
	var unit: String = String(breakdown.get("unit", ""))
	var title: Label = Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.text = "%s: %s" % [String(breakdown.get("label", "")).capitalize(), _fmt(float(breakdown.get("value", 0.0)), unit)]
	box.add_child(title)
	for item: Dictionary in breakdown.get("contributions", []):
		var row: HBoxContainer = HBoxContainer.new()
		var name: Label = Label.new()
		name.text = String(item["label"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value: Label = Label.new()
		var amount: float = float(item["amount"])
		value.text = ("+" if amount > 0.0 and _is_change(breakdown) else "") + _fmt(amount, unit)
		value.theme_type_variation = ("DangerLabel" if amount > 0.0 else "OkLabel") if _is_change(breakdown) else ""
		row.add_child(value)
		box.add_child(row)
	var forecast: String = String(breakdown.get("forecast", ""))
	if forecast != "":
		var note: Label = Label.new()
		note.theme_type_variation = "MutedLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(280, 0)
		note.text = forecast
		box.add_child(note)
	return box


## Stress breakdowns list changes (gains bad, relief good) rather than parts of a whole.
static func _is_change(breakdown: Dictionary) -> bool:
	return String(breakdown.get("label", "")).begins_with("stress")


static func _fmt(value: float, unit: String) -> String:
	var text: String
	if absf(value) >= 100.0:
		var n: int = roundi(value)
		var digits: String = str(absi(n))
		var out: String = ""
		while digits.length() > 3:
			out = "," + digits.substr(digits.length() - 3) + out
			digits = digits.substr(0, digits.length() - 3)
		text = ("-" if n < 0 else "") + digits + out
	else:
		text = str(snappedf(value, 0.1))
	return text if unit == "" else "%s %s" % [text, unit]
