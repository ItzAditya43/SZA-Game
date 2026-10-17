extends Control
## The 64 x 64 town map: terrain, buildings coloured by type, the base, the
## selected building, survivors out on trips and infected per zone. Click a
## building to select it; hover for its name.

const UiState := preload("res://ui/ui_state.gd")
const Geo := preload("res://core/geo.gd")

const TILE_PX: int = 10
const TERRAIN_COLORS: Dictionary = {
	".": Color("2a2d27"), "=": Color("58544c"), "~": Color("2c5d86"), ":": Color("4b463d"), ",": Color("2f3b26"),
}
const BASE_COLOR: Color = Color("3fd18b")
const SELECTED_COLOR: Color = Color("ffd34d")
const SURVIVOR_COLOR: Color = Color("7fd3ff")
const INFECTED_COLOR: Color = Color("e24b4a")
## Zone tint is fully opaque at this many infected per zone.
const INFECTED_TINT_FULL: float = 2500.0
const NIGHT_TINT: Color = Color(0.03, 0.05, 0.12, 0.35)

var ui_state: UiState
var show_infected: bool = true
var _terrain: ImageTexture
var _redraw_pending: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	EventBus.event.connect(_on_bus_event)
	if ui_state != null:
		ui_state.building_selected.connect(func(_id: String) -> void: queue_redraw())
	_build_terrain()


func _get_minimum_size() -> Vector2:
	var width: int = int(WorldState.town.get("width", 64))
	var height: int = int(WorldState.town.get("height", 64))
	return Vector2(width * TILE_PX, height * TILE_PX)


func _on_bus_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == &"run_started":
		_build_terrain()
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
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	if _terrain == null:
		return
	var size_px: Vector2 = _get_minimum_size()
	draw_texture_rect(_terrain, Rect2(Vector2.ZERO, size_px), false)
	if show_infected:
		_draw_zones()
	_draw_buildings()
	_draw_landmarks()
	_draw_survivors()
	if WorldState.phase() == WorldState.PHASE_NIGHT:
		draw_rect(Rect2(Vector2.ZERO, size_px), NIGHT_TINT)


func _draw_zones() -> void:
	var font: Font = get_theme_default_font()
	var zone_px: float = float(WorldState.town.get("zone_size_tiles", 16)) * TILE_PX
	for i: int in WorldState.zones.size():
		var zone: Dictionary = WorldState.zones[i]
		var count: float = float(zone["infected"])
		var rect: Rect2 = Rect2(float(i % Geo.ZONE_COLS) * zone_px, float(i / Geo.ZONE_COLS) * zone_px, zone_px, zone_px)
		var tint: Color = INFECTED_COLOR
		tint.a = clampf(count / INFECTED_TINT_FULL, 0.0, 1.0) * 0.45
		draw_rect(rect, tint)
		draw_rect(rect, Color(1, 1, 1, 0.08), false, 1.0)
		draw_string(font, rect.position + Vector2(4, 14), "%d" % roundi(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1.0, 0.75, 0.75, 0.9))


func _draw_buildings() -> void:
	var base_id: String = WorldState.base.get("building", "")
	var selected: String = ui_state.selected_building if ui_state != null else ""
	for building: Dictionary in WorldState.buildings:
		var rect: Rect2 = _building_rect(building)
		var color: Color = Color(String(Data.entry("buildings", String(building["type"])).get("color", "#999999")))
		if building["stripped"]:
			color = color.darkened(0.5)
		draw_rect(rect, color)
		draw_rect(rect, color.darkened(0.6), false, 1.0)
		if float(building.get("barricade", 0.0)) > 0.0:
			draw_rect(rect.grow(-2), Color(0.9, 0.7, 0.4, 0.8), false, 1.0)
		if building["id"] == base_id:
			draw_rect(rect.grow(2), BASE_COLOR, false, 3.0)
		if building["id"] == selected:
			draw_rect(rect.grow(3), SELECTED_COLOR, false, 2.0)


func _draw_landmarks() -> void:
	var font: Font = get_theme_default_font()
	for landmark: Dictionary in WorldState.town.get("landmarks", []):
		var pos: Vector2 = Vector2(float(landmark["x"]), float(landmark["y"])) * TILE_PX
		draw_string(font, pos, String(landmark["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))


func _draw_survivors() -> void:
	var font: Font = get_theme_default_font()
	var px_per_m: float = TILE_PX / Geo.tile_m()
	for s: Dictionary in WorldState.survivors:
		if s["status"] != &"ok" or s["location"] != &"away":
			continue
		var pos: Vector2 = Vector2(float(s["x_m"]), float(s["y_m"])) * px_per_m
		draw_circle(pos, 6.0, Color(0, 0, 0, 0.6))
		draw_circle(pos, 4.5, SURVIVOR_COLOR)
		draw_string(font, pos + Vector2(7, 4), String(s["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SURVIVOR_COLOR)


func _building_rect(building: Dictionary) -> Rect2:
	return Rect2(float(building["x"]) * TILE_PX, float(building["y"]) * TILE_PX,
		float(building["w"]) * TILE_PX, float(building["h"]) * TILE_PX)


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var building: Dictionary = Geo.building_at_tile(Vector2i(floori(click.position.x / TILE_PX), floori(click.position.y / TILE_PX)))
	if ui_state != null:
		ui_state.select_building(building.get("id", ""))
	accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var building: Dictionary = Geo.building_at_tile(Vector2i(floori(at_position.x / TILE_PX), floori(at_position.y / TILE_PX)))
	if building.is_empty():
		return ""
	return "%s (%s)" % [building["name"], Data.entry("buildings", String(building["type"]))["name"]]
