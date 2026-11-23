class_name CombatFx
extends Node2D

## Cosmetic ink belongs to the level. Saved polygons never become colliders.
signal persistent_marks_changed
const INK := Color("#17130f")
const RED := Color("#9c1f24")
const MAX_MARKS := 1024
const MAX_PARTICLES := 240
const MAX_FRAGMENTS := 16
const MAX_VERTICES := 96
const STAIN_STRIP_WIDTH := 512.0
static var _base64_regex := RegEx.create_from_string("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
var marks: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var _stains: Node2D
var _stain_strips: Dictionary = {}
var _wet_marks: Array[Dictionary] = []
var _dirty := false
## Растёт при каждом изменении пятен: автосейв пропускает неизменную картинку.
var revision := 0
## Effect budgets use simulation time, so a stalled frame cannot schedule a burst storm.
var mobile_quality := OS.has_feature("mobile")
var _clock := 0.0
var _ray_cursor := 0
var _droplet_ray := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, 9)
var _dry_accum := 0.0
var _burst_times: Dictionary = {}
var _coverage: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _terrain_polys: Array[PackedVector2Array] = []
var _terrain_grid: Dictionary = {}
var _terrain_ready := false
var rays_last_tick := 0
var deposits_last_tick := 0

func _ready() -> void:
	_rng.randomize()

class StainStrip extends Node2D:
	var marks: Array[Dictionary] = []

	func _draw() -> void:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for mark in marks:
			var tint := Color(INK, 0.66 + float(mark.wet) * 0.13)
			for i in mark.fragments.size():
				var polygon: PackedVector2Array = mark.fragments[i]
				var offset := points.size()
				points.append_array(polygon)
				for vertex in polygon:
					colors.append(tint)
				for index in mark.triangles[i]:
					indices.append(offset + index)
		if not indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)

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
		var stains := Node2D.new()
		stains.name = "CombatStains"
		stains.z_index = -1
		root.add_child(stains)
		fx._stains = stains
	return fx

static func burst(actor: Node2D, point: Vector2, direction: Vector2, color := RED, count := 12) -> void:
	if not InkFx.particles_enabled:
		return
	var fx := layer(actor)
	var cell := Vector2i((point / 32.0).floor())
	var key := Vector3i(cell.x, cell.y, color.to_rgba32())
	if fx._clock - float(fx._burst_times.get(key, -100.0)) < (0.11 if fx.mobile_quality else 0.075):
		return
	if fx._burst_times.size() > 128:
		fx._burst_times.clear()
	fx._burst_times[key] = fx._clock
	var limit := 96 if fx.mobile_quality else MAX_PARTICLES
	var amount := maxi(3, int(ceil(count * (0.65 if fx.mobile_quality else 1.0))))
	# Pale wall chips and healing sparks are light, not physical black ink.
	var ink := color.r < 0.75 and color.g < 0.5
	var origin := fx.to_local(point)
	var heading := direction.normalized()
	for i in mini(amount, maxi(0, limit - fx.particles.size())):
		var v := heading.rotated(fx._rng.randf_range(-1.35, 1.35)) * fx._rng.randf_range(95, 330)
		fx.particles.append({"p": origin, "trace": origin, "v": v,
			"life": fx._rng.randf_range(0.65, 1.15), "size": fx._rng.randf_range(1.5, 5.5), "color": color,
			"deposit": ink and i % (4 if fx.mobile_quality else 3) == 0})
	fx.queue_redraw()

static func surface(actor: Node2D, point: Vector2, normal: Vector2, strength := 1.0) -> void:
	var fx := layer(actor)
	fx._deposit(point, normal, clampf(strength, 0.1, 3.0))
	burst(actor, point + normal * 2.0, normal, INK, 24)

func _deposit(point: Vector2, normal: Vector2, strength: float) -> void:
	var cell := Vector2i((to_local(point) / 8.0).floor())
	var key := Vector4i(cell.x, cell.y, int(round(normal.x)), int(round(normal.y)))
	if float(_coverage.get(key, 0.0)) >= strength:
		return
	var footprint := PackedVector2Array()
	var tangent := normal.orthogonal()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		var edge := 1.0 + sin(angle * 5.0 + point.x) * 0.16 + cos(angle * 9.0) * 0.09
		footprint.append(point - normal * 11.0 * strength + (tangent * cos(angle) * 34.0 - normal * sin(angle) * 24.0) * strength * edge)
	var area := Rect2(point - Vector2.ONE * 72.0 * strength, Vector2.ONE * 144.0 * strength)
	var fragments: Array[PackedVector2Array] = []
	for terrain in terrain_polygons(self, area):
		for clipped in Geometry2D.intersect_polygons(footprint, terrain):
			var local := PackedVector2Array()
			for vertex in clipped:
				var v := to_local(vertex)
				local.append(Vector2(snappedf(v.x, 0.01), snappedf(v.y, 0.01)))
			if local.size() >= 3 and not Geometry2D.triangulate_polygon(local).is_empty():
				fragments.append(local)
	if fragments.is_empty():
		return
	if _coverage.size() > MAX_MARKS * 2:
		_coverage.clear()
	_coverage[key] = strength
	var mark := _mark(fragments, 1.0)
	marks.append(mark)
	_wet_marks.append(mark)
	_add_to_strip(mark)
	deposits_last_tick += 1
	if marks.size() > MAX_MARKS:
		var oldest: Dictionary = marks.pop_front()
		_wet_marks.erase(oldest)
		var index := _strip_index(oldest)
		var strip: StainStrip = _stain_strips[index]
		strip.marks.erase(oldest)
		if strip.marks.is_empty():
			_stain_strips.erase(index)
			_stains.remove_child(strip)
			strip.queue_free()
		else:
			strip.queue_redraw()
	revision += 1
	_dirty = true

static func floor_mark(actor: Node2D, point: Vector2, strength := 1.0) -> void:
	var ray := PhysicsRayQueryParameters2D.create(point - Vector2(0, 8), point + Vector2(0, 90), 9)
	var hit := actor.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		surface(actor, hit.position, hit.normal, strength)

func _physics_process(delta: float) -> void:
	var root := get_parent()
	if root is Level and root.is_frozen():
		return
	_clock += delta
	rays_last_tick = 0
	deposits_last_tick = 0
	var had_particles := not particles.is_empty()
	if not _wet_marks.is_empty():
		# Retain the terrain commands while the camera moves. Only strips
		# with drying ink need fresh vertices and colours at 20 Hz.
		_dry_accum += delta
		if _dry_accum >= 0.05:
			for i in range(_wet_marks.size() - 1, -1, -1):
				var mark := _wet_marks[i]
				mark.wet = maxf(0.0, mark.wet - _dry_accum)
				_stain_strips[_strip_index(mark)].queue_redraw()
				if mark.wet <= 0.0:
					_wet_marks.remove_at(i)
			_dry_accum = 0.0
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0.0:
			particles.remove_at(i)
			continue
		p.v.y += 720.0 * delta
		p.p += p.v * delta
	# Round-robin sweeps preserve the segment since the last sample. A small fixed
	# ray/deposit budget prevents simultaneous landings doing unbounded clipping.
	var budget := 6 if mobile_quality else 12
	var checked := 0
	var index := _ray_cursor % maxi(1, particles.size())
	var space: PhysicsDirectSpaceState2D
	var transform_to_world := global_transform
	while checked < particles.size() and rays_last_tick < budget and not particles.is_empty():
		var p: Dictionary = particles[index]
		checked += 1
		if p.deposit:
			if space == null:
				space = get_world_2d().direct_space_state
			_droplet_ray.from = transform_to_world * p.get("trace", p.p)
			_droplet_ray.to = transform_to_world * p.p
			var hit := space.intersect_ray(_droplet_ray)
			rays_last_tick += 1
			p.trace = p.p
			if not hit.is_empty():
				if deposits_last_tick < (2 if mobile_quality else 4):
					_deposit(hit.position, hit.normal, float(p.size) / 18.0)
				particles.remove_at(index)
				if particles.is_empty():
					break
				index %= particles.size()
				continue
		index = (index + 1) % particles.size()
	_ray_cursor = index

	if had_particles:
		queue_redraw()
	if _dirty:
		_dirty = false
		persistent_marks_changed.emit()

func _redraw_stains() -> void:
	for strip in _stain_strips.values():
		_stains.remove_child(strip)
		strip.queue_free()
	_stain_strips.clear()
	for mark in marks:
		_add_to_strip(mark)

func _strip_index(mark: Dictionary) -> int:
	return floori(mark.bounds.get_center().x / STAIN_STRIP_WIDTH)

func _add_to_strip(mark: Dictionary) -> void:
	var index := _strip_index(mark)
	if not _stain_strips.has(index):
		var new_strip := StainStrip.new()
		_stains.add_child(new_strip)
		_stain_strips[index] = new_strip
	var strip: StainStrip = _stain_strips[index]
	strip.marks.append(mark)
	strip.queue_redraw()

func _draw() -> void:
	var view := (get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()).grow(48.0)
	if InkFx.particle_atlas != null:
		_draw_batched_particles(view)
	else:
		_draw_unbaked_particles(view)


func _draw_batched_particles(view: Rect2) -> void:
	var batch := InkFx.ParticleBatch.new()
	for p in particles:
		if not view.has_point(p.p):
			continue
		var color := Color(p.color, minf(1.0, p.life * 4.0))
		if not mobile_quality:
			batch.trail(p.p - p.v * 0.026, p.p, p.size, color)
		batch.disc(p.p, p.size * 0.62, color)
		if p.size > 4.0:
			batch.disc(p.p - Vector2(0.8, 1.2), 0.85, Color(0.94, 0.89, 0.78, color.a * 0.55))
	if mobile_quality:
		for p in particles:
			if view.has_point(p.p):
				var width := 2.0 if p.size < 3.0 else 4.0
				batch.trail(p.p - p.v * 0.026, p.p, width, Color(p.color, 0.7), false)
	batch.draw(self, InkFx.particle_atlas)


func _draw_unbaked_particles(view: Rect2) -> void:
	# The mobile trail batch replaces up to 96 antialiased line commands with a
	# handful of material/width groups. Droplet heads still retain their shape.
	var trails: Dictionary = {}
	for p in particles:
		if not view.has_point(p.p):
			continue
		var col := Color(p.color, minf(1.0, p.life * 4.0))
		if mobile_quality:
			var width := 2.0 if p.size < 3.0 else 4.0
			var key := Vector2i(Color(p.color).to_rgba32(), int(width))
			if not trails.has(key):
				trails[key] = {"points": PackedVector2Array(), "color": Color(p.color), "width": width}
			var batch: Dictionary = trails[key]
			batch.points.append(p.p - p.v * 0.026)
			batch.points.append(p.p)
		else:
			draw_line(p.p - p.v * 0.026, p.p, col, p.size, true)
		draw_circle(p.p, p.size * 0.62, col)
		if p.size > 4.0:
			draw_circle(p.p - Vector2(0.8, 1.2), 0.85, Color(0.94, 0.89, 0.78, col.a * 0.55))
	for batch in trails.values():
		draw_multiline(batch.points, Color(batch.color, 0.7), batch.width, false)

static func terrain_polygons(actor: Node2D, area: Rect2) -> Array[PackedVector2Array]:
	var fx := actor as CombatFx if actor is CombatFx else layer(actor)
	var root := fx.get_parent()
	var result: Array[PackedVector2Array] = []
	if root is Level and not root.data.is_empty():
		fx._ensure_terrain_cache()
		var seen: Dictionary = {}
		var begin := Vector2i((area.position / 256.0).floor())
		var end := Vector2i((area.end / 256.0).floor())
		for x in range(begin.x, end.x + 1):
			for y in range(begin.y, end.y + 1):
				for index in fx._terrain_grid.get(Vector2i(x,y), []):
					if not seen.has(index):
						seen[index] = true
						result.append(fx._terrain_polys[index])
	else:
		for body in root.get_children():
			if body is StaticBody2D:
				for child in body.get_children():
					if child is CollisionShape2D and child.shape is RectangleShape2D:
						var half: Vector2 = child.shape.size * 0.5
						result.append(PackedVector2Array([child.to_global(-half), child.to_global(Vector2(half.x, -half.y)), child.to_global(half), child.to_global(Vector2(-half.x, half.y))]))
	return result

func _ensure_terrain_cache() -> void:
	if _terrain_ready:
		return
	_terrain_ready = true
	var root := get_parent() as Level
	for spec in root.data.get("solids", []) + root.data.get("one_ways", []):
		var r: Rect2 = root._rect_of(spec)
		var tile := float(InkTileset.SIZE)
		r = Rect2((r.position / tile).round() * tile, (r.end / tile).round() * tile - (r.position / tile).round() * tile)
		var polygon := PackedVector2Array([root.to_global(r.position), root.to_global(Vector2(r.end.x,r.position.y)), root.to_global(r.end), root.to_global(Vector2(r.position.x,r.end.y))])
		var index := _terrain_polys.size()
		_terrain_polys.append(polygon)
		var bounds := _bounds([polygon])
		var begin := Vector2i((bounds.position / 256.0).floor())
		var end := Vector2i((bounds.end / 256.0).floor())
		for x in range(begin.x, end.x + 1):
			for y in range(begin.y, end.y + 1):
				var key := Vector2i(x,y)
				if not _terrain_grid.has(key):
					_terrain_grid[key] = []
				_terrain_grid[key].append(index)

static func _bounds(fragments: Array) -> Rect2:
	var result := Rect2()
	var first := true
	for polygon in fragments:
		for vertex in polygon:
			if first:
				result = Rect2(vertex, Vector2.ZERO)
				first = false
			else:
				result = result.expand(vertex)
	return result

## JSON-safe level-local polygons; v permits independent future ink migrations.
func export_state() -> Array:
	var result: Array = []
	for mark in marks:
		result.append(mark.saved)
	return result

static func _mark(fragments: Array[PackedVector2Array], wet: float) -> Dictionary:
	var encoded: Array = []
	var triangles: Array[PackedInt32Array] = []
	for polygon in fragments:
		# Cached float32 bytes keep autosave JSON away from thousands of numeric arrays.
		encoded.append(Marshalls.raw_to_base64(polygon.to_byte_array()))
		triangles.append(Geometry2D.triangulate_polygon(polygon))
	return {"fragments": fragments, "triangles": triangles, "bounds": _bounds(fragments), "wet": wet,
		"saved": {"v": 2, "fragments": encoded}}

func restore_state(data) -> void:
	marks.clear()
	particles.clear()
	queue_redraw()
	_wet_marks.clear()
	_dry_accum = 0.0
	_coverage.clear()
	_burst_times.clear()
	_dirty = false
	if not data is Array:
		_redraw_stains()
		return
	for record in data.slice(maxi(0, data.size() - MAX_MARKS)):
		if not record is Dictionary or (record.get("v", 0) != 1 and record.get("v", 0) != 2) or not record.get("fragments") is Array:
			continue
		var fragments: Array[PackedVector2Array] = []
		for points in record.fragments.slice(0, MAX_FRAGMENTS):
			var polygon := _decode_polygon(points, int(record.v))
			if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty():
				fragments.append_array(_restore_terrain_fragment(polygon))
		if not fragments.is_empty():
			marks.append(_mark(fragments, 0.0))
	revision += 1
	_redraw_stains()

## Reclip old saved decor marks and marks affected by level layout changes.
## Only physical terrain receives ink; background and columns stay clean.
func _restore_terrain_fragment(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var world := PackedVector2Array()
	for point in polygon:
		world.append(to_global(point))
	var surfaces := terrain_polygons(self, _bounds([world]).grow(0.1))
	for surface_polygon in surfaces:
		var contained := true
		for point in world:
			if not Geometry2D.is_point_in_polygon(point, surface_polygon):
				contained = false
				break
		if contained:
			return [polygon]
	var result: Array[PackedVector2Array] = []
	for surface_polygon in surfaces:
		for fragment in Geometry2D.intersect_polygons(world, surface_polygon):
			var local := PackedVector2Array()
			for point in fragment:
				local.append(to_local(point))
			if local.size() >= 3 and not Geometry2D.triangulate_polygon(local).is_empty():
				result.append(local)
	return result

static func _decode_polygon(points, version: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if version == 2:
		if not points is String or points.length() < 32 or points.length() > MAX_VERTICES * 12 or _base64_regex.search(points) == null:
			return polygon
		var raw := Marshalls.base64_to_raw(points)
		if raw.size() < 24 or raw.size() > MAX_VERTICES * 8 or raw.size() % 8 != 0:
			return polygon
		var numbers := raw.to_float32_array()
		for index in range(0, numbers.size(), 2):
			polygon.append(Vector2(numbers[index], numbers[index + 1]))
	else:
		if not points is Array or points.size() < 3 or points.size() > MAX_VERTICES:
			return polygon
		for pair in points:
			if not pair is Array or pair.size() != 2 or not (pair[0] is float or pair[0] is int) or not (pair[1] is float or pair[1] is int):
				return PackedVector2Array()
			polygon.append(Vector2(float(pair[0]), float(pair[1])))
	for v in polygon:
		if not v.is_finite() or absf(v.x) > 100000.0 or absf(v.y) > 100000.0:
			return PackedVector2Array()
	return polygon
