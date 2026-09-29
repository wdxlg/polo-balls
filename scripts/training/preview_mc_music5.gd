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
	var backdrop:=ColorRect.new()
	backdrop.color=Color(0.025,0.035,0.06)
	backdrop.position=center-Vector2(1500,1500)
	backdrop.size=Vector2(3000,3000)
	backdrop.z_as_relative=false
	backdrop.z_index=1
	world.add_child(backdrop)
	var examples:Array=[
		[0.95,0.25,0.15,0.2,0.8,0.06,0.95,false],
		[0.1,0.8,0.95,0.8,0.3,0.06,0.6,false],
		[0.1,0.1,0.1,0.85,0.95,0.9,0.35,false]]
	for song:int in range(3):
		var actor:Node2D=spawn("唱片机",Vector2(-65,-150+song*145))
		actor.set_process(false)
		actor.image.z_as_relative=false
		actor.image.z_index=3
		actor.record_phase=1
		actor.music.stop()
		actor.visual_mob()
		var wave:Node2D=actor.WAVE.new()
		world.add_child(wave)
		wave.configure(actor,song,actor.global_position,Vector2.RIGHT,0.9,18,song,100)
		wave.apply_music_profile(examples[song])
		wave.radius=85
		wave.age=0.03
		wave.set_physics_process(false)
		wave.queue_redraw()
		var label:=Label.new()
		label.text=["LOW BEAT / IMPACT","SNARE + HIGH TICKS","HIGH PITCH / SUSTAIN"][song]
		label.add_theme_font_size_override("font_size",14)
		label.scale=Vector2(0.55,0.55)
		label.position=actor.global_position+Vector2(-10,67)
		label.z_index=10
		world.add_child(label)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	img.resize(540,960,Image.INTERPOLATE_LANCZOS)
	img.save_jpg("user://mc_music5_preview.jpg",0.82)
	print("MUSIC5_PREVIEW_SAVED")
	finish(0)
