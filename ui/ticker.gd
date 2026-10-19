extends PanelContainer
## The bottom strip: the last three things that happened. Click one to see where.

signal locate_requested(payload: Dictionary)

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const EventLog := preload("res://ui/event_log.gd")

const SHOWN: int = 3

var _row: VBoxContainer
var _key: String = ""


func _ready() -> void:
	theme_type_variation = "Ticker"
	_row = Kit.vbox(0)
	add_child(_row)
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"tick" and event_name != &"noise":
		refresh()


func refresh() -> void:
	var entries: Array = EventLog.visible_entries("All")
	entries = entries.filter(func(e: Dictionary) -> bool: return e["name"] != &"day_started")
	var recent: Array = entries.slice(maxi(entries.size() - SHOWN, 0))
	var key: String = str(recent.map(func(e: Dictionary) -> int: return int(e["tick"]))) + str(recent.size())
	if key == _key:
		return
	_key = key
	Kit.clear(_row)
	if recent.is_empty():
		_row.add_child(Kit.label("Nothing has happened yet. Press Space or 1 to let time run.", "MutedLabel"))
	for entry: Dictionary in recent:
		var line: Button = EventLog.line(entry, func(payload: Dictionary) -> void: locate_requested.emit(payload))
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.clip_text = true
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_row.add_child(line)
