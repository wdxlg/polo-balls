extends "res://tests/test_character_motion.gd"
func run() -> void:
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game._settings_storage_path=OS.get_environment("TEMP").path_join("spear_live_settings.json")
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false;game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(80,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false);center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await encounter(10,false)
	await encounter(30,false)
	await encounter(30,true)
	await encounter(30,true,false)
	print("SPEAR_ZOMBIE_CROWD checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func encounter(count:int,diagnostic:bool,attacking:bool=true) -> void:
	await clear_units()
	game.now_stop_state=false
	# The movement-only probe uses an ordinary body: spear has a legitimate
	# high-speed passive pass, which must not masquerade as public crowd pushing.
	var spear:Node2D=spawn("木矛" if attacking else "",Vector2.ZERO)
	spear.set_player_control_peer(1)
	if not attacking:
		spear.Has_Collision_Damage=false
		spear.Damage=0
	if diagnostic:
		# Only this separate endurance case extends HP; the first two use real 400 HP.
		spear.Max_health=10000;spear.health=10000
	spear.state_machine.set_physics_process(true)
	var zombies:Array[WeakRef]=[]
	for i:int in range(count):
		var offset:Vector2=Vector2.RIGHT.rotated(TAU*float(i)/count)*(42.0+12.0*float(i%2))
		var zombie:Node2D=spawn("僵尸",offset,"Team1")
		zombie.set_player_control_peer(0)
		zombie.state_machine.set_physics_process(true)
		zombies.append(weakref(zombie))
	var active_frames:int=0
	var attack_frames:int=0
	var moved_frames:int=0
	var damage_seen:bool=false
	var locked_frames:int=0
	var max_distance:float=0.0
	var last:Vector2=spear.global_position
	var hp:float=spear.health
	var deaths:int=0
	for frame:int in range(480):
		await physics_frame
		if not is_instance_valid(spear) or spear.health<=0:break
		active_frames+=1
		spear.set_player_control_direction(Vector2.RIGHT)
		var nearest:Node2D
		var nearest_distance:float=INF
		deaths=0
		for ref:WeakRef in zombies:
			var zombie:Node2D=ref.get_ref() as Node2D
			if not is_instance_valid(zombie) or zombie.health<=0:
				deaths+=1;damage_seen=true;continue
			damage_seen=damage_seen or zombie.health<100
			var distance:float=spear.global_position.distance_squared_to(zombie.global_position)
			if distance<nearest_distance:nearest=zombie;nearest_distance=distance
		if nearest!=null:
			spear.set_player_control_aim_position(nearest.global_position)
			if attacking and frame%16==0:spear.player_control_action(0)
		if attacking and (spear._attack_active or spear._pass_active):attack_frames+=1
		if spear.global_position.distance_to(last)>0.05:moved_frames+=1
		if spear.dizziness or spear.is_hard_controlled():locked_frames+=1
		last=spear.global_position;hp=spear.health
		max_distance=maxf(max_distance,last.distance_to(center))
		if frame==90 and count==10 and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var dir:String=OS.get_environment("TEMP").path_join("crowd_followup")
			DirAccess.make_dir_recursive_absolute(dir)
			root.get_texture().get_image().save_png(dir.path_join("spear_live.png"))
	check(active_frames>20 and moved_frames>10,"real state machine consumes movement input before defeat")
	if attacking:
		check(attack_frames>0 and damage_seen,"manual attack action reaches actual spear hits")
	else:
		check(not damage_seen,"movement-only escape neither damages nor kills a zombie")
		check(spear.get_collision_mask_value(2),"movement-only probe retains solid body collision")
	check(locked_frames==0,"zombie bite and ordinary body impacts do not lock manual control")
	if diagnostic:check(max_distance>70,"endurance probe can make headway out of the thirty-zombie enclosure")
	print("SPEAR_LIVE role=",("spear" if attacking else "plain_body")," n=",count," diagnostic=",diagnostic," attacking=",attacking," alive_frames=",active_frames," attack_frames=",attack_frames," moving_frames=",moved_frames," max_distance=",max_distance," deaths=",deaths," hp=",hp," locks=",locked_frames)
