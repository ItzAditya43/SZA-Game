extends ScrollContainer
## One card per survivor: what they are doing, their body in real units, wounds,
## and their day/night jobs. Changing a job sends `command_set_job` on the bus.

const Body := preload("res://core/body.gd")
const UiState := preload("res://ui/ui_state.gd")

const JOBS: Array[StringName] = [&"rest", &"scavenge", &"guard", &"fortify", &"collect_water", &"cook", &"treat"]
const ACTIVITY_TEXT: Dictionary = {
	&"sleeping": "asleep", &"resting": "resting", &"idle": "idle", &"light_work": "working",
	&"heavy_work": "working hard", &"guarding": "on guard", &"travelling": "travelling",
	&"searching": "searching", &"none": "",
}

var ui_state: UiState
var _list: VBoxContainer
var _cards: Dictionary = {}  # survivor id -> {"text": RichTextLabel, "day": OptionButton, ...}
var _roster_key: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	EventBus.event.connect(_on_bus_event)
	if ui_state != null:
		ui_state.building_selected.connect(func(_id: String) -> void: _refresh())
	_refresh()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name in [&"tick", &"run_started", &"survivor_joined", &"survivor_died", &"survivor_turned",
			&"survivor_left", &"survivor_exiled", &"decision_made", &"command_set_job"]:
		_refresh()


func _refresh() -> void:
	var key: String = ",".join(WorldState.survivors.map(func(s: Dictionary) -> String: return "%s:%s" % [s["id"], s["status"]]))
	if key != _roster_key:
		_roster_key = key
		_rebuild()
	for s: Dictionary in WorldState.survivors:
		if _cards.has(s["id"]):
			_update_card(s, _cards[s["id"]])


func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_cards.clear()
	for s: Dictionary in WorldState.survivors:
		var panel: PanelContainer = PanelContainer.new()
		var column: VBoxContainer = VBoxContainer.new()
		panel.add_child(column)
		var text: RichTextLabel = RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.focus_mode = Control.FOCUS_NONE
		text.add_theme_font_size_override("normal_font_size", 13)
		text.add_theme_font_size_override("bold_font_size", 15)
		column.add_child(text)
		var card: Dictionary = {"text": text}
		if s["status"] == &"ok":
			var row: HBoxContainer = HBoxContainer.new()
			column.add_child(row)
			for shift: StringName in [&"day", &"night"]:
				var label: Label = Label.new()
				label.text = "Day job" if shift == &"day" else "Night job"
				row.add_child(label)
				var picker: OptionButton = OptionButton.new()
				picker.focus_mode = Control.FOCUS_NONE
				for job: StringName in JOBS:
					picker.add_item(String(job).replace("_", " "))
				picker.item_selected.connect(_on_job_picked.bind(s["id"], shift))
				row.add_child(picker)
				card[shift] = picker
			var target_row: HBoxContainer = HBoxContainer.new()
			column.add_child(target_row)
			var target_label: Label = Label.new()
			target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			target_row.add_child(target_label)
			card["target_label"] = target_label
			for shift: StringName in [&"day", &"night"]:
				var target_button: Button = Button.new()
				target_button.focus_mode = Control.FOCUS_NONE
				target_button.text = "Scavenge selected (%s)" % shift
				target_button.tooltip_text = "Send them to the building selected on the map during the %s shift" % shift
				target_button.pressed.connect(_on_target_pressed.bind(s["id"], shift))
				target_row.add_child(target_button)
				card["target_" + String(shift)] = target_button
		_list.add_child(panel)
		_cards[s["id"]] = card


func _update_card(s: Dictionary, card: Dictionary) -> void:
	var text: RichTextLabel = card["text"]
	if s["status"] != &"ok":
		text.text = "[b]%s[/b] — %s  [color=#ff7b72]%s (%s)[/color]" % [s["name"], s["profession"], String(s["status"]).to_upper(), s["cause"]]
		return
	var lines: PackedStringArray = []
	var where: String = "at base" if s["location"] == &"base" else _trip_text(s)
	lines.append("[b]%s[/b] — %s, %d · [i]%s, %s[/i]" % [s["name"], s["profession"], int(s["age"]),
		String(s["job_now"]).replace("_", " "), ACTIVITY_TEXT.get(s["activity"], String(s["activity"]))]
		+ " · " + where)
	lines.append("Water: %s deficit, drank %.1f L today   Food: %s debt, ate %s today" % [
		_warn("%.1f L" % float(s["water_deficit_l"]), float(s["water_deficit_l"]) >= Body.THIRSTY_L),
		float(s["drunk_today_l"]),
		_warn("%s kcal" % _thousands(float(s["kcal_debt"])), float(s["kcal_debt"]) >= Body.HUNGRY_KCAL),
		_thousands(float(s["kcal_eaten_today"])) + " kcal"])
	lines.append("Health %s · Blood %.1f/%.1f L · Core %s · Fatigue %s · Sleep debt %.1f h · Stress %s (morale %d)" % [
		_warn("%d" % roundi(float(s["health"])), float(s["health"]) < 50.0),
		float(s["blood_l"]), float(s["blood_full_l"]),
		_warn("%.1f °C" % float(s["core_temp_c"]), float(s["core_temp_c"]) >= Body.HEAT_EXHAUSTION_C),
		_warn("%d" % roundi(float(s["fatigue"])), float(s["fatigue"]) > Body.EXHAUSTED_FATIGUE),
		float(s["sleep_debt_h"]),
		_warn("%d" % roundi(float(s["stress"])), float(s["stress"]) >= Body.REFUSES_JOBS_STRESS),
		roundi(Body.morale(s))])
	var conditions: Array[String] = Body.conditions(s)
	var wounds: PackedStringArray = []
	for injury: Dictionary in s["injuries"]:
		var parts: PackedStringArray = [String(Body.visible_wound_type(injury)), String(injury["location"])]
		if float(injury["bleed_l_h"]) > 0.01:
			parts.append("bleeding %.2f L/h" % float(injury["bleed_l_h"]))
		if injury["tourniquet"]:
			parts.append("tourniquet")
		if injury["stitched"]:
			parts.append("stitched")
		elif injury["bandaged"]:
			parts.append("bandaged")
		if injury["infection"] != &"none":
			parts.append("infection: " + String(injury["infection"]))
		wounds.append(" ".join(parts))
	if not conditions.is_empty() or not wounds.is_empty():
		lines.append("[color=#f2cc60]%s%s[/color]" % [", ".join(conditions),
			("   Wounds: " + "; ".join(wounds)) if not wounds.is_empty() else ""])
	lines.append("[color=#9a9a9a]Skills: scavenging %d · medicine %d · combat %d[/color]" % [
		int(s["skills"]["scavenging"]), int(s["skills"]["medicine"]), int(s["skills"]["combat"])])
	text.text = "\n".join(lines)
	for shift: StringName in [&"day", &"night"]:
		if card.has(shift):
			var picker: OptionButton = card[shift]
			picker.select(JOBS.find(s["jobs"][shift]))
	if card.has("target_label"):
		var target_label: Label = card["target_label"]
		target_label.text = "Scavenge targets — day: %s · night: %s" % [
			_building_name(String(s["targets"]["day"])), _building_name(String(s["targets"]["night"]))]
		var has_selection: bool = ui_state != null and ui_state.selected_building != ""
		for shift: String in ["day", "night"]:
			var button: Button = card["target_" + shift]
			button.disabled = not has_selection


func _on_job_picked(index: int, survivor_id: String, shift: StringName) -> void:
	EventBus.emit_event(&"command_set_job", {"survivor": survivor_id, "shift": shift, "job": JOBS[index]})


func _on_target_pressed(survivor_id: String, shift: StringName) -> void:
	if ui_state == null or ui_state.selected_building == "":
		return
	EventBus.emit_event(&"command_set_job", {"survivor": survivor_id, "shift": shift, "job": &"scavenge",
		"target": ui_state.selected_building})


static func _trip_text(s: Dictionary) -> String:
	var trip: Dictionary = s["trip"]
	if trip.is_empty():
		return "away"
	var legs: Dictionary = {&"out": "heading to", &"search": "searching", &"back": "returning from", &"fill": "ferrying water at"}
	return "%s %s" % [legs.get(trip.get("leg", &""), "away at"), trip.get("place", "town")]


static func _building_name(id: String) -> String:
	if id == "":
		return "none"
	var building: Dictionary = WorldState.building(id)
	return building.get("name", id) if not building.is_empty() else id


static func _warn(text: String, bad: bool) -> String:
	return "[color=#ff9b6a]%s[/color]" % text if bad else text


static func _thousands(value: float) -> String:
	var n: int = roundi(value)
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
