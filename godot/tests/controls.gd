extends Node

var failures := 0
var checks := 0
var flow: Node
var settings: Control
var config_existed := false
var config_bytes := PackedByteArray()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + text)

func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../builds/controls-review")
	get_viewport().get_texture().get_image().save_png("res://../builds/controls-review/" + name + ".png")

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config_existed = FileAccess.file_exists("user://settings.cfg")
	if config_existed:
		config_bytes = FileAccess.get_file_as_bytes("user://settings.cfg")
	get_window().size = Vector2i(1280, 720)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames()
	settings = flow.settings
	CTL.reset_bindings()
	CTL.touch_layout.clear()
	CTL.touch_layout_legacy = false
	CTL.touch_style = "floating"
	flow.open_settings()
	await frames()
	check(settings.visible and not flow.title_screen.visible, "settings open from title")
	await shot("keyboard")
	settings.pages.current_tab = 3
	for child in settings.pages.get_child(3).find_children("*", "OptionButton", true, false):
		var rate := child as OptionButton
		if rate.item_count != 2 or rate.get_item_id(1) != 120:
			continue
		rate.select(1)
		rate.item_selected.emit(1)
		check(Engine.max_fps == 120 and Engine.physics_ticks_per_second == 120,
			"120 Hz option changes the frame limit and preserves the physics tick")
		flow.frame_rate = 60
		flow.load_preferences()
		check(flow.frame_rate == 120, "frame rate survives preferences reload")
		settings._reset_page()
		check(Engine.max_fps == 60, "reset selects the 60 Hz frame limit")
		break
	settings.pages.current_tab = 0
	settings._capture("attack", false)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	settings._input(mouse)
	check(CTL.keyboard.attack == [-2] and settings.capture.is_empty(), "mouse button captured")
	settings._capture("jump", false)
	settings._input(key(KEY_K))
	check(CTL.keyboard.jump == [KEY_K] and not CTL.keyboard.dash.has(KEY_K) and not CTL.keyboard.dash.is_empty(), "conflict reassigned without losing dash")
	settings._capture("heal", false)
	settings._input(key(KEY_ESCAPE))
	check(settings.capture.is_empty() and CTL.keyboard.heal == CTL.DEFAULT_KEYBOARD.heal, "Escape cancels capture")
	settings.pages.current_tab = 1
	settings._capture("attack", true)
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 0.9
	settings._input(trigger)
	check(CTL.pad_map.attack == [6], "controller trigger captured")
	check(not CTL.set_pad("attack", 14), "movement D-pad protected from combat bindings")
	CTL.pad_movement = "dpad"
	CTL.pad_deadzone = 0.22
	settings._save()
	CTL.pad_movement = "both"
	CTL.pad_deadzone = 0.5
	CTL.reset_bindings()
	CTL.load_controls()
	check(CTL.keyboard.attack == [-2] and CTL.pad_map.attack == [6] and CTL.pad_movement == "dpad" and is_equal_approx(CTL.pad_deadzone, 0.22), "bindings and controller settings survive reload")
	await shot("controller")
	settings.pages.current_tab = 2
	var old_config := ConfigFile.new()
	old_config.load("user://settings.cfg")
	old_config.erase_section_key("controls", "layout_legacy")
	old_config.set_value("controls", "layout", {"move": {"center": Vector2(0.14, 0.76), "scale": 0.75}})
	old_config.save("user://settings.cfg")
	CTL.load_controls()
	check(CTL.touch_layout_legacy and is_equal_approx(flow.mobile_controls.element_radius("move"), 63.0)
		and is_equal_approx(flow.mobile_controls.element_radius("jump"), 64.0),
		"old layouts retain both customized and default button sizes")
	settings._reset_page()
	check(not CTL.touch_layout_legacy and CTL.touch_layout.is_empty()
		and is_equal_approx(flow.mobile_controls.element_radius("jump"), 84.0),
		"touch reset restores the new standard layout")
	await frames()
	await shot("touch")
	settings.start_editor()
	await frames()
	var mobile: Control = flow.mobile_controls
	check(mobile.editing and mobile.visible, "layout preview works on desktop")
	await shot("editor")
	var press := InputEventScreenTouch.new()
	press.index = 4
	press.pressed = true
	press.position = mobile.buttons().jump
	mobile._edit_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.position = press.position + Vector2(-70, -15)
	mobile._edit_input(drag)
	check(CTL.touch_layout.has("jump") and mobile.selected_element == "jump", "drag stores normalized per-control position")
	mobile.resize_selected(1.3)
	check(is_equal_approx(mobile.element_scale("jump"), 1.3), "individual control size")
	settings.finish_editor(false)
	check(CTL.touch_layout.is_empty() and not mobile.editing and settings.visible, "cancel restores original layout")
	settings.start_editor()
	mobile.selected_element = "move"
	mobile.resize_selected(0.9)
	settings.finish_editor(true)
	check(not mobile.editing, "non-overlapping layout saves")
	CTL.touch_layout.clear()
	CTL.load_controls()
	check(is_equal_approx(mobile.element_scale("move"), 0.9), "layout size persists")
	settings.go_back()
	check(flow.title_screen.visible and not settings.visible, "Back restores title")
	flow.start_run()
	CTL.mouse_gameplay_enabled = true
	Input.parse_input_event(mouse.duplicate())
	Input.flush_buffered_events()
	CTL.update(0.016)
	check(CTL.down("attack"), "assigned mouse button drives gameplay input")
	mouse.pressed = false
	Input.parse_input_event(mouse.duplicate())
	Input.flush_buffered_events()
	CTL.update(0.016)
	check(not CTL.down("attack"), "mouse release clears action")
	flow._pause()
	flow.open_settings()
	settings.go_back()
	check(flow.state == flow.State.PAUSE and flow.overlay.visible and get_tree().paused, "settings return to paused game")
	# Test fixed D-pad diagonals and neutral/release independent from rendering.
	CTL.touch_style = "dpad"
	mobile.stick_center = mobile.home_center()
	CTL.stick_start()
	mobile._move_stick(mobile.stick_center + Vector2(60, -60))
	check(CTL.stick_x == 1 and CTL.stick_y == -1, "touch D-pad supports diagonals")
	mobile.reset()
	check(not CTL.stick_on and CTL.stick_x == 0, "D-pad release clears movement")
	flow._show_title()
	flow.queue_free()
	await frames()
	if config_existed:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(config_bytes)
		file.close()
	else:
		DirAccess.remove_absolute("user://settings.cfg")
	print("CONTROLS_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
