extends RefCounted

## Визуал Ползуна в стиле 0.2 (независимый от legacy-скриптов).

var x := -28.0
var y := -16.0
var w := 56.0
var h := 36.0
var spawn_x := 0.0
var spawn_y := 0.0
var facing := -1
var t := 0.0
var hurt_t := 0.0
var hp := 2.0
var max_hp := 2.0
var pip_t := 0.7
var leg_phase := 0.0
var glow := 0.0
var state := "patrol"


func _init(_unused = null, px := -28.0, py := -16.0) -> void:
	x = px
	y = py
	spawn_x = px
	spawn_y = py


func cx() -> float:
	return x + w * 0.5


func cy() -> float:
	return y + h * 0.5


func draw() -> void:
	var ink := InkR
	var gy := y + h
	ink.ellipse_shadow(cx(), gy - 2.0, 26.0, 5.0, 0.2)

	ink.save()
	ink.t_translate(cx(), gy)
	ink.t_rotate_deg(-hurt_t * 48.0)
	var squash := (1.0 + glow * 0.1) if state == "windup" else 1.0
	ink.t_scale(float(facing) * (1.0 + hurt_t * 0.6), (2.0 - squash) * (1.0 - hurt_t * 0.7))

	var flash := hurt_t > 0.0 and int(hurt_t * 50.0) % 2 == 0
	var fill := ink.RED if flash else ink.CREAM
	var back := ink.RED if flash else ink.rgba(23, 19, 15, 36)

	for i in range(3):
		var lx := -14.0 + float(i) * 12.0
		var swing := sin(leg_phase + float(i) * 2.1) * 3.0
		ink.poly([
			Vector2(lx, -12), Vector2(lx + 2.0 + swing, -5),
			Vector2(lx + 3.0 + swing, -1),
		], 2.7, ink.INK, 1.0, 0.5)

	var tail := sin(t * 4.0) * 4.0
	ink.poly([
		Vector2(-24, -15), Vector2(-31, -20 + tail), Vector2(-34, -28 + tail),
	], 2.4, ink.INK, 1.0, 0.7)

	var body := [
		Vector2(-26, -12), Vector2(-23, -22), Vector2(-12, -27),
		Vector2(4, -28), Vector2(17, -24), Vector2(26, -17),
		Vector2(28, -9), Vector2(22, -4), Vector2(10, -3),
		Vector2(-4, -4), Vector2(-17, -3), Vector2(-24, -7),
	]
	ink.srand(int(spawn_x + spawn_y))
	ink.fill_poly(body, fill, 1.0, 1.0)
	ink.poly(body, 2.4, ink.INK, 1.0, 1.0, true)

	ink.fill_poly([
		Vector2(-22, -20), Vector2(-12, -27), Vector2(4, -28),
		Vector2(16, -24), Vector2(6, -20), Vector2(-8, -18),
	], back, 0.55, 0.8, false)

	for i in range(3):
		var bx := -14.0 + float(i) * 9.0
		ink.fill_poly([
			Vector2(bx - 4, -25), Vector2(bx, -35 - i), Vector2(bx + 4, -25),
		], ink.RED if flash else ink.INK, 1.0, 0.5)

	ink.poly([
		Vector2(17, -20), Vector2(30, -15), Vector2(31, -9),
		Vector2(23, -6),
	], 2.0, ink.INK, 1.0, 0.5)
	ink.fill_poly([
		Vector2(22, -12), Vector2(31, -9), Vector2(25, -6),
	], ink.INK, 1.0, 0.5)
	ink.line(23, -8.5, 29, -8.5, 1.2, ink.CREAM, 0.75, 0.2)
	for i in range(3):
		ink.line(24 + float(i) * 2.1, -9, 24.6 + float(i) * 2.1, -6.6, 0.9, ink.CREAM, 0.7, 0.1)

	var eye_glow := glow
	var eye_r := 6.2 + eye_glow * 2.2
	ink.circle(19, -17, eye_r, ink.CREAM, ink.INK, 1.6, 1.0, 0.4, 9)
	ink.blob(21, -17, 2.8 + eye_glow * 0.8,
		ink.RED_BRIGHT if eye_glow > 0.4 else ink.RED, null, 2.0, 1.0, 0.3, 10, 0.13, false)
	ink.poly([Vector2(24, -12), Vector2(28, -13)], 1.4, ink.INK)

	ink.restore()
	_draw_pips()


func _draw_pips() -> void:
	if hp >= max_hp or max_hp >= 90.0:
		return
	var alpha := minf(0.7, pip_t)
	for i in range(int(max_hp)):
		var px := cx() + (float(i) - (max_hp - 1.0) / 2.0) * 9.0
		var py := y - 10.0
		if float(i) < hp:
			InkR.circle(px, py, 2.6, InkR.RED, null, 2.0, alpha, 0.3, 6, false)
		else:
			InkR.circle(px, py, 2.2, null, InkR.INK, 1.0, alpha * 0.5, 0.3, 6)
