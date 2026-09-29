extends "res://tests/test_mc_bat.gd"
func run() -> void:
	game = root.get_node("Game")
	BAT = load("res://scripts/characters/我的世界/bat/bat.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	world.versus_label.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var b:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(-65,0))
	var v:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(65,0))
	b.state_machine.set_physics_process(false)
	v.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	pause_members(b)
	pause_members(v)
	settle_fusion(v)
	game.Game_Settings.Training_Debug_Mode = true
	world.get_node("CombatThreatAnalyzer")._physics_process(0.1)
	var i:int = 0
	for member:Node2D in b.living_members():
		member.global_position = center+Vector2(-90+float(i%3)*24,-15+float(i/3)*34)
		i += 1
	for entry:Array in [["蝙蝠 5只",-80],["吸血鬼",48]]:
		var label := Label.new()
		label.text = entry[0]
		label.add_theme_font_size_override("font_size",10)
		label.position = center+Vector2(entry[1],48)
		world.add_child(label)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(4,4)
	camera.make_current()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	var rect := Rect2i(Vector2i(maxi(0,size.x/2-480),maxi(0,size.y/2-200)),Vector2i(mini(size.x,960),mini(size.y,400)))
	image.get_region(rect).save_png("res://tests/mc_bat_revision_preview.png")
	game.Game_Settings.Training_Debug_Mode = false
	world.get_node("CombatThreatAnalyzer")._physics_process(0.1)
	# Capture the actual game renderer at all native animation phases.
	for member:Node2D in b.living_members(): member.set_process(false)
	for frame:int in range(25):
		for member:Node2D in b.living_members():
			member.set("_animation_time",float(frame)/50.0)
			member.set("_animation_frame",-1)
			member.advance_native_animation(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().get_region(rect).save_png("res://tests/mc_bat_revision_%02d.png"%frame)
	print("BAT_PREVIEW_SAVED")
	finish(0)
