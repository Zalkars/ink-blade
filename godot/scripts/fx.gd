class_name InkFx
extends RefCounted

## Полный порт Game/Fx.cs

enum ParticleKind { INK, DROP, SPLAT, SPARK, DUST }

class Particle:
	var kind := ParticleKind.INK
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var life := 0.0
	var max_life := 0.0
	var radius := 0.0
	var color := Color.WHITE
	var gravity := 0.0
	var drag := 0.0
	var floor_y := 0.0
	var splat_on_expiry := false

static var parts: Array[Particle] = []
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
static var particle_atlas: Texture2D

## Ink splashes share silhouettes baked at four pixels per game unit.
## The fill and the outline are separate masks so tint and fade stay independent.
const ATLAS_VARIANTS := 8
const ATLAS_CELL := 96
const ATLAS_SCALE := 4.0
const ATLAS_RADII := [2.75, 3.75, 4.5, 5.5, 6.5, 9.0, 4.5, 5.5, 6.5]
const SPLAT_ROW := 5
const FIRST_OUTLINE_ROW := 6
const DISC_ROW := 9
const DISC_RADIUS := 9.0
const ATLAS_ROWS := 10
const CELL_UV := Vector2(1.0 / ATLAS_VARIANTS, 1.0 / ATLAS_ROWS)

class ParticleBatch:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func stamp(destination: Rect2, uv: Rect2, tint: Color) -> void:
		quad(destination.position, Vector2(destination.size.x, 0.0),
			Vector2(0.0, destination.size.y), uv, tint)

	func quad(origin: Vector2, right: Vector2, down: Vector2, uv: Rect2, tint: Color) -> void:
		var base := points.size()
		points.append(origin)
		points.append(origin + right)
		points.append(origin + right + down)
		points.append(origin + down)
		uvs.append(uv.position)
		uvs.append(Vector2(uv.end.x, uv.position.y))
		uvs.append(uv.end)
		uvs.append(Vector2(uv.position.x, uv.end.y))
		for i in 4:
			colors.append(tint)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 3)

	func disc(center: Vector2, radius: float, tint: Color) -> void:
		var half := Vector2.ONE * (ATLAS_CELL / ATLAS_SCALE * 0.5 / DISC_RADIUS * radius)
		stamp(Rect2(center - half, 2.0 * half), Rect2(Vector2(0, DISC_ROW) * CELL_UV, CELL_UV), tint)

	func trail(from: Vector2, to: Vector2, width: float, tint: Color, antialiased := true) -> void:
		var vector := to - from
		if vector.length_squared() < 0.0001:
			return
		var direction := vector.normalized()
		var across := direction.orthogonal()
		var uv := Rect2(Vector2(0.5, DISC_ROW + 0.5) * CELL_UV, Vector2.ZERO)
		if antialiased:
			# The atlas has one soft texel-wide edge on the original one-pixel fringe.
			uv = Rect2(Vector2(1.5 - 10.0 / 24.0, DISC_ROW + 0.5 - 3.0 / 24.0) * CELL_UV,
				Vector2(20.0 / 24.0, 6.0 / 24.0) * CELL_UV)
			from -= direction
			vector += direction * 2.0
			width += 2.0
		quad(from - across * width * 0.5, vector, across * width, uv, tint)

	func draw(canvas: CanvasItem, atlas: Texture2D) -> void:
		if indices.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(
			canvas.get_canvas_item(), indices, points, colors, uvs,
			PackedInt32Array(), PackedFloat32Array(), atlas.get_rid())
		points.clear()
		uvs.clear()
		colors.clear()
		indices.clear()

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
		var p := parts[i]
		p.life -= dt
		if p.life <= 0.0:
			if p.splat_on_expiry:
				splat(p)
			parts.remove_at(i)
			continue
		if p.kind == ParticleKind.SPLAT:
			continue
		var velocity := p.velocity
		var drag := p.drag * dt
		velocity.y += p.gravity * dt
		velocity *= Vector2(1.0 - drag, 1.0 - drag * 0.4)
		var point := p.position + velocity * dt
		if p.floor_y != 0.0 and point.y > p.floor_y:
			point.y = p.floor_y
			velocity *= Vector2(0.55, -0.22)
			p.life = minf(p.life, 0.25)
			if p.kind == ParticleKind.DROP:
				p.kind = ParticleKind.INK
		p.position = point
		p.velocity = velocity

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

static func splat(p: Particle) -> void:
	if parts.size() > 420:
		return
	var mark := Particle.new()
	mark.kind = ParticleKind.SPLAT
	mark.position = p.position
	mark.life = rnd(0.5, 1.6)
	mark.max_life = 1.6
	mark.radius = p.radius * rnd(1.6, 3.2)
	mark.color = p.color
	parts.append(mark)

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
		var drop := Particle.new()
		drop.kind = ParticleKind.DROP if drops else ParticleKind.INK
		drop.position = Vector2(x + rnd(-4, 4), y + rnd(-4, 4))
		drop.velocity = Vector2(cos(a) * sp + vx, sin(a) * sp - rnd(0.0, 60.0) + vy)
		drop.life = rnd(0.35, 0.9)
		drop.max_life = 0.9
		drop.radius = rnd(1.8, size)
		drop.color = colors[randi() % colors.size()]
		drop.gravity = gravity
		drop.drag = 0.8
		drop.floor_y = floor_
		drop.splat_on_expiry = splat_on
		parts.append(drop)

static func sparks(x: float, y: float, angle: float, n := 7, color2 = null) -> void:
	for i in range(n):
		var a := angle + rnd(-1.1, 1.1)
		var sp := rnd(220, 640)
		var col: Color = color2 if color2 != null else [InkR.CREAM, InkR.GOLD, InkR.RED_BRIGHT][randi() % 3]
		var spark := Particle.new()
		spark.kind = ParticleKind.SPARK
		spark.position = Vector2(x, y)
		spark.velocity = Vector2(cos(a), sin(a)) * sp
		spark.life = rnd(0.10, 0.26)
		spark.max_life = 0.26
		spark.radius = rnd(1.0, 2.4)
		spark.color = col
		spark.gravity = 380.0
		spark.drag = 2.5
		parts.append(spark)

static func dust(x: float, y: float, n: int, dir_x: float) -> void:
	for i in range(n):
		var mote := Particle.new()
		mote.kind = ParticleKind.DUST
		mote.position = Vector2(x + rnd(-8, 8), y + rnd(-3, 3))
		mote.velocity = Vector2(dir_x * rnd(10, 50) + rnd(-35, 35), rnd(-90, -20))
		mote.life = rnd(0.4, 0.85)
		mote.max_life = 0.85
		mote.radius = rnd(3, 8)
		mote.color = InkR.INK_SOFT
		mote.gravity = -30.0
		mote.drag = 1.6
		parts.append(mote)

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
static func draw_behind(view := Rect2(), atlas: Texture2D = null) -> void:
	for g in ghosts:
		if view.has_area() and not view.has_point(Vector2(g.x, g.y)):
			continue
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

	var batch := ParticleBatch.new() if atlas != null else null
	for p in parts:
		if p.kind != ParticleKind.DUST or (view.has_area() and not view.has_point(p.position)):
			continue
		var k2 := p.life / p.max_life
		var radius := p.radius * (1 + (1 - k2) * 0.8)
		if batch != null:
			batch.disc(p.position, radius, InkR.ca(p.color, k2 * 0.22))
		else:
			InkR.fill_circle_color(p.position.x, p.position.y, radius, p.color, k2 * 0.22)
	if batch != null:
		batch.draw(InkR._cv, atlas)

	for r in rings:
		if view.has_area() and not view.grow(maxf(r.r0, r.r1)).has_point(Vector2(r.x, r.y)):
			continue
		var k3: float = 1.0 - float(r.life) / float(r.max)
		InkR.arc(r.x, r.y, lerpf(r.r0, r.r1, 1.0 - pow(1.0 - k3, 3.0)), 0, InkR.TAU,
			maxf(0.5, r.width * (1 - k3)), r.color, (1 - k3) * 0.55, 0.8, 24)

static func bake_particle_atlas(canvas: CanvasItem) -> void:
	InkR.set_canvas(canvas)
	InkR.begin_frame(0.0)
	InkR.t_scale(ATLAS_SCALE, ATLAS_SCALE)
	var cell := ATLAS_CELL / ATLAS_SCALE
	for row in ATLAS_RADII.size():
		for column in ATLAS_VARIANTS:
			var center := (Vector2(column, row) + Vector2.ONE * 0.5) * cell
			InkR.srand(3119 + column * 237)
			var outline := row >= FIRST_OUTLINE_ROW
			InkR.blob(center.x, center.y, ATLAS_RADII[row], null if outline else Color.WHITE,
				Color.WHITE, 1.0, 1.0, 0.8 if row == SPLAT_ROW else 1.0, 10, 0.13, outline)
	InkR.fill_circle_color(cell * 0.5, cell * (DISC_ROW + 0.5), DISC_RADIUS, Color.WHITE)
	var trail_center := Vector2(cell * 1.5, cell * (DISC_ROW + 0.5))
	canvas.draw_line(trail_center - Vector2(9.0, 0.0), trail_center + Vector2(9.0, 0.0), Color.WHITE, 4.0, true)
	InkR.set_canvas(null)


static func _batch_particle_stamp(batch: ParticleBatch, p: Particle, alpha: float) -> void:
	var splatter := p.kind == ParticleKind.SPLAT
	var radius := p.radius
	var row := SPLAT_ROW if splatter else clampi(floori(radius) - 2, 0, 4)
	var variation := posmod(int(p.position.x * (3.0 if splatter else 5.0) + p.position.y * (1.0 if splatter else 2.0)) + InkR._boil, ATLAS_VARIANTS)
	var extent := Vector2.ONE * (ATLAS_CELL / ATLAS_SCALE) * radius / float(ATLAS_RADII[row])
	var destination := Rect2(p.position - extent * 0.5, extent)
	var source := Rect2(Vector2(variation, row) * CELL_UV, CELL_UV)
	batch.stamp(destination, source, InkR.ca(p.color, alpha))
	if not splatter and radius > 4.0:
		source.position.y = (FIRST_OUTLINE_ROW + row - 2) * CELL_UV.y
		batch.stamp(destination, source, InkR.ca(InkR.INK, alpha))


static func draw_front(view := Rect2(), atlas: Texture2D = null) -> void:
	var batch := ParticleBatch.new() if atlas != null else null
	for s in parts:
		if s.kind == ParticleKind.DUST or (view.has_area() and not view.has_point(s.position)):
			continue
		var k := clampf(s.life / s.max_life, 0.0, 1.0)
		if s.kind == ParticleKind.SPARK:
			var len := 10.0 + (1 - k) * 26
			var tip := s.position
			var tail := tip - s.velocity * 0.02 * (len / 18.0)
			var tint := InkR.ca(s.color, minf(1.0, k * 1.8))
			if batch != null:
				batch.trail(tail, tip, s.radius, tint)
			else:
				InkR._cv.draw_line(tail, tip, tint, s.radius, true)
		elif batch != null:
			_batch_particle_stamp(batch, s, minf(1.0, k * 1.8))
		elif s.kind == ParticleKind.SPLAT:
			InkR.srand(int(s.position.x * 3 + s.position.y))
			InkR.blob(s.position.x, s.position.y, s.radius, s.color, null, 2.0, minf(1.0, k * 1.8), 0.8, 10, 0.13, false)
		else:
			InkR.srand(int(s.position.x * 5 + s.position.y * 2))
			InkR.blob(s.position.x, s.position.y, s.radius, s.color, InkR.INK, 1.0, minf(1.0, k * 1.8), 1.0, 10, 0.13, s.radius > 4)
	if batch != null:
		batch.draw(InkR._cv, atlas)

	for sl in slashes:
		if view.has_area() and not view.grow(sl.r + maxf(sl.w0, sl.w1)).has_point(Vector2(sl.x, sl.y)):
			continue
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
		if view.has_area() and not view.grow(t4.size * 2.0).has_point(Vector2(t4.x, t4.y)):
			continue
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
