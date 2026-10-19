extends ScrollContainer
## The Stats tab: the run so far as charts, one point per day (systems/history.gd).
## The end screen reuses build_charts().

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Chart := preload("res://ui/line_chart.gd")

const SERIES: Array[Dictionary] = [
	{"key": "water_l", "title": "Water in hand", "unit": "L", "color": Tokens.WATER},
	{"key": "food_kcal", "title": "Food in stores", "unit": "kcal", "color": Tokens.OK},
	{"key": "alive", "title": "People in the group", "unit": "", "color": Tokens.GROUP},
	{"key": "avg_stress", "title": "Average stress", "unit": "", "color": Tokens.WARN},
	{"key": "infected", "title": "Infected in town", "unit": "", "color": Tokens.INFECTED},
	{"key": "attention", "title": "Attention at base", "unit": "", "color": Tokens.NOISE},
]

var _column: VBoxContainer
var _rows: int = -1


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = Kit.vbox(Tokens.SPACE_M)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name in [&"day_started", &"run_started", &"game_loaded", &"run_won", &"run_lost"]:
		refresh()


func refresh() -> void:
	var history: Array = WorldState.stats.get("history", [])
	if history.size() == _rows:
		return
	_rows = history.size()
	Kit.clear(_column)
	_column.add_child(Kit.label("One point per day, counted at midnight.", "MutedLabel"))
	for chart: Control in build_charts(history):
		_column.add_child(chart)


static func build_charts(history: Array) -> Array:
	var out: Array = []
	for series: Dictionary in SERIES:
		var chart: Chart = Chart.new()
		chart.title = series["title"]
		chart.unit = series["unit"]
		chart.color = series["color"]
		var points: Array = []
		for row: Dictionary in history:
			points.append([float(row["tick"]) / WorldState.TICKS_PER_DAY, float(row.get(series["key"], 0.0))])
		chart.points = points
		out.append(chart)
	return out
