extends "res://core/sim_system.gd"
## Attention. A group that stays in one place gives itself away: voices and foot
## traffic, latrine and rubbish smell, cooking smoke, firelight and generator light
## at night, generator noise, hammering, gunshots, unburied bodies. Each site the
## group uses accumulates attention from those signals (data/attention.json) and
## loses it slowly while people remain, faster once they leave (half-life about
## 3 days). Infected drift toward high-attention sites (systems/infected.gd) and
## night attacks scale with the base's attention (systems/base.gd). Moving resets
## it, at a cost.

const Geo := preload("res://core/geo.gd")

const TICK_DAYS: float = 1.0 / 144.0
const TICK_HOURS: float = 1.0 / 6.0

var _config: Dictionary = {}


func setup() -> void:
	_config = Data.table("attention")
	WorldState.attention = {}
	WorldState.base["bodies"] = []
	WorldState.base["attention_level"] = &"low"
	listen(&"noise", _on_noise)
	listen(&"survivor_died", _on_death)
	listen(&"survivor_turned", _on_death)
	listen(&"base_moved", _on_base_moved)


func tick() -> void:
	var base_id: String = String(WorldState.base.get("building", ""))
	var occupants: Array = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base")
	var signals: Dictionary = _config["signals_per_hour"]
	var gain: float = 0.0
	if not occupants.is_empty():
		gain += occupants.size() * (float(signals["person_present"]) + float(signals["waste_per_person"]))
		var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
		for s: Dictionary in occupants:
			if s["job_now"] == &"cook" and s["activity"] == &"light_work":
				gain += float(signals["cooking_smoke"]) + (float(signals["firelight_at_night"]) if night else 0.0)
			elif s["job_now"] in [&"fortify", &"quick_fortify"] and s["activity"] == &"heavy_work":
				gain += float(signals["hammering"])
		if WorldState.infrastructure.get("generator_running", false):
			gain += float(signals["generator_noise"]) + (float(signals["generator_light_at_night"]) if night else 0.0)
	var bodies: Array = WorldState.base["bodies"]
	var smell_ticks: int = roundi(float(_config["body_smell_days"]) * WorldState.TICKS_PER_DAY)
	WorldState.base["bodies"] = bodies.filter(func(t: int) -> bool: return WorldState.tick - t < smell_ticks)
	gain += WorldState.base["bodies"].size() * float(signals["unburied_body"])
	if gain > 0.0:
		_add(base_id, gain * TICK_HOURS)
	for site: String in WorldState.attention.keys():
		var occupied: bool = site == base_id and not occupants.is_empty()
		var half_life: float = float(_config["half_life_days_occupied" if occupied else "half_life_days_empty"])
		WorldState.attention[site] = float(WorldState.attention[site]) * pow(0.5, TICK_DAYS / half_life)
		if float(WorldState.attention[site]) < 0.5 and site != base_id:
			WorldState.attention.erase(site)
	WorldState.base["attention"] = float(WorldState.attention.get(base_id, 0.0))
	WorldState.base["attention_level"] = level(float(WorldState.base["attention"]))


## "low", "rising" or "high" for an attention value, as the base panel shows it.
static func level(value: float) -> StringName:
	var levels: Dictionary = Data.table("attention")["levels"]
	if value >= float(levels["high"]):
		return &"high"
	if value >= float(levels["rising"]):
		return &"rising"
	return &"low"


func _add(site: String, amount: float) -> void:
	if site == "":
		return
	WorldState.attention[site] = float(WorldState.attention.get(site, 0.0)) + amount


## A one-off noise (a gunshot, a forced door) that reaches the base adds to its
## attention, more the closer it was. Continuous noise (generator, hammering) is
## counted per hour above instead.
func _on_noise(payload: Dictionary) -> void:
	if payload.get("continuous", false):
		return
	var base: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	if base.is_empty():
		return
	var radius: float = float(payload["radius_m"])
	var distance: float = Vector2(float(payload["x_m"]), float(payload["y_m"])).distance_to(Geo.building_center_m(base))
	if distance > radius:
		return
	var weights: Dictionary = _config["one_off_noise"]
	var weight: float = float(weights.get(String(payload.get("source", "noise")), weights["noise"]))
	_add(String(base["id"]), weight * (1.0 - distance / radius))


## Arriving loaded through the streets and forcing a way in is seen and heard.
func _on_base_moved(payload: Dictionary) -> void:
	_add(String(payload["to"]), float(_config["arrival"]))


## Someone who dies or turns at base leaves a body; the smell lasts a few days.
func _on_death(payload: Dictionary) -> void:
	var s: Dictionary = WorldState.survivor(String(payload["survivor"]))
	if not s.is_empty() and s["location"] == &"base":
		WorldState.base["bodies"].append(WorldState.tick)
