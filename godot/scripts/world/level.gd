class_name Level
extends Node2D

## Уровень как сцена + данные, а не массив в коде (см. docs/tech-brief.md).
## Пока данные простые: прямоугольные платформы, точки спавна врагов, границы.
## Следующий шаг — TileMapLayer вместо прямоугольников, схема уже под это написана.

signal cleared

const DEFAULT_DATA := "res://content/levels/arena_01.json"

const PAPER := Color("#f1e6d0")
const RIDGE_FAR := Color("#d5c8b1")
const RIDGE_MID := Color("#b6a891")
const RIDGE_NEAR := Color("#7d7261")
const INK_DARK := Color("#17130f")
const INK_EDGE := Color("#4a4136")
const RED := Color("#9c1f24")

@export_file("*.json") var data_path := DEFAULT_DATA

var spawn_point := Vector2.ZERO
var bounds := Rect2(0.0, 0.0, 2560.0, 720.0)
var enemies: Array = []
var data: Dictionary = {}

var _player: Player


func _ready() -> void:
	_load_data()
	_build()
	queue_redraw()


func _load_data() -> void:
	var text := FileAccess.get_file_as_string(data_path)
	if text.is_empty():
		push_error("level: не читается " + data_path)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("level: плохой JSON в " + data_path)
		return
	data = parsed


func _build() -> void:
	if data.has("bounds"):
		var b: Dictionary = data["bounds"]
		bounds = Rect2(float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 2560)), float(b.get("h", 720)))

	if data.has("spawn"):
		var s: Dictionary = data["spawn"]
		# Точка спавна задаётся по ногам, актёр стоит центром.
		spawn_point = Vector2(float(s.get("x", 120)), float(s.get("y", 600)) - 23.0)

	for solid in data.get("solids", []):
		_add_solid(_rect_of(solid), false)

	for plat in data.get("one_ways", []):
		_add_solid(_rect_of(plat), true)

	for spec in data.get("placements", []):
		_add_enemy(spec)

	# Старый формат: type вместо def_id. Оставлен для чтения прежних уровней.
	for spec in data.get("enemies", []):
		_add_enemy(spec)


func _rect_of(d: Dictionary) -> Rect2:
	return Rect2(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("w", 0)), float(d.get("h", 0)))


func _add_solid(rect: Rect2, one_way: bool) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.position + rect.size * 0.5
	cs.one_way_collision = one_way
	if one_way:
		cs.one_way_collision_margin = 8.0
	body.add_child(cs)
	add_child(body)
	_add_slab(rect, one_way)


func _add_slab(rect: Rect2, one_way: bool) -> void:
	var poly := Polygon2D.new()
	poly.color = INK_DARK if not one_way else INK_EDGE
	var pts := PackedVector2Array()
	var x := rect.position.x
	while x < rect.end.x:
		pts.append(Vector2(x, rect.position.y + sin(x * 0.07) * 1.4 - 1.2))
		x += 24.0
	pts.append(Vector2(rect.end.x, rect.position.y - 1.2))
	pts.append(Vector2(rect.end.x, rect.end.y))
	pts.append(Vector2(rect.position.x, rect.end.y))
	poly.polygon = pts
	add_child(poly)


func _add_enemy(spec: Dictionary) -> void:
	var def_id := String(spec.get("def_id", spec.get("type", "")))
	if def_id.is_empty():
		push_warning("level: у спавна нет def_id")
		return
	# Старый формат хранил короткий тип: grunt -> enemy.grunt.
	if not def_id.contains("."):
		def_id = "enemy." + def_id
	var overrides: Dictionary = spec.get("overrides", {})
	var node := DB.instantiate(StringName(def_id), overrides)
	if node == null:
		return
	if node is Node2D:
		(node as Node2D).position = Vector2(float(spec.get("x", 0)), float(spec.get("y", 600))) - Vector2(0.0, 20.0)
	if "target" in node:
		node.set("target", _player)
	node.add_to_group("enemies")
	if node.has_signal("died"):
		node.died.connect(_on_enemy_died)
	add_child(node)
	enemies.append(node)


## Точка входа для debug-консоли: создать врага по ID карточки.
func spawn_enemy(kind: String, pos: Vector2) -> bool:
	var def_id := kind
	if not def_id.contains("."):
		def_id = "enemy." + def_id
	if not DB.has(StringName(def_id)):
		return false
	_add_enemy({"def_id": def_id, "x": pos.x, "y": pos.y})
	return true


func bind_player(p: Player) -> void:
	_player = p
	for e in enemies:
		if "target" in e:
			e.set("target", p)


func enemy_count() -> int:
	return enemies.size()


func _on_enemy_died(node: Node) -> void:
	enemies.erase(node)
	if enemies.is_empty():
		cleared.emit()


func camera_limits() -> Dictionary:
	return {
		"left": int(bounds.position.x),
		"top": int(bounds.position.y),
		"right": int(bounds.end.x),
		"bottom": int(bounds.end.y),
	}


func _draw() -> void:
	var w := bounds.size.x
	var h := bounds.size.y
	draw_rect(Rect2(0.0, 0.0, w, h), PAPER)

	draw_circle(Vector2(w * 0.45, 165.0), 112.0, Color(RED, 0.88))
	draw_circle(Vector2(w * 0.45, 165.0), 116.0, Color(RED, 0.25))

	_ridge(h * 0.70, 86.0, RIDGE_FAR)
	_ridge(h * 0.82, 64.0, RIDGE_MID)
	_ridge(h * 0.94, 40.0, RIDGE_NEAR)

	for i in 14:
		var x := 90.0 + i * (w - 160.0) / 14.0
		var y := 120.0 + fmod(x * 0.31, 90.0)
		draw_line(Vector2(x, y), Vector2(x + 7.0, y - 4.0), Color(INK_DARK, 0.22), 1.5)
		draw_line(Vector2(x + 7.0, y - 4.0), Vector2(x + 13.0, y + 1.0), Color(INK_DARK, 0.22), 1.5)


func _ridge(base_y: float, amp: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var w := bounds.size.x
	var h := bounds.size.y
	var x := -48.0
	while x <= w + 48.0:
		var y := base_y - sin(x * 0.006) * amp - sin(x * 0.017 + 1.7) * amp * 0.35
		# Держим силуэт внутри кадра: иначе нижняя точка уходит за границу
		# и полигон самопересекается (триангуляция падает).
		pts.append(Vector2(x, clampf(y, 0.0, h - 2.0)))
		x += 32.0
	pts.append(Vector2(w + 48.0, h))
	pts.append(Vector2(-48.0, h))
	draw_colored_polygon(pts, col)
