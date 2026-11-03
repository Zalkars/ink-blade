class_name InkBolt
extends Area2D

## Чернильный болт часового: летит по прямой, ранит игрока и исчезает.
## Живёт в сцене уровня, поэтому убирается вместе с ним.

const SPEED := 420.0
const LIFETIME := 3.0
const RADIUS := 6.0

const INK := Color("#17130f")
const RED := Color("#9c1f24")

var velocity := Vector2.ZERO
var damage := 1
var life := LIFETIME


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0 or position.y < -80.0 or position.y > 800.0:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.take_damage(damage, 1.0 if velocity.x >= 0.0 else -1.0)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 2.0, Color(INK, 0.25))
	draw_circle(Vector2.ZERO, RADIUS, RED)
	draw_line(Vector2(-velocity.normalized().x * 14.0, -velocity.normalized().y * 14.0),
		Vector2.ZERO, Color(INK, 0.45), 2.0)
