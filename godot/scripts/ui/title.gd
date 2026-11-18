extends Control

## Титульный экран каркаса: заголовок Underdog, меню без мыши.

signal start_pressed
signal continue_pressed
signal settings_pressed
signal quit_pressed

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.55)

var input_guard := 0.0
var selected := 0
var items: Array[String] = []
var actions: Array[String] = []
var _wob := 0.0
var _confirm_quit := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	refresh()


## Пункт «ПРОДОЛЖИТЬ» появляется только когда есть незачищенный автосейв.
## «ИГРАТЬ» всегда первый: с титула новая игра не должна случайно
## превращаться в продолжение с середины.
func refresh() -> void:
	items.clear()
	actions.clear()
	_confirm_quit = false
	actions.append("play")
	items.append(L10N.t("ui.title.play"))
	var save := SaveGame.read_slot(SaveGame.AUTOSAVE)
	if not save.is_empty() and not bool(save.get("cleared", false)):
		actions.append("continue")
		items.append(L10N.t("ui.title.continue"))
	actions.append("settings")
	items.append(L10N.t("MENU_SETTINGS"))
	actions.append("quit")
	items.append(L10N.t("ui.title.quit"))
	selected = clampi(selected, 0, actions.size() - 1)


func _physics_process(delta: float) -> void:
	# Скрытый титул не должен читать ввод: visible = false не выключает
	# _physics_process сам по себе. Без этой строки прыжок в игре подтверждал
	# пункт меню — игра перезапускалась, а с выбранным «ВЫХОД» закрывалась.
	if not visible:
		return
	if input_guard > 0:
		input_guard -= delta
		return
	_wob += delta
	if CTL.pressed("down"):
		selected = (selected + 1) % actions.size()
		_confirm_quit = false
	if CTL.pressed("up"):
		selected = (selected + actions.size() - 1) % actions.size()
		_confirm_quit = false
	if CTL.confirm():
		activate(selected)
		queue_redraw()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-position, get_viewport_rect().size), PAPER)
	draw_circle(Vector2(size.x * 0.78, 180.0), 128.0, Color(RED, 0.9))
	draw_circle(Vector2(size.x * 0.78, 180.0), 132.0, Color(RED, 0.2))

	draw_string(FONT_TITLE, Vector2(88.0, 200.0), L10N.t("TITLE_LINE1"), HORIZONTAL_ALIGNMENT_LEFT, -1, 62, INK)
	draw_string(FONT_TITLE, Vector2(84.0, 320.0), L10N.t("TITLE_LINE2"), HORIZONTAL_ALIGNMENT_LEFT, -1, 112, INK)

	var pts := PackedVector2Array()
	var x := 88.0
	while x < 470.0:
		pts.append(Vector2(x, 340.0 + sin(x * 0.22) * 1.6))
		x += 8.0
	draw_polyline(pts, RED, 4.0)

	draw_string(FONT_TEXT, Vector2(92.0, 372.0), L10N.t("ui.title.subtitle"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GRAY)

	for i in items.size():
		var y := 470.0 + i * 44.0
		var on := i == selected
		if on:
			var box := PackedVector2Array([
				Vector2(84.0, y - 34.0),
				Vector2(384.0, y - 36.0),
				Vector2(386.0, y + 8.0),
				Vector2(86.0, y + 10.0),
			])
			draw_colored_polygon(box, Color(INK, 0.06))
			draw_rect(Rect2(84.0, y - 34.0, 5.0, 44.0), RED)
		var label := items[i]
		if on and actions[i] == "quit" and _confirm_quit:
			label = L10N.t("ui.title.quit_confirm")
		draw_string(FONT_BOLD, Vector2(104.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK if on else Color(INK, 0.55))

	var hint_text := ""
	if CTL.touch_enabled:
		hint_text = L10N.t("mobile.menu_hint")
	elif CTL.device == "gamepad":
		hint_text = L10N.t("ui.title.hint_pad", [L10N.t("KEY_STICK"), CTL.label_pad("jump")])
	else:
		hint_text = L10N.t("ui.title.hint", [
			CTL.label_of("up"), CTL.label_of("down"), CTL.label_of("jump"), CTL.label_of("help")])
	draw_string(FONT_TEXT, Vector2(88.0, size.y - 40.0), hint_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GRAY)

	# Системные клавиши есть только на клавиатуре: на геймпаде не показываем.
	if CTL.device != "gamepad" and not CTL.touch_enabled:
		draw_string(FONT_TEXT, Vector2(88.0, size.y - 18.0),
			L10N.t("ui.title.system_hint", [
				CTL.label_key("fullscreen"), CTL.label_key("mute"), CTL.label_key("screenshot")]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GRAY)

	draw_string(FONT_TEXT, Vector2(size.x - 210.0, size.y - 40.0), L10N.t("ui.title.version"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GRAY)


func item_rect(i: int) -> Rect2:
	return Rect2(84.0, 430.0 + i * 44.0, 520.0, 42.0)


func activate(i: int) -> void:
	if i != selected:
		_confirm_quit = false
	selected = i
	match actions[selected]:
		"continue":
			continue_pressed.emit()
		"settings":
			settings_pressed.emit()
		"play":
			start_pressed.emit()
		_:
			# Выход — только со второго нажатия: случайный пробел или
			# удар по «ВЫХОД» не должен закрывать игру.
			if _confirm_quit:
				quit_pressed.emit()
			else:
				_confirm_quit = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in actions.size():
			if item_rect(i).has_point(event.position):
				activate(i)
				accept_event()
