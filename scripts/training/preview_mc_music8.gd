extends "res://scripts/training/test_mc_new5.gd"

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	var backdrop:=ColorRect.new()
	backdrop.color=Color(0.018,0.026,0.045)
	backdrop.position=center-Vector2(900,900)
	backdrop.size=Vector2(1800,1800)
	backdrop.z_as_relative=false
	backdrop.z_index=1
	world.add_child(backdrop)
	var anchor:=ColorRect.new()
	anchor.color=Color(1.0,0.28,0.22,0.55)
	anchor.position=center+Vector2(-145,48)
	anchor.size=Vector2(290,2)
	anchor.z_as_relative=false
	anchor.z_index=4
	world.add_child(anchor)
	var pitches:Array[float]=[-1.0,0.0,1.0]
	for i:int in range(3):
		var actor:Node2D=spawn("唱片机",Vector2(-130+i*130,0))
		actor.set_process(false)
		actor.record_phase=1
		actor.music.stop()
		actor.body_punch=0
		actor._music_base_scale=Vector2(4,4)
		actor.set_music_shape(pitches[i],1.0)
		actor.advance_music_shape(0.5)
		actor.visual_mob()
		actor.image.z_as_relative=false
		actor.image.z_index=5
		if actor.has_node("Health_Bar"): actor.get_node("Health_Bar").hide()
		var label:=Label.new()
		label.text=["LOW / FAT","MID","HIGH / THIN"][i]
		label.add_theme_font_size_override("font_size",18)
		label.add_theme_color_override("font_color",Color(0.82,0.88,1.0))
		label.scale=Vector2(0.55,0.55)
		label.position=center+Vector2(-116+i*100,66)
		label.z_as_relative=false
		label.z_index=8
		world.add_child(label)
	var title:=Label.new()
	title.text="CONTINUOUS MUSIC BODY SHAPE (4X CLOSE-UP)"
	title.add_theme_font_size_override("font_size",13)
	title.add_theme_color_override("font_color",Color(0.52,0.65,0.95))
	title.scale=Vector2(0.5,0.5)
	title.position=center+Vector2(-108,-88)
	title.z_as_relative=false
	title.z_index=8
	world.add_child(title)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center+Vector2(0,-5)
	camera.zoom=Vector2(2.15,2.15)
	camera.make_current()
	camera.force_update_scroll()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	img.resize(540,720,Image.INTERPOLATE_LANCZOS)
	img.save_jpg("user://mc_music8_preview.jpg",0.86)
	print("MUSIC8_PREVIEW_SAVED")
	finish(0)
