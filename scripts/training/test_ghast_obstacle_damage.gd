extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	var ghast:Node2D=spawn("恶魂",Vector2(-200,0),"Team0")
	var ghast2:Node2D=spawn("恶魂",Vector2(-200,120),"Team1")
	var manager:Node=load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").ensure(ghast)
	var layer:TileMapLayer=world._current_map_node()
	var cell:Vector2i=layer.local_to_map(layer.to_local(center))
	var floor_data:Array=[layer.get_cell_source_id(cell),layer.get_cell_atlas_coords(cell),layer.get_cell_alternative_tile(cell)]
	# Runtime maps use hidden planning tiles. Explicitly enable this layer to test
	# compatibility with actual visible/collidable tile-based obstacles.
	layer.visible=true
	layer.collision_enabled=true
	layer.set_cell(cell,0,Vector2i(0,0),0)
	layer.update_internals()
	await physics_frame
	var point:Vector2=layer.to_global(layer.map_to_local(cell))
	var key:String=str(world.get_path_to(layer))+"/tile/"+str(cell)
	var shot:Node2D=blast(ghast,point)
	check(manager.records.has(key),"enabled tile obstacle is registered by fireball explosion")
	if manager.records.has(key):
		check(manager.records[key].hits==1,"first blast adds one damage stage")
		check(is_equal_approx(manager.damage_progress(key,layer),34.0),"first blast increments shared 0-100 progress")
		check(manager.records[key].overlay.texture==manager.CRACKS[0],"first blast shows native mining cracks")
		shot.explode()
		check(manager.records[key].hits==1,"same explosion cannot count twice")
		check(layer.get_cell_atlas_coords(cell)==Vector2i(0,0),"first blast does not destroy obstacle")
		blast(ghast2,point)
		check(manager.records[key].hits==2 and manager.records[key].overlay.texture==manager.CRACKS[1],"another ghast's second blast deepens cracks cumulatively")
		check(is_equal_approx(manager.damage_progress(key,layer),68.0),"repeated explosions accumulate progress rather than resetting cracks")
		blast(ghast,point)
		check(manager.records[key].hits==3,"third blast completes destruction")
		check(is_equal_approx(manager.damage_progress(key,layer),100.0),"destruction clamps progress at 100")
		check(not manager.colliding(layer.get_cell_tile_data(cell),layer.tile_set),"destroyed tile becomes traversable floor")
		check(layer.get_cell_source_id(cell)>=0,"destroying obstacle does not erase map ground")
		check(manager.records[key].overlay==null,"destroyed tile removes crack overlay")
		layer.update_internals()
		await physics_frame
		check(u.trace(ghast,point-Vector2(12,0),point+Vector2(12,0)).is_empty(),"destroyed tile no longer blocks physical ray")
	manager.reset_all()
	check(layer.get_cell_atlas_coords(cell)==Vector2i(0,0),"round reset restores original obstacle tile")
	check(manager.records.is_empty(),"round reset clears accumulated damage")
	layer.set_cell(cell,floor_data[0],floor_data[1],floor_data[2])
	layer.visible=false
	layer.collision_enabled=false
	var body:StaticBody2D=obstacle(Vector2(140,0),true)
	var extra:=CollisionShape2D.new()
	extra.shape=body.get_child(0).shape
	body.add_child(extra)
	var boundary:StaticBody2D=obstacle(Vector2(160,0),true,true)
	await physics_frame
	var body_key:String=str(world.get_path_to(body))+"/body"
	point=body.global_position
	blast(ghast,point)
	check(manager.records.has(body_key) and manager.records[body_key].hits==1,"multiple collision shapes count as one obstacle per explosion")
	check(not manager.records.has(str(world.get_path_to(boundary))+"/body"),"map safety boundary never takes mining damage")
	blast(ghast2,point)
	check(body.visible,"static obstacle remains after two blasts")
	blast(ghast,point)
	await process_frame
	await physics_frame
	check(not body.visible and body.collision_layer==0,"third blast removes static obstacle visuals and collision")
	check(boundary.visible and boundary.collision_layer==1,"boundary survives adjacent explosions")
	world._clear_battle_transients()
	check(body.visible and body.collision_layer==1,"real battle cleanup restores static obstacle")
	check(manager.records.is_empty(),"real battle cleanup removes all cracks and counters")
	body.queue_free()
	boundary.queue_free()
	await physics_frame
	# A non-default collision layer is still an obstacle, with adjustable durability/crack stages.
	var tuned:StaticBody2D=obstacle(Vector2(140,110),true)
	tuned.collision_layer=4
	var profile:Node=load("res://scripts/effects/我的世界/mc_obstacle_properties.gd").new()
	profile.name="MCObstacleProperties"
	profile.set("blast_step",25.0)
	profile.set("crack_thresholds",PackedFloat32Array([25.0,75.0]))
	tuned.add_child(profile)
	await physics_frame
	var tuned_key:String=str(world.get_path_to(tuned))+"/body"
	for i:int in range(4):
		blast(ghast,tuned.global_position)
		check(is_equal_approx(manager.damage_progress(tuned_key,tuned),minf(100.0,float(i+1)*25.0)),"common obstacle durability is tunable, hit="+str(i+1))
		if i==0: check(manager.records[tuned_key].overlay.texture==manager.CRACKS[0],"custom first crack threshold is honored")
		if i==2: check(manager.records[tuned_key].overlay.texture==manager.CRACKS[1],"custom deeper crack threshold is honored")
	check(tuned.is_queued_for_deletion() or not tuned.visible,"tuned obstacle breaks at its configured 100 progress")
	var stone:Node2D=load("res://scenes/terrain/矿工小石头.tscn").instantiate()
	stone.lifetime=0.0
	stone.spawn_collision_delay=0.0
	stone.position=center+Vector2(100,140)
	world.add_child(stone,true)
	await physics_frame
	await physics_frame
	point=stone.global_position
	var stone_key:String=str(world.get_path_to(stone))+"/body"
	blast(ghast,point)
	check(manager.records.has(stone_key),"actual miner stone is damaged")
	if manager.records.has(stone_key):
		check(manager.records[stone_key].overlay.is_visible_in_tree(),"mining cracks visible on real obstacle")
		blast(ghast2,point)
		check(manager.records[stone_key].hits==2,"real stone accumulates two blast hits")
		blast(ghast,point)
		check(stone.is_queued_for_deletion(),"third blast removes transient obstacle instead of leaving ghost logic")
		check(not stone.is_in_group("AI_Hazard"),"destroyed obstacle no longer misleads AI")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
func blast(ghast:Node2D,point:Vector2) -> Node2D:
	var shot:Node2D=ghast.fire_at(point)
	shot.state_machine.set_physics_process(false)
	shot.global_position=point
	shot.explode()
	return shot
