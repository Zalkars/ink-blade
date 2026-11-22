extends Node

var failures := 0
var checks := 0
var flow
const OUT := "res://../builds/revision-review/"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 4) -> void:
	for i in count:
		await get_tree().physics_frame

func tap(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames()

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT)
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await frames(12)
	await shot("title")
	flow._on_start_pressed()
	check(flow.state == flow.State.CUTSCENE, "new story starts intro")
	while flow.cutscene.visible:
		flow.cutscene.advance()
	var guided_level = flow.level
	check(flow.state == flow.State.GUIDE and get_tree().paused and flow.hud.visible, "guide overlays actual game after intro")
	await frames(45)
	await shot("controls-guide")
	await tap(KEY_SPACE)
	check(flow.control_guide.visible and flow.control_guide.step == 1, "Space advances one demonstration step")
	await frames(30)
	await tap(KEY_ESCAPE)
	await frames()
	check(flow.state == flow.State.PLAY and flow.level == guided_level, "Skip resumes the demonstrated world")
	for enemy in flow.level.enemies:
		enemy.set_physics_process(false)
	flow.player.iframes = 0
	flow.player.soul = 64
	flow.player.hp = 3
	await frames(240)
	await shot("play")
	await tap(KEY_ESCAPE)
	check(flow.state == flow.State.PAUSE, "Esc stays paused across subsequent frames")
	await shot("pause")
	await tap(KEY_ESCAPE)
	check(flow.state == flow.State.PLAY, "second Esc resumes")
	var old_level = flow.level
	await tap(KEY_R)
	check(flow.state == flow.State.PAUSE and flow.level == old_level and flow.overlay.actions[0] == "cancel_restart", "R requests safe confirmation without resetting level")
	await frames(40)
	await tap(KEY_ENTER)
	check(flow.state == flow.State.PAUSE and flow.level == old_level and not flow.overlay._confirm_restart, "default confirmation cancels destructive restart")
	await tap(KEY_ESCAPE)
	check(flow.state == flow.State.PLAY, "Esc resumes after cancel")
	var muted: bool = SND.muted
	await tap(KEY_M)
	check(SND.muted != muted, "M invokes actual mute handler")
	await tap(KEY_M)
	if DisplayServer.get_name() != "headless":
		await tap(KEY_F11)
		check(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED, "F11 actually enters fullscreen")
		await tap(KEY_F11)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "F11 restores windowed mode")
		await tap(KEY_F12)
		await frames(8)
		var files := DirAccess.get_files_at("user://screenshots")
		check(not files.is_empty(), "F12 actually writes a screenshot")
	flow._autosave(false)
	flow._show_title()
	flow.continue_run()
	check(flow.state == flow.State.PLAY and not flow.control_guide.visible and flow.player.hp == 3, "Continue preserves health and skips guide")
	flow.queue_free()
	await frames(2)
	print("WINDOWS_REVIEW_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures else 0)
