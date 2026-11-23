extends Node

var failures := 0
var checks := 0
var flow: Node
var mobile: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 3) -> void:
	for i in count:
		await get_tree().physics_frame

func touch(id: int, pos: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	get_viewport().push_input(event, true)

func tap(pos: Vector2) -> void:
	touch(9, pos, true)
	touch(9, pos, false)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := "res://../builds/mobile-review"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames()
	mobile = flow.mobile_controls
	check(CTL.touch_enabled, "touch mode enabled")
	await shot("title")
	# Dragging a menu row away must not start a new run.
	var play_point: Vector2 = flow.title_screen.item_rect(0).get_center() + flow.title_screen.position
	touch(0, play_point, true)
	touch(0, play_point + Vector2(200, 0), false)
	check(flow.state == flow.State.TITLE, "menu drag canceled")
	tap(play_point)
	check(flow.state == flow.State.CUTSCENE, "tap Play opens intro")
	await frames()
	var index: int = flow.cutscene.index
	tap(Vector2(600, 500))
	check(flow.cutscene.index == index + 1, "tap advances intro")
	while flow.cutscene.visible:
		flow.cutscene.advance()
	check(flow.state == flow.State.GUIDE and flow.level != null and flow.player != null and flow.hud.visible,
		"guide opens over loaded game with HUD after intro")
	await frames(45)
	tap(flow.control_guide._button.get_global_rect().get_center())
	check(flow.control_guide.visible and flow.control_guide.step == 1, "guide Next shows actual jump control without restarting game")
	await frames(30)
	tap(flow.control_guide._skip.get_global_rect().get_center())
	check(flow.state == flow.State.PLAY and not flow.control_guide.visible, "guide Skip enters same game")
	await frames()
	flow.player.iframes = 9999.0
	await frames(80)
	await shot("play-16x9")
	# Multi-touch: stick + jump + attack held at once.
	var center: Vector2 = mobile.home_center()
	touch(0, center, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(84, 0)
	get_viewport().push_input(drag, true)
	touch(1, mobile.buttons().jump, true)
	touch(2, mobile.buttons().attack, true)
	var x0: float = flow.player.position.x
	var y0: float = flow.player.position.y
	await frames(12)
	check(flow.player.position.x > x0 + 1 and CTL.axis_x() > 0.9, "stick moves player with two action fingers")
	check(flow.player.position.y < y0 - 20, "jump works while moving and attacking")
	check(CTL.down("attack"), "attack held")
	touch(1, mobile.buttons().jump, false)
	await frames()
	check(not CTL.down("jump") and CTL.down("attack"), "releasing jump preserves attack")
	touch(2, mobile.buttons().attack, false, true)
	await frames()
	check(not CTL.down("attack"), "canceled touch releases attack")
	tap(mobile.buttons().pause)
	check(flow.state == flow.State.PAUSE and not CTL.stick_on and CTL.touch_down.is_empty(), "pause clears all touches")
	await frames()
	await shot("pause")
	tap(flow.overlay.position + flow.overlay.item_rect(0).get_center())
	check(flow.state == flow.State.PLAY, "tap resumes")
	await frames()
	touch(0, center, true)
	flow._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(flow.state == flow.State.PAUSE and not CTL.stick_on, "focus loss pauses and clears stick")
	flow._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	check(flow.state == flow.State.PLAY, "Android Back resumes pause")
	await frames()
	flow.player.iframes = 0
	flow.player.take_damage(999, 1.0)
	await frames()
	check(flow.state == flow.State.DEAD, "death overlay")
	tap(flow.overlay.position + flow.overlay.item_rect(0).get_center())
	check(flow.state == flow.State.DEAD, "death reveal blocks accidental touch")
	await frames(int(ceil(Engine.physics_ticks_per_second * 1.1)))
	tap(flow.overlay.position + flow.overlay.item_rect(0).get_center())
	check(flow.state == flow.State.PLAY, "tap checkpoint respawns")
	await frames()
	flow.play_dialogue("archivist")
	await frames()
	tap(Vector2(600, 500))
	check(flow.dialogue.index == 1, "tap advances dialogue")
	while flow.dialogue.visible:
		flow.dialogue.advance()
	await frames()
	flow.player.global_position = flow.level.spawn_point
	flow.player.velocity = Vector2.ZERO
	flow.player.iframes = 9999.0
	flow.player.hp = 3
	flow.player.soul = 66.0
	await frames(90)
	touch(3, mobile.buttons().heal, true)
	await frames(120)
	check(flow.player.hp > 3 and flow.player.soul < 66.0, "holding Y heals using soul")
	touch(3, mobile.buttons().heal, false)
	await frames()
	get_window().size = Vector2i(1600, 720)
	await frames(4)
	check(mobile.safe.size.x > 1280, "wide display expands canvas without stretching")
	for a in mobile.buttons():
		check(mobile.safe.encloses(Rect2(mobile.buttons()[a] - Vector2(58, 58), Vector2(116, 116))), "wide safe button " + a)
	await shot("play-wide")
	print("MOBILE_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
