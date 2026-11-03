class_name Sentry
extends CharacterBody2D

## Часовой: висит в воздухе, подлетает к игроку по горизонтали и стреляет
## чернильными болтами. Не падает и не толкается о геометрию.
## Настройки приходят из карточки EntityDef.

signal died(sentry: Sentry)

const BOLT_SCENE := preload("res://scenes/actors/ink_bolt.tscn")

const HOVER_AMPLITUDE := 14.0
const SHOOT_INTERVAL := 1.7
const HURT_TIME := 0.14
const KNOCKBACK := 220.0

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const BONE := Color("#d9cdb8")

var max_hp := 3
var speed := 120.0
var chase_range := 700.0
var bolt_damage := 1

var hp := 3
var target: Player
var dead := false
var anchor := Vector2.ZERO

var hit_t := 0.0
var shoot_t := 0.6
var _wob := 0.0


func configure(def: EntityDef, overrides: Dictionary = {}) -> void:
	if def == null:
		return
	var st := def.stats
	if st != null:
		max_hp = maxi(1, st.max_hp)
		bolt_damage = maxi(0, st.damage)
		speed = st.speed
		chase_range = st.aggression_radius
	for key in overrides:
		var field := String(key)
		if not def.allows_override(field):
			push_warning("sentry: поле %s не разрешено в карточке %s" % [field, def.id])
			continue
		match field:
			"max_hp":
				max_hp = maxi(1, int(overrides[key]))
			"damage":
				bolt_damage = maxi(0, int(overrides[key]))
			"speed":
				speed = float(overrides[key])
	hp = max_hp
	queue_redraw()


func _ready() -> void:
	anchor = global_position
	collision_layer = 4
	collision_mask = 0


func _physics_process(delta: float) -> void:
	if dead:
		return
	_wob += delta
	hit_t = maxf(0.0, hit_t - delta)

	var desired := anchor + Vector2(0.0, sin(_wob * 1.8) * HOVER_AMPLITUDE)
	var in_range := target != null and not target.dead \
		and target.global_position.distance_to(global_position) < chase_range
	if in_range:
		desired.x = target.global_position.x
		shoot_t -= delta
		if shoot_t <= 0.0:
			shoot_t = SHOOT_INTERVAL
			_shoot()

	global_position = global_position.move_toward(desired, speed * delta)
	queue_redraw()


func _shoot() -> void:
	if target == null or not is_instance_valid(target):
		return
	var bolt := BOLT_SCENE.instantiate()
	bolt.global_position = global_position
	var dir := (target.global_position - global_position).normalized()
	bolt.velocity = dir * InkBolt.SPEED
	bolt.damage = bolt_damage
	get_parent().add_child(bolt)


func hit(damage: int, from_dir: int, knock: float = KNOCKBACK) -> void:
	if dead:
		return
	hp -= damage
	hit_t = HURT_TIME
	global_position.x += -from_dir * knock * 0.02
	if hp <= 0:
		dead = true
		died.emit(self)
		queue_free()


func _draw() -> void:
	var ink := BONE if hit_t > 0.0 else INK
	var sway := sin(_wob * 2.2) * 2.0
	# Ромб-тушь и два «крыла» из штрихов.
	var pts := PackedVector2Array([
		Vector2(0.0 + sway, -16.0),
		Vector2(14.0, 0.0),
		Vector2(0.0 + sway, 16.0),
		Vector2(-14.0, 0.0),
	])
	draw_colored_polygon(pts, ink)
	draw_line(Vector2(-14.0, -2.0), Vector2(-28.0, -8.0), Color(ink, 0.55), 2.0)
	draw_line(Vector2(14.0, -2.0), Vector2(28.0, -8.0), Color(ink, 0.55), 2.0)
	draw_circle(Vector2(0.0, -3.0), 3.0, RED)
