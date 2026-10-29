extends Node2D
## Buildings on their footprints, drawn from the building sprites (bld_<type>),
## with their state on show: boarded when barricaded, a forced door once looted,
## a ruin and scorch marks after a fire, a tarp on a base that has been broken
## into. Each building blocks light (LightOccluder2D). Without art, or when zoomed
## far out, buildings are flat blocks in their type's colour. Also scatters a few
## procedural trees on open ground.

const Sprites := preload("res://render/sprites.gd")
const Stores := preload("res://core/stores.gd")

const TILE: float = 64.0
## Sprites are drawn a little wider than the footprint and sit on its bottom edge,
## since the art shows a sliver of the front wall.
const SPRITE_OVERHANG: float = 1.08
const TREE_SHARE: int = 4  # percent of open tiles

var simple: bool = false:
	set(value):
		if value != simple:
			simple = value
			_refresh_all(true)
var shadows: bool = true:
	set(value):
		shadows = value
		_update_occluders()

var _sprites: Dictionary = {}  # building id -> Sprite2D
var _marks: Dictionary = {}  # building id -> Node2D (decorations)
var _occluders: Dictionary = {}
var _keys: Dictionary = {}  # building id -> state key last drawn
var _trees: Array[Vector2] = []


func _ready() -> void:
	y_sort_enabled = true


func build() -> void:
	for child: Node in get_children():
		child.queue_free()
	_sprites.clear()
	_marks.clear()
	_occluders.clear()
	_keys.clear()
	for b: Dictionary in WorldState.buildings:
		var rect: Rect2 = footprint(b)
		var holder: Node2D = Node2D.new()
		holder.position = Vector2(rect.get_center().x, rect.end.y)
		add_child(holder)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.centered = false
		holder.add_child(sprite)
		_sprites[b["id"]] = sprite
		var marks: Node2D = Node2D.new()
		holder.add_child(marks)
		_marks[b["id"]] = marks
		var occ: LightOccluder2D = LightOccluder2D.new()
		var poly: OccluderPolygon2D = OccluderPolygon2D.new()
		var r: Rect2 = Rect2(rect.position - holder.position, rect.size).grow(-TILE * 0.15)
		poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		occ.occluder = poly
		occ.visible = shadows
		holder.add_child(occ)
		_occluders[b["id"]] = occ
	_scatter_trees()
	_refresh_all(true)
	_update_occluders()
	queue_redraw()


static func footprint(b: Dictionary) -> Rect2:
	return Rect2(Vector2(float(b["x"]), float(b["y"])) * TILE, Vector2(float(b["w"]), float(b["h"])) * TILE)


func refresh() -> void:
	_refresh_all(false)
	_update_occluders()


## Every building blocks light except the base: its lamps and fires are inside it.
func _update_occluders() -> void:
	var base_id: String = WorldState.base.get("building", "")
	for id: String in _occluders:
		(_occluders[id] as LightOccluder2D).visible = shadows and id != base_id


func _refresh_all(force: bool) -> void:
	var base_id: String = WorldState.base.get("building", "")
	var breaches: int = int(WorldState.stats.get("breaches", 0))
	for b: Dictionary in WorldState.buildings:
		var id: String = b["id"]
		if not _sprites.has(id):
			continue
		var looted: bool = _looted_share(b) > 0.5 or b["stripped"]
		var key: String = "%s|%s|%d|%s|%s" % [b.get("burned", false), looted, roundi(float(b["barricade"])),
			id == base_id and breaches > 0, simple]
		if not force and _keys.get(id, "") == key:
			continue
		_keys[id] = key
		_dress(b, looted, id == base_id and breaches > 0)
	queue_redraw()


func _looted_share(b: Dictionary) -> float:
	var start: float = 0.0
	var now: float = 0.0
	for item: String in b["start_loot"]:
		start += Stores.weight_kg(item, float(b["start_loot"][item]))
	for item: String in b["loot"]:
		now += Stores.weight_kg(item, Stores.total(b["loot"], item))
	return 0.0 if start <= 0.0 else 1.0 - now / start


func _dress(b: Dictionary, looted: bool, tarp: bool) -> void:
	var rect: Rect2 = footprint(b)
	var sprite: Sprite2D = _sprites[b["id"]]
	var marks: Node2D = _marks[b["id"]]
	for child: Node in marks.get_children():
		child.queue_free()
	var burned: bool = b.get("burned", false)
	var tex: Texture2D = Sprites.get_texture("map_ruin" if burned else "bld_" + String(b["type"]))
	if simple or tex == null:
		sprite.texture = null
		return
	sprite.texture = tex
	var width: float = rect.size.x * SPRITE_OVERHANG
	var s: float = width / float(tex.get_width())
	sprite.scale = Vector2(s, s)
	var drawn: Vector2 = Vector2(tex.get_width(), tex.get_height()) * s
	sprite.position = Vector2(-drawn.x / 2.0, -drawn.y + TILE * 0.1)
	sprite.modulate = Color(0.8, 0.78, 0.76) if looted and not burned else Color.WHITE
	if burned:
		var scorch: Polygon2D = _ellipse(Vector2(0, -rect.size.y * 0.45), rect.size * 0.6, Color(0.05, 0.04, 0.03, 0.45))
		scorch.z_index = -1
		marks.add_child(scorch)
		return
	if looted:
		# A forced door: a dark gap low on the front wall.
		var door: ColorRect = ColorRect.new()
		door.color = Color(0.06, 0.05, 0.05, 0.9)
		door.size = Vector2(TILE * 0.32, TILE * 0.38)
		door.position = Vector2(-door.size.x / 2.0, -door.size.y - TILE * 0.02)
		marks.add_child(door)
	if float(b["barricade"]) > 0.0:
		var boards: Texture2D = Sprites.get_texture("map_barricade")
		if boards != null:
			var board: Sprite2D = Sprite2D.new()
			board.texture = boards
			var bs: float = TILE * 0.9 / float(boards.get_width())
			board.scale = Vector2(bs, bs)
			board.position = Vector2(0, -boards.get_height() * bs / 2.0 + TILE * 0.05)
			marks.add_child(board)
	if tarp:
		var cover: Polygon2D = Polygon2D.new()
		var w: float = rect.size.x * 0.35
		cover.polygon = PackedVector2Array([Vector2(-w, -rect.size.y * 0.75), Vector2(w * 0.4, -rect.size.y * 0.82),
			Vector2(w * 0.7, -rect.size.y * 0.45), Vector2(-w * 0.6, -rect.size.y * 0.4)])
		cover.color = Color(0.18, 0.42, 0.78, 0.92)
		marks.add_child(cover)


static func _ellipse(center: Vector2, radii: Vector2, color: Color) -> Polygon2D:
	var points: PackedVector2Array = []
	for i: int in 24:
		var a: float = TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y) / 2.0)
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = points
	poly.color = color
	return poly


# --- Flat blocks (no art, or zoomed far out) and trees ---

func _draw() -> void:
	for b: Dictionary in WorldState.buildings:
		var sprite: Sprite2D = _sprites.get(b["id"])
		if sprite != null and sprite.texture != null:
			continue
		var rect: Rect2 = footprint(b)
		var color: Color = Color(String(Data.entry("buildings", String(b["type"])).get("color", "#999999")))
		if b.get("burned", false):
			color = Color("2b2523")
		elif b["stripped"]:
			color = color.darkened(0.45)
		draw_rect(rect, color)
		draw_rect(rect, color.darkened(0.6), false, 2.0)
	if simple:
		return
	for t: Vector2 in _trees:
		draw_circle(t + Vector2(6, 7), 19.0, Color(0, 0, 0, 0.25))
		draw_circle(t, 18.0, Color("3f5a2c"))
		draw_circle(t + Vector2(-5, -5), 11.0, Color("557538"))
		draw_circle(t + Vector2(4, -7), 6.0, Color("6c8c45"))


func _scatter_trees() -> void:
	_trees.clear()
	var rows: Array = WorldState.town.get("rows", [])
	for y: int in range(1, rows.size() - 1):
		var row: String = rows[y]
		for x: int in range(1, row.length() - 1):
			if row[x] != "." or absi((x * 92837111) ^ (y * 689287499)) % 100 >= TREE_SHARE:
				continue
			if not _clear_around(rows, x, y):
				continue
			_trees.append((Vector2(x, y) + Vector2(0.5, 0.5)) * TILE)


func _clear_around(rows: Array, x: int, y: int) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if String(rows[y + dy])[x + dx] != ".":
				return false
	var tile: Vector2 = Vector2(x, y)
	for b: Dictionary in WorldState.buildings:
		if Rect2(Vector2(float(b["x"]), float(b["y"])) - Vector2.ONE, Vector2(float(b["w"]), float(b["h"])) + Vector2(2, 2)).has_point(tile):
			return false
	return true
