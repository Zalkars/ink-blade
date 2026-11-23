extends Node

## Замер FPS на арене босса: запускает игру, переносит игрока к Хранителю
## и меряет реальные кадры, пока босс бьёт волнами и каплями.
## Запуск в окне, не headless:
##   Godot --path godot res://tests/perf.tscn
## Добавьте -- --stress-fx для сравнения предельной производительности с частицами.
## --pace-60 проверяет реальное ограничение в 60 FPS на той же нагрузке.
## Стресс-тест измеряет также 1-й перцентиль, чтобы среднее не скрывало просадки.

const WARMUP := 90
const MEASURE := 360

var _stress_flow: Node
var _stress_tick := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	flow.start_run()
	await get_tree().physics_frame
	var stress := "--stress-fx" in OS.get_cmdline_user_args()
	var paced := "--pace-60" in OS.get_cmdline_user_args()
	if stress:
		Engine.max_fps = 60 if paced else 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		seed(30445)

	# Кисть в руки и к арене: так в кадре есть волны, капли и HUD босса.
	flow.player.unlock_weapon("weapon.brush", true)
	# Триггер Переписчика не должен перехватить замер: отмечаем его пройденным.
	flow.level.fired_triggers.append("archivist")
	flow.player.global_position = Vector2(13000.0, 520.0)
	flow.player.velocity = Vector2.ZERO
	flow.player.hp = flow.player.MAX_HP
	flow.player.iframes = 999.0
	if stress:
		_stress_flow = flow
		var warmup_until := Time.get_ticks_msec() + 3500
		while Time.get_ticks_msec() < warmup_until:
			await get_tree().process_frame
	else:
		for i in WARMUP:
			await get_tree().process_frame

	var elapsed := 0.0
	var worst := 999.0
	var rolling_time := 0.0
	var slowest_60_frames := INF
	var frame_times := PackedFloat64Array()
	frame_times.resize(60)
	var max_fx := 0
	var max_draws := 0
	var max_mem := 0.0
	var late_frames := 0
	var peak_particles := 0
	var combat_ink := CombatFx.layer(flow.player)
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	var start_tick := _stress_tick
	var frame_count := MEASURE * 2 if stress else MEASURE
	for i in frame_count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1_000_000.0
		last = now
		var fps := 1.0 / maxf(dt, 0.000001)
		elapsed += dt
		var ring_index := i % frame_times.size()
		rolling_time += dt - frame_times[ring_index]
		frame_times[ring_index] = dt
		if i >= frame_times.size() - 1:
			slowest_60_frames = minf(slowest_60_frames, float(frame_times.size()) / rolling_time)
		if dt > 0.020:
			late_frames += 1
		worst = minf(worst, fps)
		samples.append(fps)
		peak_particles = maxi(peak_particles, InkFx.parts.size() + combat_ink.particles.size())
		var fx := 0
		for child in flow.level.get_children():
			if child is InkWave or child is InkDrop:
				fx += 1
		max_fx = maxi(max_fx, fx)
		max_draws = maxi(max_draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_mem = maxf(max_mem, Performance.get_monitor(Performance.MEMORY_STATIC))

	var avg := float(frame_count) / elapsed
	samples.sort()
	# 5-й перцентиль — это порог худших 5% кадров, а не лучших.
	var p5 := samples[int(float(samples.size() - 1) * 0.05)]
	var p1 := samples[int(float(samples.size() - 1) * 0.01)]
	var tick_rate := float(_stress_tick - start_tick) / elapsed
	var boss_note := "none"
	if flow.level.boss != null and is_instance_valid(flow.level.boss):
		boss_note = "engaged" if flow.level.boss.engaged else "dormant"
	print("PERF: avg=%.1f min=%.1f p5=%.1f p1=%.1f slowest_60_frames=%.1f frames=%d over_20ms=%d particles=%d stress_ticks_per_s=%.1f boss=%s max_fx=%d draws=%d mem_mb=%.1f" % [
		avg, worst, p5, p1, slowest_60_frames, frame_count, late_frames, peak_particles, tick_rate, boss_note, max_fx, max_draws,
		max_mem / (1024.0 * 1024.0)])
	var ok := avg >= 58.0 and p5 >= 55.0
	if stress:
		ok = ok and peak_particles >= 500 and tick_rate >= 118.0 and (p1 >= 57.0 if paced else p1 >= 60.0)
	_stress_flow = null
	flow.queue_free()
	await get_tree().process_frame
	print("PERF_RESULT=" + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_stress_flow) or get_tree().paused:
		return
	_stress_tick += 1
	if _stress_tick % 12 != 0:
		return
	var point := Vector2(13000.0, 530.0)
	InkFx.ink_burst(point.x, point.y, 30, 390, null, 7, true, null, 0, 0, 900, 576)
	InkFx.ink_burst(point.x - 2000, point.y, 30, 390, null, 7, true, null, 0, 0, 900, 576)
	InkFx.dust(point.x, point.y + 26, 12, 1.0)
	CombatFx.burst(_stress_flow.player, point + Vector2((_stress_tick % 192) - 96, 0), Vector2.UP, InkR.RED, 24)
