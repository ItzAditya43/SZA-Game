extends PanelContainer
## The card for the building selected on the map: what it is, how dangerous, how
## far, what's still inside and when you last looked, with the two things you can
## do about it: plan a scavenging trip, or move the base there.

signal plan_requested(building_id: String)
signal move_requested(building_id: String)

const UiState := preload("res://ui/ui_state.gd")
const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Insight := preload("res://core/insight.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Jobs := preload("res://systems/jobs.gd")

var ui_state: UiState
var _column: VBoxContainer
var _key: String = "?"  # "?" = needs rebuilding


func _ready() -> void:
	theme_type_variation = "Floating"
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_column = Kit.vbox(Tokens.SPACE_XS)
	add_child(_column)
	EventBus.event.connect(_on_bus_event)
	if ui_state != null:
		ui_state.building_selected.connect(func(_id: String) -> void:
			_key = "?"
			refresh())
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name in [&"run_started", &"game_loaded", &"base_moved", &"scavenge_returned", &"day_started", &"cache_recovered"]:
		_key = "?"
		refresh()


func refresh() -> void:
	var id: String = ui_state.selected_building if ui_state != null else ""
	var b: Dictionary = WorldState.building(id)
	visible = true
	if _key == id:
		return
	_key = id
	Kit.clear(_column)
	if b.is_empty():
		_column.add_child(Kit.label("Nothing selected", "HeadingLabel"))
		_column.add_child(Kit.label("Click a building on the map to see what's inside, how dangerous it is, and to plan a trip or move there.", "MutedLabel", true))
		_column.add_child(Kit.label("Pick a map layer above to see infected, noise, light, smell or disease.", "FaintLabel", true))
		return
	var head: HBoxContainer = Kit.hbox()
	_column.add_child(head)
	var title: Label = Kit.label(b["name"], "HeadingLabel", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Kit.button("Close", func() -> void: ui_state.select_building(""), "GhostButton"))
	var type: Dictionary = Data.entry("buildings", String(b["type"]))
	var danger: float = float(b["danger"])
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_column.add_child(row)
	row.add_child(Kit.chip(type["name"], "muted"))
	row.add_child(Kit.chip("danger: " + Insight.danger_word(danger), "ok" if danger < 0.2 else ("warn" if danger < 0.5 else "danger"),
		"How likely infected are trapped inside. Searching a dangerous place risks a fight."))
	row.add_child(Kit.chip(Insight.last_visit_text(b), "muted"))
	if b["stripped"]:
		row.add_child(Kit.chip("stripped" if not b.get("burned", false) else "burned out", "warn"))
	var is_base: bool = b["id"] == WorldState.base.get("building", "")
	if is_base:
		_column.add_child(Kit.label("This is your base.", "OkLabel"))
	else:
		var distance: float = Geo.street_distance_m(Geo.base_center_m(), Geo.building_center_m(b))
		var hours: float = distance / Jobs.SPEED_OUT_M_PER_H + Jobs.SEARCH_HOURS + distance / Jobs.SPEED_BACK_M_PER_H
		_column.add_child(Kit.label("%.1f km from base · a trip takes about %.1f h" % [distance / 1000.0, hours], "MutedLabel"))
	if float(b["tank_start_l"]) > 0.0:
		_column.add_child(Kit.label("Roof tank: %s of %s L (must be boiled)" % [Kit.amount(float(b["tank_l"])), Kit.amount(float(b["tank_start_l"]))], "MutedLabel"))
	if float(b["barricade"]) > 0.0:
		_column.add_child(Kit.label("Barricades: %d of %d" % [roundi(float(b["barricade"])), int(type["max_barricade"])], "MutedLabel"))
	var cached: bool = WorldState.caches.any(func(c: Dictionary) -> bool: return c["building"] == b["id"])
	if cached:
		_column.add_child(Kit.label("Your hidden cache is here.", "InfoLabel"))
	_column.add_child(Kit.label("Inside (what's left)", "MutedLabel"))
	var loot: Label = Kit.label(loot_text(b), "", true)
	_column.add_child(loot)
	if not is_base:
		var actions: HBoxContainer = Kit.hbox()
		_column.add_child(actions)
		actions.add_child(Kit.button("Plan a scavenging trip…", func() -> void: plan_requested.emit(b["id"]), "PrimaryButton"))
		actions.add_child(Kit.button("Move base here…", func() -> void: move_requested.emit(b["id"]), "Button",
			"The whole group relocates, carrying what it can"))


## What's inside, biggest first, in plain units.
static func loot_text(b: Dictionary) -> String:
	var loot: Dictionary = Stores.snapshot(b["loot"])
	if loot.is_empty():
		return "Nothing worth taking."
	var items: Array = loot.keys()
	items.sort_custom(func(x: String, y: String) -> bool:
		return Stores.weight_kg(x, float(loot[x])) * 10.0 + (100.0 if Data.entry("items", x).get("category", "") == "medicine" else 0.0) \
			> Stores.weight_kg(y, float(loot[y])) * 10.0 + (100.0 if Data.entry("items", y).get("category", "") == "medicine" else 0.0))
	var parts: PackedStringArray = []
	for item: String in items:
		var row: Dictionary = Data.entry("items", item)
		var unit: String = String(row["unit"])
		parts.append("%s %s" % [row["name"], Kit.amount(float(loot[item]), "" if unit == "count" else unit)])
	return " · ".join(parts)


## Plain-text summary of a building, for tests and screen readers.
static func describe(b: Dictionary) -> String:
	var type: Dictionary = Data.entry("buildings", String(b["type"]))
	return "%s — %s. Danger %s. %s. Remaining loot: %s" % [b["name"], type["name"], Insight.danger_word(float(b["danger"])),
		Insight.last_visit_text(b), loot_text(b)]
