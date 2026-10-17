extends RefCounted
## Starts a fresh run: seeds randomness, clears the world and the event log, and
## registers the systems in their fixed tick order. The main scene, the headless
## runner and the tests all start runs through here, so they run the same simulation.

const TimeSystem := preload("res://systems/time.gd")


static func start(run_seed: int) -> void:
	TickLoop.reset()
	Rng.set_seed(run_seed)
	WorldState.reset(run_seed)
	EventBus.clear_log()
	# Tick order. Time goes first so every later system sees a checked clock.
	TickLoop.register(TimeSystem.new())
	# LATER: register survivors, jobs, town, resources, infrastructure, infected,
	# base and events as their milestones land.
	EventBus.emit_event(&"run_started", {"seed": run_seed})


## Reads `--name=value` from the user arguments after `--` on the command line.
static func int_arg(arg_name: String, fallback: int) -> int:
	var prefix: String = "--%s=" % arg_name
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix) and arg.trim_prefix(prefix).is_valid_int():
			return arg.trim_prefix(prefix).to_int()
	return fallback
