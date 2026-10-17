extends Node
## Autoload `WorldState`. Plain data for the whole simulation. Systems read and
## write it; the UI only reads it. The only logic here is derived clock getters.

const MINUTES_PER_TICK: int = 10
const TICKS_PER_DAY: int = 144
const MINUTES_PER_DAY: int = 24 * 60
## Tick 0 is Day 0 at 06:00. Each day runs 144 ticks, from 06:00 to the next 06:00.
const DAY_START_MINUTE: int = 6 * 60
## The day phase runs 06:00 to 18:00; night runs 18:00 to 06:00.
const DAYTIME_START_MINUTE: int = 6 * 60
const NIGHT_START_MINUTE: int = 18 * 60

const PHASE_DAY: StringName = &"day"
const PHASE_NIGHT: StringName = &"night"

var run_seed: int = 0
var tick: int = 0

var survivors: Array = []    # Milestone 2
var buildings: Array = []    # Milestone 3
var zones: Array = []        # Milestone 4
var base: Dictionary = {}    # Milestone 5
var stores: Dictionary = {}  # Milestone 2
## Hooks for later prototypes. Both stay empty in Prototype 1.
var factions: Array = []
var region: Dictionary = {}


func reset(new_seed: int) -> void:
	run_seed = new_seed
	tick = 0
	survivors = []
	buildings = []
	zones = []
	base = {}
	stores = {}
	factions = []
	region = {}


func day() -> int:
	return day_at(tick)


func minute_of_day() -> int:
	return minute_of_day_at(tick)


func clock_string() -> String:
	return clock_string_at(tick)


func phase() -> StringName:
	return phase_at(tick)


@warning_ignore("integer_division")
static func day_at(at_tick: int) -> int:
	return at_tick / TICKS_PER_DAY


static func minute_of_day_at(at_tick: int) -> int:
	return (DAY_START_MINUTE + (at_tick % TICKS_PER_DAY) * MINUTES_PER_TICK) % MINUTES_PER_DAY


## For example "Day 0 · 06:00".
@warning_ignore("integer_division")
static func clock_string_at(at_tick: int) -> String:
	var minute: int = minute_of_day_at(at_tick)
	return "Day %d · %02d:%02d" % [day_at(at_tick), minute / 60, minute % 60]


static func phase_at(at_tick: int) -> StringName:
	var minute: int = minute_of_day_at(at_tick)
	if minute >= DAYTIME_START_MINUTE and minute < NIGHT_START_MINUTE:
		return PHASE_DAY
	return PHASE_NIGHT
