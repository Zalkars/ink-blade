extends Control

## Одно окно на три состояния: пауза, смерть, зал очищен.
## Живёт в CanvasLayer с process_mode = ALWAYS, поэтому работает и на паузе.
## Наружу отдаёт действие, а не текст: перевод можно менять без правок логики.

signal chosen(action: String)

enum Mode { PAUSE, DEAD, CLEARED }

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")

var mode := Mode.PAUSE
var heading := ""
var sub := ""
var actions: Array[String] = []
var labels: Array[String] = []
var selected := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(m: int, subtitle: String = "") -> void:
	mode = m
	selected = 0
	sub = subtitle
	match m:
		Mode.PAUSE:
			heading = L10N.t("ui.pause.title")
			_set_items([
				["resume", "ui.pause.resume"],
				["restart", "ui.pause.restart"],
				["menu", "ui.pause.menu"],
			])
		Mode.DEAD:
			heading = L10N.t("ui.death.title")
			_set_items([
				["checkpoint", "ui.death.checkpoint"],
				["menu", "ui.death.menu"],
			])
		Mode.CLEARED:
			heading = L10N.t("ui.cleared.title")
			_set_items([
				["menu", "ui.cleared.menu"],
				["restart", "ui.cleared.restart"],
			])
	visible = true
	queue_redraw()


func _set_items(rows: Array) -> void:
	actions.clear()
	labels.clear()
	for row in rows:
		actions.append(String(row[0]))
		labels.append(L10N.t(String(row[1])))


func close() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	if not visible:
		return
	if CTL.pressed("down"):
		selected = (selected + 1) % actions.size()
	if CTL.pressed("up"):
		selected = (selected + actions.size() - 1) % actions.size()
	if mode == Mode.PAUSE and CTL.pressed("back"):
		chosen.emit("resume")
		return
	if CTL.confirm():
		chosen.emit(actions[selected])
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(PAPER, 0.88))
	draw_rect(Rect2(Vector2(0.0, 250.0), Vector2(size.x, 3.0)), Color(RED, 0.7))

	draw_string(FONT_TITLE, Vector2(0.0, 236.0), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 54, INK)
	if not sub.is_empty():
		draw_string(FONT_TEXT, Vector2(0.0, 288.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(INK, 0.6))

	for i in labels.size():
		var y := 366.0 + i * 52.0
		var on := i == selected
		if on:
			draw_line(Vector2(size.x * 0.5 - 150.0, y + 10.0), Vector2(size.x * 0.5 + 150.0, y + 8.0), RED, 2.5)
		draw_string(FONT_BOLD, Vector2(0.0, y), labels[i], HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, INK if on else Color(INK, 0.5))

	draw_string(FONT_TEXT, Vector2(0.0, size.y - 36.0),
		L10N.t("ui.overlay.hint", [CTL.label_key("up"), CTL.label_key("down"), CTL.label_key("jump")]),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(INK, 0.5))
