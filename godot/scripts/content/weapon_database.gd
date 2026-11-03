extends Node

## Каталог оружия. Как и DB, читает папку content/weapons в редакторе,
## а в экспортированной сборке — секцию weapons из content/manifest.json.
## Отдельный автолоад, чтобы оружие не смешивалось с врагами и пропами.

signal loaded

const WEAPON_DIR := "res://content/weapons"
const MANIFEST := "res://content/manifest.json"

var _defs: Dictionary = {}
var _source := ""


func _ready() -> void:
	reload()


func reload() -> void:
	_defs.clear()
	_source = ""
	if _use_manifest():
		_load_manifest()
	if _defs.is_empty():
		_scan()
		if not _defs.is_empty():
			_source = "scan"
	if _source.is_empty():
		_source = "empty"
	loaded.emit()
	print("WDB: %d оружия (%s)" % [_defs.size(), _source])


func _use_manifest() -> bool:
	return OS.has_feature("template") and not OS.has_feature("editor")


func _scan() -> void:
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		push_warning("WDB: нет папки " + WEAPON_DIR)
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and (file.ends_with(".tres") or file.ends_with(".res")):
			_load_file(WEAPON_DIR + "/" + file)
		file = dir.get_next()
	dir.list_dir_end()


func _load_manifest() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WDB: плохой manifest.json")
		return
	var weapons: Dictionary = parsed.get("weapons", {})
	for key in weapons.keys():
		var entry = weapons[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var path := String(entry.get("path", ""))
		if not path.is_empty():
			_load_file(path)
	if not _defs.is_empty():
		_source = "manifest"


func _load_file(path: String) -> WeaponDef:
	if not ResourceLoader.exists(path):
		push_error("WDB: нет файла " + path)
		return null
	var res: Resource = ResourceLoader.load(path)
	var def := res as WeaponDef
	if def == null or not def.is_valid():
		push_error("WDB: не WeaponDef: " + path)
		return null
	if _defs.has(def.id):
		push_error("WDB: дубликат id %s (%s)" % [String(def.id), path])
		return null
	_defs[def.id] = def
	return def


func get_weapon(id: StringName) -> WeaponDef:
	return _defs.get(id, null) as WeaponDef


func all() -> Array:
	var out: Array = _defs.values()
	out.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool:
		return a.order < b.order
	)
	return out


func ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


func count() -> int:
	return _defs.size()


func source() -> String:
	return _source
