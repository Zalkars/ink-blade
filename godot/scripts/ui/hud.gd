extends Control

## HUD в чернильном стиле 0.2: маски здоровья, шкала чернил, шевроны рывка,
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
const DEBUG_HELP := 1
const DEBUG_PERFORMANCE := 2
const DEBUG_WORLD := 4
const DEBUG_ALL := DEBUG_HELP | DEBUG_PERFORMANCE | DEBUG_WORLD
var room_prompt := ""
var room_action_available := false


func set_room_prompt(message: String, enabled := false) -> void:
	if room_prompt != message or room_action_available != enabled:
		room_prompt = message
		room_action_available = enabled
		queue_redraw()


func room_prompt_rect() -> Rect2:
	return Rect2(Vector2((size.x - 286.0) * 0.5, size.y - 94.0), Vector2(286, 48))


func is_room_touch(point: Vector2) -> bool:
	return visible and room_action_available and room_prompt_rect().has_point(get_global_transform().affine_inverse() * point)

var debug_sections := 0:
	set(value):
		debug_sections = value
		queue_redraw()
var debug_all := false:
	set(value):
		debug_all = value
		queue_redraw()


func toggle_debug_section(section: int) -> void:
	if debug_all:
		debug_sections = DEBUG_ALL
		debug_on = true
		debug_all = false
	debug_sections ^= section


func hitboxes_visible() -> bool:
	return debug_on or debug_all


func toggle_hitboxes() -> void:
	if debug_all:
		debug_all = false
		debug_sections = DEBUG_ALL
		debug_on = false
	else:
		debug_on = not debug_on
var hint := ""
var toast := ""
var toast_t := 0.0

var _hp_before := 5
var _hp_anim := 0.0
var _lost_from := 5
var _t := 0.0
var _banner := {"title": "", "sub": "", "t": 0.0, "max": 1.0}
## Чернильница: плавно проседает, поэтому храним показанное значение,
## время последней волны и жизнь капли разлива.
var _ink_before := 0.0
var _ink_shown := 0.0
var _ink_spill := 0.0
var _ink_spill_frac := 0.0
var _ink_wave_t := -100.0
var _vitals := Vector4i(-1, -1, -1, -1)
var _boss_status := Vector3i(-1, -1, -1)
var _screen_fx := Vector2.ZERO
var _combo_visible := false
var _was_debug_on := false


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
		if player.ink != _ink_before:
			if player.ink < _ink_before:
				_ink_spill_frac = clampf(_ink_before / maxf(1.0, player.max_ink), 0.02, 1.0)
				_ink_spill = 0.7
			_ink_before = player.ink
			animate = true
		var target := clampf(player.ink, 0.0, player.max_ink)
		if not is_equal_approx(_ink_shown, target):
			# Прирост виден сразу, а урон «проседает» за доли секунды.
			_ink_shown = target if target > _ink_shown else move_toward(_ink_shown, target, delta * 60.0)
			animate = true
		if _ink_spill > 0.0:
			_ink_spill = maxf(0.0, _ink_spill - delta)
			animate = true
		if _ink_shown > 0.0 and _ink_shown < player.max_ink and _t - _ink_wave_t >= 1.0 / 30.0:
			_ink_wave_t = _t
			animate = true
		animate = animate or player.hp == 1
	var boss_status := Vector3i(-1, -1, -1)
	if is_instance_valid(boss) and boss.engaged and not boss.dead:
		boss_status = Vector3i(boss.hp, boss.phase, int(boss.seal_open))
	var screen_fx := Vector2(InkFx.damage, InkFx.flash)
	var combo_visible: bool = flow != null and flow.combo >= 2 and flow.combo_t > 0.0
	if animate or int(_t * 10.0) != ink_frame or vitals != _vitals or boss_status != _boss_status \
		or screen_fx != _screen_fx or combo_visible or combo_visible != _combo_visible \
		or debug_on or debug_all or debug_sections > 0 or debug_on != _was_debug_on:
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
	_ink_before = p.ink
	_ink_shown = p.ink
	_ink_spill = 0.0
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
		_draw_ink_gauge()
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

	if debug_on or debug_all or debug_sections > 0:
		_draw_debug()
	if not room_prompt.is_empty():
		var button := room_prompt_rect()
		draw_rect(button, Color(INK, 0.92))
		draw_rect(button, Color(RED, 0.85), false, 2.0)
		draw_string(FONT_BOLD, button.position + Vector2(8, 30), room_prompt,
			HORIZONTAL_ALIGNMENT_CENTER, button.size.x - 16, 17, Color("#f1e6d0"))


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


func _draw_ink_gauge() -> void:
	var x := 56.0
	var y := 94.0
	var w := 176.0
	var h := 16.0
	var max_value := maxf(1.0, player.max_ink)
	var target := clampf(_ink_shown, 0.0, max_value)
	var k := target / max_value
	var ready := target >= Player.HEAL_COST
	var full := k >= 0.999

	InkR.srand(310)
	if full:
		InkR.radial_glow(x + w * 0.5, y + h * 0.5, 74.0, InkR.RED, 0.16,
			x - 12.0, y - 14.0, w + 24.0, h + 28.0)
	InkR.rect(x, y, w, h, InkR.rgba(240, 230, 208, 180), InkR.rgba(23, 19, 15, 150), 1.6, 1.0, 0.5)
	if k > 0.0:
		InkR.fill_poly(ink_bar_points(k, _t), InkR.INK, 0.9, 0.25, false)

	var division := 25.0
	var value := division
	while value < max_value - 0.01:
		var dx := x + 1.5 + (w - 3.0) * value / max_value
		var cost := is_equal_approx(value, Player.HEAL_COST)
		InkR.line(dx, y + 1.5, dx, y + h - 1.5, 1.6 if cost else 1.0,
			InkR.RED if cost else InkR.rgba(23, 19, 15, 90), 0.85 if cost else 0.55, 0.2)
		value += division
	InkR.rect(x, y, w, h, null, InkR.RED if ready else InkR.rgba(23, 19, 15, 170),
		2.2 if ready else 1.6, 1.0, 0.5)

	InkR.text(L10N.t("HUD_INK"), x, y - 7.0, 10.0, InkR.F_DISPLAY, InkR.A_LEFT,
		InkR.INK, 0.55 if ready else 0.42, 2.2)
	InkR.text("%d/%d" % [roundi(target), roundi(max_value)], x + w, y - 7.0, 10.0,
		InkR.F_DISPLAY, InkR.A_RIGHT, InkR.INK, 0.42, 0.5)

	# Капля отрывается от уровня, который был до урона, и падает вниз.
	if _ink_spill > 0.0:
		var progress := 1.0 - _ink_spill / 0.7
		var drop_x := x + 1.5 + (w - 3.0) * clampf(_ink_spill_frac, 0.0, 1.0)
		var drop_y := y + h + 1.0 + progress * 13.0
		InkR.circle(drop_x, drop_y, 3.6 * (1.0 - progress * 0.45), InkR.INK, null,
			1.0, 1.0 - progress * 0.85, 0.25, 8, false)
		InkR.line(drop_x, y + h + 1.0, drop_x, drop_y - 2.0, 1.4, InkR.INK, 0.55 * (1.0 - progress), 0.3)


## Заполнение шкалы: левый край ровный, правый — волна. Чистая геометрия
## для визуальной регрессии; координаты совпадают с полосой HUD.
static func ink_bar_points(fill: float, phase: float, x := 56.0, y := 94.0, w := 176.0, h := 16.0) -> Array[Vector2]:
	var k := clampf(fill, 0.0, 1.0)
	if k <= 0.0:
		return []
	var left := x + 1.5
	var top := y + 1.5
	var bottom := y + h - 1.5
	var right := left + (w - 3.0) * k
	if k >= 0.999:
		right = x + w - 1.5
	var points: Array[Vector2] = [Vector2(left, top), Vector2(right, top)]
	var amplitude := 0.9 * sin(PI * k)
	if amplitude > 0.0:
		for i in range(1, 8):
			var yy := lerpf(top, bottom, float(i) / 8.0)
			var xx := clampf(right + sin(yy * 0.9 + phase * 3.0) * amplitude, left, x + w - 1.5)
			points.append(Vector2(xx, yy))
	points.append(Vector2(right, bottom))
	points.append(Vector2(left, bottom))
	return points


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
	var shown := DEBUG_ALL if debug_all else debug_sections
	var left := Vector2(18, 110)
	var right := Vector2(size.x - 288, 96)
	if shown & DEBUG_WORLD:
		_draw_debug_block(left, L10N.t("debug.world"), _debug_world_lines())
	if shown & DEBUG_PERFORMANCE:
		right.y += _draw_debug_block(right, L10N.t("debug.performance"), [
			"FPS %d · %d Hz" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second],
			"Draw calls %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"Physics %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
			"Video %.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			"Particles %d" % InkFx.parts.size()]) + 9.0
	if shown & DEBUG_HELP or hitboxes_visible():
		var shortcuts: PackedStringArray = ["F2 · " + L10N.t("debug.hitboxes")]
		if shown & DEBUG_HELP:
			shortcuts.append_array(["F3 · " + L10N.t("debug.all"), "F4 · " + L10N.t("debug.title"), "F7 · " + L10N.t("debug.console")])
		_draw_debug_block(right, L10N.t("debug.diagnostics"), shortcuts)


func _debug_world_lines() -> PackedStringArray:
	if not is_instance_valid(player) or flow == null or not is_instance_valid(flow.level):
		return []
	var result: PackedStringArray = ["%s / %s" % [flow.level_id, flow.checkpoint_id],
		"XY %.1f / %.1f" % [player.global_position.x, player.global_position.y],
		"V %.0f, %.0f · HP %d" % [player.velocity.x, player.velocity.y, player.hp],
		"%s · %.0f / %.0f" % [L10N.t("debug.ink"), player.ink, player.max_ink],
		"%s · %d (%d)" % [L10N.t("debug.enemies"), flow.level.enemy_count(), flow.level.killed_ids.size()]]
	var initial_count := result.size()
	for rule in ["flight", "god", "damage"]:
		if flow.debug_rules[rule]:
			result.append("+ " + L10N.t("debug." + rule))
	if result.size() == initial_count:
		result.append(L10N.t("debug.rules_default"))
	return result


func _draw_debug_block(origin: Vector2, heading: String, lines: PackedStringArray) -> float:
	var height := 33.0 + lines.size() * 19.0
	draw_rect(Rect2(origin, Vector2(270, height)), Color(INK, 0.89))
	draw_rect(Rect2(origin, Vector2(3, height)), RED)
	draw_string(FONT_BOLD, origin + Vector2(12, 20), heading, HORIZONTAL_ALIGNMENT_LEFT, 246, 16, Color("#f1e6d0"))
	var y := origin.y + 22.0
	for line in lines:
		y += 19.0
		draw_string(FONT_TEXT, Vector2(origin.x + 12.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, 246, 15, Color("#f1e6d0"))
	return height
