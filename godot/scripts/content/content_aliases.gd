class_name ContentAliases
extends Resource

## Переименования ID: старый ID -> новый ID. Загрузчик разворачивает цепочку,
## поэтому сохранения и старые уровни продолжают работать после переименования.

@export var map: Dictionary = {}
