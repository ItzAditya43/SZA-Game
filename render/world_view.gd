extends SubViewportContainer
## The town as a 2D world: ground tiles, buildings, the infected, fires and the
## fog of knowledge, lit by the time of day, with weather, under a camera you
## can pan (drag, WASD) and zoom (mouse wheel). The group's tokens sit on a layer
## above the night tint so they always read.
##
## A reader only (CLAUDE.md rule 10): it reads WorldState and listens to the
## EventBus. ui/map_grid.gd sits on top for clicks, tooltips, overlays and the
## legend, and asks this view where things are on screen.

const Sprites := preload("res://render/sprites.gd")
const Geo := preload("res://core/geo.gd")
const Settings := preload("res://ui/settings.gd")
const Infrastructure := preload("res://systems/infrastructure.gd")
const GroundLayer := preload("res://render/ground_layer.gd")
const BuildingsLayer := preload("res://render/buildings_layer.gd")
const ActorsLayer := preload("res://render/actors_layer.gd")
const SurvivorTokens := preload("res://render/survivor_tokens.gd")
const FogLayer := preload("res://render/fog_layer.gd")

signal view_changed

const TILE: float = 64.0
const MAX_ZOOM: float = 2.2
## Below this zoom the map shows simplified blocks and zone tints, no dots or trees.
const LOD_ZOOM: float = 0.12
const PAN_KEYS_PX_S: float = 900.0
const ZOOM_STEP: float = 1.15
const HEAT_SHIMMER_FROM_C: float = 36.0

const SHIMMER: String = """
shader_type canvas_item;
uniform float strength = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 off = vec2(sin(SCREEN_UV.y * 140.0 + TIME * 3.1), cos(SCREEN_UV.x * 110.0 + TIME * 2.3)) * 0.0012 * strength;
	vec4 c = texture(screen_tex, SCREEN_UV + off);
	float grey = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(grey) * 1.06 + 0.05, 0.16 * strength);
	COLOR = c;
}
"""

var viewport: SubViewport
var camera: Camera2D
var ground: GroundLayer
var buildings: BuildingsLayer
var actors: ActorsLayer
var tokens: SurvivorTokens
var fog: FogLayer
## Screenshots and tests can force rain on without a storm in the simulation.
var force_rain: bool = false

var _world: Node2D
var _modulate: CanvasModulate
var _base_light: PointLight2D
var _rain: GPUParticles2D
var _dust: GPUParticles2D
var _shimmer: ColorRect
var _shimmer_material: ShaderMaterial
var _config: Dictionary
var _map_px: Vector2 = Vector2(4096, 4096)
var _min_zoom: float = 0.2
var _target_zoom: float = 1.0
var _fitted: bool = false
var _quality: Dictionary = {}
var _reduce_motion: bool = false
var _raining: bool = false


func _ready() -> void:
	_config = Data.table("render")
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.transparent_bg = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(viewport)
	_world = Node2D.new()
	viewport.add_child(_world)
	ground = GroundLayer.new()
	_world.add_child(ground)
	buildings = BuildingsLayer.new()
	_world.add_child(buildings)
	actors = ActorsLayer.new()
	_world.add_child(actors)
	fog = FogLayer.new()
	_world.add_child(fog)
	_base_light = PointLight2D.new()
	_base_light.texture = ActorsLayer.light_texture()
	_base_light.visible = false
	_world.add_child(_base_light)
	_modulate = CanvasModulate.new()
	_world.add_child(_modulate)
	# Tokens: same camera, but on their own canvas layer, so the night tint skips them.
	var token_layer: CanvasLayer = CanvasLayer.new()
	token_layer.layer = 1
	token_layer.follow_viewport_enabled = true
	viewport.add_child(token_layer)
	tokens = SurvivorTokens.new()
	token_layer.add_child(tokens)
	# Screen-space weather and effects.
	var screen: CanvasLayer = CanvasLayer.new()
	screen.layer = 2
	viewport.add_child(screen)
	_shimmer = ColorRect.new()
	_shimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shimmer_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = SHIMMER
	_shimmer_material.shader = shader
	_shimmer.material = _shimmer_material
	_shimmer.visible = false
	screen.add_child(_shimmer)
	_rain = _make_rain()
	screen.add_child(_rain)
	_dust = _make_dust()
	screen.add_child(_dust)
	camera = Camera2D.new()
	camera.position_smoothing_speed = 9.0
	viewport.add_child(camera)
	resized.connect(_on_resized)
	EventBus.event.connect(_on_bus_event)
	Settings.listen(apply_settings)
	apply_settings()
	rebuild()


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	match event_name:
		&"run_started", &"game_loaded":
			rebuild()
		&"tick":
			_on_tick()
		&"base_moved", &"scavenge_started", &"scavenge_returned", &"story_event", &"survivor_died", &"survivor_turned", \
		&"survivor_joined", &"survivor_left", &"base_breached", &"day_started", &"decision_made":
			_refresh_world()


## Rebuilds everything for a new or loaded run.
func rebuild() -> void:
	var rows: Array = WorldState.town.get("rows", [])
	if rows.is_empty():
		return
	_map_px = Vector2(String(rows[0]).length(), rows.size()) * TILE
	ground.build(rows)
	buildings.build()
	_refresh_world()
	tokens.snap()
	_fitted = false
	_on_resized()


func _on_tick() -> void:
	tokens.refresh()
	if WorldState.tick % 3 == 0:
		fog.refresh()
	if WorldState.tick % 6 == 0:
		buildings.refresh()
		actors.refresh()
	_update_light_and_weather()


func _refresh_world() -> void:
	buildings.refresh()
	actors.refresh()
	tokens.refresh()
	fog.refresh()
	_update_light_and_weather()


# --- Camera ---

func _on_resized() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_min_zoom = minf(size.x / _map_px.x, size.y / _map_px.y) * 0.9
	(_rain.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size.x * 0.6, 10, 1)
	_rain.position = Vector2(size.x / 2.0, -20)
	(_dust.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size.x / 2.0, size.y / 2.0, 1)
	_dust.position = size / 2.0
	if not _fitted:
		fit()
	else:
		_set_zoom(camera.zoom.x)


## Shows the whole town.
func fit() -> void:
	_fitted = true
	_target_zoom = _min_zoom / 0.9
	camera.zoom = Vector2(_target_zoom, _target_zoom)
	camera.position = _map_px / 2.0
	camera.reset_smoothing()
	_after_camera_move()


func tile_px() -> float:
	return TILE * camera.zoom.x


## Screen position (in this control) of a world pixel.
func world_to_view(p: Vector2) -> Vector2:
	return viewport.canvas_transform * p


func view_to_world(p: Vector2) -> Vector2:
	return viewport.canvas_transform.affine_inverse() * p


## Zooms by `factor`, keeping the world point under `at` (view coordinates) still.
func zoom_at(factor: float, at: Vector2) -> void:
	var before: Vector2 = view_to_world(at)
	_set_zoom(camera.zoom.x * factor)
	camera.force_update_scroll()
	var after: Vector2 = view_to_world(at)
	camera.position += before - after
	_clamp_camera()
	camera.reset_smoothing()
	_after_camera_move()


func pan(view_delta: Vector2) -> void:
	camera.position -= view_delta / camera.zoom.x
	_clamp_camera()
	camera.reset_smoothing()
	_after_camera_move()


## Centres the camera on a spot in town (metres), e.g. a clicked log line.
func look_at_m(pos_m: Vector2) -> void:
	camera.position = pos_m / Geo.tile_m() * TILE
	_clamp_camera()
	if _reduce_motion:
		camera.reset_smoothing()
	_after_camera_move()


func _set_zoom(z: float) -> void:
	z = clampf(z, _min_zoom, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	_clamp_camera()


func _clamp_camera() -> void:
	var half: Vector2 = size / camera.zoom.x / 2.0
	var lo: Vector2 = Vector2(minf(half.x, _map_px.x / 2.0), minf(half.y, _map_px.y / 2.0))
	var hi: Vector2 = Vector2(maxf(_map_px.x - half.x, _map_px.x / 2.0), maxf(_map_px.y - half.y, _map_px.y / 2.0))
	camera.position = camera.position.clamp(lo, hi)


func _after_camera_move() -> void:
	var far: bool = camera.zoom.x < LOD_ZOOM
	buildings.simple = far
	actors.show_dots = not far
	# Tokens keep roughly the same on-screen size, a little bigger when zoomed in.
	tokens.token_scale = clampf(0.75 / camera.zoom.x, 0.6, 2.4)
	view_changed.emit()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _typing():
		return
	var move: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_CTRL):
		return
	if Input.is_physical_key_pressed(KEY_W):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if move != Vector2.ZERO:
		pan(-move.normalized() * PAN_KEYS_PX_S * delta)


func _typing() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or get_tree().get_nodes_in_group("modal").any(
		func(n: Node) -> bool: return (n as CanvasItem).visible)


# --- Light, time of day, weather ---

func _update_light_and_weather() -> void:
	var minute: int = WorldState.minute_of_day()
	var color: Color = day_color(minute)
	_raining = force_rain or _storm_recent()
	if _raining:
		color = color.darkened(0.22).lerp(Color(0.55, 0.62, 0.75), 0.15)
	_modulate.color = color
	var days: float = float(WorldState.tick) / WorldState.TICKS_PER_DAY
	ground.set_weather(clampf(days / float(_config["weeds_full_day"]), 0.0, 1.0), 1.0 if _raining else 0.0)
	_rain.emitting = _raining and bool(_quality.get("particles", true))
	_rain.visible = _raining
	var night: bool = WorldState.phase() == WorldState.PHASE_NIGHT
	_dust.emitting = not night and not _raining and bool(_quality.get("particles", true)) and not _reduce_motion
	# Heat shimmer and bleaching in the hottest hours.
	var temp: float = float(WorldState.climate.get("temperature_c", 30.0))
	var hot: float = clampf((temp - HEAT_SHIMMER_FROM_C) / 4.0, 0.0, 1.0) if minute >= 660 and minute < 960 else 0.0
	_shimmer.visible = hot > 0.0 and bool(_quality.get("screen_effects", true)) and not _reduce_motion
	_shimmer_material.set_shader_parameter("strength", hot)
	# What the base gives away at night: lamps, a cooking fire, the generator.
	_update_base_light(night)


func _update_base_light(night: bool) -> void:
	var b: Dictionary = WorldState.building(String(WorldState.base.get("building", "")))
	var people: int = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base").size()
	if b.is_empty() or not night or people == 0 or not bool(_quality.get("lights", true)):
		_base_light.visible = false
		return
	_base_light.visible = true
	_base_light.position = Geo.building_center_m(b) / Geo.tile_m() * TILE
	_base_light.shadow_enabled = bool(_quality.get("shadows", true))
	if WorldState.infrastructure.get("generator_running", false):
		# Electric light, seen from about LIGHT_VISIBLE_M away.
		_base_light.color = Color(1.0, 0.95, 0.8)
		_base_light.energy = 1.4
		_base_light.texture_scale = Infrastructure.LIGHT_VISIBLE_M / Geo.tile_m() * TILE / 128.0 * 0.5
	else:
		var cooking: bool = WorldState.group().any(func(s: Dictionary) -> bool: return s["location"] == &"base" and s["job_now"] == &"cook")
		_base_light.color = Color(1.0, 0.62, 0.3)
		_base_light.energy = 1.1
		_base_light.texture_scale = (6.0 if cooking else 3.5)
	# LATER: blackout curtains (when buildable) shrink this light.


func _storm_recent() -> bool:
	var hours: float = float(_config["rain_hours_after_storm"])
	for i: int in range(EventBus.event_log.size() - 1, -1, -1):
		var entry: Dictionary = EventBus.event_log[i]
		if WorldState.tick - int(entry["tick"]) > roundi(hours * 6.0):
			return false
		if entry["name"] == &"story_event" and entry["payload"].get("id", "") == "storm":
			return true
	return false


## LATER: low fog at dawn in the cool season (Prototype 2 has seasons).
func _winter_fog() -> void:
	pass


## LATER: Prototype 2 floods. Raise the canal and low ground to this level (metres).
func set_water_level(_level_m: float) -> void:
	pass


func day_color(minute: int) -> Color:
	var stops: Array = _config["day_colors"]
	for i: int in range(1, stops.size()):
		var a: Dictionary = stops[i - 1]
		var b: Dictionary = stops[i]
		if minute <= int(b["minute"]):
			var t: float = float(minute - int(a["minute"])) / maxf(1.0, float(int(b["minute"]) - int(a["minute"])))
			return Color(String(a["color"])).lerp(Color(String(b["color"])), t)
	return Color(String(stops[-1]["color"]))


func apply_settings() -> void:
	_quality = {}
	for key: String in Settings.GRAPHICS_TOGGLES:
		_quality[key] = Settings.graphics(key)
	_reduce_motion = Settings.reduce_motion()
	camera.position_smoothing_enabled = not _reduce_motion
	actors.lights = _quality["lights"]
	actors.particles = _quality["particles"]
	actors.shadows = _quality["shadows"]
	actors.reduce_motion = _reduce_motion
	tokens.reduce_motion = _reduce_motion
	buildings.shadows = _quality["shadows"]
	_rain.amount = 900 if _quality["screen_effects"] else 450
	if WorldState.town.has("rows"):
		_update_light_and_weather()


func _make_rain() -> GPUParticles2D:
	var rain: GPUParticles2D = GPUParticles2D.new()
	rain.amount = 900
	rain.lifetime = 1.1
	rain.preprocess = 1.0
	var streak: GradientTexture2D = GradientTexture2D.new()
	streak.width = 2
	streak.height = 18
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(0.75, 0.82, 0.95, 0.0), Color(0.75, 0.82, 0.95, 0.55)])
	streak.gradient = grad
	rain.texture = streak
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(800, 10, 1)
	mat.direction = Vector3(0.18, 1, 0)
	mat.spread = 2.0
	mat.initial_velocity_min = 900.0
	mat.initial_velocity_max = 1100.0
	mat.gravity = Vector3.ZERO
	rain.process_material = mat
	rain.emitting = false
	rain.visible = false
	return rain


func _make_dust() -> GPUParticles2D:
	var dust: GPUParticles2D = GPUParticles2D.new()
	dust.amount = 16
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.texture = ActorsLayer._soft_dot()
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(800, 450, 1)
	var wind: Array = _config["wind_px_s"]
	mat.direction = Vector3(float(wind[0]), float(wind[1]), 0).normalized()
	mat.spread = 20.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 28.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.12
	mat.scale_max = 0.3
	mat.color = Color(0.7, 0.6, 0.42, 0.22)
	dust.process_material = mat
	return dust
