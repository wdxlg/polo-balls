extends "res://tests/test_anvil_bounce_audio.gd"
## A successful hit must not stop/restart the fall. Normal rebounds use the real shared FX.
func collision_cues(unit:Node) -> Array[Node]:
	var cues:Array[Node] = []
	for child:Node in unit.get_children():
		if child is AudioStreamPlayer2D and child.stream==unit.Unique_Collide_Audio and child.playing: cues.append(child)
	return cues
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"through-slam preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var floor:StaticBody2D = obstacle(center+Vector2(0,130),Vector2(250,6))
	var unit:Node2D = anvil(center+Vector2(0,-150))
	var upper:Node2D = dummy(center+Vector2(0,-60))
	var lower:Node2D = dummy(center+Vector2(0,40))
	var friend:Node2D = dummy(center+Vector2(0,-10),"Team0")
	unit._active_slam = true
	unit._drop_connected = false
	unit.fall_speed = 600.0
	var upper_hp:float = upper.health
	var lower_hp:float = lower.health
	var friend_hp:float = friend.health
	await physics_frame
	await process_frame
	advance_until(unit,func(): return unit.hit_count==1,1.0)
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.velocity.y>0.0 and unit.fall_speed>=600.0,"first enemy hit never stops downward velocity or changes into a wait")
	check(unit._drop_connected and unit.slam_count==0 and unit.landing_count==0,"enemy contact only stores landing-time repeat eligibility")
	check(upper.health<upper_hp and lower.health==lower_hp and friend.health==friend_hp,"first swept contact damages only the actually reached enemy")
	check(unit.obstacle_impact_count==0 and clangs(unit).is_empty(),"passing through the first enemy does not play the ground clang")
	var speed:float = unit.fall_speed
	upper_hp = upper.health
	unit.step_mob(0.05)
	check(unit.fall_speed>speed and unit.global_position.y>upper.global_position.y,"anvil keeps accelerating through the upper enemy instead of rewinding to it")
	check(upper.health<upper_hp and unit.crush_tick_count>0,"remaining underside contact continues time-scaled pressure during the same fall")
	upper_hp = upper.health
	advance_until(unit,func(): return unit.hit_count==2,1.0)
	check(lower.health<lower_hp and upper.health==upper_hp and friend.health==friend_hp,"one downward pass can also hit a second lower enemy without hitting allies")
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.landing_count==0 and unit.slam_count==0,"second victim still cannot restart the skill in midair")
	var paused:Vector2 = unit.global_position
	game.now_stop_state = true
	unit.step_mob(1.0)
	check(unit.global_position==paused and unit._drop_connected,"pause preserves the pending repeat without dropping or jumping")
	game.now_stop_state = false
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.CHAIN_WAIT,1.0)
	check(unit.landing_count==1 and absf(unit.global_position.y+unit.body_half_size().y-(floor.global_position.y-3.0))<0.1,"fall ends only at the actual solid platform surface")
	check(unit.velocity==Vector2.ZERO and unit.fall_speed==0.0 and unit.slam_count==0,"only terrain landing stops momentum; next leap has not happened yet")
	check(unit.obstacle_impact_count==1 and clangs(unit).size()==1,"the real downward obstacle impact plays exactly one anvil clang")
	check(unit._bounce_shader_params_a.y>0.0 and unit._last_wall_hit_burst_physics_frame==Engine.get_physics_frames(),"landing also uses normal project collision deformation and wall-hit effects")
	unit.step_mob(unit.chain_delay*0.4)
	check(unit.slam_phase==unit.SlamPhase.CHAIN_WAIT and unit.slam_count==0,"landing recovery happens before the next jump")
	advance_until(unit,func(): return unit.slam_count==1,1.0)
	check(unit.slam_phase==unit.SlamPhase.RISING and not unit._drop_connected,"multiple hits in one drop schedule only one fresh post-landing slam")
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	unit.step_mob(0.01)
	unit.global_position = center+Vector2(-75,113)
	unit.slam_phase = unit.SlamPhase.GROUND
	unit._active_slam = false
	unit._drop_connected = false
	unit.fall_speed = 0.0
	unit.set_player_control_peer(0)
	unit.direction = Vector2.LEFT
	var _wall:StaticBody2D = obstacle(center+Vector2(-100,75),Vector2(6,120))
	upper.global_position += Vector2(300,0)
	lower.global_position += Vector2(300,0)
	friend.global_position += Vector2(300,0)
	await physics_frame
	await process_frame
	var clang_count:int = unit.obstacle_impact_count
	check(unit.When_Coliide_Tween and unit.Unique_Collide_Audio!=null and unit.Unique_Collide_Audio!=unit.LAND_SOUND,"ordinary bounce feedback and a non-clang native collision sound are enabled")
	advance_until(unit,func(): return unit.horizontal_bounces>0,1.0)
	check(unit.direction.x>0.0 and not collision_cues(unit).is_empty(),"real lateral rebound plays the normal collision audio channel")
	check(unit._bounce_shader_params_a.y>0.0 and is_instance_valid(unit.collide_tween),"ordinary rebound starts the shared squash/rebound animation")
	check(unit._last_wall_hit_burst_physics_frame==Engine.get_physics_frames(),"ordinary rebound also emits the shared wall-impact burst")
	check(unit.obstacle_impact_count==clang_count,"normal rebound sound/effects do not substitute the special anvil clang")
	print("ANVIL_THROUGH checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
