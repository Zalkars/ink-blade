extends Control

## Титульный экран в чернильном стиле 0.2: запечённый пейзаж, живой шарф и птицы,
## подтверждение перезаписи и выбор ручных слотов.

signal start_pressed
signal continue_pressed
signal settings_pressed
signal quit_pressed

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")
const UIText := preload("res://scripts/ui/ink_ui_text.gd")
const PlayerArt := preload("res://scripts/visuals/player_visual.gd")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const GRAY := Color(0.09, 0.07, 0.06, 0.58)

var flow: Node
var input_guard := 0.0
var selected := 0
var items: Array[String] = []
var actions: Array[String] = []
var _wob := 0.0
var _confirm_quit := false
var _confirm_play := false
var _slots_open := false
var _slot_keys: Array[String] = []
var _overwrite_slot := ""
var _overwrite_manual := false

var _baked_bg: ImageTexture = null
var _baked_size := Vector2.ZERO
var _baking := false
var _portrait := PlayerArt.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	InkR.init_static()
	refresh()


## Пункт «ПРОДОЛЖИТЬ» появляется только когда есть незачищенный (или с недосмотренным финалом) автосейв.
## «ИГРАТЬ» всегда первый: с титула новая игра не должна случайно
## превращаться в продолжение с середины.
func refresh() -> void:
	items.clear()
	actions.clear()
	_slot_keys.clear()
	_confirm_quit = false
	_confirm_play = false
	if _slots_open:
		_slot_keys.append(SaveGame.AUTOSAVE)
		actions.append("slot_auto")
		items.append("%s — %s" % [L10N.t("ui.slots.auto"), SaveGame.slot_summary(SaveGame.AUTOSAVE)])
		for i in SaveGame.MANUAL_SLOTS.size():
			var key: String = SaveGame.MANUAL_SLOTS[i]
			_slot_keys.append(key)
			actions.append("slot_%d" % (i + 1))
			items.append("%s — %s" % [L10N.t("ui.slots.slot", [i + 1]), SaveGame.slot_summary(key)])
		actions.append("slots_back")
		items.append(L10N.t("ui.slots.back"))
		selected = clampi(selected, 0, actions.size() - 1)
		queue_redraw()
		return

	actions.append("play")
	items.append(L10N.t("ui.title.play"))
	var save := SaveGame.read_slot(SaveGame.AUTOSAVE)
	if SaveGame.has_unfinished_run(save):
		actions.append("continue")
		items.append(L10N.t("ui.title.continue"))
	actions.append("slots")
	items.append(L10N.t("ui.title.slots"))
	actions.append("settings")
	items.append(L10N.t("MENU_SETTINGS"))
	actions.append("quit")
	items.append(L10N.t("ui.title.quit"))
	selected = clampi(selected, 0, actions.size() - 1)
	queue_redraw()


func _has_overwrite_target() -> bool:
	return SaveGame.has_slot(SaveGame.AUTOSAVE)


func _ask_overwrite(slot: String, manual := false) -> void:
	_overwrite_slot = slot
	_overwrite_manual = manual
	_confirm_play = true
	_slots_open = false
	actions.assign(["cancel_new", "confirm_new"])
	items.assign([L10N.t("ui.new_game.cancel"), L10N.t("ui.new_game.confirm")])
	selected = 0 # Every device starts on the safe choice.
	input_guard = 0.22
	queue_redraw()


func handle_back() -> bool:
	if _slots_open:
		_slots_open = false
		selected = 0
		refresh()
		return true
	if _confirm_play or _confirm_quit:
		_confirm_play = false
		_confirm_quit = false
		refresh()
		return true
	return false


func _physics_process(delta: float) -> void:
	# Скрытый титул не должен читать ввод: visible = false не выключает
	# _physics_process сам по себе.
	if not visible:
		return
	if input_guard > 0:
		input_guard -= delta
		return
	_wob += delta
	if CTL.pressed("down"):
		selected = (selected + 1) % actions.size()
		_confirm_quit = false
	if CTL.pressed("up"):
		selected = (selected + actions.size() - 1) % actions.size()
		_confirm_quit = false
	if CTL.back():
		if handle_back():
			return
	if CTL.confirm():
		activate(selected)
		queue_redraw()
	queue_redraw()


func _ensure_baked_bg(vp: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if vp.x < 64.0 or vp.y < 64.0:
		return
	if _baking or (_baked_bg != null and _baked_size == vp):
		return
	_bake_bg_async(vp)


func _bake_bg_async(vp: Vector2) -> void:
	_baking = true
	var ivp := Vector2i(int(round(vp.x)), int(round(vp.y)))
	var sub := SubViewport.new()
	sub.size = ivp
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub.transparent_bg = false
	var node := InkBakeNode.new()
	node.w = vp.x
	node.h = vp.y
	node.fn = func(cv: CanvasItem): _bake_static_scene(cv, vp.x, vp.y)
	sub.add_child(node)
	add_child(sub)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(sub):
		if is_inside_tree():
			var tex := sub.get_texture()
			if tex != null:
				var img := tex.get_image()
				if img != null and not img.is_empty():
					img.convert(Image.FORMAT_RGBA8)
					_baked_bg = ImageTexture.create_from_image(img)
					_baked_size = vp
		sub.queue_free()
	_baking = false
	if is_inside_tree():
		queue_redraw()


func _bake_static_scene(cv: CanvasItem, w: float, h: float) -> void:
	InkR.init_static()
	InkR.set_canvas(cv)
	InkR.begin_frame(0.0)
	if InkR.tex_paper != null:
		cv.draw_texture_rect(InkR.tex_paper, Rect2(0.0, 0.0, w, h), false)
	else:
		InkR.bake_paper(cv)
		InkR.set_canvas(cv)
	_draw_static_landscape(w, h)
	InkR.vignette_full(w, h)
	InkR.set_canvas(null)


func _draw_static_landscape(w: float, h: float) -> void:
	var sx := w - 334.0
	var sy := 236.0
	var sr := 124.0
	var sun_pts: Array = []
	for i in range(30):
		var a := float(i) / 30.0 * InkR.TAU
		sun_pts.append(Vector2(sx + cos(a) * sr, sy + sin(a) * sr))
	InkR.srand(501)
	InkR.fill_poly(sun_pts, InkR.rgba(156, 33, 41, 230), 1.0, 2.2)
	# Uneven transparent washes accumulate at the edge of a hand-printed sun.
	# No screen-wide hatch or repeating dot grid.
	for i in 11:
		var center := Vector2(sx + InkR.rndf(-104.0, 72.0), sy + InkR.rndf(-108.0, 100.0))
		var radius := InkR.rndf(20.0, 62.0)
		var patch := PackedVector2Array()
		for j in 18:
			var pa := TAU * float(j) / 18.0
			var pr := radius * (1.0 + sin(float(j) * 2.1 + i) * 0.16)
			patch.append(center + Vector2(cos(pa), sin(pa) * 0.7) * pr)
		for clipped in Geometry2D.intersect_polygons(patch, PackedVector2Array(sun_pts)):
			InkR.fill_poly(Array(clipped), InkR.RED_DARK if i % 3 else InkR.RED_BRIGHT, 0.08, 0.0)
	for i in 24:
		var a := InkR.rndf(0.0, TAU)
		var r := InkR.rndf(44.0, sr - 9.0)
		InkR.blob(sx + cos(a) * r, sy + sin(a) * r, InkR.rndf(0.4, 1.4),
			InkR.CREAM, null, 1.0, 0.15, 0.0, 6, 0.1, false)
	InkR.circle(sx, sy, sr, null, InkR.rgba(23, 19, 15, 160), 2.2, 1.0, 2.0, 30)
	InkR.arc(sx + 5.0, sy - 4.0, sr + 12.0, -2.5, -0.4, 1.1, InkR.INK, 0.35, 0.9)
	InkR.arc(sx - 3.0, sy + 4.0, sr + 8.0, 0.7, 2.1, 1.6, InkR.RED, 0.5, 0.8)

	_draw_mountains(w, h)

	# Кляксы у земли рядом с фигурой.
	var fx := sx + 4.0
	var fy := h - 98.0
	InkR.srand(503)
	InkR.blob(fx + 180.0, fy + 18.0, 34.0, InkR.rgba(23, 19, 15, 41), null, 2.0, 1.0, 0.6, 10, 0.13, false, 2.0)
	InkR.blob(fx + 214.0, fy + 40.0, 12.0, InkR.rgba(23, 19, 15, 46), null, 2.0, 1.0, 0.6, 10, 0.13, false, 1.0)
	InkR.blob(fx + 134.0, fy + 48.0, 7.0, InkR.rgba(23, 19, 15, 36), null, 2.0, 1.0, 0.6, 10, 0.13, false, 1.0)


func _ridge_poly(pts_base: Array, ext: Array, w: float, h: float) -> Array:
	var dy := h - 720.0
	var out: Array = []
	for p in pts_base:
		if p.x >= w:
			break
		out.append(Vector2(p.x, p.y + dy))
	if w > 1280.0:
		for p in ext:
			if p.x < w:
				out.append(Vector2(p.x, p.y + dy))
	var last_y: float = (ext.back().y if w > 1280.0 else pts_base.back().y) + dy
	out.append(Vector2(w + 10.0, last_y))
	out.append(Vector2(w + 10.0, h + 10.0))
	out.append(Vector2(-10.0, h + 10.0))
	return out


func _draw_mountains(w: float, h: float) -> void:
	InkR.srand(530)
	var far := _ridge_poly([
		Vector2(0, 600), Vector2(120, 538), Vector2(210, 572), Vector2(318, 498),
		Vector2(420, 556), Vector2(512, 514), Vector2(620, 574), Vector2(742, 522),
		Vector2(860, 566), Vector2(980, 508), Vector2(1104, 560), Vector2(1190, 522),
		Vector2(1280, 580),
	], [Vector2(1390, 526), Vector2(1500, 568), Vector2(1660, 524)], w, h)
	InkR.fill_poly(far, InkR.rgba(23, 19, 15, 41), 1.0, 2.0)
	InkR.poly(far, 1.2, InkR.rgba(23, 19, 15, 46), 1.0, 1.15, true)


	var mid := _ridge_poly([
		Vector2(0, 652), Vector2(110, 606), Vector2(224, 638), Vector2(330, 590),
		Vector2(452, 646), Vector2(560, 602), Vector2(690, 650), Vector2(804, 604),
		Vector2(930, 648), Vector2(1040, 608), Vector2(1160, 652), Vector2(1280, 616),
	], [Vector2(1390, 648), Vector2(1500, 608), Vector2(1660, 642)], w, h)
	InkR.fill_poly(mid, InkR.rgba(23, 19, 15, 107), 1.0, 2.0)
	_draw_ridge_washes(mid, 531, 0.13)

	var near := _ridge_poly([
		Vector2(0, 690), Vector2(140, 656), Vector2(250, 682), Vector2(360, 640),
		Vector2(480, 686), Vector2(600, 654), Vector2(738, 692), Vector2(862, 650),
		Vector2(986, 686), Vector2(1102, 646), Vector2(1210, 682), Vector2(1280, 660),
	], [Vector2(1390, 684), Vector2(1500, 652), Vector2(1660, 678)], w, h)
	InkR.fill_poly(near, InkR.rgba(23, 19, 15, 224), 1.0, 2.0)
	_draw_ridge_washes(near, 532, 0.1)

	var tree_count := int(ceil(w / 148.0)) + 1
	var dy := h - 720.0
	for i in range(tree_count):
		var tx: float = 60.0 + i * 146.0 + (i % 3) * 20.0
		if tx > w - 20.0:
			break
		var ty: float = 640.0 + dy + (i % 2) * 18.0
		var tree := [Vector2(tx, ty - 46.0), Vector2(tx - 11.0, ty), Vector2(tx + 11.0, ty)]
		InkR.fill_poly(tree, InkR.rgba(23, 19, 15, 185), 1.0, 0.5, true, InkR.rgba(23, 19, 15, 220), 1.3)
		InkR.line(tx, ty, tx, ty + 8.0, 2.2, InkR.rgba(23, 19, 15, 200))


func _draw_ridge_washes(ridge: Array, seed_id: int, alpha: float) -> void:
	# A few broken face facets follow each slope instead of a repeated hatch fill.
	InkR.srand(seed_id)
	for i in range(1, ridge.size() - 3):
		if i % 3 == 0:
			continue
		var peak: Vector2 = ridge[i]
		var next: Vector2 = ridge[i + 1]
		var patch := PackedVector2Array([peak, next,
			peak + Vector2(34.0 + float(i % 3) * 12.0, 90.0), peak + Vector2(8.0, 54.0)])
		for clipped in Geometry2D.intersect_polygons(patch, PackedVector2Array(ridge)):
			InkR.fill_poly(Array(clipped), InkR.INK if i % 2 else InkR.CREAM, alpha, 0.0)


func _draw_birds(sx: float, sy: float, t: float) -> void:
	var birds := [
		[sx - 210.0, sy - 108.0, 0.9, 0.4],
		[sx - 144.0, sy - 142.0, 0.7, 1.6],
		[sx - 56.0, sy - 134.0, 0.55, 2.8],
	]
	InkR.srand(520)
	for b in birds:
		var flap := sin(t * 2.2 + float(b[3])) * 5.0
		InkR.poly([
			Vector2(float(b[0]) - 12.0, float(b[1]) + flap),
			Vector2(float(b[0]), float(b[1])),
			Vector2(float(b[0]) + 12.0, float(b[1]) + flap),
		], 1.8 * float(b[2]), InkR.rgba(23, 19, 15, 140), 1.0, 0.6)


func _draw_figure(x: float, ground_y: float, t: float) -> void:
	# Draw the exact gameplay model as native vectors, never a magnified bitmap.
	_portrait.x = -14.0
	_portrait.y = -46.0
	_portrait.ground_y = 0.0
	_portrait.grounded = true
	_portrait.t = t
	_portrait.facing = 1
	_portrait.reset_scarf()
	for i in range(_portrait.scarf.size()):
		_portrait.scarf[i].x = -2.0 - float(i) * 6.2
		_portrait.scarf[i].y = -33.0 + sin(t * 2.1 - float(i) * 0.55) * float(i) * 0.65
	InkR.save()
	InkR.t_translate(x, ground_y)
	InkR.t_scale(2.6, 2.6)
	_portrait.draw()
	InkR.restore()


func _draw() -> void:
	var vp := get_viewport_rect().size
	_ensure_baked_bg(vp)

	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_wob)

	# Фон рисуем на весь viewport (включая отступы safe area).
	InkR.save()
	InkR.t_translate(-position.x, -position.y)
	if _baked_bg != null and _baked_size == vp:
		draw_texture_rect(_baked_bg, Rect2(0.0, 0.0, vp.x, vp.y), false)
	else:
		if InkR.tex_paper != null:
			draw_texture_rect(InkR.tex_paper, Rect2(0.0, 0.0, vp.x, vp.y), false)
		else:
			draw_rect(Rect2(0.0, 0.0, vp.x, vp.y), PAPER)
		_draw_static_landscape(vp.x, vp.y)
		InkR.vignette_full(vp.x, vp.y)

	var sx := vp.x - 334.0
	var sy := 236.0
	_draw_birds(sx, sy, _wob)
	_draw_figure(sx + 4.0, vp.y - 98.0, _wob)
	InkR.restore()

	# Тексты и меню — в границах безопасной области (0..size).
	draw_string(FONT_TITLE, Vector2(92.0, 204.0), L10N.t("TITLE_LINE1"), HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(INK, 0.22))
	draw_string(FONT_TITLE, Vector2(88.0, 200.0), L10N.t("TITLE_LINE1"), HORIZONTAL_ALIGNMENT_LEFT, -1, 62, INK)
	draw_string(FONT_TITLE, Vector2(88.0, 324.0), L10N.t("TITLE_LINE2"), HORIZONTAL_ALIGNMENT_LEFT, -1, 112, Color(INK, 0.2))
	draw_string(FONT_TITLE, Vector2(84.0, 320.0), L10N.t("TITLE_LINE2"), HORIZONTAL_ALIGNMENT_LEFT, -1, 112, INK)

	InkR.srand(502)
	InkR.line(88.0, 340.0, 560.0, 340.0, 5.0, RED, 1.0, 2.0)
	InkR.line(92.0, 346.0, 510.0, 346.0, 1.5, Color(INK, 0.3), 1.0, 1.2)

	var sub_text := L10N.t("ui.slots.subtitle_load") if _slots_open else L10N.t("ui.title.subtitle")
	if _confirm_play:
		sub_text = L10N.t("ui.new_game.title")
	draw_string(FONT_TEXT, Vector2(92.0, 372.0), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GRAY)
	if _confirm_play:
		UIText.paragraph(self, FONT_TEXT, L10N.t("ui.new_game.warning"), Rect2(92, 393, minf(560.0, size.x - 180.0), 94), 18, INK, HORIZONTAL_ALIGNMENT_LEFT)

	for i in items.size():
		var r := item_rect(i)
		var y := r.position.y + 30.0
		var on := i == selected
		if on:
			var box := PackedVector2Array([
				Vector2(r.position.x, r.position.y),
				Vector2(r.end.x, r.position.y - 2.0),
				Vector2(r.end.x + 2.0, r.end.y),
				Vector2(r.position.x + 2.0, r.end.y + 2.0),
			])
			draw_colored_polygon(box, Color(INK, 0.08))
			draw_rect(Rect2(r.position.x, r.position.y, 5.0, r.size.y), RED)
			draw_rect(Rect2(r.position.x + 5.0, r.position.y, r.size.x - 5.0, r.size.y), Color(PAPER, 0.72), true)
			draw_rect(Rect2(r.position.x + 5.0, r.position.y, r.size.x - 5.0, r.size.y), Color(RED, 0.55), false, 1.4)
		else:
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y), Color(PAPER, 0.45), true)
		var label := items[i]
		if on and actions[i] == "quit" and _confirm_quit:
			label = L10N.t("ui.title.quit_confirm")
		elif on and actions[i] == "play" and _confirm_play:
			label = L10N.t("ui.title.play_confirm")
		var font_sz := 21 if _slots_open or _confirm_play else 27
		while font_sz > 14 and FONT_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x > r.size.x - 40.0:
			font_sz -= 1
		draw_string(FONT_BOLD, Vector2(r.position.x + 20.0, y), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, RED if on else Color(INK, 0.78))


	draw_string(FONT_TEXT, Vector2(size.x - 140.0, size.y - 24.0),
		L10N.t("ui.title.version"), HORIZONTAL_ALIGNMENT_RIGHT, 108.0, 14, Color(InkR.CREAM, 0.78))


func item_rect(i: int) -> Rect2:
	var w := minf(560.0 if _slots_open or _confirm_play else 400.0, size.x - 168.0)
	return Rect2(84.0, (502.0 if _confirm_play else 434.0) + i * 48.0, w, 44.0)


func activate(i: int) -> void:
	if input_guard > 0.0 or i < 0 or i >= actions.size():
		return
	if i != selected:
		_confirm_quit = false
	selected = i
	var action: String = actions[selected]
	if action == "cancel_new":
		selected = 0
		refresh()
		return
	if action == "confirm_new":
		_confirm_play = false
		SaveGame.current_slot = _overwrite_slot
		if _overwrite_manual and flow != null:
			flow.start_new_story()
		else:
			start_pressed.emit()
		return
	if _slots_open:
		if action == "slots_back":
			_slots_open = false
			selected = 0
			refresh()
			return
		if selected < _slot_keys.size() and flow != null:
			var slot: String = _slot_keys[selected]
			_slots_open = false
			var slot_data := SaveGame.read_slot(slot)
			if SaveGame.has_unfinished_run(slot_data):
				SaveGame.current_slot = slot
				flow.continue_run(slot)
			elif SaveGame.has_slot(slot):
				_ask_overwrite(slot, true)
			else:
				SaveGame.current_slot = slot
				flow.start_new_story()
			return
	match action:
		"continue":
			SaveGame.current_slot = SaveGame.AUTOSAVE
			continue_pressed.emit()
		"slots":
			_slots_open = true
			selected = 0
			refresh()
		"settings":
			settings_pressed.emit()
		"play":
			if _has_overwrite_target():
				_ask_overwrite(SaveGame.AUTOSAVE)
			else:
				_confirm_play = false
				SaveGame.current_slot = SaveGame.AUTOSAVE
				start_pressed.emit()
		_:
			# Выход — только со второго нажатия: случайный пробел или
			# удар по «ВЫХОД» не должен закрывать игру.
			if _confirm_quit:
				quit_pressed.emit()
			else:
				_confirm_quit = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in actions.size():
			if item_rect(i).has_point(event.position):
				if selected != i:
					selected = i
					_confirm_quit = false
					queue_redraw()
				break
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in actions.size():
			if item_rect(i).has_point(event.position):
				activate(i)
				accept_event()
				break
