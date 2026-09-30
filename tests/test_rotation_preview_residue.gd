extends "res://tests/test_rotation_frames_challenge.gd"
# Formation previews are frozen, yet their deferred _ready work (bat swarm, Bruce's dog...)
# used to leave real units behind that overlapped the real spawns and jammed at walls.
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():push_error("PREVIEW_RESIDUE_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=true
	game.Game_Settings.Rotation_Multi_Characters=true;game.Game_Settings.Rotation_Blue_Count=3;game.Game_Settings.Rotation_Red_Count=1
	game.Game_Settings.Map_Background="blue";game.Game_Settings.Minecraft_Clouds=false;game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate();world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	world.control.show();world.control.team.show();world.control._sync_training_mode_controls();await process_frame
	world.control._add_rotation_round()
	var map:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	world.select_rotation_round(1)
	await world.create_char("__rotation_left","蝙蝠",map.position+map.size*Vector2(0.7,0.3),1)
	await world.create_char("__rotation_left","布鲁斯",map.position+map.size*Vector2(0.6,0.6),1)
	await world.create_char("__rotation_right","羊",map.position+map.size*Vector2(0.3,0.7),1)
	for i:int in range(30): await physics_frame
	var previews:Dictionary = {}
	for a:Variant in world._rotation_formation_preview.values(): if is_instance_valid(a): previews[a.get_instance_id()] = true
	var before:Array = []
	for n:Node in root.get_tree().get_nodes_in_group("Ball"):
		if not previews.has(n.get_instance_id()): before.append(weakref(n))
	world.control.hide();world.control.team.hide()
	world._update_special_training_modes(0)
	for i:int in range(60): await physics_frame
	var left_over:int = 0
	for r:WeakRef in before:
		var n:Variant = r.get_ref()
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion(): left_over += 1
	check(left_over == 0,"nothing spawned by a formation preview survives the start (%d left)" % left_over)
	var bats:int = 0; var dogs:int = 0; var overlap:int = 0
	var bat_nodes:Array = []
	for n:Node in root.get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or n.health <= 0: continue
		if n.has_meta("mc_bat_cohort"): bats += 1; bat_nodes.append(n)
		elif str(n.name).begins_with("布鲁斯_狗"): dogs += 1
	for i:int in range(bat_nodes.size()):
		for j:int in range(i+1,bat_nodes.size()):
			if bat_nodes[i].global_position.distance_to(bat_nodes[j].global_position) < 1.0: overlap += 1
	check(bats == 15,"three real bat swarms keep their five bats each (%d)" % bats)
	check(dogs == 3,"each real Bruce keeps his dog (%d)" % dogs)
	check(overlap == 0,"no two bats share the same spot (%d pairs)" % overlap)
	print("ROTATION_PREVIEW_RESIDUE checks=%d failures=%d" % [checks,failures])
	game.Game_Settings=saved
	quit(1 if failures > 0 else 0)
