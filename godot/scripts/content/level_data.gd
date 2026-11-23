class_name LevelData
extends Resource

var id: String
var scene_path: String
var data_path: String
var order: int
var qa_only: bool
var world: Dictionary


static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


static func from_index(entry: Dictionary) -> LevelData:
	if not entry.get("id") is String or not entry.get("scene") is String or not entry.get("data") is String:
		return null
	var raw_order = entry.get("order")
	if (not raw_order is float and not raw_order is int) or not is_finite(float(raw_order)) \
			or not entry.get("qa_only", false) is bool:
		return null
	var result := LevelData.new()
	result.id = entry.id
	result.scene_path = entry.scene
	result.data_path = entry.data
	result.order = int(raw_order)
	result.qa_only = bool(entry.get("qa_only", false))
	result.world = read_json(result.data_path)
	if result.id.is_empty() or result.world.get("id") != result.id or result.world.get("version") != 1:
		return null
	return result
