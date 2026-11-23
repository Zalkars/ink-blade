class_name PropDef
extends Resource

@export var id: StringName
@export var kind := "pickup"
@export var scene: PackedScene
@export var version := 1
@export var display_name_key: String
@export_range(1, 99) var soul_amount := 10


func is_valid() -> bool:
	return not id.is_empty() and kind == "pickup" and scene != null and version == 1 \
		and not display_name_key.is_empty() and soul_amount >= 1 and soul_amount <= 99
