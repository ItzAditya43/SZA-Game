extends TileMapLayer
## The town's ground as tiles: dirt and dry grass, fields, the paved plaza, roads
## and the canal. Tiles are cut at runtime from the ground sprites; roads and the
## canal use half-width tiles so a two-tile road reads as one road, and are
## transposed where they run east-west. Falls back to flat colours without art.
## A shader lets weeds creep over the roads as the days pass and darkens wet ground.

const Sprites := preload("res://render/sprites.gd")

const TILE: int = 64
## Tiles are built at twice their world size and the layer drawn at half scale,
## so zoomed-in ground keeps the art's detail.
const TEX: int = 128
enum T { DIRT, GRASS, PLAZA, FIELD, BURNT, RUBBLE, ROAD, ROAD_A, ROAD_B, ROAD_PLAIN, CANAL, CANAL_A, CANAL_B }
const FALLBACK: Dictionary = {
	T.DIRT: Color("6b5a40"), T.GRASS: Color("66603d"), T.PLAZA: Color("8a8478"), T.FIELD: Color("5f6a38"),
	T.BURNT: Color("2e2622"), T.RUBBLE: Color("6e6862"), T.ROAD: Color("3d3d40"), T.ROAD_A: Color("3d3d40"),
	T.ROAD_B: Color("3d3d40"), T.ROAD_PLAIN: Color("3d3d40"), T.CANAL: Color("2c6e8a"), T.CANAL_A: Color("2c6e8a"),
	T.CANAL_B: Color("2c6e8a"),
}

const SHADER: String = """
shader_type canvas_item;
uniform float weeds = 0.0;
uniform float wet = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
varying vec2 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	vec4 c = COLOR;
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float grey = 1.0 - smoothstep(0.05, 0.12, hi - lo);
	float n = texture(noise_tex, world / 420.0).r;
	float speck = texture(noise_tex, world / 37.0).r;
	// Weeds: patches first, specks inside them, only on grey (paved) ground.
	float w = grey * step(n, weeds * 0.75) * step(speck, 0.35 + weeds * 0.4);
	c.rgb = mix(c.rgb, vec3(0.33, 0.42, 0.20) * (0.8 + speck * 0.4), w * 0.75);
	// Wet: darker paving with a faint sheen.
	c.rgb *= 1.0 - wet * 0.28 * (0.5 + grey * 0.5);
	c.rgb += wet * grey * 0.10 * pow(speck, 6.0);
	COLOR = c;
}
"""

var _material: ShaderMaterial


func _ready() -> void:
	scale = Vector2.ONE * float(TILE) / float(TEX)
	tile_set = _make_tile_set()
	_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = SHADER
	_material.shader = shader
	var noise: NoiseTexture2D = NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 256
	noise.height = 256
	var fast: FastNoiseLite = FastNoiseLite.new()
	fast.frequency = 0.03
	noise.noise = fast
	_material.set_shader_parameter("noise_tex", noise)
	material = _material


func set_weather(weeds: float, wet: float) -> void:
	_material.set_shader_parameter("weeds", weeds)
	_material.set_shader_parameter("wet", wet)


func build(rows: Array) -> void:
	clear()
	var h: int = rows.size()
	if h == 0:
		return
	var w: int = String(rows[0]).length()
	for y: int in h:
		for x: int in w:
			var ch: String = String(rows[y])[x]
			var tile: Array = _tile_for(rows, x, y, ch)
			set_cell(Vector2i(x, y), 0, Vector2i(tile[0], 0), tile[1])


## [atlas index, alternative (transform flags)] for the tile at x, y.
func _tile_for(rows: Array, x: int, y: int, ch: String) -> Array:
	match ch:
		"=", "~":
			var across: int = _run(rows, x, y, ch, Vector2i(1, 0))
			var down: int = _run(rows, x, y, ch, Vector2i(0, 1))
			var full: int = T.ROAD if ch == "=" else T.CANAL
			var half_a: int = T.ROAD_A if ch == "=" else T.CANAL_A
			var half_b: int = T.ROAD_B if ch == "=" else T.CANAL_B
			if down >= 4 and across <= 2:
				# Runs north-south: as drawn.
				if across == 1:
					return [full, 0]
				var left: bool = x == 0 or String(rows[y])[x - 1] != ch
				return [half_a if left else half_b, 0]
			if across >= 4 and down <= 2:
				var flags: int = TileSetAtlasSource.TRANSFORM_TRANSPOSE
				if down == 1:
					return [full, flags]
				var top: bool = y == 0 or String(rows[y - 1])[x] != ch
				return [half_a if top else half_b, flags]
			return [T.ROAD_PLAIN if ch == "=" else T.CANAL, 0]
		":":
			return [T.PLAZA, 0]
		",":
			return [T.FIELD, 0]
	var roll: int = absi((x * 73856093) ^ (y * 19349663)) % 100
	return [T.GRASS if roll < 22 else T.DIRT, 0]


## Length of the run of `ch` through (x, y) along `step` (both directions).
func _run(rows: Array, x: int, y: int, ch: String, step: Vector2i) -> int:
	var n: int = 1
	for dir: int in [-1, 1]:
		var p: Vector2i = Vector2i(x, y) + step * dir
		while p.y >= 0 and p.y < rows.size() and p.x >= 0 and p.x < String(rows[p.y]).length() and String(rows[p.y])[p.x] == ch:
			n += 1
			p += step * dir
	return n


func _make_tile_set() -> TileSet:
	var count: int = T.size()
	var atlas: Image = Image.create(TEX * count, TEX, false, Image.FORMAT_RGBA8)
	var sources: Dictionary = {
		T.DIRT: ["ground_dirt", "full"], T.GRASS: ["ground_grass", "full"], T.PLAZA: ["ground_plaza", "full"],
		T.FIELD: ["ground_field", "full"], T.BURNT: ["ground_burnt", "full"], T.RUBBLE: ["ground_rubble", "full"],
		T.ROAD: ["ground_road", "full"], T.ROAD_A: ["ground_road", "left"], T.ROAD_B: ["ground_road", "right"],
		T.ROAD_PLAIN: ["ground_road", "plain"], T.CANAL: ["ground_canal", "full"], T.CANAL_A: ["ground_canal", "left"],
		T.CANAL_B: ["ground_canal", "right"],
	}
	for index: int in count:
		var tile: Image = _cut(String(sources[index][0]), String(sources[index][1]))
		if tile == null:
			tile = Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
			tile.fill(FALLBACK[index])
		atlas.blit_rect(tile, Rect2i(0, 0, TEX, TEX), Vector2i(index * TEX, 0))
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.generate_mipmaps()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = Vector2i(TEX, TEX)
	for index: int in count:
		source.create_tile(Vector2i(index, 0))
	var tiles: TileSet = TileSet.new()
	tiles.tile_size = Vector2i(TEX, TEX)
	tiles.add_source(source, 0)
	return tiles


## A square tile from a ground sprite: all of it, its left or right half (for
## two-tile roads), or a plain patch with no markings (crossings).
func _cut(name: String, part: String) -> Image:
	var image: Image = Sprites.get_image(name)
	if image == null:
		return null
	image = image.duplicate()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var w: int = image.get_width()
	var h: int = image.get_height()
	# Trim the drawn border a little so tiles meet without seams.
	var inset: int = int(w * 0.04)
	var region: Rect2i
	match part:
		"left":
			region = Rect2i(inset, inset, w / 2 - inset, w / 2 - inset)
		"right":
			region = Rect2i(w / 2, inset, w / 2 - inset, w / 2 - inset)
		"plain":
			region = Rect2i(inset + w / 12, inset, w / 4, w / 4)
		_:
			region = Rect2i(inset, inset, w - inset * 2, h - inset * 2)
	var cut: Image = image.get_region(region)
	cut.resize(TEX, TEX, Image.INTERPOLATE_LANCZOS)
	return cut
