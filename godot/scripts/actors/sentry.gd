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
var _look_target := InkPlayer.new(null, 0.0, 0.0)
var _visual = preload("res://scripts/visuals/sentry_visual.gd").new(null, -20.0, -20.0)
var _wob := 0.0
var recoil_t := 0.0
var shot_dir := Vector2.RIGHT


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
	recoil_t = maxf(0.0, recoil_t - delta)
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
	shot_dir = dir
	recoil_t = 0.22
	CombatFx.burst(self, global_position + dir * 22, dir, RED, 12)
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
	# The chapter spans 14,080 px; distant actors need no ink draw commands.
	if not get_viewport_rect().grow(120.0).has_point(get_global_transform_with_canvas().origin):
		return
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_wob)
	if is_instance_valid(target):
		var local_target := to_local(target.global_position)
		_look_target.x = local_target.x - 14.0
		_look_target.y = local_target.y - 23.0
	_visual.g = {"player": _look_target}
	_visual.t = _wob
	_visual.hurt_t = hit_t
	_visual.hp = hp
	_visual.max_hp = max_hp
	_visual.pip_t = 0.7
	_visual.charging = shoot_t < 0.55 and is_instance_valid(target)
	_visual.charge = clampf(0.55 - shoot_t, 0.0, 0.55)
	InkR.save()
	InkR.t_translate(-shot_dir.x * recoil_t * 30, -shot_dir.y * recoil_t * 30)
	InkR.t_scale(1.0 + recoil_t * 0.4, 1.0 - recoil_t * 0.3)
	_visual.draw()
	InkR.restore()
	if recoil_t > 0:
		draw_arc(shot_dir * 22, 5 + (0.22 - recoil_t) * 65, 0, TAU, 24, Color(RED, recoil_t * 3), 2, true)
