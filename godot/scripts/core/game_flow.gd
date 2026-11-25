extends Node2D

## Корень каркаса: держит состояние игры, грузит уровень в LevelHost,
## ведёт камеру, паузу, смерть и автосейв.
## Один таймлайн: CTL.update() и вся игровая логика — в _physics_process.
## Уровни регистрируются в content/levels/index.json.

const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const OVERLAY_SCENE := preload("res://scenes/ui/overlay.tscn")
const CONSOLE_SCENE := preload("res://scenes/ui/console.tscn")
const CUTSCENE_SCENE := preload("res://scenes/ui/cutscene.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue.tscn")
const CONTROL_GUIDE_SCENE := preload("res://scenes/ui/control_guide.tscn")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const SETTINGS_FILE := "user://settings.cfg"

enum State { TITLE, PLAY, PAUSE, DEAD, CLEARED, CUTSCENE, DIALOGUE, GUIDE, VICTORY }

const OVERLAY_PAUSE := 0
const OVERLAY_DEAD := 1
const OVERLAY_CLEARED := 2
const FRAME_RATES := [60, 120]
const VICTORY_HOLD := 0.85
const VICTORY_FADE := 0.45

var shake_enabled := true
var master_volume := 0.8
var vsync_enabled := true
var frame_rate := 60
var resolution_index := 0
const RESOLUTIONS := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]
var state := State.TITLE

var host: Node2D
var camera: Camera2D
var ui: CanvasLayer
var title_screen: Control
var hud: Control
var overlay: Control
var console: Control
var cutscene: Control
var dialogue: Control
var settings: Control
var mobile_controls: Control
var control_guide: Control
var _victory_fade: ColorRect
var _victory_tween: Tween

var level: Level
var player: Player
var level_id := ""
var title_slot := SaveGame.AUTOSAVE
var qa_session := false
var _title_guide := false
var debug_panel: Control
var level_editor: Control
var _editor_room: LevelData
var _editor_start: Dictionary = {}
var _editor_linked_rooms: Dictionary[String, LevelData] = {}
var _route_id := ""
var _route_data: Dictionary = {}
var _route_worlds: Dictionary = {}
var _before_route_storage := ""
var _before_route_slot := ""
var _room_states: Dictionary = {}
var _room_entry := ""
var _editor_was_paused := false
var debug_flight_speed := 420.0
var debug_rules := {"flight": false, "god": false, "damage": false,
	"enemies": true, "particles": true, "platforms": true, "background": true}
var _debug_storage := ""
var _debug_slot := ""
var checkpoint_id := ""
var granted_rewards: Array[String] = []
var _console_guard := 0
## Финал играет один раз: после него открывается окно зачистки, а не возврат в игру.
var _finale_pending := false
var _finale_seen := false
## Записи сейва сведены в одну отложенную: пачка убийств и чернильные
## следы дают один файл, а не десятки записей на главном потоке.
var _save_dirty := false
var _save_delay := 0.0
var _last_save_sig := ""
var _queued_save_sig := ""
var _save_receipt: Array[bool] = []
const SAVE_COALESCE := 0.35
var _skip_loaded_checkpoint_heal := false
var _loaded_spawn := Vector2.ZERO
var _guide_pending := false

## Статистика забега и комбо для HUD и оверлеев (как в 0.2).
var run_time := 0.0
var run_kills := 0
var combo := 0
var max_combo := 0
var combo_t := 0.0
var combo_pop := 0.0
var hitstop := 0.0
var _hitstop_paused := false
var _current_zone := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = 120
	InkR.init_static()
	var args := OS.get_cmdline_user_args()
	var level_arg := args.find("--level")
	var requested := args[level_arg + 1] if level_arg >= 0 and level_arg + 1 < args.size() else ""
	qa_session = level_arg >= 0 and LVL.has(requested)
	if qa_session:
		SaveGame.use_storage("user://qa/saves")
	level_id = LVL.first_id()
	load_preferences()
	_apply_saved_display()
	_build_stage()
	if DisplayServer.get_name() != "headless":
		_bake_paper_async()
		_bake_particle_atlas()
	# QA-флаг для сборки: сразу в игру, без титула.
	# Запуск: InkBlade-Windows.exe --headless --quit-after 300 -- --play
	if qa_session:
		if not load_level(requested):
			_show_title()
	elif level_arg >= 0:
		push_warning("level: неизвестный или пустой --level: " + requested)
		_show_title()
	elif "--play" in args:
		start_run()
	else:
		_show_title()
	get_tree().auto_accept_quit = false
	# Окно должно получить фокус сразу: иначе первые нажатия уходят
	# в другое приложение, и кажется, что управление не работает.
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_move_to_foreground()


func _build_stage() -> void:
	host = Node2D.new()
	host.name = "LevelHost"
	host.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(host)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	add_child(camera)
	camera.make_current()

	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)

	hud = HUD_SCENE.instantiate()
	hud.visible = false
	if "flow" in hud:
		hud.flow = self
	ui.add_child(hud)

	overlay = OVERLAY_SCENE.instantiate()
	if "flow" in overlay:
		overlay.flow = self
	ui.add_child(overlay)
	overlay.chosen.connect(_on_overlay_choice)

	cutscene = CUTSCENE_SCENE.instantiate()
	ui.add_child(cutscene)
	cutscene.finished.connect(_on_cutscene_finished)

	dialogue = DIALOGUE_SCENE.instantiate()
	ui.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	dialogue.progress_changed.connect(_on_dialogue_progress)

	title_screen = TITLE_SCENE.instantiate()
	if "flow" in title_screen:
		title_screen.flow = self
	ui.add_child(title_screen)
	title_screen.start_pressed.connect(_on_start_pressed)
	title_screen.continue_pressed.connect(continue_run)
	title_screen.custom_pressed.connect(open_level_editor)
	title_screen.chapter_pressed.connect(advance_story_chapter)
	title_screen.quit_pressed.connect(_quit)
	title_screen.settings_pressed.connect(open_settings)
	title_screen.guide_pressed.connect(show_title_guide)

	console = CONSOLE_SCENE.instantiate()
	console.flow = self
	ui.add_child(console)
	console.opened.connect(_on_console_toggled)
	console.closed.connect(_on_console_toggled)

	mobile_controls = preload("res://scripts/ui/mobile_controls.gd").new()
	mobile_controls.flow = self
	ui.add_child(mobile_controls)
	settings = preload("res://scripts/ui/control_settings.gd").new()
	settings.flow = self
	ui.add_child(settings)
	control_guide = CONTROL_GUIDE_SCENE.instantiate()
	control_guide.flow = self
	ui.add_child(control_guide)
	control_guide.dismissed.connect(_on_control_guide_dismissed)
	debug_panel = preload("res://scripts/ui/debug_panel.gd").new()
	debug_panel.flow = self
	ui.add_child(debug_panel)
	level_editor = preload("res://scripts/ui/level_editor.gd").new()
	level_editor.flow = self
	ui.add_child(level_editor)
	if mobile_controls.visible:
		mobile_controls._layout()

	var transitions := CanvasLayer.new()
	transitions.layer = ui.layer + 1
	add_child(transitions)
	_victory_fade = ColorRect.new()
	_victory_fade.color = Color("#f1e6d0")
	_victory_fade.modulate.a = 0.0
	_victory_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_fade.hide()
	transitions.add_child(_victory_fade)
	_victory_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _physics_process(delta: float) -> void:
	# Единственная точка, где обновляется ввод. Все читают его после этого кадра.
	CTL.mouse_gameplay_enabled = state == State.PLAY and not settings.visible and not console.visible and not debug_panel.visible and not level_editor.visible
	CTL.update(delta)
	if level_editor.visible:
		return
	# Глобальные клавиши (F11, M, F12, отладочный HUD) работают и в настройках.
	_handle_global()
	_complete_autosave(false)
	if _save_dirty:
		_save_delay -= delta
		if _save_delay <= 0.0:
			_autosave(_finale_pending or state == State.CLEARED, false, true)
	if state != State.PLAY or settings.visible or debug_panel.visible or console.visible:
		hud.set_room_prompt("")
	if settings.visible or debug_panel.visible or console.visible:
		return
	if state == State.PLAY:
		run_time += delta
		if combo_t > 0.0:
			combo_t = maxf(0.0, combo_t - delta)
			if combo_t <= 0.0:
				combo = 0
		combo_pop = maxf(0.0, combo_pop - delta * 5.0)
		if hitstop > 0.0:
			hitstop = maxf(0.0, hitstop - delta)
		if is_instance_valid(level):
			level.hitstop = hitstop
		InkFx.update(delta * (0.12 if hitstop > 0.0 else 1.0))
		var shake := InkFx.shake_offset() if shake_enabled else Vector3.ZERO
		camera.offset = Vector2(shake.x, shake.y)
		camera.rotation = shake.z
		_check_zone_transition()
	elif state == State.DEAD:
		var shake := InkFx.shake_offset() if shake_enabled else Vector3.ZERO
		camera.offset = Vector2(shake.x, shake.y)
		camera.rotation = shake.z
	elif state == State.GUIDE:
		# The world is paused, but the spawn flash must not wash out its demonstration.
		InkFx.update(delta)
	elif state == State.VICTORY:
		InkFx.update(delta)
		var shake := InkFx.shake_offset() if shake_enabled else Vector3.ZERO
		camera.offset = Vector2(shake.x, shake.y)
		camera.rotation = shake.z

	# Кадр открытия/закрытия консоли не должен заодно ставить игру на паузу.
	if _console_guard > 0:
		_console_guard -= 1
		return

	match state:
		State.TITLE:
			pass
		State.PLAY:
			if _check_world_bounds():
				return
			_follow_player()
			if CTL.pressed("pause"):
				_pause()
			elif CTL.pressed("restart"):
				_pause()
				overlay.request_restart()
			else:
				_update_room_interaction()
		State.PAUSE, State.DEAD, State.CLEARED, State.CUTSCENE, State.DIALOGUE, State.GUIDE, State.VICTORY:
			pass


func freeze(seconds: float) -> void:
	hitstop = maxf(hitstop, seconds)
	if is_instance_valid(level):
		level.hitstop = hitstop


func add_combo() -> void:
	combo += 1
	combo_t = 1.7
	combo_pop = 1.0
	max_combo = maxi(max_combo, combo)


func format_run_time() -> String:
	var s := maxf(0.0, run_time)
	var m := int(s / 60.0)
	var rest := int(s) % 60
	return "%d:%02d" % [m, rest]


func stats_line() -> String:
	var left := level.enemy_count() if is_instance_valid(level) else 0
	return L10N.t("ui.overlay.stats", [format_run_time(), run_kills, max_combo, left])


## Горячие клавиши, которые работают в любом состоянии, кроме открытой консоли.
func _handle_global() -> void:
	if console.visible:
		return
	if CTL.pressed("help"):
		hud.toggle_debug_section(hud.DEBUG_HELP)
	if CTL.pressed("hitboxes"):
		hud.toggle_hitboxes()
		if is_instance_valid(level):
			level.queue_redraw()
	if CTL.pressed("mute"):
		SND.set_muted(not SND.muted)
		save_preferences()
		if hud.visible:
			hud.show_toast(L10N.t("ui.hud.toast.muted" if SND.muted else "ui.hud.toast.unmuted"))
	if CTL.pressed("fullscreen"):
		_toggle_fullscreen()
	if CTL.pressed("screenshot"):
		_save_screenshot()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(debug_panel) or not event is InputEventKey or not event.pressed or event.echo:
		return
	if level_editor.visible:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match key:
		KEY_F3:
			if not console.visible:
				hud.debug_all = not hud.debug_all
		KEY_F4:
			if debug_panel.visible:
				debug_panel.close()
			elif not settings.visible and not control_guide.visible:
				debug_panel.open()
		KEY_F5, KEY_F6:
			hud.toggle_debug_section(hud.DEBUG_PERFORMANCE if key == KEY_F5 else hud.DEBUG_WORLD)
		KEY_F8:
			if not is_testing_level():
				return
			return_to_level_editor()
		_:
			return
	get_viewport().set_input_as_handled()


func begin_debug_session() -> void:
	if is_testing_level() or qa_session or not _debug_storage.is_empty():
		return
	_flush_save()
	_complete_autosave(true)
	_debug_storage = SaveGame.storage
	_debug_slot = SaveGame.current_slot
	SaveGame.use_storage("user://debug/saves")
	_last_save_sig = ""


func set_debug_rule(rule: String, enabled: bool) -> void:
	if not debug_rules.has(rule) or debug_rules[rule] == enabled:
		return
	debug_rules[rule] = enabled
	_apply_debug_rules()


func reset_debug_rules() -> void:
	for rule in debug_rules:
		debug_rules[rule] = rule not in ["flight", "god", "damage"]
	debug_flight_speed = 420.0
	_apply_debug_rules()


func _apply_debug_rules() -> void:
	InkFx.particles_enabled = debug_rules.particles
	if not InkFx.particles_enabled:
		InkFx.parts.clear()
		if is_instance_valid(player):
			var ink := CombatFx.layer(player)
			ink.particles.clear()
			ink.queue_redraw()
	if is_instance_valid(level):
		level.set_debug_environment(debug_rules.enemies, debug_rules.platforms, debug_rules.background)


func debug_respawn() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(level):
		return false
	player.respawn()
	player.global_position = level.resume_position()
	hitstop = 0.0
	level.hitstop = 0.0
	_resume()
	hud.show()
	_follow_player()
	camera.reset_smoothing()
	return true


func is_testing_level() -> bool:
	return _editor_room != null


func is_custom_route() -> bool:
	return not _route_id.is_empty()


func has_custom_route(id: String) -> bool:
	return LevelDraft.valid_id(id) and SaveGame.has_unfinished_run(
		SaveGame.read_slot(SaveGame.AUTOSAVE, LevelPackage.SAVE_DIR.path_join(id)))


func open_custom_route(id: String, new_route: Dictionary) -> String:
	if not level_editor.visible or not LevelDraft.valid_id(id):
		return L10N.t("editor.error_id")
	var directory := LevelPackage.SAVE_DIR.path_join(id)
	var progress := {"level": id} if not new_route.is_empty() else SaveGame.read_slot(SaveGame.AUTOSAVE, directory)
	if new_route.is_empty() and (not SaveGame.has_unfinished_run(progress) or int(progress.get("version", 0)) > SaveGame.VERSION):
		return L10N.t("editor.error_route_save")
	var bundle = new_route if not new_route.is_empty() else progress.get("route")
	if not bundle is Dictionary or bundle.get("root") != id:
		return L10N.t("editor.error_route_save")
	var checked := LevelPackage.inspect(bundle)
	if checked.has("error"):
		return checked.error
	if not checked.finish:
		return L10N.t("editor.error_route_finish")
	if not checked.worlds.has(progress.get("level")):
		return L10N.t("editor.error_route_save")
	_flush_save()
	_restore_debug_storage()
	_before_route_storage = SaveGame.storage
	_before_route_slot = SaveGame.current_slot
	SaveGame.use_storage(directory)
	_route_id = id
	_route_data = bundle.duplicate(true)
	_route_worlds = checked.worlds.duplicate(true)
	level_editor.hide()
	if not _start_level(_respawn_if_dead(progress)):
		_restore_route_storage()
		level_editor.show()
		return L10N.t("editor.error_playtest")
	return ""


func _restore_route_storage() -> void:
	SaveGame.use_storage(_before_route_storage)
	SaveGame.current_slot = _before_route_slot
	_route_id = ""
	_route_data.clear()
	_route_worlds.clear()


func open_level_editor() -> void:
	if is_testing_level():
		return_to_level_editor()
		return
	if state not in [State.TITLE, State.PAUSE, State.PLAY]:
		return
	if is_custom_route():
		_show_title()
	debug_panel.close()
	_editor_was_paused = get_tree().paused
	get_tree().paused = true
	CTL.clear_touch()
	title_screen.hide()
	overlay.hide()
	hud.hide()
	level_editor.open()
	mobile_controls.refresh_draw_state()


func close_level_editor() -> void:
	level_editor.hide()
	level_editor.release_focus()
	CTL.clear_touch()
	for action in ["pause", "back", "attack", "jump"]:
		CTL.consume(action)
	get_tree().paused = _editor_was_paused
	if state == State.TITLE:
		title_screen.show()
		title_screen.input_guard = 0.18
	elif state == State.PAUSE:
		overlay.show()
		overlay.input_guard = 0.18
	elif state == State.PLAY:
		hud.show()
	_console_guard = 2
	mobile_controls.refresh_draw_state()


func start_editor_test(world: Dictionary, options := {}) -> bool:
	if not level_editor.visible or not LevelDraft.validate_world(world).is_empty():
		return false
	var test_world := world.duplicate(true)
	var initial := {}
	if options.has("position"):
		var position_override: Vector2 = options.position
		var candidate := {"x": position_override.x, "y": position_override.y}
		if not LevelDraft.valid_spawn(test_world, candidate):
			return false
		initial["spawn_override"] = position_override - Vector2(0, 23)
	var weapon := str(options.get("weapon", "weapon.blade"))
	if WDB.get_weapon(StringName(weapon)) != null:
		initial["weapons"] = ["weapon.blade", weapon] if weapon != "weapon.blade" else [weapon]
		initial["weapon"] = weapon
	initial["ink"] = clampf(float(options.get("soul", 0.0)), 0.0, 99.0)
	_autosave(false)
	_complete_autosave(true)
	var next := _draft_room(test_world)
	_editor_room = next
	_editor_start = initial
	_editor_linked_rooms.clear()
	level_editor.hide()
	if not _start_level(initial, false, next):
		_editor_room = null
		_editor_start.clear()
		get_tree().paused = true
		level_editor.show()
		return false
	hud.show_toast(L10N.t("editor.return_hint"))
	mobile_controls.refresh_draw_state()
	return true


func _draft_room(world: Dictionary) -> LevelData:
	var definition := LevelData.new()
	definition.id = str(world.id)
	definition.scene_path = "res://scenes/level/test_gallery.tscn"
	definition.qa_only = true
	definition.world = world
	return definition


func return_to_level_editor() -> void:
	if not is_testing_level():
		return
	if console.visible:
		console.close()
	debug_panel.close()
	_clear_level()
	_editor_room = null
	_editor_start.clear()
	_editor_linked_rooms.clear()
	_show_title()
	_open_editor_after_test()


func _open_editor_after_test() -> void:
	_editor_was_paused = false
	get_tree().paused = true
	title_screen.hide()
	level_editor.open()
	mobile_controls.refresh_draw_state()


func _update_room_interaction() -> void:
	if not is_instance_valid(level) or not is_instance_valid(player) or not is_instance_valid(level.devices):
		hud.set_room_prompt("")
		return
	var candidate: Dictionary = level.devices.nearest(player.global_position + Vector2(0, 23))
	if candidate.is_empty():
		hud.set_room_prompt("")
		return
	var enabled := level.devices.available(candidate)
	var key := "room.open_switch" if candidate.section == "switches" else "room.enter"
	if candidate.item.get("finish", false):
		key = "room.finish"
	if not enabled:
		hud.set_room_prompt(L10N.t("room.engaged" if candidate.section == "switches" else "room.locked"))
		return
	var label := L10N.t(key)
	if CTL.device != "touch":
		label = "%s · %s" % [CTL.label_of("interact"), label]
	hud.set_room_prompt(label, true)
	if CTL.pressed("interact"):
		level.devices.interact(candidate)


func _room_target(id: String) -> LevelData:
	if is_custom_route():
		return _draft_room(_route_worlds[id]) if _route_worlds.has(id) else null
	if is_testing_level():
		if id == _editor_room.id:
			return _editor_room
		if _editor_linked_rooms.has(id):
			return _editor_linked_rooms[id]
		var world := LevelDraft.read(id)
		if world.get("id") == id and LevelDraft.validate_world(world).is_empty():
			var definition := _draft_room(world)
			_editor_linked_rooms[id] = definition
			return definition
	return LVL.get_level(id) if is_testing_level() or _can_load_level(id) else null


func _travel_room(exit: Dictionary) -> bool:
	if state != State.PLAY or not is_instance_valid(player):
		return false
	if exit.get("finish", false):
		if is_testing_level():
			hud.show_toast(L10N.t("editor.route_test_finish"))
		elif is_custom_route():
			_finale_seen = true
			_autosave(true)
			_show_cleared()
		return true
	var target := _room_target(str(exit.get("level", "")))
	if target == null or not RoomLinks.connects(exit, target.world):
		hud.show_toast(L10N.t("room.missing"))
		return false
	var current := _room_snapshot()
	current.merge({"rooms": _room_states, "grants": granted_rewards, "weapons": player.weapon_ids(),
		"weapon": player.current_weapon_id(), "hp": player.hp, "ink": player.soul})
	return _start_level(_arrival(current, level_id, target.id, str(exit.get("entry", ""))), false, target, true)


func _arrival(current: Dictionary, from: String, target: String, entry := "") -> Dictionary:
	var rooms: Dictionary = current.get("rooms", {}).duplicate(true)
	var snapshot := {}
	for key in ["checkpoint", "entry", "killed", "triggers", "props", "switches", "ink_marks"]:
		if current.has(key):
			snapshot[key] = current[key]
	rooms[from] = snapshot
	var visited = rooms.get(target, {})
	var restored: Dictionary = visited.duplicate(true) if visited is Dictionary else {}
	rooms.erase(target)
	restored.merge({"rooms": rooms, "entry": entry, "level": target}, true)
	for key in ["grants", "weapons", "weapon", "hp", "ink"]:
		if current.has(key):
			restored[key] = current[key]
	return restored


func next_story_chapter(progress: Dictionary) -> String:
	if not bool(progress.get("cleared", false)) or not bool(progress.get("finale_seen", false)):
		return ""
	var from := LVL.get_level(str(progress.get("level", "")))
	if from == null:
		return ""
	var next := str(from.world.get("next_chapter", ""))
	return next if not next.is_empty() and _can_load_level(next) else ""


func advance_story_chapter(slot: String) -> void:
	_flush_save()
	var progress := SaveGame.read_slot(slot)
	var migrated := SaveGame.migrate(progress)
	var target := next_story_chapter(migrated)
	if target.is_empty():
		return
	PGS.load_dict(migrated)
	var previous_slot := SaveGame.current_slot
	SaveGame.current_slot = slot
	if not _start_level(_arrival(migrated, str(progress.level), target), false, null, true):
		SaveGame.current_slot = previous_slot


## F11: полноэкранный режим без рамки и обратно. На Android не нужен.
func _toggle_fullscreen() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var full := not (mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_display(full)


## Полноэкранный режим помнится между запусками: пишем только свой ключ,
## остальные настройки старого прототипа не трогаем.
func _apply_saved_display() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	DisplayServer.window_set_size(RESOLUTIONS[resolution_index])
	if bool(cfg.get_value("display", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save_display(fullscreen: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_FILE)


## F12: снимок кадра в user://screenshots. Работает и на паузе.
func _save_screenshot() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("screenshots")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://screenshots/ink-blade-%s.png" % stamp
	var image := get_viewport().get_texture().get_image()
	if image != null and image.save_png(path) == OK:
		print("SCREENSHOT " + path)
		if hud.visible:
			hud.show_toast(L10N.t("ui.hud.toast.screenshot"))


func _follow_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	camera.global_position = player.global_position + Vector2(0.0, -40.0)


## Camera limits do not constrain physics bodies. Keep the hero in the world,
## and handle falls even during dash or damage invulnerability.
func _check_world_bounds() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(level):
		return false
	if debug_rules.flight:
		return false
	var safe_x := clampf(player.global_position.x, level.bounds.position.x + 14.0, level.bounds.end.x - 14.0)
	if safe_x != player.global_position.x:
		player.global_position.x = safe_x
		player.velocity.x = 0.0
	if player.global_position.y > level.bounds.end.y + 160.0:
		if debug_rules.god or not debug_rules.platforms:
			player.global_position = level.resume_position()
			player.velocity = Vector2.ZERO
			return true
		player.iframes = 0.0
		player.take_damage(player.MAX_HP, 0.0)
		return true
	return false


## Новая игра. with_intro = true только при запуске с титула:
## перезапуск из паузы и продолжение с чекпоинта катсцену не повторяют.
func start_run(with_intro := false) -> void:
	PGS.reset()
	run_time = 0.0
	run_kills = 0
	combo = 0
	max_combo = 0
	combo_t = 0.0
	combo_pop = 0.0
	hitstop = 0.0
	if is_testing_level():
		_start_level(_editor_start, false, _editor_room)
	elif is_custom_route():
		_start_level({"level": _route_id})
	else:
		_start_level({}, with_intro)


## Загружает указанный уровень по идентификатору (используется консолью разработчика).
func load_level(wanted: String) -> bool:
	return not is_testing_level() and _start_level({"level": wanted}, false)


## Обычная загрузка сохраняет HP и душу. Смерть отмечается в сейве отдельно.
func continue_run(slot: String = SaveGame.AUTOSAVE) -> void:
	if is_testing_level():
		debug_respawn()
		return
	# Отложенный сейв дописывается до чтения: «Продолжить» не должно
	# откатывать последние убийства на один тик.
	_flush_save()
	var save := SaveGame.read_slot(slot)
	if not save.is_empty() and (int(save.get("version", 1)) > SaveGame.VERSION \
			or not _can_load_level(str(save.get("level", LVL.first_id())))):
		push_warning("save: слот %s недоступен в текущем режиме" % slot)
		return
	if not SaveGame.has_unfinished_run(save):
		start_run()
		return
	var migrated := _respawn_if_dead(SaveGame.migrate(save))
	PGS.load_dict(migrated)
	var previous_slot := SaveGame.current_slot
	SaveGame.current_slot = slot
	if not _start_level(migrated):
		SaveGame.current_slot = previous_slot


func _respawn_if_dead(data: Dictionary) -> Dictionary:
	if bool(data.get("dead", false)):
		data["hp"] = Player.MAX_HP
		data["ink"] = 0.0
		data["dead"] = false
	return data


func respawn_run() -> void:
	# Used only by the death overlay. A plain Continue must never heal the player.
	continue_run(SaveGame.current_slot)


func save_to_slot(slot: String) -> bool:
	if is_testing_level():
		return false
	SaveGame.current_slot = slot
	if level == null or player == null:
		var auto_data := SaveGame.read_slot(SaveGame.AUTOSAVE)
		if auto_data.is_empty():
			return false
		return SaveGame.write_slot(slot, auto_data)
	_autosave(_finale_pending or state == State.CLEARED, true)
	return SaveGame.has_slot(slot)


func _can_load_level(id: String) -> bool:
	if is_custom_route():
		return _route_worlds.has(id)
	var definition := LVL.get_level(id)
	return definition != null and (qa_session or not definition.qa_only)


func _start_level(save: Dictionary, with_intro := false, definition: LevelData = null, arriving := false) -> bool:
	if definition == null:
		var wanted := str(save.get("level", LVL.first_id()))
		if not _can_load_level(wanted):
			push_warning("level: уровень недоступен: " + wanted)
			return false
		definition = _room_target(wanted)
	var scene := ResourceLoader.load(definition.scene_path, "PackedScene") as PackedScene
	if scene == null:
		return false
	var instance := scene.instantiate()
	if not instance is Level:
		instance.free()
		push_error("level: корень сцены должен быть Level: " + definition.scene_path)
		return false
	_complete_autosave(true)
	_guide_pending = false
	control_guide.visible = false
	CTL.clear_touch()
	get_tree().paused = false
	_finale_pending = false
	_finale_seen = bool(save.get("finale_seen", false))
	_save_dirty = false
	_save_delay = 0.0
	_last_save_sig = ""
	hitstop = 0.0
	_hitstop_paused = false
	if host != null and host.process_mode == Node.PROCESS_MODE_DISABLED:
		host.process_mode = Node.PROCESS_MODE_PAUSABLE
	combo = 0
	combo_t = 0.0
	combo_pop = 0.0
	_clear_level()
	overlay.close()
	cutscene.close()
	dialogue.close()
	title_screen.visible = false
	hud.visible = true
	hud.set_room_prompt("")
	hud.debug_on = false
	state = State.PLAY

	level_id = definition.id
	checkpoint_id = String(save.get("checkpoint", ""))
	_room_entry = str(save.get("entry", ""))
	var saved_rooms = save.get("rooms", {})
	_room_states = saved_rooms.duplicate(true) if saved_rooms is Dictionary else {}

	granted_rewards.clear()
	var saved_grants = save.get("grants", [])
	if typeof(saved_grants) == TYPE_ARRAY:
		for g in saved_grants:
			var gid := String(g)
			if not gid.is_empty() and not granted_rewards.has(gid):
				granted_rewards.append(gid)

	level = instance as Level
	level.data = definition.world.duplicate(true)
	level.world_state = save
	host.add_child(level)
	level.cleared.connect(_on_cleared.bind(true))
	level.checkpoint_reached.connect(_on_checkpoint)
	level.enemy_died.connect(_on_enemy_died)
	level.trigger_reached.connect(_on_trigger)
	level.prop_collected.connect(_on_prop_collected)
	level.devices.activated.connect(_on_switch_activated)
	level.devices.travel_requested.connect(_travel_room)

	var lim := level.camera_limits()
	camera.limit_left = lim["left"]
	camera.limit_top = lim["top"]
	camera.limit_right = lim["right"]
	camera.limit_bottom = lim["bottom"]

	player = PLAYER_SCENE.instantiate()
	player.global_position = level.resume_position()
	if arriving or (checkpoint_id.is_empty() and not _room_entry.is_empty()):
		player.global_position = level.entry_position(_room_entry)
	if save.has("spawn_override"):
		player.global_position = save.spawn_override
	_loaded_spawn = player.global_position
	_skip_loaded_checkpoint_heal = not save.is_empty()
	level.add_child(player)
	player.died.connect(_on_player_died)
	var saved_weapons = save.get("weapons", [])
	var wanted_weapon := String(save.get("weapon", ""))
	if typeof(saved_weapons) == TYPE_ARRAY and not saved_weapons.is_empty():
		player.restore_weapons(saved_weapons, wanted_weapon)
	for g in granted_rewards:
		_grant_weapon(g, false)
	_restore_story_rewards(save.get("dialogue", {}))
	if not wanted_weapon.is_empty():
		player.equip_weapon(wanted_weapon)
	var hp := int(save.get("hp", player.MAX_HP))
	player.hp = clampi(hp, 1, player.MAX_HP)
	# v7 пишет ink; fallback soul держит прямые вызовы _start_level со старыми данными.
	player.soul = clampf(float(save.get("ink", save.get("soul", 0.0))), 0.0, 99.0)
	player.hp_changed.emit(player.hp, player.MAX_HP)
	var combat_ink := CombatFx.layer(player)
	combat_ink.restore_state(save.get("ink_marks", []))
	combat_ink.persistent_marks_changed.connect(_on_ink_changed)
	run_kills = level.killed_ids.size()
	for saved_room in _room_states.values():
		if saved_room is Dictionary and saved_room.get("killed") is Array:
			run_kills += saved_room.killed.size()

	var legacy_fx := preload("res://scripts/visuals/legacy_fx_layer.gd").new()
	legacy_fx.z_index = 20
	legacy_fx.flow = self
	level.add_child(legacy_fx)
	player.died.connect(func(): legacy_fx.animate_on_death = true)
	level.bind_player(player)
	_apply_debug_rules()

	camera.global_position = player.global_position + Vector2(0.0, -40.0)
	camera.reset_smoothing()
	hud.bind(player)
	hud.bind_boss(level.boss)
	_show_zone_banner()
	InkFx.flash_screen(0.55, InkR.CREAM)
	var pending_finale := bool(save.get("cleared", false)) and not _finale_seen
	print("LEVEL %s: врагов %d, чекпоинт %s" % [
		level_id, level.enemy_count(), checkpoint_id if not checkpoint_id.is_empty() else "вход"])
	if with_intro:
		play_cutscene("intro")
	elif not definition.qa_only and not is_testing_level() and bool(level.data.get("story_finale", true)) and (level.enemy_count() == 0 or pending_finale):
		_on_cleared()
	else:
		var saved_dialogue = save.get("dialogue", {})
		if saved_dialogue is Dictionary and not String(saved_dialogue.get("id", "")).is_empty():
			play_dialogue(String(saved_dialogue.id), int(saved_dialogue.get("line", 0)))
	_autosave(_finale_pending or state == State.CLEARED)
	return true


## Зоны живут в данных уровня, а не в коде: правка геометрии не разводит
## баннеры с фактическими участками. Пустой список — у уровня нет зон.
func _zone_for_x(x: float) -> String:
	if not is_instance_valid(level):
		return ""
	var zones = level.data.get("zones", [])
	if not zones is Array or zones.is_empty():
		return ""
	for z in zones:
		if z is Dictionary and x < float(z.get("until", INF)):
			return String(z.get("id", ""))
	var last = zones.back()
	return String(last.get("id", "")) if last is Dictionary else ""


func _check_zone_transition() -> void:
	if player == null or not is_instance_valid(player):
		return
	var z := _zone_for_x(player.global_position.x)
	if z != _current_zone and not z.is_empty():
		_current_zone = z
		_show_zone_banner_key(z)


func _show_zone_banner(_cp_id := "") -> void:
	var z := _zone_for_x(player.global_position.x) if is_instance_valid(player) else ""
	if z.is_empty():
		_current_zone = ""
		if hud != null and hud.has_method("show_banner"):
			hud.show_banner(_level_name(), "")
		return
	_current_zone = z
	_show_zone_banner_key(z)


func _show_zone_banner_key(zone_key: String) -> void:
	if hud == null or not hud.has_method("show_banner"):
		return
	if zone_key == "threshold":
		hud.show_banner(L10N.t("BANNER_TITLE"), L10N.t("BANNER_SUB"))
		return
	hud.show_banner(L10N.t("zone.%s.title" % zone_key), L10N.t("zone.%s.sub" % zone_key))


func _bake_paper_async() -> void:
	if InkR.tex_paper != null or DisplayServer.get_name() == "headless":
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	var node := InkBakeNode.new()
	node.w = 1280.0
	node.h = 720.0
	node.fn = func(cv): InkR.bake_paper(cv)
	vp.add_child(node)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(vp):
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				img.convert(Image.FORMAT_RGBA8)
				InkR.tex_paper = ImageTexture.create_from_image(img)
		vp.queue_free()


func _bake_particle_atlas() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(InkFx.ATLAS_VARIANTS, InkFx.ATLAS_ROWS) * InkFx.ATLAS_CELL
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bake := InkBakeNode.new()
	bake.fn = InkFx.bake_particle_atlas
	vp.add_child(bake)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	if image != null and not image.is_empty():
		image.fix_alpha_edges()
		InkFx.particle_atlas = ImageTexture.create_from_image(image)
	vp.queue_free()


func _clear_level() -> void:
	if _victory_tween != null and _victory_tween.is_valid():
		_victory_tween.kill()
	_victory_fade.hide()
	_victory_fade.modulate.a = 0.0
	InkFx.reset()
	camera.offset = Vector2.ZERO
	camera.rotation = 0.0
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	player = null


func _pause() -> void:
	_autosave(false)
	CTL.clear_touch()
	# The same Esc edge must not also activate Back in the newly opened overlay.
	CTL.consume("pause")
	CTL.consume("back")
	state = State.PAUSE
	get_tree().paused = true
	overlay.open(OVERLAY_PAUSE, L10N.t("ui.overlay.subtitle", [_level_name()]))


func _resume() -> void:
	CTL.clear_touch()
	state = State.PLAY
	get_tree().paused = false
	overlay.close()


## Титул: новая игра начинается со вступления.
func _on_start_pressed() -> void:
	start_new_story()


## Explain controls on the loaded game screen after the opening story.
func start_new_story() -> void:
	if is_testing_level() or is_custom_route():
		start_run()
		return
	if is_instance_valid(level) and is_instance_valid(player):
		_autosave(_finale_pending or state == State.CLEARED)
	CTL.clear_touch()
	for action in ["jump", "attack", "back", "pause", "restart"]:
		CTL.consume(action)
	start_run(true)
	_guide_pending = true
	if state == State.PLAY:
		_open_control_guide()


func _open_control_guide() -> void:
	_guide_pending = false
	CTL.clear_touch()
	for action in ["jump", "attack", "back", "pause", "restart"]:
		CTL.consume(action)
	state = State.GUIDE
	get_tree().paused = true
	hud.visible = true
	InkFx.flash = 0.0
	if is_instance_valid(player) and player._visual != null:
		# Intro can pause before the first idle update; initialise the world-space art.
		player._process(0.0)
		# Draw a clear static example while retaining actual spawn invulnerability.
		player._visual.iframes = 0.0
	control_guide.open()


func _on_control_guide_dismissed() -> void:
	for action in ["jump", "attack", "back", "pause"]:
		CTL.consume(action)
	CTL.clear_touch()
	if _title_guide:
		_title_guide = false
		state = State.TITLE
		get_tree().paused = false
		title_screen.input_guard = 0.2
		title_screen.show()
		return
	state = State.PLAY
	get_tree().paused = false
	hud.visible = true


func show_title_guide() -> void:
	_title_guide = true
	title_screen.hide()
	_open_control_guide()
	hud.hide()


func _show_title() -> void:
	if is_testing_level():
		return_to_level_editor()
		return
	_guide_pending = false
	if is_instance_valid(level) and is_instance_valid(player):
		_autosave(_finale_pending or state == State.CLEARED)
	CTL.clear_touch()
	get_tree().paused = false
	_finale_pending = false
	_clear_level()
	_restore_debug_storage()
	if is_custom_route():
		_restore_route_storage()
	reset_debug_rules()
	hud.visible = false
	overlay.close()
	cutscene.close()
	dialogue.close()
	control_guide.visible = false
	title_screen.reset_menu()
	# Титул открывается заново: окно защиты от нажатия с прошлого экрана
	# не переносится, иначе первое касание меню пропадает.
	title_screen.input_guard = 0.0
	title_screen.visible = true
	state = State.TITLE
	camera.global_position = Vector2(640.0, 360.0)
	camera.reset_smoothing()


func _restore_debug_storage() -> void:
	if not _debug_storage.is_empty():
		SaveGame.use_storage(_debug_storage)
		SaveGame.current_slot = _debug_slot
		_debug_storage = ""


## Чекпоинт лечит и пишет автосейв: смерть вернёт игрока сюда.
## Возврат на уже пройденный чекпоинт лечит, но лишний раз не пишет файл.
func _on_checkpoint(id: String, _pos: Vector2) -> void:
	# Loading places the player inside the checkpoint Area2D. That initial
	# body_entered must not turn an ordinary Continue into free healing.
	var loaded_overlap := _skip_loaded_checkpoint_heal and _pos.distance_to(_loaded_spawn) < 64.0
	_skip_loaded_checkpoint_heal = false
	var fresh := id != checkpoint_id
	checkpoint_id = id
	_room_entry = ""
	if level != null:
		level.activate_checkpoint(id)
	if player != null and not loaded_overlap:
		player.hp = player.MAX_HP
		player.hp_changed.emit(player.hp, player.MAX_HP)
	if fresh:
		if id != "cp_01":
			_show_zone_banner()
		_autosave(false)


## Мир помнит убитых: после смерти они не возвращаются.
## Один отложенный снимок после удара хранит и побеждённых врагов, и душу.
func _on_enemy_died(id: String) -> void:
	# Временные враги (деление, призывы) не попадают в сохранение и не
	# считаются в статистике — иначе после «Продолжить» счётчик скачет.
	if level == null or not level.is_temporary_id(id):
		run_kills += 1
	_request_autosave(0.0)


func _on_prop_collected(display_name_key: String) -> void:
	hud.show_toast(L10N.t("ui.hud.toast.pickup", [L10N.t(display_name_key)]))
	_request_autosave(0.0)


func _on_switch_activated() -> void:
	hud.show_toast(L10N.t("room.engaged"))
	_autosave(false)


## Отложенный автосейв: повторные запросы сдвигают срок к более раннему,
## поэтому чернильные следы и убийства попадают в один файл.
func _request_autosave(delay: float = SAVE_COALESCE) -> void:
	if _save_dirty:
		_save_delay = minf(_save_delay, delay)
	else:
		_save_dirty = true
		_save_delay = delay


## Немедленно дописывает отложенный сейв: любой читатель сохранения
## видит состояние на текущий момент, а не на тик назад.
func _flush_save() -> void:
	if _save_dirty:
		_autosave(_finale_pending or state == State.CLEARED)


## Save the active dialogue; the reward is granted only after its final line.
func _on_trigger(_id: String, spec: Dictionary) -> void:
	var dialogue_id := String(spec.get("dialogue", ""))
	if not dialogue_id.is_empty():
		play_dialogue(dialogue_id)
	_autosave(false)


func _grant_weapon(grant: String, show_toast := true) -> void:
	if grant.is_empty() or player == null:
		return
	if not granted_rewards.has(grant):
		granted_rewards.append(grant)
	var def := WDB.get_weapon(StringName(grant))
	if def != null:
		var unlocked := player.unlock_weapon(grant, show_toast)
		if show_toast and (unlocked or hud.toast.is_empty()):
			hud.show_toast(L10N.t("ui.hud.toast.weapon", [L10N.t(def.display_name_key)]))


## Repair saves written by older versions between the trigger and its reward.
func _restore_story_rewards(pending_dialogue: Dictionary = {}) -> void:
	for spec in level.triggers:
		if not level.fired_triggers.has(String(spec.get("id", ""))):
			continue
		var id := String(spec.get("dialogue", ""))
		if id.is_empty():
			continue
		if id == String(pending_dialogue.get("id", "")):
			continue
		var path := "res://content/dialogue/%s.json" % id
		if FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				_grant_weapon(String(data.get("grant", "")), false)


func play_cutscene(id: String) -> bool:
	if not cutscene.play(id):
		return false
	CTL.clear_touch()
	state = State.CUTSCENE
	get_tree().paused = true
	hud.visible = false
	mobile_controls.refresh_draw_state()
	return true


func play_dialogue(id: String, resume_line := 0) -> bool:
	if not dialogue.play(id, resume_line):
		return false
	CTL.clear_touch()
	state = State.DIALOGUE
	get_tree().paused = true
	hud.visible = false
	mobile_controls.refresh_draw_state()
	return true


func _on_dialogue_progress() -> void:
	_autosave(false)


func _on_ink_changed() -> void:
	_request_autosave(0.75)


func _on_cutscene_finished() -> void:
	if _finale_pending:
		_finale_pending = false
		_finale_seen = true
		_autosave(true)
		_show_cleared()
		return
	if _guide_pending:
		_open_control_guide()
		return
	state = State.PLAY
	get_tree().paused = false
	hud.visible = true


func _on_dialogue_finished(_id: String, grant: String) -> void:
	_grant_weapon(grant, true)
	state = State.PLAY
	get_tree().paused = false
	hud.visible = true
	mobile_controls.refresh_draw_state()
	_autosave(false)


func _on_player_died() -> void:
	CTL.clear_touch()
	freeze(0.09)
	state = State.DEAD
	_autosave(false)
	hud.visible = false
	get_tree().paused = true
	overlay.open(OVERLAY_DEAD, L10N.t("ui.overlay.subtitle", [_level_name()]))


func _on_cleared(live := false) -> void:
	if is_testing_level() or is_custom_route() or (is_instance_valid(level) and not bool(level.data.get("story_finale", true))):
		return
	var definition := LVL.get_level(level_id)
	if definition != null and definition.qa_only:
		return
	if _finale_pending or state == State.CLEARED:
		return
	_finale_seen = false
	_finale_pending = true
	_autosave(true)
	if not live or state != State.PLAY or not is_instance_valid(level.boss) or not level.boss.dead:
		_open_finale()
		return
	state = State.VICTORY
	get_tree().paused = true
	hud.visible = false
	CTL.clear_touch()
	mobile_controls.refresh_draw_state()
	_victory_fade.show()
	_victory_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE)
	_victory_tween.tween_interval(VICTORY_HOLD)
	_victory_tween.tween_property(_victory_fade, "modulate:a", 1.0, VICTORY_FADE)
	_victory_tween.tween_callback(func():
		_open_finale()
		cutscene._guard = ceili(VICTORY_FADE * Engine.physics_ticks_per_second) + 2)
	_victory_tween.tween_property(_victory_fade, "modulate:a", 0.0, VICTORY_FADE)
	_victory_tween.tween_callback(_victory_fade.hide)


func _open_finale() -> void:
	# Финал играет до окна зачистки: сначала история, потом «уровень пройден».
	var scene := str(level.data.get("finale_cutscene", "finale"))
	if scene.is_empty() or not play_cutscene(scene):
		_finale_pending = false
		_finale_seen = true
		_autosave(true)
		_show_cleared()


func _show_cleared() -> void:
	CTL.clear_touch()
	state = State.CLEARED
	get_tree().paused = true
	hud.visible = false
	overlay.open(OVERLAY_CLEARED, L10N.t("ui.cleared.subtitle"))


func _level_name() -> String:
	if level == null:
		return level_id
	var key := str(level.data.get("display_name_key", ""))
	if not key.is_empty():
		return L10N.t(key)
	return String(level.data.get("name", level_id))


func _complete_autosave(wait: bool) -> bool:
	if _save_receipt.is_empty():
		return true
	if not wait and SaveGame.autosave_busy():
		return false
	SaveGame.flush_autosave()
	if _save_receipt[0]:
		_last_save_sig = _queued_save_sig
	else:
		_request_autosave()
	_save_receipt = []
	return true


func _autosave(cleared: bool, force := false, background := false) -> void:
	if is_testing_level() or level == null or player == null:
		_save_dirty = false
		return
	if not _complete_autosave(not background):
		_request_autosave(0.0)
		return
	var ink := CombatFx.layer(player)
	var dead_now := player.dead or state == State.DEAD
	var dialogue_open := dialogue.visible
	# Дешёвая подпись состояния: без сериализации видно, изменилось ли что-то.
	# Неизменное состояние повторно не пишется — это главная экономия на телефоне.
	var signature := str([
		level_id, checkpoint_id, level.killed_ids.size(), level.fired_triggers.size(), level.collected_props.size(),
		_room_entry, level.devices.active_switches.size(),
		granted_rewards, player.weapon_ids(), player.current_weapon_id(),
		player.MAX_HP if dead_now else player.hp,
		0.0 if dead_now else snappedf(player.soul, 0.1),
		dead_now, ink.revision, level.enemy_count(), cleared, _finale_seen,
		PGS.save_dict(),
		String(dialogue.dialogue_id) if dialogue_open else "",
		dialogue.index if dialogue_open else -1,
	])
	_save_dirty = false
	_save_delay = 0.0
	if not force and signature == _last_save_sig:
		return
	var payload := _room_snapshot()
	payload.merge({
		"level": level_id,
		"rooms": _room_states.duplicate(true),
		"grants": granted_rewards.duplicate(),
		"weapons": player.weapon_ids(),
		"weapon": player.current_weapon_id(),
		"hp": player.MAX_HP if dead_now else player.hp,
		"ink": 0.0 if dead_now else player.soul,
		"dead": dead_now,
		"dialogue": {"id": dialogue.dialogue_id, "line": dialogue.index} if dialogue_open else {},
		"enemies_left": level.enemy_count(),
		"cleared": cleared,
		"finale_seen": _finale_seen if cleared else false,
	}, true)
	payload.merge(PGS.save_dict(), true)
	if is_custom_route():
		payload["route"] = _route_data
	if background:
		_save_receipt = SaveGame.try_autosave(payload)
		_queued_save_sig = signature
		if _save_receipt.is_empty():
			_request_autosave(0.0)
	elif SaveGame.write_autosave(payload):
		_last_save_sig = signature


func _room_snapshot() -> Dictionary:
	return {"checkpoint": checkpoint_id, "entry": _room_entry, "killed": level.killed_ids.duplicate(),
		"triggers": level.fired_triggers.duplicate(), "props": level.collected_props.duplicate(),
		"switches": level.devices.active_switches.duplicate(), "ink_marks": CombatFx.layer(player).export_state()}


func _on_overlay_choice(item: String) -> void:
	if item == "editor_return":
		return_to_level_editor()
		return
	match state:
		State.PAUSE:
			if item.begins_with("save_slot_"):
				var idx := int(item.trim_prefix("save_slot_"))
				var slot := "slot_%d" % idx
				if save_to_slot(slot) and hud != null:
					hud.show_toast(L10N.t("ui.slots.saved", [idx]))
				return
			match item:
				"settings":
					open_settings()
				"debug":
					debug_panel.open()
				"resume":
					_resume()
				"restart":
					overlay.request_restart()
				"confirm_restart":
					start_new_story()
				"menu":
					_show_title()
		State.DEAD:
			if item == "checkpoint":
				respawn_run()
			else:
				_show_title()
		State.CLEARED:
			if item == "menu":
				_show_title()
			elif item == "next_chapter":
				advance_story_chapter(SaveGame.current_slot)
			else:
				start_run()


func _quit() -> void:
	if is_instance_valid(level) and is_instance_valid(player):
		_autosave(_finale_pending or state == State.CLEARED)
	get_tree().quit()


func _exit_tree() -> void:
	_complete_autosave(true)
	InkR.tex_paper = null
	InkFx.particle_atlas = null


func _on_console_toggled() -> void:
	# Открытие и закрытие консоли не считается нажатием паузы.
	_console_guard = 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and OS.has_feature("android"):
		_request_android_refresh(frame_rate)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		CTL.clear_touch()
		if is_instance_valid(level_editor) and level_editor.visible:
			return
		if is_instance_valid(level) and is_instance_valid(player):
			_autosave(_finale_pending or state == State.CLEARED)
		if state == State.PLAY and is_instance_valid(overlay):
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(level_editor) and level_editor.visible:
			level_editor.request_close()
		elif is_instance_valid(debug_panel) and debug_panel.visible:
			debug_panel.close()
		elif settings.visible:
			settings.go_back()
		elif state == State.TITLE and title_screen.has_method("handle_back") and title_screen.handle_back():
			return
		elif state == State.PAUSE and overlay.has_method("handle_back") and overlay.handle_back():
			return
		elif state == State.PLAY:
			_pause()
		elif state == State.PAUSE:
			_resume()
		elif state == State.GUIDE:
			control_guide.dismiss()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func open_settings() -> void:
	CTL.clear_touch()
	title_screen.visible = false
	overlay.visible = false
	settings.open()


func close_settings() -> void:
	CTL.clear_touch()
	title_screen.input_guard = 0.2
	overlay.input_guard = 0.2
	title_screen.visible = state == State.TITLE
	overlay.visible = state == State.PAUSE


func load_preferences() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	var saved_slot := str(cfg.get_value("saves", "selected_slot", SaveGame.AUTOSAVE))
	title_slot = saved_slot if not qa_session and saved_slot in SaveGame.MANUAL_SLOTS else SaveGame.AUTOSAVE
	shake_enabled = bool(cfg.get_value("general", "shake", true))
	master_volume = clampf(float(cfg.get_value("general", "volume", 0.8)), 0, 1)
	CTL.vibration_enabled = bool(cfg.get_value("general", "vibration", true))
	SND.set_muted(bool(cfg.get_value("general", "muted", false)))
	vsync_enabled = bool(cfg.get_value("display", "vsync", true))
	var saved_rate = cfg.get_value("display", "frame_rate", 60)
	frame_rate = int(saved_rate) if saved_rate in FRAME_RATES else 60
	resolution_index = clampi(int(cfg.get_value("display", "resolution", 0)), 0, RESOLUTIONS.size() - 1)
	apply_preferences()

func apply_preferences() -> void:
	if Engine.max_fps != frame_rate and OS.has_feature("android"):
		_request_android_refresh(frame_rate)
	Engine.max_fps = frame_rate
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)


func _request_android_refresh(rate: int) -> void:
	var runtime = Engine.get_singleton("AndroidRuntime")
	if runtime == null or OS.get_version().get_slice(".", 0).to_int() < 11:
		return
	var activity = runtime.getActivity()
	if activity == null:
		return
	var request := func():
		var engine = activity.getGodot()
		if engine == null:
			return
		var render_view = engine.getRenderView()
		if render_view != null:
			var surface = render_view.getView().getHolder().getSurface()
			if surface != null and surface.isValid():
				surface.setFrameRate(float(rate), 0) # FRAME_RATE_COMPATIBILITY_DEFAULT
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(request))

func save_preferences() -> void:
	apply_preferences()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	if not qa_session:
		cfg.set_value("saves", "selected_slot", title_slot)
	cfg.set_value("general", "shake", shake_enabled)
	cfg.set_value("general", "volume", master_volume)
	cfg.set_value("general", "vibration", CTL.vibration_enabled)
	cfg.set_value("general", "muted", SND.muted)
	cfg.set_value("display", "vsync", vsync_enabled)
	cfg.set_value("display", "frame_rate", frame_rate)
	cfg.set_value("display", "resolution", resolution_index)
	cfg.save(SETTINGS_FILE)
