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
	var actor:Node2D=spawn("唱片机",Vector2(0,-20))
	actor.direction=Vector2.RIGHT
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.visual_mob()
	var cactus:Node2D=spawn("仙人掌",Vector2(-55,100))
	cactus.levels=3
	cactus.apply_height()
	cactus.set_process(false)
	cactus.set_physics_process(false)
	var label:=Label.new()
	label.add_theme_font_size_override("font_size",14)
	label.scale=Vector2(0.55,0.55)
	label.position=actor.global_position+Vector2(-50,23)
	world.add_child(label)
	for frame:int in range(80):
		if frame==18:
			actor._track_finished()
			actor._ejected_record.set_physics_process(false)
		if frame==22: cactus.health-=100
		actor.advance_record(0.05)
		if actor.record_phase==2 and is_instance_valid(actor._ejected_record): actor._ejected_record.advance(0.05)
		if cactus.retaliation_age>=0: cactus.advance_retaliation(0.05)
		actor.visual_mob()
		cactus.visual_mob()
		label.text=["INSERT / ","PLAY / ","EJECT / "][actor.record_phase]+actor.TRACKS[actor.track_index].to_upper()
		await create_timer(0.05).timeout
		await RenderingServer.frame_post_draw
		var frame_image:Image=root.get_texture().get_image()
		frame_image.resize(540,960,Image.INTERPOLATE_LANCZOS)
		frame_image.save_png("user://jukebox_frame_%03d.png"%frame)
	print("JUKEBOX_PREVIEW_SAVED")
	finish(0)
