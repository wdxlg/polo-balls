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
	root.size=Vector2i(960,540)
	world.camera_2d.global_position=center
	world.camera_2d.zoom=Vector2(2.5,2.5)
	world.camera_2d.reset_smoothing()
	for i:int in range(3):
		var actor:Node2D=spawn("守卫者",Vector2(-120+i*120,20),"Team0")
		actor.set_process(false)
		actor.beam_active=true
		actor.beam_end=actor.global_position+Vector2(65,-65)
		actor._tick_left=actor.laser_tick*(1.0-[0.1,0.55,0.95][i])
		actor.gaze=Vector2(1,-1).normalized()
		actor.advance_facing(1.0)
		if i==1:
			actor.spike_charging=true
			actor._spike_charge=actor.spike_charge_time*0.9
		if i==2:
			actor._spike_burst(actor.global_position)
			actor._spike_burst_age=0.075
			var fx:Node=actor._spike_effects.back()
			fx.set_process(false)
			fx.age=0.06
			fx.queue_redraw()
		actor.visual_mob()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	image.resize(960,540)
	image.save_png("user://guardian_burst_preview.png")
	print("GUARDIAN_PREVIEW_PATH ",ProjectSettings.globalize_path("user://guardian_burst_preview.png"))
	await clear_units()
	await create_timer(2).timeout
	finish(0)
