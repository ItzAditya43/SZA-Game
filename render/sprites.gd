extends RefCounted
## Loads sprites from res://assets/sprites by name (bld_house, item_rifle, ...),
## cached. Returns null when a sprite is missing, so every caller has a
## procedural fallback and the game still runs art-free.

const DIR: String = "res://assets/sprites/"

static var _cache: Dictionary = {}


static func get_texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path: String = DIR + name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		# Not imported yet (fresh clone before `godot --import`): read the PNG directly.
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null:
			tex = ImageTexture.create_from_image(image)
	_cache[name] = tex
	return tex


static func get_image(name: String) -> Image:
	var tex: Texture2D = get_texture(name)
	return tex.get_image() if tex != null else null
