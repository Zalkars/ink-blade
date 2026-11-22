extends RefCounted

## Визуал игрока в стиле 0.2 (тело, плащ, шарф, кисть-клинок, тень и аура лечения).

const HEAL_TIME := 0.8

var x := 0.0
var y := 0.0
var w := 28.0
var h := 46.0
var vx := 0.0
var vy := 0.0
var facing := 1
var grounded := false
var dead := false
var iframes := 0.0
var hurt_t := 0.0
var healing := false
var heal_t := 0.0
var squash := 1.0
var dash_active := false
var t := 0.0
var run_phase := 0.0
var blink_t := 2.0
var attack = null
var ground_y := 720.0
var scarf: Array = []
var scarf_acc := 0.0


func _init(_unused = null, px := 0.0, py := 0.0) -> void:
	x = px
	y = py
	reset_scarf()


func cx() -> float:
	return x + w * 0.5


func cy() -> float:
	return y + h * 0.5


func neck() -> Vector2:
	return Vector2(cx() - float(facing) * 2.0, y + 13.0)


func reset_scarf() -> void:
	var n := neck()
	scarf.clear()
	for i in range(9):
		var sx := n.x - float(facing) * float(i) * 4.0
		scarf.append({"x": sx, "y": n.y, "px": sx, "py": n.y})


func scarf_step() -> void:
	if scarf.is_empty():
		reset_scarf()
	var pts := scarf
	var n := neck()
	pts[0].x = n.x
	pts[0].y = n.y
	pts[0].px = n.x
	pts[0].py = n.y

	var wind := -float(facing) * 26.0 - vx * 0.16 + sin(t * 2.6) * 28.0
	for i in range(1, pts.size()):
		var p: Dictionary = pts[i]
		var pvx: float = (p.x - p.px) * 0.9
		var pvy: float = (p.y - p.py) * 0.9
		p.px = p.x
		p.py = p.y
		p.x = p.x + pvx + wind * 0.018
		p.y = p.y + pvy + 0.34
	for k in range(2):
		for i in range(1, pts.size()):
			var a: Dictionary = pts[i - 1]
			var b: Dictionary = pts[i]
			var dx: float = b.x - a.x
			var dy: float = b.y - a.y
			var d := sqrt(dx * dx + dy * dy) + 0.001
			var diff := (d - 6.2) / d
			b.x -= dx * diff
			b.y -= dy * diff


func blade_angle() -> float:
	var ang := 1.02 + sin(t * 2.1) * 0.04
	if not grounded:
		ang = 1.25
	if dash_active:
		ang = 1.6
	if healing:
		ang = 1.85
	if attack == null:
		return ang
	var a: Dictionary = attack
	var k: float
	if a.t < a.windup:
		k = -0.18 * (a.t / maxf(0.001, a.windup))
	elif a.t < a.windup + a.active:
		k = 1.0 - pow(1.0 - (a.t - a.windup) / maxf(0.001, a.active), 3.0)
	else:
		k = 1.0
	var out: float
	if a.dir == "fwd":
		out = lerpf(-1.35, 1.35, k)
	elif a.dir == "up":
		out = lerpf(2.1, -2.55, k)
	else:
		out = lerpf(-2.0, 2.0, k)
	if a.has("recover"):
		var recovery := clampf((a.t - a.windup - a.active) / maxf(a.recover, 0.001), 0.0, 1.0)
		return lerp_angle(out, 1.02, recovery * recovery * (3.0 - 2.0 * recovery))
	return out


func draw() -> void:
	var ink := InkR
	if dead:
		return
	ink.save()
	var lean := -hurt_t * 32.0
	if attack != null:
		lean += sin(clampf((attack.t - attack.windup) / maxf(attack.active, 0.001), 0.0, 1.0) * PI) * 9.0
	ink.t_translate(cx(), y + h)
	ink.t_rotate_deg(lean * facing)
	ink.t_translate(-cx(), -y - h)

	var gy := ground_y
	if gy < 715.0:
		var shadow_air := clampf((gy - (y + h)) / 260.0, 0.0, 1.0)
		ink.ellipse_shadow(cx(), gy - 2.0, 17.0 * (1.0 - shadow_air * 0.45), 4.6, 0.22 * (1.0 - shadow_air * 0.6))

	_draw_scarf()
	_draw_swing()

	var flash := hurt_t > 0.0 and int(hurt_t * 34.0) % 2 == 0
	var body_fill := ink.RED if flash else ink.CREAM
	var body_alpha := 0.55 if (iframes > 0.0 and hurt_t <= 0.0 and not dash_active and int(t * 22.0) % 2 == 0) else 1.0

	ink.save()
	ink.t_translate(cx(), y + h)

	var sy := clampf(squash, 0.8, 1.12)
	var sx := 2.0 - sy
	ink.t_scale(float(facing) * sx, sy)

	var moving := grounded and absf(vx) > 20.0
	var walk := sin(run_phase) if moving else 0.0
	var air := not grounded
	var bob := absf(sin(run_phase)) * 1.2 if moving else sin(t * 2.2) * 0.7

	# Ноги.
	var leg_y := -14.0
	var leg_swing := walk * 4.5
	var foot_a := -7.0 if air else -5.0 + leg_swing
	var foot_b := 4.0 if air else 5.0 - leg_swing
	var knee_a := -10.0 if air else -7.0 + leg_swing * 0.5
	var knee_b := -5.0 if air else -6.0 - leg_swing * 0.5
	ink.poly([Vector2(-3, leg_y), Vector2(knee_a, -7), Vector2(foot_a, -1)], 3.4, ink.INK, body_alpha, 0.5)
	ink.poly([Vector2(3, leg_y), Vector2(knee_b, -7), Vector2(foot_b, -1)], 3.4, ink.INK, body_alpha, 0.5)
	ink.line(foot_a - 2, -1, foot_a + 3, -1, 2.6, ink.INK, body_alpha, 0.3)
	ink.line(foot_b - 2, -1, foot_b + 3, -1, 2.6, ink.INK, body_alpha, 0.3)

	# Плащ.
	var sway := clampf(-vx * 0.012, -3.2, 3.2)
	var flap := sin(t * 4.2) * 1.3
	var cloak := [
		Vector2(-11, -32 - bob), Vector2(8, -33 - bob), Vector2(12, -25),
		Vector2(13 + sway * 0.2, -15 + sway * 0.4), Vector2(12, -8 + flap * 0.4),
		Vector2(8, -3), Vector2(6, -7 + flap), Vector2(3, -4),
		Vector2(-1, -8), Vector2(-5, -4), Vector2(-8, -8), Vector2(-12, -9),
		Vector2(-13, -19 + sway * 0.3),
	]
	ink.srand(900)
	ink.fill_poly(cloak, body_fill, body_alpha, 0.9)
	ink.poly(cloak, 2.2, ink.INK, body_alpha, 0.9, true)

	ink.poly([Vector2(-7, -29), Vector2(-8, -20), Vector2(-6, -12)], 1.2, ink.rgba(23, 19, 15, 89), body_alpha, 0.6)
	ink.poly([Vector2(3, -30), Vector2(1, -20), Vector2(4, -12)], 1.1, ink.rgba(23, 19, 15, 64), body_alpha, 0.6)
	ink.poly([Vector2(9, -27), Vector2(10, -19)], 1.0, ink.rgba(23, 19, 15, 51), body_alpha, 0.5)

	# Пояс.
	ink.poly([Vector2(-10, -20), Vector2(11, -21)], 3.2, ink.RED, body_alpha, 0.4)
	ink.blob(9, -20.5, 2.6, ink.RED, ink.INK, 1.0, body_alpha, 0.4)
	var sash_sway := clampf(-vx * 0.02, -5, 5)
	ink.poly([
		Vector2(10, -19), Vector2(12 + sash_sway * 0.5, -13),
		Vector2(10 + sash_sway, -8),
	], 2.2, ink.RED, body_alpha, 0.6)

	# Рука и кисть-клинок.
	var ang2 := blade_angle()
	var hx := 8.5
	var hy := -24.0 - bob
	var dx := cos(ang2)
	var dy := sin(ang2)
	ink.poly([Vector2(6, -29 - bob), Vector2(hx - 1, hy)], 3.6, ink.INK, body_alpha, 0.5)

	var bx := hx + dx * 13.0
	var by := hy + dy * 13.0
	var ex := hx + dx * 37.0
	var ey := hy + dy * 37.0
	ink.line(hx, hy, bx, by, 3.8, ink.INK, body_alpha, 0.4)
	ink.line(hx + dx * 4.0, hy + dy * 4.0, bx, by, 1.3, ink.RED, body_alpha, 0.3)
	var nx := -dy
	var ny := dx
	var bristle := [
		Vector2(bx + nx * 5.4, by + ny * 5.4),
		Vector2(ex + nx * 1.1, ey + ny * 1.1),
		Vector2(ex - nx * 1.1, ey - ny * 1.1),
		Vector2(bx - nx * 5.4, by - ny * 5.4),
	]
	ink.fill_poly(bristle, ink.RED_DARK if (attack != null and attack.step == 3) else ink.INK, body_alpha, 0.6)
	ink.poly(bristle, 1.0, ink.INK, body_alpha, 0.5, true)
	ink.line(bx + nx * 3.0, by + ny * 3.0, bx - nx * 3.0, by - ny * 3.0, 2.8, ink.RED, body_alpha, 0.3)

	# Голова.
	var hb := bob
	var head := [
		Vector2(-9, -35 - hb), Vector2(-8, -44 - hb), Vector2(-2, -49 - hb),
		Vector2(5, -49 - hb), Vector2(11, -44 - hb), Vector2(12, -36 - hb),
		Vector2(8, -31 - hb), Vector2(-3, -31 - hb),
	]
	ink.srand(901)
	ink.fill_poly(head, body_fill, body_alpha, 0.7)
	ink.poly(head, 2.2, ink.INK, body_alpha, 0.7, true)

	var ear_w := sin(t * 3.1) * 1.4
	ink.poly([Vector2(-2, -47 - hb), Vector2(-5 + ear_w, -55 - hb), Vector2(-8 + ear_w, -61 - hb)], 2.8, ink.INK, body_alpha, 0.5)
	ink.poly([Vector2(8, -47 - hb), Vector2(11 - ear_w, -54 - hb), Vector2(14 - ear_w, -59 - hb)], 2.8, ink.INK, body_alpha, 0.5)
	ink.poly([Vector2(-6 + ear_w, -56 - hb), Vector2(-8 + ear_w, -61 - hb)], 1.2, ink.RED, body_alpha, 0.4)
	ink.poly([Vector2(12 - ear_w, -54 - hb), Vector2(14 - ear_w, -59 - hb)], 1.2, ink.RED, body_alpha, 0.4)

	var blink := blink_t < 0.0 or healing
	if blink:
		ink.line(2, -39 - hb, 7, -39 - hb, 1.6, ink.INK, body_alpha, 0.3)
		ink.line(8, -38 - hb, 11, -38 - hb, 1.5, ink.INK, body_alpha, 0.3)
	else:
		ink.blob(5, -39.5 - hb, 2.4, ink.GOLD if healing else ink.RED_BRIGHT, null, 2.0, body_alpha, 0.3, 10, 0.13, false)
		ink.blob(10, -39 - hb, 1.9, ink.GOLD if healing else ink.RED_BRIGHT, null, 2.0, body_alpha, 0.3, 10, 0.13, false)
		ink.line(5.6, -41.8 - hb, 5.6, -41.8 - hb, 1.0, ink.CREAM, 0.85 * body_alpha, 0.2)

	ink.poly([Vector2(-3, -32 - hb), Vector2(1, -30 - hb)], 1.2, ink.rgba(23, 19, 15, 102), body_alpha, 0.4)

	ink.restore()

	# Аура лечения.
	if healing:
		var k2 := clampf(heal_t / HEAL_TIME, 0.0, 1.0)
		var pulse2 := 0.6 + sin(t * 12.0) * 0.2
		ink.save()
		ink.alpha_push(0.75)
		ink.circle(cx(), cy(), 34.0 + sin(t * 6.0) * 2.0, null, ink.GOLD, 1.4, 1.0, 0.7, 16)
		ink.arc(cx(), cy(), 27.0, -PI / 2.0, -PI / 2.0 + InkR.TAU * k2, 3.4, ink.RED, pulse2, 0.6)
		for i in range(3):
			var a3 := t * 1.8 + float(i) / 3.0 * InkR.TAU
			var r3 := 40.0 - fmod(t * 20.0 + float(i) * 8.0, 30.0)
			ink.blob(cx() + cos(a3) * r3, cy() + sin(a3) * r3, 2.2, ink.INK, null, 2.0, 1.0, 0.5, 10, 0.13, false)
		ink.alpha_pop()
		ink.restore()

		if heal_t > HEAL_TIME - 0.1:
			ink.fill_circle_color(cx(), cy(), 45.0, ink.CREAM, 0.25)

	ink.restore()


func _draw_swing() -> void:
	# Paint only: the actor owns all attack timings, reach and hit detection.
	if attack == null or attack.t < attack.windup:
		return
	var progress := clampf((attack.t - attack.windup) / maxf(attack.active, 0.001), 0.0, 1.0)
	var fade := 1.0
	if progress >= 1.0:
		fade = 1.0 - clampf((attack.t - attack.windup - attack.active) / maxf(float(attack.get("recover", 0.15)), 0.001), 0.0, 1.0)
	if fade <= 0.0:
		return
	var start := -1.35
	var sweep := 2.7
	if attack.dir == "up":
		start = -0.2
		sweep = -2.7
	elif attack.dir == "down":
		start = -0.2
		sweep = 2.8
	var finish := start + sweep * maxf(0.12, progress)
	InkR.save()
	InkR.t_translate(cx(), cy())
	InkR.t_scale(float(facing), 1.0)
	InkR.srand(918 + int(attack.step))
	var radius := 46.0 if attack.step < 3 else 53.0
	InkR.taper_arc(0, 0, radius, start, finish, 2.0, 10.0, InkR.INK, fade * 0.78, 0.65)
	InkR.taper_arc(0, 0, radius + 5.0, start + sweep * 0.08, finish, 1.0, 3.0, InkR.RED, fade * 0.8, 0.45)
	InkR.arc(0, 0, radius - 4.0, start, finish, 1.1, InkR.RED_BRIGHT, fade * 0.7, 0.2)
	InkR.restore()


func _draw_scarf() -> void:
	var ink := InkR
	if scarf.size() < 3:
		return
	var widths := [5.4, 5.3, 4.8, 4.2, 3.6, 3.0, 2.4, 1.9, 1.4]
	var left: Array = []
	var right: Array = []
	for i in range(scarf.size()):
		var prev: Dictionary = scarf[maxi(0, i - 1)]
		var nextp: Dictionary = scarf[mini(scarf.size() - 1, i + 1)]
		var dx: float = nextp.x - prev.x
		var dy: float = nextp.y - prev.y
		var d := sqrt(dx * dx + dy * dy) + 0.001
		dx /= d
		dy /= d
		var wid: float = widths[i] if i < widths.size() else 1.2
		left.append(Vector2(scarf[i].x - dy * wid, scarf[i].y + dx * wid))
		right.append(Vector2(scarf[i].x + dy * wid, scarf[i].y - dx * wid))
	ink.srand(777)
	var fill_col := ink.rgba(150, 30, 37, 240)
	for i in range(scarf.size() - 1):
		var quad := [left[i], right[i], right[i + 1], left[i + 1]]
		ink.fill_poly(quad, fill_col, 1.0, 0.0)

	var outline: Array = []
	for p in left:
		outline.append(p)
	for i in range(right.size() - 1, -1, -1):
		outline.append(right[i])
	ink.poly(outline, 1.2, ink.rgba(23, 19, 15, 204), 1.0, 0.4, true)

	var tip: Dictionary = scarf[scarf.size() - 1]
	ink.blob(tip.x, tip.y, 2.2, ink.RED_DARK, null, 2.0, 1.0, 0.4, 10, 0.13, false)
