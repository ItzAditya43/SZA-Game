extends Node
## Autoload `WorldState`. Plain data for the whole simulation. Systems read and
## write it; the UI only reads it. The only logic here is derived clock getters.

const MINUTES_PER_TICK: int = 10
const TICKS_PER_DAY: int = 144
const MINUTES_PER_DAY: int = 24 * 60
## Tick 0 is Day 0 at 06:00. Day numbers change at midnight, like a calendar, so
## Day 0 is 18 hours long and every later day 24 (144 ticks).
const DAY_START_MINUTE: int = 6 * 60
## The day phase runs 06:00 to 18:00; night runs 18:00 to 06:00.
const DAYTIME_START_MINUTE: int = 6 * 60
const NIGHT_START_MINUTE: int = 18 * 60

const PHASE_DAY: StringName = &"day"
const PHASE_NIGHT: StringName = &"night"

var run_seed: int = 0
var tick: int = 0

## One Dictionary per survivor, built from data/survivors.json (see systems/survivors.gd).
var survivors: Array = []
## Building instances on the town map, with their remaining loot (systems/town.gd).
var buildings: Array = []
## Terrain grid and landmarks of the town map (systems/town.gd).
var town: Dictionary = {}
## The 4 x 4 infected zones (systems/infected.gd).
var zones: Array = []
## The group's base: building, barricades, alert level (systems/base.gd).
var base: Dictionary = {}
## Group stores: item id -> Array of lots {"qty": float, "age_days": float}. See core/stores.gd.
var stores: Dictionary = {}
## Air temperature and today's range (systems/time.gd).
var climate: Dictionary = {}
## Power, water mains and phones (systems/infrastructure.gd).
var infrastructure: Dictionary = {}
## Standing orders the player sets: rations, boiling, generator, guns (systems/resources.gd).
var policies: Dictionary = {}
## Decisions waiting for the player. Each: {"id", "kind", "text", "options", ...}.
var pending_decisions: Array = []
## One-off facts other systems need to know, e.g. which events have fired.
var flags: Dictionary = {}
## Running totals for the end-of-run score.
var stats: Dictionary = {}
## {"state": &"running" | &"won" | &"lost", ...} (systems/outcome.gd).
var outcome: Dictionary = {}
var next_id: int = 1
## Hooks for later prototypes. Both stay empty in Prototype 1.
var factions: Array = []
var region: Dictionary = {}


func reset(new_seed: int) -> void:
	run_seed = new_seed
	tick = 0
	survivors = []
	buildings = []
	town = {}
	zones = []
	base = {}
	stores = {}
	climate = {}
	infrastructure = {}
	policies = {}
	pending_decisions = []
	flags = {}
	stats = {}
	outcome = {"state": &"running"}
	next_id = 1
	factions = []
	region = {}


## A fresh id for decisions and other run-scoped records.
func new_id() -> int:
	next_id += 1
	return next_id - 1


func survivor(id: String) -> Dictionary:
	for s: Dictionary in survivors:
		if s["id"] == id:
			return s
	return {}


## Survivors still in the group: alive and not gone.
func group() -> Array:
	return survivors.filter(func(s: Dictionary) -> bool: return s["status"] == &"ok")


func building(id: String) -> Dictionary:
	for b: Dictionary in buildings:
		if b["id"] == id:
			return b
	return {}


func is_running() -> bool:
	return outcome.get("state", &"running") == &"running"


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
	return (DAY_START_MINUTE + at_tick * MINUTES_PER_TICK) / MINUTES_PER_DAY


## True on the first tick of a new day (00:00), not on tick 0.
func is_new_day() -> bool:
	return tick > 0 and minute_of_day() == 0


## True at 06:00 each morning after the first.
func is_dawn() -> bool:
	return tick > 0 and minute_of_day() == DAYTIME_START_MINUTE


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
