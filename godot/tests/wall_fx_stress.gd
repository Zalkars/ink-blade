extends Node2D
var changes := 0
var checks := 0
var failures := 0
var actor: Node2D
var fx: CombatFx
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["OK" if ok else "FAIL", label])
func _ready() -> void:
	var room := Level.new()
	room.data_path = "res://content/levels/ch01_hall.json"
	add_child(room)
	room.set_physics_process(false)
	for enemy in room.enemies:
		enemy.set_physics_process(false)
	actor = Node2D.new()
	room.add_child(actor)
	fx = CombatFx.layer(actor)
	fx.set_physics_process(false)
	fx.persistent_marks_changed.connect(func(): changes += 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Effect generation must not consume combat's global random sequence.
	seed(48123)
	var expected := randi()
	seed(48123)
	CombatFx.burst(actor, Vector2(672,540), Vector2.LEFT, InkR.CREAM, 8)
	check(randi() == expected, "FX randomness is isolated from gameplay RNG")
	check(not fx.particles.is_empty(), "first wall contact retains visible impact particles")
	var initial_count := fx.particles.size()
	for i in 20:
		CombatFx.burst(actor, Vector2(672,540), Vector2.LEFT, InkR.CREAM, 8)
	check(fx.particles.size() == initial_count, "same contact burst coalesces within active swing")
	for mobile in [false,true]:
		fx.mobile_quality = mobile
		fx.restore_state([])
		for i in 120:
			CombatFx.burst(actor, Vector2(672,540), Vector2.LEFT, InkR.CREAM, 8)
			fx._physics_process(1.0/120.0)
		check(fx.marks.is_empty(), "pale wall chips never become expensive saved black ink (mobile=%s)" % mobile)
		profile(mobile)
	fx.restore_state([])
	for i in 96:
		fx.particles.append({"p":Vector2(128+i*3,570), "trace":Vector2(128+i*3,570), "v":Vector2(0,400), "life":1.0, "size":5.0, "color":CombatFx.INK, "deposit":true})
	var landing_start := Time.get_ticks_usec()
	fx._physics_process(1.0/60.0)
	print("WALL_LANDING_STORM ms=%.3f rays=%d deposits=%d" % [(Time.get_ticks_usec()-landing_start)/1000.0,fx.rays_last_tick,fx.deposits_last_tick])
	check(fx.rays_last_tick == 6 and fx.deposits_last_tick > 0 and fx.deposits_last_tick <= 2, "simultaneous mobile droplet landings keep strict work budget and real ink")
	# Small drops cannot suppress a later large projectile mark in the same cell.
	fx.restore_state([])
	fx._deposit(Vector2(620,576),Vector2.UP,0.15)
	fx._deposit(Vector2(620,576),Vector2.UP,1.7)
	check(fx.marks.size() == 2, "strong impact still expands coverage after a small droplet")
	var saved := JSON.stringify(fx.export_state())
	fx.restore_state(JSON.parse_string(saved))
	check(not fx.marks.is_empty(), "optimized stains survive JSON save and terrain-clipped restore")
	if DisplayServer.get_name() != "headless":
		# Exercise mobile trail batching on an actual renderer, not just headless CPU.
		CombatFx.burst(actor,Vector2(400,400),Vector2.UP,CombatFx.INK,24)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	print("WALL_FX_STRESS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
func profile(mobile: bool) -> void:
	fx.restore_state([])
	fx._rng.seed = 93242
	changes = 0
	var worst := 0
	var total := 0
	var peak := 0
	var max_rays := 0
	var max_deposits := 0
	var direct_marks := 0
	for tick in 720:
		var start := Time.get_ticks_usec()
		CombatFx.burst(actor, Vector2(672,540), Vector2.LEFT, InkR.CREAM, 8)
		if tick % 10 == 0:
			var before := fx.marks.size()
			CombatFx.surface(actor, Vector2(620,576), Vector2.UP, 1.0)
			direct_marks += fx.marks.size()-before
		fx._physics_process(1.0/120.0)
		var elapsed := Time.get_ticks_usec()-start
		worst = maxi(worst,elapsed)
		total += elapsed
		peak = maxi(peak,fx.particles.size())
		max_rays = maxi(max_rays,fx.rays_last_tick)
		max_deposits = maxi(max_deposits,fx.deposits_last_tick)
	var start := Time.get_ticks_usec()
	var payload := JSON.stringify(fx.export_state())
	print("WALL_STRESS mobile=%s frames=720 total_ms=%.2f worst_ms=%.2f mean_ms=%.3f peak_particles=%d marks=%d change_signals=%d max_rays=%d max_droplet_deposits=%d save_bytes=%d save_ms=%.2f" % [mobile,total/1000.0,worst/1000.0,total/720000.0,peak,fx.marks.size(),changes,max_rays,max_deposits,payload.length(),(Time.get_ticks_usec()-start)/1000.0])
	check(peak <= (96 if mobile else CombatFx.MAX_PARTICLES), "particle budget holds under multi-frame wall spam (mobile=%s)" % mobile)
	check(max_rays <= (6 if mobile else 12) and max_deposits <= (2 if mobile else 4), "per-tick droplet collision/deposit work is bounded (mobile=%s)" % mobile)
	check(direct_marks == 1, "72 identical direct impacts create only one saved mark (mobile=%s)" % mobile)
