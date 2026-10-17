extends RefCounted
## Shared bookkeeping for milestone check scripts: PASS/FAIL lines, a capture of
## bus events, and the exit code.

const SimRun := preload("res://core/sim_run.gd")
const Stores := preload("res://core/stores.gd")
const Body := preload("res://core/body.gd")

## The SceneTree running the checks, for checks that need UI nodes in a tree.
var tree: SceneTree
var failures: int = 0
var checks: int = 0
var captured: Array[Dictionary] = []


func _init() -> void:
	EventBus.event.connect(_capture)


## Override: run every check. The return value is ignored; use expect().
func run_checks() -> void:
	pass


## Returns the process exit code: 0 if every check passed, 1 otherwise.
func run() -> int:
	run_checks()
	print("\n%d/%d checks passed" % [checks - failures, checks])
	return 1 if failures > 0 else 0


func expect(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])
	else:
		failures += 1
		print("FAIL  %s%s" % [label, ("  (got: %s)" % detail) if detail != "" else ""])


## Captured events with this name since the last captured.clear().
func events_named(event_name: StringName) -> Array[Dictionary]:
	return captured.filter(func(e: Dictionary) -> bool: return e["name"] == event_name)


## Starts a sandbox run: it never ends in a win or loss, so a check can run it as
## long as it likes even after everyone has died.
func start(run_seed: int) -> void:
	SimRun.start(run_seed)
	WorldState.flags["sandbox"] = true
	captured.clear()


func ticks_for_hours(hours: float) -> int:
	return roundi(hours * 6.0)


func _capture(event_name: StringName, payload: Dictionary) -> void:
	captured.append({"name": event_name, "payload": payload, "tick": WorldState.tick})
