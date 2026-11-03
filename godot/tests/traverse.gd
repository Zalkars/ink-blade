extends Node

## Проверка проходимости уровня: игрок бежит вправо и прыгает на месте,
## пока не дойдёт до конца. Ловит дыры, слишком высокие ступени и тупики.
## Запуск: Godot --headless --path godot res://tests/traverse.tscn

const Flow := preload("res://scripts/core/game_flow.gd")

const TARGET_X := 13900.0
const MAX_STEPS := 12000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	flow.start_run()
	await get_tree().physics_frame

	# Врагов убираем: проверяем геометрию, а не бой.
	for e in flow.level.enemies.duplicate():
		e.queue_free()
	flow.level.enemies.clear()

	var p: Player = flow.player
	p.global_position = flow.level.spawn_point
	p.velocity = Vector2.ZERO
	CTL.stick_on = true
	CTL.stick_x = 1.0

	var max_x: float = p.global_position.x
	var since_jump := 0.0
	var step := 0
	for i in MAX_STEPS:
		await get_tree().physics_frame
		step = i
		# Сюжетная сцена ставит игру на паузу: закрываем её и идём дальше,
		# иначе проверка геометрии застрянет на триггере в Архиве.
		if flow.dialogue.visible:
			flow.dialogue.advance()
			continue
		if flow.cutscene.visible:
			flow.cutscene.advance()
			continue
		if not is_instance_valid(p):
			break
		max_x = maxf(max_x, p.global_position.x)
		since_jump += 1.0 / float(Engine.physics_ticks_per_second)
		if p.is_on_floor() and since_jump > 0.45:
			p.jump_buf = p.JUMP_BUFFER
			since_jump = 0.0
		if p.global_position.x >= TARGET_X:
			break

	CTL.stick_on = false
	CTL.stick_x = 0.0
	var ok := max_x >= TARGET_X
	print("TRAVERSE: x=%.0f за %.1f с, шагов %d" % [
		max_x, float(step) / float(Engine.physics_ticks_per_second), step])
	print("TRAVERSE_RESULT=" + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
