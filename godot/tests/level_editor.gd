extends Node

const Decor := preload("res://scripts/world/level_decor.gd")

var flow: Node
var checks := 0
var failures := 0


func _ready() -> void:
	SaveGame.use_storage("user://editor-tests/saves")
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await _ticks(4)
	flow.start_run()
	await _ticks(5)
	var baseline := SaveGame.read_slot(SaveGame.AUTOSAVE)
	var original_storage := SaveGame.storage
	var room: Level = flow.level
	var cell: Vector2i = room._one_way_tiles.keys()[0]
	var platform := room.tile_layer.get_cell_atlas_coords(cell)
	flow._pause()
	flow.debug_panel.open()
	flow.debug_panel._show_section("map")
	_set_switch("platforms", false)
	_check(room._backdrop.visible and room._strips_root.visible and not room._platform_art.visible, "platforms can be hidden without hiding scenery")
	_check(room.tile_layer.get_cell_atlas_coords(cell) != platform, "turning platforms off updates collision tiles")
	_set_switch("background", false)
	_set_switch("platforms", true)
	_check(not room._backdrop.visible and room._platform_art.visible and room.tile_layer.get_cell_atlas_coords(cell) == platform,
		"platforms and collision return while the backdrop stays hidden")
	_set_switch("particles", false)
	_set_switch("enemies", false)
	_check(not InkFx.particles_enabled and not room.enemies[0].visible and room.enemies[0].process_mode == Node.PROCESS_MODE_DISABLED,
		"particles and enemies can be disabled together")
	_check(room.killed_ids.is_empty() and room.enemy_count() > 0, "disabling enemies does not clear the level")
	_set_switch("enemies", true)
	_set_switch("particles", true)
	_set_switch("background", true)
	_check(InkFx.particles_enabled and room.enemies[0].visible and room._backdrop.visible, "all independent toggles restore state")
	await _capture("map-controls")
	flow.debug_panel._body.get_child(0).pressed.emit()
	var editor: Control = flow.level_editor
	await _ticks(4)
	_check(editor.visible and get_tree().paused and not flow.debug_panel.visible, "editor opens through the map panel")
	var draft: LevelDraft = editor.draft
	draft.start("qa_editor_workshop", "Мастерская · тест")
	editor._document_changed()
	var canvas: Control = editor.canvas
	editor._tool_buttons.terrain.pressed.emit()
	_check(editor.palette.item_count == 5 and canvas.tool == "solid", "terrain shows only geometry tools")
	editor.palette.select(1)
	editor.palette.item_selected.emit(1)
	editor._tool_buttons.logic.pressed.emit()
	_check(canvas.tool == "link" and editor.palette.item_count == 6, "logic has its own tools and selection")
	editor._tool_buttons.terrain.pressed.emit()
	_check(canvas.tool == "platform", "a tool category remembers the last used tool")
	_drag(canvas, Vector2(320, 416), Vector2(544, 416))
	_check(draft.data.one_ways.size() == 1 and int(draft.data.one_ways[0].w) == 256, "canvas drag creates a snapped platform")
	var original: Vector2i = draft.find_at(Vector2(350, 425))
	draft.resize_item(original, Vector2(64, 0))
	_check(int(draft.item(original).w) == 320, "selected terrain can be resized")
	draft.undo()
	_check(int(draft.item(original).w) == 256, "undo restores the previous rectangle")
	draft.redo()
	var copy := draft.duplicate_item(original)
	_check(copy != original and draft.data.one_ways.size() == 2, "duplicate creates a second platform")
	draft.move_item(copy, Vector2(0, -96))
	_check(int(draft.item(copy).y) == 320, "move changes the selection on the grid")
	draft.place("bridge", Vector2(1056, 352), Vector2(1600, 352))
	draft.place("steps", Vector2(704, 480), Vector2(800, 576))
	draft.place("checkpoint", Vector2(256, 608), Vector2.ZERO)
	draft.place("prop:prop.soul_shard", Vector2(352, 608), Vector2.ZERO)
	draft.place("enemy:enemy.grunt", Vector2(1088, 608), Vector2.ZERO)
	draft.place("decor:cabinet", Vector2(512, 576), Vector2.ZERO)
	draft.place("decor:gate", Vector2(1024, 608), Vector2.ZERO)
	draft.place("decor:lantern", Vector2(1320, 608).snapped(Vector2(32, 32)), Vector2.ZERO)
	_check(Decor.decor_rect(draft.data.decor[0], draft.data).end.y == 608, "cabinet base snaps to the real floor")
	_check(draft.validate().is_empty(), "completed map passes editor validation")
	editor._save_requested()
	_check(not draft.dirty() and LevelDraft.read("qa_editor_workshop").get("decor", []).size() == 3, "custom map is saved and reopens with decor")
	editor._file.get_popup().id_pressed.emit(1)
	await _ticks(3)
	_check(editor._picker.visible and editor._map_list.item_count == 1 and editor._map_list.get_item_metadata(0) == "qa_editor_workshop",
		"File > Open lists the saved draft by name and ID")
	await _capture("editor-open")
	editor._map_list.item_activated.emit(0)
	_check(not editor._picker.visible and draft.data.id == "qa_editor_workshop", "activating a draft in the picker opens it")
	editor._detail_buttons.layers.pressed.emit()
	var logic_buttons: Array = editor._layer_toggles.logic
	logic_buttons[0].button_pressed = false
	logic_buttons[1].button_pressed = true
	_check(editor._detail_pages.layers.visible and "doors" in canvas.hidden_sections and "doors" in canvas.locked
		and "solids" not in canvas.hidden_sections, "layer panel controls visibility and locking independently")
	await _capture("editor-layers")
	logic_buttons[0].button_pressed = true
	logic_buttons[1].button_pressed = false
	var canvas_width: float = canvas.size.x
	var canvas_zoom: float = canvas.zoom
	editor._detail_toggle.pressed.emit()
	await _ticks(3)
	_check(not editor._details.visible and canvas.size.x > canvas_width and is_equal_approx(canvas.zoom, canvas_zoom),
		"hiding the properties panel expands the canvas and keeps its zoom")
	editor._detail_toggle.pressed.emit()
	editor._detail_buttons.test.pressed.emit()
	await _ticks(3)
	_check(editor._route.is_visible_in_tree() and not editor._inspector.is_visible_in_tree(),
		"test settings and route share their own tab")
	await _capture("editor-test")
	editor._detail_buttons.object.pressed.emit()
	var inherited := LevelDraft.new()
	inherited.clone_world(LVL.get_level("ch01_hall").world, "qa_chapter_copy")
	_check(inherited.data.landmarks == "ch01_hall" and inherited.validate().is_empty(), "the first chapter can be cloned as a valid editable map")
	draft.place("decor:tablet", Vector2(1600, 608), Vector2.ZERO)
	editor._after_edit()
	canvas.refresh()
	await _capture("level-editor")
	_check(draft.dirty() and flow.start_editor_test(draft.data), "the unsaved revision launches in the real game")
	await _ticks(8)
	_check(flow.is_testing_level() and flow.level_id == "qa_editor_workshop" and flow.level.enemy_count() == 1,
		"playtest builds the edited world")
	_check(flow.level.data.decor.size() == 4 and not flow.save_to_slot("slot_1"), "playtest uses unsaved edits and disables story writes")
	flow.set_debug_rule("flight", true)
	_key(KEY_J)
	await _ticks(3)
	_check(flow.player.attack_t > 0.0 and flow.player._debug_flying, "pressing attack while flying starts a swing")
	flow.set_debug_rule("flight", false)
	await _capture("playtest")
	flow._pause()
	_check(flow.overlay.actions.has("editor_return") and not flow.overlay.actions.has("slots"), "playtest pause returns to the editor")
	flow._on_overlay_choice("editor_return")
	_check(editor.visible and draft.dirty() and draft.data.decor.size() == 4, "return restores unsaved editor state")
	_check(SaveGame.storage == original_storage and SaveGame.read_slot(SaveGame.AUTOSAVE) == baseline,
		"editing and playtest leave the story autosave intact")
	var viewport := Vector2(1280, 720)
	var left_camera := Vector2(640, 360)
	var right_camera := Vector2(12800, 360)
	var span := Rect2(0, 0, 14080, 720)
	var left_sun := Decor.sun_position(left_camera, viewport, span) - left_camera
	var right_sun := Decor.sun_position(right_camera, viewport, span) - right_camera
	_check(absf(left_sun.x - right_sun.x) > 200 and absf(right_sun.x) < viewport.x / 2.0, "sun has a visible continuous parallax range")
	print("LEVEL_EDITOR_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _set_switch(key: String, enabled: bool) -> void:
	var button: Button = flow.debug_panel._map_buttons[key]
	button.toggled.emit(enabled)
	_check(button.button_pressed == enabled and flow.debug_rules[key] == enabled, "switch reflects actual rule: " + key)


func _drag(canvas: Control, start: Vector2, finish: Vector2) -> void:
	for stage in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = stage
		event.position = canvas.get_global_transform() * (canvas.offset + (start if stage else finish) * canvas.zoom)
		get_viewport().push_input(event, true)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture-review" not in OS.get_cmdline_user_args():
		return
	await _ticks(15)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)
