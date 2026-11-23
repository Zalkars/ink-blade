extends Control

const PAPER := Color("#f1e6d0")
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const FONT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")

var flow: Node
var _card: PanelContainer
var _body: VBoxContainer
var _status: Label
var _section := "player"
var _tabs: Dictionary = {}
var _prior_pause := false
var _close: Button
var _heading: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	var scrim := ColorRect.new()
	scrim.color = Color(INK, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _surface(PAPER, RED, 2, 22.0))
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_card.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_heading = _label("debug.title", 28)
	_heading.add_theme_font_override("font", TITLE)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	_close = _button("debug.close", close)
	header.add_child(_close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for section in ["player", "map", "diagnostics"]:
		var tab := _button("debug." + section, _show_section.bind(section))
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs[section] = tab
		tabs.add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_status = _label("debug.hint", 15)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_status)
	resized.connect(_layout)
	_layout()
	hide()


func _layout() -> void:
	var card_size := Vector2(minf(size.x - 40.0, 780.0), minf(size.y - 34.0, 590.0))
	_card.position = (size - card_size) * 0.5
	_card.size = card_size


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	if flow.console.visible:
		flow.console.close()
	_prior_pause = get_tree().paused
	get_tree().paused = true
	CTL.clear_touch()
	show()
	_heading.text = L10N.t("debug.title")
	_close.text = L10N.t("debug.close")
	for key in _tabs:
		_tabs[key].text = L10N.t("debug." + key)
	_show_section(_section)
	_close.grab_focus()
	_status.text = L10N.t("debug.hint")
	flow.mobile_controls.refresh_draw_state()


func close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = _prior_pause or flow.state not in [flow.State.TITLE, flow.State.PLAY]
	CTL.clear_touch()
	CTL.consume("pause")
	CTL.consume("back")
	flow._on_console_toggled()
	flow.mobile_controls.refresh_draw_state()


func _show_section(section: String) -> void:
	_section = section
	for key in _tabs:
		_tabs[key].set_pressed_no_signal(key == section)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match section:
		"player":
			_toggle("flight", "cheat")
			_toggle("god", "cheat")
			_toggle("damage", "cheat")
			_number("speed", 50, 1800, 10, flow.debug_flight_speed)
			if is_instance_valid(flow.player):
				_number("hp", 1, flow.player.MAX_HP, 1, flow.player.hp)
				_number("soul", 0, 99, 0.1, flow.player.soul)
				_body.add_child(_button("debug.respawn", _respawn))
				_warp_row()
		"map":
			for key in ["enemies", "particles", "platforms", "background"]:
				_toggle(key, "map")
			for id in LVL.ids(flow.qa_session):
				var button := _button("", _load_level.bind(id))
				button.text = id
				_body.add_child(button)
		"diagnostics":
			var metrics := _label("", 17)
			metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			metrics.text = flow.console.inspect_player()
			_body.add_child(metrics)
			for page in [["help", 1], ["performance", 2], ["world", 3]]:
				_body.add_child(_button("debug." + page[0], _diagnostics.bind(page[1])))
			_body.add_child(_button("debug.hitboxes", _hitboxes))
			_body.add_child(_button("debug.reset", _reset))


func _toggle(key: String, command: String) -> void:
	var item := _button("debug." + key, func(): pass)
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.toggle_mode = true
	item.set_pressed_no_signal(flow.debug_rules[key])
	var label := L10N.t("debug." + key)
	var set_text := func(enabled: bool):
		item.text = ("●  " if enabled else "○  ") + label
	set_text.call(item.button_pressed)
	item.toggled.connect(func(enabled: bool):
		_command("%s %s %s" % [command, key, "on" if enabled else "off"])
		set_text.call(enabled))
	_body.add_child(item)


func _number(key: String, low: float, high: float, step: float, value: float) -> void:
	var row := HBoxContainer.new()
	var label := _label("debug." + key, 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step
	field.value = value
	field.custom_minimum_size.x = 105
	row.add_child(field)
	row.add_child(_button("debug.apply", func(): _command("set %s %s" % [key, str(field.value)])))
	_body.add_child(row)


func _warp_row() -> void:
	var row := HBoxContainer.new()
	var x := LineEdit.new()
	var y := LineEdit.new()
	x.text = str(roundi(flow.player.global_position.x))
	y.text = str(roundi(flow.player.global_position.y))
	x.placeholder_text = "X"
	y.placeholder_text = "Y"
	for field in [x, y]:
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(field)
	row.add_child(_button("debug.warp", func(): _command("warp %s %s" % [x.text, y.text])))
	_body.add_child(row)


func _command(command: String) -> void:
	_status.text = flow.console.execute(command, true)


func _respawn() -> void:
	_command("respawn")
	_prior_pause = false
	close()


func _load_level(id: String) -> void:
	_command("level " + id)
	_prior_pause = get_tree().paused
	close()


func _diagnostics(page: int) -> void:
	flow.hud.debug_page = 0 if flow.hud.debug_page == page else page
	close()


func _hitboxes() -> void:
	flow.hud.debug_on = not flow.hud.debug_on
	close()


func _reset() -> void:
	_command("reset")
	_show_section(_section)


func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = L10N.t(key) if not key.is_empty() else ""
	button.custom_minimum_size.y = 36.0
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var on: bool = state in ["hover", "pressed", "hover_pressed"]
		var style := _surface(RED if on else PAPER.darkened(0.05), RED, 1, 10.0)
		style.draw_center = state != "focus"
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.pressed.connect(action)
	return button


func _label(key: String, size_px: int) -> Label:
	var label := Label.new()
	label.text = L10N.t(key) if not key.is_empty() else ""
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size_px)
	return label


func _surface(fill: Color, edge: Color, weight: int, padding: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(weight)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.65
	style.content_margin_bottom = padding * 0.65
	return style
