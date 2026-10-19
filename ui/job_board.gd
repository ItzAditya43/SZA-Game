extends VBoxContainer
## Who does what: a row per job, a cell for the day shift and one for the night
## shift. Drag a name onto a cell to assign it. Unwise assignments are listed
## under the board (an exhausted guard, a feverish scavenger) with the reason.

const Kit := preload("res://ui/kit.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Body := preload("res://core/body.gd")
const Jobs := preload("res://systems/jobs.gd")
const Card := preload("res://ui/survivor_card.gd")

const JOB_HINTS: Dictionary = {
	&"rest": "Sleep and recover. Resting on the night shift means a full night's sleep.",
	&"scavenge": "Search a building (set the target with Plan a trip, or the building card on the map).",
	&"guard": "Watch the base. Adds defense against night attacks; tiring.",
	&"fortify": "Turn materials into barricades (3 per hour). Hammering draws attention.",
	&"quick_barricade": "",
	&"quick_fortify": "Fast, weaker barricades up to 40% of the building's cap: for a new base.",
	&"collect_water": "Fill containers from the taps; after they fail, fetch water from tanks or the canal.",
	&"cook": "Cook rice, dal and atta into meals (needs gas or firewood). Hot meals ease stress.",
	&"treat": "Dress and stitch wounds, slow infections. Best with medicine skill.",
}

var _grid: GridContainer
var _warnings: VBoxContainer
var _key: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", Tokens.SPACE_XS)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	add_child(_grid)
	_warnings = Kit.vbox(2)
	add_child(_warnings)
	refresh()


func refresh() -> void:
	var group: Array = WorldState.group()
	var key: String = str(group.map(func(s: Dictionary) -> String: return "%s%s%s" % [s["id"], s["jobs"], s["quarantined"]]))
	var warn: Array = unwise(group)
	key += str(warn)
	if key == _key:
		return
	_key = key
	Kit.clear(_grid)
	_grid.add_child(Kit.label("Job", "MutedLabel"))
	_grid.add_child(Kit.label("Day (06–18)", "MutedLabel"))
	_grid.add_child(Kit.label("Night (18–06)", "MutedLabel"))
	for job: StringName in Jobs.JOBS:
		var name: Label = Kit.label(Card.JOB_NAMES[job])
		name.tooltip_text = JOB_HINTS.get(job, "")
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		name.custom_minimum_size = Vector2(120, 0)
		_grid.add_child(name)
		for shift: StringName in [&"day", &"night"]:
			var cell: Cell = Cell.new()
			cell.job = job
			cell.shift = shift
			_grid.add_child(cell)
			for s: Dictionary in group:
				if s["jobs"][shift] == job:
					var chip: Chip = Chip.new()
					chip.survivor_id = s["id"]
					chip.text = s["name"]
					chip.theme_type_variation = "ChipMutedLabel" if not s["quarantined"] else "ChipWarnLabel"
					chip.tooltip_text = "Drag to another job or shift"
					cell.flow.add_child(chip)
	Kit.clear(_warnings)
	for line: String in warn:
		_warnings.add_child(Kit.label("! " + line, "WarnLabel", true))


## Reasons an assignment is unwise right now (the player can still do it).
static func unwise(group: Array) -> Array:
	var out: Array = []
	for s: Dictionary in group:
		var name: String = s["name"]
		if Body.is_incapacitated(s):
			out.append("%s can't work at all right now and will rest whatever the job." % name)
			continue
		if float(s["stress"]) >= Body.REFUSES_JOBS_STRESS and (s["jobs"][&"day"] != &"rest" or s["jobs"][&"night"] != &"rest"):
			out.append("%s is too shaken to work (stress %d) and will refuse." % [name, roundi(float(s["stress"]))])
		var late_afternoon: bool = WorldState.minute_of_day() >= 15 * 60 and WorldState.phase() == WorldState.PHASE_DAY
		if s["jobs"][&"night"] == &"guard" and (float(s["fatigue"]) > 70.0 and late_afternoon or float(s["sleep_debt_h"]) >= Body.SLEEP_DEBT_MISTAKES_H):
			out.append("%s is exhausted but on night guard: weaker defense, more risk of getting hurt." % name)
		var sick: bool = Body.worst_infection(s) != &"none" or Body.is_bleeding(s) or not s["illness"].is_empty() \
			or float(s["water_deficit_l"]) >= Body.THIRSTY_L or float(s["core_temp_c"]) >= Body.HEAT_EXHAUSTION_C
		for shift: StringName in [&"day", &"night"]:
			if s["jobs"][shift] == &"scavenge" and sick:
				out.append("%s is unwell but sent scavenging (%s): slow, and easy prey." % [name, shift])
			if s["jobs"][shift] == &"scavenge" and String(s["targets"][shift]) == "" and not s.has("plan"):
				out.append("%s is on Scavenge (%s) with no building chosen: use Plan a trip." % [name, shift])
			if s["jobs"][shift] == &"treat" and Body.skill(s, "medicine") < 3.0:
				out.append("%s has little medical skill for Treat." % name)
		if s["jobs"][&"day"] != &"rest" and s["jobs"][&"night"] != &"rest":
			out.append("%s works both shifts and never sleeps." % name)
	return out


## A cell of the board: a job for one shift. Takes dropped names.
class Cell:
	extends PanelContainer
	var job: StringName
	var shift: StringName
	var flow: HFlowContainer

	func _init() -> void:
		theme_type_variation = "Inset"
		custom_minimum_size = Vector2(150, 30)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		add_child(flow)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("survivor")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		EventBus.emit_event(&"command_set_job", {"survivor": data["survivor"], "shift": shift, "job": job})


## A survivor's name on the board. Drag it to reassign.
class Chip:
	extends Label
	var survivor_id: String

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview: Label = Label.new()
		preview.text = text
		preview.theme_type_variation = "ChipInfoLabel"
		set_drag_preview(preview)
		return {"survivor": survivor_id}
