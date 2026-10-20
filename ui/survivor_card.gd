extends PanelContainer
## One survivor at a glance: name and what they're doing, four meters (water,
## food, sleep, stress) and condition chips. Click to expand: full body, skills,
## traits, wounds, why their stress is what it is, and their jobs.

signal plan_trip_requested(survivor_id: String)
signal focus_requested(survivor_id: String)

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Body := preload("res://core/body.gd")
const Insight := preload("res://core/insight.gd")
const Meter := preload("res://ui/meter.gd")
const Jobs := preload("res://systems/jobs.gd")

const JOB_NAMES: Dictionary = {
	&"rest": "Rest", &"scavenge": "Scavenge", &"guard": "Guard", &"fortify": "Fortify", &"quick_fortify": "Quick barricade",
	&"collect_water": "Collect water", &"cook": "Cook", &"treat": "Treat the hurt",
}
const ACTIVITY_WORDS: Dictionary = {
	&"sleeping": "asleep", &"resting": "resting", &"idle": "idle", &"light_work": "working", &"heavy_work": "working hard",
	&"guarding": "on guard", &"travelling": "on the move", &"searching": "searching", &"none": "",
}

var survivor_id: String = ""
var expanded: bool = false
var _name: Label
var _doing: Label
var _meters: Dictionary = {}
var _chips: HFlowContainer
var _details: VBoxContainer
var _detail_key: String = ""


func _ready() -> void:
	theme_type_variation = "Card"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: VBoxContainer = Kit.vbox(Tokens.SPACE_XS)
	add_child(column)
	var head: HBoxContainer = Kit.hbox()
	column.add_child(head)
	_name = Kit.label("", "HeadingLabel")
	head.add_child(_name)
	_doing = Kit.label("", "MutedLabel")
	_doing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_doing.clip_text = true
	_doing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_doing)
	var meters: HBoxContainer = Kit.hbox(Tokens.SPACE_M)
	column.add_child(meters)
	for key: String in ["water", "food", "sleep", "stress"]:
		var m: Meter = Kit.meter(key.capitalize(), 0.0, "", "ok")
		meters.add_child(m)
		_meters[key] = m
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_chips.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	column.add_child(_chips)
	_details = Kit.vbox(Tokens.SPACE_S)
	_details.visible = false
	column.add_child(_details)
	refresh()


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		expanded = not expanded
		_detail_key = ""
		refresh()
		focus_requested.emit(survivor_id)
		accept_event()


func refresh() -> void:
	var s: Dictionary = WorldState.survivor(survivor_id)
	if s.is_empty():
		return
	_name.text = s["name"]
	if s["status"] != &"ok":
		_doing.text = "%s — %s" % [String(s["status"]).to_upper(), s["cause"]]
		for key: String in _meters:
			(_meters[key] as Control).visible = false
		Kit.clear(_chips)
		_details.visible = false
		theme_type_variation = "Card"
		modulate = Color(1, 1, 1, 0.55)
		return
	_doing.text = "%s · %s" % [s["profession"], doing_text(s)]
	var meters: Dictionary = Insight.meters(s)
	for key: String in meters:
		var data: Dictionary = meters[key]
		(_meters[key] as Meter).set_values(float(data["fill"]), String(data["text"]), "danger" if data["bad"] else "ok",
			data["breakdown"], String(data.get("extra", "")))
	var chips: Array = condition_chips(s)
	var chip_key: String = str(chips)
	if _chips.get_meta("key", "") != chip_key:
		_chips.set_meta("key", chip_key)
		Kit.clear(_chips)
		for chip: Array in chips:
			_chips.add_child(Kit.chip(chip[0], chip[1], chip[2]))
	var worst: String = "ok"
	for chip: Array in chips:
		if chip[1] == "danger":
			worst = "danger"
		elif chip[1] == "warn" and worst != "danger":
			worst = "warn"
	theme_type_variation = "CardSelected" if expanded else ("CardDanger" if worst == "danger" else ("CardWarn" if worst == "warn" else "Card"))
	_details.visible = expanded
	if expanded:
		_refresh_details(s)


## What they're doing right now, in plain words.
static func doing_text(s: Dictionary) -> String:
	if s["location"] == &"away":
		var trip: Dictionary = s["trip"]
		var legs: Dictionary = {&"out": "heading to", &"search": "searching", &"back": "coming back from",
			&"fill": "fetching water at", &"prepare": "hiding supplies before leaving for", &"clear": "clearing the new base:"}
		return "%s %s" % [legs.get(trip.get("leg", &""), "away at"), trip.get("place", "town")]
	var job: String = JOB_NAMES.get(s["job_now"], String(s["job_now"]))
	var activity: String = ACTIVITY_WORDS.get(s["activity"], "")
	if s.has("plan"):
		return "%s (%s), leaves %s for %s" % [job.to_lower(), activity, WorldState.clock_string_at(int(s["plan"]["depart_tick"])).get_slice("· ", 1),
			WorldState.building(String(s["plan"]["target"])).get("name", "?")]
	return "%s, %s" % [job.to_lower(), activity] if activity != "" else job.to_lower()


## [word, state, tooltip] for each condition worth seeing at a glance.
static func condition_chips(s: Dictionary) -> Array:
	var out: Array = []
	if Body.is_bleeding(s):
		out.append(["Bleeding", "danger", "Losing blood. A bandage slows it; a medic on Treat stitches deep wounds."])
	match Body.worst_infection(s):
		&"local":
			out.append(["Wound infected", "warn", "Will turn to fever in 2-3 days, then sepsis, unless antibiotics are given."])
		&"fever":
			out.append(["Fever", "danger", "Infected wound with fever. Sepsis follows within days without antibiotics."])
		&"sepsis":
			out.append(["Sepsis", "danger", "Deadly within days. Antibiotics now, ideally with a medic at base."])
	var pathogen: Dictionary = s["pathogen"]
	if not pathogen.is_empty() and pathogen["stage"] == &"prodrome":
		out.append(["Feverish, light-sensitive", "danger", "Signs of turning. Hours left."])
	elif not pathogen.is_empty() and pathogen["known"]:
		out.append(["Bitten", "danger", "No cure. They will turn within about 1-3 days of the bite."])
	if s["quarantined"]:
		out.append(["Quarantined", "muted", "Locked away. Not working."])
	if not s["illness"].is_empty():
		out.append(["Ill: " + String(s["illness"]["type"]), "warn", "Losing fluids fast. Rehydration salts cut the loss; keep them drinking."])
	var deficit: float = float(s["water_deficit_l"])
	if deficit >= Body.DEHYDRATED_L:
		out.append(["Dehydrated", "danger", "Confused and losing health. Water now."])
	elif deficit >= Body.THIRSTY_L:
		out.append(["Thirsty", "warn", "Working slower. Needs water."])
	var debt: float = float(s["kcal_debt"])
	if debt >= Body.STARVING_KCAL:
		out.append(["Starving", "danger", "Losing health every day."])
	elif debt >= Body.WEAK_KCAL:
		out.append(["Weak from hunger", "warn", "Working 30% slower."])
	elif debt >= Body.HUNGRY_KCAL:
		out.append(["Hungry", "info", "Working a little slower; stress rising."])
	if float(s["core_temp_c"]) >= Body.HEAT_EXHAUSTION_C and Body.worst_infection(s) == &"none":
		out.append(["Heat exhaustion", "warn", "Must rest in shade. Work at dawn or dusk, keep water up."])
	if float(s["fatigue"]) > Body.EXHAUSTED_FATIGUE:
		out.append(["Exhausted", "warn", "Twice as likely to get hurt; skills drop. Needs sleep."])
	if float(s["sleep_debt_h"]) >= Body.SLEEP_DEBT_MISTAKES_H:
		out.append(["Short of sleep", "info", "Mistakes and accidents rise."])
	var stress: float = float(s["stress"])
	if stress >= Body.MAY_LEAVE_STRESS:
		out.append(["May leave", "danger", "Morale broken: may slip away any night."])
	elif stress >= Body.REFUSES_JOBS_STRESS:
		out.append(["Too shaken to work", "warn", "Refuses jobs until stress falls below 80. Rest, hot meals and safety help."])
	for injury: Dictionary in s["injuries"]:
		if injury["infection"] == &"none" and float(injury["bleed_l_h"]) <= 0.01:
			out.append(["%s (%s)" % [String(Body.visible_wound_type(injury)).capitalize(), injury["location"]], "muted",
				"Healing. %s" % ("Stitched." if injury["stitched"] else ("Bandaged." if injury["bandaged"] else "Undressed: higher infection risk."))])
	return out


@warning_ignore("integer_division")
func _refresh_details(s: Dictionary) -> void:
	var key: String = "%s|%s|%s|%s" % [s["jobs"], s["targets"], s.get("plan", {}), WorldState.tick / 6]
	if key == _detail_key:
		return
	_detail_key = key
	Kit.clear(_details)
	var body: HFlowContainer = HFlowContainer.new()
	body.add_theme_constant_override("h_separation", Tokens.SPACE_L)
	_details.add_child(body)
	body.add_child(Kit.tip_label("Health %d" % roundi(float(s["health"])), Insight.health_breakdown(s)))
	body.add_child(Kit.label("Blood %.1f / %.1f L" % [float(s["blood_l"]), float(s["blood_full_l"])]))
	body.add_child(Kit.label("Body temp %.1f °C" % float(s["core_temp_c"])))
	body.add_child(Kit.label("Fatigue %d" % roundi(float(s["fatigue"]))))
	body.add_child(Kit.label("Sleep debt %.1f h" % float(s["sleep_debt_h"])))
	var skills: Dictionary = s["skills"]
	_details.add_child(Kit.label("Skills: scavenging %d · medicine %d · combat %d" % [int(skills["scavenging"]),
		int(skills["medicine"]), int(skills["combat"])], "MutedLabel"))
	for id: String in s.get("traits", []):
		var row: Dictionary = Data.entry("traits", id)
		_details.add_child(Kit.label("%s: %s" % [row.get("name", id), row.get("text", "")], "MutedLabel", true))
	var stress: Dictionary = Insight.stress_breakdown(s)
	if not stress["contributions"].is_empty():
		var parts: PackedStringArray = []
		for item: Dictionary in stress["contributions"].slice(0, 5):
			parts.append("%s%d %s" % ["+" if float(item["amount"]) > 0.0 else "", roundi(float(item["amount"])), item["label"]])
		_details.add_child(Kit.label("Stress %d, last 3 days: %s" % [roundi(float(s["stress"])), ", ".join(parts)], "", true))
	var jobs: HBoxContainer = Kit.hbox()
	_details.add_child(jobs)
	for shift: StringName in [&"day", &"night"]:
		jobs.add_child(Kit.label("Day job" if shift == &"day" else "Night job", "MutedLabel"))
		var picker: OptionButton = OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		for job: StringName in Jobs.JOBS:
			picker.add_item(JOB_NAMES[job])
		picker.select(Jobs.JOBS.find(s["jobs"][shift]))
		picker.item_selected.connect(func(index: int) -> void:
			EventBus.emit_event(&"command_set_job", {"survivor": survivor_id, "shift": shift, "job": Jobs.JOBS[index]}))
		jobs.add_child(picker)
	var actions: HBoxContainer = Kit.hbox()
	_details.add_child(actions)
	actions.add_child(Kit.button("Plan a scavenging trip…", func() -> void: plan_trip_requested.emit(survivor_id), "PrimaryButton"))
	if s.has("plan"):
		actions.add_child(Kit.button("Cancel planned trip", func() -> void:
			EventBus.emit_event(&"command_cancel_plan", {"survivor": survivor_id})
			_detail_key = ""
			refresh(), "GhostButton"))
