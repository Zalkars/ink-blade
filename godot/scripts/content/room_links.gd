class_name RoomLinks
extends RefCounted

const SECTIONS := ["doors", "switches", "entries", "exits"]


static func find(world: Dictionary, section: String, id: String) -> Dictionary:
	var items = world.get(section, [])
	if not items is Array:
		return {}
	for item in items:
		if item is Dictionary and item.get("id") == id:
			return item
	return {}


static func point(item: Dictionary) -> Vector2:
	return Vector2(float(item.x), float(item.y))


static func door_rect(item: Dictionary) -> Rect2:
	var size := Vector2(float(item.w), float(item.h))
	return Rect2(point(item) - Vector2(size.x * 0.5, size.y), size)


static func issues(world: Dictionary, bounds: Rect2) -> PackedStringArray:
	var result := PackedStringArray()
	var ids := {}
	for section in SECTIONS:
		var items = world.get(section, [])
		if not items is Array or items.size() > 1024:
			result.append(section)
			continue
		ids[section] = {}
		for item in items:
			if not item is Dictionary or not item.get("id") is String or item.id.is_empty() \
					or ids[section].has(item.id) or not _number(item.get("x")) or not _number(item.get("y")) \
					or not bounds.has_point(point(item)):
				result.append(section + "/" + str(item.get("id", "?")) if item is Dictionary else section)
				continue
			ids[section][item.id] = true
			if section == "doors" and (not _number(item.get("w")) or not _number(item.get("h")) \
					or not door_rect(item).has_area() or not bounds.encloses(door_rect(item))):
				result.append("doors/" + item.id)
	if not result.is_empty():
		return result
	for lever in world.get("switches", []):
		if not _valid_ids(lever.get("targets"), ids.doors) or lever.targets.is_empty():
			result.append("switches/" + lever.id)
	for gate in world.get("exits", []):
		var finish = gate.get("finish", false)
		if not finish is bool or not gate.get("level", "") is String or not gate.get("entry", "") is String \
				or not _valid_ids(gate.get("requires", []), ids.switches) \
				or (finish and (not gate.get("level", "").is_empty() or not gate.get("entry", "").is_empty())) \
				or (not finish and gate.get("level", "").is_empty()):
			result.append("exits/" + gate.id)
	return result


static func connects(exit: Dictionary, target: Dictionary) -> bool:
	var entry := str(exit.get("entry", ""))
	return not target.is_empty() and (entry.is_empty() or not find(target, "entries", entry).is_empty())


static func _valid_ids(values: Variant, catalog: Dictionary) -> bool:
	if not values is Array:
		return false
	for id in values:
		if not id is String or not catalog.has(id):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
