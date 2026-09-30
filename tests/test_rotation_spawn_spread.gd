extends "res://tests/test_rotation_frames_challenge.gd"
# Rotation rounds with several templates and quantity > 1 must not stack bodies or push them into/through the map wall.
func body_rect(actor:Node) -> Rect2:
	var e:Rect2 = world._body_extents_from_origin(actor)
	return Rect2(actor.global_position+e.position,e.size)
func wall_depth(actor:Node,map:Rect2) -> float:
	var r:Rect2 = body_rect(actor)
	return maxf(maxf(map.position.x-r.position.x,r.end.x-map.end.x),maxf(map.position.y-r.position.y,r.end.y-map.end.y))
func units(side:String = "") -> Array:
	var out:Array = []
	for actor:Node in world._battle_units_cache:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.health <= 0 or not actor.has_meta("rotation_side"): continue
		if side == "" or actor.get_meta("rotation_side") == side: out.append(actor)
	return out
func calm() -> void:
	for actor:Node in units():
		actor.Can_Attack = false; actor.Can_Skill = false
func run() -> void:
	create_timer(120,true,false,true).timeout.connect(func():push_error("SPREAD_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=true
	game.Game_Settings.Rotation_Multi_Characters=true;game.Game_Settings.Rotation_Blue_Count=5;game.Game_Settings.Rotation_Red_Count=5
	game.Game_Settings.Map_Background="blue";game.Game_Settings.Minecraft_Clouds=false;game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate();world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	world.control.show();world.control.team.show();world.control._sync_training_mode_controls();await process_frame
	world.control._add_rotation_round()
	var map:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var blue_a:Vector2 = map.position+map.size*Vector2(0.97,0.5)
	var blue_b:Vector2 = map.position+map.size*Vector2(0.6,0.4)
	var red_a:Vector2 = map.position+map.size*Vector2(0.03,0.97)
	for placement:Array in [["left",1,"铁傀儡",blue_a],["left",1,"羊",blue_b],["right",1,"羊",red_a],["left",2,"铁傀儡",blue_a],["right",2,"铁傀儡",red_a]]:
		world.select_rotation_round(placement[1])
		await world.create_char("__rotation_"+placement[0],placement[2],placement[3],placement[1])
	world.control.hide();world.control.team.hide()
	world._update_special_training_modes(0)
	calm()
	var first:Array = units()
	check(first.size() == 15,"first wave: 2 blue templates x5 and 1 red template x5 (%d)" % first.size())
	var stacked:int = 0
	for i:int in range(first.size()):
		for j:int in range(i+1,first.size()):
			if first[i].global_position.distance_to(first[j].global_position) < 1.0: stacked += 1
	check(stacked == 0,"no two bodies spawn on the same point (%d stacked pairs)" % stacked)
	var worst_spawn:float = -INF
	for actor:Node in first: worst_spawn = maxf(worst_spawn,wall_depth(actor,map))
	check(worst_spawn <= 0.0,"every spawned body starts fully inside the map (worst %.1f px)" % worst_spawn)
	var sheep:Node = null
	for actor:Node in units("left"):
		if actor.get_meta("queue_character_name","") == "羊" and int(actor.get_meta("rotation_copy_index",0)) == 0: sheep = actor
	check(sheep != null and sheep.global_position.distance_to(blue_b) < 0.1,"a template placed clear of walls keeps its exact formation spot")
	var streak:Dictionary = {}; var longest:int = 0; var center_out:int = 0
	for f:int in range(90):
		await physics_frame
		for actor:Node in units():
			if actor.has_meta("map_rescue_animating"): continue
			var id:int = actor.get_instance_id()
			streak[id] = int(streak.get(id,0))+1 if wall_depth(actor,map) > 1.5 else 0
			longest = maxi(longest,int(streak[id]))
			if not map.has_point(actor.global_position): center_out += 1
	check(center_out == 0,"no body centre leaves the map during 1.5 s of crowd settling (%d frames)" % center_out)
	check(longest <= 6,"a body pressed into the safety wall is released within 0.1 s (longest %d frames)" % longest)
	# Direct regression for the wall-embed release: a body shoved 6 px into the wall is put back without animation.
	var probe:Node = units("right")[0]
	var e:Rect2 = world._body_extents_from_origin(probe)
	var free_before:bool = probe.has_meta("map_rescue_animating")
	probe.global_position = Vector2(map.end.x-e.end.x+6.0,map.get_center().y)
	world._release_body_from_safety_wall(probe,map)
	check(not free_before and wall_depth(probe,map) <= 0.0 and map.has_point(probe.global_position) and not probe.has_meta("map_rescue_animating"),"embedded body is released to the inside edge instantly (depth %.1f)" % wall_depth(probe,map))
	var phased:Node = units("right")[1]
	phased.set_collision_mask_value(1,false)
	phased.global_position = Vector2(map.end.x-e.end.x+6.0,map.get_center().y+30.0)
	var phased_before:Vector2 = phased.global_position
	world._release_body_from_safety_wall(phased,map)
	check(phased.global_position == phased_before,"bodies that pass walls on purpose (wall collision off) are left alone")
	phased.set_collision_mask_value(1,true)
	# Wheel reinforcement: the whole blue round 1 (with summons) falls, round 2 (iron golem x5) walks in on separate lanes to separate spots.
	for actor:Node in world._battle_units_cache.duplicate():
		if is_instance_valid(actor) and actor.Team == "__rotation_left": actor.health = 0; actor.queue_free()
	await process_frame
	await physics_frame
	world._scan_rotation_family_extinctions()
	var targets:Array = []; var deadline:int = Time.get_ticks_msec()+8000
	var frame:int = 0
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		frame += 1
		if frame % 20 == 0: world._scan_rotation_family_extinctions()
		var walking:Array = units("left").filter(func(a):return a.has_meta("map_rescue_animating"))
		if walking.size() >= 5:
			for a:Node in walking: targets.append(a.get_meta("map_rescue_target"))
			break
	check(targets.size() == 5,"all five reinforcements walk in together (%d)" % targets.size())
	var same_target:int = 0
	for i:int in range(targets.size()):
		for j:int in range(i+1,targets.size()):
			if (targets[i] as Vector2).distance_to(targets[j]) < 1.0: same_target += 1
	check(same_target == 0,"reinforcements get distinct entry targets (%d shared)" % same_target)
	deadline = Time.get_ticks_msec()+8000
	while Time.get_ticks_msec() < deadline and units("left").any(func(a):return a.has_meta("map_rescue_animating")): await physics_frame
	calm()
	var arrived_worst:float = -INF
	for actor:Node in units("left"): arrived_worst = maxf(arrived_worst,wall_depth(actor,map))
	check(units("left").size() == 5 and arrived_worst <= 0.0,"reinforcements finish fully inside the map (worst %.1f px)" % arrived_worst)
	print("ROTATION_SPAWN_SPREAD checks=%d failures=%d" % [checks,failures])
	game.Game_Settings=saved
	quit(1 if failures > 0 else 0)
