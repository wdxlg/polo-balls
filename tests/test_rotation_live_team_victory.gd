extends "res://tests/test_rotation_timed_flow.gd"
func frame_wait(seconds:float) -> void:
	await create_timer(seconds,true,false,true).timeout
func enable_motion(unit:Node) -> void:
	unit.process_mode=Node.PROCESS_MODE_INHERIT;unit.set_physics_process(true)
	unit.Can_Attack=false;unit.Can_Skill=false;unit.Health_Restore=0
	unit.Speed=45;unit.direction=Vector2.RIGHT;unit.state_machine.set_physics_process(true)
func normal_actor(id:int,team:String,offset:float) -> Node:
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var entry:Dictionary={"id":id,"char":"ball","scene_path":"res://scenes/ball.tscn","team":team,"x":center.x+offset,"y":center.y}
	world._battle_setup.append(entry)
	var unit:Node=world._spawn_character_from_setup(entry)
	unit.Can_Attack=false;unit.Can_Skill=false;unit.Health_Restore=0;unit.state_machine.set_physics_process(false)
	return unit
func normal_setup() -> void:
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="manual";world.control.hide();world.control.team.hide()
func verdict(losers:Array) -> void:
	world.duel_top_hud._update_clock(0)
	world.duel_top_hud._process(0.2)
	world._update_manual_victory_bell()
	for unit:Node in losers:unit.health=0;unit.queue_free()
	await process_frame;world._update_manual_victory_bell()
	await process_frame;world.duel_top_hud._process(0.2)
func run() -> void:
	create_timer(110,true,false,true).timeout.connect(func():print("ROUND_REVISION_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true);root.size=Vector2i(540,960)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_process(false);world.set_physics_process(false)
	for mode:String in ["duel","challenge"]:
		await setup(mode,2,2)
		var old:Node=current("left");old.health=23;enable_motion(old)
		var original:int=old.get_instance_id();var pos:Vector2=old.global_position
		var loser:Node=current("right");loser.health=0;loser.queue_free()
		for _step:int in range(8): await physics_frame
		print("OLD_MOTION ",mode," active=",world.is_combat_runtime_active()," distance=",old.global_position.distance_to(pos))
		check(world.is_combat_runtime_active() and old.global_position.distance_to(pos)>1,mode+": old round really moves during death revalidation")
		check(await until(func():return world.duel_top_hud.round_result_locked),mode+": achievement arrives while original round lives")
		pos=old.global_position;await frame_wait(0.2)
		check(world.is_combat_runtime_active() and old.global_position.distance_to(pos)>1,mode+": old survivor continues real movement during victory UI")
		check(await until(func():return is_instance_valid(world._rotation_door) and world._rotation_door.phase==world._rotation_door.Phase.CLOSING),mode+": original door closes")
		var door:Node=world._rotation_door;pos=old.global_position;await frame_wait(0.08)
		check(door.phase==door.Phase.CLOSING and world.is_combat_runtime_active() and old.global_position.distance_to(pos)>0.2,mode+": closing doors do not pause gameplay")
		check(int(world._rotation_next_index.right)==1 and old.get_instance_id()==original,mode+": closing does not clear or replace old scene")
		check(await until(func():return world._rotation_combat_blocked),mode+": only fully covered loading closes combat gate")
		check(door.phase==door.Phase.COVERED and not world.is_combat_runtime_active(),mode+": cover really blocks new combat")
		check(await until(func():return world._rotation_combat_released),mode+": half-open releases new fight")
		check(door.progress<=0.5 and world.is_combat_runtime_active(),mode+": midpoint remains formal new-round start")
		await until(func():return not world._rotation_transitioning)
	# The former winner can die before cover; challenge must not credit a dead challenger.
	await setup("challenge",2,2)
	var late_blue:Node=current("left");var late_red:Node=current("right");late_red.health=0;late_red.queue_free()
	await until(func():return world.duel_top_hud.round_result_locked)
	late_blue.health=0;late_blue.queue_free()
	await until(func():return world._rotation_load_ready)
	check(str(world._rotation_results[1])=="dead" and int(world._rotation_active_setup.left)==2,"late old-round death is revalidated at cover, not incorrectly credited as a challenge win")
	await until(func():return not world._rotation_transitioning)
	await setup("wheel",2,2)
	var survivor:Node=current("left");survivor.health=23;enable_motion(survivor)
	var origin:Vector2=survivor.global_position;var retired:Node=current("right");retired.health=0;retired.queue_free()
	check(await until(func():return int(world._rotation_active_setup.right)==4),"wheel directly advances replacement without result/door delay")
	var entering:Node=current("right");var start:Vector2=entering.global_position
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	check(not is_instance_valid(world._rotation_door) and not world.duel_top_hud.round_result_locked,"wheel never opens door or per-round achievement")
	check(start.x>rect.end.x and entering.has_meta("map_rescue_animating"),"wheel replacement originates physically outside map")
	check(entering.z_index==95 and not entering.state_machine.is_physics_processing(),"ingress is visible above outside crop and not driven by competing AI movement")
	await capture("wheel_entry_start")
	await frame_wait(0.18)
	check(entering.global_position.x<start.x and entering.global_position.x>world._rotation_spawn_position("right").x,"wheel walks continuously inward, not instant appearance")
	check(survivor.health==23 and survivor.global_position.distance_to(origin)>1,"winner keeps damage and moves during incoming replacement")
	await capture("wheel_entry_mid")
	game.now_stop_state=true;var paused_pos:Vector2=entering.global_position;await frame_wait(0.12)
	check(entering.global_position.distance_to(paused_pos)<0.2,"explicit gameplay pause freezes ingress")
	game.now_stop_state=false
	check(await until(func():return not entering.has_meta("map_rescue_animating")),"wheel finishes ingress without stranded physics")
	check(entering.z_index!=95 and entering.state_machine.is_physics_processing(),"ingress restores original depth and AI physics")
	await capture("wheel_direct_entry")
	# Multi-person team remains a team even after all but one original member die.
	await normal_setup()
	var blue1:Node=normal_actor(101,"A",-45);var blue2:Node=normal_actor(102,"A",-20)
	var red1:Node=normal_actor(103,"B",20);var red2:Node=normal_actor(104,"B",45)
	await verdict([blue2,red1,red2])
	var result:Dictionary=world.duel_top_hud.victory_result
	check(world._victory_bell_played and world.duel_top_hud.outro_active and world.duel_top_hud.visible,"multi-team verdict shows original shared achievement without requiring 1v1")
	check(result.get("is_team",false) and result.get("member_count",0)==2 and result.get("wool","")=="blue","original two-person blue roster keeps blue wool even with one survivor")
	check("蓝色队伍" in world.duel_top_hud.victory_body_text(),"team winner text names its color, not an individual")
	check(world.duel_top_hud._victory_texture()!=null,"native wool texture resolves")
	world.duel_top_hud.outro_elapsed=2;await capture("blue_team_wool")
	var mirror:Control=world.duel_top_hud.make_mirror("en",world.COMBAT_TEXT_VISIBILITY_LAYER);world.versus_screen_layer.add_child(mirror)
	check("Blue Team" in mirror.victory_body_text() and mirror._victory_texture()==world.duel_top_hud._victory_texture(),"read-only English mirror shares roster/color and localizes team label")
	if DisplayServer.get_name()!="headless":
		var viewport:=SubViewport.new();viewport.size=Vector2i(1080,1920);viewport.world_2d=World2D.new();viewport.transparent_bg=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var record_mirror:Control=world.duel_top_hud.make_mirror("en",world.COMBAT_TEXT_VISIBILITY_LAYER);viewport.add_child(record_mirror)
		await process_frame;await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("user://round_flow_team_recording_en.png")
		viewport.queue_free()
	mirror.queue_free()
	# A genuinely single-person team stays a character, even against a many-person team.
	await normal_setup()
	blue1=normal_actor(201,"A",-45);blue2=normal_actor(202,"A",-20);var _solo:Node=normal_actor(203,"B",35)
	await verdict([blue1,blue2]);result=world.duel_top_hud.victory_result
	check(not result.get("is_team",true) and result.get("member_count",0)==1,"single-person winning team still uses individual identity")
	check(not "队伍" in world.duel_top_hud.victory_body_text() and world.duel_top_hud._victory_texture()!=null,"single winner displays character portrait and name")
	world.duel_top_hud.outro_elapsed=2;await capture("single_winner")
	await normal_setup()
	blue1=normal_actor(301,"A",-45);red1=normal_actor(302,"B",20);red2=normal_actor(303,"B",45)
	await verdict([blue1]);result=world.duel_top_hud.victory_result
	check(result.get("is_team",false) and result.get("wool","")=="red" and "红色队伍" in world.duel_top_hud.victory_body_text(),"multiple surviving red winners share one red-team wool result")
	world.duel_top_hud.outro_elapsed=2;await capture("red_team_wool")
	await normal_setup()
	blue1=normal_actor(601,"A",-55);red1=normal_actor(602,"B",0)
	var _third1:Node=normal_actor(603,"C",30);var _third2:Node=normal_actor(604,"C",55)
	await verdict([blue1,red1]);result=world.duel_top_hud.victory_result
	check(result.get("is_team",false) and result.get("member_count",0)==2 and result.get("key","")=="team:C","third-color multi-person team receives a single stable team result")
	check(result.get("color",Color.TRANSPARENT)==world._versus_side_color("team:C",3,2) and str(result.get("wool","")) in world.duel_top_hud.WOOL_NAMES,"third-team wool uses existing VS color mapped to native dye palette")
	for mode:String in ["boss","timed"]:
		await normal_setup()
		blue1=normal_actor(501,"A",-40);blue2=normal_actor(502,"A",-15);red1=normal_actor(503,"B",35)
		game.Game_Settings.Training_Mode_Type=mode
		if mode=="timed":
			world._timed_running=true;world._timed_damage_by_setup={501:3.0,502:5.0,503:100.0}
			world._finish_timed_training();await process_frame;world.duel_top_hud._process(0.2)
		else:
			world._boss_started=true;world._boss_intro_playing=false
			await verdict([red1])
		check(world.duel_top_hud.victory_result.get("is_team",false) and world.duel_top_hud.victory_result.get("wool","")=="blue",mode+": non-rotation result uses the same original-team wool presentation")
	# Ordinary summons do not turn a solo root into a multi-person team.
	await normal_setup()
	blue1=normal_actor(401,"A",-35);red1=normal_actor(402,"B",35)
	var summon:Node=load("res://scenes/ball.tscn").instantiate();summon.Master=blue1;summon.Team="A";world.add_child(summon)
	summon.state_machine.set_physics_process(false);summon.Can_Attack=false;summon.Can_Skill=false
	await verdict([red1]);check(world.duel_top_hud.victory_result.get("member_count",0)==1,"summons never inflate original team membership")
	await normal_setup();check(world.duel_top_hud.victory_result.is_empty(),"reset clears roster-derived winner and wool")
	await setup("duel",1,1)
	world.duel_top_hud.begin_round_result("left")
	check(world.duel_top_hud.victory_result.is_empty() and not "队伍" in world.duel_top_hud.victory_body_text(),"rotation explicitly retains character outcome and never adopts team wool")
	world.reset();await process_frame;await process_frame;game.Game_Settings=saved;world.queue_free();await process_frame
	var door:Node=root.get_node_or_null("DarkOakDoorTransition")
	if door!=null:door.queue_free()
	print("ROUND_REVISION_RESULT checks=%d failures=%d renderer=%s"%[checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
