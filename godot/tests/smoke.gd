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
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	SaveGame.erase_slot("smoke")
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame

	_check(int(Engine.physics_ticks_per_second) == 120, "тик физики 120 Гц")
	_check(flow.title_screen != null and flow.title_screen.visible, "стартовый экран — титул")
	_check(flow.title_screen.items == ["ИГРАТЬ", "ВЫХОД"], "без автосейва нет пункта «Продолжить»")

	flow.start_run()
	await get_tree().physics_frame

	_check(flow.level != null, "уровень загружен как сцена")
	_check(flow.player != null, "игрок создан сценой, а не RefCounted")
	var placements: Array = flow.level.data.get("placements", [])
	_check(flow.level.enemy_count() == placements.size() and placements.size() >= 10,
		"враги из JSON: %d из %d" % [flow.level.enemy_count(), placements.size()])
	_check(flow.level.enemies[0].target == flow.player, "враг получает цель из уровня")
	_check(flow.level.spawn_point.y > 0.0, "точка спавна из данных")
	_check(flow.level.bounds.size.x >= 6000.0, "длинный уровень: %.0f px" % flow.level.bounds.size.x)
	var lim: Dictionary = flow.level.camera_limits()
	_check(int(lim["right"]) == int(flow.level.bounds.end.x), "границы камеры совпадают с уровнем")
	_check(flow.level.tile_layer != null and flow.level.tile_layer.get_used_cells().size() > 100,
		"геометрия в TileMapLayer: %d клеток" % (flow.level.tile_layer.get_used_cells().size() if flow.level.tile_layer != null else 0))
	_check(flow.level.one_way_cells > 0, "односторонние платформы — тайлы: %d" % flow.level.one_way_cells)

	# Оружие: карточки, стартовый клинок, кисть выдаётся по сюжету
	_check(int(WDB.count()) >= 2, "каталог оружия: %d карточки" % int(WDB.count()))
	_check(flow.player.weapon != null and String(flow.player.weapon.id) == "weapon.blade",
		"стартовое оружие — клинок")
	_check(flow.player.weapons.size() == 1 and not flow.player.has_weapon("weapon.brush"),
		"на старте открыт только клинок")
	flow.player.next_weapon()
	_check(String(flow.player.weapon.id) == "weapon.blade", "без кисти переключение ничего не меняет")
	var blade_damage: int = flow.player.weapon.damage

	# Катсцена вступления: слайды из JSON, пауза, возврат в игру
	_check(flow.play_cutscene("intro"), "вступление читается из JSON")
	_check(flow.state == Flow.State.CUTSCENE and get_tree().paused and flow.cutscene.visible,
		"катсцена ставит игру на паузу")
	_check(flow.cutscene.slide_count() >= 4, "слайдов вступления: %d" % flow.cutscene.slide_count())
	for i in 8:
		if not flow.cutscene.visible:
			break
		flow.cutscene.advance()
		await get_tree().physics_frame
	_check(not flow.cutscene.visible and flow.state == Flow.State.PLAY and not get_tree().paused,
		"катсцена возвращает в игру")

	# Финал: отдельный сценарий, который играет после победы над боссом.
	_check(flow.play_cutscene("finale"), "финал читается из JSON")
	_check(flow.cutscene.slide_count() >= 3, "слайдов финала: %d" % flow.cutscene.slide_count())
	for i in 8:
		if not flow.cutscene.visible:
			break
		flow.cutscene.advance()
		await get_tree().physics_frame
	_check(flow.state == Flow.State.PLAY and not get_tree().paused, "финал возвращает в игру")

	# Диалог Переписчика: пауза, реплики, награда
	_check(flow.play_dialogue("archivist"), "диалог читается из JSON")
	_check(flow.state == Flow.State.DIALOGUE and get_tree().paused and flow.dialogue.visible,
		"диалог ставит игру на паузу")
	var archivist_lines: int = flow.dialogue.line_count()
	_check(archivist_lines >= 4, "реплик Переписчика: %d" % archivist_lines)
	for i in 10:
		if not flow.dialogue.visible:
			break
		flow.dialogue.advance()
		await get_tree().physics_frame
	_check(not flow.dialogue.visible and flow.state == Flow.State.PLAY and not get_tree().paused,
		"диалог возвращает в игру")
	_check(flow.player.has_weapon("weapon.brush"), "после разговора кисть открыта")
	_check(flow.player.weapons.size() == 2, "в руках два оружия")
	_check(flow.hud.toast.contains(L10N.t("weapon.brush.name")), "HUD сообщает о награде")

	flow.player.equip_weapon("weapon.blade")
	flow.player.next_weapon()
	_check(String(flow.player.weapon.id) == "weapon.brush", "переключение на кисть")
	_check(flow.player.weapon.damage > blade_damage, "кисть бьёт сильнее клинка")
	_check(flow.player.weapon.windup > 0.0, "у кисти есть замах")
	flow.player.next_weapon()
	_check(String(flow.player.weapon.id) == "weapon.blade", "переключение возвращает клинок")

	# Каталог контента: карточка -> сцена -> настройка
	_check(int(DB.count()) >= 1, "каталог загружен: %d карточек" % int(DB.count()))
	var grunt_def: EntityDef = DB.get_def(&"enemy.grunt")
	_check(grunt_def != null, "карточка enemy.grunt найдена")
	_check(grunt_def != null and grunt_def.stats != null and grunt_def.stats.max_hp == 2, "статы читаются из карточки")
	var probe = DB.instantiate(&"enemy.grunt")
	_check(probe is Grunt and probe.hp == 2 and is_equal_approx(probe.speed, 95.0), "карточка настраивает сцену")
	probe.free()
	var strong = DB.instantiate(&"enemy.grunt", {"max_hp": 5})
	_check(strong != null and strong.hp == 5, "переопределение уровня применяется")
	strong.free()
	var weak = DB.instantiate(&"enemy.grunt", {"unknown_field": 1})
	_check(weak != null and weak.hp == 2, "неизвестное переопределение игнорируется")
	weak.free()

	# Враги этапа: часовой стреляет, клякса делится на малых
	_check(int(DB.count()) >= 4, "каталог врагов: %d карточек" % int(DB.count()))
	_check(DB.has(&"enemy.sentry") and DB.has(&"enemy.blot") and DB.has(&"enemy.blot_small"),
		"карточки часового и кляксы на месте")

	var sentry_pos: Vector2 = flow.player.global_position + Vector2(120.0, -80.0)
	_check(flow.level.spawn_enemy("sentry", sentry_pos), "часовой создаётся по ID")
	await get_tree().physics_frame
	var sentry_node = flow.level.enemies[flow.level.enemies.size() - 1]
	_check(sentry_node is Sentry and sentry_node.target == flow.player, "часовой видит игрока")
	sentry_node.shoot_t = 0.0
	for i in 3:
		await get_tree().physics_frame
	var bolt_found := false
	for child in flow.level.get_children():
		if child is InkBolt:
			bolt_found = true
			child.queue_free()
	_check(bolt_found, "часовой стреляет чернильным болтом")
	sentry_node.hit(999, 1)
	await get_tree().physics_frame

	var blot_before_spawn: int = flow.level.enemy_count()
	_check(flow.level.spawn_enemy("blot", flow.player.global_position + Vector2(260.0, 0.0)),
		"клякса создаётся по ID")
	await get_tree().physics_frame
	var blot_node = flow.level.enemies[flow.level.enemies.size() - 1]
	var blot_before: int = flow.level.enemy_count()
	blot_node.hit(999, 1)
	await get_tree().physics_frame
	_check(flow.level.enemy_count() == blot_before + 1,
		"клякса делится на двух малых (%d -> %d)" % [blot_before, flow.level.enemy_count()])
	var small_ok := false
	for i in 2:
		var child = flow.level.enemies[flow.level.enemies.size() - 1 - i]
		if child is Blot and child.generation == 1:
			small_ok = true
	_check(small_ok, "малые кляксы помечены поколением 1")

	# Убираем детей, чтобы дальше считать врагов только из данных уровня.
	for i in 2:
		var kid = flow.level.enemies[flow.level.enemies.size() - 1]
		if kid is Blot:
			kid.hit(999, 1)
	await get_tree().physics_frame
	_check(flow.level.enemy_count() == blot_before_spawn,
		"после деления и добивания врагов снова %d" % flow.level.enemy_count())
	var temp_in_killed := false
	for killed_id in flow.level.killed_ids:
		if flow.level.is_temporary_id(killed_id):
			temp_in_killed = true
	_check(not temp_in_killed, "временные враги не попадают в killed")

	# Босс: карточка, закрытая и открытая печать, вторая фаза, смерть
	_check(DB.has(&"boss.keeper"), "карточка босса в каталоге")
	var keeper: Keeper = flow.level.boss
	_check(keeper != null and keeper is Keeper, "босс стоит на арене уровнем")
	_check(keeper != null and keeper.max_hp == 40, "у босса 40 HP из карточки")
	keeper.engaged = true
	keeper.attack_cd = 999.0
	var boss_hp: int = keeper.hp
	keeper.hit(1, 1)
	_check(keeper.hp == boss_hp, "закрытая печать гасит удар")
	keeper.open_seal(5.0)
	keeper.hit(1, 1)
	_check(keeper.hp == boss_hp - 1, "открытая печать принимает урон клинка")
	keeper.open_seal(5.0)
	var before_brush: int = keeper.hp
	keeper.hit(3, 1)
	_check(before_brush - keeper.hp == 4, "кисть по открытой печати снимает 4")
	# Призыв клякс в первой фазе.
	var before_summon: int = flow.level.enemy_count()
	keeper.state = Keeper.State.STALK
	keeper.attack_cd = 0.0
	keeper.summon_cd = 0.0
	for i in 110:
		await get_tree().physics_frame
		if flow.level.enemy_count() >= before_summon + 2:
			break
	_check(flow.level.enemy_count() == before_summon + 2, "босс призывает двух клякс")
	# Удар сверху открывает печать, когда капля доходит до пола.
	keeper.state = Keeper.State.STALK
	keeper.attack_cd = 999.0
	keeper.seal_open = false
	keeper.seal_t = 0.0
	keeper.slam_x = keeper.global_position.x
	keeper._slam()
	var seal_opened := false
	for i in 220:
		await get_tree().physics_frame
		if keeper.seal_open:
			seal_opened = true
			break
	_check(seal_opened, "удар сверху открывает печать")
	# Доводим до половины и ждём переход во вторую фазу.
	keeper.hp = keeper.max_hp / 2 + 1
	keeper.open_seal(5.0)
	keeper.hit(1, 1)
	_check(keeper.state == Keeper.State.STAGGER, "на половине здоровья босс переходит в слом")
	for i in 160:
		await get_tree().physics_frame
	_check(keeper.phase == 2, "после слома начинается вторая фаза")
	keeper.open_seal(5.0)
	keeper.hit(999, 1)
	_check(keeper.dead, "босс умирает от добивающего удара")
	await get_tree().physics_frame
	_check(not is_instance_valid(keeper), "тело босса убирается из сцены")

	# Триггер в Архиве: доводит до Переписчика и запускает диалог
	flow.level.fired_triggers.clear()
	flow.player.global_position = Vector2(3200.0, 500.0)
	flow.player.velocity = Vector2.ZERO
	await get_tree().physics_frame
	_check(not flow.dialogue.visible, "до триггера диалог закрыт")
	flow.player.global_position = Vector2(3280.0, 500.0)
	for i in 3:
		await get_tree().physics_frame
	_check(flow.state == Flow.State.DIALOGUE and flow.dialogue.visible,
		"триггер в Архиве запускает диалог")
	_check(flow.level.fired_triggers.has("archivist"), "триггер помечен пройденным")
	for i in 10:
		if not flow.dialogue.visible:
			break
		flow.dialogue.advance()
		await get_tree().physics_frame
	_check(flow.state == Flow.State.PLAY, "после триггера игра продолжается")

	# Падение и приземление
	for i in 90:
		await get_tree().physics_frame
	_check(flow.player.is_on_floor(), "игрок падает и встаёт на землю")
	_check(absf(flow.player.global_position.y - flow.level.spawn_point.y) < 2.0, "игрок стоит на кромке тайлов")

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

	# Прыжок поднимает игрока (с открытого места, чтобы не задеть платформу сверху)
	flow.player.global_position = flow.level.spawn_point
	flow.player.velocity = Vector2.ZERO
	await get_tree().physics_frame
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
	flow.player.equip_weapon("weapon.blade")
	flow.player._try_attack()
	await get_tree().physics_frame
	_check(target.hp < target_hp, "атака снимает здоровье врагу (%d -> %d)" % [target_hp, target.hp])

	# Тяжёлая кисть: замах, широкий удар, сильный урон
	var brush_target = flow.level.enemies[1]
	flow.player.global_position = brush_target.global_position + Vector2(-40.0, -40.0)
	flow.player.facing = 1
	flow.player.attack_cd = 0.0
	flow.player.equip_weapon("weapon.brush")
	_check(String(flow.player.weapon.id) == "weapon.brush", "кисть взята в руки")
	flow.player._try_attack()
	for i in 20:
		await get_tree().physics_frame
	var brush_dead: bool = not is_instance_valid(brush_target) or brush_target.hp <= 0
	_check(brush_dead, "кисть убивает ползуна одним ударом")
	flow.player.next_weapon()
	_check(String(flow.player.weapon.id) == "weapon.blade", "после удара возвращаемся к клинку")

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
	flow.player.hp = flow.player.MAX_HP
	flow.player.iframes = 0.0
	var hp0: int = flow.player.hp
	flow.player.take_damage(1, 1.0)
	flow.player.take_damage(1, 1.0)
	_check(flow.player.hp == hp0 - 1, "неуязвимость гасит второй удар подряд")

	# Чекпоинт: касание запоминает точку, лечит и пишет автосейв
	_check(flow.level.checkpoint_count() == 4, "чекпоинты из JSON: %d из 4" % flow.level.checkpoint_count())
	var cp_pos: Vector2 = flow.level.checkpoint_position("cp_02")
	flow.player.global_position = cp_pos
	flow.player.velocity = Vector2.ZERO
	for i in 4:
		await get_tree().physics_frame
	_check(flow.checkpoint_id == "cp_02", "касание чекпоинта запоминает его")
	_check(flow.player.hp == flow.player.MAX_HP, "чекпоинт восстанавливает здоровье")
	var cp_save: Dictionary = SaveGame.read_slot(SaveGame.AUTOSAVE)
	_check(String(cp_save.get("checkpoint", "")) == "cp_02", "автосейв хранит чекпоинт")
	var killed_saved: Array = cp_save.get("killed", [])
	_check(killed_saved.has("e1"), "автосейв хранит убитых врагов")
	flow.title_screen.refresh()
	_check(flow.title_screen.items.has("ПРОДОЛЖИТЬ"), "с автосейвом появляется пункт «Продолжить»")

	# Смерть и продолжение: игрок возвращается на чекпоинт, убитый враг не оживает
	var alive_before: int = flow.level.enemy_count()
	flow.player.iframes = 0.0
	flow.player.take_damage(99, 1.0)
	await get_tree().physics_frame
	_check(flow.state == Flow.State.DEAD, "смерть на чекпоинте переводит в DEAD")
	flow.continue_run()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(flow.state == Flow.State.PLAY, "продолжение возвращает в игру")
	_check(flow.player.global_position.distance_to(flow.level.checkpoint_position('cp_02')) < 2.0, "игрок появляется на чекпоинте")
	_check(flow.level.enemy_count() == alive_before, "после продолжения врагов столько же: %d" % flow.level.enemy_count())
	_check(flow.level.killed_ids.has("e1"), "убитый враг остаётся мёртвым")
	_check(flow.player.has_weapon("weapon.brush"), "после продолжения кисть остаётся")
	_check(flow.level.fired_triggers.has("archivist"), "пройденный триггер не срабатывает снова")
	_check(flow.player.hp == flow.player.MAX_HP, "после продолжения здоровье полное")

	# Сохранение
	var ok_write: bool = SaveGame.write_slot("smoke", {"level": "ch01_hall", "hp": 3})
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

	# Debug-консоль: команды меняют мир и не ломают паузу
	_check(flow.console != null and not flow.console.visible, "консоль скрыта по умолчанию")
	flow.console.open()
	_check(get_tree().paused, "открытая консоль ставит игру на паузу")
	flow.console.close()
	_check(not get_tree().paused, "закрытая консоль снимает паузу")

	flow.console.execute("warp 520 400")
	_check(flow.player.global_position.distance_to(Vector2(520.0, 400.0)) < 1.0, "warp переносит игрока")

	flow.player.hp = 1
	flow.console.execute("give hp")
	_check(flow.player.hp == flow.player.MAX_HP, "give hp восстанавливает здоровье")

	var before_spawn: int = flow.level.enemy_count()
	flow.console.execute("spawn grunt")
	_check(flow.level.enemy_count() == before_spawn + 1, "spawn добавляет врага")

	flow.console.execute("kill")
	await get_tree().physics_frame
	_check(flow.level.enemy_count() == 0, "kill убирает всех врагов")
	_check(flow.state == Flow.State.CUTSCENE and flow.cutscene.visible,
		"после зачистки играет финал")
	_check(flow.cutscene.slide_count() >= 3, "слайдов финала: %d" % flow.cutscene.slide_count())
	for i in 8:
		if not flow.cutscene.visible:
			break
		flow.cutscene.advance()
		await get_tree().physics_frame
	_check(flow.state == Flow.State.CLEARED and flow.overlay.visible,
		"финал открывает окно зачистки")
	var cleared_save: Dictionary = SaveGame.read_slot(SaveGame.AUTOSAVE)
	_check(bool(cleared_save.get("cleared", false)), "автосейв помечает уровень зачищенным")

	var fps_reply: String = flow.console.execute("fps")
	_check(fps_reply.contains("fps"), "fps печатает метрики")

	flow.queue_free()
	await get_tree().process_frame
