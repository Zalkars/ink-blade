class_name SaveGame
extends RefCounted

## Заготовка сохранений: слотовая схема с самого начала, JSON в user://saves.
## В каркасе работает один автосейв; ручные слоты включатся вместе с меню профиля.
## Запись атомарная: tmp -> rename, предыдущая версия уходит в .bak.

const VERSION := 1
const DIR := "user://saves"
const AUTOSAVE := "auto"


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _slot_path(slot: String, suffix: String = ".json") -> String:
	return "%s/%s%s" % [DIR, slot, suffix]


static func _ensure_dir() -> bool:
	var dir := _abs(DIR)
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK


static func write_slot(slot: String, data: Dictionary) -> bool:
	if not _ensure_dir():
		push_error("save: не создаётся папка " + DIR)
		return false
	var payload := {"version": VERSION, "saved_at": int(Time.get_unix_time_from_system())}
	payload.merge(data, true)

	var path := _abs(_slot_path(slot))
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("save: не открывается " + tmp)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(_slot_path(slot)):
		DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")

	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("save: не удалось заменить слот " + slot)
		return false
	return true


static func read_slot(slot: String) -> Dictionary:
	if not has_slot(slot):
		return {}
	var text := FileAccess.get_file_as_string(_slot_path(slot))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("save: слот " + slot + " не читается, берём .bak")
		var bak := FileAccess.get_file_as_string(_slot_path(slot, ".json.bak"))
		parsed = JSON.parse_string(bak)
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
	var version := int(parsed.get("version", 0))
	if version > VERSION:
		push_warning("save: слот новее игры (%d > %d)" % [version, VERSION])
	return parsed


static func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


static func erase_slot(slot: String) -> void:
	DirAccess.remove_absolute(_abs(_slot_path(slot)))
