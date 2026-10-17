extends ScrollContainer
## Details of the building selected on the map: type, danger, trip time from base,
## water tank, barricades and the loot still inside. Buttons send a survivor to
## scavenge it or move the base there.

const UiState := preload("res://ui/ui_state.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")

## Read-only use of Jobs' tuning constants, so the trip estimate matches the simulation.
const Jobs := preload("res://systems/jobs.gd")

var ui_state: UiState
var text: RichTextLabel
var _actions: VBoxContainer
var _actions_for: String = "-"
var _roster_key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.focus_mode = Control.FOCUS_NONE
	column.add_child(text)
	_actions = VBoxContainer.new()
	column.add_child(_actions)
	EventBus.event.connect(_on_bus_event)
	if ui_state != null:
		ui_state.building_selected.connect(func(_id: String) -> void: refresh())
	refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name in [&"tick", &"run_started", &"base_moved", &"scavenge_returned", &"command_set_job"]:
		refresh()


func refresh() -> void:
	var id: String = ui_state.selected_building if ui_state != null else ""
	var building: Dictionary = WorldState.building(id)
	if building.is_empty():
		text.text = "[i]Click a building on the map to see what is inside.[/i]"
		_rebuild_actions({})
		return
	text.text = describe(building)
	var key: String = id + "|" + ",".join(WorldState.group().map(func(s: Dictionary) -> String: return s["id"]))
	if key != _actions_for + "|" + _roster_key:
		_rebuild_actions(building)


## The panel text for a building. Public so tests can check what a click shows.
static func describe(building: Dictionary) -> String:
	var type: Dictionary = Data.entry("buildings", String(building["type"]))
	var lines: PackedStringArray = []
	lines.append("[b][font_size=18]%s[/font_size][/b]  —  %s" % [building["name"], type["name"]])
	var danger: float = float(building["danger"])
	lines.append("Danger: %s (%.2f) · Looted by others: %d%% a day · Door: %s · Visits: %d" % [
		_danger_word(danger), danger, roundi(float(type["daily_looted_rate"]) * 100.0),
		"locked" if building["locked"] else "open", int(building["visits"])])
	var is_base: bool = building["id"] == WorldState.base.get("building", "")
	if is_base:
		lines.append("[color=#3fd18b]This is your base.[/color]")
	else:
		var distance: float = Geo.street_distance_m(Geo.base_center_m(), Geo.building_center_m(building))
		var hours: float = distance / Jobs.SPEED_OUT_M_PER_H + Jobs.SEARCH_HOURS + distance / Jobs.SPEED_BACK_M_PER_H
		lines.append("%.1f km from base by street · a scavenging trip takes about %.1f h" % [distance / 1000.0, hours])
	if float(building["tank_start_l"]) > 0.0:
		lines.append("Water tank: %s L of %s L (needs boiling)" % [_whole(float(building["tank_l"])), _whole(float(building["tank_start_l"]))])
	lines.append("Barricades: %d of %d" % [roundi(float(building.get("barricade", 0.0))), int(type.get("max_barricade", 0))])
	lines.append("")
	if building["stripped"]:
		lines.append("[color=#ff9b6a]Stripped almost bare.[/color]")
	lines.append("[b]Remaining loot[/b]")
	var loot: Dictionary = Stores.snapshot(building["loot"])
	if loot.is_empty():
		lines.append("  nothing")
	var start: Dictionary = building["start_loot"]
	for item: String in loot:
		var row: Dictionary = Data.entry("items", item)
		var unit: String = "" if row["unit"] == "count" else " " + String(row["unit"])
		lines.append("  %s: %s%s  [color=#8a8a8a](of %s)[/color]" % [row["name"], _amount(float(loot[item]), row),
			unit, _amount(float(start.get(item, loot[item])), row)])
	return "\n".join(lines)


func _rebuild_actions(building: Dictionary) -> void:
	_actions_for = building.get("id", "")
	_roster_key = ",".join(WorldState.group().map(func(s: Dictionary) -> String: return s["id"]))
	for child: Node in _actions.get_children():
		child.queue_free()
	if building.is_empty() or building["id"] == WorldState.base.get("building", ""):
		return
	var title: Label = Label.new()
	title.text = "Send to scavenge here:"
	_actions.add_child(title)
	for s: Dictionary in WorldState.group():
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = s["name"]
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		for shift: StringName in [&"day", &"night"]:
			var button: Button = Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.text = "%s shift" % String(shift).capitalize()
			button.pressed.connect(func() -> void:
				EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": shift, "job": &"scavenge", "target": building["id"]}))
			row.add_child(button)
		_actions.add_child(row)
	var move: Button = Button.new()
	move.focus_mode = Control.FOCUS_NONE
	move.text = "Move base here"
	move.tooltip_text = "The whole group relocates, carrying what it can. Barricades stay with the old building."
	move.pressed.connect(func() -> void: EventBus.emit_event(&"command_move_base", {"building": building["id"]}))
	_actions.add_child(move)


static func _danger_word(danger: float) -> String:
	if danger < 0.2:
		return "low"
	if danger < 0.5:
		return "medium"
	if danger < 0.8:
		return "high"
	return "very high"


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
