extends "res://core/sim_system.gd"
## Survivors: the body model. Each tick, from the activity Jobs set and the air
## temperature, it moves each survivor's water, energy, fatigue, sleep, core
## temperature, blood, health and stress. It also runs wounds (bleeding,
## tourniquets, the infection chain to sepsis), waterborne illness, the pathogen
## (incubation, prodrome, turning) and the bite/antibiotics decisions, and
## handles death and people leaving.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Decisions := preload("res://core/decisions.gd")
const Geo := preload("res://core/geo.gd")
const Difficulty := preload("res://core/difficulty.gd")
const Traits := preload("res://core/traits.gd")

const TICK_DAYS: float = 1.0 / 144.0
const TICK_HOURS: float = 1.0 / 6.0

# --- Energy and water ---
## Energy burn of a 70 kg adult at rest; scaled by body weight to the 0.75 power.
const KCAL_PER_DAY_AT_REST: float = 2000.0
const REFERENCE_WEIGHT_KG: float = 70.0
const WATER_L_PER_DAY_BASE: float = 3.0
## Water need rises 4% for every °C above 25 °C.
const WATER_HEAT_THRESHOLD_C: float = 25.0
const WATER_EXTRA_PER_C: float = 0.04
## Shade indoors is this much cooler than the air outside.
const INDOOR_COOLING_C: float = 3.0
## Per activity: energy and water multipliers, fatigue change per hour, heat load.
const ACTIVITY: Dictionary = {
	&"sleeping": {"kcal": 0.85, "water": 0.8, "fatigue_h": -12.0, "heat": 0.0},
	&"resting": {"kcal": 1.0, "water": 1.0, "fatigue_h": -3.0, "heat": 0.0},
	&"idle": {"kcal": 1.05, "water": 1.0, "fatigue_h": 1.0, "heat": 0.1},
	&"light_work": {"kcal": 1.3, "water": 1.2, "fatigue_h": 3.0, "heat": 0.3},
	&"guarding": {"kcal": 1.2, "water": 1.1, "fatigue_h": 3.0, "heat": 0.3},
	&"searching": {"kcal": 1.4, "water": 1.3, "fatigue_h": 4.0, "heat": 0.5},
	&"travelling": {"kcal": 1.6, "water": 1.5, "fatigue_h": 5.0, "heat": 0.8},
	&"heavy_work": {"kcal": 1.7, "water": 1.6, "fatigue_h": 5.0, "heat": 1.0},
}

# --- Health ---
const DEHYDRATED_DAMAGE_PER_DAY: float = 40.0
const COLLAPSE_DEHYDRATION_DAMAGE_PER_DAY: float = 150.0
const STARVING_DAMAGE_PER_DAY: float = 5.0
const LOW_BLOOD_DAMAGE_PER_DAY: float = 20.0
const INFECTION_DAMAGE_PER_DAY: Dictionary = {&"local": 2.0, &"fever": 6.0, &"sepsis": 35.0}
const HEALTH_REGEN_RESTING_PER_DAY: float = 5.0
const HEALTH_REGEN_WORKING_PER_DAY: float = 2.0
const BLOOD_REGEN_L_PER_DAY: float = 0.25

# --- Heat ---
## Above this air temperature, exertion heats the body faster than sweat cools it.
const HEAT_GAIN_ABOVE_C: float = 33.0
const HEAT_GAIN_PER_C_PER_TICK: float = 0.02
const COOLING_PER_TICK: float = 0.05
## LATER (Prototype 2-3): heatstroke above 40 °C.
const MAX_CORE_C: float = 40.0
const FEVER_CORE_C: float = 38.8

# --- Sleep ---
const SLEEP_NEED_H: float = 7.0
const MAX_SLEEP_DEBT_H: float = 48.0

# --- Stress (per day while the condition lasts) ---
const STRESS_PER_DAY: Dictionary = {
	"thirsty": 6.0, "dehydrated": 12.0, "hungry": 4.0, "weak": 8.0, "wounded": 4.0,
	"infection": 8.0, "ill": 6.0, "sleep_deprived": 6.0, "exhausted": 4.0,
}
const STRESS_RELIEF_SLEEPING_PER_DAY: float = 8.0
const STRESS_RELIEF_RESTING_PER_DAY: float = 5.0
## With nothing wrong, stress eases by this much a day.
const STRESS_RELIEF_CALM_PER_DAY: float = 5.0
const STRESS_ON_GROUP_DEATH: float = 15.0
const STRESS_ON_MERCY_KILLING: float = 25.0
const STRESS_ON_EXILE: float = 15.0
const STRESS_ON_QUARANTINE: float = 10.0
const LEAVE_CHANCE_PER_DAY: float = 0.25

# --- Wounds ---
## Daily chance an open wound becomes infected, before cleaning and dressing.
const WOUND_INFECTION_CHANCE_PER_DAY: Dictionary = {&"cut": 0.05, &"laceration": 0.20, &"arterial": 0.30, &"bite": 0.25}
const BANDAGED_INFECTION_MULT: float = 0.6
const STITCHED_INFECTION_MULT: float = 0.5
const CLEANED_INFECTION_MULT: float = 0.5
const LOCAL_TO_FEVER_H: Vector2i = Vector2i(48, 72)
const FEVER_TO_SEPSIS_H: Vector2i = Vector2i(36, 60)
## A medic on the treat job slows the infection chain by this factor.
const MEDIC_INFECTION_SLOWDOWN: float = 0.5
const WOUND_HEAL_DAYS: Dictionary = {&"cut": 5.0, &"laceration": 14.0, &"arterial": 21.0, &"bite": 10.0}
const STITCHED_HEAL_MULT: float = 0.7
## Bleeding slows by this fraction each hour as blood clots (cuts) or barely (lacerations).
const CLOT_PER_HOUR: Dictionary = {&"cut": 0.5, &"laceration": 0.08, &"arterial": 0.0, &"bite": 0.4}
const BANDAGED_BLEED_MULT: float = 0.2
const TOURNIQUET_SUCCESS_BASE: float = 0.6
const TOURNIQUET_SUCCESS_PER_MEDICINE: float = 0.04
const ANTIBIOTIC_SEPSIS_SUCCESS_BASE: float = 0.5
const ANTIBIOTIC_SEPSIS_SUCCESS_PER_MEDICINE: float = 0.05
## Painkillers given by a medic ease the stress of a fresh wound.
const PAINKILLER_STRESS_RELIEF: float = 8.0

# --- Waterborne illness ---
const UNTREATED_WATER_ILLNESS_CHANCE: float = 0.30
const ILLNESSES: Array[Dictionary] = [
	{"type": "dysentery", "weight": 0.8, "loss_l_day": 2.0, "days": Vector2i(4, 7), "damage_per_day": 3.0},
	{"type": "cholera", "weight": 0.2, "loss_l_day": 6.0, "days": Vector2i(3, 5), "damage_per_day": 10.0},
]
## Oral rehydration salts cut the effective fluid loss to this fraction for a day.
const SALTS_LOSS_MULT: float = 0.4

# --- Pathogen ---
## Incubation by bite location (hours); bites nearer the brain progress faster.
const INCUBATION_H: Dictionary = {"neck": Vector2i(18, 30), "torso": Vector2i(24, 48), "arm": Vector2i(36, 60), "leg": Vector2i(36, 60)}
const PRODROME_H: Vector2i = Vector2i(6, 12)
const HIDE_BITE_BASE: float = 0.15
const HIDE_BITE_PER_STRESS: float = 0.0025


func setup() -> void:
	listen(&"decision_made", _on_decision)
	listen(&"command_add_survivor", _on_add_survivor)
	var roster: Array = WorldState.flags.get("roster", Data.table("scenario")["default_roster"])
	for id: String in roster:
		var row: Dictionary = Data.entry("survivors", id)
		if row.is_empty():
			push_error("Survivors: no survivor '%s' in the pool" % id)
			continue
		WorldState.survivors.append(_at_base(Body.new_survivor(row)))


func tick() -> void:
	var new_day: bool = WorldState.is_new_day()
	var dawn: bool = WorldState.is_dawn()
	var medic: Dictionary = _medic_at_base()
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok":
			continue
		s["damage"] = {}
		_process_new_injuries(s)
		_report_bite_if_back(s)
		_treat(s, medic)
		_body(s)
		_wounds(s, medic)
		_illness(s)
		_pathogen(s)
		_stress(s)
		if new_day:
			_daily(s)
		if dawn:
			# Sleep is tallied each morning over the night just gone.
			s["slept_last_night_h"] = float(s["slept_h"])
			var need: float = SLEEP_NEED_H
			if WorldState.base.get("attention_level", &"low") != &"low":
				need += Traits.add(s, "sleep_need_add_when_noisy_h")
			s["sleep_debt_h"] = clampf(float(s["sleep_debt_h"]) + need - float(s["slept_h"]), 0.0, MAX_SLEEP_DEBT_H)
			s["slept_h"] = 0.0
		_check_death(s)


# --- Body ---

func _body(s: Dictionary) -> void:
	var activity: Dictionary = ACTIVITY.get(s["activity"], ACTIVITY[&"idle"])
	var air: float = float(WorldState.climate.get("temperature_c", 30.0))
	if not s["outdoors"]:
		air -= INDOOR_COOLING_C
	# Water and energy.
	var heat_extra: float = WATER_EXTRA_PER_C * maxf(0.0, air - WATER_HEAT_THRESHOLD_C) * Traits.mult(s, "water_heat_mult")
	var water_need: float = WATER_L_PER_DAY_BASE * (1.0 + heat_extra)
	s["water_deficit_l"] = float(s["water_deficit_l"]) + water_need * float(activity["water"]) * TICK_DAYS
	var size: float = pow(float(s["weight_kg"]) / REFERENCE_WEIGHT_KG, 0.75)
	s["kcal_debt"] = float(s["kcal_debt"]) + KCAL_PER_DAY_AT_REST * size * float(activity["kcal"]) * TICK_DAYS
	# Fatigue and sleep.
	s["fatigue"] = clampf(float(s["fatigue"]) + float(activity["fatigue_h"]) * TICK_HOURS, 0.0, 100.0)
	if s["activity"] == &"sleeping":
		s["slept_h"] = float(s["slept_h"]) + TICK_HOURS
	# Core temperature: exertion in heat versus sweating (which needs water).
	var core: float = float(s["core_temp_c"])
	core += float(activity["heat"]) * maxf(0.0, air - HEAT_GAIN_ABOVE_C) * HEAT_GAIN_PER_C_PER_TICK * Traits.mult(s, "heat_gain_mult")
	if core > Body.NORMAL_CORE_C:
		var cooling: float = COOLING_PER_TICK * (0.5 if float(s["water_deficit_l"]) >= Body.THIRSTY_L else 1.0)
		core = maxf(Body.NORMAL_CORE_C, core - cooling)
	core = minf(core, MAX_CORE_C)
	if Body.worst_infection(s) in [&"fever", &"sepsis"] or s["pathogen"].get("stage", &"") == &"prodrome":
		core = maxf(core, FEVER_CORE_C)
	s["core_temp_c"] = core
	# Health damage, worst first so the cause of death is the right one.
	var deficit: float = float(s["water_deficit_l"])
	if deficit >= Body.COLLAPSE_DEHYDRATION_L:
		_damage(s, "dehydration", COLLAPSE_DEHYDRATION_DAMAGE_PER_DAY * TICK_DAYS)
	elif deficit >= Body.DEHYDRATED_L:
		_damage(s, "dehydration", DEHYDRATED_DAMAGE_PER_DAY * TICK_DAYS)
	if float(s["kcal_debt"]) >= Body.STARVING_KCAL:
		_damage(s, "starvation", STARVING_DAMAGE_PER_DAY * TICK_DAYS)
	if Body.blood_fraction(s) < Body.BLOOD_COLLAPSE_FRACTION:
		_damage(s, "blood loss", LOW_BLOOD_DAMAGE_PER_DAY * TICK_DAYS)
	# Recovery when nothing is hurting them.
	if s["damage"].is_empty() and not Body.is_bleeding(s) and Body.worst_infection(s) == &"none" and s["illness"].is_empty():
		var regen: float = HEALTH_REGEN_RESTING_PER_DAY if s["activity"] in [&"sleeping", &"resting"] else HEALTH_REGEN_WORKING_PER_DAY
		s["health"] = minf(100.0, float(s["health"]) + regen * TICK_DAYS)
	if deficit < Body.THIRSTY_L and not Body.is_bleeding(s):
		s["blood_l"] = minf(float(s["blood_full_l"]), float(s["blood_l"]) + BLOOD_REGEN_L_PER_DAY * TICK_DAYS)


func _damage(s: Dictionary, cause: String, amount: float) -> void:
	s["health"] = float(s["health"]) - amount
	s["damage"][cause] = float(s["damage"].get(cause, 0.0)) + amount


# --- Wounds ---

## Wounds arrive from Infected and Base marked "new". Tourniquets and bites are
## settled here, within the same 10-minute tick the wound happened.
func _process_new_injuries(s: Dictionary) -> void:
	for injury: Dictionary in s["injuries"]:
		if not injury.get("new", false):
			continue
		injury["new"] = false
		if injury["type"] == &"arterial":
			var kit: Dictionary = WorldState.stores if s["location"] == &"base" else s["carried"]
			var chance: float = TOURNIQUET_SUCCESS_BASE + TOURNIQUET_SUCCESS_PER_MEDICINE * Body.skill(s, "medicine")
			if Stores.total(kit, "tourniquet") >= 1.0 and Rng.chance(chance):
				Stores.take(kit, "tourniquet", 1.0)
				injury["tourniquet"] = true
				injury["bleed_l_h"] = 0.0
				EventBus.emit_event(&"tourniquet_applied", {"survivor": s["id"],
					"text": "%s tied a tourniquet over an arterial bleed in time." % s["name"]})
			else:
				# Without a tourniquet in two or three minutes, an arterial bleed is fatal.
				s["blood_l"] = 0.0
				s["death_hint"] = "arterial bleed"
		elif injury["type"] == &"bite" and s["pathogen"].is_empty():
			var range_h: Vector2i = INCUBATION_H.get(String(injury["location"]), INCUBATION_H["arm"])
			s["pathogen"] = {"stage": &"incubation", "hours_left": float(Rng.randi_range(range_h.x, range_h.y)),
				"location": String(injury["location"]), "reported": false, "known": false, "hidden": false,
				"bitten_tick": WorldState.tick}


## A bite is reported (or hidden) once the survivor is back among the group.
func _report_bite_if_back(s: Dictionary) -> void:
	var pathogen: Dictionary = s["pathogen"]
	if pathogen.is_empty() or pathogen["reported"] or s["location"] != &"base":
		return
	pathogen["reported"] = true
	var hide_chance: float = HIDE_BITE_BASE + HIDE_BITE_PER_STRESS * float(s["stress"])
	if not pathogen.get("cannot_hide", false) and Rng.chance(hide_chance):
		pathogen["hidden"] = true
		for injury: Dictionary in s["injuries"]:
			if injury["type"] == &"bite":
				injury["disguised_as"] = &"cut"
		return
	pathogen["known"] = true
	for injury: Dictionary in s["injuries"]:
		injury.erase("disguised_as")
	EventBus.emit_event(&"bite_reported", {"survivor": s["id"],
		"text": "%s shows the group a bite on the %s." % [s["name"], pathogen["location"]]})
	_ask_about_bite(s, "%s has been bitten on the %s. There is no cure. What do you do?" % [s["name"], pathogen["location"]], true)


func _ask_about_bite(s: Dictionary, text: String, allow_watch: bool) -> void:
	var options: Array = [Decisions.option(&"quarantine", "Quarantine them",
		"They stop working and are locked away. If they turn, nobody else is hurt. Their stress rises.")]
	if allow_watch:
		options.append(Decisions.option(&"watch", "Keep working and watch for fever",
			"They keep working. A fever comes before they turn, and you'll be asked again then. If nobody acts in time, they can turn among the group."))
	options.append(Decisions.option(&"exile", "Send them away",
		"They leave with nothing and are gone for good. Everyone's stress rises.", true))
	options.append(Decisions.option(&"mercy", "End it before they turn",
		"They die now. It weighs heavily on everyone.", true))
	Decisions.create(&"bite", text, options, {"survivor": s["id"],
		"unknowns": ["Exactly when they will turn: usually 1 to 3 days after the bite, faster for bites near the head."]})


## Best medic on the treat job at base right now, or {}.
func _medic_at_base() -> Dictionary:
	var best: Dictionary = {}
	for s: Dictionary in WorldState.survivors:
		if s["status"] == &"ok" and s["location"] == &"base" and s["job_now"] == &"treat" and s["activity"] == &"light_work":
			if best.is_empty() or Body.skill(s, "medicine") > Body.skill(best, "medicine"):
				best = s
	return best


## First aid anyone can give at base (a dressing on a bleeding wound), plus what
## only a medic on the treat job does: clean, stitch, painkillers, rehydration salts.
func _treat(s: Dictionary, medic: Dictionary) -> void:
	if s["location"] != &"base":
		return
	for injury: Dictionary in s["injuries"]:
		if float(injury["bleed_l_h"]) > 0.01 and not injury["bandaged"] and Stores.total(WorldState.stores, "bandages") >= 1.0:
			Stores.take(WorldState.stores, "bandages", 1.0)
			injury["bandaged"] = true
			injury["bleed_l_h"] = float(injury["bleed_l_h"]) * BANDAGED_BLEED_MULT
		if medic.is_empty():
			continue
		if not injury["cleaned"]:
			injury["cleaned"] = true
		if injury["type"] in [&"laceration", &"arterial"] and not injury["stitched"]:
			injury["stitched"] = true
			injury["bleed_l_h"] = 0.0
			EventBus.emit_event(&"wound_stitched", {"survivor": s["id"],
				"text": "%s stitched %s's wound." % [medic["name"], s["name"]]})
		if not injury.get("painkiller", false) and Stores.total(WorldState.stores, "painkillers") >= 1.0:
			Stores.take(WorldState.stores, "painkillers", 1.0)
			injury["painkiller"] = true
			var eased: float = float(s["stress"])
			s["stress"] = maxf(0.0, float(s["stress"]) - PAINKILLER_STRESS_RELIEF)
			Traits.note_stress(s, "painkillers", float(s["stress"]) - eased)
	var illness: Dictionary = s["illness"]
	if not illness.is_empty() and int(illness.get("salts_until_tick", -1)) < WorldState.tick and Stores.total(WorldState.stores, "rehydration_salts") >= 1.0:
		# Anyone can mix a sachet of oral rehydration salts.
		Stores.take(WorldState.stores, "rehydration_salts", 1.0)
		illness["salts_until_tick"] = WorldState.tick + WorldState.TICKS_PER_DAY


func _wounds(s: Dictionary, medic: Dictionary) -> void:
	var bleed_total: float = 0.0
	var healed: Array = []
	for injury: Dictionary in s["injuries"]:
		var type: StringName = injury["type"]
		if injury["tourniquet"] or injury["stitched"]:
			injury["bleed_l_h"] = 0.0
		else:
			injury["bleed_l_h"] = float(injury["bleed_l_h"]) * pow(1.0 - float(CLOT_PER_HOUR.get(type, 0.0)), TICK_HOURS)
		bleed_total += float(injury["bleed_l_h"])
		injury["age_h"] = float(injury["age_h"]) + TICK_HOURS
		var infection: StringName = injury["infection"]
		if infection != &"none":
			var pace: float = MEDIC_INFECTION_SLOWDOWN if not medic.is_empty() and s["location"] == &"base" else 1.0
			injury["infection_h"] = float(injury["infection_h"]) + TICK_HOURS * pace
			_damage(s, "infection" if infection != &"sepsis" else "sepsis", float(INFECTION_DAMAGE_PER_DAY[infection]) * TICK_DAYS)
			if float(injury["infection_h"]) >= float(injury["next_stage_h"]) and infection != &"sepsis":
				_advance_infection(s, injury)
		var heal_days: float = float(WOUND_HEAL_DAYS.get(type, 7.0)) * (STITCHED_HEAL_MULT if injury["stitched"] else 1.0)
		if infection == &"none" and float(injury["age_h"]) >= heal_days * 24.0:
			healed.append(injury)
		elif s["location"] == &"base" and infection != &"none" and int(injury.get("asked_stage", -1)) < _stage_rank(infection):
			_ask_about_antibiotics(s, injury)
	s["blood_l"] = float(s["blood_l"]) - bleed_total * TICK_HOURS
	for injury: Dictionary in healed:
		s["injuries"].erase(injury)
		EventBus.emit_event(&"wound_healed", {"survivor": s["id"],
			"text": "%s's %s has healed." % [s["name"], Body.visible_wound_type(injury)]})


func _advance_infection(s: Dictionary, injury: Dictionary) -> void:
	injury["infection_h"] = 0.0
	if injury["infection"] == &"local":
		injury["infection"] = &"fever"
		injury["next_stage_h"] = float(Rng.randi_range(FEVER_TO_SEPSIS_H.x, FEVER_TO_SEPSIS_H.y))
		EventBus.emit_event(&"infection_worsened", {"survivor": s["id"], "stage": &"fever",
			"text": "%s's infected %s has brought on a fever." % [s["name"], Body.visible_wound_type(injury)]})
	else:
		injury["infection"] = &"sepsis"
		EventBus.emit_event(&"infection_worsened", {"survivor": s["id"], "stage": &"sepsis",
			"text": "%s has sepsis. Without antibiotics they will die within days." % s["name"]})


static func _stage_rank(stage: StringName) -> int:
	return [&"none", &"local", &"fever", &"sepsis"].find(stage)


## Known to be carrying the pathogen: wound care no longer changes the outcome,
## so the group is not asked about it.
static func _doomed(s: Dictionary) -> bool:
	return not s["pathogen"].is_empty() and s["pathogen"]["known"]


func _ask_about_antibiotics(s: Dictionary, injury: Dictionary) -> void:
	injury["asked_stage"] = _stage_rank(injury["infection"])
	if _doomed(s):
		return
	var strips: float = Stores.total(WorldState.stores, "antibiotics")
	var stage_text: Dictionary = {&"local": "is red and swelling", &"fever": "is infected and they have a fever",
		&"sepsis": "has turned septic"}
	var text: String = "%s's %s %s." % [s["name"], Body.visible_wound_type(injury), stage_text[injury["infection"]]]
	if strips < 1.0:
		EventBus.emit_event(&"infection_untreatable", {"survivor": s["id"], "text": text + " There are no antibiotics."})
		return
	# Only the newest question about a wound stays open.
	for old: Dictionary in WorldState.pending_decisions.duplicate():
		if old["kind"] == &"antibiotics" and int(old["injury"]) == int(injury["id"]):
			Decisions.resolve(int(old["id"]))
	Decisions.create(&"antibiotics", text + " Antibiotic strips left: %d. Use one now?" % int(strips),
		[Decisions.option(&"give", "Give antibiotics",
			"Uses one strip (%d left after). A wound infection or fever clears; sepsis may not." % (int(strips) - 1), true),
		Decisions.option(&"wait", "Wait and keep them",
			"The strip stays in stores. Untreated, the infection worsens: fever in 2-3 days, then sepsis, which kills within days.")],
		{"survivor": s["id"], "injury": injury["id"],
			"unknowns": ["Whether something worse will need the strip later."]})


# --- Illness ---

func _illness(s: Dictionary) -> void:
	var illness: Dictionary = s["illness"]
	if illness.is_empty():
		return
	var on_salts: bool = int(illness.get("salts_until_tick", -1)) >= WorldState.tick
	var loss: float = float(illness["loss_l_day"]) * (SALTS_LOSS_MULT if on_salts else 1.0)
	s["water_deficit_l"] = float(s["water_deficit_l"]) + loss * TICK_DAYS
	_damage(s, illness["type"], float(illness["damage_per_day"]) * TICK_DAYS)
	illness["hours_left"] = float(illness["hours_left"]) - TICK_HOURS
	if float(illness["hours_left"]) <= 0.0:
		s["illness"] = {}
		EventBus.emit_event(&"illness_over", {"survivor": s["id"], "text": "%s has recovered from %s." % [s["name"], illness["type"]]})


func _start_illness(s: Dictionary) -> void:
	var roll: float = Rng.randf()
	var chosen: Dictionary = ILLNESSES[-1]
	for kind: Dictionary in ILLNESSES:
		roll -= float(kind["weight"])
		if roll < 0.0:
			chosen = kind
			break
	var days: Vector2i = chosen["days"]
	s["illness"] = {"type": chosen["type"], "loss_l_day": chosen["loss_l_day"], "damage_per_day": chosen["damage_per_day"],
		"hours_left": float(Rng.randi_range(days.x, days.y)) * 24.0}
	EventBus.emit_event(&"illness_started", {"survivor": s["id"], "illness": chosen["type"],
		"text": "%s has %s from untreated water." % [s["name"], chosen["type"]]})


# --- Pathogen ---

func _pathogen(s: Dictionary) -> void:
	var pathogen: Dictionary = s["pathogen"]
	if pathogen.is_empty():
		return
	pathogen["hours_left"] = float(pathogen["hours_left"]) - TICK_HOURS
	if float(pathogen["hours_left"]) > 0.0:
		return
	if pathogen["stage"] == &"incubation":
		pathogen["stage"] = &"prodrome"
		pathogen["hours_left"] = float(Rng.randi_range(PRODROME_H.x, PRODROME_H.y))
		EventBus.emit_event(&"prodrome_started", {"survivor": s["id"],
			"text": "%s is feverish, sweating and flinching at light." % s["name"]})
		if s["quarantined"] or s["location"] != &"base":
			return
		if pathogen["hidden"]:
			pathogen["hidden"] = false
			pathogen["known"] = true
			for injury: Dictionary in s["injuries"]:
				injury.erase("disguised_as")
			EventBus.emit_event(&"hidden_bite_found", {"survivor": s["id"],
				"text": "%s admits the 'cut' was a bite." % s["name"]})
			_ask_about_bite(s, "%s hid a bite and is now feverish. They will turn within hours." % s["name"], false)
		else:
			_ask_about_bite(s, "%s's fever has started. They will turn within hours." % s["name"], false)
	else:
		_turn(s)


func _turn(s: Dictionary) -> void:
	s["status"] = &"turned"
	s["cause"] = "turned"
	var at_base: bool = s["location"] == &"base"
	var hours: float = float(WorldState.tick - int(s["pathogen"]["bitten_tick"])) / 6.0
	EventBus.emit_event(&"survivor_turned", {"survivor": s["id"], "name": s["name"], "at_base": at_base,
		"quarantined": s["quarantined"], "x_m": s.get("x_m", 0.0), "y_m": s.get("y_m", 0.0), "hours_since_bite": hours,
		"text": "%s has turned%s." % [s["name"], " inside the quarantine room" if s["quarantined"] else ""]})
	_group_stress(STRESS_ON_GROUP_DEATH, s)
	_drop_carried(s)


# --- Stress ---

func _stress(s: Dictionary) -> void:
	var delta: float = 0.0
	var causes: Array = []  # [reason, per-day amount], for the UI's breakdown only
	var deficit: float = float(s["water_deficit_l"])
	var debt: float = float(s["kcal_debt"])
	if deficit >= Body.DEHYDRATED_L:
		delta += float(STRESS_PER_DAY["dehydrated"])
		causes.append(["dehydrated", float(STRESS_PER_DAY["dehydrated"])])
	elif deficit >= Body.THIRSTY_L:
		delta += float(STRESS_PER_DAY["thirsty"])
		causes.append(["thirsty", float(STRESS_PER_DAY["thirsty"])])
	if debt >= Body.WEAK_KCAL:
		delta += float(STRESS_PER_DAY["weak"])
		causes.append(["weak from hunger", float(STRESS_PER_DAY["weak"])])
	elif debt >= Body.HUNGRY_KCAL:
		delta += float(STRESS_PER_DAY["hungry"])
		causes.append(["hungry", float(STRESS_PER_DAY["hungry"])])
	if not s["injuries"].is_empty():
		var wounded: float = Traits.mult(s, "stress_from_wounds_mult") * float(STRESS_PER_DAY["wounded"])
		delta += wounded
		causes.append(["wounded", wounded])
	if s.get("craving", false):
		delta += Traits.add(s, "stress_without_cigarettes_per_day")
		causes.append(["no cigarettes", Traits.add(s, "stress_without_cigarettes_per_day")])
	if Body.worst_infection(s) != &"none":
		delta += float(STRESS_PER_DAY["infection"])
		causes.append(["infected wound", float(STRESS_PER_DAY["infection"])])
	if not s["illness"].is_empty():
		delta += float(STRESS_PER_DAY["ill"])
		causes.append(["ill", float(STRESS_PER_DAY["ill"])])
	if float(s["sleep_debt_h"]) >= Body.SLEEP_DEBT_MISTAKES_H:
		delta += float(STRESS_PER_DAY["sleep_deprived"])
		causes.append(["short of sleep", float(STRESS_PER_DAY["sleep_deprived"])])
	if float(s["fatigue"]) > Body.EXHAUSTED_FATIGUE:
		delta += float(STRESS_PER_DAY["exhausted"])
		causes.append(["exhausted", float(STRESS_PER_DAY["exhausted"])])
	var raw: float = delta
	if delta == 0.0:
		delta -= STRESS_RELIEF_CALM_PER_DAY
		causes.append(["a calm day", -STRESS_RELIEF_CALM_PER_DAY])
	else:
		delta = Traits.stress_gain(s, delta)
		var scale: float = delta / raw
		for cause: Array in causes:
			cause[1] = float(cause[1]) * scale
	if s["activity"] == &"sleeping":
		delta -= STRESS_RELIEF_SLEEPING_PER_DAY
		causes.append(["sleep", -STRESS_RELIEF_SLEEPING_PER_DAY])
	elif s["activity"] == &"resting":
		delta -= STRESS_RELIEF_RESTING_PER_DAY
		causes.append(["rest", -STRESS_RELIEF_RESTING_PER_DAY])
	var before: float = float(s["stress"])
	s["stress"] = clampf(float(s["stress"]) + delta * TICK_DAYS, 0.0, 100.0)
	# Record what actually changed, shared between the causes (clamping included).
	var applied: float = float(s["stress"]) - before
	if delta != 0.0 and applied != 0.0:
		for cause: Array in causes:
			Traits.note_stress(s, String(cause[0]), float(cause[1]) / delta * applied)


func _group_stress(amount: float, except: Dictionary = {}) -> void:
	for other: Dictionary in WorldState.survivors:
		if other["status"] == &"ok" and other["id"] != except.get("id", ""):
			Traits.add_stress(other, amount, "deaths", "a loss in the group")


# --- Daily ---

## At midnight: cigarettes, infection and illness rolls, and whether anyone leaves.
func _daily(s: Dictionary) -> void:
	var packs: float = Traits.add(s, "cigarettes_per_day")
	if packs > 0.0:
		var supply: Dictionary = WorldState.stores if s["location"] == &"base" else s["carried"]
		s["craving"] = Stores.take(supply, "cigarettes", packs) < packs
	for injury: Dictionary in s["injuries"]:
		if injury["infection"] != &"none":
			continue
		var chance: float = float(WOUND_INFECTION_CHANCE_PER_DAY.get(injury["type"], 0.1)) * Difficulty.mult("disease")
		if injury["bandaged"]:
			chance *= BANDAGED_INFECTION_MULT
		if injury["stitched"]:
			chance *= STITCHED_INFECTION_MULT
		if injury["cleaned"]:
			chance *= CLEANED_INFECTION_MULT
		if Rng.chance(chance):
			injury["infection"] = &"local"
			injury["infection_h"] = 0.0
			injury["next_stage_h"] = float(Rng.randi_range(LOCAL_TO_FEVER_H.x, LOCAL_TO_FEVER_H.y))
			if _doomed(s):
				continue
			EventBus.emit_event(&"wound_infected", {"survivor": s["id"],
				"text": "%s's %s is red, hot and swelling." % [s["name"], Body.visible_wound_type(injury)]})
	if s["drank_untreated_today"]:
		s["drank_untreated_today"] = false
		if s["illness"].is_empty() and Rng.chance(UNTREATED_WATER_ILLNESS_CHANCE * Difficulty.mult("disease")):
			_start_illness(s)
	if float(s["stress"]) >= Body.MAY_LEAVE_STRESS and Rng.chance(LEAVE_CHANCE_PER_DAY):
		s["status"] = &"left"
		s["cause"] = "left the group"
		_drop_carried(s)
		EventBus.emit_event(&"survivor_left", {"survivor": s["id"], "name": s["name"],
			"text": "%s could not take any more and slipped away in the night." % s["name"]})


# --- Death ---

func _check_death(s: Dictionary) -> void:
	if s["status"] != &"ok":
		return
	var cause: String = ""
	if Body.blood_fraction(s) <= Body.BLOOD_LETHAL_FRACTION:
		cause = String(s.get("death_hint", "blood loss"))
	elif float(s["health"]) <= 0.0:
		cause = String(s.get("death_hint", ""))
		if cause == "":
			var worst: float = 0.0
			for key: String in s["damage"]:
				if float(s["damage"][key]) > worst:
					worst = float(s["damage"][key])
					cause = key
		if cause == "":
			cause = "their injuries"
	if cause != "":
		_kill(s, cause)


func _kill(s: Dictionary, cause: String) -> void:
	s["status"] = &"dead"
	s["cause"] = cause
	s["health"] = 0.0
	_drop_carried(s)
	EventBus.emit_event(&"survivor_died", {"survivor": s["id"], "name": s["name"], "cause": cause,
		"x_m": s.get("x_m", 0.0), "y_m": s.get("y_m", 0.0),
		"text": "%s died: %s." % [s["name"], cause]})
	_group_stress(STRESS_ON_GROUP_DEATH, s)


## Whatever a survivor carried away from base is lost with them.
func _drop_carried(s: Dictionary) -> void:
	s["carried"] = {}
	s["weapon"] = ""
	s["ammo"] = 0


func _at_base(s: Dictionary) -> Dictionary:
	var pos: Vector2 = Geo.base_center_m()
	s["x_m"] = pos.x
	s["y_m"] = pos.y
	return s


# --- Commands and decisions ---

func _on_add_survivor(payload: Dictionary) -> void:
	var row: Dictionary = Data.entry("survivors", String(payload["id"]))
	if row.is_empty() or not WorldState.survivor(String(payload["id"])).is_empty():
		push_error("Survivors: cannot add '%s'" % payload["id"])
		return
	var s: Dictionary = _at_base(Body.new_survivor(row))
	WorldState.survivors.append(s)
	if payload.get("bitten", false):
		s["injuries"].append(Body.new_injury(&"bite", "arm", 0.0))
		_process_new_injuries(s)
	EventBus.emit_event(&"survivor_joined", {"survivor": s["id"], "text": "%s joins the group." % s["name"]})


func _on_decision(payload: Dictionary) -> void:
	var decision: Dictionary = Decisions.find(int(payload["id"]))
	if decision.is_empty() or not decision["kind"] in [&"bite", &"antibiotics"]:
		return
	Decisions.resolve(int(payload["id"]))
	var s: Dictionary = WorldState.survivor(String(decision["survivor"]))
	if s.is_empty() or s["status"] != &"ok":
		return
	var choice: StringName = StringName(payload["option"])
	match choice:
		&"quarantine":
			s["quarantined"] = true
			Traits.add_stress(s, STRESS_ON_QUARANTINE, "", "quarantined")
			EventBus.emit_event(&"survivor_quarantined", {"survivor": s["id"], "text": "%s is locked in the quarantine room." % s["name"]})
		&"exile":
			s["status"] = &"exiled"
			s["cause"] = "sent away"
			_drop_carried(s)
			_group_stress(STRESS_ON_EXILE, s)
			EventBus.emit_event(&"survivor_exiled", {"survivor": s["id"], "name": s["name"], "text": "%s is sent away." % s["name"]})
		&"mercy":
			s["death_hint"] = "mercy killing"
			_kill(s, "mercy killing")
			_group_stress(STRESS_ON_MERCY_KILLING - STRESS_ON_GROUP_DEATH, s)
		&"give":
			_give_antibiotics(s, int(decision["injury"]))


func _give_antibiotics(s: Dictionary, injury_id: int) -> void:
	for injury: Dictionary in s["injuries"]:
		if int(injury.get("id", -1)) != injury_id or injury["infection"] == &"none":
			continue
		if Stores.take(WorldState.stores, "antibiotics", 1.0) < 1.0:
			EventBus.emit_event(&"infection_untreatable", {"survivor": s["id"], "text": "The antibiotics are gone."})
			return
		var cured: bool = true
		if injury["infection"] == &"sepsis":
			var medic: Dictionary = _medic_at_base()
			var skill: float = Body.skill(medic, "medicine") if not medic.is_empty() else 1.0
			var expert: float = 0.0
			for other: Dictionary in WorldState.group():
				if other["location"] == &"base":
					expert = maxf(expert, Traits.add(other, "sepsis_cure_add"))
			cured = Rng.chance(ANTIBIOTIC_SEPSIS_SUCCESS_BASE + ANTIBIOTIC_SEPSIS_SUCCESS_PER_MEDICINE * skill + expert)
		if cured:
			injury["infection"] = &"none"
			injury["infection_h"] = 0.0
			injury["cleaned"] = true
			injury.erase("asked_stage")
		EventBus.emit_event(&"antibiotics_given", {"survivor": s["id"], "cured": cured,
			"text": "%s gets antibiotics. %s" % [s["name"], "The infection clears." if cured else "It is too late; the sepsis holds."]})
		return

