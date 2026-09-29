extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("REWORK_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor
func wall_at(point:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(5,200)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func effect_for(actor):
	for child in actor.get_children():
		if child.has_method("replace_with_hit") and child.is_active_effect(): return child
	return null
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	sheep.health = 300
	sheep._observed_health = 300
	sheep._begin_grazing()
	sheep.visual_mob()
	check(sheep._grass_patch.get_child_count() == 1,"only one native grass sprite")
	check(sheep._grass_patch.get_node_or_null("GrassBlockTop") == null,"no floor tile")
	var tuft:Sprite2D = sheep._grass_patch.get_child(0)
	check(tuft.texture.resource_path.ends_with("short_grass.png"),"native Minecraft grass")
	sheep._graze(0.79)
	check(sheep.health == 300 and sheep._bite_serial == 0,"no healing before bite")
	check(get_nodes_in_group("SheepGrassBiteFX").is_empty(),"no particles between bites")
	sheep._graze(0.02)
	check(sheep.health == 310 and sheep._bite_serial == 1,"one bite one heal settlement")
	check(get_nodes_in_group("SheepGrassBiteFX").size() == 1,"one grass fragment burst per bite")
	var sounds:Dictionary = {}
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		sounds[player.get_meta("mc_sound_event","")] = true
	check(sounds.has("block.grass.break") and sounds.has("entity.generic.eat"),"bite plays grass and chewing audio")
	sheep.visual_mob()
	check(tuft.scale.y < 0.8 and sheep.image.rotation == 0,"grass and head react at bite")
	var tuft_root:Vector2 = tuft.to_global(tuft.get_rect().end)
	check(absf(tuft_root.y-sheep._graze_ground_position().y) < 0.01,"grass root anchored to actual feet ground")
	var ground_before:Vector2 = sheep._grass_patch.global_position
	sheep._bite_flash_left = 0.1
	sheep.visual_mob()
	check(absf(tuft.to_global(tuft.get_rect().end).y-ground_before.y) < 0.01,"bite squash never lifts grass roots")
	var debris = get_nodes_in_group("SheepGrassBiteFX")[0]
	var part:Dictionary = debris.parts[0]
	check(debris.particle_position(part,0.1).y < debris.particle_position(part,0.0).y and debris.particle_position(part,0.6).y > debris.particle_position(part,0.1).y,"grass fragments fall downward")
	check(is_equal_approx(debris.particle_position(part,debris.landing_time(part)+0.1).y,debris.floor_y),"fragments reach ground before disappearing")
	check(debris.particle_alpha(part,debris.landing_time(part)+0.6) > 0.9,"grounded fragments remain briefly visible")
	check(debris.parts.size() >= 7 and debris.parts.size() <= 10 and debris.z_index >= 100,"visible foreground native grass debris")
	var hp:int = sheep.health
	sheep._graze(0.4)
	check(sheep.health == hp,"health remains fixed between mouthfuls")
	game.now_stop_state = true
	sheep._graze(2)
	check(sheep.health == hp,"paused grazing gives no healing")
	game.now_stop_state = false
	sheep._graze(0.4)
	check(sheep.health == 320 and sheep._bite_serial == 2,"second mouthful settles once")
	var count:int = get_nodes_in_group("SheepGrassBiteFX").size()
	sheep._receive_graze_bite(2)
	check(get_nodes_in_group("SheepGrassBiteFX").size() == count,"duplicate network bite event has no duplicate effects")
	sheep.receive_positional_damage(10,Vector2.ZERO,false,null)
	hp = sheep.health
	sheep._graze(2)
	check(sheep.health == hp and sheep._graze_elapsed == 0,"damage cancels pending bite without delayed heal")
	sheep.health = sheep.Max_health-1
	sheep.ram_state = sheep.RamState.GRAZE
	sheep._graze(0.8)
	check(sheep.health == sheep.Max_health and sheep.ram_state == sheep.RamState.ROAM,"last bite clamps to max and finishes")
	check(not sheep._grass_patch.visible,"last bite removes single grass")
	print("SHEEP_BITE_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
