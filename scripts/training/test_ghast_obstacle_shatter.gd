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
	var _sword:Node2D=spawn("钻石剑",Vector2(-200,140),"Team1")
	await create_timer(0.1).timeout
	var arena:Node=world.get_node_or_null("MinecraftNetheriteArenaManager")
	if arena==null:
		arena=load("res://scripts/effects/我的世界/下界合金竞技场.gd").new()
		world.add_child(arena)
	arena._ensure_table()
	await physics_frame
	var table:Node2D=get_first_node_in_group("MinecraftSmithingTable")
	check(is_instance_valid(table),"real diamond-sword smithing table exists")
	var point:Vector2=table.global_position
	var manager:Node=load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").ensure(ghast)
	for i:int in range(2): blast(ghast,point)
	check(table.visible and not table.is_queued_for_deletion(),"table intact through first two blasts")
	var previous:int=get_nodes_in_group("MCItemFragments").size()
	blast(ghast,point)
	check(table.is_queued_for_deletion() and not table.visible,"third blast actually removes table")
	check(get_nodes_in_group("MinecraftSmithingTable").is_empty(),"destroyed table immediately stops being usable for smithing")
	check(world.get_meta("mc_smithing_table_destroyed",false),"table destruction is remembered for the current round")
	check(get_nodes_in_group("MCItemFragments").size()==previous+1,"obstacle keeps the original flying fragmentation effect")
	var fx:Node2D=get_nodes_in_group("MCItemFragments").back()
	check(fx.pieces.size()>1,"table breaks into multiple texture pieces")
	for piece:Dictionary in fx.pieces:
		check(piece.sprite.texture.atlas.resource_path.contains("smithing_table"),"fragments come from the native smithing table texture, not the crack overlay")
	var before:Vector2=fx.pieces[0].sprite.global_position
	fx.advance(0.05)
	check(fx.pieces[0].sprite.global_position!=before,"original obstacle fragments launch and fall without changing the obstacle flow")
	await process_frame
	for i:int in range(8):
		arena._ensure_table()
		arena._process(0.1)
		await process_frame
	check(get_nodes_in_group("MinecraftSmithingTable").is_empty(),"active diamond sword cannot immediately respawn destroyed table")
	check(is_instance_valid(fx),"debris survives removal of source obstacle")
	manager.reset_all()
	check(not world.has_meta("mc_smithing_table_destroyed"),"round reset clears destroyed-table latch")
	arena._ensure_table()
	await process_frame
	check(is_instance_valid(get_first_node_in_group("MinecraftSmithingTable")),"new round can spawn a fresh smithing table")
	var fresh:Node2D=get_first_node_in_group("MinecraftSmithingTable")
	await physics_frame
	blast(ghast,fresh.global_position)
	var key:String=str(world.get_path_to(fresh))+"/body"
	check(manager.records[key].hits==1,"new table starts with a clean three-hit count")
	world._clear_battle_transients()
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
func blast(ghast:Node2D,point:Vector2) -> void:
	var shot:Node2D=ghast.fire_at(point)
	shot.state_machine.set_physics_process(false)
	shot.global_position=point
	shot.explode()
