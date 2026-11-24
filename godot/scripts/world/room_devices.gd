class_name RoomDevices
extends Node2D

signal activated
signal travel_requested(exit: Dictionary)

const INK := Color("#211b19")
const RED := Color("#a8262c")
const BRASS := Color("#9d6e38")
const PAPER := Color("#eee2c9")
const REACH := 76.0

var active_switches: Array[String] = []
var world: Dictionary
var _barriers: Dictionary[String, CollisionShape2D] = {}


func setup(data: Dictionary, saved_switches: Array) -> void:
	world = data
	for lever in world.get("switches", []):
		if lever.id in saved_switches:
			active_switches.append(lever.id)
	for door in world.get("doors", []):
		var rect := RoomLinks.door_rect(door)
		var body := StaticBody2D.new()
		body.position = rect.get_center()
		body.collision_layer = Player.SOLID_MASK
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.disabled = is_open(door.id)
		body.add_child(collider)
		add_child(body)
		_barriers[door.id] = collider


func is_open(door_id: String) -> bool:
	for lever in world.get("switches", []):
		if lever.id in active_switches and door_id in lever.targets:
			return true
	return false


func nearest(feet: Vector2) -> Dictionary:
	var best := REACH * REACH
	var candidate := {}
	for section in ["switches", "exits"]:
		for item in world.get(section, []):
			var point := RoomLinks.point(item)
			var distance := feet.distance_squared_to(point)
			if distance < best:
				var ray := PhysicsRayQueryParameters2D.create(feet - Vector2(0, 23), point - Vector2(0, 23), Player.SOLID_MASK)
				if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
					continue
				candidate = {"section": section, "item": item}
				best = distance
	return candidate


func available(candidate: Dictionary) -> bool:
	if candidate.is_empty():
		return false
	var item: Dictionary = candidate.item
	if candidate.section == "switches":
		return item.id not in active_switches
	for id in item.get("requires", []):
		if id not in active_switches:
			return false
	return true


func interact(candidate: Dictionary) -> bool:
	if not available(candidate):
		return false
	var item: Dictionary = candidate.item
	if candidate.section == "exits":
		travel_requested.emit(item)
		return true
	active_switches.append(item.id)
	for id in item.targets:
		if _barriers.has(id):
			_barriers[id].set_deferred("disabled", true)
	queue_redraw()
	activated.emit()
	return true


func _draw() -> void:
	if world.is_empty():
		return
	for row in world.get("doors", []):
		var rect := RoomLinks.door_rect(row)
		var opened := is_open(row.id)
		draw_rect(rect.grow(4), INK, false, 5)
		if opened:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 18)), INK)
			continue
		draw_rect(rect, Color("#50403a"))
		for y in range(int(rect.position.y + 20), int(rect.end.y), 24):
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), INK, 3)
		draw_circle(rect.get_center(), 6, BRASS)
	for row in world.get("switches", []):
		var feet := RoomLinks.point(row)
		var enabled: bool = row.id in active_switches
		var joint := feet - Vector2(0, 16)
		var knob := joint + Vector2(15 if enabled else -15, -24)
		draw_rect(Rect2(feet - Vector2(17, 11), Vector2(34, 11)), INK)
		draw_line(feet, joint, INK, 5)
		draw_line(joint, knob, INK, 5, true)
		draw_circle(knob, 7, BRASS if enabled else RED, true, -1, true)
	for row in world.get("exits", []):
		var feet := RoomLinks.point(row)
		var start := feet - Vector2(27, 88)
		draw_rect(Rect2(start, Vector2(54, 88)), Color(INK, 0.42))
		draw_rect(Rect2(start, Vector2(54, 88)), INK, false, 4)
		var point := feet - Vector2(0, 44)
		if row.get("finish", false):
			draw_line(point + Vector2(-10, 0), point + Vector2(-3, 7), BRASS, 4)
			draw_line(point + Vector2(-3, 7), point + Vector2(11, -9), BRASS, 4)
			continue
		draw_line(point - Vector2(12, 0), point + Vector2(12, 0), PAPER, 3)
		draw_line(point + Vector2(12, 0), point + Vector2(4, -8), PAPER, 3)
		draw_line(point + Vector2(12, 0), point + Vector2(4, 8), PAPER, 3)
