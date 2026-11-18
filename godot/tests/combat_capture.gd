extends Node2D
class Room extends Level:
 func _ready() -> void:
  pass
func _ready() -> void:
 var room := Room.new()
 add_child(room)
 var floor := Polygon2D.new()
 floor.polygon = PackedVector2Array([Vector2(0,320),Vector2(1000,320),Vector2(1000,500),Vector2(0,500)])
 floor.color = Color("#4a4136")
 room.add_child(floor)
 var camera := Camera2D.new()
 camera.position = Vector2(490,265)
 camera.zoom = Vector2(2,2)
 add_child(camera)
 var players: Array[Player] = []
 for i in 3:
  var p := preload("res://scenes/actors/player.tscn").instantiate() as Player
  p.position = Vector2(250+i*110,297)
  room.add_child(p)
  p.set_physics_process(false)
  players.append(p)
 players[0]._try_attack()
 players[0].attack_t = 0.12
 players[1].healing = true
 players[1].heal_t = 0.6
 players[2].hurt_t = 0.24
 players[2].iframes = 0.8
 var grunt := preload("res://scenes/actors/grunt.tscn").instantiate() as Grunt
 grunt.position = Vector2(580,297)
 room.add_child(grunt)
 grunt.set_physics_process(false)
 grunt.facing = -1
 grunt.attack_t = 0.12
 var sentry := preload("res://scenes/actors/sentry.tscn").instantiate() as Sentry
 sentry.position = Vector2(700,210)
 sentry.target = players[2]
 room.add_child(sentry)
 sentry.set_physics_process(false)
 sentry.shoot_t = 0.12
 var bolt := InkBolt.new()
 bolt.position = Vector2(640,250)
 bolt.velocity = Vector2(-360,180)
 room.add_child(bolt)
 bolt.set_physics_process(false)
 CombatFx.surface(players[0],Vector2(540,320),Vector2.UP,1.4)
 for i in 8:
  await get_tree().process_frame
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("res://../artifacts/combat")
 get_viewport().get_texture().get_image().save_png("res://../artifacts/combat/combat-preview.png")
 print("SHOT combat-preview")
 get_tree().quit()
