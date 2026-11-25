class_name AIProfile
extends Resource

## Тип поведения врага и его параметры. Код врага читает kind,
## а params остаются свободным словарём для конкретной реализации.

## Новые роли добавляются только в конец: CHASER=1…BOSS=4 уже записаны в карточках.
enum Kind { NONE, CHASER, FLYER, TURRET, BOSS, SHIELDER, DISRUPTOR, DUELIST, BURROWER, TANK, TRAP }

@export var kind: Kind = Kind.CHASER
@export var params: Dictionary = {}
