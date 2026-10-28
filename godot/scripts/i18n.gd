extends Node

## Локализация игры (автолоад L10N).
##
## Как добавить новый язык:
##   1. Скопируйте godot/locale/ru.json в godot/locale/<код>.json
##      (например fr.json, de.json, ja.json).
##   2. Переведите значения в блоке "strings". Ключи не трогайте.
##   3. Укажите "name" (название языка на нём самом) и "order"
##      (порядок в переключателе, 0 — сверху).
## Больше ничего менять не нужно: файл подхватится при запуске.
##
## Если ключ отсутствует в переводе, показывается русский текст,
## а в отладочной сборке выводится предупреждение.
##
## Выбор языка хранится в user://settings.cfg (секция [locale]).

const LOCALE_DIR := "res://locale"
const FALLBACK := "ru"

var lang := FALLBACK

var _strings := {}  # код языка -> { ключ: текст }
var _names := {}    # код языка -> название на самом языке
var _order := {}    # код языка -> порядок в списке
var _codes: Array[String] = []


func _ready() -> void:
	_load_locales()
	if not _strings.has(lang):
		lang = FALLBACK
	_audit()


func _load_locales() -> void:
	_strings.clear()
	_names.clear()
	_order.clear()
	_codes.clear()

	var dir := DirAccess.open(LOCALE_DIR)
	if dir == null:
		push_error("L10N: не найден каталог %s" % LOCALE_DIR)
		return

	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.get_extension().to_lower() == "json":
			var code := file.get_basename()
			var text := FileAccess.get_file_as_string(LOCALE_DIR + "/" + file)
			var data = JSON.parse_string(text)
			if data is Dictionary and data.get("strings") is Dictionary:
				_strings[code] = data["strings"]
				_names[code] = str(data.get("name", code))
				_order[code] = int(data.get("order", 100))
				_codes.append(code)
			else:
				push_error("L10N: не удалось прочитать %s" % file)
		file = dir.get_next()
	dir.list_dir_end()

	_codes.sort_custom(func(a: String, b: String) -> bool: return int(_order[a]) < int(_order[b]))


## Перевод по ключу. args — значения для подстановки через %.
func t(key: String, args: Array = []) -> String:
	var value = _strings.get(lang, {}).get(key)
	if value == null:
		value = _strings.get(FALLBACK, {}).get(key)
	if value == null:
		if OS.is_debug_build():
			push_warning("L10N: нет ключа '%s' (язык %s)" % [key, lang])
		return key
	var s := str(value)
	if args.is_empty():
		return s
	return s % args


func set_lang(code: String) -> void:
	if _strings.has(code):
		lang = code


func next_lang() -> void:
	if _codes.is_empty():
		return
	var i := _codes.find(lang)
	lang = _codes[(i + 1) % _codes.size()]


func prev_lang() -> void:
	if _codes.is_empty():
		return
	var i := _codes.find(lang)
	lang = _codes[(i - 1 + _codes.size()) % _codes.size()]


## Название текущего языка на нём самом (например «Русский»).
func lang_name() -> String:
	return str(_names.get(lang, lang))


func languages() -> Array[String]:
	return _codes.duplicate()


func has_lang(code: String) -> bool:
	return _strings.has(code)


## Список отсутствующих ключей по языкам (для ручной проверки переводов).
func audit() -> Dictionary:
	var report := {}
	var base: Dictionary = _strings.get(FALLBACK, {})
	for code in _codes:
		var missing: Array[String] = []
		for key in base.keys():
			if not _strings[code].has(key):
				missing.append(str(key))
		if not missing.is_empty():
			report[code] = missing
	return report


func _audit() -> void:
	if not OS.is_debug_build():
		return
	var report := audit()
	for code in report.keys():
		push_warning("L10N: в %s нет ключей: %s" % [code, ", ".join(PackedStringArray(report[code]))])
