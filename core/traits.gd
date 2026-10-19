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


## Adds a stress gain (or relief) to a survivor, clamped to 0..100.
static func add_stress(s: Dictionary, amount: float, kind: String = "") -> void:
	s["stress"] = clampf(float(s["stress"]) + stress_gain(s, amount, kind), 0.0, 100.0)
