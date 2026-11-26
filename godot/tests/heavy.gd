extends Node2D

## Heavy attack regression: hold/release, cost, fallback, profiles and ink gain.
## Godot --headless --path godot tests/heavy.tscn
class TestRoom extends Level:
	var freezes: Array[float] = []
	var debug_rules := {"damage": false, "god": false, "flight": false}

	func _ready() -> void:
		pass

	func add_combo() -> void:
		pass

	func freeze(seconds: float) -> void:
		freezes.append(seconds)
		hitstop = maxf(hitstop, seconds)

var failures := 0
var checks := 0
var room: Level
var player: Player

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

func reset_input() -> void:
	CTL.state["attack"] = false
	CTL.edge["attack"] = false
	CTL.state["swap"] = false
	CTL.edge["swap"] = false
	player.attack_t = 0.0
	player.attack_cd = 0.0
	player.attack_windup = 0.0
	player.attack_buf = 0.0
	player.heavy_hold = 0.0
	player.heavy_ready = false
	player._attack_down = false
	player._attack_resolved = false
	player._queued_heavy = false
	player.hurt_t = 0.0
	player.dash_t = 0.0
	player.combo_time = 0.0

func press() -> void:
	CTL.state["attack"] = true
	CTL.edge["attack"] = true
	player._handle_weapon_input(0.0)
	CTL.edge["attack"] = false

func hold(seconds: float) -> void:
	player._handle_weapon_input(seconds)

func release() -> void:
	CTL.state["attack"] = false
	player._handle_weapon_input(0.0)

func tap() -> void:
	CTL.state["attack"] = false
	CTL.edge["attack"] = true
	player._handle_weapon_input(0.0)
	CTL.edge["attack"] = false

func start_heavy() -> void:
	press()
	hold(Player.HEAVY_HOLD + 0.01)
	release()

func _ready() -> void:
	room = TestRoom.new()
	add_child(room)
	solid(Vector2(400, 340), Vector2(800, 40))
	player = preload("res://scenes/actors/player.tscn").instantiate() as Player
	player.position = Vector2(300, 280)
	room.add_child(player)
	await ticks(25)
	player.set_physics_process(false)
	check(player.is_on_floor(), "player grounded")

	var blade := WDB.get_weapon(&"weapon.blade")
	var brush := WDB.get_weapon(&"weapon.brush")
	check(blade != null and blade.heavy_damage == 2 and is_equal_approx(blade.heavy_windup, 0.10)
		and is_equal_approx(blade.heavy_active, 0.14) and is_equal_approx(blade.heavy_cooldown, 0.22)
		and blade.heavy_ink_cost == 25 and blade.heavy_reach == Vector2(80, 64),
		"blade card keeps its heavy profile")
	check(brush != null and brush.heavy_damage == 4 and is_equal_approx(brush.heavy_windup, 0.18)
		and is_equal_approx(brush.heavy_active, 0.36) and is_equal_approx(brush.heavy_cooldown, 0.26)
		and brush.heavy_ink_cost == 25 and brush.heavy_reach == Vector2(84, 64),
		"brush card overrides the heavy profile")

	# A short press is still a free light attack and does not advance into heavy.
	reset_input()
	player.ink = 100.0
	press()
	hold(0.10)
	check(player.attack_t == 0.0 and not player.heavy_ready, "holding below 0,18 s does not attack")
	release()
	check(player.attack_t > 0.0 and not player.swing_heavy and player.swing_damage == 1,
		"short press releases a light attack")
	check(player.ink == 100.0, "light attack is free")

	# A tap that begins and ends between physics ticks is not lost.
	reset_input()
	player.ink = 100.0
	tap()
	check(player.attack_t > 0.0 and not player.swing_heavy and player.ink == 100.0,
		"tap between ticks still produces a light attack")

	# Holding suppresses light attacks entirely and prepares heavy on release.
	reset_input()
	player.ink = 100.0
	press()
	for i in 10:
		hold(0.10)
	check(player.attack_t == 0.0 and player.heavy_ready, "one second hold prepares heavy without auto-repeat")
	check(player.ink == 100.0, "preparing heavy does not spend ink")
	release()
	check(player.attack_t > 0.0 and player.swing_heavy and player.swing_damage == 2,
		"release after 0,18 s starts the heavy strike")
	check(is_equal_approx(player.ink, 75.0), "heavy strike costs 25 ink at the start")
	check(is_equal_approx(player.attack_windup, 0.10) and is_equal_approx(player.swing_active, 0.14)
		and is_equal_approx(player.attack_cd, 0.46), "blade heavy uses its own timing")
	check(player.combo_time == 0.0, "heavy strike resets the blade series")

	# Heavy hit grants 12 ink, and a killing heavy also grants the kill bonus.
	reset_input()
	player.ink = 100.0
	var grunt := preload("res://scenes/actors/grunt.tscn").instantiate() as Grunt
	grunt.position = player.position + Vector2(40.0, 0.0)
	room.add_child(grunt)
	grunt.set_physics_process(false)
	grunt.target = player
	grunt.hp = 3
	start_heavy()
	player._physics_process(0.11)
	check(grunt.hp == 1, "heavy blade deals 2 damage after its windup")
	check(is_equal_approx(player.ink, 87.0), "heavy hit grants 12 ink")
	check(room.freezes.has(0.075), "heavy hit freezes the frame for 0,075 s")
	reset_input()
	player.ink = 100.0
	grunt.hp = 1
	start_heavy()
	player._physics_process(0.11)
	check(grunt.hp <= 0, "second heavy finishes the grunt")
	check(is_equal_approx(player.ink, 97.0), "heavy kill adds the 10 ink kill bonus")

	# No ink: the normal attack comes out after the same hold, with no charge.
	reset_input()
	player.ink = 24.0
	press()
	hold(Player.HEAVY_HOLD + 0.01)
	check(player.attack_t == 0.0 and player.heavy_ready, "empty ink still waits for release")
	release()
	check(player.attack_t > 0.0 and not player.swing_heavy and player.swing_damage == 1,
		"empty ink falls back to a light attack")
	check(is_equal_approx(player.ink, 24.0), "fallback light attack does not spend ink")
	reset_input()
	player.ink = 24.0
	check(not player._try_attack(true) and player.attack_t == 0.0 and player.ink == 24.0,
		"direct heavy request is rejected without 25 ink")

	# Brush overrides damage, windup, recovery and reach.
	reset_input()
	check(player.unlock_weapon("weapon.brush"), "brush can be unlocked for the profile check")
	player.equip_weapon("weapon.brush")
	player.ink = 100.0
	start_heavy()
	check(player.swing_heavy and player.swing_damage == 4, "brush heavy deals 4 damage")
	check(is_equal_approx(player.attack_windup, 0.18) and is_equal_approx(player.swing_active, 0.36)
		and is_equal_approx(player.attack_cd, 0.80), "brush heavy uses its own timing")
	check(player.swing_reach == Vector2(84, 64), "brush heavy uses the card reach")
	check(is_equal_approx(player.ink, 75.0), "brush heavy costs the same 25 ink")

	print("HEAVY_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
