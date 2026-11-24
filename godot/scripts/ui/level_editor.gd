extends Control

const EditorCanvas := preload("res://scripts/ui/level_editor_canvas.gd")
const Decor := preload("res://scripts/world/level_decor.gd")
const FONT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const DISPLAY := preload("res://assets/fonts/Underdog-Regular.ttf")
const PAPER := Color("#efe5d3")
const PANEL := Color("#f8f0e2")
const FIELD := Color("#fffaef")
const BORDER := Color("#cbbca7")
const INK := Color("#29211e")
const MUTED := Color("#6d5b50")
const RED := Color("#8e302f")
const TOOL_GROUPS := ["edit", "terrain", "actors", "logic", "decor"]
const DETAIL_PAGES := ["object", "map", "layers", "test"]

var flow: Node
var draft := LevelDraft.new()
var canvas: Control
var palette: ItemList
var _file: MenuButton
var _picker: ConfirmationDialog
var _map_list: ItemList
var _copying_map := false
var _document_title: Label
var _document_id: Label
var _changed_mark: Label
var _level_id: LineEdit
var _level_name: LineEdit
var _width: SpinBox
var _height: SpinBox
var _selected: Label
var _inspector: VBoxContainer
var _item_fields: Dictionary[String, SpinBox] = {}
var _item_actions: HBoxContainer
var _object_help: Label
var _link_help: Label
var _duplicate: Button
var _delete: Button
var _target_room: LineEdit
var _target_entry: LineEdit
var _target_requires: LineEdit
var _link_rows: Dictionary[String, VBoxContainer] = {}
var _layer_toggles := {}
var _details: PanelContainer
var _detail_toggle: Button
var _detail_pages: Dictionary[String, ScrollContainer] = {}
var _detail_buttons: Dictionary[String, Button] = {}
var _detail_tab := "object"
var _tool_buttons: Dictionary[String, Button] = {}
var _tools: Dictionary = {}
var _last_tool: Dictionary = {}
var _tool_group := ""
var _tool_hint: Label
var _view_zoom: Label
var _view_cursor: Label
var _test_start: OptionButton
var _test_weapon: OptionButton
var _test_soul: SpinBox
var _route: MenuButton
var _json_dialog: FileDialog
var _json_data: Dictionary
var _status: Label
var _undo: Button
var _redo: Button
var _confirm: ConfirmationDialog
var _pending := Callable()
var _previewed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS
	z_index = 40
	theme = _editor_theme()
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	_build_header(layout)
	_build_workspace(layout)
	_build_status(layout)
	_build_map_picker()
	_confirm = ConfirmationDialog.new()
	_confirm.title = L10N.t("editor.title")
	_confirm.theme = theme
	_confirm.ok_button_text = L10N.t("editor.confirm")
	_confirm.cancel_button_text = L10N.t("editor.cancel")
	_style_button(_confirm.get_ok_button(), true)
	_style_button(_confirm.get_cancel_button())
	_confirm.confirmed.connect(_accept_pending)
	_confirm.canceled.connect(func(): _pending = Callable())
	add_child(_confirm)
	_json_dialog = FileDialog.new()
	_json_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_json_dialog.use_native_dialog = true
	_json_dialog.filters = PackedStringArray(["*.json;JSON;application/json"])
	_json_dialog.file_selected.connect(_json_selected)
	add_child(_json_dialog)
	draft.saved = draft.data.duplicate(true)
	_load_tools()
	_select_tool("select")
	_show_detail("object")
	_sync(true)
	hide()


func _build_header(layout: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	layout.add_child(top)
	var heading := _label(L10N.t("editor.title"), 24)
	heading.add_theme_font_override("font", DISPLAY)
	top.add_child(heading)
	top.add_child(VSeparator.new())
	var document := VBoxContainer.new()
	document.add_theme_constant_override("separation", 1)
	document.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(document)
	var title := HBoxContainer.new()
	document.add_child(title)
	_changed_mark = _label("●", 11, RED)
	_changed_mark.size_flags_vertical = SIZE_SHRINK_CENTER
	_changed_mark.tooltip_text = L10N.t("editor.dirty")
	title.add_child(_changed_mark)
	_document_title = _label("", 17)
	_document_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_document_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_child(_document_title)
	_document_id = _label("", 12, MUTED)
	_document_id.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	document.add_child(_document_id)
	_file = _menu(top, "editor.file", ["editor.new", "editor.open", "editor.clone", "",
		"editor.json_import", "editor.json_room", "editor.json_route"])
	_file.about_to_popup.connect(_refresh_file_menu)
	_file.get_popup().id_pressed.connect(_file_requested)
	_file.get_popup().set_item_shortcut(0, _shortcut(KEY_N))
	_file.get_popup().set_item_shortcut(1, _shortcut(KEY_O))
	var save := _button("editor.save", _save_requested)
	save.tooltip_text = "Ctrl+S"
	top.add_child(save)
	top.add_child(_button("editor.playtest", _playtest, true))
	top.add_child(_button("editor.close", request_close))


func _build_status(layout: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	_status = _label("", 14, MUTED)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = MOUSE_FILTER_PASS
	footer.add_child(_status)
	_view_cursor = _label("", 13, MUTED)
	_view_cursor.custom_minimum_size.x = 112
	_view_cursor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_view_cursor)


func _update_view(percent: int, cell: Vector2i) -> void:
	_view_zoom.text = "%d%%" % percent
	_view_cursor.text = "X %d  ·  Y %d" % [cell.x, cell.y]


func _build_map_picker() -> void:
	_picker = ConfirmationDialog.new()
	_picker.theme = theme
	_picker.cancel_button_text = L10N.t("editor.cancel")
	_style_button(_picker.get_ok_button(), true)
	_style_button(_picker.get_cancel_button())
	_picker.confirmed.connect(_open_picked_map)
	add_child(_picker)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_picker.add_child(margin)
	_map_list = ItemList.new()
	_map_list.custom_minimum_size = Vector2(388, 234)
	_map_list.add_theme_constant_override("v_separation", 9)
	_map_list.add_theme_stylebox_override("panel", _style(FIELD, BORDER, 8))
	_map_list.add_theme_stylebox_override("selected", _style(RED, RED))
	_map_list.add_theme_stylebox_override("selected_focus", _style(RED, RED))
	_map_list.add_theme_stylebox_override("focus", _focus_style())
	_map_list.add_theme_color_override("font_color", INK)
	_map_list.add_theme_color_override("font_selected_color", FIELD)
	_map_list.item_activated.connect(func(_index: int):
		_picker.hide()
		_open_picked_map())
	margin.add_child(_map_list)


func _build_properties(body: VBoxContainer) -> void:
	body.add_child(_label(L10N.t("editor.map_properties"), 19))
	_level_id = LineEdit.new()
	_level_id.max_length = 48
	_form_field(body, "editor.map_id", _level_id)
	_level_name = LineEdit.new()
	_level_name.max_length = 80
	_form_field(body, "editor.level_name", _level_name)
	var dimensions := HBoxContainer.new()
	dimensions.add_theme_constant_override("separation", 8)
	body.add_child(dimensions)
	_width = _size_field(dimensions, "editor.width", 640, LevelDraft.MAX_SIZE.x)
	_height = _size_field(dimensions, "editor.height", 384, LevelDraft.MAX_SIZE.y)
	body.add_child(_note("editor.map_help"))
	body.add_child(_button("editor.apply", _apply_and_report))


func _build_workspace(layout: VBoxContainer) -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(main)
	_build_palette(main)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 7)
	main.add_child(center)
	_build_canvas_header(center)
	canvas = EditorCanvas.new()
	canvas.draft = draft
	canvas.custom_minimum_size = Vector2(280, 180)
	canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	canvas.size_flags_vertical = SIZE_EXPAND_FILL
	canvas.changed.connect(_after_edit)
	canvas.selection_changed.connect(_canvas_selection_changed)
	canvas.tool_changed.connect(_select_tool)
	canvas.view_changed.connect(_update_view)
	center.add_child(canvas)
	_build_details(main)


func _build_palette(parent: HBoxContainer) -> void:
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 218
	var sidebar := _panel_body(panel)
	sidebar.add_child(_label(L10N.t("editor.tools"), 19))
	var categories := GridContainer.new()
	categories.columns = 2
	categories.add_theme_constant_override("h_separation", 5)
	categories.add_theme_constant_override("v_separation", 5)
	sidebar.add_child(categories)
	for key in TOOL_GROUPS:
		var button := _button("editor.category_" + key, _change_tool_group.bind(key))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 32
		categories.add_child(button)
		_tool_buttons[key] = button
	palette = ItemList.new()
	palette.size_flags_vertical = SIZE_EXPAND_FILL
	palette.add_theme_font_size_override("font_size", 16)
	palette.add_theme_constant_override("v_separation", 10)
	palette.add_theme_stylebox_override("panel", _style(FIELD, BORDER, 8))
	palette.add_theme_stylebox_override("selected", _style(RED, RED))
	palette.add_theme_stylebox_override("selected_focus", _style(RED, RED))
	palette.add_theme_color_override("font_color", INK)
	palette.add_theme_color_override("font_selected_color", FIELD)
	palette.item_selected.connect(func(index: int): _select_tool(str(palette.get_item_metadata(index))))
	sidebar.add_child(palette)
	_tool_hint = _note("editor.editor_help")
	_tool_hint.custom_minimum_size.y = 52
	sidebar.add_child(_tool_hint)


func _build_canvas_header(center: VBoxContainer) -> void:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	center.add_child(toolbar)
	_undo = _button("editor.undo", _undo_action)
	_redo = _button("editor.redo", _redo_action)
	_undo.tooltip_text = "Ctrl+Z"
	_redo.tooltip_text = "Ctrl+Y"
	toolbar.add_child(_undo)
	toolbar.add_child(_redo)
	toolbar.add_spacer(false)
	var zoom_out := _button("editor.zoom_out", func(): canvas.adjust_zoom(1.0 / 1.22, canvas.size * 0.5))
	var zoom_in := _button("editor.zoom_in", func(): canvas.adjust_zoom(1.22, canvas.size * 0.5))
	zoom_out.tooltip_text = L10N.t("editor.zoom_less")
	zoom_in.tooltip_text = L10N.t("editor.zoom_more")
	toolbar.add_child(zoom_out)
	_view_zoom = _label("", 13, MUTED)
	_view_zoom.custom_minimum_size.x = 44
	_view_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_view_zoom)
	toolbar.add_child(zoom_in)
	var fit := _button("editor.fit", func(): canvas.fit())
	fit.tooltip_text = L10N.t("editor.fit_help")
	toolbar.add_child(fit)
	toolbar.add_child(VSeparator.new())
	_detail_toggle = _button("editor.details", _toggle_details)
	_detail_toggle.tooltip_text = L10N.t("editor.details_help")
	toolbar.add_child(_detail_toggle)


func _build_details(parent: HBoxContainer) -> void:
	_details = _panel(parent)
	_details.custom_minimum_size.x = 262
	var body := _panel_body(_details)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	body.add_child(tabs)
	for key in DETAIL_PAGES:
		var button := _button("editor.tab_" + key, _show_detail.bind(key))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		tabs.add_child(button)
		_detail_buttons[key] = button
	_build_inspector(_detail_page(body, "object"))
	_build_properties(_detail_page(body, "map"))
	_build_layer_options(_detail_page(body, "layers"))
	_build_test_options(_detail_page(body, "test"))


func _detail_page(parent: VBoxContainer, key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	_detail_pages[key] = scroll
	var body := VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	return body


func _build_test_options(body: VBoxContainer) -> void:
	body.add_child(_label(L10N.t("editor.test_settings"), 19))
	_test_start = OptionButton.new()
	_test_start.fit_to_longest_item = false
	_form_field(body, "editor.test_start", _test_start)
	_test_weapon = OptionButton.new()
	_test_weapon.fit_to_longest_item = false
	for id in WDB.ids():
		var definition := WDB.get_weapon(id)
		_test_weapon.add_item(L10N.t(definition.display_name_key))
		_test_weapon.set_item_metadata(_test_weapon.item_count - 1, str(id))
	_form_field(body, "editor.test_weapon", _test_weapon)
	_test_soul = SpinBox.new()
	_test_soul.max_value = 99
	_form_field(body, "debug.soul", _test_soul)
	body.add_child(_note("editor.test_help"))
	body.add_child(_button("editor.playtest", _playtest, true))
	body.add_child(HSeparator.new())
	body.add_child(_label(L10N.t("editor.route"), 19))
	body.add_child(_note("editor.route_help"))
	_route = _menu(body, "editor.route_actions", ["editor.route_start", "editor.route_continue"])
	_route.about_to_popup.connect(_refresh_route_menu)
	_route.get_popup().id_pressed.connect(_route_requested)


func _menu(parent: Container, key: String, items: Array) -> MenuButton:
	var button := MenuButton.new()
	button.text = "▾" if key.is_empty() else L10N.t(key) + " ▾"
	_style_button(button)
	var popup := button.get_popup()
	popup.add_theme_stylebox_override("panel", _style(PAPER, RED))
	popup.add_theme_stylebox_override("hover", _style(RED, RED))
	popup.add_theme_font_override("font", FONT)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", PAPER)
	popup.add_theme_color_override("font_disabled_color", Color(INK, 0.46))
	for i in items.size():
		if items[i].is_empty():
			popup.add_separator("", i)
		else:
			popup.add_item(L10N.t(items[i]), i)
	parent.add_child(button)
	return button


func _build_inspector(parent: VBoxContainer) -> void:
	_selected = _label("", 19)
	_selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_selected)
	_object_help = _note("editor.object_help")
	parent.add_child(_object_help)
	_item_actions = HBoxContainer.new()
	_item_actions.add_theme_constant_override("separation", 6)
	_duplicate = _button("editor.duplicate", func(): canvas.duplicate_selected())
	_duplicate.tooltip_text = "Ctrl+D"
	_item_actions.add_child(_duplicate)
	_delete = _button("editor.delete", func(): canvas.delete_selected())
	_delete.tooltip_text = "Delete"
	_item_actions.add_child(_delete)
	parent.add_child(_item_actions)
	_inspector = VBoxContainer.new()
	_inspector.add_theme_constant_override("separation", 10)
	parent.add_child(_inspector)
	for pair in [["x", "y"], ["w", "h"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_inspector.add_child(row)
		for key in pair:
			var field := SpinBox.new()
			field.max_value = LevelDraft.MAX_SIZE.x if key in ["x", "w"] else LevelDraft.MAX_SIZE.y
			_form_field(row, "editor.coord_" + key, field)
			_item_fields[key] = field
	_target_room = _link_field("editor.target_room", _room_choices)
	_target_entry = _link_field("editor.target_entry", _entry_choices)
	_target_requires = _link_field("editor.target_requires")
	_inspector.add_child(_button("editor.apply", _apply_item))
	_link_help = _note("editor.link_fields_help")
	_inspector.add_child(_link_help)


func _link_field(key: String, choices := Callable()) -> LineEdit:
	var row := HBoxContainer.new()
	var field := LineEdit.new()
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(field)
	_link_rows[key] = _form_field(_inspector, key, row)
	if choices.is_valid():
		var picker := _menu(row, "", [])
		picker.flat = false
		picker.tooltip_text = L10N.t(key)
		picker.about_to_popup.connect(_refresh_choices.bind(picker.get_popup(), choices))
		picker.get_popup().id_pressed.connect(_pick_link_value.bind(picker.get_popup(), field))
	return field


func _build_layer_options(body: VBoxContainer) -> void:
	body.add_child(_label(L10N.t("editor.tab_layers"), 19))
	var matrix := GridContainer.new()
	matrix.columns = 3
	matrix.add_theme_constant_override("h_separation", 7)
	matrix.add_theme_constant_override("v_separation", 9)
	body.add_child(matrix)
	matrix.add_child(_label(L10N.t("editor.layer_name"), 13, MUTED))
	matrix.add_child(_label(L10N.t("editor.layer_visible"), 13, MUTED))
	matrix.add_child(_label(L10N.t("editor.layer_locked"), 13, MUTED))
	for key in EditorCanvas.LAYERS:
		var label := _label(L10N.t("editor.layer_" + key), 15)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		matrix.add_child(label)
		var shown := CheckBox.new()
		var locked := CheckBox.new()
		for button in [shown, locked]:
			button.size_flags_horizontal = SIZE_SHRINK_CENTER
			button.toggled.connect(func(_enabled: bool): _apply_layer(key))
			matrix.add_child(button)
		shown.tooltip_text = L10N.t("editor.layer_show_help")
		locked.tooltip_text = L10N.t("editor.layer_lock_help")
		_layer_toggles[key] = [shown, locked]
	body.add_child(HSeparator.new())
	var grid := CheckBox.new()
	grid.text = L10N.t("editor.show_grid")
	grid.button_pressed = true
	grid.toggled.connect(func(enabled: bool):
		canvas.grid_visible = enabled
		canvas.queue_redraw())
	body.add_child(grid)
	body.add_child(_note("editor.layers_help"))


func _sync_layers() -> void:
	for key in _layer_toggles:
		var first: String = EditorCanvas.LAYERS[key][0]
		var toggles: Array = _layer_toggles[key]
		toggles[0].set_pressed_no_signal(first not in canvas.hidden_sections)
		toggles[1].set_pressed_no_signal(first in canvas.locked)


func _apply_layer(key: String) -> void:
	var toggles: Array = _layer_toggles[key]
	canvas.set_layer(key, toggles[0].button_pressed, not toggles[1].button_pressed)


func _sync_test_starts() -> void:
	var selected := str(_test_start.get_selected_metadata()) if _test_start.selected >= 0 else "@main"
	_test_start.clear()
	_test_start.add_item(L10N.t("editor.start_main"))
	_test_start.set_item_metadata(0, "@main")
	_test_start.add_item(L10N.t("editor.start_cursor"))
	_test_start.set_item_metadata(1, "@cursor")
	for checkpoint in draft.data.checkpoints:
		_test_start.add_item(checkpoint.id)
		_test_start.set_item_metadata(_test_start.item_count - 1, checkpoint.id)
	for index in _test_start.item_count:
		if _test_start.get_item_metadata(index) == selected:
			_test_start.select(index)
			return
	_test_start.select(0)


func _size_field(parent: Container, key: String, lower: int, upper: int) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = lower
	field.max_value = upper
	field.step = LevelDraft.GRID
	_form_field(parent, key, field)
	return field


func _load_tools() -> void:
	_tools = {
		"edit": _named_tools("select", ["box", "resize", "pan", "erase"]),
		"terrain": _named_tools("solid", ["platform", "ledge", "bridge", "steps"]),
		"actors": _named_tools("spawn", ["checkpoint"]),
		"logic": _named_tools("link", ["door", "switch", "entry", "exit", "finish"]),
		"decor": {},
	}
	for id in DB.ids():
		var card := DB.get_def(id)
		var label := L10N.t(card.display_name_key) if not card.display_name_key.is_empty() else str(id)
		_tools.actors["enemy:" + str(id)] = L10N.t("editor.enemy_small_blot") if id == &"enemy.blot_small" else label
	for id in PDB.ids():
		_tools.actors["prop:" + str(id)] = L10N.t(PDB.get_def(id).display_name_key)
	for kind in Decor.DECOR_SIZES:
		_tools.decor["decor:" + kind] = L10N.t("editor.decor_" + kind)


func _named_tools(first: String, rest: Array) -> Dictionary:
	var tools := {}
	for key in [first] + rest:
		tools[key] = L10N.t("editor.tool_" + key)
	return tools


func _change_tool_group(group: String) -> void:
	var items: Dictionary = _tools[group]
	_select_tool(_last_tool.get(group, items.keys().front()))


func _select_tool(key: String) -> void:
	for group in TOOL_GROUPS:
		var items: Dictionary = _tools[group]
		if not items.has(key):
			continue
		if _tool_group != group:
			_tool_group = group
			_mark_tab(_tool_buttons, group, 14)
			palette.clear()
			for tool in items:
				var row := palette.add_item(L10N.t("editor.tool_platform_short") if tool == "platform" else items[tool])
				palette.set_item_tooltip(row, items[tool])
				palette.set_item_metadata(palette.item_count - 1, tool)
		_last_tool[group] = key
		palette.select(items.keys().find(key))
		palette.ensure_current_is_visible()
		canvas.tool = key
		canvas.queue_redraw()
		_tool_hint.text = L10N.t("editor.tool_help_" + key if key in ["select", "box", "link", "pan", "resize", "erase"]
			else "editor.tool_help_terrain" if group == "terrain" else "editor.tool_help_place")
		return


func _show_detail(key: String) -> void:
	_detail_tab = key
	for tab in _detail_pages:
		_detail_pages[tab].visible = tab == key
	_mark_tab(_detail_buttons, key, 13)
	if key == "layers":
		_sync_layers()


func _toggle_details() -> void:
	_details.visible = not _details.visible


func _canvas_selection_changed() -> void:
	_update_selection()
	if canvas.has_focus() and not canvas.editable_selection().is_empty() and _detail_tab != "object":
		_show_detail("object")


func _mark_tab(buttons: Dictionary, active: String, size_px: int) -> void:
	for key in buttons:
		_style_button(buttons[key], key == active)
		buttons[key].add_theme_font_size_override("font_size", size_px)


func _room_choices() -> Dictionary:
	var options := {str(draft.data.id): str(draft.data.id)}
	for id in LevelDraft.files():
		options[id] = id
	for id in LVL.ids():
		options[id] = id
	return options


func _entry_choices() -> Dictionary:
	var choices := {"": L10N.t("editor.start_main")}
	var id := _target_room.text.strip_edges()
	var world: Dictionary = draft.data if id == draft.data.id else LevelDraft.read(id)
	if world.is_empty():
		var source := LVL.get_level(id)
		if source != null:
			world = source.world
	for entry in world.get("entries", []):
		if entry is Dictionary and entry.get("id") is String:
			choices[entry.id] = entry.id
	return choices


func _refresh_choices(popup: PopupMenu, choices: Callable) -> void:
	popup.clear()
	var options: Dictionary = choices.call()
	for value in options:
		popup.add_item(options[value])
		popup.set_item_metadata(popup.item_count - 1, value)


func _pick_link_value(id: int, popup: PopupMenu, field: LineEdit) -> void:
	var value := str(popup.get_item_metadata(popup.get_item_index(id)))
	if field == _target_room and field.text != value:
		_target_entry.clear()
	field.text = value


func open() -> void:
	show()
	_select_tool(canvas.tool)
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
	if not visible or _confirm.visible or _picker.visible or _json_dialog.visible \
			or not event is InputEventKey or not event.pressed or event.echo:
		return
	var editing_text := get_viewport().gui_get_focus_owner() is LineEdit
	if event.keycode == KEY_ESCAPE:
		request_close()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_save_requested()
	elif event.ctrl_pressed and event.keycode == KEY_N:
		_new_requested()
	elif event.ctrl_pressed and event.keycode == KEY_O:
		_pick_document(false)
	elif event.ctrl_pressed and not editing_text and event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo_action()
		else:
			_undo_action()
	elif event.ctrl_pressed and not editing_text and event.keycode == KEY_Y:
		_redo_action()
	elif event.ctrl_pressed and not editing_text and event.keycode == KEY_D:
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


func _refresh_file_menu() -> void:
	_file.get_popup().set_item_disabled(1, LevelDraft.files().is_empty())


func _file_requested(id: int) -> void:
	match id:
		0:
			_new_requested()
		1, 2:
			_pick_document(id == 2)
		4, 5, 6:
			_json_requested(id - 4)


func _pick_document(copying: bool) -> void:
	_copying_map = copying
	var ids := LVL.ids() if copying else LevelDraft.files()
	if ids.is_empty():
		_report(L10N.t("editor.no_drafts"), false)
		return
	_map_list.clear()
	for id in ids:
		var title := ""
		if copying:
			var definition := LVL.get_level(id)
			title = L10N.t(str(definition.world.display_name_key)) if definition.world.has("display_name_key") else str(definition.world.get("name", id))
		else:
			title = str(LevelDraft.read(id).get("name", ""))
		var row := _map_list.add_item(title + "   ·   " + id if not title.is_empty() and title != id else id)
		_map_list.set_item_metadata(row, id)
		if id == draft.data.id:
			_map_list.select(row)
	if not _map_list.is_anything_selected():
		_map_list.select(0)
	_picker.title = L10N.t("editor.copy_map_title" if copying else "editor.open_map_title")
	_picker.ok_button_text = L10N.t("editor.copy" if copying else "editor.open")
	_picker.popup_centered(Vector2i(500, 324))
	_map_list.grab_focus()
	_map_list.ensure_current_is_visible()


func _open_picked_map() -> void:
	var selected := _map_list.get_selected_items()
	if selected.is_empty():
		return
	var id := str(_map_list.get_item_metadata(selected[0]))
	_apply_properties()
	var action := _clone_document.bind(id) if _copying_map else _load_document.bind(id)
	_discard_or(action, "editor.confirm_discard")


func _load_document(id: String) -> void:
	var data := LevelDraft.read(id)
	var errors := LevelDraft.validate_world(data)
	if data.get("id") != id or not errors.is_empty():
		_report(L10N.t("editor.error_file", [id]), true)
		return
	draft.replace(data)
	_document_changed()


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
	_sync(false)
	_report(L10N.t("editor.saved", [draft.data.id]), false)


func _refresh_route_menu() -> void:
	var id := _level_id.text.strip_edges()
	_route.get_popup().set_item_disabled(1, not flow.has_custom_route(id))


func _route_requested(action: int) -> void:
	_apply_and_report()
	var id := str(draft.data.id)
	if action == 1:
		_launch_route({}, id)
		return
	if draft.dirty() or id not in LevelDraft.files():
		_report(L10N.t("editor.error_route_unsaved"), true)
		return
	var result := LevelPackage.collect(draft.data)
	if result.has("error"):
		_report(result.error, true)
		return
	var data: Dictionary = result.data
	if flow.has_custom_route(id):
		_ask(_launch_route.bind(data, id), "editor.route_restart")
	else:
		_launch_route(data, id)


func _launch_route(data: Dictionary, id: String) -> void:
	var error: String = flow.open_custom_route(id, data)
	if not error.is_empty():
		_report(error, true)


func _json_requested(action: int) -> void:
	_apply_and_report()
	_json_data = {}
	if action == 1:
		if not draft.validate().is_empty():
			return
		_json_data = draft.data.duplicate(true)
	elif action == 2:
		var result := LevelPackage.collect(draft.data)
		if result.has("error"):
			_report(result.error, true)
			return
		_json_data = result.data
	_json_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action == 0 else FileDialog.FILE_MODE_SAVE_FILE
	_json_dialog.title = L10N.t(["editor.json_import", "editor.json_room", "editor.json_route"][action])
	_json_dialog.current_file = "" if action == 0 else str(draft.data.id) + ("_route" if action == 2 else "") + ".json"
	_json_dialog.popup_centered_ratio(0.76)


func _json_selected(path: String) -> void:
	if not _json_data.is_empty():
		var target := path if path.begins_with("content://") or path.get_extension().to_lower() == "json" else path + ".json"
		var result := LevelDraft.write_json(target, _json_data, not OS.has_feature("android"))
		_json_data = {}
		_report(L10N.t("editor.json_exported", [target.get_file()]) if result == OK \
			else L10N.t("editor.error_save", [error_string(result)]), result != OK)
		return
	var source := LevelPackage.read_file(path)
	if source.has("error"):
		_report(source.error, true)
		return
	_discard_or(_import_json.bind(source.data), "editor.confirm_discard")


func _import_json(data: Dictionary) -> void:
	var result := LevelPackage.install(data)
	if result.has("error"):
		_report(result.error, true)
		return
	_load_document(result.root)
	if canvas.invalid_exits.is_empty():
		_report(L10N.t("editor.json_imported", [result.count, result.root]), false)


func _playtest() -> void:
	_apply_and_report()
	if not draft.validate().is_empty() or not canvas.invalid_exits.is_empty():
		return
	var options := {"weapon": str(_test_weapon.get_selected_metadata()), "soul": _test_soul.value}
	var start := str(_test_start.get_selected_metadata())
	if start == "@cursor":
		options["position"] = canvas.cursor_point()
	elif start != "@main":
		var checkpoint := RoomLinks.find(draft.data, "checkpoints", start)
		if not checkpoint.is_empty():
			options["position"] = RoomLinks.point(checkpoint)
	if not flow.start_editor_test(draft.data, options):
		_report(L10N.t("editor.error_spawn") if options.has("position") else L10N.t("editor.error_playtest"), true)


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
	_show_errors()


func _sync(properties: bool) -> void:
	if properties:
		_level_id.text = str(draft.data.id)
		_level_name.text = str(draft.data.get("name", ""))
		_width.value = draft.data.bounds.w
		_height.value = draft.data.bounds.h
	_undo.disabled = draft.undo_stack.is_empty()
	_redo.disabled = draft.redo_stack.is_empty()
	_document_title.text = str(draft.data.get("name", "")).strip_edges()
	if _document_title.text.is_empty():
		_document_title.text = L10N.t("editor.new_name")
	_document_title.tooltip_text = _document_title.text
	_document_id.text = str(draft.data.id)
	_changed_mark.visible = draft.dirty()
	_sync_test_starts()
	_update_selection()


func _update_selection() -> void:
	var selected: Array[Vector2i] = canvas.editable_selection()
	_inspector.visible = selected.size() == 1
	_item_actions.visible = not selected.is_empty()
	_duplicate.disabled = selected.size() != 1
	_object_help.visible = selected.is_empty()
	if selected.is_empty():
		_selected.text = L10N.t("editor.no_selection")
		return
	if selected.size() > 1:
		_selected.text = L10N.t("editor.selection_count", [selected.size()])
		return
	var item: Dictionary = draft.item(selected[0])
	if item.is_empty():
		_selected.text = L10N.t("editor.no_selection")
		return
	var section: String = LevelDraft.SECTIONS[selected[0].x]
	_selected.text = str(item.get("id", L10N.t("editor.tool_solid" if section == "solids" else "editor.tool_platform")))
	for key in _item_fields:
		var field := _item_fields[key]
		field.get_parent().visible = item.has(key)
		field.set_value_no_signal(float(item.get(key, 0)))
	var exit := section == "exits"
	var has_target := exit and not bool(item.get("finish", false))
	_link_rows["editor.target_room"].visible = has_target
	_link_rows["editor.target_entry"].visible = has_target
	_link_rows["editor.target_requires"].visible = exit
	_link_help.visible = exit
	_target_room.text = str(item.get("level", ""))
	_target_entry.text = str(item.get("entry", ""))
	_target_requires.text = ", ".join(PackedStringArray(item.get("requires", [])))


func _apply_item() -> void:
	var selection: Array[Vector2i] = canvas.editable_selection()
	if selection.size() != 1:
		return
	var section: String = LevelDraft.SECTIONS[selection[0].x]
	var changes := {}
	for key in _item_fields:
		var field := _item_fields[key]
		if field.get_parent().visible:
			var value := int(field.value)
			if section in ["solids", "one_ways"]:
				value = int(snappedf(value, LevelDraft.GRID))
			changes[key] = value
	if section == "exits":
		if _link_rows["editor.target_room"].visible:
			changes["level"] = _target_room.text.strip_edges()
			changes["entry"] = _target_entry.text.strip_edges()
		var required: Array[String] = []
		for id in _target_requires.text.split(",", false):
			if not id.strip_edges().is_empty() and id.strip_edges() not in required:
				required.append(id.strip_edges())
		changes["requires"] = required
	if not draft.set_item_properties(selection[0], changes):
		_report(L10N.t("editor.error_rows", [section]), true)
		return
	canvas.refresh(false)
	_after_edit()


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
	canvas.invalid_exits = _unresolved_exits()
	canvas.queue_redraw()
	if errors.is_empty() and not canvas.invalid_exits.is_empty():
		_report(L10N.t("editor.error_link", [canvas.invalid_exits[0]]), true)
	elif errors.is_empty():
		_report(L10N.t("editor.dirty" if draft.dirty() else "editor.ready"), false)
	else:
		_report(errors[0], true)


func _unresolved_exits() -> PackedStringArray:
	var result := PackedStringArray()
	var destinations := {}
	for gate in draft.data.exits:
		if gate.get("finish", false):
			continue
		var target := str(gate.get("level", ""))
		if not destinations.has(target):
			if target == draft.data.id:
				destinations[target] = draft.data
			else:
				var definition := LVL.get_level(target)
				destinations[target] = definition.world if definition != null else LevelDraft.read(target)
		if not RoomLinks.connects(gate, destinations[target]):
			result.append(gate.id)
	return result


func _report(message: String, error: bool) -> void:
	_status.text = message
	_status.tooltip_text = message
	_status.add_theme_color_override("font_color", RED if error else MUTED)


func _label(value: String, pixels: int, color := INK) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", pixels)
	return label


func _note(key: String) -> Label:
	var label := _label(L10N.t(key), 14, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _form_field(parent: Container, key: String, control: Control) -> VBoxContainer:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 4)
	field.add_child(_label(L10N.t(key), 13, MUTED))
	control.custom_minimum_size.y = 32
	field.add_child(control)
	parent.add_child(field)
	return field


func _panel(parent: Container) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 10))
	parent.add_child(panel)
	return panel


func _panel_body(panel: PanelContainer) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	return body


func _shortcut(key: Key) -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = true
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut


func _editor_theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 15
	result.set_stylebox("normal", "LineEdit", _style(FIELD, BORDER))
	result.set_stylebox("read_only", "LineEdit", _style(PANEL, BORDER))
	result.set_stylebox("focus", "LineEdit", _focus_style())
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", RED)
	result.set_color("selection_color", "LineEdit", RED)
	result.set_color("font_selected_color", "LineEdit", FIELD)
	for kind in ["OptionButton", "CheckBox"]:
		for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			result.set_color(state, kind, INK)
	result.set_stylebox("normal", "OptionButton", _style(FIELD, BORDER))
	result.set_stylebox("hover", "OptionButton", _style(PANEL, BORDER))
	result.set_stylebox("pressed", "OptionButton", _style(PANEL, RED))
	result.set_stylebox("focus", "OptionButton", _focus_style())
	result.set_stylebox("panel", "PopupMenu", _style(PANEL, BORDER))
	result.set_stylebox("hover", "PopupMenu", _style(RED, RED))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", FIELD)
	result.set_color("font_accelerator_color", "PopupMenu", MUTED)
	result.set_stylebox("panel", "AcceptDialog", _style(PANEL, BORDER, 14))
	return result


func _button(key: String, action: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = L10N.t(key)
	_style_button(button, accent)
	button.pressed.connect(action)
	return button


func _style_button(button: Button, accent := false) -> void:
	button.custom_minimum_size.y = 33
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _style(RED if accent else PANEL, RED if accent else BORDER))
	button.add_theme_stylebox_override("hover", _style(RED, RED))
	button.add_theme_stylebox_override("pressed", _style(RED, RED))
	button.add_theme_stylebox_override("disabled", _style(PAPER, BORDER))
	button.add_theme_stylebox_override("focus", _focus_style())
	button.add_theme_color_override("font_color", PAPER if accent else INK)
	button.add_theme_color_override("font_focus_color", PAPER if accent else INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color(INK, 0.46))


func _focus_style() -> StyleBoxFlat:
	var focus := _style(PANEL, RED)
	focus.draw_center = false
	focus.set_border_width_all(2)
	return focus


func _style(fill: Color, edge: Color, margin := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.55
	style.content_margin_bottom = margin * 0.55
	return style
