class_name Keeper
extends CharacterBody2D

## Хранитель Первого Взмаха — босс финальной арены.
## Большая фигура из перечёркнутых имён. Пока красная печать на груди закрыта,
## удары не снимают здоровье: печать открывается после тяжёлого удара сверху.
## Тяжёлая кисть ломает печать быстрее клинка, потому что бьёт сильнее.
##
## Фаза 1: волна по полу, удар сверху, призыв двух клякс.
## Фаза 2: волна в обе стороны, дождь чернил, короче замах и длиннее окно.

signal died(keeper: Keeper)
signal summon(pos: Vector2, def_id: StringName, count: int)
signal phase_changed(phase: int)

enum State { DORMANT, STALK, WINDUP_SWEEP, WINDUP_SLAM, SUMMON, RECOVER, STAGGER, DEAD }

const WAVE_SCENE := preload("res://scenes/actors/ink_wave.tscn")
const DROP_SCENE := preload("res://scenes/actors/ink_drop.tscn")

const GRAVITY := 1900.0
const MAX_FALL := 950.0
const SEAL_TIME := 1.3
const TOUCH_RANGE := Vector2(58.0, 76.0)
const TOUCH_COOLDOWN := 0.9
const KNOCKBACK := 60.0
const HURT_TIME := 0.12

const INK := Color("#17130f")
const INK_SOFT := Color("#4a3c2e")
const RED := Color("#9c1f24")
const RED_BRIGHT := Color("#c9353a")
const RED_DARK := Color("#651419")
const BONE := Color("#d9cdb8")
const PAPER := Color("#f1e6d0")

var max_hp := 40
var damage := 1
var speed := 70.0
var engage_range := 620.0
var windup := 0.55

var hp := 40
var phase := 1
var state := State.DORMANT
var engaged := false
var dead := false
var target: Player

var facing := -1
var state_t := 0.0
var attack_cd := 0.0
var summon_cd := 12.0
var rain_t := 2.0
var seal_open := false
var seal_t := 0.0
var hit_t := 0.0
var clang_t := 0.0
var touch_cd := 0.0
var slam_x := 0.0
var _t := 0.0
var _next_sweep := true

var min_x := 0.0
var max_x := 100000.0


## Заполняет параметры из карточки контента и применяет переопределения уровня.
func configure(def: EntityDef, overrides: Dictionary = {}) -> void:
	if def == null:
		return
	var st := def.stats
	if st != null:
		max_hp = maxi(1, st.max_hp)
		damage = maxi(0, st.damage)
		speed = st.speed
		engage_range = st.aggression_radius
		windup = st.telegraph_time
	for key in overrides:
		var field := String(key)
		if not def.allows_override(field):
			push_warning("keeper: поле %s не разрешено в карточке %s" % [field, def.id])
			continue
		match field:
			"max_hp":
				max_hp = maxi(1, int(overrides[key]))
			"damage":
				damage = maxi(0, int(overrides[key]))
			"speed":
				speed = float(overrides[key])
	hp = max_hp
	queue_redraw()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	# Арену берём из границ уровня, а не из константы: босс не уходит
	# в соседние зоны и не вываливается за край.
	var lvl := get_parent()
	if lvl is Level:
		min_x = lvl.bounds.position.x + 300.0
		max_x = lvl.bounds.end.x - 240.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	hit_t = maxf(0.0, hit_t - delta)
	clang_t = maxf(0.0, clang_t - delta)
	touch_cd = maxf(0.0, touch_cd - delta)
	summon_cd = maxf(0.0, summon_cd - delta)
	if seal_open:
		seal_t = maxf(0.0, seal_t - delta)
		if seal_t <= 0.0:
			seal_open = false

	if target == null or not is_instance_valid(target) or target.dead:
		_apply_gravity(delta)
		move_and_slide()
		queue_redraw()
		return

	if not engaged:
		if global_position.distance_to(target.global_position) <= engage_range:
			engaged = true
			state = State.STALK
			attack_cd = 0.9
			summon_cd = 12.0
		_apply_gravity(delta)
		move_and_slide()
		queue_redraw()
		return

	if phase == 2:
		rain_t -= delta
		if rain_t <= 0.0:
			rain_t = 2.6
			_rain()

	match state:
		State.STALK:
			_tick_stalk(delta)
		State.WINDUP_SWEEP:
			_stop(delta)
			state_t -= delta
			if state_t <= 0.0:
				_sweep()
				state = State.RECOVER
				state_t = 1.25 if phase == 2 else 0.9
		State.WINDUP_SLAM:
			_stop(delta)
			state_t -= delta
			if state_t <= 0.0:
				_slam()
				state = State.RECOVER
				state_t = 1.25 if phase == 2 else 0.9
		State.SUMMON:
			_stop(delta)
			state_t -= delta
			if state_t <= 0.0:
				_summon()
				state = State.RECOVER
				state_t = 0.8
		State.RECOVER:
			_stop(delta)
			state_t -= delta
			if state_t <= 0.0:
				state = State.STALK
				attack_cd = 0.35 if phase == 2 else 0.6
		State.STAGGER:
			_stop(delta)
			state_t -= delta
			if state_t <= 0.0:
				phase = 2
				state = State.STALK
				attack_cd = 0.35
				rain_t = 0.8
				phase_changed.emit(2)
		_:
			_stop(delta)

	if absf(target.global_position.x - global_position.x) < TOUCH_RANGE.x \
		and absf(target.global_position.y - global_position.y) < TOUCH_RANGE.y:
		_touch_player(target.global_position.x - global_position.x)

	_apply_gravity(delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, min_x, max_x)
	queue_redraw()


func _tick_stalk(delta: float) -> void:
	var dx := target.global_position.x - global_position.x
	if absf(dx) > 12.0:
		facing = 1 if dx > 0.0 else -1
	var want := 0.0
	if absf(dx) > 108.0:
		want = signf(dx) * speed
	velocity.x = move_toward(velocity.x, want, 600.0 * delta)

	attack_cd -= delta
	if attack_cd > 0.0:
		return
	if phase == 1 and summon_cd <= 0.0:
		summon_cd = 12.0
		state = State.SUMMON
		state_t = 0.7
		return
	if _next_sweep:
		_next_sweep = false
		state = State.WINDUP_SWEEP
		state_t = windup if phase == 1 else windup * 0.62
	else:
		_next_sweep = true
		slam_x = clampf(target.global_position.x, min_x, max_x)
		state = State.WINDUP_SLAM
		state_t = windup if phase == 1 else windup * 0.62


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)


func _touch_player(dx: float) -> void:
	if touch_cd > 0.0:
		return
	touch_cd = TOUCH_COOLDOWN
	target.take_damage(damage, 1.0 if dx >= 0.0 else -1.0)


## Открывает печать на время. Вызывается тяжёлым ударом, но доступно и тестам.
func open_seal(duration := SEAL_TIME) -> void:
	seal_open = true
	seal_t = duration
	queue_redraw()


func _sweep() -> void:
	var dir := 1.0 if target.global_position.x >= global_position.x else -1.0
	_spawn_wave(dir)
	if phase == 2:
		_spawn_wave(-dir)


func _spawn_wave(dir: float) -> void:
	var wave := WAVE_SCENE.instantiate()
	wave.global_position = global_position + Vector2(dir * 40.0, 10.0)
	wave.velocity = Vector2(dir * InkWave.SPEED, 0.0)
	wave.damage = damage
	get_parent().add_child(wave)


func _slam() -> void:
	var drop := DROP_SCENE.instantiate()
	drop.global_position = Vector2(slam_x, -20.0)
	drop.damage = damage
	drop.floor_y = global_position.y
	# Печать открывается, когда тяжёлый удар действительно дошёл до пола,
	# а не в момент замаха: у игрока есть время подойти.
	drop.landed.connect(_on_drop_landed)
	get_parent().add_child(drop)


## Капля от удара сверху дошла до пола: открываем печать.
func _on_drop_landed() -> void:
	if not dead:
		open_seal()


func _summon() -> void:
	summon.emit(global_position + Vector2(-96.0, 20.0), &"enemy.blot", 1)
	summon.emit(global_position + Vector2(96.0, 20.0), &"enemy.blot", 1)


func _rain() -> void:
	var drop := DROP_SCENE.instantiate()
	var x := clampf(target.global_position.x + randf_range(-140.0, 140.0), min_x, max_x)
	drop.global_position = Vector2(x, -20.0)
	drop.damage = damage
	drop.floor_y = global_position.y
	get_parent().add_child(drop)


## Печать принимает урон только открытой. Тяжёлый удар (кисть) ломает её быстрее.
func hit(amount: int, from_dir: int, knock: float = KNOCKBACK) -> void:
	if dead:
		return
	if not seal_open:
		clang_t = 0.2
		velocity.x = -from_dir * 24.0
		return
	var dealt := amount + (1 if amount >= 3 else 0)
	hp -= dealt
	hit_t = HURT_TIME
	velocity.x = -from_dir * knock
	if hp <= 0:
		_die()
		return
	if phase == 1 and hp <= max_hp / 2:
		state = State.STAGGER
		state_t = 1.1
		seal_open = false
		seal_t = 0.0


func _die() -> void:
	dead = true
	state = State.DEAD
	seal_open = false
	died.emit(self)
	queue_free()


func _draw() -> void:
	var flash := hit_t > 0.0
	var ink := BONE if flash else INK
	var sway := sin(_t * 1.4) * 2.0

	# Тень и ряса из перечёркнутых строк.
	draw_circle(Vector2(0.0, 20.0), 36.0, Color(INK, 0.14))
	var robe := PackedVector2Array([
		Vector2(-34.0, 20.0),
		Vector2(-24.0 + sway, -22.0),
		Vector2(-18.0, -58.0),
		Vector2(18.0, -58.0),
		Vector2(24.0 + sway, -22.0),
		Vector2(34.0, 20.0),
	])
	draw_colored_polygon(robe, ink)
	for i in 4:
		var y := 8.0 - i * 18.0
		draw_line(Vector2(-26.0 + sway * 0.4, y), Vector2(26.0 + sway * 0.4, y - 2.0),
			Color(PAPER, 0.16), 1.2)

	# Плечи и руки. Правая рука держит кисть и двигается на замахе.
	var arm_dir := float(facing)
	draw_line(Vector2(-16.0, -52.0), Vector2(-40.0, -22.0), Color(ink, 0.92), 9.0)
	var brush_len := 46.0
	if state == State.WINDUP_SWEEP:
		brush_len = 62.0
	elif state == State.WINDUP_SLAM:
		brush_len = 34.0
	draw_line(Vector2(16.0, -52.0), Vector2(16.0 + arm_dir * 20.0, -52.0 + brush_len * 0.4),
		Color(ink, 0.92), 9.0)
	draw_line(Vector2(16.0 + arm_dir * 20.0, -52.0 + brush_len * 0.4),
		Vector2(16.0 + arm_dir * 34.0, -52.0 + brush_len),
		Color(INK_SOFT, 0.95), 4.0)
	draw_circle(Vector2(16.0 + arm_dir * 34.0, -52.0 + brush_len), 5.0, RED)

	# Голова и зачёркнутое имя вместо лица.
	draw_circle(Vector2(sway * 0.5, -74.0), 17.0, ink)
	draw_line(Vector2(-13.0, -76.0), Vector2(13.0, -72.0), RED, 3.0)
	draw_circle(Vector2(-5.0, -80.0), 2.0, Color(RED_BRIGHT, 0.8))
	draw_circle(Vector2(6.0, -79.0), 2.0, Color(RED_BRIGHT, 0.8))

	# Печать на груди: закрытая — тёмная, открытая — яркая и с кольцом.
	var seal := Vector2(0.0, -40.0)
	draw_circle(seal, 17.0, Color(PAPER, 0.92))
	draw_circle(seal, 14.0, RED_BRIGHT if seal_open else RED_DARK)
	draw_line(seal + Vector2(-8.0, 0.0), seal + Vector2(8.0, 0.0), Color(PAPER, 0.9), 2.0)
	draw_line(seal + Vector2(0.0, -8.0), seal + Vector2(0.0, 8.0), Color(PAPER, 0.9), 2.0)
	if seal_open:
		var pulse := 20.0 + sin(_t * 9.0) * 3.0
		draw_arc(seal, pulse, 0.0, TAU, 28, Color(RED, 0.75), 2.0)
		draw_arc(seal, pulse + 6.0, 0.0, TAU, 28, Color(RED, 0.3), 1.0)
	elif clang_t > 0.0:
		draw_arc(seal, 20.0, 0.0, TAU, 20, Color(BONE, clang_t / 0.2), 2.0)

	# Фаза 2: по фигуре идут трещины, как по порванной странице.
	if phase == 2:
		draw_line(Vector2(-20.0, -54.0), Vector2(-8.0, -20.0), Color(RED, 0.55), 2.0)
		draw_line(Vector2(-8.0, -20.0), Vector2(-18.0, 12.0), Color(RED, 0.55), 2.0)
		draw_line(Vector2(22.0, -48.0), Vector2(10.0, -8.0), Color(RED, 0.4), 1.5)

	# Телеграфы: линия по полу перед волной и столб перед ударом сверху.
	if state == State.WINDUP_SWEEP:
		var a := 0.35 + 0.35 * (1.0 - clampf(state_t / maxf(windup, 0.01), 0.0, 1.0))
		draw_line(Vector2(-120.0, 20.0), Vector2(120.0, 20.0), Color(RED, a), 4.0)
	elif state == State.WINDUP_SLAM:
		var lx := slam_x - global_position.x
		draw_line(Vector2(lx, -540.0), Vector2(lx, 20.0), Color(RED, 0.45), 2.0)
		draw_line(Vector2(lx - 10.0, 20.0), Vector2(lx + 10.0, 20.0), Color(RED, 0.7), 3.0)
