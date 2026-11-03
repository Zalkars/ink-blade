class_name AIProfile
extends Resource

## Тип поведения врага и его параметры. Код врага читает kind,
## а params остаются свободным словарём для конкретной реализации.

enum Kind { NONE, CHASER, FLYER, TURRET }

@export var kind: Kind = Kind.CHASER
@export var params: Dictionary = {}
