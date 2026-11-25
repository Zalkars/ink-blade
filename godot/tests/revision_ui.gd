extends Node

const Hud := preload("res://scripts/ui/hud.gd")
const Guide := preload("res://scenes/ui/control_guide.tscn")
var failures := 0
var dismissed_count := 0

class InkAtlas extends Control:
	func _draw() -> void:
		for phase in 32:
			for step in 100:
				draw_set_transform(Vector2(step * 44, phase * 44))
				var fill := float(step) / 99.0
				var points := Hud.ink_bar_points(fill, float(phase) * TAU / 96.0, 2.0, 2.0, 40.0, 40.0)
				if points.size() >= 3:
					draw_colored_polygon(PackedVector2Array(points), Color.BLACK)

class Gauge extends "res://scripts/ui/hud.gd":
	func _draw() -> void:
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(_t)
		_draw_ink_gauge()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func rendered(viewport: SubViewport) -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var staged = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/revision-ui-strings.json"))
	for language in staged:
		L10N._strings[language].merge(staged[language], true)
	var output := "res://../builds/revision-ui/"
	DirAccess.make_dir_recursive_absolute(output)
	if DisplayServer.get_name() == "headless":
		push_error("Run this regression with a rendering display")
		get_tree().quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(4400, 1408)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var atlas := InkAtlas.new()
	viewport.add_child(atlas)
	var pixels: Image = await rendered(viewport)
	pixels.save_png(output + "ink-bar-all-levels-32-phases.png")
	var missing := 0
	var decreases := 0
	for phase in 32:
		var previous := 0
		for step in 100:
			var count := 0
			for y in 44:
				for x in 44:
					if pixels.get_pixel(step * 44 + x, phase * 44 + y).r < 0.1:
						count += 1
			if (step == 0 and count != 0) or (step >= 5 and count == 0):
				missing += 1
			if count < previous:
				decreases += 1
			previous = count
	check(missing == 0, "rendered ink bar present from 5%%, empty at 0, all 32 phases (%d missing)" % missing)
	check(decreases == 0, "rendered ink fill area monotonic at every phase (%d decreases)" % decreases)
	viewport.queue_free()
	await get_tree().process_frame
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1200, 1920)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sheet)
	var values := [0, 1, 24, 25, 49, 50, 75, 99, 100]
	var players: Array[Player] = []
	for row in 16:
		for column in values.size():
			var sample := Gauge.new()
			var p := Player.new()
			p.ink = values[column]
			players.append(p)
			sample.player = p
			sample._ink_shown = p.ink
			sample._ink_before = p.ink
			sample.position = Vector2(column * 132 + 4, row * 120 + 4)
			sample._t = float(row) * TAU / 48.0
			sheet.add_child(sample)
			sample.set_process(false)
	var shot: Image = await rendered(sheet)
	shot.save_png(output + "ink-gauge-contact-sheet.png")
	var ink_unchanged := true
	for i in players.size():
		ink_unchanged = ink_unchanged and players[i].ink == values[i % values.size()]
	check(ink_unchanged, "144 ink gauge renders preserve actual ink")
	sheet.queue_free()
	await get_tree().process_frame
	for p in players:
		p.free()
	var guide = Guide.instantiate()
	add_child(guide)
	guide.dismissed.connect(func(): dismissed_count += 1)
	guide.open()
	guide.dismiss()
	check(guide.visible and dismissed_count == 0, "opening input guard prevents accidental dismissal")
	await get_tree().create_timer(0.4).timeout
	var old_key = CTL.keyboard["jump"].duplicate()
	CTL.keyboard["jump"] = [KEY_Z]
	check(guide.binding("jump") == "Z", "guide reflects current keyboard binding")
	CTL.keyboard["jump"] = old_key
	for device in ["keyboard", "gamepad", "touch"]:
		CTL.device = device
		guide.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + "guide-" + device + ".png")
	check(not guide.binding("heal").is_empty(), "touch guide contains healing control")
	guide.dismiss()
	guide.dismiss()
	check(not guide.visible and dismissed_count == 1, "dismiss emits exactly once")
	var overlay = preload("res://scenes/ui/overlay.tscn").instantiate()
	add_child(overlay)
	var actions: Array[String] = []
	overlay.chosen.connect(func(action: String): actions.append(action))
	overlay.open(overlay.Mode.PAUSE, "test")
	overlay.activate(overlay.actions.find("restart"))
	check(overlay._confirm_restart and overlay.selected == 0 and actions.is_empty(), "restart opens confirmation with cancel selected")
	overlay.activate(1)
	check(actions.is_empty(), "opening input cannot confirm restart")
	check(overlay.handle_back() and not overlay._confirm_restart and overlay.sub == "test", "Back restores pause menu")
	overlay.request_restart()
	overlay.input_guard = 0
	overlay.activate(0)
	check(not overlay._confirm_restart and actions.is_empty(), "cancel restart preserves session")
	overlay.request_restart()
	overlay.input_guard = 0
	overlay.activate(1)
	check(actions == ["confirm_restart"], "explicit confirm emits separate restart action")
	overlay.open(overlay.Mode.PAUSE)
	overlay.request_restart()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "restart-confirm.png")
	overlay.queue_free()
	guide.queue_free()
	await get_tree().process_frame
	print("REVISION_UI_RESULT=%s" % ("OK" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures else 0)
