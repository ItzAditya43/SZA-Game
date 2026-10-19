extends "res://core/sim_system.gd"
## Base. The building the group lives in and keeps its stores. Its defense is the
## building's own (house 10, school 25, police station 50...) plus barricades
## built on the fortify job (or quick barricades, faster but weaker) plus whoever
## stands guard. Each night hour nearby infected may attack: likelier and bigger
## the more attention the base has drawn (systems/attention.gd) and the more
## infected in its zone, less likely the stronger it is. Moving base carries what
## the group can (on foot, by handcart or vehicle) and hides the rest in a cache.

const Body := preload("res://core/body.gd")
const Stores := preload("res://core/stores.gd")
const Geo := preload("res://core/geo.gd")
const Decisions := preload("res://core/decisions.gd")
const Difficulty := preload("res://core/difficulty.gd")
const Traits := preload("res://core/traits.gd")

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

# --- Night attacks (rolled each night hour) ---
const ATTACK_BASE_PER_HOUR: float = 0.05
## Zone population at which the base attack chance applies as is.
const ATTACK_DENSITY_REF: float = 500.0
const DEFENSE_SCALE: float = 100.0
const ATTACK_SHARE_OF_ZONE: float = 0.010
const ATTACK_MIN_SIZE: int = 2
const STRENGTH_PER_INFECTED: float = 3.5
## Repelled attacks wear barricades down by this share of their strength.
const BARRICADE_WEAR: float = 0.2
const GUARD_HURT_CHANCE: float = 0.1
const BREACH_HURT_BASE: float = 0.15
const BREACH_HURT_PER_OVERMATCH: float = 0.3
const ASLEEP_HURT_MULT: float = 1.3
const BREACH_KILLED_SHARE: float = 0.15
const BREACH_BITTEN_SHARE: float = 0.35
const STRESS_ON_ATTACK: float = 5.0
const STRESS_ON_BREACH: float = 15.0
const GUARD_AMMO_PER_ATTACK: int = 4
const GUNSHOT_RADIUS_M: float = 600.0
## A survivor turning inside base attacks whoever is near.
const TURNED_INSIDE_HURT_CHANCE: float = 0.35

# --- Moving base ---
## Share of the group's total carrying capacity each category may take on the
## first packing pass (shares overlap; whatever is left is filled by priority).
const MOVE_SHARE: Dictionary = {
	"medicine": 0.05, "comfort": 0.01, "weapon": 0.05, "food": 0.45, "water": 0.30,
	"fuel": 0.08, "gear": 0.15, "materials": 0.10, "vehicle": 1.0,
}
## What the group carries first when it moves.
const MOVE_PRIORITY: Array[String] = [
	"antibiotics", "tourniquet", "ors", "bandages", "painkillers", "ammo", "rifle", "machete",
	"water_boiled", "water_bottled", "packaged_food", "cooked_meal", "rice", "dal", "atta", "fresh_produce",
	"fuel", "cooking_gas", "generator", "water_drum", "materials", "water_untreated",
]


var _mobility: Dictionary = {}


func setup() -> void:
	listen(&"survivor_turned", _on_survivor_turned)
	listen(&"command_move_base", _on_move_base)
	_mobility = Data.table("mobility")
	WorldState.base = {"building": String(Data.table("scenario")["start_building"]),
		"defense": 0.0, "defense_parts": {}, "attacks": 0, "breaches": 0, "attention": 0.0, "attention_level": &"low", "bodies": []}
	WorldState.stats["attacks"] = 0
	WorldState.stats["breaches"] = 0


func tick() -> void:
	_fortify()
	_update_defense()
	if WorldState.tick % 6 == 0 and WorldState.phase() == WorldState.PHASE_NIGHT:
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
		parts["others"] = float(parts["others"]) + Traits.add(s, "base_defense_add")
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
	var quick: Dictionary = _mobility["quick_barricade"]
	for s: Dictionary in WorldState.group():
		if s["location"] != &"base" or not s["job_now"] in [&"fortify", &"quick_fortify"] or s["activity"] != &"heavy_work":
			continue
		var is_quick: bool = s["job_now"] == &"quick_fortify"
		var per_material: float = float(quick["points_per_material"]) if is_quick else BARRICADE_PER_MATERIAL
		var job_cap: float = cap * float(quick["cap_share"]) if is_quick else cap
		var room: float = (job_cap - float(building["barricade"])) / per_material
		var rate: float = float(quick["materials_per_hour"]) if is_quick else FORTIFY_MATERIALS_PER_HOUR
		var wanted: float = minf(room, rate * Body.work_speed(s) * Traits.mult(s, "fortify_speed_mult") / 6.0)
		var used: float = Stores.take(WorldState.stores, "materials", wanted)
		if used <= Stores.EPSILON:
			if int(s.get("fortify_warned_shift", -1)) != _shift_index():
				s["fortify_warned_shift"] = _shift_index()
				var why: String = "the barricades are as strong as this building allows" if room <= 0.01 else "there are no materials left"
				EventBus.emit_event(&"fortify_blocked", {"survivor": s["id"], "text": "%s can't fortify: %s." % [s["name"], why]})
			continue
		building["barricade"] = float(building["barricade"]) + used * per_material
		hammering = true
	if hammering and WorldState.tick % 6 == 0:
		var pos: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"noise", {"x_m": pos.x, "y_m": pos.y, "radius_m": HAMMERING_NOISE_M, "source": &"hammering", "continuous": true})


@warning_ignore("integer_division")
static func _shift_index() -> int:
	return WorldState.tick / (WorldState.TICKS_PER_DAY / 2)


# --- Attacks ---

func _maybe_attack() -> void:
	if WorldState.group().is_empty():
		return
	var zone: Dictionary = WorldState.zones[Geo.zone_index_at(Geo.base_center_m())]
	var count: float = float(zone["infected"])
	var config: Dictionary = Data.table("attention")
	var drawn: float = float(config["attack_baseline"]) + float(WorldState.base.get("attention", 0.0)) / float(config["attack_reference"])
	var defense: float = float(WorldState.base["defense"])
	var attacks: float = Difficulty.mult("attacks")
	var chance: float = ATTACK_BASE_PER_HOUR * attacks * (count / ATTACK_DENSITY_REF) * drawn * exp(-defense / DEFENSE_SCALE)
	if not Rng.chance(chance):
		return
	var size: int = maxi(ATTACK_MIN_SIZE, roundi(count * ATTACK_SHARE_OF_ZONE * attacks * lerpf(0.5, 1.5, Rng.randf())))
	_attack(size, zone)


## Public to tests through call(): an attack of `size` infected on the base right now.
func _attack(size: int, zone: Dictionary) -> void:
	var building: Dictionary = base_building()
	var defense: float = float(WorldState.base["defense"])
	var strength: float = float(size) * STRENGTH_PER_INFECTED
	WorldState.base["attacks"] = int(WorldState.base["attacks"]) + 1
	WorldState.stats["attacks"] = int(WorldState.stats["attacks"]) + 1
	var guards: Array = _guards()
	var weapons: float = float(WorldState.base["defense_parts"].get("weapons", 0.0))
	# Guards only open fire when the attack could break in without the guns.
	if weapons >= float(WEAPON_DEFENSE["rifle"]) and strength > defense - weapons:
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
		# A handful scratching at a fortress frightens less than a near thing.
		var closeness: float = clampf(1.5 * strength / maxf(defense, 1.0), 0.3, 1.0)
		for s: Dictionary in at_base:
			Traits.add_stress(s, STRESS_ON_ATTACK * closeness, "fights", "night attack")
		var where: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"night_attack", {"size": size, "strength": strength, "defense": defense, "breached": false,
			"x_m": where.x, "y_m": where.y,
			"text": "About %d infected hit the base in the dark. The defenses held (%d against %d)." % [size, roundi(defense), roundi(strength)]})
	else:
		building["barricade"] = float(building["barricade"]) * 0.5
		killed = roundi(size * 0.5)
		WorldState.base["breaches"] = int(WorldState.base["breaches"]) + 1
		WorldState.stats["breaches"] = int(WorldState.stats["breaches"]) + 1
		var hurt_chance: float = clampf(BREACH_HURT_BASE + BREACH_HURT_PER_OVERMATCH * (strength - defense) / maxf(defense, 1.0), 0.1, 0.9)
		var casualties: PackedStringArray = []
		for s: Dictionary in at_base:
			Traits.add_stress(s, STRESS_ON_BREACH, "fights", "base broken into")
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
		var breach_at: Vector2 = Geo.base_center_m()
		EventBus.emit_event(&"base_breached", {"size": size, "strength": strength, "defense": defense, "breached": true,
			"x_m": breach_at.x, "y_m": breach_at.y,
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
	var transport: Dictionary = _transport(movers, old, target)
	for s: Dictionary in movers:
		Traits.add_stress(s, float(_mobility["stress_per_move"]), "", "uprooted by a move")
	# Loads: one per person on foot, plus handcarts and the vehicle as extra loads.
	var capacity: Array[float] = []
	var holders: Array = []
	for s: Dictionary in movers:
		capacity.append(float(_mobility["on_foot_kg"]) * Traits.mult(s, "carry_kg_mult") * clampf(Body.work_speed(s), 0.4, 1.0))
		holders.append(s)
	for extra: float in transport["extra_kg"]:
		capacity.append(extra)
		holders.append(movers[holders.size() % movers.size()])
	var conveyances: Dictionary = transport["vehicles_used"]
	for item: String in conveyances:
		Stores.take(WorldState.stores, item, float(conveyances[item]))
	# First each category gets its share of the total load, then any room left is
	# filled in priority order, so a full water tank can't crowd out the food.
	var total_kg: float = 0.0
	for kg: float in capacity:
		total_kg += kg
	var budgets: Dictionary = {}
	for category: String in MOVE_SHARE:
		budgets[category] = float(MOVE_SHARE[category]) * total_kg
	_pack(capacity, holders, budgets)
	_pack(capacity, holders, {})
	# The handcarts and vehicle arrive with the group.
	for item: String in conveyances:
		Stores.add(movers[0]["carried"], item, float(conveyances[item]))
	var hide_hours: float = float(payload.get("hide_hours", _mobility["cache"]["hide_hours"]))
	var left_behind: Dictionary = Stores.snapshot(WorldState.stores)
	if not left_behind.is_empty():
		var cache_config: Dictionary = _mobility["cache"]
		var quality: float = minf(float(cache_config["quality_max"]),
			float(cache_config["quality_base"]) + float(cache_config["quality_per_hour"]) * hide_hours)
		WorldState.caches.append({"id": WorldState.new_id(), "building": old["id"], "items": WorldState.stores.duplicate(true),
			"quality": quality, "tick": WorldState.tick})
		WorldState.stores.clear()
	WorldState.base["building"] = target["id"]
	# Moving in means searching the place: whatever is still inside becomes the group's.
	var found: Dictionary = Stores.snapshot(target["loot"])
	Stores.merge_into(WorldState.stores, target["loot"])
	target["stripped"] = true
	EventBus.emit_event(&"base_moved", {"from": old["id"], "to": target["id"], "left_behind": left_behind,
		"hide_hours": hide_hours if not left_behind.is_empty() else 0.0,
		"speed_mult": transport["speed_mult"], "noise_m": transport["noise_m"], "found": found,
		"text": "The group moves from %s to %s%s%s." % [old["name"], target["name"], transport["how"],
			", hiding what it can't carry" if not left_behind.is_empty() else ""]})


## Packs stores into the loads in MOVE_PRIORITY order. With budgets, each item's
## category may only use its budget (kg); without, anything fits.
func _pack(capacity: Array[float], holders: Array, budgets: Dictionary) -> void:
	for item: String in MOVE_PRIORITY:
		var category: String = Data.entry("items", item).get("category", "")
		var index: int = 0
		while index < capacity.size() and Stores.total(WorldState.stores, item) > Stores.EPSILON:
			var room: float = capacity[index]
			if not budgets.is_empty():
				room = minf(room, float(budgets.get(category, 0.0)))
			var fits: float = Stores.qty_for_weight(item, room)
			if Data.entry("items", item).get("unit", "") in ["count", "rounds", "units"]:
				fits = floorf(fits)
			if fits <= Stores.EPSILON:
				if not budgets.is_empty() and float(budgets.get(category, 0.0)) <= 0.01:
					break
				index += 1
				continue
			var lots: Array = Stores.take_lots(WorldState.stores, item, fits)
			var moved: float = 0.0
			for lot: Dictionary in lots:
				moved += float(lot["qty"])
			Stores.add_lots(holders[index]["carried"], item, lots)
			var kg: float = Stores.weight_kg(item, moved)
			capacity[index] -= kg
			if not budgets.is_empty():
				budgets[category] = float(budgets[category]) - kg


## How the group travels: on foot, with any handcarts, or by vehicle if it has
## one, a driver and the fuel for the trip.
func _transport(movers: Array, from: Dictionary, to: Dictionary) -> Dictionary:
	var out: Dictionary = {"extra_kg": [], "vehicles_used": {}, "speed_mult": 1.0, "noise_m": 15.0, "how": " on foot"}
	var km: float = Geo.street_distance_m(Geo.building_center_m(from), Geo.building_center_m(to)) / 1000.0
	var vehicle: Dictionary = _mobility["vehicle"]
	var fuel_needed: float = km * float(vehicle["fuel_l_per_km"])
	var driver: bool = movers.any(func(s: Dictionary) -> bool: return Traits.has(s, "can_drive"))
	if Stores.total(WorldState.stores, "vehicle") >= 1.0 and driver and Stores.total(WorldState.stores, "fuel") >= fuel_needed:
		Stores.take(WorldState.stores, "fuel", fuel_needed)
		out["extra_kg"].append(float(vehicle["carry_kg"]))
		out["vehicles_used"]["vehicle"] = 1.0
		out["speed_mult"] = float(vehicle["speed_mult"])
		out["noise_m"] = float(vehicle["noise_m"])
		out["how"] = " by vehicle"
		return out
	var carts: int = mini(roundi(Stores.total(WorldState.stores, "handcart")), movers.size())
	if carts > 0:
		var cart: Dictionary = _mobility["handcart"]
		for i: int in carts:
			out["extra_kg"].append(float(cart["carry_kg"]))
		out["vehicles_used"]["handcart"] = float(carts)
		out["speed_mult"] = float(cart["speed_mult"])
		out["noise_m"] = float(cart["noise_m"])
		out["how"] = " with %d handcart%s" % [carts, "" if carts == 1 else "s"]
	return out
