extends Node

var flow
var checks := 0
var failures := 0
const OUT := "res://../builds/phone-menu-review/"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 4) -> void:
	for i in count:
		await get_tree().physics_frame

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func check_rows(panel: Control, label: String) -> void:
	var safe := Rect2(Vector2.ZERO, panel.size)
	for i in panel.actions.size():
		var r: Rect2 = panel.item_rect(i)
		check(safe.encloses(r) and r.size.y >= 72 and r.size.x >= 600, label + " roomy safe target " + str(i))
		if i > 0:
			var previous: Rect2 = panel.item_rect(i - 1)
			check(r.position.y - previous.end.y >= 8, label + " separated target " + str(i))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	CTL.touch_enabled = true
	CTL.device = "touch"
	for dimensions in [Vector2i(1280,720), Vector2i(1560,720), Vector2i(1600,720)]:
		get_window().size = dimensions
		flow.start_run()
		flow._show_title()
		await frames(8)
		var title = flow.title_screen
		check_rows(title, "title " + str(dimensions.x))
		await shot("title-%d" % dimensions.x)
		title.activate(title.actions.find("slots"))
		check_rows(title, "load slots " + str(dimensions.x))
		await shot("slots-%d" % dimensions.x)
		title.handle_back()
		title.activate(title.actions.find("play"))
		check_rows(title, "new game " + str(dimensions.x))
		check(title.actions[title.selected] == "cancel_new", "large confirmation still defaults to cancel")
		await shot("confirm-%d" % dimensions.x)
		title.handle_back()
		flow.continue_run()
		flow._pause()
		check_rows(flow.overlay, "pause " + str(dimensions.x))
		await shot("pause-%d" % dimensions.x)
		flow.overlay.activate(flow.overlay.actions.find("slots"))
		check_rows(flow.overlay, "save slots " + str(dimensions.x))
		flow.overlay.handle_back()
		flow.overlay.request_restart()
		check_rows(flow.overlay, "restart " + str(dimensions.x))
		await shot("restart-%d" % dimensions.x)
		flow.overlay.open(flow.overlay.Mode.DEAD)
		flow.overlay._death_t = 1.2
		check_rows(flow.overlay, "death " + str(dimensions.x))
		await shot("death-%d" % dimensions.x)
		flow.overlay.close()
	flow.queue_free()
	await frames(2)
	print("PHONE_MENUS_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures else 0)
