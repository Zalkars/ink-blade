class_name Blot
extends CharacterBody2D

## Клякса: прыгает к игроку и при смерти делится на двух малых.
## Малые кляксы уже не делятся: поколение хранится в самой сцене.
## Настройки приходят из карточки EntityDef.

signal died(blot: Blot)
signal split(pos: Vector2, def_id: StringName)

const GRAVITY := 1900.0
const MAX_FALL := 950.0
const HOP_VELOCITY := 430.0
const HOP_INTERVAL := 0.8
const TOUCH_RANGE := Vector2(34.0, 36.0)
const TOUCH_COOLDOWN := 0.8
const KNOCKBACK := 380.0
const HURT_TIME := 0.14

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const BONE := Color("#d9cdb8")

var max_hp := 3
var speed := 150.0
var chase_range := 520.0
var touch_damage := 1
## 0 — делится при смерти, 1 — уже нет.
var generation := 0
## Призванная боссом клякса не делится, даже оставаясь первым поколением:
## иначе один призыв превращался бы в трёх врагов.
var splits := true

var hp := 3
var target: Player
var dead := false

var hit_t := 0.0
var touch_cd := 0.0
var hop_t := 0.0
var _wob := 0.0


func configure(def: EntityDef, overrides: Dictionary = {}) -> void:
	if def == null:
		return
	var st := def.stats
	if st != null:
		max_hp = maxi(1, st.max_hp)
		touch_damage = maxi(0, st.damage)
		speed = st.speed
		chase_range = st.aggression_radius
	for key in overrides:
		var field := String(key)
		if not def.allows_override(field):
			push_warning("blot: поле %s не разрешено в карточке %s" % [field, def.id])
			continue
		match field:
			"max_hp":
				max_hp = maxi(1, int(overrides[key]))
			"damage":
				touch_damage = maxi(0, int(overrides[key]))
			"speed":
				speed = float(overrides[key])
			"generation":
				generation = int(overrides[key])
			"splits":
				splits = bool(overrides[key])
	hp = max_hp
	if generation > 0:
		scale = Vector2(0.72, 0.72)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var par := get_parent()
	if par is Level and par.is_frozen():
		return
	if dead:
		return
	_wob += delta
	hit_t = maxf(0.0, hit_t - delta)
	touch_cd = maxf(0.0, touch_cd - delta)
	hop_t = maxf(0.0, hop_t - delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if hop_t <= 0.0 and target != null and not target.dead \
			and target.global_position.distance_to(global_position) < chase_range:
			hop_t = HOP_INTERVAL
			var dx := target.global_position.x - global_position.x
			velocity.x = signf(dx) * speed
			velocity.y = -HOP_VELOCITY

	if target != null and not target.dead:
		var dx := target.global_position.x - global_position.x
		if absf(dx) < TOUCH_RANGE.x and absf(target.global_position.y - global_position.y) < TOUCH_RANGE.y:
			_touch_player(dx)

	var was_airborne := not is_on_floor()
	Level.move_ground_enemy(self)
	if was_airborne and is_on_floor():
		CombatFx.floor_mark(self, global_position, 0.65 if generation > 0 else 0.9)
	queue_redraw()


func _touch_player(dx: float) -> void:
	if touch_cd > 0.0 or target == null:
		return
	touch_cd = TOUCH_COOLDOWN
	target.take_damage(touch_damage, 1.0 if dx >= 0.0 else -1.0)


func hit(damage: int, from_dir: int, knock: float = KNOCKBACK) -> void:
	if dead:
		return
	hp -= damage
	InkFx.text_fx(global_position.x, global_position.y - 30, "-%d" % damage, 20, InkR.RED, false)
	InkFx.ink_burst(global_position.x, global_position.y, 9, 150, [InkR.INK, InkR.RED], 4, false, null, 0, 0, 1000, global_position.y + 25)
	hit_t = HURT_TIME
	velocity.x = from_dir * knock
	velocity.y = -180.0
	if hp <= 0:
		InkFx.ink_burst(global_position.x, global_position.y, 22, 260, null, 6, true, null, 0, 0, 1000, global_position.y + 25)
		dead = true
		# Сначала просим уровень создать детей, потом сообщаем о смерти:
		# иначе «зал очищен» сработает раньше, чем появятся малые кляксы.
		if splits and generation == 0:
			split.emit(global_position, &"enemy.blot_small")
		died.emit(self)
		queue_free()


func _draw() -> void:
	# The chapter spans 14,080 px; distant actors need no ink draw commands.
	if not get_viewport_rect().grow(120.0).has_point(get_global_transform_with_canvas().origin):
		return
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_wob)
	var sy := 1.0
	if is_on_floor() and hop_t < 0.2:
		sy = 0.75 + hop_t * 1.25
	elif not is_on_floor():
		sy = 1.0 + clampf(-velocity.y / 1200.0, -0.15, 0.3)
	InkR.save()
	InkR.t_translate(0, 20)
	InkR.t_scale(2.0 - sy, sy)
	InkR.t_translate(0, -20)
	var fill := InkR.RED if hit_t > 0.0 else InkR.CREAM
	InkR.srand(650)
	InkR.blob(0, 1, 18, fill, InkR.INK, 2.4, 1.0, 1.0, 12, 0.16)
	InkR.hatch(InkR.circle_pts(0, 1, 16, 12), 8, 0.12)
	# Wet fringe and pale paper glints give the body volume without changing its collider.
	for rim in 5:
		var rx := -15.0 + float(rim) * 7.5
		var ry := 9.0 + sin(_wob * 4.0 + float(rim) * 1.7) * 2.5
		InkR.poly([Vector2(rx, ry), Vector2(rx + sin(_wob * 3.0 + rim) * 3.0, ry + 7.0)],
			2.6, InkR.INK, 0.8, 0.4)
	InkR.poly([Vector2(-11, -5), Vector2(-8, -10), Vector2(-2, -12)],
		2.2, InkR.PAPER_LIGHT, 0.8, 0.3)
	InkR.blob(-12, 1, 1.8, InkR.PAPER_LIGHT, null, 1.0, 0.7, 0.2, 7, 0.1, false)
	for i in 2:
		var x := -6.0 + i * 12.0
		InkR.blob(x, -4, 4.0, InkR.CREAM, InkR.INK, 1.3)
		InkR.blob(x + 1, -4, 2.0, InkR.RED, null)
	InkR.poly([Vector2(-5, 6), Vector2(0, 8), Vector2(6, 5)],
		1.6, InkR.INK, 1.0, 0.4)
	for i in 3:
		var x := -12.0 + i * 11.0
		InkR.poly([Vector2(x, 13), Vector2(x + sin(_wob * 4 + i) * 3, 20)],
			2.2, InkR.INK, 0.7, 0.5)

	InkR.restore()
