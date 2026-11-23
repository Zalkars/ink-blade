extends Control

## HUD в чернильном стиле 0.2: маски здоровья, колба души, шевроны рывка,
## счётчик комбо, баннер зала, затухающая подсказка и полоса босса.

const FONT_TITLE := preload("res://assets/fonts/Underdog-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const FAINT := Color(0.09, 0.07, 0.06, 0.5)

var flow: Node
var player: Player
var boss: Keeper
var debug_on := false
var debug_page := 0:
	set(value):
		debug_page = value
		queue_redraw()
var hint := ""
var toast := ""
var toast_t := 0.0

var _hp_before := 5
var _hp_anim := 0.0
var _lost_from := 5
var _t := 0.0
var _banner := {"title": "", "sub": "", "t": 0.0, "max": 1.0}
## Кэш жидкости в фляге: полигоны пересобираются не каждый кадр.
var _soul_points := PackedVector2Array()
var _soul_triangles := PackedInt32Array()
var _soul_cells_k := -1.0
var _soul_cells_t := -100.0
var _vitals := Vector4i(-1, -1, -1, -1)
var _boss_status := Vector3i(-1, -1, -1)
var _screen_fx := Vector2.ZERO
var _combo_visible := false
var _was_debug_on := false
## Высота метки стоимости лечения постоянна — считается один раз.
static var _soul_cost_surface := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InkR.init_static()
	resized.connect(queue_redraw)


# Kept for existing language-refresh callers; control legends live in the guide.
func _rebuild_hint() -> void:
	hint = ""
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	var ink_frame := int(_t * 10.0)
	var animate := _hp_anim > 0.0 or (toast_t > 0.0 and toast_t <= 0.6)
	var banner_time: float = _banner.t
	var banner_length: float = _banner.max
	animate = animate or (banner_time > 0.0 and (banner_time > banner_length - 0.5 or banner_time <= 1.2))
	_t += delta
	_hp_anim = maxf(0.0, _hp_anim - delta)
	if is_instance_valid(player) and player.hp != _hp_before:
		_lost_from = _hp_before
		_hp_before = player.hp
		_hp_anim = 0.55
		animate = true
	if toast_t > 0.0:
		toast_t = maxf(0.0, toast_t - delta)
	if _banner.t > 0.0:
		_banner.t = maxf(0.0, _banner.t - delta)
	var vitals := Vector4i(-1, -1, -1, -1)
	if is_instance_valid(player):
		var dash := player.dash_ready()
		vitals = Vector4i(player.hp, player.weapon_index, player.weapons.size(), 4 if dash >= 1.0 else ceili(dash * 3.0))
		var fill := clampf(player.soul / 99.0, 0.0, 1.0)
		var wave_due := fill > 0.0 and fill < 1.0 and _t - _soul_cells_t >= 1.0 / 30.0
		animate = animate or player.hp == 1 or fill != _soul_cells_k or wave_due
	var boss_status := Vector3i(-1, -1, -1)
	if is_instance_valid(boss) and boss.engaged and not boss.dead:
		boss_status = Vector3i(boss.hp, boss.phase, int(boss.seal_open))
	var screen_fx := Vector2(InkFx.damage, InkFx.flash)
	var combo_visible: bool = flow != null and flow.combo >= 2 and flow.combo_t > 0.0
	if animate or int(_t * 10.0) != ink_frame or vitals != _vitals or boss_status != _boss_status \
		or screen_fx != _screen_fx or combo_visible or combo_visible != _combo_visible \
		or debug_on or debug_page > 0 or debug_on != _was_debug_on:
		queue_redraw()
	_vitals = vitals
	_boss_status = boss_status
	_screen_fx = screen_fx
	_combo_visible = combo_visible
	_was_debug_on = debug_on


## Короткое сообщение поверх игры: «получено оружие», важная находка.
func show_toast(text: String) -> void:
	toast = text
	toast_t = 3.5
	queue_redraw()


func show_banner(title_text: String, sub_text: String = "", duration := 4.0) -> void:
	if title_text.is_empty():
		return
	_banner = {"title": title_text, "sub": sub_text, "t": duration, "max": maxf(0.1, duration)}
	queue_redraw()


func bind(p: Player) -> void:
	player = p
	_hp_before = p.hp
	_hp_anim = 0.0
	queue_redraw()


func bind_boss(b: Keeper) -> void:
	boss = b
	queue_redraw()


func _draw() -> void:
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(_t)

	# Виньетка и экранные вспышки покрывают весь viewport, включая safe-area поля.
	var vp := get_viewport_rect().size
	InkR.save()
	InkR.t_translate(-position.x, -position.y)
	InkR.vignette_full(vp.x, vp.y)
	InkFx.draw_screen(vp.x, vp.y)
	InkR.restore()

	var boss_visible := boss != null and is_instance_valid(boss) and boss.engaged and not boss.dead
	if is_instance_valid(player):
		# Quiet paper wash keeps the small ink marks legible over every backdrop.
		InkR.rect(26, 20, 224, 151, InkR.rgba(246, 237, 218, 192), null, 0, 1.0, 2.2, false)
		_draw_masks()
		_draw_soul_flask()
		_draw_dash_chevrons()
		_draw_weapon()

	if boss_visible:
		_draw_boss()

	if flow != null and flow.combo >= 2 and flow.combo_t > 0.0:
		_draw_combo(96.0 if boss_visible else 58.0)

	if _banner.t > 0.0:
		_draw_banner()

	if toast_t > 0.0 and not toast.is_empty():
		_draw_toast(132.0 if boss_visible else 96.0)

	if debug_on or debug_page > 0:
		_draw_debug()


func _draw_masks() -> void:
	for i in player.MAX_HP:
		var px := 56.0 + float(i) * 34.0
		var py := 44.0
		var alive := i < player.hp
		var last := alive and player.hp == 1
		InkR.srand(300 + i)
		if alive:
			var pulse := 1.0 + sin(_t * 6.0) * 0.06 if last else 1.0
			if _hp_anim > 0.0:
				pulse += sin(_hp_anim * PI / 0.55) * 0.1
			InkR.blob(px, py, 11.0 * pulse, InkR.RED, InkR.INK, 2.0, 1.0, 0.8, 9, 0.1)
			InkR.circle(px - 5.5, py - 4.0, 2.1, InkR.CREAM, null, 2.0, 0.85, 0.2, 10, false)
			InkR.circle(px + 4.5, py - 4.5, 2.1, InkR.CREAM, null, 2.0, 0.85, 0.2, 10, false)
			InkR.line(px - 4.0, py + 4.0, px + 4.0, py + 4.0, 1.6, InkR.RED_DARK, 0.8, 1.0)
		else:
			InkR.blob(px, py, 11.0, null, InkR.rgba(23, 19, 15, 89), 1.5, 1.0, 0.8, 9, 0.1)
			InkR.line(px - 6.0, py - 6.0, px + 2.0, py + 2.0, 1.1, InkR.rgba(23, 19, 15, 71), 1.0, 1.0)
			InkR.line(px + 4.0, py - 5.0, px + 1.0, py + 1.0, 1.0, InkR.rgba(23, 19, 15, 56), 1.0, 1.0)
		if _hp_anim > 0.0 and i >= player.hp and i < _lost_from:
			var progress := 1.0 - _hp_anim / 0.55
			var gx := px + sin(progress * 5.0) * 7.0
			var gy := py - progress * 24.0
			InkR.blob(gx, gy, 11.0 * (1.0 - progress * 0.45), InkR.RED, InkR.INK, 1.6, 1.0 - progress, 0.8, 9, 0.1)


func _draw_soul_flask() -> void:
	var x := 57.0
	var y := 101.0
	var r := 21.0
	var k := clampf(player.soul / 99.0, 0.0, 1.0)
	var ready := player.soul >= Player.HEAL_COST

	InkR.srand(310)
	InkR.circle(x, y, r - 2.0, InkR.rgba(240, 230, 208, 230), null, 2.0, 1.0, 0.5, 24, false)
	# Independent vertical cells cannot self-intersect or fail triangulation.
	# Clip both surface endpoints to the analytic circle, including at 1/99.
	var liquid := Color(23.0 / 255.0, 19.0 / 255.0, 15.0 / 255.0, 210.0 / 255.0)
	# Пересобираем не чаще 30 раз в секунду: волна в маленькой фляге
	# не требует пересчёта 80 полигонов на каждом кадре отрисовки.
	if k != _soul_cells_k or (k > 0.0 and k < 1.0 and _t - _soul_cells_t >= 1.0 / 30.0):
		_soul_points.clear()
		_soul_triangles.clear()
		for cell in soul_liquid_cells(k, _t):
			var offset := _soul_points.size()
			_soul_points.append_array(cell)
			_soul_triangles.append_array([offset, offset + 1, offset + 2])
			if cell.size() == 4:
				_soul_triangles.append_array([offset, offset + 2, offset + 3])
		_soul_cells_k = k
		_soul_cells_t = _t
	if not _soul_triangles.is_empty():
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _soul_triangles, _soul_points, PackedColorArray([liquid]))

	InkR.circle(x, y, r, null, InkR.RED if ready else InkR.rgba(23, 19, 15, 166), 2.6 if ready else 2.0, 1.0, 0.9, 14)
	InkR.rect(x - 7.0, y - r - 7.0, 14.0, 9.0, InkR.CREAM, InkR.INK, 1.5, 1.0, 0.4)
	InkR.line(x - 9, y - r - 8, x + 9, y - r - 8, 2.3, InkR.RED, 0.8, 0.4)
	InkR.line(x - r + 4.0, y - 6.0, x - r + 4.0, y + 9.0, 1.2, InkR.rgba(246, 237, 218, 128), 1.0, 1.0)

	if ready:
		var pulse := 0.5 + sin(_t * 5.0) * 0.3
		InkR.save()
		InkR.alpha_push(pulse * 0.5)
		InkR.circle(x, y, r + 5.0, null, InkR.RED, 1.2, 1.0, 1.0, 16)
		InkR.restore()

	var cost_y := y + soul_cost_surface()
	InkR.line(x + r + 3.0, cost_y, x + r + 11.0, cost_y, 1.5, InkR.rgba(156, 33, 41, 160), 1.0, 0.6)
	InkR.text(L10N.t("HUD_SOUL"), x + r + 14.0, y + 4.0, 11.0, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.55 if ready else 0.42, 1.5)


## Высота метки стоимости лечения: значение постоянное, считается один раз.
static func soul_cost_surface() -> float:
	if _soul_cost_surface < 0.0:
		_soul_cost_surface = soul_surface(Player.HEAL_COST / 99.0)
	return _soul_cost_surface


## Height corresponding to an area fraction of the round flask.
static func soul_surface(fill: float, radius := 20.0) -> float:
	var k := clampf(fill, 0.0, 1.0)
	var low := -radius
	var high := radius
	for iteration in 18:
		var middle := (low + high) * 0.5
		var area := radius * radius * acos(middle / radius) - middle * sqrt(maxf(0.0, radius * radius - middle * middle))
		if area > k * PI * radius * radius:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Pure geometry shared with the rendered sweep regression.
static func soul_liquid_cells(fill: float, phase: float) -> Array[PackedVector2Array]:
	var cells: Array[PackedVector2Array] = []
	var k := clampf(fill, 0.0, 1.0)
	if k <= 0.0:
		return cells
	var radius := 20.0
	# Soul is proportional to the filled area, so a single unit occupies
	# visible pixels instead of a subpixel cap at the bottom of the circle.
	var surface := soul_surface(k, radius)
	var amplitude := 1.2 * sin(PI * k)
	for i in 80:
		var x0 := -radius + float(i) * 0.5
		var x1 := x0 + 0.5
		var bottom0 := sqrt(maxf(0.0, radius * radius - x0 * x0))
		var bottom1 := sqrt(maxf(0.0, radius * radius - x1 * x1))
		var top0 := clampf(surface + sin(x0 * 0.28 + phase * 3.0) * amplitude, -bottom0, bottom0)
		var top1 := clampf(surface + sin(x1 * 0.28 + phase * 3.0) * amplitude, -bottom1, bottom1)
		if bottom0 - top0 + bottom1 - top1 < 0.00001:
			continue
		var origin := Vector2(57.0, 101.0)
		var points := PackedVector2Array([origin + Vector2(x0, top0), origin + Vector2(x1, top1)])
		# Avoid repeated endpoints at the clipped edge of a partially wet cell.
		if bottom1 - top1 > 0.000001:
			points.append(origin + Vector2(x1, bottom1))
		if bottom0 - top0 > 0.000001:
			points.append(origin + Vector2(x0, bottom0))
		if not Geometry2D.triangulate_polygon(points).is_empty():
			cells.append(points)
	return cells



func _draw_dash_chevrons() -> void:
	var x := 38.0
	var y := 143.0
	var ready_val := player.dash_ready()
	var ready := ready_val >= 1.0
	InkR.srand(320)
	for i in range(3):
		var tri := [
			Vector2(x + i * 9.0, y - 8.0),
			Vector2(x + 8.0 + i * 9.0, y),
			Vector2(x + i * 9.0, y + 8.0),
		]
		var col := InkR.INK if ready else InkR.rgba(23, 19, 15, 56)
		var al := 0.9 if ready else 0.5
		InkR.poly(tri, 2.6, col, al, 0.5)
		if not ready and float(i) / 3.0 < ready_val:
			InkR.poly(tri, 2.6, InkR.rgba(156, 33, 41, 160), 1.0, 0.4)
	InkR.text(L10N.t("HUD_DASH"), x + 4.0, y + 19.0, 9.0, InkR.F_DISPLAY, InkR.A_LEFT, InkR.INK, 0.4, 2.0)


func _draw_combo(cy: float) -> void:
	var a := clampf(float(flow.combo_t) / 1.6, 0.0, 1.0)
	var pop := 1.0 + float(flow.combo_pop) * 0.4
	var cx := size.x * 0.5
	InkR.text("×%d" % int(flow.combo), cx, cy, roundf(34.0 * pop), InkR.F_HAND, InkR.A_CENTER, InkR.RED, minf(1.0, a * 2.0), 0.0, 1.2)
	InkR.text(L10N.t("HUD_COMBO"), cx, cy + 16.0, 9.0, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.45 * a, 3.0)


func _draw_banner() -> void:
	var a := 1.0
	if _banner.t > _banner.max - 0.5:
		a = (_banner.max - _banner.t) / 0.5
	elif _banner.t < 1.2:
		a = _banner.t / 1.2
	a = clampf(a, 0.0, 1.0)
	var cx := size.x * 0.5
	var ts := 40.0
	var tw := InkR.measure_text(String(_banner.title), ts, 3.0, InkR.F_TITLE)
	var max_w := maxf(320.0, size.x - 240.0)
	if tw > max_w:
		ts = maxf(22.0, ts * max_w / tw)
	InkR.text(String(_banner.title), cx, 232.0, ts, InkR.F_TITLE, InkR.A_CENTER, InkR.INK, a, 3.0, 2.0)
	InkR.line(cx - 160.0, 248.0, cx + 160.0, 248.0, 2.5, InkR.RED, a, 1.4)
	if not String(_banner.sub).is_empty():
		InkR.text(String(_banner.sub), cx, 274.0, 16.0, InkR.F_HAND, InkR.A_CENTER, InkR.INK, a * 0.72)


## Текущее оружие справа сверху: имя и точки-переключатели.
func _draw_weapon() -> void:
	var wname := player.weapon_name()
	if wname.is_empty():
		return
	var right := size.x - (140.0 if CTL.touch_enabled else 40.0)
	draw_string(FONT_TEXT, Vector2(right - 340.0, 36.0), L10N.t("ui.hud.weapon"),
		HORIZONTAL_ALIGNMENT_RIGHT, 340.0, 11, FAINT)
	draw_string(FONT_BOLD, Vector2(right - 340.0, 62.0), wname,
		HORIZONTAL_ALIGNMENT_RIGHT, 340.0, 18, Color(INK, 0.82))
	var count: int = player.weapons.size()
	for i in count:
		var c := Vector2(right - float(count - 1 - i) * 16.0, 78.0)
		draw_circle(c, 4.0, RED if i == player.weapon_index else Color(INK, 0.22))


## Полоса босса: имя, здоровье, фаза и состояние печати.
func _draw_boss() -> void:
	var w := minf(560.0, size.x - 420.0)
	if w < 260.0:
		w = minf(420.0, size.x - 80.0)
	var x := (size.x - w) * 0.5
	var y := 18.0
	draw_string(FONT_BOLD, Vector2(x, y + 2.0), L10N.t("entity.keeper.name"),
		HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(INK, 0.85))
	InkR.srand(410)
	InkR.rect(x, y + 10.0, w, 10.0, InkR.rgba(23, 19, 15, 36), InkR.rgba(23, 19, 15, 130), 1.4, 1.0, 0.5)
	var frac := clampf(float(boss.hp) / float(maxi(1, boss.max_hp)), 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(x, y + 10.0, w * frac, 10.0), RED)
	draw_line(Vector2(x + w * 0.5, y + 8.0), Vector2(x + w * 0.5, y + 22.0),
		Color(PAPER, 0.85), 2.0)
	draw_string(FONT_TEXT, Vector2(x + w + 10.0, y + 19.0),
		L10N.t("ui.hud.boss.phase", [boss.phase]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FAINT)
	if boss.seal_open:
		draw_string(FONT_BOLD, Vector2(x, y + 36.0), L10N.t("ui.hud.boss.seal_open"),
			HORIZONTAL_ALIGNMENT_CENTER, w, 11, RED)


func _draw_toast(y: float) -> void:
	var a := clampf(toast_t / 0.6, 0.0, 1.0)
	var w := minf(540.0, size.x - 80.0)
	var x := (size.x - w) * 0.5
	InkR.srand(420)
	InkR.rect(x, y, w, 40.0, InkR.rgba(246, 237, 218, int(235 * a)), InkR.rgba(23, 19, 15, int(180 * a)), 1.6, a, 0.7)
	draw_rect(Rect2(x + 2.0, y + 2.0, w - 4.0, 2.5), Color(RED, a))
	draw_string(FONT_BOLD, Vector2(x, y + 27.0), toast,
		HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(INK, 0.92 * a))


func _draw_debug() -> void:
	var lines := PackedStringArray()
	match debug_page:
		1:
			lines = ["F2 · " + L10N.t("debug.hitboxes"), "F3 · " + L10N.t("debug.console"),
				"F4 · " + L10N.t("debug.title"), "F5 · " + L10N.t("debug.performance"), "F6 · " + L10N.t("debug.world")]
		2:
			lines = ["FPS %d · %d Hz" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second],
				"Draw calls %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"Physics %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
				"Video %.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
				"Particles %d" % InkFx.parts.size()]
		3:
			if is_instance_valid(player) and flow != null and is_instance_valid(flow.level):
				lines = ["%s / %s" % [flow.level_id, flow.checkpoint_id],
					"XY %.1f, %.1f" % [player.global_position.x, player.global_position.y],
					"V %.0f, %.0f · HP %d" % [player.velocity.x, player.velocity.y, player.hp],
					"%s · %d / %d" % [L10N.t("debug.enemies"), flow.level.enemy_count(), flow.level.killed_ids.size()]]
	if debug_on:
		lines.append("F2 · " + L10N.t("debug.hitboxes"))
	var origin := Vector2(size.x - 243.0, 90.0)
	draw_rect(Rect2(origin, Vector2(223, 14 + lines.size() * 20)), Color(INK, 0.91))
	var y := origin.y + 22.0
	for line in lines:
		draw_string(FONT_TEXT, Vector2(origin.x + 12.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, 199, 15, Color("#f1e6d0"))
		y += 20.0
