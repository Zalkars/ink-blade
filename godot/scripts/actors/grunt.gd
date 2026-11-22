class_name Grunt
extends CharacterBody2D

## Простейший враг основы: идёт к игроку, бьёт касанием, умирает от двух ударов.
## Здесь же проверяется главное требование каркаса: враг — сцена, а не RefCounted
## внутри game.gd, и добавляется он данными уровня.

signal died(grunt: Grunt)

var max_hp := 2
var speed := 95.0
var chase_range := 560.0
var touch_damage := 1

const GRAVITY := 1900.0
const MAX_FALL := 950.0
const TOUCH_RANGE := Vector2(30.0, 34.0)
const TOUCH_COOLDOWN := 0.8
const KNOCKBACK := 460.0
const HURT_TIME := 0.14

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const BONE := Color("#d9cdb8")

var hp := 2
var target: Player
var dead := false

var hit_t := 0.0
var touch_cd := 0.0
var _visual = preload("res://scripts/visuals/grunt_visual.gd").new(null, -28.0, -16.0)
var _wob := 0.0
var attack_t := 0.0
var attack_dir := 1.0
var facing := 1


## Заполняет параметры из карточки контента и применяет переопределения уровня.
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
			push_warning("grunt: поле %s не разрешено в карточке %s" % [field, def.id])
			continue
		match field:
			"max_hp":
				max_hp = maxi(1, int(overrides[key]))
			"damage":
				touch_damage = maxi(0, int(overrides[key]))
			"speed":
				speed = float(overrides[key])
	hp = max_hp
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

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	if attack_t > 0.0:
		var previous := attack_t
		attack_t = maxf(0.0, attack_t - delta)
		if previous > 0.16 and attack_t <= 0.16:
			_strike()
	var dir := 0.0
	if target != null and not target.dead and target.global_position.distance_to(global_position) < chase_range:
		var dx := target.global_position.x - global_position.x
		if absf(dx) > 12.0:
			dir = signf(dx)
		if absf(dx) < TOUCH_RANGE.x and absf(target.global_position.y - global_position.y) < TOUCH_RANGE.y:
			_touch_player(dx)

	if dir != 0 and attack_t <= 0.0:
		facing = int(dir)
	if hit_t <= 0.0:
		velocity.x = move_toward(velocity.x, dir * speed if attack_t <= 0.0 else 0.0, 900.0 * delta)
	move_and_slide()
	queue_redraw()


func _touch_player(dx: float) -> void:
	if touch_cd > 0.0 or target == null:
		return
	touch_cd = TOUCH_COOLDOWN
	attack_dir = 1.0 if dx >= 0.0 else -1.0
	facing = int(attack_dir)
	attack_t = 0.38

func _strike() -> void:
	var start := global_position + Vector2(0, -8)
	var ray := PhysicsRayQueryParameters2D.create(start, start + Vector2(attack_dir * 44, 0), 1)
	var wall := get_world_2d().direct_space_state.intersect_ray(ray)
	if not wall.is_empty():
		CombatFx.surface(self, wall.position, wall.normal, 0.7)
	elif is_instance_valid(target) and not target.dead:
		var offset := target.global_position - global_position
		if offset.x * attack_dir >= -8 and absf(offset.x) < 48 and absf(offset.y) < 38:
			target.take_damage(touch_damage, attack_dir)


func hit(damage: int, from_dir: int, knock: float = KNOCKBACK) -> void:
	if dead:
		return
	hp -= damage
	InkFx.text_fx(global_position.x, global_position.y - 30, "-%d" % damage, 20, InkR.RED, false)
	InkFx.ink_burst(global_position.x, global_position.y, 9, 150, [InkR.INK, InkR.RED], 4, false, null, 0, 0, 1000, global_position.y + 25)
	hit_t = HURT_TIME
	attack_t = 0.0
	velocity.x = from_dir * knock
	velocity.y = -180.0
	if hp <= 0:
		InkFx.ink_burst(global_position.x, global_position.y, 22, 260, null, 6, true, null, 0, 0, 1000, global_position.y + 25)
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
	_visual.t = _wob
	_visual.leg_phase = _wob * absf(velocity.x) * 0.085
	InkR.save()
	InkR.t_translate(0, 20)
	InkR.t_rotate_deg(float(facing) * (-12.0 if attack_t > 0.16 else sin(attack_t / 0.16 * PI) * 18.0))
	InkR.t_translate(0, -20)
	_visual.facing = facing
	_visual.hurt_t = hit_t
	_visual.hp = hp
	_visual.max_hp = max_hp
	_visual.pip_t = 0.7
	_visual.draw()
	InkR.restore()
	if attack_t > 0:
		var k := clampf((0.16 - attack_t) / 0.16, 0, 1)
		var tip := Vector2(facing * (18.0 + k * 24.0), -18.0 + k * 26.0)
		draw_line(Vector2(facing * 8, -14), tip, RED if attack_t > 0.16 else INK, 5.0, true)
		if attack_t <= 0.16:
			draw_arc(Vector2(0, -8), 40, -1.1 if facing > 0 else PI - 0.8,
				0.8 if facing > 0 else PI + 1.1, 18, Color(RED, 1.0 - k), 4.0, true)
