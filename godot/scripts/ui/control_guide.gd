extends Control

## A paused introduction on the real world; highlighted controls are never copies.
signal dismissed
const TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const ACTIONS := ["move", "jump", "attack", "dash", "heal", "swap", "pause"]
var flow: Node
var step := 0
var _guard := 0.0
var _button: Button
var _skip: Button
var _touch_id := -1
var _touch_start := Vector2.ZERO
var _touch_target := ""
var _card := Rect2()
var _time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_button = _make_button()
	_button.pressed.connect(advance)
	_skip = _make_button()
	_skip.pressed.connect(dismiss)
	resized.connect(_layout)
	_layout()
	visible = false

func _make_button() -> Button:
	var button := Button.new()
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 19)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = RED if state in ["hover", "pressed"] else PAPER
		style.border_color = RED if state == "focus" else INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_focus_color", RED)
	button.add_theme_color_override("font_disabled_color", Color(INK, 0.5))
	button.add_theme_color_override("font_hover_pressed_color", PAPER)
	add_child(button)
	return button

func open() -> void:
	_consume_navigation()
	_touch_id = -1
	step = 0
	_guard = 0.3
	visible = true
	_layout()
	_button.grab_focus()
	queue_redraw()

func advance() -> void:
	if not visible or _guard > 0.0:
		return
	if step == ACTIONS.size() - 1:
		dismiss()
		return
	_consume_navigation()
	_touch_id = -1
	step += 1
	_guard = 0.18
	_layout()

func dismiss() -> void:
	if not visible or _guard > 0.0:
		return
	_consume_navigation()
	_touch_id = -1
	visible = false
	dismissed.emit()

func _physics_process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_guard = maxf(0.0, _guard - delta)
	_button.disabled = _guard > 0.0
	_skip.disabled = _guard > 0.0
	_layout()
	if _guard <= 0.0:
		if CTL.back():
			dismiss()
		elif CTL.confirm():
			if _skip.has_focus():
				dismiss()
			else:
				advance()
	queue_redraw()

func binding(action: String) -> String:
	if CTL.device == "touch":
		return {"move": "↔", "jump": "A", "attack": "X", "dash": "B", "heal": "Y", "swap": "⇄", "pause": "Ⅱ"}.get(action, "")
	if action == "move":
		return CTL.label_pad("left") if CTL.device == "gamepad" else CTL.label_move()
	return CTL.label_pad(action) if CTL.device == "gamepad" else CTL.label_key(action)

func _is_touch() -> bool:
	return CTL.touch_enabled and CTL.device != "gamepad"

## Viewport coordinates, refreshed to follow custom layout, safe area and resize.
func target_center() -> Vector2:
	if flow != null and _is_touch():
		var mobile = flow.mobile_controls
		var action: String = ACTIONS[step]
		var point: Vector2 = mobile.home_center() if action == "move" else mobile.buttons()[action]
		return mobile.get_global_transform_with_canvas() * point
	if flow != null and is_instance_valid(flow.player):
		return flow.player.get_global_transform_with_canvas().origin
	return Vector2(size.x * 0.5, size.y * 0.75)

func target_radius() -> float:
	return flow.mobile_controls.element_radius(ACTIONS[step]) + 12.0 if _is_touch() and flow != null else 44.0

func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.95)
	style.border_color = Color(INK, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(INK, 0.16)
	style.shadow_size = 6
	draw_style_box(style, _card)
	draw_rect(Rect2(_card.position + Vector2(0, 16), Vector2(4, 44)), RED)
	draw_string(TITLE, _card.position + Vector2(22, 36), L10N.t("guide.title"), HORIZONTAL_ALIGNMENT_LEFT, _card.size.x - 136, 25, INK)
	draw_string(TEXT, Vector2(_card.end.x - 100, _card.position.y + 35), L10N.t("guide.progress", [step + 1, ACTIONS.size()]), HORIZONTAL_ALIGNMENT_RIGHT, 78, 17, RED)
	var action: String = ACTIONS[step]
	var text := L10N.t("guide.touch." + action) if _is_touch() else L10N.t("guide.step." + action, [binding(action)])
	if _is_touch() and action == "move" and CTL.touch_style == "dpad":
		text = L10N.t("guide.touch.move_dpad")
	var paragraph := TextParagraph.new()
	paragraph.width = _card.size.x - 44
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var font_size := 22
	paragraph.add_string(text, TEXT, font_size)
	while paragraph.get_size().y > 86 and font_size > 17:
		font_size -= 1
		paragraph.clear()
		paragraph.add_string(text, TEXT, font_size)
	paragraph.draw(get_canvas_item(), _card.position + Vector2(22, 61), INK)
	var point := get_global_transform_with_canvas().affine_inverse() * target_center()
	var radius := target_radius()
	var pulse := sin(_time * 3.0) * 2.0
	draw_arc(point, radius + pulse, 0, TAU, 72, Color(PAPER, 0.92), 6.0, true)
	draw_arc(point, radius + pulse, 0, TAU, 72, RED, 2.5, true)
	var start := _card.get_center()
	var direction := (point - start).normalized()
	var sx := absf((_card.size.x * 0.5 + 8) / direction.x) if absf(direction.x) > 0.001 else INF
	var sy := absf((_card.size.y * 0.5 + 8) / direction.y) if absf(direction.y) > 0.001 else INF
	start += direction * minf(sx, sy)
	var end := point - direction * (radius + 8)
	if start.distance_to(point) > radius + 18:
		draw_line(start, end, Color(PAPER, 0.95), 5, true)
		draw_line(start, end, RED, 2, true)
		var side := direction.orthogonal()
		draw_polyline(PackedVector2Array([end - direction * 13 + side * 6, end, end - direction * 13 - side * 6]), RED, 3, true)

func _consume_navigation() -> void:
	for action in ["jump", "attack", "dash", "heal", "swap", "pause", "back", "up", "down"]:
		CTL.consume(action)
	CTL.clear_touch()

func _layout() -> void:
	if _button == null:
		return
	var width := minf(740, size.x - 48)
	var left := (size.x - width) * 0.5
	var top := clampf(size.y * 0.16, 56, 118)
	# Move only the card if a saved control layout puts the target beneath it.
	if visible and _is_touch():
		var point := get_global_transform_with_canvas().affine_inverse() * target_center()
		if Rect2(left, top, width, 220).grow(target_radius()).has_point(point):
			top = size.y - 244 if point.y < size.y * 0.5 else 24.0
	_card = Rect2(left, top, width, 220)
	_button.position = Vector2(_card.end.x - 226, _card.end.y - 63)
	_button.size = Vector2(204, 46)
	_skip.position = Vector2(_card.position.x + 22, _card.end.y - 63)
	_skip.size = Vector2(180, 46)
	_button.text = L10N.t("guide.play" if step == ACTIONS.size() - 1 else "guide.next")
	_skip.text = L10N.t("guide.skip")
	queue_redraw()

func _hit_target(point: Vector2) -> String:
	for item in [["next", _button], ["skip", _skip]]:
		var local: Vector2 = item[1].get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, item[1].size).has_point(local):
			return item[0]
	if _is_touch() and point.distance_to(target_center()) <= target_radius():
		return "action"
	return ""

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if CTL.touch_enabled:
			CTL.device = "touch"
		if event.pressed:
			if _guard <= 0.0 and _touch_id == -1 and not event.canceled:
				_touch_id = event.index
				_touch_start = event.position
				_touch_target = _hit_target(event.position)
		elif event.index == _touch_id:
			var activate: bool = not event.canceled and not _touch_target.is_empty() and _hit_target(event.position) == _touch_target and event.position.distance_to(_touch_start) <= 24.0
			var action := _touch_target
			_touch_id = -1
			if activate:
				if action == "skip":
					dismiss()
				else:
					advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _touch_id and (event.position.distance_to(_touch_start) > 24.0 or _hit_target(event.position) != _touch_target):
			_touch_target = ""
		get_viewport().set_input_as_handled()
