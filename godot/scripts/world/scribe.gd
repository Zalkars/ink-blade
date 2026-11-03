class_name Scribe
extends Node2D

## Старый Переписчик: ждёт игрока в Архиве, отдаёт кисть.
## Пока только вид и лёгкое дыхание; разговор запускает триггер уровня.

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var sway := sin(_t * 1.1) * 1.2
	# Ряса.
	var robe := PackedVector2Array([
		Vector2(-20.0, 0.0),
		Vector2(-15.0 + sway, -58.0),
		Vector2(15.0 + sway, -58.0),
		Vector2(20.0, 0.0),
	])
	draw_colored_polygon(robe, INK)
	# Капюшон и лицо.
	draw_circle(Vector2(sway, -66.0), 11.0, INK)
	draw_circle(Vector2(sway + 3.0, -67.0), 1.8, RED)
	# Кисть в руке.
	draw_line(Vector2(14.0 + sway, -40.0), Vector2(36.0 + sway, -6.0), Color(INK, 0.8), 3.0)
	draw_line(Vector2(34.0 + sway, -9.0), Vector2(38.0 + sway, -3.0), RED, 3.0)
	# Лист на полу рядом.
	draw_rect(Rect2(-44.0, -3.0, 18.0, 12.0), Color(PAPER, 0.8))
	draw_line(Vector2(-42.0, 1.0), Vector2(-28.0, 1.0), Color(INK, 0.25), 1.0)
