class_name InkPlayer
extends RefCounted

## Полный порт Game/Player.cs

const RUN_SPEED := 300.0
const GRAV := 2520.0
const MAX_FALL := 1180.0
const ACC_G := 3300.0
const DEC_G := 3900.0
const ACC_A := 2200.0
const DEC_A := 1050.0
const JUMP_VEL := 800.0
const COYOTE := 0.1
const JUMP_BUF := 0.13
const DASH_SPEED := 870.0
const DASH_TIME := 0.15
const DASH_CD := 0.34
const SOUL_MAX := 99.0
const HEAL_COST := 40.0
const HEAL_TIME := 0.8

# (windup, active, recover, reach, dmg, knock)
const ATTACKS := [
	null,
	[0.05, 0.10, 0.10, 66.0, 1.0, 280.0],
	[0.045, 0.10, 0.11, 70.0, 1.0, 320.0],
	[0.07, 0.12, 0.16, 78.0, 2.0, 420.0],
]

var g = null  # game

# Body
var x := 0.0
var y := 0.0
var w := 28.0
var h := 46.0
var vx := 0.0
var vy := 0.0
var grounded := false
var on_one_way := false
var hit_wall := false
var drop_t := 0.0

var facing := 1
var coyote := 0.0
var jump_buf := 0.0
var hp := 5.0
var max_hp := 5.0
var soul := 0.0
var iframes := 0.0
var hurt_t := 0.0
var dead := false
var death_t := 0.0

var dash_active := false
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := 1
var air_dash := true

var attack = null   # dict
var attack_cd := 0.0
var attack_queued := false
var combo_step := 0
var combo_timer := 0.0

var healing := false
var heal_t := 0.0
var heal_fx_t := 0.0

var t := 0.0
var squash := 1.0
var run_phase := 0.0
var blink_t := 2.0
var ghost_t := 0.0
var landed_fx := 0.0

var scarf: Array = []
var scarf_acc := 0.0

func _init(game, X: float, Y: float) -> void:
	g = game
	x = X
	y = Y
	w = 28.0
	h = 46.0
	reset_scarf()

func cx() -> float:
	return x + w * 0.5

func cy() -> float:
	return y + h * 0.5

func hitbox() -> Rect2:
	return Rect2(x + 3, y + 2, w - 6, h - 3)

func is_invuln() -> bool:
	return dead or iframes > 0.0 or dash_active

func gain_soul(n: float) -> void:
	soul = minf(SOUL_MAX, soul + n)

func reset_scarf() -> void:
	var n := neck()
	scarf.clear()
	for i in range(9):
		var sx: float = n.x - float(facing) * float(i) * 4.0
		scarf.append({"x": sx, "y": n.y, "px": sx, "py": n.y})

func neck() -> Vector2:
	return Vector2(cx() - float(facing) * 2.0, y + 13.0)

# ---------- update ----------
func update(dt: float) -> void:
	t += dt
	iframes = maxf(0.0, iframes - dt)
	hurt_t = maxf(0.0, hurt_t - dt)
	attack_cd = maxf(0.0, attack_cd - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	drop_t = maxf(0.0, drop_t - dt)
	jump_buf = maxf(0.0, jump_buf - dt)
	combo_timer = maxf(0.0, combo_timer - dt)
	if combo_timer <= 0.0:
		combo_step = 0
	blink_t -= dt
	if blink_t < -0.12:
		blink_t = randf_range(2.0, 5.0)
	squash += (1.0 - squash) * minf(1.0, dt * 17.0)
	landed_fx = maxf(0.0, landed_fx - dt)

	if dead:
		death_t += dt
		vy = minf(vy + GRAV * dt, MAX_FALL)
		y += vy * dt
		vx *= 0.96
		x += vx * dt
		return

	if grounded:
		coyote = COYOTE
	else:
		coyote = maxf(0.0, coyote - dt)

	var ix: float = CTL.axis_x()
	var iy: float = CTL.axis_y()
	var move: float = ix if absf(ix) > 0.18 else 0.0
	var jump_pressed: bool = CTL.pressed("jump")
	var attack_pressed: bool = CTL.pressed("attack")
	var dash_pressed: bool = CTL.pressed("dash")
	var heal_held: bool = CTL.down("heal")

	# --- лечение ---
	if healing:
		var can_hold: bool = heal_held and grounded and soul >= HEAL_COST and hp < max_hp
		if not can_hold or attack_pressed or dash_pressed or hurt_t > 0.0:
			cancel_heal()
		else:
			heal_t += dt
			vx = approach(vx, 0.0, 3200.0 * dt)
			heal_fx_t -= dt
			if heal_fx_t <= 0.0:
				heal_fx_t = 0.13
				var a := randf_range(0.0, InkR.TAU)
				InkFx.ink_burst(cx() + cos(a) * 24.0, cy() + sin(a) * 20.0, 1, 40.0,
					[InkR.RED, InkR.INK, InkR.GOLD], 2.6, false, null,
					-cos(a) * 90.0, -sin(a) * 90.0, -140.0, 9999.0)
			if heal_t >= HEAL_TIME:
				finish_heal()

	if not healing and heal_held and grounded and soul >= HEAL_COST and hp < max_hp \
			and attack == null and not dash_active and hurt_t <= 0.0:
		healing = true
		heal_t = 0.0
		vx = 0.0
		SND.heal_loop()

	# --- прыжок ---
	if not healing and jump_pressed:
		if on_one_way and iy > 0.4:
			drop_t = 0.22
			y += 3.0
			grounded = false
			coyote = 0.0
			jump_buf = 0.0
			InkFx.dust(cx(), y + h, 4, 0.0)
		else:
			jump_buf = JUMP_BUF

	if jump_buf > 0.0 and coyote > 0.0 and not healing:
		vy = -JUMP_VEL
		jump_buf = 0.0
		coyote = 0.0
		grounded = false
		squash = 0.85
		InkFx.dust(cx(), y + h, 5, 0.0)
		SND.jump()

	# --- рывок ---
	if dash_pressed and dash_cd <= 0.0 and not healing and attack == null and (grounded or air_dash):
		start_dash(move)

	# --- атака ---
	if attack_pressed and not healing and not dash_active:
		if attack == null:
			if attack_cd <= 0.0:
				start_attack(0, iy)
		elif attack.t > attack.windup + attack.active * 0.35:
			attack_queued = true

	# --- движение ---
	var target := 0.0
	if not healing and hurt_t <= 0.0 and not dash_active:
		target = move * RUN_SPEED
		if attack != null and grounded:
			target *= 0.3
	var accel := 0.0
	if grounded:
		accel = ACC_G if absf(target) > 1.0 else DEC_G
	else:
		accel = ACC_A if absf(target) > 1.0 else DEC_A
	vx = approach(vx, target, accel * dt)

	if move != 0.0 and attack == null and not healing and hurt_t <= 0.0:
		facing = 1 if move > 0.0 else -1

	# --- таймеры атаки ---
	if attack != null:
		attack.t += dt
		if not attack.spawned and attack.t >= attack.windup:
			attack.spawned = true
			spawn_slash()
			SND.slash(attack.step)
		var active_end: float = attack.windup + attack.active
		var total: float = active_end + attack.recover
		if attack_queued and attack.t >= active_end and attack.step < 3:
			start_attack(attack.step, iy, true)
		elif attack.t >= total:
			attack = null
			attack_cd = 0.06
			attack_queued = false

	# --- рывок ---
	if dash_active:
		dash_t -= dt
		vx = float(dash_dir) * DASH_SPEED
		vy = 0.0
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.028
			InkFx.ghost_trail(x, y, w, h, facing, 0.22)
		if dash_t <= 0.0:
			dash_active = false
			vx *= 0.55

	# --- гравитация ---
	if not dash_active:
		var gz := GRAV
		if vy < 0.0 and not CTL.down("jump"):
			gz *= 2.15
		vy = minf(vy + gz * dt, MAX_FALL)

	# --- коллизии ---
	var was_grounded: bool = grounded
	var fall_speed: float = vy
	InkWorld.move_x(self, dt)
	InkWorld.move_y(self, dt)

	if not was_grounded and grounded:
		squash = 0.82
		air_dash = true
		landed_fx = 0.18
		if fall_speed > 350.0:
			InkFx.dust(cx(), y + h, 6, 0.0)
			SND.land(minf(1.0, fall_speed / 900.0))
			InkFx.add_shake(1.5)

	if grounded and absf(vx) > 12.0 and attack == null:
		run_phase += absf(vx) * dt * 0.085

	if y > 780.0:
		g.hazard_teleport()

	# --- шарф ---
	scarf_acc += dt
	while scarf_acc > 1.0 / 60.0:
		scarf_step()
		scarf_acc -= 1.0 / 60.0

func approach(v: float, tgt: float, delta: float) -> float:
	if v < tgt:
		return minf(v + delta, tgt)
	return maxf(v - delta, tgt)

func scarf_step() -> void:
	var pts := scarf
	var n := neck()
	pts[0].x = n.x
	pts[0].y = n.y
	pts[0].px = n.x
	pts[0].py = n.y

	var wind: float = -float(facing) * 26.0 - vx * 0.16 + sin(t * 2.6) * 28.0
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

func start_dash(move: float) -> void:
	dash_active = true
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	var dir := facing
	if absf(move) > 0.2:
		dir = 1 if move > 0.0 else -1
	dash_dir = dir
	facing = dir
	vy = 0.0
	vx = float(dir) * DASH_SPEED
	if not grounded:
		air_dash = false
	attack = null
	attack_queued = false
	healing = false
	heal_t = 0.0
	iframes = maxf(iframes, 0.19)
	ghost_t = 0.0
	squash = 1.06
	InkFx.dust(cx(), y + h - 2.0, 8, float(-dir))
	InkFx.ring(cx(), cy(), 6, 34, InkR.INK_SOFT, 0.28, 2)
	SND.dash()
	CTL.rumble(0.15, 0.35, 90)

func start_attack(step: int, iy: float, chain := false) -> void:
	var next_step: int
	if chain:
		next_step = mini(3, step + 1)
	elif combo_timer > 0.0 and combo_step > 0 and combo_step < 3:
		next_step = combo_step + 1
	else:
		next_step = 1

	var def: Array = ATTACKS[next_step]
	var dir := "fwd"
	if iy < -0.45:
		dir = "up"
	elif not grounded and iy > 0.45:
		dir = "down"

	var ix: float = CTL.axis_x()
	if dir == "fwd" and absf(ix) > 0.2:
		facing = 1 if ix > 0.0 else -1

	attack = {
		"step": next_step, "dir": dir, "t": 0.0,
		"windup": def[0], "active": def[1], "recover": def[2],
		"reach": def[3], "dmg": def[4], "knock": def[5],
		"spawned": false, "hit": {},
	}
	attack_queued = false
	combo_step = next_step
	combo_timer = 0.55
	attack_cd = 0.04
	healing = false
	squash = 1.03

	if grounded:
		vx += float(facing) * 55.0
	else:
		vx += float(facing) * 110.0

func spawn_slash() -> void:
	var a = attack
	if a == null:
		return
	var cxm := cx()
	var cym := cy() - 2.0
	var a0 := 0.0
	var a1 := 0.0
	var ox := cxm
	var oy := cym
	var radius := 54.0 + float(a.step) * 3.0
	if a.dir == "fwd":
		if facing > 0:
			a0 = -1.2
			a1 = 1.05
		else:
			a0 = PI + 1.2
			a1 = PI - 1.05
		ox = cxm + float(facing) * 6.0
	elif a.dir == "up":
		a0 = PI + 0.35
		a1 = PI * 2 - 0.35
		oy = cym - 18.0
	else:
		a0 = 0.35
		a1 = PI - 0.35
		oy = cym + 14.0

	InkFx.slash(ox, oy, a0, a1, radius, 20, 7, a.active + 0.11,
		InkR.RED_BRIGHT if a.step == 3 else InkR.RED)
	InkFx.sparks(ox + cos(a1) * radius * 0.6, oy + sin(a1) * radius * 0.6, a1, 3, InkR.INK_SOFT)

func attack_active() -> bool:
	var a = attack
	return a != null and a.t >= a.windup and a.t <= a.windup + a.active

func attack_hitbox() -> Rect2:
	var a = attack
	if a == null:
		return Rect2()
	if a.dir == "fwd":
		if facing > 0:
			return Rect2(cx() + 4, cy() - 29, a.reach, 58)
		return Rect2(cx() - 4 - a.reach, cy() - 29, a.reach, 58)
	if a.dir == "up":
		return Rect2(cx() - 27, y - a.reach + 10, 54, a.reach)
	return Rect2(cx() - 27, y + h - 12, 54, a.reach)

func pogo() -> void:
	vy = -660.0
	grounded = false
	squash = 0.88
	air_dash = true
	InkFx.ring(cx(), y + h, 8, 44, InkR.RED, 0.3, 2)
	InkFx.dust(cx(), y + h, 6, 0.0)

func finish_heal() -> void:
	hp = minf(max_hp, hp + 1.0)
	soul -= HEAL_COST
	healing = false
	heal_t = 0.0
	InkFx.ring(cx(), cy(), 12, 60, InkR.GOLD, 0.5, 3)
	InkFx.ink_burst(cx(), cy(), 10, 150.0, [InkR.GOLD, InkR.CREAM, InkR.RED], 3.5,
		false, null, 0.0, 0.0, -160.0, 9999.0)
	InkFx.text_fx(cx(), y - 12, "+1", 22, InkR.RED, false)
	SND.heal()
	CTL.rumble(0.3, 0.5, 160)

func cancel_heal() -> void:
	if not healing:
		return
	healing = false
	heal_t = 0.0

func hurt(dmg: float, src_x: float) -> bool:
	if is_invuln():
		return false
	hp -= dmg
	iframes = 1.1
	hurt_t = 0.34
	attack = null
	attack_queued = false
	healing = false
	heal_t = 0.0
	dash_active = false
	dash_t = 0.0

	var dir := 1
	var dd: float = cx() - src_x
	if absf(dd) >= 1.0:
		dir = -1 if dd < 0 else 1
	else:
		dir = -facing
	vx = float(dir) * 330.0
	vy = -340.0
	grounded = false
	facing = -dir

	InkFx.ink_burst(cx(), cy(), 14, 300.0, [InkR.RED, InkR.RED_DARK, InkR.INK], 5.0, true)
	InkFx.sparks(cx(), cy(), 0.0 if dir > 0 else PI, 9, InkR.RED_BRIGHT)
	InkFx.add_shake(9.0)
	InkFx.damage_screen(1.0)
	InkFx.flash_screen(0.2, InkR.RED)
	InkFx.text_fx(cx(), y - 10, "-%d" % int(dmg), 24, InkR.RED, false)
	SND.hurt()
	CTL.rumble(0.9, 0.5, 220)
	g.freeze(0.075)

	if hp <= 0:
		hp = 0.0
		die()
	return true

func die() -> void:
	if dead:
		return
	dead = true
	death_t = 0.0
	vy = -420.0
	vx = float(-facing) * 90.0
	attack = null
	healing = false
	dash_active = false
	InkFx.ink_burst(cx(), cy(), 34, 440.0, [InkR.INK, InkR.INK, InkR.RED, InkR.INK_SOFT], 7.0, true)
	InkFx.ring(cx(), cy(), 10, 140, InkR.RED, 0.7, 4)
	InkFx.add_shake(16, 0.02)
	InkFx.flash_screen(0.35, InkR.RED)
	SND.death()
	CTL.rumble(1.0, 0.8, 500)

func shadow_y() -> float:
	var best := 720.0
	for s in InkWorld.solids:
		if cx() < s.position.x or cx() > s.end.x:
			continue
		if s.position.y >= y + h - 4 and s.position.y < best:
			best = s.position.y
	for s in InkWorld.oneways:
		if cx() < s.position.x or cx() > s.end.x:
			continue
		if s.position.y >= y + h - 4 and s.position.y < best:
			best = s.position.y
	return best

# ---------- отрисовка ----------
func blade_angle() -> float:
	var ang := 1.02 + sin(t * 2.1) * 0.04
	if not grounded:
		ang = 1.25
	if dash_active:
		ang = 1.6
	if healing:
		ang = 1.85
	var a = attack
	if a == null:
		return ang
	var k: float
	if a.t < a.windup:
		k = -0.18 * (a.t / maxf(0.001, a.windup))
	elif a.t < a.windup + a.active:
		k = 1.0 - pow(1.0 - (a.t - a.windup) / a.active, 3.0)
	else:
		k = 1.0
	if a.dir == "fwd":
		return lerpf(-1.35, 1.35, k)
	if a.dir == "up":
		return lerpf(2.1, -2.55, k)
	return lerpf(-2.0, 2.0, k)

func draw() -> void:
	var ink := InkR
	if dead:
		return
	var gy := shadow_y()
	if gy < 715.0:
		var shadow_air: float = clampf((gy - (y + h)) / 260.0, 0.0, 1.0)
		ink.ellipse_shadow(cx(), gy - 2.0, 17.0 * (1 - shadow_air * 0.45), 4.6, 0.22 * (1 - shadow_air * 0.6))

	draw_scarf()

	var flash: bool = hurt_t > 0 and int(hurt_t * 34) % 2 == 0
	var body_fill: Color = ink.RED if flash else ink.CREAM
	var alpha: float = 1.0
	if iframes > 0.0 and hurt_t <= 0.0 and not dash_active:
		alpha = 0.55 if int(t * 22) % 2 == 0 else 1.0

	ink.save()
	ink.t_translate(cx(), y + h)

	var sy: float = clampf(squash, 0.8, 1.12)
	var sx: float = 2 - sy
	ink.t_scale(float(facing) * sx, sy)

	var moving: bool = grounded and absf(vx) > 20.0
	var walk: float = sin(run_phase) if moving else 0.0
	var air := not grounded
	var bob: float = absf(sin(run_phase)) * 1.2 if moving else sin(t * 2.2) * 0.7

	# ноги
	var leg_y := -14.0
	var leg_swing: float = walk * 4.5
	var foot_a: float = -7.0 if air else -5.0 + leg_swing
	var foot_b: float = 4.0 if air else 5.0 - leg_swing
	var knee_a: float = -10.0 if air else -7.0 + leg_swing * 0.5
	var knee_b: float = -5.0 if air else -6.0 - leg_swing * 0.5
	ink.poly([Vector2(-3, leg_y), Vector2(knee_a, -7), Vector2(foot_a, -1)], 3.4, ink.INK, 1.0, 0.5)
	ink.poly([Vector2(3, leg_y), Vector2(knee_b, -7), Vector2(foot_b, -1)], 3.4, ink.INK, 1.0, 0.5)
	ink.line(foot_a - 2, -1, foot_a + 3, -1, 2.6, ink.INK, 1.0, 0.3)
	ink.line(foot_b - 2, -1, foot_b + 3, -1, 2.6, ink.INK, 1.0, 0.3)

	# плащ
	var sway: float = clampf(-vx * 0.012, -3.2, 3.2)
	var flap: float = sin(t * 4.2) * 1.3
	var cloak := [
		Vector2(-11, -32 - bob), Vector2(8, -33 - bob), Vector2(12, -25),
		Vector2(13 + sway * 0.2, -15 + sway * 0.4), Vector2(12, -8 + flap * 0.4),
		Vector2(8, -3), Vector2(6, -7 + flap), Vector2(3, -4),
		Vector2(-1, -8), Vector2(-5, -4), Vector2(-8, -8), Vector2(-12, -9),
		Vector2(-13, -19 + sway * 0.3)
	]
	ink.srand(900)
	ink.fill_poly(cloak, body_fill, 1.0, 0.9)
	ink.poly(cloak, 2.2, ink.INK, 1.0, 0.9, true)

	ink.poly([Vector2(-7, -29), Vector2(-8, -20), Vector2(-6, -12)], 1.2, ink.rgba(23, 19, 15, 89), 1.0, 0.6)
	ink.poly([Vector2(3, -30), Vector2(1, -20), Vector2(4, -12)], 1.1, ink.rgba(23, 19, 15, 64), 1.0, 0.6)
	ink.poly([Vector2(9, -27), Vector2(10, -19)], 1.0, ink.rgba(23, 19, 15, 51), 1.0, 0.5)

	# пояс
	ink.poly([Vector2(-10, -20), Vector2(11, -21)], 3.2, ink.RED, 1.0, 0.4)
	ink.blob(9, -20.5, 2.6, ink.RED, ink.INK, 1.0, 1.0, 0.4)
	var sash_sway: float = clampf(-vx * 0.02, -5, 5)
	ink.poly([
		Vector2(10, -19), Vector2(12 + sash_sway * 0.5, -13),
		Vector2(10 + sash_sway, -8)
	], 2.2, ink.RED, 1.0, 0.6)

	# рука и кисть-клинок
	var ang2: float = blade_angle()
	var hx := 8.5
	var hy: float = -24 - bob
	var dx: float = cos(ang2)
	var dy: float = sin(ang2)
	ink.poly([Vector2(6, -29 - bob), Vector2(hx - 1, hy)], 3.6, ink.INK, 1.0, 0.5)

	var bx: float = hx + dx * 13
	var by: float = hy + dy * 13
	var ex: float = hx + dx * 37
	var ey: float = hy + dy * 37
	ink.line(hx, hy, bx, by, 3.8, ink.INK, 1.0, 0.4)
	ink.line(hx + dx * 4, hy + dy * 4, bx, by, 1.3, ink.RED, 1.0, 0.3)
	var nx := -dy
	var ny := dx
	var bristle := [
		Vector2(bx + nx * 5.4, by + ny * 5.4),
		Vector2(ex + nx * 1.1, ey + ny * 1.1),
		Vector2(ex - nx * 1.1, ey - ny * 1.1),
		Vector2(bx - nx * 5.4, by - ny * 5.4)
	]
	ink.fill_poly(bristle, ink.RED_DARK if (attack != null and attack.step == 3) else ink.INK, 1.0, 0.6)
	ink.poly(bristle, 1.0, ink.INK, 1.0, 0.5, true)
	ink.line(bx + nx * 3, by + ny * 3, bx - nx * 3, by - ny * 3, 2.8, ink.RED, 1.0, 0.3)

	# голова
	var hb := bob
	var head := [
		Vector2(-9, -35 - hb), Vector2(-8, -44 - hb), Vector2(-2, -49 - hb),
		Vector2(5, -49 - hb), Vector2(11, -44 - hb), Vector2(12, -36 - hb),
		Vector2(8, -31 - hb), Vector2(-3, -31 - hb)
	]
	ink.srand(901)
	ink.fill_poly(head, body_fill, 1.0, 0.7)
	ink.poly(head, 2.2, ink.INK, 1.0, 0.7, true)

	var ear_w: float = sin(t * 3.1) * 1.4
	ink.poly([Vector2(-2, -47 - hb), Vector2(-5 + ear_w, -55 - hb), Vector2(-8 + ear_w, -61 - hb)], 2.8, ink.INK, 1.0, 0.5)
	ink.poly([Vector2(8, -47 - hb), Vector2(11 - ear_w, -54 - hb), Vector2(14 - ear_w, -59 - hb)], 2.8, ink.INK, 1.0, 0.5)
	ink.poly([Vector2(-6 + ear_w, -56 - hb), Vector2(-8 + ear_w, -61 - hb)], 1.2, ink.RED, 1.0, 0.4)
	ink.poly([Vector2(12 - ear_w, -54 - hb), Vector2(14 - ear_w, -59 - hb)], 1.2, ink.RED, 1.0, 0.4)

	var blink: bool = blink_t < 0 or healing
	if blink:
		ink.line(2, -39 - hb, 7, -39 - hb, 1.6, ink.INK, 1.0, 0.3)
		ink.line(8, -38 - hb, 11, -38 - hb, 1.5, ink.INK, 1.0, 0.3)
	else:
		ink.blob(5, -39.5 - hb, 2.4, ink.GOLD if healing else ink.RED_BRIGHT, null, 2.0, 1.0, 0.3, 10, 0.13, false)
		ink.blob(10, -39 - hb, 1.9, ink.GOLD if healing else ink.RED_BRIGHT, null, 2.0, 1.0, 0.3, 10, 0.13, false)
		ink.line(5.6, -41.8 - hb, 5.6, -41.8 - hb, 1.0, ink.CREAM, 0.85, 0.2)

	ink.poly([Vector2(-3, -32 - hb), Vector2(1, -30 - hb)], 1.2, ink.rgba(23, 19, 15, 102), 1.0, 0.4)

	ink.restore()

	# аура лечения
	if healing:
		var k2: float = clampf(heal_t / HEAL_TIME, 0.0, 1.0)
		var pulse2: float = 0.6 + sin(t * 12) * 0.2
		ink.save()
		ink.alpha_push(0.75)
		ink.circle(cx(), cy(), 34 + sin(t * 6) * 2, null, ink.GOLD, 1.4, 1.0, 0.7, 16)
		ink.arc(cx(), cy(), 27, -PI / 2, -PI / 2 + InkR.TAU * k2, 3.4, ink.RED, pulse2, 0.6)
		for i in range(3):
			var a3: float = t * 1.8 + float(i) / 3.0 * InkR.TAU
			var r3: float = 40.0 - fmod(t * 20 + i * 8, 30)
			ink.blob(cx() + cos(a3) * r3, cy() + sin(a3) * r3, 2.2, ink.INK, null, 2.0, 1.0, 0.5, 10, 0.13, false)
		ink.alpha_pop()
		ink.restore()

		if heal_t > HEAL_TIME - 0.1:
			ink.fill_circle_color(cx(), cy(), 45, ink.CREAM, 0.25)

func draw_scarf() -> void:
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
	var fill_col: Color = ink.rgba(150, 30, 37, 240)
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
