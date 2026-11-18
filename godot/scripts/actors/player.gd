class_name Player
extends CharacterBody2D

## Игрок новой основы. CharacterBody2D + один таймлайн в _physics_process.
## Цифры — первый проход по docs/baseline/2026-10-28/feel.md:
##   падение медленнее (гравитация -25%, максимальная скорость падения -20%),
##   прыжок выше примерно на 12% при более долгом полёте,
##   рывок длиннее на 12%, у атаки появился кулдаун.
## Всё это замеряется на новом контроллере и правится по ощущениям.

signal hp_changed(hp: int, max_hp: int)
signal died
signal weapon_changed(name: String)

const MAX_HP := 5

const RUN_SPEED := 300.0
const ACC_GROUND := 3300.0
const DEC_GROUND := 3900.0
const ACC_AIR := 2200.0
const DEC_AIR := 1050.0

const GRAVITY := 1900.0
const MAX_FALL := 950.0
const JUMP_VELOCITY := 735.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.13

const DASH_SPEED := 980.0
const DASH_TIME := 0.15
const DASH_COOLDOWN := 0.34

const ATTACK_TIME := 0.18
const ATTACK_COOLDOWN := 0.08
const ATTACK_DAMAGE := 1
const ATTACK_REACH := Vector2(52, 44)

const HURT_INVULN := 0.9
const HURT_KNOCKBACK := Vector2(320.0, -260.0)

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const BONE := Color("#d9cdb8")

# Слой столкновений врагов: по нему бьёт атака игрока.
const ENEMY_LAYER := 4

var hp := MAX_HP
var facing := 1
var dead := false

var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := 1.0
var air_dash := true

var coyote := 0.0
var jump_buf := 0.0
var iframes := 0.0
var hurt_t := 0.0
var attack_t := 0.0
var attack_cd := 0.0
var attack_windup := 0.0
var attack_total := ATTACK_TIME
var _struck := false
const HEAL_TIME := 0.8
const HEAL_COST := 40.0
var soul := 0.0
var healing := false
var heal_t := 0.0
var heal_flash := 0.0
var attack_step := 0
var attack_facing := 1

var weapons: Array = []
var weapon_index := 0
var weapon: WeaponDef

var _visual = preload("res://scripts/visuals/player_visual.gd").new(null, -14.0, -23.0)
var _visual_pos := Vector2.INF
var _wob := 0.0
var _spawn := Vector2.ZERO


func _ready() -> void:
	_spawn = global_position
	# На старте открыт только клинок: кисть выдаёт Переписчик.
	var all := WDB.all()
	if not all.is_empty():
		unlock_weapon(String(all[0].id), false)
	hp_changed.emit(hp, MAX_HP)


## Открывает оружие по карточке. Возвращает false, если карточки нет
## или оружие уже открыто — тогда HUD не показывает ложную награду.
func unlock_weapon(id: String, equip := true) -> bool:
	var def := WDB.get_weapon(StringName(id))
	if def == null:
		push_warning("player: нет карточки оружия " + id)
		return false
	for w in weapons:
		if String(w.id) == id:
			return false
	weapons.append(def)
	weapons.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool:
		return a.order < b.order
	)
	if equip or weapon == null:
		_equip(weapons.find(def))
	return true


func has_weapon(id: String) -> bool:
	for w in weapons:
		if String(w.id) == id:
			return true
	return false


func weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for w in weapons:
		out.append(String(w.id))
	return out


func current_weapon_id() -> String:
	return String(weapon.id) if weapon != null else ""


## Восстанавливает открытый набор из сохранения и берёт прежнее оружие.
func restore_weapons(ids: Array, current: String = "") -> void:
	for id in ids:
		unlock_weapon(String(id), false)
	if not current.is_empty() and equip_weapon(current):
		return
	if not weapons.is_empty():
		_equip(0)


func equip_weapon(id: String) -> bool:
	for i in weapons.size():
		if String(weapons[i].id) == id:
			_equip(i)
			return true
	return false


## Берёт оружие по порядку карточек. Если каталог пуст, остаётся встроенный клинок.
func _equip(index: int) -> void:
	if weapons.is_empty():
		return
	weapon_index = wrapi(index, 0, weapons.size())
	weapon = weapons[weapon_index]
	attack_t = 0.0
	attack_windup = 0.0
	attack_cd = 0.0
	_struck = false
	weapon_changed.emit(weapon_name())


func next_weapon() -> void:
	if weapons.size() < 2:
		return
	_equip(weapon_index + 1)


func weapon_name() -> String:
	if weapon == null:
		return ""
	return L10N.t(weapon.display_name_key)


func _physics_process(delta: float) -> void:
	_wob += delta
	heal_flash = maxf(0.0, heal_flash - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	iframes = maxf(0.0, iframes - delta)
	hurt_t = maxf(0.0, hurt_t - delta)
	attack_t = maxf(0.0, attack_t - delta)
	attack_windup = maxf(0.0, attack_windup - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	if attack_t > 0.0 and not _struck and attack_windup <= 0.0:
		_strike()
		_struck = true

	if dead:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, DEC_GROUND * delta)
		move_and_slide()
		queue_redraw()
		return

	coyote = maxf(0.0, coyote - delta)
	jump_buf = maxf(0.0, jump_buf - delta)

	if is_on_floor():
		coyote = COYOTE_TIME
		air_dash = true

	if CTL.pressed("jump"):
		jump_buf = JUMP_BUFFER
	if CTL.pressed("dash"):
		_try_dash()
	if CTL.pressed("attack"):
		_try_attack()
	if CTL.pressed("swap"):
		next_weapon()

	var can_heal := (CTL.down("heal") and is_on_floor() and hp < MAX_HP
		and soul >= HEAL_COST and attack_t <= 0.0 and dash_t <= 0.0
		and hurt_t <= 0.0 and jump_buf <= 0.0)
	if can_heal and not healing:
		SND.heal_loop()
	healing = can_heal
	if healing:
		heal_t += delta
		velocity.x = move_toward(velocity.x, 0.0, DEC_GROUND * delta)
		if heal_t >= HEAL_TIME:
			soul -= HEAL_COST
			hp = mini(MAX_HP, hp + 1)
			heal_t = 0.0
			healing = false
			heal_flash = 0.4
			hp_changed.emit(hp, MAX_HP)
			SND.heal()
			CombatFx.burst(self, global_position, Vector2.UP, InkR.GOLD, 22)
		move_and_slide()
		queue_redraw()
		return
	heal_t = 0.0

	var ax := CTL.axis_x()
	if absf(ax) < 0.2:
		ax = 0.0

	if dash_t > 0.0:
		dash_t -= delta
		velocity.x = dash_dir * DASH_SPEED
		velocity.y = 0.0
		move_and_slide()
		queue_redraw()
		return

	if ax != 0.0 and attack_t <= 0.0 and hurt_t <= 0.0:
		facing = 1 if ax > 0.0 else -1

	_apply_gravity(delta)
	if hurt_t <= 0.0:
		_apply_run(ax * (0.35 if attack_t > 0.0 else 1.0), delta)

	if jump_buf > 0.0 and coyote > 0.0:
		velocity.y = -JUMP_VELOCITY
		jump_buf = 0.0
		coyote = 0.0
		air_dash = true

	move_and_slide()
	queue_redraw()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)


func _apply_run(ax: float, delta: float) -> void:
	var grounded := is_on_floor()
	var accel := ACC_GROUND if grounded else ACC_AIR
	var brake := DEC_GROUND if grounded else DEC_AIR
	if ax == 0.0:
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	else:
		velocity.x = move_toward(velocity.x, ax * RUN_SPEED, accel * delta)


func _try_dash() -> void:
	if dash_cd > 0.0 or hurt_t > 0.0 or attack_t > 0.0 or dead:
		return
	if not is_on_floor() and not air_dash:
		return
	var ax := CTL.axis_x()
	dash_dir = 1.0 if ax > 0.05 else (-1.0 if ax < -0.05 else float(facing))
	facing = int(dash_dir)
	dash_t = DASH_TIME
	dash_cd = DASH_COOLDOWN
	if not is_on_floor():
		air_dash = false


func _try_attack() -> void:
	if attack_cd > 0.0 or weapon == null or hurt_t > 0.0 or dash_t > 0.0 or dead:
		return
	healing = false
	heal_t = 0.0
	attack_step = attack_step % 2 + 1
	attack_facing = facing
	_struck = false
	attack_windup = weapon.windup
	attack_total = weapon.windup + weapon.active
	attack_t = attack_total
	attack_cd = attack_total + weapon.cooldown
	if attack_windup <= 0.0:
		_strike()
		_struck = true


func _strike() -> void:
	if weapon == null:
		return
	SND.slash(attack_step)
	var reach: Vector2 = weapon.reach
	var center := global_position
	if weapon.hit_both_sides:
		# Кисть бьёт вокруг: широкая фигура без смещения вперёд.
		reach = Vector2(weapon.reach.x * 2.0, weapon.reach.y)
	else:
		center += Vector2(weapon.reach.x * 0.5 * facing, 0.0)
	var shape := RectangleShape2D.new()
	shape.size = reach
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = ENEMY_LAYER
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var found := get_world_2d().direct_space_state.intersect_shape(params, 8)
	for hit in found:
		var body = hit.get("collider")
		if body != null and body.has_method("hit"):
			var hp_before := int(body.get("hp"))
			body.hit(weapon.damage, attack_facing, weapon.knockback)
			if int(body.get("hp")) < hp_before:
				soul = minf(99.0, soul + 12.0)
				CombatFx.burst(self, body.global_position, Vector2(attack_facing, -0.35))
				SND.hit(weapon.damage >= 3)
	var start := global_position + Vector2(0, -4)
	var ray := PhysicsRayQueryParameters2D.create(start, start + Vector2(weapon.reach.x * attack_facing, 0), 1)
	var wall := get_world_2d().direct_space_state.intersect_ray(ray)
	if not wall.is_empty():
		CombatFx.burst(self, wall.position, wall.normal, BONE, 8)


func take_damage(amount: int, from_dir: float) -> void:
	if dead or iframes > 0.0 or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	iframes = HURT_INVULN
	hurt_t = 0.28
	attack_t = 0.0
	attack_windup = 0.0
	dash_t = 0.0
	healing = false
	heal_t = 0.0
	SND.hurt()
	CombatFx.burst(self, global_position, Vector2(from_dir, -0.6), RED, 20)
	var away := 1.0 if from_dir == 0.0 else from_dir
	velocity = Vector2(away * HURT_KNOCKBACK.x, HURT_KNOCKBACK.y)
	hp_changed.emit(hp, MAX_HP)
	if hp == 0:
		dead = true
		velocity = Vector2(-facing * 180.0, -220.0)
		died.emit()


func respawn() -> void:
	global_position = _spawn
	velocity = Vector2.ZERO
	hp = MAX_HP
	dead = false
	iframes = 0.0
	dash_t = 0.0
	dash_cd = 0.0
	air_dash = true
	healing = false
	heal_t = 0.0
	heal_flash = 0.0
	attack_t = 0.0
	attack_cd = 0.0
	attack_windup = 0.0
	hurt_t = 0.0
	hp_changed.emit(hp, MAX_HP)


func dash_ready() -> float:
	if DASH_COOLDOWN <= 0.0:
		return 1.0
	return clampf(1.0 - dash_cd / DASH_COOLDOWN, 0.0, 1.0)


func _process(delta: float) -> void:
	# World coordinates keep the scarf trailing while the actor moves.
	_visual.x = global_position.x - 14.0
	_visual.y = global_position.y - 23.0
	_visual.vx = velocity.x
	_visual.vy = velocity.y
	_visual.facing = facing
	_visual.grounded = is_on_floor()
	_visual.dead = dead
	_visual.iframes = iframes
	_visual.hurt_t = hurt_t
	_visual.healing = healing
	_visual.heal_t = heal_t
	_visual.squash = 0.91 if healing else (1.08 if hurt_t > 0.0 else 1.0)
	_visual.dash_active = dash_t > 0.0
	_visual.t += delta
	_visual.run_phase += absf(velocity.x) * delta * 0.085
	_visual.blink_t -= delta
	if _visual.blink_t < -0.12:
		_visual.blink_t = randf_range(2.0, 5.0)
	_visual.attack = null
	if attack_t > 0.0 and weapon != null:
		_visual.attack = {"step": attack_step, "dir": "fwd",
			"t": attack_total - attack_t, "windup": weapon.windup,
			"active": weapon.active}
	elif attack_cd > 0.0 and _struck and weapon != null and hurt_t <= 0.0:
		_visual.attack = {"step": attack_step, "dir": "fwd",
			"t": attack_total + weapon.cooldown - attack_cd,
			"windup": weapon.windup, "active": weapon.active, "recover": weapon.cooldown}
	if _visual_pos == Vector2.INF or _visual_pos.distance_to(global_position) > 200.0:
		_visual.reset_scarf()
	_visual_pos = global_position
	_visual.scarf_acc += delta
	while _visual.scarf_acc >= 1.0 / 60.0:
		_visual.scarf_step()
		_visual.scarf_acc -= 1.0 / 60.0
	var ray := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, 22), global_position + Vector2(0, 720), 1)
	var ground := get_world_2d().direct_space_state.intersect_ray(ray)
	_visual.ground_y = ground.position.y if not ground.is_empty() else 10000.0
	queue_redraw()


func _draw() -> void:
	# The chapter spans 14,080 px; distant actors need no ink draw commands.
	if not get_viewport_rect().grow(120.0).has_point(get_global_transform_with_canvas().origin):
		return
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_visual.t)
	InkR.save()
	InkR.t_translate(-global_position.x, -global_position.y)
	_visual.draw()
	InkR.restore()

	if heal_flash > 0.0:
		draw_arc(Vector2.ZERO, 20.0 + (0.4 - heal_flash) * 75.0, 0, TAU, 40,
			Color(InkR.GOLD, heal_flash * 2.0), 2.5, true)
	# The trail only exists during the active swing; anticipation stays readable.
	if attack_t > 0.0 and weapon != null and attack_windup <= 0.0:
		var k := clampf((attack_total - attack_t - weapon.windup) / maxf(weapon.active, 0.001), 0, 1)
		var sweep := -1.35 + 2.7 * (1.0 - pow(1.0 - k, 3))
		var a0 := sweep - 0.85
		var a1 := sweep
		if attack_step == 2:
			a0 = -sweep
			a1 = -sweep + 0.85
		var opacity := sin(PI * k)
		for i in 3:
			var col := Color(weapon.ink if i < 2 else BONE, opacity * (1.0 - i * 0.23))
			var r := weapon.swing_radius - i * 3.0
			if attack_facing > 0:
				InkR.taper_arc(8.5, -1.0, r, a0, a1, weapon.swing_width + 3 - i, 0.5, col)
			else:
				InkR.taper_arc(-8.5, -1.0, r, PI - a1, PI - a0, weapon.swing_width + 3 - i, 0.5, col)
