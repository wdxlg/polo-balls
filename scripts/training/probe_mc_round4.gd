extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.now_stop_state=false
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.camera_2d.global_position=center
	world.camera_2d.zoom=Vector2(2,2)
	world.camera_2d.reset_smoothing()
	var g:Node2D=spawn("守卫者",Vector2(-90,-80))
	var v:Node2D=spawn("",Vector2(70,-80),"Team1")
	v.health=10000
	g.step_mob(0.01)
	g.advance_facing(5)
	g.visual_mob()
	var s:Node2D=spawn("史莱姆",Vector2(0,80))
	s.emit_jump_fx(true)
	var fx:Node2D=get_nodes_in_group("MCSlimeJumpFX")[0]
	fx.set_process(false)
	fx.update_visual(0.07)
	await process_frame
	print("PROBE gpos ",g.global_position," beam local/global ",g.beam.transform," / ",g.beam.global_transform," pts ",g.beam.points," beamvis ",g.beam.visible," active ",g.beam_active)
	for it:CanvasItem in [s,s.graphics,s.image,fx,fx.ring]: print("PROBE LAYER ",it.get_path()," z ",it.z_index," rel ",it.z_as_relative," top ",it.is_set_as_top_level()," canvas ",it.get_canvas())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mc_round4_before.png")
	finish(0)
