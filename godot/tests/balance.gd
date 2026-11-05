extends Node

## Оценка длительности боя с боссом: игрок стоит рядом и бьёт только
## по открытой печати. Не заменяет живую игру, но ловит явный перекос.
## Запуск ускоренно:
##   Godot --headless --fixed-fps 120 --path godot res://tests/balance.tscn

const MAX_SECONDS := 180.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	var flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	await _measure(flow, "weapon.brush")
	await _measure(flow, "weapon.blade")
	flow.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _measure(flow, weapon_id: String) -> void:
	flow.start_run()
	await get_tree().physics_frame
	flow.level.fired_triggers.append("archivist")
	var p: Player = flow.player
	p.unlock_weapon("weapon.brush", false)
	p.equip_weapon(weapon_id)
	p.iframes = 9999.0
	p.global_position = Vector2(13000.0, 520.0)
	p.velocity = Vector2.ZERO
	var keeper: Keeper = flow.level.boss
	keeper.engaged = true
	keeper.state = Keeper.State.STALK
	keeper.attack_cd = 0.9
	var start_hp := keeper.hp
	var last_hp := keeper.hp
	var hits := 0
	var t := 0.0
	while t < MAX_SECONDS and is_instance_valid(keeper) and not keeper.dead:
		await get_tree().physics_frame
		if not is_instance_valid(keeper) or keeper.dead:
			break
		t += 1.0 / 120.0
		# Держим игрока рядом с боссом и бьём только в открытую печать.
		p.global_position = Vector2(keeper.global_position.x - 60.0, 520.0)
		p.velocity = Vector2.ZERO
		p.facing = 1
		if keeper.seal_open:
			p._try_attack()
		if keeper.hp < last_hp:
			hits += 1
			last_hp = keeper.hp
	var result := "dead" if (not is_instance_valid(keeper) or keeper.dead) else "timeout"
	print("BALANCE %s: %.1f s, hits=%d, start_hp=%d, result=%s" % [
		weapon_id, t, hits, start_hp, result])
