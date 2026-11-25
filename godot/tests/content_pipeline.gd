extends Node

var checks := 0
var failures := 0
var flow: Node


func _ready() -> void:
	SaveGame.use_storage("user://pipeline-tests/saves")
	for slot in [SaveGame.AUTOSAVE, "slot_1", "slot_2"]:
		SaveGame.erase_slot(slot)
	_check_schema()
	_check_save_v7()
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
	_check(migrated.version == SaveGame.VERSION and migrated.props.is_empty() and migrated.checkpoint == "cp_02"
		and migrated.soul == 41.0 and migrated.ink == 41.0 and migrated.killed == ["e1"]
		and migrated.weapon == "weapon.brush", "v4 migration retains progress")
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
	flow.player.ink = 96.0
	flow.player.global_position = shard.global_position - Vector2(0, 23)
	await _ticks(10)
	_check(flow.player.ink == 100.0 and flow.level.collected_props == ["shard_1"], "physical pickup clamps ink and is collected once")
	flow._flush_save()
	flow.continue_run()
	_check(_pickup() == null and flow.player.ink == 100.0, "pickup remains collected after save/load")
	flow.load_level("test_gallery")
	shard = _pickup()
	_check(shard != null, "a new run restores pickups")
	flow.player.ink = 100.0
	flow._autosave(false)
	flow.player.global_position = shard.global_position - Vector2(0, 23)
	await _ticks(10)
	flow._flush_save()
	_check(SaveGame.read_slot("auto").props == ["shard_1"], "pickup at full ink is still persisted")
	flow.player.iframes = 0.0
	flow.player.take_damage(Player.MAX_HP, 0.0)
	flow.respawn_run()
	_check(_pickup() == null and flow.player.ink == 0.0, "respawn keeps pickup state and resets ink")
	flow.qa_session = false
	flow._show_title()
	SaveGame.use_storage(previous)
	_check(SaveGame.read_slot("slot_1") == original and SaveGame.read_slot("auto").is_empty(), "QA does not touch story saves")
	flow.start_run()
	var before := SaveGame.read_slot("auto")
	flow.console.execute("set ink nope", true)
	_check(SaveGame.storage == previous and flow.player.ink == 0.0, "invalid command leaves session unchanged")
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


## Поля 0.6.1: новые значения по умолчанию не меняют старые карточки,
## enum не сдвигает записанные Kind, PGS стартует с базовыми числами 0.5.2.
func _check_schema() -> void:
	var stats := EntityStats.new()
	_check(stats.poise == 0 and stats.ink_reward == 0 and stats.armor == 0 and is_zero_approx(stats.shield_arc)
		and stats.parryable_melee and stats.parryable_projectile and stats.contact_damage,
		"entity stats defaults keep old cards unchanged")
	_check(AIProfile.Kind.CHASER == 1 and AIProfile.Kind.FLYER == 2 and AIProfile.Kind.TURRET == 3
		and AIProfile.Kind.BOSS == 4 and AIProfile.Kind.SHIELDER == 5 and AIProfile.Kind.TRAP == 10,
		"AI profile enum keeps stored values and appends new roles")
	var weapon := WeaponDef.new()
	_check(weapon.heavy_damage == 2 and is_equal_approx(weapon.heavy_windup, 0.10)
		and is_equal_approx(weapon.heavy_active, 0.14) and is_equal_approx(weapon.heavy_cooldown, 0.22)
		and weapon.heavy_reach == Vector2(80, 64) and weapon.heavy_ink_cost == 25
		and weapon.heavy_pierce == 0 and not weapon.heavy_marks and not weapon.ranged
		and weapon.projectile_scene == null and is_equal_approx(weapon.projectile_speed, 720.0)
		and weapon.ink_cost == 6 and weapon.pierce == 1,
		"weapon card gains heavy and ranged defaults")
	var old_prop := PDB.get_def(&"prop.soul_shard")
	_check(old_prop != null and old_prop.is_valid() and old_prop.kind == "pickup",
		"legacy pickup card still validates")
	if old_prop != null:
		var mark_prop := old_prop.duplicate() as PropDef
		mark_prop.kind = "mark"
		mark_prop.payload = &"mark.blot"
		_check(mark_prop.is_valid(), "mark prop accepts a payload")
		mark_prop.payload = &""
		_check(not mark_prop.is_valid(), "mark prop without payload is rejected")
	PGS.reset()
	_check(PGS.max_hp() == 5 and PGS.max_ink() == 100 and PGS.abilities.is_empty()
		and not PGS.has_ability(&"ability.double_jump"), "PGS starts with base health and ink")
	PGS.grant_ability(&"ability.double_jump")
	PGS.grant_ability(&"ability.double_jump")
	_check(PGS.abilities.size() == 1 and PGS.has_ability(&"ability.double_jump"),
		"abilities are granted once")
	PGS.shards = 9
	PGS.vessels = 3
	_check(PGS.max_hp() == 8 and PGS.max_ink() == 175, "shards and vessels raise caps to maximum")
	PGS.marks_owned.assign([&"mark.blot", &"mark.seal", &"mark.clean", &"mark.press"])
	_check(not PGS.equip_marks([&"mark.blot", &"mark.blot", &"mark.seal"]),
		"duplicate marks are rejected")
	_check(not PGS.equip_marks([&"mark.ghost"]), "unowned marks are rejected")
	_check(not PGS.equip_marks([&"mark.blot", &"mark.seal", &"mark.clean", &"mark.press"]),
		"a fourth mark is rejected")
	_check(PGS.marks_equipped.is_empty(), "failed equip leaves the loadout unchanged")
	_check(PGS.equip_marks([&"mark.blot", &"mark.seal"]), "two owned marks equip")
	var snapshot := PGS.save_dict()
	PGS.reset()
	PGS.load_dict(snapshot)
	_check(PGS.shards == 9 and PGS.vessels == 3 and PGS.has_ability(&"ability.double_jump")
		and PGS.marks_equipped.size() == 2 and PGS.marks_equipped.has(&"mark.blot"),
		"PGS state round-trips through save_dict")
	PGS.reset()


## Схема v7: ink заменяет soul, старые ключи и неизвестные поля не теряются.
func _check_save_v7() -> void:
	var v6 := {"version": 6, "level": "ch01_hall", "checkpoint": "cp_02", "hp": 7, "soul": 80.0,
		"killed": ["e1"], "triggers": ["archivist"], "props": ["shard_1"], "switches": ["lever"],
		"rooms": {"archive_annex": {"killed": []}}, "weapons": ["weapon.brush"], "weapon": "weapon.brush",
		"cleared": true, "finale_seen": true, "dead": false, "custom": "keep"}
	var migrated := SaveGame.migrate(v6)
	_check(migrated.version == 7 and migrated.ink == 80.0 and migrated.soul == 80.0 and migrated.hp == 5,
		"v6 migration turns soul into ink and caps hp")
	_check(migrated.abilities.is_empty() and migrated.shards == 0 and migrated.vessels == 0
		and migrated.marks_owned.is_empty() and migrated.marks_equipped.is_empty()
		and migrated.names.is_empty(), "v6 migration starts empty progression")
	_check(migrated.chapters_cleared == ["ch01_hall"] and migrated.map.is_empty()
		and migrated.ending == "" and not migrated.epilogue_seen and not migrated.ng_plus,
		"v6 migration adds chapter, map and ending fields")
	_check(migrated.killed == ["e1"] and migrated.triggers == ["archivist"] and migrated.props == ["shard_1"]
		and migrated.switches == ["lever"] and migrated.rooms.has("archive_annex") and migrated.custom == "keep",
		"v7 keeps legacy keys and unknown fields")
	var clamped := SaveGame.migrate({"version": 6, "level": "ch01_hall", "soul": 120.0, "hp": 9})
	_check(clamped.ink == 100.0 and clamped.hp == 5 and clamped.chapters_cleared.is_empty(),
		"v6 migration clamps ink and ignores uncleared chapters")
	var v1 := SaveGame.migrate({"version": 1})
	_check(v1.version == 7 and v1.checkpoint == "" and v1.killed.is_empty() and v1.ink == 0.0
		and v1.abilities.is_empty(), "v1 save still opens as v7")
	var v7 := SaveGame.migrate({"version": 7, "ink": 30.0, "hp": 2})
	_check(v7.version == 7 and v7.ink == 30.0 and v7.hp == 2 and not v7.has("soul"),
		"v7 migration does not write the legacy soul key")


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
