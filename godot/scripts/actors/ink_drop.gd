class_name InkDrop
extends Area2D

## Капля чернил с потолка. Сначала показывает тонкую красную линию,
## потом падает. Нужна и для удара сверху, и для дождя во второй фазе.

signal landed

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
var _done := false
## Уровень пола: на этой высоте капля считается приземлившейся.
var floor_y := 760.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if not falling:
		if _t >= TELEGRAPH:
			falling = true
			monitoring = true
	else:
		fall_speed = minf(fall_speed + GRAVITY * delta, MAX_FALL)
		position.y += fall_speed * delta
		if position.y >= floor_y:
			_finish()
			return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _done:
		return
	if body is Player:
		body.take_damage(damage, 1.0)
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	landed.emit()
	queue_free()


func _draw() -> void:
	if not falling:
		var a := 0.18 + 0.42 * clampf(_t / TELEGRAPH, 0.0, 1.0)
		var floor_local := floor_y - global_position.y
		draw_line(Vector2.ZERO, Vector2(0.0, floor_local), Color(RED, a), 1.5)
		draw_circle(Vector2(0.0, 2.0), 4.0, Color(RED, a + 0.2))
		return
	draw_circle(Vector2(0.0, -6.0), 6.0, Color(INK, 0.25))
	draw_circle(Vector2.ZERO, RADIUS, INK)
	draw_circle(Vector2(-3.0, -3.0), 3.0, Color(RED, 0.85))
