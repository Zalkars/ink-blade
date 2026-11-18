class_name CombatFx
extends Node2D

## Level-owned ink: bounded storage, no collision, discarded with the room.
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const MAX_MARKS := 160
const MAX_PARTICLES := 240
var marks: Array[Dictionary] = []
var particles: Array[Dictionary] = []

static func layer(actor: Node) -> CombatFx:
	var root := actor.get_parent()
	while root.get_parent() != null and not root is Level:
		root = root.get_parent()
	var fx := root.get_node_or_null("CombatInk") as CombatFx
	if fx == null:
		fx = CombatFx.new()
		fx.name = "CombatInk"
		fx.z_index = 2
		root.add_child(fx)
	return fx

static func burst(actor: Node2D, point: Vector2, direction: Vector2, color := RED, count := 12) -> void:
	var fx := layer(actor)
	for i in count:
		if fx.particles.size() >= MAX_PARTICLES:
			fx.particles.pop_front()
		var v := direction.normalized().rotated(randf_range(-1.2, 1.2)) * randf_range(70, 240)
		fx.particles.append({"p": fx.to_local(point), "v": v,
			"life": randf_range(0.2, 0.48), "size": randf_range(1.5, 4.5), "color": color})
	fx.queue_redraw()

static func surface(actor: Node2D, point: Vector2, normal: Vector2, strength := 1.0) -> void:
	var fx := layer(actor)
	var tangent := normal.orthogonal()
	var polygon := PackedVector2Array()
	for i in 22:
		var a := TAU * i / 22.0
		var radius := randf_range(0.72, 1.15) * strength
		polygon.append((tangent * cos(a) * 24.0 + normal * sin(a) * 7.0) * radius)
	var dots: Array[Vector2] = []
	for i in 9:
		dots.append(tangent * randf_range(-36, 36) * strength + normal * randf_range(1, 10))
	fx.marks.append({"p": fx.to_local(point + normal * 0.8), "poly": polygon, "dots": dots})
	if fx.marks.size() > MAX_MARKS:
		fx.marks.pop_front()
	burst(actor, point, normal, INK, 16)

static func floor_mark(actor: Node2D, point: Vector2, strength := 1.0) -> void:
	var ray := PhysicsRayQueryParameters2D.create(point - Vector2(0, 8), point + Vector2(0, 90), 1)
	var hit := actor.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		surface(actor, hit.position, hit.normal, strength)

func _process(delta: float) -> void:
	if particles.is_empty():
		return
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0:
			particles.remove_at(i)
			continue
		p.v.y += 500.0 * delta
		p.p += p.v * delta
	queue_redraw()

func _draw() -> void:
	for mark in marks:
		draw_set_transform(mark.p)
		draw_colored_polygon(mark.poly, Color(INK, 0.78))
		for i in mark.dots.size():
			draw_circle(mark.dots[i], 1.0 + (i % 3) * 0.65, Color(INK, 0.65))
	draw_set_transform(Vector2.ZERO)
	for p in particles:
		var col := Color(p.color, minf(1.0, p.life * 5.0))
		draw_line(p.p - p.v * 0.018, p.p, col, p.size, true)
