extends Node

## Каталог карточек контента.
## В редакторе и при запуске проекта читает content/entities напрямую,
## в экспортированной сборке — сгенерированный content/manifest.json.
## Сканировать res:// в PCK нельзя: поведение отличается от редактора.

signal loaded

const ENTITY_DIR := "res://content/entities"
const MANIFEST := "res://content/manifest.json"
const ALIASES := "res://content/aliases.tres"

var _defs: Dictionary = {}
var _aliases: Dictionary = {}
var _source := ""


func _ready() -> void:
	reload()


func reload() -> void:
	_defs.clear()
	_aliases.clear()
	_source = ""
	_load_aliases()

	if _use_manifest():
		_load_manifest()
	if _defs.is_empty():
		_scan()
		if not _defs.is_empty():
			_source = "scan"
	if _source.is_empty():
		_source = "empty"

	loaded.emit()
	print("DB: %d карточек (%s)" % [_defs.size(), _source])


func _use_manifest() -> bool:
	return OS.has_feature("template") and not OS.has_feature("editor")


func _load_aliases() -> void:
	if not ResourceLoader.exists(ALIASES):
		return
	var res: Resource = ResourceLoader.load(ALIASES)
	if res is ContentAliases:
		var aliases := res as ContentAliases
		for key in aliases.map:
			_aliases[StringName(key)] = StringName(aliases.map[key])


func _scan() -> void:
	var dir := DirAccess.open(ENTITY_DIR)
	if dir == null:
		push_error("DB: нет папки " + ENTITY_DIR)
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and (file.ends_with(".tres") or file.ends_with(".res")):
			_load_file(ENTITY_DIR + "/" + file)
		file = dir.get_next()
	dir.list_dir_end()


func _load_manifest() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		push_warning("DB: нет manifest.json, читаю папку напрямую")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DB: плохой manifest.json")
		return
	var entities: Dictionary = parsed.get("entities", {})
	for key in entities.keys():
		var entry = entities[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var path := String(entry.get("path", ""))
		if path.is_empty():
			continue
		var def := _load_file(path)
		if def != null and String(def.id) != String(key):
			push_warning("DB: id в манифесте %s не совпадает с карточкой %s" % [key, def.id])
	if not _defs.is_empty():
		_source = "manifest"


func _load_file(path: String) -> EntityDef:
	if not ResourceLoader.exists(path):
		push_error("DB: нет файла " + path)
		return null
	var res: Resource = ResourceLoader.load(path)
	var def := res as EntityDef
	if def == null:
		push_error("DB: не EntityDef: " + path)
		return null
	_register(def, path)
	return def


func _register(def: EntityDef, path: String) -> void:
	if not def.is_valid():
		push_error("DB: карточка без id или scene: " + path)
		return
	if _defs.has(def.id):
		push_error("DB: дубликат id %s (%s)" % [String(def.id), path])
		return
	_defs[def.id] = def


## Разворачивает цепочку переименований: old -> mid -> new.
func resolve_id(id: StringName) -> StringName:
	var cur := id
	var guard := 0
	while _aliases.has(cur) and guard < 32:
		cur = _aliases[cur]
		guard += 1
	return cur


func get_def(id: StringName) -> EntityDef:
	var def = _defs.get(resolve_id(id), null)
	return def as EntityDef


func has(id: StringName) -> bool:
	return _defs.has(resolve_id(id))


func all(category: int = -1) -> Array:
	var out: Array = []
	for id in _defs:
		var def: EntityDef = _defs[id]
		if category < 0 or int(def.category) == category:
			out.append(def)
	out.sort_custom(func(a: EntityDef, b: EntityDef) -> bool:
		return String(a.id) < String(b.id)
	)
	return out


func ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


## Создаёт сцену по ID и передаёт ей карточку. Сцена сама решает,
## какие поля карточки ей нужны: configure(def, overrides).
func instantiate(id: StringName, overrides: Dictionary = {}) -> Node:
	var def := get_def(id)
	if def == null:
		push_error("DB: неизвестная карточка " + String(id))
		return null
	var node := def.scene.instantiate()
	if node.has_method("configure"):
		node.configure(def, overrides)
	elif not overrides.is_empty():
		push_warning("DB: у сцены %s нет configure(), переопределения пропущены" % String(id))
	return node


func count() -> int:
	return _defs.size()


func source() -> String:
	return _source
