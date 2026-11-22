extends Node2D

const Decor = preload("res://scripts/world/level_decor.gd")
const OUTPUT = "res://../builds/mountain-floor-review/"
class FallbackLevel extends Level:
	func _bake_strips_async() -> void:
		pass
class SurfaceProbe extends Node2D:
	func _draw() -> void:
		InkR.init_static()
		InkR.set_canvas(self)
		Decor.draw_surface(Rect2(0, 576, 1280, 144), false, Rect2(0,0,1280,720))
var checks := 0
var failures := 0
var level: Level
var camera: Camera2D
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + label)
func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if DisplayServer.get_name() == "headless":
		print("MOUNTAIN_FLOOR: rendered test requires a rendering display")
		get_tree().quit(2)
		return
	camera = Camera2D.new()
	camera.position = Vector2(640,360)
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	var vp := SubViewport.new()
	vp.size = Vector2i(1280,720)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(SurfaceProbe.new())
	add_child(vp)
	await frame()
	await frame()
	var floor_image := vp.get_texture().get_image()
	check(floor_image.get_pixel(640,650).a > 0.995, "ground bake is opaque before composition")
	vp.queue_free()
	for baked in [false, true]:
		level = preload("res://scenes/level/ch01_hall.tscn").instantiate() if baked else FallbackLevel.new()
		level.data_path = "res://content/levels/ch01_hall.json"
		add_child(level)
		level.set_physics_process(false)
		for child in level.get_children():
			if child is CanvasItem and child not in [level._backdrop, level._strips_root, level._fallback]:
				child.visible = false
			child.set_physics_process(false)
		for x in [2528.0,2592.0,7008.0,7072.0,11232.0,11296.0]:
			camera.position = Vector2(x,360)
			await frame()
			if baked:
				for i in 70:
					await frame()
					var left := int(maxf(0, floor((x-640)/1280)))
					var right := int(floor((x+639)/1280))
					var ready := true
					for strip in range(left,right+1):
						ready = ready and level._baked_strips.has(strip)
					if ready: break
			await frame()
			var image := get_viewport().get_texture().get_image()
			image.save_png(OUTPUT+"%s-%d.png" % ["baked" if baked else "fallback",int(x)])
			level._backdrop.visible = false
			await frame()
			var without := get_viewport().get_texture().get_image()
			var samples := 0
			var opaque := true
			for spec in level.data.solids:
				var r := level._rect_of(spec)
				if r.end.y < level.bounds.end.y: continue
				for sx in range(48,1232,80):
					var wx: float = x - 640 + sx
					var yy := int(r.position.y+24)
					if wx > r.position.x+8 and wx < r.end.x-8 and yy < 710:
						var a := image.get_pixel(sx,yy)
						var b := without.get_pixel(sx,yy)
						opaque = opaque and absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < 0.015
						samples += 1
			check(samples > 0 and opaque, "%s floor hides background x=%d (%d samples)" % ["baked" if baked else "fallback",int(x),samples])
			level._backdrop.visible = true
			level._strips_root.visible = false
			level._fallback.visible = false
			level._fallback.set_process(false)
			await frame()
			var sky := get_viewport().get_texture().get_image()
			check(sky.get_pixel(640,700).is_equal_approx(Decor.RIDGE_MID), "mountains stay present at zone boundary x=%d" % int(x))
			level._strips_root.visible = true
			level._fallback.set_process(true)
			level._fallback.visible = true
		if not baked:
			for strip in level._strip_count(): level._baked_strips[strip] = null
			await frame()
			level._baked_strips.clear()
			camera.position.x = 640
			await frame()
			await frame()
			check(level._fallback.visible, "fallback returns after moving from baked to unbaked strips")
		level.queue_free()
		await frame()
	print("MOUNTAIN_FLOOR: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
