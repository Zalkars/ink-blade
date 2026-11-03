extends Node

## Снимает несколько кадров каркаса в PNG (для показа и для docs).
## Запуск: Godot --path godot tests/capture.tscn

const DIR := "C:/Users/alexk/AppData/Local/Temp/opencode/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame

	await _wait(8)
	await _shot("skeleton-title")

	flow.start_run()
	await _wait(15)

	var p = flow.player
	p.global_position = Vector2(800.0, 520.0)
	p.velocity = Vector2.ZERO
	await _wait(40)
	p.facing = 1
	p._try_attack()
	await _wait(4)
	await _shot("skeleton-play")

	flow._pause()
	await _wait(4)
	await _shot("skeleton-pause")

	flow._resume()
	flow.console.open()
	flow.console.execute("help")
	flow.console.execute("warp 900 480")
	flow.console.execute("spawn grunt")
	flow.console.execute("fps")
	await _wait(4)
	await _shot("skeleton-console")
	flow.console.close()

	get_tree().quit()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(DIR + name + ".png")
	print("SHOT ", name, " ", img.get_size())
