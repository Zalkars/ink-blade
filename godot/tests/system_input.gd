extends Node

class SpyFlow extends "res://scripts/core/game_flow.gd":
	var screenshot_requests := 0
	var fullscreen_requests := 0
	func _save_screenshot() -> void:
		screenshot_requests += 1
	func _toggle_fullscreen() -> void:
		fullscreen_requests += 1

var checks := 0
var failures := 0
var flow

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)

func frames(count := 4) -> void:
	for i in count:
		await get_tree().physics_frame

func key(code: int, physical: int, held: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = physical
	event.pressed = held
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int, physical := 0) -> void:
	key(code, physical if physical else code, true)
	key(code, physical if physical else code, false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CTL.reset_bindings()
	flow = SpyFlow.new()
	add_child(flow)
	await frames()
	flow.start_run()
	flow.player.iframes = 9999
	await frames()
	tap(KEY_ESCAPE)
	await frames()
	check(flow.state == flow.State.PAUSE and flow.overlay.visible, "Esc opens pause and stays open beyond opening tick")
	tap(KEY_ESCAPE)
	await frames()
	check(flow.state == flow.State.PLAY and not flow.overlay.visible, "second Esc resumes from paused event path")
	key(KEY_ESCAPE, KEY_ESCAPE, true)
	await frames()
	check(flow.state == flow.State.PAUSE, "held Escape opens pause")
	key(KEY_ESCAPE, KEY_ESCAPE, true, true)
	await frames()
	check(flow.state == flow.State.PAUSE, "keyboard echo does not resume pause")
	key(KEY_ESCAPE, KEY_ESCAPE, false)
	await frames()
	tap(KEY_ESCAPE)
	await frames()
	check(flow.state == flow.State.PLAY, "release while paused permits the next Esc press")
	var muted: bool = SND.muted
	tap(KEY_M)
	await frames()
	check(SND.muted != muted, "short M press/release toggles mute once")
	await frames()
	check(SND.muted != muted, "system action is not repeated on subsequent ticks")
	var debug: bool = flow.hud.debug_on
	tap(KEY_F2)
	await frames()
	check(flow.hud.debug_on != debug, "F2 reaches global hitbox function")
	tap(KEY_F1)
	await frames()
	check(flow.hud.debug_on == debug, "F1 reaches global debug function")
	tap(KEY_F11)
	tap(KEY_F12)
	await frames()
	check(flow.fullscreen_requests == 1 and flow.screenshot_requests == 1, "F11 and F12 dispatch through actual flow handlers")
	tap(0x0416, KEY_M)
	await frames()
	check(SND.muted == muted, "physical binding survives non-Latin logical keycode")
	tap(KEY_ESCAPE)
	await frames()
	var focus_button := Button.new()
	focus_button.text = "Focused GUI"
	flow.ui.add_child(focus_button)
	focus_button.grab_focus()
	tap(KEY_F12)
	await frames()
	check(flow.screenshot_requests == 2, "focused GUI and paused tree do not swallow system keys")
	tap(KEY_ESCAPE)
	await frames()
	check(flow.state == flow.State.PLAY, "Esc resumes even with GUI focus")
	flow.set_physics_process(false)
	key(KEY_M, KEY_M, true)
	CTL.update(1.0 / 120.0)
	check(CTL.down("mute"), "native press is held before focus loss")
	key(KEY_M, KEY_M, false)
	CTL._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	CTL.update(1.0 / 120.0)
	check(not CTL.down("mute") and not CTL.pressed("mute"), "focus loss clears pending and held event keys")
	get_tree().paused = false
	print("SYSTEM_INPUT_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
