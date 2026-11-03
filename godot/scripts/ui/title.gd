extends Control

## Титульный экран каркаса: заголовок Underdog, меню без мыши.

signal start_pressed
signal quit_pressed

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.55)

const ITEMS := ["ИГРАТЬ", "ВЫХОД"]

var selected := 0
var _wob := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _physics_process(delta: float) -> void:
	_wob += delta
	if CTL.pressed("down"):
		selected = (selected + 1) % ITEMS.size()
	if CTL.pressed("up"):
		selected = (selected + ITEMS.size() - 1) % ITEMS.size()
	if CTL.confirm():
		if selected == 0:
			start_pressed.emit()
		else:
			quit_pressed.emit()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_circle(Vector2(size.x * 0.78, 180.0), 128.0, Color(RED, 0.9))
	draw_circle(Vector2(size.x * 0.78, 180.0), 132.0, Color(RED, 0.2))

	draw_string(FONT_TITLE, Vector2(88.0, 200.0), "ЧЕРНИЛЬНЫЙ", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, INK)
	draw_string(FONT_TITLE, Vector2(84.0, 320.0), "КЛИНОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 112, INK)

	var pts := PackedVector2Array()
	var x := 88.0
	while x < 470.0:
		pts.append(Vector2(x, 340.0 + sin(x * 0.22) * 1.6))
		x += 8.0
	draw_polyline(pts, RED, 4.0)

	draw_string(FONT_TEXT, Vector2(92.0, 372.0), "ТРЕНИРОВОЧНАЯ ЗАЛА · КАРКАС", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GRAY)

	for i in ITEMS.size():
		var y := 470.0 + i * 62.0
		var on := i == selected
		if on:
			var box := PackedVector2Array([
				Vector2(84.0, y - 34.0),
				Vector2(384.0, y - 36.0),
				Vector2(386.0, y + 8.0),
				Vector2(86.0, y + 10.0),
			])
			draw_colored_polygon(box, Color(INK, 0.06))
			draw_rect(Rect2(84.0, y - 34.0, 5.0, 44.0), RED)
		draw_string(FONT_BOLD, Vector2(104.0, y), ITEMS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK if on else Color(INK, 0.55))

	draw_string(FONT_TEXT, Vector2(88.0, size.y - 40.0),
		"%s / %s — выбор   ·   %s — подтвердить   ·   %s — отладка" % [
			CTL.label_key("up"), CTL.label_key("down"), CTL.label_key("jump"), CTL.label_key("help")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GRAY)

	draw_string(FONT_TEXT, Vector2(size.x - 210.0, size.y - 40.0), "каркас · v0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GRAY)
