extends Node

const DIRECTORY := "res://content/props/"
const MANIFEST := "res://content/manifest.json"

var _defs: Dictionary[StringName, PropDef] = {}


func _ready() -> void:
	if OS.has_feature("template") and not OS.has_feature("editor"):
		var entries = LevelData.read_json(MANIFEST).get("props", {})
		if not entries is Dictionary:
			push_error("PDB: некорректная секция props в манифесте")
			return
		for id in entries:
			var entry = entries[id]
			if entry is Dictionary:
				_register(str(entry.get("path", "")), StringName(id))
	else:
		for file in DirAccess.get_files_at(DIRECTORY):
			if file.get_extension() in ["tres", "res"]:
				_register(DIRECTORY + file)
	print("PDB: %d (%s)" % [_defs.size(), "manifest" if OS.has_feature("template") else "scan"])


func _register(path: String, expected := &"") -> void:
	var def := ResourceLoader.load(path) as PropDef if ResourceLoader.exists(path) else null
	if def == null or not def.is_valid() or _defs.has(def.id) or (expected != &"" and expected != def.id):
		push_error("PDB: некорректная карточка " + path)
		return
	_defs[def.id] = def


func get_def(id: StringName) -> PropDef:
	return _defs.get(id)


func ids() -> Array[StringName]:
	var result := _defs.keys()
	result.sort()
	return result
