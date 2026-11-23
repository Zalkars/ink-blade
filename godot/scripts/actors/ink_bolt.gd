class_name InkBolt
extends Area2D

## Чернильный болт часового: летит по прямой, ранит игрока и исчезает.
## Живёт в сцене уровня, поэтому убирается вместе с ним.

const SPEED := 420.0
const LIFETIME := 3.0
const RADIUS := 11.0

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
	var par := get_parent()
	if par is Level and par.is_frozen():
		return
	if _done:
		return
	var next := global_position + velocity * delta
	var ray := PhysicsRayQueryParameters2D.create(global_position, next + velocity.normalized() * RADIUS, 3)
	var space := get_world_2d().direct_space_state
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.collider is Player and hit.collider.dash_t > 0.0:
		# Keep sweeping against terrain even when the player is in front of a wall.
		ray.exclude = [hit.collider.get_rid()]
		hit = space.intersect_ray(ray)
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
		if body.dash_t > 0.0:
			return
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
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(LIFETIME - life)
	for i in _trail.size():
		var p := to_local(_trail[i])
		var k := 1.0 - float(i) / maxf(1, _trail.size())
		InkR.srand(i + int(global_position.x))
		InkR.blob(p.x, p.y, RADIUS * k * 0.8, INK, null, 2.0, k * 0.5, 0.8, 10, 0.13, false)
	# Elongated wet core and loose satellite beads follow the shot direction.
	var tail := -velocity.normalized()
	for j in 3:
		var bead := tail * (17.0 + j * 9.0) + tail.orthogonal() * sin(life * 19.0 + j) * 3.0
		draw_circle(bead, 2.4 - j * 0.5, Color(INK, 0.7 - j * 0.13))
	InkR.srand(int(global_position.x))
	InkR.blob(0, 0, RADIUS, INK, INK, 1.5, 1.0, 1.2, 10, 0.12)
	InkR.blob(-2, -1, RADIUS * 0.45, RED, null, 2.0, 1.0, 0.5, 10, 0.13, false)
	InkR.blob(3, -4, 2.2, InkR.CREAM, null, 2.0, 1.0, 0.2, 10, 0.13, false)
