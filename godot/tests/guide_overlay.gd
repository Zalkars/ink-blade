extends Node

var flow
var guide
var checks := 0
var failures := 0
var capture := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 42) -> void:
	for i in count:
		await get_tree().physics_frame

func touch(id: int, point: Vector2, held: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = held
	event.canceled = canceled
	get_viewport().push_input(event, true)

func tap(point: Vector2) -> void:
	touch(1, point, true)
	touch(1, point, false)

func button_center(button: Button) -> Vector2:
	return button.get_global_transform_with_canvas() * button.size * 0.5

func shot(label: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../builds/guide-overlay-review")
	get_viewport().get_texture().get_image().save_png("res://../builds/guide-overlay-review/" + label + ".png")
	print("SHOT ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture = "--capture" in OS.get_cmdline_user_args()
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames(4)
	flow.start_new_story()
	while flow.cutscene.visible:
		flow.cutscene.advance()
	await frames(40)
	guide = flow.control_guide
	var original_level = flow.level
	var original_player = flow.player
	var original_position: Vector2 = flow.player.position
	var original_weapons: Array = flow.player.weapon_ids()
	check(guide.visible and flow.state == flow.State.GUIDE and flow.hud.visible and get_tree().paused, "guide overlays paused real gameplay with visible HUD")
	check(is_equal_approx(flow.player._visual.cx(), flow.player.global_position.x) and is_equal_approx(flow.player._visual.y + 23.0, flow.player.global_position.y), "paused guide draws the hero at actual spawn rather than world origin")
	check(guide.binding("jump") == CTL.label_key("jump"), "keyboard text uses actual assignments")
	await shot("keyboard-move")
	CTL.touch_enabled = true
	CTL.device = "touch"
	flow.mobile_controls.visible = true
	flow.mobile_controls.set_process(true)
	flow.mobile_controls.set_process_input(true)
	flow.mobile_controls._layout()
	await frames()
	check(guide.binding("jump") == "A", "touch binding is actual button glyph rather than action name")
	check(guide.target_center().is_equal_approx(flow.mobile_controls.home_center()), "movement highlights actual joystick home")
	await shot("touch-move")
	tap(guide.target_center())
	await frames()
	check(guide.step == 1, "real highlighted movement control advances guide")
	check(not CTL.stick_on and CTL.touch_down.is_empty(), "guide touch cannot move player")
	var next := button_center(guide._button)
	touch(1, next, true)
	touch(2, button_center(guide._skip), true)
	touch(2, button_center(guide._skip), false)
	check(guide.visible and guide.step == 1, "second finger cannot skip or advance guide")
	touch(1, next + Vector2(80, 80), false)
	check(guide.step == 1, "dragging off Next cancels advance")
	touch(1, next, true)
	touch(1, next, false, true)
	check(guide.step == 1, "canceled touch does not advance")
	get_window().size = Vector2i(1560, 720)
	CTL.touch_layout["jump"] = {"center": Vector2(0.29, 0.60), "scale": 1.2}
	flow.mobile_controls._layout()
	await frames()
	var actual_jump: Vector2 = flow.mobile_controls.buttons().jump
	check(guide.target_center().is_equal_approx(actual_jump) and is_equal_approx(guide.target_radius(), flow.mobile_controls.element_radius("jump") + 12), "highlight follows saved custom position and size after wide resize")
	await shot("touch-jump-custom-wide")
	tap(actual_jump)
	await frames()
	check(guide.step == 2 and flow.player.attack_t == 0, "jump tutorial tap advances without gameplay input")
	await shot("touch-attack-wide")
	tap(guide.target_center())
	await frames()
	check(guide.step == 3 and flow.player.attack_t == 0 and CTL.touch_down.is_empty(), "attack tutorial tap does not attack or leave held input")
	for expected_step in [4, 5, 6]:
		tap(guide.target_center())
		await frames()
		check(guide.step == expected_step, "real control advances to step %d" % expected_step)
		await shot("touch-step-%d-wide" % expected_step)
	check(flow.player.weapon_ids() == original_weapons and flow.player.ink == 0, "teaching locked swap and heal does not grant weapons or resource")
	check(flow.player.position == original_position, "player remains at original position throughout tutorial")
	tap(guide.target_center())
	check(not guide.visible and flow.state == flow.State.PLAY and not get_tree().paused, "last real pause button starts gameplay")
	check(flow.level == original_level and flow.player == original_player, "dismissal resumes original world and player without reload")
	print("GUIDE_OVERLAY_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
