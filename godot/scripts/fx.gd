class_name InkFx
extends RefCounted

## Полный порт Game/Fx.cs

static var parts: Array = []   # Particle
static var ghosts: Array = []
static var slashes: Array = []
static var rings: Array = []
static var texts: Array = []
static var shake := 0.0
static var shake_rot := 0.0
static var flash := 0.0
static var damage := 0.0
static var t := 0.0
static var flash_color: Color = InkR.CREAM

# Particle поля: type, x, y, vx, vy, life, max, size, gravity, drag, floor, alpha, rot, vr, color, splat

static func reset() -> void:
	parts.clear()
	ghosts.clear()
	slashes.clear()
	rings.clear()
	texts.clear()
	shake = 0.0
	shake_rot = 0.0
	flash = 0.0
	damage = 0.0

static func rnd(a := 0.0, b := 1.0) -> float:
	return a + randf() * (b - a)

static func update(dt: float) -> void:
	t += dt
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p.life -= dt
		if p.life <= 0.0:
			if p.splat:
				splat(p)
			parts.remove_at(i)
			continue
		p.vy += p.gravity * dt
		p.vx *= 1.0 - p.drag * dt
		p.vy *= 1.0 - p.drag * dt * 0.4
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.rot += p.vr * dt
		if p.floor != 0.0 and p.y > p.floor:
			p.y = p.floor
			p.vy *= -0.22
			p.vx *= 0.55
			p.life = minf(p.life, 0.25)
			if p.type == "drop":
				p.type = "ink"

	for i in range(ghosts.size() - 1, -1, -1):
		var g: Dictionary = ghosts[i]
		g.life -= dt
		if g.life <= 0.0:
			ghosts.remove_at(i)
	for i in range(slashes.size() - 1, -1, -1):
		var s: Dictionary = slashes[i]
		s.life -= dt
		if s.life <= 0.0:
			slashes.remove_at(i)
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r.life -= dt
		if r.life <= 0.0:
			rings.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		var tx: Dictionary = texts[i]
		tx.life -= dt
		tx.y += tx.vy * dt
		tx.vy *= 0.94
		if tx.life <= 0.0:
			texts.remove_at(i)

	shake = maxf(0.0, shake - dt * 58.0)
	shake_rot *= pow(0.001, dt)
	flash = maxf(0.0, flash - dt * 3.4)
	damage = maxf(0.0, damage - dt * 1.7)

static func splat(p: Dictionary) -> void:
	if parts.size() > 420:
		return
	parts.append({
		"type": "splat", "x": p.x, "y": p.y,
		"life": rnd(0.5, 1.6), "max": 1.6,
		"size": p.get("size", 3.0) * rnd(1.6, 3.2),
		"color": p.color, "alpha": 0.35, "gravity": 0.0,
		"vx": 0.0, "vy": 0.0, "rot": 0.0, "vr": 0.0, "drag": 0.0, "floor": 0.0,
		"splat": false,
	})

static func add_shake(a: float, rot := 0.0) -> void:
	shake = minf(26.0, maxf(shake, a))
	if rot > 0.0:
		shake_rot = maxf(shake_rot, rot)

static func flash_screen(a: float, color2 = null) -> void:
	flash = maxf(flash, a)
	if color2 != null:
		flash_color = color2

static func damage_screen(a: float) -> void:
	damage = maxf(damage, a)

static func shake_offset() -> Vector3:
	if shake <= 0.2:
		return Vector3.ZERO
	return Vector3(rnd(-shake, shake), rnd(-shake, shake) * 0.7, rnd(-shake_rot, shake_rot))

static func ink_burst(x: float, y: float, n := 10, power := 220.0, colors = null, size := 5.0, drops := false,
		_angle = null, vx := 0.0, vy := 0.0, gravity := 1300.0, floor_ := 618.0, splat_on := true) -> void:
	if colors == null:
		colors = [InkR.INK, InkR.INK, InkR.RED, InkR.INK_SOFT]
	for i in range(n):
		if parts.size() > 460:
			break
		var a: float
		if _angle != null:
			a = _angle + rnd(-0.9, 0.9)
		else:
			a = rnd(0.0, InkR.TAU)
		var sp := rnd(0.25, 1.0) * power
		parts.append({
			"type": "drop" if drops else "ink",
			"x": x + rnd(-4, 4), "y": y + rnd(-4, 4),
			"vx": cos(a) * sp + vx,
			"vy": sin(a) * sp - rnd(0.0, 60.0) + vy,
			"life": rnd(0.35, 0.9), "max": 0.9,
			"size": rnd(1.8, size),
			"color": colors[randi() % colors.size()],
			"gravity": gravity, "drag": 0.8, "floor": floor_,
			"splat": splat_on, "alpha": 1.0,
			"rot": 0.0, "vr": 0.0,
		})

static func sparks(x: float, y: float, angle: float, n := 7, color2 = null) -> void:
	for i in range(n):
		var a := angle + rnd(-1.1, 1.1)
		var sp := rnd(220, 640)
		var col: Color = color2 if color2 != null else [InkR.CREAM, InkR.GOLD, InkR.RED_BRIGHT][randi() % 3]
		parts.append({
			"type": "spark", "x": x, "y": y,
			"vx": cos(a) * sp, "vy": sin(a) * sp,
			"life": rnd(0.10, 0.26), "max": 0.26,
			"size": rnd(1.0, 2.4),
			"color": col,
			"gravity": 380.0, "drag": 2.5, "floor": 0.0,
			"splat": false, "alpha": 1.0,
			"rot": 0.0, "vr": 0.0,
		})

static func dust(x: float, y: float, n: int, dir_x: float) -> void:
	for i in range(n):
		parts.append({
			"type": "dust", "x": x + rnd(-8, 8), "y": y + rnd(-3, 3),
			"vx": dir_x * rnd(10, 50) + rnd(-35, 35),
			"vy": rnd(-90, -20),
			"life": rnd(0.4, 0.85), "max": 0.85,
			"size": rnd(3, 8), "color": InkR.INK_SOFT,
			"gravity": -30.0, "drag": 1.6, "floor": 0.0,
			"splat": false, "alpha": 0.22,
			"rot": 0.0, "vr": 0.0,
		})

static func ring(x: float, y: float, r0: float, r1: float, color2 = null, life := 0.3, width := 2.0) -> void:
	rings.append({
		"x": x, "y": y, "r0": r0, "r1": r1,
		"color": color2 if color2 != null else InkR.INK,
		"life": life, "max": life, "width": width,
	})

static func ghost_trail(x: float, y: float, w: float, h: float, facing: int, life := 0.22) -> void:
	if ghosts.size() > 30:
		return
	ghosts.append({
		"x": x, "y": y, "w": w, "h": h, "facing": facing,
		"life": life, "max": life, "color": InkR.RED,
	})

static func slash(x: float, y: float, a0: float, a1: float, r: float, w0: float, w1: float, life: float, color2: Color) -> void:
	slashes.append({
		"x": x, "y": y, "a0": a0, "a1": a1, "r": r, "w0": w0, "w1": w1,
		"life": life, "max": life, "color": color2,
	})

static func text_fx(x: float, y: float, s: String, size := 20.0, color2 = null, hand := true, life := 0.7, vy := -70.0) -> void:
	if texts.size() > 30:
		return
	texts.append({
		"x": x, "y": y, "str": s, "size": size,
		"color": color2 if color2 != null else InkR.INK,
		"hand": hand, "life": life, "max": life, "vy": vy,
	})

# ---------- отрисовка ----------
static func draw_behind() -> void:
	for g in ghosts:
		var k: float = g.life / g.max
		InkR.save()
		var cx: float = g.x + g.w / 2.0
		var by: float = g.y + g.h
		InkR.t_translate(cx, by)
		InkR.t_scale(float(g.facing), 1.0)
		var cloak := [
			Vector2(-12, -31), Vector2(10, -32), Vector2(13, -12),
			Vector2(10, -2), Vector2(3, -6), Vector2(-5, -3), Vector2(-13, -10)
		]
		InkR.srand(int(g.x * 7 + g.y * 3))
		InkR.fill_poly(cloak, InkR.CREAM, k * 0.28, 1.1)
		InkR.blob(1, -38, 10, InkR.CREAM, null, 2.0, k * 0.28, 0.6, 10, 0.13, false)
		InkR.restore()

	for p in parts:
		if p.type != "dust":
			continue
		var k2: float = p.life / p.max
		InkR.fill_circle_color(p.x, p.y, p.size * (1 + (1 - k2) * 0.8), p.color, k2 * p.alpha)

	for r in rings:
		var k3: float = 1.0 - float(r.life) / float(r.max)
		InkR.save()
		InkR.arc(r.x, r.y, lerpf(r.r0, r.r1, 1.0 - pow(1.0 - k3, 3.0)), 0, InkR.TAU,
			maxf(0.5, r.width * (1 - k3)), r.color, (1 - k3) * 0.55, 0.8, 24)
		InkR.restore()

static func draw_front() -> void:
	for s in parts:
		if s.type == "dust":
			continue
		var k: float = clampf(s.life / s.max, 0.0, 1.0)
		InkR.save()
		if s.type == "spark":
			var len := 10.0 + (1 - k) * 26
			InkR.line(s.x, s.y, s.x - s.vx * 0.02 * (len / 18), s.y - s.vy * 0.02 * (len / 18),
				s.size, s.color, minf(1.0, k * 1.8), 0.0)
		elif s.type == "splat":
			InkR.srand(int(s.x * 3 + s.y))
			InkR.blob(s.x, s.y, s.size, s.color, null, 2.0, minf(1.0, k * 1.8), 0.8, 10, 0.13, false)
		else:
			InkR.srand(int(s.x * 5 + s.y * 2))
			InkR.blob(s.x, s.y, s.size, s.color, InkR.INK, 1.0, minf(1.0, k * 1.8), 1.0, 10, 0.13, s.size > 4)
		InkR.restore()

	for sl in slashes:
		var k4: float = 1.0 - float(sl.life) / float(sl.max)
		var grow: float = 1.0 - pow(1.0 - k4, 3.0)
		var a0: float = sl.a0
		var a1: float = lerpf(sl.a0, sl.a1, minf(1.0, grow * 1.35))
		var alpha: float = (1.0 - k4) * 0.9
		InkR.srand(int(sl.x * 3 + sl.y * 7))
		InkR.taper_arc(sl.x, sl.y, sl.r - 4 + grow * 8, a0, a1,
			sl.w0 * (1 - k4 * 0.5), sl.w1, InkR.INK, alpha * 0.55, 1.4)
		InkR.taper_arc(sl.x, sl.y, sl.r + grow * 4, a0, a1,
			sl.w0 * 0.62, sl.w1 * 0.35, sl.color, alpha, 1.0)
		InkR.taper_arc(sl.x, sl.y, sl.r + grow * 2, a0 + 0.05, a1 - 0.05,
			sl.w0 * 0.2, sl.w1 * 0.18, InkR.CREAM, alpha * 0.85, 0.6)

	for t4 in texts:
		var k5: float = clampf(t4.life / t4.max, 0.0, 1.0)
		var pop: float = minf(1.0, (1.0 - k5) * 4.0)
		var scale: float = 0.7 + (1.0 + 2.70158 * pow(pop - 1.0, 3.0) + 1.70158 * pow(pop - 1.0, 2.0)) * 0.35
		InkR.text(t4.str, t4.x, t4.y, t4.size * scale,
			InkR.F_HAND if t4.hand else InkR.F_BOLD, InkR.A_CENTER,
			t4.color, minf(1.0, k5 * 2.0), 0.0, 1.0)

static func draw_screen(w: float, h: float) -> void:
	if damage > 0.0:
		var tint := InkR.rgba(140, 20, 30, int(clampf(0.5 * damage, 0.0, 1.0) * 255.0))
		InkR._cv.draw_texture_rect(InkR.tex_radial_edge, Rect2(0, 0, w, h), false, tint)
	if flash > 0.0:
		InkR.save()
		InkR.fill_rect_color(0, 0, w, h, flash_color, minf(0.8, flash))
		InkR.restore()
