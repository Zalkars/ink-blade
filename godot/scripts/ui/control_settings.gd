extends Control

## Native controls provide mouse, touch, keyboard focus and controller navigation.
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

func trc(key: String) -> String:
	return L10N.t("controls." + key)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme_new := Theme.new()
	theme_new.default_font = preload("res://assets/fonts/PTSerif-Regular.ttf")
	theme_new.default_font_size = 20
	theme_new.set_color("font_color", "Label", Color("#17130f"))
	var page_box := StyleBoxFlat.new()
	page_box.bg_color = Color("#e6d9bf")
	page_box.set_content_margin_all(14)
	theme_new.set_stylebox("panel", "TabContainer", page_box)
	for state_name in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tab_box := StyleBoxFlat.new()
		tab_box.bg_color = Color("#e6d9bf") if state_name == "tab_selected" else Color("#ccbea5")
		tab_box.content_margin_left = 16
		tab_box.content_margin_right = 16
		tab_box.content_margin_top = 10
		tab_box.content_margin_bottom = 10
		theme_new.set_stylebox(state_name, "TabBar", tab_box)
	for color_name in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		theme_new.set_color(color_name, "TabBar", Color("#17130f"))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#f1e6d0")
	box.border_color = Color("#9c1f24")
	box.set_border_width_all(2)
	box.set_content_margin_all(18)
	theme_new.set_stylebox("panel", "PanelContainer", box)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#302923")
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(10)
	theme_new.set_stylebox("normal", "Button", normal)
	theme_new.set_stylebox("normal", "OptionButton", normal)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("#c24435")
	focus.set_border_width_all(3)
	theme_new.set_stylebox("focus", "Button", focus)
	theme = theme_new
	var background := ColorRect.new()
	background.color = Color("#f1e6d0")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.name = "Background"
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 44
	panel.offset_right = -44
	panel.offset_top = 20
	panel.offset_bottom = -20
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = trc("title")
	title.add_theme_color_override("font_color", Color("#17130f"))
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	pages = TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pages)
	_build_bindings(false)
	_build_bindings(true)
	_build_touch()
	_build_general()
	status = Label.new()
	status.text = trc("hint")
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color("#17130f"))
	column.add_child(status)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	button(footer, trc("reset"), _reset_page)
	button(footer, trc("back"), go_back)
	_build_editor()
	visible = false

func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(160, 48)
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
	line.add_child(label)
	return line

func option(parent: Node, text: String, values: Array, current: int, callback: Callable) -> void:
	var line := row(parent, text)
	var control := OptionButton.new()
	control.custom_minimum_size = Vector2(320, 48)
	for value in values:
		control.add_item(trc(value))
	control.selected = current
	control.item_selected.connect(callback)
	line.add_child(control)

func slider(parent: Node, text: String, low: float, high: float, value: float, callback: Callable) -> HSlider:
	var line := row(parent, text)
	var control := HSlider.new()
	control.custom_minimum_size = Vector2(240, 48)
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
	note.text = trc("pad_note" if pad else "key_note")
	note.add_theme_font_size_override("font_size", 16)
	column.add_child(note)
	for action in CTL.BINDABLE:
		if action == "back" or (pad and action in ["left", "right", "up", "down"]):
			continue
		var line := row(column, L10N.t("ACT_" + action.to_upper()))
		var control := button(line, CTL.label_pad(action) if pad else CTL.label_key(action), func(): _capture(action, pad))
		control.custom_minimum_size.x = 320
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
	note.text = trc("touch_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	editor.add_child(bar)
	var column := VBoxContainer.new()
	bar.add_child(column)
	var line := HBoxContainer.new()
	column.add_child(line)
	selected_label = Label.new()
	selected_label.clip_text = true
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.add_theme_color_override("font_color", Color("#17130f"))
	line.add_child(selected_label)
	button(line, trc("save"), func(): finish_editor(true))
	button(line, trc("cancel"), func(): finish_editor(false))
	size_slider = slider(column, trc("size"), 65, 150, 100, func(v: float):
		flow.mobile_controls.resize_selected(v / 100.0))
	editor.visible = false

func open() -> void:
	_relabel()
	visible = true
	_guard = 0.2
	panel.visible = true
	get_node("Background").visible = true
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
	status.text = trc("capture_hint")

func _end_capture() -> void:
	capture = ""
	_guard = 0.2
	_refresh_bindings()

func _input(event: InputEvent) -> void:
	if not visible:
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
	_guard = maxf(0.0, _guard - delta)
	if not capture.is_empty():
		capture_time -= delta
		if capture_time <= 0:
			_end_capture()
			status.text = trc("timeout")

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
	# Rebuild controls to reflect reset slider and selector values.
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
	editor.visible = true
	flow.mobile_controls.begin_edit()
	select_element("move")

func select_element(action: String) -> void:
	selected_label.text = trc("drag") + " · " + (trc("movement") if action == "move" else L10N.t("ACT_" + action.to_upper()))
	size_slider.set_value_no_signal(flow.mobile_controls.element_scale(action) * 100.0)
	# Keep the numeric label in sync without resizing the previous selection.
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
	control.custom_minimum_size = Vector2(320, 48)
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
	language.custom_minimum_size = Vector2(320,48)
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
		resolution.custom_minimum_size = Vector2(320,48)
		for value in flow.RESOLUTIONS:
			resolution.add_item("%d × %d" % [value.x,value.y])
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
	status.text = trc("hint")
	var footer := panel.get_child(0).get_child(3)
	footer.get_child(0).text = trc("reset")
	footer.get_child(1).text = trc("back")
