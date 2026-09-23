extends "res://tests/test_battle_recording.gd"
# GPU / real character / actual right-click simulation: both language videos.
func run() -> void:
	create_timer(100.0,true,false,true).timeout.connect(func():print("BOW_RECORD_TIMEOUT");quit(2))
	game = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	root.size = Vector2i(540,960)
	world.control.hide()
	await settle(0.45)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position=center
	camera.make_current()
	var bow:Node2D = load("res://scenes/characters/我的世界/天堂陨落长弓.tscn").instantiate()
	bow.Team = "Team0"
	bow.Can_Attack=false
	bow.Can_Skill=false
	bow.Health_Restore=0
	bow.position=center + Vector2(-90,-25)
	world.add_child(bow,true)
	var enemy:Node2D = load("res://scenes/ball.tscn").instantiate()
	enemy.Team="Team1"
	enemy.Can_Attack=false
	enemy.Can_Skill=false
	enemy.Health_Restore=0
	enemy.position=center + Vector2(145,-25)
	world.add_child(enemy,true)
	enemy.Max_health=10000
	enemy.default_properties.Max_health=10000
	enemy.health=10000
	enemy.Has_Collision_Damage=false
	enemy.self_hitbox.monitoring=false
	bow.state_machine.set_physics_process(false)
	enemy.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	bow.facing=Vector2.RIGHT
	bow.visual_mob()
	game.now_stop_state=false
	paused=false
	game.stop_background.hide()
	game.stop_text.hide()
	game.speed_text.hide()
	game.speed_slider.hide()
	world.control.hide()
	bow._fire()
	print("BOW_RECORD fired before capture")
	bow.spawn_heaven_rift(center+Vector2(30,30),Vector2.RIGHT)
	await settle(0.18)
	check(bow._rifts.size() > 0,"real bow has opened a fracture before right-click recording")
	controls=world.control._battle_record_controls
	recorder=controls.recorder
	recorder.preferences=recorder.PreferencesScript.new("user://bow_record_e2e.cfg")
	recorder.preferences.directory="user://recordings/bow_record_e2e"
	check(recorder.start_simulated(),"real longbow battle begins right-click offline recording")
	if failures: quit(1);return
	var initial:int=int(Time.call("get_wall_ticks_usec"))
	var seen:Dictionary={}
	while recorder._frame_index < 150 and recorder.mode == recorder.Mode.SIM and int(Time.call("get_wall_ticks_usec"))-initial < 65000000:
		await process_frame
		if recorder._frame_index in [30,60,90,120,150] and not seen.has(recorder._frame_index):
			seen[recorder._frame_index]=true
			if recorder._frame_index == 30:
				check(bow._rifts.size() >= 2,"real arrow opens a second fracture during offline simulation")
				var frame:Image = recorder._grab_image()
				var rift:Variant=bow._rifts[0].get_ref()
				if is_instance_valid(rift):
					var p:Vector2i=Vector2i(recorder._sim_viewport.canvas_transform * rift._points[0])
					var sky:Color=frame.get_pixelv(p + Vector2i(0,65))
					var fracture_pixels:int=0
					for y:int in range(p.y-52,p.y+53):
						for x:int in range(p.x-52,p.x+53):
							var c:Color=frame.get_pixel(x,y)
							if c.b < sky.b - 0.18 and c.g < sky.g - 0.12:fracture_pixels+=1
					print("BOW_RECORD fracture_pixels=",fracture_pixels," sky=",sky)
					check(fracture_pixels > 20,"real longbow fracture is visible in the offline video source")
			print("BOW_RECORD frame=",recorder._frame_index," active_rifts=",bow._rifts.size()," rain=",get_nodes_in_group("HeavenfallRainCrack").size()," pierce=",get_nodes_in_group("HeavenfallPierceTear").size())
	check(recorder._frame_index>=150,"simulated 150 real frames, no frame skips")
	print("BOW_RECORD samples: initial=",initial," last=",int(Time.call("get_wall_ticks_usec"))," frames=",recorder._frame_index," path=",recorder._out_path," en_path=",recorder._secondary._out_path)
	var english_path:String=recorder._secondary._out_path
	recorder.stop()
	await wait_idle()
	check(FileAccess.file_exists(recorder._out_path) and FileAccess.file_exists(english_path),"both language MP4 files are saved")
	print("BOW_RECORD_RESULT %d/%d" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
