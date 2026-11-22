extends Node

## Finite boss fight with ordinary HP, actual movement, collisions and weapon attacks.
class TestRoom extends Level:
	func _ready() -> void:
		pass

const MAX_SECONDS := 100.0
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(('OK ' if ok else 'FAIL ') + label)

func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	await _measure('weapon.brush')
	await _measure('weapon.blade')
	await _measure('weapon.brush', true)
	await _measure('weapon.blade', true)
	await _contracts()
	print('BALANCE_RESULT=%s (%d checks)' % ['OK' if failures == 0 else 'FAIL', checks])
	get_tree().quit(0 if failures == 0 else 1)

func _room() -> Level:
	var room := TestRoom.new()
	room.bounds = Rect2(0, 0, 2000, 720)
	add_child(room)
	var floor := StaticBody2D.new()
	floor.position = Vector2(1000, 600)
	floor.collision_layer = 1
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2200, 48)
	col.shape = shape
	floor.add_child(col)
	room.add_child(floor)
	return room

func _measure(weapon_id: String, actual_scene := false) -> void:
	var room: Level
	var boss: Keeper
	if actual_scene:
		room = preload('res://scenes/level/ch01_hall.tscn').instantiate() as Level
		add_child(room)
		boss = room.boss
		# Keep the real level geometry and boss summons; isolate the boss fight
		# from unrelated placements already traversed on the way to this arena.
		for enemy in room.enemies.duplicate():
			if enemy != boss:
				enemy.queue_free()
		room.enemies = [boss]
		room.fired_triggers.append('archivist')
	else:
		room = _room()
		boss = DB.instantiate(&'boss.keeper') as Keeper
		boss.position = Vector2(950, 556)
		room.add_child(boss)
		boss.summon.connect(func(pos: Vector2, id: StringName, count: int):
			for i in count:
				var add = DB.instantiate(id)
				add.position = pos
				add.target = boss.target
				room.add_child(add))
	var p := preload('res://scenes/actors/player.tscn').instantiate() as Player
	p.position = Vector2(13200, 553) if actual_scene else Vector2(700, 553)
	room.add_child(p)
	p.unlock_weapon('weapon.brush', false)
	p.equip_weapon(weapon_id)
	boss.target = p
	if actual_scene:
		room.bind_player(p)
	var scenario := ('ch01_hall/' if actual_scene else 'flat/') + weapon_id
	var t := 0.0
	var hits := 0
	var previous_hp := boss.hp
	var min_hp := p.hp
	var last_jump := -1.0
	while t < MAX_SECONDS and is_instance_valid(boss) and not p.dead:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if not is_instance_valid(boss):
			hits += 1
			break
		if boss.hp < previous_hp:
			hits += 1
			previous_hp = boss.hp
		min_hp = mini(min_hp, p.hp)
		# Stay outside contact reach, then approach the exhausted boss.
		var goal := boss.position.x - (65.0 if boss.seal_open else 190.0)
		var danger := false
		for node in room.get_children():
			if node is InkDrop and absf(node.position.x - p.position.x) < 65:
				goal = node.position.x - 115
				danger = true
		CTL.move_x = signf(goal - p.position.x) if absf(goal - p.position.x) > 10 else 0.0
		CTL.edge['jump'] = false
		var wave_near := false
		for node in room.get_children():
			if node is InkWave and absf(node.position.x - p.position.x) < 145:
				wave_near = true
		if p.is_on_floor() and t - last_jump > 0.7 and (wave_near or (boss.state == Keeper.State.WINDUP_SWEEP and boss.state_t < 0.18)):
			CTL.edge['jump'] = true
			last_jump = t
		p.facing = 1 if boss.position.x > p.position.x else -1
		if boss.seal_open and absf(boss.position.x - p.position.x) < 100:
			p._try_attack()
		CTL.state['heal'] = p.hp < 4 and p.soul >= Player.HEAL_COST and absf(boss.position.x - p.position.x) > 130 and not danger
	var won := not is_instance_valid(boss)
	print('BALANCE %s seconds=%.2f hits=%d hp=%d min_hp=%d won=%s' % [scenario,t,hits,p.hp,min_hp,won])
	check(won, scenario + ' defeated through real movement and attacks without invulnerability')
	check(not p.dead, scenario + ' player survives')
	CTL.move_x = 0
	CTL.edge['jump'] = false
	CTL.state['heal'] = false
	room.queue_free()
	await get_tree().physics_frame

func _contracts() -> void:
	var room := _room()
	var p := preload('res://scenes/actors/player.tscn').instantiate() as Player
	p.position = Vector2(700,553)
	room.add_child(p)
	p.set_physics_process(false)
	var boss := DB.instantiate(&'boss.keeper') as Keeper
	boss.position = Vector2(700,556)
	boss.target = p
	room.add_child(boss)
	boss.set_physics_process(false)
	boss._sweep()
	check(boss.seal_open and boss.seal_t >= 1.8, 'sweep exposes a reachable seal window')
	boss.state = Keeper.State.RECOVER
	boss.state_t = boss.seal_t
	var hp := p.hp
	boss._physics_process(0.1)
	check(p.hp == hp, 'exhausted boss does not deal touch damage during punish window')
	boss.open_seal(0.05)
	boss._physics_process(0.1)
	check(not boss.seal_open, 'seal vulnerability expires')
	var drop := InkDrop.new()
	drop.position = Vector2(700, 530)
	drop.floor_y = 556
	room.add_child(drop)
	drop.set_physics_process(false)
	drop.falling = true
	drop.landed.connect(boss._on_drop_landed)
	await get_tree().physics_frame
	drop._on_body_entered(p)
	check(not drop._done and p.hp < hp, 'slam damages once but keeps falling after hitting player')
	var after := p.hp
	p.iframes = 0
	drop._on_body_entered(p)
	check(p.hp == after, 'same drop cannot hit player twice')
	for i in 60:
		if drop._done:
			break
		drop._physics_process(1.0 / 120.0)
	check(boss.seal_open and boss.state == Keeper.State.RECOVER and boss.seal_t >= 2.4, 'slam landing reliably exposes seal after player collision')
	boss.phase = 2
	boss.rain_t = 0.01
	var before := room.get_child_count()
	boss._physics_process(0.1)
	check(room.get_child_count() == before, 'phase two rain cannot overlap recovery opportunity')
	room.queue_free()
	await get_tree().physics_frame
