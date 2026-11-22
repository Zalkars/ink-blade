extends Control

## Катсцена-слайдшоу в чернильном стиле 0.2 через InkR: гравюра-вклейка, штриховка,
## живые контуры, бумага и виньетка внутри пластины с сохранением safe-area отступов.

signal finished

const DIR := "res://content/cutscenes"
const LevelDecor := preload("res://scripts/world/level_decor.gd")

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const UIText := preload("res://scripts/ui/ink_ui_text.gd")

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
	InkR.init_static()
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
	var vp := get_viewport_rect().size
	draw_rect(Rect2(-position, vp), PAPER)
	if slides.is_empty():
		return

	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_t)

	var plate_w := minf(980.0, size.x - 160.0)
	var plate_x := (size.x - plate_w) * 0.5
	var plate := Rect2(plate_x, 42.0, plate_w, 368.0)

	# Гравюра-вклейка с бумагой, рамкой и внутренней виньеткой.
	if InkR.tex_paper != null:
		draw_texture_rect(InkR.tex_paper, plate, false)
	else:
		InkR.fill_rect_color(plate.position.x, plate.position.y, plate.size.x, plate.size.y, InkR.PAPER_LIGHT, 1.0)

	var slide: Dictionary = slides[index]
	_draw_art(String(slide.get("art", "")), plate)

	if InkR.tex_vignette != null:
		draw_texture_rect(InkR.tex_vignette, plate, false, Color(1, 1, 1, 0.72))

	InkR.srand(210 + index * 19)
	InkR.rect(plate.position.x, plate.position.y, plate.size.x, plate.size.y, null, INK, 2.2, 1.0, 0.9)
	InkR.rect(plate.position.x + 6.0, plate.position.y + 6.0, plate.size.x - 12.0, plate.size.y - 12.0,
		null, InkR.rgba(23, 19, 15, 58), 1.0, 1.0, 0.5)

	InkR.srand(240 + index)
	InkR.line(140.0, 434.0, size.x - 140.0, 434.0, 2.5, Color(RED, 0.72), 1.0, 1.4)
	var text := L10N.t(String(slide.get("text", "")))
	UIText.paragraph(self, FONT_TITLE, text, Rect2(120.0, 458.0, size.x - 240.0, size.y - 552.0), 36, INK)

	draw_string(FONT_TEXT, Vector2(size.x - 140.0, size.y - 52.0),
		"%d / %d" % [index + 1, slides.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 13, GRAY)


func _draw_art(kind: String, plate: Rect2) -> void:
	var cx := plate.position.x + plate.size.x * 0.5
	var base := plate.end.y - 42.0
	InkR.srand(300 + index * 31)
	match kind:
		"city":
			# Кровавое солнце со штриховкой + силуэты шпилей и набегающий прилив.
			var sx := cx + plate.size.x * 0.24
			var sy := plate.position.y + 104.0
			var sun_pts := InkR.circle_pts(sx, sy, 62.0, 24)
			InkR.fill_poly(sun_pts, InkR.rgba(156, 33, 41, 220), 1.0, 1.5)
			InkR.hatch(sun_pts, 8.0, 0.2, INK)
			UIText.engrave(sun_pts, 5.5, INK, 0.52)
			InkR.circle(sx, sy, 64.0, null, InkR.rgba(23, 19, 15, 130), 1.8, 1.0, 1.2, 24)
			for b in [[-84.0, -48.0, 0.0], [-42.0, -72.0, 1.4], [18.0, -82.0, 2.5]]:
				var flap := sin(_t * 2.2 + float(b[2])) * 4.0
				var bx := sx + float(b[0])
				var by := sy + float(b[1])
				InkR.poly([Vector2(bx - 10.0, by + flap), Vector2(bx, by), Vector2(bx + 10.0, by + flap)], 1.6, INK, 0.7, 0.5)

			var heights := [112.0, 178.0, 92.0, 214.0, 146.0, 244.0, 118.0, 186.0, 134.0]
			var step := (plate.size.x - 100.0) / float(heights.size())
			for i in heights.size():
				var bx := plate.position.x + 56.0 + float(i) * step
				var bw := step * 0.76
				var bh: float = heights[i]
				var tower := [
					Vector2(bx, base),
					Vector2(bx, base - bh),
					Vector2(bx + bw * 0.5, base - bh - (26.0 if i % 2 == 1 else 8.0)),
					Vector2(bx + bw, base - bh),
					Vector2(bx + bw, base),
				]
				InkR.srand(320 + i)
				InkR.fill_poly(tower, InkR.rgba(23, 19, 15, 206), 1.0, 0.9, true, INK, 1.6)
				InkR.hatch(tower, 11.0, 0.14, InkR.CREAM)
				UIText.engrave(tower, 11.0, InkR.CREAM, 0.19)
				for wy in range(int(bh / 42.0)):
					InkR.blob(bx + bw * 0.35, base - bh + 28.0 + float(wy) * 38.0, 2.4, InkR.RED_BRIGHT, null, 1.0, 0.85, 0.2, 8, 0.1, false)
			var wave_pts: Array = []
			var wx := plate.position.x + 14.0
			while wx <= plate.end.x - 14.0:
				wave_pts.append(Vector2(wx, base + sin(wx * 0.025 + _t * 2.0) * 6.0))
				wx += 24.0
			wave_pts.append(Vector2(plate.end.x - 14.0, plate.end.y - 10.0))
			wave_pts.append(Vector2(plate.position.x + 14.0, plate.end.y - 10.0))
			InkR.fill_poly(wave_pts, InkR.rgba(23, 19, 15, 225), 1.0, 0.9)
			InkR.line(plate.position.x + 18.0, base, plate.end.x - 18.0, base, 2.2, RED, 0.65, 1.2)
			# Broken reflections carry the city's red windows into the ink tide.
			for i in range(12):
				var rx := plate.position.x + 40.0 + float(i) * (plate.size.x - 80.0) / 12.0
				InkR.line(rx, base + 16.0 + (i % 3) * 6.0, rx + 14.0, base + 17.0 + (i % 3) * 6.0, 1.3, RED, 0.42, 0.5)

		"ink":
			# Волны чернильного прилива и поднимающаяся тварь с красными глазами.
			for k in range(5):
				var pts: Array = []
				var wx := plate.position.x + 18.0
				var y0 := plate.position.y + 170.0 + float(k) * 36.0
				while wx <= plate.end.x - 18.0:
					pts.append(Vector2(wx, y0 + sin(wx * 0.015 + float(k) + _t * (1.2 + float(k) * 0.2)) * 16.0))
					wx += 26.0
				pts.append(Vector2(plate.end.x - 18.0, plate.end.y - 12.0))
				pts.append(Vector2(plate.position.x + 18.0, plate.end.y - 12.0))
				InkR.srand(350 + k)
				InkR.fill_poly(pts, InkR.rgba(23, 19, 15, 42 + k * 38), 1.0, 1.2)
				InkR.poly(pts.slice(0, pts.size() - 2), 2.2 + float(k) * 0.4, INK, 0.35 + float(k) * 0.12, 1.0)

			var mx := cx - 120.0
			var my := plate.position.y + 178.0
			InkR.srand(370)
			InkR.blob(mx, my, 68.0, InkR.rgba(20, 16, 12, 236), INK, 2.4, 1.0, 1.4, 14, 0.18)
			InkR.blob(mx + 42.0, my - 30.0, 32.0, InkR.rgba(20, 16, 12, 236), INK, 2.0, 1.0, 1.2, 10, 0.16)
			InkR.blob(mx - 36.0, my - 26.0, 24.0, InkR.rgba(20, 16, 12, 236), INK, 2.0, 1.0, 1.2, 10, 0.16)
			InkR.blob(mx + 14.0, my + 24.0, 6.5, InkR.RED_BRIGHT, null, 1.0, 0.95, 0.3, 8, 0.12, false)
			InkR.blob(mx - 10.0, my + 22.0, 5.0, InkR.RED_BRIGHT, null, 1.0, 0.95, 0.3, 8, 0.12, false)
			# Перечёркивающие мазки справа.
			for j in range(4):
				var sy := plate.position.y + 92.0 + float(j) * 44.0
				InkR.line(cx + 40.0, sy, cx + 290.0, sy + 8.0, 2.0, INK, 0.35, 1.0)
				InkR.line(cx + 30.0, sy + 6.0, cx + 300.0, sy - 6.0, 4.0, RED, 0.72, 1.6)

		"blade":
			# Чистый лист с печатью и перерезающий его чернильный клинок.
			var page := Rect2(cx - 170.0, plate.position.y + 62.0, 340.0, 242.0)
			InkR.srand(410)
			InkR.rect(page.position.x + 6.0, page.position.y + 7.0, page.size.x, page.size.y, InkR.rgba(23, 19, 15, 44), null, 0.0, 1.0, 0.4, false)
			InkR.rect(page.position.x, page.position.y, page.size.x, page.size.y, InkR.rgba(247, 239, 221, 240), INK, 2.0, 1.0, 0.9)
			for i in range(6):
				var ly := page.position.y + 42.0 + float(i) * 30.0
				InkR.line(page.position.x + 32.0, ly, page.end.x - 36.0, ly - 2.0, 1.6, InkR.rgba(23, 19, 15, 42), 1.0, 0.6)
			InkR.circle(page.end.x - 42.0, page.end.y - 38.0, 14.0, null, RED, 1.8, 0.75, 0.9, 12)
			InkR.text(L10N.t("PANEL_SEAL"), page.end.x - 42.0, page.end.y - 33.0, 14.0, InkR.F_DISPLAY, InkR.A_CENTER, RED, 0.75)
			# Клинок и широкая дуга разреза.
			var p0 := Vector2(cx - 250.0, base + 12.0)
			var p1 := Vector2(cx + 240.0, plate.position.y + 52.0)
			InkR.taper_arc(cx + 10.0, plate.position.y + 210.0, 160.0, -2.5, -0.55, 18.0, 4.0, InkR.rgba(156, 33, 41, 180), 0.9, 1.2)
			InkR.line(p0.x, p0.y, p1.x, p1.y, 10.0, INK, 0.95, 1.1)
			InkR.line(p0.x + 12.0, p0.y - 8.0, p1.x - 16.0, p1.y + 8.0, 3.0, RED, 0.85, 0.8)

		"hall":
			# Колонны, свод, лестница и печать Первого Взмаха.
			LevelDecor.draw_pillar(cx - 260.0, plate.position.y + 34.0, 44.0, base - plate.position.y - 34.0)
			LevelDecor.draw_pillar(cx + 216.0, plate.position.y + 34.0, 44.0, base - plate.position.y - 34.0)
			InkR.arc(cx, plate.position.y + 184.0, 238.0, PI, TAU, 10.0, InkR.rgba(23, 19, 15, 200), 1.0, 1.4, 24)
			var seal_pts := InkR.circle_pts(cx, plate.position.y + 168.0, 52.0, 20)
			InkR.fill_poly(seal_pts, InkR.rgba(156, 33, 41, 210), 1.0, 1.2)
			InkR.hatch(seal_pts, 8.0, 0.16, INK)
			UIText.engrave(seal_pts, 6.0, INK, 0.4)
			InkR.circle(cx, plate.position.y + 168.0, 62.0, null, InkR.rgba(156, 33, 41, 90), 2.0, 1.0, 1.2, 22)
			InkR.line(cx - 32.0, plate.position.y + 168.0, cx + 32.0, plate.position.y + 168.0, 3.0, InkR.CREAM, 0.85, 0.6)
			InkR.line(cx, plate.position.y + 136.0, cx, plate.position.y + 200.0, 3.0, InkR.CREAM, 0.85, 0.6)
			for step_i in range(4):
				var sw := 320.0 + float(step_i) * 60.0
				var sy := base - float(3 - step_i) * 14.0
				InkR.rect(cx - sw * 0.5, sy, sw, 14.0, InkR.rgba(23, 19, 15, 110 + step_i * 22), INK, 1.4, 1.0, 0.7)
			InkR.line(plate.position.x + 36.0, base + 14.0, plate.end.x - 36.0, base + 14.0, 2.4, INK, 0.8, 1.0)

		"pen":
			# Город внизу и огромное перо над ним: зацепка на следующую главу.
			var sky := base + 14.0
			var heights := [72.0, 134.0, 58.0, 162.0, 106.0, 188.0, 86.0, 142.0, 68.0]
			var step := (plate.size.x - 140.0) / float(heights.size())
			for i in heights.size():
				var bx := plate.position.x + 80.0 + float(i) * step
				var h: float = heights[i]
				var box := [Vector2(bx, sky), Vector2(bx, sky - h), Vector2(bx + step * 0.72, sky - h), Vector2(bx + step * 0.72, sky)]
				InkR.fill_poly(box, InkR.rgba(23, 19, 15, 178), 1.0, 0.8, true, INK, 1.4)
			InkR.line(plate.position.x + 28.0, sky, plate.end.x - 28.0, sky, 2.4, INK, 0.85, 1.0)

			var tip := Vector2(cx + 42.0, sky - 56.0)
			var top := Vector2(cx + 280.0, plate.position.y + 24.0)
			var nib := [
				tip,
				Vector2(cx + 126.0, sky - 170.0),
				Vector2(cx + 190.0, sky - 132.0),
			]
			InkR.fill_poly(nib, InkR.rgba(23, 19, 15, 232), 1.0, 0.9, true, INK, 2.0)
			InkR.hatch(nib, 7.0, 0.2, InkR.CREAM)
			UIText.engrave(nib, 7.0, InkR.CREAM, 0.4)
			InkR.line(cx + 158.0, sky - 150.0, top.x, top.y, 12.0, INK, 0.95, 1.2)
			InkR.line(cx + 158.0, sky - 150.0, top.x, top.y, 3.0, RED, 0.6, 0.8)
			InkR.line(tip.x, tip.y, cx + 158.0, sky - 150.0, 1.6, InkR.CREAM, 0.65, 0.4)
			var drop_y := tip.y + 8.0 + absf(sin(_t * 1.8)) * 10.0
			InkR.blob(tip.x, drop_y, 7.5, RED, INK, 1.5, 0.95, 0.4, 9, 0.16)
			InkR.circle(tip.x, drop_y, 16.0, null, InkR.rgba(156, 33, 41, 72), 1.4, 1.0, 0.7, 14)

		_:
			InkR.blob(cx, plate.position.y + 180.0, 82.0, InkR.rgba(23, 19, 15, 185), INK, 2.2)
			InkR.blob(cx - 24.0, plate.position.y + 158.0, 18.0, RED, null)
