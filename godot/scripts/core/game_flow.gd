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
	get_tree().paused = false
	_clear_level()
	overlay.close()
	title_screen.visible = false
	hud.visible = true
	hud.debug_on = false
	state = State.PLAY

	level = LEVELS[level_id].instantiate()
	host.add_child(level)
	level.cleared.connect(_on_cleared)

	var lim := level.camera_limits()
	camera.limit_left = lim["left"]
	camera.limit_top = lim["top"]
	camera.limit_right = lim["right"]
	camera.limit_bottom = lim["bottom"]

	player = PLAYER_SCENE.instantiate()
	player.global_position = level.spawn_point
	level.add_child(player)
	player.died.connect(_on_player_died)
	level.bind_player(player)

	camera.global_position = player.global_position + Vector2(0.0, -40.0)
	camera.reset_smoothing()
	hud.bind(player)
	_autosave(false)
	print("LEVEL %s: врагов %d" % [level_id, level.enemy_count()])


func _clear_level() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	player = null


func _pause() -> void:
	state = State.PAUSE
	get_tree().paused = true
	overlay.open(OVERLAY_PAUSE, "зал: %s" % level.data.get("name", level_id))


func _resume() -> void:
	state = State.PLAY
	get_tree().paused = false
	overlay.close()


func _show_title() -> void:
	get_tree().paused = false
	_clear_level()
	hud.visible = false
	overlay.close()
	title_screen.visible = true
	state = State.TITLE
	camera.global_position = Vector2(640.0, 360.0)
	camera.reset_smoothing()


func _on_player_died() -> void:
	state = State.DEAD
	get_tree().paused = true
	overlay.open(OVERLAY_DEAD, "зал: %s" % level.data.get("name", level_id))


func _on_cleared() -> void:
	state = State.CLEARED
	_autosave(true)
	get_tree().paused = true
	overlay.open(OVERLAY_CLEARED, "зал очищен, прогресс записан")


func _autosave(cleared: bool) -> void:
	if level == null or player == null:
		return
	SaveGame.write_slot(SaveGame.AUTOSAVE, {
		"level": level_id,
		"hp": player.hp,
		"enemies_left": level.enemy_count(),
		"cleared": cleared,
	})


func _on_overlay_choice(item: String) -> void:
	match state:
		State.PAUSE:
			match item:
				"ПРОДОЛЖИТЬ":
					_resume()
				"ЗАНОВО":
					start_run()
				"В МЕНЮ":
					_show_title()
		State.DEAD:
			if item == "ЗАНОВО":
				start_run()
			else:
				_show_title()
		State.CLEARED:
			if item == "В МЕНЮ":
				_show_title()
			else:
				start_run()


func _quit() -> void:
	get_tree().quit()


func _on_console_toggled() -> void:
	# Открытие и закрытие консоли не считается нажатием паузы.
	_console_guard = 2
