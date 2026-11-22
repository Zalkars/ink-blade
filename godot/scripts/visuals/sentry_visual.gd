extends RefCounted

## Визуал Часового в стиле 0.2 (независимый от legacy-скриптов).

var x := -20.0
var y := -20.0
var w := 40.0
var h := 40.0
var t := 0.0
var hurt_t := 0.0
var hp := 3.0
var max_hp := 3.0
var pip_t := 0.7
var charge := 0.0
var charging := false
var anchor_x := 0.0
var look_pos := Vector2(100.0, 0.0)


func _init(_unused = null, px := -20.0, py := -20.0) -> void:
	x = px
	y = py
	anchor_x = px


func cx() -> float:
	return x + w * 0.5


func cy() -> float:
	return y + h * 0.5


func draw() -> void:
	var ink := InkR
	ink.save()
	ink.t_translate(cx(), cy())
	ink.t_rotate_deg(sin(t * 28.0) * hurt_t * 65.0)
	ink.t_scale(1.0 + hurt_t * 0.7, 1.0 - hurt_t * 0.6)
	ink.t_translate(-cx(), -cy())
	var flash := hurt_t > 0.0 and int(hurt_t * 50.0) % 2 == 0
	var fill := ink.RED if flash else ink.CREAM

	for i in range(4):
		var ox := -15.0 + float(i) * 10.0
		var ph := t * 2.2 + float(i) * 1.4
		ink.poly([
			Vector2(cx() + ox, cy() + 10),
			Vector2(cx() + ox + sin(ph) * 8.0, cy() + 26),
			Vector2(cx() + ox + sin(ph + 1.0) * 12.0, cy() + 40),
		], 2.0, ink.rgba(23, 19, 15, 140), 1.0, 0.8)

	if charging:
		var k := charge / 0.55
		ink.save()
		ink.arc(cx(), cy(), 26.0 + (1.0 - k) * 22.0, 0.0, InkR.TAU, 1.5, ink.RED, 0.3 + k * 0.5, 0.6)
		ink.restore()
		var ax := atan2(look_pos.y - cy(), look_pos.x - cx())
		ink.line(cx() + cos(ax) * 22.0, cy() + sin(ax) * 22.0, look_pos.x, look_pos.y,
			1.4, ink.RED, 0.18 + k * 0.4, 0.0, [4.0, 9.0])

	ink.srand(int(anchor_x))
	ink.blob(cx(), cy(), 21, fill, ink.INK, 2.4, 1.0, 1.1, 12, 0.1)
	ink.hatch(ink.circle_pts(cx(), cy(), 20, 14), 9.0, 0.09)

	var ex := cx() + clampf((look_pos.x - cx()) * 0.06, -5.0, 5.0)
	var ey := cy() + clampf((look_pos.y - cy()) * 0.06, -4.0, 4.0)
	ink.blob(ex, ey, 10.5, ink.CREAM, ink.INK, 1.8, 1.0, 0.5, 10)
	ink.blob(ex, ey, 5.4 + charge * 4.0, ink.RED_BRIGHT if charging else ink.RED,
		null, 2.0, 1.0, 0.3, 10, 0.13, false)
	ink.blob(ex, ey, 2.2, ink.INK, null, 2.0, 1.0, 0.2, 10, 0.13, false)
	ink.line(ex + 3, ey - 4, ex + 4, ey - 2, 1.4, ink.CREAM, 1.0, 1.0)

	var tilt := -3.0 if charging else 0.0
	ink.poly([
		Vector2(ex - 8, ey - 11 + tilt), Vector2(ex, ey - 13),
		Vector2(ex + 7, ey - 11 - tilt),
	], 2.0, ink.INK, 1.0, 0.4)

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
