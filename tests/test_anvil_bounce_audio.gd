extends "res://tests/test_anvil.gd"
func obstacle(point:Vector2,size:Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collider.shape = rectangle
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = point
	return wall
func clangs(unit:Node) -> Array[Node]:
	var result:Array[Node] = []
	for cue:Node in get_nodes_in_group("MCNativeSFX"):
		if cue.get_meta("mc_anvil_obstacle_source",0)==unit.get_instance_id(): result.append(cue)
	return result
func damage_sounds(unit:Node) -> Array[Node]:
	var result:Array[Node] = []
	for cue:Node in get_nodes_in_group("MCNativeSFX"):
		if cue.get_meta("mc_damage_source",0)==unit.get_instance_id(): result.append(cue)
	return result
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"bounce/audio preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var _floor:StaticBody2D = obstacle(center+Vector2(0,40),Vector2(300,6))
	var left:StaticBody2D = obstacle(center+Vector2(-80,0),Vector2(6,140))
	var right:StaticBody2D = obstacle(center+Vector2(80,0),Vector2(6,140))
	var unit:Node2D = anvil(center+Vector2(0,-10))
	unit.set_player_control_peer(0)
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	unit.direction = Vector2.RIGHT
	await physics_frame
	await process_frame
	check(unit.Speed>0.0 and unit.cruising_velocity()>0.0,"normal anvil has horizontal locomotion instead of forced zero Speed")
	var before:Vector2 = unit.global_position
	unit.step_mob(0.1)
	check(unit.global_position.x>before.x and unit.global_position.y>before.y and unit.fall_speed>0.0,"ordinary air movement combines horizontal travel and gravity")
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.GROUND,2.0)
	check(unit.obstacle_impact_count==1 and clangs(unit).size()==1,"first genuine floor impact produces one anvil clang")
	var y:float = unit.global_position.y
	var x:float = unit.global_position.x
	unit.step_mob(0.15)
	check(unit.global_position.x>x and is_equal_approx(unit.global_position.y,y),"landing preserves left/right ground movement")
	check(unit.obstacle_impact_count==1,"sliding along supporting floor does not spam clangs")
	clear_cues()
	advance_until(unit,func(): return unit.horizontal_bounces>=1,2.0)
	check(unit.direction.x<0.0 and unit.obstacle_impact_count==1 and clangs(unit).is_empty(),"right wall reverses horizontal heading without any anvil clang")
	x = unit.global_position.x
	unit.step_mob(0.1)
	check(unit.global_position.x<x,"rebound really moves away from the wall")
	advance_until(unit,func(): return unit.horizontal_bounces>=2,3.0)
	check(unit.direction.x>0.0 and unit.obstacle_impact_count==1 and clangs(unit).is_empty(),"left wall uses normal feedback without the anvil clang")

	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.RIGHT
	unit.global_position = center+Vector2(62,y-center.y)
	await physics_frame
	await process_frame
	var count:int = unit.obstacle_impact_count
	unit.step_mob(0.2)
	check(unit.obstacle_impact_count==count and clangs(unit).is_empty(),"manual horizontal collision also avoids the special anvil clang")
	count = unit.obstacle_impact_count
	unit.step_mob(0.5)
	check(unit.obstacle_impact_count==count,"holding input into one wall does not repeatedly ring")
	unit.set_player_control_peer(0)
	unit.direction = Vector2.LEFT
	var speed:float = unit.Speed
	unit.Speed = speed*1.5
	x = unit.global_position.x
	unit.step_mob(0.1)
	check(absf((x-unit.global_position.x)-unit.Speed*unit.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER*0.1)<0.03,"normal horizontal motion respects current Speed buffs and shared movement multiplier")
	unit.Speed = speed
	game.Game_Settings.Ball_Can_Move = false
	x = unit.global_position.x
	unit.step_mob(0.1)
	check(is_equal_approx(x,unit.global_position.x),"global movement switch stops voluntary cruising")
	game.Game_Settings.Ball_Can_Move = true
	left.queue_free();right.queue_free()
	await process_frame

	# Characters can turn a roaming anvil around, but are not metallic obstacles.
	var target:Node2D = dummy(center+Vector2(0,y-center.y))
	unit.global_position = center+Vector2(-50,y-center.y)
	unit.direction = Vector2.RIGHT
	unit.slam_phase = unit.SlamPhase.GROUND
	unit._horizontal_contact = ""
	await physics_frame
	await process_frame
	count = unit.obstacle_impact_count
	var bounces:int = unit.horizontal_bounces
	unit.step_mob(0.4)
	check(unit.horizontal_bounces>bounces and unit.direction.x<0.0,"ordinary body contact with a character can reverse horizontal movement")
	check(unit.obstacle_impact_count==count,"touching an enemy is not an anvil-clang event")

	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.RIGHT
	unit.Can_Skill = true
	unit.default_properties.Can_Skill = true
	unit.cooldown_left = 0.0
	check(unit.begin_slam(target),"skill can still start after horizontal cruising")
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.FALLING,4.0)
	x = unit.global_position.x
	unit.step_mob(0.1)
	check(absf(unit.global_position.x-x)<=maxf(absf(unit._launch_horizontal_speed),unit.fall_track_speed)*0.1+0.03,"fall moves within impulse/pursuit budget rather than adding normal player input")
	count = unit.obstacle_impact_count
	clear_cues()
	advance_until(unit,func(): return unit.hit_count>=1,5.0)
	check(unit.obstacle_impact_count==count and clangs(unit).is_empty(),"real enemy smash produces no anvil clang")
	check(not damage_sounds(unit).is_empty() and damage_sounds(unit)[-1].get_meta("mc_sound_event")==unit.HIT_GAIN.damage_event(unit.last_impact_damage),"real enemy smash retains the proper MC hurt/critical audio")
	advance_until(unit,func(): return unit.hit_count>=2,5.0)
	check(unit.obstacle_impact_count==count+1 and unit.landing_count>=1 and unit.chain_hits>=2,"only the intervening solid landing clangs before the second enemy hit")

	# Finish the connected drop, then dodge the next release.
	var old_slams:int = unit.slam_count
	advance_until(unit,func(): return unit.slam_count==old_slams+1,5.0)
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.FALLING,4.0)
	count = unit.obstacle_impact_count
	target.global_position += Vector2(200,0)
	await physics_frame
	await process_frame
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.GROUND,5.0)
	check(unit.obstacle_impact_count==count+1 and not clangs(unit).is_empty(),"miss into solid platform does play the anvil clang")
	unit.set_player_control_peer(0)
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	unit.direction = Vector2.RIGHT
	unit.global_position = center+Vector2(145,y-center.y)
	unit._horizontal_contact = ""
	await physics_frame
	await process_frame
	unit.step_mob(0.4)
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.global_position.y>y+1.0,"walking off a platform resumes gravity instead of hovering")
	game.now_stop_state = true
	before = unit.global_position
	unit.step_mob(1.0)
	check(unit.global_position==before,"pause freezes both cruising and falling")
	game.now_stop_state = false
	print("ANVIL_BOUNCE_AUDIO checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
