extends "res://tests/test_rotation_frames_challenge.gd"
func idle_actors() -> void:
	for actor:Node in world._battle_units_cache:
		if not is_instance_valid(actor): continue
		actor.Can_Attack=false;actor.Can_Skill=false;actor.Health_Restore=0
		actor.state_machine.set_physics_process(false);actor.set_physics_process(false)
func live(side:String) -> Array:
	var result:Array=[]
	for actor:Node in world._battle_units_cache:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.health>0 and actor.get_meta("rotation_side","")==side:result.append(actor)
	return result
func place(side:String,round_id:int,position:Vector2) -> void:
	world.select_rotation_round(round_id)
	await world.create_char("__rotation_"+side,"ball",position,round_id)
	idle_actors()
func kill_all(side:String) -> void:
	for actor:Node in live(side): actor.health=0;actor.queue_free()
	await process_frame
	world._scan_rotation_family_extinctions()
	await create_timer(0.42,true,false,true).timeout
	idle_actors()
func run() -> void:
	create_timer(100,true,false,true).timeout.connect(func():push_error("ROSTER_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type="challenge";game.Game_Settings.Training_Wheel_Battle=true
	game.Game_Settings.Rotation_Multi_Characters=true;game.Game_Settings.Rotation_Blue_Count=2;game.Game_Settings.Rotation_Red_Count=3
	game.Game_Settings.Map_Background="blue";game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate();world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_process(false);world.set_physics_process(false)
	world.Characters_Dic["ball"]=load("res://scenes/ball.tscn");world.control.show();world.control.team.show()
	world.control._sync_training_mode_controls();await process_frame
	var ui:Control=world.control
	check(ui.rotation_match_option.item_count==2,"normal/challenge remain while wheel is a separate control")
	check(ui.rotation_count_spins.size()==2,"independent blue/red quantity inputs exist")
	check(ui.team_box.has_node("RotationBlueTeam") and ui.team_box.has_node("RotationRedTeam"),"rotation immediately provides reserved team choices")
	ui._add_rotation_round();ui._add_rotation_round();world.select_rotation_round(1)
	check(world.rotation_round_numbers().has(2) and world.rotation_round_numbers().has(3),"manually added empty rounds remain selectable after changing selection")
	var blue_button:Button=ui.team_box.get_node("RotationBlueTeam")
	blue_button.button_pressed=true
	ui.reset_team_buts()
	check(world.now_choose_team=="__rotation_left","blue button actually selects blue regardless of map half")
	check(blue_button.get_theme_color("font_color").b>blue_button.get_theme_color("font_color").r,"blue team choice has blue text")
	check(ui.rotation_round_panel.visible and ui.rotation_round_panel.position.y>ui.team.get_node("Team").position.y+ui.team.get_node("Team").size.y,"round panel sits below team panel")
	await process_frame;await RenderingServer.frame_post_draw
	if not OS.get_cmdline_user_args().is_empty():root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/formation_ui.png")
	ui.team.hide();ui.game_setting.show();ui._show_settings_category("training")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false);ui._sync_training_mode_controls();ui.settings_scroll.scroll_vertical=0
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		if not OS.get_cmdline_user_args().is_empty():root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/settings_"+locale+"_top.png")
		ui.settings_scroll.ensure_control_visible(ui.rotation_count_spins.right)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		if not OS.get_cmdline_user_args().is_empty():root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/settings_"+locale+"_counts.png")
		check(ui.rotation_count_spins.right.is_visible_in_tree(),"localized quantity control is visible via settings scroll")
	game.set_language("zh",false);ui.game_setting.hide();ui.team.show()
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var a:Vector2=rect.position+rect.size*Vector2(0.8,0.7)
	var b:Vector2=rect.position+rect.size*Vector2(0.7,0.6)
	var red:Vector2=rect.position+rect.size*Vector2(0.2,0.4)
	var top:Vector2=rect.position+rect.size*Vector2(0.5,0.18)
	await place("left",1,a);await place("left",1,b);await place("right",1,red)
	check(world.rotation_selected_round==1 and world._rotation_rosters.left.size()==2,"multi placement stays on selected round without automatic advancement")
	check(world._rotation_formation_preview.size()==3,"all templates of the selected round are visible for formation")
	var preview:Node=world._rotation_formation_preview[int(world._rotation_rosters.left[0].id)]
	preview.global_position+=Vector2(5,8);a=preview.global_position
	await place("left",2,top);await place("right",2,red+Vector2(0,30))
	check(world._rotation_rosters.left[0].x==a.x and world._rotation_rosters.left[0].y==a.y,"moving a formation preview persists its free position")
	check(world._rotation_formation_preview.size()==2,"choosing a later round displays that round only")
	ui.hide();ui.team.hide();world._update_special_training_modes(0);idle_actors();await process_frame
	check(world._rotation_started and live("left").size()==4 and live("right").size()==3,"initial wave expands two blue templates by2 and one red template by3")
	check(not live("left")[2].has_meta("rotation_entry_target") and live("left")[2].global_position.distance_to(b)<0.1,"every template of the first wave spawns at its placement, not as reinforcement")
	check(world._rotation_active_records.left.size()==2 and int(world._rotation_next_index.left)==2,"a complete multi-template round is consumed together")
	check(live("left")[0].global_position.distance_to(a)<0.1,"blue spawns at freely chosen right-side position")
	check(live("left")[0].Max_health==1000 and live("right")[0].Max_health==1000,"quantity multiplier does not scale combat attributes")
	var red_id:int=live("right")[0].get_instance_id();live("right")[0].health=123
	var blue_units:Array=live("left")
	for actor:Node in blue_units.slice(0,3):actor.health=0;actor.queue_free()
	await process_frame;world._scan_rotation_family_extinctions();await create_timer(0.35,true,false,true).timeout
	check(int(world._rotation_next_index.left)==2 and not world._rotation_transitioning,"partial team loss including a whole template family does not replace the round")
	var ticket:int=world.begin_battle_spawn(live("left")[0],world)
	await kill_all("left")
	check(int(world._rotation_next_index.left)==2,"pending descendant ticket keeps the multiplied round alive after all bodies leave")
	world.finish_battle_spawn(ticket);world._scan_rotation_family_extinctions()
	await create_timer(0.42,true,false,true).timeout;idle_actors()
	check(int(world._rotation_next_index.left)==3 and live("left").size()==2,"last current member dying replaces the entire next blue round")
	check(live("right")[0].get_instance_id()==red_id and live("right")[0].health==123,"winning red side keeps actual identities and damaged health")
	check(not is_instance_valid(world._rotation_door),"wheel switch bypasses doors")
	var entered:Node=live("left")[0]
	check(entered.global_position.y<rect.position.y+64 and entered.has_meta("map_rescue_animating"),"replacement approaches from the nearest top wall, not the blue-side wall")
	var target:Vector2=entered.get_meta("rotation_entry_target")
	check(target.y==rect.position.y+minf(64,minf(rect.size.x,rect.size.y)*0.2) and target.distance_to(top)>1,"entry only crosses the boundary and does not travel to the stored placement")
	var _previous:Vector2=entered.global_position;game.now_stop_state=true
	await physics_frame;await physics_frame;var stopped:Vector2=entered.global_position
	await create_timer(0.16,true,false,true).timeout
	check(entered.global_position.distance_to(stopped)<0.1,"paused combat freezes entrance")
	game.now_stop_state=false
	var deadline:int=Time.get_ticks_msec()+5000
	while entered.has_meta("map_rescue_animating") and Time.get_ticks_msec()<deadline: await physics_frame
	idle_actors()
	check(not entered.has_meta("map_rescue_animating") and rect.has_point(entered.global_position),"entry finishes inside without stranded collision state")
	for point:Vector2 in [rect.position+rect.size*Vector2(0.1,0.5),rect.position+rect.size*Vector2(0.9,0.5),rect.position+rect.size*Vector2(0.5,0.1),rect.position+rect.size*Vector2(0.5,0.9)]:
		var entry:Dictionary=world._rotation_wall_entry(point)
		check(not rect.has_point(entry.start) and rect.has_point(entry.end),"nearest-wall entry endpoints are outside/inside respectively")
	# Wheel wins over challenge without deleting the selected underlying rule.
	game.Game_Settings.Rotation_Match_Type="challenge"
	check(game.get_rotation_match_type()=="wheel","wheel takes precedence over a saved challenge selection")
	game.Game_Settings.Training_Wheel_Battle=false
	check(game.get_rotation_match_type()=="challenge","turning wheel off restores selected challenge")
	# Incomplete manual normal rounds cannot pair round1 with round2.
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Rotation_Blue_Count=1;game.Game_Settings.Rotation_Red_Count=1
	ui.show();ui.team.show();await place("left",1,a);await place("right",2,red)
	ui.hide();ui.team.hide();world._update_special_training_modes(0)
	check(not world._rotation_started and ui.team.visible,"incomplete normal round returns to formation with a prompt")
	for child:Node in ui.get_children():
		if child is AcceptDialog:child.queue_free()
	await place("right",1,red);await place("left",2,b)
	ui.hide();ui.team.hide();world._update_special_training_modes(0);idle_actors()
	check(world._rotation_started and live("left").size()==1 and live("right").size()==1,"matching manually selected round1 starts correctly")
	var extra:Dictionary=world._rotation_rosters.left[1].duplicate(true);extra.id=900;extra.scene_path="res://unloaded_second_template.tscn"
	world._rotation_rosters.left.append(extra)
	var dead_for_preload:Array[String]=["right"]
	check(world._rotation_next_scene_paths(dead_for_preload).has(extra.scene_path),"loader includes every template in the next round, including a missing later path")
	world._rotation_rosters.left.pop_back()
	await kill_all("right")
	var wait_end:int=Time.get_ticks_msec()+7000
	while world._rotation_transitioning and Time.get_ticks_msec()<wait_end: await process_frame
	idle_actors()
	check(int(world._rotation_next_index.left)==2 and int(world._rotation_next_index.right)==2,"normal grouped rounds advance both sides through the existing doors")
	world.reset();await process_frame;await process_frame;ui.show();ui.team.show();await place("left",1,a)
	ui.hide();ui.team.hide();world._update_special_training_modes(0)
	check(not world._rotation_started and ui.team.visible,"an entirely empty opposing roster also produces the missing-side prompt")
	for child:Node in ui.get_children():
		if child is AcceptDialog: child.queue_free()
	# Deleting a current member never jumps past live teammates.
	world.reset();await process_frame;await process_frame;ui.show();ui.team.show()
	await place("left",1,a);await place("left",1,b);await place("right",1,red)
	ui.hide();ui.team.hide();world._update_special_training_modes(0);idle_actors()
	var removed:int=int(world._rotation_active_records.left[0])
	var removed_ticket:int=world.begin_battle_spawn(live("left")[0],world)
	world.delete_rotation_queue_setup_id(removed)
	await process_frame;await process_frame
	check(live("left").size()==1 and world._rotation_active_records.left.size()==1,"deleting one grouped slot preserves remaining current members")
	check(not world._battle_spawn_tickets.has(removed_ticket),"deleting a whole slot invalidates its pending spawn tickets")
	check(world._rotation_active_name.left=="ball","deleting a grouped slot refreshes the remaining display name")
	# Disabling multi restores one-template-per-placement automatic round selection.
	world.reset();await process_frame;await process_frame;game.Game_Settings.Rotation_Multi_Characters=false
	ui.show();ui.team.show();world.rotation_selected_round=0
	await world.create_char("__rotation_left","ball",a,0);await world.create_char("__rotation_left","ball",b,0)
	check(world._rotation_rosters.left.size()==2 and world._rotation_rosters.left[0].round==1 and world._rotation_rosters.left[1].round==2,"single-template mode automatically assigns consecutive rounds")
	world.select_rotation_round(1);await world.create_char("__rotation_left","ball",b,1)
	check(world._rotation_rosters.left.size()==2,"editing a chosen single-template round replaces rather than adds its occupant")
	game.Game_Settings.Training_Mode_Type="manual";ui._sync_rotation_formation_ui()
	check(not blue_button.visible and not ui.rotation_round_panel.visible,"leaving rotation hides reserved choices and round panel")
	check(ui.return_random_team()=="","hidden rotation teams do not leak into ordinary random teams")
	game.Game_Settings.Rotation_Blue_Count=7;game.Game_Settings.Rotation_Red_Count=9;game.Game_Settings.Rotation_Multi_Characters=true
	game.Game_Settings.Rotation_Match_Type="challenge";game.Game_Settings.Training_Wheel_Battle=true;game.save_persistent_settings()
	game.Game_Settings.Rotation_Blue_Count=1;game.Game_Settings.Rotation_Red_Count=1;game.load_persistent_settings()
	check(game.rotation_team_count("left")==7 and game.rotation_team_count("right")==9 and game.rotation_multi_enabled(),"quantities and multi-round preference survive file reload")
	check(game.Game_Settings.Rotation_Match_Type=="challenge" and game.is_rotation_wheel_enabled(),"saved challenge and independent wheel preference coexist")
	world.reset();await process_frame;world.queue_free();await process_frame;game.Game_Settings=saved
	print("ROTATION_ROSTERS checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
