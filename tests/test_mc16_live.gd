extends "res://tests/test_mc16_spider_drowned.gd"
# Finite live battle: no direct damage calls; real physics, timers and skill loops.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(35.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(1.8,1.8)
	camera.make_current()
	var spider:Node2D = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(-160,-70))
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(120,70))
	var ally:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(180,-70))
	# Brief quiet opening: let real ambient/network timers fire before continuous
	# silk/charged-hit damage saturates the protected 24-voice budget. No fake audio calls.
	spider._mc_ambient_wait = 0.12
	var trapped:Node2D = dummy(center+Vector2(-600,500))
	var target:Node2D = dummy(center+Vector2(600,500))
	# This fixture now runs beyond the new 12s charge delay; keep both test targets
	# alive for the full observation and keep the quiet-window parking inside the map.
	for actor:Node in [trapped,target]:
		actor.Max_health = 10000000.0
		actor.default_properties["Max_health"] = 10000000.0
		actor.health = 10000000.0
	var safe_rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"]).grow(-80.0)
	# A slow real walker stays within the web and exercises terrain footsteps.
	trapped.Speed = 20.0
	trapped.default_properties["Speed"] = 20.0
	trapped.direction = Vector2.RIGHT
	trapped.state_machine.set_physics_process(true)
	for manager:Node in get_nodes_in_group("MCSpiderWebFootsteps"): manager.set_physics_process(true)
	for p:Vector2 in [Vector2(-230,-130),Vector2(230,130),Vector2(230,-130),Vector2(-230,130)]: wall_touch(spider.silk_network,center+p)
	# Seed two wall poles, then let charging, periodic strikes and the network run.
	for pair:Array in [[drowned,center+Vector2(110,40)],[ally,center+Vector2(190,-45)]]:
		var unit:Node = pair[0]
		var spear:Node = unit._trident
		spear.launch(Vector2.RIGHT)
		spear.stick(pair[1])
		spear.set_physics_process(true)
		unit._refill_left = 0.2
		unit.Speed = 0.0
		unit.default_properties["Speed"] = 0.0
		unit.state_machine.set_physics_process(true)
	spider.silk_network.set_physics_process(true)
	spider.state_machine.set_physics_process(true)
	world.get_node("MCTridentNetwork").set_physics_process(true)
	var hp0:float = trapped.health
	var hp1:float = target.health
	var saw_hunt:bool = false
	var saw_return:bool = false
	var saw_arc:bool = false
	var saw_charge:bool = false
	var saw_stun:bool = false
	var struck:int = 0
	var capture:bool = OS.get_cmdline_user_args().has("--capture")
	for i:int in range(260):
		if i==10:
			trapped.global_position = center
			target.global_position = center+Vector2(110,40) # Inside the real pole radius.
		if i==140:
			trapped.global_position = Vector2(safe_rect.position.x,safe_rect.end.y)
			target.global_position = safe_rect.end
		if i==180:
			trapped.global_position = center
			target.global_position = center+Vector2(110,40)
		await create_timer(0.08).timeout
		if not is_instance_valid(trapped) or not is_instance_valid(target):
			check(false,"long-run fixture targets remain alive inside arena")
			finish(1)
			return
		saw_hunt = saw_hunt or spider._lunge_left>0.0
		saw_arc = saw_arc or not get_nodes_in_group("MCTridentArc").is_empty()
		saw_stun = saw_stun or trapped.dizziness or target.dizziness
		for spear:Node in get_nodes_in_group("MCTrident"):
			saw_return = saw_return or spear.flight_state==2
			saw_charge = saw_charge or spear.charged
			for child:Node in spear.get_children():
				if child.has_signal("impact_started") and child._impact_started: struck += 1
		if capture and i in [0,1,31,65,82]:
			await RenderingServer.frame_post_draw
			var image:Image = root.get_texture().get_image()
			image.save_png("res://tests/mc16_rework_live_"+str(i)+".png")
	check(trapped.health<hp0 and target.health<hp1,"live silk / trident mechanics cause real damage")
	check(saw_hunt,"live crossing web triggers autonomous spider pounce")
	check(saw_return,"live ordinary attack goes out and spins back")
	check(saw_charge,"live twelve-second grounded timer enchants wall trident")
	check(struck>0,"live warning reaches Creeper lightning impact")
	check(saw_arc,"live same-team charged endpoints generate arcs")
	check(saw_stun,"live lightning still applies timed stun")
	check(not get_nodes_in_group("MCSpiderSilk").is_empty(),"live silk network remains attached")
	check(int(spider.native_feedback.played.get("block.cobweb.place",0))>0 and int(spider.native_feedback.played.get("block.cobweb.step",0))>0,"live native cobweb placement and walking sounds")
	check(int(spider.native_feedback.played.get("entity.spider.ambient",0))>0,"live spider breathes with timed original hiss")
	var trident_cues:Dictionary = {}
	for actor:Node in [drowned,ally]:
		for event:String in actor.native_feedback.played: trident_cues[event] = int(trident_cues.get(event,0))+int(actor.native_feedback.played[event])
	for event:String in ["item.trident.throw","item.trident.hit","item.trident.return","item.trident.hit_ground","block.enchantment_table.use","item.trident.thunder","block.redstone_torch.burnout"]:
		check(int(trident_cues.get(event,0))>0,"live original sound trigger: "+event)
	check(trapped.Buff_Dic.get(spider.get_instance_id(),{}).has("蜘蛛网"),"live cobweb maintains strong movement slow")
	print("MC16_LIVE checks=",checks," failures=",failures," impacts=",struck)
	finish(0 if failures==0 else 1)
