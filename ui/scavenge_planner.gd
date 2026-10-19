extends PanelContainer
## The scavenge planner: pick a target, a team and when to leave, see what the trip
## will cost before you commit (time, risk, noise, carrying), and put what to bring
## back in order. Estimates come from core/insight.gd, which uses the simulation's
## own formulas. Confirming sends command_plan_trip for each team member.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Insight := preload("res://core/insight.gd")
const Body := preload("res://core/body.gd")
const Geo := preload("res://core/geo.gd")
const BuildingPanel := preload("res://ui/building_panel.gd")

const DEPARTURES: Array[StringName] = [&"now", &"midday", &"dusk", &"night"]
const DEPART_NAMES: Dictionary = {&"now": "Now", &"midday": "Midday heat (12:00)", &"dusk": "Dusk (17:30)", &"night": "Night (20:00)"}
const DEPART_HELP: Dictionary = {
	&"now": "Leave as soon as they're ready.",
	&"midday": "Infected are sluggish in the heat, but people overheat working outdoors.",
	&"dusk": "Cooler; infected waking up.",
	&"night": "Infected most active; searching by torchlight is slower and finds less.",
}
const DEFAULT_PRIORITIES: Array[String] = ["medicine", "water", "food", "fuel", "tools", "materials"]
const BAND_STATE: Dictionary = {"low": "ok", "moderate": "info", "high": "warn", "severe": "danger"}

var _target: String = ""
var _team: Array = []
var _depart: StringName = &"now"
var _priorities: Array = DEFAULT_PRIORITIES.duplicate()
var _column: VBoxContainer


func _ready() -> void:
	theme_type_variation = "Modal"
	visible = false
	_column = Kit.vbox(Tokens.SPACE_S)
	_column.custom_minimum_size = Vector2(720, 0)
	add_child(_column)


func open(target_id: String, survivor_id: String = "") -> void:
	_target = target_id
	if _target == "" or _target == WorldState.base.get("building", ""):
		_target = _nearest_unvisited()
	_team = [survivor_id] if survivor_id != "" else []
	if _team.is_empty():
		var best: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return _able(s) and s["location"] == &"base")
		best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Body.skill(a, "scavenging") > Body.skill(b, "scavenging"))
		if not best.is_empty():
			_team = [best[0]["id"]]
	_depart = &"now"
	visible = true
	_rebuild()
	_center.call_deferred()


func close() -> void:
	visible = false


func _rebuild() -> void:
	Kit.clear(_column)
	_column.add_child(Kit.label("Plan a scavenging trip", "TitleLabel"))
	var target: Dictionary = WorldState.building(_target)
	# Target.
	var row: HBoxContainer = Kit.hbox()
	_column.add_child(row)
	row.add_child(Kit.label("Where", "HeadingLabel"))
	var picker: OptionButton = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	var choices: Array = _targets()
	for b: Dictionary in choices:
		picker.add_item("%s — %s, %.1f km%s" % [b["name"], Data.entry("buildings", String(b["type"]))["name"],
			Geo.street_distance_m(Geo.base_center_m(), Geo.building_center_m(b)) / 1000.0, " (stripped)" if b["stripped"] else ""])
	picker.select(maxi(0, choices.map(func(b: Dictionary) -> String: return b["id"]).find(_target)))
	picker.item_selected.connect(func(index: int) -> void:
		_target = choices[index]["id"]
		_rebuild())
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	if not target.is_empty():
		_column.add_child(Kit.label("Inside: " + BuildingPanel.loot_text(target), "MutedLabel", true))
		_column.add_child(Kit.label("Danger %s · %s" % [Insight.danger_word(float(target["danger"])), Insight.last_visit_text(target)], "MutedLabel"))
	# Team.
	_column.add_child(Kit.label("Who goes", "HeadingLabel"))
	var team: HFlowContainer = HFlowContainer.new()
	team.add_theme_constant_override("h_separation", Tokens.SPACE_M)
	_column.add_child(team)
	for s: Dictionary in WorldState.group():
		var box: CheckBox = CheckBox.new()
		box.focus_mode = Control.FOCUS_NONE
		var problem: String = _problem(s)
		box.text = "%s (scav %d)%s" % [s["name"], int(s["skills"]["scavenging"]), (" — " + problem) if problem != "" else ""]
		box.button_pressed = _team.has(s["id"])
		box.disabled = s["location"] != &"base" or not _able(s)
		box.toggled.connect(func(on: bool) -> void:
			if on and not _team.has(s["id"]):
				_team.append(s["id"])
			elif not on:
				_team.erase(s["id"])
			_rebuild())
		team.add_child(box)
	# When.
	_column.add_child(Kit.label("When to leave", "HeadingLabel"))
	var when: HBoxContainer = Kit.hbox()
	_column.add_child(when)
	for depart: StringName in DEPARTURES:
		var band: String = _worst_band(depart)
		var button: Button = Kit.button("%s\nrisk: %s" % [DEPART_NAMES[depart], band], func() -> void:
			_depart = depart
			_rebuild(), "Button", DEPART_HELP[depart])
		button.toggle_mode = true
		button.button_pressed = depart == _depart
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		when.add_child(button)
	_column.add_child(Kit.label(DEPART_HELP[_depart], "MutedLabel", true))
	# Estimates.
	_column.add_child(Kit.label("What it will take", "HeadingLabel"))
	if _team.is_empty() or target.is_empty():
		_column.add_child(Kit.label("Pick someone to go.", "WarnLabel"))
	for id: String in _team:
		var s: Dictionary = WorldState.survivor(id)
		var est: Dictionary = Insight.trip_estimate(s, target, _depart)
		var line: HBoxContainer = Kit.hbox()
		_column.add_child(line)
		line.add_child(Kit.label(s["name"], "HeadingLabel"))
		line.add_child(Kit.label("leaves %s, back about %s (%.1f h) · carries up to %.0f kg" % [
			WorldState.clock_string_at(int(est["depart_tick"])), WorldState.clock_string_at(int(est["return_tick"])),
			float(est["hours"]), float(est["carry_kg"])]))
		line.add_child(Kit.chip("risk %s: %d%% chance of getting hurt" % [est["band"], roundi(float(est["hurt"]) * 100.0)],
			BAND_STATE[est["band"]], "Meeting infected somewhere on the trip: %d%%. Most meetings end with slipping past or fighting them off.\nFrom infected numbers along the route and at the building, time of day and heat, their stealth, combat skill, weapon and wounds." % roundi(float(est["risk"]) * 100.0)))
	if not _team.is_empty() and not target.is_empty():
		var est0: Dictionary = Insight.trip_estimate(WorldState.survivor(String(_team[0])), target, _depart)
		_column.add_child(Kit.label("Noise: " + String(est0["noise"]) + ("  · Night search: slower, finds less." if est0["night_search"] else ""), "MutedLabel", true))
	# Priorities.
	_column.add_child(Kit.label("Bring back first (drag or use the arrows)", "HeadingLabel"))
	var list: VBoxContainer = Kit.vbox(2)
	_column.add_child(list)
	for i: int in _priorities.size():
		var item: PriorityRow = PriorityRow.new()
		item.planner = self
		item.index = i
		list.add_child(item)
		var h: HBoxContainer = Kit.hbox()
		item.add_child(h)
		h.add_child(Kit.label("%d. %s" % [i + 1, String(_priorities[i]).capitalize()]))
		h.add_child(Kit.spacer())
		h.add_child(Kit.button("↑", func() -> void: move_priority(i, i - 1), "GhostButton", "Earlier"))
		h.add_child(Kit.button("↓", func() -> void: move_priority(i, i + 1), "GhostButton", "Later"))
	# Actions.
	var actions: HBoxContainer = Kit.hbox()
	actions.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(actions)
	actions.add_child(Kit.button("Cancel", close, "GhostButton"))
	var go: Button = Kit.button("Send them", _confirm, "PrimaryButton")
	go.disabled = _team.is_empty() or target.is_empty()
	actions.add_child(go)


func move_priority(from: int, to: int) -> void:
	if to < 0 or to >= _priorities.size():
		return
	var item: Variant = _priorities.pop_at(from)
	_priorities.insert(to, item)
	_rebuild()


func _confirm() -> void:
	for id: String in _team:
		EventBus.emit_event(&"command_plan_trip", {"survivor": id, "target": _target, "depart": _depart, "priorities": _priorities.duplicate()})
	close()


func _worst_band(depart: StringName) -> String:
	var target: Dictionary = WorldState.building(_target)
	if target.is_empty() or _team.is_empty():
		return "-"
	var order: Array = ["low", "moderate", "high", "severe"]
	var worst: int = 0
	for id: String in _team:
		worst = maxi(worst, order.find(Insight.trip_estimate(WorldState.survivor(id), target, depart)["band"]))
	return order[worst]


static func _able(s: Dictionary) -> bool:
	return not s["quarantined"] and not Body.is_incapacitated(s) and float(s["stress"]) < Body.REFUSES_JOBS_STRESS


static func _problem(s: Dictionary) -> String:
	if s["location"] != &"base":
		return "away"
	if s["quarantined"]:
		return "quarantined"
	if Body.is_incapacitated(s):
		return "can't work"
	if float(s["stress"]) >= Body.REFUSES_JOBS_STRESS:
		return "too shaken"
	if Body.is_bleeding(s) or Body.worst_infection(s) != &"none":
		return "hurt: easy prey"
	if float(s["fatigue"]) > Body.EXHAUSTED_FATIGUE:
		return "exhausted"
	if float(s["water_deficit_l"]) >= Body.THIRSTY_L:
		return "thirsty"
	return ""


## Every building but the base, nearest first.
func _targets() -> Array:
	var home: Vector2 = Geo.base_center_m()
	var list: Array = WorldState.buildings.filter(func(b: Dictionary) -> bool: return b["id"] != WorldState.base.get("building", ""))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Geo.street_distance_m(home, Geo.building_center_m(a)) < Geo.street_distance_m(home, Geo.building_center_m(b)))
	return list


func _nearest_unvisited() -> String:
	for b: Dictionary in _targets():
		if not b["stripped"]:
			return b["id"]
	return _targets()[0]["id"]


func _center() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	reset_size()


## A priority you can drag onto another to swap places.
class PriorityRow:
	extends PanelContainer
	var planner: Object
	var index: int

	func _init() -> void:
		theme_type_variation = "Inset"
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview: Label = Label.new()
		preview.text = "moving…"
		preview.theme_type_variation = "ChipInfoLabel"
		set_drag_preview(preview)
		return {"priority": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("priority")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		planner.call("move_priority", int(data["priority"]), index)
