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
	camera.zoom=Vector2(3.5,3.5)
	camera.make_current()
	camera.force_update_scroll()
	for song:int in range(3):
		var point:Vector2=Vector2(-40,-100+song*100)
		var actor:Node2D=spawn("音符盒",point)
		actor.music.stop()
		actor.direction=Vector2.RIGHT
		actor.visual_mob()
		var wave:Node2D=actor.WAVE.new()
		world.add_child(wave)
		wave.configure(actor,song,actor.global_position,Vector2.RIGHT,0.85,18,song)
		wave.radius=72
		wave.set_physics_process(false)
		wave.queue_redraw()
		var label:=Label.new()
		label.text=["Pigstep","Otherside","CAT"][song]
		label.add_theme_font_size_override("font_size",14)
		label.scale=Vector2(0.55,0.55)
		label.position=actor.global_position+Vector2(-18,18)
		world.add_child(label)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mc_note_revision3_themes.png")
	print("NOTE3_THEMES_SAVED")
	finish(0)
