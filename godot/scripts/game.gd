extends Node2D

## Полный порт Game.cs — фрейм-цикл, состояния (title/play/paused/dead),
## combat, hazard-телепорт, все экраны, оркестрация запекания и тач-UI.

const W := 1280.0
const H := 720.0

const MENU_ITEMS := ["resume", "restart", "settings", "controls", "title"]
const TITLE_MENU_ITEMS := ["play", "settings", "controls"]
const SETTINGS_ITEMS := ["lang", "sound", "shake", "vibration", "touch", "hitboxes", "controls", "bindings", "back"]
const SETTINGS_FILE := "user://settings.cfg"

var state := "title"
var clock := 0.0
var title_t := 0.0
var time_scale := 1.0
var hitstop := 0.0

var player = null
var enemies: Array = []
var projectiles: Array = []

var combo := 0
var max_combo := 0
var kills := 0
var hits := 0
var deaths := 0
var combo_t := 0.0
var combo_pop := 0.0
var run_time := 0.0
var banner := {"title": "", "sub": "", "t": 0.0, "max": 1.0}
var hint_timer := 0.0
var hint_alpha := 0.0

var death_delay := 0.0
var dead_t := 0.0
var menu_index := 0
var submenu = null

var title_menu_index := 0
var title_submenu = null
var settings_menu_index := 0

var settings_shake := true
var settings_sound := true
var settings_vibration := true
var settings_touch := 0 # 0 = auto, 1 = on, 2 = off
var debug_hitboxes := false

var fps := 60
var fps_acc := 0.0
var fps_n := 0

var touch_mode := false
var _pointers := {}
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _baking := false
var _rebaking := false
var _rebake_pending := false

# экран назначения клавиш
var bind_menu_index := 0
var bind_col := 0
var bind_capture := false
var bind_capture_t := 0.0
var bind_lock_t := 0.0
var bind_notice := ""
var bind_notice_t := 0.0

# Тач-схема в координатах логического холста 1280x720. Координаты касаний
# переводятся через обратную матрицу viewport canvas transform.
const T_ZONE_STICK := Rect2(0, 140, 560, 580)
const STICK_RADIUS := 64.0
const TOUCH_ZONES := {
	"jump": Rect2(940, 584, 116, 116),
	"attack": Rect2(1068, 516, 136, 136),
	"dash": Rect2(1170, 400, 106, 106),
	"heal": Rect2(1000, 392, 108, 104),
	"pause": Rect2(1160, 84, 112, 78),
}
const TOUCH_LABELS := {
	"jump": "A", "attack": "X", "dash": "B", "heal": "Y", "pause": "Ⅱ",
}
const TOUCH_RECTS := {
	"jump": Vector2(998, 642),
	"attack": Vector2(1136, 584),
	"dash": Vector2(1223, 453),
	"heal": Vector2(1054, 444),
	"pause": Vector2(1216, 123),
}


func _ready() -> void:
	_load_settings()
	InkR.init_static()
	InkWorld.init_world()
	InkFx.reset()
	_new_run()
	state = "title"
	title_t = 0.0
	_bake_all()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		L10N.set_lang(str(cfg.get_value("locale", "lang", L10N.lang)))
		settings_sound = cfg.get_value("audio", "sound", true)
		settings_shake = cfg.get_value("game", "shake", true)
		settings_vibration = cfg.get_value("game", "vibration", true)
		settings_touch = cfg.get_value("controls", "touch_mode", 0)
		debug_hitboxes = cfg.get_value("debug", "hitboxes", false)
		_load_bindings(cfg)
	CTL.vibration_enabled = settings_vibration
	SND.set_muted(not settings_sound)
	_apply_touch_mode()


## Читает назначения клавиш/кнопок из секции [bindings].
## Отсутствующие или битые значения остаются по умолчанию.
func _load_bindings(cfg: ConfigFile) -> void:
	for a in CTL.ACTIONS:
		var kb = cfg.get_value("bindings", "key_" + a, null)
		if kb is Array:
			var keys := []
			for k in kb:
				if int(k) > 0:
					keys.append(int(k))
			CTL.keyboard[a] = keys
		var pd = cfg.get_value("bindings", "pad_" + a, null)
		if pd is Array:
			var slots := []
			for s in pd:
				var slot := int(s)
				if slot >= 0 and slot < CTL.PAD_LABELS.size():
					slots.append(slot)
			CTL.pad_map[a] = slots
	# Esc — постоянная клавиша паузы/назад, даже если файл старый или битый.
	var pause_keys: Array = CTL.keyboard.get("pause", [])
	if not pause_keys.has(KEY_ESCAPE):
		pause_keys.append(KEY_ESCAPE)
		CTL.keyboard["pause"] = pause_keys


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("locale", "lang", L10N.lang)
	cfg.set_value("audio", "sound", settings_sound)
	cfg.set_value("game", "shake", settings_shake)
	cfg.set_value("game", "vibration", settings_vibration)
	cfg.set_value("controls", "touch_mode", settings_touch)
	cfg.set_value("debug", "hitboxes", debug_hitboxes)
	for a in CTL.ACTIONS:
		cfg.set_value("bindings", "key_" + a, CTL.keyboard.get(a, []))
		cfg.set_value("bindings", "pad_" + a, CTL.pad_map.get(a, []))
	cfg.save(SETTINGS_FILE)


func _apply_touch_mode() -> void:
	match settings_touch:
		0:
			touch_mode = OS.has_feature("android") or DisplayServer.is_touchscreen_available() or CTL.device == "touch"
		1:
			touch_mode = true
		2:
			touch_mode = false


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	clock += dt
	InkR.begin_frame(clock)

	fps_acc += dt
	fps_n += 1
	if fps_acc > 0.5:
		fps = int(round(float(fps_n) / fps_acc))
		fps_acc = 0.0
		fps_n = 0

	CTL.update(dt)

	_handle_global()

	if state == "play":
		var ts := time_scale
		if hitstop > 0.0:
			hitstop = maxf(0.0, hitstop - dt)
			ts *= 0.06
		var sim := dt * ts
		var guard := 0
		while sim > 0.0001 and guard < 10:
			var step_dt: float = minf(sim, 1.0 / 120.0)
			_step(step_dt)
			sim -= step_dt
			guard += 1
			if state != "play":
				break
	elif state == "title":
		_update_title(dt)
	elif state == "paused":
		_update_pause(dt)
		InkFx.update(dt * 0.25)
	elif state == "dead":
		_update_dead(dt)
		InkFx.update(dt * 0.5)

	queue_redraw()


# ---------- run ----------

func _new_run() -> void:
	InkFx.reset()
	player = InkPlayer.new(self, InkWorld.SPAWN.x, InkWorld.SPAWN.y)
	enemies.clear()
	enemies.append(InkDummy.new(self, 610, 560))
	enemies.append(InkGrunt.new(self, 1020, 584, -1, 860, 1200))
	enemies.append(InkGrunt.new(self, 238, 432, 1, 160, 360))
	enemies.append(InkSentry.new(self, 760, 222))
	projectiles.clear()
	combo = 0
	combo_t = 0
	combo_pop = 0
	max_combo = 0
	kills = 0
	hits = 0
	run_time = 0
	death_delay = 0
	dead_t = 0
	hitstop = 0
	time_scale = 1
	hint_timer = 0
	hint_alpha = 0
	banner = {"title": "", "sub": "", "t": 0.0, "max": 1.0}


func _start_run() -> void:
	_touch_stop()
	bind_capture = false
	bind_lock_t = 0.0
	_new_run()
	state = "play"
	title_submenu = null
	banner = {
		"title": L10N.t("BANNER_TITLE"),
		"sub": L10N.t("BANNER_SUB"),
		"t": 4.2, "max": 4.2,
	}
	hint_timer = 18
	hint_alpha = 1
	InkFx.flash_screen(0.7, InkR.CREAM)
	SND.unlock()
	SND.ui_confirm()


func freeze(seconds: float) -> void:
	hitstop = maxf(hitstop, seconds)


func add_combo() -> void:
	combo += 1
	combo_t = 1.7
	combo_pop = 1
	max_combo = maxi(max_combo, combo)


func on_enemy_killed(e) -> void:
	kills += 1
	player.gain_soul(15)
	InkFx.add_shake(2)


func hazard_teleport() -> void:
	var p = player
	if p == null or p.dead:
		return
	var damaged: bool = p.hurt(1, p.cx() + 1)
	p.x = InkWorld.SPAWN.x
	p.y = InkWorld.SPAWN.y
	p.vx = 0
	p.vy = 0
	p.facing = 1
	p.reset_scarf()
	InkFx.ink_burst(p.cx(), p.cy(), 18, 280.0, [InkR.INK, InkR.RED_DARK, InkR.INK_SOFT], 6.0, true)
	InkFx.ring(p.cx(), p.cy(), 6, 100, InkR.INK, 0.5, 3)
	if damaged:
		InkFx.damage_screen(0.8)


# ---------- цикл ----------

func _handle_global() -> void:
	# Пока экран ждёт новую клавишу, глобальные горячие клавиши молчат:
	# иначе назначение, скажем, на «M» тут же выключило бы звук.
	if bind_capture or bind_lock_t > 0.0:
		return
	if CTL.pressed("mute"):
		settings_sound = not settings_sound
		SND.set_muted(not settings_sound)
		_save_settings()
		SND.ui()
	if CTL.pressed("fullscreen"):
		_toggle_fullscreen()
	if CTL.pressed("screenshot"):
		_save_screenshot()
	if CTL.pressed("hitboxes"):
		debug_hitboxes = not debug_hitboxes
		_save_settings()
		SND.ui()
	if CTL.pressed("help"):
		if state == "play":
			_open_pause("controls")
		elif state == "paused":
			submenu = null if submenu == "controls" else "controls"
			menu_index = 0
			SND.ui()
		elif state == "title":
			title_submenu = null if title_submenu == "controls" else "controls"
			SND.ui()

	if state == "play" and CTL.pressed("pause"):
		_open_pause(null)
	elif state == "play" and CTL.pressed("restart"):
		_start_run()
	elif state == "title" and CTL.pressed("pause"):
		if title_submenu != null:
			title_submenu = null
			SND.ui()
		else:
			title_submenu = "settings"
			settings_menu_index = 0
			SND.ui()


func _step(dt: float) -> void:
	run_time += dt
	player.update(dt)
	for e in enemies:
		e.update(dt)
	for pr in projectiles:
		pr.update(dt)
	projectiles = projectiles.filter(func(p): return not p.dead)

	_combat()

	InkFx.update(dt)

	if combo_t > 0:
		combo_t -= dt
		if combo_t <= 0:
			combo = 0
	combo_pop = maxf(0, combo_pop - dt * 5)
	if banner.t > 0:
		banner.t = maxf(0, banner.t - dt)
	if hint_timer > 0:
		hint_timer = maxf(0, hint_timer - dt)
	hint_alpha = clampf(hint_timer / 2.4, 0, 1)

	if not player.dead and InkWorld.in_hazard(player):
		hazard_teleport()

	if player.dead:
		death_delay += dt
		if death_delay > 1.1:
			state = "dead"
			deaths += 1


func _combat() -> void:
	var p = player
	if p == null or p.dead:
		return

	var atk = p.attack
	if atk != null and p.attack_active():
		var box: Rect2 = p.attack_hitbox()
		for e in enemies:
			if e.dead or atk.hit.has(e.id):
				continue
			if not box.intersects(e.hitbox()):
				continue
			atk.hit[e.id] = true
			var dir := signi(e.cx() - p.cx())
			if dir == 0:
				dir = p.facing
			e.hurt(atk.dmg, dir, int(atk.step) == 3)
			p.gain_soul(12)
			hits += 1
			var hx: float = clampf(e.cx(), box.position.x + 4, box.end.x - 4)
			var hy: float = clampf(e.cy(), box.position.y + 4, box.end.y - 4)
			InkFx.sparks(hx, hy, -0.5 if p.facing > 0 else PI + 0.5, 5, InkR.CREAM)
			if atk.dir == "down":
				p.pogo()
		for pr in projectiles:
			if pr.dead or atk.hit.has(pr.id):
				continue
			if not box.intersects(pr.hitbox()):
				continue
			atk.hit[pr.id] = true
			pr.deflect()
			p.gain_soul(8)
			add_combo()

	if p.is_invuln():
		return

	var phb: Rect2 = p.hitbox()
	for e in enemies:
		if e.dead or not e.contact:
			continue
		if not phb.intersects(e.hitbox()):
			continue
		if p.hurt(1, e.cx()):
			InkFx.sparks(p.cx(), p.cy(), 0.0 if p.facing > 0 else PI, 6, InkR.RED_BRIGHT)
		break

	if p.is_invuln():
		return
	for pr in projectiles:
		if pr.dead:
			continue
		if not phb.intersects(pr.hitbox()):
			continue
		p.hurt(1, pr.x)
		pr.kill(true)
		break


# ---------- пауза ----------

func _open_pause(sub) -> void:
	if state != "play":
		return
	_touch_stop()
	bind_capture = false
	bind_lock_t = 0.0
	state = "paused"
	# _process продолжает текущий кадр после _handle_global; без поглощения
	# edge пауза сразу закрывалась в _update_pause тем же самым нажатием.
	CTL.edge["pause"] = false
	submenu = sub
	menu_index = 0
	SND.ui()


func _close_pause() -> void:
	_touch_stop()
	bind_capture = false
	bind_lock_t = 0.0
	state = "play"
	submenu = null
	hint_timer = maxf(hint_timer, 3)
	SND.ui_confirm()


func _update_pause(dt: float) -> void:
	if submenu == "controls":
		if CTL.pressed("pause") or CTL.pressed("help"):
			submenu = null
			menu_index = 0
			SND.ui()
		return
	elif submenu == "settings":
		_update_settings(dt)
		return
	elif submenu == "bindings":
		_update_bindings(dt)
		return

	if CTL.pressed("pause"):
		_close_pause()
		return
	var n := MENU_ITEMS.size()
	if CTL.pressed("up"):
		menu_index = (menu_index - 1 + n) % n
		SND.ui()
	if CTL.pressed("down"):
		menu_index = (menu_index + 1) % n
		SND.ui()
	if CTL.confirm():
		_activate_menu()


func _activate_menu() -> void:
	var item: String = MENU_ITEMS[menu_index]
	SND.ui_confirm()
	if item == "resume":
		_close_pause()
	elif item == "restart":
		_start_run()
	elif item == "settings":
		submenu = "settings"
		settings_menu_index = 0
	elif item == "controls":
		submenu = "controls"
	elif item == "title":
		_touch_stop()
		state = "title"
		title_t = 0.0
		submenu = null
		title_submenu = null
		InkFx.reset()
		_new_run()


func _update_title(dt: float) -> void:
	title_t += dt
	if title_submenu == "controls":
		if CTL.pressed("pause") or CTL.pressed("help"):
			title_submenu = null
			SND.ui()
		return
	elif title_submenu == "settings":
		_update_settings(dt)
		return
	elif title_submenu == "bindings":
		_update_bindings(dt)
		return

	if title_t < 0.25:
		return

	if CTL.pressed("up"):
		title_menu_index = (title_menu_index - 1 + TITLE_MENU_ITEMS.size()) % TITLE_MENU_ITEMS.size()
		SND.ui()
	elif CTL.pressed("down"):
		title_menu_index = (title_menu_index + 1) % TITLE_MENU_ITEMS.size()
		SND.ui()

	if CTL.confirm() or CTL.pressed("jump") or CTL.pressed("attack"):
		_activate_title_menu(title_menu_index)


func _activate_title_menu(index: int) -> void:
	var item: String = TITLE_MENU_ITEMS[index]
	SND.ui_confirm()
	if item == "play":
		_start_run()
	elif item == "settings":
		title_submenu = "settings"
		settings_menu_index = 0
	elif item == "controls":
		title_submenu = "controls"


func _update_settings(_dt: float) -> void:
	if CTL.pressed("pause"):
		if state == "title":
			title_submenu = null
		else:
			submenu = null
		SND.ui()
		return

	var n := SETTINGS_ITEMS.size()
	if CTL.pressed("up"):
		settings_menu_index = (settings_menu_index - 1 + n) % n
		SND.ui()
	elif CTL.pressed("down"):
		settings_menu_index = (settings_menu_index + 1) % n
		SND.ui()

	if CTL.confirm() or CTL.pressed("left") or CTL.pressed("right"):
		_toggle_setting(settings_menu_index)


func _toggle_setting(idx: int) -> void:
	var id: String = SETTINGS_ITEMS[idx]
	if id == "lang":
		L10N.next_lang()
	elif id == "sound":
		settings_sound = not settings_sound
		SND.set_muted(not settings_sound)
	elif id == "shake":
		settings_shake = not settings_shake
	elif id == "vibration":
		settings_vibration = not settings_vibration
		CTL.vibration_enabled = settings_vibration
	elif id == "touch":
		settings_touch = (settings_touch + 1) % 3
		_apply_touch_mode()
	elif id == "hitboxes":
		debug_hitboxes = not debug_hitboxes
	elif id == "controls":
		if state == "title":
			title_submenu = "controls"
		else:
			submenu = "controls"
		SND.ui_confirm()
		return
	elif id == "bindings":
		bind_capture = false
		bind_capture_t = 0.0
		bind_lock_t = 0.0
		bind_menu_index = 0
		bind_col = 0
		bind_notice = ""
		bind_notice_t = 0.0
		if state == "title":
			title_submenu = "bindings"
		else:
			submenu = "bindings"
		SND.ui_confirm()
		return
	elif id == "back":
		if state == "title":
			title_submenu = null
		else:
			submenu = null
		SND.ui_confirm()
		return

	if id == "lang":
		_request_rebake()
	_save_settings()
	SND.ui_confirm()


func _update_dead(dt: float) -> void:
	dead_t += dt
	if dead_t < 0.55:
		return
	if CTL.confirm() or CTL.pressed("restart"):
		_start_run()
	elif CTL.pressed("pause"):
		_touch_stop()
		state = "title"
		title_t = 0.0
		title_submenu = null
		_new_run()


# ---------- отрисовка ----------

func _draw() -> void:
	InkR.set_canvas(self)
	# aspect=ignore растягивает логический холст на весь экран телефона,
	# поэтому боковых рамок не остаётся.
	var extra_w: float = _extra_canvas_width()
	InkR.save()
	if extra_w > 0.0:
		InkR.fill_rect_color(0, 0, W + extra_w, H, InkR.PAPER, 1.0)
		InkR.t_translate(extra_w * 0.5, 0.0)
	if state == "title":
		_render_title()
	elif state == "paused":
		_render_world()
		_render_pause()
	elif state == "dead":
		_render_world()
		_render_death()
	else:
		_render_world()
		InkHud.draw(self)
		if death_delay > 0 and player.dead:
			_render_death_fade()
		if debug_hitboxes:
			_render_debug()

	if debug_hitboxes:
		InkR.text("%d FPS · %s · %s" % [fps, state, CTL.device],
			1240, 700, 10, InkR.F_BODY, InkR.A_RIGHT, InkR.INK, 0.5)

	if touch_mode:
		if state == "play":
			_draw_touch_ui()
		elif state == "paused":
			_draw_pause_touch_ui()
	InkR.restore()


func _render_world() -> void:
	var sh: Vector3 = InkFx.shake_offset() if settings_shake else Vector3.ZERO
	InkR.save()
	InkR.t_translate(640 + sh.x, 360 + sh.y)
	if sh.z != 0:
		InkR.t_rotate_deg(sh.z * 180.0 / PI)
	InkR.t_scale(1.015, 1.015)
	InkR.t_translate(-640, -360)

	if InkR.tex_stage != null:
		InkR.stage()
	else:
		_draw_stage_live()
	InkFx.draw_behind()
	for e in enemies:
		e.draw()
	for pr in projectiles:
		pr.draw()
	player.draw()
	InkFx.draw_front()
	InkR.restore()
	InkFx.draw_screen(W, H)


func _draw_stage_live() -> void:
	# резервный живой рендер зала (пока текстура ещё не запечена)
	if InkR.tex_paper != null:
		InkR.paper()
	else:
		InkR.fill_rect_color(0, 0, W, H, InkR.PAPER, 1.0)
	InkWorld.draw_back_static(clock)
	InkWorld.draw_candle(78, 620, 0, 1)
	InkWorld.draw_candle(1198, 620, 1.7, 0.9)
	InkWorld.draw_candle(368, 468, 0.6, 0.75)
	InkWorld.draw_front_static()
	InkWorld.draw_grass(clock)


# ---------- титульный экран ----------

func _render_title() -> void:
	if InkR.tex_title != null:
		InkR.title()
	else:
		if InkR.tex_paper != null:
			InkR.paper()
		else:
			InkR.fill_rect_color(0, 0, W, H, InkR.PAPER, 1.0)
		_render_title_scene(title_t)
		InkR.vignette()

	_title_birds(title_t)

	if title_submenu == "settings":
		_render_settings()
	elif title_submenu == "controls":
		_render_controls()
	elif title_submenu == "bindings":
		_render_bindings()
	else:
		_render_title_menu()


func _render_title_menu() -> void:
	var labels := [L10N.t("MENU_PLAY"), L10N.t("MENU_SETTINGS"), L10N.t("MENU_CONTROLS")]
	var bx := 440.0
	var bw := 400.0
	var bh := 48.0
	var start_y := 440.0

	for i in range(labels.size()):
		var by: float = start_y + i * 58.0
		var sel: bool = (i == title_menu_index)

		if sel:
			InkR.srand(800 + i)
			InkR.fill_poly([
				Vector2(bx - 12, by - 4), Vector2(bx + bw + 12, by - 6),
				Vector2(bx + bw + 8, by + bh + 4), Vector2(bx - 8, by + bh + 6)
			], InkR.rgba(156, 33, 41, 28), 1.0, 0.8)
			InkR.rect(bx, by, bw, bh, InkR.rgba(246, 237, 218, 245), InkR.RED, 2.2, 1.0, 1.0)
			InkR.line(bx + 16, by + 10, bx + 16, by + bh - 10, 4.0, InkR.RED, 1.0, 0.8)
		else:
			InkR.rect(bx, by, bw, bh, InkR.rgba(246, 237, 218, 200), InkR.rgba(23, 19, 15, 120), 1.4, 1.0, 0.8)

		InkR.text(labels[i], bx + bw * 0.5, by + bh * 0.5 + 7, 20 if sel else 18,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.RED if sel else InkR.INK, 1.0 if sel else 0.8, 2.0)

	if touch_mode or CTL.device == "touch":
		InkR.text(L10N.t("TITLE_TAP_SELECT"), 640, 646, 12,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.45, 1.5)
	else:
		InkR.text(L10N.t("TITLE_HINT"),
			640, 646, 11, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.5, 1.0)


func _title_menu_item_at(pos: Vector2) -> int:
	var bx := 440.0
	var bw := 400.0
	var bh := 48.0
	var start_y := 440.0
	for i in range(TITLE_MENU_ITEMS.size()):
		var by: float = start_y + i * 58.0
		if Rect2(bx - 10, by - 6, bw + 20, bh + 12).has_point(pos):
			return i
	return -1


func _render_settings() -> void:
	InkR.save()
	InkR.alpha_push(0.72)
	InkR.fill_rect_color(0, 0, W, H, InkR.PAPER)
	InkR.restore()

	InkR.radial_rect(0, 0, W, H, 640, 360, 760, [
		[0.0, InkR.rgba(60, 10, 14, 0)],
		[1.0, InkR.rgba(39, 8, 11, 87)]
	])

	var x := 370.0
	var y := 80.0
	var w := 540.0
	var h := 596.0
	InkHud.panel(x, y, w, h, L10N.t("SETTINGS_TITLE"), 28)

	InkR.text(L10N.t("SETTINGS_SUBTITLE"),
		x + w * 0.5, y + 80, 11, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.42, 1.0)

	var iy := y + 112.0
	var row_h := 46.0
	for i in range(SETTINGS_ITEMS.size()):
		var id: String = SETTINGS_ITEMS[i]
		var sel: bool = (i == settings_menu_index)
		var ry: float = iy + i * row_h

		if sel:
			InkR.srand(650 + i)
			InkR.fill_poly([
				Vector2(x + 28, ry - 14), Vector2(x + 36, ry + 16),
				Vector2(x + w - 28, ry + 13), Vector2(x + w - 36, ry - 12)
			], InkR.rgba(156, 33, 41, 31), 1.0, 0.8)
			InkR.fill_poly([
				Vector2(x + 38, ry - 7), Vector2(x + 50, ry),
				Vector2(x + 38, ry + 7), Vector2(x + 43, ry)
			], InkR.RED, 1.0, 0.5)

		var title_str := ""
		var val_str := ""
		var is_on := false

		if id == "lang":
			title_str = L10N.t("SET_LANG")
			val_str = L10N.lang_name().to_upper()
			is_on = true
		elif id == "sound":
			title_str = L10N.t("SET_SOUND")
			is_on = settings_sound
			val_str = L10N.t("VALUE_ON") if is_on else L10N.t("VALUE_OFF")
		elif id == "shake":
			title_str = L10N.t("SET_SHAKE")
			is_on = settings_shake
			val_str = L10N.t("VALUE_ON") if is_on else L10N.t("VALUE_OFF")
		elif id == "vibration":
			title_str = L10N.t("SET_VIBRATION")
			is_on = settings_vibration
			val_str = L10N.t("VALUE_ON") if is_on else L10N.t("VALUE_OFF")
		elif id == "touch":
			title_str = L10N.t("SET_TOUCH")
			if settings_touch == 0:
				val_str = L10N.t("VALUE_AUTO")
				is_on = true
			elif settings_touch == 1:
				val_str = L10N.t("VALUE_ON")
				is_on = true
			else:
				val_str = L10N.t("VALUE_OFF")
				is_on = false
		elif id == "hitboxes":
			title_str = L10N.t("SET_HITBOXES")
			is_on = debug_hitboxes
			val_str = L10N.t("VALUE_ON") if is_on else L10N.t("VALUE_OFF")
		elif id == "controls":
			title_str = L10N.t("SET_CONTROLS")
			val_str = "›"
		elif id == "bindings":
			title_str = L10N.t("SET_BINDINGS")
			val_str = "›"
		elif id == "back":
			title_str = L10N.t("UI_BACK")
			val_str = ""

		InkR.text(title_str, x + 56, ry + 7, 19 if sel else 18,
			InkR.F_BODY, InkR.A_LEFT, InkR.RED if sel else InkR.INK, 1.0 if sel else 0.75)

		if id == "controls" or id == "bindings":
			InkR.text(val_str, x + w - 50, ry + 7, 22,
				InkR.F_BODY, InkR.A_RIGHT, InkR.RED if sel else InkR.INK, 0.8 if sel else 0.4)
		elif id != "back":
			var badge_col: Color = InkR.RED if is_on else InkR.rgba(23, 19, 15, 70)
			# ширина плашки подстраивается под название языка (локализации бывают длинными)
			var badge_w: float = maxf(70.0, InkR.measure_text(val_str, 12) + 18.0)
			var badge_x: float = x + w - 50 - badge_w
			InkR.rect(badge_x, ry - 12, badge_w, 26,
				InkR.rgba(156, 33, 41, 24) if is_on else InkR.rgba(23, 19, 15, 12),
				badge_col, 1.2, 1.0, 0.5)
			InkR.text(val_str, badge_x + badge_w * 0.5, ry + 4, 12,
				InkR.F_BOLD, InkR.A_CENTER, badge_col, 1.0)

	InkR.line(x + 30, y + h - 54, x + w - 30, y + h - 54, 1.0, InkR.rgba(23, 19, 15, 46), 1.0, 0.8)
	var hint := L10N.t("SETTINGS_HINT_TOUCH") if (touch_mode or CTL.device == "touch") \
		else L10N.t("SETTINGS_HINT_KB")
	InkR.text(hint, x + w * 0.5, y + h - 26, 12,
		InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.6)


func _tap_settings(pos: Vector2) -> void:
	var x := 370.0
	var y := 80.0
	var w := 540.0
	var iy := y + 112.0
	var row_h := 46.0
	for i in range(SETTINGS_ITEMS.size()):
		var ry: float = iy + i * row_h
		if Rect2(x + 20, ry - 18, w - 40, row_h - 4).has_point(pos):
			settings_menu_index = i
			_toggle_setting(i)
			return


func _render_title_scene(t: float) -> void:
	# солнце
	var sx := 946.0
	var sy := 236.0
	var sr := 124.0
	var sun_pts: Array = []
	for i in range(30):
		var a: float = float(i) / 30.0 * InkR.TAU
		sun_pts.append(Vector2(sx + cos(a) * sr, sy + sin(a) * sr))
	InkR.srand(501)
	InkR.fill_poly(sun_pts, InkR.rgba(156, 33, 41, 230), 1.0, 2.2)
	InkR.hatch(sun_pts, 11, 0.12, InkR.INK)
	InkR.circle(sx, sy, sr, null, InkR.rgba(23, 19, 15, 140), 2.0, 1.0, 2.0, 30)

	_title_mountains(t)
	_title_figure(950, 622, t)

	InkR.srand(503)
	InkR.blob(1130, 640, 34, InkR.rgba(23, 19, 15, 41), null, 2.0, 1.0, 0.6, 10, 0.13, false, 2.0)
	InkR.blob(1164, 662, 12, InkR.rgba(23, 19, 15, 46), null, 2.0, 1.0, 0.6, 10, 0.13, false, 1.0)
	InkR.blob(1084, 670, 7, InkR.rgba(23, 19, 15, 36), null, 2.0, 1.0, 0.6, 10, 0.13, false, 1.0)

	InkR.srand(502)
	InkR.text(L10N.t("TITLE_LINE1"), 96, 238, 62, InkR.F_TITLE, InkR.A_LEFT, InkR.INK, 1.0, 2.0, 2.0)
	InkR.text(L10N.t("TITLE_LINE2"), 92, 344, 108, InkR.F_TITLE, InkR.A_LEFT, InkR.INK, 1.0, 4.0, 3.0)
	InkR.line(100, 364, 610, 364, 5.0, InkR.RED, 1.0, 2.2)
	InkR.line(104, 370, 560, 370, 1.5, InkR.rgba(23, 19, 15, 77), 1.0, 1.4)
	InkR.text(L10N.t("TITLE_SUBTITLE"), 102, 400, 14,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.6, 4.0)

	InkR.text(L10N.t("TITLE_VERSION"), 1240, 700, 11,
		InkR.F_HAND, InkR.A_RIGHT, InkR.CREAM, 0.55)


func _title_birds(t: float) -> void:
	var birds := [
		[742.0, 142.0, 0.9, 0.0], [806.0, 108.0, 0.7, 1.4], [862.0, 168.0, 0.55, 2.6]
	]
	InkR.srand(520)
	for b in birds:
		var flap: float = sin(t * 2.2 + b[3]) * 5
		InkR.poly([
			Vector2(b[0] - 12, b[1] + flap), Vector2(b[0], b[1]), Vector2(b[0] + 12, b[1] + flap)
		], 1.8 * b[2], InkR.rgba(23, 19, 15, 140), 1.0, 0.6)


func _title_mountains(_t: float) -> void:
	InkR.srand(530)

	var far := [
		Vector2(0, 600), Vector2(120, 538), Vector2(210, 572), Vector2(318, 498),
		Vector2(420, 556), Vector2(512, 514), Vector2(620, 574), Vector2(742, 522),
		Vector2(860, 566), Vector2(980, 508), Vector2(1104, 560), Vector2(1190, 522),
		Vector2(1280, 580), Vector2(1280, 720), Vector2(0, 720)
	]
	InkR.fill_poly(far, InkR.rgba(23, 19, 15, 41), 1.0, 2.0)
	InkR.poly(far, 1.2, InkR.rgba(23, 19, 15, 46), 1.0, 1.15, true)

	var mid := [
		Vector2(0, 652), Vector2(110, 606), Vector2(224, 638), Vector2(330, 590),
		Vector2(452, 646), Vector2(560, 602), Vector2(690, 650), Vector2(804, 604),
		Vector2(930, 648), Vector2(1040, 608), Vector2(1160, 652), Vector2(1280, 616),
		Vector2(1280, 720), Vector2(0, 720)
	]
	InkR.fill_poly(mid, InkR.rgba(23, 19, 15, 107), 1.0, 2.0)
	InkR.hatch(mid, 15, 0.1, InkR.CREAM)

	var near := [
		Vector2(0, 690), Vector2(140, 656), Vector2(250, 682), Vector2(360, 640),
		Vector2(480, 686), Vector2(600, 654), Vector2(738, 692), Vector2(862, 650),
		Vector2(986, 686), Vector2(1102, 646), Vector2(1210, 682), Vector2(1280, 660),
		Vector2(1280, 720), Vector2(0, 720)
	]
	InkR.fill_poly(near, InkR.rgba(23, 19, 15, 224), 1.0, 2.0)
	InkR.hatch(near, 13, 0.09, InkR.CREAM, 1.0, true)

	for i in range(9):
		var x: float = 60 + i * 146 + (i % 3) * 20
		var y: float = 640 + (i % 2) * 18
		InkR.poly([
			Vector2(x, y - 46), Vector2(x - 11, y), Vector2(x + 11, y)
		], 1.4, InkR.rgba(23, 19, 15, 191))
		InkR.line(x, y, x, y + 8, 2.0, InkR.rgba(23, 19, 15, 179))

	var blink: float = 0.5 + sin(title_t * 1.7) * 0.3
	InkR.save()
	InkR.alpha_push(0.55 * blink)
	InkR.circle(312, 668, 2.6, InkR.RED_BRIGHT, null, 2.0, 1.0, 0.3, 13, false)
	InkR.circle(324, 668, 2.6, InkR.RED_BRIGHT, null, 2.0, 1.0, 0.3, 13, false)
	InkR.restore()


func _title_figure(x: float, ground_y: float, t: float) -> void:
	InkR.save()
	InkR.t_translate(x, ground_y)
	InkR.t_scale(1.9, 1.9)

	InkR.srand(540)
	InkR.fill_poly([
		Vector2(-46, 0), Vector2(-34, -10), Vector2(-12, -13), Vector2(12, -8),
		Vector2(34, -12), Vector2(48, 0)
	], InkR.rgba(23, 19, 15, 230), 1.0, 1.5)

	var wave: float = sin(t * 2.2) * 4
	InkR.poly([
		Vector2(-4, -31), Vector2(-24, -35 + wave), Vector2(-42, -27 + wave * 1.4), Vector2(-56, -32 + wave)
	], 3.2, InkR.RED, 1.0, 0.8)
	InkR.poly([
		Vector2(-6, -28), Vector2(-26, -25 + wave * 0.6), Vector2(-40, -18 + wave)
	], 1.8, InkR.RED_DARK, 1.0, 0.8)

	var cloak := [
		Vector2(-12, -32), Vector2(9, -33), Vector2(13, -24), Vector2(15, -8),
		Vector2(11, -1), Vector2(4, -5), Vector2(-2, -2), Vector2(-8, -6), Vector2(-14, -11)
	]
	InkR.srand(541)
	InkR.fill_poly(cloak, InkR.rgba(20, 17, 14, 247), 1.0, 1.2)
	InkR.poly(cloak, 1.0, InkR.rgba(246, 237, 218, 56), 1.0, 1.0, true)

	var head := [
		Vector2(-9, -35), Vector2(-8, -44), Vector2(-1, -49), Vector2(6, -48),
		Vector2(12, -43), Vector2(12, -34), Vector2(6, -30), Vector2(-3, -31)
	]
	InkR.fill_poly(head, InkR.rgba(20, 17, 14, 250), 1.0, 0.9)
	InkR.poly(head, 1.0, InkR.rgba(246, 237, 218, 56), 1.0, 0.8, true)
	InkR.poly([Vector2(-2, -47), Vector2(-6, -56), Vector2(-9, -62)], 2.4, InkR.rgba(20, 17, 14, 250), 1.0, 0.4)
	InkR.poly([Vector2(8, -47), Vector2(11, -55), Vector2(14, -60)], 2.4, InkR.rgba(20, 17, 14, 250), 1.0, 0.4)
	InkR.blob(6, -39, 1.9, InkR.RED_BRIGHT, null, 2.0, 1.0, 0.5, 10, 0.25, false)

	InkR.line(10, -25, 23, -9, 3.0, InkR.rgba(20, 17, 14, 250))
	InkR.line(22, -10, 31, 1, 4.6, InkR.rgba(20, 17, 14, 250))
	InkR.line(19, -13, 24, -8, 1.4, InkR.RED)

	InkR.alpha_push(0.25)
	InkR.poly([Vector2(-12, -32), Vector2(-14, -11), Vector2(-8, -6)], 1.4, InkR.CREAM)
	InkR.alpha_pop()
	InkR.ellipse_shadow(0, 2, 34, 6, 0.22)
	InkR.restore()


# ---------- пауза ----------

func _render_pause() -> void:
	InkR.save()
	InkR.alpha_push(0.72)
	InkR.fill_rect_color(0, 0, 1280, 720, InkR.PAPER)
	InkR.restore()

	InkR.radial_rect(0, 0, 1280, 720, 640, 340, 760, [
		[0.0, InkR.rgba(60, 10, 14, 0)],
		[1.0, InkR.rgba(39, 8, 11, 87)]
	])

	if submenu == "controls":
		_render_controls()
		return
	elif submenu == "settings":
		_render_settings()
		return
	elif submenu == "bindings":
		_render_bindings()
		return

	var x := 400.0
	var y := 108.0
	var w := 480.0
	var h := 474.0
	InkHud.panel(x, y, w, h, L10N.t("PAUSE_TITLE"), 30)

	InkR.text(L10N.t("PAUSE_STATS", [_fmt_time(run_time), kills, max_combo]),
		x + w / 2, y + 82, 11, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.42, 1.0)

	var labels := [
		L10N.t("PAUSE_RESUME"),
		L10N.t("PAUSE_RESTART"),
		L10N.t("PAUSE_SETTINGS"),
		L10N.t("PAUSE_CONTROLS"),
		L10N.t("PAUSE_QUIT"),
	]

	var iy := y + 134.0
	for i in range(MENU_ITEMS.size()):
		var id: String = MENU_ITEMS[i]
		var sel := i == menu_index
		if sel:
			InkR.srand(600 + i)
			InkR.fill_poly([
				Vector2(x + 34, iy - 14), Vector2(x + 40, iy + 14),
				Vector2(x + w - 34, iy + 11), Vector2(x + w - 40, iy - 12)
			], InkR.rgba(156, 33, 41, 31), 1.0, 0.8)
			InkR.fill_poly([
				Vector2(x + 44, iy - 7), Vector2(x + 56, iy),
				Vector2(x + 44, iy + 7), Vector2(x + 49, iy)
			], InkR.RED, 1.0, 0.5)
		InkR.text(labels[i], x + 62, iy + 7, 21 if sel else 20,
			InkR.F_BODY, InkR.A_LEFT, InkR.RED if sel else InkR.INK, 1.0 if sel else 0.72)
		if id == "settings" or id == "controls":
			InkR.text("›", x + w - 56, iy + 6, 24,
				InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.7 if sel else 0.3)
		iy += 50

	InkR.line(x + 30, y + h - 58, x + w - 30, y + h - 58, 1.0, InkR.rgba(23, 19, 15, 46), 1.0, 0.8)
	var hint := L10N.t("PAUSE_HINT_TOUCH") if (touch_mode or CTL.device == "touch") \
		else (L10N.t("PAUSE_HINT_PAD") if CTL.device == "gamepad" \
		else L10N.t("PAUSE_HINT_KB"))
	InkR.text(hint, x + w / 2, y + h - 32, 12,
		InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.62)


func _draw_pause_touch_ui() -> void:
	var c: Vector2 = TOUCH_RECTS["pause"]
	var r: float = 56.0
	InkR.blob(c.x, c.y, r, InkR.rgba(156, 33, 41, 60), InkR.rgba(246, 237, 218, 220), 2.2, 1.0, 0.35, 12, 0.06)
	InkR.line(c.x - 9, c.y - 13, c.x - 9, c.y + 13, 4.0, InkR.CREAM, 1.0, 0.2)
	InkR.line(c.x + 9, c.y - 13, c.x + 9, c.y + 13, 4.0, InkR.CREAM, 1.0, 0.2)


func _render_controls() -> void:
	var x := 170.0
	var y := 40.0
	var w := 940.0
	var h := 636.0
	if touch_mode or CTL.device == "touch":
		_render_touch_controls(x, y, w, h)
		return
	InkHud.panel(x, y, w, h, L10N.t("CONTROLS_TITLE"), 28)

	InkR.text(L10N.t("COL_ACTION"), x + 52, y + 96, 10, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	InkR.text(L10N.t("COL_KEYBOARD"), x + 420, y + 96, 10, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	InkR.text(L10N.t("COL_GAMEPAD"), x + 590, y + 96, 10, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)

	var rows := [
		[L10N.t("ACT_MOVE"), CTL.label_move(), L10N.t("KEY_STICK")],
		[L10N.t("ACT_JUMP"), CTL.label_key("jump"), CTL.label_pad("jump")],
		[L10N.t("ACT_ATTACK"), CTL.label_key("attack"), CTL.label_pad("attack")],
		[L10N.t("ACT_DASH"), CTL.label_key("dash"), CTL.label_pad("dash")],
		[L10N.t("ACT_HEAL"), CTL.label_key("heal"), CTL.label_pad("heal")],
		[L10N.t("ACT_PAUSE"), CTL.label_key("pause"), CTL.label_pad("pause")],
		[L10N.t("ACT_RESTART"), CTL.label_key("restart"), CTL.label_pad("restart")],
		[L10N.t("ACT_DEBUG"), CTL.label_key("hitboxes"), "—"],
	]

	var ry := y + 126.0
	for i in range(rows.size()):
		var r: Array = rows[i]
		if i % 2 == 0:
			InkR.rect(x + 28, ry - 14, w - 56, 32, InkR.rgba(23, 19, 15, 9),
				InkR.rgba(23, 19, 15, 13), 0.5, 1.0, 0.5)
		InkR.text(r[0], x + 52, ry + 6, 15, InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.85)
		if r[1] != "—":
			InkHud.glyph(x + 420, ry, r[1], false, 22, 10, 7)
		else:
			InkR.text("—", x + 420, ry + 6, 14, InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.3)
		if r[2] != "—":
			InkHud.glyph(x + 590, ry, r[2], false, 22, 10, 7)
		else:
			InkR.text("—", x + 590, ry + 6, 14, InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.3)
		ry += 33

	InkR.line(x + 690, y + 88, x + 690, y + 424, 1.0, InkR.rgba(23, 19, 15, 31), 1.0, 0.8)
	InkR.text(L10N.t("INPUT_TEST"), x + 720, y + 118, 10,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)

	var snap: Dictionary = CTL.snapshot()
	var btn_labels := ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "⌗", "▶"]
	for i in range(btn_labels.size()):
		var col := i % 5
		var rowi := i / 5
		var bx: float = x + 748 + col * 42
		var by: float = y + 156 + rowi * 40
		var on: bool = i < snap.buttons.size() and bool(snap.buttons[i])
		InkR.srand(700 + i)
		InkR.circle(bx, by, 12, InkR.RED if on else InkR.rgba(246, 237, 218, 153),
			InkR.RED_DARK if on else InkR.rgba(23, 19, 15, 89), 1.4, 1.0, 0.6, 10)
		InkR.text(btn_labels[i], bx, by + 1, 9, InkR.F_BOLD, InkR.A_CENTER,
			InkR.CREAM if on else InkR.rgba(23, 19, 15, 140), 1.0, 0.0, 0.0, 1)

	var sx := 960.0
	var sy := 282.0
	InkR.rect(sx - 34, sy - 26, 68, 52, InkR.rgba(23, 19, 15, 8),
		InkR.rgba(23, 19, 15, 56), 1.1, 1.0, 0.6)
	InkR.line(sx - 28, sy, sx + 28, sy, 1.0, InkR.rgba(23, 19, 15, 46))
	InkR.line(sx, sy - 20, sx, sy + 20, 1.0, InkR.rgba(23, 19, 15, 46))
	var ax: float = snap.axes[0] if snap.axes.size() > 0 else 0.0
	var ay: float = snap.axes[1] if snap.axes.size() > 1 else 0.0
	InkR.circle(sx + ax * 26, sy + ay * 18, 4.4, InkR.RED, InkR.RED_DARK, 1.0, 1.0, 0.4, 8)
	InkR.text(L10N.t("KEY_STICK"), sx, sy + 40, 9, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.45)

	InkR.text(L10N.t("PAD_CONNECTED") if snap.connected else L10N.t("PAD_MISSING"),
		x + 720, y + 362, 11, InkR.F_DISPLAY, InkR.A_LEFT,
		InkR.INK if snap.connected else InkR.RED, 0.7, 1.0)
	InkR.text(snap.id if snap.connected else L10N.t("PAD_PRESS_ANY"),
		x + 720, y + 378, 10, InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.45)
	InkR.text(L10N.t("CONTROLS_VERSION"), x + 720, y + 398, 10,
		InkR.F_HAND, InkR.A_LEFT, InkR.INK, 0.5)

	InkR.line(x + 34, y + 430, x + w - 34, y + 430, 1.0, InkR.rgba(23, 19, 15, 51), 1.0, 0.8)

	var notes := [
		L10N.t("CONTROLS_NOTE_1"),
		L10N.t("CONTROLS_NOTE_2"),
		L10N.t("CONTROLS_NOTE_3"),
	]
	for i in range(notes.size()):
		InkR.text(notes[i], x + w / 2, y + 456 + i * 24, 13,
			InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.72)

	InkR.line(x + 34, y + 526, x + w - 34, y + 526, 1.2, InkR.rgba(156, 33, 41, 89), 1.0, 0.8, [6.0, 6.0])
	InkR.text(L10N.t("CONTROLS_BACK"), x + 52, y + h - 26, 11,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 2.0)
	InkR.text(L10N.t("CONTROLS_CLOSE", [CTL.first_key_label("help")]), x + w - 52, y + h - 26, 11,
		InkR.F_DISPLAY, InkR.A_RIGHT, InkR.INK, 0.45, 1.0)


func _render_touch_controls(x: float, y: float, w: float, h: float) -> void:
	InkHud.panel(x, y, w, h, L10N.t("TOUCH_CONTROLS_TITLE"), 28)
	InkR.text(L10N.t("COL_ACTION"), x + 90, y + 96, 10, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	InkR.text(L10N.t("TOUCH_COL_BUTTON"), x + 540, y + 96, 10, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	var rows := [
		[L10N.t("TOUCH_MOVE"), L10N.t("KEY_STICK")],
		[L10N.t("TOUCH_JUMP"), "A"],
		[L10N.t("TOUCH_ATTACK"), "X"],
		[L10N.t("TOUCH_DASH"), "B"],
		[L10N.t("TOUCH_HEAL"), "Y"],
		[L10N.t("TOUCH_PAUSE"), "Ⅱ"],
	]
	var ry: float = y + 132.0
	for i in range(rows.size()):
		if i % 2 == 0:
			InkR.rect(x + 54, ry - 18, w - 108, 42, InkR.rgba(23, 19, 15, 9),
				InkR.rgba(23, 19, 15, 13), 0.5, 1.0, 0.5)
		InkR.text(rows[i][0], x + 90, ry + 8, 16, InkR.F_BODY, InkR.A_LEFT, InkR.INK, 0.88)
		InkHud.glyph(x + 540, ry, rows[i][1], false, 32, 14, 10)
		ry += 52

	InkR.line(x + 54, y + 472, x + w - 54, y + 472, 1.2, InkR.rgba(156, 33, 41, 89), 1.0, 0.8)
	InkR.text(L10N.t("TOUCH_TIP"),
		x + w / 2, y + 508, 14, InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.72)

	var bx := x + w * 0.5 - 110.0
	var by := y + h - 56.0
	var bw := 220.0
	var bh := 42.0
	InkR.rect(bx, by, bw, bh, InkR.rgba(246, 237, 218, 240), InkR.rgba(23, 19, 15, 180), 1.6, 1.0, 0.8)
	InkR.text(L10N.t("UI_BACK"), x + w * 0.5, by + bh * 0.5 + 5, 16,
		InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.9, 1.5)


# ---------- назначение клавиш ----------

const BIND_PANEL := Rect2(170, 40, 940, 636)
const BIND_ROW_H := 28.0
const BIND_ROWS_Y := 120.0
const BIND_KEY_X := 470.0
const BIND_PAD_X := 690.0
const BIND_CELL_W := 180.0
const BIND_CAPTURE_MAX := 10.0
const BIND_MOVE := ["left", "right", "up", "down"]


func _bind_last() -> int:
	return CTL.BINDABLE.size() + 1


func _bind_is_fixed(a: String) -> bool:
	return a in BIND_MOVE


func _bind_action_name(a: String) -> String:
	match a:
		"left": return L10N.t("ACT_LEFT")
		"right": return L10N.t("ACT_RIGHT")
		"up": return L10N.t("ACT_UP")
		"down": return L10N.t("ACT_DOWN")
		"jump": return L10N.t("ACT_JUMP")
		"attack": return L10N.t("ACT_ATTACK")
		"dash": return L10N.t("ACT_DASH")
		"heal": return L10N.t("ACT_HEAL")
		"pause": return L10N.t("ACT_PAUSE")
		"restart": return L10N.t("ACT_RESTART")
		"help": return L10N.t("ACT_HELP")
		"hitboxes": return L10N.t("ACT_DEBUG")
		"mute": return L10N.t("ACT_MUTE")
		"fullscreen": return L10N.t("ACT_FULLSCREEN")
		"screenshot": return L10N.t("ACT_SCREENSHOT")
	return a


func _update_bindings(dt: float) -> void:
	# после захвата клавиши гасим навигацию, иначе та же кнопка сразу
	# запустила бы новое назначение
	if bind_lock_t > 0.0:
		bind_lock_t = maxf(0.0, bind_lock_t - dt)
		return
	if bind_notice_t > 0.0:
		bind_notice_t = maxf(0.0, bind_notice_t - dt)
	if bind_capture:
		bind_capture_t += dt
		if bind_capture_t >= BIND_CAPTURE_MAX:
			bind_capture = false
			bind_capture_t = 0.0
			bind_notice = L10N.t("BIND_CANCELLED")
			bind_notice_t = 1.6
			SND.ui()
		return
	if CTL.pressed("pause"):
		_close_bindings()
		return
	var n: int = _bind_last() + 1
	if CTL.pressed("up"):
		bind_menu_index = (bind_menu_index - 1 + n) % n
		SND.ui()
	elif CTL.pressed("down"):
		bind_menu_index = (bind_menu_index + 1) % n
		SND.ui()
	if bind_menu_index < CTL.BINDABLE.size():
		if CTL.pressed("left") and bind_col != 0:
			bind_col = 0
			SND.ui()
		elif CTL.pressed("right") and bind_col != 1:
			bind_col = 1
			SND.ui()
	if CTL.confirm():
		_activate_bind_row()


func _activate_bind_row() -> void:
	if bind_menu_index == CTL.BINDABLE.size():
		CTL.reset_bindings()
		_save_settings()
		bind_notice = L10N.t("BIND_RESET_DONE")
		bind_notice_t = 2.2
		SND.ui_confirm()
		return
	if bind_menu_index > CTL.BINDABLE.size():
		_close_bindings()
		return
	var a: String = CTL.BINDABLE[bind_menu_index]
	if bind_col == 1 and _bind_is_fixed(a):
		bind_notice = L10N.t("BIND_FIXED")
		bind_notice_t = 2.2
		SND.ui()
		return
	_start_capture()


func _close_bindings() -> void:
	bind_capture = false
	bind_capture_t = 0.0
	bind_lock_t = 0.0
	if state == "title":
		title_submenu = "settings"
	else:
		submenu = "settings"
	settings_menu_index = SETTINGS_ITEMS.find("bindings")
	SND.ui()


func _start_capture() -> void:
	bind_capture = true
	bind_capture_t = 0.0
	bind_lock_t = 0.12
	bind_notice = ""
	bind_notice_t = 0.0
	SND.ui()


func _cancel_capture() -> void:
	bind_capture = false
	bind_capture_t = 0.0
	bind_lock_t = 0.2
	SND.ui()


func _finish_capture(ok: bool) -> void:
	bind_capture = false
	bind_capture_t = 0.0
	bind_lock_t = 0.25
	if ok:
		_save_settings()
		bind_notice = ""
		bind_notice_t = 0.0
		SND.ui_confirm()
	else:
		bind_notice_t = 2.2
		SND.ui()


func _apply_key_capture(code: int) -> void:
	var a: String = CTL.BINDABLE[bind_menu_index]
	var ok: bool = CTL.set_key(a, code)
	if not ok:
		bind_notice = L10N.t("BIND_RESERVED")
	_finish_capture(ok)


func _apply_pad_capture(slot: int) -> void:
	var a: String = CTL.BINDABLE[bind_menu_index]
	var ok: bool = CTL.set_pad(a, slot)
	if not ok:
		bind_notice = L10N.t("BIND_FIXED")
	_finish_capture(ok)


## Возвращает true, если событие поглощено экраном назначений.
func _handle_bind_capture(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = int(event.physical_keycode)
		if code == 0:
			code = int(event.keycode)
		if code == KEY_ESCAPE:
			_cancel_capture()
			return true
		if bind_col != 0:
			return false
		_apply_key_capture(code)
		return true
	if event is InputEventJoypadButton and event.pressed:
		if bind_col != 1:
			return false
		var slot: int = CTL.slot_of_joy(event.button_index)
		if slot < 0:
			bind_notice = L10N.t("BIND_UNSUPPORTED")
			_finish_capture(false)
		else:
			_apply_pad_capture(slot)
		return true
	if event is InputEventJoypadMotion and bind_col == 1:
		if absf(event.axis_value) < 0.55:
			return false
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			_apply_pad_capture(6)
			return true
		if event.axis == JOY_AXIS_TRIGGER_RIGHT:
			_apply_pad_capture(7)
			return true
		return false
	if event is InputEventScreenTouch and event.pressed:
		_cancel_capture()
		return true
	if event is InputEventMouseButton and event.pressed:
		_cancel_capture()
		return true
	return false


func _render_bindings() -> void:
	var x := BIND_PANEL.position.x
	var y := BIND_PANEL.position.y
	var w := BIND_PANEL.size.x
	var h := BIND_PANEL.size.y
	InkHud.panel(x, y, w, h, L10N.t("BIND_TITLE"), 28)

	InkR.text(L10N.t("BIND_SUBTITLE"), x + w * 0.5, y + 76, 11,
		InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.42, 1.0)

	InkR.text(L10N.t("COL_ACTION"), x + 52, y + 100, 10,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	InkR.text(L10N.t("COL_KEYBOARD"), x + BIND_KEY_X, y + 100, 10,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)
	InkR.text(L10N.t("COL_GAMEPAD"), x + BIND_PAD_X, y + 100, 10,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55, 3.0)

	for i in range(CTL.BINDABLE.size()):
		var a: String = CTL.BINDABLE[i]
		var ry: float = y + BIND_ROWS_Y + i * BIND_ROW_H
		var sel: bool = (i == bind_menu_index)
		if i % 2 == 0:
			InkR.rect(x + 28, ry - 13, w - 56, 26, InkR.rgba(23, 19, 15, 9),
				InkR.rgba(23, 19, 15, 13), 0.5, 1.0, 0.5)
		if sel:
			InkR.srand(900 + i)
			InkR.fill_poly([
				Vector2(x + 34, ry - 11), Vector2(x + 46, ry - 8),
				Vector2(x + 41, ry + 12), Vector2(x + 32, ry + 9)
			], InkR.rgba(156, 33, 41, 40), 1.0, 0.8)
		InkR.text(_bind_action_name(a), x + 56, ry + 5, 14,
			InkR.F_BODY, InkR.A_LEFT, InkR.RED if sel else InkR.INK, 1.0 if sel else 0.78)
		_draw_bind_cell(a, 0, x + BIND_KEY_X, ry, sel and bind_col == 0)
		_draw_bind_cell(a, 1, x + BIND_PAD_X, ry, sel and bind_col == 1)

	var fy: float = y + BIND_ROWS_Y + CTL.BINDABLE.size() * BIND_ROW_H + 14.0
	InkR.line(x + 34, fy - 8, x + w - 34, fy - 8, 1.0,
		InkR.rgba(23, 19, 15, 46), 1.0, 0.8)
	_draw_bind_button(Rect2(x + 52, fy, 240, 38), L10N.t("BIND_RESET"),
		bind_menu_index == CTL.BINDABLE.size())
	_draw_bind_button(Rect2(x + w - 52 - 240, fy, 240, 38), L10N.t("UI_BACK"),
		bind_menu_index > CTL.BINDABLE.size())

	if bind_notice_t > 0.0 and bind_notice != "":
		var na: float = clampf(bind_notice_t / 0.5, 0.0, 1.0)
		InkR.text(bind_notice, x + w * 0.5, y + h - 16, 12,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.RED, na, 1.0)
	else:
		var hint := L10N.t("BIND_HINT_TOUCH") if (touch_mode or CTL.device == "touch") \
			else (L10N.t("BIND_HINT_PAD") if CTL.device == "gamepad" else L10N.t("BIND_HINT_KB"))
		InkR.text(hint, x + w * 0.5, y + h - 16, 11,
			InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.55)

	if bind_capture:
		_draw_bind_capture()


func _draw_bind_cell(a: String, col: int, cx: float, cy: float, active: bool) -> void:
	var fixed: bool = _bind_is_fixed(a)
	var text: String = CTL.label_key(a) if col == 0 else CTL.label_pad(a)
	var alpha := 0.82
	if col == 1 and fixed:
		alpha = 0.45
	if active:
		InkR.rect(cx - 8, cy - 12, BIND_CELL_W, 24, InkR.rgba(156, 33, 41, 22),
			InkR.RED, 1.3, 1.0, 0.6)
		alpha = 1.0
	InkR.text(text, cx, cy + 5, 13, InkR.F_BOLD, InkR.A_LEFT,
		InkR.RED if active else InkR.INK, alpha)


func _draw_bind_button(r: Rect2, text: String, sel: bool) -> void:
	InkR.rect(r.position.x, r.position.y, r.size.x, r.size.y,
		InkR.rgba(156, 33, 41, 30) if sel else InkR.rgba(246, 237, 218, 200),
		InkR.RED if sel else InkR.rgba(23, 19, 15, 120), 1.6 if sel else 1.2, 1.0, 0.8)
	InkR.text(text, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 6, 15,
		InkR.F_DISPLAY, InkR.A_CENTER, InkR.RED if sel else InkR.INK,
		1.0 if sel else 0.8, 1.5)


func _draw_bind_capture() -> void:
	InkR.save()
	InkR.alpha_push(0.55)
	InkR.fill_rect_color(0, 0, W, H, InkR.rgba(17, 12, 9, 255))
	InkR.restore()

	var pw := 640.0
	var ph := 220.0
	var px := (W - pw) * 0.5
	var py := (H - ph) * 0.5
	InkHud.panel(px, py, pw, ph, L10N.t("BIND_TITLE"), 24)

	var idx: int = clampi(bind_menu_index, 0, CTL.BINDABLE.size() - 1)
	InkR.text(_bind_action_name(CTL.BINDABLE[idx]), px + pw * 0.5, py + 86, 26,
		InkR.F_DISPLAY, InkR.A_CENTER, InkR.RED, 1.0, 1.5)
	InkR.text(L10N.t("BIND_PRESS"), px + pw * 0.5, py + 120, 14,
		InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.85, 1.0)
	InkR.text(L10N.t("BIND_CANCEL"), px + pw * 0.5, py + 146, 11,
		InkR.F_HAND, InkR.A_CENTER, InkR.INK, 0.55)

	var k: float = clampf(1.0 - bind_capture_t / BIND_CAPTURE_MAX, 0.0, 1.0)
	InkR.rect(px + 90, py + 168, pw - 180, 6, InkR.rgba(23, 19, 15, 20),
		InkR.rgba(23, 19, 15, 60), 1.0, 1.0, 0.5)
	InkR.rect(px + 90, py + 168, (pw - 180) * k, 6, InkR.rgba(156, 33, 41, 190),
		null, 0.0, 1.0, 0.5)


func _tap_bindings(pos: Vector2) -> void:
	if bind_capture:
		_cancel_capture()
		return
	var x := BIND_PANEL.position.x
	var y := BIND_PANEL.position.y
	var w := BIND_PANEL.size.x
	for i in range(CTL.BINDABLE.size()):
		var ry: float = y + BIND_ROWS_Y + i * BIND_ROW_H
		if Rect2(x + 34, ry - 13, w - 68, 26).has_point(pos):
			bind_menu_index = i
			if pos.x >= x + BIND_PAD_X - 10:
				bind_col = 1
			elif pos.x >= x + BIND_KEY_X - 10:
				bind_col = 0
			_activate_bind_row()
			return
	var fy: float = y + BIND_ROWS_Y + CTL.BINDABLE.size() * BIND_ROW_H + 14.0
	if Rect2(x + 52, fy, 240, 38).has_point(pos):
		bind_menu_index = CTL.BINDABLE.size()
		_activate_bind_row()
		return
	if Rect2(x + w - 52 - 240, fy, 240, 38).has_point(pos):
		bind_menu_index = CTL.BINDABLE.size() + 1
		_activate_bind_row()
		return
	if not BIND_PANEL.has_point(pos):
		_close_bindings()


# ---------- смерть и отладка ----------

func _render_death() -> void:
	InkR.save()
	InkR.alpha_push(0.75)
	InkR.fill_rect_color(0, 0, 1280, 720, InkR.rgba(17, 12, 9, 255))
	InkR.restore()

	InkR.radial_rect(0, 0, 1280, 720, 640, 320, 560, [
		[0.0, InkR.rgba(120, 20, 28, 84)],
		[1.0, InkR.rgba(120, 20, 28, 0)]
	])

	InkR.radial_rect(0, 500, 1280, 220, 640, 575, 520, [
		[0.0, InkR.rgba(17, 12, 9, 175)],
		[0.6, InkR.rgba(17, 12, 9, 80)],
		[1.0, InkR.rgba(17, 12, 9, 0)]
	])

	InkR.srand(801)
	InkR.blob(470, 300, 120, InkR.rgba(120, 25, 30, 64), null, 2.0, 1.0, 0.6, 10, 0.13, false, 4.0)
	InkR.blob(840, 280, 90, InkR.rgba(120, 25, 30, 51), null, 2.0, 1.0, 0.6, 10, 0.13, false, 4.0)
	InkR.blob(640, 330, 210, InkR.rgba(20, 15, 11, 205), null, 2.0, 1.0, 0.6, 10, 0.13, false, 3.0)

	InkR.text(L10N.t("DEATH_TITLE"), 640, 276, 44,
		InkR.F_TITLE, InkR.A_CENTER, InkR.CREAM, 1.0, 0.0, 2.0)
	InkR.line(400, 298, 880, 298, 3.0, InkR.RED, 1.0, 1.8)
	InkR.text(L10N.t("DEATH_SUB"), 640, 328, 17,
		InkR.F_HAND, InkR.A_CENTER, InkR.CREAM, 0.55)
	InkR.text(L10N.t("DEATH_STATS", [_fmt_time(run_time), kills, max_combo]),
		640, 376, 13, InkR.F_DISPLAY, InkR.A_CENTER, InkR.CREAM, 0.6, 1.0)

	var pulse: float = 0.75 + sin(clock * 3.4) * 0.25
	if touch_mode or CTL.device == "touch":
		var rx := 440.0
		var ry := 456.0
		var rw := 400.0
		var rh := 50.0
		InkR.rect(rx, ry, rw, rh, InkR.rgba(156, 33, 41, 210), InkR.RED, 2.2, 1.0, 0.8)
		InkR.text(L10N.t("DEATH_REBIRTH"), 640, ry + 32, 21,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.CREAM, pulse, 2.0)

		var mx := 480.0
		var my := 524.0
		var mw := 320.0
		var mh := 44.0
		InkR.rect(mx, my, mw, mh, InkR.rgba(23, 19, 15, 170), InkR.rgba(246, 237, 218, 120), 1.4, 1.0, 0.8)
		InkR.text(L10N.t("DEATH_MENU"), 640, my + 28, 16,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.CREAM, 0.85, 1.0)
	else:
		InkR.text(L10N.t("DEATH_HINT_REBIRTH"), 640, 520, 20,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.CREAM, pulse, 2.0)
		InkR.text(L10N.t("DEATH_HINT_MENU"), 640, 560, 14,
			InkR.F_DISPLAY, InkR.A_CENTER, InkR.CREAM, 0.7, 1.5)

	InkR.text(L10N.t("DEATH_TAGLINE"), 640, 642, 13,
		InkR.F_HAND, InkR.A_CENTER, InkR.CREAM, 0.4)


func _render_death_fade() -> void:
	# Ink.Alpha = a * 0.6; FillRectColor(...)
	var a: float = clampf(death_delay / 1.1, 0, 1) * 0.6
	InkR.fill_rect_color(0, 0, 1280, 720, InkR.rgba(18, 13, 10, 255), a)


func _render_debug() -> void:
	for s in InkWorld.solids:
		_dbg_box(s.position.x, s.position.y, s.size.x, s.size.y, InkR.rgba(44, 111, 107, 102))
	for s in InkWorld.oneways:
		_dbg_box(s.position.x, s.position.y, s.size.x, s.size.y, InkR.rgba(44, 111, 107, 64))
	var phb: Rect2 = player.hitbox()
	_dbg_box(phb.position.x, phb.position.y, phb.size.x, phb.size.y, InkR.rgba(31, 122, 58, 255))
	_dbg_box(player.x, player.y, player.w, player.h, InkR.rgba(31, 122, 58, 200))
	if player.attack != null and player.attack_active():
		var ahb: Rect2 = player.attack_hitbox()
		_dbg_box(ahb.position.x, ahb.position.y, ahb.size.x, ahb.size.y, InkR.rgba(184, 146, 63, 255))
	for e in enemies:
		if e.dead:
			continue
		var hb: Rect2 = e.hitbox()
		_dbg_box(hb.position.x, hb.position.y, hb.size.x, hb.size.y, InkR.rgba(156, 33, 41, 230))
	for pr in projectiles:
		if pr.dead:
			continue
		var hb: Rect2 = pr.hitbox()
		_dbg_box(hb.position.x, hb.position.y, hb.size.x, hb.size.y, InkR.rgba(156, 33, 41, 230))

	InkR.text("HITBOXES · %d FPS" % fps, 44, 178, 10,
		InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.5, 2.0)


func _dbg_box(x: float, y: float, w: float, h: float, col: Color) -> void:
	# Ink.Rect(x, y, w, h, null, color, 1.2f, 1f, 0f, true, [5, 4])
	InkR.rect(x, y, w, h, null, col, 1.2, 1.0, 0.0, true, [5.0, 4.0])


func _fmt_time(seconds: float) -> String:
	var s: float = maxf(0, seconds)
	var m := int(s / 60.0)
	var rest := int(s) % 60
	return "%d:%02d" % [m, rest]


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	SND.ui()


func _save_screenshot() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("screenshots")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://screenshots/ink-blade-%s.png" % stamp
	var image := get_viewport().get_texture().get_image()
	if image != null and image.save_png(path) == OK:
		SND.ui_confirm()


# ---------- запекание ----------

func _bake_all() -> void:
	_baking = true
	await _bake_paper()
	await _bake_stage()
	await _bake_title()
	_baking = false


## Перезапекает слои с текстом после смены языка. Если язык меняют несколько
## раз подряд, лишние проходы схлопываются в один.
func _request_rebake() -> void:
	_rebake_pending = true
	if _rebaking:
		return
	_rebaking = true
	while _rebake_pending:
		_rebake_pending = false
		InkR.tex_stage = null
		InkR.tex_title = null
		await _bake_stage()
		await _bake_title()
	_rebaking = false


func _bake_image(size: Vector2i, draw_fn: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	var node := InkBakeNode.new()
	node.w = float(size.x)
	node.h = float(size.y)
	node.fn = draw_fn
	vp.add_child(node)
	add_child(vp)
	# ждём по крайней мере один кадр отрисовки
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


func _bake_paper() -> void:
	var img := await _bake_image(Vector2i(1280, 720),
		func(cv): InkR.bake_paper(cv))
	InkR.tex_paper = ImageTexture.create_from_image(img)


func _bake_stage() -> void:
	var pad := float(InkWorld.PAD)
	var img := await _bake_image(
		Vector2i(1280 + int(pad) * 2, 720 + int(pad) * 2),
		func(cv): InkWorld.bake_stage(cv))
	InkR.tex_stage = ImageTexture.create_from_image(img)


func _bake_title() -> void:
	var img := await _bake_image(Vector2i(1280, 720), func(cv): _bake_title_frame(cv))
	InkR.tex_title = ImageTexture.create_from_image(img)


func _bake_title_frame(cv) -> void:
	InkR.set_canvas(cv)
	if InkR.tex_paper != null:
		InkR.paper()
	else:
		InkR.fill_rect_color(0, 0, 1280, 720, InkR.PAPER, 1.0)
	_render_title_scene(0.0)
	InkR.vignette()


# ---------- тач-UI ----------

func _zone_action(pos: Vector2) -> String:
	# Проверяем расстояние до центров кнопок с запасом радиуса (круговая зона удобнее пальцу)
	for a in TOUCH_RECTS:
		var c: Vector2 = TOUCH_RECTS[a]
		var r: float = (TOUCH_ZONES[a] as Rect2).size.x * 0.5
		if pos.distance_to(c) <= r * 1.3:
			return a
	for a in TOUCH_ZONES:
		if (TOUCH_ZONES[a] as Rect2).has_point(pos):
			return a
	return ""


func _touch_stop() -> void:
	# сброс всех касаний (при смене состояния)
	if _stick_id != -1:
		_stick_id = -1
		_stick_vec = Vector2.ZERO
		CTL.stick_end()
	for idx in Array(_pointers.keys()):
		var a: String = _pointers[idx]
		_pointers.erase(idx)
		if a != "" and a != "stick":
			CTL.touch_exit(a)
	_pointers.clear()


func _touch_canvas_pos(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp != null:
		var xform: Transform2D = vp.get_canvas_transform()
		if not is_zero_approx(xform.determinant()):
			var p: Vector2 = xform.affine_inverse() * screen_pos
			if p.x >= -60.0 and p.x <= W + 60.0 and p.y >= -60.0 and p.y <= H + 60.0:
				return p
	var win_size: Vector2 = Vector2(DisplayServer.window_get_size())
	if win_size.x > 0.0 and win_size.y > 0.0:
		return Vector2(screen_pos.x * W / win_size.x, screen_pos.y * H / win_size.y)
	return screen_pos


func _extra_canvas_width() -> float:
	return 0.0


func _touch_zone_action(screen_pos: Vector2) -> String:
	var a := _zone_action(_touch_canvas_pos(screen_pos))
	if a != "":
		return a
	if screen_pos.x >= 0.0 and screen_pos.x <= W and screen_pos.y >= 0.0 and screen_pos.y <= H:
		return _zone_action(screen_pos)
	return ""


func _input(event: InputEvent) -> void:
	# экран назначений перехватывает ввод целиком, пока ждёт клавишу
	if bind_capture:
		if _handle_bind_capture(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if settings_touch != 2:
			touch_mode = true
		CTL.device = "touch"
		var idx: int = event.index
		var pos: Vector2 = _touch_canvas_pos(event.position)
		if event.pressed:
			SND.unlock()
			if state == "play":
				var a := _touch_zone_action(event.position)
				if a == "pause":
					_open_pause(null)
					return
				elif a != "":
					_pointers[idx] = a
					CTL.touch_enter(a)
					CTL.touch_tap(a)
				elif _stick_id == -1 and T_ZONE_STICK.has_point(pos):
					_pointers[idx] = "stick"
					_stick_id = idx
					_stick_origin = pos
					_stick_vec = Vector2.ZERO
					CTL.stick_start()
			else:
				_tap_ui(pos, event.position)
		else:
			var held: String = _pointers.get(idx, "")
			if held == "stick":
				if idx == _stick_id:
					_stick_id = -1
					_stick_vec = Vector2.ZERO
					CTL.stick_end()
			elif held != "":
				CTL.touch_exit(held)
			_pointers.erase(idx)
	elif event is InputEventScreenDrag:
		if state != "play":
			return
		var idx: int = event.index
		var pos: Vector2 = _touch_canvas_pos(event.position)
		var old: String = _pointers.get(idx, "")
		if old == "stick":
			# якорь подтягивается, когда палец выходит за радиус стика
			var v: Vector2 = pos - _stick_origin
			if v.length() > STICK_RADIUS:
				_stick_origin = pos - v.normalized() * STICK_RADIUS
				v = v.normalized() * STICK_RADIUS
			_stick_vec = v
			CTL.stick_move(v.x / STICK_RADIUS, v.y / STICK_RADIUS)
			return
		var na := _touch_zone_action(event.position)
		if na == old:
			return
		if old != "":
			CTL.touch_exit(old)
		if na != "":
			_pointers[idx] = na
			CTL.touch_enter(na)
			CTL.touch_tap(na)
		elif _stick_id == -1 and T_ZONE_STICK.has_point(pos):
			_pointers[idx] = "stick"
			_stick_id = idx
			_stick_origin = pos
			_stick_vec = Vector2.ZERO
			CTL.stick_start()
		else:
			_pointers.erase(idx)
	elif event is InputEventMouseButton and not (event is InputEventScreenTouch):
		# Поддержка мыши для тестирования и отладки UI на ПК
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			SND.unlock()
			var pos := _touch_canvas_pos(event.position)
			if state == "play":
				var a := _touch_zone_action(event.position)
				if a == "pause":
					_open_pause(null)
			else:
				_tap_ui(pos, event.position)


func _tap_ui(pos: Vector2, screen_pos := Vector2(-1, -1)) -> void:
	# тапы вне игровых зон: навигация по UI
	match state:
		"title":
			if title_submenu == "settings":
				# Кнопка «‹ НАЗАД» или строка «НАЗАД» в настройках
				if Rect2(40, 40, 160, 50).has_point(pos) or Rect2(370 + 20, 80 + 112 + (SETTINGS_ITEMS.size() - 1) * 46 - 18, 540 - 40, 44).has_point(pos):
					title_submenu = null
					SND.ui()
				else:
					_tap_settings(pos)
			elif title_submenu == "controls":
				title_submenu = null
				SND.ui()
			elif title_submenu == "bindings":
				_tap_bindings(pos)
			else:
				var i := _title_menu_item_at(pos)
				if i >= 0:
					title_menu_index = i
					_activate_title_menu(i)
		"paused":
			if submenu == "settings":
				if Rect2(40, 40, 160, 50).has_point(pos) or Rect2(370 + 20, 80 + 112 + (SETTINGS_ITEMS.size() - 1) * 46 - 18, 540 - 40, 44).has_point(pos):
					submenu = null
					SND.ui()
				else:
					_tap_settings(pos)
			elif submenu == "controls":
				submenu = null
				SND.ui()
			elif submenu == "bindings":
				_tap_bindings(pos)
			elif _zone_action(pos) == "pause" or (screen_pos.x >= 0.0 and _touch_zone_action(screen_pos) == "pause"):
				_close_pause()
			else:
				var i := _menu_item_at(pos)
				if i >= 0:
					menu_index = i
					_activate_menu()
		"dead":
			if dead_t >= 0.55:
				if Rect2(480, 524, 320, 48).has_point(pos) or _zone_action(pos) == "pause":
					_touch_stop()
					state = "title"
					title_t = 0.0
					title_submenu = null
					InkFx.reset()
					_new_run()
					SND.ui_confirm()
				elif Rect2(440, 456, 400, 54).has_point(pos) or pos.y < 520:
					_start_run()


func _menu_item_at(pos: Vector2) -> int:
	var x := 400.0
	var y := 108.0
	var w := 480.0
	for i in range(MENU_ITEMS.size()):
		var iy: float = y + 134.0 + i * 50.0
		if Rect2(x + 20, iy - 20, w - 40, 44).has_point(pos):
			return i
	return -1


func _draw_touch_ui() -> void:
	# ---- плавающий стик ----
	var base: Vector2 = _stick_origin if _stick_id != -1 else Vector2(150, 592)
	var active: bool = _stick_id != -1
	InkR.circle(base.x, base.y, STICK_RADIUS, InkR.rgba(23, 19, 15, 20 if active else 12),
		InkR.rgba(246, 237, 218, 110 if active else 66), 2.0, 1.0, 0.35, 16)
	InkR.circle(base.x, base.y, 30, null, InkR.rgba(246, 237, 218, 40), 1.2, 1.0, 0.3)
	# Стрелки рисуем линиями, а не шрифтовыми глифами: на разных Android
	# шрифтах символы ◀/▶ выглядели неровно.
	var arrow_col := InkR.rgba(246, 237, 218, 150)
	InkR.line(base.x - 48, base.y, base.x - 30, base.y - 11, 3.0, arrow_col, 1.0, 0.35)
	InkR.line(base.x - 48, base.y, base.x - 30, base.y + 11, 3.0, arrow_col, 1.0, 0.35)
	InkR.line(base.x + 48, base.y, base.x + 30, base.y - 11, 3.0, arrow_col, 1.0, 0.35)
	InkR.line(base.x + 48, base.y, base.x + 30, base.y + 11, 3.0, arrow_col, 1.0, 0.35)
	if active:
		var kpos: Vector2 = _stick_origin + _stick_vec
		InkR.circle(kpos.x, kpos.y, 20, InkR.rgba(246, 237, 218, 120),
			InkR.rgba(246, 237, 218, 220), 1.6, 1.0, 0.35)

	# ---- кнопки действий ----
	for a in TOUCH_ZONES:
		var c: Vector2 = TOUCH_RECTS[a]
		var r: float = (TOUCH_ZONES[a] as Rect2).size.x * 0.5
		var down_now: bool = bool(CTL.touch_down.get(a, false))
		var fill: Color = InkR.rgba(246, 237, 218, 66) if down_now else InkR.rgba(23, 19, 15, 22)
		var edge_col: Color = InkR.rgba(246, 237, 218, 210) if down_now else InkR.rgba(246, 237, 218, 110)
		var lcol: Color = InkR.rgba(23, 19, 15, 200) if down_now else InkR.rgba(246, 237, 218, 160)
		var rr: float = r * (1.06 if down_now else 1.0)
		InkR.blob(c.x, c.y, rr, fill, edge_col, 2.0, 1.0, 0.35, 12, 0.06)
		if a == "pause":
			InkR.line(c.x - 9, c.y - 13, c.x - 9, c.y + 13, 4.0, lcol, 1.0, 0.2)
			InkR.line(c.x + 9, c.y - 13, c.x + 9, c.y + 13, 4.0, lcol, 1.0, 0.2)
		else:
			InkR.text(TOUCH_LABELS[a], c.x, c.y + 6, int(r * 0.38),
				InkR.F_DISPLAY, InkR.A_CENTER, lcol, 1.0, 0.0, 0.0, 1)
