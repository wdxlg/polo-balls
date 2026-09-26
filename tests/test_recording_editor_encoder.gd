extends Node
## Real editor/F6 harness. An owned, temporary one-shot recorder hook invokes run().
## options: root (evidence folder), output_root (isolated movie folder), label, armor.
## This fixture changes preferences only in memory; use the paired evidence helper.
var _trace_path:String
var failures:Array[String]=[]
func run(recorder:Node, options:Dictionary) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var root:Window=get_tree().root
	await get_tree().create_timer(3.0,true,false,true).timeout
	var args:PackedStringArray = [str(options.root),str(options.label),"150"]
	_trace_path=args[0].path_join(args[1]+".log")
	var armor:bool=bool(options.get("armor",false))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	var saved_frame_cap:int = Engine.max_fps
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Creating = false
	game.Game_Settings.Map_Background = "summit"
	game.now_stop_state = true
	root.size = Vector2i(540,960)
	var world:Node = get_tree().current_scene
	if bool(options.get("skip_prewarmer", false)) and is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.team.hide()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	await world.create_char("Team0","烈焰人",center+Vector2(-28,0))
	await world.create_char("Team1","不死盔甲架" if armor else "监守者",center+Vector2(28,0))
	await get_tree().create_timer(0.5,true,false,true).timeout
	var start_delay:float = float(options.get("start_delay", 0.0))
	if start_delay>0.0: await get_tree().create_timer(start_delay,true,false,true).timeout
	var pref:RefCounted = recorder.PreferencesScript.new("user://live_stop_probe_owned.cfg")
	pref.directory = str(options.output_root).path_join(args[1])
	pref.tail_seconds = float(options.get("tail_seconds", 100.0))
	recorder.preferences = pref
	game.now_stop_state = false
	game.stop_background.hide()
	game.stop_text.hide()
	if game.Stop_Override_Tween: game.Stop_Override_Tween.kill()
	OS.set_environment("BATTLE_RECORD_PROFILE","1")
	if int(options.get("frame_cap",0))>0: Engine.max_fps=int(options.frame_cap)
	var recording_entry_cap:int = Engine.max_fps
	if bool(options.get("mouse_click", false)):
		await get_tree().create_timer(2.0,true,false,true).timeout
	var start:int = Time.get_ticks_msec()
	if bool(options.get("mouse_click", false)):
		root.grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		var button:Button = world.control._battle_record_controls.button
		# Include viewport stretch/letterboxing; the external editor embed's
		# screen transform alone omits it. Controller adds native client origin.
		var point:Vector2 = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
		var click:FileAccess = FileAccess.open(args[0].path_join(args[1]+".click.json"),FileAccess.WRITE)
		click.store_string(JSON.stringify({"pid":OS.get_process_id(),"x":point.x,"y":point.y,"button_pos":str(button.global_position),"button_size":str(button.size),"window_pos":str(root.position),"window_size":str(root.size),"focused":root.has_focus()}))
		click.close()
		var click_deadline:int = Time.get_ticks_msec()+20000
		while not recorder.is_recording() and Time.get_ticks_msec()<click_deadline:
			await get_tree().process_frame
			point = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
			var click_path:String = args[0].path_join(args[1]+".click.json")
			click = FileAccess.open(click_path+".tmp",FileAccess.WRITE)
			click.store_string(JSON.stringify({"pid":OS.get_process_id(),"x":point.x,"y":point.y,"hovered":root.gui_get_hovered_control()==button,"focused":root.has_focus()}))
			click.close()
			DirAccess.rename_absolute(click_path+".tmp",click_path)
	else:
		world.control._battle_record_controls.button.button_up.emit()
	var ok:bool = recorder.is_recording()
	_check(ok,"real toolbar left-button release starts LIVE")
	_trace(str("LIVE_STOP_START ok=",ok," engine=",Engine.get_version_info()," renderer=",RenderingServer.get_current_rendering_method()," driver=",RenderingServer.get_current_rendering_driver_name()," tail=",recorder._tail_seconds," fps_cap=",Engine.max_fps," focused=",root.has_focus()," mouse_click=",options.get("mouse_click",false)))
	var limit:float = float(args[2]) if args.size()>2 else 20.0
	var last_log:float = -1.0
	var natural_stop:bool = false
	var end_frame:int=-1
	var tail_start:int=-1
	var peak:int=0
	var paused_once:bool=false
	while recorder.is_recording() and Time.get_ticks_msec()-start<limit*1000.0:
		await get_tree().process_frame
		if recorder._game_time>=7.25 and end_frame<0:
			_check(world._collect_alive_victory_sides().size()==2,"real opposing sides still active before test defeat")
			end_frame=recorder._frame_index
			for actor:Node in world._battle_units_cache:
				if is_instance_valid(actor) and actor.Team=="Team0" and actor.health>0: actor.take_damage(1000000.0,true)
		if recorder.get_tail_left()>=0.0 and tail_start<0: tail_start=recorder._frame_index
		if recorder.get_tail_left()>0.0 and recorder.get_tail_left()<pref.tail_seconds-minf(5.0,pref.tail_seconds*0.5) and not paused_once:
			paused_once=true
			game.now_stop_state=true
			var frame_before:int=recorder._frame_index
			var tail_before:float=recorder.get_tail_left()
			await get_tree().create_timer(0.5,true,false,true).timeout
			_check(frame_before==recorder._frame_index and tail_before==recorder.get_tail_left(),"pause excludes frames and tail time")
			game.now_stop_state=false
		var elapsed:float = float(Time.get_ticks_msec()-start)/1000.0
		if elapsed-last_log>(0.1 if elapsed<4.0 else 1.0):
			last_log=elapsed
			var writers:Array = []
			for output:Node in [recorder,recorder._secondary]:
				if is_instance_valid(output) and output._writer!=null:
					peak=maxi(peak,output._writer.peak_bytes)
					writers.append({"written":output._writer.frames_written,"bytes":output._writer._bytes,"frames":output._writer._frames,"peak":output._writer.peak_bytes})
			_trace(str("LIVE_STOP_SAMPLE wall=",elapsed," game=",recorder._game_time," frames=",recorder._frame_index," bell=",world._victory_bell_played," tail=",recorder.get_tail_left()," pending=",recorder._live_pending.size()," codec=",recorder._video_codec," fps=",Engine.get_frames_per_second()," writer=",writers))
	natural_stop = not recorder.is_recording()
	if recorder.is_recording(): recorder.stop()
	var finish_deadline:int = Time.get_ticks_msec()+45000
	while recorder.is_busy() and Time.get_ticks_msec()<finish_deadline: await get_tree().process_frame
	_trace(str("LIVE_STOP_RESULT early=",natural_stop," frames=",recorder._frame_index," game=",recorder._game_time," tail=",recorder.get_tail_left()," error=",recorder.get_last_error()," outputs=",recorder.last_outputs))
	_check(ok and end_frame>=435 and natural_stop and not recorder.is_busy(),"actual end and full tail finish automatically")
	_check(tail_start>=0 and recorder._frame_index-tail_start>=int(pref.tail_seconds*60.0)-2,str(pref.tail_seconds," seconds of tail retained"))
	_check(recorder.get_last_error().is_empty(),"no encoder/timing error")
	_check(recorder.last_outputs.size()==2,"both languages saved")
	_check(peak<recorder.WriterScript.MAX_BYTES,"unchanged bounded queue")
	_check(paused_once,"pause/resume exercised")
	_check(Engine.max_fps==recording_entry_cap,"recording completion restores the original render policy")
	_check(recorder._game_time>0.0 and recorder._physics_clock/recorder._game_time>=0.9,"real physics progress keeps pace with recorded game time")
	var result:Dictionary={"failures":failures,"tail_start_frame":tail_start,"end_frame":end_frame,"peak_bytes":peak,"early":natural_stop,"frames":recorder._frame_index,"game":recorder._game_time,"tail":recorder.get_tail_left(),"error":recorder.get_last_error(),"outputs":recorder.last_outputs}
	result["physics_time"]=recorder._physics_clock
	result["restored_frame_cap"]=Engine.max_fps
	var f:FileAccess = FileAccess.open(args[0].path_join(args[1]+".json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"));f.close()
	if recorder.is_busy(): get_tree().quit(2); return
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	game.Game_Settings=saved
	game.now_stop_state=saved_stop
	Engine.max_fps=saved_frame_cap
	get_tree().quit(0 if failures.is_empty() else 1)

func _trace(message:String) -> void:
	var path:String=_trace_path
	var f:FileAccess=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(message)
	f.close()

func _check(ok:bool,message:String) -> void:
	_trace(("PASS: " if ok else "FAIL: ")+message)
	if not ok: failures.append(message)
