extends "res://tests/test_copper_sword.gd"
const ANVIL_PATH:String = "res://scenes/characters/我的世界/铁砧.tscn"
func anvil(point:Vector2) -> Node2D:
	var unit:Node2D = spawn(ANVIL_PATH,point)
	unit.Can_Attack = true
	unit.Can_Skill = true
	unit.default_properties.Can_Attack = true
	unit.default_properties.Can_Skill = true
	unit.set_player_control_peer(1) # Tests trigger the skill explicitly, but hit chains remain automatic.
	unit.cooldown_left = 0.0
	unit.set_process(false)
	return unit
func advance_until(unit:Node,predicate:Callable,seconds:float = 4.0) -> void:
	var elapsed:float = 0.0
	while not predicate.call() and elapsed<seconds:
		unit.step_mob(1.0/120.0)
		elapsed += 1.0/120.0
	check(predicate.call(),"anvil reaches requested simulation condition within "+str(seconds)+"s")
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"anvil native preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = anvil(center+Vector2(-150,-50))
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	await physics_frame
	await process_frame
	world._ensure_character_path_index()
	check(world._character_paths_by_folder.get("我的世界",{}).get("铁砧","")==ANVIL_PATH,"anvil is registered in Minecraft partition")
	check(unit.get_preview_texture()==unit.TEXTURE and unit.TEXTURE.get_size()==Vector2(64,64),"anvil uses the native-model baked inventory art")
	check(not unit.Has_Collision_Damage and not unit.self_hitbox.monitoring,"generic contact damage is disabled")
	check(unit.Hit_Audio.is_empty() and unit.Collide_Audio_Node.is_empty() and unit.Unique_Death_Audio==unit.BREAK_SOUND,"anvil does not mix generic ball cues into native item audio")
	var start:Vector2 = unit.global_position
	unit.step_mob(0.1)
	var first_distance:float = unit.global_position.y-start.y
	var first_speed:float = unit.fall_speed
	unit.step_mob(0.1)
	var second_distance:float = unit.global_position.y-start.y-first_distance
	check(is_equal_approx(first_speed,unit.gravity_acceleration*0.1) and is_equal_approx(unit.fall_speed,unit.gravity_acceleration*0.2),"fall speed grows with gravitational acceleration")
	check(second_distance>first_distance*2.0 and is_equal_approx(unit.global_position.x,start.x),"fall displacement increases, with no random lateral walk")
	check(is_equal_approx(unit.global_position.y-start.y,0.5*unit.gravity_acceleration*0.2*0.2),"gravity integration is physically consistent with one-half g t squared")
	var clone:Node2D = anvil(start+Vector2(70,0))
	clone.Can_Skill = false
	for i:int in range(20): clone.step_mob(0.01)
	check(is_equal_approx(clone.global_position.y-start.y,unit.global_position.y-start.y) and is_equal_approx(clone.fall_speed,unit.fall_speed),"fine/coarse update schedules produce the same gravity trajectory")
	clone.queue_free()
	game.now_stop_state = true
	var paused:Vector2 = unit.global_position
	var paused_speed:float = unit.fall_speed
	unit.step_mob(5.0)
	check(unit.global_position==paused and unit.fall_speed==paused_speed,"pause freezes gravity")
	game.now_stop_state = false
	check(unit.falling_damage(600.0)>unit.falling_damage(300.0) and is_equal_approx(unit.falling_damage(600.0),unit.falling_damage(300.0)*2.0),"impact damage grows with actual downward speed")

	# Exact top release, no ascent damage, immediate momentum-preserving gravity.
	var target:Node2D = dummy(center)
	var friend:Node2D = dummy(center,"Team0")
	await physics_frame
	await process_frame
	unit.Can_Skill = true
	unit.default_properties.Can_Skill = true
	unit.cooldown_left = 0.0
	var hp:float = target.health
	var friend_hp:float = friend.health
	check(unit.begin_slam(target),"previous enemy-aligned jump behavior restored")
	check(not unit.begin_slam(target),"an active drop cannot be duplicated by repeated skill presses")
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.FALLING)
	var bounds:Rect2 = unit.map_bounds_for(target.global_position)
	check(is_equal_approx(unit.velocity.x,unit._fall_track_velocity) and is_equal_approx(unit.global_position.y,bounds.position.y+unit.body_half_size().y+unit.top_padding),"release keeps momentum-integrated X and safe map-top Y")
	check(target.health==hp and unit.fall_speed>0.0 and is_equal_approx(unit.fall_speed,unit.jump_velocity(1.0).y),"leap causes no premature damage and flows into the drop without resetting downward speed")
	game.now_stop_state = true
	var phase_time:float = unit.phase_elapsed
	var paused_release:Vector2 = unit.global_position
	unit.step_mob(2.0)
	check(unit.phase_elapsed==phase_time and unit.global_position==paused_release,"pause freezes the skill too")
	game.now_stop_state = false
	advance_until(unit,func(): return unit.hit_count==1,5.0)
	check(unit.last_impact_speed>=unit.minimum_impact_speed and is_equal_approx(hp-target.health,ceilf(unit.falling_damage(unit.last_impact_speed))),"real falling hurtbox contact uses pre-impact velocity for damage")
	check(friend.health==friend_hp and unit.health==unit.Max_health,"slam never damages self or allies")
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.fall_speed>0.0 and unit._drop_connected,"a hit arms a repeat but does not interrupt the downward fall")
	var slams:int = unit.slam_count
	hp = target.health
	advance_until(unit,func(): return unit.slam_count==slams+1)
	check(unit.slam_phase==unit.SlamPhase.RISING and unit.landing_count>=1 and target.health<=hp and unit.hit_count==1,"next slam waits for solid landing; underside pressure never becomes another full impact")
	advance_until(unit,func(): return unit.hit_count==2,5.0)
	check(unit.chain_hits==2 and target.health<hp,"second automatic slam really deals a second speed-scaled hit")

	# Complete the connected drop first, then dodge the next fresh release.
	slams = unit.slam_count
	advance_until(unit,func(): return unit.slam_count==slams+1,5.0)
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.FALLING,5.0)
	var drop_x:float = unit.global_position.x
	target.global_position.x += 140.0
	await physics_frame
	await process_frame
	hp = target.health
	var misses:int = unit.miss_count
	advance_until(unit,func(): return unit.miss_count>misses,6.0)
	check(unit.global_position.x>drop_x and unit.global_position.x<target.global_position.x-40.0 and target.health==hp,"slow falling tracking moves toward target but a large dodge still escapes")
	check(unit.slam_phase==unit.SlamPhase.GROUND and unit.cooldown_left>0 and unit.chain_hits==0,"miss lands, ends the chain and starts normal cooldown")
	check(not unit.begin_slam(target),"manual skill cannot bypass miss cooldown")
	var floor_y:float = unit.global_position.y
	unit.step_mob(0.2)
	check(is_equal_approx(unit.global_position.y,floor_y) and unit.fall_speed==0.0,"anvil rests on terrain instead of falling through the floor")

	# A real solid platform cuts the fall path before the enemy below it.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(180,5)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = center+Vector2(0,-40)
	target.global_position = center
	unit.global_position = center+Vector2(0,-100)
	unit.slam_phase = unit.SlamPhase.FALLING
	unit._active_slam = true
	unit._drop_connected = false
	unit.fall_speed = 800.0
	unit._fall_hits.clear()
	await physics_frame
	await process_frame
	hp = target.health
	unit.step_mob(0.15)
	check(unit.slam_phase==unit.SlamPhase.GROUND and target.health==hp and unit.global_position.y<center.y-40,"high-speed drop stops on real terrain and cannot hurt through it")
	wall.queue_free()

	unit.Can_Skill = false
	unit.cooldown_left = 0.0
	check(not unit.begin_slam(target),"Can_Skill disables launching/repeating a slam")
	unit.Can_Skill = true
	unit.apply_damage_disable(1.0)
	check(not unit.begin_slam(target) and not unit._damage_with_feedback(target,100.0,target.global_position),"damage-disable blocks skill and impact damage")
	unit._damage_output_disabled_until_msec = 0
	var replica:Node2D = anvil(center+Vector2(250,0))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	var replica_position:Vector2 = replica.global_position
	hp = target.health
	replica.step_mob(3.0)
	check(replica.global_position==replica_position and not replica.begin_slam(target) and not replica._damage_with_feedback(target,100.0,target.global_position) and target.health==hp,"replicas cannot simulate a second gravity/hit/skill authority")
	unit.health = 0
	unit.step_mob(3.0)
	check(not unit.begin_slam(target),"dead anvil cannot begin another chain")
	check(not unit.get_armor_test_effect_summary().is_empty(),"anvil mechanic summary available")
	print("ANVIL_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
