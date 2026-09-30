extends "res://tests/test_rotation_timed_network.gd"
func prepare_rosters() -> void:
	game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type="challenge"
	game.Game_Settings.Training_Wheel_Battle=true;game.Game_Settings.Rotation_Multi_Characters=true
	game.Game_Settings.Rotation_Blue_Count=2;game.Game_Settings.Rotation_Red_Count=3
	game.Game_Settings.Guest_Free_Permissions=false
	world.control.show();world.control.team.show();world.control._sync_training_mode_controls()
func side_units(side:String) -> Array:
	var units:Array=[]
	for actor:Node in world._battle_units_cache:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.health>0 and actor.Team=="__rotation_"+side: units.append(actor)
	return units
func host_case() -> void:
	prepare_rosters()
	check(await until(func():return flag("ready")),"roster client ready")
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	for side:String in ["left","right"]:
		for number:int in [1,2]:
			world._enqueue_rotation_character("", "ball",rect.position+rect.size*Vector2(0.5,0.2),side,"res://scenes/ball.tscn",number)
	world._enqueue_rotation_character("","ball",rect.position+rect.size*Vector2(0.7,0.7),"left","res://scenes/ball.tscn",1)
	world.select_rotation_round(1)
	ack("draft")
	check(await until(func():return flag("selection_sent") and world.rotation_selected_round==2),"guest round choice reaches authority over reliable RPC")
	check(world._rotation_formation_preview.size()==2,"only the authority builds the selected round's previews")
	world.control.hide();world.control.team.hide();world._update_special_training_modes(0)
	for actor:Node in world._battle_units_cache:
		if is_instance_valid(actor): actor.Can_Attack=false;actor.Can_Skill=false;actor.set_physics_process(false);actor.state_machine.set_physics_process(false)
	check(side_units("left").size()==4 and side_units("right").size()==3,"host creates the multiplied grouped first round exactly once")
	check(await until(func():return flag("first_wave")),"client sees exact roster round and group members")
	var left:Array=side_units("left")
	for actor:Node in left.slice(0,3):actor.health=0;actor.queue_free()
	await create_timer(0.4,true,false,true).timeout
	check(int(world._rotation_next_index.left)==2,"network host does not advance on partial group loss")
	var winner:int=side_units("right")[0].get_instance_id()
	left[3].health=0;left[3].queue_free()
	check(await until(func():return int(world._rotation_next_index.left)==3),"full group elimination advances the authority to round2")
	check(side_units("right")[0].get_instance_id()==winner,"challenge plus wheel keeps the existing red winner")
	check(not is_instance_valid(world._rotation_door),"network wheel replacement does not create a transition")
	check(await until(func():return flag("replacement")),"client receives next group without local duplicate previews")
	ack("finish")
	await create_timer(3.5,true,false,true).timeout
func guest_case() -> void:
	prepare_rosters();game.network_role="client"
	world.control._sync_training_mode_controls()
	check(not world.control.rotation_count_spins.left.editable and world.control.rotation_match_option.disabled,"restricted guest cannot edit room quantities or rule selector")
	check(game._is_network_shared_setting("Rotation_Blue_Count") and game._is_network_shared_setting("Rotation_Multi_Characters"),"new preferences use the existing shared room-settings contract")
	game.network_role="offline"
	ack("ready");await until(func():return flag("draft"))
	check(await until(func():return world._rotation_rosters.left.size()==3 and world._rotation_rosters.right.size()==2),"live roster RPC carries all manual rounds")
	world._refresh_rotation_formation_preview()
	check(world._rotation_formation_preview.is_empty(),"client cannot create local preview actors")
	world.select_rotation_round(2);ack("selection_sent")
	check(await until(func():return world._rotation_active_records.left.size()==2),"client reconstructs the full active group from authoritative round metadata")
	check(int(world._rotation_rosters.left[1].round)==1 and int(world._rotation_rosters.left[2].round)==2,"same-round grouping is preserved remotely")
	check(await until(func():return side_units("left").size()==4 and side_units("right").size()==3),"real replicated actors match both quantity multipliers")
	ack("first_wave")
	check(await until(func():return int(world._rotation_active_setup.left)==int(world._rotation_rosters.left[2].id)),"wheel replacement leader reaches the client")
	check(world._rotation_active_records.left.size()==1 and world._rotation_formation_preview.is_empty(),"replacement remains one multiplied template without client-only actors")
	ack("replacement");await until(func():return flag("finish"));game.network_role="offline"
	await create_timer(3.5,true,false,true).timeout
