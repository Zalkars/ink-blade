extends Control

signal changed
signal selection_changed
signal tool_changed(tool: String)
signal view_changed(percent: int, cell: Vector2i)

const Decor := preload("res://scripts/world/level_decor.gd")
const INK := Color("#211b19")
const PAPER := Color("#eaddc4")
const RED := Color("#a8262c")
const FONT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const LAYERS := {
	"geometry": ["solids", "one_ways"], "actors": ["checkpoints", "placements", "props"],
	"decor": ["decor"], "logic": RoomLinks.SECTIONS,
}

var draft: LevelDraft
var tool := "solid"
var selection := Vector2i(-1, -1)
var group: Array[Vector2i] = []
var hidden_sections: Array = []
var locked: Array = []
var invalid_exits := PackedStringArray()
var grid_visible := true
var _link_source := Vector2i(-1, -1)
var zoom := 1.0
var offset := Vector2.ZERO
var cursor := Vector2.ZERO
var _origin := Vector2.ZERO
var _dragging := false
var _panning := false
var _touch := -1
var _view_size := Vector2.ZERO
var _last_percent := 0
var _last_cell := Vector2i(-1, -1)


func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_ALL
	resized.connect(_keep_view_centered)
	mouse_exited.connect(queue_redraw)


func fit() -> void:
	var bounds := draft.bounds_rect()
	zoom = maxf(0.06, minf((size.x - 64) / bounds.size.x, (size.y - 64) / bounds.size.y))
	offset = (size - bounds.size * zoom) * 0.5
	_report_view()
	queue_redraw()


func adjust_zoom(factor: float, anchor: Vector2) -> void:
	var world := (anchor - offset) / zoom
	zoom = clampf(zoom * factor, 0.06, 4.0)
	offset = anchor - world * zoom
	_report_view()
	queue_redraw()


func refresh(clear_selection := true) -> void:
	if clear_selection:
		selection = Vector2i(-1, -1)
		group.clear()
		_link_source = Vector2i(-1, -1)
		selection_changed.emit()
	_report_view()
	queue_redraw()


func _keep_view_centered() -> void:
	if _view_size != Vector2.ZERO:
		offset += (size - _view_size) * 0.5
	_view_size = size
	queue_redraw()


func _report_view() -> void:
	var percent := roundi(zoom * 100)
	var cell := Vector2i(cursor_point())
	if percent != _last_percent or cell != _last_cell:
		_last_percent = percent
		_last_cell = cell
		view_changed.emit(percent, cell)


func delete_selected() -> void:
	draft.delete_items(editable_selection())
	refresh()
	changed.emit()


func move_selected(delta: Vector2) -> void:
	draft.move_items(editable_selection(), delta)
	changed.emit()
	queue_redraw()


func duplicate_selected() -> void:
	if editable_selection().size() != 1:
		return
	selection = draft.duplicate_item(selection)
	group.assign([selection])
	selection_changed.emit()
	changed.emit()
	queue_redraw()


func cursor_point() -> Vector2:
	return _grid_cell(cursor)


func set_layer(layer: String, show_layer: bool, editable: bool) -> void:
	var before := editable_selection()
	for section in LAYERS[layer]:
		hidden_sections.erase(section)
		locked.erase(section)
		if not show_layer:
			hidden_sections.append(section)
		if not editable:
			locked.append(section)
	var available := editable_selection()
	if before != available:
		group.assign(available)
		selection = available.back() if not available.is_empty() else Vector2i(-1, -1)
		selection_changed.emit()
	if _link_source.x >= 0 and LevelDraft.SECTIONS[_link_source.x] in _ignored():
		_link_source = Vector2i(-1, -1)
	queue_redraw()


func editable_selection() -> Array[Vector2i]:
	var items: Array[Vector2i] = []
	if group.is_empty():
		items.append(selection)
	else:
		items.assign(group)
	return items.filter(func(key: Vector2i) -> bool: return key.x >= 0 and LevelDraft.SECTIONS[key.x] not in hidden_sections and LevelDraft.SECTIONS[key.x] not in locked)


func _ignored() -> Array:
	return hidden_sections + locked


func _can_place() -> bool:
	var kind := tool.get_slice(":", 0)
	var section: String = {"solid": "solids", "ledge": "solids", "steps": "solids", "platform": "one_ways", "bridge": "one_ways",
		"checkpoint": "checkpoints", "enemy": "placements", "prop": "props", "decor": "decor", "door": "doors",
		"switch": "switches", "entry": "entries", "exit": "exits", "finish": "exits"}.get(kind, "")
	return section not in hidden_sections and section not in locked


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_touch = event.index
			_begin(event.position, tool == "pan")
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if event.canceled:
				_dragging = false
				_panning = false
			else:
				_end(event.position)
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		_motion(event.position, event.relative)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var left: bool = event.button_index == MOUSE_BUTTON_LEFT
		var middle: bool = event.button_index == MOUSE_BUTTON_MIDDLE
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			adjust_zoom(1.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.16, event.position)
		elif event.pressed and (left or middle):
			_begin(event.position, middle or tool == "pan" or Input.is_key_pressed(KEY_SPACE), event.shift_pressed)
		elif not event.pressed and (left or middle):
			_end(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			draft.delete_item(draft.find_at((event.position - offset) / zoom, _ignored()))
			refresh()
			changed.emit()
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_motion(event.position, event.relative)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.ctrl_pressed:
		var step: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT,
			KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}.get(event.keycode, Vector2.ZERO)
		if step != Vector2.ZERO:
			move_selected(step * LevelDraft.GRID)
			accept_event()
		elif event.keycode == KEY_DELETE:
			delete_selected()
			accept_event()


func _begin(screen: Vector2, pan: bool, additive := false) -> void:
	grab_focus()
	cursor = (screen - offset) / zoom
	_origin = cursor
	_panning = pan
	_dragging = not pan
	if not pan and tool in ["select", "resize"]:
		var target := draft.find_at(cursor, _ignored())
		if additive and target.x >= 0 and tool == "select":
			if target in group:
				group.erase(target)
			else:
				group.append(target)
		elif target not in group or tool == "resize":
			group.clear()
			if target.x >= 0:
				group.append(target)
		selection = group.back() if not group.is_empty() else Vector2i(-1, -1)
		selection_changed.emit()
	_report_view()
	queue_redraw()


func _motion(screen: Vector2, movement: Vector2) -> void:
	if _panning:
		offset += movement
	cursor = (screen - offset) / zoom
	_report_view()
	queue_redraw()


func _end(screen: Vector2) -> void:
	_panning = false
	if not _dragging:
		return
	_dragging = false
	cursor = (screen - offset) / zoom
	_report_view()
	var start := _grid_cell(_origin)
	var finish := _grid_cell(cursor)
	match tool:
		"select":
			draft.move_items(editable_selection(), (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID))
		"box":
			group = draft.find_in(Rect2(_origin, cursor - _origin).abs(), _ignored())
			selection = group.back() if not group.is_empty() else Vector2i(-1, -1)
			if not group.is_empty():
				tool = "select"
				tool_changed.emit(tool)
			selection_changed.emit()
		"link":
			_link_at(draft.find_at(cursor, _ignored()))
		"resize":
			draft.resize_item(selection, (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID))
		"erase":
			draft.delete_item(draft.find_at(_origin, _ignored()))
			refresh()
		_:
			if _can_place():
				draft.place(tool, start, finish)
	changed.emit()
	queue_redraw()


func _link_at(target: Vector2i) -> void:
	if target.x < 0:
		_link_source = Vector2i(-1, -1)
		return
	if LevelDraft.SECTIONS[target.x] == "switches":
		_link_source = target
	elif draft.link_switch(_link_source, target):
		_link_source = Vector2i(-1, -1)


func _grid_cell(world: Vector2) -> Vector2:
	var cell := (world / LevelDraft.GRID).floor() * LevelDraft.GRID
	return cell.clamp(Vector2.ZERO, draft.bounds_rect().end - Vector2.ONE * LevelDraft.GRID)


func _draw() -> void:
	if draft == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#332b28"))
	var bounds := draft.bounds_rect()
	var world_view := Rect2(-offset / zoom, size / zoom).intersection(bounds)
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	draw_rect(bounds, PAPER)
	if "decor" not in hidden_sections:
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		InkR.t_translate(offset.x, offset.y)
		InkR.t_scale(zoom, zoom)
		for row in draft.data.decor:
			var rect := draft.item_rect("decor", row)
			if rect.intersects(world_view) and Decor.decor_has_support(row, draft.data):
				Decor.draw_decor(row, draft.data)
		draw_set_transform(offset, 0, Vector2.ONE * zoom)
	for row in draft.data.solids if "solids" not in hidden_sections else []:
		var rect := LevelDraft.rect(row)
		draw_rect(rect, Color("#645349"))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("#382c28"), 4 / zoom)
	for row in draft.data.one_ways if "one_ways" not in hidden_sections else []:
		var rect := LevelDraft.rect(row)
		draw_rect(rect, Color("#a6755c"))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), RED, 2 / zoom)
	if grid_visible:
		_draw_grid(world_view)
	draw_rect(bounds, Color(INK, 0.85), false, 2 / zoom)
	_draw_pin(LevelDraft.point(draft.data.spawn), Color("#2b6745"), "▶")
	for row in draft.data.checkpoints if "checkpoints" not in hidden_sections else []:
		_draw_pin(LevelDraft.point(row), Color("#415779"), "◆")
	for row in draft.data.placements if "placements" not in hidden_sections else []:
		_draw_pin(LevelDraft.point(row), RED, "!")
	for row in draft.data.props if "props" not in hidden_sections else []:
		_draw_pin(LevelDraft.point(row), Color("#935f23"), "+")
	if "decor" not in hidden_sections:
		for row in draft.data.decor:
			if not Decor.decor_has_support(row, draft.data):
				draw_rect(draft.item_rect("decor", row), RED, false, 2.0 / zoom)
	if "doors" not in hidden_sections:
		_draw_links()
	_draw_ghost(bounds)
	draw_set_transform(Vector2.ZERO)


func _draw_links() -> void:
	var blue := Color("#357284")
	for lever in draft.data.switches:
		var point := RoomLinks.point(lever)
		for id in lever.targets:
			var door := RoomLinks.find(draft.data, "doors", id)
			if not door.is_empty():
				draw_line(point - Vector2(0, 14), RoomLinks.door_rect(door).get_center(), Color(blue, 0.65), 2 / zoom, true)
		_draw_pin(point, blue if not lever.targets.is_empty() else RED, "S")
	for door in draft.data.doors:
		var rect := RoomLinks.door_rect(door)
		draw_rect(rect, Color(blue, 0.32))
		draw_rect(rect, blue, false, 2 / zoom)
	for entry in draft.data.entries:
		_draw_pin(RoomLinks.point(entry), blue, "←")
	for exit in draft.data.exits:
		_draw_pin(RoomLinks.point(exit), RED if exit.id in invalid_exits else blue, "✓" if exit.get("finish", false) else "→")
	var source := draft.item(_link_source)
	if tool == "link" and not source.is_empty():
		draw_line(RoomLinks.point(source) - Vector2(0, 14), cursor, blue, 2 / zoom, true)


func _draw_grid(view: Rect2) -> void:
	if not view.has_area():
		return
	var gap := LevelDraft.GRID if zoom >= 0.23 else LevelDraft.GRID * 4
	var col := Color(INK, 0.16)
	for x in range(ceili(view.position.x / gap) * gap, ceili(view.end.x), gap):
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), col, 1 / zoom)
	for y in range(ceili(view.position.y / gap) * gap, ceili(view.end.y), gap):
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), col, 1 / zoom)


func _draw_pin(feet: Vector2, color: Color, mark: String) -> void:
	var radius := maxf(13.0, 8.5 / zoom)
	var center := feet - Vector2(0, radius * 1.4)
	draw_circle(center, radius, color, true, -1.0, true)
	draw_line(feet, center, color, 2 / zoom)
	var font_size := ceili(radius * 1.23)
	var width := FONT.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, center + Vector2(-width * 0.5, font_size * 0.32), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PAPER)


func _draw_ghost(bounds: Rect2) -> void:
	for target in editable_selection():
		var selected := draft.item(target)
		if selected.is_empty():
			continue
		var rect := draft.item_rect(LevelDraft.SECTIONS[target.x], selected)
		if _dragging and tool == "select":
			rect.position += (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID)
		elif _dragging and tool == "resize" and selected.has("w"):
			var delta := (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID)
			rect.size.x = maxf(LevelDraft.GRID, rect.size.x + delta.x)
			if LevelDraft.SECTIONS[target.x] != "one_ways":
				rect.size.y = maxf(LevelDraft.GRID, rect.size.y + delta.y)
		draw_rect(rect.grow(2 / zoom), Color("#4385a0"), false, 2.3 / zoom)
	if _dragging and tool == "box":
		var selection_box := Rect2(_origin, cursor - _origin).abs()
		draw_rect(selection_box, Color("#4385a044"))
		draw_rect(selection_box, Color("#4385a0"), false, 2 / zoom)
	if not bounds.has_point(cursor) or _panning or tool in ["pan", "select", "resize", "box", "link"] or not _can_place() \
			or (not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()) and not _dragging):
		return
	var from := _grid_cell(_origin if _dragging else cursor)
	var to := _grid_cell(cursor)
	var rect := Rect2(from, Vector2.ONE * LevelDraft.GRID)
	if tool in LevelDraft.GEOMETRY_TOOLS:
		for shape in LevelDraft.geometry(tool, from, to):
			draw_rect(shape, Color(RED, 0.28))
			draw_rect(shape, RED, false, 2 / zoom)
		return
	elif tool.begins_with("decor:"):
		rect = Decor.decor_rect({"kind": tool.get_slice(":", 1), "x": from.x, "y": from.y}, draft.data)
	draw_rect(rect, Color(RED, 0.28))
	draw_rect(rect, RED, false, 2 / zoom)
