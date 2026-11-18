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
var _done := false
var _trail: Array[Vector2] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
	monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var next := global_position + velocity * delta
	var ray := PhysicsRayQueryParameters2D.create(global_position, next + velocity.normalized() * RADIUS, 3)
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		global_position = hit.position
		if hit.collider is Player:
			_on_body_entered(hit.collider)
		else:
			_impact(hit.position, hit.normal)
		return
	_trail.push_front(global_position)
	if _trail.size() > 8:
		_trail.pop_back()
	global_position = next
	life -= delta
	if life <= 0.0 or position.y < -80.0 or position.y > 800.0:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _done:
		return
	if body is Player:
		_done = true
		CombatFx.burst(self, global_position, -velocity, RED, 10)
		body.take_damage(damage, 1.0 if velocity.x >= 0.0 else -1.0)
		queue_free()
	else:
		_impact(global_position, -velocity.normalized())

func _impact(point: Vector2, normal: Vector2) -> void:
	if _done:
		return
	_done = true
	CombatFx.surface(self, point, normal)
	queue_free()

func _draw() -> void:
	for i in range(1, _trail.size()):
		draw_line(to_local(_trail[i - 1]), to_local(_trail[i]), Color(INK, 0.5 * (1.0 - i / 8.0)), 5.0 - i * 0.5, true)
	draw_circle(Vector2.ZERO, RADIUS + 2.0, Color(INK, 0.25))
	draw_circle(Vector2.ZERO, RADIUS, INK)
	draw_circle(-velocity.normalized() * 1.5, 3.0 + sin(life * 28.0) * 0.7, RED)
	draw_line(Vector2(-velocity.normalized().x * 14.0, -velocity.normalized().y * 14.0),
		Vector2.ZERO, Color(INK, 0.45), 2.0)
