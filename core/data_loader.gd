extends Node
## Autoload `Data`. Loads every res://data/*.json at startup into `tables`, keyed
## by file stem ("buildings", "items", ...). Content lives in these files, never
## in code.
# LATER: exported builds need "*.json" in the export filter for these to ship.

const DATA_DIR: String = "res://data"

var tables: Dictionary = {}
## One message per file that failed to load. Empty when everything loaded.
var errors: Array[String] = []


func _init() -> void:
	load_all()


func load_all() -> void:
	tables.clear()
	errors.clear()
	if not DirAccess.dir_exists_absolute(DATA_DIR):
		_fail("%s: data folder not found" % DATA_DIR)
		return
	var file_names: PackedStringArray = DirAccess.get_files_at(DATA_DIR)
	file_names.sort()
	for file_name: String in file_names:
		if file_name.get_extension() == "json":
			_load_file(DATA_DIR.path_join(file_name))


## The parsed contents of data/<table_name>.json. Note that JSON numbers parse as floats.
func table(table_name: String) -> Variant:
	if not tables.has(table_name):
		push_error("Data: no table '%s' (expected %s/%s.json)" % [table_name, DATA_DIR, table_name])
		return null
	return tables[table_name]


func _load_file(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_fail("%s: could not read file (error %d)" % [path, FileAccess.get_open_error()])
		return
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		_fail("%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return
	tables[path.get_file().get_basename()] = json.data


func _fail(message: String) -> void:
	push_error("Data: " + message)
	errors.append(message)
