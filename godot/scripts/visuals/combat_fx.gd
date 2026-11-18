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
	# Ink seeps inward from the contact edge. Never paint free space.
	var footprint := PackedVector2Array()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		var edge := 1.0 + sin(angle * 5 + point.x) * 0.12 + cos(angle * 9) * 0.07
		footprint.append(point - normal * 13 * strength + (tangent * cos(angle) * 34 - normal * sin(angle) * 21) * strength * edge)
	var fragments: Array[PackedVector2Array] = []
	var area := Rect2(point - Vector2.ONE * 64 * strength, Vector2.ONE * 128 * strength)
	for terrain in terrain_polygons(actor, area):
		for clipped in Geometry2D.intersect_polygons(footprint, terrain):
			var local := PackedVector2Array()
			for vertex in clipped:
				local.append(fx.to_local(vertex))
			if local.size() >= 3:
				fragments.append(local)
	fx.marks.append({"fragments": fragments})
	fx.get_parent().queue_redraw()
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
	for p in particles:
		var col := Color(p.color, minf(1.0, p.life * 5.0))
		draw_line(p.p - p.v * 0.018, p.p, col, p.size, true)


static func terrain_polygons(actor: Node2D, area: Rect2) -> Array[PackedVector2Array]:
	var root := layer(actor).get_parent()
	var result: Array[PackedVector2Array] = []
	if root is Level and not root.data.is_empty():
		for spec in root.data.get("solids", []) + root.data.get("one_ways", []):
			var r: Rect2 = root._rect_of(spec)
			var tile := float(InkTileset.SIZE)
			r = Rect2((r.position / tile).round() * tile, (r.end / tile).round() * tile - (r.position / tile).round() * tile)
			var polygon := PackedVector2Array([root.to_global(r.position), root.to_global(Vector2(r.end.x, r.position.y)), root.to_global(r.end), root.to_global(Vector2(r.position.x, r.end.y))])
			if r.intersects(Rect2(root.to_local(area.position), area.size)):
				result.append(polygon)
	else:
		# Synthetic rooms and standalone geometry use actual collider shapes.
		for body in root.get_children():
			if body is StaticBody2D:
				for child in body.get_children():
					if child is CollisionShape2D and child.shape is RectangleShape2D:
						var half: Vector2 = child.shape.size * 0.5
						result.append(PackedVector2Array([child.to_global(-half), child.to_global(Vector2(half.x,-half.y)), child.to_global(half), child.to_global(Vector2(-half.x,half.y))]))
	return result

func draw_terrain(canvas: Node2D) -> void:
	for mark in marks:
		for fragment in mark.fragments:
			var polygon := PackedVector2Array()
			for vertex in fragment:
				polygon.append(canvas.to_local(to_global(vertex)))
			# Thin edge plus translucent soaking keeps the relief texture visible.
			canvas.draw_colored_polygon(polygon, Color(INK, 0.7))
