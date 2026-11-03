class_name Checkpoint
extends Area2D

## Чекпоинт: чернильная метка на полу. Игрок касается — уровень запоминает точку,
## а GameFlow пишет автосейв. Позиция задаётся по ногам, как и точка входа уровня.

signal reached(id: String, pos: Vector2)

const INK := Color("#17130f")
const RED := Color("#9c1f24")

const RADIUS := 40.0
const FOOT_OFFSET := 26.0

var id := ""
var active := false

var _t := 0.0


func setup(cp_id: String, feet: Vector2) -> void:
	id = cp_id
	position = feet - Vector2(0.0, FOOT_OFFSET)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	shape.position = Vector2(0.0, FOOT_OFFSET)
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	queue_redraw()


func activate() -> void:
	if active:
		return
	active = true
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		reached.emit(id, position + Vector2(0.0, FOOT_OFFSET))


func _draw() -> void:
	# Столбик чернил и метка: до активации приглушённая, после — красная.
	var col := RED if active else Color(INK, 0.42)
	var sway := sin(_t * 1.7) * 1.3
	var tip := Vector2(sway, -20.0)
	draw_line(Vector2(0.0, FOOT_OFFSET), tip, col, 3.0)
	draw_circle(tip, 5.0 if active else 4.0, col)
	if active:
		draw_arc(tip, 11.0, 0.0, TAU, 22, Color(RED, 0.45), 1.5)
