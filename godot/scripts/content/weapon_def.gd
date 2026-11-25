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

@export_group("Тяжёлый удар")
@export var heavy_damage: int = 2
@export var heavy_windup: float = 0.10
@export var heavy_active: float = 0.14
@export var heavy_cooldown: float = 0.22
@export var heavy_reach: Vector2 = Vector2(80, 64)
@export var heavy_ink_cost: int = 25
@export var heavy_pierce: int = 0
@export var heavy_marks: bool = false

@export_group("Дальний бой")
@export var ranged: bool = false
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 720.0
@export var ink_cost: int = 6
@export var pierce: int = 1

@export_group("Вид")
@export var ink: Color = Color("#9c1f24")
@export var swing_radius: float = 38.0
@export var swing_width: float = 3.0


func is_valid() -> bool:
	return not id.is_empty() and not display_name_key.is_empty()
