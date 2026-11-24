extends Control

signal changed
signal selection_changed

const Decor := preload("res://scripts/world/level_decor.gd")
const INK := Color("#211b19")
const PAPER := Color("#eaddc4")
const RED := Color("#a8262c")
const FONT := preload("res://assets/fonts/PTSerif-Regular.ttf")

var draft: LevelDraft
var tool := "solid"
var selection := Vector2i(-1, -1)
var hide_decor := false
var zoom := 1.0
var offset := Vector2.ZERO
var cursor := Vector2.ZERO
var _origin := Vector2.ZERO
var _dragging := false
var _panning := false
var _touch := -1


func _ready() -> void:
	clip_contents = true
	focus_mode = FOCUS_ALL
	mouse_exited.connect(queue_redraw)


func fit() -> void:
	var bounds := draft.bounds_rect()
	zoom = maxf(0.06, minf((size.x - 64) / bounds.size.x, (size.y - 64) / bounds.size.y))
	offset = (size - bounds.size * zoom) * 0.5
	queue_redraw()


func adjust_zoom(factor: float, anchor: Vector2) -> void:
	var world := (anchor - offset) / zoom
	zoom = clampf(zoom * factor, 0.06, 4.0)
	offset = anchor - world * zoom
	queue_redraw()


func refresh(clear_selection := true) -> void:
	if clear_selection:
		selection = Vector2i(-1, -1)
		selection_changed.emit()
	queue_redraw()


func delete_selected() -> void:
	draft.delete_item(selection)
	refresh()
	changed.emit()


func move_selected(delta: Vector2) -> void:
	draft.move_item(selection, delta)
	changed.emit()
	queue_redraw()


func duplicate_selected() -> void:
	selection = draft.duplicate_item(selection)
	selection_changed.emit()
	changed.emit()
	queue_redraw()


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
			_begin(event.position, middle or tool == "pan" or Input.is_key_pressed(KEY_SPACE))
		elif not event.pressed and (left or middle):
			_end(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			draft.delete_item(draft.find_at((event.position - offset) / zoom))
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


func _begin(screen: Vector2, pan: bool) -> void:
	grab_focus()
	cursor = (screen - offset) / zoom
	_origin = cursor
	_panning = pan
	_dragging = not pan
	if not pan and tool in ["select", "resize"]:
		selection = draft.find_at(cursor)
		selection_changed.emit()
	queue_redraw()


func _motion(screen: Vector2, movement: Vector2) -> void:
	if _panning:
		offset += movement
	cursor = (screen - offset) / zoom
	queue_redraw()


func _end(screen: Vector2) -> void:
	_panning = false
	if not _dragging:
		return
	_dragging = false
	cursor = (screen - offset) / zoom
	var start := _grid_cell(_origin)
	var finish := _grid_cell(cursor)
	match tool:
		"select":
			draft.move_item(selection, (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID))
		"resize":
			draft.resize_item(selection, (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID))
		"erase":
			draft.delete_item(draft.find_at(_origin))
			selection = Vector2i(-1, -1)
		_:
			draft.place(tool, start, finish)
	changed.emit()
	queue_redraw()


func _grid_cell(world: Vector2) -> Vector2:
	var cell := (world / LevelDraft.GRID).floor() * LevelDraft.GRID
	return cell.clamp(Vector2.ZERO, draft.bounds_rect().end - Vector2.ONE * LevelDraft.GRID)


func _draw() -> void:
	if draft == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#352926"))
	var bounds := draft.bounds_rect()
	var world_view := Rect2(-offset / zoom, size / zoom).intersection(bounds)
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	draw_rect(bounds, PAPER)
	if not hide_decor:
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		InkR.t_translate(offset.x, offset.y)
		InkR.t_scale(zoom, zoom)
		for row in draft.data.decor:
			var rect := draft.item_rect("decor", row)
			if rect.intersects(world_view) and Decor.decor_has_support(row, draft.data):
				Decor.draw_decor(row, draft.data)
		draw_set_transform(offset, 0, Vector2.ONE * zoom)
	for row in draft.data.solids:
		var rect := LevelDraft.rect(row)
		draw_rect(rect, Color("#645349"))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("#382c28"), 4 / zoom)
	for row in draft.data.one_ways:
		var rect := LevelDraft.rect(row)
		draw_rect(rect, Color("#a6755c"))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), RED, 2 / zoom)
	_draw_grid(world_view)
	draw_rect(bounds, Color(INK, 0.85), false, 2 / zoom)
	_draw_pin(LevelDraft.point(draft.data.spawn), Color("#2b6745"), "▶")
	for row in draft.data.checkpoints:
		_draw_pin(LevelDraft.point(row), Color("#415779"), "◆")
	for row in draft.data.placements:
		_draw_pin(LevelDraft.point(row), RED, "!")
	for row in draft.data.props:
		_draw_pin(LevelDraft.point(row), Color("#935f23"), "+")
	if not hide_decor:
		for row in draft.data.decor:
			if not Decor.decor_has_support(row, draft.data):
				draw_rect(draft.item_rect("decor", row), RED, false, 2.0 / zoom)
	_draw_ghost(bounds)
	draw_set_transform(Vector2.ZERO)
	var cell := _grid_cell(cursor)
	var info := "%d, %d  ·  %d%%" % [roundi(cell.x), roundi(cell.y), roundi(zoom * 100)]
	draw_rect(Rect2(Vector2(10, size.y - 31), Vector2(162, 23)), Color(INK, 0.9))
	draw_string(FONT, Vector2(18.0, size.y - 14), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PAPER)


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
	var selected := draft.item(selection)
	if not selected.is_empty():
		var rect := draft.item_rect(LevelDraft.SECTIONS[selection.x], selected)
		if _dragging and tool == "select":
			rect.position += (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID)
		elif _dragging and tool == "resize" and selected.has("w"):
			var delta := (cursor - _origin).snapped(Vector2.ONE * LevelDraft.GRID)
			rect.size.x = maxf(LevelDraft.GRID, rect.size.x + delta.x)
			if LevelDraft.SECTIONS[selection.x] == "solids":
				rect.size.y = maxf(LevelDraft.GRID, rect.size.y + delta.y)
		draw_rect(rect.grow(2 / zoom), Color("#4385a0"), false, 2.3 / zoom)
	if not bounds.has_point(cursor) or _panning or tool in ["pan", "select", "resize"] \
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
