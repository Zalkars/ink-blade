extends Control

## Катсцена-слайдшоу: процедурный фон, крупная строка, подтверждение.
## Текст берётся ключами из locale, сценарий — из content/cutscenes/<id>.json.
## Живёт в CanvasLayer с process_mode = ALWAYS, поэтому работает на паузе.

signal finished

const DIR := "res://content/cutscenes"

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.55)

var slides: Array = []
var index := 0
var _t := 0.0
var _guard := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play(id: String) -> bool:
	var path := DIR + "/" + id + ".json"
	if not FileAccess.file_exists(path):
		push_error("cutscene: нет файла " + path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("cutscene: плохой JSON " + path)
		return false
	slides = parsed.get("slides", [])
	if slides.is_empty():
		push_error("cutscene: нет слайдов " + path)
		return false
	index = 0
	_t = 0.0
	# Кадр, на котором открыли катсцену, не должен сразу листать слайд.
	_guard = 2
	visible = true
	queue_redraw()
	return true


func close() -> void:
	visible = false
	slides.clear()
	index = 0


func slide_count() -> int:
	return slides.size()


func advance() -> void:
	if not visible:
		return
	index += 1
	_t = 0.0
	if index >= slides.size():
		close()
		finished.emit()
		return
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _guard > 0:
		_guard -= 1
		return
	if CTL.confirm() or CTL.pressed("back"):
		advance()
		return
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if slides.is_empty():
		return
	var slide: Dictionary = slides[index]
	_draw_art(String(slide.get("art", "")))

	draw_line(Vector2(140.0, 430.0), Vector2(size.x - 140.0, 430.0), Color(RED, 0.55), 2.0)
	var text := L10N.t(String(slide.get("text", "")))
	draw_multiline_string(FONT_TITLE, Vector2(140.0, 486.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x - 280.0, 38, 3, INK)

	draw_string(FONT_TEXT, Vector2(0.0, size.y - 58.0),
		L10N.t("cutscene.hint", [CTL.label_key("jump")]),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, GRAY)
	draw_string(FONT_TEXT, Vector2(size.x - 160.0, size.y - 58.0),
		"%d / %d" % [index + 1, slides.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRAY)


## Фон слайда рисуется кодом: у среза ещё нет финального арта,
## но композиция и тон уже заданы.
func _draw_art(kind: String) -> void:
	var base := 360.0
	match kind:
		"city":
			draw_circle(Vector2(960.0, 150.0), 64.0, Color(RED, 0.85))
			draw_circle(Vector2(960.0, 150.0), 72.0, Color(RED, 0.16))
			var heights := [120, 180, 90, 210, 150, 250, 110, 190, 140]
			for i in heights.size():
				var x := 90.0 + i * 112.0
				var h := float(heights[i])
				draw_rect(Rect2(x, base - h, 86.0, h), Color(INK, 0.82))
				for wy in range(int(h / 34.0)):
					draw_circle(Vector2(x + 22.0, base - h + 24.0 + wy * 34.0), 2.2, Color(RED, 0.7))
			draw_line(Vector2(60.0, base), Vector2(size.x - 60.0, base), Color(INK, 0.8), 2.0)
		"ink":
			for k in 5:
				var pts := PackedVector2Array()
				var x := 60.0
				while x < size.x - 60.0:
					pts.append(Vector2(x, 300.0 + k * 34.0 + sin(x * 0.012 + k) * 18.0))
					x += 12.0
				draw_polyline(pts, Color(INK, 0.16 + k * 0.14), 3.0 + k)
			draw_circle(Vector2(380.0, 250.0), 74.0, Color(INK, 0.9))
			draw_circle(Vector2(420.0, 220.0), 34.0, Color(INK, 0.9))
			draw_circle(Vector2(350.0, 215.0), 22.0, Color(INK, 0.9))
			draw_circle(Vector2(400.0, 300.0), 8.0, Color(RED, 0.9))
		"blade":
			draw_rect(Rect2(470.0, 140.0, 340.0, 220.0), Color(1, 1, 1, 0.35))
			draw_rect(Rect2(470.0, 140.0, 340.0, 220.0), Color(INK, 0.35), false, 2.0)
			for i in 6:
				draw_line(Vector2(500.0, 180.0 + i * 28.0), Vector2(760.0, 178.0 + i * 28.0), Color(INK, 0.12), 2.0)
			draw_line(Vector2(360.0, 390.0), Vector2(900.0, 120.0), Color(INK, 0.85), 10.0)
			draw_line(Vector2(370.0, 382.0), Vector2(880.0, 128.0), Color(RED, 0.7), 3.0)
		"hall":
			draw_rect(Rect2(360.0, 120.0, 40.0, 250.0), Color(INK, 0.85))
			draw_rect(Rect2(880.0, 120.0, 40.0, 250.0), Color(INK, 0.85))
			draw_arc(Vector2(640.0, 250.0), 260.0, PI, TAU, 48, Color(INK, 0.85), 18.0)
			draw_circle(Vector2(640.0, 250.0), 46.0, Color(RED, 0.85))
			draw_circle(Vector2(640.0, 250.0), 54.0, Color(RED, 0.18))
			for i in 4:
				draw_rect(Rect2(440.0 + i * 100.0, 370.0, 100.0, 16.0), Color(INK, 0.55))
			draw_line(Vector2(80.0, 386.0), Vector2(size.x - 80.0, 386.0), Color(INK, 0.7), 2.0)
		_:
			draw_circle(Vector2(640.0, 260.0), 90.0, Color(INK, 0.75))
			draw_circle(Vector2(600.0, 230.0), 24.0, Color(RED, 0.8))
