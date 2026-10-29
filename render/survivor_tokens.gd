extends Node2D
## The group's tokens, drawn above the night tint so they always read: one token
## per living survivor in the group colour with their name, glided (not
## teleported) to where the simulation puts them each tick. At base they gather
## round the base; out on a trip they walk the route. The sprite shows what they
## are doing: carrying a pack, on guard, asleep, or (once the group knows) bitten.

const Sprites := preload("res://render/sprites.gd")
const Geo := preload("res://core/geo.gd")
const Tokens := preload("res://ui/theme/tokens.gd")

const TILE: float = 64.0
const TOKEN_PX: float = 46.0
## How quickly a token catches up with its position (per second); higher = snappier.
const FOLLOW: float = 6.0

var reduce_motion: bool = false
## Set by the view so tokens stay a readable size whatever the zoom.
var token_scale: float = 1.0:
	set(value):
		token_scale = value
		for token: Node2D in _tokens.values():
			token.scale = Vector2(value, value)

var _tokens: Dictionary = {}  # survivor id -> Node2D
var _targets: Dictionary = {}  # survivor id -> Vector2 (px)


func refresh() -> void:
	var group: Array = WorldState.group()
	var seen: Dictionary = {}
	var at_base: Array = group.filter(func(s: Dictionary) -> bool: return s["location"] != &"away")
	var base: Vector2 = Geo.base_center_m() / Geo.tile_m() * TILE if not WorldState.base.is_empty() else Vector2.ZERO
	for s: Dictionary in group:
		var id: String = s["id"]
		seen[id] = true
		var target: Vector2
		if s["location"] == &"away":
			target = Vector2(float(s["x_m"]), float(s["y_m"])) / Geo.tile_m() * TILE
		else:
			var i: int = at_base.find(s)
			var angle: float = TAU * float(i) / maxf(1.0, float(at_base.size())) - PI / 2.0
			target = base + Vector2(cos(angle), sin(angle)) * TILE * 0.9
		_targets[id] = target
		var token: Node2D = _tokens.get(id)
		if token == null:
			token = _make_token(s)
			token.position = target
			add_child(token)
			_tokens[id] = token
		_dress(token, s)
	for id: String in _tokens.keys():
		if not seen.has(id):
			_tokens[id].queue_free()
			_tokens.erase(id)
			_targets.erase(id)


func snap() -> void:
	for id: String in _tokens:
		_tokens[id].position = _targets[id]


func _process(delta: float) -> void:
	for id: String in _tokens:
		var token: Node2D = _tokens[id]
		if reduce_motion:
			token.position = _targets[id]
		else:
			token.position = token.position.lerp(_targets[id], 1.0 - exp(-delta * FOLLOW))


func _make_token(s: Dictionary) -> Node2D:
	var token: Node2D = Node2D.new()
	token.scale = Vector2(token_scale, token_scale)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	token.add_child(sprite)
	var label: Label = Label.new()
	label.name = "Name"
	label.text = String(s["name"])
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Tokens.GROUP)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.position = Vector2(TOKEN_PX * 0.55, -11)
	token.add_child(label)
	return token


func _dress(token: Node2D, s: Dictionary) -> void:
	var name: String = "tok_survivor"
	if s["location"] == &"away":
		name = "tok_survivor_pack"
	elif s["pathogen"].get("known", false):
		name = "tok_survivor_bitten"
	elif s["activity"] == &"sleeping":
		name = "tok_survivor_rest"
	elif s["job_now"] == &"guard":
		name = "tok_survivor_guard"
	var sprite: Sprite2D = token.get_node("Sprite")
	var tex: Texture2D = Sprites.get_texture(name)
	if tex == null:
		sprite.texture = null
		token.queue_redraw()
		return
	if sprite.texture != tex:
		sprite.texture = tex
		var k: float = TOKEN_PX / float(tex.get_width())
		sprite.scale = Vector2(k, k)
	# Only people out of the base get a name tag; at base they'd overlap.
	(token.get_node("Name") as Label).visible = s["location"] == &"away"
