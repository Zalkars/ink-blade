extends Node

## Isolated APPDATA required. --capture saves representative UI frames at both aspects.
var failures := 0
var checks := 0
var flow
var capture := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 4) -> void:
	for i in count:
		await get_tree().physics_frame

func shot(label: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://../builds/ui-review/"
	DirAccess.make_dir_recursive_absolute(path)
	get_viewport().get_texture().get_image().save_png(path + label + ".png")
	print("SHOT ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture = "--capture" in OS.get_cmdline_user_args()
	# Preview staged translations without mutating shared locale files.
	var staged = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/ui-strings-0.4.2.json"))
	for language in staged:
		L10N._strings[language].merge(staged[language], true)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames()
	flow.start_run()
	flow.player.hp = 3
	flow._autosave(false)
	flow.save_to_slot("slot_1")
	flow._show_title()
	var title = flow.title_screen
	var original := SaveGame.read_slot(SaveGame.AUTOSAVE)
	var manual := SaveGame.read_slot("slot_1")
	SaveGame.current_slot = "slot_1"
	title.input_guard = 0
	title.activate(title.actions.find("play"))
	check(title._confirm_play and title.selected == 0 and title.actions[0] == "cancel_new", "new game defaults to explicit cancel")
	check(SaveGame.read_slot(SaveGame.AUTOSAVE) == original, "opening confirmation preserves autosave")
	title.activate(1)
	check(flow.state == flow.State.TITLE, "rapid repeated confirm cannot overwrite")
	await frames(40)
	title.activate(0)
	check(not title._confirm_play and SaveGame.read_slot(SaveGame.AUTOSAVE) == original and SaveGame.current_slot == "slot_1", "cancel preserves progress and selected slot")
	title.activate(title.actions.find("play"))
	check(title.handle_back() and not title._confirm_play, "Back cancels confirmation")
	for dimensions in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1600, 720)]:
		get_window().size = dimensions
		await frames(8)
		await shot("title-%d" % dimensions.x)
		title.input_guard = 0
		title.activate(title.actions.find("play"))
		await frames(16)
		check(Rect2(Vector2.ZERO, title.size).encloses(title.item_rect(1)), "confirmation stays in safe canvas %d" % dimensions.x)
		await shot("confirm-%d" % dimensions.x)
		title.handle_back()
		flow.open_settings()
		await frames()
		await shot("settings-%d" % dimensions.x)
		if dimensions.x == 1560:
			flow.settings.pages.current_tab = 1
			await frames()
			flow.settings.pages.get_tab_bar().grab_focus()
			var pad := InputEventJoypadButton.new()
			pad.button_index = JOY_BUTTON_DPAD_DOWN
			pad.pressed = true
			Input.parse_input_event(pad)
			Input.flush_buffered_events()
			await frames()
			pad.pressed = false
			Input.parse_input_event(pad)
			var focused := get_viewport().gui_get_focus_owner()
			check(focused != null and focused.is_visible_in_tree(), "controller navigation keeps visible settings focus")
			await shot("settings-gamepad-1560")
		flow.settings.go_back()
	check(SaveGame.read_slot("slot_1") == manual, "UI navigation preserves manual save")
	SaveGame.current_slot = SaveGame.AUTOSAVE
	flow.start_run()
	await frames(4)
	flow.host.process_mode = Node.PROCESS_MODE_DISABLED
	flow.player.global_position = Vector2(600, 540)
	flow.camera.global_position = Vector2(780, 360)
	flow.camera.reset_smoothing()
	flow.player.hp = 2
	flow.player.soul = 54
	flow.hud.show_banner("Ink Blade", "")
	await frames(20)
	await shot("hud-wide")
	get_window().size = Vector2i(1560, 720)
	CTL.touch_enabled = true
	CTL.device = "touch"
	flow.mobile_controls.visible = true
	flow.mobile_controls.set_process(true)
	flow.mobile_controls.set_process_input(true)
	flow.mobile_controls._layout()
	await frames(8)
	await shot("hud-touch-1560")
	flow._pause()
	await frames()
	await shot("pause-wide")
	flow._resume()
	flow.play_cutscene("intro")
	await frames()
	await shot("cutscene-wide")
	print("UI_REVIEW_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures else 0)
