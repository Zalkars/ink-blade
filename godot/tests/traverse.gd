extends Node

## Real CharacterBody2D traversal against production TileMap collision.
## -- --capture renders four zones; default checks walking/jumping and dash-only attempts.
var level: Level
var p: Player
var failures: Array[String] = []

func _ready() -> void:
	level = preload("res://scenes/level/ch01_hall.tscn").instantiate()
	add_child(level)
	p = preload("res://scenes/actors/player.tscn").instantiate()
	p.position = level.spawn_point
	level.add_child(p)
	level.bind_player(p)
	await get_tree().physics_frame
	_check_placements()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture()
		return
	for e in level.enemies:
		e.queue_free()
	level.enemies.clear()
	# Each checkpoint must resume into an independently traversable route.
	for cp in level.data.checkpoints:
		await _reset(Vector2(cp.x, cp.y - 23.0))
		var reached := await _run(13900.0, 4200, true, false)
		_check(reached >= 13900.0, "ordinary jumps from %s reached %.0f" % [cp.id, reached])
	# Repeated horizontal dash cannot scale the rises, even when restarting at later zones.
	for attempt in [[128.0, 576.0, 2560.0], [3840.0, 640.0, 7040.0], [7104.0, 576.0, 11264.0]]:
		await _reset(Vector2(attempt[0], attempt[1] - 23.0))
		var reached := await _run(attempt[2], 600, false, true)
		_check(reached < attempt[2], "dash-only from %.0f stopped at %.0f before %.0f" % [attempt[0], reached, attempt[2]])
	CTL.stick_on = false
	CTL.stick_x = 0.0
	CTL.update(1.0 / 60.0)
	print("TRAVERSE_RESULT=" + ("OK" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func _reset(pos: Vector2) -> void:
	CTL.stick_on = false
	CTL.stick_x = 0.0
	CTL.update(1.0 / 60.0)
	p.global_position = pos
	p.velocity = Vector2.ZERO
	p.dash_t = 0.0
	p.dash_buf = 0.0
	p.dash_cd = 0.0
	p.jump_buf = 0.0
	for i in 4:
		await get_tree().physics_frame

func _run(target: float, steps: int, jump: bool, dash: bool) -> float:
	var farthest := p.global_position.x
	var jumps := 0
	var min_feet := p.position.y + 23.0
	for i in steps:
		CTL.stick_on = true
		CTL.stick_x = 1.0
		CTL.update(1.0 / 60.0)
		if jump and p.is_on_floor():
			p.jump_buf = p.JUMP_BUFFER
			jumps += 1
		if dash:
			p.dash_buf = p.INPUT_BUFFER
		await get_tree().physics_frame
		farthest = maxf(farthest, p.global_position.x)
		min_feet = minf(min_feet, p.position.y + 23.0)
		if p.position.y > 740.0:
			_check(false, "fell below level at " + str(p.position))
			break
		if farthest >= target:
			break
	print("ROUTE x=%.0f jumps=%d highest_feet=%.0f dash=%s" % [farthest, jumps, min_feet, dash])
	return farthest

func _check(ok: bool, message: String) -> void:
	if not message.begins_with("clearance") or not ok:
		print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)

func _check_placements() -> void:
	var objects: Array = level.data.placements + level.data.checkpoints + level.data.triggers + [level.data.spawn]
	for spec in objects:
		var body := Rect2(float(spec.x) - 14.0, float(spec.y) - 42.0, 28.0, 41.0)
		var supported := false
		for solid in level.data.solids + level.data.one_ways:
			var r := level._rect_of(solid)
			if r.position.y == float(spec.y) and float(spec.x) >= r.position.x + 14.0 and float(spec.x) <= r.end.x - 14.0:
				supported = true
		for solid in level.data.solids:
			_check(not body.intersects(level._rect_of(solid)), "clearance %s / %.0f" % [spec.get("id", "spawn"), float(solid.x)])
		_check(supported, "support " + str(spec.get("id", "spawn")))
	_check(level.data.placements.size() == 30, "30 stable enemy placements")
	for i in 30:
		_check(level.data.placements[i].id == "e%d" % (i + 1), "stable e%d" % (i + 1))

func _capture() -> void:
	var output := ProjectSettings.globalize_path("res://../builds/revision-level/captures")
	DirAccess.make_dir_recursive_absolute(output)
	var cam := Camera2D.new()
	add_child(cam)
	cam.position = Vector2(640, 360)
	cam.make_current()
	p.set_physics_process(false)
	for e in level.enemies:
		e.set_physics_process(false)
	for shot in [["threshold", 800.0, 480.0], ["archive", 4220.0, 640.0], ["gallery", 8700.0, 448.0], ["sanctum", 13300.0, 576.0]]:
		p.position = Vector2(shot[1], shot[2] - 23.0)
		cam.position.x = shot[1]
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join(shot[0] + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE " + path)
	get_tree().quit(0 if failures.is_empty() else 1)
