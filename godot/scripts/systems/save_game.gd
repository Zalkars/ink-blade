class_name SaveGame
extends RefCounted

## Сохранения: слотовая схема с самого начала, JSON в user://saves.
## Поддерживаются автосейв и три ручных слота; запись атомарная: tmp -> rename, предыдущая версия уходит в .bak.

const VERSION := 4
const DIR := "user://saves"
const AUTOSAVE := "auto"
const MANUAL_SLOTS := ["slot_1", "slot_2", "slot_3"]

static var current_slot := AUTOSAVE


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
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false

	if FileAccess.file_exists(_slot_path(slot)):
		# Never overwrite a healthy backup with an unreadable primary.
		if not _read_file(_slot_path(slot)).is_empty():
			if FileAccess.file_exists(path + ".bak") and DirAccess.remove_absolute(path + ".bak") != OK:
				return false
			if DirAccess.rename_absolute(path, path + ".bak") != OK:
				return false
		elif DirAccess.remove_absolute(path) != OK:
			return false

	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.copy_absolute(path + ".bak", path)
		push_error("save: не удалось заменить слот " + slot)
		return false
	return true


static func read_slot(slot: String) -> Dictionary:
	var parsed := _read_file(_slot_path(slot))
	if parsed.is_empty():
		parsed = _read_file(_slot_path(slot, ".json.bak"))
	if parsed.is_empty():
		return {}
	var version := int(parsed.get("version", 0))
	if version > VERSION:
		push_warning("save: слот новее игры (%d > %d)" % [version, VERSION])
	return parsed


static func has_slot(slot: String) -> bool:
	return not read_slot(slot).is_empty()


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


## Приводит старый слот к текущей схеме. Новые поля получают безопасные значения,
## поэтому сейв версии 1 (без чекпоинта) и версии 2 продолжает читаться.
static func migrate(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var version := int(out.get("version", 1))
	if version < 2:
		if not out.has("checkpoint"):
			out["checkpoint"] = ""
		if typeof(out.get("killed")) != TYPE_ARRAY:
			out["killed"] = []
		out["version"] = 2
	if typeof(out.get("triggers")) != TYPE_ARRAY:
		out["triggers"] = []
	if typeof(out.get("weapons")) != TYPE_ARRAY:
		out["weapons"] = []
	if typeof(out.get("grants")) != TYPE_ARRAY:
		var inferred: Array = []
		for w in out["weapons"]:
			var wid := String(w)
			if wid != "weapon.blade" and not wid.is_empty() and not inferred.has(wid):
				inferred.append(wid)
		out["grants"] = inferred
	if not out.has("weapon"):
		out["weapon"] = ""
	out["soul"] = clampf(float(out.get("soul", 0.0)), 0.0, 99.0)
	out["finale_seen"] = bool(out.get("finale_seen", false))
	if typeof(out.get("dialogue")) != TYPE_DICTIONARY:
		out["dialogue"] = {}
	if typeof(out.get("ink_marks")) != TYPE_ARRAY:
		out["ink_marks"] = []
	out["dead"] = bool(out.get("dead", false))
	if version <= VERSION:
		out["version"] = VERSION
	return out


## Слот считается незавершённым, если уровень ещё не зачищен либо финальная катсцена не досмотрена.
static func has_unfinished_run(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if not bool(data.get("cleared", false)):
		return true
	return not bool(data.get("finale_seen", false))


static func slot_summary(slot: String) -> String:
	var data := read_slot(slot)
	if data.is_empty():
		return L10N.t("ui.slots.empty")
	if bool(data.get("cleared", false)) and bool(data.get("finale_seen", false)):
		return L10N.t("ui.slots.cleared")
	var cp := String(data.get("checkpoint", ""))
	var zone_key := "zone.threshold.title"
	match cp:
		"cp_02":
			zone_key = "zone.archive.title"
		"cp_03":
			zone_key = "zone.gallery.title"
		"cp_04":
			zone_key = "zone.sanctum.title"
	var enemies_left := int(data.get("enemies_left", 0))
	return L10N.t("ui.slots.summary", [L10N.t(zone_key), enemies_left])


static func erase_slot(slot: String) -> void:
	for suffix in [".json", ".json.bak", ".json.tmp"]:
		var path := _abs(_slot_path(slot, suffix))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
