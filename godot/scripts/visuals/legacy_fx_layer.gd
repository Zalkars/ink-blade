extends Node2D

## Original 0.2 effects rendered in world coordinates, owned by the level.
## Also draws F2 debug hitboxes when hud.debug_on is active.
var animate_on_death := false
var flow: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	if get_tree().paused and animate_on_death:
		InkFx.update(delta)
	queue_redraw()


func _draw() -> void:
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(InkFx.t)
	InkFx.draw_behind()
	InkFx.draw_front()
	if flow != null and flow.hud != null and flow.hud.debug_on:
		_draw_hitboxes()


func _draw_hitboxes() -> void:
	var p = flow.player
	if p != null and is_instance_valid(p):
		InkR.dbg_rect(p.global_position.x - 14.0, p.global_position.y - 23.0, 28.0, 46.0, InkR.TEAL, 0.9)
		var atk: Rect2 = p.active_attack_hitbox()
		if atk.has_area():
			InkR.dbg_rect(atk.position.x, atk.position.y, atk.size.x, atk.size.y, InkR.GOLD, 0.95)
	var lvl = flow.level
	if lvl == null or not is_instance_valid(lvl):
		return
	for e in lvl.enemies:
		if not is_instance_valid(e):
			continue
		var r := Vector2(28.0, 44.0) if e is Keeper else Vector2(18.0, 20.0)
		var off := Vector2(0.0, -32.0) if e is Keeper else Vector2.ZERO
		InkR.dbg_rect(e.global_position.x + off.x - r.x, e.global_position.y + off.y - r.y, r.x * 2.0, r.y * 2.0, InkR.RED, 0.85)
	for child in lvl.get_children():
		if child is InkBolt or child is InkDrop:
			InkR.dbg_rect(child.global_position.x - 11.0, child.global_position.y - 11.0, 22.0, 22.0, InkR.RED_BRIGHT, 0.9)
		elif child is InkWave:
			InkR.dbg_rect(child.global_position.x - 22.0, child.global_position.y - 14.0, 44.0, 28.0, InkR.RED_BRIGHT, 0.9)
	for cp in lvl.checkpoints:
		if is_instance_valid(cp):
			InkR.dbg_rect(cp.global_position.x - 40.0, cp.global_position.y - 14.0, 80.0, 80.0, InkR.INK_SOFT, 0.45)
