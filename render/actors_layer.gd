extends Node2D
## What moves and burns in the world (darkened at night with everything else):
## the infected as clustered dots per zone, drifting slowly and leaning towards
## a base that has drawn attention; dark marks where people died; and fires
## with flames, a smoke column that drifts with the wind, and their own light.
## Dots show the simulation's zone counts. LATER (prompt 4): read PlayerKnowledge
## so the counts are fuzzy where the group hasn't looked recently.

const Sprites := preload("res://render/sprites.gd")
const Geo := preload("res://core/geo.gd")

const TILE: float = 64.0
const DOT_PX: float = 30.0
const BODY_PX: float = 34.0

var particles: bool = true:
	set(value):
		particles = value
		for fire: Node2D in _fires.values():
			var smoke: GPUParticles2D = fire.get_node_or_null("Smoke")
			if smoke != null:
				smoke.emitting = value
var lights: bool = true:
	set(value):
		lights = value
		for fire: Node2D in _fires.values():
			var light: PointLight2D = fire.get_node_or_null("Light")
			if light != null:
				light.visible = value
var shadows: bool = true
var reduce_motion: bool = false
var show_dots: bool = true

var _config: Dictionary
var _time: float = 0.0
var _fires: Dictionary = {}  # "x,y" -> Node2D
var _bodies: Array = []  # [{pos: Vector2 (px), tick: int}]
var _dot_tex: Texture2D
var _body_tex: Texture2D


func _ready() -> void:
	_config = Data.table("render")
	_dot_tex = Sprites.get_texture("tok_infected")
	_body_tex = Sprites.get_texture("tok_body")


func _process(delta: float) -> void:
	if not reduce_motion:
		_time += delta
	queue_redraw()


## Re-reads bodies and fires from the event log (which survives save and load).
func refresh() -> void:
	var now: int = WorldState.tick
	var body_ticks: int = roundi(float(_config["body_mark_days"]) * WorldState.TICKS_PER_DAY)
	var fire_ticks: int = roundi(float(_config["fire_smoke_hours"]) * 6.0)
	_bodies.clear()
	var burning: Dictionary = {}
	for entry: Dictionary in EventBus.event_log:
		var age: int = now - int(entry["tick"])
		var payload: Dictionary = entry["payload"]
		if entry["name"] in [&"survivor_died", &"survivor_turned"] and age < body_ticks and payload.has("x_m"):
			_bodies.append({"pos": _px(Vector2(float(payload["x_m"]), float(payload["y_m"]))), "tick": int(entry["tick"])})
		elif entry["name"] == &"story_event" and payload.get("id", "") == "market_fire" and age < fire_ticks and payload.has("x_m"):
			burning["%d,%d" % [roundi(float(payload["x_m"])), roundi(float(payload["y_m"]))]] = _px(Vector2(float(payload["x_m"]), float(payload["y_m"])))
	for key: String in _fires.keys():
		if not burning.has(key):
			_fires[key].queue_free()
			_fires.erase(key)
	for key: String in burning:
		if not _fires.has(key):
			_fires[key] = _make_fire(burning[key])
			add_child(_fires[key])


static func _px(pos_m: Vector2) -> Vector2:
	return pos_m / Geo.tile_m() * TILE


@warning_ignore("integer_division")
func _draw() -> void:
	for body: Dictionary in _bodies:
		var p: Vector2 = body["pos"]
		if _body_tex != null:
			draw_texture_rect(_body_tex, Rect2(p - Vector2(BODY_PX, BODY_PX) / 2.0, Vector2(BODY_PX, BODY_PX)), false, Color(0.75, 0.75, 0.75, 0.9))
		else:
			draw_circle(p, 9.0, Color(0.1, 0.08, 0.08, 0.8))
	if not show_dots:
		return
	var per_dot: float = float(_config["infected_per_dot"])
	var max_dots: int = int(_config["infected_max_dots_per_zone"])
	var zone_px: float = float(WorldState.town.get("zone_size_tiles", 16)) * TILE
	var base: Vector2 = _px(Geo.base_center_m()) if not WorldState.base.is_empty() else Vector2(-1, -1)
	var pull: float = clampf(float(WorldState.base.get("attention", 0.0)) / 200.0, 0.0, 1.0)
	for z: int in WorldState.zones.size():
		var count: float = float(WorldState.zones[z]["infected"])
		var dots: int = mini(max_dots, ceili(count / per_dot))
		var corner: Vector2 = Vector2(float(z % Geo.ZONE_COLS), float(z / Geo.ZONE_COLS)) * zone_px
		for i: int in dots:
			# Each dot has a fixed home in its zone, clustered in a few groups.
			var group: int = i % 4
			var gx: float = _hash01(z * 31 + group * 7) * 0.7 + 0.15
			var gy: float = _hash01(z * 17 + group * 13 + 5) * 0.7 + 0.15
			var home: Vector2 = corner + Vector2(gx, gy) * zone_px + Vector2(_hash01(i * 3 + z) - 0.5, _hash01(i * 7 + z * 3) - 0.5) * zone_px * 0.22
			var wander: Vector2 = Vector2(sin(_time * 0.21 + i * 1.7), cos(_time * 0.17 + i * 2.3)) * 14.0
			var lean: Vector2 = Vector2.ZERO
			if base.x >= 0.0 and pull > 0.0:
				lean = (base - home).limit_length(zone_px * 0.35 * pull)
			var p: Vector2 = home + wander + lean
			if _dot_tex != null:
				draw_texture_rect(_dot_tex, Rect2(p - Vector2(DOT_PX, DOT_PX) / 2.0, Vector2(DOT_PX, DOT_PX)), false)
			else:
				draw_circle(p, 7.0, Color(0.85, 0.25, 0.22))


static func _hash01(n: int) -> float:
	var h: int = (n * 2654435761) & 0xffffffff
	h = ((h >> 13) ^ h) * 1274126177 & 0xffffffff
	return float(h % 10000) / 10000.0


func _make_fire(pos: Vector2) -> Node2D:
	var fire: Node2D = Node2D.new()
	fire.position = pos
	var tex: Texture2D = Sprites.get_texture("map_fire")
	if tex != null:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		var s: float = TILE * 2.0 / float(tex.get_width())
		sprite.scale = Vector2(s, s)
		fire.add_child(sprite)
	var smoke: GPUParticles2D = GPUParticles2D.new()
	smoke.name = "Smoke"
	smoke.amount = 60
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.texture = _soft_dot()
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	var wind: Array = _config["wind_px_s"]
	mat.direction = Vector3(float(wind[0]) * 0.3, -1.0, 0.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 45.0
	mat.gravity = Vector3(float(wind[0]), float(wind[1]) - 6.0, 0.0)
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.25, 0.23, 0.22, 0.55))
	ramp.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	var ramp_tex: GradientTexture1D = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.2))
	var grow_tex: CurveTexture = CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	smoke.process_material = mat
	smoke.emitting = particles
	smoke.z_index = 5
	fire.add_child(smoke)
	var light: PointLight2D = PointLight2D.new()
	light.name = "Light"
	light.texture = light_texture()
	light.texture_scale = 6.0
	light.color = Color(1.0, 0.6, 0.25)
	light.energy = 1.3
	light.shadow_enabled = shadows
	light.visible = lights
	fire.add_child(light)
	return fire


static var _dot: Texture2D
static var _light: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g: GradientTexture2D = GradientTexture2D.new()
		g.width = 32
		g.height = 32
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad: Gradient = Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		_dot = g
	return _dot


## A soft radial light, used by every PointLight2D.
static func light_texture() -> Texture2D:
	if _light == null:
		var g: GradientTexture2D = GradientTexture2D.new()
		g.width = 128
		g.height = 128
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad: Gradient = Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		g.gradient = grad
		_light = g
	return _light
