class_name LootEntry
extends Resource

## Одна строка таблицы добычи: что, с какой вероятностью, сколько.

@export var item_id: StringName
@export_range(0.0, 1.0) var chance: float = 1.0
@export var amount: int = 1
