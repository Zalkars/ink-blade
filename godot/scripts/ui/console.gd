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
const COMMANDS := {
	"help": "help [команда]",
	"fps": "fps",
	"inspect": "inspect",
	"warp": "warp [x y]",
	"checkpoint": "checkpoint [id]",
	"give": "give [hp [n] | soul [n] | dash | all]",
	"set": "set <hp|soul|speed> <число>",
	"weapon": "weapon <id>",
	"spawn": "spawn [враг [x y [количество]]]",
	"kill": "kill",
	"level": "level [id]",
	"cheat": "cheat <flight|god|damage> [on|off|toggle]",
	"map": "map <enemies|particles|platforms|background> [on|off|toggle]",
	"respawn": "respawn",
	"reset": "reset",
	"panel": "panel",
	"clear": "clear",
}

var flow: Node = null

@onready var _panel: ColorRect = $Panel
@onready var _log: RichTextLabel = $Panel/Log
@onready var _edit: LineEdit = $Panel/Input

var _lines: Array[String] = []
var _history: Array[String] = []
var _hist_i := 0
var _was_paused := false
var _suggestions := PackedStringArray()
var _suggest_index := 0
var _hint: Label


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
	_edit.text_changed.connect(_update_suggestions)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Panel.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -80.0
	_hint.offset_bottom = -48.0
	_hint.offset_left = 22.0
	_hint.offset_right = -22.0
	_hint.add_theme_color_override("font_color", RED)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_log.offset_bottom = -85
	_log.scroll_active = true
	_print("F4 — панель · help — команды · ↑↓ — выбор · Tab — подстановка")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := int(event.physical_keycode)
	if key == 0:
		key = int(event.keycode)
	if key == KEY_QUOTELEFT or key == KEY_F3:
		if flow != null and is_instance_valid(flow.debug_panel) and flow.debug_panel.visible:
			return
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
	_update_suggestions("")
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
func execute(line: String, isolate := false) -> String:
	var text := line.strip_edges()
	if text.is_empty():
		return ""
	_print("> " + text)
	_history.append(text)
	if _history.size() > MAX_LINES:
		_history.pop_front()
	_hist_i = _history.size()
	return _run(text, isolate)


func _on_submit(text: String) -> void:
	var previous_state: int = flow.state
	execute(text, true)
	_edit.text = ""
	_update_suggestions("")
	if visible:
		if flow.state != previous_state:
			_was_paused = get_tree().paused
		get_tree().paused = true
		_edit.grab_focus()


func _run(line: String, isolate: bool) -> String:
	var parts := line.replace("\t", " ").split(" ", false)
	if parts.is_empty():
		return ""
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	if cmd in ["fps", "kill", "clear", "inspect", "respawn", "reset", "panel"] and not args.is_empty():
		return _reply(COMMANDS[cmd])
	match cmd:
		"help":
			return _cmd_help(args)
		"fps":
			return _cmd_fps()
		"warp":
			return _cmd_warp(args, isolate)
		"give":
			return _cmd_give(args, isolate)
		"spawn":
			return _cmd_spawn(args, isolate)
		"kill":
			if _player() == null:
				return _reply("игрок не в игре")
			_isolate(isolate)
			return _cmd_kill()
		"level":
			return _cmd_level(args, isolate)
		"cheat", "map":
			return _cmd_rule(cmd, args, isolate)
		"set":
			return _cmd_set(args, isolate)
		"checkpoint":
			return _cmd_checkpoint(args, isolate)
		"weapon":
			if _player() == null or args.size() != 1 or WDB.get_weapon(StringName(args[0])) == null:
				return _reply(COMMANDS.weapon)
			_isolate(isolate)
			_player().unlock_weapon(args[0], true)
			_player().equip_weapon(args[0])
			return _reply(args[0])
		"inspect":
			return _reply(inspect_player())
		"respawn":
			if _player() == null:
				return _reply("игрок не в игре")
			_isolate(isolate)
			flow.debug_respawn()
			_was_paused = false
			return _reply("игрок возрождён")
		"reset":
			flow.reset_debug_rules()
			return _reply("отладочные параметры сброшены")
		"panel":
			flow.debug_panel.open()
			return "F4"
		"clear":
			_lines.clear()
			_refresh()
			return "журнал очищен"
		_:
			return _reply("неизвестная команда: " + cmd + ". help — список")


func _cmd_help(args: PackedStringArray) -> String:
	if args.size() == 1:
		return _reply(COMMANDS.get(args[0].to_lower(), "неизвестная команда " + args[0]))
	if not args.is_empty():
		return _reply(COMMANDS.help)
	return _reply("\n".join(PackedStringArray(COMMANDS.values())))


func _cmd_fps() -> String:
	var fps := Engine.get_frames_per_second()
	var draw := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if flow != null and flow.hud != null:
		flow.hud.debug_on = not flow.hud.debug_on
	return _reply("fps %d · draw calls %d · примитивов %d · тик %d Гц" % [
		fps, draw, prim, int(Engine.physics_ticks_per_second)
	])


func _cmd_warp(args: PackedStringArray, isolate: bool) -> String:
	var p = _player()
	if p == null:
		return _reply("игрок не в игре")
	if args.size() == 2 and _coordinate(args[0]) and _coordinate(args[1]):
		_isolate(isolate)
		var x := float(args[0])
		var y := float(args[1])
		p.global_position = Vector2(x, y)
		p.velocity = Vector2.ZERO
		if flow.camera != null:
			flow.camera.global_position = p.global_position
			flow.camera.reset_smoothing()
		return _reply("warp -> %.0f, %.0f" % [x, y])
	if args.is_empty() and flow.level != null:
		_isolate(isolate)
		p.global_position = flow.level.spawn_point
		p.velocity = Vector2.ZERO
		return _reply("warp -> точка входа")
	return _reply("warp <x> <y>")


func _cmd_give(args: PackedStringArray, isolate: bool) -> String:
	var p = _player()
	if p == null:
		return _reply("игрок не в игре")
	var what := str(args[0]).to_lower() if args.size() > 0 else "hp"
	if args.size() > 2 or (args.size() == 2 and (what not in ["hp", "soul"] or not _numeric(args[1]) or float(args[1]) < 0)) \
			or what not in ["hp", "soul", "dash", "all"]:
		return _reply(COMMANDS.give)
	_isolate(isolate)
	match what:
		"hp":
			var n := int(clampf(float(args[1]), 0, p.MAX_HP)) if args.size() > 1 else int(p.MAX_HP)
			p.hp = mini(p.MAX_HP, p.hp + n)
			p.hp_changed.emit(p.hp, p.MAX_HP)
			return _reply("здоровье %d из %d" % [p.hp, p.MAX_HP])
		"dash":
			p.dash_cd = 0.0
			return _reply("рывок готов")
		"soul":
			p.soul = clampf(p.soul + (float(args[1]) if args.size() == 2 else 99.0), 0.0, 99.0)
			return _reply("душа %.1f" % p.soul)
		"all":
			p.hp = p.MAX_HP
			p.dash_cd = 0.0
			p.hp_changed.emit(p.hp, p.MAX_HP)
			return _reply("здоровье и рывок восстановлены")
		_:
			return _reply("give hp [n] | dash | all")


func _cmd_spawn(args: PackedStringArray, isolate: bool) -> String:
	if flow == null or flow.level == null:
		return _reply("уровень не загружен")
	var kind := str(args[0]).to_lower() if args.size() > 0 else "grunt"
	var id := kind if kind.contains(".") else "enemy." + kind
	if not DB.has(StringName(id)):
		return _reply("неизвестный враг: " + kind)
	if not flow.level.enemies_enabled:
		return _reply("враги отключены: map enemies on")
	if args.size() == 2 or args.size() > 4 or (args.size() >= 3 and (not _coordinate(args[1]) or not _coordinate(args[2]))) \
			or (args.size() == 4 and (not args[3].is_valid_int() or int(args[3]) < 1 or int(args[3]) > 20)):
		return _reply(COMMANDS.spawn)
	var pos: Vector2
	if args.size() >= 3:
		pos = Vector2(float(args[1]), float(args[2]))
	else:
		var p = _player()
		if p == null:
			return _reply("spawn <тип> <x> <y>")
		pos = p.global_position + Vector2(80.0 * float(p.facing), 0.0)
	_isolate(isolate)
	var count := int(args[3]) if args.size() == 4 else 1
	for i in count:
		flow.level.spawn_enemy(id, pos + Vector2(i * 38.0, 0.0))
	return _reply("spawn %s в %.0f, %.0f" % [kind, pos.x, pos.y])


func _cmd_level(args: PackedStringArray, isolate: bool) -> String:
	if flow == null:
		return _reply("игра не запущена")
	if args.is_empty():
		var keys := LVL.ids(flow.qa_session)
		return _reply("уровень: %s · доступно: %s" % [flow.level_id, ", ".join(keys)])
	var wanted := str(args[0]).strip_edges()
	if args.size() != 1 or not flow._can_load_level(wanted):
		return _reply("неизвестный или недоступный уровень: " + wanted)
	_isolate(isolate)
	if not flow.load_level(wanted):
		return _reply("неизвестный уровень: " + wanted)
	return _reply("уровень -> " + wanted)


func _numeric(value: String) -> bool:
	return value.is_valid_float() and is_finite(float(value))


func _coordinate(value: String) -> bool:
	return _numeric(value) and absf(float(value)) <= 1_000_000.0


func _isolate(enabled: bool) -> void:
	if enabled and flow != null:
		flow.begin_debug_session()


func _cmd_rule(command: String, args: PackedStringArray, isolate: bool) -> String:
	var keys := ["flight", "god", "damage"] if command == "cheat" else ["enemies", "particles", "platforms", "background"]
	if args.is_empty() or args.size() > 2 or args[0] not in keys:
		return _reply(COMMANDS[command])
	var mode := args[1] if args.size() == 2 else "toggle"
	if mode not in ["on", "off", "toggle"]:
		return _reply(COMMANDS[command])
	var enabled: bool = not flow.debug_rules[args[0]] if mode == "toggle" else mode == "on"
	_isolate(isolate)
	flow.set_debug_rule(args[0], enabled)
	return _reply("%s %s" % [args[0], "on" if enabled else "off"])


func _cmd_set(args: PackedStringArray, isolate: bool) -> String:
	if args.size() != 2 or args[0] not in ["hp", "soul", "speed"] or not _numeric(args[1]):
		return _reply(COMMANDS.set)
	var value := float(args[1])
	var p = _player()
	if args[0] != "speed" and p == null:
		return _reply("игрок не в игре")
	_isolate(isolate)
	match args[0]:
		"hp":
			p.hp = int(clampf(value, 1, p.MAX_HP))
			p.hp_changed.emit(p.hp, p.MAX_HP)
			value = p.hp
		"soul":
			p.soul = clampf(value, 0.0, 99.0)
			value = p.soul
		"speed":
			flow.debug_flight_speed = clampf(value, 50.0, 1800.0)
			value = flow.debug_flight_speed
	return _reply("%s %.1f" % [args[0], value])


func _cmd_checkpoint(args: PackedStringArray, isolate: bool) -> String:
	if _player() == null or flow.level == null:
		return _reply("уровень не загружен")
	if args.is_empty():
		return _reply(" · ".join(PackedStringArray(flow.level.checkpoint_nodes.keys())))
	if args.size() != 1 or not flow.level.checkpoint_nodes.has(args[0]):
		return _reply(COMMANDS.checkpoint)
	_isolate(isolate)
	var pos: Vector2 = flow.level.checkpoint_position(args[0])
	return _cmd_warp(PackedStringArray([str(pos.x), str(pos.y)]), false)


func inspect_player() -> String:
	var p = _player()
	if p == null or flow.level == null:
		return "уровень не загружен"
	return "%s / %s · X %.1f Y %.1f · V %.0f, %.0f · HP %d/%d · душа %.1f · враги %d" % [
		flow.level_id, flow.checkpoint_id, p.global_position.x, p.global_position.y, p.velocity.x, p.velocity.y,
		p.hp, p.MAX_HP, p.soul, flow.level.enemy_count()]


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
				# У босса урон принимает только открытая печать:
				# для debug-команды открываем её принудительно.
				if e.has_method("open_seal"):
					e.open_seal(5.0)
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
	if not (event is InputEventKey) or not event.pressed:
		return
	var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if key == KEY_TAB and not _suggestions.is_empty():
		var prefix := _edit.text.substr(0, _edit.text.rfind(" ") + 1)
		_edit.text = prefix + _suggestions[_suggest_index] + " "
		_edit.caret_column = _edit.text.length()
		_update_suggestions(_edit.text)
		accept_event()
	elif key in [KEY_UP, KEY_DOWN]:
		var direction := -1 if key == KEY_UP else 1
		if not _suggestions.is_empty():
			_suggest_index = posmod(_suggest_index + direction, _suggestions.size())
			_draw_hints()
		elif not _history.is_empty():
			_hist_i = clampi(_hist_i + direction, 0, _history.size())
			_edit.text = _history[_hist_i] if _hist_i < _history.size() else ""
			_edit.caret_column = _edit.text.length()
		accept_event()


func _update_suggestions(text: String) -> void:
	_suggestions.clear()
	_suggest_index = 0
	var parts := text.split(" ", false)
	var ends_in_space := text.ends_with(" ")
	var token := "" if ends_in_space or parts.is_empty() else parts[-1].to_lower()
	var index := parts.size() if ends_in_space else parts.size() - 1
	var command := parts[0].to_lower() if not parts.is_empty() else ""
	var candidates := PackedStringArray()
	if index == 0 or (command == "help" and index == 1):
		candidates = PackedStringArray(COMMANDS.keys())
	elif index >= 1:
		match command:
			"cheat": candidates = ["flight", "god", "damage"] if index == 1 else ["on", "off", "toggle"] if index == 2 else []
			"map": candidates = ["enemies", "particles", "platforms", "background"] if index == 1 else ["on", "off", "toggle"] if index == 2 else []
			"give": candidates = ["hp", "soul", "dash", "all"] if index == 1 else []
			"set": candidates = ["hp", "soul", "speed"] if index == 1 else []
			"weapon": candidates = PackedStringArray(WDB.ids()) if index == 1 else []
			"level": candidates = LVL.ids(flow.qa_session) if index == 1 else []
			"spawn": candidates = PackedStringArray(DB.ids()) if index == 1 else []
			"checkpoint":
				if flow.level != null and index == 1:
					candidates = PackedStringArray(flow.level.checkpoint_nodes.keys())
	for option in candidates:
		if option.begins_with(token):
			_suggestions.append(option)
	_draw_hints(command)


func _draw_hints(command := "") -> void:
	if _suggestions.is_empty():
		_hint.text = COMMANDS.get(command, "↑↓ история · Tab подстановка")
		return
	var shown := PackedStringArray()
	var start := maxi(0, _suggest_index - 2)
	for i in range(start, mini(start + 6, _suggestions.size())):
		shown.append(("▸ " if i == _suggest_index else "  ") + _suggestions[i])
	_hint.text = "     ".join(shown)
