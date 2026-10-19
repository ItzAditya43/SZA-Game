extends RefCounted
## Survivor traits from data/traits.json. A trait is a set of named effects; keys
## ending in _mult multiply (several traits stack by product), everything else
## adds up. Systems ask for the effect they care about:
##   Traits.mult(s, "carry_kg_mult"), Traits.add(s, "base_defense_add").

const Difficulty := preload("res://core/difficulty.gd")


static func mult(s: Dictionary, key: String) -> float:
	var value: float = 1.0
	for id: String in s.get("traits", []):
		value *= float(Data.entry("traits", id).get("effects", {}).get(key, 1.0))
	return value


static func add(s: Dictionary, key: String) -> float:
	var value: float = 0.0
	for id: String in s.get("traits", []):
		value += float(Data.entry("traits", id).get("effects", {}).get(key, 0.0))
	return value


static func has(s: Dictionary, key: String) -> bool:
	return add(s, key) != 0.0


## A stress gain for this survivor, after difficulty and personality. `kind` picks
## a trait multiplier: "deaths", "wounds" or "fights". Relief is never scaled.
static func stress_gain(s: Dictionary, amount: float, kind: String = "") -> float:
	if amount <= 0.0:
		return amount
	var scaled: float = amount * Difficulty.mult("stress") * mult(s, "stress_gain_mult")
	if kind != "":
		scaled *= mult(s, "stress_from_%s_mult" % kind)
	return scaled


## Adds a stress gain (or relief) to a survivor, clamped to 0..100, and notes why.
static func add_stress(s: Dictionary, amount: float, kind: String = "", reason: String = "") -> void:
	var before: float = float(s["stress"])
	s["stress"] = clampf(before + stress_gain(s, amount, kind), 0.0, 100.0)
	note_stress(s, reason if reason != "" else kind, float(s["stress"]) - before)


## How many days of stress causes each survivor keeps, for the "why" breakdown.
const STRESS_CAUSE_DAYS: int = 3


## Records a change in stress and its cause for the UI's breakdown. Bookkeeping
## only: it never changes the stress itself.
static func note_stress(s: Dictionary, reason: String, change: float) -> void:
	if absf(change) < 0.000001:
		return
	var day: int = WorldState.day()
	if not s.has("stress_causes"):
		s["stress_causes"] = {}
	var causes: Dictionary = s["stress_causes"]
	if not causes.has(day):
		causes[day] = {}
		for old: int in causes.keys():
			if old <= day - STRESS_CAUSE_DAYS:
				causes.erase(old)
	var today: Dictionary = causes[day]
	var label: String = reason if reason != "" else "other"
	today[label] = float(today.get(label, 0.0)) + change
