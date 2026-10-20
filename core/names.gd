extends RefCounted
## Rolls a run's names from its seed: the town, every person in the survivor pool
## and every building, from the mixed pools in data/names.json. Uses its own random
## stream (Rng.stream), so names never change what happens in the simulation, and
## the same seed always gives the same names. The start screen calls generate()
## to preview names before a run; SimRun stores the result in WorldState.names.

const RngScript := preload("res://core/rng.gd")


## {"town": String, "people": {id: name}, "buildings": {id: name}}, all unique.
static func generate(run_seed: int) -> Dictionary:
	var pools: Dictionary = Data.table("names")
	var rng: RandomNumberGenerator = RngScript.stream(run_seed, "names")
	var town: String = _pick(rng, pools["towns"])
	var people: Dictionary = {}
	var given: Array = pools["given_names"].duplicate()
	for row: Dictionary in Data.table("survivors"):
		people[String(row["id"])] = String(given.pop_at(rng.randi_range(0, given.size() - 1)))
	var buildings: Dictionary = {}
	var used: Dictionary = {}
	var patterns: Dictionary = pools["buildings"]
	for row: Dictionary in Data.table("town_layout")["buildings"]:
		var options: Array = patterns.get(String(row["type"]), ["{word} building"])
		var name: String = ""
		# Retry until unique; fall back to numbering if a pool runs dry.
		for attempt: int in 50:
			name = _fill(rng, _pick(rng, options), town, pools)
			if not used.has(name):
				break
		var base_name: String = name
		var n: int = 2
		while used.has(name):
			name = "%s %d" % [base_name, n]
			n += 1
		used[name] = true
		buildings[String(row["id"])] = name
	return {"town": town, "people": people, "buildings": buildings}


## The name a person goes by in this run (their profession before a run exists).
static func person(id: String) -> String:
	var people: Dictionary = WorldState.names.get("people", {})
	if people.has(id):
		return String(people[id])
	return String(Data.entry("survivors", id).get("profession", id))


static func _fill(rng: RandomNumberGenerator, pattern: String, town: String, pools: Dictionary) -> String:
	return pattern.format({"town": town, "surname": _pick(rng, pools["surnames"]), "word": _pick(rng, pools["words"])})


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return String(options[rng.randi_range(0, options.size() - 1)])
