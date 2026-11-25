class_name PropDef
extends Resource

## kind остаётся строкой: старые карточки и валидатор не переписываются.
const KINDS := ["pickup", "heart_shard", "ink_vessel", "mark", "name", "weapon", "key"]
const PAYLOAD_KINDS := ["mark", "name", "weapon", "key"]

@export var id: StringName
@export var kind := "pickup"
@export var scene: PackedScene
@export var version := 1
@export var display_name_key: String
## Для "pickup" это количество чернил; поле не переименовывается до 0.8.
@export_range(1, 99) var soul_amount := 10
@export var amount := 1
## ID пометки, имени, оружия или ключа.
@export var payload: StringName


func is_valid() -> bool:
	if id.is_empty() or scene == null or version != 1 or display_name_key.is_empty():
		return false
	if not kind in KINDS or amount < 1:
		return false
	if kind in PAYLOAD_KINDS and payload.is_empty():
		return false
	if kind == "pickup" and (soul_amount < 1 or soul_amount > 99):
		return false
	return true
