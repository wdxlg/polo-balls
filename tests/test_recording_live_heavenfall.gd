extends "res://tests/test_battle_recording.gd"
# Real GPU/encoder wall-time witness: longbow visual overload vs left-click recording.
var physics_ticks:int=0
var draw_ticks:int=0
func _on_draw() -> void: draw_ticks += 1
func _on_physics() -> void: physics_ticks += 1
func elapsed(start:int) -> float: return float(int(Time.call("get_wall_ticks_usec"))-start) / 1000000.0
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():print("LIVE_BOW_TIMEOUT");quit(2))
	game=root.get_node("Game")
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Training_Boss_Intro=false
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	root.size=Vector2i(1080,1920) if OS.get_environment("BOW_PROBE_SIZE") == "full" else Vector2i(540,960)
	await settle(0.6)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	var center:Vector2=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.position=center
	camera.make_current()
	var bow:Node2D=load("res://scenes/characters/我的世界/天堂陨落长弓.tscn").instantiate()
	bow.Team="Team0"
	bow.Can_Attack=false
	bow.Can_Skill=false
	bow.Health_Restore=0
	bow.position=center+Vector2(-90,-25)
	world.add_child(bow,true)
	var enemy:Node2D=load("res://scenes/ball.tscn").instantiate()
	enemy.Team="Team1"
	enemy.Can_Attack=false
	enemy.Can_Skill=false
	enemy.Health_Restore=0
	enemy.position=center+Vector2(145,-25)
	world.add_child(enemy,true)
	enemy.Max_health=100000
	enemy.default_properties.Max_health=100000
	enemy.health=100000
	enemy.Has_Collision_Damage=false
	enemy.self_hitbox.monitoring=false
	bow.state_machine.set_physics_process(false)
	enemy.state_machine.set_physics_process(false)
	controls=world.control._battle_record_controls
	recorder=controls.recorder
	recorder.preferences=recorder.PreferencesScript.new("user://live_bow_probe.cfg")
	recorder.preferences.directory="user://recordings/live_bow_probe"
	game.now_stop_state=false
	paused=false
	game.stop_background.hide()
	game.stop_text.hide()
	game.speed_text.hide()
	game.speed_slider.hide()
	world.control.hide()
	await physics_frame
	physics_frame.connect(_on_physics)
	RenderingServer.frame_post_draw.connect(_on_draw)
	var origin:int=int(Time.call("get_wall_ticks_usec"))
	var old:int=physics_ticks
	var old_draw:int=draw_ticks
	var next_shot:float=0.0
	while elapsed(origin)<3.0:
		await process_frame
		if elapsed(origin)>float(next_shot):
			bow.facing=Vector2.RIGHT
			bow._fire()
			next_shot+=1.0 if OS.get_environment("BOW_PROBE_STRESS") == "1" else 2.15
	var normal_rate:float=float(physics_ticks-old)/elapsed(origin)
	print("LIVE_BOW_NORMAL physics_fps=%.2f ticks=%d seconds=%.2f rifts=%d draw_fps=%.2f" % [normal_rate,physics_ticks-old,elapsed(origin),bow._rifts.size(),float(draw_ticks-old_draw)/elapsed(origin)])
	check(recorder.start_live(),"live begins with active longbow battle")
	origin=int(Time.call("get_wall_ticks_usec"))
	old=physics_ticks
	old_draw=draw_ticks
	next_shot=0
	var previous_second:int=-1
	var peak_rifts:int=0
	var peak_rain:int=0
	while elapsed(origin)<8.0 and recorder.mode==recorder.Mode.LIVE:
		await process_frame
		if elapsed(origin)>float(next_shot):
			bow.facing=Vector2.RIGHT
			bow._fire()
			next_shot+=1.0 if OS.get_environment("BOW_PROBE_STRESS") == "1" else 2.15
		var second:int=int(elapsed(origin))
		if second!=previous_second:
			peak_rifts=maxi(peak_rifts,bow._rifts.size())
			peak_rain=maxi(peak_rain,get_nodes_in_group("HeavenfallRainCrack").size())
			previous_second=second
			print("LIVE_BOW_PROGRESS t=",second," frames=",recorder._frame_index," ticks=",physics_ticks-old," rifts=",bow._rifts.size()," rain=",get_nodes_in_group("HeavenfallRainCrack").size()," queue_zh=",recorder._writer.peak_bytes if recorder._writer != null else 0," queue_en=",recorder._secondary._writer.peak_bytes if recorder._secondary != null and recorder._secondary._writer != null else 0)
	var rate:float=float(physics_ticks-old)/maxf(elapsed(origin),0.0001)
	check(recorder.mode==recorder.Mode.LIVE and recorder.get_last_error().is_empty(),"longbow effects do not abort LIVE capture")
	check(rate>54.0,"left-click recording sustains at least 90% of real-time physical simulation")
	check(peak_rifts>=3 and peak_rain>=2,"longbow rifts and rain actually overlap during LIVE capture")
	check(recorder._writer!=null and recorder._secondary!=null and recorder._secondary._writer!=null and recorder._writer.peak_bytes<recorder._writer.MAX_BYTES and recorder._secondary._writer.peak_bytes<recorder._secondary._writer.MAX_BYTES,"both encoder queues stay below their byte limits")
	check(recorder._frame_index>=475 and recorder._frame_index<=485,"eight seconds of 60fps frames are produced without cutting the battle")
	print("LIVE_BOW_RECORD physics_fps=%.2f seconds=%.2f frames=%d mode=%d error=%s queue_zh=%d queue_en=%d draw_fps=%.2f" % [rate,elapsed(origin),recorder._frame_index,recorder.mode,recorder.get_last_error(),recorder._writer.peak_bytes if recorder._writer != null else 0,recorder._secondary._writer.peak_bytes if recorder._secondary != null and recorder._secondary._writer != null else 0,float(draw_ticks-old_draw)/elapsed(origin)])
	var zh_writer:RefCounted=recorder._writer
	var en_writer:RefCounted=recorder._secondary._writer if recorder._secondary!=null else null
	if recorder.mode==recorder.Mode.LIVE:recorder.stop()
	await wait_idle()
	check(recorder.last_outputs.size()==2 and FileAccess.file_exists(recorder.last_outputs.zh) and FileAccess.file_exists(recorder.last_outputs.en),"both language MP4s are finalized")
	check(zh_writer!=null and en_writer!=null and zh_writer.frames_written==recorder._frame_index and en_writer.frames_written==recorder._frame_index,"encoder writes every accepted frame in both languages")
	print("LIVE_HEAVENFALL_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
