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
var boss: Keeper
var debug_on := false
var hint := ""
var toast := ""
var toast_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint = L10N.t("ui.hud.hint", [
		CTL.label_move(),
		CTL.label_key("jump"),
		CTL.label_key("dash"),
		CTL.label_key("attack"),
		CTL.label_key("swap"),
		CTL.label_key("pause"),
	])


func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t = maxf(0.0, toast_t - delta)
	queue_redraw()


## Короткое сообщение поверх игры: «получено оружие», важная находка.
func show_toast(text: String) -> void:
	toast = text
	toast_t = 3.5
	queue_redraw()


func bind(p: Player) -> void:
	player = p


func bind_boss(b: Keeper) -> void:
	boss = b


func _draw() -> void:
	if player != null:
		_draw_hearts()
		_draw_dash()
		_draw_weapon()

	if boss != null and is_instance_valid(boss) and boss.engaged and not boss.dead:
		_draw_boss()

	if toast_t > 0.0 and not toast.is_empty():
		_draw_toast()

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
	draw_string(FONT_TEXT, pos + Vector2(106.0, 7.0), L10N.t("ui.hud.dash"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FAINT)


## Текущее оружие справа сверху: имя и точки-переключатели.
func _draw_weapon() -> void:
	var name := player.weapon_name()
	if name.is_empty():
		return
	var right := size.x - 40.0
	draw_string(FONT_TEXT, Vector2(right - 340.0, 36.0), L10N.t("ui.hud.weapon"),
		HORIZONTAL_ALIGNMENT_RIGHT, 340.0, 11, FAINT)
	draw_string(FONT_BOLD, Vector2(right - 340.0, 62.0), name,
		HORIZONTAL_ALIGNMENT_RIGHT, 340.0, 18, Color(INK, 0.78))
	var count: int = player.weapons.size()
	for i in count:
		var c := Vector2(right - float(count - 1 - i) * 16.0, 78.0)
		draw_circle(c, 4.0, RED if i == player.weapon_index else Color(INK, 0.2))


## Полоса босса: имя, здоровье, фаза и состояние печати.
func _draw_boss() -> void:
	var w := 560.0
	var x := (size.x - w) * 0.5
	var y := 18.0
	draw_string(FONT_BOLD, Vector2(x, y + 2.0), L10N.t("entity.keeper.name"),
		HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(INK, 0.85))
	draw_rect(Rect2(x, y + 10.0, w, 10.0), Color(INK, 0.18))
	var frac := clampf(float(boss.hp) / float(maxi(1, boss.max_hp)), 0.0, 1.0)
	draw_rect(Rect2(x, y + 10.0, w * frac, 10.0), RED)
	draw_line(Vector2(x + w * 0.5, y + 10.0), Vector2(x + w * 0.5, y + 20.0),
		Color(PAPER, 0.8), 2.0)
	draw_string(FONT_TEXT, Vector2(x + w + 10.0, y + 19.0),
		L10N.t("ui.hud.boss.phase", [boss.phase]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FAINT)
	if boss.seal_open:
		draw_string(FONT_BOLD, Vector2(x, y + 36.0), L10N.t("ui.hud.boss.seal_open"),
			HORIZONTAL_ALIGNMENT_CENTER, w, 11, RED)


func _draw_toast() -> void:
	var a := clampf(toast_t / 0.6, 0.0, 1.0)
	var w := 540.0
	var x := (size.x - w) * 0.5
	draw_rect(Rect2(x, 96.0, w, 40.0), Color(PAPER, 0.92 * a))
	draw_rect(Rect2(x, 96.0, w, 2.0), Color(RED, a))
	draw_string(FONT_BOLD, Vector2(x, 123.0), toast,
		HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(INK, 0.92 * a))


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
