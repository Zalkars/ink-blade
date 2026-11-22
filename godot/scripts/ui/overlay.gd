extends Control

## Одно окно на три состояния: пауза, смерть, зал очищен (включая выбор ручных слотов).
## Оформлено в чернильном стиле 0.2 через InkR; работает на паузе.

signal chosen(action: String)

enum Mode { PAUSE, DEAD, CLEARED }

const UIText := preload("res://scripts/ui/ink_ui_text.gd")
const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const CREAM := Color("#f6edda")

var flow: Node
var mode := Mode.PAUSE
var heading := ""
var sub := ""
var stats := ""
var actions: Array[String] = []
var labels: Array[String] = []
var input_guard := 0.0
var selected := 0
var _slots_open := false
var _confirm_restart := false
var _restart_sub := ""
var _death_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	InkR.init_static()
	visible = false


func open(m: int, subtitle: String = "") -> void:
	mode = m
	_confirm_restart = false
	selected = 0
	sub = subtitle
	_slots_open = false
	_death_t = 0.0
	stats = flow.stats_line() if flow != null and flow.has_method("stats_line") else ""
	input_guard = 0.95 if m == Mode.DEAD else 0.0
	match m:
		Mode.PAUSE:
			heading = L10N.t("ui.pause.title")
			_set_items([
				["resume", "ui.pause.resume"],
				["slots", "ui.pause.slots"],
				["settings", "MENU_SETTINGS"],
				["restart", "ui.pause.restart"],
				["menu", "ui.pause.menu"],
			])
		Mode.DEAD:
			heading = L10N.t("DEATH_TITLE")
			sub = L10N.t("DEATH_SUB")
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


func _open_save_slots() -> void:
	_slots_open = true
	selected = 0
	sub = L10N.t("ui.slots.subtitle_save")
	actions.clear()
	labels.clear()
	for i in SaveGame.MANUAL_SLOTS.size():
		var key: String = SaveGame.MANUAL_SLOTS[i]
		actions.append("save_slot_%d" % (i + 1))
		labels.append("%s — %s" % [L10N.t("ui.slots.slot", [i + 1]), SaveGame.slot_summary(key)])
	actions.append("slots_back")
	labels.append(L10N.t("ui.slots.back"))
	queue_redraw()


func request_restart() -> void:
	if _confirm_restart:
		return
	_restart_sub = sub
	_confirm_restart = true
	_slots_open = false
	selected = 0
	input_guard = 0.3
	heading = L10N.t("ui.new_game.title")
	sub = L10N.t("ui.new_game.warning")
	stats = ""
	_set_items([["cancel_restart", "ui.new_game.cancel"], ["confirm_restart", "ui.new_game.confirm"]])
	for action in ["jump", "attack", "pause", "back", "restart"]:
		CTL.consume(action)
	queue_redraw()


func handle_back() -> bool:
	if _confirm_restart:
		open(mode, _restart_sub)
		return true
	if _slots_open:
		open(Mode.PAUSE, L10N.t("ui.overlay.subtitle", [flow._level_name()]) if flow != null else "")
		return true
	return false


func _set_items(rows: Array) -> void:
	actions.clear()
	labels.clear()
	for row in rows:
		actions.append(String(row[0]))
		labels.append(L10N.t(String(row[1])))


func close() -> void:
	_slots_open = false
	visible = false


func _physics_process(delta: float) -> void:
	if not visible:
		return
	if mode == Mode.DEAD:
		_death_t += delta
	if input_guard > 0:
		input_guard = maxf(0.0, input_guard - delta)
		queue_redraw()
		return
	if CTL.pressed("down"):
		selected = (selected + 1) % actions.size()
	if CTL.pressed("up"):
		selected = (selected + actions.size() - 1) % actions.size()
	if mode == Mode.PAUSE and CTL.back():
		if handle_back():
			return
		chosen.emit("resume")
		return
	if CTL.confirm():
		activate(selected)
		return
	queue_redraw()


func activate(i: int) -> void:
	if input_guard > 0.0 or i < 0 or i >= actions.size():
		return
	selected = i
	var act := actions[i]
	if act == "restart":
		request_restart()
		return
	if act == "cancel_restart":
		handle_back()
		return
	if act == "confirm_restart":
		for action in ["jump", "attack", "pause", "back", "restart"]:
			CTL.consume(action)
		chosen.emit("confirm_restart")
		return
	if act == "slots":
		_open_save_slots()
		return
	if act == "slots_back":
		handle_back()
		return
	if act.begins_with("save_slot_"):
		chosen.emit(act)
		_open_save_slots()
		return
	chosen.emit(act)


func _panel_rect() -> Rect2:
	var w := minf(560.0 if _slots_open else 480.0, size.x - 80.0)
	var h := 196.0 + float(labels.size()) * 52.0 + 56.0
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 - 6.0, w, h)


func item_rect(i: int) -> Rect2:
	if mode == Mode.DEAD:
		var bw := minf(420.0, size.x - 100.0)
		return Rect2((size.x - bw) * 0.5, 424.0 + float(i) * 60.0, bw, 48.0)
	var pr := _panel_rect()
	return Rect2(pr.position.x + 28.0, pr.position.y + 148.0 + float(i) * 52.0, pr.size.x - 56.0, 44.0)


func _draw() -> void:
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_death_t if mode == Mode.DEAD else 0.0)

	var vp := get_viewport_rect().size
	if mode == Mode.DEAD:
		_draw_dead(vp)
		return

	# Полноэкранная подложка бумаги + радиальная виньетка (с учётом safe area).
	InkR.save()
	InkR.t_translate(-position.x, -position.y)
	InkR.fill_rect_color(0.0, 0.0, vp.x, vp.y, PAPER, 0.74)
	InkR.radial_rect(0.0, 0.0, vp.x, vp.y, vp.x * 0.5, vp.y * 0.48, maxf(vp.x, vp.y) * 0.65, [
		[0.0, InkR.rgba(60, 10, 14, 0)],
		[1.0, InkR.rgba(39, 8, 11, 87)],
	])
	InkR.restore()

	var pr := _panel_rect()
	_draw_ink_panel(pr, heading)

	if not sub.is_empty():
		UIText.paragraph(self, FONT_TEXT, sub, Rect2(pr.position.x + 24.0, pr.position.y + 62.0, pr.size.x - 48.0, 74.0), 14, Color(INK, 0.68))
	if not stats.is_empty():
		InkR.text(stats, pr.position.x + pr.size.x * 0.5, pr.position.y + 104.0, 11.0,
			InkR.F_DISPLAY, InkR.A_CENTER, INK, 0.46, 0.8)

	for i in labels.size():
		var r := item_rect(i)
		var on := i == selected
		var cy := r.position.y + r.size.y * 0.5
		if on:
			InkR.srand(600 + i)
			InkR.fill_poly([
				Vector2(r.position.x + 6.0, r.position.y + 4.0),
				Vector2(r.position.x + 12.0, r.end.y - 4.0),
				Vector2(r.end.x - 6.0, r.end.y - 6.0),
				Vector2(r.end.x - 12.0, r.position.y + 6.0),
			], InkR.rgba(156, 33, 41, 34), 1.0, 0.8)
			InkR.fill_poly([
				Vector2(r.position.x + 14.0, cy - 7.0),
				Vector2(r.position.x + 26.0, cy),
				Vector2(r.position.x + 14.0, cy + 7.0),
				Vector2(r.position.x + 19.0, cy),
			], RED, 1.0, 0.5)
		var col := RED if on else INK
		var sz := 17 if _slots_open else 20
		while sz > 12 and FONT_BOLD.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > r.size.x - 56.0:
			sz -= 1
		draw_string(FONT_BOLD, Vector2(r.position.x + 36.0, cy + 7.0), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56.0, sz, Color(col, 1.0 if on else 0.78))
		if actions[i] in ["settings", "slots"]:
			draw_string(FONT_BOLD, Vector2(r.end.x - 28.0, cy + 7.0), "›",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.7 if on else 0.35))

	InkR.line(pr.position.x + 30.0, pr.end.y - 52.0, pr.end.x - 30.0, pr.end.y - 52.0, 1.0, InkR.rgba(23, 19, 15, 46), 1.0, 0.8)



func _draw_ink_panel(pr: Rect2, title_text: String) -> void:
	var x := pr.position.x
	var y := pr.position.y
	var w := pr.size.x
	var h := pr.size.y
	InkR.srand(int(x * 3.0 + y))
	InkR.save()
	InkR.alpha_push(0.35)
	InkR.fill_rect_color(x + 8.0, y + 9.0, w, h, INK, 1.0)
	InkR.restore()

	InkR.rect(x, y, w, h, InkR.rgba(246, 237, 218, 246), INK, 2.6, 1.0, 1.1)
	InkR.rect(x + 6.0, y + 6.0, w - 12.0, h - 12.0, null, InkR.rgba(23, 19, 15, 46), 1.0, 1.0, 0.7)

	var m := 12.0
	for c in [
		[x + m, y + m, 1.0, 1.0], [x + w - m, y + m, -1.0, 1.0],
		[x + m, y + h - m, 1.0, -1.0], [x + w - m, y + h - m, -1.0, -1.0],
	]:
		InkR.line(c[0], c[1], c[0] + 12.0 * c[2], c[1], 1.4, InkR.rgba(23, 19, 15, 89), 1.0, 1.0)
		InkR.line(c[0], c[1], c[0], c[1] + 12.0 * c[3], 1.4, InkR.rgba(23, 19, 15, 89), 1.0, 1.0)

	InkR.text(title_text, x + w * 0.5, y + 44.0, 30.0, InkR.F_TITLE, InkR.A_CENTER, INK, 1.0, 3.0)
	InkR.line(x + 34.0, y + 58.0, x + w - 34.0, y + 58.0, 2.0, InkR.rgba(156, 33, 41, 160), 1.0, 1.0)

	InkR.save()
	InkR.alpha_push(0.72)
	InkR.circle(x + w - 28.0, y + h - 28.0, 11.0, null, RED, 1.6, 1.0, 0.8, 10)
	InkR.text(L10N.t("PANEL_SEAL"), x + w - 28.0, y + h - 23.0, 12.0, InkR.F_DISPLAY, InkR.A_CENTER, RED)
	InkR.restore()


func _draw_dead(vp: Vector2) -> void:
	if _death_t < 0.72:
		var fade := clampf(_death_t / 0.72, 0.0, 1.0) * 0.62
		InkR.save()
		InkR.t_translate(-position.x, -position.y)
		InkR.fill_rect_color(0.0, 0.0, vp.x, vp.y, InkR.rgba(18, 13, 10, 255), fade)
		InkR.restore()
		return

	var reveal := clampf((_death_t - 0.72) / 0.35, 0.0, 1.0)
	var bg_alpha := lerpf(0.62, 0.80, reveal)
	InkR.save()
	InkR.t_translate(-position.x, -position.y)
	InkR.alpha_push(bg_alpha)
	InkR.fill_rect_color(0.0, 0.0, vp.x, vp.y, InkR.rgba(17, 12, 9, 255), 1.0)
	InkR.alpha_pop()
	InkR.radial_rect(0.0, 0.0, vp.x, vp.y, vp.x * 0.5, vp.y * 0.45, 560.0, [
		[0.0, InkR.rgba(120, 20, 28, int(84 * reveal))],
		[1.0, InkR.rgba(120, 20, 28, 0)],
	])
	InkR.restore()

	var cx := size.x * 0.5
	InkR.srand(801)
	InkR.blob(cx - 170.0, 260.0, 110.0, InkR.rgba(120, 25, 30, int(64 * reveal)), null, 2.0, 1.0, 0.6, 10, 0.13, false, 4.0)
	InkR.blob(cx + 190.0, 245.0, 84.0, InkR.rgba(120, 25, 30, int(51 * reveal)), null, 2.0, 1.0, 0.6, 10, 0.13, false, 4.0)
	InkR.blob(cx, 268.0, 170.0, InkR.rgba(20, 15, 11, int(170 * reveal)), null, 2.0, 1.0, 0.6, 10, 0.13, false, 3.0)

	InkR.text(heading, cx, 258.0, 42.0, InkR.F_TITLE, InkR.A_CENTER, CREAM, reveal, 0.0, 2.0)
	InkR.line(cx - 240.0, 280.0, cx + 240.0, 280.0, 3.0, RED, reveal, 1.8)
	if not sub.is_empty():
		InkR.text(sub, cx, 312.0, 18.0, InkR.F_HAND, InkR.A_CENTER, CREAM, 0.62 * reveal)
	if not stats.is_empty():
		InkR.text(stats, cx, 354.0, 13.0, InkR.F_DISPLAY, InkR.A_CENTER, CREAM, 0.66 * reveal, 1.0)

	for i in labels.size():
		var r := item_rect(i)
		var on := i == selected
		var fill := InkR.rgba(156, 33, 41, int(215 * reveal)) if on else InkR.rgba(23, 19, 15, int(175 * reveal))
		var edge := RED if on else InkR.rgba(246, 237, 218, int(130 * reveal))
		InkR.srand(820 + i)
		InkR.rect(r.position.x, r.position.y, r.size.x, r.size.y, fill, edge, 2.2 if on else 1.4, reveal, 0.8)
		draw_string(FONT_BOLD, Vector2(r.position.x, r.position.y + 32.0), labels[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color(CREAM, reveal))

	InkR.text(L10N.t("DEATH_TAGLINE"), cx, size.y - 48.0, 14.0, InkR.F_HAND, InkR.A_CENTER, CREAM, 0.45 * reveal)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in actions.size():
			if item_rect(i).has_point(event.position):
				if selected != i:
					selected = i
					queue_redraw()
				break
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in actions.size():
			if item_rect(i).has_point(event.position):
				activate(i)
				accept_event()
				break
