class_name InkBakeNode
extends Node2D

## Узел для запекания больших статичных картинок (бумага/зал/титульный экран)
## в SubViewport — аналог Ink.Bake / World.Bake / Game.BakeTitle в оригинале.

var w := 0.0
var h := 0.0
var fn: Callable = Callable()


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
