extends Control

## Debug-консоль каркаса: warp, give, spawn, kill, fps.
## Открывается клавишей «ё» (клавиша слева от единицы) или F3.
## Пока консоль открыта, игра стоит на паузе, а ввод уходит в строку.

signal opened
signal closed

const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")

const INK := Color("#17130f")
const PAPER := Color("#f1e6d0")
const RED := Color("#9c1f24")

const MAX_LINES := 200

var flow: Node = null

@onready var _panel: ColorRect = $Panel
@onready var _log: RichTextLabel = $Panel/Log
@onready var _edit: LineEdit = $Panel/Input

var _lines: Array[String] = []
var _history: Array[String] = []
var _hist_i := 0
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel.color = PAPER
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.scroll_active = false
	_log.add_theme_font_override("normal_font", FONT_TEXT)
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_color_override("default_color", INK)
	_edit.add_theme_font_override("font", FONT_TEXT)
	_edit.add_theme_font_size_override("font_size", 17)
	_edit.add_theme_color_override("font_color", INK)
	_edit.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	_edit.add_theme_color_override("caret_color", RED)
	_edit.add_theme_constant_override("caret_width", 2)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PAPER, 0.0)
	box.border_color = Color(INK, 0.4)
	box.border_width_bottom = 2
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	_edit.add_theme_stylebox_override("normal", box)
	_edit.add_theme_stylebox_override("focus", box)
	_edit.add_theme_stylebox_override("read_only", box)
	_edit.placeholder_text = "команда: help"
	_edit.text_submitted.connect(_on_submit)
	_edit.gui_input.connect(_on_input_gui)
	_print("консоль каркаса. help — список команд.")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := int(event.physical_keycode)
	if key == 0:
		key = int(event.keycode)
	if key == KEY_QUOTELEFT or key == KEY_F3:
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and visible:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_edit.text = ""
	_edit.grab_focus()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_edit.release_focus()
	get_tree().paused = _was_paused
	closed.emit()


## Выполняет строку так же, как это сделал бы игрок. Возвращает ответ консоли.
func execute(line: String) -> String:
	var text := line.strip_edges()
	if text.is_empty():
		return ""
	_print("> " + text)
	_history.append(text)
	_hist_i = _history.size()
	return _run(text)


func _on_submit(text: String) -> void:
	execute(text)
	_edit.text = ""
	_edit.grab_focus()


func _run(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return ""
	var cmd := parts[0].to_lower()
	match cmd:
		"help":
			return _cmd_help()
		"fps":
			return _cmd_fps()
		"warp":
			return _cmd_warp(parts.slice(1))
		"give":
			return _cmd_give(parts.slice(1))
		"spawn":
			return _cmd_spawn(parts.slice(1))
		"kill":
			return _cmd_kill()
		"clear":
			_lines.clear()
			_refresh()
			return "журнал очищен"
		_:
			return _reply("неизвестная команда: " + cmd + ". help — список")


func _cmd_help() -> String:
	return _reply(
		"warp <x> <y> — перенести игрока (без аргументов — на точку входа)\n" +
		"give hp [n] | dash | all — здоровье и рывок\n" +
		"spawn grunt [x] [y] — создать врага\n" +
		"kill — убрать всех врагов\n" +
		"fps — показать счётчик кадров и переключить отладку HUD\n" +
		"clear — очистить журнал"
	)


func _cmd_fps() -> String:
	var fps := Engine.get_frames_per_second()
	var draw := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if flow != null and flow.hud != null:
		flow.hud.debug_on = not flow.hud.debug_on
	return _reply("fps %d · draw calls %d · примитивов %d · тик %d Гц" % [
		fps, draw, prim, int(Engine.physics_ticks_per_second)
	])


func _cmd_warp(args: Array) -> String:
	var p = _player()
	if p == null:
		return _reply("игрок не в игре")
	if args.size() >= 2:
		var x := float(args[0])
		var y := float(args[1])
		p.global_position = Vector2(x, y)
		p.velocity = Vector2.ZERO
		if flow.camera != null:
			flow.camera.global_position = p.global_position
			flow.camera.reset_smoothing()
		return _reply("warp -> %.0f, %.0f" % [x, y])
	if flow.level != null:
		p.global_position = flow.level.spawn_point
		p.velocity = Vector2.ZERO
		return _reply("warp -> точка входа")
	return _reply("warp <x> <y>")


func _cmd_give(args: Array) -> String:
	var p = _player()
	if p == null:
		return _reply("игрок не в игре")
	var what := str(args[0]).to_lower() if args.size() > 0 else "hp"
	match what:
		"hp":
			var n: int = int(args[1]) if args.size() > 1 else int(p.MAX_HP)
			p.hp = mini(p.MAX_HP, p.hp + n)
			p.hp_changed.emit(p.hp, p.MAX_HP)
			return _reply("здоровье %d из %d" % [p.hp, p.MAX_HP])
		"dash":
			p.dash_cd = 0.0
			return _reply("рывок готов")
		"all":
			p.hp = p.MAX_HP
			p.dash_cd = 0.0
			p.hp_changed.emit(p.hp, p.MAX_HP)
			return _reply("здоровье и рывок восстановлены")
		_:
			return _reply("give hp [n] | dash | all")


func _cmd_spawn(args: Array) -> String:
	if flow == null or flow.level == null:
		return _reply("уровень не загружен")
	var kind := str(args[0]).to_lower() if args.size() > 0 else "grunt"
	var pos: Vector2
	if args.size() >= 3:
		pos = Vector2(float(args[1]), float(args[2]))
	else:
		var p = _player()
		if p == null:
			return _reply("spawn <тип> <x> <y>")
		pos = p.global_position + Vector2(80.0 * float(p.facing), 0.0)
	if not flow.level.spawn_enemy(kind, pos):
		return _reply("неизвестный враг: " + kind)
	return _reply("spawn %s в %.0f, %.0f" % [kind, pos.x, pos.y])


func _cmd_kill() -> String:
	if flow == null:
		return _reply("игра не запущена")
	var killed := 0
	# Клякса при смерти создаёт детей в том же вызове hit(),
	# поэтому проходим группу повторно, пока живые не кончатся.
	for sweep in 8:
		var found := get_tree().get_nodes_in_group("enemies")
		var alive := 0
		for e in found:
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			alive += 1
			if e.has_method("hit"):
				e.hit(999, 1)
				killed += 1
		if alive == 0:
			break
	return _reply("убрано врагов: %d" % killed)


func _player():
	if flow == null or flow.player == null or not is_instance_valid(flow.player):
		return null
	return flow.player


func _reply(text: String) -> String:
	_print(text)
	return text


func _print(text: String) -> void:
	_lines.append(text)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_refresh()
	print("[console] " + text)


func _refresh() -> void:
	if _log == null:
		return
	_log.text = "\n".join(PackedStringArray(_lines))


func _on_input_gui(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_UP and not _history.is_empty():
		_hist_i = maxi(0, _hist_i - 1)
		_edit.text = _history[_hist_i]
		_edit.caret_column = _edit.text.length()
		accept_event()
	elif event.keycode == KEY_DOWN and not _history.is_empty():
		_hist_i = mini(_history.size() - 1, _hist_i + 1)
		_edit.text = _history[_hist_i]
		_edit.caret_column = _edit.text.length()
		accept_event()
