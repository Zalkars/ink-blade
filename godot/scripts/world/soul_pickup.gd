class_name SoulPickup
extends Area2D

signal collected(placement_id: String, display_name_key: String)

var definition: PropDef
var placement_id: String
var _collected := false


func _ready() -> void:
	body_entered.connect(_collect)


func _collect(body: Node2D) -> void:
	if _collected or not body is Player or body.dead or definition == null:
		return
	_collected = true
	body.soul = minf(99.0, body.soul + definition.soul_amount)
	collected.emit(placement_id, definition.display_name_key)
	queue_free()


func _draw() -> void:
	var shape := PackedVector2Array([Vector2(0, -25), Vector2(11, -10), Vector2(0, 1), Vector2(-11, -10)])
	var edge := shape.duplicate()
	edge.append(shape[0])
	draw_colored_polygon(shape, Color("#9c1f24"))
	draw_polyline(edge, Color("#17130f"), 2.0, true)
	draw_line(Vector2(0, -21), Vector2(-6, -11), Color("#f1e6d0"), 2.0, true)
