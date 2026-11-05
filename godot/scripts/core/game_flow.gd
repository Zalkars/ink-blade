extends Node2D

## Корень каркаса: держит состояние игры, грузит уровень в LevelHost,
## ведёт камеру, паузу, смерть и автосейв.
## Один таймлайн: CTL.update() и вся игровая логика — в _physics_process.
## Новый уровень = новая сцена в LEVELS + JSON в content/levels, код не правится.

const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const OVERLAY_SCENE := preload("res://scenes/ui/overlay.tscn")
const CONSOLE_SCENE := preload("res://scenes/ui/console.tscn")
const CUTSCENE_SCENE := preload("res://scenes/ui/cutscene.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue.tscn")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

const LEVELS := {
	"ch01_hall": preload("res://scenes/level/ch01_hall.tscn"),
	"arena_01": preload("res://scenes/level/arena_01.tscn"),
}
const FIRST_LEVEL := "ch01_hall"

enum State { TITLE, PLAY, PAUSE, DEAD, CLEARED, CUTSCENE, DIALOGUE }

const OVERLAY_PAUSE := 0
const OVERLAY_DEAD := 1
const OVERLAY_CLEARED := 2

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

var level: Level
var player: Player
var level_id := FIRST_LEVEL
var checkpoint_id := ""
var _console_guard := 0
## Финал играет один раз: после него открывается окно зачистки, а не возврат в игру.
var _finale_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = 120
	_build_stage()
	# QA-флаг для сборки: сразу в игру, без титула.
	# Запуск: InkBlade-Windows.exe --headless --quit-after 300 -- --play
	if "--play" in OS.get_cmdline_user_args():
		start_run()
	else:
		_show_title()


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
	ui.add_child(hud)

	overlay = OVERLAY_SCENE.instantiate()
	ui.add_child(overlay)
	overlay.chosen.connect(_on_overlay_choice)

	cutscene = CUTSCENE_SCENE.instantiate()
	ui.add_child(cutscene)
	cutscene.finished.connect(_on_cutscene_finished)

	dialogue = DIALOGUE_SCENE.instantiate()
	ui.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

	title_screen = TITLE_SCENE.instantiate()
	ui.add_child(title_screen)
	title_screen.start_pressed.connect(_on_start_pressed)
	title_screen.continue_pressed.connect(continue_run)
	title_screen.quit_pressed.connect(_quit)

	console = CONSOLE_SCENE.instantiate()
	console.flow = self
	ui.add_child(console)
	console.opened.connect(_on_console_toggled)
	console.closed.connect(_on_console_toggled)


func _physics_process(delta: float) -> void:
	# Единственная точка, где обновляется ввод. Все читают его после этого кадра.
	CTL.update(delta)

	if CTL.pressed("help"):
		hud.debug_on = not hud.debug_on

	# Кадр открытия/закрытия консоли не должен заодно ставить игру на паузу.
	if _console_guard > 0:
		_console_guard -= 1
		return

	match state:
		State.TITLE:
			pass
		State.PLAY:
			_follow_player()
			if CTL.pressed("pause"):
				_pause()
			elif CTL.pressed("restart"):
				start_run()
		State.PAUSE, State.DEAD, State.CLEARED, State.CUTSCENE, State.DIALOGUE:
			pass


func _follow_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	camera.global_position = player.global_position + Vector2(0.0, -40.0)


## Новая игра. with_intro = true только при запуске с титула:
## перезапуск из паузы и продолжение с чекпоинта катсцену не повторяют.
func start_run(with_intro := false) -> void:
	_start_level({}, with_intro)


## Продолжение с автосейва: пройденный чекпоинт, живые враги, здоровье.
func continue_run() -> void:
	var save := SaveGame.read_slot(SaveGame.AUTOSAVE)
	if save.is_empty() or bool(save.get("cleared", false)):
		start_run()
		return
	_start_level(SaveGame.migrate(save))


func _start_level(save: Dictionary, with_intro := false) -> void:
	get_tree().paused = false
	_finale_pending = false
	_clear_level()
	overlay.close()
	cutscene.close()
	dialogue.close()
	title_screen.visible = false
	hud.visible = true
	hud.debug_on = false
	state = State.PLAY

	var wanted := String(save.get("level", FIRST_LEVEL))
	level_id = wanted if LEVELS.has(wanted) else FIRST_LEVEL
	checkpoint_id = String(save.get("checkpoint", ""))

	level = LEVELS[level_id].instantiate()
	level.world_state = save
	host.add_child(level)
	level.cleared.connect(_on_cleared)
	level.checkpoint_reached.connect(_on_checkpoint)
	level.enemy_died.connect(_on_enemy_died)
	level.trigger_reached.connect(_on_trigger)

	var lim := level.camera_limits()
	camera.limit_left = lim["left"]
	camera.limit_top = lim["top"]
	camera.limit_right = lim["right"]
	camera.limit_bottom = lim["bottom"]

	player = PLAYER_SCENE.instantiate()
	player.global_position = level.resume_position()
	level.add_child(player)
	player.died.connect(_on_player_died)
	var saved_weapons = save.get("weapons", [])
	if typeof(saved_weapons) == TYPE_ARRAY and not saved_weapons.is_empty():
		player.restore_weapons(saved_weapons, String(save.get("weapon", "")))
	var hp := int(save.get("hp", player.MAX_HP))
	player.hp = clampi(hp, 1, player.MAX_HP)
	player.hp_changed.emit(player.hp, player.MAX_HP)
	level.bind_player(player)

	camera.global_position = player.global_position + Vector2(0.0, -40.0)
	camera.reset_smoothing()
	hud.bind(player)
	hud.bind_boss(level.boss)
	_autosave(false)
	print("LEVEL %s: врагов %d, чекпоинт %s" % [
		level_id, level.enemy_count(), checkpoint_id if not checkpoint_id.is_empty() else "вход"])
	if with_intro:
		play_cutscene("intro")


func _clear_level() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	player = null


func _pause() -> void:
	state = State.PAUSE
	get_tree().paused = true
	overlay.open(OVERLAY_PAUSE, L10N.t("ui.overlay.subtitle", [_level_name()]))


func _resume() -> void:
	state = State.PLAY
	get_tree().paused = false
	overlay.close()


## Титул: новая игра начинается со вступления.
func _on_start_pressed() -> void:
	start_run(true)


func _show_title() -> void:
	get_tree().paused = false
	_finale_pending = false
	_clear_level()
	hud.visible = false
	overlay.close()
	cutscene.close()
	dialogue.close()
	title_screen.refresh()
	title_screen.visible = true
	state = State.TITLE
	camera.global_position = Vector2(640.0, 360.0)
	camera.reset_smoothing()


## Чекпоинт лечит и пишет автосейв: смерть вернёт игрока сюда.
## Возврат на уже пройденный чекпоинт лечит, но лишний раз не пишет файл.
func _on_checkpoint(id: String, _pos: Vector2) -> void:
	var fresh := id != checkpoint_id
	checkpoint_id = id
	if level != null:
		level.activate_checkpoint(id)
	if player != null:
		player.hp = player.MAX_HP
		player.hp_changed.emit(player.hp, player.MAX_HP)
	if fresh:
		_autosave(false)


## Мир помнит убитых: после смерти они не возвращаются.
## Временные враги (деление, призыв, debug-спавн) не пишут файл зря.
func _on_enemy_died(id: String) -> void:
	if level != null and level.is_temporary_id(id):
		return
	_autosave(false)


## Триггер уже записан в fired_triggers, поэтому сохраняем до разговора:
## если игрок закроет игру во время диалога, сцена не повторится.
func _on_trigger(_id: String, spec: Dictionary) -> void:
	_autosave(false)
	var dialogue_id := String(spec.get("dialogue", ""))
	if not dialogue_id.is_empty():
		play_dialogue(dialogue_id)


func play_cutscene(id: String) -> bool:
	if not cutscene.play(id):
		return false
	state = State.CUTSCENE
	get_tree().paused = true
	hud.visible = false
	return true


func play_dialogue(id: String) -> bool:
	if not dialogue.play(id):
		return false
	state = State.DIALOGUE
	get_tree().paused = true
	hud.visible = false
	return true


func _on_cutscene_finished() -> void:
	if _finale_pending:
		_finale_pending = false
		_show_cleared()
		return
	state = State.PLAY
	get_tree().paused = false
	hud.visible = true


func _on_dialogue_finished(_id: String, grant: String) -> void:
	if not grant.is_empty() and player != null:
		var def := WDB.get_weapon(StringName(grant))
		if def != null and player.unlock_weapon(grant, true):
			hud.show_toast(L10N.t("ui.hud.toast.weapon", [L10N.t(def.display_name_key)]))
	state = State.PLAY
	get_tree().paused = false
	hud.visible = true
	_autosave(false)


func _on_player_died() -> void:
	state = State.DEAD
	get_tree().paused = true
	overlay.open(OVERLAY_DEAD, L10N.t("ui.overlay.subtitle", [_level_name()]))


func _on_cleared() -> void:
	_autosave(true)
	# Финал играет до окна зачистки: сначала история, потом «уровень пройден».
	_finale_pending = true
	if not play_cutscene("finale"):
		_finale_pending = false
		_show_cleared()


func _show_cleared() -> void:
	state = State.CLEARED
	get_tree().paused = true
	hud.visible = false
	overlay.open(OVERLAY_CLEARED, L10N.t("ui.cleared.subtitle"))


func _level_name() -> String:
	if level == null:
		return level_id
	return String(level.data.get("name", level_id))


func _autosave(cleared: bool) -> void:
	if level == null or player == null:
		return
	SaveGame.write_slot(SaveGame.AUTOSAVE, {
		"level": level_id,
		"checkpoint": checkpoint_id,
		"killed": level.killed_ids.duplicate(),
		"triggers": level.fired_triggers.duplicate(),
		"weapons": player.weapon_ids(),
		"weapon": player.current_weapon_id(),
		"hp": player.hp,
		"enemies_left": level.enemy_count(),
		"cleared": cleared,
	})


func _on_overlay_choice(item: String) -> void:
	match state:
		State.PAUSE:
			match item:
				"resume":
					_resume()
				"restart":
					start_run()
				"menu":
					_show_title()
		State.DEAD:
			if item == "checkpoint":
				continue_run()
			else:
				_show_title()
		State.CLEARED:
			if item == "menu":
				_show_title()
			else:
				start_run()


func _quit() -> void:
	get_tree().quit()


func _on_console_toggled() -> void:
	# Открытие и закрытие консоли не считается нажатием паузы.
	_console_guard = 2
