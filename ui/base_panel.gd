extends ScrollContainer
## The base: its defense and what it is made of, utilities, the group's stores in
## real units, and the standing orders (rations, boiling, generator, guns).
## Changing an order sends `command_set_policy` on the bus.

const Stores := preload("res://core/stores.gd")

const POLICY_CHOICES: Array[Dictionary] = [
	{"key": &"food_ration", "label": "Food ration", "values": [&"full", &"reduced", &"half", &"minimal"],
		"names": ["Full (up to 3,000 kcal)", "Reduced (2,000)", "Half (1,500)", "Minimal (800)"]},
	{"key": &"water_ration", "label": "Water ration", "values": [&"as_needed", &"4L", &"3L", &"2L", &"1L"],
		"names": ["As needed", "4 L a day", "3 L a day", "2 L a day", "1 L a day"]},
	{"key": &"boil_water", "label": "Boil water", "values": [true, false], "names": ["Boil before drinking", "Drink it as it is"]},
	{"key": &"generator", "label": "Generator", "values": [&"off", &"evening", &"night"],
		"names": ["Off", "Evenings 18-22", "All night"]},
	{"key": &"use_guns", "label": "Firearms", "values": [false, true], "names": ["Hold fire (quiet)", "Use guns (600 m gunshot)"]},
]
const STORE_GROUPS: Array[String] = ["water", "food", "medicine", "comfort", "fuel", "materials", "gear", "vehicle", "weapon"]

var _text: RichTextLabel
var _pickers: Dictionary = {}  # policy key -> OptionButton


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for choice: Dictionary in POLICY_CHOICES:
		var label: Label = Label.new()
		label.text = choice["label"]
		grid.add_child(label)
		var picker: OptionButton = OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		for name: String in choice["names"]:
			picker.add_item(name)
		picker.item_selected.connect(func(index: int) -> void:
			EventBus.emit_event(&"command_set_policy", {"key": choice["key"], "value": choice["values"][index]}))
		grid.add_child(picker)
		_pickers[choice["key"]] = picker
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.focus_mode = Control.FOCUS_NONE
	_text.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_text)
	EventBus.event.connect(_on_bus_event)
	_refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name != &"noise" and event_name != &"light":
		_refresh()


func _refresh() -> void:
	for choice: Dictionary in POLICY_CHOICES:
		var picker: OptionButton = _pickers[choice["key"]]
		var index: int = (choice["values"] as Array).find(WorldState.policies.get(choice["key"]))
		if index >= 0:
			picker.select(index)
	_text.text = describe()


static func describe() -> String:
	var base: Dictionary = WorldState.base
	var building: Dictionary = WorldState.building(String(base.get("building", "")))
	if building.is_empty():
		return ""
	var type: Dictionary = Data.entry("buildings", String(building["type"]))
	var lines: PackedStringArray = []
	lines.append("[b][font_size=18]Base: %s[/font_size][/b]  —  %s" % [building["name"], type["name"]])
	var parts: Dictionary = base.get("defense_parts", {})
	lines.append("Defense [b]%d[/b] = building %d + barricades %d/%d + guards %d + weapons %d + others awake %d" % [
		roundi(float(base.get("defense", 0.0))), roundi(float(parts.get("building", 0.0))), roundi(float(building["barricade"])),
		int(type["max_barricade"]), roundi(float(parts.get("guards", 0.0))), roundi(float(parts.get("weapons", 0.0))),
		roundi(float(parts.get("others", 0.0)))])
	var level: StringName = base.get("attention_level", &"low")
	var level_text: Dictionary = {&"low": "low", &"rising": "[color=#f2cc60]rising[/color]", &"high": "[color=#ff7b72]high — infected are being drawn here[/color]"}
	lines.append("Attention: %s (%d) · Night attacks so far: %d (%d broke in)" % [level_text[level],
		roundi(float(base.get("attention", 0.0))), int(base.get("attacks", 0)), int(base.get("breaches", 0))])
	for cache: Dictionary in WorldState.caches:
		lines.append("Cache hidden at %s (%d%% well hidden)" % [WorldState.building(String(cache["building"]))["name"], roundi(float(cache["quality"]) * 100.0)])
	var infra: Dictionary = WorldState.infrastructure
	lines.append("Power: %s · Taps: %s · Generator: %s" % [
		"grid" if infra.get("power_on", false) else "none", "running" if infra.get("mains_on", false) else "dry",
		"running" if infra.get("generator_running", false) else "off"])
	var tank: String = ""
	if float(building["tank_start_l"]) > 0.0:
		tank = " · building tank %s L (needs boiling)" % _whole(float(building["tank_l"]))
	lines.append("Water containers: %s of %s L%s" % [_whole(Stores.stored_water_l(WorldState.stores)),
		_whole(Stores.water_capacity_l(WorldState.stores)), tank])
	lines.append("")
	lines.append("[b]Stores[/b]  —  food %s kcal (%.1f person-days at full ration)" % [
		_whole(Stores.food_kcal(WorldState.stores)), Stores.food_kcal(WorldState.stores) / 2500.0 / maxf(1.0, WorldState.group().size())])
	var snapshot: Dictionary = Stores.snapshot(WorldState.stores)
	for category: String in STORE_GROUPS:
		var parts_text: PackedStringArray = []
		for item: String in snapshot:
			var row: Dictionary = Data.entry("items", item)
			if row.get("category", "") != category:
				continue
			var unit: String = "" if row["unit"] == "count" else " " + String(row["unit"])
			parts_text.append("%s %s%s" % [row["name"], _amount(float(snapshot[item]), row), unit])
		if not parts_text.is_empty():
			lines.append("  [color=#9a9a9a]%s:[/color] %s" % [category.capitalize(), " · ".join(parts_text)])
	return "\n".join(lines)


static func _amount(qty: float, row: Dictionary) -> String:
	if String(row["unit"]) in ["count", "rounds", "units"] or qty >= 10.0:
		return _whole(qty)
	return str(snappedf(qty, 0.1))


static func _whole(qty: float) -> String:
	var digits: String = str(roundi(qty))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out
