extends "res://core/sim_system.gd"
## Events. The hand-written events in data/events.json. Each has a trigger (a day
## range, an hour, a daily chance, conditions), a text, and effects on the world;
## some ask the player to decide first. Every event has a cause in the world
## (a cooking fire, an evacuee who hid a bite), never a disaster from nowhere.

const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Decisions := preload("res://core/decisions.gd")

## Events without an hour roll at this hour.
const DEFAULT_HOUR: int = 10
## Rain caught off a roof: share of the water that reaches a tank or container.
const ROOF_CATCH_SHARE: float = 0.8
## Buckets and pans put out for a storm catch this share of the base roof's rain.
const BUCKET_CATCH_SHARE: float = 0.3
const FIRE_BUILDING_TYPES: Array[String] = ["kirana", "pharmacy", "hardware"]

var _events: Array = []


func setup() -> void:
	listen(&"decision_made", _on_decision)
	_events = Data.table("events")
	WorldState.flags["events_fired"] = {}


@warning_ignore("integer_division")
func tick() -> void:
	if WorldState.minute_of_day() % 60 != 0:
		return
	var hour: int = WorldState.minute_of_day() / 60
	var day: int = WorldState.day()
	var fired: Dictionary = WorldState.flags["events_fired"]
	for event: Dictionary in _events:
		if fired.has(event["id"]):
			continue
		var trigger: Dictionary = event["trigger"]
		if day < int(trigger["day_min"]) or day > int(trigger["day_max"]) or hour != int(trigger.get("hour", DEFAULT_HOUR)):
			continue
		if not _conditions_met(trigger.get("requires", [])):
			continue
		if not Rng.chance(float(trigger.get("chance_per_day", 1.0))):
			continue
		_fire(event)


func _fire(event: Dictionary) -> void:
	WorldState.flags["events_fired"][event["id"]] = WorldState.tick
	EventBus.emit_event(&"story_event", {"id": event["id"], "title": event["title"], "text": event["text"]})
	_apply(event.get("effects", []))
	if event.has("decision"):
		var decision: Dictionary = event["decision"]
		var options: Array = []
		for option: Dictionary in decision["options"]:
			options.append(Decisions.option(StringName(option["id"]), String(option["label"])))
		Decisions.create(&"event", String(decision["text"]), options, {"event": event["id"]})


func _on_decision(payload: Dictionary) -> void:
	var decision: Dictionary = Decisions.find(int(payload["id"]))
	if decision.is_empty() or decision["kind"] != &"event":
		return
	Decisions.resolve(int(payload["id"]))
	for event: Dictionary in _events:
		if event["id"] != decision["event"]:
			continue
		for option: Dictionary in event["decision"]["options"]:
			if StringName(option["id"]) == StringName(payload["option"]):
				_apply(option.get("effects", []))


func _conditions_met(conditions: Array) -> bool:
	for condition: Dictionary in conditions:
		match String(condition["type"]):
			"flag":
				if not WorldState.flags.get(String(condition["flag"]), false):
					return false
			"group_size_at_most":
				if WorldState.group().size() > int(condition["value"]):
					return false
			"max_temp_at_least":
				if float(WorldState.climate.get("today_max_c", 0.0)) < float(condition["value"]):
					return false
			_:
				push_error("Events: unknown condition %s" % condition)
				return false
	return true


func _apply(effects: Array) -> void:
	for effect: Dictionary in effects:
		match String(effect["type"]):
			"scale_loot":
				for building: Dictionary in _targets(effect):
					for item: String in Stores.snapshot(building["loot"]):
						Stores.take(building["loot"], item, Stores.total(building["loot"], item) * (1.0 - float(effect["factor"])))
			"add_loot":
				for building: Dictionary in _targets(effect):
					var items: Dictionary = effect["items"]
					for item: String in items:
						Stores.add(building["loot"], item, float(items[item]))
						building["start_loot"][item] = float(building["start_loot"].get(item, 0.0)) + float(items[item])
					building["stripped"] = false
			"destroy_loot":
				_burn(effect)
			"set_danger":
				for building: Dictionary in _targets(effect):
					building["danger"] = float(effect["value"])
			"set_flag":
				WorldState.flags[String(effect["flag"])] = true
			"noise":
				var pos: Vector2 = _position(effect)
				EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": float(effect["radius_m"]),
					"source": StringName(effect.get("source", "noise"))})
			"add_infected":
				var zone: Dictionary = WorldState.zones[Geo.zone_index_at(_position(effect))]
				zone["infected"] = float(zone["infected"]) + float(effect["count"])
			"kill_infected":
				var zone: Dictionary = WorldState.zones[Geo.zone_index_at(_position(effect))]
				zone["infected"] = float(zone["infected"]) * (1.0 - float(effect["share"]))
			"group_stress":
				for s: Dictionary in WorldState.group():
					s["stress"] = clampf(float(s["stress"]) + float(effect["value"]), 0.0, 100.0)
			"add_survivor":
				EventBus.emit_event(&"command_add_survivor", {"id": effect["id"],
					"bitten": Rng.chance(float(effect.get("bitten_chance", 0.0)))})
			"heat_wave":
				var climate: Dictionary = WorldState.climate
				climate["heat_bonus_c"] = float(effect["bonus_c"])
				climate["heat_bonus_until_day"] = WorldState.day() + int(effect["days"]) - 1
				climate["today_max_c"] = float(climate["today_max_c"]) + float(effect["bonus_c"])
				climate["today_min_c"] = float(climate["today_min_c"]) + float(effect["bonus_c"]) * 0.5
			"rain":
				_rain(float(effect["mm"]))
			_:
				push_error("Events: unknown effect %s" % effect)


## Buildings named by "building" (an id) or "building_type".
func _targets(effect: Dictionary) -> Array:
	if effect.has("building"):
		var building: Dictionary = WorldState.building(String(effect["building"]))
		return [] if building.is_empty() else [building]
	return WorldState.buildings.filter(func(b: Dictionary) -> bool: return b["type"] == String(effect.get("building_type", "")))


func _position(effect: Dictionary) -> Vector2:
	if effect.has("building"):
		return Geo.building_center_m(WorldState.building(String(effect["building"])))
	for landmark: Dictionary in WorldState.town["landmarks"]:
		if landmark["name"] == effect.get("landmark", ""):
			return Vector2(float(landmark["x"]) + 0.5, float(landmark["y"]) + 0.5) * Geo.tile_m()
	push_error("Events: no position for %s" % effect)
	return Vector2.ZERO


## The shops nearest the landmark burn out, everything inside lost. The base is spared.
func _burn(effect: Dictionary) -> void:
	var origin: Vector2 = _position(effect)
	var shops: Array = WorldState.buildings.filter(func(b: Dictionary) -> bool:
		return FIRE_BUILDING_TYPES.has(String(b["type"])) and b["id"] != WorldState.base.get("building", ""))
	shops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return origin.distance_to(Geo.building_center_m(a)) < origin.distance_to(Geo.building_center_m(b)))
	var names: PackedStringArray = []
	for building: Dictionary in shops.slice(0, int(effect["count"])):
		building["loot"] = {}
		building["stripped"] = true
		building["burned"] = true
		names.append(building["name"])
	EventBus.emit_event(&"buildings_burned", {"text": "Burned out: %s." % ", ".join(names)})


## Rain fills every roof tank by roof area (1 mm on 1 m² is 1 litre) and the
## group's buckets at base.
func _rain(mm: float) -> void:
	var tile: float = Geo.tile_m()
	for building: Dictionary in WorldState.buildings:
		if float(building["tank_start_l"]) <= 0.0:
			continue
		var roof_m2: float = float(building["w"]) * float(building["h"]) * tile * tile
		building["tank_l"] = minf(float(building["tank_start_l"]), float(building["tank_l"]) + mm * roof_m2 * ROOF_CATCH_SHARE)
	var base: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	if base.is_empty():
		return
	var base_roof: float = float(base["w"]) * float(base["h"]) * tile * tile
	var room: float = Stores.water_capacity_l(WorldState.stores) - Stores.stored_water_l(WorldState.stores)
	var caught: float = minf(room, mm * base_roof * BUCKET_CATCH_SHARE)
	Stores.add(WorldState.stores, "water_untreated", caught)
	EventBus.emit_event(&"rain_caught", {"litres": caught,
		"text": "The group caught %d L of rainwater at base (needs boiling); roof tanks across town refill." % roundi(caught)})
