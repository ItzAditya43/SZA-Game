extends "res://tests/checks_base.gd"
## The tutorial: data/tutorial.json is consistent with the game's events, tips queue
## and are remembered, the Getting started list ticks off, the guide opens and
## pauses, and a whole run with the screen attached raises tips without errors.

const Tutorial := preload("res://ui/tutorial.gd")
const Settings := preload("res://ui/settings.gd")
const GettingStarted := preload("res://ui/getting_started.gd")

## Triggers the HUD sends itself (not bus events).
const UI_TRIGGERS: Array[String] = ["building_selected", "planner_opened", "overlay_set", "alerts_first",
	"tab_People", "tab_Stores", "tab_Base", "tab_Log", "tab_Stats", "speed_used", "guard_set"]
const TABS: Array[String] = ["People", "Stores", "Base", "Log", "Stats"]


func run_checks() -> void:
	Settings.persist = false
	_check_data()
	_check_triggers_are_real()
	_check_trigger_mapping()


func _source_text() -> String:
	var text: String = ""
	for dir: String in ["res://systems", "res://core"]:
		for file: String in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				text += FileAccess.get_file_as_string(dir.path_join(file))
	return text


func _check_data() -> void:
	var hints: Dictionary = Tutorial.hints()
	var bad: PackedStringArray = []
	for id: String in hints:
		var hint: Dictionary = hints[id]
		if String(hint.get("on", "")) == "" or String(hint.get("text", "")).length() < 40:
			bad.append(id)
	expect("every tip names its trigger and has real text", bad.is_empty(), ", ".join(bad))
	var long: PackedStringArray = []
	for id: String in hints:
		if String(hints[id]["text"]).length() > 420:
			long.append(id)
	expect("no tip is a wall of text (420 characters at most)", long.is_empty(), ", ".join(long))
	var pages: Array = Tutorial.guide()
	expect("the guide has pages, each with a title and a body",
		pages.size() >= 5 and pages.all(func(p: Dictionary) -> bool: return String(p["title"]) != "" and String(p["body"]).length() > 60))
	expect("the Getting started list has steps, each with text, a reason and a way to finish",
		Tutorial.steps().size() >= 3 and Tutorial.steps().all(func(s: Dictionary) -> bool:
			return String(s["id"]) != "" and String(s["text"]) != "" and String(s["why"]) != "" and String(s["done_on"]) != ""))


## A typo in a trigger would make a tip that never shows: every trigger must be a
## bus event some system or core file emits, or one the HUD sends.
func _check_triggers_are_real() -> void:
	var source: String = _source_text()
	var unknown: PackedStringArray = []
	var all: Array[String] = []
	for id: String in Tutorial.hints():
		all.append(String(Tutorial.hints()[id]["on"]))
	for step: Dictionary in Tutorial.steps():
		all.append(String(step["done_on"]))
	for trigger: String in all:
		if not UI_TRIGGERS.has(trigger) and not source.contains('&"%s"' % trigger):
			unknown.append(trigger)
	expect("every tip and step trigger is a UI trigger or an event the simulation emits", unknown.is_empty(), ", ".join(unknown))
	var tab_missing: PackedStringArray = []
	for tab: String in TABS:
		if not Tutorial.hints().values().any(func(h: Dictionary) -> bool: return h["on"] == "tab_" + tab):
			tab_missing.append(tab)
	expect("every side-panel tab has an explanatory tip", tab_missing.is_empty(), ", ".join(tab_missing))
	var step_ids: Array = Tutorial.steps().map(func(s: Dictionary) -> String: return s["id"])
	expect("Getting started step ids are unique", step_ids.size() == Array(step_ids).duplicate().filter(func(i: String) -> bool: return step_ids.count(i) == 1).size())


func _check_trigger_mapping() -> void:
	start(950)
	TickLoop.set_speed(TickLoop.Speed.PAUSED)
	expect("a night guard order completes the guard step", Tutorial.triggers(&"command_set_job", {"job": &"guard", "shift": &"night"}) == ["guard_set"])
	expect("a day guard order does not", Tutorial.triggers(&"command_set_job", {"job": &"guard", "shift": &"day"}).is_empty())
	expect("ticks raise nothing (they would be checked every 10 minutes)", Tutorial.triggers(&"tick", {}).is_empty())
	var gated: Dictionary = {"on": "x", "max_day": 0}
	expect("a Day 0 tip applies on Day 0 and not on Day 3", Tutorial.applies(gated) and not _applies_on_day(gated, 3))
	var night: Dictionary = {"on": "phase_changed", "when": "night"}
	expect("a night tip does not apply at dawn", not Tutorial.applies(night) or WorldState.phase() == WorldState.PHASE_NIGHT)


func _applies_on_day(hint: Dictionary, day: int) -> bool:
	var before: int = WorldState.tick
	WorldState.tick = day * WorldState.TICKS_PER_DAY + 40
	var result: bool = Tutorial.applies(hint)
	WorldState.tick = before
	return result


# --- The main screen ---

func check_screen(main: Node) -> void:
	var hud: Control = main.get_node("HUD")
	var hints: Control = hud.get("hints")
	var list: Control = hud.get("getting_started")
	Settings.reset_hints()
	Settings.overrides.erase("hints/guide_seen")
	start(951)
	hud.get("start_screen").visible = false
	hints.call("turn_off")
	Settings.reset_hints()
	_check_tip_queue(hud, hints)
	_check_ui_triggers(hud, hints)
	_check_getting_started(hud, list)
	_check_guide(hud)
	_check_whole_run(hud, hints)
	# The first-run guide opens through a deferred call: see check_launch and check_after.
	# Launch order, as main.gd does it: a backdrop world starts, then the start screen opens.
	Settings.reset_hints()
	SimRun.start(952)
	hud.get("start_screen").visible = true


func _check_tip_queue(_hud: Control, hints: Control) -> void:
	hints.call("show_hint", "tab_stores")
	expect("a tip shows when raised", hints.visible)
	hints.call("show_hint", "tab_base")
	hints.call("show_hint", "tab_base")
	expect("a second tip waits its turn, and is queued once", (hints.get("_queue") as Array).size() == 1 and hints.visible
		and String((hints.get("_text") as Label).text).begins_with("Stores"))
	expect("the card says another tip is waiting", String((hints.get("_more") as Label).text).contains("1 more"))
	hints.call("dismiss")
	expect("Got it shows the next waiting tip", hints.visible and String((hints.get("_text") as Label).text).begins_with("Base"))
	hints.call("dismiss")
	expect("Got it on the last tip closes the card", not hints.visible)
	hints.call("show_hint", "tab_stores")
	expect("a tip that has been dismissed never comes back", not hints.visible)
	Settings.reset_hints()
	hints.call("show_hint", "tab_stores")
	expect("'Show the tips again' brings tips back", hints.visible)
	hints.call("turn_off")
	hints.call("show_hint", "tab_base")
	hints.call("show_hint", "first_death")
	expect("'No more tips' turns every tip off", not hints.visible and (hints.get("_queue") as Array).is_empty())
	Settings.reset_hints()


func _check_ui_triggers(hud: Control, hints: Control) -> void:
	var tabs: TabContainer = hud.get("tabs")
	tabs.current_tab = 0
	hints.call("dismiss")
	Settings.reset_hints()
	tabs.current_tab = 2
	expect("opening the Base tab shows the Base tip", hints.visible and String((hints.get("_text") as Label).text).begins_with("Base"))
	hints.call("dismiss")
	hud.get("ui_state").select_building("grocery_02")
	expect("selecting a building shows the building tip", hints.visible and String((hints.get("_text") as Label).text).contains("danger"))
	hints.call("dismiss")
	hud.call("set_overlay", "noise")
	expect("switching a map layer explains the layers", hints.visible and String((hints.get("_text") as Label).text).begins_with("Map layers"))
	hints.call("dismiss")
	hud.get("planner").call("open", "grocery_02", "")
	expect("opening the trip planner explains it", hints.visible and String((hints.get("_text") as Label).text).contains("Send"))
	hints.call("dismiss")
	hud.get("planner").visible = false
	hud.get("ui_state").select_building("")
	tabs.current_tab = 0
	Settings.reset_hints()


func _check_getting_started(hud: Control, list: Control) -> void:
	Settings.reset_hints()
	list.call("rebuild")
	expect("a fresh player sees the Getting started list", list.visible and not GettingStarted.all_done())
	expect("a run starting at 1x does not tick the clock step by itself", not GettingStarted.is_done("run"))
	var top: Control = hud.get("top_bar")
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	top.call("_unhandled_key_input", space)
	expect("pressing Space ticks the clock step", GettingStarted.is_done("run"),
		str(hud.get_tree().get_nodes_in_group(&"modal").filter(func(n: Node) -> bool: return (n as Control).visible).map(func(n: Node) -> String: return n.get_script().resource_path)))
	TickLoop.set_speed(TickLoop.Speed.PAUSED)
	hud.get("ui_state").select_building("house_01")
	expect("clicking a building ticks its step", GettingStarted.is_done("building"))
	var s: Dictionary = WorldState.group()[0]
	EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": &"night", "job": &"guard"})
	expect("a night guard order ticks the guard step", GettingStarted.is_done("guard"))
	(hud.get("tabs") as TabContainer).current_tab = 1
	expect("opening Stores ticks its step", GettingStarted.is_done("stores"))
	expect("the list stays until the trip step is done too", list.visible and not GettingStarted.is_done("trip"))
	var target: String = "grocery_02"
	EventBus.emit_event(&"command_plan_trip", {"survivor": WorldState.group()[1]["id"], "target": target, "depart": &"midday"})
	expect("planning a trip ticks the trip step", GettingStarted.is_done("trip"), str(captured.filter(func(e: Dictionary) -> bool: return e["name"] == &"trip_planned").size()))
	expect("once every step is done the list goes away", GettingStarted.all_done() and not list.visible)
	(hud.get("tabs") as TabContainer).current_tab = 0
	hud.get("ui_state").select_building("")
	Settings.reset_hints()
	list.call("rebuild")
	expect("'Show the tips again' brings the list back", list.visible)


func _check_guide(hud: Control) -> void:
	var guide: Control = hud.get("guide")
	TickLoop.set_speed(TickLoop.Speed.X1)
	hud.call("open_guide")
	expect("the guide opens and pauses the game", guide.visible and TickLoop.speed == TickLoop.Speed.PAUSED)
	expect("the guide counts as an open pop-up", hud.call("modal_open"))
	var pages: int = Tutorial.guide().size()
	expect("the guide starts on page 1 with Back disabled", int(guide.get("_page")) == 0 and (guide.get("_back") as Button).disabled)
	guide.call("show_page", 1)
	expect("Next moves on", int(guide.get("_page")) == 1 and String((guide.get("_title") as Label).text) == String(Tutorial.guide()[1]["title"]))
	guide.call("show_page", 999)
	expect("the last page offers Done, not Next", int(guide.get("_page")) == pages - 1 and (guide.get("_next") as Button).text == "Done")
	var fits: bool = true
	for i: int in pages:
		guide.call("show_page", i)
		var size: Vector2 = guide.get_combined_minimum_size()
		fits = fits and size.y < 640.0 and size.x < 1000.0
	expect("every guide page fits a 720p screen", fits)
	guide.call("close")
	expect("closing the guide hides it", not guide.visible and not hud.call("modal_open"))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	(hud.get("top_bar") as Control).call("_unhandled_key_input", key)
	expect("H opens the guide", guide.visible)
	guide.call("close")
	var buttons: Array = _buttons(hud.get("save_menu"))
	hud.get("save_menu").call("open_pause")
	buttons = _buttons(hud.get("save_menu"))
	expect("the pause menu has a How to play entry", buttons.has("How to play…"), str(buttons))
	hud.get("save_menu").call("close")
	expect("the start screen has a How to play button", _buttons(hud.get("start_screen")).has("How to play"))
	expect("the shortcuts card lists H", (load("res://ui/shortcuts.gd").KEYS as Array).any(func(r: Array) -> bool: return r[0] == "H"))


func _buttons(node: Node) -> Array:
	var out: Array = []
	for child: Node in node.find_children("*", "Button", true, false):
		out.append((child as Button).text)
	return out


## A whole run with the screen attached raises tips without errors, never shows a
## blank one, and the first one at least is the opening tip.
func _check_whole_run(hud: Control, hints: Control) -> void:
	Settings.reset_hints()
	SimRun.start(953)
	var first: String = String((hints.get("_text") as Label).text)
	expect("a new run opens with the start tip", hints.visible and first.begins_with("Your five survivors"), first.left(40))
	var shown: Dictionary = {}
	var blank: int = 0
	for day: int in 12:
		TickLoop.run_headless(WorldState.TICKS_PER_DAY)
		if hints.visible:
			var text: String = String((hints.get("_text") as Label).text)
			shown[text] = true
			blank += 1 if text.strip_edges() == "" else 0
			hints.call("dismiss")
	expect("twelve days with the screen attached raise tips and none are blank", shown.size() >= 3 and blank == 0, "%d different tips" % shown.size())


## One frame later: the deferred check has run for the launch world.
func check_launch(main: Node) -> void:
	var hud: Control = main.get_node("HUD")
	expect("at launch the start screen shows and the guide waits for the first real run",
		hud.get("start_screen").visible and not hud.get("guide").visible)
	# A real start, as start_screen does it: hide the screen, start a run, then set the speed.
	hud.get("start_screen").visible = false
	SimRun.start(953)
	TickLoop.set_speed(TickLoop.Speed.X1)


## Called a frame after that: the deferred first-run guide has had its turn.
func check_after(main: Node) -> int:
	var hud: Control = main.get_node("HUD")
	var guide: Control = hud.get("guide")
	expect("the first run on a fresh install opens the guide, paused", guide.visible and TickLoop.speed == TickLoop.Speed.PAUSED)
	guide.call("close")
	TickLoop.set_speed(TickLoop.Speed.X1)
	SimRun.start(954)
	expect("later runs do not open the guide again", not guide.visible)
	print("\n%d/%d checks passed" % [checks - failures, checks])
	return 1 if failures > 0 else 0
