extends "res://core/sim_system.gd"
## Jobs. Each survivor has one job for the day shift (06:00-18:00) and one for the
## night shift (18:00-06:00). Every tick this system turns the job and the hour
## into an activity (sleeping, working, travelling...) that Survivors uses for the
## body and other systems use for output (Base: fortify, Resources: cook...).
## Scavenging is a trip: out along the streets, a search, and back with what fits
## in a pack. Player orders arrive as `command_set_job` on the bus.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Traits := preload("res://core/traits.gd")

const JOBS: Array[StringName] = [&"rest", &"scavenge", &"guard", &"fortify", &"quick_fortify", &"collect_water", &"cook", &"treat"]
## Activity while doing each job at base during working hours.
const JOB_ACTIVITY: Dictionary = {
	&"guard": &"guarding",
	&"fortify": &"heavy_work",
	&"quick_fortify": &"heavy_work",
	&"collect_water": &"heavy_work",
	&"cook": &"light_work",
	&"treat": &"light_work",
}
## Jobs done out in the sun (heat load) rather than indoors.
const OUTDOOR_JOBS: Array[StringName] = [&"fortify", &"quick_fortify", &"collect_water", &"guard"]
## Working hours: start an hour into the shift and work 9 hours (07:00-16:00 by day,
## 19:00-04:00 by night). Guards watch the whole shift.
const WORK_START_OFFSET_MIN: int = 60
const WORK_MINUTES: int = 9 * 60
## Resting on the night shift: free time until 21:00, then sleep until 06:00.
const NIGHT_SLEEP_START_MINUTE: int = 21 * 60
## Resting on the day shift: nap when this tired or short of sleep, wake when rested.
const NAP_FATIGUE: float = 35.0
const NAP_SLEEP_DEBT_H: float = 2.0
const WAKE_FATIGUE: float = 5.0

# --- Trips ---
## Moving carefully through streets with infected about, and slower when loaded.
const SPEED_OUT_M_PER_H: float = 1800.0
const SPEED_BACK_M_PER_H: float = 1400.0
## Hurt or exhausted people still move, just slower.
const MIN_SPEED_MULT: float = 0.4
const SEARCH_HOURS: float = 2.0
## Searching by torchlight takes longer and finds less.
const NIGHT_SEARCH_TIME_MULT: float = 1.5
const NIGHT_SEARCH_SHARE_MULT: float = 0.7
## Share of what is there that a search turns up: base plus per point of scavenging skill.
const SEARCH_SHARE_BASE: float = 0.35
const SEARCH_SHARE_PER_SKILL: float = 0.07
const SEARCH_SHARE_MAX: float = 0.9
const CARRY_KG: float = 25.0
## Crumbs are not worth bagging.
const MIN_PICKUP_KG: float = 0.1
## Noise radius in metres: walking and whispering, quiet searching, forcing a door.
const NOISE_TRAVEL_M: float = 15.0
const NOISE_SEARCH_M: float = 10.0
const NOISE_BREAK_DOOR_M: float = 50.0
## What goes in the pack first, and at most how many kg of each category per trip.
const LOOT_PRIORITY: Array[String] = [
	"antibiotics", "tourniquet", "ors", "bandages", "painkillers", "cigarettes", "ammo", "rifle", "machete",
	"water_bottled", "packaged_food", "rice", "dal", "atta", "fresh_produce", "fuel", "cooking_gas",
	"materials", "water_drum", "generator",
]
const CATEGORY_KG_CAP: Dictionary = {
	"medicine": 3.0, "comfort": 1.0, "weapon": 8.0, "water": 8.0, "food": 14.0, "fuel": 8.0, "materials": 10.0, "gear": 25.0,
}
## Gear worth carrying home first when the group has none yet.
const WANTED_GEAR: Dictionary = {"generator": 1.0, "water_drum": 2.0}
## Taken along on every trip if the stores have them.
const TRIP_KIT: Dictionary = {"tourniquet": 1.0, "bandages": 1.0}
const TRIP_WATER_L: float = 1.5
const TRIP_AMMO: int = 10

# --- Water ---
## Filling drums from the tap while the mains still run.
const TAP_FILL_L_PER_H: float = 120.0
## Ferrying water by hand: two 10-litre jerry cans a round trip, plus time to fill.
const CANS_L: float = 20.0
const FILL_HOURS: float = 1.0 / 6.0
## Leave this much in a tank for whoever else depends on it? No: take what you can.
const MIN_TANK_L: float = 20.0
## Moving in: the group clears its new building room by room before settling.
const CLEAR_BUILDING_HOURS: float = 1.0


func setup() -> void:
	listen(&"command_set_job", _on_set_job)
	listen(&"encounter", _on_encounter)
	listen(&"base_moved", _on_base_moved)
	for s: Dictionary in WorldState.survivors:
		_place_at_base(s)
		_schedule(s)


func tick() -> void:
	for s: Dictionary in WorldState.survivors:
		s["exposure"] = {}
		if s["status"] != &"ok":
			s["activity"] = &"none"
			continue
		if s["location"] == &"away":
			_continue_trip(s)
		else:
			_place_at_base(s)
			_schedule(s)


## Sets job_now, activity, outdoors and asleep for a survivor at base, and starts
## a trip when a scavenging shift begins.
func _schedule(s: Dictionary) -> void:
	var shift: StringName = current_shift()
	var job: StringName = s["jobs"][shift]
	if s["quarantined"] or Body.is_incapacitated(s):
		job = &"rest"
	elif float(s["stress"]) >= Body.REFUSES_JOBS_STRESS and job != &"rest":
		if int(s.get("refused_shift", -1)) != shift_index():
			s["refused_shift"] = shift_index()
			EventBus.emit_event(&"job_refused", {"survivor": s["id"],
				"text": "%s is too shaken to %s and stays in." % [s["name"], String(s["jobs"][shift]).replace("_", " ")]})
		job = &"rest"
	s["job_now"] = job
	s["outdoors"] = false
	if job == &"rest":
		_rest(s, shift)
		return
	s["asleep"] = false
	if job == &"guard":
		s["activity"] = &"guarding"
		s["outdoors"] = true
	elif job == &"scavenge":
		s["activity"] = &"idle"
		if in_work_hours() and int(s.get("trip_shift", -1)) != shift_index():
			_start_scavenge(s, shift)
	elif job == &"collect_water" and in_work_hours():
		_collect_water_at_base(s)
	elif in_work_hours() and JOB_ACTIVITY.has(job):
		s["activity"] = JOB_ACTIVITY[job]
		s["outdoors"] = OUTDOOR_JOBS.has(job)
	else:
		s["activity"] = &"idle"


func _rest(s: Dictionary, shift: StringName) -> void:
	var minute: int = WorldState.minute_of_day()
	if shift == &"night":
		s["asleep"] = minute >= NIGHT_SLEEP_START_MINUTE or minute < WorldState.DAYTIME_START_MINUTE
	elif s["asleep"]:
		s["asleep"] = float(s["fatigue"]) > WAKE_FATIGUE
	else:
		s["asleep"] = float(s["fatigue"]) >= NAP_FATIGUE or float(s["sleep_debt_h"]) >= NAP_SLEEP_DEBT_H
	s["activity"] = &"sleeping" if s["asleep"] else &"resting"


# --- Water ---

## While the taps run, fill containers at base. Once they fail, go out and ferry
## water from the nearest tank or the canal for the rest of the working hours.
func _collect_water_at_base(s: Dictionary) -> void:
	s["activity"] = &"heavy_work"
	s["outdoors"] = false
	var room: float = Stores.water_capacity_l(WorldState.stores) - Stores.stored_water_l(WorldState.stores)
	if room <= 1.0:
		_warn_once(s, "water_full", "%s has filled every container. Find water drums to store more." % s["name"])
		s["activity"] = &"idle"
		return
	if WorldState.infrastructure.get("mains_on", false):
		Stores.add(WorldState.stores, "water_boiled", minf(room, TAP_FILL_L_PER_H * Body.work_speed(s) / 6.0))
		return
	if int(s.get("trip_shift", -1)) == shift_index():
		s["activity"] = &"idle"
		return
	s["trip_shift"] = shift_index()
	var source: Dictionary = _nearest_water()
	if source.is_empty():
		_warn_once(s, "no_water_source", "%s finds no water to collect." % s["name"])
		return
	_begin_trip(s, &"collect_water", source)


## The nearest building with water in its tank, or the nearest bank of the canal.
func _nearest_water() -> Dictionary:
	var home: Vector2 = Geo.base_center_m()
	var best: Dictionary = {}
	var best_distance: float = INF
	for building: Dictionary in WorldState.buildings:
		if building["id"] == WorldState.base.get("building", "") or float(building["tank_l"]) < MIN_TANK_L:
			continue
		var d: float = Geo.street_distance_m(home, Geo.building_center_m(building))
		if d < best_distance:
			best_distance = d
			best = building
	var canal: Vector2 = _nearest_canal(home)
	if canal != Vector2.INF and Geo.street_distance_m(home, canal) < best_distance:
		var tile: float = Geo.tile_m()
		return {"id": "canal", "name": "the canal", "x": floori(canal.x / tile), "y": floori(canal.y / tile), "w": 1, "h": 1,
			"tank_l": INF}
	return best


func _nearest_canal(from: Vector2) -> Vector2:
	var rows: Array = WorldState.town.get("rows", [])
	var tile: float = Geo.tile_m()
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] != "~":
				continue
			var pos: Vector2 = Vector2((x + 0.5) * tile, (y + 0.5) * tile)
			var d: float = Geo.street_distance_m(from, pos)
			if d < best_distance:
				best_distance = d
				best = pos
	return best


## Ferrying water: each tick at the source delivers that tick's share of round trips.
func _ferry_water(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	var distance: float = float(trip["distance_m"])
	var round_trip_h: float = 2.0 * distance / SPEED_OUT_M_PER_H + FILL_HOURS
	var litres: float = CANS_L / round_trip_h * Body.work_speed(s) / 6.0
	var room: float = Stores.water_capacity_l(WorldState.stores) - Stores.stored_water_l(WorldState.stores)
	var source: Dictionary = WorldState.building(String(trip["building"]))
	if not source.is_empty():
		litres = minf(litres, float(source["tank_l"]))
	litres = minf(litres, room)
	if litres > 0.0:
		Stores.add(WorldState.stores, "water_untreated", litres)
		trip["litres"] = float(trip.get("litres", 0.0)) + litres
		if not source.is_empty():
			source["tank_l"] = float(source["tank_l"]) - litres
	var dry: bool = not source.is_empty() and float(source["tank_l"]) < 1.0
	if not in_work_hours() or room <= 1.0 or dry:
		_head_back(s)


func _warn_once(s: Dictionary, key: String, text: String) -> void:
	if int(s.get("warned_" + key, -1)) == shift_index():
		return
	s["warned_" + key] = shift_index()
	EventBus.emit_event(&"job_blocked", {"survivor": s["id"], "text": text})


# --- Trips ---

func _start_scavenge(s: Dictionary, shift: StringName) -> void:
	s["trip_shift"] = shift_index()
	var target: Dictionary = WorldState.building(String(s["targets"][shift]))
	if target.is_empty() or target["id"] == WorldState.base.get("building", ""):
		EventBus.emit_event(&"job_needs_target", {"survivor": s["id"],
			"text": "%s has no building to scavenge. Pick one on the map." % s["name"]})
		return
	_pack_for_trip(s)
	_begin_trip(s, &"scavenge", target)
	s["trip"]["packed"] = Stores.snapshot(s["carried"])
	EventBus.emit_event(&"scavenge_started", {"survivor": s["id"], "building": target["id"],
		"text": "%s sets out for %s (%s, %.1f km)." % [s["name"], target["name"],
			Data.entry("buildings", String(target["type"]))["name"].to_lower(), float(s["trip"]["distance_m"]) / 1000.0]})


func _begin_trip(s: Dictionary, kind: StringName, target: Dictionary) -> void:
	var origin: Vector2 = Geo.base_center_m()
	var dest: Vector2 = Geo.building_center_m(target)
	s["location"] = &"away"
	s["trip"] = {"kind": kind, "building": target["id"], "place": target["name"], "leg": &"out", "origin": origin,
		"dest": dest, "distance_m": Geo.street_distance_m(origin, dest), "progress_m": 0.0, "work_ticks_left": 0,
		"started_tick": WorldState.tick}
	s["job_now"] = kind
	_continue_trip(s)


## The weapon, a first-aid kit and a bottle of water go along if the stores have them.
func _pack_for_trip(s: Dictionary) -> void:
	var stores: Dictionary = WorldState.stores
	if WorldState.policies.get(&"use_guns", false) and Stores.total(stores, "rifle") >= 1.0 and Stores.total(stores, "ammo") >= 1.0:
		Stores.take(stores, "rifle", 1.0)
		s["weapon"] = "rifle"
		s["ammo"] = int(Stores.take(stores, "ammo", float(TRIP_AMMO)))
	elif Stores.total(stores, "machete") >= 1.0:
		Stores.take(stores, "machete", 1.0)
		s["weapon"] = "machete"
	for item: String in TRIP_KIT:
		Stores.add_lots(s["carried"], item, Stores.take_lots(stores, item, float(TRIP_KIT[item])))
	for item: String in ["water_boiled", "water_bottled"]:
		var have: float = Stores.total(s["carried"], "water_boiled") + Stores.total(s["carried"], "water_bottled")
		Stores.add_lots(s["carried"], item, Stores.take_lots(stores, item, TRIP_WATER_L - have))


func _continue_trip(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	var speed_mult: float = maxf(MIN_SPEED_MULT, Body.work_speed(s))
	s["asleep"] = false
	match trip["leg"]:
		&"prepare":
			# Hiding what the group can't carry before it leaves.
			s["activity"] = &"heavy_work"
			trip["work_ticks_left"] = int(trip["work_ticks_left"]) - 1
			if int(trip["work_ticks_left"]) <= 0:
				trip["leg"] = &"out"
		&"out", &"back":
			var speed: float = SPEED_OUT_M_PER_H if trip["leg"] == &"out" else SPEED_BACK_M_PER_H
			speed *= Traits.mult(s, "travel_speed_mult") * float(trip.get("speed_mult", 1.0))
			trip["progress_m"] = minf(float(trip["distance_m"]), float(trip["progress_m"]) + speed * speed_mult / 6.0)
			s["activity"] = &"travelling"
			s["outdoors"] = true
			s["exposure"] = {"outdoors": true, "building": "", "noise_m": float(trip.get("noise_m", NOISE_TRAVEL_M))}
			_set_position(s)
			if float(trip["progress_m"]) >= float(trip["distance_m"]):
				if trip["leg"] == &"out":
					_arrive(s)
				else:
					_return_home(s)
		&"fill":
			s["activity"] = &"heavy_work"
			s["outdoors"] = true
			s["exposure"] = {"outdoors": true, "building": "", "noise_m": NOISE_TRAVEL_M,
				"zone": Geo.zone_index_at(trip["dest"])}
			_ferry_water(s)
		&"clear":
			# Anything trapped inside the new base is met here, as on a search.
			s["activity"] = &"searching"
			s["outdoors"] = false
			s["exposure"] = {"outdoors": false, "building": trip["building"], "noise_m": NOISE_SEARCH_M,
				"zone": Geo.zone_index_at(trip["dest"])}
			trip["work_ticks_left"] = int(trip["work_ticks_left"]) - 1
			if int(trip["work_ticks_left"]) <= 0:
				_finish_move(s)
		&"search":
			s["activity"] = &"searching"
			s["outdoors"] = false
			s["exposure"] = {"outdoors": false, "building": trip["building"], "noise_m": NOISE_SEARCH_M,
				"zone": Geo.zone_index_at(trip["dest"])}
			trip["work_ticks_left"] = int(trip["work_ticks_left"]) - 1
			if int(trip["work_ticks_left"]) <= 0:
				_take_loot(s)
				_head_back(s)


func _set_position(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	var origin: Vector2 = trip["origin"]
	var dest: Vector2 = trip["dest"]
	var t: float = float(trip["progress_m"]) / maxf(float(trip["distance_m"]), 1.0)
	var pos: Vector2 = origin.lerp(dest, t) if trip["leg"] == &"out" else dest.lerp(origin, t)
	s["x_m"] = pos.x
	s["y_m"] = pos.y
	s["exposure"]["zone"] = Geo.zone_index_at(pos)


func _arrive(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	var building: Dictionary = WorldState.building(String(trip["building"]))
	s["x_m"] = float(trip["dest"].x)
	s["y_m"] = float(trip["dest"].y)
	if trip["kind"] == &"move":
		trip["leg"] = &"clear"
		trip["work_ticks_left"] = roundi(CLEAR_BUILDING_HOURS * 6.0)
		return
	if trip["kind"] == &"collect_water":
		trip["leg"] = &"fill"
		return
	trip["leg"] = &"search"
	var hours: float = SEARCH_HOURS * (NIGHT_SEARCH_TIME_MULT if WorldState.phase() == WorldState.PHASE_NIGHT else 1.0)
	trip["work_ticks_left"] = roundi(hours * 6.0)
	building["visits"] = int(building["visits"]) + 1
	_recover_caches(s, building)
	if building["locked"]:
		building["locked"] = false
		EventBus.emit_event(&"noise", {"x_m": s["x_m"], "y_m": s["y_m"], "radius_m": NOISE_BREAK_DOOR_M, "source": &"door"})
		EventBus.emit_event(&"door_forced", {"survivor": s["id"], "building": building["id"],
			"text": "%s forces the door of %s. The noise carries." % [s["name"], building["name"]]})


func _take_loot(s: Dictionary) -> void:
	var building: Dictionary = WorldState.building(String(s["trip"]["building"]))
	var share: float = minf(SEARCH_SHARE_MAX, SEARCH_SHARE_BASE + SEARCH_SHARE_PER_SKILL * Body.skill(s, "scavenging")
		+ Traits.add(s, "search_share_add"))
	if WorldState.phase() == WorldState.PHASE_NIGHT:
		share *= NIGHT_SEARCH_SHARE_MULT
	var capacity: float = CARRY_KG * Traits.mult(s, "carry_kg_mult") * clampf(Body.work_speed(s), MIN_SPEED_MULT, 1.0) - _carried_kg(s)
	var category_kg: Dictionary = {}
	for item: String in _loot_order():
		var item_share: float = share
		if Data.entry("items", item).get("category", "") == "medicine":
			item_share = minf(SEARCH_SHARE_MAX, share * Traits.mult(s, "medicine_find_mult"))
		var available: float = Stores.total(building["loot"], item) * item_share
		if available <= Stores.EPSILON or capacity <= 0.0:
			continue
		var row: Dictionary = Data.entry("items", item)
		var category: String = row["category"]
		var room_kg: float = minf(capacity, float(CATEGORY_KG_CAP.get(category, 10.0)) - float(category_kg.get(category, 0.0)))
		var qty: float = minf(available, Stores.qty_for_weight(item, room_kg))
		if String(row["unit"]) in ["count", "rounds", "units"]:
			qty = floorf(qty)
		if qty <= Stores.EPSILON or Stores.weight_kg(item, qty) < MIN_PICKUP_KG and not String(row["unit"]) in ["count", "rounds"]:
			continue
		Stores.add_lots(s["carried"], item, Stores.take_lots(building["loot"], item, qty))
		var kg: float = Stores.weight_kg(item, qty)
		capacity -= kg
		category_kg[category] = float(category_kg.get(category, 0.0)) + kg


## Gear the group lacks jumps the queue, right after medicine.
func _loot_order() -> Array[String]:
	var order: Array[String] = LOOT_PRIORITY.duplicate()
	for item: String in WANTED_GEAR:
		if Stores.total(WorldState.stores, item) < float(WANTED_GEAR[item]):
			order.erase(item)
			order.insert(order.find("ammo"), item)
	return order


func _head_back(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	trip["leg"] = &"back"
	trip["progress_m"] = 0.0
	trip["origin"] = Geo.base_center_m()
	trip["dest"] = Vector2(float(s["x_m"]), float(s["y_m"]))
	trip["distance_m"] = Geo.street_distance_m(trip["origin"], trip["dest"])


func _return_home(s: Dictionary) -> void:
	var trip: Dictionary = s["trip"]
	s["exposure"] = {}
	if trip["kind"] == &"move":
		_finish_move(s)
		return
	if trip["kind"] == &"collect_water":
		s["location"] = &"base"
		s["trip"] = {}
		_place_at_base(s)
		EventBus.emit_event(&"water_collected", {"survivor": s["id"], "litres": float(trip.get("litres", 0.0)),
			"text": "%s ferried %d L of water from %s (needs boiling)." % [s["name"], roundi(float(trip.get("litres", 0.0))), trip["place"]]})
		return
	var building: Dictionary = WorldState.building(String(trip["building"]))
	var summary: Dictionary = Stores.snapshot(s["carried"])
	var packed: Dictionary = trip.get("packed", {})
	for item: String in packed:
		summary[item] = float(summary.get(item, 0.0)) - float(packed[item])
		if float(summary[item]) <= 0.01:
			summary.erase(item)
	var kg: float = _carried_kg(s)
	Stores.merge_into(WorldState.stores, s["carried"])
	if s["weapon"] != "":
		Stores.add(WorldState.stores, String(s["weapon"]), 1.0)
		Stores.add(WorldState.stores, "ammo", float(s["ammo"]))
		s["weapon"] = ""
		s["ammo"] = 0
	var hours: float = float(WorldState.tick - int(trip["started_tick"])) / 6.0
	s["location"] = &"base"
	s["trip"] = {}
	_place_at_base(s)
	EventBus.emit_event(&"scavenge_returned", {"survivor": s["id"], "building": building.get("id", ""),
		"loot": summary, "hours": hours, "kg": kg,
		"text": "%s is back from %s after %.1f h with %.1f kg: %s." % [s["name"], building.get("name", "town"), hours, kg, _loot_text(summary)]})


## Infected cut a trip short: anyone hurt heads straight home with what they have.
func _on_encounter(payload: Dictionary) -> void:
	var s: Dictionary = WorldState.survivor(String(payload["survivor"]))
	if s.is_empty() or s["status"] != &"ok" or s["location"] != &"away":
		return
	if not payload.get("abort_trip", false) or s["trip"].get("leg", &"") == &"back":
		return
	_head_back(s)


## The whole group walks to the new base carrying what Base packed for them.
func _on_base_moved(payload: Dictionary) -> void:
	var from: Vector2 = Geo.building_center_m(WorldState.building(String(payload["from"])))
	var target: Dictionary = WorldState.building(String(payload["to"]))
	var dest: Vector2 = Geo.building_center_m(target)
	var prepare_ticks: int = roundi(float(payload.get("hide_hours", 0.0)) * 6.0)
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base":
			continue
		s["location"] = &"away"
		s["trip"] = {"kind": &"move", "building": target["id"], "place": target["name"],
			"leg": &"prepare" if prepare_ticks > 0 else &"out", "origin": from, "dest": dest,
			"distance_m": Geo.street_distance_m(from, dest), "progress_m": 0.0, "work_ticks_left": prepare_ticks,
			"started_tick": WorldState.tick, "speed_mult": float(payload.get("speed_mult", 1.0)),
			"noise_m": float(payload.get("noise_m", NOISE_TRAVEL_M))}


## A cache the group hid here goes back into the building's loot for this search.
func _recover_caches(s: Dictionary, building: Dictionary) -> void:
	for cache: Dictionary in WorldState.caches.duplicate():
		if cache["building"] != building["id"]:
			continue
		Stores.merge_into(building["loot"], cache["items"])
		WorldState.caches.erase(cache)
		EventBus.emit_event(&"cache_recovered", {"survivor": s["id"], "building": building["id"],
			"text": "%s digs out the group's cache at %s." % [s["name"], building["name"]]})


func _finish_move(s: Dictionary) -> void:
	s["exposure"] = {}
	Stores.merge_into(WorldState.stores, s["carried"])
	s["location"] = &"base"
	s["trip"] = {}
	_place_at_base(s)


func _carried_kg(s: Dictionary) -> float:
	var kg: float = 0.0
	var carried: Dictionary = s["carried"]
	for item: String in carried:
		kg += Stores.weight_kg(item, Stores.total(carried, item))
	return kg


func _place_at_base(s: Dictionary) -> void:
	var pos: Vector2 = Geo.base_center_m()
	s["x_m"] = pos.x
	s["y_m"] = pos.y


static func _loot_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return "nothing"
	var parts: PackedStringArray = []
	for item: String in summary:
		var row: Dictionary = Data.entry("items", item)
		var qty: float = summary[item]
		var whole: bool = qty >= 10.0 or String(row["unit"]) in ["count", "rounds", "units"]
		var amount: String = str(roundi(qty)) if whole else str(snappedf(qty, 0.1))
		var unit: String = "" if String(row["unit"]) == "count" else " " + String(row["unit"])
		parts.append("%s %s%s" % [String(row["name"]).to_lower(), amount, unit])
	return ", ".join(parts)


func _on_set_job(payload: Dictionary) -> void:
	var s: Dictionary = WorldState.survivor(String(payload["survivor"]))
	var shift: StringName = StringName(payload["shift"])
	var job: StringName = StringName(payload["job"])
	if s.is_empty() or not JOBS.has(job) or not shift in [&"day", &"night"]:
		push_error("Jobs: bad command_set_job %s" % payload)
		return
	s["jobs"][shift] = job
	if payload.has("target"):
		s["targets"][shift] = String(payload["target"])


static func current_shift() -> StringName:
	return &"day" if WorldState.phase() == WorldState.PHASE_DAY else &"night"


## Minutes since the current shift began.
static func minutes_into_shift() -> int:
	var start: int = WorldState.DAYTIME_START_MINUTE if current_shift() == &"day" else WorldState.NIGHT_START_MINUTE
	return posmod(WorldState.minute_of_day() - start, WorldState.MINUTES_PER_DAY)


static func in_work_hours() -> bool:
	var into: int = minutes_into_shift()
	return into >= WORK_START_OFFSET_MIN and into < WORK_START_OFFSET_MIN + WORK_MINUTES


## A number that changes every shift, for "once per shift" bookkeeping.
@warning_ignore("integer_division")
static func shift_index() -> int:
	return WorldState.tick / (WorldState.TICKS_PER_DAY / 2)
