extends SceneTree
## Real 1080x1920/60fps bilingual encoding, with a stale prior victory and live armor combat.
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",text)
func wall_msec() -> int:
	return int(Time.call("get_wall_ticks_msec")) if Time.has_method("get_wall_ticks_msec") else Time.get_ticks_msec()
func run() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2 or DisplayServer.get_name()=="headless": quit(2); return
	var output_root:String = args[0].path_join("e2e-"+args[1])
	DirAccess.make_dir_recursive_absolute(output_root)
	var simulated:bool = args[1]=="sim"
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Minecraft_Clouds = false
	game.now_stop_state = true
	root.size = Vector2i(540,960)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.team.hide()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	world.create_char("Team0","烈焰人",center+Vector2(-28,0))
	world.create_char("Team1","木剑",center+Vector2(28,0))
	await process_frame
	var role:Node
	var old_enemy:Node
	for actor:Node in world._battle_units_cache:
		if actor.Team=="Team0": role=actor
		if actor.Team=="Team1": old_enemy=actor
	check(is_instance_valid(role) and is_instance_valid(old_enemy),"real role and previous opponent exist")
	if not is_instance_valid(role) or not is_instance_valid(old_enemy): quit(2); return
	old_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	old_enemy.health = 0
	world._update_manual_victory_bell()
	check(world._victory_bell_played,"prior battle really settled before adding the armor opponent")
	world.create_char("Team1","不死盔甲架",center+Vector2(28,0))
	await process_frame
	world.refresh_versus_text()
	check(world._collect_alive_victory_sides().size()==2 and world._victory_bell_played,"live opposing armor battle coexists with the old bell")
	var recorder:Node = world.control._battle_record_controls.recorder
	var prefs:RefCounted = recorder.PreferencesScript.new("user://armor_recording_e2e_owned.cfg")
	prefs.directory = output_root
	prefs.tail_seconds = 1.5
	recorder.preferences = prefs
	if not simulated:
		game.now_stop_state = false
		game.stop_background.hide()
		game.stop_text.hide()
		if game.Stop_Override_Tween: game.Stop_Override_Tween.kill()
	var started:bool = recorder.start_simulated() if simulated else recorder.start_live()
	check(started,"start actual "+args[1]+" dual-language encoders: "+recorder.get_last_error())
	var deadline:int = wall_msec()+95000
	var ended_at_frame:int = -1
	var running_at_seven_seconds:bool = false
	var live_combat_at_end:bool = false
	var no_vs_while_alive:bool = false
	while recorder.is_recording() and wall_msec()<deadline:
		await process_frame
		if recorder._game_time>=7.25 and ended_at_frame<0:
			running_at_seven_seconds = true
			live_combat_at_end = world._collect_alive_victory_sides().size()==2 and is_instance_valid(role) and role.health>0
			no_vs_while_alive = not world.versus_label.visible and world.armor_intro_label.visible
			ended_at_frame = recorder._frame_index
			print("ARMOR_E2E_END_INJECTION mode=",args[1]," game_time=",recorder._game_time," frames=",ended_at_frame," sides=",world._collect_alive_victory_sides().size())
			# Actual damage/health/death path: no synthetic recording-finish flag.
			if is_instance_valid(role): role.take_damage(1000000.0,true)
	check(running_at_seven_seconds and live_combat_at_end,"still recording an actual contested armor fight after seven seconds")
	check(no_vs_while_alive,"recording retains the introduction without a VS title")
	check(not recorder.is_recording(),"actual role defeat plus configured tail automatically stops recording")
	if recorder.is_recording(): recorder.stop()
	while recorder.is_busy() and wall_msec()<deadline:
		await process_frame
	check(not recorder.is_busy(),"both encoders and audio mux finish before watchdog")
	check(recorder._frame_index-ended_at_frame>=88 if ended_at_frame>=0 else false,"true end retains at least 88 frames of the 1.5-second tail")
	check(recorder.get_last_error().is_empty(),"no encoder/readback/timing error: "+recorder.get_last_error())
	check(recorder.last_outputs.size()==2,"both real movies were saved")
	if recorder.last_outputs.size()==2:
		var zh:String = str(recorder.last_outputs.zh)
		var en:String = str(recorder.last_outputs.en)
		check(zh.get_base_dir().get_file().begins_with("烈焰人") and zh.get_file() == "中文.mp4","Chinese movie sits in a folder named after the new character")
		check(en.get_base_dir() == zh.get_base_dir() and en.get_file() == "English.mp4","English movie shares the folder under a fixed short name")
		check(recorder.last_folder == zh.get_base_dir() and recorder.last_covers.size() == 4,"Chinese/English 9:16 and 16:9 covers are written too: %s" % [recorder.last_covers])
		for cover:String in recorder.last_covers.values():
			check(cover.get_base_dir() == zh.get_base_dir() and Image.load_from_file(cover) != null,"cover is a readable image in the recording folder: " + cover)
		check(FileAccess.file_exists(zh) and FileAccess.file_exists(en),"both output paths exist on disk")
	var result:Dictionary = {"mode":args[1],"checks":checks,"failures":failures,"frames":recorder._frame_index,"end_frame":ended_at_frame,"duration_from_frames":float(recorder._frame_index)/60.0,"outputs":recorder.last_outputs.duplicate(),"error":recorder.get_last_error()}
	var file:FileAccess = FileAccess.open(args[0].path_join("e2e-"+args[1]+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	if recorder.is_busy(): quit(2); return
	await create_timer(0.5,true,false,true).timeout
	if not OS.get_environment("RECORDING_UI_EVIDENCE_DIR").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("RECORDING_UI_EVIDENCE_DIR").path_join("recorded_result_"+args[1]+".png"))
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("ARMOR_RECORD_E2E ",JSON.stringify(result))
	quit(0 if failures==0 else 1)
