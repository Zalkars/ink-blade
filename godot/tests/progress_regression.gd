extends Node2D

## Run with an isolated APPDATA: this test writes the autosave slot.
var checks := 0
var failures := 0
var flow

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["OK" if ok else "FAIL", label])

func fresh() -> void:
	flow.start_run()
	flow.host.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	fresh()
	flow.level.fired_triggers.append("archivist")
	flow._on_trigger("archivist", flow.level.triggers[0])
	check(flow.dialogue.visible and not flow.player.has_weapon("weapon.brush"), "reward waits for dialogue completion")
	flow.dialogue.advance()
	flow.dialogue.advance()
	check(SaveGame.read_slot("auto").dialogue.line == 2, "dialogue line saved before interruption")
	flow.continue_run()
	check(flow.dialogue.visible and flow.dialogue.index == 2 and not flow.player.has_weapon("weapon.brush"), "interrupted dialogue resumes current line without early reward")
	# Simulate relaunch by discarding the entire root, not only reloading its level.
	flow.free()
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	flow.continue_run()
	check(flow.dialogue.visible and flow.dialogue.index == 2, "dialogue survives root recreation")
	while flow.dialogue.visible:
		flow.dialogue.advance()
	check(flow.player.has_weapon("weapon.brush") and SaveGame.read_slot("auto").dialogue.is_empty(), "completed dialogue grants brush and clears pending progress")
	flow.continue_run()
	check(flow.player.has_weapon("weapon.brush") and not flow.dialogue.visible, "completed dialogue does not replay")
	var old_save := SaveGame.read_slot("auto")
	old_save["version"] = 2
	old_save["weapons"] = ["weapon.blade"]
	old_save["weapon"] = "weapon.blade"
	old_save.erase("soul")
	old_save.erase("dialogue")
	SaveGame.write_slot("auto", old_save)
	flow.continue_run()
	check(flow.player.has_weapon("weapon.brush") and flow.player.soul == 0, "old interrupted-dialogue save repaired")
	flow.player.soul = 80
	flow.player.hp = 2
	flow._autosave(false)
	flow.continue_run()
	flow.host.process_mode = Node.PROCESS_MODE_DISABLED
	check(flow.player.soul == 80, "healing resource survives continue")
	check(flow.player.hp == 2, "ordinary continue preserves saved HP")
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	flow.player.set_physics_process(false)
	for enemy in flow.level.enemies:
		enemy.set_physics_process(false)
	for tick in 4:
		await get_tree().physics_frame
	check(flow.player.hp == 2, "loaded checkpoint overlap does not heal on first physics frames")
	flow.host.process_mode = Node.PROCESS_MODE_DISABLED
	check(CTL.set_key("jump", KEY_P), "rebind jump")
	check(flow.hud.hint.is_empty() and "P" in flow.control_guide.binding("jump"), "bindings update in guide without HUD keyboard clutter")
	CTL.reset_bindings()
	var p: Player = flow.player
	p.attack_cd = 0
	p._try_attack()
	var recovery: float = p.attack_cd
	p.next_weapon()
	p.next_weapon()
	check(recovery > 0 and is_equal_approx(p.attack_cd, recovery), "switch roundtrip retains attack recovery")
	p._try_attack()
	check(p.attack_t == 0, "cannot attack again during retained recovery")
	for kind in ["grunt", "blot", "sentry", "keeper"]:
		var id: String = "boss.keeper" if kind == "keeper" else "enemy." + kind
		var e = DB.instantiate(StringName(id))
		flow.level.add_child(e)
		e.set_physics_process(false)
		if e.has_method("open_seal"):
			e.open_seal()
		var x: float = e.position.x
		e.hit(1, 1, 140)
		check(e.position.x > x if kind == "sentry" else e.velocity.x > 0, kind + " knocked right")
		x = e.position.x
		e.hp = 10
		e.hit(1, -1, 140)
		check(e.position.x < x if kind == "sentry" else e.velocity.x < 0, kind + " knocked left")
		e.queue_free()
	# Keep bodies in physics while freezing their AI and movement.
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	flow.level.set_physics_process(false)
	for e in flow.level.enemies:
		e.set_physics_process(false)
	p.set_physics_process(false)
	p.position = Vector2(2000, 300)
	p.facing = 1
	p.attack_cd = 0
	p._try_attack()
	var target = DB.instantiate(&"enemy.grunt")
	target.position = Vector2(2040, 300)
	target.hp = 10
	flow.level.add_child(target)
	target.set_physics_process(false)
	var wall := StaticBody2D.new()
	wall.position = Vector2(2020, 300)
	wall.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 100)
	collision.shape = shape
	wall.add_child(collision)
	flow.level.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	p._strike()
	check(target.hp == 10, "wall blocks melee damage")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	p._strike()
	check(target.hp < 10, "same target takes damage after wall removed")
	target.queue_free()
	await get_tree().physics_frame
	var victim = flow.level.enemies[0]
	victim.position = Vector2(2040, 300)
	victim.hp = 1
	p.soul = 0
	p._hit_targets.clear()
	await get_tree().physics_frame
	p._strike()
	await get_tree().process_frame
	check(p.soul == 12 and SaveGame.read_slot("auto").soul == 12, "killing blow soul included in autosave")
	# Kill all placements but the final splitting enemy, then reload mid-split.
	fresh()
	var last
	for e in flow.level.enemies:
		if String(e.get_meta("placement_id")) == "e27":
			last = e
	for e in flow.level.enemies.duplicate():
		if e == last:
			continue
		if e.has_method("open_seal"):
			e.open_seal()
		e.hit(999, 1)
	for e in flow.level.enemies.duplicate():
		if e != last:
			e.hit(999, 1)
	last.hit(999, 1)
	check(flow.level.enemy_count() == 2 and not SaveGame.read_slot("auto").cleared, "save during last enemy split")
	flow.continue_run()
	check(flow.level.enemy_count() == 0 and flow.cutscene.visible, "empty loaded level starts finale")
	check(SaveGame.read_slot("auto").cleared, "empty loaded level saves completion")
	await get_tree().process_frame
	check(SaveGame.read_slot("auto").cleared, "deferred combat save cannot undo completion")
	fresh()
	flow.player.position.x = -100
	flow._check_world_bounds()
	check(flow.player.position.x >= 0, "left boundary contains player")
	flow.player.position.x = 15000
	flow._check_world_bounds()
	check(flow.player.position.x < flow.level.bounds.end.x, "right boundary contains player")
	flow.player.iframes = 999
	flow.player.position.y = 2000
	flow._check_world_bounds()
	check(flow.player.dead and flow.state == flow.State.DEAD, "fall ends run even with invulnerability")
	# Recover the interrupted rename state, then preserve a healthy backup.
	SaveGame.erase_slot("regression")
	SaveGame.write_slot("regression", {"hp": 4})
	var path := ProjectSettings.globalize_path("user://saves/regression.json")
	DirAccess.rename_absolute(path, path + ".bak")
	check(SaveGame.has_slot("regression") and SaveGame.read_slot("regression").hp == 4, "backup-only save recovered")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	check(SaveGame.read_slot("regression").hp == 4, "corrupt primary falls back to backup")
	check(SaveGame.write_slot("regression", {"hp": 5}), "write after backup recovery")
	DirAccess.remove_absolute(path)
	check(SaveGame.read_slot("regression").hp == 4, "write preserves healthy backup of corrupt primary")
	SaveGame.erase_slot("regression")
	check(not SaveGame.has_slot("regression"), "erase removes backup too")

	# Surface ink survives disk JSON, a new root, and death; a new run is clean.
	fresh()
	CombatFx.surface(flow.player, Vector2(128.0, 576.0), Vector2.UP)
	flow._pause()
	var saved_ink: Array = SaveGame.read_slot("auto").get("ink_marks", [])
	check(not saved_ink.is_empty(), "pause flushes surface ink to save without an enemy kill")
	flow.free()
	flow = preload("res://scenes/flow/game_flow.tscn").instantiate()
	add_child(flow)
	flow.continue_run()
	check(JSON.parse_string(JSON.stringify(CombatFx.layer(flow.player).export_state())) == saved_ink, "surface ink survives application root recreation and JSON roundtrip")
	flow._on_player_died()
	flow.respawn_run()
	check(JSON.parse_string(JSON.stringify(CombatFx.layer(flow.player).export_state())) == saved_ink, "death keeps surface ink")
	flow.start_run()
	check(CombatFx.layer(flow.player).export_state().is_empty(), "new run clears old ink")

	# M1: damage to 1 HP + enemy kill -> die -> continue restores MAX_HP.
	fresh()
	flow.player.hp = 1
	flow.player.soul = 63
	flow._on_enemy_died("e1")
	flow._on_player_died()
	flow.continue_run()
	check(flow.player.hp == flow.player.MAX_HP, "continue after death restores full HP")
	check(flow.player.soul == 0, "death resets soul even after app-style continue")
	flow.player.hp = 1
	flow.player.soul = 45
	flow._on_player_died()
	flow._on_overlay_choice("checkpoint")
	check(flow.player.hp == flow.player.MAX_HP and flow.player.soul == 0, "death overlay restores full HP with zero soul")

	# M1: cleared without finale_seen keeps Continue and replays finale; finishing finale marks finale_seen.
	fresh()
	flow._on_cleared()
	flow.cutscene.advance()
	var mid_finale := SaveGame.read_slot(SaveGame.AUTOSAVE)
	check(bool(mid_finale.get("cleared", false)) and not bool(mid_finale.get("finale_seen", false)), "cleared mid-finale marks finale_seen false")
	flow.title_screen.refresh()
	check(flow.title_screen.actions.has("continue"), "title keeps Continue until finale finishes")
	flow.continue_run()
	check(flow.cutscene.visible and flow.state == flow.State.CUTSCENE, "continue with unseen finale replays finale")
	check(flow.cutscene.index == 0, "interrupted finale replays from first slide")
	while flow.cutscene.visible:
		flow.cutscene.advance()
	var post_finale := SaveGame.read_slot(SaveGame.AUTOSAVE)
	check(bool(post_finale.get("cleared", false)) and bool(post_finale.get("finale_seen", false)), "finishing finale writes finale_seen")
	flow.title_screen.refresh()
	check(not flow.title_screen.actions.has("continue"), "title hides Continue after finale seen")

	# M1: Play over unfinished autosave asks confirmation and keeps .bak.
	fresh()
	flow.player.soul = 44.0
	flow._autosave(false)
	flow.title_screen.refresh()
	flow.title_screen.visible = true
	flow.title_screen.selected = 0
	flow.title_screen.input_guard = 0.0
	flow.title_screen.activate(0)
	check(flow.title_screen._confirm_play and flow.title_screen.visible, "Play over unfinished save asks confirmation")
	check(flow.title_screen.handle_back() and not flow.title_screen._confirm_play, "Back cancels overwrite confirmation")
	flow.title_screen.input_guard = 0.0
	flow.title_screen.activate(0)
	check(flow.title_screen._confirm_play, "first Play press arms confirmation again")
	check(flow.title_screen.actions[flow.title_screen.selected] == "cancel_new", "overwrite confirmation defaults to Cancel")
	flow.title_screen.input_guard = 0.0
	flow.title_screen.activate(0)
	check(not flow.title_screen._confirm_play and SaveGame.read_slot("auto").soul == 44, "repeated confirm on safe default preserves save")
	flow.title_screen.activate(0)
	flow.title_screen.input_guard = 0.0
	flow.title_screen.activate(flow.title_screen.actions.find("confirm_new"))
	check(not flow.title_screen.visible and flow.state == flow.State.CUTSCENE, "explicit overwrite choice starts new intro")
	while flow.cutscene.visible:
		flow.cutscene.advance()
	var guided_level = flow.level
	check(flow.state == flow.State.GUIDE and flow.hud.visible and guided_level != null, "controls guide overlays the actual loaded level")
	flow.control_guide._guard = 0.0
	flow.control_guide.dismiss()
	check(flow.state == flow.State.PLAY and flow.level == guided_level and not flow.control_guide.visible, "guide dismissal resumes same level without another intro")
	check(FileAccess.file_exists("user://saves/auto.json.bak"), "backup preserved on overwrite")

	# M1: Manual save slot save, summary, and load.
	SaveGame.erase_slot("slot_1")
	fresh()
	flow.player.soul = 72.0
	check(flow.save_to_slot("slot_1"), "manual slot saves")
	check(not SaveGame.slot_summary("slot_1").contains(L10N.t("ui.slots.empty")), "slot summary reads saved state")
	flow.player.soul = 0.0
	flow.continue_run("slot_1")
	check(is_equal_approx(flow.player.soul, 72.0), "loading manual slot restores progress")
	SaveGame.erase_slot("slot_1")
	SaveGame.erase_slot(SaveGame.AUTOSAVE)
	SaveGame.current_slot = SaveGame.AUTOSAVE

	# M4 P2: dash iframes, air dash indicator, one-way drop-through, hitstop & level load.
	check(flow.load_level("arena_01") and flow.level_id == "arena_01", "load_level switches to arena_01")
	fresh()
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	var pd: Player = flow.player
	pd.dash_cd = 0.0
	pd.iframes = 0.0
	var hp_before_dash := pd.hp
	pd._try_dash()
	check(pd.iframes >= 0.18, "dash grants >=0.18s iframes")
	pd.take_damage(1, 1.0)
	check(pd.hp == hp_before_dash, "dash iframes block damage")

	# Air dash ready drop-off & ground recovery.
	fresh()
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	var pa: Player = flow.player
	pa.global_position = Vector2(592.0, 260.0)
	pa.velocity = Vector2.ZERO
	await get_tree().physics_frame
	check(not pa.is_on_floor() and pa.air_dash and pa.dash_ready() > 0.9, "airborne player starts with ready air dash")
	pa._try_dash()
	await get_tree().physics_frame
	check(not pa.air_dash and is_zero_approx(pa.dash_ready()), "air dash reports 0.0 ready in air after spending")
	for i in 240:
		await get_tree().physics_frame
		if pa.is_on_floor():
			break
	# air_dash restores on the next tick after move_and_slide reports the floor.
	await get_tree().physics_frame
	check(pa.is_on_floor() and pa.air_dash, "landing restores air dash")

	# Use an actual one-way platform from the current layout.
	fresh()
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	var po: Player = flow.player
	for enemy in flow.level.enemies:
		enemy.set_physics_process(false)
	var platform: Dictionary = flow.level.data.one_ways[0]
	po.global_position = Vector2(float(platform.x) + float(platform.w) * 0.5, float(platform.y) - 31.0)
	po.velocity = Vector2.ZERO
	for i in 30:
		await get_tree().physics_frame
		if po.is_on_floor():
			break
	check(po.is_on_floor() and po._on_one_way_only(), "player stands strictly on one-way platform")
	var y_on_platform := po.global_position.y
	var dropped := po.try_drop_through()
	for i in 90:
		await get_tree().physics_frame
	check(dropped and po.global_position.y > y_on_platform + float(platform.h) + 46.0 and po.collision_mask == po.GROUND_MASK,
		"down + jump drops through one-way platform and restores mask")
	# Solid floor never lets the player drop through.
	check(po.is_on_floor() and not po.try_drop_through(), "solid floor blocks drop-through")

	# Hitstop triggers on blade hit and decays back to zero.
	fresh()
	flow.host.process_mode = Node.PROCESS_MODE_PAUSABLE
	var ph: Player = flow.player
	var grunt = DB.instantiate(&"enemy.grunt")
	flow.level.add_child(grunt)
	grunt.set_physics_process(false)
	grunt.global_position = ph.global_position + Vector2(36.0, 0.0)
	ph.facing = 1
	ph.equip_weapon("weapon.blade")
	ph.attack_cd = 0.0
	ph._try_attack()
	var saw_hitstop := false
	for i in 10:
		await get_tree().physics_frame
		if flow.hitstop > 0.0:
			saw_hitstop = true
			break
	for i in 20:
		await get_tree().physics_frame
	check(saw_hitstop and is_zero_approx(flow.hitstop), "blade hit triggers hitstop and decays to 0")

	print("PROGRESS_REGRESSION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
