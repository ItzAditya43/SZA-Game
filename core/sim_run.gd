extends RefCounted
## Starts a fresh run: seeds randomness, clears the world and the event log, and
## registers the systems in their fixed tick order. The main scene, the headless
## runner and the tests all start runs through here, so they run the same simulation.

const SimSystem := preload("res://core/sim_system.gd")
const Difficulty := preload("res://core/difficulty.gd")
const Names := preload("res://core/names.gd")

## Tick order. Time goes first so every later system sees this tick's clock and
## temperature. Jobs runs before Infected so encounters roll on this tick's
## positions, and Survivors runs after both so it applies this tick's wounds.
const SYSTEM_SCRIPTS: Array[Script] = [
	preload("res://systems/time.gd"),
	preload("res://systems/infrastructure.gd"),
	preload("res://systems/town.gd"),
	preload("res://systems/base.gd"),
	preload("res://systems/jobs.gd"),
	preload("res://systems/infected.gd"),
	preload("res://systems/survivors.gd"),
	preload("res://systems/resources.gd"),
	preload("res://systems/attention.gd"),
	preload("res://systems/events.gd"),
	preload("res://systems/outcome.gd"),
	preload("res://systems/history.gd"),
]


## roster: survivor ids from the pool, [] for the scenario's default five, or
## ["random"] for a seeded random pick.
static func start(run_seed: int, difficulty_id: String = Difficulty.DEFAULT_ID, roster: Array = []) -> void:
	TickLoop.reset()
	Rng.set_seed(run_seed)
	WorldState.reset(run_seed)
	WorldState.names = Names.generate(run_seed)
	WorldState.difficulty = Difficulty.preset(difficulty_id)
	WorldState.flags["roster"] = pick_roster(roster)
	EventBus.clear_log()
	var systems: Array[SimSystem] = []
	for script: Script in SYSTEM_SCRIPTS:
		var system: SimSystem = script.new()
		systems.append(system)
		TickLoop.register(system)
	for system: SimSystem in systems:
		system.setup()
	EventBus.emit_event(&"run_started", {"seed": run_seed, "difficulty": WorldState.difficulty["id"],
		"text": "Day 0 of the outbreak in %s. %s, seed %d." % [WorldState.names["town"], WorldState.difficulty["name"], run_seed]})


static func pick_roster(roster: Array) -> Array:
	var scenario: Dictionary = Data.table("scenario")
	if roster.is_empty() or roster == ["default"]:
		return Array(scenario["default_roster"])
	if roster == ["random"]:
		var ids: Array = Data.table("survivors").map(func(row: Dictionary) -> String: return row["id"])
		var picked: Array = []
		for i: int in int(scenario["roster_size"]):
			picked.append(ids.pop_at(Rng.randi_range(0, ids.size() - 1)))
		return picked
	return roster


## A roster from `--roster=default|random|id,id,...` on the command line.
static func roster_arg() -> Array:
	var text: String = string_arg("roster", "default")
	return Array(text.split(",", false))


## Reads `--name=value` from the user arguments after `--` on the command line.
static func int_arg(arg_name: String, fallback: int) -> int:
	var prefix: String = "--%s=" % arg_name
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix) and arg.trim_prefix(prefix).is_valid_int():
			return arg.trim_prefix(prefix).to_int()
	return fallback


## Reads `--name=value` as text from the user arguments after `--`.
static func string_arg(arg_name: String, fallback: String) -> String:
	var prefix: String = "--%s=" % arg_name
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
