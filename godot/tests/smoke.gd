extends Node

## Smoke-тест каркаса: поднимает сцену, грузит уровень, гоняет физику
## и проверяет ключевые требования из docs/tech-brief.md §11.
## Запуск: Godot --headless --path godot tests/smoke.tscn

const Flow := preload("res://scripts/core/game_flow.gd")

var failures := 0
var checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _run()
	print("SMOKE: %d проверок, %d провалов" % [checks, failures])
	print("SMOKE_RESULT=" + ("OK" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _run() -> void:
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame

	_check(int(Engine.physics_ticks_per_second) == 120, "тик физики 120 Гц")
	_check(flow.title_screen != null and flow.title_screen.visible, "стартовый экран — титул")

	flow.start_run()
	await get_tree().physics_frame

	_check(flow.level != null, "уровень загружен как сцена")
	_check(flow.player != null, "игрок создан сценой, а не RefCounted")
	_check(flow.level.enemy_count() == 4, "враги из JSON: %d из 4" % flow.level.enemy_count())
	_check(flow.level.spawn_point.y > 0.0, "точка спавна из данных")

	# Падение и приземление
	for i in 90:
		await get_tree().physics_frame
	_check(flow.player.is_on_floor(), "игрок падает и встаёт на землю")

	# Рывок действительно двигает игрока
	var x0: float = flow.player.global_position.x
	flow.player.facing = 1
	flow.player._try_dash()
	for i in 20:
		await get_tree().physics_frame
	var dash_moved: float = flow.player.global_position.x - x0
	_check(dash_moved > 120.0, "рывок прошёл %.0f px" % dash_moved)

	for i in 40:
		await get_tree().physics_frame

	# Прыжок поднимает игрока
	var y0: float = flow.player.global_position.y
	flow.player.jump_buf = flow.player.JUMP_BUFFER
	for i in 12:
		await get_tree().physics_frame
	var rose: float = y0 - flow.player.global_position.y
	_check(rose > 30.0, "прыжок поднял на %.0f px за 0.1 с" % rose)
	var landed := false
	for i in 240:
		await get_tree().physics_frame
		if flow.player.is_on_floor():
			landed = true
			break
	_check(landed, "после прыжка игрок возвращается на землю")

	# Атака реально попадает по врагу (слои, форма, запрос физики)
	var target = flow.level.enemies[0]
	flow.player.global_position = target.global_position + Vector2(-40.0, -40.0)
	await get_tree().physics_frame
	var target_hp: int = target.hp
	flow.player.attack_cd = 0.0
	flow.player.facing = 1
	flow.player._try_attack()
	await get_tree().physics_frame
	_check(target.hp < target_hp, "атака снимает здоровье врагу (%d -> %d)" % [target_hp, target.hp])

	# Настроенные ощущения: прыжок выше, падение медленнее, рывок длиннее
	var jump_h: float = (flow.player.JUMP_VELOCITY * flow.player.JUMP_VELOCITY) / (2.0 * flow.player.GRAVITY)
	_check(jump_h > 132.0 and jump_h < 155.0, "высота прыжка %.0f px (в прототипе ~127)" % jump_h)
	var fall_top: float = flow.player.MAX_FALL / flow.player.GRAVITY
	_check(fall_top > 0.45, "разгон до максимального падения %.2f с (было 0.47)" % fall_top)
	var dash_len: float = flow.player.DASH_SPEED * flow.player.DASH_TIME
	_check(dash_len > 143.0, "дистанция рывка %.0f px (в прототипе 131)" % dash_len)
	_check(flow.player.ATTACK_COOLDOWN > 0.0, "у атаки есть кулдаун")

	# Хит по врагу: два удара убивают
	var victim = flow.level.enemies[0]
	var before: int = flow.level.enemy_count()
	victim.hit(1, 1)
	victim.hit(1, 1)
	await get_tree().physics_frame
	_check(flow.level.enemy_count() == before - 1, "враг умирает от двух ударов")

	# Урон игроку и неуязвимость
	var hp0: int = flow.player.hp
	flow.player.take_damage(1, 1.0)
	flow.player.take_damage(1, 1.0)
	_check(flow.player.hp == hp0 - 1, "неуязвимость гасит второй удар подряд")

	# Сохранение
	var ok_write: bool = SaveGame.write_slot("smoke", {"level": "arena_01", "hp": 3})
	var loaded: Dictionary = SaveGame.read_slot("smoke")
	_check(ok_write, "слот пишется")
	_check(int(loaded.get("hp", 0)) == 3 and int(loaded.get("version", 0)) == SaveGame.VERSION, "слот читается с версией")
	SaveGame.erase_slot("smoke")

	# Пауза
	flow._pause()
	_check(get_tree().paused, "пауза останавливает дерево")
	_check(flow.overlay.visible, "окно паузы открыто")
	flow._resume()
	_check(not get_tree().paused, "продолжение снимает паузу")

	# Смерть и перезапуск
	flow.player.iframes = 0.0
	flow.player.take_damage(99, 1.0)
	await get_tree().physics_frame
	_check(flow.state == Flow.State.DEAD, "смерть переводит в состояние DEAD")
	_check(flow.overlay.visible, "окно смерти открыто")
	flow.start_run()
	await get_tree().physics_frame
	_check(flow.state == Flow.State.PLAY, "перезапуск возвращает в игру")
	_check(flow.player.hp == flow.player.MAX_HP, "после перезапуска здоровье полное")

	flow.queue_free()
	await get_tree().process_frame
