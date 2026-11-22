extends RefCounted

## Уникальные мировые ориентиры четырёх зон главы I. Декор не принимает чернила.
## Используется для запекания 1280px полос уровня и живых элементов в кадре.

const PAPER := Color("#f1e6d0")
const RIDGE_FAR := Color("#d8ccb4")
const RIDGE_MID := Color("#c0b299")
const RIDGE_NEAR := Color("#998c77")
const INK_DARK := Color("#17130f")
const RED := Color("#9c1f24")

const STRIP_W := 1280.0
const STRIP_H := 720.0


static func zone_at(x: float, level_id: String) -> String:
	if level_id != "ch01_hall":
		return "sanctum"
	if x < 2560.0:
		return "threshold"
	if x < 7040.0:
		return "archive"
	if x < 11264.0:
		return "gallery"
	return "sanctum"


static func draw_backdrop(cv: CanvasItem, cam_x: float, vp_w: float, vp_h: float, level_id: String) -> void:
	InkR.init_static()
	InkR.set_canvas(cv)
	InkR.begin_frame(0.0)

	# Бумага на весь экран в координатах камеры.
	var x0 := cam_x - vp_w * 0.5 - 40.0
	var bw := vp_w + 80.0
	if InkR.tex_paper != null:
		cv.draw_texture_rect(InkR.tex_paper, Rect2(x0, -20.0, bw, vp_h + 40.0), false)
	else:
		cv.draw_rect(Rect2(x0, -20.0, bw, vp_h + 40.0), PAPER)

	# All zones keep the original paper palette. Variety comes from their decor.
	var zone := zone_at(cam_x, level_id)
	if zone == "threshold":
		var sx := 920.0 + cam_x * 0.08
		InkR.srand(3)
		InkR.circle(sx, 168.0, 106.0, InkR.rgba(156, 33, 41, 18), InkR.rgba(156, 33, 41, 110), 2.0, 1.0, 1.4, 36)
		InkR.circle(sx - 15.0, 160.0, 88.0, PAPER, InkR.rgba(23, 19, 15, 100), 2.0, 1.0, 1.1, 32)
	# The sky is continuous: interior landmarks change, not the distant landscape.
	_draw_parallax_ridge(cv, x0, bw, vp_h, 490.0, 62.0, RIDGE_FAR, cam_x * 0.14, 0.004, 0.0)
	_draw_parallax_ridge(cv, x0, bw, vp_h, 590.0, 48.0, RIDGE_MID, cam_x * 0.23, 0.006, 1.4)


static func _draw_parallax_ridge(cv: CanvasItem, x0: float, w: float, h: float, base_y: float, amp: float, col: Color, scroll: float, freq: float, phase: float) -> void:
	var pts := PackedVector2Array()
	var step := 48.0
	# Anchor sampling in world space so the silhouette does not re-tessellate
	# every time the camera moves a fraction of a pixel.
	var x := floorf(x0 / step) * step - step
	while x <= x0 + w + step:
		var wx := x - scroll
		var y := base_y - sin(wx * freq + phase) * amp - sin(wx * (freq * 2.3) + 1.7) * amp * 0.35
		pts.append(Vector2(x, clampf(y, 80.0, h - 2.0)))
		x += step
	pts.append(Vector2(x0 + w + step, h + 10.0))
	pts.append(Vector2(x0 - step, h + 10.0))
	cv.draw_colored_polygon(pts, col)


static func draw_strip_decor(strip_index: int, level_id: String, data: Dictionary, bounds: Rect2) -> void:
	var x0 := float(strip_index) * STRIP_W
	var x1 := minf(x0 + STRIP_W, bounds.end.x)
	if x1 <= x0:
		return
	var floor_y := _floor_y_at(x0 + STRIP_W * 0.5, data)
	_draw_strip_dust(x0, x1, strip_index)
	# Draw fixed world landmarks through every intersecting bake strip. No strip-sized motif loop.
	if level_id != "ch01_hall":
		_draw_sanctum_strip(strip_index, x0, floor_y)
	else:
		if x0 < 2560.0:
			_draw_threshold_strip(strip_index, floor_y)
		if x1 > 2560.0 and x0 < 7040.0:
			_draw_archive_strip(strip_index, x0, x1, data)
		if x1 > 7040.0 and x0 < 11264.0:
			_draw_gallery_strip(strip_index, x0, x1, floor_y, data)
		if x1 > 11264.0:
			_draw_sanctum_strip(strip_index, x0, floor_y)

	# Угловые штриховки на границах уровня.
	if strip_index == 0:
		InkR.srand(301)
		InkR.hatch([Vector2(0, 470), Vector2(120, 620), Vector2(0, 620)], 12.0, 0.1, InkR.INK, 1.0, true)
	if x1 >= bounds.end.x - 16.0:
		InkR.srand(302)
		InkR.hatch([Vector2(bounds.end.x, 470), Vector2(bounds.end.x, 620), Vector2(bounds.end.x - 140, 620)], 12.0, 0.1, InkR.INK, 1.0, true)

	# Поверхности земли и платформ (solid + one_way), попадающие в полосу.
	for spec in data.get("solids", []):
		var r := _rect_of(spec)
		if r.end.x >= x0 - 32.0 and r.position.x <= x1 + 32.0:
			draw_surface(r, false, bounds, data.get("solids", []))
	for spec in data.get("one_ways", []):
		var r := _rect_of(spec)
		if r.end.x >= x0 - 32.0 and r.position.x <= x1 + 32.0:
			draw_surface(r, true, bounds)


static func _floor_y_at(x: float, data: Dictionary) -> float:
	var best := 576.0
	for spec in data.get("solids", []):
		var r := _rect_of(spec)
		if x >= r.position.x and x <= r.end.x and r.size.y >= 80.0:
			best = r.position.y
			break
	return best


static func _rect_of(d: Dictionary) -> Rect2:
	return Rect2(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("w", 0)), float(d.get("h", 0)))


static func _draw_strip_dust(x0: float, x1: float, strip_index: int) -> void:
	var s := 991 + strip_index * 73
	for i in range(18):
		s = int((s * 16807) % 2147483647)
		var rx := float(s - 1) / 2147483646.0
		s = int((s * 16807) % 2147483647)
		var ry := float(s - 1) / 2147483646.0
		s = int((s * 16807) % 2147483647)
		var rr := 1.0 + (float(s - 1) / 2147483646.0) * 2.5
		InkR.fill_circle_color(x0 + 32.0 + rx * (x1 - x0 - 64.0), 84.0 + ry * 440.0, rr, InkR.INK, 0.07)


static func _draw_threshold_strip(_strip_index: int, _floor_y: float) -> void:
	# One entrance ruin, one lintel, then open country; no colonnade.
	draw_pillar(420.0, 120.0, 64.0, 456.0)
	InkR.line(420.0, 120.0, 1040.0, 92.0, 12.0, InkR.rgba(23, 19, 15, 65), 1.0, 1.0)
	draw_gate(790.0, 128.0, 340.0)
	draw_banner(548.0, 126.0, 70.0, 192.0, 0.19, "I")
	InkR.text(L10N.t("WORLD_INK_REMEMBERS"), 790.0, 70.0, 19.0, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.25, 8.0)
	InkR.srand(102)
	InkR.poly([Vector2(1760, 512), Vector2(1770, 244), Vector2(1850, 226), Vector2(1864, 416)], 9.0, InkR.rgba(23, 19, 15, 65), 1.0, 1.0)
	draw_name_tablet(2380.0, 150.0, 132.0, 180.0, 2)


static func _draw_archive_strip(_strip_index: int, _x0: float, _x1: float, _data: Dictionary) -> void:
	# Asymmetric storage bays: broad bookcase, hanging scrolls, sunken reading room.
	_draw_archive_alcove(2690.0, 156.0, 310.0, 250.0, 17)
	draw_banner(3170.0, 40.0, 84.0, 222.0, 0.17, "")
	InkR.text(L10N.t("zone.archive.title"), 3330.0, 100.0, 22.0, InkR.F_DISPLAY, InkR.A_CENTER, InkR.INK, 0.28, 6.0)
	_draw_archive_alcove(3560.0, 218.0, 192.0, 220.0, 51)
	InkR.srand(418)
	InkR.poly([Vector2(3910, 510), Vector2(3910, 220), Vector2(4050, 110), Vector2(4510, 110), Vector2(4670, 220), Vector2(4670, 410)], 7.0, InkR.rgba(23, 19, 15, 74), 1.0, 1.2)
	_draw_archive_alcove(4070.0, 248.0, 380.0, 250.0, 68)
	for scroll in [[5150.0, 110.0, 84.0, 204.0], [5310.0, 76.0, 110.0, 250.0], [5490.0, 138.0, 64.0, 154.0]]:
		draw_name_tablet(scroll[0], scroll[1], scroll[2], scroll[3], int(scroll[0]))
	_draw_archive_alcove(5930.0, 100.0, 270.0, 244.0, 93)
	draw_gate(6770.0, 134.0, 360.0)


static func _draw_archive_alcove(x: float, y: float, w: float, h: float, seed_id: int) -> void:
	InkR.srand(seed_id)
	InkR.rect(x, y, w, h, InkR.rgba(120, 100, 70, 16), InkR.rgba(23, 19, 15, 58), 1.6, 1.0, 0.8)
	for row in range(4):
		var py := y + 42.0 + float(row) * 46.0
		InkR.line(x + 8.0, py, x + w - 8.0, py, 2.0, InkR.rgba(23, 19, 15, 68), 1.0, 0.4)
		for book in range(int(w / 22.0) - 1):
			var bx := x + 14.0 + float(book) * 20.0
			var bh := 20.0 + float((seed_id + row * 3 + book) % 12)
			InkR.rect(bx, py - bh, 13.0, bh, InkR.rgba(23, 19, 15, 28), InkR.rgba(23, 19, 15, 76), 1.0, 1.0, 0.4)


static func _draw_gallery_strip(_strip_index: int, _x0: float, _x1: float, _floor_y: float, _data: Dictionary) -> void:
	# Broken memorial wall with three distinct groups, open space between them.
	InkR.srand(661)
	InkR.fill_poly([Vector2(7350, 576), Vector2(7350, 176), Vector2(7540, 132), Vector2(7770, 200), Vector2(7910, 480)], InkR.rgba(110, 119, 119, 28), 1.0, 1.0)
	draw_name_tablet(7420.0, 218.0, 210.0, 226.0, 4)
	draw_name_tablet(8130.0, 140.0, 150.0, 230.0, 7)
	InkR.poly([Vector2(8530, 448), Vector2(8530, 122), Vector2(8680, 98), Vector2(8710, 352)], 6.0, InkR.rgba(23, 19, 15, 68), 1.0, 1.0)
	draw_name_tablet(8950.0, 80.0, 168.0, 194.0, 8)
	InkR.fill_poly([Vector2(9640, 544), Vector2(9710, 284), Vector2(10020, 244), Vector2(10180, 480)], InkR.rgba(110, 119, 119, 35), 1.0, 1.0)
	draw_name_tablet(9760.0, 124.0, 260.0, 170.0, 11)
	draw_banner(10570.0, 40.0, 74.0, 196.0, 0.13, "")
	draw_name_tablet(10950.0, 164.0, 180.0, 150.0, 13)


static func _draw_sanctum_strip(_strip_index: int, _x0: float, _floor_y: float) -> void:
	# One ceremonial doorway and one enormous seal, framed only at the arena edges.
	draw_pillar(11300.0, 56.0, 80.0, 520.0)
	draw_gate(12000.0, 120.0, 350.0)
	draw_banner(11610.0, 56.0, 86.0, 244.0, 0.20, "")
	InkR.srand(701)
	InkR.circle(13350.0, 270.0, 208.0, InkR.rgba(156, 33, 41, 14), InkR.rgba(156, 33, 41, 80), 3.0, 1.0, 1.6, 48)
	InkR.circle(13350.0, 270.0, 172.0, null, InkR.rgba(23, 19, 15, 60), 2.0, 1.0, 1.0, 40)
	InkR.line(13260.0, 270.0, 13440.0, 270.0, 4.0, InkR.rgba(156, 33, 41, 86), 1.0, 1.0)
	InkR.line(13350.0, 180.0, 13350.0, 360.0, 4.0, InkR.rgba(156, 33, 41, 86), 1.0, 1.0)
	draw_banner(13810.0, 56.0, 90.0, 300.0, 0.22, L10N.t("PANEL_SEAL"))


static func draw_name_tablet(x: float, y: float, w: float, h: float, idx: int) -> void:
	InkR.srand(550 + idx)
	InkR.rect(x, y, w, h, InkR.rgba(246, 237, 218, 128), InkR.rgba(23, 19, 15, 72), 1.5, 1.0, 0.8)
	for row in range(5):
		var ly := y + 28.0 + float(row) * 26.0
		InkR.line(x + 18.0, ly, x + w - 18.0, ly, 1.4, InkR.rgba(23, 19, 15, 58), 1.0, 0.5)
		if (idx + row) % 2 == 0:
			InkR.line(x + 14.0, ly - 3.0, x + w - 14.0, ly + 4.0, 2.0, InkR.rgba(156, 33, 41, 95), 1.0, 0.6)


static func draw_pillar(x: float, y: float, w: float, h: float) -> void:
	InkR.srand(int(x + y))
	InkR.rect(x, y, w, h, InkR.rgba(120, 100, 70, 15), InkR.rgba(23, 19, 15, 48), 2.0)
	InkR.rect(x - 8.0, y + h - 26.0, w + 16.0, 26.0, InkR.rgba(120, 100, 70, 22), InkR.rgba(23, 19, 15, 56), 2.0)
	InkR.line(x + 10.0, y + 8.0, x + 10.0, y + h - 30.0, 1.0, InkR.rgba(23, 19, 15, 28), 1.0, 0.0)
	InkR.line(x + w - 12.0, y + 8.0, x + w - 12.0, y + h - 30.0, 1.0, InkR.rgba(23, 19, 15, 28), 1.0, 0.0)
	InkR.poly([
		Vector2(x + w * 0.2, y + 40.0), Vector2(x + w * 0.5, y + 120.0), Vector2(x + w * 0.35, y + 230.0),
	], 1.0, InkR.rgba(23, 19, 15, 34), 1.0, 0.0)


static func draw_gate(cx: float, top: float, bottom: float) -> void:
	var w := 150.0
	var pts: Array = [Vector2(cx - w / 2.0, bottom)]
	for i in range(15):
		var a := PI + float(i) / 14.0 * PI
		pts.append(Vector2(cx + cos(a) * (w / 2.0), top + 75.0 + sin(a) * 75.0))
	pts.append(Vector2(cx + w / 2.0, bottom))
	InkR.srand(41)
	InkR.fill_poly(pts, InkR.rgba(30, 24, 18, 72), 1.0, 0.8)
	InkR.poly(pts, 3.0, InkR.rgba(23, 19, 15, 136), 1.0, 1.15, true)

	for i in range(-2, 3):
		InkR.line(cx + float(i) * 27.0, top + 78.0, cx + float(i) * 27.0, bottom - 8.0, 2.0, InkR.rgba(240, 228, 204, 28), 1.0, 0.0)
	InkR.arc(cx, top + 75.0, w / 2.0 - 6.0, PI, PI * 2.0, 2.0, InkR.rgba(240, 228, 204, 34), 1.0, 0.0)

	chain(cx - 58.0, top + 78.0, bottom - 14.0, 2.0, 0.4)
	chain(cx + 62.0, top + 66.0, bottom - 30.0, -2.0, 0.35)
	InkR.line(cx - 62.0, top + 110.0, cx + 64.0, top + 130.0, 4.0, InkR.rgba(20, 16, 12, 128), 1.0, 0.0)
	InkR.line(cx - 62.0, top + 110.0, cx + 64.0, top + 130.0, 1.5, InkR.rgba(240, 228, 204, 32), 1.0, 0.0)


static func draw_banner(x: float, y: float, w: float, h: float, alpha: float, emblem := "") -> void:
	var pts: Array = Array(banner_polygon(x, y, w, h))
	InkR.srand(int(x))
	InkR.fill_poly(pts, InkR.rgba(156, 33, 41, int(alpha * 255.0)), 1.0, 1.2)
	InkR.poly(pts, 1.5, InkR.rgba(23, 19, 15, 89), 0.7, 1.2, true)
	InkR.circle(x + w / 2.0, y + h * 0.38, w * 0.2, null, InkR.rgba(240, 228, 204, 71), 1.5, 1.0, 0.8)
	InkR.line(x + w / 2.0, y + h * 0.2, x + w / 2.0, y + h * 0.56, 1.0, InkR.rgba(240, 228, 204, 51), 1.0, 0.0)
	InkR.line(x + w / 2.0, y, x + w / 2.0, y - 14.0, 2.0, InkR.rgba(23, 19, 15, 102), 1.0, 0.0)
	if not emblem.is_empty():
		InkR.text(emblem, x + w * 0.5, y + h * 0.44, 28.0, InkR.F_DISPLAY, InkR.A_CENTER, InkR.rgba(240, 228, 204, 76))


static func chain(x: float, y0: float, y1: float, sway: float, alpha: float) -> void:
	var n := int(floor((y1 - y0) / 11.0))
	var pts: Array = []
	for i in range(n + 1):
		var y := y0 + float(i) * 11.0
		var xx := x + sin(float(i) * 0.35 + y0) * sway
		pts.append(Vector2(xx, y))
	InkR.poly(pts, 1.1, InkR.INK, alpha * 0.4, 0.3)
	for i in range(n + 1):
		var p: Vector2 = pts[i]
		if i % 2 == 0:
			InkR.circle(p.x, p.y, 2.8, null, InkR.INK, 1.1, alpha, 0.3, 7)
		else:
			InkR.line(p.x - 2.4, p.y - 4.0, p.x + 2.4, p.y + 4.0, 1.2, InkR.INK, alpha, 0.2)


static func draw_candle_dynamic(x: float, base_y: float, t: float, s: float) -> void:
	var flick := sin(t * 7.3 + x) * 2.0 + sin(t * 13.1 + x * 0.4) * 1.2
	InkR.radial_glow(x, base_y - 24.0 * s, 52.0 * s, Color(220.0 / 255.0, 150.0 / 255.0, 60.0 / 255.0), 0.18, x - 60.0, base_y - 90.0, 120.0, 100.0)
	InkR.srand(int(x + 5.0))
	InkR.rect(x - 5.0 * s, base_y - 26.0 * s, 10.0 * s, 26.0 * s, InkR.rgba(246, 237, 218, 217), InkR.INK, 1.4, 1.0, 0.6)
	InkR.line(x - 4.0 * s, base_y - 18.0 * s, x - 2.0 * s, base_y - 13.0 * s, 1.2, InkR.rgba(23, 19, 15, 77), 1.0, 0.2)
	InkR.blob(x + flick * 0.3, base_y - 34.0 * s, 4.4 * s, InkR.GOLD, InkR.rgba(23, 19, 15, 166), 1.0, 1.0, 0.8, 10, 0.2)
	InkR.blob(x + flick * 0.4, base_y - 33.0 * s, 2.1 * s, InkR.RED_BRIGHT, null, 2.0, 1.0, 0.5, 10, 0.25, false)
	InkR.line(x - 9.0 * s, base_y, x + 9.0 * s, base_y, 2.0, InkR.rgba(23, 19, 15, 128), 1.0, 0.0)


static func draw_grass_tuft(x: float, y: float, t: float, seed_id: int) -> void:
	InkR.srand(200 + seed_id)
	for j in range(3):
		InkR.poly([
			Vector2(x + float(j) * 4.0 - 4.0, y),
			Vector2(x + float(j) * 5.0 - 8.0 + sin(t + float(seed_id)) * 2.0, y - 7.0 - float(j) * 2.0),
		], 1.4, InkR.rgba(23, 19, 15, 102), 1.0, 0.6)


static func draw_surface(rect: Rect2, one_way: bool, bounds: Rect2, solids: Array = []) -> void:
	var tile := float(InkTileset.SIZE)
	var start := (rect.position / tile).round() * tile
	var end := (rect.end / tile).round() * tile
	var sz := end - start
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	if sz.y >= 96.0 and end.y >= bounds.end.y:
		# The historical gradient is translucent ink on paper, not solid ground.
		# Supply its original paper backing before compositing the unchanged wash.
		InkR.fill_rect_color(start.x, start.y, sz.x, sz.y, PAPER, 1.0)
		InkR.fill_rect_gradient(start.x, start.y, sz.x, sz.y, InkR.tex_floor_grad)
		InkR.line(start.x, start.y, end.x, start.y, 4.5, InkR.INK, 1.0, 0.8)
		InkR.line(start.x + 3.0, start.y + 6.0, end.x - 3.0, start.y + 6.0,
			1.4, InkR.INK, 0.25, 0.5)
		InkR.hatch([start + Vector2(0.0, 8.0), Vector2(end.x, start.y + 8.0),
			end, Vector2(start.x, end.y)], 17.0, 0.08)
		for edge in ground_side_edges(Rect2(start, sz), solids):
			InkR.line(edge[0].x, edge[0].y, edge[1].x, edge[1].y, 2.8, InkR.INK, 0.9, 0.45)
	else:
		platform(start.x, start.y, sz.x, sz.y, one_way)


## Outline only exposed faces, never the hidden seam inside adjacent ground.
static func ground_side_edges(rect: Rect2, solids: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var tile := float(InkTileset.SIZE)
	for side in [-1, 1]:
		var x := rect.position.x if side == -1 else rect.end.x
		var intervals: Array[Vector2] = [Vector2(rect.position.y, rect.end.y)]
		for spec in solids:
			var other := _rect_of(spec)
			var start := (other.position / tile).round() * tile
			var end := (other.end / tile).round() * tile
			other = Rect2(start, end - start)
			if other == rect:
				continue
			var covers := other.position.x < x - 0.1 and other.end.x >= x - 0.1 if side == -1 else other.position.x <= x + 0.1 and other.end.x > x + 0.1
			if not covers:
				continue
			var remaining: Array[Vector2] = []
			for interval in intervals:
				if other.position.y >= interval.y or other.end.y <= interval.x:
					remaining.append(interval)
					continue
				if other.position.y > interval.x:
					remaining.append(Vector2(interval.x, other.position.y))
				if other.end.y < interval.y:
					remaining.append(Vector2(other.end.y, interval.y))
			intervals = remaining
		for interval in intervals:
			if interval.y > interval.x:
				result.append(PackedVector2Array([Vector2(x, interval.x), Vector2(x, interval.y)]))
	return result


static func platform(x: float, y: float, w: float, h: float, one_way: bool) -> void:
	InkR.srand(int(x + y * 3.0))
	InkR.rect(x, y, w, h,
		Color("#eee2c9") if one_way else Color("#e2d3b2"),
		InkR.INK, 2.4, 1.0, 0.8)
	InkR.line(x + 3.0, y + 2.0, x + w - 3.0, y + 2.0, 1.6, InkR.rgba(250, 244, 228, 166), 1.0, 0.8)
	InkR.hatch([
		Vector2(x + 2.0, y + h - 2.0), Vector2(x + w - 2.0, y + h - 2.0),
		Vector2(x + w - 2.0, y + h + 18.0), Vector2(x + 2.0, y + h + 18.0),
	], 7.0, 0.16)

	if one_way:
		InkR.line(x + 3.0, y + h + 4.0, x + w - 3.0, y + h + 4.0, 1.0, InkR.rgba(23, 19, 15, 64), 1.0, 0.0, [5.0, 7.0])
		chain(x + 22.0, y - 44.0, y, 0.0, 0.25)
		chain(x + w - 26.0, y - 52.0, y, 0.0, 0.22)
	else:
		InkR.line(x + 10.0, y + h + 7.0, x + 8.0, y + h + 20.0, 1.2, InkR.rgba(23, 19, 15, 51), 1.0, 0.4)
		InkR.line(x + w - 12.0, y + h + 7.0, x + w - 10.0, y + h + 20.0, 1.2, InkR.rgba(23, 19, 15, 51), 1.0, 0.4)
		InkR.poly([
			Vector2(x + w * 0.3, y + h), Vector2(x + w * 0.4, y + h + 12.0), Vector2(x + w * 0.52, y + h),
		], 1.0, InkR.rgba(23, 19, 15, 41), 1.0, 0.0)

static func banner_polygon(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h * 0.82),
		Vector2(x + w * 0.82, y + h), Vector2(x + w * 0.6, y + h * 0.86),
		Vector2(x + w * 0.42, y + h), Vector2(x + w * 0.22, y + h * 0.88), Vector2(x, y + h * 0.84)])
