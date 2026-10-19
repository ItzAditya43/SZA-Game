extends "res://core/sim_system.gd"
## Infected. The infected are sick living people, so they follow physical rules.
## The town is split into 16 zones (4 x 4, 500 m each), each holding a count.
## Counts grow while the outbreak spreads, drift between neighbouring zones, are
## pulled toward noise, seek water in the heat, and die off from day 15 because
## nobody feeds or treats them. They are least active in the midday heat and most
## active at night. Survivors out of base roll for encounters every tick, by zone
## density, noise, time of day, skill and weapon.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Difficulty := preload("res://core/difficulty.gd")
const Traits := preload("res://core/traits.gd")

const ZONE_AREA_KM2: float = 0.25
const ZONE_HALF_M: float = 250.0
const COLUMN_NAMES: String = "ABCD"

# --- Activity by time of day ---
const ACTIVITY_NIGHT: float = 1.0
const ACTIVITY_DAWN_DUSK: float = 0.75
const ACTIVITY_DAY: float = 0.5
## Midday heat (12:00-16:00) slows them further: activity falls by this share per °C above 32 °C.
const MIDDAY_START_MINUTE: int = 12 * 60
const MIDDAY_END_MINUTE: int = 16 * 60
const HEAT_SLOWDOWN_FROM_C: float = 32.0
const HEAT_SLOWDOWN_PER_C: float = 0.08
const HEAT_SLOWDOWN_FLOOR: float = 0.2

# --- Movement (per hour) ---
## Share of each zone that wanders into its neighbours every hour.
const DIFFUSION_PER_HOUR: float = 0.003
## In the afternoon heat, a share of zones without water move toward the canal.
const WATER_SEEKING_PER_HOUR: float = 0.005
const WATER_SEEKING_ABOVE_C: float = 35.0
## Noise pulls at most this share of a zone per event, scaled by how far into the zone the sound reaches.
const NOISE_PULL_MAX: float = 0.15

# --- Die-off ---
## Zones with water lose fewer of their infected.
const WATER_DIE_OFF_MULT: float = 0.75
## Days of 40 °C or more kill weakened infected.
const HEAT_WAVE_DIE_OFF_C: float = 40.0
const HEAT_WAVE_DIE_OFF_PER_DAY: float = 0.005

# --- Encounters ---
## Chance per tick of meeting infected = 1 - exp(-K x density x activity x modifiers), density per km².
const ENCOUNTER_K: float = 3.2e-5
## Searching inside: infected trapped in the building matter more than the street.
const INSIDE_EXPOSURE_BASE: float = 0.6
const INSIDE_EXPOSURE_PER_DANGER: float = 1.5
const NOISE_EXPOSURE_PER_M: float = 1.0 / 50.0
const STEALTH_BASE: float = 1.2
const STEALTH_PER_SKILL: float = 0.05
## Group size met: 1 plus up to this many more per 1,500 infected per km².
const GROUP_PER_DENSITY: float = 1.0 / 1500.0
const AVOID_BASE: float = 0.35
const AVOID_PER_SCAVENGING: float = 0.05
const AVOID_PER_EXTRA_INFECTED: float = 0.08
const AVOID_DAYLIGHT_BONUS: float = 0.1
const FIGHT_BASE: float = 0.55
const FIGHT_PER_MARGIN: float = 0.08
const WEAPON_BONUS: Dictionary = {"": 0.0, "machete": 1.5, "rifle": 4.0}
const GUNSHOT_RADIUS_M: float = 600.0
## When a fight goes badly: share of outcomes that are death or a bite (the rest are wounds).
const KILLED_SHARE: float = 0.08
const BITTEN_SHARE: float = 0.35
const INJURY_TYPES: Array[Dictionary] = [
	{"type": &"cut", "weight": 0.55, "bleed": Vector2(0.02, 0.05)},
	{"type": &"laceration", "weight": 0.40, "bleed": Vector2(0.1, 0.5)},
	{"type": &"arterial", "weight": 0.05, "bleed": Vector2(9.0, 9.0)},
]
const WOUND_LOCATIONS: Dictionary = {"arm": 0.45, "leg": 0.35, "torso": 0.15, "neck": 0.05}
const BITE_LOCATIONS: Dictionary = {"arm": 0.5, "leg": 0.3, "torso": 0.12, "neck": 0.08}
const STRESS_BY_OUTCOME: Dictionary = {&"avoided": 2.0, &"fought_off": 5.0, &"injured": 10.0, &"bitten": 20.0, &"killed": 0.0}


@warning_ignore("integer_division")
func setup() -> void:
	listen(&"noise", _on_noise)
	listen(&"survivor_turned", _on_survivor_turned)
	var zones: Dictionary = Data.table("town_layout")["zones"]
	var start: Array = zones["start_infected"]
	var weights: Array = WorldState.town["zone_growth_weights"]
	var rows: Array = WorldState.town["rows"]
	var size: int = int(zones["size_tiles"])
	for i: int in start.size():
		var has_water: bool = false
		for y: int in range(int(i / Geo.ZONE_COLS) * size, (int(i / Geo.ZONE_COLS) + 1) * size):
			if String(rows[y]).substr((i % Geo.ZONE_COLS) * size, size).contains("~"):
				has_water = true
		WorldState.zones.append({"index": i, "name": zone_name(i), "infected": float(start[i]) * Difficulty.mult("infected"),
			"growth_weight": float(weights[i]), "has_water": has_water})
	WorldState.stats["infected_killed"] = 0
	WorldState.stats["infected_peak"] = total()


func tick() -> void:
	if WorldState.is_new_day():
		_daily()
	if WorldState.tick % 6 == 0:
		_hourly()
	for s: Dictionary in WorldState.survivors:
		if s["status"] == &"ok" and not s["exposure"].is_empty():
			_roll_encounter(s)


## Activity right now, 0..1: lowest in the midday heat, highest at night.
static func activity() -> float:
	var minute: int = WorldState.minute_of_day()
	if WorldState.phase() == WorldState.PHASE_NIGHT:
		return ACTIVITY_NIGHT
	if minute < 8 * 60 or minute >= 16 * 60:
		return ACTIVITY_DAWN_DUSK
	if minute >= MIDDAY_START_MINUTE and minute < MIDDAY_END_MINUTE:
		var temp: float = float(WorldState.climate.get("temperature_c", 30.0))
		return ACTIVITY_DAY * clampf(1.0 - (temp - HEAT_SLOWDOWN_FROM_C) * HEAT_SLOWDOWN_PER_C, HEAT_SLOWDOWN_FLOOR, 1.0)
	return ACTIVITY_DAY


static func total() -> float:
	var sum: float = 0.0
	for zone: Dictionary in WorldState.zones:
		sum += float(zone["infected"])
	return sum


@warning_ignore("integer_division")
static func zone_name(index: int) -> String:
	return "%s%d" % [COLUMN_NAMES[index % Geo.ZONE_COLS], index / Geo.ZONE_COLS + 1]


# --- Population ---

func _daily() -> void:
	var day: int = WorldState.day()
	var scenario: Dictionary = Data.table("scenario")["infected"]
	if day <= int(scenario["growth_until_day"]):
		var weight_sum: float = 0.0
		for zone: Dictionary in WorldState.zones:
			weight_sum += float(zone["growth_weight"])
		for zone: Dictionary in WorldState.zones:
			zone["infected"] = float(zone["infected"]) + float(scenario["growth_per_day"]) * Difficulty.mult("infected") \
				* float(zone["growth_weight"]) / weight_sum
		WorldState.stats["infected_peak"] = maxf(float(WorldState.stats["infected_peak"]), total())
	var rate: float = 0.0
	if day >= int(scenario["die_off_start_day"]):
		rate = float(scenario["die_off_rate_per_day"])
	var heat_deaths: float = HEAT_WAVE_DIE_OFF_PER_DAY if float(WorldState.climate.get("today_max_c", 0.0)) >= HEAT_WAVE_DIE_OFF_C else 0.0
	if rate + heat_deaths <= 0.0:
		return
	var before: float = total()
	for zone: Dictionary in WorldState.zones:
		var zone_rate: float = rate * (WATER_DIE_OFF_MULT if zone["has_water"] else 1.0) + heat_deaths
		zone["infected"] = float(zone["infected"]) * (1.0 - zone_rate)
	if day == int(scenario["die_off_start_day"]):
		EventBus.emit_event(&"die_off_started", {"text": "Fewer infected on the streets. Without food, water or care they have started to die."})
	if heat_deaths > 0.0:
		EventBus.emit_event(&"heat_die_off", {"dead": before - total(),
			"text": "The %.0f °C heat killed about %d weakened infected." % [float(WorldState.climate["today_max_c"]), roundi(before - total())]})


func _hourly() -> void:
	var counts: Array[float] = []
	for zone: Dictionary in WorldState.zones:
		counts.append(float(zone["infected"]))
	var next: Array[float] = counts.duplicate()
	for i: int in counts.size():
		var neighbours: Array[int] = _neighbours(i)
		var leaving: float = counts[i] * DIFFUSION_PER_HOUR
		next[i] -= leaving
		for n: int in neighbours:
			next[n] += leaving / neighbours.size()
	var hot: bool = float(WorldState.climate.get("temperature_c", 0.0)) >= WATER_SEEKING_ABOVE_C
	if hot:
		for i: int in counts.size():
			if WorldState.zones[i]["has_water"]:
				continue
			var water_zone: int = (Geo.ZONE_COLS - 1) * Geo.ZONE_COLS + i % Geo.ZONE_COLS
			var moving: float = next[i] * WATER_SEEKING_PER_HOUR
			next[i] -= moving
			next[water_zone] += moving
	for i: int in counts.size():
		WorldState.zones[i]["infected"] = maxf(0.0, next[i])
	_drift_to_attention()


## Every hour, infected in zones near a site with attention edge toward it.
func _drift_to_attention() -> void:
	var config: Dictionary = Data.table("attention")
	var radius: float = float(config["drift_radius_m"])
	var act: float = activity()
	for site: String in WorldState.attention:
		var building: Dictionary = WorldState.building(site)
		if building.is_empty():
			continue
		var pos: Vector2 = Geo.building_center_m(building)
		var target: int = Geo.zone_index_at(pos)
		var share: float = float(config["drift_share_per_hour_per_100"]) * float(WorldState.attention[site]) / 100.0 * act
		var moved: float = 0.0
		for i: int in WorldState.zones.size():
			if i == target or pos.distance_to(Geo.zone_center_m(i)) > radius:
				continue
			var zone: Dictionary = WorldState.zones[i]
			var count: float = float(zone["infected"]) * minf(share, 0.5)
			zone["infected"] = float(zone["infected"]) - count
			moved += count
		WorldState.zones[target]["infected"] = float(WorldState.zones[target]["infected"]) + moved


@warning_ignore("integer_division")
static func _neighbours(index: int) -> Array[int]:
	var out: Array[int] = []
	var col: int = index % Geo.ZONE_COLS
	var row: int = index / Geo.ZONE_COLS
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if col + d.x >= 0 and col + d.x < Geo.ZONE_COLS and row + d.y >= 0 and row + d.y < Geo.ZONE_COLS:
			out.append((row + d.y) * Geo.ZONE_COLS + col + d.x)
	return out


## Infected within earshot of a one-off noise move toward it, more the farther the
## sound reaches into their zone. Continuous noise and light from a site the group
## uses work through its attention instead (_drift_to_attention).
func _on_noise(payload: Dictionary) -> void:
	if payload.get("continuous", false):
		return
	_pull(Vector2(float(payload["x_m"]), float(payload["y_m"])), float(payload["radius_m"]), NOISE_PULL_MAX,
		StringName(payload.get("source", &"noise")))


func _pull(pos: Vector2, radius: float, pull_max: float, source: StringName) -> void:
	var target: int = Geo.zone_index_at(pos)
	var moved: float = 0.0
	var act: float = activity()
	for i: int in WorldState.zones.size():
		if i == target:
			continue
		var distance: float = pos.distance_to(Geo.zone_center_m(i))
		var reach: float = radius - maxf(0.0, distance - ZONE_HALF_M)
		if reach <= 0.0:
			continue
		var zone: Dictionary = WorldState.zones[i]
		var count: float = float(zone["infected"]) * pull_max * clampf(reach / radius, 0.0, 1.0) * act
		zone["infected"] = float(zone["infected"]) - count
		moved += count
	WorldState.zones[target]["infected"] = float(WorldState.zones[target]["infected"]) + moved
	if moved >= 5.0 and source in [&"gunshot", &"generator", &"hammering"]:
		var what: String = {&"gunshot": "The gunshot", &"generator": "The generator", &"hammering": "The hammering"}[source]
		EventBus.emit_event(&"noise_drew_infected", {"source": source, "zone": target, "moved": moved,
			"text": "%s drew about %d infected toward %s." % [what, roundi(moved), zone_name(target)]})


func _on_survivor_turned(payload: Dictionary) -> void:
	# Turned away from base, they join the infected where they stood. At base,
	# Base deals with them.
	if payload.get("at_base", false):
		return
	var zone: int = Geo.zone_index_at(Vector2(float(payload["x_m"]), float(payload["y_m"])))
	WorldState.zones[zone]["infected"] = float(WorldState.zones[zone]["infected"]) + 1.0


# --- Encounters ---

func _roll_encounter(s: Dictionary) -> void:
	var exposure: Dictionary = s["exposure"]
	var zone: Dictionary = WorldState.zones[int(exposure.get("zone", 0))]
	var density: float = float(zone["infected"]) / ZONE_AREA_KM2
	var act: float = activity()
	var mult: float = 1.0
	if not exposure["outdoors"]:
		var building: Dictionary = WorldState.building(String(exposure["building"]))
		mult = INSIDE_EXPOSURE_BASE + INSIDE_EXPOSURE_PER_DANGER * float(building.get("danger", 0.3))
	mult *= 1.0 + float(exposure["noise_m"]) * NOISE_EXPOSURE_PER_M
	mult *= maxf(0.3, STEALTH_BASE - STEALTH_PER_SKILL * Body.skill(s, "scavenging"))
	var chance: float = 1.0 - exp(-ENCOUNTER_K * Difficulty.mult("encounters") * density * act * mult)
	if not Rng.chance(chance):
		return
	var met: int = 1 + floori(Rng.randf() * (1.0 + density * GROUP_PER_DENSITY))
	_resolve(s, zone, met)


@warning_ignore("integer_division")
func _resolve(s: Dictionary, zone: Dictionary, met: int) -> void:
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	var place: String = _place_name(s)
	var avoid: float = AVOID_BASE + AVOID_PER_SCAVENGING * Body.skill(s, "scavenging") - AVOID_PER_EXTRA_INFECTED * (met - 1)
	avoid += -AVOID_DAYLIGHT_BONUS if night else AVOID_DAYLIGHT_BONUS
	var outcome: StringName
	var killed_infected: int = 0
	var shots: int = 0
	if Rng.chance(clampf(avoid, 0.05, 0.85)):
		outcome = &"avoided"
	else:
		var weapon: String = s["weapon"]
		if weapon == "rifle" and int(s["ammo"]) <= 0:
			weapon = ""
		var defense: float = Body.skill(s, "combat") / 2.0 + float(WEAPON_BONUS.get(weapon, 0.0))
		var margin: float = defense - float(met) * (1.3 if night else 1.0)
		if weapon == "rifle":
			shots = mini(int(s["ammo"]), 1 + met / 2)
			s["ammo"] = int(s["ammo"]) - shots
			EventBus.emit_event(&"noise", {"x_m": s["x_m"], "y_m": s["y_m"], "radius_m": GUNSHOT_RADIUS_M, "source": &"gunshot"})
		var fight: float = clampf(FIGHT_BASE + FIGHT_PER_MARGIN * margin, 0.1, 0.95) / Body.injury_multiplier(s)
		if Rng.chance(fight):
			outcome = &"fought_off"
			killed_infected = mini(met, 1 + Rng.randi_range(0, 1) + (shots if shots > 0 else 0))
		else:
			var roll: float = Rng.randf()
			var badness: float = clampf(1.0 - margin * 0.1, 0.5, 2.0)
			if roll < KILLED_SHARE * badness:
				outcome = &"killed"
			elif roll < (KILLED_SHARE + BITTEN_SHARE) * badness:
				outcome = &"bitten"
			else:
				outcome = &"injured"
			killed_infected = Rng.randi_range(0, 1)
	killed_infected = mini(killed_infected, roundi(float(zone["infected"])))
	zone["infected"] = maxf(0.0, float(zone["infected"]) - killed_infected)
	WorldState.stats["infected_killed"] = int(WorldState.stats["infected_killed"]) + killed_infected
	Traits.add_stress(s, float(STRESS_BY_OUTCOME[outcome]), "fights")
	match outcome:
		&"injured":
			s["injuries"].append(_random_wound())
		&"bitten":
			var bite: Dictionary = Body.new_injury(&"bite", _pick(BITE_LOCATIONS), 0.05)
			# Until they are back and say so, nobody knows it was a bite.
			bite["disguised_as"] = &"cut"
			s["injuries"].append(bite)
		&"killed":
			s["health"] = 0.0
			s["death_hint"] = "killed by infected"
	var group: String = "an infected" if met == 1 else "%d infected" % met
	var gun: String = " firing %d shot%s" % [shots, "" if shots == 1 else "s"] if shots > 0 else ""
	var text: String = {
		&"avoided": "%s slipped past %s near %s." % [s["name"], group, place],
		&"fought_off": "%s fought off %s near %s%s." % [s["name"], group, place, gun],
		&"injured": "%s was hurt fighting %s near %s%s." % [s["name"], group, place, gun],
		&"bitten": "%s was hurt fighting %s near %s%s." % [s["name"], group, place, gun],
		&"killed": "%s was killed by %s near %s." % [s["name"], group, place],
	}[outcome]
	EventBus.emit_event(&"encounter", {"survivor": s["id"], "outcome": outcome, "met": met, "zone": zone["index"],
		"shots": shots, "abort_trip": outcome in [&"injured", &"bitten"], "text": text})


func _random_wound() -> Dictionary:
	var roll: float = Rng.randf()
	var chosen: Dictionary = INJURY_TYPES[0]
	for kind: Dictionary in INJURY_TYPES:
		roll -= float(kind["weight"])
		if roll < 0.0:
			chosen = kind
			break
	var bleed: Vector2 = chosen["bleed"]
	return Body.new_injury(chosen["type"], _pick(WOUND_LOCATIONS), lerpf(bleed.x, bleed.y, Rng.randf()))


static func _pick(weights: Dictionary) -> String:
	var roll: float = Rng.randf()
	for key: String in weights:
		roll -= float(weights[key])
		if roll < 0.0:
			return key
	return String(weights.keys()[0])


static func _place_name(s: Dictionary) -> String:
	return String(s["trip"].get("place", "the base"))
