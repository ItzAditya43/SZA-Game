extends Control
## The town map, scaled to fill its space: terrain, buildings coloured by type,
## your base, survivors out on trips with their route, and one overlay at a time
## (infected, noise, light at night, smell, attention, disease risk) with a legend.
## Hover a building for what you know about it; click to select it.

const UiState := preload("res://ui/ui_state.gd")
const Geo := preload("res://core/geo.gd")
const Tokens := preload("res://ui/theme/tokens.gd")
const Insight := preload("res://core/insight.gd")
const Stores := preload("res://core/stores.gd")
const Infrastructure := preload("res://systems/infrastructure.gd")

const TERRAIN_COLORS: Dictionary = {
	".": Color("2a2d27"), "=": Color("4f4b44"), "~": Color("2c5d86"), ":": Color("45413a"), ",": Color("2f3b26"),
}
const OVERLAYS: Array[String] = ["infected", "noise", "light", "smell", "attention", "disease", "none"]
const OVERLAY_NAMES: Dictionary = {"infected": "Infected", "noise": "Noise", "light": "Light at night", "smell": "Smell and wind",
	"attention": "Attention", "disease": "Disease risk", "none": "Plain map"}
## Infected tint is strongest at this many per zone.
const INFECTED_TINT_FULL: float = 2500.0
const NIGHT_TINT: Color = Color(0.03, 0.05, 0.12, 0.32)
const NOISE_FADE_TICKS: int = 12
const PULSE_SECONDS: float = 3.0

var ui_state: UiState
var overlay: String = "infected"
var _terrain: ImageTexture
var _noises: Array = []  # [{"pos": Vector2 (m), "radius": float, "tick": int, "source": StringName}]
var _pulse: Vector2 = Vector2(-1, -1)
var _pulse_left: float = 0.0
var _hover: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320, 320)
	clip_contents = true
	tooltip_text = " "
	EventBus.event.connect(_on_bus_event)
	if ui_state != null:
		ui_state.building_selected.connect(func(_id: String) -> void: queue_redraw())
	_build_terrain()


func _process(delta: float) -> void:
	if _pulse_left > 0.0:
		_pulse_left -= delta
		queue_redraw()


func set_overlay(name: String) -> void:
	overlay = name
	queue_redraw()


## Flashes a ring at a spot in town (metres), e.g. when a log line is clicked.
func pulse_at(pos_m: Vector2) -> void:
	_pulse = pos_m
	_pulse_left = PULSE_SECONDS
	queue_redraw()


func _on_bus_event(event_name: StringName, payload: Dictionary) -> void:
	match event_name:
		&"run_started", &"game_loaded":
			_noises.clear()
			_build_terrain()
		&"noise":
			_noises.append({"pos": Vector2(float(payload["x_m"]), float(payload["y_m"])), "radius": float(payload["radius_m"]),
				"tick": WorldState.tick, "source": payload.get("source", &"noise")})
			if _noises.size() > 40:
				_noises.pop_front()
	queue_redraw()


func _build_terrain() -> void:
	var rows: Array = WorldState.town.get("rows", [])
	if rows.is_empty():
		_terrain = null
		return
	var image: Image = Image.create(String(rows[0]).length(), rows.size(), false, Image.FORMAT_RGB8)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			image.set_pixel(x, y, TERRAIN_COLORS.get(row[x], Color.BLACK))
	_terrain = ImageTexture.create_from_image(image)
	queue_redraw()


# --- Geometry: the map is square, centred in the control ---

func tile_px() -> float:
	var tiles: float = float(WorldState.town.get("width", 64))
	return floorf(minf(size.x, size.y) / tiles * 4.0) / 4.0


## Left-aligned, so the building card has room on the right of wide screens.
func map_origin() -> Vector2:
	var span: float = tile_px() * float(WorldState.town.get("width", 64))
	return Vector2(Tokens.SPACE_S, floorf((size.y - span) / 2.0))


func to_screen(pos_m: Vector2) -> Vector2:
	return map_origin() + pos_m / Geo.tile_m() * tile_px()


func to_tile(screen: Vector2) -> Vector2i:
	var local: Vector2 = (screen - map_origin()) / tile_px()
	return Vector2i(floori(local.x), floori(local.y))


func _building_rect(b: Dictionary) -> Rect2:
	var t: float = tile_px()
	return Rect2(map_origin() + Vector2(float(b["x"]), float(b["y"])) * t, Vector2(float(b["w"]), float(b["h"])) * t)


# --- Drawing ---

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.BG_APP)
	if _terrain == null:
		return
	var t: float = tile_px()
	var span: float = t * float(WorldState.town.get("width", 64))
	draw_texture_rect(_terrain, Rect2(map_origin(), Vector2(span, span)), false)
	if overlay == "infected":
		_draw_infected()
	_draw_buildings()
	match overlay:
		"noise":
			_draw_noise()
		"light":
			_draw_light()
		"smell":
			_draw_smell()
		"attention":
			_draw_attention()
		"disease":
			_draw_disease()
	_draw_landmarks()
	if overlay == "infected":
		_draw_infected_labels()
	_draw_survivors()
	if WorldState.phase() == WorldState.PHASE_NIGHT:
		draw_rect(Rect2(map_origin(), Vector2(span, span)), NIGHT_TINT)
	if _pulse_left > 0.0:
		var p: Vector2 = to_screen(_pulse)
		var phase: float = fmod(_pulse_left, 1.0)
		draw_arc(p, 10.0 + (1.0 - phase) * 30.0, 0.0, TAU, 40, Color(Tokens.ACCENT, phase), 3.0)
		draw_circle(p, 5.0, Tokens.ACCENT)
	_draw_legend()


@warning_ignore("integer_division")
func _draw_infected() -> void:
	var zone_px: float = float(WorldState.town.get("zone_size_tiles", 16)) * tile_px()
	for i: int in WorldState.zones.size():
		var count: float = float(WorldState.zones[i]["infected"])
		var rect: Rect2 = Rect2(map_origin() + Vector2(float(i % Geo.ZONE_COLS), float(i / Geo.ZONE_COLS)) * zone_px, Vector2(zone_px, zone_px))
		draw_rect(rect, Color(Tokens.INFECTED, clampf(count / INFECTED_TINT_FULL, 0.0, 1.0) * 0.42))
		draw_rect(rect, Color(1, 1, 1, 0.07), false, 1.0)


## Zone counts go on top of the buildings, on a dark plate so they stay readable.
@warning_ignore("integer_division")
func _draw_infected_labels() -> void:
	var font: Font = get_theme_default_font()
	var zone_px: float = float(WorldState.town.get("zone_size_tiles", 16)) * tile_px()
	for i: int in WorldState.zones.size():
		var corner: Vector2 = map_origin() + Vector2(float(i % Geo.ZONE_COLS), float(i / Geo.ZONE_COLS)) * zone_px
		var label: String = "%d infected" % roundi(float(WorldState.zones[i]["infected"]))
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL).x
		draw_rect(Rect2(corner + Vector2(2, 2), Vector2(width + 8, Tokens.FONT_SMALL + 6)), Color(Tokens.BG_APP, 0.8))
		draw_string(font, corner + Vector2(6, Tokens.FONT_SMALL + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Color(1, 0.8, 0.78))


func _draw_buildings() -> void:
	var base_id: String = WorldState.base.get("building", "")
	var selected: String = ui_state.selected_building if ui_state != null else ""
	for b: Dictionary in WorldState.buildings:
		var rect: Rect2 = _building_rect(b)
		var color: Color = Color(String(Data.entry("buildings", String(b["type"])).get("color", "#999999")))
		if b.get("burned", false):
			color = Color("2b2523")
		elif b["stripped"]:
			color = color.darkened(0.5)
		draw_rect(rect, color)
		draw_rect(rect, color.darkened(0.6), false, 1.0)
		if float(b.get("barricade", 0.0)) > 0.0:
			draw_rect(rect.grow(-2), Color(0.95, 0.75, 0.45, 0.9), false, 1.5)
		if b["id"] == _hover:
			draw_rect(rect.grow(1), Color(1, 1, 1, 0.6), false, 1.5)
		if b["id"] == base_id:
			draw_rect(rect.grow(3), Tokens.GROUP, false, 3.0)
			draw_string(get_theme_default_font(), rect.position + Vector2(0, -5), "BASE", HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Tokens.GROUP)
		if b["id"] == selected:
			draw_rect(rect.grow(5), Tokens.ACCENT, false, 2.0)


func _draw_landmarks() -> void:
	var font: Font = get_theme_default_font()
	for landmark: Dictionary in WorldState.town.get("landmarks", []):
		var pos: Vector2 = map_origin() + Vector2(float(landmark["x"]), float(landmark["y"])) * tile_px()
		draw_string(font, pos, String(landmark["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Color(1, 1, 1, 0.5))


func _draw_survivors() -> void:
	var font: Font = get_theme_default_font()
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok" or s["location"] != &"away":
			continue
		var pos: Vector2 = to_screen(Vector2(float(s["x_m"]), float(s["y_m"])))
		var trip: Dictionary = s["trip"]
		if trip.has("dest") and trip.get("leg", &"") == &"out":
			draw_dashed_line(pos, to_screen(trip["dest"]), Color(Tokens.GROUP, 0.7), 1.5, 6.0)
		elif trip.has("origin") and trip.get("leg", &"") == &"back":
			draw_dashed_line(pos, to_screen(trip["origin"]), Color(Tokens.GROUP, 0.7), 1.5, 6.0)
		draw_circle(pos, 9.0, Color(0, 0, 0, 0.7))
		draw_circle(pos, 7.0, Tokens.GROUP)
		draw_string(font, pos + Vector2(-4, 5), String(s["name"]).left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Tokens.TEXT_ON_ACCENT)
		draw_string(font, pos + Vector2(11, 5), String(s["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Tokens.GROUP)


func _px(metres: float) -> float:
	return metres / Geo.tile_m() * tile_px()


func _draw_noise() -> void:
	for n: Dictionary in _noises:
		var age: int = WorldState.tick - int(n["tick"])
		if age > NOISE_FADE_TICKS:
			continue
		var fade: float = 1.0 - float(age) / NOISE_FADE_TICKS
		var color: Color = Color(Tokens.NOISE, 0.15 + 0.6 * fade)
		draw_arc(to_screen(n["pos"]), _px(float(n["radius"])), 0.0, TAU, 64, color, 2.0)
	var base: Vector2 = Geo.base_center_m()
	if WorldState.infrastructure.get("generator_running", false):
		draw_arc(to_screen(base), _px(Infrastructure.GENERATOR_NOISE_M), 0.0, TAU, 48, Color(Tokens.NOISE, 0.8), 2.0)


func _draw_light() -> void:
	var base: Vector2 = Geo.base_center_m()
	var lit: bool = WorldState.infrastructure.get("generator_running", false)
	var cooking: bool = WorldState.group().any(func(s: Dictionary) -> bool: return s["location"] == &"base" and s["job_now"] == &"cook" and s["activity"] == &"light_work")
	if lit:
		draw_circle(to_screen(base), _px(Infrastructure.LIGHT_VISIBLE_M), Color(Tokens.LIGHT, 0.14))
	if cooking:
		draw_circle(to_screen(base), _px(300.0), Color(Tokens.LIGHT, 0.12))


func _draw_smell() -> void:
	var base: Vector2 = Geo.base_center_m()
	var people: int = WorldState.group().filter(func(s: Dictionary) -> bool: return s["location"] == &"base").size()
	var radius: float = 60.0 + 25.0 * people
	if WorldState.group().any(func(s: Dictionary) -> bool: return s["job_now"] == &"cook"):
		radius += 120.0
	radius += 80.0 * WorldState.base.get("bodies", []).size()
	draw_circle(to_screen(base), _px(radius), Color(Tokens.SMELL, 0.18))
	draw_arc(to_screen(base), _px(radius), 0.0, TAU, 48, Color(Tokens.SMELL, 0.6), 1.5)


func _draw_attention() -> void:
	var font: Font = get_theme_default_font()
	for site: String in WorldState.attention:
		var b: Dictionary = WorldState.building(site)
		if b.is_empty():
			continue
		var value: float = float(WorldState.attention[site])
		var pos: Vector2 = to_screen(Geo.building_center_m(b))
		draw_circle(pos, 8.0 + sqrt(value) * 3.0, Color(Tokens.NOISE, 0.22))
		draw_string(font, pos + Vector2(10, -10), "%d" % roundi(value), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, Tokens.NOISE)


func _draw_disease() -> void:
	var t: float = tile_px()
	var rows: Array = WorldState.town.get("rows", [])
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == "~":
				draw_rect(Rect2(map_origin() + Vector2(x, y) * t, Vector2(t, t)), Color(Tokens.DISEASE, 0.35))
	for b: Dictionary in WorldState.buildings:
		if float(b["tank_l"]) > 50.0 and not WorldState.infrastructure.get("mains_on", false):
			draw_circle(to_screen(Geo.building_center_m(b)), 4.0, Color(Tokens.DISEASE, 0.9))


func _draw_legend() -> void:
	var lines: Array = {
		"infected": [["Red tint and number: infected per 500 m zone", Tokens.INFECTED]],
		"noise": [["Rings: recent noises, sized by how far they carry", Tokens.NOISE], ["Gunshot 600 m · generator 150 m · door 50 m", Tokens.TEXT_MUTED]],
		"light": [["Glow: light seen at night (generator ~1 km, fires ~300 m)", Tokens.LIGHT]],
		"smell": [["Patch: smell from the base (people, latrine, cooking, bodies)", Tokens.SMELL], ["Wind: calm (no wind yet in this version)", Tokens.TEXT_MUTED]],
		"attention": [["Circles: attention at sites you've used", Tokens.NOISE], ["High attention draws infected and night attacks", Tokens.TEXT_MUTED]],
		"disease": [["Purple: water that must be boiled (canal, roof tanks)", Tokens.DISEASE]],
		"none": [],
	}[overlay]
	lines = lines + [["Blue outline: base · yellow: selected · blue dots: people out", Tokens.TEXT_MUTED]]
	var font: Font = get_theme_default_font()
	var h: float = Tokens.FONT_SMALL + 6.0
	var box: Rect2 = Rect2(Vector2(8, size.y - 8 - h * lines.size() - 8), Vector2(390, h * lines.size() + 8))
	draw_rect(box, Color(Tokens.BG_PANEL, 0.88))
	for i: int in lines.size():
		draw_string(font, box.position + Vector2(8, 4 + h * (i + 1) - 6), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SMALL, lines[i][1])


# --- Input ---

func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		var hovered: String = Geo.building_at_tile(to_tile(motion.position)).get("id", "")
		if hovered != _hover:
			_hover = hovered
			queue_redraw()
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var building: Dictionary = Geo.building_at_tile(to_tile(click.position))
	if ui_state != null:
		ui_state.select_building(building.get("id", ""))
	accept_event()


func _make_custom_tooltip(_for_text: String) -> Object:
	var b: Dictionary = WorldState.building(_hover)
	if b.is_empty():
		return null
	var box: VBoxContainer = VBoxContainer.new()
	var title: Label = Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.text = b["name"]
	box.add_child(title)
	var type: Dictionary = Data.entry("buildings", String(b["type"]))
	var info: Label = Label.new()
	info.theme_type_variation = "MutedLabel"
	var loot_kg: float = 0.0
	for item: String in Stores.snapshot(b["loot"]):
		loot_kg += Stores.weight_kg(item, Stores.total(b["loot"], item))
	info.text = "%s · danger %s · %s\nAbout %s kg of supplies inside%s\nClick to inspect, scavenge or move in." % [type["name"],
		Insight.danger_word(float(b["danger"])), Insight.last_visit_text(b), Insight.thousands(loot_kg),
		" (stripped)" if b["stripped"] else ""]
	box.add_child(info)
	return box
