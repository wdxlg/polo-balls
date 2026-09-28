extends SceneTree
## 仙人掌分节 (2026-09-29): unlimited growth until a wall stops it, +1 segment of HP / max HP per
## growth, shared effects, per-segment hurtboxes (independent hits, pooled HP) and per-segment flash.
var game:Node
var world:Node
var saved:Dictionary
var checks:int = 0
var failures:int = 0
var center:Vector2

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else: print("ok: ",label)

func seconds(t:float) -> void: await create_timer(t).timeout

func spawn(role:String,offset:Vector2,team:String) -> Node2D:
	var path:String = "res://scenes/characters/我的世界/" + role + ".tscn" if role != "" else "res://scenes/ball.tscn"
	var actor:Node2D = (load(path) as PackedScene).instantiate()
	actor.Team = team
	actor.position = center + offset
	world.add_child(actor,true)
	actor.Has_Collision_Damage = false
	actor.Speed = 0
	actor.default_properties["Speed"] = 0
	actor.velocity = Vector2.ZERO
	return actor

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func() -> void: finish())
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func() -> void: current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await seconds(0.5)
	var map_rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = map_rect.get_center()
	print("map rect ",map_rect)
	var base_y:float = map_rect.end.y - 80.0 - center.y # bottom segment near the bottom edge
	var cactus:Node2D = spawn("仙人掌",Vector2(0,base_y),"Team0")
	cactus.volley_interval = 999.0
	cactus.volley_left = 999.0
	cactus.contact_interval = 999.0
	cactus.growth_interval = 999.0
	await seconds(0.2)
	var seg_hp:int = cactus.segment_health
	check(seg_hp == 200 and cactus.levels == 1 and cactus.Max_health == 200,"starts as one segment with 200 HP (%d / %d)" % [cactus.health,cactus.Max_health])
	# one growth: +1 segment of HP and max HP
	cactus.health = 150
	cactus.growth_elapsed = cactus.growth_interval
	await seconds(0.1)
	check(cactus.levels == 2 and cactus.Max_health == 400 and cactus.health == 350,"growing adds one segment of health and max health (%d / %d)" % [cactus.health,cactus.Max_health])
	# no cap: well past the old 5
	for i:int in range(5):
		cactus.growth_elapsed = cactus.growth_interval
		await physics_frame
		await physics_frame
	check(cactus.levels == 7 and cactus.Max_health == seg_hp*7 and cactus.health == cactus.Max_health - 50,"no segment cap: 7 segments, max %d HP" % cactus.Max_health)
	var anchor:Vector2 = cactus.global_position
	check(cactus.get_node("CollisionShape2D").shape.size.y == 96.0*7,"collision grows with every segment")
	await process_frame
	check(cactus._segment_sprites.size() == 7 and cactus.image.get_child_count() >= 6,"one sprite per segment (%d)" % cactus._segment_sprites.size())
	check(cactus._segment_hurtboxes.size() == 7 and cactus.self_hurtbox.collision_layer == 0 and cactus._segment_hurtboxes[6].collision_layer != 0,"one hurtbox per segment; hitboxes see the segments")
	# a wall right above the top stops growth
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200,20)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = cactus.to_global(Vector2(0,48.0 - 96.0*7 - 40.0))
	await physics_frame
	await physics_frame
	cactus.growth_elapsed = cactus.growth_interval
	await seconds(0.1)
	check(cactus.levels == 7 and cactus.growth_blocked,"a wall above stops the growth (%d)" % cactus.levels)
	var blocker:Node2D = spawn("",Vector2.ZERO,"Team1")
	blocker.global_position = cactus.to_global(Vector2(0,-96.0*7))
	blocker.collision_layer = 1
	wall.queue_free()
	await physics_frame
	cactus.growth_elapsed = cactus.growth_interval
	await seconds(0.1)
	check(cactus.levels == 8,"a unit above does not stop it; it grows again once the wall is gone (%d)" % cactus.levels)
	check(cactus.global_position.distance_to(anchor) < 0.5,"bottom stays put")
	blocker.queue_free()
	# shared visual state reaches every segment
	cactus.image.set_instance_shader_parameter(&"character_grayscale",0.7)
	await process_frame
	await process_frame
	check(absf(float(cactus._segment_sprites[5].get_instance_shader_parameter(&"character_grayscale")) - 0.7) < 0.01,"shared shader effects (e.g. grayscale / tint) show on every segment")
	cactus.image.set_instance_shader_parameter(&"character_grayscale",0.0)
	var status:Script = load("res://scripts/effects/我的世界/女巫药水效果.gd")
	status.apply_effect(cactus,"slowness",null,1,3.0)
	await physics_frame
	check(cactus.has_node("MinecraftStatus_slowness") or cactus.get_children().any(func(n:Node) -> bool: return String(n.name).to_lower().contains("slowness")),"a potion effect sits on the whole plant")
	# per-segment hits through the real hitbox path
	var attacker:Node2D = spawn("",Vector2(300,base_y),"Team1")
	attacker.Damage = 20
	attacker.default_properties["Damage"] = 20
	attacker.collision_layer = 0
	attacker.collision_mask = 0
	await physics_frame
	for i:int in range(cactus.levels): cactus.segment_flash[i] = 0.0
	var hp0:int = cactus.health
	var hb:Area2D = attacker.self_hitbox
	var a:bool = hb.try_hit_hurtbox(cactus._segment_hurtboxes[0])
	var d1:int = hp0 - cactus.health
	var b:bool = hb.try_hit_hurtbox(cactus._segment_hurtboxes[2])
	var d2:int = hp0 - d1 - cactus.health
	var c:bool = hb.try_hit_hurtbox(cactus._segment_hurtboxes[0]) # same segment again inside the guard
	var d3:int = hp0 - d1 - d2 - cactus.health
	check(a and b and not c and d1 > 0 and d2 > 0 and d3 == 0,"each segment is its own target: 2 segments = 2 hits, the same segment is guarded (-%d, -%d, -%d)" % [d1,d2,d3])
	check(cactus.segment_flash[0] > 0.3 and cactus.segment_flash[2] > 0.3 and cactus.segment_flash[1] == 0.0 and cactus.segment_flash[4] == 0.0,"only the struck segments flash white (%s)" % [cactus.segment_flash])
	check(cactus.health <= cactus.Max_health and cactus.Max_health == seg_hp*cactus.levels,"health is pooled (%d / %d, %d segments)" % [cactus.health,cactus.Max_health,cactus.levels])
	await seconds(0.4)
	# positional damage: the segment under the impact point flashes
	for i:int in range(cactus.levels): cactus.segment_flash[i] = 0.0
	var hp1:int = cactus.health
	cactus.receive_positional_damage(15.0,cactus.to_global(Vector2(40,-96.0*5)),false,attacker)
	await process_frame
	check(hp1 - cactus.health == 15 and cactus.segment_flash[5] > 0.0 and cactus.segment_flash[0] == 0.0 and cactus.segment_flash[3] == 0.0,"positional hit flashes only segment 5 (%s)" % [cactus.segment_flash])
	await seconds(0.4)
	# a real overlapping hitbox covering three segments hits three times
	var sweeper:Node2D = spawn("",Vector2(600,base_y),"Team1")
	sweeper.Damage = 10
	sweeper.collision_layer = 0
	sweeper.collision_mask = 0
	var hs:Area2D = sweeper.self_hitbox
	var hshape:CollisionShape2D = hs.get_node("CollisionShape2D")
	var tall := RectangleShape2D.new()
	tall.size = Vector2(30,96.0*2.6)
	hshape.shape = tall
	hs.monitoring = true
	await physics_frame
	var hp2:int = cactus.health
	var hits0:Array = cactus.segment_hits.duplicate()
	sweeper.global_position = cactus.to_global(Vector2(40,-96.0*2)) # covers segments 1..3
	for i:int in range(6): await physics_frame
	var struck:int = 0
	for i:int in range(cactus.levels):
		if int(cactus.segment_hits[i]) > int(hits0[i]): struck += 1
	check(struck == 3 and hp2 - cactus.health == 30,"one attack overlapping three segments hits all three (%d segments, -%d)" % [struck,hp2 - cactus.health])
	sweeper.queue_free()
	attacker.queue_free()
	finish()

func finish() -> void:
	print("CACTUS_SEGMENTS checks=",checks," failures=",failures)
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
