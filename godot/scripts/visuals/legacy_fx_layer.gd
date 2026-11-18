extends Node2D

## Original 0.2 effects rendered in world coordinates, owned by the level.
var animate_on_death := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if get_tree().paused and animate_on_death:
		InkFx.update(delta)
	queue_redraw()

func _draw() -> void:
	InkR.init_static()
	InkR.set_canvas(self)
	InkR.begin_frame(InkFx.t)
	InkFx.draw_behind()
	InkFx.draw_front()
