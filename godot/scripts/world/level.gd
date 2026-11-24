class_name Level
extends Node2D

## Уровень как сцена + данные.
## Гибридный фон: параллакс-небо с затмением и холмами + запечённые полосы по 1280 px
## с декором 4 зон + живые свечи, трава и пыль в видимой области камеры.

signal cleared
signal checkpoint_reached(id: String, pos: Vector2)
signal enemy_died(id: String)
signal trigger_reached(id: String, spec: Dictionary)
signal prop_collected(display_name_key: String)

const DEFAULT_DATA := "res://content/levels/arena_01.json"
## Временные ID не попадают в сохранение: дети деления, призывы босса, debug-спавн.
const TEMP_ID_PREFIXES := ["split_", "summon_", "spawn_"]
const LevelDecor := preload("res://scripts/world/level_decor.gd")
const BAKE_DISTANCE := 2600.0

const PAPER := Color("#f1e6d0")

@export_file("*.json") var data_path := DEFAULT_DATA

var spawn_point := Vector2.ZERO
var bounds := Rect2(0.0, 0.0, 2560.0, 720.0)
var enemies: Array = []
var checkpoints: Array = []
var checkpoint_nodes: Dictionary = {}
var killed_ids: Array[String] = []
var collected_props: Array[String] = []
var _split_serial := 0
var _summon_serial := 0
var triggers: Array = []
var fired_triggers: Array[String] = []
var boss: Keeper
var tile_layer: TileMapLayer
var one_way_cells := 0
var _one_way_tiles: Dictionary[Vector2i, Vector2i] = {}
var enemies_enabled := true
var _platforms_enabled := true
var _background_enabled := true
var hitstop := 0.0
var data: Dictionary = {}
## Состояние мира из автосейва: какой чекпоинт пройден и кого уже нет.
## Задаётся до add_child(), потому что _ready() сразу строит уровень.
var world_state: Dictionary = {}

var _player: Player
var _backdrop: _BackdropLayer
var _strips_root: Node2D
var _fallback: _FallbackLayer
var _dynamic: _DynamicDecorLayer
var _platform_art: _PlatformLayer
var _baked_strips: Dictionary = {}
var _bake_range := Vector2i(-1, -1)
var _baking := false
var _candles: Array = []
var _grass: Array = []
var _dust: Array = []


class _BackdropLayer extends Node2D:
	var owner_level: Level
	var cam_x := 640.0
	var cam_y := 360.0
	var vp_w := 1280.0
	var vp_h := 720.0
	var paper: Texture2D

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_2d()
		var vp := get_viewport_rect().size
		var center := cam.get_screen_center_position() if cam != null else Vector2(640.0, 360.0)
		var width := maxf(1280.0, vp.x)
		var height := maxf(720.0, vp.y)
		if center.x != cam_x or center.y != cam_y or width != vp_w or height != vp_h or paper != InkR.tex_paper:
			cam_x = center.x
			cam_y = center.y
			vp_w = width
			vp_h = height
			paper = InkR.tex_paper
			queue_redraw()

	func _draw() -> void:
		if is_instance_valid(owner_level):
			LevelDecor.draw_backdrop(self, Vector2(cam_x, cam_y), Vector2(vp_w, vp_h), owner_level.bounds)


class _FallbackLayer extends Node2D:
	var owner_level: Level
	var _last_strips := Vector2i(-1, -1)

	func _process(_delta: float) -> void:
		if is_instance_valid(owner_level):
			visible = owner_level._background_enabled and not owner_level._all_strips_baked()
			var strips := _visible_strips()
			if visible and strips != _last_strips:
				_last_strips = strips
				queue_redraw()

	func _visible_strips() -> Vector2i:
		var cam := get_viewport().get_camera_2d()
		var cam_x := cam.get_screen_center_position().x if cam != null else 640.0
		var half_w := maxf(640.0, get_viewport_rect().size.x * 0.5) + 120.0
		return Vector2i(
			maxi(0, ceili((cam_x - half_w) / LevelDecor.STRIP_W) - 1),
			mini(owner_level._strip_count() - 1, floori((cam_x + half_w) / LevelDecor.STRIP_W)))

	func _draw() -> void:
		if not is_instance_valid(owner_level):
			return
		var strips := _visible_strips()
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		for i in range(strips.x, strips.y + 1):
			if owner_level._baked_strips.has(i):
				continue
			var sx0 := float(i) * LevelDecor.STRIP_W
			var sx1 := sx0 + LevelDecor.STRIP_W
			for spec in owner_level.data.get("solids", []):
				var r := owner_level._rect_of(spec)
				if r.end.x >= sx0 - 32.0 and r.position.x <= sx1 + 32.0:
					LevelDecor.draw_surface(r, false, owner_level.bounds, owner_level.data.get("solids", []))


class _PlatformLayer extends Node2D:
	var owner_level: Level

	func _draw() -> void:
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(0.0)
		for spec in owner_level.data.get("one_ways", []):
			LevelDecor.draw_surface(owner_level._rect_of(spec), true, owner_level.bounds)


class _DynamicDecorLayer extends Node2D:
	var owner_level: Level
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(owner_level):
			return
		var cam := get_viewport().get_camera_2d()
		var cam_x := cam.get_screen_center_position().x if cam != null else 640.0
		var half_w := maxf(640.0, get_viewport_rect().size.x * 0.5) + 140.0
		var vx0 := cam_x - half_w
		var vx1 := cam_x + half_w
		InkR.init_static()
		InkR.set_canvas(self)
		InkR.begin_frame(t)
		for c in owner_level._candles:
			if c.x >= vx0 and c.x <= vx1:
				LevelDecor.draw_candle_dynamic(c.x, c.y, t, c.s)
		for g in owner_level._grass:
			if g.x >= vx0 and g.x <= vx1:
				LevelDecor.draw_grass_tuft(g.x, g.y, t, g.seed)
		if InkFx.particles_enabled:
			for d in owner_level._dust:
				if d.x >= vx0 and d.x <= vx1:
					var yy: float = d.y + sin(t * d.sp + d.ph) * 14.0
					InkR.fill_circle_color(d.x + sin(t * 0.25 + d.ph) * 6.0, yy, d.r, InkR.INK, d.a)


func _ready() -> void:
	if data.is_empty():
		_load_data()
	_build()
	_build_visual_layers()
	queue_redraw()


func _load_data() -> void:
	data = LevelData.read_json(data_path)
	if data.is_empty():
		push_error("level: не читается JSON " + data_path)


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
	_build_props()

	var index := 0
	for spec in data.get("placements", []):
		_add_enemy(spec, index)
		index += 1

	# Старый формат: type вместо def_id. Оставлен для чтения прежних уровней.
	for spec in data.get("enemies", []):
		_add_enemy(spec, index)
		index += 1


func _build_props() -> void:
	for id in world_state.get("props", []):
		collected_props.append(str(id))
	for spec in data.get("props", []):
		var id := str(spec.get("id", ""))
		if id.is_empty() or collected_props.has(id):
			continue
		var definition := PDB.get_def(StringName(spec.get("def_id", "")))
		if definition == null:
			continue
		var instance := definition.scene.instantiate()
		if not instance is SoulPickup:
			instance.free()
			continue
		var pickup := instance as SoulPickup
		pickup.definition = definition
		pickup.placement_id = id
		pickup.position = Vector2(float(spec.x), float(spec.y))
		pickup.collected.connect(_on_prop_collected)
		add_child(pickup)


func _on_prop_collected(id: String, display_name_key: String) -> void:
	if not collected_props.has(id):
		collected_props.append(id)
		prop_collected.emit(display_name_key)


func _build_visual_layers() -> void:
	_backdrop = _BackdropLayer.new()
	_backdrop.name = "Backdrop"
	_backdrop.z_index = -10
	_backdrop.owner_level = self
	add_child(_backdrop)

	_strips_root = Node2D.new()
	_strips_root.name = "Strips"
	_strips_root.z_index = -5
	add_child(_strips_root)

	_fallback = _FallbackLayer.new()
	_fallback.name = "StripFallback"
	_fallback.z_index = -4
	_fallback.owner_level = self
	add_child(_fallback)
	_platform_art = _PlatformLayer.new()
	_platform_art.name = "PlatformArt"
	_platform_art.owner_level = self
	_platform_art.z_index = -3
	add_child(_platform_art)

	_populate_dynamic_decor()
	_dynamic = _DynamicDecorLayer.new()
	_dynamic.name = "DynamicDecor"
	_dynamic.z_index = -2
	_dynamic.owner_level = self
	add_child(_dynamic)

	var has_renderer := DisplayServer.get_name() != "headless"
	set_process(has_renderer)
	if has_renderer:
		_bake_strips_async()


func _populate_dynamic_decor() -> void:
	_candles.clear()
	_grass.clear()
	_dust.clear()
	var lid := str(data.get("landmarks", data.get("id", "ch01_hall")))
	if lid == "ch01_hall":
		for x in [92.0, 520.0, 1320.0, 2370.0, 3210.0, 3320.0, 3810.0, 4480.0, 5720.0, 6830.0, 7160.0, 8400.0, 9390.0, 10280.0, 11350.0, 12780.0, 13910.0]:
			var feet := LevelDecor._floor_y_at(x, data)
			_candles.append({"x": x, "y": feet, "s": 0.8 if x < 11264.0 else 1.0})
	else:
		_candles.append({"x": 92.0, "y": 576.0, "s": 1.0})
		_candles.append({"x": 1240.0, "y": 576.0, "s": 0.9})
		_candles.append({"x": 2360.0, "y": 512.0, "s": 0.8})

	var gi := 0
	for spec in data.get("solids", []):
		var r := _rect_of(spec)
		if r.position.x < 2560.0 and r.size.y >= 96.0 and r.size.x >= 400.0:
			var gx := r.position.x + 90.0
			while gx < r.end.x - 90.0:
				_grass.append({"x": gx, "y": r.position.y, "seed": gi})
				gx += 173.0 + float((gi * 97) % 229)
				gi += 1

	var seed_v := 713
	var rnd := func() -> float:
		seed_v = int((seed_v * 16807) % 2147483647)
		return float(seed_v - 1) / 2147483646.0
	var count := int(bounds.size.x / 160.0)
	for i in count:
		_dust.append({
			"x": 40.0 + rnd.call() * (bounds.size.x - 80.0),
			"y": 90.0 + rnd.call() * 440.0,
			"r": 1.2 + rnd.call() * 2.4,
			"a": 0.05 + rnd.call() * 0.11,
			"sp": 0.25 + rnd.call() * 0.55,
			"ph": rnd.call() * 10.0,
		})


func _strip_count() -> int:
	return maxi(1, int(ceil(bounds.size.x / LevelDecor.STRIP_W)))


func _all_strips_baked() -> bool:
	return _baked_strips.size() >= _strip_count()


func _bake_focus_x() -> float:
	if is_instance_valid(_player):
		return _player.global_position.x
	var camera := get_viewport().get_camera_2d()
	return camera.get_screen_center_position().x if camera != null else spawn_point.x


func _process(_delta: float) -> void:
	if _baking or not is_instance_valid(_strips_root) or _all_strips_baked():
		return
	var focus := _bake_focus_x()
	var strips := Vector2i(
		ceili((focus - BAKE_DISTANCE) / LevelDecor.STRIP_W - 0.5),
		floori((focus + BAKE_DISTANCE) / LevelDecor.STRIP_W - 0.5))
	if strips != _bake_range:
		_bake_range = strips
		_bake_strips_async()


func _bake_strips_async() -> void:
	_baking = true
	var total := _strip_count()
	var lid := String(data.get("id", "ch01_hall"))
	while is_instance_valid(self) and is_inside_tree():
		var focus_x := _bake_focus_x()
		var best := -1
		var best_dist := BAKE_DISTANCE
		for i in total:
			if _baked_strips.has(i):
				continue
			var cx := (float(i) + 0.5) * LevelDecor.STRIP_W
			var d := absf(cx - focus_x)
			if d <= best_dist:
				best_dist = d
				best = i
		if best < 0:
			break
		var strip_i := best
		# Keep the frozen render target as the sprite texture. Reading it back
		# and re-uploading it synchronously stalls the first frames in a new area.
		var sub := SubViewport.new()
		sub.size = Vector2i(int(LevelDecor.STRIP_W), maxi(int(LevelDecor.STRIP_H), ceili(bounds.end.y)))
		sub.disable_3d = true
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		var node := InkBakeNode.new()
		node.fn = func(cv: CanvasItem):
			InkR.init_static()
			InkR.set_canvas(cv)
			InkR.begin_frame(0.0)
			InkR.t_translate(-float(strip_i) * LevelDecor.STRIP_W, 0.0)
			LevelDecor.draw_strip_decor(strip_i, lid, data, bounds)
			InkR.set_canvas(null)
		sub.add_child(node)
		add_child(sub)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(self) or not is_instance_valid(sub):
			break
		node.queue_free()
		var sp := Sprite2D.new()
		sp.name = "Strip_%d" % strip_i
		sp.centered = false
		sp.position = Vector2(float(strip_i) * LevelDecor.STRIP_W, 0.0)
		sp.texture = sub.get_texture()
		_strips_root.add_child(sp)
		_baked_strips[strip_i] = sp
		_fallback.queue_redraw()
	_baking = false


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


func is_frozen() -> bool:
	return hitstop > 0.0


static func move_ground_enemy(enemy: CharacterBody2D) -> void:
	var room := enemy.get_parent() as Level
	# The chapter's floor is a static TileMapLayer. Settled bodies still
	# evaluate attacks and targeting, but have no motion to submit.
	if room != null and room.tile_layer != null and enemy.is_on_floor() \
		and enemy.velocity == Vector2.ZERO and enemy.get_platform_velocity() == Vector2.ZERO:
		return
	enemy.move_and_slide()


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
## берутся из одного тайлсета.
func _build_tiles() -> void:
	tile_layer = TileMapLayer.new()
	tile_layer.name = "Tiles"
	tile_layer.self_modulate.a = 0.0
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
			var cell := Vector2i(tx, ty)
			var atlas := Vector2i(InkTileset.ONE_WAY, 0) if one_way else Vector2i(
				InkTileset.SOLID_TOP if ty == y0 else InkTileset.SOLID, 0)
			if one_way:
				if not _one_way_tiles.has(cell):
					_one_way_tiles[cell] = tile_layer.get_cell_atlas_coords(cell)
				one_way_cells += 1
			tile_layer.set_cell(cell, 0, atlas)


func set_debug_environment(show_enemies: bool, show_platforms: bool, show_background: bool) -> void:
	if enemies_enabled != show_enemies:
		enemies_enabled = show_enemies
		for child in get_children():
			if child in enemies or child is EnemyProjectile:
				child.visible = show_enemies
				child.process_mode = Node.PROCESS_MODE_INHERIT if show_enemies else Node.PROCESS_MODE_DISABLED
	if _platforms_enabled != show_platforms:
		_platforms_enabled = show_platforms
		for cell in _one_way_tiles:
			var atlas := Vector2i(InkTileset.ONE_WAY, 0) if show_platforms else _one_way_tiles[cell]
			if atlas == Vector2i(-1, -1):
				tile_layer.erase_cell(cell)
			else:
				tile_layer.set_cell(cell, 0, atlas)
	_background_enabled = show_background
	_backdrop.visible = show_background
	_dynamic.visible = show_background
	_dynamic.set_process(show_background)
	_dynamic.queue_redraw()
	_strips_root.visible = show_background
	_platform_art.visible = show_platforms
	_fallback.visible = _strips_root.visible and not _all_strips_baked()
	queue_redraw()


func _draw() -> void:
	if _background_enabled:
		return
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(0.0)
	var solids: Array = data.get("solids", [])
	for solid in solids:
		LevelDecor.draw_surface(_rect_of(solid), false, bounds, solids)


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
## Призванная клякса не делится: один призыв остаётся одним врагом.
func _on_boss_summon(pos: Vector2, def_id: StringName, count: int) -> void:
	for i in count:
		_summon_serial += 1
		_add_enemy({
			"id": "summon_%d" % _summon_serial,
			"def_id": String(def_id),
			"x": pos.x,
			"y": pos.y,
			"overrides": {"splits": false},
		})


## Точка входа для debug-консоли: создать врага по ID карточки.
func spawn_enemy(kind: String, pos: Vector2) -> bool:
	if not enemies_enabled:
		return false
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


## Временные ID не попадают в сохранение: это дети деления, призывы босса
## и отладочный спавн. Постоянные расстановки уровня приходят из JSON.
func is_temporary_id(id: String) -> bool:
	for prefix in TEMP_ID_PREFIXES:
		if id.begins_with(prefix):
			return true
	return false


func _on_enemy_died(node: Node) -> void:
	var placement_id := String(node.get_meta("placement_id", ""))
	if not placement_id.is_empty() and not is_temporary_id(placement_id) \
		and not killed_ids.has(placement_id):
		killed_ids.append(placement_id)
	enemies.erase(node)
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
