extends "res://core/sim_system.gd"
## Time. Registered first. Checks that the clock advanced by exactly one tick, and
## sets the calendar date and air temperature for the tick (from scenario.json).
## Clock problems are reported as `clock_error` on the bus rather than assert(): a
## failed assert in a headless run halts waiting for a debugger instead of failing.

const MONTH_NAMES: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Any non-leap year works; only month and day are shown.
const CALENDAR_YEAR: int = 2026

var _last_tick: int = -1
var _climate: Dictionary = {}
var _start_unix: int = 0


func setup() -> void:
	var scenario: Dictionary = Data.table("scenario")
	_climate = scenario["climate"]
	var start: Dictionary = scenario["start_date"]
	_start_unix = Time.get_unix_time_from_datetime_dict({
		"year": CALENDAR_YEAR, "month": int(start["month"]), "day": int(start["day"]), "hour": 12,
	})
	WorldState.climate = {"temperature_c": 0.0, "today_min_c": 0.0, "today_max_c": 0.0,
		"heat_bonus_c": 0.0, "heat_bonus_until_day": -1, "date": ""}
	_start_day(0)
	_update_temperature()


func tick() -> void:
	var now: int = WorldState.tick
	if _last_tick != -1 and now != _last_tick + 1:
		_report("Clock jumped from tick %d to %d" % [_last_tick, now])
	if WorldState.day() * WorldState.TICKS_PER_DAY + now % WorldState.TICKS_PER_DAY != now:
		_report("Day %d does not match tick %d" % [WorldState.day(), now])
	var minute: int = WorldState.minute_of_day()
	if minute % WorldState.MINUTES_PER_TICK != 0 or minute < 0 or minute >= WorldState.MINUTES_PER_DAY:
		_report("Minute of day %d is off the 10-minute grid" % minute)
	_last_tick = now
	if now % WorldState.TICKS_PER_DAY == 0:
		_start_day(WorldState.day())
	_update_temperature()


## Rolls today's low and high: a straight ramp over the run plus a little jitter,
## plus any heat-wave bonus an event has set.
func _start_day(day: int) -> void:
	var days: float = float(Data.table("scenario")["days_to_survive"])
	var progress: float = clampf(float(day) / days, 0.0, 1.0)
	var jitter: float = float(_climate["daily_jitter_c"])
	var shift: float = (Rng.randf() * 2.0 - 1.0) * jitter
	var climate: Dictionary = WorldState.climate
	var bonus: float = float(climate["heat_bonus_c"]) if day <= int(climate["heat_bonus_until_day"]) else 0.0
	climate["today_min_c"] = lerpf(float(_climate["min_c_start"]), float(_climate["min_c_end"]), progress) + shift * 0.5 + bonus * 0.5
	climate["today_max_c"] = lerpf(float(_climate["max_c_start"]), float(_climate["max_c_end"]), progress) + shift + bonus
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(_start_unix + day * 86400)
	climate["date"] = "%d %s" % [date["day"], MONTH_NAMES[int(date["month"]) - 1]]


## Cosine curve from the coolest hour up to the warmest and back down.
func _update_temperature() -> void:
	var climate: Dictionary = WorldState.climate
	var low: float = float(climate["today_min_c"])
	var high: float = float(climate["today_max_c"])
	var coolest: float = float(_climate["coolest_hour"])
	var warmest: float = float(_climate["warmest_hour"])
	var hour: float = float(WorldState.minute_of_day()) / 60.0
	var warming: float = warmest - coolest
	var since_coolest: float = fposmod(hour - coolest, 24.0)
	var warmth: float
	if since_coolest <= warming:
		warmth = (1.0 - cos(PI * since_coolest / warming)) / 2.0
	else:
		warmth = (1.0 + cos(PI * (since_coolest - warming) / (24.0 - warming))) / 2.0
	climate["temperature_c"] = low + (high - low) * warmth


func _report(message: String) -> void:
	push_error("Time: " + message)
	EventBus.emit_event(&"clock_error", {"message": message})
