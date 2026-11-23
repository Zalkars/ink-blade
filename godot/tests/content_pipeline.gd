extends Node

var checks := 0
var failures := 0
var flow: Node


func _ready() -> void:
	SaveGame.use_storage("user://pipeline-tests/saves")
	for slot in [SaveGame.AUTOSAVE, "slot_1", "slot_2"]:
		SaveGame.erase_slot(slot)
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await _ticks(2)
	flow.title_slot = SaveGame.AUTOSAVE
	var title: Control = flow.title_screen
	_check(title.actions == ["play", "slots", "settings", "quit"], "main menu separates saved games from Play")
	var old := {"version": 4, "level": "ch01_hall", "checkpoint": "cp_02", "hp": 3, "soul": 41.0,
		"killed": ["e1"], "triggers": ["archivist"], "weapons": ["weapon.blade", "weapon.brush"],
		"weapon": "weapon.brush", "ink_marks": [], "finale_seen": false}
	SaveGame.write_slot("slot_1", old)
	var migrated := SaveGame.migrate(SaveGame.read_slot("slot_1"))
	_check(migrated.version == 5 and migrated.props.is_empty() and migrated.checkpoint == "cp_02"
		and migrated.soul == 41.0 and migrated.killed == ["e1"] and migrated.weapon == "weapon.brush", "v4 migration retains progress")
	var original := SaveGame.read_slot("slot_1")
	title.activate(title.actions.find("slots"))
	await _capture("slots")
	title.activate(title.actions.find("slot_1"))
	_check(flow.title_slot == "slot_1" and flow.state == flow.State.TITLE, "choosing slot keeps the title open")
	title.activate(title.actions.find("play"))
	_check(title.actions.has("continue") and title.actions.has("normal") and title.actions.has("guide"), "Play describes the active save")
	await _capture("play")
	title.activate(title.actions.find("guide"))
	await _ticks(45)
	flow.control_guide.dismiss()
	_check(flow.state == flow.State.TITLE and SaveGame.read_slot("slot_1") == original, "tutorial replay writes no progress")
	_check(not flow.load_level("test_gallery"), "QA room is unavailable to story sessions")
	var previous := SaveGame.storage
	SaveGame.use_storage("user://pipeline-tests/qa")
	flow.qa_session = true
	_check(flow.load_level("test_gallery") and flow.player != null, "loads the gallery through the level index")
	var shard := _pickup()
	_check(shard != null and PDB.get_def(&"prop.soul_shard") != null, "registry places the pickup")
	if shard == null:
		get_tree().quit(1)
		return
	flow.player.soul = 96.0
	flow.player.global_position = shard.global_position - Vector2(0, 23)
	await _ticks(10)
	_check(flow.player.soul == 99.0 and flow.level.collected_props == ["shard_1"], "physical pickup clamps soul and is collected once")
	flow._flush_save()
	flow.continue_run()
	_check(_pickup() == null and flow.player.soul == 99.0, "pickup remains collected after save/load")
	flow.load_level("test_gallery")
	shard = _pickup()
	_check(shard != null, "a new run restores pickups")
	flow.player.soul = 99.0
	flow._autosave(false)
	flow.player.global_position = shard.global_position - Vector2(0, 23)
	await _ticks(10)
	flow._flush_save()
	_check(SaveGame.read_slot("auto").props == ["shard_1"], "pickup at full soul is still persisted")
	flow.player.iframes = 0.0
	flow.player.take_damage(Player.MAX_HP, 0.0)
	flow.respawn_run()
	_check(_pickup() == null and flow.player.soul == 0.0, "respawn keeps pickup state and resets soul")
	flow.qa_session = false
	flow._show_title()
	SaveGame.use_storage(previous)
	_check(SaveGame.read_slot("slot_1") == original and SaveGame.read_slot("auto").is_empty(), "QA does not touch story saves")
	flow.start_run()
	var before := SaveGame.read_slot("auto")
	flow.console.execute("set soul nope", true)
	_check(SaveGame.storage == previous and flow.player.soul == 0.0, "invalid command leaves session unchanged")
	flow.console.open()
	flow.console._edit.text = "map p"
	flow.console._update_suggestions("map p")
	_press_key(KEY_DOWN)
	_press_key(KEY_TAB)
	_check(flow.console._edit.text == "map platforms ", "Arrow selects a suggestion and Tab completes the argument")
	await _capture("console")
	flow.console.close()
	flow.debug_panel.open()
	await _capture("developer-panel")
	flow.debug_panel.close()
	var enemies: int = flow.level.enemy_count()
	flow.console.execute("cheat god on", true)
	flow.console.execute("map enemies off", true)
	flow.console.execute("map platforms off", true)
	flow.player.iframes = 0.0
	flow.player.take_damage(2, 1.0)
	_check(flow.player.hp == Player.MAX_HP and flow.level.enemy_count() == enemies and not flow.level.enemies_enabled,
		"invincibility and disabled enemies are reversible debug controls")
	flow._show_title()
	_check(SaveGame.storage == previous and SaveGame.read_slot("auto") == before and not flow.debug_rules.god,
		"leaving debug restores the story save and defaults")
	print("CONTENT_PIPELINE: %d checks, %d failures" % [checks, failures])
	print("CONTENT_PIPELINE_RESULT=" + ("OK" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _pickup() -> SoulPickup:
	for child in flow.level.get_children():
		if child is SoulPickup and not child.is_queued_for_deletion():
			return child
	return null


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture-review" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("OK " if ok else "FAIL ") + label)
