class_name InkSentry
extends InkEnemy

## Парящее око — порт Sentry

var anchor_x := 0.0
var anchor_y := 0.0
var kx := 0.0
var ky := 0.0
var cool := 0.0
var charge := 0.0
var charging := false

func _init(game, X: float, Y: float) -> void:
	super(game, "sentry", X, Y, 40.0, 40.0, 2.0)
	hover = true
	anchor_x = X
	anchor_y = Y
	cool = randf_range(0.8, 1.4)

func behavior(dt: float) -> void:
	var p = g.player
	var bob := sin(t * 1.7) * 9.0
	kx *= pow(0.002, dt)
	ky *= pow(0.002, dt)
	x = anchor_x + kx
	y = anchor_y + bob + ky

	var dx: float = p.cx() - cx()
	var dy: float = p.cy() - cy()
	var sees: bool = not p.dead and Vector2(dx, dy).length() < 620.0

	if charging:
		charge += dt
		if charge >= 0.55:
			charging = false
			charge = 0.0
			cool = 1.65
			fire(dx, dy)
	else:
		cool -= dt
		if cool <= 0.0 and sees:
			charging = true
			charge = 0.0
			SND.tone({"type": "sine", "freq": 280.0, "freq2": 520.0, "dur": 0.5, "gain": 0.035})
		if cool < -0.4:
			cool = 0.6

func fire(dx: float, dy: float) -> void:
	var a := atan2(dy, dx)
	const SPEED := 345.0
	kx -= cos(a) * 14.0
	ky -= sin(a) * 14.0
	g.projectiles.append(InkBolt.new(g, cx() + cos(a) * 20.0, cy() + sin(a) * 20.0,
		cos(a) * SPEED, sin(a) * SPEED))
	InkFx.sparks(cx(), cy(), a, 8, InkR.RED_BRIGHT)
	InkFx.ring(cx(), cy(), 8, 36, InkR.RED, 0.3, 2)
	SND.noise({"freq": 1400.0, "freq2": 300.0, "dur": 0.22, "gain": 0.07})
	InkFx.add_shake(2.0)

func hurt(dmg: float, dir_x: float, heavy: bool) -> void:
	super.hurt(dmg, dir_x, heavy)
	if not dead:
		kx += dir_x * 22.0
		ky -= 14.0
		charging = false
		charge = 0.0
		cool = maxf(cool, 0.7)

func draw() -> void:
	var ink := InkR
	if dead:
		return
	var p = g.player
	var flash: bool = hurt_t > 0 and int(hurt_t * 50) % 2 == 0
	var fill: Color = ink.RED if flash else ink.CREAM

	ink.ellipse_shadow(cx(), 618, 18, 4, 0.08)

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

	if randf() < 0.02:
		InkFx.sparks(cx(), cy() + 16, PI / 2, 1, InkR.INK_SOFT)

	draw_pips()
