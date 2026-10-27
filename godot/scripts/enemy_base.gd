class_name InkEnemy
extends RefCounted

## Полный порт Game/Enemy.cs — базовый класс EnemyBase

static var _next_id := 1

var g = null
var type := "enemy"
var id := ""
var hp := 1.0
var max_hp := 1.0
var spawn_x := 0.0
var spawn_y := 0.0
var facing := -1
var t := 0.0
var hurt_t := 0.0
var pip_t := 0.0
var dead := false
var respawn_t := 0.0
var contact := true
var hover := false
var state := "idle"
var state_t := 0.0
var touch_cd := 0.0

# Body
var x := 0.0
var y := 0.0
var w := 20.0
var h := 20.0
var vx := 0.0
var vy := 0.0
var grounded := false
var on_one_way := false
var hit_wall := false
var drop_t := 0.0

func _init(game, type_: String, X: float, Y: float, W_: float, H_: float, hp_: float) -> void:
	g = game
	type = type_
	id = "e%d" % InkEnemy._next_id
	InkEnemy._next_id += 1
	x = X
	y = Y
	w = W_
	h = H_
	hp = hp_
	max_hp = hp_
	spawn_x = X
	spawn_y = Y

func cx() -> float:
	return x + w * 0.5

func cy() -> float:
	return y + h * 0.5

func hitbox() -> Rect2:
	return Rect2(x + 3, y + 3, w - 6, h - 5)

func set_state(s: String, dur: float) -> void:
	state = s
	state_t = dur

func update(dt: float) -> void:
	t += dt
	hurt_t = maxf(0.0, hurt_t - dt)
	pip_t = maxf(0.0, pip_t - dt)
	touch_cd = maxf(0.0, touch_cd - dt)

	if dead:
		respawn_t -= dt
		if respawn_t <= 0.0:
			respawn()
		return

	behavior(dt)
	physics(dt)

func behavior(_dt: float) -> void:
	pass

func _draw() -> void:
	pass

func physics(dt: float, gravity := 2400.0) -> void:
	if not hover:
		vy = minf(vy + gravity * dt, 1100.0)
		InkWorld.move_x(self, dt)
		InkWorld.move_y(self, dt)

func hurt(dmg: float, dir_x: float, heavy: bool) -> void:
	if dead:
		return
	hp -= dmg
	hurt_t = 0.2
	pip_t = 2.2
	vx = dir_x * (120.0 if hover else 210.0)
	if not hover:
		vy = -150.0
	InkFx.text_fx(cx(), y - 6, "%d" % int(dmg), 30 if dmg > 1 else 23,
		InkR.RED_BRIGHT if dmg > 1 else InkR.RED, false, 0.75)
	InkFx.ink_burst(cx(), cy(), 7, 230.0, null, 4.0, true)
	InkFx.sparks(cx(), cy(), 0.0 if dir_x > 0 else PI, 6)
	SND.hit(dmg > 1)
	InkFx.add_shake(7.0 if dmg > 1 else 3.5)
	g.freeze(0.075 if dmg > 1 else 0.045)
	g.add_combo()
	CTL.rumble(0.25, 0.5, 90)

	if hp <= 0:
		die()

func die() -> void:
	dead = true
	respawn_t = 3.6
	InkFx.ink_burst(cx(), cy(), 26, 380.0, [InkR.INK, InkR.INK, InkR.RED_DARK, InkR.INK_SOFT], 6.0, true)
	InkFx.ring(cx(), cy(), 6, 90, InkR.INK_SOFT, 0.45, 3)
	SND.kill()
	InkFx.add_shake(8.0)
	g.freeze(0.06)
	g.on_enemy_killed(self)

func respawn() -> void:
	dead = false
	hp = max_hp
	x = spawn_x
	y = spawn_y
	vx = 0.0
	vy = 0.0
	facing = -1
	hurt_t = 0.0
	pip_t = 0.0
	state = "patrol"
	state_t = 0.6
	InkFx.ring(cx(), cy(), 4, 56, InkR.INK_SOFT, 0.5, 2)
	InkFx.ink_burst(cx(), cy(), 12, 120.0, [InkR.INK, InkR.INK_SOFT], 4.0,
		false, null, 0.0, 0.0, -120.0, 9999.0)
	SND.spawn()

func draw_pips() -> void:
	var ink := InkR
	if dead or hp >= max_hp or max_hp >= 90:
		return
	var alpha: float = minf(0.7, pip_t)
	for i in range(int(max_hp)):
		var px: float = cx() + (float(i) - (max_hp - 1.0) / 2.0) * 9.0
		var py: float = y - 10.0
		if float(i) < hp:
			ink.circle(px, py, 2.6, ink.RED, null, 2.0, alpha, 0.3, 6, false)
		else:
			ink.circle(px, py, 2.2, null, ink.INK, 1.0, alpha * 0.5, 0.3, 6)
