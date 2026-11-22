class_name InkGrunt
extends InkEnemy

## Чернильный гончий — порт Grunt

var min_x := 0.0
var max_x := 0.0
var glow := 0.0
var leg_phase := 0.0

func _init(game, X: float, Y: float, facing_ := -1, min_x_ = null, max_x_ = null) -> void:
	super(game, "grunt", X, Y, 56.0, 36.0, 3.0)
	facing = facing_
	min_x = min_x_ if min_x_ != null else X - 110.0
	max_x = max_x_ if max_x_ != null else X + 110.0
	set_state("patrol", 0.4)

func behavior(dt: float) -> void:
	var p = g.player
	var dx: float = p.cx() - cx()
	var dy: float = p.cy() - cy()
	var sees: bool = not p.dead and absf(dx) < 340.0 and absf(dy) < 120.0

	if hurt_t > 0.0:
		vx *= pow(0.02, dt)
		return

	match state:
		"patrol":
			vx = float(facing) * 78.0
			if grounded:
				var ahead: float = x + w + 10.0 if facing > 0 else x - 10.0
				var ground: bool = InkWorld.has_ground_at(ahead, y + h + 3.0)
				if not ground or x < min_x or x + w > max_x or hit_wall:
					facing *= -1
					set_state("patrol", 0.45)
					vx = 0.0
			leg_phase += absf(vx) * dt * 0.09
			if sees:
				facing = 1 if dx > 0 else -1
				set_state("windup", 0.48)
				vx = 0.0
		"windup":
			vx = approach(vx, 0.0, 2400.0 * dt)
			glow = minf(1.0, glow + dt * 5.0)
			facing = 1 if dx > 0 else -1
			state_t -= dt
			if state_t <= 0.0:
				set_state("lunge", 0.27)
				vx = float(facing) * 650.0
				vy = -60.0
				InkFx.dust(cx(), y + h, 5, float(-facing))
				SND.noise({"freq": 700.0, "dur": 0.12, "gain": 0.05, "type": "lowpass"})
		"lunge":
			vx = float(facing) * 650.0
			state_t -= dt
			if state_t <= 0.0:
				set_state("recover", 0.55)
				vx *= 0.2
		"recover":
			vx = approach(vx, 0.0, 2600.0 * dt)
			glow = maxf(0.0, glow - dt * 4.0)
			state_t -= dt
			if state_t <= 0.0:
				set_state("patrol", 0.5)
		_:
			state_t -= dt
			if state_t <= 0.0:
				set_state("patrol", 0.5)

	if state != "windup":
		glow = maxf(0.0, glow - dt * 3.0)

func approach(v: float, tgt: float, delta: float) -> float:
	if v < tgt:
		return minf(v + delta, tgt)
	return maxf(v - delta, tgt)

func hurt(dmg: float, dir_x: float, heavy: bool) -> void:
	super.hurt(dmg, dir_x, heavy)
	if not dead:
		set_state("recover", 0.32)

func draw() -> void:
	if dead:
		return
	var ink := InkR
	var gy: float = y + h
	ink.ellipse_shadow(cx(), gy - 2.0, 26, 5, 0.2)

	if state == "windup":
		var k: float = 1.0 - maxf(0.0, state_t) / 0.48
		ink.line(cx() + float(facing) * 20, cy(), g.player.cx(), g.player.cy(),
			1.6, ink.RED, 1.0, 0.0, [7.0, 8.0])

	ink.save()
	ink.t_translate(cx(), gy)
	var squash: float = (1.0 + glow * 0.1) if state == "windup" else 1.0
	ink.t_scale(float(facing), 2.0 - squash)

	var flash: bool = hurt_t > 0 and int(hurt_t * 50) % 2 == 0
	var fill: Color = ink.RED if flash else ink.CREAM
	var back: Color = ink.RED if flash else ink.rgba(23, 19, 15, 36)

	# ноги
	for i in range(3):
		var lx: float = -14 + i * 12
		var swing: float = sin(leg_phase + i * 2.1) * 3 if state == "patrol" else 1.5
		ink.poly([
			Vector2(lx, -12), Vector2(lx + 2 + swing, -5),
			Vector2(lx + 3 + swing, -1)
		], 2.7, ink.INK, 1.0, 0.5)

	# хвост
	var tail: float = sin(t * 4) * 4
	ink.poly([
		Vector2(-24, -15), Vector2(-31, -20 + tail), Vector2(-34, -28 + tail)
	], 2.4, ink.INK, 1.0, 0.7)

	# тело
	var body := [
		Vector2(-26, -12), Vector2(-23, -22), Vector2(-12, -27),
		Vector2(4, -28), Vector2(17, -24), Vector2(26, -17),
		Vector2(28, -9), Vector2(22, -4), Vector2(10, -3),
		Vector2(-4, -4), Vector2(-17, -3), Vector2(-24, -7)
	]
	ink.srand(int(spawn_x + spawn_y))
	ink.fill_poly(body, fill, 1.0, 1.0)
	ink.poly(body, 2.4, ink.INK, 1.0, 1.0, true)

	# тёмная спина
	ink.fill_poly([
		Vector2(-22, -20), Vector2(-12, -27), Vector2(4, -28),
		Vector2(16, -24), Vector2(6, -20), Vector2(-8, -18)
	], back, 0.55, 0.8, false)

	# шипы на спине
	for i in range(3):
		var bx: float = -14 + i * 9
		ink.fill_poly([
			Vector2(bx - 4, -25), Vector2(bx, -35 - i), Vector2(bx + 4, -25)
		], ink.RED if flash else ink.INK, 1.0, 0.5)

	# морда и пасть
	ink.poly([
		Vector2(17, -20), Vector2(30, -15), Vector2(31, -9),
		Vector2(23, -6)
	], 2.0, ink.INK, 1.0, 0.5)
	ink.fill_poly([
		Vector2(22, -12), Vector2(31, -9), Vector2(25, -6)
	], ink.INK, 1.0, 0.5)
	ink.line(23, -8.5, 29, -8.5, 1.2, ink.CREAM, 0.75, 0.2)
	for i in range(3):
		ink.line(24 + i * 2.1, -9, 24.6 + i * 2.1, -6.6, 0.9, ink.CREAM, 0.7, 0.1)

	# глаз
	var eye_glow := glow
	var eye_r: float = 6.2 + eye_glow * 2.2
	ink.circle(19, -17, eye_r, ink.CREAM, ink.INK, 1.6, 1.0, 0.4, 9)
	ink.blob(21, -17, 2.8 + eye_glow * 0.8,
		ink.RED_BRIGHT if eye_glow > 0.4 else ink.RED, null, 2.0, 1.0, 0.3, 10, 0.13, false)
	ink.poly([Vector2(24, -12), Vector2(28, -13)], 1.4, ink.INK)

	if state == "lunge" and randf() < 0.4:
		InkFx.dust(cx() - float(facing) * 18.0, gy, 1, float(-facing))

	ink.restore()
	draw_pips()
