extends Node

var flow
var checks := 0
var failures := 0
var render := false
var out := "res://../builds/button-states-review/"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 8) -> void:
	for i in count:
		await get_tree().physics_frame

func center(button: Control) -> Vector2:
	return button.get_global_transform_with_canvas() * (button.size * 0.5)

func pointer(button: BaseButton, down: bool, touch := false) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 11
		event.position = center(button)
		event.pressed = down
		get_viewport().push_input(event, true)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = center(button)
		get_viewport().push_input(motion, true)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center(button)
		event.pressed = down
		get_viewport().push_input(event, true)

func screenshot(label: String) -> Image:
	if not render:
		return null
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out)
	image.save_png(out + label + ".png")
	return image

func readable_pressed(button: BaseButton, image: Image, label: String) -> void:
	if image == null:
		return
	var origin := button.get_global_transform_with_canvas() * Vector2(9, 9)
	var finish := button.get_global_transform_with_canvas() * (button.size - Vector2(9, 9))
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	origin *= scale
	finish *= scale
	var red := 0
	var paper := 0
	var total := 0
	for y in range(maxi(0, int(origin.y)), mini(image.get_height(), int(finish.y))):
		for x in range(maxi(0, int(origin.x)), mini(image.get_width(), int(finish.x))):
			var c := image.get_pixel(x, y)
			total += 1
			if c.r > 0.4 and c.r > c.g * 1.7 and c.r > c.b * 1.5:
				red += 1
			if c.r > 0.75 and c.g > 0.68 and c.b > 0.55:
				paper += 1
	check(total > 0 and red > total * 0.5 and paper > 40, label + " has real light glyph pixels on red pressed background")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	render = DisplayServer.get_name() != "headless"
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames()
	flow.start_new_story()
	while flow.cutscene.visible:
		flow.cutscene.advance()
	await frames(50)
	var guide = flow.control_guide
	guide._button.grab_focus()
	pointer(guide._button, true)
	await frames()
	readable_pressed(guide._button, await screenshot("guide-desktop-held-focused"), "desktop guide")
	pointer(guide._button, false)
	await frames(35)
	CTL.touch_enabled = true
	CTL.device = "touch"
	flow.mobile_controls.visible = true
	flow.mobile_controls.set_process(true)
	flow.mobile_controls.set_process_input(true)
	flow.mobile_controls._layout()
	for dimensions in [Vector2i(1280,720), Vector2i(1560,720), Vector2i(1600,720), Vector2i(960,540)]:
		get_window().size = dimensions
		await frames()
		flow.mobile_controls._layout()
		await frames()
		var bounds := Rect2(Vector2.ZERO, guide.size)
		check(guide._button.size.y >= 72 and guide._button.size.x >= 300, "phone guide broad finger targets %d" % dimensions.x)
		check(bounds.encloses(guide._button.get_rect()) and bounds.encloses(guide._skip.get_rect()), "phone guide footer stays inside safe canvas %d" % dimensions.x)
		guide._button.grab_focus()
		pointer(guide._button, true, true)
		await frames()
		readable_pressed(guide._button, await screenshot("guide-phone-held-%d" % dimensions.x), "phone guide %d" % dimensions.x)
		# Cancel instead of activating so each aspect checks the same step.
		var cancel := InputEventScreenTouch.new()
		cancel.index = 11
		cancel.position = center(guide._button)
		cancel.pressed = false
		cancel.canceled = true
		get_viewport().push_input(cancel, true)
		await frames()
	guide.dismiss()
	flow._pause()
	flow.open_settings()
	await frames()
	var settings = flow.settings
	for kind in ["Button", "OptionButton", "CheckButton"]:
		check(not (settings.theme.get_stylebox("focus", kind) as StyleBoxFlat).draw_center, kind + " focus draws only border")
	for dimensions in [Vector2i(1280,720), Vector2i(1560,720), Vector2i(1600,720), Vector2i(960,540)]:
		get_window().size = dimensions
		await frames()
		var button: Button = settings.binding_buttons.key_left
		check(button.size.y >= 72 and button.size.x >= 320, "phone settings assignment has finger target %d" % dimensions.x)
		check(settings.panel.get_rect().end.x <= settings.size.x and settings.panel.get_rect().end.y <= settings.size.y, "settings panel stays inside safe canvas %d" % dimensions.x)
		button.grab_focus()
		pointer(button, true)
		await frames()
		readable_pressed(button, await screenshot("settings-held-%d" % dimensions.x), "settings assignment %d" % dimensions.x)
		pointer(button, false)
		await frames()
		settings._end_capture()
	settings.pages.current_tab = 2
	await frames()
	var option: OptionButton = settings.pages.get_child(2).get_child(0).get_child(0).get_child(1)
	option.grab_focus()
	pointer(option, true)
	await frames()
	await screenshot("settings-option-popup-phone")
	pointer(option, false)
	option.get_popup().hide()
	settings.pages.current_tab = 3
	await frames()
	var toggle: CheckButton = settings.pages.get_child(3).get_child(0).get_child(0).get_child(1)
	toggle.grab_focus()
	pointer(toggle, true)
	await frames()
	await screenshot("settings-check-held-phone")
	pointer(toggle, false)
	print("BUTTON_STATES_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
