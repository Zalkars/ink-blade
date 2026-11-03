class_name InkTileset
extends RefCounted

## Собирает TileSet из одного атласа. Держим его кодом, а не .tres:
## физика тайлов задаётся в одном месте и не разъезжается с картинкой.
## Атлас рисует tools/build_tileset.gd.

const TEXTURE := preload("res://assets/tiles/ink_tiles.png")
const SIZE := 32

const SOLID := 0
const SOLID_TOP := 1
const ONE_WAY := 2


static func build() -> TileSet:
	var set := TileSet.new()
	set.tile_size = Vector2i(SIZE, SIZE)
	set.add_physics_layer()
	set.set_physics_layer_collision_layer(0, 1)
	set.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = TEXTURE
	source.texture_region_size = Vector2i(SIZE, SIZE)
	set.add_source(source, 0)

	for tile in [SOLID, SOLID_TOP, ONE_WAY]:
		source.create_tile(Vector2i(tile, 0))
		var data := source.get_tile_data(Vector2i(tile, 0), 0)
		data.add_collision_polygon(0)
		# Квадрат тайла. Начало координат — центр тайла.
		var half := float(SIZE) * 0.5
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half),
		]))
		if tile == ONE_WAY:
			data.set_collision_polygon_one_way(0, 0, true)

	return set
