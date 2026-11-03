class_name WeaponDef
extends Resource

## Карточка оружия: числа и подача, без веток в коде игрока.
## Игрок читает карточку и применяет её к своему удару.
## Новое оружие = новый .tres в content/weapons, код не правится.

@export var id: StringName
## Ключ локализации для имени в HUD.
@export var display_name_key: String = ""
## Порядок в списке и переключении.
@export var order: int = 0

@export_group("Удар")
@export var damage: int = 1
## Пауза перед попаданием: у тяжёлого оружия заметнее.
@export var windup: float = 0.0
## Сколько длится сам взмах.
@export var active: float = 0.18
## Пауза после взмаха до следующего удара.
@export var cooldown: float = 0.08
@export var reach: Vector2 = Vector2(52, 44)
@export var knockback: float = 140.0
## Бьёт в обе стороны: нужно тяжёлой кисти.
@export var hit_both_sides: bool = false

@export_group("Вид")
@export var ink: Color = Color("#9c1f24")
@export var swing_radius: float = 38.0
@export var swing_width: float = 3.0


func is_valid() -> bool:
	return not id.is_empty() and not display_name_key.is_empty()
