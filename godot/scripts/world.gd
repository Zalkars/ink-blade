class_name InkWorld
extends RefCounted

## Полный порт Game/World.cs — зал, коллизии, hazard, статичный арт.

const W := 1280.0
const H := 720.0
const FLOOR_Y := 620.0
const SPAWN := Vector2(300, 574)
const PAD := 80  # подушка запечённого стейджа

static var solids: Array = [
	Rect2(0, 0, 44, 720),
	Rect2(1236, 0, 44, 720),
	Rect2(0, 620, 722, 100),
	Rect2(840, 620, 440, 100),
	Rect2(130, 468, 272, 24),
	Rect2(900, 440, 300, 24),
	Rect2(44, 352, 118, 18),
]
static var oneways: Array = [
	Rect2(560, 330, 175, 16),
	Rect2(690, 510, 132, 14),
]
static var hazards: Array = [
	Rect2(714, 664, 132, 56),
]
static var decor: Array = []

# ---------- частицы пыли в воздухе (запекаются статично) ----------
static func init_world() -> void:
	decor.clear()
	var seed := 991
	var rnd := func() -> float:
		seed = int((seed * 16807) % 2147483647)
		return (seed - 1) / 2147483646.0
	for i in range(34):
		decor.append({
			"x": 60.0 + rnd.call() * 1160.0,
			"y": 90.0 + rnd.call() * 500.0,
			"r": 1.0 + rnd.call() * 3.0,
			"a": 0.05 + rnd.call() * 0.14,
			"sp": 0.2 + rnd.call() * 0.6,
			"ph": rnd.call() * 10.0,
		})

# ---------- физика ----------
static func has_ground_at(px: float, py: float) -> bool:
	for s in solids:
		if px >= s.position.x and px <= s.end.x and absf(py - s.position.y) < 12.0:
			return true
	for s in oneways:
		if px >= s.position.x and px <= s.end.x and absf(py - s.position.y) < 12.0:
			return true
	return false

static func _hits(ent, r: Rect2) -> bool:
	return ent.x < r.end.x and ent.x + ent.w > r.position.x \
		and ent.y < r.end.y and ent.y + ent.h > r.position.y

static func move_x(ent, dt: float) -> void:
	ent.x += ent.vx * dt
	ent.hit_wall = false
	for s in solids:
		if not _hits(ent, s):
			continue
		if ent.vx > 0.0:
			ent.x = s.position.x - ent.w
		elif ent.vx < 0.0:
			ent.x = s.end.x
		else:
			ent.x = s.position.x - ent.w if ent.x + ent.w * 0.5 < s.end.x else s.end.x
		ent.vx = 0.0
		ent.hit_wall = true
	if ent.x < 44.0:
		ent.x = 44.0
		ent.vx = maxf(0.0, ent.vx)
		ent.hit_wall = true
	if ent.x + ent.w > 1236.0:
		ent.x = 1236.0 - ent.w
		ent.vx = minf(0.0, ent.vx)
		ent.hit_wall = true

static func move_y(ent, dt: float) -> void:
	var prev_bottom: float = ent.y + ent.h
	ent.y += ent.vy * dt
	ent.grounded = false
	ent.on_one_way = false

	for s in solids:
		if not _hits(ent, s):
			continue
		if ent.vy > 0.0:
			ent.y = s.position.y - ent.h
			ent.vy = 0.0
			ent.grounded = true
		elif ent.vy < 0.0:
			ent.y = s.end.y
			ent.vy = 0.0

	if ent.drop_t <= 0.0:
		for s in oneways:
			if ent.vy < 0.0:
				continue
			if prev_bottom > s.position.y + 2.0:
				continue
			if not _hits(ent, s):
				continue
			ent.y = s.position.y - ent.h
			ent.vy = 0.0
			ent.grounded = true
			ent.on_one_way = true

static func in_hazard(ent) -> bool:
	for h in hazards:
		if _hits(ent, h):
			return true
	return false

# ---------- запекание стейджа ----------
static func bake_stage(cv: CanvasItem, t := 0.0) -> void:
	var pad := float(InkWorld.PAD)
	cv.draw_set_transform_matrix(Transform2D())
	InkR.set_canvas(cv)
	InkR.t_translate(pad, pad)
	# бумагу на весь запечённый холст (с подушкой)
	if InkR.tex_paper != null:
		cv.draw_texture_rect(InkR.tex_paper, Rect2(-pad, -pad, InkWorld.W + pad * 2.0, InkWorld.H + pad * 2.0), false)
	draw_back_static(t)
	draw_dust_dynamic(0)
	draw_candle(78, 620, 0, 1)
	draw_candle(1198, 620, 1.7, 0.9)
	draw_candle(368, 468, 0.6, 0.75)
	draw_front_static()
	draw_grass(t)
	InkR.t_translate(-pad, -pad)
	InkR.vignette_full(W + pad * 2.0, H + pad * 2.0)
	InkR.vignette_full(W + pad * 2.0, H + pad * 2.0)
	InkR.set_canvas(null)

# ---------- статичный фон ----------
static func draw_back_static(t := 0.0) -> void:
	# дальние каменные швы
	InkR.srand(31)
	var y := 120.0
	while y < 600.0:
		var pts: Array = []
		var x := 44.0
		while x <= 1236.0:
			pts.append(Vector2(x, y + sin(x * 0.02 + y) * 1.5))
			x += 40.0
		InkR.poly(pts, 1.2, InkR.INK, 0.06, 0.0)
		y += 118.0
	for i in range(5):
		var xv: float = 170 + i * 235
		InkR.srand(100 + i)
		InkR.poly([
			Vector2(xv, 100), Vector2(xv + 8, 190), Vector2(xv - 4, 280), Vector2(xv + 5, 390)
		], 1.2, InkR.INK, 0.07, 2.5)

	# затмение
	InkR.srand(3)
	InkR.circle(985, 196, 116, InkR.INK, null, 2, 0.07, 1.5, 26, false)
	InkR.circle(985, 196, 118, null, InkR.rgba(156, 33, 41, 56), 2.5, 0.8, 1.6, 30)
	InkR.hatch(InkR.circle_pts(985, 196, 112, 20), 15.0, 0.05, InkR.INK)

	draw_gate(t)
	draw_banners(t)

	# каллиграфия на стене
	InkR.save()
	InkR.t_translate(104, 520)
	InkR.t_rotate_deg(-90)
	InkR.text("ЧЕРНИЛЬНЫЙ КЛИНОК", 0, 0, 44, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.055, 12)
	InkR.restore()

	draw_pillar(74, 108, 58, 512)
	draw_pillar(1148, 108, 58, 512)

	InkR.text("ЧЕРНИЛА ПОМНЯТ", 640, 108, 20, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.16, 9)
	InkR.line(470, 122, 810, 122, 0.16, InkR.INK, 1.5, 1.0)

static func draw_pillar(x: float, y: float, w: float, h: float) -> void:
	InkR.srand(int(x + y))
	InkR.rect(x, y, w, h, InkR.rgba(120, 100, 70, 13), InkR.rgba(23, 19, 15, 41), 2)
	InkR.rect(x - 8, y + h - 26, w + 16, 26, null, InkR.rgba(23, 19, 15, 41), 2)
	InkR.line(x + 10, y + 8, x + 10, y + h - 30, 1.0, InkR.rgba(23, 19, 15, 26), 1.0, 0.0)
	InkR.line(x + w - 12, y + 8, x + w - 12, y + h - 30, 1.0, InkR.rgba(23, 19, 15, 26), 1.0, 0.0)
	InkR.poly([
		Vector2(x + w * 0.2, y + 40), Vector2(x + w * 0.5, y + 120), Vector2(x + w * 0.35, y + 230)
	], 1.0, InkR.rgba(23, 19, 15, 31), 1.0, 0.0)

static func draw_gate(_t: float) -> void:
	var cx := 640.0
	var w := 150.0
	var top := 128.0
	var bottom := 330.0
	var pts: Array = [Vector2(cx - w / 2, bottom)]
	for i in range(15):
		var a := PI + float(i) / 14.0 * PI
		pts.append(Vector2(cx + cos(a) * (w / 2), top + 75 + sin(a) * 75))
	pts.append(Vector2(cx + w / 2, bottom))
	InkR.srand(41)
	InkR.fill_poly(pts, InkR.rgba(30, 24, 18, 77), 1.0, 0.8)
	InkR.poly(pts, 3.0, InkR.rgba(23, 19, 15, 140), 1.0, 1.15, true)

	for i in range(-2, 3):
		InkR.line(cx + i * 27, top + 78, cx + i * 27, bottom - 8, 2.0, InkR.rgba(240, 228, 204, 26), 1.0, 0.0)
	InkR.arc(cx, top + 75, w / 2 - 6, PI, PI * 2, 2.0, InkR.rgba(240, 228, 204, 33), 1.0, 0.0)

	chain(cx - 58, top + 78, bottom - 14, 2, 0.4)
	chain(cx + 62, top + 66, bottom - 30, -2, 0.35)
	InkR.line(cx - 62, 238, cx + 64, 258, 4.0, InkR.rgba(20, 16, 12, 128), 1.0, 0.0)
	InkR.line(cx - 62, 238, cx + 64, 258, 1.5, InkR.rgba(240, 228, 204, 31), 1.0, 0.0)

	InkR.srand(44)
	InkR.rect(cx - 62, 352, 124, 42, InkR.rgba(247, 239, 221, 230), InkR.rgba(23, 19, 15, 153), 1.6, 1.0, 1.0)
	InkR.text("ДАЛЬШЕ —", cx - 2, 370, 12, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.7, 2)
	InkR.text("В РАЗРАБОТКЕ", cx - 2, 386, 11, InkR.F_HAND, InkR.A_CENTER, InkR.RED, 0.85)
	InkR.line(cx - 66, 344, cx - 50, 352, 1.5, InkR.rgba(23, 19, 15, 128), 1.0, 0.0)
	InkR.line(cx + 50, 344, cx + 66, 352, 1.5, InkR.rgba(23, 19, 15, 128), 1.0, 0.0)

static func draw_banners(t: float) -> void:
	var sway := sin(t * 0.7) * 3
	banner(232 + sway, 36, 62, 196, 0.16)
	banner(1042 - sway, 36, 56, 168, 0.14)
	InkR.text("I", 263 + sway, 120, 30, InkR.F_DISPLAY, InkR.A_CENTER, InkR.rgba(240, 228, 204, 51))

static func banner(x: float, y: float, w: float, h: float, alpha: float) -> void:
	var pts := [
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h * 0.82),
		Vector2(x + w * 0.82, y + h), Vector2(x + w * 0.6, y + h * 0.86),
		Vector2(x + w * 0.42, y + h), Vector2(x + w * 0.22, y + h * 0.88),
		Vector2(x, y + h * 0.84)
	]
	InkR.srand(int(x))
	InkR.fill_poly(pts, InkR.rgba(156, 33, 41, int(alpha * 255)), 1.0, 1.2)
	InkR.poly(pts, 1.5, InkR.rgba(23, 19, 15, 89), 0.7, 1.2, true)
	InkR.circle(x + w / 2, y + h * 0.38, w * 0.2, null, InkR.rgba(240, 228, 204, 71), 1.5, 1.0, 0.8)
	InkR.line(x + w / 2, y + h * 0.2, x + w / 2, y + h * 0.56, 1.0, InkR.rgba(240, 228, 204, 51), 1.0, 0.0)
	InkR.line(x + w / 2, y, x + w / 2, y - 14, 2.0, InkR.rgba(23, 19, 15, 102), 1.0, 0.0)

static func chain(x: float, y0: float, y1: float, sway: float, alpha: float) -> void:
	var n := int(floor((y1 - y0) / 11.0))
	var pts: Array = []
	for i in range(n + 1):
		var y := y0 + i * 11.0
		var xx := x + sin(i * 0.35 + y0) * sway
		pts.append(Vector2(xx, y))
	InkR.poly(pts, 1.1, InkR.INK, alpha * 0.4, 0.3)
	for i in range(n + 1):
		var p: Vector2 = pts[i]
		if i % 2 == 0:
			InkR.circle(p.x, p.y, 2.8, null, InkR.INK, 1.1, alpha, 0.3, 7)
		else:
			InkR.line(p.x - 2.4, p.y - 4, p.x + 2.4, p.y + 4, 1.2, InkR.INK, alpha, 0.2)

static func draw_candle(x: float, base_y: float, t: float, s: float) -> void:
	var flick := sin(t * 7.3 + x) * 2 + sin(t * 13.1 + x * 0.4) * 1.2
	InkR.radial_glow(x, base_y - 24 * s, 52 * s, Color(220.0 / 255.0, 150.0 / 255.0, 60.0 / 255.0), 0.18, x - 60, base_y - 90, 120, 100)

	InkR.srand(int(x + 5))
	InkR.rect(x - 5 * s, base_y - 26 * s, 10 * s, 26 * s, InkR.rgba(246, 237, 218, 217), InkR.INK, 1.4, 1.0, 0.6)
	InkR.line(x - 4 * s, base_y - 18 * s, x - 2 * s, base_y - 13 * s, 1.2, InkR.rgba(23, 19, 15, 77), 1.0, 0.2)
	InkR.blob(x + flick * 0.3, base_y - 34 * s, 4.4 * s, InkR.GOLD, InkR.rgba(23, 19, 15, 166), 1.0, 1.0, 0.8, 10, 0.2)
	InkR.blob(x + flick * 0.4, base_y - 33 * s, 2.1 * s, InkR.RED_BRIGHT, null, 2.0, 1.0, 0.5, 10, 0.25, false)
	InkR.line(x - 9 * s, base_y, x + 9 * s, base_y, 2.0, InkR.rgba(23, 19, 15, 128), 1.0, 0.0)

# ---------- передний план ----------
static func draw_front_static() -> void:
	InkR.fill_rect_gradient(44, 620, 1192, 100, InkR.tex_floor_grad)

	InkR.srand(71)
	InkR.line(44, 620, 720, 620, 4.5, InkR.INK, 1.0, 0.8)
	InkR.line(840, 620, 1236, 620, 4.5, InkR.INK, 1.0, 0.8)
	InkR.line(50, 626, 716, 626, 1.4, InkR.INK, 0.25, 0.5)

	for x in range(80, 700, 118):
		InkR.line(float(x), 624, float(x) - 6, 720, 1.3, InkR.rgba(23, 19, 15, 33), 1.0, 0.0)
	for x in range(880, 1220, 118):
		InkR.line(float(x), 624, float(x) + 6, 720, 1.3, InkR.rgba(23, 19, 15, 33), 1.0, 0.0)
	InkR.hatch([Vector2(46, 628), Vector2(718, 628), Vector2(718, 720), Vector2(46, 720)], 17, 0.08)
	InkR.hatch([Vector2(842, 628), Vector2(1234, 628), Vector2(1234, 720), Vector2(842, 720)], 17, 0.08)

	InkR.fill_rect_gradient(720, 620, 120, 100, InkR.tex_pit_grad)

	InkR.srand(83)
	InkR.poly([
		Vector2(722, 620), Vector2(714, 650), Vector2(726, 672),
		Vector2(716, 700), Vector2(722, 720)
	], 3.0, InkR.INK, 1.0, 1.15)
	InkR.poly([
		Vector2(838, 620), Vector2(847, 648), Vector2(834, 674),
		Vector2(847, 702), Vector2(838, 720)
	], 3.0, InkR.INK, 1.0, 1.15)

	for i in range(4):
		var sx := 736.0 + i * 27
		var hh := 26.0 + (i % 2) * 10
		InkR.srand(120 + i)
		InkR.fill_poly([Vector2(sx - 9, 700), Vector2(sx, 700 - hh), Vector2(sx + 9, 700)],
			InkR.INK, 1.0, 0.7, true, InkR.INK, 1.5)
		InkR.line(sx - 4, 696, sx, 700 - hh + 4, 1.2, InkR.CREAM, 0.35, 0.3)
	InkR.line(720, 702, 840, 702, 2.0, InkR.rgba(23, 19, 15, 153), 1.0, 0.0)

	platform(130, 468, 272, 24, false)
	platform(900, 440, 300, 24, false)
	platform(44, 352, 118, 18, false)
	platform(560, 330, 175, 16, true)
	platform(690, 510, 132, 14, true)

	InkR.srand(301)
	InkR.hatch([Vector2(0, 600), Vector2(110, 720), Vector2(0, 720)], 12, 0.1, InkR.INK, 1.0, true)
	InkR.hatch([Vector2(1280, 620), Vector2(1280, 720), Vector2(1150, 720)], 12, 0.09, InkR.INK, 1.0, true)

static func draw_grass(t: float) -> void:
	for i in range(9):
		var x: float = 100 + i * 128 + sin(i * 3) * 30
		if x > 700 and x < 860:
			continue
		var y := 620.0
		InkR.srand(200 + i)
		for j in range(3):
			InkR.poly([
				Vector2(x + j * 4 - 4, y),
				Vector2(x + j * 5 - 8 + sin(t + i) * 2, y - 7 - j * 2)
			], 1.4, InkR.rgba(23, 19, 15, 102), 1.0, 0.6)

static func platform(x: float, y: float, w: float, h: float, one_way: bool) -> void:
	InkR.srand(int(x + y * 3))
	InkR.rect(x, y, w, h,
		Color("#eee2c9") if one_way else Color("#e2d3b2"),
		InkR.INK, 2.4, 1.0, 0.8)
	InkR.line(x + 3, y + 2, x + w - 3, y + 2, 1.6, InkR.rgba(250, 244, 228, 166), 1.0, 0.8)
	InkR.hatch([
		Vector2(x + 2, y + h - 2), Vector2(x + w - 2, y + h - 2),
		Vector2(x + w - 2, y + h + 18), Vector2(x + 2, y + h + 18)
	], 7, 0.16)

	if one_way:
		InkR.line(x + 3, y + h + 4, x + w - 3, y + h + 4, 1.0, InkR.rgba(23, 19, 15, 64), 1.0, 0.0, [5.0, 7.0])
		chain(x + 22, y - 44, y, 0, 0.25)
		chain(x + w - 26, y - 52, y, 0, 0.22)
	else:
		InkR.line(x + 10, y + h + 7, x + 8, y + h + 20, 1.2, InkR.rgba(23, 19, 15, 51), 1.0, 0.4)
		InkR.line(x + w - 12, y + h + 7, x + w - 10, y + h + 20, 1.2, InkR.rgba(23, 19, 15, 51), 1.0, 0.4)
		InkR.poly([
			Vector2(x + w * 0.3, y + h), Vector2(x + w * 0.4, y + h + 12), Vector2(x + w * 0.52, y + h)
		], 1.0, InkR.rgba(23, 19, 15, 41), 1.0, 0.0)

# ---------- динамическая пыль (для дальнего плана не используется — оригинал запекает её при t=0) ----------
static func draw_dust_dynamic(t: float) -> void:
	for d in decor:
		var y: float = d.y + sin(t * d.sp + d.ph) * 18 - fmod(t * 6 * d.sp, 40)
		InkR.fill_circle_color(d.x + sin(t * 0.2 + d.ph) * 6, y, d.r, InkR.INK, d.a)
