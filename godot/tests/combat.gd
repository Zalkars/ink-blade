extends Node2D

## Isolated combat regression; does not read or erase saves.
## Godot --headless --path godot tests/combat.tscn
class TestRoom extends Level:
	func _ready() -> void:
		pass

var failures := 0
var checks := 0
var room: Level

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s %s" % ["OK" if ok else "FAIL", label])

func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func solid(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	room.add_child(body)

func _ready() -> void:
	room = TestRoom.new()
	add_child(room)
	solid(Vector2(400, 340), Vector2(800, 40))
	solid(Vector2(620, 180), Vector2(40, 280))
	var player := preload("res://scenes/actors/player.tscn").instantiate() as Player
	player.position = Vector2(300, 280)
	room.add_child(player)
	await ticks(25)
	player.set_physics_process(false)
	check(player.is_on_floor(), "player grounded")
	player.hp = 3
	player.soul = 80
	CTL.state["heal"] = true
	for i in 50:
		player._physics_process(1.0 / 60)
	check(player.hp == 4 and is_equal_approx(player.soul, 40), "heal completes and spends ink once")
	CTL.state["heal"] = false
	player._physics_process(0.01)
	check(not player.healing and player.heal_t == 0, "release cancels channel")
	player.hp = 3
	player.soul = 0
	CTL.state["heal"] = true
	player._physics_process(1.0)
	check(player.hp == 3 and not player.healing, "no heal without ink")
	CTL.state["heal"] = false
	player.attack_t = 0.1
	player.healing = true
	player.dash_t = 0.1
	player.take_damage(1, -1)
	player.take_damage(1, -1)
	check(player.hp == 2 and player.attack_t == 0 and not player.healing and player.dash_t == 0,
		"damage interrupts actions; invulnerability blocks duplicate damage")
	player.iframes = 0
	player.hurt_t = 0
	player.position = Vector2(300, 297)
	player.velocity = Vector2.ZERO
	var grunt := preload("res://scenes/actors/grunt.tscn").instantiate() as Grunt
	grunt.position = Vector2(325, 297)
	room.add_child(grunt)
	grunt.set_physics_process(false)
	grunt.target = player
	grunt._touch_player(-25)
	check(player.hp == 2 and grunt.attack_t > 0, "melee telegraph precedes damage")
	grunt._physics_process(0.23)
	check(player.hp == 1, "melee strike lands after windup")
	player.iframes = 0
	player.hurt_t = 0
	player.soul = 0
	player.attack_cd = 0
	player.facing = 1
	player._try_attack()
	check(grunt.hp == 2, "blade anticipation precedes damage")
	player._physics_process(0.06)
	check(grunt.hp == 1 and player.soul == 12, "successful blade hit earns ink")
	player.attack_t = 0
	grunt.queue_free()
	var bolt := InkBolt.new()
	bolt.position = Vector2(500, 200)
	bolt.velocity = Vector2(2000, 0)
	room.add_child(bolt)
	bolt.set_physics_process(false)
	await ticks(2)
	bolt._physics_process(0.1)
	var fx := room.get_node("CombatInk") as CombatFx
	# Keep landing particles deterministic while testing each projectile separately.
	fx.set_physics_process(false)
	check(fx.marks.size() == 1, "fast bolt hits wall and leaves a surface mark")
	await ticks(2)
	var drop := InkDrop.new()
	drop.position = Vector2(450, 280)
	drop.falling = true
	drop.fall_speed = 900
	drop.floor_y = 500
	room.add_child(drop)
	drop.set_physics_process(false)
	var landed := [false]
	drop.landed.connect(func(): landed[0] = true)
	drop._physics_process(0.1)
	check(landed[0] and fx.marks.size() == 2, "drop hits actual floor before fallback height")
	var wave := InkWave.new()
	wave.position = Vector2(570, 300)
	wave.velocity = Vector2(360, 0)
	room.add_child(wave)
	wave.set_physics_process(false)
	wave._physics_process(0.1)
	check(fx.marks.size() == 3, "wave stains the wall on contact")
	fx._physics_process(2.0)
	check(fx.particles.is_empty() and fx.marks.size() == 3, "stains persist after particles expire")
	for i in CombatFx.MAX_MARKS + 5:
		CombatFx.surface(player, Vector2(100 + i % 200, 320), Vector2.UP)
	check(fx.marks.size() > 3 and fx.marks.size() <= CombatFx.MAX_MARKS and fx.particles.size() <= CombatFx.MAX_PARTICLES,
		"effect storage is bounded")
	# Призванная боссом клякса остаётся одной: иначе призыв давал трёх врагов.
	var summoned_before := room.enemies.size()
	room._on_boss_summon(Vector2(500, 300), &"enemy.blot", 1)
	var summoned = room.enemies.back()
	check(room.enemies.size() == summoned_before + 1 and not summoned.splits, "boss summon stays a single blot")
	summoned.hit(99, 1)
	await ticks(2)
	check(room.enemies.size() == summoned_before, "boss summon does not split on death")
	var weak_fx: WeakRef = weakref(fx)
	room.queue_free()
	await ticks(2)
	check(weak_fx.get_ref() == null, "level unload frees ink effects")
	print("COMBAT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
