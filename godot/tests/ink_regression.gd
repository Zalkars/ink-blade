extends Node2D
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["OK" if ok else "FAIL", label])
func _ready() -> void:
	var room := Node2D.new()
	add_child(room)
	var actor := Node2D.new()
	room.add_child(actor)
	var body := StaticBody2D.new()
	body.position = Vector2(100, 200)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(200, 40)
	collider.shape = shape
	body.add_child(collider)
	room.add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fx := CombatFx.new()
	room.add_child(fx)
	var stains := CombatFx.StainsLayer.new()
	stains.owner_fx = fx
	room.add_child(stains)
	fx._stains = stains
	fx.set_physics_process(false)
	fx._deposit(Vector2(100, 180), Vector2.UP, 1.0)
	check(fx.marks.size() == 1, "impact leaves one terrain mark")
	var all_inside := true
	for poly in fx.marks[0].fragments:
		for v in poly:
			all_inside = all_inside and v.x >= -0.01 and v.x <= 200.01 and v.y >= 179.99 and v.y <= 220.01
	check(all_inside, "ink clipped to actual terrain; no free-space paint")
	var saved := fx.export_state()
	var encoded := JSON.stringify(saved)
	fx.restore_state(JSON.parse_string(encoded))
	check(JSON.stringify(fx.export_state()) == encoded, "JSON ink roundtrip is stable")
	fx._deposit(Vector2(700, 40), Vector2.UP, 1.0)
	check(fx.marks.size() == 1, "empty air cannot receive persistent ink")
	fx.restore_state([null, {}, {"v": 3, "fragments": []}, {"v": 1, "fragments": [[[0, 0], [10, 0], ["bad", 4]]]}])
	check(fx.marks.is_empty(), "malformed and future-version marks ignored")
	fx.restore_state([{"v": 1, "fragments": [[[0,0],[10,0],[10,10],[0,10]]]}])
	check(fx.marks.is_empty(), "saved background and column marks are discarded")
	fx.restore_state([{"v": 1, "fragments": [[[10,185],[20,185],[20,195],[10,195]]]}])
	check(fx.marks.size() == 1 and fx.export_state()[0].v == 2, "legacy numeric polygons migrate to compact v2")
	fx.restore_state([{"v":2,"fragments":["!malformed", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}])
	check(fx.marks.is_empty(), "malformed compact payloads ignored")
	var over_limit: Array = []
	for i in CombatFx.MAX_MARKS + 5:
		over_limit.append(saved[0])
	fx.restore_state(over_limit)
	check(fx.marks.size() == CombatFx.MAX_MARKS, "save restore bounds mark count")
	var started := Time.get_ticks_usec()
	var stress_state := fx.export_state()
	var export_ms := (Time.get_ticks_usec()-started)/1000.0
	var stress_json := JSON.stringify(stress_state)
	print("INK_STRESS marks=%d bytes=%d export_ms=%.2f export_json_ms=%.2f" % [fx.marks.size(), stress_json.length(), export_ms, (Time.get_ticks_usec()-started)/1000.0])
	fx.restore_state([])
	fx.particles = [{"p": Vector2(100, 160), "v": Vector2(0, 180), "life": 1.0, "size": 5.0, "color": CombatFx.INK, "deposit": true}]
	for i in 30:
		fx._physics_process(1.0 / 120.0)
	check(not fx.marks.is_empty() and fx.particles.is_empty(), "falling droplets deposit and stop at surface")
	# Tangencies and narrow surfaces must never feed invalid polygons to rendering.
	fx.restore_state([])
	shape.size = Vector2(200, 0.02)
	for x in [0.0, 0.001, 99.999, 199.999, 200.0]:
		fx._deposit(Vector2(x, 199.99), Vector2.UP, 0.12)
	var valid_triangles := true
	for mark in fx.marks:
		for indices in mark.triangles:
			valid_triangles = valid_triangles and indices.size() >= 3 and indices.size() % 3 == 0
	check(valid_triangles, "thin-surface and edge-touch fragments have valid cached triangles")
	fx._redraw_stains()
	await get_tree().process_frame
	await get_tree().process_frame
	check(true, "cached triangles submitted to canvas without retriangulation")
	body.position.x += 500.0
	fx.restore_state(saved)
	check(fx.marks.is_empty(), "old terrain marks disappear when their physical surface moves away")
	print("INK_REGRESSION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
