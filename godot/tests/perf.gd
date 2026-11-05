extends Node

## Замер FPS на арене босса: запускает игру, переносит игрока к Хранителю
## и меряет реальные кадры, пока босс бьёт волнами и каплями.
## Запуск в окне, не headless:
##   Godot --path godot res://tests/perf.tscn
## Печатает PERF_RESULT=OK, если средний FPS не ниже 58 и 5-й перцентиль не ниже 55.
## Худший кадр печатается для справки: одиночный провал не валит замер.

const WARMUP := 90
const MEASURE := 360

var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	flow.start_run()
	await get_tree().physics_frame

	# Кисть в руки и к арене: так в кадре есть волны, капли и HUD босса.
	flow.player.unlock_weapon("weapon.brush", true)
	# Триггер Переписчика не должен перехватить замер: отмечаем его пройденным.
	flow.level.fired_triggers.append("archivist")
	flow.player.global_position = Vector2(13000.0, 520.0)
	flow.player.velocity = Vector2.ZERO
	flow.player.hp = flow.player.MAX_HP
	flow.player.iframes = 999.0

	for i in WARMUP:
		await get_tree().process_frame

	var total := 0.0
	var worst := 999.0
	var max_fx := 0
	var max_draws := 0
	var max_mem := 0.0
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in MEASURE:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1_000_000.0
		last = now
		var fps := 1.0 / maxf(dt, 0.000001)
		total += fps
		worst = minf(worst, fps)
		samples.append(fps)
		var fx := 0
		for child in flow.level.get_children():
			if child is InkWave or child is InkDrop:
				fx += 1
		max_fx = maxi(max_fx, fx)
		max_draws = maxi(max_draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_mem = maxf(max_mem, Performance.get_monitor(Performance.MEMORY_STATIC))

	var avg := total / float(MEASURE)
	samples.sort()
	# 5-й перцентиль — это порог худших 5% кадров, а не лучших.
	var p5 := samples[int(float(samples.size() - 1) * 0.05)]
	var p1 := samples[int(float(samples.size() - 1) * 0.01)]
	var boss_note := "none"
	if flow.level.boss != null and is_instance_valid(flow.level.boss):
		boss_note = "engaged" if flow.level.boss.engaged else "dormant"
	print("PERF: avg=%.1f min=%.1f p5=%.1f p1=%.1f frames=%d boss=%s max_fx=%d draws=%d mem_mb=%.1f" % [
		avg, worst, p5, p1, MEASURE, boss_note, max_fx, max_draws,
		max_mem / (1024.0 * 1024.0)])
	# Единичный провал на старте окна не считается провалом замера:
	# смотрим средний FPS и 5-й перцентиль (худшие 5% кадров).
	var ok := avg >= 58.0 and p5 >= 55.0
	print("PERF_RESULT=" + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
