extends RefCounted
## A survivor's body as plain data, plus derived views of it: conditions, work
## speed, effective skill. The thresholds live here so every system and the UI
## agree on what "dehydrated" or "exhausted" means.

## Water deficit in litres.
const THIRSTY_L: float = 3.0
const DEHYDRATED_L: float = 6.0
const COLLAPSE_DEHYDRATION_L: float = 9.0
## Cumulative energy deficit in kcal (eating pays it back).
const HUNGRY_KCAL: float = 4000.0
const WEAK_KCAL: float = 12000.0
const STARVING_KCAL: float = 25000.0
## Fatigue 0..100 and sleep debt in hours.
const EXHAUSTED_FATIGUE: float = 80.0
const SLEEP_DEBT_MISTAKES_H: float = 6.0
## Core body temperature.
const NORMAL_CORE_C: float = 37.0
const HEAT_EXHAUSTION_C: float = 38.5
## Blood volume as a fraction of normal (about 70 ml per kg of body weight).
const BLOOD_ML_PER_KG: float = 70.0
const BLOOD_COLLAPSE_FRACTION: float = 0.7
const BLOOD_LETHAL_FRACTION: float = 0.6
## Stress 0..100. Morale shown to the player is 100 - stress.
const REFUSES_JOBS_STRESS: float = 80.0
const MAY_LEAVE_STRESS: float = 95.0
const INCAPACITATED_HEALTH: float = 15.0

const Traits := preload("res://core/traits.gd")

## Work speed multiplier per active wound type, applied once per wound.
const WOUND_WORK_SPEED: Dictionary = {&"cut": 0.95, &"laceration": 0.8, &"arterial": 0.5, &"bite": 0.9}


## A new survivor record from a data/survivors.json row.
static func new_survivor(row: Dictionary) -> Dictionary:
	var weight: float = float(row["weight_kg"])
	var skills: Dictionary = row["skills"]
	var jobs: Dictionary = row.get("jobs", {})
	return {
		"id": String(row["id"]),
		"name": String(row["name"]),
		"profession": String(row["profession"]),
		"background": String(row.get("background", "")),
		"traits": Array(row.get("traits", [])),
		"age": int(row["age"]),
		"weight_kg": weight,
		"skills": {
			"scavenging": int(skills["scavenging"]),
			"medicine": int(skills["medicine"]),
			"combat": int(skills["combat"]),
		},
		"status": &"ok",  # ok | dead | turned | exiled | left
		"cause": "",
		"jobs": {"day": StringName(jobs.get("day", "rest")), "night": StringName(jobs.get("night", "rest"))},
		"targets": {"day": String(row.get("targets", {}).get("day", "")), "night": String(row.get("targets", {}).get("night", ""))},
		"job_now": &"rest",
		"activity": &"idle",
		"outdoors": false,
		"asleep": false,
		"location": &"base",  # base | away
		"x_m": 0.0,
		"y_m": 0.0,
		"trip": {},
		"carried": {},
		"weapon": "",
		"ammo": 0,
		"exposure": {},
		"water_deficit_l": 0.0,
		"drunk_today_l": 0.0,
		"drank_untreated_today": false,
		"kcal_debt": 0.0,
		"kcal_eaten_today": 0.0,
		"meals_missed": 0,
		"fatigue": 10.0,
		"sleep_debt_h": 0.0,
		"slept_h": 0.0,
		"health": 100.0,
		"blood_l": weight * BLOOD_ML_PER_KG / 1000.0,
		"blood_full_l": weight * BLOOD_ML_PER_KG / 1000.0,
		"core_temp_c": NORMAL_CORE_C,
		"stress": float(row.get("stress", 40)),
		"injuries": [],
		"illness": {},
		"pathogen": {},
		"quarantined": false,
		"damage": {},
	}


## A fresh wound. Whoever inflicts it (Infected, Base) adds it with "new": true;
## Survivors settles tourniquets and bites for new wounds on the same tick.
static func new_injury(type: StringName, location: String, bleed_l_h: float) -> Dictionary:
	return {"id": WorldState.new_id(), "type": type, "location": location, "bleed_l_h": bleed_l_h,
		"infection": &"none", "infection_h": 0.0, "next_stage_h": 0.0, "bandaged": false, "stitched": false,
		"cleaned": false, "tourniquet": false, "age_h": 0.0, "new": true}


static func blood_fraction(s: Dictionary) -> float:
	return float(s["blood_l"]) / float(s["blood_full_l"])


static func morale(s: Dictionary) -> float:
	return 100.0 - float(s["stress"])


static func worst_infection(s: Dictionary) -> StringName:
	var order: Array[StringName] = [&"none", &"local", &"fever", &"sepsis"]
	var worst: int = 0
	for injury: Dictionary in s["injuries"]:
		worst = maxi(worst, order.find(injury["infection"]))
	return order[worst]


static func is_bleeding(s: Dictionary) -> bool:
	for injury: Dictionary in s["injuries"]:
		if float(injury["bleed_l_h"]) > 0.01:
			return true
	return false


## Too hurt, sick or spent to do any job.
static func is_incapacitated(s: Dictionary) -> bool:
	return (float(s["health"]) < INCAPACITATED_HEALTH
		or blood_fraction(s) < BLOOD_COLLAPSE_FRACTION
		or float(s["water_deficit_l"]) >= COLLAPSE_DEHYDRATION_L
		or float(s["core_temp_c"]) >= HEAT_EXHAUSTION_C and not worst_infection(s) in [&"fever", &"sepsis"]
		or worst_infection(s) == &"sepsis"
		or s["pathogen"].get("stage", &"") == &"prodrome")


static func work_speed(s: Dictionary) -> float:
	var speed: float = 1.0
	var deficit: float = float(s["water_deficit_l"])
	if deficit >= DEHYDRATED_L:
		speed *= 0.4
	elif deficit >= THIRSTY_L:
		speed *= 0.8
	var debt: float = float(s["kcal_debt"])
	if debt >= WEAK_KCAL:
		speed *= 0.7
	elif debt >= HUNGRY_KCAL:
		speed *= 0.9
	if float(s["fatigue"]) > EXHAUSTED_FATIGUE:
		speed *= 0.8
	if float(s["core_temp_c"]) >= HEAT_EXHAUSTION_C:
		speed *= 0.3
	if blood_fraction(s) < 0.8:
		speed *= 0.6
	if not s["illness"].is_empty():
		speed *= 0.5
	match worst_infection(s):
		&"fever":
			speed *= 0.5
		&"sepsis":
			speed *= 0.1
	for injury: Dictionary in s["injuries"]:
		speed *= float(WOUND_WORK_SPEED.get(injury["type"], 1.0))
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	speed *= Traits.mult(s, "night_work_speed_mult" if night else "day_work_speed_mult")
	return speed


## Skill after fatigue and sleep-debt penalties, never below 1.
static func skill(s: Dictionary, skill_name: String) -> float:
	var value: float = float(s["skills"][skill_name]) + Traits.add(s, skill_name + "_add")
	if float(s["fatigue"]) > EXHAUSTED_FATIGUE:
		value -= 2.0
	if float(s["sleep_debt_h"]) >= SLEEP_DEBT_MISTAKES_H:
		value -= 1.0
	return maxf(value, 1.0)


## How much likelier this survivor is to get hurt than when rested.
static func injury_multiplier(s: Dictionary) -> float:
	var mult: float = 1.0
	if float(s["fatigue"]) > EXHAUSTED_FATIGUE:
		mult *= 2.0
	if float(s["sleep_debt_h"]) >= SLEEP_DEBT_MISTAKES_H:
		mult *= 1.5
	return mult


## Short labels for the UI. Hidden bites show as what the survivor claims they are.
static func conditions(s: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var deficit: float = float(s["water_deficit_l"])
	if deficit >= COLLAPSE_DEHYDRATION_L:
		out.append("Collapsing from dehydration")
	elif deficit >= DEHYDRATED_L:
		out.append("Dehydrated, confused")
	elif deficit >= THIRSTY_L:
		out.append("Thirsty")
	var debt: float = float(s["kcal_debt"])
	if debt >= STARVING_KCAL:
		out.append("Starving")
	elif debt >= WEAK_KCAL:
		out.append("Weak from hunger")
	elif debt >= HUNGRY_KCAL:
		out.append("Hungry")
	if float(s["fatigue"]) > EXHAUSTED_FATIGUE:
		out.append("Exhausted")
	if float(s["sleep_debt_h"]) >= SLEEP_DEBT_MISTAKES_H:
		out.append("Sleep-deprived")
	if float(s["core_temp_c"]) >= HEAT_EXHAUSTION_C and worst_infection(s) == &"none":
		out.append("Heat exhaustion")
	if is_bleeding(s):
		out.append("Bleeding")
	if blood_fraction(s) < BLOOD_COLLAPSE_FRACTION:
		out.append("Collapsed from blood loss")
	elif blood_fraction(s) < 0.8:
		out.append("Weak from blood loss")
	match worst_infection(s):
		&"local":
			out.append("Wound infected")
		&"fever":
			out.append("Infected wound, fever")
		&"sepsis":
			out.append("Sepsis")
	if not s["illness"].is_empty():
		out.append("Ill: %s" % s["illness"]["type"])
	var pathogen: Dictionary = s["pathogen"]
	if not pathogen.is_empty():
		if pathogen["stage"] == &"prodrome":
			out.append("Fever, sweating, flinches at light")
		elif pathogen["known"]:
			out.append("Bitten")
	if s["quarantined"]:
		out.append("Quarantined")
	return out


## What the player sees for a wound: a hidden bite passes for a cut.
static func visible_wound_type(injury: Dictionary) -> StringName:
	return StringName(injury.get("disguised_as", injury["type"]))
