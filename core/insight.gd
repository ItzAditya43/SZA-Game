extends RefCounted
## Read-only explanations and forecasts for the UI. Every number the player sees
## can say where it comes from (realism rule 4: the player can always trace why),
## and the planner's estimates use the simulation's own formulas and constants,
## so they never drift from what will actually happen. Nothing here changes the world.
##
## A breakdown is {"value": float, "unit": String, "label": String,
##   "contributions": [{"label": String, "amount": float}], "forecast": String}.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Traits := preload("res://core/traits.gd")
const Geo := preload("res://core/geo.gd")
const Survivors := preload("res://systems/survivors.gd")
const Jobs := preload("res://systems/jobs.gd")
const Infected := preload("res://systems/infected.gd")
const TimeSystem := preload("res://systems/time.gd")
const Resources := preload("res://systems/resources.gd")
const Infrastructure := preload("res://systems/infrastructure.gd")

const SLEEP_NEED_H: float = 7.0
## Encounter-risk bands for a trip, by the chance of meeting infected at least once.
## Bands for the chance of coming back hurt (injured, bitten or worse).
const RISK_BANDS: Array = [[0.08, "low"], [0.2, "moderate"], [0.4, "high"], [1.01, "severe"]]


static func breakdown(value: float, unit: String, label: String, contributions: Array, forecast: String = "") -> Dictionary:
	return {"value": value, "unit": unit, "label": label, "contributions": contributions, "forecast": forecast}


static func part(label: String, amount: float) -> Dictionary:
	return {"label": label, "amount": amount}


# --- A survivor's day ---

## Hours a typical day splits into, by activity, from the survivor's jobs.
static func typical_day(s: Dictionary) -> Dictionary:
	var hours: Dictionary = {}
	for shift: StringName in [&"day", &"night"]:
		var job: StringName = s["jobs"][shift]
		if s["quarantined"]:
			job = &"rest"
		match job:
			&"rest":
				if shift == &"night":
					_add_hours(hours, &"idle", 3.0)
					_add_hours(hours, &"sleeping", 9.0)
				else:
					_add_hours(hours, &"resting", 12.0)
			&"guard":
				_add_hours(hours, &"guarding", 12.0)
			&"scavenge":
				_add_hours(hours, &"travelling", 3.0)
				_add_hours(hours, &"searching", Jobs.SEARCH_HOURS)
				_add_hours(hours, &"idle", 12.0 - 3.0 - Jobs.SEARCH_HOURS)
			_:
				_add_hours(hours, Jobs.JOB_ACTIVITY.get(job, &"idle"), Jobs.WORK_MINUTES / 60.0)
				_add_hours(hours, &"idle", 12.0 - Jobs.WORK_MINUTES / 60.0)
	return hours


static func _add_hours(hours: Dictionary, activity: StringName, h: float) -> void:
	hours[activity] = float(hours.get(activity, 0.0)) + h


## Litres a survivor needs to drink in a typical day at today's temperatures.
static func water_need(s: Dictionary) -> Dictionary:
	var climate: Dictionary = WorldState.climate
	var mean_air: float = (float(climate.get("today_min_c", 28.0)) + float(climate.get("today_max_c", 36.0))) / 2.0
	var base: float = Survivors.WATER_L_PER_DAY_BASE
	var at_rest: float = 0.0
	var total: float = 0.0
	for activity: StringName in typical_day(s):
		var h: float = float(typical_day(s)[activity]) / 24.0
		var air: float = mean_air if activity in [&"travelling", &"heavy_work", &"guarding"] else mean_air - Survivors.INDOOR_COOLING_C
		var heat: float = Survivors.WATER_EXTRA_PER_C * maxf(0.0, air - Survivors.WATER_HEAT_THRESHOLD_C) * Traits.mult(s, "water_heat_mult")
		var mult: float = float(Survivors.ACTIVITY[activity]["water"])
		total += base * (1.0 + heat) * mult * h
		at_rest += base * mult * h
	var parts: Array = [part("basic need", base), part("work and activity", at_rest - base), part("heat (about %d °C)" % roundi(mean_air), total - at_rest)]
	var illness: Dictionary = s["illness"]
	if not illness.is_empty():
		var loss: float = float(illness["loss_l_day"]) * (Survivors.ORS_LOSS_MULT if int(illness.get("ors_until_tick", -1)) >= WorldState.tick else 1.0)
		parts.append(part("%s (fluid loss)" % illness["type"], loss))
		total += loss
	return breakdown(total, "L", "water a day", parts)


## kcal a survivor burns in a typical day.
static func food_need(s: Dictionary) -> Dictionary:
	var size: float = pow(float(s["weight_kg"]) / Survivors.REFERENCE_WEIGHT_KG, 0.75)
	var rest: float = Survivors.KCAL_PER_DAY_AT_REST * size
	var total: float = 0.0
	for activity: StringName in typical_day(s):
		total += rest * float(Survivors.ACTIVITY[activity]["kcal"]) * float(typical_day(s)[activity]) / 24.0
	return breakdown(total, "kcal", "energy a day", [part("body at rest (%d kg)" % roundi(float(s["weight_kg"])), rest),
		part("work and activity", total - rest)])


static func sleep_need_h(s: Dictionary) -> float:
	var need: float = SLEEP_NEED_H
	if WorldState.base.get("attention_level", &"low") != &"low":
		need += Traits.add(s, "sleep_need_add_when_noisy_h")
	return need


## What has moved this survivor's stress over the last few days, biggest first.
static func stress_breakdown(s: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for day: Variant in s.get("stress_causes", {}):
		var causes: Dictionary = s["stress_causes"][day]
		for reason: String in causes:
			totals[reason] = float(totals.get(reason, 0.0)) + float(causes[reason])
	var parts: Array = []
	for reason: String in totals:
		if absf(float(totals[reason])) >= 0.5:
			parts.append(part(reason, float(totals[reason])))
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a["amount"])) > absf(float(b["amount"])))
	var stress: float = float(s["stress"])
	var forecast: String = "Calm." if stress < 40.0 else ("Strained." if stress < Body.REFUSES_JOBS_STRESS else
		("Too shaken to work." if stress < Body.MAY_LEAVE_STRESS else "May leave the group any night."))
	return breakdown(stress, "", "stress (last 3 days)", parts, forecast + " Refuses work at 80, may leave at 95.")


static func health_breakdown(s: Dictionary) -> Dictionary:
	var parts: Array = []
	var damage: Dictionary = s.get("damage", {})
	for cause: String in damage:
		parts.append(part(cause, -float(damage[cause]) * WorldState.TICKS_PER_DAY))
	var forecast: String = "Losing health." if not parts.is_empty() else "Recovering slowly when rested, fed and watered."
	return breakdown(float(s["health"]), "", "health (per day)", parts, forecast)


## The four meters on a compact survivor card, each as a breakdown with a 0..1 fill.
static func meters(s: Dictionary) -> Dictionary:
	var water: Dictionary = water_need(s)
	var food: Dictionary = food_need(s)
	var slept: float = float(s.get("slept_last_night_h", s.get("slept_h", 0.0)))
	# Before the first dawn nobody has had a night yet: show it as rested.
	var first_night: bool = not s.has("slept_last_night_h")
	if first_night:
		slept = sleep_need_h(s)
	return {
		"water": {"fill": clampf(1.0 - float(s["water_deficit_l"]) / Body.COLLAPSE_DEHYDRATION_L, 0.0, 1.0),
			"bad": float(s["water_deficit_l"]) >= Body.THIRSTY_L,
			"text": "%.1f / %.1f L" % [float(s["drunk_today_l"]), float(water["value"])], "breakdown": water,
			"extra": "Behind by %.1f L (thirsty at 3, confused at 6, collapse at 9)." % float(s["water_deficit_l"])},
		"food": {"fill": clampf(1.0 - float(s["kcal_debt"]) / Body.WEAK_KCAL, 0.0, 1.0),
			"bad": float(s["kcal_debt"]) >= Body.HUNGRY_KCAL,
			"text": "%s / %s kcal" % [short(float(s["kcal_eaten_today"])), short(float(food["value"]))], "breakdown": food,
			"extra": "Short by %s kcal (hungry at 4,000, weak at 12,000)." % thousands(float(s["kcal_debt"]))},
		"sleep": {"fill": clampf(slept / sleep_need_h(s), 0.0, 1.0), "bad": float(s["sleep_debt_h"]) >= Body.SLEEP_DEBT_MISTAKES_H,
			"text": ("rested" if first_night else "%.1f / %.0f h" % [slept, sleep_need_h(s)]),
			"breakdown": breakdown(slept, "h", "sleep last night", [part("needed", sleep_need_h(s)), part("sleep debt", float(s["sleep_debt_h"]))],
				"Mistakes and accidents rise with 6+ h of sleep debt.")},
		"stress": {"fill": clampf(float(s["stress"]) / 100.0, 0.0, 1.0), "bad": float(s["stress"]) >= Body.REFUSES_JOBS_STRESS,
			"text": "%d / 100" % roundi(float(s["stress"])), "breakdown": stress_breakdown(s)},
	}


# --- Stores ---

## Usable water by source, and how long it lasts at the group's daily need.
static func water_forecast() -> Dictionary:
	var stores: Dictionary = WorldState.stores
	var parts: Array = [part("bottled", Stores.total(stores, "water_bottled")), part("safe (boiled or tap)", Stores.total(stores, "water_boiled")),
		part("untreated (needs boiling)", Stores.total(stores, "water_untreated"))]
	var base: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	var taps: bool = WorldState.infrastructure.get("mains_on", false)
	if not base.is_empty() and float(base["tank_l"]) > 0.0 and not taps:
		parts.append(part("base roof tank (needs boiling)", float(base["tank_l"])))
	var total: float = 0.0
	for p: Dictionary in parts:
		total += float(p["amount"])
	var use: float = group_water_need()
	var days: float = total / maxf(use, 0.1)
	var forecast: String = "Taps are running: drinking water is free until they fail." if taps else \
		"Lasts about %.1f days at %.0f L a day for %d people." % [days, use, WorldState.group().size()]
	var out: Dictionary = breakdown(total, "L", "water", parts, forecast)
	out["days"] = INF if taps else days
	out["daily"] = use
	out["trend"] = _trend("water_l")
	return out


static func group_water_need() -> float:
	var use: float = 0.0
	for s: Dictionary in WorldState.group():
		use += float(water_need(s)["value"])
	return use


static func food_forecast() -> Dictionary:
	var stores: Dictionary = WorldState.stores
	var parts: Array = []
	var ready: float = 0.0
	var raw: float = 0.0
	for item: String in Stores.snapshot(stores):
		var row: Dictionary = Data.entry("items", item)
		if row.get("category", "") != "food":
			continue
		var qty: float = Stores.total(stores, item)
		parts.append(part(String(row["name"]) + (" (needs cooking)" if row.get("needs_cooking", false) else ""), qty))
		if row.get("needs_cooking", false):
			raw += qty
		else:
			ready += qty
	var use: float = 0.0
	for s: Dictionary in WorldState.group():
		use += float(food_need(s)["value"])
	var days: float = (ready + raw) / maxf(use, 1.0)
	var forecast: String = "Lasts about %.1f days at %s kcal a day." % [days, thousands(use)]
	if raw > ready and not WorldState.group().any(func(s: Dictionary) -> bool: return s["jobs"][&"day"] == &"cook"):
		forecast += " Most of it must be cooked, and nobody is on the cook job."
	var out: Dictionary = breakdown(ready + raw, "kcal", "food", parts, forecast)
	out["days"] = days
	out["daily"] = use
	out["trend"] = _trend("food_kcal")
	return out


static func fuel_forecast() -> Dictionary:
	var stores: Dictionary = WorldState.stores
	var petrol: float = Stores.total(stores, "fuel")
	var gas: float = Stores.total(stores, "cooking_gas")
	var wood: float = Stores.total(stores, "materials")
	var generator: bool = Stores.total(stores, "generator") >= 1.0
	var parts: Array = [part("petrol/diesel (L)", petrol), part("cooking gas (kg)", gas), part("materials that can burn as firewood", wood)]
	var hours: float = petrol / Infrastructure.GENERATOR_FUEL_L_PER_H
	var forecast: String = ("Generator: about %.0f hours of running." % hours) if generator else "No generator yet."
	var out: Dictionary = breakdown(gas, "kg", "cooking gas", parts, forecast)
	out["generator_hours"] = hours if generator else 0.0
	return out


static func medicine_forecast() -> Dictionary:
	var stores: Dictionary = WorldState.stores
	var parts: Array = []
	for item: String in ["antibiotics", "bandages", "ors", "painkillers", "tourniquet"]:
		parts.append(part(String(Data.entry("items", item)["name"]), Stores.total(stores, item)))
	var strips: float = Stores.total(stores, "antibiotics")
	return breakdown(strips, "strips", "antibiotics", parts,
		"Antibiotics are the only cure for an infected wound or sepsis." if strips < 2.0 else "")


## Change since yesterday's snapshot, or 0.
static func _trend(key: String) -> float:
	var history: Array = WorldState.stats.get("history", [])
	if history.size() < 2:
		return 0.0
	return float(history[-1][key]) - float(history[-2][key])


# --- Base ---

static func defense_breakdown() -> Dictionary:
	var parts: Array = []
	var names: Dictionary = {"building": "the building itself", "barricades": "barricades", "guards": "guards on watch",
		"weapons": "weapons in guards' hands", "others": "others awake at base"}
	var source: Dictionary = WorldState.base.get("defense_parts", {})
	for key: String in source:
		parts.append(part(names.get(key, key), float(source[key])))
	return breakdown(float(WorldState.base.get("defense", 0.0)), "", "defense", parts,
		"An attack breaks in when its strength (about 3.5 per infected) beats this.")


## Attention points gained per hour right now, by what is giving the base away.
static func attention_breakdown() -> Dictionary:
	var config: Dictionary = Data.table("attention")
	var signals: Dictionary = config["signals_per_hour"]
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	var occupants: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	var parts: Array = []
	if not occupants.is_empty():
		parts.append(part("voices and foot traffic", occupants.size() * float(signals["person_present"])))
		parts.append(part("latrine and rubbish smell", occupants.size() * float(signals["waste_per_person"])))
	var cooking: float = 0.0
	var hammering: float = 0.0
	for s: Dictionary in occupants:
		if s["job_now"] == &"cook" and s["activity"] == &"light_work":
			cooking += float(signals["cooking_smoke"]) + (float(signals["firelight_at_night"]) if night else 0.0)
		elif s["job_now"] in [&"fortify", &"quick_fortify"] and s["activity"] == &"heavy_work":
			hammering += float(signals["hammering"])
	if cooking > 0.0:
		parts.append(part("cooking smoke and firelight", cooking))
	if hammering > 0.0:
		parts.append(part("hammering", hammering))
	if WorldState.infrastructure.get("generator_running", false) and not occupants.is_empty():
		parts.append(part("generator noise and light", float(signals["generator_noise"]) + (float(signals["generator_light_at_night"]) if night else 0.0)))
	var bodies: int = WorldState.base.get("bodies", []).size()
	if bodies > 0:
		parts.append(part("unburied bodies", bodies * float(signals["unburied_body"])))
	var value: float = float(WorldState.base.get("attention", 0.0))
	var drawn: float = float(config["attack_baseline"]) + value / float(config["attack_reference"])
	var forecast: String = "Night attacks at %.1f× the rate of a site nobody knows about yet. It fades by half every %d days once you leave (%d while you stay)." % [
		drawn / float(config["attack_baseline"]), roundi(float(config["half_life_days_empty"])), roundi(float(config["half_life_days_occupied"]))]
	return breakdown(value, "", "attention (gained per hour now)", parts, forecast)


# --- The scavenge planner ---

## What a trip would look like, using the same speeds, search time, noise and
## encounter formula as the simulation. depart: &"now", &"midday", &"dusk" or &"night".
static func trip_estimate(s: Dictionary, building: Dictionary, depart: StringName) -> Dictionary:
	var origin: Vector2 = Geo.base_center_m()
	var dest: Vector2 = Geo.building_center_m(building)
	var distance: float = Geo.street_distance_m(origin, dest)
	var speed_mult: float = maxf(Jobs.MIN_SPEED_MULT, Body.work_speed(s)) * Traits.mult(s, "travel_speed_mult")
	var tick: int = Jobs.departure_tick(depart)
	var start_tick: int = tick
	var risk_keep: float = 1.0
	var hurt_keep: float = 1.0
	var scav: float = Body.skill(s, "scavenging")
	var noise: float = Jobs.NOISE_TRAVEL_M
	# Out.
	var progress: float = 0.0
	while true:
		progress = minf(distance, progress + Jobs.SPEED_OUT_M_PER_H * speed_mult / 6.0)
		var meet: float = _tick_risk(origin.lerp(dest, progress / maxf(distance, 1.0)), tick, -1.0, noise, scav)
		risk_keep *= 1.0 - meet
		hurt_keep *= 1.0 - meet * hurt_if_met(s, origin.lerp(dest, progress / maxf(distance, 1.0)), tick)
		tick += 1
		if progress >= distance:
			break
	var arrive_tick: int = tick
	var night: bool = WorldState.phase_at(arrive_tick - 1) == WorldState.PHASE_NIGHT
	var search_ticks: int = roundi(Jobs.SEARCH_HOURS * (Jobs.NIGHT_SEARCH_TIME_MULT if night else 1.0) * 6.0)
	for i: int in search_ticks:
		var meet_inside: float = _tick_risk(dest, tick, float(building["danger"]), Jobs.NOISE_SEARCH_M, scav)
		risk_keep *= 1.0 - meet_inside
		hurt_keep *= 1.0 - meet_inside * hurt_if_met(s, dest, tick)
		tick += 1
	# Back.
	progress = 0.0
	while true:
		progress = minf(distance, progress + Jobs.SPEED_BACK_M_PER_H * speed_mult / 6.0)
		var meet_back: float = _tick_risk(dest.lerp(origin, progress / maxf(distance, 1.0)), tick, -1.0, noise, scav)
		risk_keep *= 1.0 - meet_back
		hurt_keep *= 1.0 - meet_back * hurt_if_met(s, dest.lerp(origin, progress / maxf(distance, 1.0)), tick)
		tick += 1
		if progress >= distance:
			break
	var risk: float = 1.0 - risk_keep
	var hurt: float = 1.0 - hurt_keep
	var band: String = "severe"
	for row: Array in RISK_BANDS:
		if hurt < float(row[0]):
			band = row[1]
			break
	var carry: float = Jobs.CARRY_KG * Traits.mult(s, "carry_kg_mult") * clampf(Body.work_speed(s), Jobs.MIN_SPEED_MULT, 1.0)
	return {
		"distance_m": distance, "depart_tick": start_tick, "return_tick": tick - 1,
		"hours": float(tick - 1 - start_tick) / 6.0, "risk": risk, "hurt": hurt, "band": band, "carry_kg": carry,
		"noise": "voices and footsteps %d m, searching %d m%s" % [roundi(Jobs.NOISE_TRAVEL_M), roundi(Jobs.NOISE_SEARCH_M),
			(", forcing the locked door %d m" % roundi(Jobs.NOISE_BREAK_DOOR_M)) if building["locked"] else ""],
		"night_search": night,
	}


## Chance that meeting infected at this place and time ends badly (not slipped past,
## not fought off), from the same rules the infected system uses. Assumes the
## typical group size for the zone's density.
static func hurt_if_met(s: Dictionary, pos: Vector2, at_tick: int) -> float:
	var zone: Dictionary = WorldState.zones[Geo.zone_index_at(pos)]
	var density: float = float(zone["infected"]) / Infected.ZONE_AREA_KM2
	var met: float = 1.0 + 0.5 * density * Infected.GROUP_PER_DENSITY
	var night: bool = WorldState.phase_at(at_tick) == WorldState.PHASE_NIGHT
	var avoid: float = Infected.AVOID_BASE + Infected.AVOID_PER_SCAVENGING * Body.skill(s, "scavenging") - Infected.AVOID_PER_EXTRA_INFECTED * (met - 1.0)
	avoid += -Infected.AVOID_DAYLIGHT_BONUS if night else Infected.AVOID_DAYLIGHT_BONUS
	var weapon: String = s["weapon"]
	if weapon == "rifle" and int(s["ammo"]) <= 0:
		weapon = ""
	var defense: float = Body.skill(s, "combat") / 2.0 + float(Infected.WEAPON_BONUS.get(weapon, 0.0))
	var margin: float = defense - met * (1.3 if night else 1.0)
	var fight: float = clampf(Infected.FIGHT_BASE + Infected.FIGHT_PER_MARGIN * margin, 0.1, 0.95) / Body.injury_multiplier(s)
	return (1.0 - clampf(avoid, 0.05, 0.85)) * (1.0 - clampf(fight, 0.0, 1.0))


static func _tick_risk(pos: Vector2, at_tick: int, danger: float, noise_m: float, scavenging: float) -> float:
	var zone: Dictionary = WorldState.zones[Geo.zone_index_at(pos)]
	var density: float = float(zone["infected"]) / Infected.ZONE_AREA_KM2
	var minute: int = WorldState.minute_of_day_at(at_tick)
	var climate: Dictionary = WorldState.climate
	var temp: float = TimeSystem.temperature_at(float(minute) / 60.0, float(climate.get("today_min_c", 28.0)), float(climate.get("today_max_c", 36.0)))
	return Infected.encounter_chance(density, Infected.activity_at(minute, temp), danger, noise_m, scavenging)


# --- Buildings ---

static func danger_word(danger: float) -> String:
	if danger < 0.2:
		return "low"
	if danger < 0.5:
		return "medium"
	if danger < 0.8:
		return "high"
	return "very high"


static func last_visit_text(building: Dictionary) -> String:
	if not building.has("last_visit_tick"):
		return "never visited"
	var days: int = WorldState.day() - WorldState.day_at(int(building["last_visit_tick"]))
	return "visited today" if days == 0 else ("visited yesterday" if days == 1 else "last visited %d days ago" % days)


## 1,870 -> "1.9k" for tight spaces.
static func short(value: float) -> String:
	return "%.1fk" % (value / 1000.0) if absf(value) >= 1000.0 else str(roundi(value))


static func thousands(value: float) -> String:
	var n: int = roundi(value)
	var digits: String = str(absi(n))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
