class_name EntityDef
extends Resource

## Карточка контента: враг, босс, проп, триггер или пикап.
## Новый враг = новая карточка + сцена из готовых компонентов, без правки кода.

enum Category { ENEMY, BOSS, PROP, TRIGGER, PICKUP }

@export var id: StringName
@export var display_name_key: String
@export var category: Category = Category.ENEMY
@export var scene: PackedScene
@export var icon: Texture2D
@export var tags: PackedStringArray
@export var stats: EntityStats
@export var ai_profile: AIProfile
@export var loot: Array[LootEntry] = []
@export var sfx: Dictionary = {}
@export var vfx: Dictionary = {}
@export var flags: Dictionary = {}
## Поля, которые уровню разрешено переопределять у конкретного экземпляра.
@export var overridable: PackedStringArray = PackedStringArray(["max_hp", "damage", "speed"])
@export var version: int = 1


func is_valid() -> bool:
	return not id.is_empty() and scene != null


## Проверка переопределения: поле должно быть объявлено в карточке.
func allows_override(field: String) -> bool:
	return overridable.has(field)
