extends RefCounted

const MANIFEST := "res://content/manifest.json"
const INDEX := "res://content/levels/index.json"

var errors: PackedStringArray = []
var manifest: Dictionary
var overlay: String
var _locales: Dictionary = {}
var _aliases: Dictionary = {}


func inspect(root := "") -> void:
	overlay = root.trim_suffix("/")
	var aliases := ResourceLoader.load(_resolve("res://content/aliases.tres")) as ContentAliases
	_aliases = aliases.map if aliases != null else {}
	manifest = {"schema": 1}
	for kind in ["entities", "weapons", "props"]:
		manifest[kind] = _cards(kind)
	for language in ["ru", "en"]:
		_locales[language] = _json("res://locale/%s.json" % language).get("strings", {})
	for id in manifest.props:
		_validate_key(manifest.props[id].display_name_key, manifest.props[id].path)
	var dialogues := _story("dialogue", "lines")
	_story("cutscenes", "slides")
	var index := _json(INDEX)
	manifest["level_index_hash"] = _hash(_resolve(INDEX))
	manifest["levels"] = _levels(index, dialogues)


func _resolve(path: String) -> String:
	var fixture := overlay.path_join(path.trim_prefix("res://"))
	if not overlay.is_empty() and (FileAccess.file_exists(fixture) or ResourceLoader.exists(fixture)):
		return fixture
	return path


func _files(path: String) -> PackedStringArray:
	var names := DirAccess.get_files_at(path)
	var fixture := overlay.path_join(path.trim_prefix("res://"))
	if not overlay.is_empty() and DirAccess.dir_exists_absolute(fixture):
		for item in DirAccess.get_files_at(fixture):
			if not item in names:
				names.append(item)
	names.sort()
	return names


func _json(path: String) -> Dictionary:
	var result := LevelData.read_json(_resolve(path))
	if result.is_empty():
		errors.append(path + ": JSON отсутствует или повреждён")
	return result


func _hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	# Git may check project text out with CRLF on Windows and LF elsewhere.
	if path.get_extension() in ["json", "tscn", "tres"]:
		return FileAccess.get_file_as_string(path).replace("\r\n", "\n").sha256_text()
	return FileAccess.get_sha256(path)


func _cards(kind: String) -> Dictionary:
	var directory := "res://content/" + kind
	var entries := {}
	for file in _files(directory):
		if file.get_extension() not in ["tres", "res"]:
			continue
		var path := directory.path_join(file)
		var source := _resolve(path)
		var def := ResourceLoader.load(source)
		var entry := {"path": path, "hash": _hash(source)}
		if kind == "entities" and def is EntityDef:
			entry.merge({"type": "EntityDef", "category": int(def.category), "version": def.version})
		elif kind == "weapons" and def is WeaponDef:
			entry.merge({"type": "WeaponDef", "order": def.order})
		elif kind == "props" and def is PropDef:
			entry.merge({"type": "PropDef", "kind": def.kind, "version": def.version, "display_name_key": def.display_name_key})
		else:
			errors.append(path + ": неверный тип карточки")
			continue
		if not def.is_valid():
			errors.append(path + ": некорректная карточка")
		elif entries.has(str(def.id)):
			errors.append(path + ": дубликат ID " + str(def.id))
		else:
			entries[str(def.id)] = entry
	return entries


func _story(folder: String, field: String) -> Dictionary:
	var result := {}
	var directory := "res://content/" + folder
	for file in _files(directory):
		if not file.ends_with(".json"):
			continue
		var path := directory.path_join(file)
		var data := _json(path)
		var id := file.get_basename()
		if data.get("version") != 1 or data.get("id") != id or not data.get(field) is Array:
			errors.append(path + ": неверная версия, ID или поле " + field)
			continue
		result[id] = true
		for row in data[field]:
			if not row is Dictionary:
				errors.append(path + ": элементы " + field + " должны быть объектами")
				continue
			_validate_key(row.get("text", ""), path + " text")
			if field == "lines":
				_validate_key(row.get("speaker", ""), path + " speaker")
		var grant := str(data.get("grant", ""))
		if not grant.is_empty() and not manifest.weapons.has(grant):
			errors.append(path + ": неизвестная награда grant " + grant)
	return result


func _levels(index: Dictionary, dialogues: Dictionary) -> Dictionary:
	var result := {}
	var seen := {}
	var orders := {}
	if index.get("version") != 1 or not index.get("levels") is Array:
		errors.append(INDEX + ": неверная версия или поле levels")
		return result
	for entry in index.levels:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() \
				or not entry.get("scene") is String or not entry.get("data") is String \
				or not _number(entry.get("order")) or float(entry.order) != floorf(float(entry.order)) \
				or not entry.get("qa_only", false) is bool:
			errors.append(INDEX + ": неверные поля записи " + str(entry))
			continue
		if seen.has(entry.id) or orders.has(int(entry.order)):
			errors.append(INDEX + ": дубликат ID или order: " + entry.id)
			continue
		seen[entry.id] = true
		orders[int(entry.order)] = true
		var world := _json(entry.data)
		if world.get("version") != 1 or world.get("id") != entry.id:
			errors.append(entry.data + ": версия или ID уровня не совпадает с индексом")
		var scene_path := _resolve(entry.scene)
		var scene := ResourceLoader.load(scene_path, "PackedScene") as PackedScene if ResourceLoader.exists(scene_path, "PackedScene") else null
		if scene == null:
			errors.append(entry.scene + ": отсутствует сцена уровня")
			continue
		var instance := scene.instantiate()
		var script := instance.get_script() as Script
		if script == null or script.resource_path != "res://scripts/world/level.gd" or instance.get("data_path") != entry.data:
			errors.append(entry.scene + ": корень сцены или data_path не совпадает с индексом")
		instance.free()
		_validate_world(world, entry.data, dialogues)
		result[entry.id] = {"scene": entry.scene, "data": entry.data, "order": int(entry.order),
			"qa_only": bool(entry.get("qa_only", false)), "scene_hash": _hash(scene_path),
			"data_hash": _hash(_resolve(entry.data))}
	var first = index.get("first")
	if not first is String or not result.has(first) or result[first].qa_only:
		errors.append(INDEX + ": первый сюжетный уровень недоступен")
	return result


func _validate_world(world: Dictionary, path: String, dialogues: Dictionary) -> void:
	var raw = world.get("bounds")
	if not raw is Dictionary or not _number(raw.get("x")) or not _number(raw.get("y")) \
			or not _number(raw.get("w")) or not _number(raw.get("h")) or raw.w <= 0 or raw.h <= 0:
		errors.append(path + ": неверные bounds")
		return
	var bounds := Rect2(raw.x, raw.y, raw.w, raw.h)
	_position(world.get("spawn"), bounds, path + " spawn")
	for section in ["placements", "props", "checkpoints", "triggers"]:
		var entries = world.get(section, [])
		if not entries is Array:
			errors.append(path + ": " + section + " должен быть массивом")
			continue
		var ids := {}
		for spec in entries:
			if not spec is Dictionary or not spec.get("id") is String or spec.id.is_empty() or ids.has(spec.id):
				errors.append(path + ": пустой или повторный ID в " + section + " " + str(spec))
				continue
			ids[spec.id] = true
			var label: String = "%s %s/%s" % [path, section, spec.id]
			_position(spec, bounds, label)
			var reference := str(spec.get("def_id", ""))
			if section == "placements" and not manifest.entities.has(_resolve_enemy(reference)):
				errors.append(label + ": неизвестный def_id " + reference)
			if section == "props" and not manifest.props.has(reference):
				errors.append(label + ": неизвестный def_id " + reference)
			if section == "triggers" and spec.has("dialogue") and not dialogues.has(str(spec.dialogue)):
				errors.append(label + ": неизвестный dialogue " + str(spec.dialogue))
	if world.has("display_name_key"):
		_validate_key(world.display_name_key, path)
	var zones = world.get("zones", [])
	if not zones is Array:
		errors.append(path + ": zones должен быть массивом")
		return
	for zone in zones:
		if not zone is Dictionary or not zone.get("id") is String or zone.id.is_empty():
			errors.append(path + ": неверная зона")
		elif zone.id == "threshold":
			_validate_key("BANNER_TITLE", path)
			_validate_key("BANNER_SUB", path)
		else:
			_validate_key("zone.%s.title" % zone.id, path)
			_validate_key("zone.%s.sub" % zone.id, path)


func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _resolve_enemy(id: String) -> String:
	for i in 32:
		if not _aliases.has(id):
			break
		id = str(_aliases[id])
	return id


func _position(spec: Variant, bounds: Rect2, path: String) -> void:
	if not spec is Dictionary or not _number(spec.get("x")) or not _number(spec.get("y")) \
			or not bounds.has_point(Vector2(spec.x, spec.y)):
		errors.append(path + ": координаты за bounds или неверный формат")


func _validate_key(key: Variant, path: String) -> void:
	for lang in _locales:
		var strings = _locales[lang]
		if not key is String or key.is_empty() or not strings is Dictionary or not strings.get(key) is String:
			errors.append("%s: отсутствует ключ %s в locale/%s.json" % [path, str(key), lang])
