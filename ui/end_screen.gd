extends PanelContainer
## Shown when the run is won or lost: what happened and the score, each person's
## fate, the run as charts, and the key decisions and losses on a timeline.
## "New run" asks the main scene to start again.

signal new_run_requested

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Stats := preload("res://ui/stats_panel.gd")

const TIMELINE_KINDS: Array[String] = ["decision", "loss", "move", "attack"]

var _column: VBoxContainer
var _charts: GridContainer
var _timeline: VBoxContainer
var _text: RichTextLabel


func _ready() -> void:
	visible = false
	theme_type_variation = "Modal"
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(980, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_column = Kit.vbox(Tokens.SPACE_M)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_column)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(940, 0)
	_column.add_child(_text)
	_charts = GridContainer.new()
	_charts.columns = 3
	_column.add_child(_charts)
	_column.add_child(Kit.label("How it went", "HeadingLabel"))
	_timeline = Kit.vbox(2)
	_column.add_child(_timeline)
	var row: HBoxContainer = Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(row)
	row.add_child(Kit.button("Look around", func() -> void: visible = false, "GhostButton"))
	row.add_child(Kit.button("New run", func() -> void:
		visible = false
		new_run_requested.emit(), "PrimaryButton"))
	EventBus.event.connect(_on_bus_event)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"run_won" or event_name == &"run_lost":
		show_outcome.call_deferred()
	elif event_name in [&"run_started", &"game_loaded"]:
		visible = false


func show_outcome() -> void:
	_text.text = describe(WorldState.outcome)
	Kit.clear(_charts)
	for chart: Control in Stats.build_charts(WorldState.stats.get("history", [])):
		chart.custom_minimum_size = Vector2(300, 120)
		_charts.add_child(chart)
	Kit.clear(_timeline)
	for item: Dictionary in WorldState.stats.get("timeline", []):
		if not TIMELINE_KINDS.has(String(item["kind"])):
			continue
		var mark: String = {"decision": "Decided", "loss": "Lost", "move": "Moved", "attack": "Attacked"}[item["kind"]]
		_timeline.add_child(Kit.label("%s   %s: %s" % [WorldState.clock_string_at(int(item["tick"])), mark, item["text"]],
			"DangerLabel" if item["kind"] == "loss" else "", true))
	visible = true
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()


static func describe(outcome: Dictionary) -> String:
	var won: bool = outcome["state"] == &"won"
	var lines: PackedStringArray = []
	lines.append("[center][font_size=28][b]%s[/b][/font_size][/center]" % ("You survived" if won else "The group is gone"))
	lines.append("[center]%s  (%s, %s)[/center]" % [outcome["reason"], WorldState.clock_string_at(int(outcome["tick"])),
		WorldState.difficulty.get("name", "")])
	lines.append("")
	lines.append("[b]Score %d[/b] = %d alive × 100 + %d days on full rations × 10 + %d for supplies stored" % [
		roundi(float(outcome["score"])), int(outcome["alive"]), int(outcome["full_ration_days"]), roundi(float(outcome["supplies_points"]))])
	lines.append("Night attacks: %d (%d broke in) · Infected killed by the group: %d" % [
		int(WorldState.stats.get("attacks", 0)), int(WorldState.stats.get("breaches", 0)), int(WorldState.stats.get("infected_killed", 0))])
	var fates: Dictionary = outcome["fates"]
	var parts: PackedStringArray = []
	for name: String in fates:
		parts.append("%s: %s" % [name, "alive" if fates[name] == "alive" else "[i]%s[/i]" % fates[name]])
	lines.append("Fates: " + " · ".join(parts))
	return "\n".join(lines)
