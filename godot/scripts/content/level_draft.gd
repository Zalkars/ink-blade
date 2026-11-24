class_name LevelDraft
extends RefCounted

const Decor := preload("res://scripts/world/level_decor.gd")
const DIR := "user://level_editor"
const GRID := 32
const MAX_SIZE := Vector2i(16384, 2048)
const SECTIONS := ["solids", "one_ways", "checkpoints", "placements", "props", "decor", "doors", "switches", "entries", "exits"]
const GEOMETRY_TOOLS := ["solid", "platform", "ledge", "bridge", "steps"]
const HISTORY_LIMIT := 32

var data: Dictionary
var saved: Dictionary
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []


func _init() -> void:
	start("custom_level", L10N.t("editor.new_name"))


func start(id: String, title: String) -> void:
	replace({"version": 1, "id": id, "name": title, "bounds": {"x": 0, "y": 0, "w": 2048, "h": 768},
		"spawn": {"x": 128, "y": 608}, "solids": [{"x": 0, "y": 608, "w": 2048, "h": 160}]})
	# New drafts have never been saved and can be offered for saving on exit.
	saved = {}


func replace(world: Dictionary) -> void:
	data = world.duplicate(true)
	for section in SECTIONS:
		if not data.has(section):
			data[section] = []
	saved = data.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()


func clone_world(world: Dictionary, id: String) -> void:
	replace(world)
	data.id = id
	if world.get("id") == "ch01_hall":
		data.landmarks = "ch01_hall"
	data.erase("display_name_key")
	data.name = str(world.get("name", id)).capitalize()
	var bounds: Dictionary = data.bounds
	bounds.h = ceili(float(bounds.h) / GRID) * GRID
	for section in ["solids", "one_ways"]:
		for row in data[section]:
			bounds.h = maxi(int(bounds.h), int(float(row.y) + float(row.h)))
	saved = {}


func edit() -> void:
	undo_stack.append(data.duplicate(true))
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()


func undo() -> void:
	if not undo_stack.is_empty():
		redo_stack.append(data)
		data = undo_stack.pop_back()


func redo() -> void:
	if not redo_stack.is_empty():
		undo_stack.append(data)
		data = redo_stack.pop_back()


func dirty() -> bool:
	return JSON.stringify(data) != JSON.stringify(saved)


func bounds_rect() -> Rect2:
	return rect(data.bounds)


static func rect(row: Dictionary) -> Rect2:
	return Rect2(float(row.x), float(row.y), float(row.w), float(row.h))


static func point(row: Dictionary) -> Vector2:
	return Vector2(float(row.x), float(row.y))


func place(tool: String, from: Vector2, to: Vector2) -> void:
	if tool in GEOMETRY_TOOLS:
		var shapes := geometry(tool, from, to)
		for shape in shapes:
			if not bounds_rect().encloses(shape):
				return
		if shapes.is_empty():
			return
		edit()
		var section := "one_ways" if tool in ["platform", "bridge"] else "solids"
		for shape in shapes:
			data[section].append(_rectangle(shape))
		return
	if not bounds_rect().has_point(from):
		return
	var item := {"x": int(from.x), "y": int(from.y)}
	if tool == "spawn":
		edit()
		data.spawn = item
		return
	var kind := tool.get_slice(":", 0)
	var section: String = {"checkpoint": "checkpoints", "enemy": "placements", "prop": "props", "decor": "decor",
		"door": "doors", "switch": "switches", "entry": "entries", "exit": "exits", "finish": "exits"}.get(kind, "")
	if section.is_empty():
		return
	edit()
	item.id = _next_id(section, kind)
	if kind == "decor":
		item.kind = tool.get_slice(":", 1)
		item.grounded = item.kind != "banner"
	elif kind == "enemy" or kind == "prop":
		item.def_id = tool.get_slice(":", 1)
	elif kind == "door":
		item["w"] = GRID
		item["h"] = GRID * 4
	elif kind == "switch":
		item["targets"] = []
	elif kind == "exit":
		item["level"] = ""
		item["entry"] = ""
	elif kind == "finish":
		item["finish"] = true
	data[section].append(item)


func link_switch(source: Vector2i, target: Vector2i) -> bool:
	var lever := item(source)
	var door := item(target)
	if lever.is_empty() or door.is_empty() or SECTIONS[source.x] != "switches" or SECTIONS[target.x] != "doors":
		return false
	edit()
	if door.id in lever.targets:
		lever.targets.erase(door.id)
	else:
		lever.targets.append(door.id)
	return true


static func geometry(tool: String, start: Vector2, finish: Vector2) -> Array[Rect2]:
	var top_left := start.min(finish)
	var dimensions := (start - finish).abs() + Vector2(GRID, GRID)
	if tool in ["platform", "ledge", "bridge"]:
		dimensions.y = GRID
	var result: Array[Rect2] = []
	if tool == "steps":
		var step_count := mini(12, int(dimensions.x / GRID))
		var rightward := finish.x >= start.x
		for index in step_count:
			var height := minf(GRID * (index + 1), dimensions.y)
			var column := index if rightward else int(dimensions.x / GRID) - index - 1
			result.append(Rect2(top_left + Vector2(column * GRID, dimensions.y - height), Vector2(GRID, height)))
	elif tool == "bridge":
		for dx in range(0, int(dimensions.x), GRID * 5):
			result.append(Rect2(top_left + Vector2(dx, 0), Vector2(minf(GRID * 4, dimensions.x - dx), GRID)))
	else:
		result.append(Rect2(top_left, dimensions))
	return result


func _rectangle(area: Rect2) -> Dictionary:
	return {"x": int(area.position.x), "y": int(area.position.y), "w": int(area.size.x), "h": int(area.size.y)}


func _next_id(section: String, prefix: String) -> String:
	var taken := {}
	for row in data[section]:
		taken[row.id] = true
	var index := 1
	while taken.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


func find_at(world: Vector2, ignored: Array = []) -> Vector2i:
	# Interactive items are drawn above terrain and selected first.
	for section in range(SECTIONS.size() - 1, -1, -1):
		if SECTIONS[section] in ignored:
			continue
		var rows: Array = data[SECTIONS[section]]
		for index in range(rows.size() - 1, -1, -1):
			if item_rect(SECTIONS[section], rows[index]).has_point(world):
				return Vector2i(section, index)
	return Vector2i(-1, -1)


func find_in(area: Rect2, ignored: Array = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for section in SECTIONS.size():
		if SECTIONS[section] in ignored:
			continue
		var rows: Array = data[SECTIONS[section]]
		for index in rows.size():
			if area.intersects(item_rect(SECTIONS[section], rows[index])):
				result.append(Vector2i(section, index))
	return result


func item_rect(section: String, row: Dictionary) -> Rect2:
	if section == "solids" or section == "one_ways":
		return rect(row)
	if section == "decor":
		return Decor.decor_rect(row, data)
	if section == "doors":
		return RoomLinks.door_rect(row)
	return Rect2(point(row) - Vector2(17, 32), Vector2(34, 38))


func item(selected: Vector2i) -> Dictionary:
	if selected.x < 0 or selected.x >= SECTIONS.size() or selected.y < 0 or selected.y >= data[SECTIONS[selected.x]].size():
		return {}
	return data[SECTIONS[selected.x]][selected.y]


func move_item(selected: Vector2i, delta: Vector2) -> void:
	move_items([selected], delta)


func move_items(selected: Array[Vector2i], delta: Vector2) -> void:
	if selected.is_empty() or delta == Vector2.ZERO:
		return
	var world := bounds_rect()
	for key in selected:
		var target := item(key)
		if target.is_empty() or not world.has_point(point(target) + delta):
			return
		if target.has("w") and not world.encloses(Rect2(item_rect(SECTIONS[key.x], target).position + delta, item_rect(SECTIONS[key.x], target).size)):
			return
	edit()
	for key in selected:
		var target := item(key)
		target.x = int(float(target.x) + delta.x)
		target.y = int(float(target.y) + delta.y)


func delete_item(selected: Vector2i) -> void:
	delete_items([selected])


func delete_items(selected: Array[Vector2i]) -> void:
	var ordered := selected.filter(func(key: Vector2i) -> bool: return not item(key).is_empty())
	if ordered.is_empty():
		return
	edit()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	for key in ordered:
		var section: String = SECTIONS[key.x]
		var removed: Dictionary = data[section][key.y]
		if section == "doors":
			for lever in data.switches:
				lever.targets.erase(removed.id)
		elif section == "switches":
			for gate in data.exits:
				if gate.has("requires"):
					gate.requires.erase(removed.id)
		data[section].remove_at(key.y)


func set_item_properties(selected: Vector2i, changes: Dictionary) -> bool:
	var target := item(selected)
	if target.is_empty():
		return false
	var updated := target.duplicate(true)
	updated.merge(changes, true)
	if not bounds_rect().has_point(point(updated)):
		return false
	if updated.has("w"):
		var rectangle := item_rect(SECTIONS[selected.x], updated)
		if not rectangle.has_area() or not bounds_rect().encloses(rectangle):
			return false
	if updated != target:
		edit()
		data[SECTIONS[selected.x]][selected.y] = updated
	return true


func resize_item(selected: Vector2i, delta: Vector2) -> void:
	var target := item(selected)
	if not target.has("w") or delta == Vector2.ZERO:
		return
	var width := maxi(GRID, int(float(target.w) + delta.x))
	var height := int(target.h) if SECTIONS[selected.x] == "one_ways" else maxi(GRID, int(float(target.h) + delta.y))
	set_item_properties(selected, {"w": width, "h": height})


func duplicate_item(selected: Vector2i) -> Vector2i:
	var source := item(selected)
	if source.is_empty():
		return selected
	var section: String = SECTIONS[selected.x]
	var copy := source.duplicate(true)
	var area := item_rect(section, source)
	var shift := maxf(GRID, ceilf(area.size.x / GRID) * GRID)
	if not bounds_rect().encloses(Rect2(area.position + Vector2(shift, 0), area.size)):
		shift = -shift
	if not bounds_rect().encloses(Rect2(area.position + Vector2(shift, 0), area.size)):
		return selected
	edit()
	copy.x = int(float(copy.x) + shift)
	if copy.has("id"):
		copy.id = _next_id(section, str(copy.id).get_slice("_", 0))
	data[section].append(copy)
	return Vector2i(selected.x, data[section].size() - 1)


static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 48:
		return false
	for character in id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return id[0] in "abcdefghijklmnopqrstuvwxyz"


static func files() -> PackedStringArray:
	var result := PackedStringArray()
	if DirAccess.dir_exists_absolute(DIR):
		for file in DirAccess.get_files_at(DIR):
			if file.get_extension() == "json" and valid_id(file.get_basename()):
				result.append(file.get_basename())
	return result


static func read(id: String) -> Dictionary:
	return LevelData.read_json(DIR.path_join(id + ".json")) if valid_id(id) else {}


func save() -> Error:
	if not validate().is_empty():
		return ERR_INVALID_DATA
	var created := DirAccess.make_dir_recursive_absolute(DIR)
	if created != OK:
		return created
	var target := DIR.path_join(str(data.id) + ".json")
	var result := write_json(target, data)
	if result == OK:
		saved = data.duplicate(true)
	return result


static func write_json(target: String, payload: Dictionary, atomic := true) -> Error:
	var temporary := target + ".tmp" if atomic else target
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK and atomic:
		result = DirAccess.rename_absolute(temporary, target)
	if result != OK and atomic:
		DirAccess.remove_absolute(temporary)
	return result


func validate() -> PackedStringArray:
	return validate_world(data)


static func validate_world(world: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if world.get("version") != 1 or not world.get("id") is String or not valid_id(world.id) or LVL.has(world.id):
		errors.append(L10N.t("editor.error_id"))
	var area = world.get("bounds")
	if not _point_valid(area) or not _number(area.get("w")) or not _number(area.get("h")):
		return errors + PackedStringArray([L10N.t("editor.error_size")])
	var bounds := rect(area)
	if bounds.position != Vector2.ZERO or bounds.size.x < 640 or bounds.size.y < 384 or bounds.size.x > MAX_SIZE.x or bounds.size.y > MAX_SIZE.y:
		return errors + PackedStringArray([L10N.t("editor.error_size")])
	for section in SECTIONS:
		if section in RoomLinks.SECTIONS:
			continue
		var rows = world.get(section, [])
		if not rows is Array or rows.size() > 1024:
			errors.append(L10N.t("editor.error_rows", [section]))
			continue
		var ids := {}
		for row in rows:
			if not _point_valid(row) or not bounds.has_point(point(row)):
				errors.append(L10N.t("editor.error_rows", [section]))
				continue
			if section in ["solids", "one_ways"]:
				if not _number(row.get("w")) or not _number(row.get("h")) or not rect(row).has_area() or not bounds.encloses(rect(row)):
					errors.append(L10N.t("editor.error_rows", [section]))
				continue
			var id := str(row.get("id", ""))
			if not valid_id(id) or ids.has(id):
				errors.append(L10N.t("editor.error_rows", [section]))
			ids[id] = true
			if section == "placements" and not DB.has(StringName(str(row.get("def_id", "")))) \
					or section == "props" and PDB.get_def(StringName(str(row.get("def_id", "")))) == null \
					or section == "decor" and not Decor.DECOR_SIZES.has(str(row.get("kind", ""))):
				errors.append(L10N.t("editor.error_rows", [section]))
			elif section == "decor" and row.kind != "banner" and bool(row.get("grounded", true)):
				if not bounds.encloses(Decor.decor_rect(row, world)) or not Decor.decor_has_support(row, world):
					errors.append(L10N.t("editor.error_decor", [id]))
	if not errors.is_empty():
		return errors
	var issues := RoomLinks.issues(world, bounds)
	for issue in issues:
		errors.append(L10N.t("editor.error_link", [issue]))
	if issues.is_empty():
		if not valid_spawn(world, world.get("spawn")):
			errors.append(L10N.t("editor.error_spawn"))
		for entry in world.get("entries", []):
			if not valid_spawn(world, entry):
				errors.append(L10N.t("editor.error_link", [entry.id]))
	# Clones retain gameplay-linked objects only while their data stays valid.
	var triggers = world.get("triggers", [])
	if not triggers is Array:
		errors.append(L10N.t("editor.error_rows", ["triggers"]))
	else:
		for row in triggers:
			if not _point_valid(row) or not bounds.has_point(point(row)) or not valid_id(str(row.get("id", ""))):
				errors.append(L10N.t("editor.error_rows", ["triggers"]))
	return errors


static func valid_spawn(world: Dictionary, spawn: Variant) -> bool:
	if not _point_valid(spawn):
		return false
	var body := Rect2(point(spawn) - Vector2(14, 46), Vector2(28, 46))
	var bounds := rect(world.bounds)
	if not bounds.has_point(point(spawn)) or not bounds.encloses(body):
		return false
	for row in world.get("solids", []):
		if rect(row).intersects(body):
			return false
	for row in world.get("doors", []):
		if row is Dictionary and _point_valid(row) and _number(row.get("w")) and _number(row.get("h")) and RoomLinks.door_rect(row).intersects(body):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _point_valid(value: Variant) -> bool:
	return value is Dictionary and _number(value.get("x")) and _number(value.get("y"))
