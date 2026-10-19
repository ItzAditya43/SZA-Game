extends VBoxContainer
## The Log tab: everything that happened, newest at the bottom, with a filter.
## Click a line to jump to where it happened on the map.

signal locate_requested(payload: Dictionary)

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")

const LOG_LINES: int = 60
## Bookkeeping the player does not need to read.
const HIDDEN_EVENTS: Array[StringName] = [&"phase_changed", &"speed_changed", &"policy_changed", &"decision_made",
	&"command_set_job", &"command_set_policy", &"command_move_base", &"command_add_survivor", &"command_plan_trip",
	&"command_cancel_plan", &"game_saved"]
const FILTERS: Dictionary = {
	"All": [],
	"Danger": [&"survivor_died", &"survivor_turned", &"base_breached", &"night_attack", &"encounter", &"bite_reported",
		&"hidden_bite_found", &"prodrome_started", &"infection_worsened", &"wound_infected", &"illness_started"],
	"Supplies": [&"scavenge_returned", &"water_collected", &"food_spoiled", &"cache_recovered", &"cache_lost", &"rain_caught",
		&"building_stripped", &"pharmacy_looted"],
	"Town": [&"story_event", &"power_failed", &"mains_failed", &"phones_down", &"mains_warning", &"power_warning",
		&"noise_drew_infected", &"buildings_burned"],
}
const DANGER_EVENTS: Array[StringName] = [&"survivor_died", &"survivor_turned", &"base_breached", &"run_lost"]
const WARN_EVENTS: Array[StringName] = [&"decision_needed", &"bite_reported", &"hidden_bite_found", &"prodrome_started",
	&"infection_worsened", &"wound_infected", &"illness_started", &"encounter", &"night_attack", &"mains_warning", &"power_warning"]

var _filter: String = "All"
var _list: VBoxContainer
var _scroll: ScrollContainer
var _pinned: bool = true
var _shown: String = ""


func _ready() -> void:
	var filters: HBoxContainer = Kit.hbox(Tokens.SPACE_XS)
	add_child(filters)
	filters.add_child(Kit.label("Show:", "MutedLabel"))
	for name: String in FILTERS:
		filters.add_child(Kit.button(name, func() -> void:
			_filter = name
			_shown = ""
			refresh(), "GhostButton"))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = Kit.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	# Stay pinned to the newest line while the reader hasn't scrolled up; the bar's
	# range is only known after layout, so follow it as it changes.
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	bar.changed.connect(func() -> void:
		if _pinned:
			_scroll.scroll_vertical = int(bar.max_value))
	bar.value_changed.connect(func(v: float) -> void:
		_pinned = v >= bar.max_value - bar.page - 4.0)
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"tick" and event_name != &"noise":
		refresh()


func refresh() -> void:
	var entries: Array = visible_entries(_filter)
	var key: String = "%s|%d|%d" % [_filter, entries.size(), int(entries[-1]["tick"]) if not entries.is_empty() else -1]
	if key == _shown:
		return
	_shown = key
	Kit.clear(_list)
	for entry: Dictionary in entries.slice(maxi(entries.size() - LOG_LINES, 0)):
		_list.add_child(line(entry, func(payload: Dictionary) -> void: locate_requested.emit(payload)))
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	_pinned = true
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


static func visible_entries(filter: String) -> Array:
	var allowed: Array = FILTERS.get(filter, [])
	return EventBus.event_log.filter(func(e: Dictionary) -> bool:
		return not HIDDEN_EVENTS.has(e["name"]) and e["payload"].has("text") and (allowed.is_empty() or allowed.has(e["name"])))


## How serious an event is: "danger", "warn" or "".
static func severity(event_name: StringName) -> String:
	return "danger" if DANGER_EVENTS.has(event_name) else ("warn" if WARN_EVENTS.has(event_name) else "")


## One clickable log line: the time, a marker for serious events ([!] or [!!],
## so colour is never the only sign), and the sentence.
static func line(entry: Dictionary, on_click: Callable) -> Button:
	var payload: Dictionary = entry["payload"]
	var b: Button = Button.new()
	b.theme_type_variation = "GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var level: String = severity(entry["name"])
	var mark: String = {"danger": "[!!] ", "warn": "[!] "}.get(level, "")
	b.text = "%s   %s%s" % [WorldState.clock_string_at(int(entry["tick"])), mark, payload["text"]]
	if payload.has("x_m") or payload.has("building") or payload.has("survivor"):
		b.tooltip_text = "Show on the map"
		b.pressed.connect(func() -> void: on_click.call(payload))
	return b
