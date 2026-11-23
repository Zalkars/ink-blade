extends Node

const INDEX := "res://content/levels/index.json"

var _levels: Dictionary[String, LevelData] = {}
var _ordered: Array[LevelData] = []
var _first := ""


func _ready() -> void:
	var index := LevelData.read_json(INDEX)
	if index.get("version") != 1 or not index.get("levels") is Array:
		push_error("LVL: некорректный индекс " + INDEX)
		return
	for entry in index.levels:
		var level := LevelData.from_index(entry) if entry is Dictionary else null
		if level == null or _levels.has(level.id) or not ResourceLoader.exists(level.scene_path, "PackedScene"):
			push_warning("LVL: недоступная запись уровня %s" % str(entry))
			continue
		_levels[level.id] = level
		_ordered.append(level)
	_ordered.sort_custom(func(a: LevelData, b: LevelData) -> bool: return a.order < b.order)
	var first := get_level(str(index.get("first", "")))
	if first != null and not first.qa_only:
		_first = first.id
	else:
		push_error("LVL: первый сюжетный уровень недоступен")


func get_level(id: String) -> LevelData:
	return _levels.get(id)


func ids(include_qa := true) -> PackedStringArray:
	var result := PackedStringArray()
	for level in _ordered:
		if include_qa or not level.qa_only:
			result.append(level.id)
	return result


func has(id: String) -> bool:
	return _levels.has(id)


func first_id() -> String:
	return _first
