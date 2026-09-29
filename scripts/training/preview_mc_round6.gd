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
	create_timer(65).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<13: await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center
	camera.zoom=Vector2(2.0,2.0)
	camera.make_current()
	camera.force_update_scroll()
	var actors:Array[Node2D]=[]
	var roles:Array[String]=["史莱姆","守卫者","恶魂","木矛","重锤","钻石剑","钓鱼竿","粘性活塞"]
	for i:int in range(roles.size()):
		var offset:Vector2=Vector2((i-1)*150,-140) if i<3 else Vector2((i-5)*90,80)
		var actor:Node2D=spawn(roles[i],offset)
		actor.set_process(false)
		if actor.has_method("visual_mob"): actor.visual_mob()
		actors.append(actor)
	var label:=Label.new()
	label.text="MC DEATH EFFECTS"
	label.position=Vector2(20,120)
	label.add_theme_font_size_override("font_size",28)
	var hud:=CanvasLayer.new()
	root.add_child(hud)
	hud.add_child(label)
	DirAccess.make_dir_recursive_absolute("user://mc_round6_preview")
	for index:int in range(28):
		if index==4:
			for actor:Node2D in actors:
				actor.health=0
				actor.Die()
				actor.queue_free()
		await create_timer(0.10).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://mc_round6_preview/frame_%02d.png"%index)
	check(get_nodes_in_group("MCDeathPose").is_empty(),"death poses completed in real time")
	check(get_nodes_in_group("MCItemFragments").is_empty(),"debris exited map in real time")
	print("ROUND6_DEATH_PREVIEW ",ProjectSettings.globalize_path("user://mc_round6_preview"))
	finish(0 if failures==0 else 1)
