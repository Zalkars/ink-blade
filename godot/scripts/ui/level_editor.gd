extends Control

const EditorCanvas := preload("res://scripts/ui/level_editor_canvas.gd")
const Decor := preload("res://scripts/world/level_decor.gd")
const FONT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const DISPLAY := preload("res://assets/fonts/Underdog-Regular.ttf")
const PAPER := Color("#eee2c9")
const INK := Color("#211b19")
const RED := Color("#932b2d")

var flow: Node
var draft := LevelDraft.new()
var canvas: Control
var palette: ItemList
var _stored: OptionButton
var _templates: OptionButton
var _level_id: LineEdit
var _level_name: LineEdit
var _width: SpinBox
var _height: SpinBox
var _selected: Label
var _status: Label
var _undo: Button
var _redo: Button
var _open: Button
var _confirm: ConfirmationDialog
var _pending := Callable()
var _previewed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS
	z_index = 40
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	_build_header(layout)
	_build_properties(layout)
	_build_workspace(layout)
	_status = _label("", 16)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.title = L10N.t("editor.title")
	_confirm.ok_button_text = L10N.t("editor.confirm")
	_confirm.cancel_button_text = L10N.t("editor.cancel")
	_confirm.confirmed.connect(_accept_pending)
	_confirm.canceled.connect(func(): _pending = Callable())
	add_child(_confirm)
	draft.saved = draft.data.duplicate(true)
	_sync(true)
	hide()


func _build_header(layout: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	layout.add_child(top)
	var heading := _label(L10N.t("editor.title"), 25)
	heading.add_theme_font_override("font", DISPLAY)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(_button("editor.new", _new_requested))
	_stored = OptionButton.new()
	_stored.custom_minimum_size.x = 124
	top.add_child(_stored)
	_open = _button("editor.open", _open_requested)
	top.add_child(_open)
	top.add_child(_button("editor.save", _save_requested))
	top.add_child(_button("editor.playtest", _playtest, true))
	top.add_child(_button("editor.close", request_close))


func _build_properties(layout: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	layout.add_child(row)
	row.add_child(_label("ID", 14))
	_level_id = LineEdit.new()
	_level_id.max_length = 48
	_level_id.custom_minimum_size.x = 174
	row.add_child(_level_id)
	_level_name = LineEdit.new()
	_level_name.placeholder_text = L10N.t("editor.level_name")
	_level_name.max_length = 80
	_level_name.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_level_name)
	_width = _size_field(row, "editor.width", 640, LevelDraft.MAX_SIZE.x)
	_height = _size_field(row, "editor.height", 384, LevelDraft.MAX_SIZE.y)
	row.add_child(_button("editor.apply", _apply_and_report))
	_templates = OptionButton.new()
	_templates.custom_minimum_size.x = 104
	row.add_child(_templates)
	row.add_child(_button("editor.clone", _clone_requested))


func _build_workspace(layout: VBoxContainer) -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(main)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 248
	main.add_child(sidebar)
	sidebar.add_child(_label(L10N.t("editor.palette"), 20))
	palette = ItemList.new()
	palette.size_flags_vertical = SIZE_EXPAND_FILL
	palette.add_theme_font_override("font", FONT)
	palette.add_theme_font_size_override("font_size", 16)
	palette.add_theme_constant_override("v_separation", 7)
	palette.add_theme_stylebox_override("panel", _style(Color("#382b26"), INK))
	palette.add_theme_stylebox_override("selected", _style(RED, RED))
	palette.add_theme_stylebox_override("selected_focus", _style(RED, RED))
	palette.item_selected.connect(func(index: int):
		canvas.tool = str(palette.get_item_metadata(index))
		canvas.queue_redraw())
	sidebar.add_child(palette)
	var info := _label(L10N.t("editor.hint"), 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(info)
	var main_area := VBoxContainer.new()
	main_area.size_flags_horizontal = SIZE_EXPAND_FILL
	main.add_child(main_area)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	main_area.add_child(toolbar)
	_undo = _button("editor.undo", _undo_action)
	_redo = _button("editor.redo", _redo_action)
	toolbar.add_child(_undo)
	toolbar.add_child(_redo)
	toolbar.add_child(_button("editor.delete", func(): canvas.delete_selected()))
	toolbar.add_child(_button("editor.duplicate", func(): canvas.duplicate_selected()))
	toolbar.add_child(_button("editor.fit", func(): canvas.fit()))
	toolbar.add_child(_button("editor.zoom_out", func(): canvas.adjust_zoom(1.0 / 1.22, canvas.size * 0.5)))
	toolbar.add_child(_button("editor.zoom_in", func(): canvas.adjust_zoom(1.22, canvas.size * 0.5)))
	var decor := _button("editor.preview_decor", func():
		canvas.hide_decor = not canvas.hide_decor
		canvas.queue_redraw())
	decor.toggle_mode = true
	decor.set_pressed_no_signal(true)
	toolbar.add_child(decor)
	canvas = EditorCanvas.new()
	canvas.draft = draft
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	canvas.size_flags_vertical = SIZE_EXPAND_FILL
	canvas.changed.connect(_after_edit)
	canvas.selection_changed.connect(_update_selection)
	main_area.add_child(canvas)
	_selected = _label("", 15)
	main_area.add_child(_selected)


func _size_field(row: HBoxContainer, key: String, lower: int, upper: int) -> SpinBox:
	row.add_child(_label(L10N.t(key), 14))
	var field := SpinBox.new()
	field.min_value = lower
	field.max_value = upper
	field.step = LevelDraft.GRID
	field.custom_minimum_size.x = 77
	row.add_child(field)
	return field


func _populate_palette() -> void:
	var chosen: String = canvas.tool
	palette.clear()
	for key in ["select", "resize", "pan", "erase", "solid", "platform", "ledge", "bridge", "steps", "spawn", "checkpoint"]:
		_palette_item(key, L10N.t("editor.tool_" + key))
	for id in DB.ids():
		var card := DB.get_def(id)
		var label := L10N.t(card.display_name_key) if not card.display_name_key.is_empty() else str(id)
		_palette_item("enemy:" + str(id), L10N.t("editor.enemy_small_blot") if id == &"enemy.blot_small" else label)
	for id in PDB.ids():
		_palette_item("prop:" + str(id), L10N.t(PDB.get_def(id).display_name_key))
	for kind in Decor.DECOR_SIZES:
		_palette_item("decor:" + kind, L10N.t("editor.decor_" + kind))
	for index in palette.item_count:
		if palette.get_item_metadata(index) == chosen:
			palette.select(index)
			break


func _palette_item(key: String, label: String) -> void:
	palette.add_item(label)
	palette.set_item_metadata(palette.item_count - 1, key)
	palette.set_item_tooltip(palette.item_count - 1, label)


func open() -> void:
	show()
	_populate_palette()
	_update_saved_list()
	_templates.clear()
	for id in LVL.ids():
		_templates.add_item(id)
	_sync(true)
	canvas.grab_focus()
	if not _previewed:
		canvas.call_deferred("fit")
		_previewed = true
	_show_errors()


func request_close() -> void:
	_apply_properties()
	_discard_or(flow.close_level_editor, "editor.confirm_discard")


func _input(event: InputEvent) -> void:
	if not visible or _confirm.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		request_close()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_save_requested()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo_action()
		else:
			_undo_action()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_action()
	elif event.ctrl_pressed and event.keycode == KEY_D:
		canvas.duplicate_selected()
	elif event.keycode == KEY_F8:
		_playtest()
	else:
		return
	get_viewport().set_input_as_handled()


func _new_requested() -> void:
	_apply_properties()
	_discard_or(_new_document, "editor.confirm_discard")


func _new_document() -> void:
	var index := 1
	var stored := LevelDraft.files()
	while "custom_%d" % index in stored:
		index += 1
	draft.start("custom_%d" % index, L10N.t("editor.new_name"))
	_document_changed()


func _open_requested() -> void:
	if _stored.selected < 0 or _open.disabled:
		return
	_apply_properties()
	var id := _stored.get_item_text(_stored.selected)
	_discard_or(_load_document.bind(id), "editor.confirm_discard")


func _load_document(id: String) -> void:
	var data := LevelDraft.read(id)
	var errors := LevelDraft.validate_world(data)
	if data.get("id") != id or not errors.is_empty():
		_report(L10N.t("editor.error_file", [id]), true)
		return
	draft.replace(data)
	_document_changed()


func _clone_requested() -> void:
	if _templates.selected < 0:
		return
	_apply_properties()
	var id := _templates.get_item_text(_templates.selected)
	_discard_or(_clone_document.bind(id), "editor.confirm_discard")


func _clone_document(id: String) -> void:
	var base := LVL.get_level(id)
	if base == null:
		return
	var copy := id + "_copy"
	var suffix := 2
	var stored := LevelDraft.files()
	while copy in stored:
		copy = "%s_copy_%d" % [id, suffix]
		suffix += 1
	draft.clone_world(base.world, copy)
	_document_changed()


func _document_changed() -> void:
	_sync(true)
	canvas.refresh()
	canvas.fit()
	_show_errors()


func _apply_properties() -> void:
	var bounds: Dictionary = draft.data.bounds
	var id := _level_id.text.strip_edges()
	var title := _level_name.text.strip_edges()
	if id == draft.data.id and title == draft.data.get("name", "") \
			and _width.value == bounds.w and _height.value == bounds.h:
		return
	draft.edit()
	draft.data.id = id
	draft.data.name = title
	bounds.w = int(_width.value)
	bounds.h = int(_height.value)
	canvas.refresh(false)


func _apply_and_report() -> void:
	_apply_properties()
	_after_edit()


func _save_requested() -> void:
	_apply_and_report()
	if not draft.validate().is_empty():
		return
	if draft.data.id in LevelDraft.files() and draft.saved.get("id") != draft.data.id:
		_ask(_write, "editor.confirm_replace")
		return
	_write()


func _write() -> void:
	var result := draft.save()
	if result != OK:
		_report(L10N.t("editor.error_save", [error_string(result)]), true)
		return
	_update_saved_list()
	_sync(false)
	_report(L10N.t("editor.saved", [draft.data.id]), false)


func _playtest() -> void:
	_apply_and_report()
	if draft.validate().is_empty() and not flow.start_editor_test(draft.data):
		_report(L10N.t("editor.error_playtest"), true)


func _undo_action() -> void:
	draft.undo()
	_sync(true)
	canvas.refresh()
	_show_errors()


func _redo_action() -> void:
	draft.redo()
	_sync(true)
	canvas.refresh()
	_show_errors()


func _after_edit() -> void:
	_sync(false)
	_update_selection()
	_show_errors()


func _sync(properties: bool) -> void:
	if properties:
		_level_id.text = str(draft.data.id)
		_level_name.text = str(draft.data.get("name", ""))
		_width.value = draft.data.bounds.w
		_height.value = draft.data.bounds.h
	_undo.disabled = draft.undo_stack.is_empty()
	_redo.disabled = draft.redo_stack.is_empty()
	_update_selection()


func _update_selection() -> void:
	var item: Dictionary = draft.item(canvas.selection)
	if item.is_empty():
		_selected.text = L10N.t("editor.no_selection")
		return
	var name := str(item.get("def_id", item.get("kind", item.get("id", LevelDraft.SECTIONS[canvas.selection.x]))))
	var dimensions := "   ·   %d × %d" % [int(item.w), int(item.h)] if item.has("w") else ""
	_selected.text = "%s   ·   X %d   Y %d%s" % [name, int(item.x), int(item.y), dimensions]


func _update_saved_list() -> void:
	_stored.clear()
	var stored := LevelDraft.files()
	_open.disabled = stored.is_empty()
	if stored.is_empty():
		_stored.add_item(L10N.t("editor.no_drafts"))
		return
	for id in stored:
		_stored.add_item(id)
	if draft.data.id in stored:
		_stored.select(stored.find(draft.data.id))


func _discard_or(action: Callable, key: String) -> void:
	if draft.dirty():
		_ask(action, key)
	else:
		action.call()


func _ask(action: Callable, key: String) -> void:
	_pending = action
	_confirm.dialog_text = L10N.t(key)
	_confirm.popup_centered(Vector2i(370, 150))
	_confirm.get_cancel_button().grab_focus()


func _accept_pending() -> void:
	var action := _pending
	_pending = Callable()
	if action.is_valid():
		action.call()


func _show_errors() -> void:
	var errors := draft.validate()
	if errors.is_empty():
		_report(L10N.t("editor.dirty" if draft.dirty() else "editor.ready"), false)
	else:
		_report(errors[0], true)


func _report(message: String, error: bool) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", RED if error else INK)


func _label(value: String, pixels: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", pixels)
	return label


func _button(key: String, action: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = L10N.t(key)
	button.custom_minimum_size.y = 33
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _style(RED if accent else PAPER.darkened(0.05), RED))
	button.add_theme_stylebox_override("hover", _style(RED, RED))
	button.add_theme_stylebox_override("pressed", _style(RED, RED))
	button.add_theme_stylebox_override("disabled", _style(PAPER.darkened(0.08), PAPER.darkened(0.18)))
	var focus := _style(PAPER, RED)
	focus.draw_center = false
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", PAPER if accent else INK)
	button.add_theme_color_override("font_focus_color", PAPER if accent else INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color(INK, 0.46))
	button.pressed.connect(action)
	return button


func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style
