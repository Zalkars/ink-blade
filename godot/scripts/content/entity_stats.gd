class_name EntityStats
extends Resource

## Числовые параметры карточки. Отдельный ресурс, чтобы один и тот же набор
## можно было переиспользовать и переопределять в уровнях.

@export var max_hp: int = 1
@export var damage: int = 1
@export var speed: float = 0.0
@export var aggression_radius: float = 0.0
@export var telegraph_time: float = 0.0
