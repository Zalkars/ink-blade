class_name InkDrop
extends EnemyProjectile

## Капля чернил с потолка. Сначала показывает тонкую красную линию,
## потом падает. Нужна и для удара сверху, и для дождя во второй фазе.

signal landed
signal resolved

const TELEGRAPH := 0.55
const GRAVITY := 1500.0
const MAX_FALL := 900.0
const RADIUS := 10.0

const INK := Color("#17130f")
const RED := Color("#9c1f24")

var damage := 1
var falling := false
var fall_speed := 0.0
var _t := 0.0
var _hit_player := false
## Уровень пола: на этой высоте капля считается приземлившейся.
var floor_y := 760.0


func _ready() -> void:
	collision_layer = ATTACK_LAYER
	collision_mask = 2
	monitoring = false
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
	_t += delta
	if not falling:
		if _t >= TELEGRAPH:
			falling = true
			monitoring = true
	else:
		fall_speed = minf(fall_speed + GRAVITY * delta, MAX_FALL)
		var next := global_position + Vector2(0, fall_speed * delta)
		var ray := PhysicsRayQueryParameters2D.create(global_position, next + Vector2(0, RADIUS), 1)
		var ground := get_world_2d().direct_space_state.intersect_ray(ray)
		if not ground.is_empty():
			global_position = ground.position
			CombatFx.surface(self, ground.position, ground.normal, 1.7)
			_finish()
			return
		global_position = next
		if global_position.y >= floor_y + 24.0:
			CombatFx.floor_mark(self, global_position, 1.7)
			_finish()
			return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _done:
		return
	if body is Player and body.dash_t <= 0.0 and not _hit_player:
		_hit_player = true
		set_deferred("monitoring", false)
		body.take_damage(damage, 1.0)
		CombatFx.burst(self, global_position, Vector2.UP, RED, 18)
		# Keep falling after one hit: the heavy slam must still reach the floor
		# and expose the seal, including when the player mistimes a dodge.


func _can_break() -> bool:
	return falling


func _on_broken() -> void:
	_finish(false)


func _finish(ground_contact := true) -> void:
	if _done:
		return
	_done = true
	if ground_contact:
		landed.emit()
	resolved.emit()
	queue_free()


func _draw() -> void:
	if not falling:
		var a := 0.18 + 0.42 * clampf(_t / TELEGRAPH, 0.0, 1.0)
		var floor_local := floor_y - global_position.y
		draw_line(Vector2.ZERO, Vector2(0.0, floor_local), Color(RED, a), 1.5)
		draw_circle(Vector2(0.0, 2.0), 4.0, Color(RED, a + 0.2))
		return
	for i in 4:
		draw_circle(Vector2(sin(_t * 17 + i) * 2, -float(i + 1) * 10), 7.0 - i * 1.5, Color(INK, 0.4 - i * 0.08))
	draw_circle(Vector2(0.0, -6.0), 6.0, Color(INK, 0.25))
	# A heavy drop stretches into a point while falling; its hit radius is unchanged.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -23), Vector2(6, -8), Vector2(10, 0), Vector2(7, 8),
		Vector2(0, 11), Vector2(-7, 8), Vector2(-10, 0), Vector2(-6, -8)]), INK)
	draw_line(Vector2(-3, -8), Vector2(-4, 1), Color(0.94, 0.89, 0.78, 0.65), 1.8, true)
	draw_circle(Vector2(-3.0, -3.0), 3.0, Color(RED, 0.85))
