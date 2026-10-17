extends Node
## Autoload `TickLoop`. Drives the simulation. Each tick: advance the clock,
## announce a new day or phase, run every registered system in registration order,
## then emit `tick`.

const SimSystem := preload("res://core/sim_system.gd")

enum Speed { PAUSED, X1, X3, X10 }

## Real seconds per tick at 1×. 144 ticks a day × 0.5 s = 72 s per in-game day.
const SECONDS_PER_TICK_AT_1X: float = 0.5
const SPEED_MULTIPLIERS: Dictionary = {
	Speed.PAUSED: 0.0,
	Speed.X1: 1.0,
	Speed.X3: 3.0,
	Speed.X10: 10.0,
}
const SPEED_LABELS: Dictionary = {
	Speed.PAUSED: "Pause",
	Speed.X1: "1×",
	Speed.X3: "3×",
	Speed.X10: "10×",
}
## Caps catch-up after a long frame hitch, so the sim never runs a sudden burst of ticks.
const MAX_TICKS_PER_FRAME: int = 10

var speed: Speed = Speed.PAUSED
var _resume_speed: Speed = Speed.X1
var _systems: Array[SimSystem] = []
var _auto_pause_events: Dictionary = {}  # StringName -> true
var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if speed == Speed.PAUSED:
		return
	var multiplier: float = SPEED_MULTIPLIERS[speed]
	_accumulator += delta * multiplier
	var ran: int = 0
	while _accumulator >= SECONDS_PER_TICK_AT_1X and speed != Speed.PAUSED:
		if ran == MAX_TICKS_PER_FRAME:
			_accumulator = 0.0
			break
		_accumulator -= SECONDS_PER_TICK_AT_1X
		step()
		ran += 1


## Pauses and unregisters every system. Auto-pause events are kept.
func reset() -> void:
	speed = Speed.PAUSED
	_resume_speed = Speed.X1
	_accumulator = 0.0
	_systems.clear()


func register(system: SimSystem) -> void:
	_systems.append(system)


func set_speed(new_speed: Speed) -> void:
	if new_speed == speed:
		return
	speed = new_speed
	if speed != Speed.PAUSED:
		_resume_speed = speed
	_accumulator = 0.0
	EventBus.emit_event(&"speed_changed", {"speed": SPEED_LABELS[speed]})


## Pauses, or resumes at the last speed used.
func toggle_pause() -> void:
	set_speed(_resume_speed if speed == Speed.PAUSED else Speed.PAUSED)


## Pause whenever this event fires on the bus. Used for decisions that need the player.
func auto_pause_on(event_name: StringName) -> void:
	_auto_pause_events[event_name] = true
	# Connected here, not in _ready(): under --script, autoloads are not ready yet
	# when the runner starts.
	if not EventBus.event.is_connected(_on_bus_event):
		EventBus.event.connect(_on_bus_event)


## Advances the simulation by one tick.
func step() -> void:
	var previous_tick: int = WorldState.tick
	WorldState.tick += 1
	var now: int = WorldState.tick
	if WorldState.day_at(now) != WorldState.day_at(previous_tick):
		EventBus.emit_event(&"day_started", {"day": WorldState.day_at(now), "text": "Day %d begins." % WorldState.day_at(now)})
	var previous_phase: StringName = WorldState.phase_at(previous_tick)
	var phase: StringName = WorldState.phase_at(now)
	if phase != previous_phase:
		EventBus.emit_event(&"phase_changed", {"phase": phase, "previous": previous_phase})
	for system: SimSystem in _systems:
		system.tick()
	EventBus.emit_event(&"tick", {"tick": now})


## Runs `ticks` ticks back to back with no timers, ignoring speed and auto-pause.
## For the headless runner and tests.
# LATER: once decisions exist, headless runs need a policy that answers them.
func run_headless(ticks: int) -> void:
	for i: int in ticks:
		step()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if _auto_pause_events.has(event_name) and speed != Speed.PAUSED:
		set_speed(Speed.PAUSED)
