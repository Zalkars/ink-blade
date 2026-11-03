extends Control

## HUD на Control, без мыши. Пока рисует только то, что нужно каркасу:
## здоровье, готовность рывка, подсказку по управлению и отладочную строку.

const FONT_BOLD := preload("res://assets/fonts/PTSerif-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/PTSerif-Regular.ttf")

const INK := Color("#17130f")
const RED := Color("#9c1f24")
const PAPER := Color("#f1e6d0")
const FAINT := Color(0.09, 0.07, 0.06, 0.45)

var player: Player
var debug_on := false
var hint := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint = "%s — бег   ·   %s — прыжок   ·   %s — рывок   ·   %s — удар   ·   %s — пауза" % [
		CTL.label_move(),
		CTL.label_key("jump"),
		CTL.label_key("dash"),
		CTL.label_key("attack"),
		CTL.label_key("pause"),
	]


func _process(_delta: float) -> void:
	queue_redraw()


func bind(p: Player) -> void:
	player = p


func _draw() -> void:
	if player != null:
		_draw_hearts()
		_draw_dash()

	if not hint.is_empty():
		var strip := Rect2(0.0, size.y - 46.0, size.x, 46.0)
		draw_rect(strip, Color(PAPER, 0.94))
		draw_line(Vector2(0.0, strip.position.y), Vector2(size.x, strip.position.y), Color(INK, 0.25), 1.0)
		draw_string(FONT_TEXT, Vector2(40.0, size.y - 18.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.6))

	if debug_on:
		_draw_debug()


func _draw_hearts() -> void:
	var x := 44.0
	for i in player.MAX_HP:
		var c := Vector2(x + i * 24.0, 44.0)
		var filled := i < player.hp
		_draw_drop(c, 9.0, RED if filled else Color(INK, 0.25))


func _draw_drop(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.0, -r * 1.5),
		c + Vector2(r * 0.62, -r * 0.35),
		c + Vector2(r, r * 0.35),
		c + Vector2(r * 0.45, r),
		c + Vector2(-r * 0.45, r),
		c + Vector2(-r, r * 0.35),
		c + Vector2(-r * 0.62, -r * 0.35),
	])
	draw_colored_polygon(pts, col)


func _draw_dash() -> void:
	var ready := player.dash_ready()
	var pos := Vector2(40.0, 70.0)
	draw_rect(Rect2(pos, Vector2(96.0, 5.0)), Color(INK, 0.18))
	draw_rect(Rect2(pos, Vector2(96.0 * ready, 5.0)), RED if ready >= 1.0 else Color(RED, 0.55))
	draw_string(FONT_TEXT, pos + Vector2(106.0, 7.0), "РЫВОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FAINT)


func _draw_debug() -> void:
	var lines := PackedStringArray()
	lines.append("FPS %d" % Engine.get_frames_per_second())
	lines.append("draw calls %d" % int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	lines.append("tick %d Hz" % int(Engine.physics_ticks_per_second))
	lines.append("enemies %d" % (get_tree().get_nodes_in_group("enemies").size()))
	lines.append("pos %.0f, %.0f" % [player.global_position.x, player.global_position.y] if player != null else "pos —")
	var y := 26.0
	for line in lines:
		draw_string(FONT_TEXT, Vector2(size.x - 190.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FAINT)
		y += 16.0
