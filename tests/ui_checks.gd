extends "res://tests/checks_base.gd"
## Phase 2, prompt 2: the numbers the UI shows come from the simulation's own rules,
## and the screen builds and runs headless without errors.

const Insight := preload("res://core/insight.gd")
const Jobs := preload("res://systems/jobs.gd")
const Attention := preload("res://systems/attention.gd")
const Alerts := preload("res://ui/alerts.gd")
const StatsPanel := preload("res://ui/stats_panel.gd")
const Decisions := preload("res://core/decisions.gd")


func run_checks() -> void:
	_check_trip_estimate_matches_trip()
	_check_attention_breakdown_matches_gain()
	_check_forecasts()
	_check_risk_bands_follow_time_of_day()
	_check_history_and_timeline()
	_check_alerts_use_what_the_group_knows()
	# The screen check runs from test_ui.gd one frame later: nodes added while the
	# test script initialises only become ready once the tree starts running.


func _rest_everyone() -> void:
	for s: Dictionary in WorldState.survivors:
		for shift: StringName in [&"day", &"night"]:
			EventBus.emit_event(&"command_set_job", {"survivor": s["id"], "shift": shift, "job": &"rest"})
	Stores.add(WorldState.stores, "water_bottled", 300.0)
	Stores.add(WorldState.stores, "packaged_food", 100000.0)


# --- Part E: the planner's estimate is the trip the simulation runs ---

func _check_trip_estimate_matches_trip() -> void:
	var errors: PackedStringArray = []
	for target: String in ["kirana_02", "school_01", "pharmacy_01"]:
		for depart: StringName in [&"midday", &"dusk"]:
			start(900)
			_rest_everyone()
			# No infected anywhere: an encounter would wound them and slow the walk home.
			for zone: Dictionary in WorldState.zones:
				zone["infected"] = 0.0
			var s: Dictionary = WorldState.group()[1]
			var b: Dictionary = WorldState.building(target)
			EventBus.emit_event(&"command_plan_trip", {"survivor": s["id"], "target": target, "depart": depart})
			TickLoop.run_headless(Jobs.departure_tick(depart) - WorldState.tick)
			var estimate: Dictionary = Insight.trip_estimate(s, b, depart)
			TickLoop.run_headless(ticks_for_hours(float(estimate["hours"]) + 3.0))
			var started: Array[Dictionary] = events_named(&"scavenge_started")
			var returned: Array[Dictionary] = events_named(&"scavenge_returned")
			if started.is_empty() or returned.is_empty():
				errors.append("%s/%s: no trip ran" % [target, depart])
				continue
			var off_out: int = int(started[0]["tick"]) - int(estimate["depart_tick"])
			var off_back: int = int(returned[0]["tick"]) - int(estimate["return_tick"])
			if absi(off_out) > 1 or absi(off_back) > 1:
				errors.append("%s/%s: left %+d, back %+d ticks off" % [target, depart, off_out, off_back])
	expect("the planner's departure and return times match the trip the simulation runs (within 10 min)", errors.is_empty(),
		", ".join(errors))


func _check_risk_bands_follow_time_of_day() -> void:
	start(901)
	var s: Dictionary = WorldState.group()[0]
	var b: Dictionary = WorldState.building("kirana_02")
	var midday: Dictionary = Insight.trip_estimate(s, b, &"midday")
	var night: Dictionary = Insight.trip_estimate(s, b, &"night")
	expect("a night trip is estimated as more dangerous than a midday one", float(night["hurt"]) > float(midday["hurt"]),
		"hurt %.0f%% midday, %.0f%% night" % [float(midday["hurt"]) * 100.0, float(night["hurt"]) * 100.0])
	expect("the chance of getting hurt is never above the chance of meeting infected",
		float(midday["hurt"]) <= float(midday["risk"]) and float(night["hurt"]) <= float(night["risk"]))


# --- Part D: breakdowns add up to what the simulation does ---

func _check_attention_breakdown_matches_gain() -> void:
	start(902)
	var config: Dictionary = Data.table("attention")
	var decay: float = pow(0.5, (1.0 / WorldState.TICKS_PER_DAY) / float(config["half_life_days_occupied"]))
	var worst: float = 0.0
	for i: int in WorldState.TICKS_PER_DAY:
		var before: float = float(WorldState.base["attention"])
		TickLoop.run_headless(1)
		var shown: float = 0.0
		for p: Dictionary in Insight.attention_breakdown()["contributions"]:
			shown += float(p["amount"])
		var gained: float = (float(WorldState.base["attention"]) / decay - before) * 6.0
		worst = maxf(worst, absf(gained - shown))
	expect("the attention breakdown adds up to the attention the base actually gains each hour", worst < 0.01,
		"largest gap %.4f per hour over a day" % worst)


func _check_forecasts() -> void:
	start(903)
	TickLoop.run_headless(ticks_for_hours(30.0))
	var water: Dictionary = Insight.water_forecast()
	var total: float = 0.0
	for p: Dictionary in water["contributions"]:
		total += float(p["amount"])
	expect("the water forecast's parts add up to its total", is_equal_approx(total, float(water["value"])))
	if is_inf(float(water["days"])):
		expect("with taps running, water days are unlimited", WorldState.infrastructure["mains_on"])
	else:
		expect("water days = water in hand / the group's daily need",
			is_equal_approx(float(water["days"]), float(water["value"]) / float(water["daily"])))
	var s: Dictionary = WorldState.group()[0]
	var need: Dictionary = Insight.water_need(s)
	var sum: float = 0.0
	for p: Dictionary in need["contributions"]:
		sum += float(p["amount"])
	expect("a survivor's water need is the sum of its causes", absf(sum - float(need["value"])) < 0.01,
		"%.2f vs %.2f" % [sum, float(need["value"])])
	var meters: Dictionary = Insight.meters(s)
	expect("each survivor card has water, food, sleep and stress meters", meters.keys() == ["water", "food", "sleep", "stress"])


# --- Part I: history and timeline ---

func _check_history_and_timeline() -> void:
	start(904)
	TickLoop.run_headless(3 * WorldState.TICKS_PER_DAY)
	var history: Array = WorldState.stats["history"]
	expect("the run keeps one snapshot a day for the charts (plus the start)", history.size() == 4, str(history.size()))
	var charts: Array = StatsPanel.build_charts(history)
	expect("the Stats tab draws a chart for each tracked series", charts.size() == StatsPanel.SERIES.size())
	for chart: Control in charts:
		chart.free()


# --- Part F: alerts only from what the group can know ---

func _check_alerts_use_what_the_group_knows() -> void:
	start(905)
	_rest_everyone()
	var s: Dictionary = WorldState.group()[0]
	s["pathogen"] = {"stage": &"incubation", "hours_left": 40.0, "known": false}
	var ids: Array = Alerts.current({}).map(func(a: Dictionary) -> String: return String(a["type"]))
	expect("a hidden bite raises no bite alert (the group doesn't know yet)", not ids.has("bite"), str(ids))
	var other: Dictionary = WorldState.group()[1]
	Decisions.create(&"bite", "Test bite?", [Decisions.option(&"a", "A")], {"survivor": other["id"]})
	var before: bool = Alerts.current({}).any(func(a: Dictionary) -> bool: return a["type"] == "decision")
	other["status"] = &"dead"
	var after: bool = Alerts.current({}).any(func(a: Dictionary) -> bool: return a["type"] == "decision")
	expect("a waiting decision about someone who has since died stops being shown", before and not after)


# --- Parts B, J: the screen builds, runs and switches tabs without errors ---

## Call once main.tscn has been in the tree for a frame. Returns the exit code.
func check_screen(main: Node) -> int:
	var hud: Control = main.get_node("HUD")
	start(906)
	TickLoop.run_headless(ticks_for_hours(30.0))
	var tabs: TabContainer = hud.get("tabs")
	for i: int in tabs.get_tab_count():
		tabs.current_tab = i
	for overlay: String in ["noise", "light", "smell", "attention", "disease", "infected"]:
		hud.call("set_overlay", overlay)
	hud.get("planner").call("open", "kirana_02", "")
	expect("the main screen builds, runs a day and switches every tab and overlay", tabs.get_tab_count() == 5)
	print("\n%d/%d checks passed" % [checks - failures, checks])
	return 1 if failures > 0 else 0
