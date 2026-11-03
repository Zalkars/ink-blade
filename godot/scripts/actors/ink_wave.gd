class_name InkWave
extends Area2D

## Волна чернил от замаха Хранителя: идёт по полу, ранит игрока и исчезает.
## Живёт в сцене уровня, поэтому убирается вместе с ним.

const SPEED := 360.0
const LIFETIME := 2.6
const RADIUS := 14.0

const INK := Color("#17130f")
const RED := Color("#9c1f24")

var velocity := Vector2.ZERO
var damage := 1
var life := LIFETIME
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(44.0, 28.0)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.take_damage(damage, 1.0 if velocity.x >= 0.0 else -1.0)
		queue_free()


func _draw() -> void:
	var dir := 1.0 if velocity.x >= 0.0 else -1.0
	# Гребень волны: три рваные линии, сдвинутые по фазе.
	for k in 3:
		var pts := PackedVector2Array()
		for i in 9:
			var x := -30.0 + i * 8.0
			var y := -12.0 + k * 7.0 + sin(_t * 12.0 + i * 0.8 + k) * 3.0
			pts.append(Vector2(x * dir, y))
		draw_polyline(pts, Color(INK, 0.85 - k * 0.22), 4.0 - k)
	draw_circle(Vector2(-dir * 22.0, 8.0), 3.0, Color(RED, 0.8))
	draw_circle(Vector2(-dir * 8.0, 12.0), 2.0, Color(RED, 0.55))
