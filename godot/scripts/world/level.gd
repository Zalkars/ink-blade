class_name Level
extends Node2D

## Уровень как сцена + данные, а не массив в коде (см. docs/tech-brief.md).
## Пока данные простые: прямоугольные платформы, точки спавна врагов, границы.
## Следующий шаг — TileMapLayer вместо прямоугольников, схема уже под это написана.

signal cleared
signal checkpoint_reached(id: String, pos: Vector2)
signal enemy_died(id: String)
signal trigger_reached(id: String, spec: Dictionary)

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
var checkpoints: Array = []
var checkpoint_nodes: Dictionary = {}
var killed_ids: Array[String] = []
var _split_serial := 0
var _summon_serial := 0
var triggers: Array = []
var fired_triggers: Array[String] = []
var boss: Keeper
var tile_layer: TileMapLayer
var one_way_cells := 0
var data: Dictionary = {}
## Состояние мира из автосейва: какой чекпоинт пройден и кого уже нет.
## Задаётся до add_child(), потому что _ready() сразу строит уровень.
var world_state: Dictionary = {}

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

	for id in world_state.get("killed", []):
		killed_ids.append(String(id))

	_build_checkpoints()
	_build_tiles()
	_build_triggers()

	var index := 0
	for spec in data.get("placements", []):
		_add_enemy(spec, index)
		index += 1

	# Старый формат: type вместо def_id. Оставлен для чтения прежних уровней.
	for spec in data.get("enemies", []):
		_add_enemy(spec, index)
		index += 1


## Триггеры — точки сюжета. Срабатывают один раз, когда игрок доходит до x.
## Сам разговор запускает game_flow: уровень не знает про UI.
func _build_triggers() -> void:
	for spec in data.get("triggers", []):
		var id := String(spec.get("id", ""))
		if id.is_empty():
			continue
		triggers.append(spec)
		if world_state.get("triggers", []).has(id):
			fired_triggers.append(id)
		if String(spec.get("npc", "")) == "scribe":
			var npc := Scribe.new()
			npc.name = "Scribe_" + id
			npc.position = Vector2(float(spec.get("x", 0)), float(spec.get("y", 600)))
			add_child(npc)


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for spec in triggers:
		var id := String(spec.get("id", ""))
		if fired_triggers.has(id):
			continue
		if _player.global_position.x >= float(spec.get("x", 0)):
			fired_triggers.append(id)
			trigger_reached.emit(id, spec)


## Создаёт метки чекпоинтов и переносит точку входа на пройденную.
func _build_checkpoints() -> void:
	var saved_id := String(world_state.get("checkpoint", ""))
	var list: Array = data.get("checkpoints", [])
	for i in list.size():
		var c: Dictionary = list[i]
		var cp_id := String(c.get("id", "cp_%d" % i))
		var feet := Vector2(float(c.get("x", 0)), float(c.get("y", 0)))
		var node := Checkpoint.new()
		node.name = "Checkpoint_" + cp_id
		node.setup(cp_id, feet)
		node.reached.connect(_on_checkpoint_reached)
		add_child(node)
		checkpoints.append(node)
		checkpoint_nodes[cp_id] = node
		if cp_id == saved_id:
			node.activate()
			spawn_point = feet - Vector2(0.0, 23.0)


func _rect_of(d: Dictionary) -> Rect2:
	return Rect2(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("w", 0)), float(d.get("h", 0)))


## Геометрия уровня растеризуется в TileMapLayer: коллизия и картинка
## берутся из одного тайлсета. Прямоугольники в JSON — временный формат
## авторинга; будущий редактор будет писать клетки напрямую.
func _build_tiles() -> void:
	tile_layer = TileMapLayer.new()
	tile_layer.name = "Tiles"
	tile_layer.tile_set = InkTileset.build()
	add_child(tile_layer)

	for solid in data.get("solids", []):
		_paint_rect(_rect_of(solid), false)

	for plat in data.get("one_ways", []):
		_paint_rect(_rect_of(plat), true)


func _paint_rect(rect: Rect2, one_way: bool) -> void:
	var tile := float(InkTileset.SIZE)
	var x0 := int(round(rect.position.x / tile))
	var y0 := int(round(rect.position.y / tile))
	var x1 := int(round(rect.end.x / tile))
	var y1 := int(round(rect.end.y / tile))
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			var atlas := Vector2i(InkTileset.ONE_WAY, 0) if one_way else Vector2i(
				InkTileset.SOLID_TOP if ty == y0 else InkTileset.SOLID, 0)
			tile_layer.set_cell(Vector2i(tx, ty), 0, atlas)
			if one_way:
				one_way_cells += 1


func _add_enemy(spec: Dictionary, index: int = 0) -> void:
	var placement_id := String(spec.get("id", "auto_%d" % index))
	if killed_ids.has(placement_id):
		return
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
	node.set_meta("placement_id", placement_id)
	if node is Node2D:
		(node as Node2D).position = Vector2(float(spec.get("x", 0)), float(spec.get("y", 600))) - Vector2(0.0, 20.0)
	if "target" in node:
		node.set("target", _player)
	node.add_to_group("enemies")
	if node.has_signal("died"):
		node.died.connect(_on_enemy_died)
	# Клякса просит уровень создать детей ДО сигнала смерти,
	# иначе «зал очищен» сработает раньше, чем появятся малые.
	if node.has_signal("split"):
		node.split.connect(_on_enemy_split)
	if node is Keeper:
		boss = node
		if node.has_signal("summon"):
			node.summon.connect(_on_boss_summon)
	add_child(node)
	enemies.append(node)


## Делит кляксу на двух малых. Дети — обычные враги уровня: их можно бить,
## они попадают в группу enemies и учитываются в enemy_count().
func _on_enemy_split(pos: Vector2, def_id: StringName) -> void:
	for i in 2:
		_split_serial += 1
		var offset := -12.0 if i == 0 else 12.0
		_add_enemy({
			"id": "split_%d" % _split_serial,
			"def_id": String(def_id),
			"x": pos.x + offset,
			"y": pos.y + 20.0,
			"overrides": {"generation": 1},
		})


## Босс призывает клякс. Они обычные враги уровня и не попадают в сохранение:
## после смерти игрока бой начинается заново с полным набором.
func _on_boss_summon(pos: Vector2, def_id: StringName, count: int) -> void:
	for i in count:
		_summon_serial += 1
		_add_enemy({
			"id": "summon_%d" % _summon_serial,
			"def_id": String(def_id),
			"x": pos.x,
			"y": pos.y,
		})


## Точка входа для debug-консоли: создать врага по ID карточки.
func spawn_enemy(kind: String, pos: Vector2) -> bool:
	var def_id := kind
	if not def_id.contains("."):
		def_id = "enemy." + def_id
	if not DB.has(StringName(def_id)):
		return false
	_add_enemy({
		"id": "spawn_%d" % Time.get_ticks_usec(),
		"def_id": def_id,
		"x": pos.x,
		"y": pos.y,
	})
	return true


func bind_player(p: Player) -> void:
	_player = p
	for e in enemies:
		if "target" in e:
			e.set("target", p)


func enemy_count() -> int:
	return enemies.size()


func checkpoint_count() -> int:
	return checkpoints.size()


## Позиция центра тела на чекпоинте: по ней игрок появляется после смерти.
func checkpoint_position(id: String) -> Vector2:
	var node = checkpoint_nodes.get(id, null)
	if node == null:
		return Vector2.ZERO
	return node.position + Vector2(0.0, Checkpoint.FOOT_OFFSET) - Vector2(0.0, 23.0)


func activate_checkpoint(id: String) -> void:
	var node = checkpoint_nodes.get(id, null)
	if node != null:
		node.activate()


## Куда ставить игрока при старте: точка входа или пройденный чекпоинт.
func resume_position() -> Vector2:
	return spawn_point


func _on_checkpoint_reached(id: String, pos: Vector2) -> void:
	checkpoint_reached.emit(id, pos)


func _on_enemy_died(node: Node) -> void:
	var placement_id := String(node.get_meta("placement_id", ""))
	if not placement_id.is_empty() and not killed_ids.has(placement_id):
		killed_ids.append(placement_id)
	enemies.erase(node)
	# Смерть босса заканчивает бой: призванные кляксы не должны держать зал.
	# Остальные расстановки уровня остаются на своих местах.
	if node is Keeper:
		for e in enemies.duplicate():
			if is_instance_valid(e) and String(e.get_meta("placement_id", "")).begins_with("summon_"):
				enemies.erase(e)
				e.queue_free()
	enemy_died.emit(placement_id)
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
