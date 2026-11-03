extends Node2D

## Корень каркаса: держит состояние игры, грузит уровень в LevelHost,
## ведёт камеру, паузу, смерть и автосейв.
## Один таймлайн: CTL.update() и вся игровая логика — в _physics_process.
## Новый уровень = новая сцена в LEVELS + JSON в content/levels, код не правится.

const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const OVERLAY_SCENE := preload("res://scenes/ui/overlay.tscn")
const CONSOLE_SCENE := preload("res://scenes/ui/console.tscn")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

const LEVELS := {
	"arena_01": preload("res://scenes/level/arena_01.tscn"),
}
const FIRST_LEVEL := "arena_01"

enum State { TITLE, PLAY, PAUSE, DEAD, CLEARED }

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

var level: Level
var player: Player
var level_id := FIRST_LEVEL
var checkpoint_id := ""
var _console_guard := 0


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

	title_screen = TITLE_SCENE.instantiate()
	ui.add_child(title_screen)
	title_screen.start_pressed.connect(start_run)
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
		State.PAUSE, State.DEAD, State.CLEARED:
			pass


func _follow_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	camera.global_position = player.global_position + Vector2(0.0, -40.0)


func start_run() -> void:
	_start_level({})


## Продолжение с автосейва: пройденный чекпоинт, живые враги, здоровье.
func continue_run() -> void:
	var save := SaveGame.read_slot(SaveGame.AUTOSAVE)
	if save.is_empty() or bool(save.get("cleared", false)):
		start_run()
		return
	_start_level(SaveGame.migrate(save))


func _start_level(save: Dictionary) -> void:
	get_tree().paused = false
	_clear_level()
	overlay.close()
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

	var lim := level.camera_limits()
	camera.limit_left = lim["left"]
	camera.limit_top = lim["top"]
	camera.limit_right = lim["right"]
	camera.limit_bottom = lim["bottom"]

	player = PLAYER_SCENE.instantiate()
	player.global_position = level.resume_position()
	level.add_child(player)
	player.died.connect(_on_player_died)
	var hp := int(save.get("hp", player.MAX_HP))
	player.hp = clampi(hp, 1, player.MAX_HP)
	player.hp_changed.emit(player.hp, player.MAX_HP)
	level.bind_player(player)

	camera.global_position = player.global_position + Vector2(0.0, -40.0)
	camera.reset_smoothing()
	hud.bind(player)
	_autosave(false)
	print("LEVEL %s: врагов %d, чекпоинт %s" % [
		level_id, level.enemy_count(), checkpoint_id if not checkpoint_id.is_empty() else "вход"])


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


func _show_title() -> void:
	get_tree().paused = false
	_clear_level()
	hud.visible = false
	overlay.close()
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
func _on_enemy_died(_id: String) -> void:
	_autosave(false)


func _on_player_died() -> void:
	state = State.DEAD
	get_tree().paused = true
	overlay.open(OVERLAY_DEAD, L10N.t("ui.overlay.subtitle", [_level_name()]))


func _on_cleared() -> void:
	state = State.CLEARED
	_autosave(true)
	get_tree().paused = true
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
