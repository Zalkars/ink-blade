extends Control

## The flow owns pausing and decides when to open this new-game introduction.
signal dismissed

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const ACTIONS := ["move", "jump", "attack", "dash", "heal", "swap", "pause"]
var _guard := 0.0
var _button: Button
var _touch_id := -1
var _touch_start := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_button = Button.new()
	_button.add_theme_font_override("font", FONT_BOLD)
	_button.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = RED if state in ["hover", "pressed"] else PAPER
		style.border_color = RED if state == "focus" else INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(2)
		_button.add_theme_stylebox_override(state, style)
	_button.add_theme_color_override("font_color", INK)
	_button.add_theme_color_override("font_hover_color", PAPER)
	_button.add_theme_color_override("font_pressed_color", PAPER)
	_button.add_theme_color_override("font_focus_color", RED)
	_button.add_theme_color_override("font_disabled_color", INK)
	_button.add_theme_color_override("font_hover_pressed_color", PAPER)
	_button.pressed.connect(dismiss)
	add_child(_button)
	resized.connect(_layout)
	_layout()
	visible = false

func open() -> void:
	_consume_navigation()
	_touch_id = -1
	_layout()
	_guard = 0.3
	visible = true
	_button.text = L10N.t("guide.done")
	_button.disabled = true
	_button.grab_focus()
	queue_redraw()

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
	_guard = maxf(0.0, _guard - delta)
	_button.disabled = _guard > 0.0
	if _guard <= 0.0 and (CTL.confirm() or CTL.back()):
		dismiss()
	queue_redraw()

func binding(action: String) -> String:
	if action == "move":
		if CTL.device == "gamepad":
			return CTL.label_pad("left")
		if CTL.device == "touch":
			return L10N.t("controls.dpad" if CTL.touch_style == "dpad" else "KEY_STICK")
		return CTL.label_move()
	return CTL.label_of(action)

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, PAPER)
	var width := minf(1080.0, size.x - 80.0)
	var left := (size.x - width) * 0.5
	var top := maxf(20.0, (size.y - 650.0) * 0.5)
	draw_rect(Rect2(left, top, 5, 76), RED)
	draw_string(FONT_TITLE, Vector2(left + 22, top + 36), L10N.t("guide.title"), HORIZONTAL_ALIGNMENT_LEFT, width - 22, 34, INK)
	var device_key := "controls.controller" if CTL.device == "gamepad" else ("controls.touch" if CTL.device == "touch" else "controls.keyboard")
	draw_string(FONT_TEXT, Vector2(left + 22, top + 66), L10N.t(device_key), HORIZONTAL_ALIGNMENT_LEFT, width - 22, 18, RED)
	var row_h := minf(100.0, (size.y - top - 220.0) / 4.0)
	var card_w := (width - 20.0) * 0.5
	for i in ACTIONS.size():
		var rect := Rect2(left + (i % 2) * (card_w + 20.0), top + 100.0 + (i / 2) * row_h, card_w, row_h - 10.0)
		draw_rect(rect, Color("#f6edda"))
		draw_line(rect.position + Vector2(0, 1), Vector2(rect.end.x, rect.position.y + 1), Color(INK, 0.22), 1.0)
		var label := L10N.t("guide.move") if ACTIONS[i] == "move" else L10N.t("ACT_" + ACTIONS[i].to_upper())
		draw_string(FONT_BOLD, rect.position + Vector2(16, 27), label, HORIZONTAL_ALIGNMENT_LEFT, card_w - 32, 19, INK)
		var keys := binding(ACTIONS[i])
		var font_size := 21
		while font_size > 12 and FONT_TEXT.get_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > card_w - 32:
			font_size -= 1
		draw_string(FONT_TEXT, rect.position + Vector2(16, rect.size.y - 17), keys, HORIZONTAL_ALIGNMENT_LEFT, card_w - 32, font_size, RED)

func _consume_navigation() -> void:
	for action in ["jump", "attack", "dash", "pause", "back", "up", "down"]:
		CTL.consume(action)

# Geometry must also exist before a draw frame and with the headless renderer.
func _layout() -> void:
	if _button == null:
		return
	var top := maxf(20.0, (size.y - 650.0) * 0.5)
	_button.position = Vector2(size.x * 0.5 - 145, size.y - top - 68)
	_button.size = Vector2(290, 52)
	queue_redraw()

func _inside_button(point: Vector2) -> bool:
	var local := _button.get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(Vector2.ZERO, _button.size).has_point(local)

# Touch-to-mouse emulation is disabled in the project. Own the entire tap so
# dragging, canceled touches and additional fingers cannot activate the button.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _guard <= 0.0 and _touch_id == -1 and not event.canceled and _inside_button(event.position):
				_touch_id = event.index
				_touch_start = event.position
				get_viewport().set_input_as_handled()
		elif event.index == _touch_id:
			var activate: bool = not event.canceled and _inside_button(event.position) and event.position.distance_to(_touch_start) <= 24.0
			_touch_id = -1
			get_viewport().set_input_as_handled()
			if activate:
				dismiss()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		if not _inside_button(event.position) or event.position.distance_to(_touch_start) > 24.0:
			_touch_id = -1
		get_viewport().set_input_as_handled()
