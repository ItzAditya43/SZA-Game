extends RefCounted
## Saving and loading a run. A save is a JSON file in user://saves/: readable
## metadata (version, difficulty, seed, roster, day, survivors alive, real-world
## time) plus the exact world, random-number state and event log. encode() keeps
## dictionary key order (systems iterate in that order while rolling dice), int vs
## float, StringName and vectors, and writes floats at full precision, so a loaded
## run continues exactly as it would have. Loading rebuilds a fresh run with the same seed, difficulty and roster
## (so every system is set up) and then puts the saved world on top.

const SimRun := preload("res://core/sim_run.gd")

## Bump whenever the shape of WorldState changes, and add a migration below or
## let older saves be refused with a clear message.
## 2: stress causes, last night's sleep, planned trips, last visits, daily history
## and the timeline (UI/UX overhaul). Version 1 saves are migrated on load.
## 3: neutral setting. Survivor, item and building ids changed (nurse, lentils,
## grocery_01...) and names are generated per run (WorldState.names). Older saves
## are refused with the message in read().
const SAVE_VERSION: int = 3
const OLDEST_LOADABLE_VERSION: int = 3
const SAVE_DIR: String = "user://saves"
const AUTOSAVE_SLOTS: int = 3


static func save(slot: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path: String = "%s/%s.json" % [SAVE_DIR, slot]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(envelope(), "\t", false, true))
	file.close()
	EventBus.emit_event(&"game_saved", {"slot": slot, "text": "Saved (%s)." % slot.replace("_", " ")})
	return path


## Autosave at dawn, rotating through a few slots.
static func autosave() -> String:
	return save("autosave_%d" % (WorldState.day() % AUTOSAVE_SLOTS))


static func envelope() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"difficulty": WorldState.difficulty.get("id", "normal"),
		"seed": WorldState.run_seed,
		"roster": WorldState.flags.get("roster", []),
		"day": WorldState.day(),
		"clock": WorldState.clock_string(),
		"alive": WorldState.group().size(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_unix": Time.get_unix_time_from_system(),
		# int64 does not survive JSON's doubles, so the RNG state travels as text.
		"rng_state": str(Rng.get_state()),
		"world": encode(WorldState.to_dict()),
		"event_log": encode(EventBus.event_log),
	}


## Loads a save. Returns "" on success, or a message for the player.
static func load_game(path: String) -> String:
	var info: Dictionary = read(path)
	if info.has("error"):
		return info["error"]
	var world: Variant = decode(info["world"])
	var saved_log: Variant = decode(info["event_log"])
	if not world is Dictionary or not saved_log is Array:
		return "That save is damaged and can't be loaded."
	SimRun.start(int(info["seed"]), String(info["difficulty"]), Array(info["roster"]))
	_migrate(world, int(info["save_version"]))
	WorldState.from_dict(world)
	Rng.set_state(String(info["rng_state"]).to_int())
	EventBus.event_log.assign(saved_log)
	EventBus.emit_event(&"game_loaded", {"text": "Loaded the save from %s (%s)." % [info["saved_at"], info["clock"]]})
	return ""


## Brings an older save's world up to the current shape.
static func _migrate(world: Dictionary, version: int) -> void:
	if version < 2:
		# Version 1 had no history or timeline; start them from the moment of loading.
		var stats: Dictionary = world.get("stats", {})
		if not stats.has("history"):
			stats["history"] = []
		if not stats.has("timeline"):
			stats["timeline"] = []
		world["stats"] = stats


## The save's JSON, or {"error": message}. Refuses unknown versions clearly.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "There is no save at %s." % path}
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not parsed is Dictionary or not parsed.has("save_version"):
		return {"error": "That file isn't a Survival Sim save."}
	var version: int = int(parsed["save_version"])
	if version < OLDEST_LOADABLE_VERSION or version > SAVE_VERSION:
		return {"error": "That save is from a different version of the game (save version %d, this game reads %d) and can't be loaded." % [version, SAVE_VERSION]}
	return parsed


## Every save, newest first: {"path", "slot", "day", "clock", "difficulty", "alive", "saved_at", "ok"}.
static func list() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return out
	for file_name: String in DirAccess.get_files_at(SAVE_DIR):
		if file_name.get_extension() != "json":
			continue
		var path: String = SAVE_DIR.path_join(file_name)
		var info: Dictionary = read(path)
		out.append({"path": path, "slot": file_name.get_basename(), "ok": not info.has("error"),
			"error": info.get("error", ""), "day": int(info.get("day", 0)), "clock": info.get("clock", "?"),
			"difficulty": info.get("difficulty", "?"), "alive": int(info.get("alive", 0)),
			"saved_at": info.get("saved_at", "?"), "saved_unix": float(info.get("saved_unix", 0.0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["saved_unix"]) > float(b["saved_unix"]))
	return out


## Path of the most recent readable save, or "".
static func latest() -> String:
	for entry: Dictionary in list():
		if entry["ok"]:
			return entry["path"]
	return ""


## A fingerprint of the whole simulation state, to prove a reload continues identically.
static func state_hash() -> String:
	return (JSON.stringify(encode(WorldState.to_dict()), "", false, true) + str(Rng.get_state())).sha256_text()


## A JSON-safe copy of a value that decode() turns back into exactly the same value:
## dictionaries become {"d": [[key, value], ...]} in their own key order; ints,
## floats (as their exact bit pattern), StringNames and vectors are tagged.
static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var pairs: Array = []
			for key: Variant in value:
				pairs.append([encode(key), encode(value[key])])
			return {"d": pairs}
		TYPE_ARRAY:
			return (value as Array).map(func(item: Variant) -> Variant: return encode(item))
		TYPE_INT:
			return {"i": str(value)}
		TYPE_FLOAT:
			# Neither Godot's JSON writer nor its text-to-number parser round-trips
			# every double exactly, so floats travel as their 64-bit pattern.
			var bytes: PackedByteArray = PackedByteArray()
			bytes.resize(8)
			bytes.encode_double(0, value)
			return {"f": str(bytes.decode_s64(0))}
		TYPE_STRING_NAME:
			return {"n": String(value)}
		TYPE_VECTOR2:
			return {"v2": [value.x, value.y]}
		TYPE_VECTOR2I:
			return {"v2i": [value.x, value.y]}
		TYPE_STRING, TYPE_BOOL, TYPE_NIL:
			return value
	push_error("SaveGame: can't save a value of type %s" % type_string(typeof(value)))
	return null


static func decode(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).map(func(item: Variant) -> Variant: return decode(item))
	if not value is Dictionary:
		return value
	var tagged: Dictionary = value
	if tagged.has("d"):
		var out: Dictionary = {}
		for pair: Array in tagged["d"]:
			out[decode(pair[0])] = decode(pair[1])
		return out
	if tagged.has("i"):
		return String(tagged["i"]).to_int()
	if tagged.has("n"):
		return StringName(tagged["n"])
	if tagged.has("f"):
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(8)
		bytes.encode_s64(0, String(tagged["f"]).to_int())
		return bytes.decode_double(0)
	if tagged.has("v2"):
		return Vector2(float(tagged["v2"][0]), float(tagged["v2"][1]))
	if tagged.has("v2i"):
		return Vector2i(int(tagged["v2i"][0]), int(tagged["v2i"][1]))
	return tagged
