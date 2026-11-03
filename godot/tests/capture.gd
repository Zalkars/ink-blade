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

	flow.start_run(true)
	await _wait(2)
	await _shot("skeleton-cutscene")
	for i in 4:
		flow.cutscene.advance()
	await _wait(15)

	var p = flow.player
	p.global_position = Vector2(800.0, 520.0)
	p.velocity = Vector2.ZERO
	await _wait(40)
	p.facing = 1
	p._try_attack()
	await _wait(4)
	await _shot("skeleton-play")

	flow.play_dialogue("archivist")
	await _wait(6)
	await _shot("skeleton-dialogue")
	for i in 6:
		flow.dialogue.advance()
	await _wait(2)

	flow.console.open()
	flow.console.execute("warp 700 500")
	flow.console.execute("spawn sentry 900 420")
	flow.console.execute("spawn blot 1060 576")
	flow.console.close()
	await _wait(60)
	await _shot("skeleton-enemies")

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
