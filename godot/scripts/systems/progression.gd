extends Node

## Скрипторий: постоянная прогрессия игрока.
## Хранит только то, что переживает смерть: способности, осколки, сосуды,
## пометки, имена и пройденные главы. Сцену не знает и в бою не участвует.
## Значения по умолчанию повторяют 0.5.2: 5 сердец и 100 чернил.

const BASE_MAX_HP := 5
const MAX_HP := 8
const BASE_MAX_INK := 100
const MAX_INK := 175
const INK_PER_VESSEL := 25
const SHARDS_PER_HEART := 3
const MAX_SHARDS := 9
const MAX_VESSELS := 3
const MARKS_SLOTS := 3

var abilities: Array[StringName] = []
var shards := 0
var vessels := 0
var marks_owned: Array[StringName] = []
var marks_equipped: Array[StringName] = []
var names: Array[StringName] = []
var chapters_cleared: Array[StringName] = []


func reset() -> void:
	abilities.clear()
	shards = 0
	vessels = 0
	marks_owned.clear()
	marks_equipped.clear()
	names.clear()
	chapters_cleared.clear()


func has_ability(id: StringName) -> bool:
	return abilities.has(id)


func grant_ability(id: StringName) -> void:
	if not id.is_empty() and not abilities.has(id):
		abilities.append(id)


func max_hp() -> int:
	return clampi(BASE_MAX_HP + floori(float(shards) / SHARDS_PER_HEART), BASE_MAX_HP, MAX_HP)


func max_ink() -> int:
	return clampi(BASE_MAX_INK + vessels * INK_PER_VESSEL, BASE_MAX_INK, MAX_INK)


## Экипировка атомарная: при любой ошибке текущий набор остаётся прежним.
func equip_marks(ids: Array) -> bool:
	var next: Array[StringName] = []
	for raw in ids:
		var id := StringName(str(raw))
		if id.is_empty() or not marks_owned.has(id) or next.has(id):
			return false
		next.append(id)
	if next.size() > MARKS_SLOTS:
		return false
	marks_equipped = next
	return true


## Пометки появятся в 0.8. API фиксируем сейчас, чтобы бой не обрастал условиями.
func bonus_for(_kind: StringName, _context: Dictionary = {}) -> float:
	return 0.0


func save_dict() -> Dictionary:
	return {
		"abilities": _strings(abilities),
		"shards": shards,
		"vessels": vessels,
		"marks_owned": _strings(marks_owned),
		"marks_equipped": _strings(marks_equipped),
		"names": _strings(names),
		"chapters_cleared": _strings(chapters_cleared),
	}


## Читает данные v7 терпимо: неизвестные ID и дубликаты отбрасываются,
## счётчики зажимаются, битый набор пометок не ломает загрузку.
func load_dict(data: Dictionary) -> void:
	reset()
	abilities = _read_ids(data.get("abilities"))
	shards = clampi(int(data.get("shards", 0)), 0, MAX_SHARDS)
	vessels = clampi(int(data.get("vessels", 0)), 0, MAX_VESSELS)
	marks_owned = _read_ids(data.get("marks_owned"))
	names = _read_ids(data.get("names"))
	chapters_cleared = _read_ids(data.get("chapters_cleared"))
	for id in _read_ids(data.get("marks_equipped")):
		if marks_owned.has(id) and marks_equipped.size() < MARKS_SLOTS:
			marks_equipped.append(id)


func _read_ids(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not value is Array:
		return out
	for raw in value:
		if not raw is String and not raw is StringName:
			continue
		var id := StringName(str(raw))
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


func _strings(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out
