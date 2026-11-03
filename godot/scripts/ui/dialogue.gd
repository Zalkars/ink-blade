extends Control

## Диалог: нижняя панель с именем и репликой, игра на паузе.
## Реплики — content/dialogue/<id>.json, текст — ключи локализации.
## Наружу отдаёт id диалога и id награды, а не текст.

signal finished(dialogue_id: String, grant: String)

const DIR := "res://content/dialogue"

const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.55)

var lines: Array = []
var dialogue_id := ""
var grant := ""
var index := 0
var _t := 0.0
var _guard := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play(id: String) -> bool:
	var path := DIR + "/" + id + ".json"
	if not FileAccess.file_exists(path):
		push_error("dialogue: нет файла " + path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("dialogue: плохой JSON " + path)
		return false
	lines = parsed.get("lines", [])
	if lines.is_empty():
		push_error("dialogue: нет реплик " + path)
		return false
	dialogue_id = id
	grant = String(parsed.get("grant", ""))
	index = 0
	_t = 0.0
	_guard = 2
	visible = true
	queue_redraw()
	return true


func close() -> void:
	visible = false
	lines.clear()
	index = 0


func line_count() -> int:
	return lines.size()


func advance() -> void:
	if not visible:
		return
	index += 1
	if index >= lines.size():
		var id := dialogue_id
		var gift := grant
		close()
		finished.emit(id, gift)
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
	if lines.is_empty():
		return
	var panel_h := 232.0
	var panel_y := size.y - panel_h
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.03, 0.28))
	draw_rect(Rect2(0.0, panel_y, size.x, panel_h), Color(PAPER, 0.97))
	draw_rect(Rect2(0.0, panel_y, size.x, 3.0), Color(RED, 0.8))

	_draw_scribe(Vector2(64.0, panel_y + 62.0))

	var line: Dictionary = lines[index]
	var speaker := L10N.t(String(line.get("speaker", "")))
	if not speaker.is_empty():
		draw_string(FONT_BOLD, Vector2(112.0, panel_y + 46.0), speaker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RED)
	var text := L10N.t(String(line.get("text", "")))
	draw_multiline_string(FONT_TEXT, Vector2(112.0, panel_y + 88.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 184.0, 22, 4, INK)

	draw_string(FONT_TEXT, Vector2(40.0, size.y - 20.0),
		"%d / %d" % [index + 1, lines.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRAY)
	draw_string(FONT_TEXT, Vector2(0.0, size.y - 20.0),
		L10N.t("dialogue.hint", [CTL.label_key("jump")]),
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - 40.0, 14, GRAY)


## Маленький силуэт Переписчика: капюшон, ряса и кисть.
func _draw_scribe(c: Vector2) -> void:
	draw_circle(c + Vector2(0.0, -18.0), 11.0, Color(INK, 0.85))
	var robe := PackedVector2Array([
		c + Vector2(-14.0, -8.0),
		c + Vector2(-20.0, 30.0),
		c + Vector2(20.0, 30.0),
		c + Vector2(14.0, -8.0),
	])
	draw_colored_polygon(robe, Color(INK, 0.85))
	draw_line(c + Vector2(15.0, -16.0), c + Vector2(36.0, 12.0), Color(INK, 0.7), 3.0)
	draw_circle(c + Vector2(36.0, 12.0), 3.0, RED)
