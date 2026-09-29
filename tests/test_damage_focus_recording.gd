extends "res://tests/test_damage_focus_zoom.gd"
## Real LIVE capture: both languages must inherit the exact combat push-in.

func record_hit(label:String,composition:int,target_health:int) -> void:
	var recorder:Node = world.control._battle_record_controls.recorder
	var target:Node2D = spawn_character(target_health,"B")
	target.set_meta("morph_display_name","下界合金剑")
	world.refresh_versus_text()
	check(recorder.set_composition(composition),label+": recording composition selected")
	check(recorder.start_live(),label+": actual bilingual LIVE recording starts")
	if recorder.is_idle():
		target.queue_free()
		return
	await create_timer(0.3,true,false,true).timeout
	var zh:SubViewport = recorder._sim_viewport
	var en:SubViewport = recorder._secondary._sim_viewport
	check(is_instance_valid(zh) and is_instance_valid(en),label+": both genuine output viewports are active")
	var source:RichTextLabel = world.versus_label
	var mirror:Node = recorder._locale_mirror
	var title_id:int = source.get_instance_id()
	check(source.is_visible_in_tree() and source.text.contains("VS") and mirror.copies.has(title_id),label+": source VS is mirrored to both recordings")
	var camera_before:float = world.camera_2d.zoom.x
	var zh_before:float = zh.canvas_transform.get_scale().x
	var en_before:float = en.canvas_transform.get_scale().x
	world._damage_focus_pending_strength = -1.0
	world._damage_focus_started_usec = 0
	world._damage_focus_next_usec = 0
	world._damage_focus_weight = 0.0
	world._damage_focus_peak_zoom = 1.0
	target.take_damage(100.0,true)
	var peak_camera:float = camera_before
	var peak_zh:float = zh_before
	var peak_en:float = en_before
	var saved:bool = false
	var titles_visible:bool = true
	for frame:int in range(35):
		await RenderingServer.frame_post_draw
		peak_camera = maxf(peak_camera,world.camera_2d.zoom.x)
		peak_zh = maxf(peak_zh,zh.canvas_transform.get_scale().x)
		peak_en = maxf(peak_en,en.canvas_transform.get_scale().x)
		if source.is_visible_in_tree() and mirror.copies.has(title_id):
			titles_visible = titles_visible and mirror.copies[title_id]["zh"].holder.is_visible_in_tree() and mirror.copies[title_id]["en"].holder.is_visible_in_tree()
		if not saved and peak_camera > camera_before * 1.07 and peak_zh > zh_before * 1.06 and peak_en > en_before * 1.06:
			zh.get_texture().get_image().save_png(EVIDENCE+label+"_zh.png")
			en.get_texture().get_image().save_png(EVIDENCE+label+"_en.png")
			saved = true
	print("DAMAGE_RECORD_FRAME ",label," camera=",camera_before," -> ",peak_camera,
		" zh=",zh_before," -> ",peak_zh," en=",en_before," -> ",peak_en)
	check(peak_camera > camera_before * 1.07,label+": live player camera zooms on confirmed damage")
	check(peak_zh > zh_before * 1.06 and peak_en > en_before * 1.06 and saved,
		label+": Chinese and English video frames both inherit the camera push-in")
	check(titles_visible,label+": both mirrored VS titles stay visible through the damage zoom")
	recorder.stop()
	var deadline:int = Time.get_ticks_msec() + 30000
	while recorder.is_busy() and Time.get_ticks_msec() < deadline:
		await create_timer(0.1,true,false,true).timeout
	var files_written:bool = recorder.last_outputs.size() == 2
	for path:String in recorder.last_outputs.values():
		files_written = files_written and FileAccess.file_exists(path)
	check(not recorder.is_busy() and files_written,label+": both actual MP4 files complete")
	if is_instance_valid(target) and not target.is_queued_for_deletion(): target.queue_free()
	await process_frame

func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): push_error("DAMAGE_RECORD_TIMEOUT");quit(2))
	game = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	root.size = Vector2i(540,960)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.hide()
	world.set_physics_process(false)
	var attacker:Node2D = spawn_character(200,"A")
	attacker.set_meta("morph_display_name","钻石剑")
	await create_timer(0.25,true,false,true).timeout
	var recorder:Node = world.control._battle_record_controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://damage_focus_record_test.cfg")
	recorder.preferences.directory = EVIDENCE
	recorder.preferences.tail_seconds = 60.0
	await record_hit("full_overkill_100_on_20",recorder.preferences.FULL,20)
	await record_hit("follow_100_on_200",recorder.preferences.FOLLOW,200)
	if is_instance_valid(attacker): attacker.queue_free()
	world.queue_free()
	await process_frame
	game.Game_Settings = old_settings
	print("DAMAGE_RECORD_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
