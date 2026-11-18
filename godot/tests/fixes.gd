extends Node
var failures := 0
var checks := 0
var flow: Node
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + label)
func frames(n := 3) -> void:
	for i in n: await get_tree().physics_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	InkFx.update(0.035)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../builds/fix-review")
	get_viewport().get_texture().get_image().save_png("res://../builds/fix-review/" + name + ".png")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var existed := FileAccess.file_exists("user://settings.cfg")
	var backup := FileAccess.get_file_as_bytes("user://settings.cfg") if existed else PackedByteArray()
	get_window().size = Vector2i(1600,720)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames()
	flow.start_run()
	flow.set_physics_process(false)
	var p: Player = flow.player
	p.set_physics_process(false)
	for enemy in flow.level.enemies:
		if is_instance_valid(enemy): enemy.set_physics_process(false)
	CTL.reset_bindings()
	CTL.touch_enabled = true
	CTL.mouse_gameplay_enabled = true
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.device = -1
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	CTL.update(0.01)
	check(not CTL.down("attack"), "emulated mouse from arbitrary touch cannot attack")
	mouse = mouse.duplicate()
	mouse.device = 0
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	CTL.update(0.01)
	check(CTL.down("attack"), "genuine mouse still attacks alongside touch controls")
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	CTL.update(0.01)
	CTL.touch_enter("jump")
	CTL.update(0.01)
	check(CTL.down("jump") and not CTL.down("attack"), "jump does not attack")
	CTL.stick_start()
	CTL.stick_move(1,0)
	CTL.update(0.01)
	check(CTL.axis_x() > 0.9 and not CTL.down("attack"), "stick does not attack")
	CTL.touch_tap("attack")
	CTL.update(0.01)
	check(CTL.pressed("attack"), "explicit touch attack remains available")
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	CTL.clear_touch()
	for action in CTL.ACTIONS: CTL.edge[action] = false
	CTL.touch_enabled = false
	p.position = Vector2(800,450)
	var above := preload("res://scenes/actors/grunt.tscn").instantiate() as Grunt
	above.position = p.position + Vector2(0,-65)
	flow.level.add_child(above)
	above.set_physics_process(false)
	var side := preload("res://scenes/actors/grunt.tscn").instantiate() as Grunt
	side.position = p.position + Vector2(45,0)
	flow.level.add_child(side)
	side.set_physics_process(false)
	await frames()
	CTL.move_y = -1
	p.attack_cd = 0
	p._try_attack()
	p._physics_process(0.06)
	check(p.attack_dir == "up" and above.hp < above.max_hp and side.hp == side.max_hp, "upward input hits above instead of sideways")
	check(not InkFx.slashes.is_empty() and InkFx.slashes.back().r >= 57 and InkFx.slashes.back().w0 == 20, "original broad slash geometry and independent lifetime")
	var hp_after := above.hp
	p._strike()
	check(above.hp == hp_after, "active attack hits an enemy only once")
	await shot("up-attack")
	p.attack_cd = 0
	CTL.move_y = 0
	p._try_attack()
	await frames(8)
	await shot("forward-attack")
	InkFx.reset()
	p.iframes = 0
	p.take_damage(1,-1)
	check(InkFx.damage > 0 and InkFx.flash > 0 and not InkFx.texts.is_empty(), "damage restores number, flash and vignette")
	await shot("damage")
	InkFx.reset()
	p.respawn()
	check(InkFx.parts.size() >= 26 and not InkFx.rings.is_empty(), "respawn emits smoke and ring")
	await shot("respawn")
	flow.shake_enabled = false
	flow.master_volume = 0.36
	CTL.vibration_enabled = false
	SND.set_muted(true)
	flow.vsync_enabled = false
	flow.save_preferences()
	flow.master_volume = 1
	flow.shake_enabled = true
	flow.load_preferences()
	check(not flow.shake_enabled and is_equal_approx(flow.master_volume,0.36) and not CTL.vibration_enabled and SND.muted and not flow.vsync_enabled, "general settings persist and reload")
	flow.open_settings()
	flow.settings.pages.current_tab = 3
	await frames()
	check(flow.settings.pages.get_tab_count() == 4, "general settings tab exists")
	await shot("general")
	flow.settings.go_back()
	var spec: Dictionary = flow.level.data.one_ways[0]
	var r: Rect2 = flow.level._rect_of(spec)
	var tile := float(InkTileset.SIZE)
	r = Rect2((r.position / tile).round()*tile,(r.end/tile).round()*tile-(r.position/tile).round()*tile)
	CombatFx.surface(p, flow.level.to_global(Vector2(r.end.x-2,r.position.y)), Vector2.UP)
	var fx := flow.level.get_node("CombatInk") as CombatFx
	var inside := true
	var fragments: Array = fx.marks.back().fragments
	for poly in fragments:
		for vertex in poly:
			if not r.grow(0.01).has_point(flow.level.to_local(fx.to_global(vertex))): inside = false
	check(not fragments.is_empty() and inside, "ink at platform corner stays inside terrain")
	p.position = Vector2(r.end.x - 40,r.position.y-24)
	flow.camera.global_position = p.position - Vector2(0,100)
	flow.camera.reset_smoothing()
	var bolt := InkBolt.new()
	bolt.position = p.position + Vector2(120, -60)
	bolt.velocity = Vector2(-140,0)
	flow.level.add_child(bolt)
	await frames(8)
	await shot("terrain-ink")
	for action in CTL.ACTIONS: CTL.edge[action] = false
	flow.play_cutscene("intro")
	flow.cutscene.offset_left = 64
	await frames()
	await shot("cutscene-safe-area")
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		check(img.get_pixel(8,img.get_height()-15).is_equal_approx(Color("#f1e6d0")), "cutscene background covers left safe-area margin")
	flow.cutscene.close()
	get_tree().paused = false
	p.hp = 1
	p.iframes = 0
	p.take_damage(1,-1)
	var time_at_death := InkFx.t
	await frames(5)
	check(flow.state == flow.State.DEAD and InkFx.t > time_at_death, "death particles continue while world is paused")
	flow._show_title()
	flow.queue_free()
	await frames()
	if existed:
		var f := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else: DirAccess.remove_absolute("user://settings.cfg")
	print("FIXES_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL",checks])
	get_tree().quit(0 if failures == 0 else 1)
