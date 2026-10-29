extends Sprite2D
## The fog of knowledge, one cell per tile: never-seen ground is dark, ground
## seen a while ago is washed grey (more the older it is), and what the group can
## see now (round the base and round anyone out) is clear.
##
## Built from WorldState alone, so it needs no saved state of its own: the base
## and survivors' positions are "now", buildings the group has searched (their
## last_visit_tick) and the streets between them and the base are "seen then".
## LATER (prompt 4): replace with PlayerKnowledge's observed-at times.

const Geo := preload("res://core/geo.gd")

const TILE: float = 64.0
const NEVER: Color = Color(0.03, 0.04, 0.06, 0.42)
## Grey wash for stale knowledge, reached after this many days.
const STALE_FULL_DAYS: float = 6.0
const STALE: Color = Color(0.35, 0.36, 0.38, 0.3)
## The start house's street is known from day 0.
const HOME_KNOWN_M: float = 400.0

var _config: Dictionary
var _image: Image
var _texture: ImageTexture
var _seen: PackedInt32Array  # last tick each tile was seen, -1 never


func _ready() -> void:
	_config = Data.table("render")
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = 20


func refresh() -> void:
	var w: int = int(WorldState.town.get("width", 64))
	var h: int = int(WorldState.town.get("height", 64))
	if _image == null or _image.get_width() != w:
		_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		_texture = ImageTexture.create_from_image(_image)
		texture = _texture
		scale = Vector2(TILE, TILE)
	_seen = PackedInt32Array()
	_seen.resize(w * h)
	_seen.fill(-1)
	var now: int = WorldState.tick
	var tile_m: float = Geo.tile_m()
	var start: Dictionary = WorldState.building(String(Data.table("scenario")["start_building"]))
	if not start.is_empty():
		_mark(Geo.building_center_m(start), HOME_KNOWN_M, 0, w, h)
	var base: Vector2 = Geo.base_center_m() if not WorldState.base.is_empty() else Vector2(-1, -1)
	for b: Dictionary in WorldState.buildings:
		if not b.has("last_visit_tick"):
			continue
		var when: int = int(b["last_visit_tick"])
		var at: Vector2 = Geo.building_center_m(b)
		_mark(at, float(_config["survivor_view_m"]), when, w, h)
		if base.x >= 0.0:
			# The way there and back, seen on the walk.
			var steps: int = maxi(1, int(base.distance_to(at) / (tile_m * 2.0)))
			for i: int in steps + 1:
				_mark(base.lerp(at, float(i) / steps), 60.0, when, w, h)
	if base.x >= 0.0:
		_mark(base, float(_config["base_view_m"]), now, w, h)
	for s: Dictionary in WorldState.group():
		if s["location"] == &"away":
			_mark(Vector2(float(s["x_m"]), float(s["y_m"])), float(_config["survivor_view_m"]), now, w, h)
	for y: int in h:
		for x: int in w:
			var seen: int = _seen[y * w + x]
			var c: Color
			if seen < 0:
				c = NEVER
			else:
				var days: float = float(now - seen) / WorldState.TICKS_PER_DAY
				c = Color(STALE, STALE.a * clampf(days / STALE_FULL_DAYS, 0.0, 1.0))
			_image.set_pixel(x, y, c)
	_texture.update(_image)


func _mark(center_m: Vector2, radius_m: float, tick: int, w: int, h: int) -> void:
	var tile_m: float = Geo.tile_m()
	var c: Vector2 = center_m / tile_m
	var r: float = radius_m / tile_m
	for y: int in range(maxi(0, floori(c.y - r)), mini(h, ceili(c.y + r) + 1)):
		for x: int in range(maxi(0, floori(c.x - r)), mini(w, ceili(c.x + r) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				var i: int = y * w + x
				_seen[i] = maxi(_seen[i], tick)
