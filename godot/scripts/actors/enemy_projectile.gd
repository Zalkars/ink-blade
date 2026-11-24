class_name EnemyProjectile
extends Area2D

const ATTACK_LAYER := 16

var _done := false


func break_by_attack() -> bool:
	if _done or is_queued_for_deletion() or not _can_break():
		return false
	CombatFx.burst(self, global_position, Vector2.UP, InkR.RED, 12)
	InkFx.sparks(global_position.x, global_position.y, -PI * 0.5, 7, InkR.CREAM)
	_on_broken()
	return true


func _can_break() -> bool:
	return true


func _on_broken() -> void:
	_done = true
	queue_free()
