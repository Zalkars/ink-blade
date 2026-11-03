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

var weapons: Array = []
var weapon_index := 0
var weapon: WeaponDef

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

	if ax != 0.0:
		facing = 1 if ax > 0.0 else -1

	_apply_gravity(delta)
	_apply_run(ax, delta)

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
	if dash_cd > 0.0:
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
	if attack_cd > 0.0 or weapon == null:
		return
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
			body.hit(weapon.damage, facing, weapon.knockback)


func take_damage(amount: int, from_dir: float) -> void:
	if dead or iframes > 0.0:
		return
	hp = maxi(0, hp - amount)
	iframes = HURT_INVULN
	hurt_t = 0.18
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
	hp_changed.emit(hp, MAX_HP)


func dash_ready() -> float:
	if DASH_COOLDOWN <= 0.0:
		return 1.0
	return clampf(1.0 - dash_cd / DASH_COOLDOWN, 0.0, 1.0)


func _draw() -> void:
	var ink := INK
	if iframes > 0.0 and int(iframes * 24.0) % 2 == 0:
		ink = BONE
	if dead:
		ink = Color(INK, 0.55)

	var sway := sin(_wob * 2.4) * 1.4
	var pts := PackedVector2Array([
		Vector2(-7.0, -23.0),
		Vector2(6.0, -22.0),
		Vector2(11.0 + sway * 0.4, 0.0),
		Vector2(9.0, 23.0),
		Vector2(-9.0, 23.0),
		Vector2(-11.0 + sway * 0.4, 0.0),
	])
	draw_colored_polygon(pts, ink)

	if not dead:
		draw_circle(Vector2(3.5 * facing, -9.0), 2.4, RED)

	if attack_t > 0.0 and weapon != null:
		var k := 1.0 - attack_t / maxf(attack_total, 0.001)
		var a0 := -0.9 + k * 0.9
		var a1 := 0.7 + k * 0.5
		var r: float = weapon.swing_radius
		var col: Color = weapon.ink
		if facing > 0:
			draw_arc(Vector2(2.0, -4.0), r, a0, a1, 14, col, weapon.swing_width)
		else:
			draw_arc(Vector2(-2.0, -4.0), r, PI - a1, PI - a0, 14, col, weapon.swing_width)
