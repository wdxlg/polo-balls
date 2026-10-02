extends "res://tests/test_character_motion.gd"
func sample_motion(input_direction:Vector2,manual:bool) -> Vector2:
	await clear_units()
	var actor:Node2D=spawn("",Vector2.ZERO)
	actor.Speed=100.0
	actor.get_body_motion().set_physics_process(false)
	actor.direction=input_direction
	if manual:
		actor.set_player_control_peer(1)
		actor.set_player_control_direction(input_direction)
	var effect:Node=actor.apply_knockback(Vector2.RIGHT,60,180,0,0,{"lock_control":true})
	effect.set_physics_process(false)
	check(not actor.dizziness and not actor.is_hard_controlled() and actor.Can_Attack,"ordinary force does not acquire even legacy input locks")
	var from:Vector2=actor.global_position
	for frame:int in range(10):
		await physics_frame
		actor.direction=input_direction
		if manual: actor.set_player_control_direction(input_direction)
		actor.move(actor.Speed,1.0/60.0)
		effect._physics_process(1.0/60.0)
	check(not actor.dizziness and actor.Can_Attack,"movement and attack remain available throughout impulse")
	return actor.global_position-from
func run() -> void:
	game=root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("body_motion_settings.json")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false)
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for manual:bool in [false,true]:
		var same:Vector2=await sample_motion(Vector2.RIGHT,manual)
		var idle:Vector2=await sample_motion(Vector2.ZERO,manual)
		var opposite:Vector2=await sample_motion(Vector2.LEFT,manual)
		var oblique:Vector2=await sample_motion(Vector2.UP,manual)
		check(same.x>idle.x+5 and idle.x>opposite.x+5,"same direction adds and opposite input resists; manual="+str(manual))
		print("VECTOR_SAMPLE ",manual," ",same," ",idle," ",opposite," ",oblique)
		check(oblique.y< -5 and absf(oblique.x-idle.x)<1.5,"oblique input retains independent tangent")
	await clear_units()
	var actor:Node2D=spawn("",Vector2.ZERO)
	actor.get_body_motion().set_physics_process(false)
	actor.Speed=100;actor.direction=Vector2.LEFT
	var first:Node=actor.apply_knockback(Vector2.RIGHT,60,180)
	var second:Node=actor.apply_knockback(Vector2.LEFT,60,180)
	first.set_physics_process(false);second.set_physics_process(false)
	check(first!=second and actor.get_body_motion().impulse_velocity().is_zero_approx(),"simultaneous opposite hits cancel, never last-writer wins")
	actor.Repel=Vector2.UP*17
	first._finish(false)
	check(actor.Repel==Vector2.UP*17 and actor.get_body_motion().impulse_velocity().x< -170,"cleanse releases only its owned impulse")
	second._finish(false);actor.Repel=Vector2.ZERO
	var effect:Node=actor.apply_knockback(Vector2.RIGHT,30,120)
	effect.set_physics_process(false)
	var from:Vector2=actor.global_position
	for frame:int in range(120):
		await physics_frame
		actor.move(actor.Speed,1.0/60.0)
		if is_instance_valid(effect) and not effect._finished: effect._physics_process(1.0/60.0)
	check(not is_instance_valid(effect) or effect._finished,"opposing input cannot prolong forced travel")
	check(actor.global_position.x<from.x-60,"movement can eventually reverse the knockback")
	check(not actor.dizziness,"no recovery lock after impulse")
	# Pause does not consume force lifetime or decay, and replicas do not acquire it.
	effect=actor.apply_knockback(Vector2.RIGHT,40,160);effect.set_physics_process(false)
	var elapsed:float=effect._elapsed;var value:Vector2=actor.get_body_motion().impulse_velocity()
	game.now_stop_state=true
	await physics_frame
	effect._physics_process(1.0)
	check(effect._elapsed==elapsed and actor.get_body_motion().impulse_velocity()==value,"runtime pause freezes effect")
	game.now_stop_state=false;effect._finish(false)
	actor.set_multiplayer_authority(2)
	effect=actor.apply_knockback(Vector2.RIGHT,50,200)
	check(not actor.dizziness and actor.get_body_motion().impulse_velocity().is_zero_approx(),"non-authority replica has no local force or control lock")
	actor.set_multiplayer_authority(1)
	# Explicit stun is separate; overlapping stuns release independently.
	var stun_a:Node=actor.apply_stun(0.10);var stun_b:Node=actor.apply_stun(0.20)
	stun_a.set_physics_process(false);stun_b.set_physics_process(false)
	check(actor.dizziness and actor.is_hard_controlled(),"explicit stun is still hard control")
	stun_a._physics_process(0.11)
	check(actor.dizziness,"one stun finishing does not unlock another")
	stun_b._physics_process(0.21)
	check(not actor.dizziness,"all explicit stun leases release")
	# Real wall sweep and piston subclass callback.
	await clear_units()
	actor=spawn("",Vector2.ZERO);actor.Speed=0;actor.direction=Vector2.ZERO
	actor.get_body_motion().set_physics_process(false)
	var wall:StaticBody2D=obstacle(Vector2(45,0),true)
	wall.get_child(0).shape.size=Vector2(8,160)
	await physics_frame
	effect=load("res://scripts/characters/我的世界/new5/piston_push.gd").new()
	effect.target=actor;effect.distance=100;effect.speed=300;effect.stun_only_on_collision=true
	actor.add_child(effect);effect.set_physics_process(false)
	var hp:float=actor.health;var blocked:bool=true;var saw_stun:bool=false
	for frame:int in range(60):
		await physics_frame
		actor.stand(1.0/60.0)
		if is_instance_valid(effect) and not effect._finished:effect._physics_process(1.0/60.0)
		blocked=blocked and actor.global_position.x<=wall.global_position.x-22+0.2
		saw_stun=saw_stun or actor.dizziness
	check(blocked,"ordinary impulse respects real wall sweep")
	check(actor.health<hp and saw_stun,"piston retains collision damage and explicit wall stun")
	check(not actor.dizziness,"piston stun finishes")
	wall.queue_free()
	# Zombie holding bite range is still pushed, and ordinary knockback does not cancel bite.
	await clear_units()
	var zombie:Node2D=spawn("僵尸",Vector2.ZERO)
	var victim:Node2D=spawn("",Vector2(34,0),"Team1")
	zombie.get_body_motion().set_physics_process(false)
	zombie.Nearest_Enemy=victim;zombie.step_zombie(0.001)
	check(zombie._hold_distance and zombie.bite_left>=0,"zombie keeps its bite-distance hold")
	var bite_before:float=zombie.bite_left
	effect=zombie.apply_knockback(Vector2.LEFT,10,60);effect.set_physics_process(false)
	zombie.step_zombie(0.01)
	check(zombie.can_act() and zombie.bite_left>=0 and zombie.bite_left<bite_before,"ordinary impulse does not cancel an active bite")
	from=zombie.global_position
	await physics_frame
	zombie.move(zombie.Speed,1.0/60.0)
	check(zombie.global_position.x<from.x,"bite hold stops self propulsion, not external momentum")
	zombie.apply_stun(0.15);zombie.step_zombie(0.01)
	check(zombie.bite_left<0,"true stun still cancels bite")
	print("MOBILE_KNOCKBACK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
