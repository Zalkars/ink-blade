class_name InkR
extends RefCounted

## Полный порт модуля Core/Ink.cs (SkiaSharp) рисования "чернилами".
## Статический рендерер, рисующий в текущий CanvasItem (_cv).
## Экспериментальная семантика как в оригинале: глобальная Ink.Alpha влияет
## только на ЗАЛИВКИ (FillPoly/FillCircle/FillRect), а внешние контуры (Poly) нет.

# ---------- палитра (класс C) ----------
const PAPER := Color("#efe4cc")
const PAPER_LIGHT := Color("#f7efdd")
const PAPER_DARK := Color("#ddceac")
const INK := Color("#17130f")
const INK_SOFT := Color("#4a3c2e")
const RED := Color("#9c2129")
const RED_BRIGHT := Color("#c9353a")
const RED_DARK := Color("#651419")
const TEAL := Color("#2c6f6b")
const GOLD := Color("#b8923f")
const CREAM := Color("#f6edda")
const BONE := Color("#e6d8ba")
const PAPER_COLOR := Color("#efe4cc")

const W := 1280.0
const H := 720.0

# FontKind
const F_TITLE := 0
const F_DISPLAY := 1
const F_BODY := 2
const F_BOLD := 3
const F_ITALIC := 4
const F_HAND := 5

# InkAlign
const A_LEFT := 0
const A_CENTER := 1
const A_RIGHT := 2

# ---------- состояние рендера ----------
static var _cv: CanvasItem = null
static var _alpha := 1.0
static var _alpha_stack: Array = []
static var _tx_stack: Array = []
static var _tx := Transform2D()
static var _boil := 0
static var _seed: int = 123456789
static var _font: Font = null
static var _inited := false

# предсозданные текстуры
static var tex_hatch: ImageTexture = null
static var tex_radial_center: ImageTexture = null
static var tex_radial_edge: ImageTexture = null
static var tex_vgrad: ImageTexture = null        # фон бумаги (3 стопа)
static var tex_floor_grad: ImageTexture = null
static var tex_pit_grad: ImageTexture = null
static var tex_soul_liq: ImageTexture = null     # альфа-градиент шкалы души
static var tex_vignette: ImageTexture = null
static var tex_paper: ImageTexture = null     # запекается позже (bake paper)
static var tex_stage: ImageTexture = null     # запечённый статичный зал
static var tex_title: ImageTexture = null     # запечённый титульный экран

const TAU := 6.283185307179586

# ---------- инициализация ----------
static func init_static() -> void:
	if _inited:
		return
	_inited = true
	_font = ThemeDB.fallback_font
	_make_tex_hatch()
	_make_tex_radials()
	_make_tex_vgrads()
	_make_tex_vignette()

static func begin_frame(real_time: float) -> void:
	_boil = int(real_time * 10.0)

static func ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func rgba(r: int, g: int, b: int, a: int) -> Color:
	return Color(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0, float(a) / 255.0)

# ---------- текстуры ----------
static func _make_tex_hatch() -> void:
	var img := Image.create(64, 1, false, Image.FORMAT_RGBA8)
	for x in range(64):
		var a := clampf(1.0 - absf(float(x) - 4.0) / 4.0, 0.0, 1.0)
		img.set_pixel(x, 0, Color(1, 1, 1, a))
	tex_hatch = ImageTexture.create_from_image(img)

static func _radial_img(size: int, at_center: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var a := clampf(d, 0.0, 1.0)
			if at_center:
				a = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

static func _make_tex_radials() -> void:
	tex_radial_edge = _radial_img(128, false)   # 0 в центре -> 1 на краю
	tex_radial_center = _radial_img(128, true)  # 1 в центре -> 0 на краю

static func _vgrad_tex(colors: Array) -> ImageTexture:
	# colors: массив [Color...] сверху вниз
	var h := 256
	var img := Image.create(1, h, false, Image.FORMAT_RGBA8)
	var n := colors.size() - 1
	for y in range(h):
		var t := float(y) / float(h - 1) * float(n)
		var i := mini(int(t), n - 1)
		var f := t - float(i)
		var c0: Color = colors[i]
		var c1: Color = colors[i + 1]
		img.set_pixel(0, y, Color(lerpf(c0.r, c1.r, f), lerpf(c0.g, c1.g, f), lerpf(c0.b, c1.b, f), lerpf(c0.a, c1.a, f)))
	return ImageTexture.create_from_image(img)

static func _make_tex_vgrads() -> void:
	tex_vgrad = _vgrad_tex([
		Color("#f4ecd9"), Color("#efe4cc"), Color("#e3d4b3")
	])
	tex_floor_grad = _vgrad_tex([rgba(120, 98, 64, 26), rgba(60, 44, 28, 87)])
	tex_pit_grad = _vgrad_tex([rgba(30, 24, 18, 51), rgba(20, 16, 12, 184), rgba(12, 9, 7, 245)])
	tex_soul_liq = _vgrad_tex([rgba(23, 19, 15, 184), rgba(23, 19, 15, 230)])

static func _make_tex_vignette() -> void:
	var w := 256
	var h := 144
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cc := Vector2(w * 0.5, h * 0.5)
	var rad: float = maxf(w, h) * 0.78
	for y in range(h):
		for x in range(w):
			var d := Vector2(x + 0.5 - cc.x, y + 0.5 - cc.y).length() / rad
			var a := 0.0
			if d <= 0.7:
				a = lerpf(0.0, 18.0 / 255.0, d / 0.7)
			else:
				a = lerpf(18.0 / 255.0, 97.0 / 255.0, (d - 0.7) / 0.3)
			img.set_pixel(x, y, Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, clampf(a, 0.0, 1.0)))
	tex_vignette = ImageTexture.create_from_image(img)

# ---------- случайность с boil ----------
static func srand(n: int) -> void:
	var x := (n * 2654435761) & 0xFFFFFFFF
	x = (x ^ ((_boil * 0x9e3779b1) & 0xFFFFFFFF)) & 0xFFFFFFFF
	_seed = x if x != 0 else 123456789

static func rand() -> float:
	var x := _seed & 0xFFFFFFFF
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & 0xFFFFFFFF
	_seed = x
	return float(x) / 4294967296.0

static func rndf(a := 0.0, b := 1.0) -> float:
	return a + (b - a) * rand()

# ---------- канва / трансформации ----------
static func set_canvas(cv: CanvasItem) -> void:
	_cv = cv
	_alpha = 1.0
	_alpha_stack.clear()
	_tx_stack.clear()
	_tx = Transform2D()
	_apply()

static func _apply() -> void:
	if _cv != null:
		_cv.draw_set_transform_matrix(_tx)

static func save() -> void:
	_alpha_stack.append(_alpha)
	_tx_stack.append(_tx)

static func restore() -> void:
	if _tx_stack.is_empty():
		return
	_tx = _tx_stack.pop_back()
	if _alpha_stack.size() > 0:
		_alpha = _alpha_stack.pop_back()
	_apply()

static func t_translate(x: float, y: float) -> void:
	_tx = _tx.translated_local(Vector2(x, y))
	_apply()

static func t_scale(sx: float, sy: float) -> void:
	_tx = _tx.scaled_local(Vector2(sx, sy))
	_apply()

static func t_rotate_deg(deg: float) -> void:
	_tx = _tx.rotated_local(deg * PI / 180.0)
	_apply()

# ручное управление глобальной альфой заливок (Ink.Alpha в оригинале)
static func alpha_push(a: float) -> void:
	_alpha = a

static func alpha_pop() -> void:
	_alpha = _alpha_stack.back() if _alpha_stack.size() > 0 else 1.0

# ---------- фигуры ----------
static func _wobble(pts: Array, amp: float, closed: bool) -> Array:
	var outp: Array = []
	var n := pts.size()
	if n < 2:
		return outp
	var last := n if closed else n - 1
	for i in range(last):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var dx := b.x - a.x
		var dy := b.y - a.y
		var ll := sqrt(dx * dx + dy * dy) + 0.001
		var steps := maxi(1, int(ceil(ll / 9.0)))
		var nx := -dy / ll
		var ny := dx / ll
		var phase := rand() * PI * 2.0
		for s in range(steps):
			var t := float(s) / float(steps)
			var w := sin(t * PI * 2.0 + phase) * 0.55 + (rand() * 2.0 - 1.0) * 0.9
			outp.append(Vector2(a.x + dx * t + nx * w * amp, a.y + dy * t + ny * w * amp))
	if not closed and n > 0:
		outp.append(pts[n - 1])
	return outp

static func _dashed(d: Array, col: Color, width: float, dash: Array) -> void:
	var on_len := float(dash[0])
	var off_len := float(dash[1])
	var segs: Array = []
	var cur := PackedVector2Array()
	var pos := 0.0
	var is_on := true
	for i in range(1, d.size()):
		var a: Vector2 = d[i - 1]
		var b: Vector2 = d[i]
		var dist := a.distance_to(b)
		if dist <= 0.0001:
			continue
		var t := 0.0
		while t < dist - 0.0001:
			var need := (on_len if is_on else off_len) - pos
			var take := minf(dist - t, need)
			if is_on:
				if cur.is_empty():
					cur.append(a.lerp(b, t / dist))
				if t + take >= dist - 0.0001:
					cur.append(b)
				else:
					cur.append(a.lerp(b, (t + take) / dist))
			pos += take
			t += take
			if pos >= need - 0.0001 and need > 0.0:
				if is_on and cur.size() >= 2:
					segs.append(cur)
				cur = PackedVector2Array()
				is_on = not is_on
				pos = 0.0
	if is_on and cur.size() >= 2:
		segs.append(cur)
	for s in segs:
		_cv.draw_polyline(s, col, width, true)

static func poly(pts: Array, width := 2.0, color2 = null, a := 1.0, jitter := 1.15, closed := false, passes := 1, dash = null) -> void:
	if _cv == null or pts.size() < 2:
		return
	var col: Color = color2 if color2 != null else INK
	for p in range(maxi(1, passes)):
		var d := _wobble(pts, jitter * (1.0 if p == 0 else 0.65), closed)
		if d.size() < 2:
			break
		var pcol := ca(col, a)
		var pw := width
		if p > 0:
			pcol = ca(col, a * 0.4)
			pw = width * 0.65
		if dash != null and dash.size() == 2:
			_dashed(d, pcol, pw, dash)
			continue
		var pl := PackedVector2Array(d)
		if closed:
			pl.append(d[0])
		_cv.draw_polyline(pl, pcol, pw, true)

static func line(x1: float, y1: float, x2: float, y2: float, width := 2.0, color2 = null, a := 1.0, jitter := 1.15, dash = null) -> void:
	poly([Vector2(x1, y1), Vector2(x2, y2)], width, color2, a, jitter, false, 1, dash)

static func fill_poly(pts: Array, color2: Color, a := 1.0, jitter := 0.9, outline := false, outline_color = null, outline_width := 2.0, passes := 1) -> void:
	if _cv == null or pts.size() < 3:
		return
	var d: Array = pts if jitter <= 0.0 else _wobble(pts, jitter, true)
	if d.size() < 3:
		return
	var pv := PackedVector2Array(d)
	var tris := Geometry2D.triangulate_polygon(pv)
	if tris.is_empty() and jitter > 0.0:
		pv = PackedVector2Array(pts)
		tris = Geometry2D.triangulate_polygon(pv)
	if not tris.is_empty():
		_cv.draw_polygon(pv, PackedColorArray([ca(color2, _alpha * a)]))
	if outline:
		poly(pts, outline_width, outline_color if outline_color != null else INK, a, jitter, true, passes)

static func rect(x: float, y: float, w: float, h: float, fill = null, color2 = null, width := 2.0, a := 1.0, jitter := 1.15, outline := true, dash = null, passes := 1) -> void:
	var pts := [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	if fill != null:
		fill_poly(pts, fill, a, jitter)
	if outline:
		poly(pts, width, color2 if color2 != null else INK, a, jitter, true, passes, dash)

static func _blob_pts(x: float, y: float, r: float, n: int, wobble: float, phase := 0.0) -> Array:
	var pts: Array = []
	for i in range(n):
		var an := float(i) / float(n) * TAU + phase
		var rr := r * (1.0 - wobble + rand() * wobble * 2.0)
		pts.append(Vector2(x + cos(an) * rr, y + sin(an) * rr))
	return pts

static func blob(x: float, y: float, r: float, fill = null, color2 = null, width := 2.0, a := 1.0, jitter := 0.6, n := 10, wobble := 0.13, outline := true, phase := 0.0) -> void:
	var pts := _blob_pts(x, y, r, n, wobble, phase)
	if fill != null:
		fill_poly(pts, fill, a, jitter)
	if outline:
		poly(pts, width, color2 if color2 != null else INK, a, maxf(0.1, jitter), true)

static func circle(x: float, y: float, r: float, fill = null, color2 = null, width := 2.0, a := 1.0, jitter := 0.5, n := 13, outline := true) -> void:
	var pts: Array = []
	for i in range(n):
		var an := float(i) / float(n) * TAU
		pts.append(Vector2(x + cos(an) * r, y + sin(an) * r))
	if fill != null:
		fill_poly(pts, fill, a, jitter)
	if outline:
		poly(pts, width, color2 if color2 != null else INK, a, maxf(0.1, jitter), true)

static func circle_pts(cx: float, cy: float, r: float, n: int) -> Array:
	var pts: Array = []
	for i in range(n):
		var an := float(i) / float(n) * TAU
		pts.append(Vector2(cx + cos(an) * r, cy + sin(an) * r))
	return pts

static func arc(cx: float, cy: float, r: float, a0: float, a1: float, width := 2.0, color2 = null, a := 1.0, jitter := 0.6, steps := 0, wobble := 0.0) -> void:
	if steps <= 0:
		steps = maxi(6, int(ceil(absf(a1 - a0) * r / 12.0)))
	var pts: Array = []
	for i in range(steps + 1):
		var an := lerpf(a0, a1, float(i) / float(steps))
		var rr := r + (sin(i * 1.7) * wobble if wobble != 0.0 else 0.0)
		pts.append(Vector2(cx + cos(an) * rr, cy + sin(an) * rr))
	poly(pts, width, color2, a, jitter)

static func taper_arc(cx: float, cy: float, r: float, a0: float, a1: float, w0: float, w1: float, color2: Color, a := 1.0, jag := 1.0) -> void:
	var steps := 16
	var outer: Array = []
	var inner: Array = []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var an := lerpf(a0, a1, t)
		var bulge := sin(t * PI)
		var w := lerpf(w0, w1, t) * (0.45 + 0.75 * bulge)
		var rr := r + bulge * 5.0 + (rand() * 2.0 - 1.0) * jag
		var ca_: float = cos(an)
		var sa_: float = sin(an)
		outer.append(Vector2(cx + ca_ * (rr + w * 0.5), cy + sa_ * (rr + w * 0.5)))
		inner.append(Vector2(cx + ca_ * (rr - w * 0.5), cy + sa_ * (rr - w * 0.5)))
	inner.reverse()
	for p in inner:
		outer.append(p)
	fill_poly(outer, color2, a, 0.7)

static func ellipse_shadow(x: float, y: float, rx: float, ry: float, a0 := 0.25) -> void:
	if _cv == null:
		return
	for i in range(3, 0, -1):
		var k := 0.7 + i * 0.12
		var a := a0 * (0.25 + 0.15 * i)
		var pts: Array = []
		var n := 22
		for j in range(n):
			var an := float(j) / float(n) * TAU
			pts.append(Vector2(x + cos(an) * rx * k, y + sin(an) * ry * k))
		_cv.draw_colored_polygon(PackedVector2Array(pts), ca(INK, a))

static func hatch(pts: Array, gap := 8.0, a := 0.25, color2 = null, width := 1.0, cross := false) -> void:
	if _cv == null or pts.size() < 3 or tex_hatch == null:
		return
	var col: Color = color2 if color2 != null else INK
	var per := 2.0 * maxf(4.0, gap)
	var pva := PackedVector2Array(pts)
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var c0 := ca(col, _alpha * a)
	for p in pts:
		uvs.append(Vector2((p.x + p.y) / per, 0.0))
		cols.append(c0)
	_cv.draw_polygon(pva, cols, uvs, tex_hatch)
	if cross:
		var c1 := ca(col, _alpha * a * 0.6)
		uvs = PackedVector2Array()
		cols = PackedColorArray()
		for p in pts:
			uvs.append(Vector2((p.x - p.y) / (per * 1.7), 0.0))
			cols.append(c1)
		_cv.draw_polygon(pva, cols, uvs, tex_hatch)

# ---------- текст ----------
static func measure_text(s: String, size := 22.0, spacing := 0.0) -> float:
	if _font == null:
		return 0.0
	var px := maxi(4, int(round(size)))
	if spacing == 0.0:
		return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var w := 0.0
	for ch in s:
		w += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + spacing
	return maxf(0.0, w - spacing)

static func text(s: String, x: float, y: float, size := 22.0, font_kind := F_BODY, align := A_LEFT, color2: Color = INK, a := 1.0, spacing := 0.0, ghost := 0.0, baseline := 0) -> void:
	if _cv == null or _font == null:
		return
	var px := maxi(4, int(round(size)))
	var total := measure_text(s, size, spacing)
	var tx := x
	if align == A_CENTER:
		tx = x - total * 0.5
	elif align == A_RIGHT:
		tx = x - total
	var ty := y
	if baseline == 1:
		# y — вертикальный центр строки, а не базовая линия
		ty = y + (_font.get_ascent(px) - _font.get_descent(px)) * 0.5
	elif baseline == 2:
		ty = y - _font.get_ascent(px)

	var em := maxf(0.001, a)
	if ghost > 0.0:
		_draw_str(s, tx + ghost, ty + ghost, px, ca(color2, _alpha * em * 0.28), spacing)
	_draw_str(s, tx, ty, px, ca(color2, _alpha * em), spacing)

static func _draw_str(s: String, x: float, y: float, px: int, col: Color, spacing: float) -> void:
	if _cv == null:
		return
	if spacing == 0.0:
		_cv.draw_string(_font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		return
	var cx := x
	for ch in s:
		_cv.draw_string(_font, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		cx += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + spacing

# ---------- плоские заливки ----------
static func fill_rect_color(x: float, y: float, w: float, h: float, col: Color, a := 1.0) -> void:
	if _cv == null:
		return
	_cv.draw_rect(Rect2(x, y, w, h), ca(col, _alpha * a), true)

static func fill_circle_color(x: float, y: float, r: float, col: Color, a := 1.0) -> void:
	if _cv == null:
		return
	var pts: Array = []
	var n := 24
	for i in range(n):
		var an := float(i) / float(n) * TAU
		pts.append(Vector2(x + cos(an) * r, y + sin(an) * r))
	_cv.draw_colored_polygon(PackedVector2Array(pts), ca(col, _alpha * a))

# радиальные и линейные градиенты — через готовые текстуры с тинтом
static func radial_glow(cx: float, cy: float, r: float, col: Color, a: float, x: float, y: float, w: float, h: float) -> void:
	if _cv == null or tex_radial_center == null:
		return
	var tint := ca(col, _alpha * a)
	_cv.draw_texture_rect(tex_radial_center, Rect2(x, y, w, h), false, tint)

static func radial_rect(x: float, y: float, w: float, h: float, cx: float, cy: float, r: float, stops: Array) -> void:
	if _cv == null:
		return
	# stops: массив [(pos, Color)]
	var first: Color = stops[0][1]
	var last: Color = stops[stops.size() - 1][1]
	var tex := tex_radial_edge if first.a <= last.a else tex_radial_center
	var tint := Color(last.r, last.g, last.b, minf(last.a, 1.0))
	if first.a > last.a:
		tint = Color(first.r, first.g, first.b, minf(first.a, 1.0))
	# середина-интерполяция цвета
	var mid: Color = stops[mini(stops.size() / 2, stops.size() - 1)][1]
	var usec := mid if stops.size() > 2 else tint
	_cv.draw_texture_rect(tex, Rect2(x, y, w, h), false, Color(usec.r, usec.g, usec.b, usec.a))

static func fill_rect_gradient(x: float, y: float, w: float, h: float, tex: ImageTexture) -> void:
	if _cv == null or tex == null:
		return
	_cv.draw_texture_rect(tex, Rect2(x, y, w, h), false)

# ---------- запечённые большие картинки ----------
static func paper() -> void:
	if _cv == null or tex_paper == null:
		return
	_cv.draw_texture_rect(tex_paper, Rect2(0, 0, W, H), false)

static func paper_to(cv: CanvasItem, rt: Rect2) -> void:
	cv.draw_texture_rect(tex_paper, rt, false)

static func vignette() -> void:
	if _cv == null or tex_vignette == null:
		return
	_cv.draw_texture_rect(tex_vignette, Rect2(0, 0, W, H), false)

static func vignette_full(w: float, h: float) -> void:
	if _cv == null or tex_vignette == null:
		return
	_cv.draw_texture_rect(tex_vignette, Rect2(0, 0, w, h), false)

static func stage() -> void:
	# статичный зал запекается с подушкой 80px вокруг
	if _cv == null or tex_stage == null:
		return
	_cv.draw_texture_rect(tex_stage, Rect2(-80, -80, W + 160.0, H + 160.0), false)

static func title() -> void:
	if _cv == null or tex_title == null:
		return
	_cv.draw_texture_rect(tex_title, Rect2(0, 0, W, H), false)

# ---------- запекание бумаги ----------
static func bake_paper(cv: CanvasItem) -> void:
	# вызывается в viewport-запекании (cv: bake_node с полями w/h)
	if tex_vgrad == null:
		return
	cv.draw_set_transform_matrix(Transform2D())
	cv.draw_texture_rect(tex_vgrad, Rect2(0, 0, cv.w, cv.h), false)
	set_canvas(cv)
	var w: float = cv.w
	var h: float = cv.h
	# пятна
	srand(77)
	for i in range(34):
		var x := rndf(0, w)
		var y := rndf(0, h)
		var r := rndf(15, 125)
		var dark := rand() < 0.6
		var col := Color(120.0 / 255.0, 95.0 / 255.0, 58.0 / 255.0, rndf(4.0, 11.0) / 255.0) if dark \
			else Color(1, 250.0 / 255.0, 235.0 / 255.0, rndf(6.0, 26.0) / 255.0)
		cv.draw_texture_rect(tex_radial_center, Rect2(x - r, y - r, r * 2.0, r * 2.0), false, col)
	# волокна
	for i in range(200):
		var fx := rndf(0, w)
		var fy := rndf(0, h)
		var flen := rndf(2, 15)
		var an := rndf(0, PI)
		cv.draw_line(Vector2(fx, fy), Vector2(fx + cos(an) * flen, fy + sin(an) * flen),
			Color(110.0 / 255.0, 88.0 / 255.0, 55.0 / 255.0, rndf(4.0, 15.0) / 255.0), 1.0)
	# крапинки
	for i in range(650):
		var sx := rndf(0, w)
		var sy := rndf(0, h)
		var ss := 1.0 if rand() < 0.85 else 2.0
		cv.draw_rect(Rect2(sx, sy, ss, ss), Color(60.0 / 255.0, 46.0 / 255.0, 30.0 / 255.0, rndf(5.0, 23.0) / 255.0), true)
