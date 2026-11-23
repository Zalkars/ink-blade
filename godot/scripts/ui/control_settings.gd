extends Control

## Экран настроек в чернильном стиле 0.2 поверх доступной навигации
## (клавиатура, мышь, геймпад и сенсор) с учётом safe area.

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const CREAM := Color("#f6edda")

var flow: Node
var panel: PanelContainer
var pages: TabContainer
var status: Label
var capture := ""
var capture_pad := false
var capture_button: Button
var capture_time := 0.0
var editor: VBoxContainer
var size_slider: HSlider
var selected_label: Label
var snapshot := {}
var binding_buttons := {}
var _guard := 0.0
var _frame_layer: Control
var _phone_theme := false

func _phone_layout() -> bool:
	return CTL.touch_enabled or OS.has_feature("mobile")

func _responsive_layout() -> void:
	if panel == null:
		return
	_phone_theme = _phone_layout()
	theme = _build_theme()
	panel.offset_left = 20 if _phone_theme else 44
	panel.offset_right = -panel.offset_left
	panel.offset_top = 12 if _phone_theme else 20
	panel.offset_bottom = -panel.offset_top
	_resize_controls(panel)
	if editor != null:
		_resize_controls(editor)
	if _frame_layer != null:
		_frame_layer.queue_redraw()

func _resize_controls(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.custom_minimum_size.y = _target_height()
			if child.get_parent() is HBoxContainer and child.get_parent().get_child(0) is Label:
				child.custom_minimum_size.x = _field_width()
		elif child is HSlider:
			child.custom_minimum_size = Vector2(_field_width() - 80, _target_height())
		_resize_controls(child)

func _target_height() -> float:
	return 78.0 if _phone_layout() else 44.0

func _field_width() -> float:
	return clampf(size.x * 0.40, 320, 520) if _phone_layout() else 320.0


class _InkSettingsBg extends Control:
	func _draw() -> void:
		var owner_ctrl := get_parent() as Control
		var offset := owner_ctrl.position if owner_ctrl != null else Vector2.ZERO
		var vp := get_viewport_rect().size
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		InkR.save()
		InkR.t_translate(-offset.x, -offset.y)
		if InkR.tex_paper != null:
			draw_texture_rect(InkR.tex_paper, Rect2(0.0, 0.0, vp.x, vp.y), false)
		else:
			InkR.fill_rect_color(0.0, 0.0, vp.x, vp.y, PAPER, 1.0)
		InkR.radial_rect(0.0, 0.0, vp.x, vp.y, vp.x * 0.5, vp.y * 0.5, maxf(vp.x, vp.y) * 0.68, [
			[0.0, InkR.rgba(60, 10, 14, 0)],
			[1.0, InkR.rgba(39, 8, 11, 72)],
		])
		InkR.vignette_full(vp.x, vp.y)
		InkR.restore()


class _InkPanelFrame extends Control:
	var target: Control
	func _draw() -> void:
		if target == null or not target.visible:
			return
		var r := target.get_rect()
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		InkR.srand(int(r.position.x * 3.0 + r.position.y))
		InkR.save()
		InkR.alpha_push(0.28)
		InkR.fill_rect_color(r.position.x + 8.0, r.position.y + 9.0, r.size.x, r.size.y, INK, 1.0)
		InkR.restore()
		InkR.rect(r.position.x, r.position.y, r.size.x, r.size.y, InkR.rgba(246, 237, 218, 248), INK, 2.4, 1.0, 0.9)
		InkR.rect(r.position.x + 6.0, r.position.y + 6.0, r.size.x - 12.0, r.size.y - 12.0,
			null, InkR.rgba(23, 19, 15, 48), 1.0, 1.0, 0.6)
		var m := 12.0
		for c in [
			[r.position.x + m, r.position.y + m, 1.0, 1.0],
			[r.end.x - m, r.position.y + m, -1.0, 1.0],
			[r.position.x + m, r.end.y - m, 1.0, -1.0],
			[r.end.x - m, r.end.y - m, -1.0, -1.0],
		]:
			InkR.line(c[0], c[1], c[0] + 12.0 * c[2], c[1], 1.4, InkR.rgba(23, 19, 15, 92), 1.0, 0.8)
			InkR.line(c[0], c[1], c[0], c[1] + 12.0 * c[3], 1.4, InkR.rgba(23, 19, 15, 92), 1.0, 0.8)
		InkR.line(r.position.x + 28.0, r.position.y + 64.0, r.end.x - 28.0, r.position.y + 64.0,
			2.0, InkR.rgba(156, 33, 41, 155), 1.0, 1.0)
		InkR.save()
		InkR.alpha_push(0.68)
		InkR.circle(r.end.x - 26.0, r.end.y - 26.0, 11.0, null, RED, 1.6, 1.0, 0.7, 10)
		InkR.text(L10N.t("PANEL_SEAL"), r.end.x - 26.0, r.end.y - 21.0, 12.0, InkR.F_DISPLAY, InkR.A_CENTER, RED)
		InkR.restore()


func trc(key: String) -> String:
	return L10N.t("controls." + key)


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_TEXT
	t.default_font_size = 24 if _phone_layout() else 19
	t.set_color("font_color", "Label", INK)

	var page_box := StyleBoxFlat.new()
	page_box.bg_color = Color("#ede0c6")
	page_box.border_color = Color(INK, 0.35)
	page_box.set_border_width_all(1)
	page_box.set_content_margin_all(14)
	t.set_stylebox("panel", "TabContainer", page_box)

	for state_name in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		var tab_box := StyleBoxFlat.new()
		tab_box.bg_color = CREAM if state_name == "tab_selected" else (Color("#e5d5b7") if state_name == "tab_hovered" else Color("#d7c6a6"))
		tab_box.draw_center = state_name != "tab_focus"
		tab_box.border_color = RED if state_name in ["tab_selected", "tab_focus"] else Color(INK, 0.35)
		tab_box.set_border_width_all(1)
		if state_name == "tab_selected":
			tab_box.border_width_top = 3
		tab_box.content_margin_left = 18
		tab_box.content_margin_right = 18
		tab_box.content_margin_top = 22 if _phone_layout() else 10
		tab_box.content_margin_bottom = 22 if _phone_layout() else 10
		t.set_stylebox(state_name, "TabBar", tab_box)
		t.set_stylebox(state_name, "TabContainer", tab_box)
	for ctrl_type in ["TabBar", "TabContainer"]:
		t.set_font("font", ctrl_type, FONT_BOLD)
		t.set_font_size("font_size", ctrl_type, 23 if _phone_layout() else 17)
		t.set_color("font_selected_color", ctrl_type, RED)
		t.set_color("font_unselected_color", ctrl_type, Color(INK, 0.72))
		t.set_color("font_hovered_color", ctrl_type, RED)
	t.set_font("tab_font", "TabContainer", FONT_BOLD)
	t.set_font_size("tab_font_size", "TabContainer", 23 if _phone_layout() else 17)

	var transparent_panel := StyleBoxFlat.new()
	transparent_panel.bg_color = Color(0, 0, 0, 0)
	transparent_panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", transparent_panel)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = CREAM
	btn_normal.border_color = Color(INK, 0.7)
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(2)
	btn_normal.set_content_margin_all(9)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color("#eadbbf")
	btn_hover.border_color = RED
	btn_hover.set_border_width_all(2)
	btn_hover.set_corner_radius_all(2)
	btn_hover.set_content_margin_all(9)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = RED
	btn_pressed.border_color = INK
	btn_pressed.set_border_width_all(2)
	btn_pressed.set_corner_radius_all(2)
	btn_pressed.set_content_margin_all(9)

	var btn_focus := StyleBoxFlat.new()
	btn_focus.draw_center = false
	btn_focus.border_color = RED
	btn_focus.set_border_width_all(2)
	btn_focus.set_corner_radius_all(2)

	for kind in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", kind, btn_normal)
		t.set_stylebox("hover", kind, btn_hover)
		t.set_stylebox("pressed", kind, btn_pressed)
		t.set_stylebox("hover_pressed", kind, btn_pressed)
		t.set_stylebox("disabled", kind, btn_normal)
		t.set_stylebox("focus", kind, btn_focus)
		t.set_font("font", kind, FONT_BOLD)
		t.set_font_size("font_size", kind, 25 if _phone_layout() else 17)
		t.set_color("font_color", kind, INK)
		t.set_color("font_hover_color", kind, RED)
		t.set_color("font_focus_color", kind, INK)
		t.set_color("font_disabled_color", kind, Color(INK, 0.52))
		t.set_color("font_pressed_color", kind, CREAM)
		t.set_color("font_hover_pressed_color", kind, CREAM)

	var slider_track := StyleBoxFlat.new()
	slider_track.bg_color = Color(INK, 0.22)
	slider_track.content_margin_top = 4
	slider_track.content_margin_bottom = 4
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = RED
	slider_fill.content_margin_top = 4
	slider_fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_track)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	var popup_box := StyleBoxFlat.new()
	popup_box.bg_color = CREAM
	popup_box.border_color = INK
	popup_box.set_border_width_all(2)
	popup_box.set_content_margin_all(6)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color(RED, 0.16)
	t.set_stylebox("panel", "PopupMenu", popup_box)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", RED)
	t.set_font("font", "PopupMenu", FONT_TEXT)
	t.set_font_size("font_size", "PopupMenu", 25 if _phone_layout() else 19)
	t.set_constant("v_separation", "PopupMenu", 28 if _phone_layout() else 8)

	return t


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InkR.init_static()
	theme = _build_theme()
	_phone_theme = _phone_layout()

	var background := _InkSettingsBg.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_frame_layer = _InkPanelFrame.new()
	_frame_layer.name = "InkFrame"
	_frame_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_layer)

	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 44
	panel.offset_right = -44
	panel.offset_top = 20
	panel.offset_bottom = -20
	_frame_layer.target = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.text = trc("title")
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_color_override("font_color", INK)
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)

	pages = TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pages)

	_build_bindings(false)
	_build_bindings(true)
	_build_touch()
	_build_general()

	status = Label.new()
	status.text = ""
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(INK, 0.72))
	column.add_child(status)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	button(footer, trc("reset"), _reset_page)
	button(footer, trc("back"), go_back)

	_build_editor()
	resized.connect(_responsive_layout)
	_responsive_layout()
	visible = false


func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(160, _target_height())
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result


func page(label: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = label
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	pages.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	return column


func row(parent: Node, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	return line


func option(parent: Node, text: String, values: Array, current: int, callback: Callable) -> void:
	var line := row(parent, text)
	var control := OptionButton.new()
	control.custom_minimum_size = Vector2(_field_width(), _target_height())
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in values:
		control.add_item(trc(value))
	control.selected = current
	control.item_selected.connect(callback)
	line.add_child(control)


func slider(parent: Node, text: String, low: float, high: float, value: float, callback: Callable) -> HSlider:
	var line := row(parent, text)
	var control := HSlider.new()
	control.custom_minimum_size = Vector2(_field_width() - 80, _target_height())
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.min_value = low
	control.max_value = high
	control.step = 1
	control.value = value
	line.add_child(control)
	var number := Label.new()
	number.custom_minimum_size.x = 66
	number.text = "%d%%" % value
	line.add_child(number)
	control.value_changed.connect(func(v: float):
		number.text = "%d%%" % v
		callback.call(v))
	return control


func _build_bindings(pad: bool) -> void:
	var column := page(trc("controller" if pad else "keyboard"))
	if pad:
		option(column, trc("movement"), ["both", "stick", "dpad"], ["both", "stick", "dpad"].find(CTL.pad_movement), func(i: int):
			CTL.pad_movement = ["both", "stick", "dpad"][i]
			_save())
		slider(column, trc("deadzone"), 10, 60, CTL.pad_deadzone * 100, func(v: float):
			CTL.pad_deadzone = v / 100.0
			_save())
	var note := Label.new()
	note.text = trc("bind_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(INK, 0.72))
	column.add_child(note)
	for action in CTL.BINDABLE:
		if action == "back" or (pad and action in ["left", "right", "up", "down"]):
			continue
		var line := row(column, L10N.t("ACT_" + action.to_upper()))
		var control := button(line, CTL.label_pad(action) if pad else CTL.label_key(action), func(): _capture(action, pad))
		control.custom_minimum_size.x = _field_width()
		binding_buttons[("pad_" if pad else "key_") + action] = control


func _build_touch() -> void:
	var column := page(trc("touch"))
	option(column, trc("movement"), ["floating", "stick", "dpad"], ["floating", "stick", "dpad"].find(CTL.touch_style), func(i: int):
		CTL.touch_style = ["floating", "stick", "dpad"][i]
		flow.mobile_controls.reset()
		_save())
	slider(column, trc("opacity"), 25, 100, CTL.touch_opacity * 100, func(v: float):
		CTL.touch_opacity = v / 100.0
		_save())
	var note := Label.new()
	note.text = trc("layout_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(INK, 0.78))
	column.add_child(note)
	button(column, trc("edit"), start_editor)


func _build_editor() -> void:
	editor = VBoxContainer.new()
	add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	editor.offset_left = 24
	editor.offset_right = -180
	editor.offset_top = 12
	var bar := PanelContainer.new()
	var bar_box := StyleBoxFlat.new()
	bar_box.bg_color = Color(CREAM, 0.96)
	bar_box.border_color = INK
	bar_box.set_border_width_all(2)
	bar_box.set_content_margin_all(12)
	bar.add_theme_stylebox_override("panel", bar_box)
	editor.add_child(bar)
	var column := VBoxContainer.new()
	bar.add_child(column)
	var line := HBoxContainer.new()
	column.add_child(line)
	selected_label = Label.new()
	selected_label.clip_text = true
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.add_theme_color_override("font_color", INK)
	line.add_child(selected_label)
	button(line, trc("save"), func(): finish_editor(true))
	button(line, trc("cancel"), func(): finish_editor(false))
	size_slider = slider(column, trc("size"), 65, 150, 100, func(v: float):
		flow.mobile_controls.resize_selected(v / 100.0))
	editor.visible = false


func open() -> void:
	_responsive_layout()
	_relabel()
	visible = true
	_guard = 0.2
	panel.visible = true
	get_node("Background").visible = true
	_frame_layer.visible = true
	_frame_layer.queue_redraw()
	get_node("Background").queue_redraw()
	pages.get_tab_bar().focus_mode = Control.FOCUS_ALL
	pages.get_tab_bar().grab_focus()


func _save() -> void:
	status.text = trc("saved" if CTL.save_controls() == OK else "save_error")


func _refresh_bindings() -> void:
	for key in binding_buttons:
		var action: String = key.substr(4)
		binding_buttons[key].text = CTL.label_pad(action) if key.begins_with("pad_") else CTL.label_key(action)


func _capture(action: String, pad: bool) -> void:
	capture = action
	capture_pad = pad
	capture_time = 8.0
	capture_button = binding_buttons[("pad_" if pad else "key_") + action]
	capture_button.text = trc("press")
	status.text = trc("capture_note")


func _end_capture() -> void:
	capture = ""
	_guard = 0.2
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Tab changes can discard the old page's focused control. Let a pad enter
	# the new page directly, including after mouse/touch cleared GUI focus.
	if capture.is_empty() and event.is_action_pressed("ui_down"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or focused == pages.get_tab_bar():
			var first := _first_focusable(pages.get_current_tab_control())
			if first != null:
				first.grab_focus()
				get_viewport().set_input_as_handled()
				return
	if not capture.is_empty():
		var code := 0
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_end_capture()
			elif not capture_pad:
				code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		elif not capture_pad and event is InputEventMouseButton and event.pressed and event.button_index in [1, 2, 3, 8, 9]:
			code = -event.button_index
		elif capture_pad and event is InputEventJoypadButton and event.pressed:
			code = CTL.slot_of_joy(event.button_index) + 1
		elif capture_pad and event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.65:
			code = 7 if event.axis == JOY_AXIS_TRIGGER_LEFT else 8
		if code != 0 and not capture.is_empty():
			var ok: bool = CTL.set_pad(capture, code - 1) if capture_pad else CTL.set_key(capture, code)
			if ok:
				_save()
				_end_capture()
			else:
				status.text = trc("reserved")
		get_viewport().set_input_as_handled()
		return
	if _guard <= 0.0 and ((event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START])):
		go_back()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _phone_theme != _phone_layout():
		_responsive_layout()
	_guard = maxf(0.0, _guard - delta)
	if not capture.is_empty():
		capture_time -= delta
		if capture_time <= 0:
			_end_capture()
			status.text = trc("timeout")
	_frame_layer.queue_redraw()


func _first_focusable(node: Node) -> Control:
	if node is Control and node.focus_mode == Control.FOCUS_ALL and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _first_focusable(child)
		if found != null:
			return found
	return null


func _reset_page() -> void:
	match pages.current_tab:
		0: CTL.keyboard = CTL.DEFAULT_KEYBOARD.duplicate(true)
		1:
			for action in CTL.ACTIONS:
				CTL.pad_map[action] = CTL.DEFAULT_PAD.get(action, []).duplicate()
			CTL.pad_movement = "both"
			CTL.pad_deadzone = 0.32
		3:
			flow.shake_enabled = true
			flow.master_volume = 0.8
			CTL.vibration_enabled = true
			SND.set_muted(false)
			flow.vsync_enabled = true
			flow.resolution_index = 0
			flow.save_preferences()
		2:
			CTL.touch_layout.clear()
			CTL.touch_style = "floating"
			CTL.touch_opacity = 0.8
	_save()
	var index := pages.current_tab
	for child in pages.get_children():
		pages.remove_child(child)
		child.queue_free()
	binding_buttons.clear()
	_build_bindings(false)
	_build_bindings(true)
	_build_touch()
	_build_general()
	pages.current_tab = index
	pages.get_tab_bar().grab_focus()


func start_editor() -> void:
	snapshot = CTL.touch_layout.duplicate(true)
	panel.visible = false
	get_node("Background").visible = false
	_frame_layer.visible = false
	editor.visible = true
	flow.mobile_controls.begin_edit()
	select_element("move")


func select_element(action: String) -> void:
	selected_label.text = trc("drag") + " · " + (trc("movement") if action == "move" else L10N.t("ACT_" + action.to_upper()))
	size_slider.set_value_no_signal(flow.mobile_controls.element_scale(action) * 100.0)
	size_slider.get_parent().get_child(2).text = "%d%%" % size_slider.value


func finish_editor(save: bool) -> void:
	if save and flow.mobile_controls.has_overlap():
		selected_label.text = trc("overlap")
		return
	if not save:
		CTL.touch_layout = snapshot.duplicate(true)
	flow.mobile_controls.end_edit()
	editor.visible = false
	panel.visible = true
	get_node("Background").visible = true
	_frame_layer.visible = true
	if save:
		_save()
	pages.get_tab_bar().grab_focus()


func go_back() -> void:
	if not capture.is_empty():
		_end_capture()
	elif editor.visible:
		finish_editor(false)
	else:
		visible = false
		flow.close_settings()


func toggle(parent: Node, key: String, value: bool, callback: Callable) -> void:
	var line := row(parent, trc(key))
	var control := CheckButton.new()
	control.custom_minimum_size = Vector2(_field_width(), _target_height())
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.button_pressed = value
	line.add_child(control)
	control.toggled.connect(callback)


func _build_general() -> void:
	var column := page(trc("general"))
	toggle(column, "sound", not SND.muted, func(v: bool):
		SND.set_muted(not v)
		flow.save_preferences())
	slider(column, trc("volume"), 0, 100, flow.master_volume * 100, func(v: float):
		flow.master_volume = v / 100.0
		flow.save_preferences())
	toggle(column, "shake", flow.shake_enabled, func(v: bool):
		flow.shake_enabled = v
		flow.camera.offset = Vector2.ZERO
		flow.camera.rotation = 0
		flow.save_preferences())
	toggle(column, "vibration", CTL.vibration_enabled, func(v: bool):
		CTL.vibration_enabled = v
		flow.save_preferences())
	var line := row(column, trc("language"))
	var language := OptionButton.new()
	language.custom_minimum_size = Vector2(_field_width(), _target_height())
	language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var codes := L10N.languages()
	for code in codes:
		language.add_item(code.to_upper())
	language.selected = codes.find(L10N.lang)
	line.add_child(language)
	language.item_selected.connect(func(i: int):
		L10N.set_lang(codes[i])
		flow.title_screen.refresh()
		flow.hud._rebuild_hint()
		_relabel.call_deferred())
	if not OS.has_feature("mobile"):
		toggle(column, "fullscreen", DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN], func(_v: bool): flow._toggle_fullscreen())
		var resolution_line := row(column, trc("resolution"))
		var resolution := OptionButton.new()
		resolution.custom_minimum_size = Vector2(_field_width(), _target_height())
		resolution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for value in flow.RESOLUTIONS:
			resolution.add_item("%d × %d" % [value.x, value.y])
		resolution.selected = flow.resolution_index
		resolution_line.add_child(resolution)
		resolution.item_selected.connect(func(i: int):
			flow.resolution_index = i
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_size(flow.RESOLUTIONS[i])
			flow.save_preferences())
		toggle(column, "vsync", flow.vsync_enabled, func(v: bool):
			flow.vsync_enabled = v
			flow.save_preferences())


func _relabel() -> void:
	var index := pages.current_tab
	for child in pages.get_children():
		pages.remove_child(child)
		child.queue_free()
	binding_buttons.clear()
	_build_bindings(false)
	_build_bindings(true)
	_build_touch()
	_build_general()
	pages.current_tab = index
	panel.get_child(0).get_child(0).text = trc("title")
	status.text = ""
	var footer := panel.get_child(0).get_child(3)
	footer.get_child(0).text = trc("reset")
	footer.get_child(1).text = trc("back")
