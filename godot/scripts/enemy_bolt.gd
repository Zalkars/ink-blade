class_name InkBolt
extends RefCounted

## Снаряд — порт InkBolt

static var _next_id := 10000

var g = null
var id := ""
var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var r := 11.0
var life := 3.6
var dead := false
var t := 0.0
var trail: Array = []   # [{x, y, life}]

func _init(game, X: float, Y: float, VX: float, VY: float) -> void:
	g = game
	id = "p%d" % InkBolt._next_id
	InkBolt._next_id += 1
	x = X
	y = Y
	vx = VX
	vy = VY

func hitbox() -> Rect2:
	return Rect2(x - r, y - r, r * 2, r * 2)

func update(dt: float) -> void:
	t += dt
	life -= dt
	trail.append({"x": x, "y": y, "life": 0.28})
	if trail.size() > 12:
		trail.pop_front()
	for e in trail:
		e.life -= dt

	x += vx * dt
	y += vy * dt

	if life <= 0.0:
		kill(false)
		return
	var hb := hitbox()
	for s in InkWorld.solids:
		if hb.intersects(s):
			kill(true)
			return
	for s in InkWorld.oneways:
		if hb.intersects(s):
			kill(true)
			return
	if y > 720.0 or y < 0.0 or x < 0.0 or x > 1280.0:
		kill(false)

func kill(splat: bool) -> void:
	if dead:
		return
	dead = true
	if splat:
		InkFx.ink_burst(x, y, 7, 190.0, [InkR.INK, InkR.RED_DARK], 4.0, false, null, 0.0, 0.0, 1300.0, y + 30.0)
		SND.noise({"freq": 500.0, "dur": 0.1, "gain": 0.04, "type": "lowpass"})

func deflect() -> void:
	if dead:
		return
	InkFx.sparks(x, y, 0.0, 10, InkR.CREAM)
	InkFx.ring(x, y, 4, 30, InkR.GOLD, 0.25, 2)
	InkFx.text_fx(x, y - 10, "+", 18, InkR.GOLD, false)
	dead = true
	SND.deflect()

func draw() -> void:
	if dead:
		return
	var ink := InkR
	for i in range(trail.size()):
		var e: Dictionary = trail[i]
		var k: float = maxf(0.0, e.life / 0.28)
		ink.save()
		ink.srand(i + int(x))
		ink.blob(e.x, e.y, r * k * 0.8, ink.INK, null, 2.0, k * 0.5, 0.8, 10, 0.13, false)
		ink.restore()
	ink.srand(int(x))
	ink.blob(x, y, r, ink.INK, ink.INK, 1.5, 1.0, 1.2, 10, 0.12)
	ink.blob(x - 2, y - 1, r * 0.45, ink.RED, null, 2.0, 1.0, 0.5, 10, 0.13, false)
	ink.blob(x + 3, y - 4, 2.2, ink.CREAM, null, 2.0, 1.0, 0.2, 10, 0.13, false)
