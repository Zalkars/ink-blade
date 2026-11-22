extends Node

var failures := 0
var dismissals := 0
var guide: Control

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	get_viewport().push_input(event, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	guide = preload("res://scenes/ui/control_guide.tscn").instantiate()
	add_child(guide)
	guide.dismissed.connect(func(): dismissals += 1)
	guide.open()
	var point: Vector2 = guide._button.get_global_rect().get_center()
	check(guide._button.size.x > 0 and guide._button.size.y > 0 and guide.get_global_rect().has_point(point), "button geometry exists before drawing")
	touch(0, point, true)
	await get_tree().create_timer(0.4).timeout
	touch(0, point, false)
	check(guide.visible, "touch begun during guard cannot dismiss later")
	touch(0, point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(50, 0)
	get_viewport().push_input(drag, true)
	touch(0, point, false)
	check(guide.visible, "drag out and back cancels activation")
	touch(0, point, true)
	touch(0, point, false, true)
	check(guide.visible, "canceled touch preserves guide")
	touch(0, point, true)
	touch(1, point, false)
	check(guide.visible, "another finger cannot finish a tap")
	touch(0, point, false)
	check(guide.visible and guide.step == 1 and dismissals == 0, "touch release inside advances one step without mouse emulation")
	await get_tree().create_timer(0.25).timeout
	point = guide._skip.get_global_rect().get_center()
	touch(0, point, true)
	touch(0, point, false)
	check(not guide.visible and dismissals == 1, "explicit skip dismisses guide")
	guide.open()
	get_window().size = Vector2i(1600, 720)
	await get_tree().create_timer(0.4).timeout
	point = guide._button.get_global_rect().get_center()
	check(guide.get_global_rect().encloses(guide._button.get_global_rect()), "resize keeps button hit area inside overlay without drawing")
	touch(0, point, true)
	touch(0, point, false)
	check(guide.visible and guide.step == 1, "Next tap works after resize")
	await get_tree().create_timer(0.25).timeout
	point = guide._skip.get_global_rect().get_center()
	touch(0, point, true)
	touch(0, point, false)
	check(not guide.visible and dismissals == 2, "Skip tap works after resize")
	guide.queue_free()
	await get_tree().process_frame
	print("GUIDE_TOUCH_RESULT=%s" % ("OK" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures else 0)
