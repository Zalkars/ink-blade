extends Control

## Диалог в чернильном стиле 0.2: затемнение и панель на весь viewport (safe-area friendly),
## угловые скобки, печать и силуэт Переписчика через InkR.

signal finished(dialogue_id: String, grant: String)
signal progress_changed

const DIR := "res://content/dialogue"

const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.58)

var lines: Array = []
var dialogue_id := ""
var grant := ""
var index := 0
var _t := 0.0
var _guard := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InkR.init_static()
	visible = false


func play(id: String, resume_line := 0) -> bool:
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
	index = clampi(resume_line, 0, lines.size() - 1)
	_t = 0.0
	_guard = 2
	visible = true
	queue_redraw()
	progress_changed.emit()
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
	progress_changed.emit()


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
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_t)

	var vp := get_viewport_rect().size
	var panel_h := 232.0
	var panel_y := size.y - panel_h
	var top_in_vp := position.y + panel_y

	# Затемнение и панель покрывают весь экран, включая отступы вырезов.
	InkR.save()
	InkR.t_translate(-position.x, -position.y)
	InkR.fill_rect_color(0.0, 0.0, vp.x, vp.y, InkR.rgba(14, 10, 8, 255), 0.32)
	InkR.fill_rect_color(0.0, top_in_vp, vp.x, vp.y - top_in_vp, PAPER, 0.97)
	InkR.line(0.0, top_in_vp, vp.x, top_in_vp, 3.0, RED, 0.85, 1.0)
	InkR.restore()

	InkR.srand(510 + index)
	InkR.line(24.0, panel_y + 12.0, size.x - 24.0, panel_y + 12.0, 1.0, InkR.rgba(23, 19, 15, 42), 1.0, 0.5)
	_draw_scribe(Vector2(64.0, panel_y + 66.0))

	var line: Dictionary = lines[index]
	var speaker := L10N.t(String(line.get("speaker", "")))
	if not speaker.is_empty():
		draw_string(FONT_BOLD, Vector2(114.0, panel_y + 46.0), speaker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RED)
	var text := L10N.t(String(line.get("text", "")))
	draw_multiline_string(FONT_TEXT, Vector2(114.0, panel_y + 88.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 184.0, 22, 4, INK)

	draw_string(FONT_TEXT, Vector2(40.0, size.y - 20.0),
		"%d / %d" % [index + 1, lines.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GRAY)


## Маленький силуэт Переписчика в чернильном стиле.
func _draw_scribe(c: Vector2) -> void:
	InkR.srand(520)
	InkR.blob(c.x, c.y - 18.0, 11.0, InkR.rgba(23, 19, 15, 218), INK, 1.6, 1.0, 0.5, 10, 0.1)
	InkR.fill_poly([
		c + Vector2(-14.0, -8.0),
		c + Vector2(-20.0, 30.0),
		c + Vector2(20.0, 30.0),
		c + Vector2(14.0, -8.0),
	], InkR.rgba(23, 19, 15, 220), 1.0, 0.7, true, INK, 1.5)
	InkR.line(c.x + 15.0, c.y - 16.0, c.x + 36.0, c.y + 12.0, 3.0, INK, 0.85, 0.4)
	InkR.blob(c.x + 36.0, c.y + 12.0, 3.4, RED, null, 1.0, 0.95, 0.3, 8, 0.1, false)
