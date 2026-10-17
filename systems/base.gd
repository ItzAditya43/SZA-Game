extends "res://core/sim_system.gd"
## Base. The building the group lives in and keeps its stores. Its defense is the
## building's own (house 10, school 25, police station 50...) plus barricades
## built on the fortify job plus whoever stands guard. Noise and light near the
## base raise its alert level; each night hour, nearby infected may attack, more
## likely the louder the base and the more infected in its zone, less likely the
## stronger it is. Moving base carries what the group can, and leaves the rest.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Decisions := preload("res://core/decisions.gd")

# --- Defense ---
## Each guard adds this plus 2 per point of combat, less when tired.
const GUARD_DEFENSE: float = 10.0
const GUARD_DEFENSE_PER_COMBAT: float = 2.0
## Everyone else at base wakes and helps a little.
const OTHER_DEFENSE: float = 2.0
const WEAPON_DEFENSE: Dictionary = {"rifle": 10.0, "machete": 3.0}

# --- Fortify ---
const FORTIFY_MATERIALS_PER_HOUR: float = 3.0
const BARRICADE_PER_MATERIAL: float = 1.0
const HAMMERING_NOISE_M: float = 80.0

# --- Alert ---
## Alert decays by this share each hour.
const ALERT_DECAY_PER_HOUR: float = 0.1
const LIGHT_ALERT: float = 0.1

# --- Night attacks (rolled each night hour) ---
const ATTACK_BASE_PER_HOUR: float = 0.04
## Zone population at which the base attack chance applies as is.
const ATTACK_DENSITY_REF: float = 500.0
const DEFENSE_SCALE: float = 100.0
const ATTACK_SHARE_OF_ZONE: float = 0.008
const ATTACK_MIN_SIZE: int = 2
const STRENGTH_PER_INFECTED: float = 3.0
## Repelled attacks wear barricades down by this share of their strength.
const BARRICADE_WEAR: float = 0.2
const GUARD_HURT_CHANCE: float = 0.1
const BREACH_HURT_BASE: float = 0.15
const BREACH_HURT_PER_OVERMATCH: float = 0.3
const ASLEEP_HURT_MULT: float = 1.3
const BREACH_KILLED_SHARE: float = 0.15
const BREACH_BITTEN_SHARE: float = 0.35
const STRESS_ON_ATTACK: float = 5.0
const STRESS_ON_BREACH: float = 20.0
const GUARD_AMMO_PER_ATTACK: int = 4
const GUNSHOT_RADIUS_M: float = 600.0
## A survivor turning inside base attacks whoever is near.
const TURNED_INSIDE_HURT_CHANCE: float = 0.35

# --- Moving base ---
const CARRY_KG: float = 25.0
## What the group carries first when it moves.
const MOVE_PRIORITY: Array[String] = [
	"antibiotics", "tourniquet", "ors", "bandages", "painkillers", "ammo", "rifle", "machete",
	"water_boiled", "water_bottled", "packaged_food", "cooked_meal", "rice", "dal", "atta", "fresh_produce",
	"fuel", "cooking_gas", "generator", "water_drum", "materials", "water_untreated",
]


func setup() -> void:
	listen(&"noise", _on_noise)
	listen(&"light", _on_light)
	listen(&"survivor_turned", _on_survivor_turned)
	listen(&"command_move_base", _on_move_base)
	WorldState.base = {"building": String(Data.table("scenario")["start_building"]), "alert": 0.0,
		"defense": 0.0, "defense_parts": {}, "attacks": 0, "breaches": 0}
	WorldState.stats["attacks"] = 0
	WorldState.stats["breaches"] = 0


func tick() -> void:
	_fortify()
	_update_defense()
	if WorldState.tick % 6 == 0:
		WorldState.base["alert"] = float(WorldState.base["alert"]) * (1.0 - ALERT_DECAY_PER_HOUR)
		if WorldState.phase() == WorldState.PHASE_NIGHT:
			_maybe_attack()


func base_building() -> Dictionary:
	return WorldState.building(String(WorldState.base["building"]))


# --- Defense ---

func _update_defense() -> void:
	var building: Dictionary = base_building()
	var type: Dictionary = Data.entry("buildings", String(building["type"]))
	var parts: Dictionary = {"building": float(type["base_defense"]), "barricades": float(building["barricade"]),
		"guards": 0.0, "others": 0.0, "weapons": 0.0}
	var rifles: float = Stores.total(WorldState.stores, "rifle") if WorldState.policies.get(&"use_guns", false) and Stores.total(WorldState.stores, "ammo") >= 1.0 else 0.0
	var machetes: float = Stores.total(WorldState.stores, "machete")
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base" or s["quarantined"]:
			continue
		if s["activity"] == &"guarding":
			parts["guards"] = float(parts["guards"]) + (GUARD_DEFENSE + GUARD_DEFENSE_PER_COMBAT * Body.skill(s, "combat")) * (1.0 - float(s["fatigue"]) / 200.0)
			if rifles >= 1.0:
				rifles -= 1.0
				parts["weapons"] = float(parts["weapons"]) + float(WEAPON_DEFENSE["rifle"])
			elif machetes >= 1.0:
				machetes -= 1.0
				parts["weapons"] = float(parts["weapons"]) + float(WEAPON_DEFENSE["machete"])
		elif not Body.is_incapacitated(s):
			parts["others"] = float(parts["others"]) + OTHER_DEFENSE
	var total: float = 0.0
	for key: String in parts:
		total += float(parts[key])
	WorldState.base["defense"] = total
	WorldState.base["defense_parts"] = parts


func _guards() -> Array:
	return WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base" and s["activity"] == &"guarding")


# --- Fortify ---

func _fortify() -> void:
	var building: Dictionary = base_building()
	var cap: float = float(Data.entry("buildings", String(building["type"]))["max_barricade"])
	var hammering: bool = false
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base" or s["job_now"] != &"fortify" or s["activity"] != &"heavy_work":
			continue
		var room: float = (cap - float(building["barricade"])) / BARRICADE_PER_MATERIAL
		var wanted: float = minf(room, FORTIFY_MATERIALS_PER_HOUR * Body.work_speed(s) / 6.0)
		var used: float = Stores.take(WorldState.stores, "materials", wanted)
		if used <= Stores.EPSILON:
			if int(s.get("fortify_warned_shift", -1)) != _shift_index():
				s["fortify_warned_shift"] = _shift_index()
				var why: String = "the barricades are as strong as this building allows" if room <= 0.01 else "there are no materials left"
				EventBus.emit_event(&"fortify_blocked", {"survivor": s["id"], "text": "%s can't fortify: %s." % [s["name"], why]})
			continue
		building["barricade"] = float(building["barricade"]) + used * BARRICADE_PER_MATERIAL
		hammering = true
	if hammering and WorldState.tick % 6 == 0:
		var pos: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": HAMMERING_NOISE_M, "source": &"hammering"})


@warning_ignore("integer_division")
static func _shift_index() -> int:
	return WorldState.tick / (WorldState.TICKS_PER_DAY / 2)


# --- Alert ---

## Noise that reaches the base puts the neighbourhood on edge: louder and closer
## noise raises the alert level more.
func _on_noise(payload: Dictionary) -> void:
	var radius: float = float(payload["radius_m"])
	var distance: float = Vector2(float(payload["x_m"]), float(payload["y_m"])).distance_to(Geo.base_center_m())
	if distance > radius:
		return
	var loudness: float = clampf(radius / GUNSHOT_RADIUS_M, 0.05, 1.0)
	WorldState.base["alert"] = float(WorldState.base["alert"]) + loudness * (1.0 - distance / radius)


func _on_light(payload: Dictionary) -> void:
	var distance: float = Vector2(float(payload["x_m"]), float(payload["y_m"])).distance_to(Geo.base_center_m())
	if distance <= float(payload["radius_m"]):
		WorldState.base["alert"] = float(WorldState.base["alert"]) + LIGHT_ALERT


# --- Attacks ---

func _maybe_attack() -> void:
	var zone: Dictionary = WorldState.zones[Geo.zone_index_at(Geo.base_center_m())]
	var count: float = float(zone["infected"])
	var alert: float = float(WorldState.base["alert"])
	var defense: float = float(WorldState.base["defense"])
	var chance: float = ATTACK_BASE_PER_HOUR * (count / ATTACK_DENSITY_REF) * (1.0 + alert) * exp(-defense / DEFENSE_SCALE)
	if not Rng.chance(chance):
		return
	var size: int = maxi(ATTACK_MIN_SIZE, roundi(count * ATTACK_SHARE_OF_ZONE * (1.0 + alert) * lerpf(0.5, 1.5, Rng.randf())))
	_attack(size, zone)


## Public to tests through call(): an attack of `size` infected on the base right now.
func _attack(size: int, zone: Dictionary) -> void:
	var building: Dictionary = base_building()
	var defense: float = float(WorldState.base["defense"])
	var strength: float = float(size) * STRENGTH_PER_INFECTED
	WorldState.base["attacks"] = int(WorldState.base["attacks"]) + 1
	WorldState.stats["attacks"] = int(WorldState.stats["attacks"]) + 1
	var guards: Array = _guards()
	if float(WorldState.base["defense_parts"].get("weapons", 0.0)) >= float(WEAPON_DEFENSE["rifle"]):
		Stores.take(WorldState.stores, "ammo", float(GUARD_AMMO_PER_ATTACK))
		var pos: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": GUNSHOT_RADIUS_M, "source": &"gunshot"})
	var at_base: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	var killed: int
	if strength <= defense:
		building["barricade"] = maxf(0.0, float(building["barricade"]) - strength * BARRICADE_WEAR)
		killed = roundi(size * 0.3)
		for g: Dictionary in guards:
			if Rng.chance(GUARD_HURT_CHANCE * strength / maxf(defense, 1.0) * Body.injury_multiplier(g)):
				_hurt(g, Rng.chance(0.3))
		for s: Dictionary in at_base:
			s["stress"] = clampf(float(s["stress"]) + STRESS_ON_ATTACK, 0.0, 100.0)
		EventBus.emit_event(&"night_attack", {"size": size, "strength": strength, "defense": defense, "breached": false,
			"text": "About %d infected hit the base in the dark. The defenses held (%d against %d)." % [size, roundi(defense), roundi(strength)]})
	else:
		building["barricade"] = float(building["barricade"]) * 0.5
		killed = roundi(size * 0.5)
		WorldState.base["breaches"] = int(WorldState.base["breaches"]) + 1
		WorldState.stats["breaches"] = int(WorldState.stats["breaches"]) + 1
		var hurt_chance: float = clampf(BREACH_HURT_BASE + BREACH_HURT_PER_OVERMATCH * (strength - defense) / maxf(defense, 1.0), 0.1, 0.9)
		var casualties: PackedStringArray = []
		for s: Dictionary in at_base:
			s["stress"] = clampf(float(s["stress"]) + STRESS_ON_BREACH, 0.0, 100.0)
			var chance: float = hurt_chance * Body.injury_multiplier(s) * (ASLEEP_HURT_MULT if s["asleep"] else 1.0)
			if not Rng.chance(minf(chance, 0.95)):
				continue
			var roll: float = Rng.randf()
			if roll < BREACH_KILLED_SHARE:
				s["health"] = 0.0
				s["death_hint"] = "killed when the base was overrun"
				casualties.append(s["name"] + " killed")
			else:
				_hurt(s, roll < BREACH_KILLED_SHARE + BREACH_BITTEN_SHARE)
				casualties.append(s["name"] + " hurt")
		EventBus.emit_event(&"base_breached", {"size": size, "strength": strength, "defense": defense, "breached": true,
			"text": "About %d infected broke into the base (%d against a defense of %d)%s." % [size, roundi(strength), roundi(defense),
				": " + ", ".join(casualties) if not casualties.is_empty() else ""]})
	zone["infected"] = maxf(0.0, float(zone["infected"]) - killed)
	WorldState.stats["infected_killed"] = int(WorldState.stats.get("infected_killed", 0)) + killed


func _hurt(s: Dictionary, bitten: bool) -> void:
	if bitten:
		var bite: Dictionary = Body.new_injury(&"bite", ["arm", "leg", "torso", "neck"][Rng.randi_range(0, 3)], 0.05)
		s["injuries"].append(bite)
	else:
		var deep: bool = Rng.chance(0.4)
		s["injuries"].append(Body.new_injury(&"laceration" if deep else &"cut", ["arm", "leg", "torso"][Rng.randi_range(0, 2)],
			lerpf(0.1, 0.4, Rng.randf()) if deep else lerpf(0.02, 0.05, Rng.randf())))


func _on_survivor_turned(payload: Dictionary) -> void:
	if not payload.get("at_base", false) or payload.get("quarantined", false):
		return
	var victims: PackedStringArray = []
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base" or s["quarantined"]:
			continue
		if Rng.chance(TURNED_INSIDE_HURT_CHANCE * (ASLEEP_HURT_MULT if s["asleep"] else 1.0)):
			_hurt(s, Rng.chance(0.5))
			victims.append(s["name"])
	EventBus.emit_event(&"turned_inside", {"survivor": payload["survivor"],
		"text": "%s turned inside the base before anyone could stop them%s. The group put them down." % [payload["name"],
			", hurting " + ", ".join(victims) if not victims.is_empty() else ""]})


# --- Moving base ---

## The group packs what it can carry and walks to the new building. What it
## cannot carry stays in the old base, where it can be scavenged later.
func _on_move_base(payload: Dictionary) -> void:
	var target: Dictionary = WorldState.building(String(payload["building"]))
	var old: Dictionary = base_building()
	if target.is_empty() or target["id"] == old["id"]:
		return
	var movers: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	if movers.is_empty():
		EventBus.emit_event(&"move_refused", {"text": "Nobody is at base to move."})
		return
	var capacity: Array[float] = []
	for s: Dictionary in movers:
		capacity.append(CARRY_KG * clampf(Body.work_speed(s), 0.4, 1.0))
	var index: int = 0
	for item: String in MOVE_PRIORITY:
		while index < movers.size() and Stores.total(WorldState.stores, item) > Stores.EPSILON:
			var fits: float = Stores.qty_for_weight(item, capacity[index])
			if fits <= Stores.EPSILON:
				index += 1
				continue
			var lots: Array = Stores.take_lots(WorldState.stores, item, fits)
			var moved: float = 0.0
			for lot: Dictionary in lots:
				moved += float(lot["qty"])
			Stores.add_lots(movers[index]["carried"], item, lots)
			capacity[index] -= Stores.weight_kg(item, moved)
	var left_behind: Dictionary = Stores.snapshot(WorldState.stores)
	Stores.merge_into(old["loot"], WorldState.stores)
	WorldState.base["building"] = target["id"]
	WorldState.base["alert"] = 0.0
	EventBus.emit_event(&"base_moved", {"from": old["id"], "to": target["id"], "left_behind": left_behind,
		"text": "The group moves from %s to %s%s." % [old["name"], target["name"],
			", leaving some stores behind" if not left_behind.is_empty() else ""]})
