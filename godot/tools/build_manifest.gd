extends SceneTree

## Генерирует content/manifest.json из карточек content/entities и content/weapons.
## В экспортированной сборке EntityDatabase и WeaponDatabase читают этот файл.
## Запуск: Godot --headless --path godot --script res://tools/build_manifest.gd

const ENTITY_DIR := "res://content/entities"
const WEAPON_DIR := "res://content/weapons"
const OUT := "res://content/manifest.json"


func _initialize() -> void:
	var entries := {}
	var errors := 0
	var dir := DirAccess.open(ENTITY_DIR)
	if dir == null:
		printerr("manifest: нет папки " + ENTITY_DIR)
		quit(1)
		return

	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and (file.ends_with(".tres") or file.ends_with(".res")):
			var path := ENTITY_DIR + "/" + file
			var res: Resource = ResourceLoader.load(path)
			var def := res as EntityDef
			if def == null or not def.is_valid():
				printerr("manifest: пропущена карточка " + path)
				errors += 1
			elif entries.has(String(def.id)):
				printerr("manifest: дубликат id %s (%s)" % [def.id, path])
				errors += 1
			else:
				entries[String(def.id)] = {
					"path": path,
					"type": "EntityDef",
					"category": int(def.category),
					"version": def.version,
					"hash": FileAccess.get_sha256(path),
				}
		file = dir.get_next()
	dir.list_dir_end()

	var weapons := _scan_weapons()
	errors += int(weapons.get("errors", 0))
	var weapon_entries: Dictionary = weapons.get("entries", {})

	var manifest := {
		"schema": 1,
		"entities": entries,
		"weapons": weapon_entries,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("manifest: не пишется " + OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(manifest, "  ", false) + "\n")
	f.close()

	print("manifest: %d карточек, %d оружия, ошибок %d -> %s" % [
		entries.size(), weapon_entries.size(), errors, OUT])
	quit(1 if errors > 0 else 0)


func _scan_weapons() -> Dictionary:
	var entries := {}
	var errors := 0
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		return {"entries": entries, "errors": 0}
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and (file.ends_with(".tres") or file.ends_with(".res")):
			var path := WEAPON_DIR + "/" + file
			var res: Resource = ResourceLoader.load(path)
			var def := res as WeaponDef
			if def == null or not def.is_valid():
				printerr("manifest: пропущено оружие " + path)
				errors += 1
			elif entries.has(String(def.id)):
				printerr("manifest: дубликат оружия %s (%s)" % [def.id, path])
				errors += 1
			else:
				entries[String(def.id)] = {
					"path": path,
					"type": "WeaponDef",
					"order": def.order,
					"hash": FileAccess.get_sha256(path),
				}
		file = dir.get_next()
	dir.list_dir_end()
	return {"entries": entries, "errors": errors}
