extends RefCounted
## Runs the simulation with no UI, as fast as possible, and prints a summary.
## Started by tools/headless_runner.gd.
##   One run:  --seed=42 --days=30 [--difficulty=normal] [--strategy=balanced] [--verbose=1]
##   Batch:    --games=100 [--difficulty=easy|normal|hard|all]
##             [--strategy=balanced|fortress|hoard_water|keep_moving|all] [--seed=1]
## Without --strategy a single run has nobody giving orders (the default jobs run
## and decisions wait forever); batch runs always use the auto-player.

const SimRun := preload("res://core/sim_run.gd")
const AutoPlayer := preload("res://tools/auto_player.gd")
const Difficulty := preload("res://core/difficulty.gd")

var _days_started: int = 0
var _clock_errors: int = 0
var _verbose: bool = false
var _player: AutoPlayer


## Returns the process exit code.
func run() -> int:
	if not Data.errors.is_empty():
		printerr("Data failed to load; see errors above.")
		return 1
	EventBus.event.connect(_on_bus_event)
	var games: int = SimRun.int_arg("games", 0)
	if games > 0:
		return _batch(games)
	var run_seed: int = SimRun.int_arg("seed", 42)
	var days: int = SimRun.int_arg("days", 30)
	var strategy: String = SimRun.string_arg("strategy", "")
	_verbose = SimRun.int_arg("verbose", 0) == 1
	var difficulty: String = SimRun.string_arg("difficulty", Difficulty.DEFAULT_ID)
	SimRun.start(run_seed, difficulty)
	if strategy != "":
		_player = AutoPlayer.new(StringName(strategy))
		_player.begin()
	TickLoop.run_headless(days * WorldState.TICKS_PER_DAY)
	print("Ran %d days (%d ticks) on %s with seed %d%s" % [days, WorldState.tick, difficulty, run_seed, " as " + strategy if strategy != "" else ""])
	print("Final clock: %s" % WorldState.clock_string())
	print("day_started events: %d" % _days_started)
	if not WorldState.is_running():
		var outcome: Dictionary = WorldState.outcome
		print("Outcome: %s on day %d. %s Score %d. Fates: %s" % [outcome["state"], int(outcome["day"]), outcome["reason"],
			roundi(float(outcome["score"])), outcome["fates"]])
	if _clock_errors > 0:
		printerr("clock_error events: %d" % _clock_errors)
		return 1
	return 0


func _batch(games: int) -> int:
	var first_seed: int = SimRun.int_arg("seed", 1)
	var choice: String = SimRun.string_arg("strategy", "balanced")
	var strategies: Array = AutoPlayer.STRATEGIES if choice == "all" else [StringName(choice)]
	var level: String = SimRun.string_arg("difficulty", Difficulty.DEFAULT_ID)
	var levels: Array = Difficulty.ids() if level == "all" else [level]
	var started: int = Time.get_ticks_msec()
	for difficulty: String in levels:
		print("== %s ==" % Difficulty.preset(difficulty)["name"])
		for strategy: StringName in strategies:
			_batch_one(games, first_seed, difficulty, strategy)
	print("(%.1f s)" % ((Time.get_ticks_msec() - started) / 1000.0))
	return 0


func _batch_one(games: int, first_seed: int, difficulty: String, strategy: StringName) -> void:
	var won: int = 0
	var alive: int = 0
	var people: int = 0
	var score: float = 0.0
	var end_day: float = 0.0
	var causes: Dictionary = {}
	var breaches: int = 0
	for game: int in games:
		SimRun.start(first_seed + game, difficulty)
		_player = AutoPlayer.new(strategy)
		_player.begin()
		var end_tick: int = int(Data.table("scenario")["days_to_survive"]) * WorldState.TICKS_PER_DAY
		while WorldState.is_running() and WorldState.tick <= end_tick:
			TickLoop.step()
		var outcome: Dictionary = WorldState.outcome
		if outcome["state"] == &"won":
			won += 1
		alive += int(outcome["alive"])
		people += int(outcome["started"])
		score += float(outcome["score"])
		end_day += float(outcome["day"])
		breaches += int(WorldState.stats.get("breaches", 0))
		for s: Dictionary in WorldState.survivors:
			if s["status"] != &"ok":
				causes[s["cause"]] = int(causes.get(s["cause"], 0)) + 1
	var cause_list: Array = causes.keys()
	cause_list.sort_custom(func(a: String, b: String) -> bool: return int(causes[a]) > int(causes[b]))
	var top: PackedStringArray = []
	for cause: String in cause_list.slice(0, 6):
		top.append("%s %d" % [cause, causes[cause]])
	print("%-12s %d games: won %d%% · survivors alive %d%% (%d of %d) · avg score %d · avg end day %.1f · breaches/game %.1f" % [
		strategy, games, roundi(100.0 * won / games), roundi(100.0 * alive / maxi(people, 1)), alive, people,
		roundi(score / games), end_day / games, float(breaches) / games])
	print("             losses: %s" % ", ".join(top))


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	if _verbose and payload.has("text"):
		print("%s  %s" % [WorldState.clock_string(), payload["text"]])
	if event_name == &"day_started":
		_days_started += 1
	elif event_name == &"clock_error":
		_clock_errors += 1
