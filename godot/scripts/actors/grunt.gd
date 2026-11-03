class_name Grunt
extends CharacterBody2D

## Простейший враг основы: идёт к игроку, бьёт касанием, умирает от двух ударов.
## Здесь же проверяется главное требование каркаса: враг — сцена, а не RefCounted
## внутри game.gd, и добавляется он данными уровня.

signal died(grunt: Grunt)

const MAX_HP := 2
const SPEED := 95.0
const CHASE_RANGE := 560.0
const GRAVITY := 1900.0
const MAX_FALL := 950.0
const TOUCH_RANGE := Vector2(30.0, 34.0)
const TOUCH_DAMAGE := 1
const TOUCH_COOLDOWN := 0.8
const KNOCKBACK := 460.0
const HURT_TIME := 0.14

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const BONE := Color("#d9cdb8")

var hp := MAX_HP
var target: Player
var dead := false

var hit_t := 0.0
var touch_cd := 0.0
var _wob := 0.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	_wob += delta
	hit_t = maxf(0.0, hit_t - delta)
	touch_cd = maxf(0.0, touch_cd - delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	var dir := 0.0
	if target != null and not target.dead and target.global_position.distance_to(global_position) < CHASE_RANGE:
		var dx := target.global_position.x - global_position.x
		if absf(dx) > 12.0:
			dir = signf(dx)
		if absf(dx) < TOUCH_RANGE.x and absf(target.global_position.y - global_position.y) < TOUCH_RANGE.y:
			_touch_player(dx)

	velocity.x = move_toward(velocity.x, dir * SPEED, 900.0 * delta)
	move_and_slide()
	queue_redraw()


func _touch_player(dx: float) -> void:
	if touch_cd > 0.0 or target == null:
		return
	touch_cd = TOUCH_COOLDOWN
	target.take_damage(TOUCH_DAMAGE, 1.0 if dx >= 0.0 else -1.0)


func hit(damage: int, from_dir: int) -> void:
	if dead:
		return
	hp -= damage
	hit_t = HURT_TIME
	velocity.x = -from_dir * KNOCKBACK
	velocity.y = -180.0
	if hp <= 0:
		dead = true
		died.emit(self)
		queue_free()


func _draw() -> void:
	var ink := INK
	if hit_t > 0.0:
		ink = BONE
	var sway := sin(_wob * 3.0) * 1.8
	var pts := PackedVector2Array([
		Vector2(-9.0, -20.0),
		Vector2(8.0, -21.0),
		Vector2(16.0 + sway * 0.4, 4.0),
		Vector2(12.0, 20.0),
		Vector2(-12.0, 20.0),
		Vector2(-16.0 + sway * 0.4, 3.0),
	])
	draw_colored_polygon(pts, ink)
	draw_circle(Vector2(-4.5, -8.0), 2.2, RED)
	draw_circle(Vector2(4.5, -8.0), 2.2, RED)
