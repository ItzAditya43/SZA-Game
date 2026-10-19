extends ScrollContainer
## The Base tab: where the group lives, how strong it is and why, how much
## attention it's drawing and why, and the standing orders. Each order says what
## it costs before you pick it.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Insight := preload("res://core/insight.gd")
const Stores := preload("res://core/stores.gd")

const ORDERS: Array[Dictionary] = [
	{"key": &"food_ration", "label": "Food ration", "values": [&"full", &"reduced", &"half", &"minimal"],
		"names": ["Full (up to 3,000 kcal)", "Reduced (2,000)", "Half (1,500)", "Minimal (800)"],
		"help": "Less food stretches stores, but hungry people work slower and get stressed."},
	{"key": &"water_ration", "label": "Water ration", "values": [&"as_needed", &"4L", &"3L", &"2L", &"1L"],
		"names": ["As needed", "4 L a day", "3 L a day", "2 L a day", "1 L a day"],
		"help": "People need 3-6 L a day in this heat. Below that they dehydrate within days."},
	{"key": &"boil_water", "label": "Boil water", "values": [true, false], "names": ["Boil before drinking", "Drink it as it is"],
		"help": "Boiling costs cooking gas or firewood. Untreated tank or canal water gives a 30% daily chance of dysentery or cholera."},
	{"key": &"generator", "label": "Generator", "values": [&"off", &"evening", &"night"], "names": ["Off", "Evenings 18–22", "All night"],
		"help": "Light and a working fridge, for 1 L of fuel an hour. Its noise and light draw attention."},
	{"key": &"use_guns", "label": "Firearms", "values": [false, true], "names": ["Hold fire (quiet)", "Use guns"],
		"help": "Guns win fights, but a shot carries 600 m and draws infected and attention."},
]

var _column: VBoxContainer
var _info: VBoxContainer
var _pickers: Dictionary = {}
var _key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = Kit.vbox(Tokens.SPACE_S)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_column)
	_info = Kit.vbox(Tokens.SPACE_S)
	_column.add_child(_info)
	_column.add_child(HSeparator.new())
	_column.add_child(Kit.label("Standing orders", "HeadingLabel"))
	for order: Dictionary in ORDERS:
		var row: HBoxContainer = Kit.hbox()
		var name: Label = Kit.label(order["label"])
		name.custom_minimum_size = Vector2(110, 0)
		row.add_child(name)
		var picker: OptionButton = OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		picker.tooltip_text = order["help"]
		for text: String in order["names"]:
			picker.add_item(text)
		picker.item_selected.connect(func(index: int) -> void:
			EventBus.emit_event(&"command_set_policy", {"key": order["key"], "value": order["values"][index]}))
		row.add_child(picker)
		_column.add_child(row)
		_column.add_child(Kit.label(order["help"], "MutedLabel", true))
		_pickers[order["key"]] = picker
	EventBus.event.connect(_on_bus_event)
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"noise" and (event_name != &"tick" or WorldState.tick % 3 == 0):
		refresh()


@warning_ignore("integer_division")
func refresh() -> void:
	for order: Dictionary in ORDERS:
		var index: int = (order["values"] as Array).find(WorldState.policies.get(order["key"]))
		if index >= 0:
			(_pickers[order["key"]] as OptionButton).select(index)
	var key: String = "%d|%s|%s" % [WorldState.tick / 3, WorldState.base.get("building", ""), WorldState.caches.size()]
	if key == _key:
		return
	_key = key
	Kit.clear(_info)
	var building: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	if building.is_empty():
		return
	var type: Dictionary = Data.entry("buildings", String(building["type"]))
	_info.add_child(Kit.label("Base: %s" % building["name"], "SubtitleLabel"))
	_info.add_child(Kit.label("%s · to move, click another building on the map and choose Move base here." % type["name"], "MutedLabel", true))
	var defense: Dictionary = Insight.defense_breakdown()
	var row: HBoxContainer = Kit.hbox()
	row.add_child(Kit.tip_label("Defense %d" % roundi(float(defense["value"])), defense, "HeadingLabel"))
	row.add_child(Kit.label("barricades %d of %d · %d attacks so far, %d broke in" % [roundi(float(building["barricade"])),
		int(type["max_barricade"]), int(WorldState.base.get("attacks", 0)), int(WorldState.base.get("breaches", 0))], "MutedLabel"))
	_info.add_child(row)
	var attention: Dictionary = Insight.attention_breakdown()
	var level: StringName = WorldState.base.get("attention_level", &"low")
	var state: String = {&"low": "ok", &"rising": "warn", &"high": "danger"}[level]
	row = Kit.hbox()
	row.add_child(Kit.tip_label("Attention %d" % roundi(float(attention["value"])), attention, "HeadingLabel"))
	row.add_child(Kit.chip(String(level), state, "How much the base is giving itself away. Hover the number for why."))
	_info.add_child(row)
	_info.add_child(Kit.label(String(attention["forecast"]), "MutedLabel", true))
	var tank: float = float(building["tank_l"])
	_info.add_child(Kit.label("Water containers %s of %s L%s" % [Kit.amount(Stores.stored_water_l(WorldState.stores)),
		Kit.amount(Stores.water_capacity_l(WorldState.stores)),
		(" · roof tank %s L" % Kit.amount(tank)) if float(building["tank_start_l"]) > 0.0 else ""], "MutedLabel"))
	for cache: Dictionary in WorldState.caches:
		_info.add_child(Kit.label("Hidden cache at %s (%d%% well hidden). Send someone there to dig it out." % [
			WorldState.building(String(cache["building"])).get("name", "?"), roundi(float(cache["quality"]) * 100.0)], "InfoLabel", true))
