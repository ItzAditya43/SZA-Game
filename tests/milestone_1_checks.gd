extends RefCounted
## Milestone 1 checks, run by tests/test_milestone_1.gd. Prints PASS/FAIL per check.

const SimRun := preload("res://core/sim_run.gd")

## Folders whose code must not reach into ui/ (CLAUDE.md rule 2).
const SIMULATION_DIRS: Array[String] = ["res://core", "res://systems"]
## Everything except tests and core/rng.gd must get randomness from Rng (rule 6).
const RNG_CHECKED_DIRS: Array[String] = ["res://core", "res://systems", "res://ui", "res://tools"]
const RNG_FILE: String = "res://core/rng.gd"

var _failures: int = 0
var _checks: int = 0
var _captured: Array[Dictionary] = []


## Returns the process exit code: 0 if every check passed, 1 otherwise.
func run() -> int:
	EventBus.event.connect(_capture)
	_check_clock()
	_check_three_day_run()
	_check_rng()
	_check_event_log()
	_check_speeds_and_auto_pause()
	_check_data()
	_check_architecture()
	print("\n%d/%d checks passed" % [_checks - _failures, _checks])
	return 1 if _failures > 0 else 0


func _check_clock() -> void:
	SimRun.start(1)
	WorldState.tick = 0
	_expect("tick 0 is Day 0 · 06:00, phase day",
		WorldState.clock_string() == "Day 0 · 06:00" and WorldState.phase() == &"day",
		"%s, %s" % [WorldState.clock_string(), WorldState.phase()])
	WorldState.tick = 72
	_expect("tick 72 is Day 0 · 18:00, phase night",
		WorldState.clock_string() == "Day 0 · 18:00" and WorldState.phase() == &"night",
		"%s, %s" % [WorldState.clock_string(), WorldState.phase()])
	WorldState.tick = 144
	_expect("tick 144 is Day 1 · 06:00",
		WorldState.clock_string() == "Day 1 · 06:00", WorldState.clock_string())


func _check_three_day_run() -> void:
	SimRun.start(42)
	_captured.clear()
	TickLoop.run_headless(3 * WorldState.TICKS_PER_DAY)
	var days: Array = []
	var phases: Array = []
	var clock_errors: int = 0
	for entry: Dictionary in _captured:
		if entry["name"] == &"day_started":
			days.append(int(entry["payload"]["day"]))
		elif entry["name"] == &"phase_changed":
			phases.append(entry["payload"]["phase"])
		elif entry["name"] == &"clock_error":
			clock_errors += 1
	_expect("3 headless days emit exactly 3 day_started (days 1, 2, 3)",
		days == [1, 2, 3], str(days))
	_expect("3 headless days end at Day 3 · 06:00",
		WorldState.clock_string() == "Day 3 · 06:00", WorldState.clock_string())
	_expect("phase_changed alternates night/day 6 times in 3 days",
		phases == [&"night", &"day", &"night", &"day", &"night", &"day"], str(phases))
	_expect("the Time system sees a consistent clock for 3 days", clock_errors == 0,
		"%d clock_error events" % clock_errors)
	# A skipped tick must be caught, or the check above proves nothing.
	print("      (deliberately skipping ticks: the next ERROR line is expected)")
	_captured.clear()
	WorldState.tick += 5
	TickLoop.step()
	_expect("the Time system reports a skipped tick as clock_error",
		_captured.any(func(e: Dictionary) -> bool: return e["name"] == &"clock_error"))


func _check_rng() -> void:
	var first: Array[float] = _ten_randf(42)
	var second: Array[float] = _ten_randf(42)
	var other: Array[float] = _ten_randf(43)
	_expect("same seed gives the same 10 Rng.randf() values", first == second,
		"%s vs %s" % [first, second])
	_expect("a different seed gives different values", first != other)


func _check_event_log() -> void:
	SimRun.start(7)
	TickLoop.run_headless(5)
	EventBus.emit_event(&"test_event", {"source": "test"})
	var last: Dictionary = EventBus.event_log.back()
	_expect("a test event on the bus appears in the event log",
		last["name"] == &"test_event" and last["payload"] == {"source": "test"} and last["tick"] == 5,
		str(last))
	_expect("tick events are broadcast but kept out of the log",
		EventBus.event_log.all(func(e: Dictionary) -> bool: return e["name"] != &"tick"))
	for i: int in 250:
		EventBus.emit_event(&"filler", {"i": i})
	_expect("event log keeps only the last 200 events",
		EventBus.event_log.size() == 200 and EventBus.event_log.back()["payload"]["i"] == 249,
		"size %d" % EventBus.event_log.size())


func _check_speeds_and_auto_pause() -> void:
	SimRun.start(7)
	TickLoop.set_speed(TickLoop.Speed.X3)
	TickLoop.toggle_pause()
	var paused: bool = TickLoop.speed == TickLoop.Speed.PAUSED
	TickLoop.toggle_pause()
	_expect("toggle_pause pauses, then resumes at the previous speed",
		paused and TickLoop.speed == TickLoop.Speed.X3)
	TickLoop.auto_pause_on(&"decision_needed")
	EventBus.emit_event(&"decision_needed")
	_expect("an auto-pause event pauses the loop", TickLoop.speed == TickLoop.Speed.PAUSED)
	TickLoop.set_speed(TickLoop.Speed.PAUSED)


func _check_data() -> void:
	var expected: Array[String] = ["buildings", "events", "items", "loot_tables", "survivors"]
	var loaded: Array = Data.tables.keys()
	_expect("data loader read the 5 spec JSON files without errors",
		Data.errors.is_empty() and expected.all(func(t: String) -> bool: return loaded.has(t)),
		"%s, errors %s" % [loaded, Data.errors])
	var pharmacy: Dictionary = Data.entry("buildings", "pharmacy")
	_expect("buildings.json holds the pharmacy example",
		int(pharmacy.get("count", 0)) == 2 and is_equal_approx(float(pharmacy.get("daily_looted_rate", 0.0)), 0.15), str(pharmacy))


func _check_architecture() -> void:
	var ui_refs: Array[String] = []
	for path: String in _gd_files(SIMULATION_DIRS):
		var code: String = _code_without_comments(path)
		if code.contains("res://ui") or code.contains("get_tree("):
			ui_refs.append(path)
	_expect("no file in core/ or systems/ references ui/ or the scene tree",
		ui_refs.is_empty(), str(ui_refs))

	var direct_random: RegEx = RegEx.create_from_string("(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\s*\\(")
	var offenders: Array[String] = []
	for path: String in _gd_files(RNG_CHECKED_DIRS):
		if path != RNG_FILE and direct_random.search(_code_without_comments(path)) != null:
			offenders.append(path)
	offenders.append_array(_files_matching(["res://main.gd"], direct_random))
	_expect("no code outside core/rng.gd calls the global random functions",
		offenders.is_empty(), str(offenders))


func _ten_randf(run_seed: int) -> Array[float]:
	Rng.set_seed(run_seed)
	var values: Array[float] = []
	for i: int in 10:
		values.append(Rng.randf())
	return values


func _capture(event_name: StringName, payload: Dictionary) -> void:
	_captured.append({"name": event_name, "payload": payload})


func _expect(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS  " + label)
	else:
		_failures += 1
		print("FAIL  %s%s" % [label, ("  (got: %s)" % detail) if detail != "" else ""])


func _gd_files(dirs: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	for dir: String in dirs:
		for file_name: String in DirAccess.get_files_at(dir):
			if file_name.get_extension() == "gd":
				paths.append(dir.path_join(file_name))
	return paths


func _files_matching(paths: Array[String], pattern: RegEx) -> Array[String]:
	var matches: Array[String] = []
	for path: String in paths:
		if pattern.search(_code_without_comments(path)) != null:
			matches.append(path)
	return matches


## The file's code with `#` comments and `##` doc comments stripped, so prose
## that mentions randi() or ui/ does not count as a reference.
func _code_without_comments(path: String) -> String:
	var lines: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var hash_at: int = line.find("#")
		lines.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(lines)
