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
	hp = max_hp
	if generation > 0:
		scale = Vector2(0.72, 0.72)
	queue_redraw()


func _physics_process(delta: float) -> void:
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

	move_and_slide()
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
	hit_t = HURT_TIME
	velocity.x = -from_dir * knock
	velocity.y = -180.0
	if hp <= 0:
		dead = true
		# Сначала просим уровень создать детей, потом сообщаем о смерти:
		# иначе «зал очищен» сработает раньше, чем появятся малые кляксы.
		if generation == 0:
			split.emit(global_position, &"enemy.blot_small")
		died.emit(self)
		queue_free()


func _draw() -> void:
	var ink := BONE if hit_t > 0.0 else INK
	var wob := sin(_wob * 4.0) * 1.6
	var pts := PackedVector2Array([
		Vector2(-15.0 + wob, -8.0),
		Vector2(-8.0, -17.0),
		Vector2(6.0 + wob, -16.0),
		Vector2(16.0, -4.0),
		Vector2(13.0, 12.0),
		Vector2(2.0, 18.0),
		Vector2(-11.0, 14.0),
		Vector2(-17.0, 2.0),
	])
	draw_colored_polygon(pts, ink)
	draw_circle(Vector2(-5.0, -4.0), 2.2, RED)
	draw_circle(Vector2(5.0, -4.0), 2.2, RED)
	# Капли, стекающие с кляксы.
	draw_circle(Vector2(-12.0, 16.0), 2.5, Color(ink, 0.6))
	draw_circle(Vector2(10.0, 18.0), 1.8, Color(ink, 0.5))
