extends InkPlayer

## Presentation only: the actor owns movement, combat and collisions.
var ground_y := 720.0

func blade_angle() -> float:
	if attack == null:
		return super.blade_angle()
	var angle := super.blade_angle()
	var a: Dictionary = attack
	if a.has("recover"):
		var recovery := clampf((a.t - a.windup - a.active) / maxf(a.recover, 0.001), 0, 1)
		return lerp_angle(angle, 1.02, recovery * recovery * (3.0 - 2.0 * recovery))
	return angle

func draw() -> void:
	InkR.save()
	var lean := -hurt_t * 32.0
	if attack != null:
		lean += sin(clampf((attack.t - attack.windup) / maxf(attack.active, 0.001), 0, 1) * PI) * 9.0
	InkR.t_translate(cx(), y + h)
	InkR.t_rotate_deg(lean * facing)
	InkR.t_translate(-cx(), -y - h)
	super.draw()
	InkR.restore()

func shadow_y() -> float:
	return ground_y
