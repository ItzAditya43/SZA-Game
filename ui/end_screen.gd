extends PanelContainer
## Shown when the run is won or lost: what happened, the score and how it was
## made, and each survivor's fate. "New run" asks the main scene to start again.

signal new_run_requested

var _text: RichTextLabel


func _ready() -> void:
	visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.96)
	style.border_color = Color(1, 1, 1, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(600, 0)
	column.add_child(_text)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	var close: Button = Button.new()
	close.text = "Look around"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	row.add_child(close)
	var again: Button = Button.new()
	again.text = "New run"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void:
		visible = false
		new_run_requested.emit())
	row.add_child(again)
	EventBus.event.connect(_on_bus_event)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"run_won" or event_name == &"run_lost":
		_text.text = describe(WorldState.outcome)
		visible = true
		_center.call_deferred()
	elif event_name == &"run_started":
		visible = false


static func describe(outcome: Dictionary) -> String:
	var won: bool = outcome["state"] == &"won"
	var lines: PackedStringArray = []
	lines.append("[center][font_size=28][b]%s[/b][/font_size][/center]" % ("You survived" if won else "The group is gone"))
	lines.append("[center]%s  (%s)[/center]" % [outcome["reason"], WorldState.clock_string_at(int(outcome["tick"]))])
	lines.append("")
	lines.append("[b]Score %d[/b] = %d alive × 100 + %d days on full rations × 10 + %d for supplies stored" % [
		roundi(float(outcome["score"])), int(outcome["alive"]), int(outcome["full_ration_days"]), roundi(float(outcome["supplies_points"]))])
	lines.append("Night attacks: %d (%d broke in) · Infected killed by the group: %d" % [
		int(WorldState.stats.get("attacks", 0)), int(WorldState.stats.get("breaches", 0)), int(WorldState.stats.get("infected_killed", 0))])
	lines.append("")
	var fates: Dictionary = outcome["fates"]
	for name: String in fates:
		var fate: String = fates[name]
		lines.append("  %s — %s" % [name, "[color=#7ee787]alive[/color]" if fate == "alive" else "[color=#ff7b72]%s[/color]" % fate])
	return "\n".join(lines)


func _center() -> void:
	reset_size()
	var parent_size: Vector2 = get_parent_area_size()
	position = ((parent_size - size) / 2.0).floor()
