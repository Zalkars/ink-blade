extends SceneTree

## Рисует чернильный тайлсет для TileMapLayer.
## Три тайла в ряд, 32×32:
##   0 — сплошная заливка (низ платформы),
##   1 — верх платформы с рваным чернильным краем,
##   2 — односторонняя платформа: тонкая чернильная полоса сверху.
## Запуск: Godot --headless --path godot --script res://tools/build_tileset.gd

const OUT := "res://assets/tiles/ink_tiles.png"
const TILE := 32
const COLUMNS := 3

const INK := Color("#17130f")
const INK_EDGE := Color("#4a4136")
const INK_SOFT := Color("#2b241d")


func _initialize() -> void:
	var img := Image.create(TILE * COLUMNS, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_paint_fill(img, 0)
	_paint_top(img, 1)
	_paint_one_way(img, 2)

	var err := img.save_png(OUT)
	if err != OK:
		printerr("tileset: не записался " + OUT)
		quit(1)
		return
	print("tileset: %d×%d -> %s" % [TILE * COLUMNS, TILE, OUT])
	quit(0)


## Детерминированный шум 0..1: одна и та же картинка при каждом запуске.
func _noise(x: int, y: int) -> float:
	var v := sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453
	return v - floor(v)


func _ink(x: int, y: int, base: Color) -> Color:
	var n := (_noise(x, y) - 0.5) * 0.05
	return base.lightened(n) if n > 0.0 else base.darkened(-n)


func _paint_fill(img: Image, column: int) -> void:
	for y in TILE:
		for x in TILE:
			img.set_pixel(column * TILE + x, y, _ink(x, y, INK))


func _paint_top(img: Image, column: int) -> void:
	for x in TILE:
		# Рваная кромка: высота светлой полосы гуляет от 1 до 5 пикселей.
		var edge := 2 + int(round(1.0 + sin(float(x) * 0.7) * 1.1 + sin(float(x) * 0.31 + 1.7) * 0.7))
		edge = clampi(edge, 1, 5)
		for y in TILE:
			var col := INK_EDGE if y < edge else INK
			img.set_pixel(column * TILE + x, y, _ink(x, y, col))
		# Тёмная линия под кромкой, чтобы верх читался как срез.
		if edge < TILE:
			img.set_pixel(column * TILE + x, edge, _ink(x, edge, INK_SOFT))


func _paint_one_way(img: Image, column: int) -> void:
	for x in TILE:
		var height := 6 + int(round(sin(float(x) * 0.5) * 1.2 + sin(float(x) * 0.17 + 0.9) * 0.8))
		height = clampi(height, 4, 9)
		for y in height:
			var col := INK_EDGE if y == 0 else INK
			img.set_pixel(column * TILE + x, y, _ink(x, y, col))
		# Редкие капли снизу: полоса не выглядит линейкой.
		if _noise(x, 7) > 0.86:
			img.set_pixel(column * TILE + x, height, _ink(x, height, INK))
