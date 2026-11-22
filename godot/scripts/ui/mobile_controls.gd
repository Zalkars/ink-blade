extends Control

## Сенсорный слой текущего GameFlow. Каждый палец владеет своим действием.
## --touch включает тот же слой на ПК для проверки без Android-устройства.
##
## Схема по образцу мобильной Dead Cells:
## - плавающий стик появляется под пальцем в любой точке левой части экрана
##   и тянется за пальцем, если тот уходит дальше радиуса;
## - направление делится на восемь секторов, бег сразу на полной скорости;
## - кнопки стоят дугой под правым большим пальцем, прыжок — самая крупная в углу;
## - зона нажатия шире рисунка, при касании между кнопками выбирается ближайшая;
## - палец можно перекатить с кнопки на соседнюю, не отрывая его от экрана;
## - быстрый горизонтальный свайп по свободной правой части — рывок в ту сторону;
## - недоступные действия приглушены, при игре с геймпада слой скрывается.
const FONT := preload("res://assets/fonts/PTSerif-Bold.ttf")
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
# Зона нажатия относительно нарисованного радиуса.
const HIT_SCALE := 1.3
# Порог перехода пальца на соседнюю кнопку: нужно выйти за свою кнопку.
const SLIDE_RELEASE := 1.15
# Доля безопасной ширины слева, где появляется плавающий стик.
const MOVE_ZONE := 0.45
const MOVE_ZONE_TOP := 0.22
const STICK_DEADZONE := 0.2
const SWIPE_DIST := 64.0
const SWIPE_MS := 260
const BASE_RADIUS := {
	"move": 84.0, "jump": 64.0, "attack": 60.0, "dash": 54.0,
	"heal": 46.0, "swap": 42.0, "pause": 38.0,
}
const LETTERS := {"jump": "A", "attack": "X", "dash": "B", "heal": "Y"}
var editing := false
var selected_element := "move"
var edit_pointer := -1
var edit_offset := Vector2.ZERO
var flow: Node
var fingers := {}
var stick_id := -1
var stick_center := Vector2.ZERO
var stick_tip := Vector2.ZERO
var safe := Rect2()
var _last_state := -1
var _last_device := ""
var _mouse_down := false
var feedback := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	CTL.touch_enabled = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()
	visible = CTL.touch_enabled
	if not visible:
		set_process(false)
		set_process_input(false)
		return
	CTL.device = "touch"
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	reset()
	safe = Rect2(Vector2.ZERO, get_viewport_rect().size)
	if OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		var physical := Rect2(DisplayServer.get_display_safe_area())
		if physical.has_area():
			var inverse := get_viewport().get_screen_transform().affine_inverse()
			safe = safe.intersection(inverse * physical)
	# Все меню и HUD получают те же отступы от вырезов, что и кнопки.
	for child in get_parent().get_children():
		if child is Control and child != self:
			child.offset_left = safe.position.x
			child.offset_top = safe.position.y
			child.offset_right = safe.end.x - get_viewport_rect().size.x
			child.offset_bottom = safe.end.y - get_viewport_rect().size.y
	stick_center = home_center()
	stick_tip = stick_center
	queue_redraw()


func reset() -> void:
	fingers.clear()
	stick_id = -1
	_mouse_down = false
	CTL.clear_touch()


func _process(_delta: float) -> void:
	if _last_state != flow.state:
		reset()
		_last_state = flow.state
	if CTL.device != _last_device:
		# Геймпад перехватил управление: отпускаем всё, что держали пальцы.
		if CTL.device == "gamepad":
			reset()
		_last_device = CTL.device
	for action in buttons():
		var target := 1.0 if CTL.touch_down.get(action, false) else 0.0
		feedback[action] = move_toward(float(feedback.get(action, 0.0)), target, _delta * 12.0)
	modulate.a = 1.0 if editing else CTL.touch_opacity
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset()


## Как в мобильной Dead Cells: пока играют с геймпада, кнопки не закрывают
## картинку. Первое касание экрана возвращает их.
func hidden() -> bool:
	return not editing and CTL.device == "gamepad"


## Раскладка по умолчанию: дуга под правый большой палец.
func buttons() -> Dictionary:
	var end := safe.end
	var result := {
		"jump": end - Vector2(100.0, 100.0),
		"attack": end - Vector2(238.0, 120.0),
		"dash": end - Vector2(118.0, 250.0),
		"heal": end - Vector2(262.0, 262.0),
		"swap": end - Vector2(376.0, 92.0),
		"pause": Vector2(end.x - 60.0, safe.position.y + 58.0),
	}
	for action in result:
		result[action] = element_center(action, result[action])
	return result


## Ближайшая кнопка в нормированных радиусах: крупная кнопка не проигрывает
## мелкой, а касание в щели между ними уходит той, к которой палец ближе.
func action_at(pos: Vector2, reach := HIT_SCALE) -> String:
	var centers := buttons()
	var nearest := ""
	var best := INF
	for action in centers:
		var d: float = pos.distance_to(centers[action]) / element_radius(action)
		# Пауза ловит только точное касание: её нельзя задеть в бою.
		var limit := minf(reach, 1.1) if action == "pause" else reach
		if d <= limit and d < best:
			best = d
			nearest = action
	return nearest


func in_move_zone(pos: Vector2) -> bool:
	if CTL.touch_style == "floating":
		return pos.x <= safe.position.x + safe.size.x * MOVE_ZONE \
			and pos.y >= safe.position.y + safe.size.y * MOVE_ZONE_TOP
	return pos.distance_to(home_center()) <= element_radius("move") * 1.6


func _input(event: InputEvent) -> void:
	if flow.console.visible:
		return
	if editing:
		_edit_input(event)
		return
	if is_instance_valid(flow.settings) and flow.settings.visible:
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			_release(event.index, event.position, true)
		elif event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	# QA mode supports a mouse too. Ignore emulated mouse events on phones.
	elif not OS.has_feature("mobile") and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
		if event.pressed:
			_press(100, event.position)
		else:
			_release(100, event.position)
	elif not OS.has_feature("mobile") and event is InputEventMouseMotion and _mouse_down:
		_drag(100, event.position)


func _press(id: int, pos: Vector2) -> void:
	if not is_instance_valid(flow.settings) or not flow.settings.visible:
		CTL.device = "touch"
	SND.unlock()
	if flow.state != flow.State.PLAY:
		# Меню подтверждаем только отпусканием на той же строке.
		if not fingers.is_empty():
			return
		fingers[id] = {"state": flow.state, "start": pos}
		return
	var action := action_at(pos)
	if not action.is_empty():
		if action == "pause":
			flow._pause()
			reset()
			return
		_hold(id, action)
	elif stick_id == -1 and in_move_zone(pos):
		stick_id = id
		stick_center = clamp_center(pos, element_radius("move")) if CTL.touch_style == "floating" else home_center()
		CTL.stick_start()
		_move_stick(pos)
	elif CTL.swipe_dash:
		fingers[id] = {"swipe": true, "start": pos, "t": Time.get_ticks_msec()}


func _hold(id: int, action: String) -> void:
	fingers[id] = {"action": action}
	CTL.touch_enter(action)
	CTL.touch_tap(action)
	CTL.haptic()


func _move_stick(pos: Vector2) -> void:
	var r := element_radius("move")
	var delta := pos - stick_center
	# Плавающий стик тянется за пальцем: смена направления не требует
	# возвращать палец через весь круг.
	if CTL.touch_style == "floating" and delta.length() > r:
		stick_center = pos - delta.normalized() * r
		delta = pos - stick_center
	delta = delta.limit_length(r)
	stick_tip = stick_center + delta
	var axis := CTL.sector(delta / r, STICK_DEADZONE)
	CTL.stick_move(axis.x, axis.y)


func _drag(id: int, pos: Vector2) -> void:
	if id == stick_id:
		_move_stick(pos)
		return
	if not fingers.has(id):
		return
	var held: Dictionary = fingers[id]
	if held.has("action"):
		if CTL.slide_buttons:
			_slide(id, held, pos)
	elif held.has("swipe") and not held.get("done", false):
		var d: Vector2 = pos - held.start
		if Time.get_ticks_msec() - int(held.t) <= SWIPE_MS \
				and absf(d.x) >= SWIPE_DIST and absf(d.x) > absf(d.y) * 1.2:
			held["done"] = true
			CTL.touch_dash(signf(d.x))
			CTL.haptic()


## Перекат пальца с кнопки на кнопку. Гистерезис: палец должен покинуть свою
## кнопку и оказаться внутри рисунка соседней, поэтому небольшой сдвиг
## большого пальца не отменяет прыжок и не включает соседний рывок.
func _slide(id: int, held: Dictionary, pos: Vector2) -> void:
	var current: String = held.action
	if pos.distance_to(buttons()[current]) <= element_radius(current) * SLIDE_RELEASE:
		return
	var next := action_at(pos, 1.0)
	if next.is_empty() or next == current or next == "pause":
		return
	CTL.touch_exit(current)
	_hold(id, next)


func _release(id: int, pos: Vector2, canceled := false) -> void:
	if id == stick_id:
		stick_id = -1
		stick_tip = stick_center
		CTL.stick_end()
	if not fingers.has(id):
		return
	var held: Dictionary = fingers[id]
	fingers.erase(id)
	if held.has("action"):
		CTL.touch_exit(held.action)
		return
	if held.has("swipe"):
		return
	if canceled or held.state != flow.state or pos.distance_to(held.start) > 36.0:
		return
	var panel: Control = null
	match flow.state:
		flow.State.TITLE:
			panel = flow.title_screen
		flow.State.PAUSE, flow.State.DEAD, flow.State.CLEARED:
			panel = flow.overlay
		flow.State.CUTSCENE:
			if flow.cutscene._guard == 0:
				flow.cutscene.advance()
		flow.State.DIALOGUE:
			if flow.dialogue._guard == 0:
				flow.dialogue.advance()
	if panel != null:
		var local := pos - panel.position
		var start: Vector2 = held.start - panel.position
		for i in panel.actions.size():
			if panel.item_rect(i).has_point(local) and panel.item_rect(i).has_point(start):
				if panel.has_method("activate"):
					panel.activate(i)
				else:
					panel.selected = i
					panel.chosen.emit(panel.actions[i])
				panel.queue_redraw()
				break


## Доступно ли действие сейчас: недоступные кнопки приглушаются.
func available(action: String) -> bool:
	if editing or flow == null or not is_instance_valid(flow.player):
		return true
	match action:
		"heal":
			return flow.player.soul >= Player.HEAL_COST and flow.player.hp < Player.MAX_HP
		"swap":
			return flow.player.weapons.size() > 1
	return true


## Неровный контур и полупрозрачная тушь из v0.2; форма стабильна между кадрами.
func _ink_disc(c: Vector2, radius: float, fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for i in 48:
		var angle := TAU * float(i) / 48.0
		var r := radius * (1.0 + sin(angle * 5.0 + 0.7) * 0.016 + cos(angle * 9.0) * 0.009)
		points.append(c + Vector2.from_angle(angle) * r)
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, Color(INK, 0.45 * edge.a), 5.0, true)
	draw_polyline(points, edge, 2.0, true)


func _draw() -> void:
	if (flow.state != flow.State.PLAY and not editing) or flow.console.visible or hidden():
		return
	if editing:
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var home := home_center()
	var center := stick_center if stick_id >= 0 else home
	var cream := Color("#302923") if editing else Color("#f6edda")
	var r := element_radius("move")
	if CTL.touch_style != "dpad":
		_ink_disc(center, r, Color(INK, 0.14), Color(cream, 0.65))
	else:
		var cross := PackedVector2Array()
		for point in [Vector2(-0.34,-1), Vector2(0.34,-1), Vector2(0.34,-0.34), Vector2(1,-0.34), Vector2(1,0.34), Vector2(0.34,0.34), Vector2(0.34,1), Vector2(-0.34,1), Vector2(-0.34,0.34), Vector2(-1,0.34), Vector2(-1,-0.34), Vector2(-0.34,-0.34)]:
			cross.append(center + point * r)
		draw_colored_polygon(cross, Color(INK, 0.22))
		cross.append(cross[0])
		draw_polyline(cross, Color(cream, 0.8), 3, true)
	draw_arc(center, r * 0.39, 0.0, TAU, 32, Color(cream, 0.3), 1.5, true)
	for direction in [-1.0, 1.0]:
		var arrow := center + Vector2(direction * r * 0.68, 0.0)
		draw_polyline(PackedVector2Array([arrow + Vector2(-direction * 12.0, -10.0), arrow, arrow + Vector2(-direction * 12.0, 10.0)]), Color(cream, 0.85), 3.0, true)
	if stick_id >= 0:
		_ink_disc(stick_tip, r * 0.32, Color(cream, 0.55), Color(cream, 0.9))
	if CTL.touch_style == "dpad":
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var c: Vector2 = center + direction * r * 0.6
			draw_rect(Rect2(c - Vector2.ONE * r * 0.22, Vector2.ONE * r * 0.44), Color(cream, 0.6))
	if editing:
		draw_arc(home, r + 7, 0, TAU, 64, RED if selected_element == "move" else Color(INK, 0.3), 3, true)
	var centers := buttons()
	for action in centers:
		var c: Vector2 = centers[action]
		var press := float(feedback.get(action, 0.0))
		var radius := element_radius(action) * (1.0 + press * 0.045)
		var k := radius / 52.0
		var dim := 1.0 if available(action) else 0.42
		if editing:
			draw_arc(c, radius + 7, 0, TAU, 64, RED if selected_element == action else Color(INK, 0.3), 3, true)
		var fill := Color(INK, 0.22 * dim).lerp(Color(cream, 0.78), press)
		var edge := Color(cream, 0.78 * dim).lerp(RED, press)
		var text := Color(cream, dim).lerp(INK, press)
		_ink_disc(c, radius, fill, edge)
		if action == "pause":
			for x in [-7.0, 7.0]:
				draw_line(c + Vector2(x, -12.0), c + Vector2(x, 12.0), text, 4.0, true)
		elif action == "swap":
			for direction in [-1.0, 1.0]:
				var y: float = -8.0 * direction * k
				draw_line(c + Vector2(-19, y) * Vector2(k, 1), c + Vector2(19, y) * Vector2(k, 1), text, 2.5, true)
				var tip := c + Vector2(direction * 19 * k, y)
				draw_polyline(PackedVector2Array([tip + Vector2(-direction * 7, -6), tip, tip + Vector2(-direction * 7, 6)]), text, 2.5, true)
		else:
			# Тень сохраняет читаемость светлых букв и на бумаге, и на туши.
			var letter_size := int(round(32.0 * k))
			var baseline := 10.0 * k
			draw_string(FONT, c + Vector2(-radius + 1, baseline + 1), LETTERS[action], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, letter_size, Color(INK, 0.45 * (1.0 - press) * dim))
			draw_string(FONT, c + Vector2(-radius, baseline), LETTERS[action], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, letter_size, text)
		if action != "pause":
			draw_string(FONT, c + Vector2(-radius, 32.0 * k), L10N.t("mobile." + action), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 13, text)
		if action == "dash" and is_instance_valid(flow.player):
			var ready: float = flow.player.dash_ready()
			if ready < 1.0 and ready > 0.0:
				draw_arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * ready, 48, RED, 3.0, true)
			elif ready <= 0.0:
				draw_arc(c, radius - 6.0, 0.0, TAU, 32, Color(INK, 0.35), 2.0, true)

		if action == "heal" and is_instance_valid(flow.player):
			if flow.player.healing:
				var progress: float = clampf(flow.player.heal_t / Player.HEAL_TIME, 0.0, 1.0)
				draw_arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, InkR.GOLD, 3.0, true)
			else:
				# Как счётчик фляг Dead Cells: видно, сколько души до лечения.
				var charge: float = clampf(flow.player.soul / Player.HEAL_COST, 0.0, 1.0)
				if charge > 0.0:
					draw_arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(InkR.GOLD, 0.35 + 0.4 * dim), 2.0, true)


func element_scale(action: String) -> float:
	return float(CTL.touch_layout.get(action, {}).get("scale", 1.0))

func element_radius(action: String) -> float:
	return float(BASE_RADIUS.get(action, 52.0)) * element_scale(action)

func clamp_center(pos: Vector2, radius: float) -> Vector2:
	var top := safe.position.y + radius
	if editing:
		top = maxf(top, 176.0 + radius)
	return Vector2(clampf(pos.x, safe.position.x + radius + 8, safe.end.x - radius - 8), clampf(pos.y, top + 8, safe.end.y - radius - 8))

func element_center(action: String, fallback: Vector2) -> Vector2:
	var entry: Dictionary = CTL.touch_layout.get(action, {})
	var pos: Vector2 = safe.position + entry.center * safe.size if entry.has("center") else fallback
	# Editor header is not part of the playable safe area. Pause may be dragged below it.
	var radius := element_radius(action)
	return Vector2(clampf(pos.x, safe.position.x + radius + 8, safe.end.x - radius - 8), clampf(pos.y, safe.position.y + radius + 8, safe.end.y - radius - 8))

func home_center() -> Vector2:
	return element_center("move", safe.position + Vector2(170.0, safe.size.y - 160.0))

func begin_edit() -> void:
	editing = true
	selected_element = "move"
	visible = true
	set_process(true)
	set_process_input(true)
	_layout()

func end_edit() -> void:
	editing = false
	edit_pointer = -1
	reset()
	visible = CTL.touch_enabled
	set_process(visible)
	set_process_input(visible)
	queue_redraw()

func resize_selected(value: float) -> void:
	var centers := buttons()
	centers["move"] = home_center()
	var entry: Dictionary = CTL.touch_layout.get(selected_element, {}).duplicate()
	entry["scale"] = clampf(value, 0.65, 1.5)
	CTL.touch_layout[selected_element] = entry
	entry["center"] = (clamp_center(centers[selected_element], element_radius(selected_element)) - safe.position) / safe.size
	queue_redraw()

func has_overlap() -> bool:
	var centers := buttons()
	centers["move"] = home_center()
	var keys := centers.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if centers[keys[i]].distance_to(centers[keys[j]]) < element_radius(keys[i]) + element_radius(keys[j]) + 4:
				return true
	return false

func _edit_input(event: InputEvent) -> void:
	var id := -1
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var motion := false
	if event is InputEventScreenTouch:
		id = event.index
		pos = event.position
		pressed = event.pressed and not event.canceled
		released = not event.pressed or event.canceled
	elif event is InputEventScreenDrag:
		id = event.index
		pos = event.position
		motion = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		id = 100
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion:
		id = 100
		pos = event.position
		motion = true
	if id < 0:
		return
	if pressed and edit_pointer == -1:
		var centers := buttons()
		centers["move"] = home_center()
		for action in centers:
			if pos.distance_to(centers[action]) <= element_radius(action) + 8:
				selected_element = action
				edit_pointer = id
				edit_offset = centers[action] - pos
				flow.settings.select_element(action)
				get_viewport().set_input_as_handled()
				break
	elif motion and edit_pointer == id:
		var entry: Dictionary = CTL.touch_layout.get(selected_element, {}).duplicate()
		entry["center"] = (clamp_center(pos + edit_offset, element_radius(selected_element)) - safe.position) / safe.size
		CTL.touch_layout[selected_element] = entry
		get_viewport().set_input_as_handled()
	elif released and edit_pointer == id:
		edit_pointer = -1
		get_viewport().set_input_as_handled()
