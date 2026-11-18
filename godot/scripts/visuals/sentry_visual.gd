extends InkEnemy

var charge := 0.0
var charging := false
var anchor_x := 0.0

func _init(game, X: float, Y: float) -> void:
	super(game, "sentry", X, Y, 40.0, 40.0, 2.0)

## v0.2 eye renderer without arena-specific shadow or simulation effects.

func draw() -> void:
	var ink := InkR
	if dead:
		return
	var p = g.player
	var flash: bool = hurt_t > 0 and int(hurt_t * 50) % 2 == 0
	var fill: Color = ink.RED if flash else ink.CREAM


	for i in range(4):
		var ox: float = -15 + i * 10
		var ph: float = t * 2.2 + i * 1.4
		ink.poly([
			Vector2(cx() + ox, cy() + 10),
			Vector2(cx() + ox + sin(ph) * 8, cy() + 26),
			Vector2(cx() + ox + sin(ph + 1) * 12, cy() + 40)
		], 2.0, ink.rgba(23, 19, 15, 140), 1.0, 0.8)

	if charging:
		var k: float = charge / 0.55
		ink.save()
		ink.arc(cx(), cy(), 26 + (1 - k) * 22, 0, InkR.TAU, 1.5, ink.RED, 0.3 + k * 0.5, 0.6)
		ink.restore()

		var ax: float = atan2(p.cy() - cy(), p.cx() - cx())
		ink.line(cx() + cos(ax) * 22, cy() + sin(ax) * 22, p.cx(), p.cy(),
			1.4, ink.RED, 0.18 + k * 0.4, 0.0, [4.0, 9.0])

	ink.srand(int(anchor_x))
	ink.blob(cx(), cy(), 21, fill, ink.INK, 2.4, 1.0, 1.1, 12, 0.1)
	ink.hatch(ink.circle_pts(cx(), cy(), 20, 14), 9.0, 0.09)

	var ex: float = cx() + clampf((p.cx() - cx()) * 0.06, -5, 5)
	var ey: float = cy() + clampf((p.cy() - cy()) * 0.06, -4, 4)
	ink.blob(ex, ey, 10.5, ink.CREAM, ink.INK, 1.8, 1.0, 0.5, 10)
	ink.blob(ex, ey, 5.4 + charge * 4.0, ink.RED_BRIGHT if charging else ink.RED,
		null, 2.0, 1.0, 0.3, 10, 0.13, false)
	ink.blob(ex, ey, 2.2, ink.INK, null, 2.0, 1.0, 0.2, 10, 0.13, false)
	ink.line(ex + 3, ey - 4, ex + 4, ey - 2, 1.4, ink.CREAM, 1.0, 1.0)

	var tilt := -3.0 if charging else 0.0
	ink.poly([
		Vector2(ex - 8, ey - 11 + tilt), Vector2(ex, ey - 13),
		Vector2(ex + 7, ey - 11 - tilt)
	], 2.0, ink.INK, 1.0, 0.4)


	draw_pips()
