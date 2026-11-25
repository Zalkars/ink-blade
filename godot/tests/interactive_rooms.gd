extends Node

var flow: Node
var checks := 0
var failures := 0


func _ready() -> void:
	SaveGame.use_storage("user://interactive-tests/saves")
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await _ticks(3)
	if "--resume-route" in OS.get_cmdline_user_args():
		await _resume_editor_route()
		_finish()
		return
	flow.start_run()
	await _ticks(4)
	var old := SaveGame.migrate({"version": 5, "level": "ch01_hall", "killed": ["e1"], "props": ["test"]})
	_check(old.version == SaveGame.VERSION and old.rooms.is_empty() and old.switches.is_empty()
		and old.killed == ["e1"] and old.props == ["test"] and old.ink == 0.0,
		"v5 migration preserves existing progress")
	_move(Vector2(3312, 576))
	await _ticks(4)
	while flow.dialogue.visible:
		flow.dialogue.advance()
	await _ticks(4)
	flow.player.ink = 31.0
	flow.player.hp = 3
	await _use(Vector2(3616, 576))
	_check(flow.level_id == "archive_annex" and flow.player.ink == 31 and flow.player.hp == 3 and flow.player.has_weapon("weapon.brush"),
		"archive exit preserves inventory and health")
	if flow.level_id != "archive_annex":
		_finish()
		return
	_check(absf(flow.player.global_position.x - 128) < 5, "player appears at the named arrival")
	_check(_door_blocks(), "closed vault door blocks a physics ray")
	var locked: Dictionary = flow.level.devices.nearest(Vector2(1440, 608))
	_check(not flow.level.devices.available(locked), "vault exit is gated by the lever")
	await _capture("vault-closed")
	await _use(Vector2(832, 448))
	_check(flow.level.devices.is_open("vault_door") and not _door_blocks(), "lever removes the physical door")
	_check(SaveGame.read_slot("auto").switches == ["annex_lever"], "lever is recorded immediately")
	flow.level.enemies[0].hit(99, 1)
	_move(Vector2(1312, 608))
	await _ticks(8)
	flow._flush_save()
	_check(flow.level.collected_props == ["archive_reward"] and flow.player.ink == 41, "vault supplies an actual collectible reward")
	flow.continue_run()
	await _ticks(4)
	_check(flow.level_id == "archive_annex" and flow.level.devices.is_open("vault_door") and flow.level.enemy_count() == 0
		and flow.level.collected_props == ["archive_reward"], "Continue restores the current room")
	await _use(Vector2(1440, 608))
	_check(flow.level_id == "ch01_hall" and absf(flow.player.global_position.x - 3488) < 5, "vault exit returns to the named hall entry")
	var save := SaveGame.read_slot("auto")
	_check(save.rooms.has("archive_annex") and save.rooms.archive_annex.switches == ["annex_lever"], "hall autosave records the visited vault")
	_check(flow.run_kills == 1, "run statistics include enemies defeated in other rooms")
	await _use(Vector2(3616, 576))
	_check(flow.level_id == "archive_annex" and flow.level.devices.is_open("vault_door") and flow.level.enemy_count() == 0
		and flow.level.collected_props == ["archive_reward"], "revisiting the vault retains its world state")
	flow.player.hp = 0
	flow._on_player_died()
	await _ticks(2)
	flow.continue_run()
	await _ticks(4)
	_check(flow.level_id == "archive_annex" and flow.player.hp == flow.player.MAX_HP and flow.level.devices.is_open("vault_door")
		and flow.level.collected_props == ["archive_reward"], "respawn restores health and preserves vault progress")
	if CTL.touch_enabled:
		_move(Vector2(64, 608))
		await _ticks(3)
		var rect: Rect2 = flow.hud.room_prompt_rect()
		var touch_point: Vector2 = flow.hud.get_global_transform() * rect.get_center()
		flow.mobile_controls._press(77, touch_point)
		flow.mobile_controls._release(77, touch_point)
		await _ticks(4)
		_check(flow.level_id == "ch01_hall", "touch prompt activates the nearby exit")
	flow._show_title()
	var before := SaveGame.read_slot("auto")
	await _check_editor(before)
	if "--save-route" not in OS.get_cmdline_user_args():
		await _check_story_chapter()
	_finish()


func _check_editor(before: Dictionary) -> void:
	flow.open_level_editor()
	await _ticks(4)
	var editor: Control = flow.level_editor
	var draft: LevelDraft = editor.draft
	var canvas: Control = editor.canvas
	var partner := LevelDraft.new()
	partner.start("qa_room_two", "Test room two")
	partner.place("entry", Vector2(448, 608), Vector2.ZERO)
	partner.place("exit", Vector2(960, 608), Vector2.ZERO)
	partner.data.exits[0].level = "qa_room_one"
	partner.data.exits[0].entry = "entry_1"
	_check(partner.save() == OK, "the paired draft can be saved before its target is created")
	draft.start("qa_room_one", "Test room one")
	draft.place("entry", Vector2(192, 608), Vector2.ZERO)
	draft.place("checkpoint", Vector2(320, 608), Vector2.ZERO)
	draft.place("switch", Vector2(512, 608), Vector2.ZERO)
	draft.place("door", Vector2(896, 608), Vector2.ZERO)
	draft.place("exit", Vector2(1088, 608), Vector2.ZERO)
	editor._document_changed()
	await _ticks(2)
	canvas.tool = "link"
	_click(canvas, Vector2(512, 584))
	_click(canvas, Vector2(896, 552))
	_check(draft.data.switches[0].targets == ["door_1"], "the canvas link tool connects the lever and door")
	canvas.tool = "select"
	_click(canvas, Vector2(1088, 584))
	_pick_suggestion(editor._target_room, "qa_room_two")
	_pick_suggestion(editor._target_entry, "entry_1")
	_check(editor._target_room.text == "qa_room_two" and editor._target_entry.text == "entry_1",
		"the exit inspector picks a saved room and a named entry from its menus")
	editor._target_requires.text = "switch_1"
	editor._item_fields.x.value = 1120
	editor._apply_item()
	_check(draft.data.exits[0].x == 1120 and draft.data.exits[0].level == "qa_room_two" and editor._unresolved_exits().is_empty(),
		"the inspector edits a position and the exit destination")
	await _capture("editor-exit")
	canvas.set_layer("geometry", true, false)
	canvas.set_layer("actors", false, true)
	_check("solids" in canvas.locked and "checkpoints" in canvas.hidden_sections and "exits" not in canvas.locked,
		"layer visibility and locking are independent")
	canvas.tool = "box"
	_drag(canvas, Vector2(478, 465), Vector2(929, 605))
	_check(canvas.group.size() == 2 and canvas.tool == "select", "marquee selects the lever and door together")
	canvas.move_selected(Vector2(32, 0))
	_check(draft.data.switches[0].x == 544 and draft.data.doors[0].x == 928, "group move preserves both links")
	canvas.delete_selected()
	_check(draft.data.switches.is_empty() and draft.data.doors.is_empty() and draft.data.exits[0].requires.is_empty(),
		"group deletion removes dangling local references")
	draft.undo()
	editor._document_changed()
	canvas.set_layer("actors", true, true)
	_check(draft.validate().is_empty(), "undo restores the connected group")
	editor._test_start.select(2)
	for i in editor._test_weapon.item_count:
		if editor._test_weapon.get_item_metadata(i) == "weapon.brush":
			editor._test_weapon.select(i)
	editor._test_ink.value = 60
	await _capture("linked-editor")
	editor._playtest()
	await _ticks(4)
	_check(flow.is_testing_level() and flow.level_id == "qa_room_one" and flow.player.ink == 60 and
		flow.player.current_weapon_id() == "weapon.brush" and absf(flow.player.global_position.x - 320) < 5,
		"playtest starts at the selected checkpoint with the chosen weapon and ink")
	if not flow.is_testing_level():
		return
	await _use(Vector2(544, 608))
	await _use(Vector2(1120, 608))
	_check(flow.level_id == "qa_room_two" and absf(flow.player.global_position.x - 448) < 5, "playtest loads a paired saved draft at its entry")
	await _use(Vector2(960, 608))
	_check(flow.level_id == "qa_room_one" and flow.level.devices.is_open("door_1"), "return to unsaved draft keeps its open door")
	flow.return_to_level_editor()
	_check(editor.visible and draft.dirty() and SaveGame.read_slot("auto") == before, "return restores unsaved edits and preserves the real slot")
	await _check_saved_route(editor, partner, before)


func _check_saved_route(editor: Control, partner: LevelDraft, story_save: Dictionary) -> void:
	partner.place("checkpoint", Vector2(544, 608), Vector2.ZERO)
	partner.place("prop:prop.soul_shard", Vector2(752, 608), Vector2.ZERO)
	partner.place("finish", Vector2(1200, 608), Vector2.ZERO)
	_check(partner.save() == OK, "second editor room saves its checkpoint, reward and explicit finish")
	editor._write()
	var route_dir := LevelPackage.SAVE_DIR.path_join("qa_room_one")
	editor._detail_buttons.test.pressed.emit()
	editor._route.get_popup().id_pressed.emit(0)
	_check(flow.is_custom_route() and flow.state == flow.State.PLAY and flow.level_id == "qa_room_one",
		"Route > Start opens the first editor room in its own save")
	if not flow.is_custom_route():
		return
	_check(await _walk_to(544), "walk through room one to the lever with normal movement")
	await _interact()
	_check(flow.level.devices.is_open("door_1"), "the lever opens the door during a saved route")
	_check(await _walk_to(1120), "walk through the opened door to the linked exit")
	await _interact()
	_check(flow.level_id == "qa_room_two" and absf(flow.player.global_position.x - 448) < 5,
		"saved route lands at the named entry in room two")
	if flow.level_id != "qa_room_two":
		flow._show_title()
		return
	_check(await _walk_to(752), "walk across checkpoint to the reward in room two")
	await _ticks(5)
	flow._pause()
	flow.overlay.activate(flow.overlay.actions.find("menu"))
	var progress := SaveGame.read_slot("auto", route_dir)
	_check(flow.state == flow.State.TITLE and progress.level == "qa_room_two" and progress.checkpoint == "checkpoint_1" \
		and progress.props == ["prop_1"] and progress.rooms.qa_room_one.switches == ["switch_1"],
		"Save and Exit preserves the active checkpoint, pickup and first room's lever")
	_check(SaveGame.read_slot("auto") == story_save, "custom route leaves the story save intact")
	partner.data.exits.erase(RoomLinks.find(partner.data, "exits", "finish_1"))
	_check(partner.save() == OK, "author can change the editor map between game sessions")
	if "--save-route" in OS.get_cmdline_user_args():
		return
	flow.queue_free()
	await _ticks(3)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await _ticks(4)
	await _resume_editor_route()
	flow._show_title()
	partner.place("finish", Vector2(1200, 608), Vector2.ZERO)
	partner.save()
	flow.open_level_editor()
	editor = flow.level_editor
	editor._load_document("qa_room_one")
	await _check_json(editor)
	flow.close_level_editor()


func _resume_editor_route() -> void:
	var route_dir := LevelPackage.SAVE_DIR.path_join("qa_room_one")
	flow.title_screen.activate(flow.title_screen.actions.find("play"))
	flow.title_screen.activate(flow.title_screen.actions.find("custom"))
	var editor: Control = flow.level_editor
	editor._load_document("qa_room_one")
	editor._detail_buttons.test.pressed.emit()
	editor._route.get_popup().id_pressed.emit(1)
	await _ticks(3)
	_check(flow.is_custom_route() and flow.level_id == "qa_room_two" and absf(flow.player.global_position.x - 544) < 5 \
		and flow.player.ink == 10 and flow.level.collected_props == ["prop_1"],
		"fresh game instance resumes the correct editor room, checkpoint and inventory from disk")
	if not flow.is_custom_route():
		return
	_check(await _walk_to(1200), "walk to the finish from the saved checkpoint")
	await _interact()
	_check(flow.state == flow.State.CLEARED and not SaveGame.has_unfinished_run(SaveGame.read_slot("auto", route_dir)),
		"saved map snapshot still has the finish and marks both-room route complete")


func _check_json(editor: Control) -> void:
	var path := ProjectSettings.globalize_path("user://editor-route-export.json")
	editor._json_dialog.use_native_dialog = false
	editor._file.get_popup().id_pressed.emit(6)
	editor._json_dialog.file_selected.emit(path)
	editor._json_dialog.hide()
	var exported := LevelPackage.read_file(path)
	_check(exported.get("data", {}).get("rooms", []).size() == 2, "editor exports both linked rooms in one JSON file")
	if not exported.has("data"):
		return
	var invalid: Dictionary = exported.data.duplicate(true)
	invalid.rooms[0].exits[0].entry = "absent_entry"
	var files := LevelDraft.files()
	_check(LevelPackage.install(invalid).has("error") and LevelDraft.files() == files,
		"invalid package is rejected before writing drafts")
	editor._file.get_popup().id_pressed.emit(4)
	editor._json_dialog.file_selected.emit(path)
	editor._json_dialog.hide()
	var copy: Dictionary = editor.draft.data
	var imported := LevelDraft.read(str(copy.exits[0].level))
	_check(copy.id != "qa_room_one" and imported.get("id") != "qa_room_two" and not imported.is_empty() \
		and imported.exits[0].level == copy.id and LevelDraft.read("qa_room_one").exits[0].level == "qa_room_two",
		"JSON import assigns new IDs, retargets internal links and preserves original drafts")
	var single_path := ProjectSettings.globalize_path("user://editor-single-export.json")
	editor._file.get_popup().id_pressed.emit(5)
	editor._json_dialog.file_selected.emit(single_path)
	editor._json_dialog.hide()
	var single := LevelPackage.read_file(single_path)
	_check(single.get("data", {}).get("id") == copy.id and LevelPackage.install(single.data).get("count") == 1,
		"a single map can also be exported and reimported")


func _check_story_chapter() -> void:
	SaveGame.write_slot("auto", {"level": "ch01_hall", "cleared": true, "finale_seen": true,
		"weapons": ["weapon.blade", "weapon.brush"], "weapon": "weapon.brush", "ink": 21, "hp": 3})
	flow.title_screen.reset_menu()
	await _ticks(ceili(Engine.physics_ticks_per_second * 0.2) + 1)
	flow.title_screen.activate(flow.title_screen.actions.find("play"))
	_check(flow.title_screen.actions.has("next_chapter"), "title offers Chapter II after exiting a completed Chapter I")
	flow.title_screen.activate(flow.title_screen.actions.find("next_chapter"))
	_check(flow.level_id == "ch02_cistern" and flow.player.current_weapon_id() == "weapon.brush" and flow.player.ink == 21,
		"title opens Chapter II from a completed Chapter I save with the same inventory")
	if flow.level_id != "ch02_cistern":
		return
	await _capture("cistern")
	await _use(Vector2(1040, 416))
	_check(flow.level.devices.is_open("sluice"), "the Cistern lever opens the sluice")
	await _use(Vector2(1936, 608))
	_check(flow.level_id == "ch02_scriptorium", "the Cistern connects to the Scriptorium")
	flow._show_title()
	flow.title_screen.activate(flow.title_screen.actions.find("play"))
	flow.title_screen.activate(flow.title_screen.actions.find("continue"))
	_check(flow.level_id == "ch02_scriptorium" and SaveGame.read_slot("auto").rooms.ch02_cistern.switches == ["sluice_lever"],
		"story Continue restores the chapter and the Cistern lever")
	if flow.level_id != "ch02_scriptorium":
		return
	for i in 3:
		for enemy in flow.level.enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.dead:
				enemy.hit(99, 1)
		await _ticks(4)
	_check(flow.state == flow.State.CLEARED and not flow.cutscene.visible and SaveGame.read_slot("auto").finale_seen,
		"clearing the Scriptorium completes Chapter II with its own ending")


func _pick_suggestion(field: LineEdit, value: String) -> void:
	var button := field.get_parent().get_child(1) as MenuButton
	button.about_to_popup.emit()
	var popup := button.get_popup()
	for i in popup.item_count:
		if popup.get_item_metadata(i) == value:
			popup.id_pressed.emit(popup.get_item_id(i))
			return


func _door_blocks() -> bool:
	var ray := PhysicsRayQueryParameters2D.create(Vector2(1090, 560), Vector2(1190, 560), Player.SOLID_MASK)
	return not flow.player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _move(feet: Vector2) -> void:
	flow.player.iframes = 5
	flow.player.global_position = feet - Vector2(0, 23)
	flow.player.velocity = Vector2.ZERO


func _use(feet: Vector2) -> void:
	_move(feet)
	await _ticks(2)
	await _interact()


func _walk_to(x: float) -> bool:
	var right: bool = flow.player.global_position.x < x
	_key(KEY_D if right else KEY_A, true)
	for i in 540:
		if absf(flow.player.global_position.x - x) < 16.0:
			break
		await _ticks(1)
	_key(KEY_D if right else KEY_A, false)
	await _ticks(3)
	return absf(flow.player.global_position.x - x) < 28.0


func _interact() -> void:
	for pressed in [true, false]:
		_key(KEY_E, pressed)
	await _ticks(5)


func _key(code: int, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	Input.parse_input_event(key)
	Input.flush_buffered_events()


func _click(canvas: Control, point: Vector2) -> void:
	_drag(canvas, point, point)


func _drag(canvas: Control, start: Vector2, finish: Vector2) -> void:
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = canvas.get_global_transform() * (canvas.offset + (start if pressed else finish) * canvas.zoom)
		get_viewport().push_input(button, true)


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


func _finish() -> void:
	print("INTERACTIVE_ROOMS_RESULT=%s (%d checks)" % ["OK" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
