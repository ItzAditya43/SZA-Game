extends ScrollContainer
## The Stores tab: how long water, food, fuel and medicine will last at the
## group's current use, with a trend since yesterday, then everything in stores.
## Hover any forecast for where the number comes from.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Insight := preload("res://core/insight.gd")
const Stores := preload("res://core/stores.gd")
const Meter := preload("res://ui/meter.gd")

const GROUPS: Array[String] = ["water", "food", "medicine", "comfort", "fuel", "materials", "gear", "vehicle", "weapon"]

var _column: VBoxContainer
var _key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = Kit.vbox(Tokens.SPACE_S)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"noise" and (event_name != &"tick" or WorldState.tick % 6 == 0):
		refresh()


@warning_ignore("integer_division")
func refresh() -> void:
	var key: String = "%d|%s" % [WorldState.tick / 6, Stores.snapshot(WorldState.stores).size()]
	if key == _key:
		return
	_key = key
	Kit.clear(_column)
	_column.add_child(Kit.label("How long things last", "HeadingLabel"))
	var water: Dictionary = Insight.water_forecast()
	var food: Dictionary = Insight.food_forecast()
	var fuel: Dictionary = Insight.fuel_forecast()
	var medicine: Dictionary = Insight.medicine_forecast()
	_forecast_row("Water", water, float(water["days"]), "%s L" % Kit.amount(float(water["value"])), float(water["trend"]), "L")
	_forecast_row("Food", food, float(food["days"]), "%s kcal" % Kit.amount(float(food["value"])), float(food["trend"]), "kcal")
	var gas_days: float = float(fuel["value"]) / maxf(0.01, _gas_per_day())
	_forecast_row("Cooking gas", fuel, gas_days, "%s kg" % Kit.amount(float(fuel["value"])), 0.0, "kg")
	var strips: float = float(medicine["value"])
	var med: Dictionary = {"state": "danger" if strips < 1.0 else ("warn" if strips < 3.0 else "ok")}
	var row: HBoxContainer = Kit.hbox()
	row.add_child(Kit.tip_label("Antibiotics: %d strips" % roundi(strips), medicine))
	row.add_child(Kit.chip("none" if strips < 1.0 else ("few" if strips < 3.0 else "ok"), med["state"]))
	_column.add_child(row)
	_column.add_child(HSeparator.new())
	_column.add_child(Kit.label("In stores", "HeadingLabel"))
	var snapshot: Dictionary = Stores.snapshot(WorldState.stores)
	for category: String in GROUPS:
		var parts: PackedStringArray = []
		for item: String in snapshot:
			var item_row: Dictionary = Data.entry("items", item)
			if item_row.get("category", "") != category:
				continue
			var unit: String = String(item_row["unit"])
			parts.append("%s %s" % [item_row["name"], Kit.amount(float(snapshot[item]), "" if unit == "count" else unit)])
		if not parts.is_empty():
			var line: Label = Kit.label("%s: %s" % [category.capitalize(), " · ".join(parts)], "", true)
			_column.add_child(line)
	if snapshot.is_empty():
		_column.add_child(Kit.label("Nothing. Everyone is away or the stores were left behind.", "MutedLabel", true))


func _forecast_row(name: String, breakdown: Dictionary, days: float, amount: String, trend: float, unit: String) -> void:
	var row: HBoxContainer = Kit.hbox()
	var state: String = "ok" if days >= 4.0 else ("warn" if days >= 2.0 else "danger")
	var days_text: String = "taps running" if days == INF else ("%.1f days" % days)
	var m: Meter = Kit.meter(name, clampf(days / 7.0, 0.0, 1.0) if days != INF else 1.0, days_text, state, breakdown)
	m.custom_minimum_size = Vector2(220, 34)
	row.add_child(m)
	row.add_child(Kit.tip_label(amount, breakdown, "MutedLabel"))
	if trend != 0.0:
		var arrow: String = "rising" if trend > 0.0 else "falling"
		row.add_child(Kit.chip("%s %s%s" % [arrow, "+" if trend > 0.0 else "", Kit.amount(trend, unit)], "ok" if trend > 0.0 else "muted",
			"Change since yesterday's count"))
	_column.add_child(row)


## A rough day's gas: cooking the group's food plus boiling its water.
func _gas_per_day() -> float:
	const Resources := preload("res://systems/resources.gd")
	var kcal: float = 0.0
	for s: Dictionary in WorldState.group():
		kcal += float(Insight.food_need(s)["value"])
	var boil: float = Insight.group_water_need() if WorldState.policies.get(&"boil_water", true) and not WorldState.infrastructure.get("mains_on", false) else 0.0
	return kcal / 1000.0 * Resources.COOK_GAS_KG_PER_1000_KCAL + boil / 10.0 * Resources.BOIL_GAS_KG_PER_10L
