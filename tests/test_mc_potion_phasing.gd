extends SceneTree
## Real physics bodies, Hurtbox Area2D and large-battle crowd separation.
## Invisibility must phase through character bodies without phasing through walls
## or granting immunity to attacks; clearing the status must restore everything.

var game:Node
var world:Node
var saved_settings:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MC_POTION_PHASING_FAIL " + label)

func spawn(team:String,at:Vector2) -> Node2D:
	# Delay loading the ball script until Game autoload is registered.
	var actor:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.position = at
	world.add_child(actor,true)
	actor.health = 100
	actor.Has_Collision_Damage = false
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	return actor

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world) and is_instance_valid(world.get("_mc_prewarmer")):
		for resource_path:Variant in world._mc_prewarmer._paths.values():
			var load_status:int = ResourceLoader.load_threaded_get_status(str(resource_path))
			if load_status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(resource_path))
	if game != null:
		game.Game_Settings = saved_settings
		game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)

func separation(pair:Array) -> Vector2:
	world._large_battle_separation_elapsed = 1.0
	world._rebuild_battle_spatial_grid(pair)
	world._update_large_battle_crowd_separation(pair,0.04)
	return world._battle_spatial_pushes[0]

func run() -> void:
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.2,true,false,true).timeout
	world.set_physics_process(false)
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var passer:Node2D = spawn("Team0",center+Vector2(-60,-200))
	var ghost:Node2D = spawn("Team1",center+Vector2(-5,-200))
	await physics_frame
	var effects:GDScript = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	var body_layer:int = ghost.collision_layer
	var body_mask:int = ghost.collision_mask
	var hurt_layer:int = ghost.self_hurtbox.collision_layer
	var hit_mask:int = ghost.self_hitbox.collision_mask
	var blocked:KinematicCollision2D = passer.move_and_collide(Vector2(110,0),true)
	check(blocked != null and blocked.get_collider() == ghost,"before invisibility a real CharacterBody2D blocks another actor")
	check(bool(effects.call("apply_effect",ghost,"invisibility",1,8.0,passer)),"the canonical status applies to a real fighter")
	var status:Node = ghost.get_node("MinecraftStatus_invisibility")
	status.set_physics_process(false)
	check(not ghost.get_collision_layer_value(2) and not ghost.get_collision_mask_value(2) and ghost.get_collision_mask_value(1),"invisibility removes only character body layer/mask, not wall collision")
	check(ghost.self_hurtbox.collision_layer == hurt_layer and ghost.self_hitbox.collision_mask == hit_mask and ghost.self_hurtbox.get_collision_layer_value(2),"attack and hurtbox Area2D layers remain available")
	check(ghost.is_combat_targetable() and not ghost.is_combat_lockable(),"unlocked by AI but still a valid damage target")
	blocked = passer.move_and_collide(Vector2(110,0),true)
	check(blocked == null or blocked.get_collider() != ghost,"real body movement passes through an invisible character")
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape:=CollisionShape2D.new()
	var rectangle:=RectangleShape2D.new()
	rectangle.size = Vector2(12,110)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = ghost.global_position+Vector2(55,0)
	var probe:=Area2D.new()
	probe.collision_layer = 0
	probe.collision_mask = 2
	probe.monitoring = true
	var probe_shape:=CollisionShape2D.new()
	var circle:=CircleShape2D.new()
	circle.radius = 28.0
	probe_shape.shape = circle
	probe.add_child(probe_shape)
	world.add_child(probe)
	probe.global_position = ghost.global_position
	await physics_frame
	var wall_hit:KinematicCollision2D = ghost.move_and_collide(Vector2(100,0),true)
	check(wall_hit != null and wall_hit.get_collider() == wall,"invisible character still collides with a real layer-1 wall")
	check(probe.get_overlapping_areas().has(ghost.self_hurtbox),"another hitbox-like Area2D still sees the invisible Hurtbox")
	var before:int = ghost.health
	check(ghost.receive_spatial_raw_health_damage(5.0,{"shape":"all"}) and ghost.health == before-5,"invisibility grants no damage immunity")
	probe.queue_free()
	wall.queue_free()
	effects.call("clear",ghost,"invisibility",passer)
	await process_frame
	check(ghost.collision_layer == body_layer and ghost.collision_mask == body_mask and not ghost.has_meta(&"mc_ignore_character_body_collision"),"clearing invisibility restores original body layer/mask and removes phase marker")
	blocked = passer.move_and_collide(Vector2(110,0),true)
	check(blocked != null and blocked.get_collider() == ghost,"after invisibility, real character-to-character blocking resumes")
	var pair:Array = [passer,ghost]
	world.large_battle_unit_threshold = 2
	world.large_battle_disable_below = 2
	world._update_large_battle_mode(pair)
	ghost.global_position = passer.global_position+Vector2(6,0)
	var push:Vector2 = separation(pair)
	check(push.length() > 0.01 and (push+(world._battle_spatial_pushes[1] as Vector2)).length() < 0.01,"large-battle mode normally separates overlapping fighters")
	effects.call("apply_effect",ghost,"invisibility",1,8.0,passer)
	ghost.get_node("MinecraftStatus_invisibility").set_physics_process(false)
	push = separation(pair)
	check(push.is_zero_approx() and (world._battle_spatial_pushes[1] as Vector2).is_zero_approx() and ghost._crowd_separation_velocity.is_zero_approx() and passer._crowd_separation_velocity.is_zero_approx(),"invisible body exerts no soft separation in either direction")
	world.large_battle_optimization_enabled = false
	world._update_large_battle_mode(pair)
	check(not ghost.get_collision_mask_value(2) and not ghost.get_collision_layer_value(2),"switching back to normal physics cannot briefly restore invisible body collision")
	world.large_battle_optimization_enabled = true
	world._update_large_battle_mode(pair)
	effects.call("clear",ghost,"invisibility",passer)
	await process_frame
	check(ghost.get_collision_layer_value(2) and not ghost.get_collision_mask_value(2),"expiry during large-battle mode restores body layer but keeps its performance-mode mask")
	push = separation(pair)
	check(push.length() > 0.01,"clearing invisibility resumes normal large-battle soft separation")
	world.large_battle_optimization_enabled = false
	world._update_large_battle_mode(pair)
	check(ghost.collision_layer == body_layer and ghost.collision_mask == body_mask,"exiting large-battle mode finally restores the exact original body mask")
	print("MC_POTION_PHASING_RESULT checks=",checks," failures=",failures)
	await finish(1 if failures > 0 else 0)
