extends "res://core/sim_system.gd"
## Infrastructure collapse. Phones and internet go down on day 2, the power grid
## fails at a random time between day 3 and day 6, and water-mains pressure
## between day 7 and day 12 (scenario.json). After the grid fails, a generator at
## base gives light (and a working fridge) at the cost of fuel and noise; its
## light is visible for a kilometre at night.

const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")

const GENERATOR_FUEL_L_PER_H: float = 1.0
const GENERATOR_NOISE_M: float = 150.0
const LIGHT_VISIBLE_M: float = 1000.0
## Generator schedules: evening is 18:00-22:00, night is 18:00-06:00.
const EVENING_END_MINUTE: int = 22 * 60


func setup() -> void:
	var timing: Dictionary = Data.table("scenario")["infrastructure"]
	WorldState.infrastructure = {
		"power_on": true, "mains_on": true, "phones_on": true, "generator_running": false,
		"phones_fail_tick": first_tick_of_day(int(timing["phones_fail_day"])) + Rng.randi_range(0, 143),
		"power_fail_tick": Rng.randi_range(first_tick_of_day(int(timing["power_fail_day_min"])),
			first_tick_of_day(int(timing["power_fail_day_max"]) + 1) - 1),
		"mains_fail_tick": Rng.randi_range(first_tick_of_day(int(timing["mains_fail_day_min"])),
			first_tick_of_day(int(timing["mains_fail_day_max"]) + 1) - 1),
	}


func tick() -> void:
	var infra: Dictionary = WorldState.infrastructure
	var now: int = WorldState.tick
	if infra["phones_on"] and now >= int(infra["phones_fail_tick"]):
		infra["phones_on"] = false
		EventBus.emit_event(&"phones_down", {"text": "Mobile networks and the internet go dark. No more calls home."})
	if infra["power_on"] and now >= int(infra["power_fail_tick"]):
		infra["power_on"] = false
		EventBus.emit_event(&"power_failed", {"text": "The power grid fails. The town goes dark; fridges and fans stop."})
	if infra["mains_on"] and now >= int(infra["mains_fail_tick"]):
		infra["mains_on"] = false
		EventBus.emit_event(&"mains_failed", {"text": "The taps run dry: water-mains pressure is gone. Water now comes only from tanks, rain or the canal."})
	_run_generator()


## Tick of 00:00 on a day (day 0 starts at 06:00, so it begins at tick 0).
@warning_ignore("integer_division")
static func first_tick_of_day(day: int) -> int:
	return maxi(0, (day * WorldState.MINUTES_PER_DAY - WorldState.DAY_START_MINUTE) / WorldState.MINUTES_PER_TICK)


func _run_generator() -> void:
	var infra: Dictionary = WorldState.infrastructure
	var mode: StringName = WorldState.policies.get(&"generator", &"off")
	var minute: int = WorldState.minute_of_day()
	var wanted: bool = false
	if not infra["power_on"] and WorldState.phase() == WorldState.PHASE_NIGHT:
		wanted = mode == &"night" or mode == &"evening" and minute >= WorldState.NIGHT_START_MINUTE and minute < EVENING_END_MINUTE
	var can: bool = Stores.total(WorldState.stores, "generator") >= 1.0 and Stores.total(WorldState.stores, "fuel") > 0.0
	var running: bool = wanted and can
	if wanted and not can and int(WorldState.flags.get("generator_warned_day", -1)) != WorldState.day():
		WorldState.flags["generator_warned_day"] = WorldState.day()
		var missing: String = "a generator" if Stores.total(WorldState.stores, "generator") < 1.0 else "fuel"
		EventBus.emit_event(&"generator_unavailable", {"text": "No light tonight: the group has no %s." % missing})
	infra["generator_running"] = running
	if not running:
		return
	Stores.take(WorldState.stores, "fuel", GENERATOR_FUEL_L_PER_H / 6.0)
	if WorldState.tick % 6 == 0:
		var pos: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": GENERATOR_NOISE_M, "source": &"generator", "continuous": true})
		EventBus.emit_event(&"light", {"x_m": pos.x, "y_m": pos.y, "radius_m": LIGHT_VISIBLE_M})
