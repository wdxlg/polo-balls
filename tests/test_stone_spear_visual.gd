extends SceneTree
var arena:Node2D
var units:Array[Node2D]=[]
var checks:int=0
var failures:int=0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var game:Node=root.get_node("Game")
	game.now_stop_state=false
	root.size=Vector2i(1080,720)
	root.content_scale_size=Vector2i(1080,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	RenderingServer.set_default_clear_color(Color("192124"))
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	var camera:=Camera2D.new()
	camera.zoom=Vector2(3,3)
	arena.add_child(camera)
	var packed:PackedScene=load("res://scenes/characters/我的世界/石矛.tscn")
	for i:int in range(3):
		var unit:Node2D=packed.instantiate()
		unit.position=Vector2((i-1)*110,0)
		arena.add_child(unit)
		unit.state_machine.set_physics_process(false)
		unit.formation=i
		unit._facing=0.0
		unit._orbit=0.0
		unit._transition_left=0.0
		unit.direction=Vector2.ZERO
		unit._switch_wait=100.0
		unit._stab_wait=100.0
		unit._last_body_position=unit.global_position
		if i==2:
			unit._stab_time=unit.stab_out_time
			unit._stab_distance=unit.stab_reach(102.0)
			unit._main_shift=unit._stab_distance
			for j:int in range(4): unit._stab_axes[j]=float(j)*PI*0.5-PI*0.5
		for j:int in range(4):
			var pose:Dictionary=unit.formation_pose(j,102.0)
			unit._centers[j]=unit.global_position+pose.offset
			unit._angles[j]=pose.angle
		unit._apply_pose()
		unit.get_node("Health_Bar").hide()
		units.append(unit)
	var layer:=CanvasLayer.new()
	arena.add_child(layer)
	for i:int in range(3):
		var label:=Label.new()
		label.text=["FOLLOW / FOUR SPEARS","ORBIT / TANGENTIAL","THRUST / OUTWARD ONLY"][i]
		label.position=Vector2(32+i*350,105)
		label.add_theme_font_size_override("font_size",20)
		label.modulate=Color("dce9cb")
		layer.add_child(label)
	var footer:=Label.new()
	footer.text="STONE SPEAR  |  Native game render  |  Four copies at 78% opacity"
	footer.position=Vector2(32,650)
	footer.add_theme_font_size_override("font_size",22)
	layer.add_child(footer)
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/previews")
	check(image.save_png("res://tests/previews/stone_spear_formations.png")==OK,"actual GPU screenshot saved")
	check(image.get_width()==1080 and image.get_height()==720,"real viewport dimensions")
	for unit:Node2D in units:
		for sprite:Sprite2D in unit._copies:
			var p:Vector2=sprite.get_global_transform_with_canvas()*Vector2(-10,-10)
			var color:Color=image.get_pixelv(Vector2i(p))
			check(Vector3(color.r-0.098,color.g-0.129,color.b-0.141).length()>0.03,"native copy contributes visible pixels")
	# Live production orbit is advanced by real simulation, then pause must freeze it.
	var orbit:Node2D=units[1]
	var previous:float=orbit._orbit
	for frame:int in range(30):
		await physics_frame
		orbit.tick_physics(orbit.State.Stand,1.0/60.0)
	check(orbit._orbit>previous,"real simulation advances orbit while stationary")
	previous=orbit._orbit
	game.now_stop_state=true
	orbit.tick_physics(orbit.State.Stand,1.0)
	check(is_equal_approx(orbit._orbit,previous),"pause freezes visible orbit")
	game.now_stop_state=false
	# Real PCM capture uses the existing game recording bus.
	var bus:int=AudioServer.get_bus_index("GameplayRecord")
	check(bus>=0,"game recording audio bus exists")
	if bus>=0:
		var capture:=AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus,capture)
		orbit._emit_audio(true,orbit.global_position,80.0)
		await create_timer(0.4).timeout
		var pcm:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
		var peak:float=0.0
		for sample:Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		check(peak>0.00001,"original hit sound produces real nonzero GameplayRecord PCM")
		AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	print("STONE_VISUAL_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
