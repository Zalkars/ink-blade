extends Node2D

## Godot implementation of the Ink Blade prototype.
## The game keeps a 1280x720 logical canvas so the Windows and Android builds
## share the same simulation and artwork. Touch controls are translated to
## the same actions used by keyboard and gamepad input.

const W := 1280.0
const H := 720.0
const FLOOR := 600.0
const GRAVITY := 1850.0
const PAPER := Color("#efe4cc")
const PAPER_LIGHT := Color("#f7efdd")
const PAPER_DARK := Color("#ddceac")
const INK := Color("#17130f")
const INK_SOFT := Color("#4a3c2e")
const RED := Color("#9c2129")
const RED_BRIGHT := Color("#c9353a")
const RED_DARK := Color("#651419")
const TEAL := Color("#2c6f6b")
const GOLD := Color("#b8923f")
const CREAM := Color("#f6edda")

var font: Font
var state := "title"
var title_t := 0.0
var clock := 0.0
var run_time := 0.0
var hitstop := 0.0
var death_delay := 0.0
var dead_t := 0.0
var title_controls := false
var paused_submenu := ""
var menu_index := 0
var shake_enabled := true
var sound_enabled := true
var debug_hitboxes := false
var hint_timer := 0.0
var banner_timer := 0.0
var combo := 0
var combo_timer := 0.0
var max_combo := 0
var kills := 0
var hits := 0
var deaths := 0
var fps := 60
var fps_acc := 0.0
var fps_frames := 0
var player := {}
var enemies: Array = []
var projectiles: Array = []
var particles: Array = []
var rings: Array = []
var flashes: Array = []
var touch_down := {}
var touch_pressed := {}
var show_touch := false
var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
const AUDIO_RATE := 22050

var menu_items := ["resume", "restart", "controls", "shake", "sound", "title"]

func _ready() -> void:
	font = ThemeDB.fallback_font
	show_touch = OS.has_feature("mobile")
	_init_audio()
	_new_run()
	queue_redraw()

func _init_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = AUDIO_RATE
	stream.buffer_length = 0.6
	audio_player.stream = stream
	add_child(audio_player)
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()

func _process(delta: float) -> void:
	var dt := min(delta, 0.05)
	clock += dt
	fps_acc += dt
	fps_frames += 1
	if fps_acc > 0.5:
		fps = int(round(float(fps_frames) / fps_acc))
		fps_acc = 0.0
		fps_frames = 0

	_handle_global()
	if state == "title":
		title_t += dt
		if not title_controls and title_t > 0.65 and (_confirm() or _pressed("pause") or _pressed("restart") or _pressed("jump")):
			_start_run()
	elif state == "play":
		var sim_dt := dt
		if hitstop > 0.0:
			hitstop = max(0.0, hitstop - dt)
			sim_dt *= 0.06
		_update_play(sim_dt)
	elif state == "paused":
		_update_pause(dt)
	elif state == "dead":
		dead_t += dt
		_update_effects(dt * 0.5)
		if dead_t > 0.55 and (_confirm() or _pressed("restart") or _pressed("pause")):
			if _pressed("pause"):
				state = "title"
				title_t = 0.0
				_new_run()
			else:
				_start_run()
	_update_touch_frame()
	queue_redraw()

func _handle_global() -> void:
	if _pressed("mute"):
		sound_enabled = not sound_enabled
		_beep(700.0, 0.04)
	if _pressed("debug"):
		debug_hitboxes = not debug_hitboxes
	if _pressed("help"):
		if state == "play":
			_open_pause("controls")
		elif state == "paused":
			paused_submenu = "" if paused_submenu == "controls" else "controls"
		elif state == "title":
			title_controls = not title_controls
	if state == "play" and _pressed("pause"):
		_open_pause("")
	elif state == "play" and _pressed("restart"):
		_start_run()

func _new_run() -> void:
	player = {
		"x": 300.0, "y": 550.0, "vx": 0.0, "vy": 0.0, "facing": 1,
		"health": 5, "max_health": 5, "soul": 0, "invuln": 0.0,
		"attack_t": 0.0, "attack_step": 0, "attack_hit": false,
		"dash_t": 0.0, "dash_cd": 0.0, "heal_t": 0.0, "dead": false,
		"grounded": false, "coyote": 0.0
	}
	enemies = [
		{"kind": "dummy", "x": 610.0, "y": 560.0, "vx": 0.0, "vy": 0.0, "hp": 8, "max_hp": 8, "dead": false, "hurt": 0.0, "phase": 0.0, "contact": false, "min_x": 610.0, "max_x": 610.0, "cooldown": 0.0},
		{"kind": "grunt", "x": 1020.0, "y": 560.0, "vx": -35.0, "vy": 0.0, "hp": 3, "max_hp": 3, "dead": false, "hurt": 0.0, "phase": 0.0, "contact": true, "min_x": 860.0, "max_x": 1200.0, "cooldown": 0.0},
		{"kind": "grunt", "x": 238.0, "y": 410.0, "vx": 35.0, "vy": 0.0, "hp": 3, "max_hp": 3, "dead": false, "hurt": 0.0, "phase": 1.3, "contact": true, "min_x": 160.0, "max_x": 360.0, "cooldown": 0.0},
		{"kind": "sentry", "x": 760.0, "y": 220.0, "vx": 0.0, "vy": 0.0, "hp": 4, "max_hp": 4, "dead": false, "hurt": 0.0, "phase": 0.0, "contact": false, "min_x": 0.0, "max_x": 0.0, "cooldown": 1.0}
	]
	projectiles.clear()
	particles.clear()
	rings.clear()
	flashes.clear()
	combo = 0
	combo_timer = 0.0
	max_combo = 0
	kills = 0
	hits = 0
	run_time = 0.0
	death_delay = 0.0
	dead_t = 0.0
	hint_timer = 0.0
	banner_timer = 0.0
	hitstop = 0.0

func _start_run() -> void:
	_new_run()
	state = "play"
	title_controls = false
	banner_timer = 4.2
	hint_timer = 18.0
	_flash(CREAM, 0.7)
	_beep(520.0, 0.12)

func _update_play(dt: float) -> void:
	run_time += dt
	_update_player(dt)
	for enemy in enemies:
		_update_enemy(enemy, dt)
	for shot in projectiles:
		_update_projectile(shot, dt)
	projectiles = projectiles.filter(func(p): return not p.dead)
	_combat()
	_update_effects(dt)
	combo_timer = max(0.0, combo_timer - dt)
	if combo_timer <= 0.0:
		combo = 0
	banner_timer = max(0.0, banner_timer - dt)
	hint_timer = max(0.0, hint_timer - dt)
	if _hazard(player) and not player.dead:
		_hazard_teleport()
	if player.dead:
		death_delay += dt
		if death_delay > 1.1:
			state = "dead"
			deaths += 1

func _update_player(dt: float) -> void:
	player.invuln = max(0.0, player.invuln - dt)
	player.dash_cd = max(0.0, player.dash_cd - dt)
	player.attack_t = max(0.0, player.attack_t - dt)
	player.dash_t = max(0.0, player.dash_t - dt)
	player.heal_t = max(0.0, player.heal_t - dt)
	var move := _axis_x()
	if player.dead:
		player.vx = move * 80.0
		player.vy += GRAVITY * dt
		player.x += player.vx * dt
		player.y += player.vy * dt
		return
	if player.dash_t > 0.0:
		player.vx = player.facing * 850.0
		player.vy = 0.0
	else:
		var target := move * 330.0
		var acceleration := 1900.0 if move == 0.0 else 2400.0
		player.vx = move_toward(player.vx, target, acceleration * dt)
		if move != 0.0:
			player.facing = 1 if move > 0.0 else -1
		player.vy += GRAVITY * dt
		if _pressed("jump") and (player.grounded or player.coyote > 0.0):
			player.vy = -710.0
			player.grounded = false
			player.coyote = 0.0
			_beep(300.0, 0.1)
		if _pressed("dash") and player.dash_cd <= 0.0:
			player.dash_t = 0.16
			player.dash_cd = 0.62
			player.invuln = 0.24
			_emit_burst(Vector2(player.x, player.y), 8, TEAL)
			_beep(900.0, 0.08)
		if _pressed("attack") and player.attack_t <= 0.0:
			player.attack_step = (player.attack_step % 3) + 1
			player.attack_t = 0.32
			player.attack_hit = false
			_beep(1050.0 - player.attack_step * 120.0, 0.06)
		if _down("heal") and player.soul >= 30 and player.health < player.max_health and player.attack_t <= 0.0:
			player.heal_t += dt
			if player.heal_t > 0.75:
				player.heal_t = 0.0
				player.soul -= 30
				player.health += 1
				player.invuln = 0.4
				_emit_burst(Vector2(player.x, player.y - 35), 14, GOLD)
				_beep(520.0, 0.2)
		else:
			player.heal_t = 0.0
	player.x += player.vx * dt
	player.y += player.vy * dt
	player.x = clamp(player.x, 28.0, W - 28.0)
	var was_grounded: bool = player.grounded
	player.grounded = false
	if player.y >= FLOOR - 50.0 and player.vy >= 0.0:
		player.y = FLOOR - 50.0
		if not was_grounded and player.vy > 380.0:
			_beep(110.0, 0.05)
		player.vy = 0.0
		player.grounded = true
	if player.vy >= 0.0:
		for platform in _platforms():
			if player.x > platform.position.x and player.x < platform.end.x and player.y + 50.0 >= platform.position.y and player.y + 50.0 <= platform.position.y + 22.0 and player.y - player.vy * dt + 50.0 <= platform.position.y + 8.0:
				player.y = platform.position.y - 50.0
				player.vy = 0.0
				player.grounded = true
	player.coyote = 0.09 if player.grounded else max(0.0, player.coyote - dt)

func _update_enemy(e: Dictionary, dt: float) -> void:
	if e.dead:
		e.y += 450.0 * dt
		e.hurt = max(0.0, e.hurt - dt)
		return
	e.hurt = max(0.0, e.hurt - dt)
	e.cooldown = max(0.0, e.cooldown - dt)
	e.phase += dt
	if e.kind == "grunt":
		if e.x < e.min_x:
			e.vx = abs(e.vx)
		if e.x > e.max_x:
			e.vx = -abs(e.vx)
		if abs(player.x - e.x) < 180.0 and abs(player.y - e.y) < 80.0:
			e.vx = sign(player.x - e.x) * 55.0
		e.x += e.vx * dt
		if e.y < FLOOR - 40.0:
			e.y += GRAVITY * dt
			e.y = min(e.y, FLOOR - 40.0)
	elif e.kind == "sentry":
		e.y = 220.0 + sin(clock * 1.4) * 18.0
		e.x = 760.0 + sin(clock * 0.55) * 170.0
		if e.cooldown <= 0.0:
			e.cooldown = 2.5
			var d := Vector2(player.x - e.x, player.y - 30.0 - e.y).normalized()
			projectiles.append({"x": e.x, "y": e.y, "vx": d.x * 260.0, "vy": d.y * 260.0, "dead": false, "life": 4.0, "id": randi()})
			_beep(250.0, 0.06)

func _update_projectile(p: Dictionary, dt: float) -> void:
	p.life -= dt
	p.x += p.vx * dt
	p.y += p.vy * dt
	if p.life <= 0.0 or p.x < -40.0 or p.x > W + 40.0 or p.y < -40.0 or p.y > H + 40.0:
		p.dead = true

func _combat() -> void:
	if player.dead:
		return
	if player.attack_t > 0.0 and not player.attack_hit and player.attack_t < 0.24:
		var box := _attack_box()
		for e in enemies:
			if e.dead or not _rect_overlap(box, _enemy_box(e)):
				continue
			player.attack_hit = true
			var damage := player.attack_step
			e.hp -= damage
			e.hurt = 0.16
			e.vx = player.facing * (180.0 + damage * 50.0)
			player.soul = min(100, player.soul + 12)
			hits += 1
			_add_combo()
			_emit_burst(Vector2(e.x, e.y - 24), 10, CREAM)
			_flash(RED_BRIGHT, 0.08)
			if e.hp <= 0:
				e.dead = true
				kills += 1
				player.soul = min(100, player.soul + 15)
				_emit_burst(Vector2(e.x, e.y - 25), 20, RED_DARK)
				_beep(120.0, 0.2)
			else:
				_beep(150.0, 0.07)
			break
		for p in projectiles:
			if p.dead:
				continue
			if _rect_overlap(box, Rect2(p.x - 10, p.y - 10, 20, 20)):
				p.vx = -p.vx * 1.25
				p.vy = -p.vy * 1.25
				p.life = 2.0
				player.soul = min(100, player.soul + 8)
				_add_combo()
				_emit_burst(Vector2(p.x, p.y), 9, GOLD)
				_beep(1400.0, 0.06)
	if player.invuln > 0.0:
		return
	var ph := Rect2(player.x - 15, player.y - 45, 30, 48)
	for e in enemies:
		if not e.dead and e.contact and _rect_overlap(ph, _enemy_box(e)):
			_hurt(1, e.x)
			break
	if player.invuln > 0.0:
		return
	for p in projectiles:
		if not p.dead and _rect_overlap(ph, Rect2(p.x - 10, p.y - 10, 20, 20)):
			_hurt(1, p.x)
			p.dead = true
			break

func _hurt(amount: int, source_x: float) -> void:
	if player.invuln > 0.0 or player.dead:
		return
	player.health -= amount
	player.invuln = 0.8
	player.vx = -sign(source_x - player.x) * 260.0
	player.vy = -300.0
	combo = 0
	_emit_burst(Vector2(player.x, player.y - 20), 12, RED_BRIGHT)
	_flash(RED_BRIGHT, 0.22)
	_beep(90.0, 0.18)
	if player.health <= 0:
		player.dead = true
		player.vx = -sign(source_x - player.x) * 100.0
		player.vy = -400.0

func _hazard_teleport() -> void:
	_hurt(1, player.x + 1.0)
	player.x = 300.0
	player.y = 550.0
	player.vx = 0.0
	player.vy = 0.0
	player.facing = 1
	_emit_burst(Vector2(player.x, player.y), 18, RED_DARK)

func _open_pause(submenu: String) -> void:
	if state != "play":
		return
	state = "paused"
	paused_submenu = submenu
	menu_index = 0
	_beep(700.0, 0.04)

func _update_pause(_dt: float) -> void:
	if paused_submenu == "controls":
		if _pressed("pause") or _pressed("help"):
			paused_submenu = ""
		return
	if _pressed("pause"):
		state = "play"
		_beep(520.0, 0.08)
		return
	if _pressed("move_up"):
		menu_index = (menu_index - 1 + menu_items.size()) % menu_items.size()
	if _pressed("move_down"):
		menu_index = (menu_index + 1) % menu_items.size()
	if _confirm():
		_activate_menu()

func _activate_menu() -> void:
	var item: String = menu_items[menu_index]
	_beep(520.0, 0.1)
	match item:
		"resume": state = "play"
		"restart": _start_run()
		"controls": paused_submenu = "controls"
		"shake": shake_enabled = not shake_enabled
		"sound": sound_enabled = not sound_enabled
		"title":
			state = "title"
			title_t = 0.0
			_new_run()

func _add_combo() -> void:
	combo += 1
	combo_timer = 1.7
	max_combo = max(max_combo, combo)

func _attack_box() -> Rect2:
	var x: float = player.x + player.facing * 50.0 - (65.0 if player.facing > 0 else 95.0)
	return Rect2(x, player.y - 78.0, 130.0, 70.0)

func _enemy_box(e: Dictionary) -> Rect2:
	var r := 28.0 if e.kind == "dummy" else (24.0 if e.kind == "grunt" else 30.0)
	return Rect2(e.x - r, e.y - r * 2.0, r * 2.0, r * 2.0)

func _rect_overlap(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)

func _platforms() -> Array:
	return [Rect2(120, 480, 260, 18), Rect2(850, 430, 285, 18)]

func _hazard(p: Dictionary) -> bool:
	return p.x > 715.0 and p.x < 840.0 and p.y > 550.0

func _axis_x() -> float:
	var value := Input.get_axis("move_left", "move_right")
	if touch_down.get("move_left", false): value -= 1.0
	if touch_down.get("move_right", false): value += 1.0
	return clamp(value, -1.0, 1.0)

func _confirm() -> bool:
	return _pressed("jump") or _pressed("attack")

func _pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action) or bool(touch_pressed.get(action, false))

func _down(action: String) -> bool:
	return Input.is_action_pressed(action) or bool(touch_down.get(action, false))

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var action := _touch_action(event.position)
		if action != "":
			if event.pressed:
				touch_down[action] = true
				touch_pressed[action] = true
			else:
				touch_down.erase(action)
	elif event is InputEventScreenDrag:
		var action_drag := _touch_action(event.position)
		if action_drag != "":
			touch_down[action_drag] = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_action := _touch_action(event.position)
		if mouse_action != "":
			if event.pressed:
				touch_down[mouse_action] = true
				touch_pressed[mouse_action] = true
			else:
				touch_down.erase(mouse_action)

func _touch_action(pos: Vector2) -> String:
	if Rect2(34, 580, 94, 92).has_point(pos): return "move_left"
	if Rect2(140, 580, 94, 92).has_point(pos): return "move_right"
	if Rect2(970, 572, 82, 100).has_point(pos): return "jump"
	if Rect2(1065, 520, 88, 100).has_point(pos): return "attack"
	if Rect2(1160, 572, 88, 100).has_point(pos): return "dash"
	if Rect2(1065, 420, 88, 82).has_point(pos): return "heal"
	if Rect2(1180, 24, 72, 58).has_point(pos): return "pause"
	return ""

func _update_touch_frame() -> void:
	touch_pressed.clear()

func _emit_burst(pos: Vector2, count: int, color: Color) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(max(1, count)) + randf_range(-0.3, 0.3)
		particles.append({"p": pos, "v": Vector2(cos(angle), sin(angle)) * randf_range(50.0, 220.0), "life": randf_range(0.25, 0.7), "max": 0.7, "color": color, "size": randf_range(1.5, 4.0)})

func _flash(color: Color, life: float) -> void:
	flashes.append({"color": color, "life": life, "max": life})

func _update_effects(dt: float) -> void:
	for p in particles:
		p.life -= dt
		p.p += p.v * dt
		p.v *= pow(0.02, dt)
	particles = particles.filter(func(p): return p.life > 0.0)
	for r in rings:
		r.life -= dt
		r.radius += r.speed * dt
	rings = rings.filter(func(r): return r.life > 0.0)
	for f in flashes:
		f.life -= dt
	flashes = flashes.filter(func(f): return f.life > 0.0)

func _beep(freq: float, duration: float) -> void:
	if not sound_enabled:
		return
	if audio_playback == null:
		return
	var frames := int(clamp(duration, 0.02, 0.35) * AUDIO_RATE)
	for i in range(frames):
		var t := float(i) / AUDIO_RATE
		var envelope := exp(-t * 18.0)
		var sample := sin(TAU * freq * t) * 0.12 * envelope
		audio_playback.push_frame(Vector2(sample, sample))

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), PAPER)
	if state == "title":
		_draw_title()
		if title_controls:
			_draw_controls_overlay(true)
	else:
		_draw_world()
		_draw_hud()
		if state == "paused":
			_draw_pause()
		elif state == "dead":
			_draw_death()
		if debug_hitboxes:
			_draw_debug()
	if show_touch:
		_draw_touch_controls()

func _draw_title() -> void:
	_draw_paper_texture()
	var sun := Vector2(946, 236)
	draw_circle(sun, 124, Color(0.61, 0.13, 0.16, 0.9))
	draw_arc(sun, 124, 0, TAU, 40, INK, 2.0, true)
	var far := PackedVector2Array([Vector2(0,600),Vector2(120,538),Vector2(210,572),Vector2(318,498),Vector2(420,556),Vector2(512,514),Vector2(620,574),Vector2(742,522),Vector2(860,566),Vector2(980,508),Vector2(1104,560),Vector2(1190,522),Vector2(1280,580),Vector2(1280,720),Vector2(0,720)])
	draw_colored_polygon(far, Color(INK, 0.16))
	var mid := PackedVector2Array([Vector2(0,652),Vector2(110,606),Vector2(224,638),Vector2(330,590),Vector2(452,646),Vector2(560,602),Vector2(690,650),Vector2(804,604),Vector2(930,648),Vector2(1040,608),Vector2(1160,652),Vector2(1280,616),Vector2(1280,720),Vector2(0,720)])
	draw_colored_polygon(mid, Color(INK, 0.42))
	draw_string(font, Vector2(96, 238), "ЧЕРНИЛЬНЫЙ", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, INK)
	draw_string(font, Vector2(92, 344), "КЛИНОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 108, INK)
	draw_line(Vector2(100, 364), Vector2(610, 364), RED, 5.0, true)
	draw_string(font, Vector2(102, 400), "ТРЕНИРОВОЧНАЯ ЗАЛА · ПРОТОТИП", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK, 0.65))
	draw_string(font, Vector2(102, 452), "F1 — управление   ·   M — звук", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.55))
	draw_string(font, Vector2(1240, 700), "v 0.1 · Godot port", HORIZONTAL_ALIGNMENT_RIGHT, 200, 11, Color(CREAM, 0.7))
	var pulse := 0.62 + sin(title_t * 3.1) * 0.28
	draw_rect(Rect2(420, 636, 440, 48), Color(CREAM, 0.92), true)
	draw_rect(Rect2(420, 636, 440, 48), Color(INK, 0.65), false, 1.6)
	draw_line(Vector2(438, 647), Vector2(438, 673), RED, 3.0)
	draw_string(font, Vector2(640, 667), "НАЖМИ ПРОБЕЛ ИЛИ  A", HORIZONTAL_ALIGNMENT_CENTER, 0, 19, Color(INK, pulse))

func _draw_paper_texture() -> void:
	for i in range(30):
		var x := float((i * 173) % 1280)
		var y := float((i * 97) % 720)
		draw_circle(Vector2(x, y), 1.0 + float(i % 3), Color(INK, 0.025))

func _draw_world() -> void:
	_draw_paper_texture()
	# Background mountains and pillars.
	draw_colored_polygon(PackedVector2Array([Vector2(0,300),Vector2(180,240),Vector2(340,310),Vector2(520,230),Vector2(700,300),Vector2(860,235),Vector2(1040,300),Vector2(1280,230),Vector2(1280,720),Vector2(0,720)]), Color(INK, 0.035))
	draw_rect(Rect2(0, FLOOR, W, H - FLOOR), Color(INK, 0.08), true)
	draw_line(Vector2(46, FLOOR), Vector2(718, FLOOR), INK_SOFT, 3.0)
	draw_line(Vector2(842, FLOOR), Vector2(1234, FLOOR), INK_SOFT, 3.0)
	# Hazard pit.
	draw_colored_polygon(PackedVector2Array([Vector2(718, FLOOR),Vector2(842,FLOOR),Vector2(838,720),Vector2(722,720)]), Color(RED_DARK,0.25))
	for x in range(730, 835, 18):
		draw_line(Vector2(x, 700), Vector2(x + 9, 680), RED_DARK, 2.0)
	for p in _platforms():
		draw_rect(p, Color(INK, 0.72), true)
		draw_line(p.position, Vector2(p.end.x, p.position.y), CREAM, 2.0)
	for e in enemies:
		_draw_enemy(e)
	for p in projectiles:
		draw_circle(Vector2(p.x, p.y), 9, RED_BRIGHT)
		draw_circle(Vector2(p.x, p.y), 4, CREAM)
	_draw_player()
	for p in particles:
		draw_circle(p.p, p.size, Color(p.color, clamp(p.life / p.max, 0.0, 1.0)))
	for f in flashes:
		draw_rect(Rect2(0, 0, W, H), Color(f.color, clamp(f.life / f.max * 0.22, 0.0, 0.22)), true)

func _draw_player() -> void:
	var x: float = player.x
	var y: float = player.y
	var alpha := 0.45 if player.invuln > 0.0 and int(clock * 18.0) % 2 == 0 else 1.0
	var body := Color(INK, alpha)
	draw_colored_polygon(PackedVector2Array([Vector2(x-14,y-8),Vector2(x+13,y-8),Vector2(x+10,y-42),Vector2(x-11,y-42)]), body)
	draw_circle(Vector2(x, y - 54), 17, body)
	draw_colored_polygon(PackedVector2Array([Vector2(x-12,y-69),Vector2(x-2,y-84),Vector2(x+5,y-68),Vector2(x+14,y-78),Vector2(x+12,y-58),Vector2(x-12,y-58)]), body)
	var scarf := PackedVector2Array([Vector2(x-9,y-31),Vector2(x-42 - sin(clock*4.0)*8,y-18),Vector2(x-62,y-35),Vector2(x-39,y-4),Vector2(x-8,y-20)])
	draw_colored_polygon(scarf, Color(RED, alpha))
	draw_line(Vector2(x + player.facing * 9, y - 40), Vector2(x + player.facing * 34, y - 45), CREAM, 3.0)
	if player.attack_t > 0.0:
		var center := Vector2(x + player.facing * 38, y - 47)
		var start := -1.2 if player.facing > 0 else PI + 1.2
		var end := 1.2 if player.facing > 0 else PI - 1.2
		draw_arc(center, 60.0 + player.attack_step * 5.0, start, end, 16, Color(CREAM,0.9), 6.0, true)

func _draw_enemy(e: Dictionary) -> void:
	if e.dead and e.y > 760.0:
		return
	var x: float = e.x
	var y: float = e.y
	var col := Color(INK, 0.45) if e.hurt > 0.0 and int(clock*20.0)%2==0 else INK
	if e.kind == "dummy":
		draw_rect(Rect2(x-23,y-62,46,62), col, true)
		draw_circle(Vector2(x,y-75), 20, col)
		draw_line(Vector2(x-32,y),Vector2(x+32,y),INK_SOFT,5.0)
	elif e.kind == "grunt":
		draw_colored_polygon(PackedVector2Array([Vector2(x-23,y),Vector2(x-18,y-42),Vector2(x-6,y-54),Vector2(x+16,y-47),Vector2(x+24,y),]), col)
		draw_line(Vector2(x-12,y-44),Vector2(x+11,y-47),RED_BRIGHT,3.0)
	else:
		draw_circle(Vector2(x,y-25), 29, col)
		draw_circle(Vector2(x,y-25), 12, RED_DARK)
		draw_line(Vector2(x-36,y-25),Vector2(x+36,y-25),Color(CREAM, 0.45),3.0)
	if e.hp < e.max_hp and not e.dead:
		draw_rect(Rect2(x-30,y-88,60,5), Color(INK,0.25), true)
		draw_rect(Rect2(x-30,y-88,60*float(e.hp)/float(e.max_hp),5), RED, true)

func _draw_hud() -> void:
	for i in range(player.max_health):
		var c := RED_BRIGHT if i < player.health else Color(INK,0.18)
		draw_circle(Vector2(48 + i*28, 42), 9, c)
		draw_circle(Vector2(48 + i*28, 42), 5, PAPER_LIGHT)
	draw_string(font, Vector2(48, 78), "ДУША", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK,0.7))
	draw_rect(Rect2(48, 87, 120, 8), Color(INK,0.2), true)
	draw_rect(Rect2(48, 87, 120 * float(player.soul) / 100.0, 8), GOLD, true)
	if combo > 1:
		draw_string(font, Vector2(640, 86), "СЕРИЯ  %02d" % combo, HORIZONTAL_ALIGNMENT_CENTER, 0, 24, RED)
	if banner_timer > 0.0:
		draw_rect(Rect2(380, 122, 520, 72), Color(CREAM,0.9), true)
		draw_string(font, Vector2(640, 153), "ЗАЛ ПЕРВОГО ВЗМАХА", HORIZONTAL_ALIGNMENT_CENTER, 0, 22, INK)
		draw_string(font, Vector2(640, 178), "освой движение и клинок", HORIZONTAL_ALIGNMENT_CENTER, 0, 13, Color(INK,0.65))
	if hint_timer > 0.0:
		draw_string(font, Vector2(640, 690), "A/D — движение   ПРОБЕЛ — прыжок   J — атака   K — рывок   L — лечение", HORIZONTAL_ALIGNMENT_CENTER, 900, 14, Color(INK, clamp(hint_timer / 2.4,0.0,1.0) * 0.7))

func _draw_pause() -> void:
	draw_rect(Rect2(0,0,W,H), Color(INK,0.42), true)
	draw_rect(Rect2(360,120,560,480), Color(PAPER,0.97), true)
	draw_rect(Rect2(360,120,560,480), INK, false, 3.0)
	if paused_submenu == "controls":
		_draw_controls_overlay(false)
		return
	draw_string(font, Vector2(640,180), "ПАУЗА", HORIZONTAL_ALIGNMENT_CENTER, 0, 38, INK)
	for i in range(menu_items.size()):
		var label := ["ПРОДОЛЖИТЬ","ЗАНОВО","УПРАВЛЕНИЕ","ВСТРЯСКА: "+("ВКЛ" if shake_enabled else "ВЫКЛ"),"ЗВУК: "+("ВКЛ" if sound_enabled else "ВЫКЛ"),"В МЕНЮ"][i]
		var y := 245.0 + i * 48.0
		var selected := i == menu_index
		if selected: draw_rect(Rect2(438,y-30,404,38), Color(RED,0.14), true)
		draw_string(font, Vector2(640,y), label, HORIZONTAL_ALIGNMENT_CENTER, 0, 21, RED if selected else INK)

func _draw_controls_overlay(_title: bool) -> void:
	draw_rect(Rect2(300,110,680,500), Color(PAPER,0.98), true)
	draw_rect(Rect2(300,110,680,500), INK, false, 3.0)
	draw_string(font, Vector2(640,170), "УПРАВЛЕНИЕ", HORIZONTAL_ALIGNMENT_CENTER, 0, 32, INK)
	var rows := ["ДВИЖЕНИЕ        A / D или левый стик", "ПРЫЖОК           ПРОБЕЛ / A", "АТАКА            J / X", "РЫВОК            K / B", "ЛЕЧЕНИЕ          L / Y", "ПАУЗА            ESC / START", "F1                открыть этот экран"]
	for i in range(rows.size()):
		draw_string(font, Vector2(410,230+i*42), rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	draw_string(font, Vector2(640,570), "F1 / ESC — закрыть", HORIZONTAL_ALIGNMENT_CENTER, 0, 16, Color(INK,0.65))

func _draw_death() -> void:
	draw_rect(Rect2(0,0,W,H), Color(RED_DARK,0.18), true)
	draw_rect(Rect2(350,255,580,190), Color(PAPER,0.94), true)
	draw_rect(Rect2(350,255,580,190), RED_DARK, false, 3.0)
	draw_string(font, Vector2(640,325), "ЧЕРНИЛА ПОБЕДИЛИ", HORIZONTAL_ALIGNMENT_CENTER, 0, 34, RED_DARK)
	draw_string(font, Vector2(640,370), "НАЖМИ R ИЛИ ПРОБЕЛ — ВОЗРОДИТЬСЯ", HORIZONTAL_ALIGNMENT_CENTER, 0, 16, INK)
	draw_string(font, Vector2(640,405), "УБИТО: %d   МАКС. СЕРИЯ: %d" % [kills, max_combo], HORIZONTAL_ALIGNMENT_CENTER, 0, 14, Color(INK,0.7))

func _draw_debug() -> void:
	draw_rect(_attack_box(), Color(RED,0.18), true)
	draw_rect(_attack_box(), RED, false, 1.0)
	for e in enemies:
		if not e.dead: draw_rect(_enemy_box(e), Color(TEAL,0.2), false, 1.0)
	draw_string(font, Vector2(1240,700), "%d FPS · %s" % [fps,state], HORIZONTAL_ALIGNMENT_RIGHT, 180, 12, Color(INK,0.6))

func _draw_touch_controls() -> void:
	var labels := {"move_left":"◀", "move_right":"▶", "jump":"A", "attack":"X", "dash":"B", "heal":"Y", "pause":"Ⅱ"}
	var rects := {"move_left":Rect2(34,580,94,92),"move_right":Rect2(140,580,94,92),"jump":Rect2(970,572,82,100),"attack":Rect2(1065,520,88,100),"dash":Rect2(1160,572,88,100),"heal":Rect2(1065,420,88,82),"pause":Rect2(1180,24,72,58)}
	for key in rects:
		var r: Rect2 = rects[key]
		var active := bool(touch_down.get(key,false))
		draw_rect(r, Color(INK,0.28 if active else 0.14), true)
		draw_rect(r, Color(CREAM,0.55), false, 2.0)
		draw_string(font, r.position + Vector2(r.size.x/2, r.size.y/2+9), labels[key], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, CREAM)
