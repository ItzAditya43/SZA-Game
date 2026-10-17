extends PanelContainer
## The scrolling event log: the last bus events with their time. Events that carry
## a "text" payload show that sentence; others show their name and payload.

const LOG_LINES: int = 40
## Bookkeeping events the player does not need to read.
const HIDDEN_EVENTS: Array[StringName] = [&"phase_changed", &"speed_changed", &"policy_changed", &"decision_made", &"command_set_job",
	&"command_set_policy", &"command_move_base", &"command_add_survivor", &"encounter_avoided"]

var _view: RichTextLabel


func _ready() -> void:
	_view = RichTextLabel.new()
	_view.bbcode_enabled = true
	_view.scroll_following = true
	_view.focus_mode = Control.FOCUS_NONE
	var monospace: SystemFont = SystemFont.new()
	monospace.font_names = PackedStringArray(["monospace"])
	_view.add_theme_font_override("mono_font", monospace)
	_view.add_theme_font_size_override("normal_font_size", 13)
	add_child(_view)
	EventBus.event.connect(_on_bus_event)
	_refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"tick":
		_refresh()


func _refresh() -> void:
	var lines: PackedStringArray = []
	var entries: Array[Dictionary] = EventBus.event_log.filter(
		func(e: Dictionary) -> bool: return not HIDDEN_EVENTS.has(e["name"]))
	for entry: Dictionary in entries.slice(maxi(entries.size() - LOG_LINES, 0)):
		var payload: Dictionary = entry["payload"]
		var at: String = WorldState.clock_string_at(int(entry["tick"]))
		var body: String
		if payload.has("text"):
			body = String(payload["text"]).replace("[", "[lb]")
		else:
			body = "[color=#9a9a9a]%s %s[/color]" % [entry["name"], str(payload).replace("[", "[lb]")]
		var color: String = _color_for(entry["name"])
		lines.append("[code][color=#8a8a8a]%s[/color][/code]  [color=%s]%s[/color]" % [at, color, body])
	_view.text = "\n".join(lines)


static func _color_for(event_name: StringName) -> String:
	if event_name in [&"survivor_died", &"survivor_turned", &"base_breached", &"run_lost"]:
		return "#ff7b72"
	if event_name in [&"decision_needed", &"bite_reported", &"hidden_bite_found", &"prodrome_started",
			&"infection_worsened", &"wound_infected", &"illness_started", &"encounter", &"night_attack"]:
		return "#f2cc60"
	if event_name in [&"run_won", &"survivor_joined", &"antibiotics_given", &"scavenge_returned"]:
		return "#7ee787"
	return "#e6e6e6"
