class_name LevelPackage
extends RefCounted

const FORMAT := "ink-blade-levels"
const VERSION := 1
const MAX_BYTES := 4 * 1024 * 1024
const MAX_ROOMS := 24
const SAVE_DIR := "user://custom_routes"


static func collect(root: Dictionary) -> Dictionary:
	var root_error := _room_error(root)
	if not root_error.is_empty():
		return {"error": root_error}
	var worlds := {root.id: root}
	var pending: Array[Dictionary] = [root]
	while not pending.is_empty():
		var world: Dictionary = pending.pop_front()
		for gate in world.get("exits", []):
			if gate.get("finish", false):
				continue
			var target: Dictionary = worlds.get(gate.level, {})
			var unseen := target.is_empty()
			if target.is_empty():
				target = LevelDraft.read(gate.level)
			if target.get("id") != gate.level or not RoomLinks.connects(gate, target):
				return {"error": _link_error(world, gate)}
			if unseen:
				if worlds.size() >= MAX_ROOMS:
					return {"error": L10N.t("editor.error_package_limit", [MAX_ROOMS])}
				var error := _room_error(target)
				if not error.is_empty():
					return {"error": error}
				worlds[gate.level] = target
				pending.append(target)
	var data := {"format": FORMAT, "version": VERSION, "root": root.id, "rooms": worlds.values()}
	if JSON.stringify(data, "  ").to_utf8_buffer().size() >= MAX_BYTES:
		return {"error": L10N.t("editor.error_package_size")}
	return {"data": data}


static func inspect(data: Dictionary, strict := true) -> Dictionary:
	var rooms = data.get("rooms")
	if data.get("format") != FORMAT or data.get("version") != VERSION or not data.get("root") is String \
			or not rooms is Array or rooms.is_empty() or rooms.size() > MAX_ROOMS:
		return {"error": L10N.t("editor.error_json_format")}
	var worlds := {}
	for world in rooms:
		if not world is Dictionary or not world.get("id") is String or not LevelDraft.valid_id(world.id) or worlds.has(world.id):
			return {"error": L10N.t("editor.error_json_format")}
		var error := _room_error(world)
		if not error.is_empty():
			return {"error": error}
		worlds[world.id] = world
	if not worlds.has(data.root):
		return {"error": L10N.t("editor.error_json_format")}
	var finish := false
	var visited := {data.root: true}
	var pending: Array[String] = [data.root]
	while not pending.is_empty():
		var id: String = pending.pop_front()
		var world: Dictionary = worlds[id]
		for gate in world.get("exits", []):
			if gate.get("finish", false):
				finish = true
				continue
			if not worlds.has(gate.level) and not strict:
				continue
			if not RoomLinks.connects(gate, worlds.get(gate.level, {})):
				return {"error": _link_error(world, gate)}
			if not visited.has(gate.level):
				visited[gate.level] = true
				pending.append(gate.level)
	if visited.size() != worlds.size():
		return {"error": L10N.t("editor.error_package_detached")}
	return {"worlds": worlds, "finish": finish}


static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": L10N.t("editor.error_file", [path.get_file()])}
	if file.get_length() >= MAX_BYTES:
		return {"error": L10N.t("editor.error_package_size")}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": L10N.t("editor.error_json_line", [json.get_error_line() + 1, json.get_error_message()])}
	if not json.data is Dictionary:
		return {"error": L10N.t("editor.error_json_format")}
	return {"data": json.data}


static func install(source: Dictionary) -> Dictionary:
	var single := not source.has("format")
	var data := source.duplicate(true)
	if single:
		data = {"format": FORMAT, "version": VERSION, "root": source.get("id"), "rooms": [data]}
	if data.format != FORMAT or data.get("version") != VERSION or not data.get("root") is String \
			or not data.get("rooms") is Array or data.rooms.is_empty() or data.rooms.size() > MAX_ROOMS:
		return {"error": L10N.t("editor.error_json_format")}
	var ids := {}
	var taken := {}
	for id in LevelDraft.files():
		taken[id] = true
	for world in data.rooms:
		if not world is Dictionary or not world.get("id") is String or not LevelDraft.valid_id(world.id) or ids.has(world.id):
			return {"error": L10N.t("editor.error_json_format")}
		ids[world.id] = world.id
		if not taken.has(world.id) and not LVL.has(world.id):
			taken[world.id] = true
			continue
		var index := 2
		var new_id := _copy_id(world.id, index)
		while taken.has(new_id) or LVL.has(new_id):
			index += 1
			new_id = _copy_id(world.id, index)
		taken[new_id] = true
		ids[world.id] = new_id
	if not ids.has(data.root):
		return {"error": L10N.t("editor.error_json_format")}
	data.root = ids[data.root]
	for world in data.rooms:
		world.id = ids[world.id]
		if world.get("exits") is Array:
			for gate in world.exits:
				if gate is Dictionary and gate.get("level") is String and ids.has(gate.level):
					gate.level = ids[gate.level]
	var result := inspect(data, not single)
	if result.has("error"):
		return result
	var err := DirAccess.make_dir_recursive_absolute(LevelDraft.DIR)
	var written := PackedStringArray()
	if err == OK:
		for world in data.rooms:
			var path := LevelDraft.DIR.path_join(world.id + ".json")
			err = ERR_ALREADY_EXISTS if FileAccess.file_exists(path) else LevelDraft.write_json(path, world)
			if err != OK:
				break
			written.append(path)
	if err != OK:
		for path in written:
			DirAccess.remove_absolute(path)
		return {"error": L10N.t("editor.error_save", [error_string(err)])}
	return {"root": data.root, "count": data.rooms.size()}


static func _copy_id(id: String, index: int) -> String:
	var suffix := "_import_%d" % index
	return id.left(48 - suffix.length()) + suffix


static func _room_error(world: Dictionary) -> String:
	var errors := LevelDraft.validate_world(world)
	if not errors.is_empty():
		return "%s · %s" % [str(world.get("id", "?")), errors[0]]
	var legacy = world.get("enemies", [])
	if not legacy is Array or legacy.size() > 1024:
		return L10N.t("editor.error_rows", ["enemies"])
	for row in legacy:
		if not LevelDraft._point_valid(row) or not LevelDraft.rect(world.bounds).has_point(LevelDraft.point(row)):
			return L10N.t("editor.error_rows", ["enemies"])
	for enemy in world.get("placements", []) + legacy:
		if not enemy.get("overrides", {}) is Dictionary:
			return L10N.t("editor.error_rows", ["placements"])
	return ""


static func _link_error(world: Dictionary, gate: Dictionary) -> String:
	return L10N.t("editor.error_package_link", [world.id, gate.id, gate.level, str(gate.get("entry", ""))])
