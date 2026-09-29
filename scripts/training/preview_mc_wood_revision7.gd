extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()+Vector2(0,-80)
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center
	camera.zoom=Vector2(3.0,3.0)
	camera.make_current()
	camera.force_update_scroll()
	var sword:Node2D=spawn("木剑",Vector2(0,-55))
	sword.sword_charge=1
	sword.begin_swing()
	sword.advance_attack(sword.attack_duration()*0.65)
	sword.visual_mob()
	var broken:Node2D=spawn("木剑",Vector2(0,60))
	broken.spend_durability(45)
	await process_frame
	var bench:Node2D=broken.workbench
	bench.set_physics_process(false)
	bench.age=3.0
	bench.update_opacity()
	bench.progress=1.2
	for part:Node2D in bench.living_pieces():
		part.state_machine.set_physics_process(false)
		part.global_position=bench.global_position+Vector2(-25 if part==broken else 25,0)
		part.visual_mob()
	bench.queue_redraw()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mc_wood7_visual.png")
	print("WOOD7_VISUAL_SAVED")
	finish(0)
