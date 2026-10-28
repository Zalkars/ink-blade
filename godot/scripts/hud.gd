class_name InkHud
extends RefCounted

## Полный порт Game/Hud.cs

static func panel(x: float, y: float, w: float, h: float, title_ = null, title_size := 26.0) -> void:
	var ink := InkR
	ink.srand(int(x * 3 + y))
	ink.save()
	ink.alpha_push(0.35)
	ink.fill_rect_color(x + 8, y + 9, w, h, ink.INK, 1.0)
	ink.restore()

	ink.rect(x, y, w, h, ink.rgba(246, 237, 218, 245), ink.INK, 2.6, 1.0, 1.1)
	ink.rect(x + 6, y + 6, w - 12, h - 12, null, ink.rgba(23, 19, 15, 46), 1.0, 1.0, 0.7)

	var m := 12.0
	var corners := [
		[x + m, y + m, 1.0, 1.0], [x + w - m, y + m, -1.0, 1.0],
		[x + m, y + h - m, 1.0, -1.0], [x + w - m, y + h - m, -1.0, -1.0]
	]
	for c in corners:
		ink.line(c[0], c[1], c[0] + 12 * c[2], c[1], 1.4, ink.rgba(23, 19, 15, 89), 1.0, 1.0)
		ink.line(c[0], c[1], c[0], c[1] + 12 * c[3], 1.4, ink.rgba(23, 19, 15, 89), 1.0, 1.0)

	if title_ != null:
		ink.text(title_, x + w / 2, y + 40, title_size, ink.F_DISPLAY, ink.A_CENTER, ink.INK, 1.0, 4)
		ink.line(x + 34, y + 54, x + w - 34, y + 54, 2.0, ink.rgba(156, 33, 41, 153), 1.0, 1.0)

	ink.save()
	ink.alpha_push(0.7)
	ink.circle(x + w - 30, y + h - 30, 11, null, ink.RED, 1.6, 1.0, 0.8, 10)
	ink.text(L10N.t("PANEL_SEAL"), x + w - 30, y + h - 25, 12, ink.F_DISPLAY, ink.A_CENTER, ink.RED)
	ink.restore()

static func glyph(x: float, y: float, label: String, active := false, panel_size := 28.0, font_size := 13.0, pad := 9.0) -> float:
	var ink := InkR
	var gw := maxf(panel_size, ink.measure_text(label, font_size) + pad * 2)
	var gh := panel_size
	ink.srand(int(x * 7 + y))
	if active:
		ink.rect(x, y - gh / 2, gw, gh, ink.RED, ink.RED_DARK, 1.6, 1.0, 0.7)
		ink.text(label, x + gw / 2, y + 1, font_size, ink.F_BOLD, ink.A_CENTER, ink.CREAM, 1.0, 0.0, 0.0, 1)
	else:
		ink.rect(x, y - gh / 2, gw, gh, ink.rgba(246, 237, 218, 191), ink.rgba(23, 19, 15, 179), 1.4, 1.0, 0.7)
		ink.text(label, x + gw / 2, y + 1, font_size, ink.F_BOLD, ink.A_CENTER, ink.INK, 1.0, 0.0, 0.0, 1)
	return gw

static func mask_draw(p, i: int) -> void:
	var ink := InkR
	var px: float = 56 + i * 34
	var py := 44.0
	var alive: bool = float(i) < p.hp
	var last: bool = alive and p.hp == 1.0
	ink.srand(300 + i)
	if alive:
		var pulse: float = 1.0 + sin(p.t * 6) * 0.06 if last else 1.0
		ink.blob(px, py, 11 * pulse, ink.RED, ink.INK, 2.0, 1.0, 0.8, 9, 0.1)
		ink.circle(px - 6.5, py - 4, 2.1, ink.CREAM, null, 2.0, 0.85, 0.2, 10, false)
		ink.circle(px + 4, py - 5, 2.1, ink.CREAM, null, 2.0, 0.85, 0.2, 10, false)
		ink.line(px - 4, py + 4, px + 4, py + 4, 1.6, ink.RED_DARK, 0.8, 1.0)
	else:
		ink.blob(px, py, 11, null, ink.rgba(23, 19, 15, 89), 1.5, 1.0, 0.8, 9, 0.1)
		ink.line(px - 6, py - 6, px + 2, py + 2, 1.1, ink.rgba(23, 19, 15, 71), 1.0, 1.0)
		ink.line(px + 4, py - 5, px + 1, py + 1, 1.0, ink.rgba(23, 19, 15, 56), 1.0, 1.0)

static func draw_soul(p) -> void:
	var ink := InkR
	var x := 57.0
	var y := 101.0
	var r := 21.0
	var k: float = p.soul / 99.0
	var ready_: bool = p.soul >= 40

	ink.srand(310)
	ink.save()
	# заливка круга-«рыбы»: фон
	ink.circle(x, y, r - 3, ink.rgba(240, 230, 208, 230), null, 2.0, 1.0, 0.5, 24, false)
	# жидкость волной, обрезанная по кругу
	var top: float = y + r - (r * 2) * k
	var dy := top - y
	var hh: float = sqrt(maxf(0.0, r * r - dy * dy))
	if hh > 0.1:
		var ph_r: float = atan2(dy, hh)
		var ph_l: float = atan2(dy, -hh)
		var pts: Array = []
		# поверхность с волной
		var nseg := 12
		for i in range(nseg + 1):
			var xx: float = x - hh + (float(i) / float(nseg)) * hh * 2.0
			pts.append(Vector2(xx, top + sin(i * 1.3 + p.t * 3) * 1.6))
		# дуга по кругу от правой точки через низ к левой
		var arc_t := ph_r
		if ph_l + InkR.TAU > arc_t:
			ph_l += InkR.TAU
		var steps := 16
		arc_t += (ph_l - arc_t) / float(steps) * 0.0
		for i in range(1, steps + 1):
			var an := lerpf(ph_r, ph_l, float(i) / float(steps))
			pts.append(Vector2(x + cos(an) * r, y + sin(an) * r))
		if pts.size() >= 3:
			# градиент: сначала базовый цвет
			ink.fill_poly(pts, ink.rgba(23, 19, 15, 205), 1.0, 0.5, false)
	ink.restore()

	ink.circle(x, y, r, null, ink.RED if ready_ else ink.rgba(23, 19, 15, 166), 2.6 if ready_ else 2.0, 1.0, 0.9, 14)
	ink.line(x - r + 4, y - 6, x - r + 4, y + 9, 1.0, ink.rgba(246, 237, 218, 102), 1.0, 1.0)

	if ready_:
		var pulse: float = 0.5 + sin(p.t * 5) * 0.3
		ink.save()
		ink.alpha_push(pulse * 0.5)
		ink.circle(x, y, r + 5, null, ink.RED, 1.2, 1.0, 1.0, 16)
		ink.restore()

	var cost_y: float = y + r - (r * 2) * (40.0 / 99.0)
	ink.line(x + r + 3, cost_y, x + r + 11, cost_y, 1.2, ink.rgba(156, 33, 41, 128), 1.0, 1.0)
	ink.text(L10N.t("HUD_SOUL"), x + r + 14, y + 4, 10, ink.F_DISPLAY, ink.A_LEFT, ink.INK, 0.4, 2)

static func draw_dash(p) -> void:
	var ink := InkR
	var x := 38.0
	var y := 143.0
	var ready_: bool = p.dash_cd <= 0.0 and (p.grounded or p.air_dash)
	ink.srand(320)
	for i in range(3):
		var tri := [
			Vector2(x + i * 9, y - 8), Vector2(x + 8 + i * 9, y),
			Vector2(x + i * 9, y + 8)
		]
		var col: Color = ink.INK if ready_ else ink.rgba(23, 19, 15, 56)
		var al: float = 0.9 if ready_ else 0.5
		ink.poly(tri, 2.6, col, al, 0.5)
		if not ready_:
			var k: float = 1.0 - minf(1.0, p.dash_cd / 0.34)
			if float(i) / 3.0 < k:
				ink.poly(tri, 2.6, ink.rgba(156, 33, 41, 140), 1.0, 0.4)
	ink.text(L10N.t("HUD_DASH"), x + 4, y + 19, 9, ink.F_DISPLAY, ink.A_LEFT, ink.INK, 0.35, 2)

static func draw_combo(g) -> void:
	var ink := InkR
	if g.combo < 2:
		return
	var a: float = clampf(g.combo_t / 1.6, 0.0, 1.0)
	var pop: float = 1.0 + g.combo_pop * 0.4
	ink.save()
	ink.alpha_push(1.0)
	ink.text("×%d" % g.combo, 640, 58, roundf(34 * pop), ink.F_HAND, ink.A_CENTER, ink.RED, minf(1.0, a * 2), 0.0, 1.2)
	ink.text(L10N.t("HUD_COMBO"), 640, 74, 9, ink.F_DISPLAY, ink.A_CENTER, ink.INK, 0.4, 3)
	ink.restore()

static func draw_device() -> void:
	var ink := InkR
	var gp: bool = CTL.device == "gamepad"
	var x := 1236.0
	ink.save()
	ink.alpha_push(0.45)
	ink.text(L10N.t("HUD_GAMEPAD") if gp else L10N.t("HUD_KEYBOARD"), x - 30, 34, 10, ink.F_DISPLAY, ink.A_RIGHT, ink.INK, 1.0, 2)
	ink.text(L10N.t("HUD_HELP", [CTL.first_key_label("help")]), x - 30, 52, 10, ink.F_DISPLAY, ink.A_RIGHT, ink.INK, 1.0, 1)
	ink.restore()
	ink.alpha_push(0.4)
	if gp:
		ink.rect(x - 22, 24, 20, 12, null, ink.INK, 1.4, 1.0, 0.5)
		ink.circle(x - 17, 29, 1.6, ink.INK, null, 2.0, 1.0, 0.2, 8, false)
		ink.circle(x - 11, 31, 1.6, ink.INK, null, 2.0, 1.0, 0.2, 8, false)
	else:
		ink.rect(x - 22, 25, 20, 11, null, ink.INK, 1.4, 1.0, 0.5)
		ink.line(x - 18, 30, x - 15, 30, 1.0, ink.INK, 1.0, 1.0)
		ink.line(x - 12, 30, x - 9, 30, 1.0, ink.INK, 1.0, 1.0)
	ink.alpha_pop()

static func draw_hints(g) -> void:
	var ink := InkR
	var a: float = g.hint_alpha
	if a <= 0.01:
		return
	var lines := [
		[["attack", L10N.t("HINT_ATTACK")], ["dash", L10N.t("HINT_DASH")], ["heal", L10N.t("HINT_HEAL")]],
		[["jump", L10N.t("HINT_JUMP")], ["attack_up", L10N.t("HINT_DROP")], ["pause", L10N.t("HINT_PAUSE")]],
	]
	ink.save()
	ink.alpha_push(a * 0.8)
	var x := 44.0
	var y := 650.0
	ink.rect(x - 12, y - 24, 660, 62, ink.rgba(246, 237, 218, 179), ink.rgba(23, 19, 15, 77), 1.2, 1.0, 0.8)
	for li in range(lines.size()):
		var cxm := x
		var cy: float = y + li * 24
		for entry in lines[li]:
			var action: String = entry[0]
			var textv: String = entry[1]
			var label: String = CTL.label_of(action)
			var gw: float = glyph(cxm, cy - 4, label, false, 20, 11, 8)
			cxm += gw + 9
			ink.text(textv, cxm, cy + 1, 12, ink.F_BODY, ink.A_LEFT, ink.INK, 0.75)
			cxm += ink.measure_text(textv, 12) + 17
	ink.restore()

static func draw_banner(g) -> void:
	var ink := InkR
	var b: Dictionary = g.banner
	if b.t <= 0.0:
		return
	var a := 1.0
	if b.t > b.max - 0.5:
		a = (b.max - b.t) / 0.5
	elif b.t < 1.2:
		a = b.t / 1.2
	ink.save()
	ink.alpha_push(1.0)
	# длинные названия залов в других языках не должны вылезать за экран
	var ts := 40.0
	var tw := ink.measure_text(b.title, ts, 3.0)
	if tw > 760.0:
		ts = maxf(22.0, ts * 760.0 / tw)
	ink.text(b.title, 640, 238, ts, ink.F_TITLE, ink.A_CENTER, ink.INK, clampf(a, 0.0, 1.0), 3, 2)
	ink.line(480, 254, 800, 254, 2.5, ink.RED, 1.0, 1.4)
	if b.sub != "":
		ink.text(b.sub, 640, 280, 15, ink.F_HAND, ink.A_CENTER, ink.INK, clampf(a, 0.0, 1.0) * 0.65)
	ink.restore()

static func draw(g) -> void:
	var p = g.player
	for i in range(int(p.max_hp)):
		mask_draw(p, i)
	draw_soul(p)
	draw_dash(p)
	draw_combo(g)
	if g.touch_mode or CTL.device == "touch":
		draw_touch_hints(g)
	else:
		draw_device()
		draw_hints(g)
	draw_banner(g)


static func draw_touch_hints(g) -> void:
	var ink := InkR
	var a: float = g.hint_alpha
	if a <= 0.01:
		return
	ink.save()
	ink.alpha_push(a * 0.82)
	ink.rect(330, 666, 620, 32, ink.rgba(23, 19, 15, 82),
		ink.rgba(246, 237, 218, 92), 1.0, 1.0, 0.5)
	ink.text(L10N.t("TOUCH_HINT_BAR"),
		640, 687, 10, ink.F_DISPLAY, ink.A_CENTER, ink.CREAM, 1.0, 0.8)
	ink.restore()
