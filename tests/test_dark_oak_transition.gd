extends SceneTree
const TRANSITION = preload("res://scripts/ui/dark_oak_transition.gd")
const OUTPUT:String = "E:/godot/polo-balls-checkpoints/dark_oak_fast_20260927/"
var checks:int = 0
var failures:int = 0
var midpoint_calls:int = 0
var underneath_clicks:int = 0
var overlay:Node
var marker:CanvasLayer
var marker_button:Button
var frame_paths:Array[String] = []
var motion_play_ms:int = 0
var motion_covered_ms:int = 0
var motion_opening_ms:int = 0
var motion_done_ms:int = 0
var frame_times:Array[int] = []
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(count:int=3) -> void:
	for i:int in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
func image() -> Image:
	var im:Image=root.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: im.linear_to_srgb()
	return im
func click(at:Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed:bool in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=at;e.pressed=pressed;root.push_input(e,true)
func wait_finished() -> void:
	while overlay.is_busy(): await frames(1)
func on_covered() -> void:
	motion_covered_ms=Time.get_ticks_msec()
	check(overlay.progress==1.0,"covered signal only after full closure")
	image().save_png(OUTPUT+"closed.png")
func swap_color() -> void:
	midpoint_calls+=1
	check(overlay.phase==overlay.Phase.COVERED and overlay.progress==1.0,"change callable runs only behind fully closed doors")
	marker_button.modulate=Color(0.1,1.0,0.2)
func delayed_change() -> void:
	midpoint_calls+=1
	await create_timer(0.15,true,false,true).timeout
	check(overlay.phase==overlay.Phase.COVERED and overlay.progress==1.0,"asynchronous change keeps doors closed until ready")
func replace_scene() -> void:
	midpoint_calls+=1
	check(change_scene_to_file("res://scenes/world.tscn")==OK,"actual scene replacement requested behind closed doors")
func run() -> void:
	create_timer(150,true,false,true).timeout.connect(func():quit(2))
	var game:Node=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	var locale:String=game.current_locale
	var original_scale:float=Engine.time_scale
	AudioServer.set_bus_mute(0,true)
	game.Game_Settings.Map_Background="blue"
	game.Game_Settings.Only_In_Game_Translation=false
	game.set_language("zh",false)
	var world:Node=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	await frames(8)
	world.control.ui_parallax_enabled=false
	world.control.game_setting.show()
	world.control._show_settings_category("parameters")
	await frames(5)
	var button:Button=world.control.find_child("TestDarkOakTransition",true,false)
	check(button!=null and button.is_visible_in_tree(),"test button visible in Settings > Parameters")
	check(button.text=="测试双门转场","Chinese settings label")
	check(button.get_parent()==world.control.settings_category_boxes["parameters"],"button belongs to parameters, not battle settings persistence")
	game.set_language("en",false)
	await frames(3)
	check(button.text=="Test door transition","English label follows UI locale")
	game.Game_Settings.Only_In_Game_Translation=true
	await frames(2)
	check(button.text=="测试双门转场","only-in-game translation keeps UI Chinese")
	game.Game_Settings.Only_In_Game_Translation=false
	game.set_language("zh",false)
	await frames(3)
	image().save_png(OUTPUT+"settings.png")
	var before:Dictionary=game.Game_Settings.duplicate(true)
	overlay=TRANSITION.ensure(self)
	check(overlay.rig.leaves.size()==4 and overlay.viewport_3d.own_world_3d,"real 3D door world has four upper/lower mesh instances")
	check(overlay.rig.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"doors use actual perspective projection")
	check(is_equal_approx(overlay.rig.hinges[0].rotation.y,-PI*0.5) and is_equal_approx(overlay.rig.hinges[1].rotation.y,PI*0.5),"initial doors are open by exactly 90 degrees at opposite hinges")
	check(is_equal_approx(overlay.rig.thickness/overlay.rig.half_width,3.0/16.0),"door thickness follows original Minecraft model")
	var anchors:Array[Vector3]=[overlay.rig.hinges[0].position,overlay.rig.hinges[1].position]
	var stable_hinges:bool=true
	var initial_builds:int=overlay.rig.build_count
	var middle_saved:bool=false
	var saw_entry:bool=false
	var saw_exit:bool=false
	var previous_carriage:float=overlay.rig.carriages[0].position.x
	var recording:=AudioEffectRecord.new()
	recording.format=AudioStreamWAV.FORMAT_16_BITS
	var ui_bus:int=AudioServer.get_bus_index("UI")
	var effect_index:int=AudioServer.get_bus_effect_count(ui_bus)
	AudioServer.add_bus_effect(ui_bus,recording)
	recording.set_recording_active(true)
	var audio_start:int=Time.get_ticks_msec()
	paused=true
	Engine.time_scale=0.0
	motion_play_ms=Time.get_ticks_msec()
	click(button.get_global_rect().get_center())
	await frames(1)
	overlay=root.get_node_or_null("DarkOakDoorTransition")
	check(overlay!=null and overlay.is_busy(),"real GUI mouse press starts transition while paused and time_scale zero")
	if overlay==null:
		Engine.time_scale=original_scale;paused=false;quit(1);return
	overlay.covered.connect(on_covered)
	check(button.disabled,"test button is disabled while animation runs")
	check(not overlay.play(swap_color),"overlapping/repeated requests are rejected")
	check(overlay.layer==4096,"reserved layer above HUD, draft UI and embedded windows")
	check(overlay.get_parent()==root,"transition owned by root, not disposable current scene")
	check(TRANSITION.ensure(self)==overlay,"single reusable overlay per root")
	while overlay.is_busy():
		await frames(1)
		motion_done_ms=Time.get_ticks_msec() if overlay.is_busy() else motion_done_ms
		if overlay.rig.hinges[0].position!=anchors[0] or overlay.rig.hinges[1].position!=anchors[1]:stable_hinges=false
		var carriage_x:float=overlay.rig.carriages[0].position.x
		if overlay.phase==overlay.Phase.CLOSING and carriage_x>previous_carriage+0.00001:saw_entry=true
		if overlay.phase==overlay.Phase.OPENING:
			if motion_opening_ms==0:motion_opening_ms=Time.get_ticks_msec()
			if carriage_x<previous_carriage-0.00001:saw_exit=true
		previous_carriage=carriage_x
		if not middle_saved and overlay.progress>0.45 and overlay.progress<0.70:
			image().save_png(OUTPUT+"hinged_half.png");middle_saved=true
		var im:Image=image();im.resize(540,960,Image.INTERPOLATE_NEAREST)
		var path:String=OUTPUT+"frame_%03d.png" % frame_paths.size()
		im.save_png(path);frame_paths.append(path);frame_times.append(Time.get_ticks_msec())
	await create_timer(0.35,true,false,true).timeout
	recording.set_recording_active(false)
	var wave:AudioStreamWAV=recording.get_recording()
	wave.save_to_wav(OUTPUT+"door_ui_capture.wav")
	var pcm:PackedByteArray=wave.data
	var peak:int=0
	for i:int in range(0,pcm.size()-1,2):peak=maxi(peak,absi(pcm.decode_s16(i)))
	check(peak>100,"actual original door audio produces nonzero UI-bus PCM while paused at zero game speed")
	print("DOOR_AUDIO_PCM bytes=",pcm.size()," peak=",peak," sample_rate=",wave.mix_rate)
	AudioServer.remove_bus_effect(ui_bus,effect_index)
	check(overlay.audio_events==["close","open"],"one original close sound at closure and one open sound at opening")
	check(overlay.open_audio.bus==&"UI" and overlay.close_audio.bus==&"UI","native door sounds use existing UI audio service, not paused gameplay bus")
	check(stable_hinges and overlay.rig.build_count==initial_builds,"local door hinges stay attached to moving carriages; animation never rebuilds geometry")
	check(saw_entry and saw_exit,"carriages move inward during closing and outward during opening")
	check(is_equal_approx(overlay.rig.carriages[0].position.x,-overlay.rig.outward_travel),"completed animation reaches fully offscreen carriage before hiding")
	check(middle_saved,"actual intermediate 3D rotation frame captured")
	check(is_equal_approx(overlay.rig.hinges[0].rotation.y,-PI*0.5),"finished door returns to fully open 90-degree pose")
	check(overlay.viewport_3d.render_target_update_mode==SubViewport.UPDATE_DISABLED,"idle transition stops 3D rendering")
	await frames(2)
	check(not overlay.visible and not overlay.is_processing_input(),"idle overlay is invisible and no longer consumes input")
	check(not button.disabled,"button reenabled after opening")
	check(paused and Engine.time_scale==0.0,"transition preserves existing pause and zero time scale")
	check(game.Game_Settings==before and current_scene==world,"test preview does not alter battle, map or saved settings")
	check(midpoint_calls==0,"rejected callback was not run")
	FileAccess.open(OUTPUT+"frames.json",FileAccess.WRITE).store_string(JSON.stringify({"paths":frame_paths,"times_ms":frame_times,"audio_start_ms":audio_start}))
	image().save_png(OUTPUT+"after.png")
	var cold_close_ms:int=motion_covered_ms-motion_play_ms
	var cold_open_ms:int=motion_done_ms-motion_opening_ms
	print("DOOR_MOTION_MS cold_close=",cold_close_ms," cold_open=",cold_open_ms)
	check(overlay.close_seconds==0.275 and overlay.open_seconds==0.30,"service exposes the doubled motion timings")
	# The first transition also pays one-off 3D viewport/shader setup, so measure a warm run.
	overlay.close_seconds=0.275;overlay.open_seconds=0.30;overlay.hold_seconds=0.20
	motion_play_ms=Time.get_ticks_msec();motion_covered_ms=0;motion_opening_ms=0;motion_done_ms=0
	check(overlay.play(),"warm timing run starts with the doubled motion")
	while overlay.is_busy():
		await frames(1)
		if overlay.phase==overlay.Phase.OPENING and motion_opening_ms==0:motion_opening_ms=Time.get_ticks_msec()
	motion_done_ms=Time.get_ticks_msec()
	var close_ms:int=motion_covered_ms-motion_play_ms
	var open_ms:int=motion_done_ms-motion_opening_ms
	print("DOOR_MOTION_MS warm_close=",close_ms," warm_open=",open_ms)
	check(close_ms>=200 and close_ms<=420,"default closing motion is about twice the old speed: "+str(close_ms)+" ms")
	check(open_ms>=220 and open_ms<=480,"default opening motion is about twice the old speed: "+str(open_ms)+" ms")
	check(close_ms+open_ms<850,"combined closing and opening motion stays under 850 ms")
	await validate_travel_endpoints()
	# Place a deliberately very high opaque UI over the game, still below the doors.
	marker=CanvasLayer.new();marker.layer=4000;root.add_child(marker)
	marker_button=Button.new();marker_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pink:=StyleBoxFlat.new();pink.bg_color=Color(1,0,1)
	for state:String in ["normal","hover","pressed","focus"]:marker_button.add_theme_stylebox_override(state,pink)
	marker.add_child(marker_button);marker_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker_button.pressed.connect(func():underneath_clicks+=1)
	marker.process_mode=Node.PROCESS_MODE_ALWAYS
	await frames(2)
	click(Vector2(100,100));await frames(1)
	check(underneath_clicks==1,"underlying high UI receives clicks when idle")
	overlay.close_seconds=0.08;overlay.open_seconds=0.08;overlay.hold_seconds=0.06
	check(overlay.play(swap_color),"reusable transition accepts a change callback")
	click(Vector2(100,100))
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true)
	await overlay.covered
	check(underneath_clicks==1 and paused,"active shield blocks underlying clicks and Esc")
	var covered_image:Image=image()
	var wrong:int=0
	for y:int in range(1,20):
		for x:int in range(1,12):
			var c:Color=covered_image.get_pixel(int(float(x)*covered_image.get_width()/12.0),int(float(y)*covered_image.get_height()/20.0))
			if c.r>0.8 and c.b>0.8 and c.g<0.2:wrong+=1
	check(wrong==0,"closed doors cover even layer-4000 magenta UI across 209 GPU samples")
	await wait_finished()
	check(midpoint_calls==1 and overlay.change_applied,"covered change applied exactly once before opening")
	check(marker_button.modulate.g==1.0 and not overlay.visible,"opening reveals changed underlying content")
	check(overlay.rig.materials[1].albedo_texture==TRANSITION.TOP and overlay.rig.materials[0].albedo_texture==TRANSITION.BOTTOM,"3D faces use original top and bottom textures")
	check(overlay.rig.leaves[0].get_aabb().size.z>0 and overlay.rig.leaves[2].get_aabb().size.z>0,"both leaves have real front, back and thickness faces")
	check(overlay.rig.materials[0].texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,"3D pixel texture uses nearest sampling")
	Engine.time_scale=2.0
	await frames(3)
	check(is_equal_approx(overlay.open_audio.pitch_scale*AudioServer.playback_speed_scale,1.0),"existing Audios service keeps UI door pitch at 1x during doubled gameplay speed")
	Engine.time_scale=0.0
	check(overlay.play(delayed_change),"asynchronous callback supported")
	await wait_finished()
	check(midpoint_calls==2,"async callback runs once")
	check(overlay.play(swap_color),"start cancel-before-close case")
	overlay.cancel()
	await frames(5)
	check(not overlay.is_busy() and midpoint_calls==2,"cancellation releases overlay and prevents pending change")
	check(overlay.play(),"preview can restart after cancellation")
	await wait_finished()
	# Odd logical dimensions and live resize while closed: no central or horizontal crack.
	var old_size:Vector2i=root.content_scale_size
	root.content_scale_size=Vector2i(541,963)
	overlay.hold_seconds=0.12
	overlay.play()
	await overlay.covered
	await frames(1)
	var rig:Node3D=overlay.rig
	var left:Vector2=rig.camera.unproject_position(rig.hinges[0].to_global(Vector3(rig.half_width+0.002,0,0)))
	var right:Vector2=rig.camera.unproject_position(rig.hinges[1].to_global(Vector3(-rig.half_width-0.002,0,0)))
	check(left.x>=right.x and is_zero_approx(rig.hinges[0].rotation.y),"closed 3D inner edges overlap at odd viewport width without centre seam")
	check(rig.camera.unproject_position(Vector3(0,1.004,0)).y<=0 and rig.camera.unproject_position(Vector3(0,-1.004,0)).y>=overlay.viewport_3d.size.y,"3D doors cover full top/bottom viewport extents")
	root.content_scale_size=Vector2i(1280,720)
	await frames(2)
	check(overlay.shield.size==root.get_visible_rect().size,"landscape resize follows full viewport, independent of game camera")
	await wait_finished()
	root.content_scale_size=old_size
	await frames(2)
	marker.queue_free();await frames(1)
	# World._ready owns its startup pause/speed policy. Compare against native reload,
	# rather than incorrectly requiring a new World to inherit the old paused zero speed.
	check(change_scene_to_file("res://scenes/world.tscn")==OK,"native scene reload baseline")
	await frames(6)
	var baseline_paused:bool=paused
	var baseline_scale:float=Engine.time_scale
	print("NATIVE_WORLD_STARTUP paused=",baseline_paused," scale=",baseline_scale)
	paused=true;Engine.time_scale=0.0
	var old_world_id:int=current_scene.get_instance_id()
	check(overlay.play(replace_scene),"scene transition started")
	await wait_finished()
	await frames(3)
	check(current_scene!=null and current_scene.get_instance_id()!=old_world_id,"new actual World scene revealed after transition")
	check(root.get_node("DarkOakDoorTransition")==overlay and not overlay.is_busy(),"root overlay survives old scene teardown and completes")
	check(paused==baseline_paused and is_equal_approx(Engine.time_scale,baseline_scale),"door transition preserves native new-scene startup policy")
	Engine.time_scale=original_scale;paused=false
	game.Game_Settings=saved;game.set_language(locale,false)
	current_scene.queue_free();overlay.queue_free()
	await process_frame
	print("DARK_OAK_TRANSITION_RESULT checks=",checks," failures=",failures," captured_frames=",frame_paths.size())
	quit(0 if failures==0 else 1)

func validate_travel_endpoints() -> void:
	# Keep the overlay visibly enabled: prove absence comes from geometry, not hide().
	overlay.visible=true
	overlay.viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var rig:Node3D=overlay.rig
	for size:Vector2i in [Vector2i(540,960),Vector2i(541,963),Vector2i(1280,720),Vector2i(2400,400)]:
		overlay.viewport_3d.size=size
		rig.configure(Vector2(size))
		rig.set_progress(0.0)
		await frames(2)
		var outside:bool=true
		for i:int in range(rig.leaves.size()):
			var leaf:MeshInstance3D=rig.leaves[i]
			for corner:int in range(8):
				var screen:Vector2=rig.camera.unproject_position(leaf.to_global(leaf.get_aabb().get_endpoint(corner)))
				if (i<2 and screen.x>=-1.0) or (i>=2 and screen.x<=size.x+1.0):outside=false
		check(outside,"all thick-door vertices fully offscreen at 90 degrees: "+str(size))
		check(visible_door_pixels()==0,"GPU endpoint has zero visible hinge/door pixels while overlay enabled: "+str(size))
		var builds:int=rig.build_count
		rig.set_progress(0.5)
		await frames(2)
		check(visible_door_pixels()>0 and is_equal_approx(rig.hinges[0].rotation.y,-PI/4.0) and is_equal_approx(rig.carriages[0].position.x,-rig.outward_travel*0.5),"halfway pose combines visible rotation and carriage travel: "+str(size))
		rig.set_progress(1.0)
		await frames(2)
		check(rig.carriages[0].position==Vector3.ZERO and rig.carriages[1].position==Vector3.ZERO and visible_door_pixels()==size.x*size.y,"fully closed carriage settles at zero and GPU covers every pixel: "+str(size))
		rig.set_progress(0.0)
		await frames(2)
		check(visible_door_pixels()==0 and rig.build_count==builds,"opening ends fully offscreen without hiding or rebuilding: "+str(size))
	overlay.visible=false
	overlay.viewport_3d.render_target_update_mode=SubViewport.UPDATE_DISABLED
	overlay._layout()

func visible_door_pixels() -> int:
	var im:Image=overlay.viewport_3d.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	var pixels:PackedByteArray=im.get_data()
	var count:int=0
	for i:int in range(3,pixels.size(),4):
		if pixels[i]>0:count+=1
	return count
