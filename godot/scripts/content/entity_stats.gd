class_name EntityStats
extends Resource

## Числовые параметры карточки. Отдельный ресурс, чтобы один и тот же набор
## можно было переиспользовать и переопределять в уровнях.

@export var max_hp: int = 1
@export var damage: int = 1
@export var speed: float = 0.0
@export var aggression_radius: float = 0.0
@export var telegraph_time: float = 0.0

## Поля 0.6. Значения по умолчанию сохраняют поведение старых карточек.
@export var poise: int = 0
@export var ink_reward: int = 0
@export var parryable_melee: bool = true
@export var parryable_projectile: bool = true
@export var armor: int = 0
@export var shield_arc: float = 0.0
@export var contact_damage: bool = true
