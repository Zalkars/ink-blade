class_name InkDummy
extends InkEnemy

## Учебное чучело — порт Dummy

var wobble := 0.0
var wobble_v := 0.0
var total := 0.0
var hits := 0

func _init(game, X: float, Y: float) -> void:
	super(game, "dummy", X, Y, 44.0, 60.0, 999.0)
	contact = false

func behavior(dt: float) -> void:
	wobble_v += -wobble * 90.0 * dt
	wobble_v *= pow(0.02, dt)
	wobble += wobble_v * dt
	wobble = clampf(wobble, -0.5, 0.5)

func hurt(dmg: float, dir_x: float, heavy: bool) -> void:
	wobble_v += dir_x * 9.0
	total += dmg
	hits += 1
	hurt_t = 0.14
	InkFx.text_fx(cx() + randf_range(-6, 6), y - 4, "%d" % int(dmg), 22, InkR.RED, false, 0.7)
	InkFx.ink_burst(cx() + randf_range(-8, 8), cy() - 6, 5, 160.0, null, 3.0, false,
		null, 0.0, 0.0, 700.0, 618.0)
	InkFx.sparks(cx(), cy() - 8, 0.0 if dir_x > 0 else PI, 4, InkR.GOLD)
	SND.hit(dmg > 1)
	InkFx.add_shake(2.0)
	g.add_combo()
	g.freeze(0.035)

func draw() -> void:
	var ink := InkR
	ink.ellipse_shadow(cx(), 618, 24, 5, 0.18)

	ink.save()
	ink.t_translate(cx(), 620)
	ink.t_rotate_deg(wobble * 0.12 * 180.0 / PI)
	var flash: bool = hurt_t > 0

	ink.rect(-20, -8, 40, 8, ink.rgba(120, 98, 64, 128), ink.INK, 1.8, 1.0, 0.7)
	ink.rect(-4, -44, 8, 38, ink.rgba(190, 166, 120, 217), ink.INK, 1.6, 1.0, 0.6)

	var body := [
		Vector2(-17, -44), Vector2(-15, -58), Vector2(-5, -64),
		Vector2(9, -64), Vector2(18, -56), Vector2(19, -44),
		Vector2(12, -38), Vector2(-4, -38), Vector2(-14, -40)
	]
	ink.srand(515)
	ink.fill_poly(body, ink.RED if flash else ink.BONE, 1.0, 1.0)
	ink.poly(body, 2.0, ink.INK, 1.0, 1.0, true)

	ink.circle(0, -51, 9, null, ink.RED, 2.0, 1.0, 0.5, 12)
	ink.circle(0, -51, 4.4, ink.RED, null, 2.0, 1.0, 0.4, 10, false)
	ink.line(-24, -51, -20, -51, 1.5, ink.RED, 1.0, 1.0)

	ink.blob(0, -71, 10, ink.RED if flash else ink.GOLD, ink.INK, 1.8, 1.0, 1.0, 11)
	ink.line(-7, -78, -11, -84, 1.6, ink.INK, 1.0, 1.0)
	ink.line(4, -81, 2, -88, 1.6, ink.INK, 1.0, 1.0)
	ink.line(-3, -63, 3, -63, 1.4, ink.INK, 0.5, 1.0)

	ink.line(-5, -74, -1, -70, 1.8, ink.INK, 1.0, 1.0)
	ink.line(-5, -70, -1, -74, 1.8, ink.INK, 1.0, 1.0)
	ink.line(2, -74, 6, -70, 1.8, ink.INK, 1.0, 1.0)
	ink.line(2, -70, 6, -74, 1.8, ink.INK, 1.0, 1.0)

	ink.restore()

	if hits > 0:
		ink.text("УРОН: %d" % int(total), cx(), y - 30, 14, ink.F_DISPLAY, ink.A_CENTER,
			ink.INK, 0.45, 2)
