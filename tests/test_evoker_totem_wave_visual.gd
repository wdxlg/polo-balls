extends "res://tests/test_evoker_totem_visual.gd"
var capture:SubViewport
func ring_frame(wave:Node2D) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shown:Image = capture.get_texture().get_image()
	wave.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var blank:Image = capture.get_texture().get_image()
	wave.show()
	var center:Vector2 = capture.canvas_transform*wave.global_position
	var maximum:float = 0.0
	var peak:float = 0.0
	var changed:int = 0
	var gold:int = 0
	var green:int = 0
	for y:int in range(maxi(0,int(center.y)-240),mini(shown.get_height(),int(center.y)+241)):
		for x:int in range(maxi(0,int(center.x)-240),mini(shown.get_width(),int(center.x)-12)):
			if Vector2(x,y).distance_to(center)<24.0: continue
			var a:Color = shown.get_pixel(x,y)
			var b:Color = blank.get_pixel(x,y)
			# Ignore the separate potion HUD and non-ring damage-text animation.
			if a.g<=b.g+0.01 or a.r<=b.r+0.01: continue
			var difference:float = absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			if difference<0.055: continue
			changed += 1
			maximum = maxf(maximum,Vector2(x,y).distance_to(center))
			peak = maxf(peak,difference)
			if a.r>b.r+0.03 and a.g>b.g+0.03 and a.r>a.b: gold += 1
			if a.g>b.g+0.01 and a.g-b.g>(a.r-b.r)*0.5: green += 1
	return {"image":shown,"center":center,"radius":maximum,"peak":peak,"changed":changed,"gold":gold,"green":green}
func run() -> void:
	create_timer(80,true,false,true).timeout.connect(func():push_error("TOTEM_WAVE_GPU_TIMEOUT");quit(2))
	var game:Node = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	var original_stop:bool = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.Game_Settings.High_Damage_Feedback = false
	game.Game_Settings.Minecraft_Clouds = false
	var was_processing:bool = game.is_processing()
	game.set_process(false)
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(720,720)
	var world:Node2D = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.set_process(false)
	world.control.get_parent().hide()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.camera_2d.global_position = center
	world.camera_2d.zoom = Vector2(1.3,1.3)
	world.camera_2d.force_update_scroll()
	capture = SubViewport.new()
	capture.size = Vector2i(512,512)
	capture.world_2d = world.get_world_2d()
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	capture.canvas_transform = Transform2D(0.0,Vector2(256,256)-center)
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.set_process(false)
	world.camera_2d.set_physics_process(false)
	var caster:Node2D = load("res://scenes/characters/我的世界/唤魔者.tscn").instantiate()
	caster.Team = "Team0"
	caster.Can_Attack = false
	caster.Can_Skill = false
	world.add_child(caster,true)
	caster.global_position = center
	caster.state_machine.set_physics_process(false)
	caster.set_physics_process(false)
	caster.health = 0
	var wave:Node2D = caster._totem_wave
	wave.set_physics_process(false)
	check(caster.health==50 and wave!=null,"real GPU battle triggers revival and wave together")
	for fx:Node in get_nodes_in_group("MCEvokerTotemFX"): fx.set_process(false)
	await create_timer(0.2).timeout
	DirAccess.make_dir_recursive_absolute("user://evoker_totem_wave")
	var frames:Array[Dictionary] = []
	for age:float in [0.15,0.32,0.54]:
		game.now_stop_state = false
		wave.advance(age-wave.age)
		game.now_stop_state = true
		paused = true
		var frame:Dictionary = await ring_frame(wave)
		paused = false
		frames.append(frame)
		var crop:Rect2i = Rect2i(Vector2i(frame.center)-Vector2i(235,235),Vector2i(470,470)).intersection(Rect2i(Vector2i.ZERO,frame.image.get_size()))
		check(frame.image.get_region(crop).save_png("user://evoker_totem_wave/phase_"+str(frames.size())+".png")==OK,"GPU phase capture "+str(age))
		check(absf(frame.radius-wave.radius)<7.0,"GPU radius matches physical front at "+str(age))
		check(frame.changed>80,"real ring pixels visible at phase "+str(age))
		print("TOTEM_RING_GPU age=",age," radius=",frame.radius," peak=",frame.peak," pixels=",frame.changed," gold=",frame.gold," green=",frame.green)
	check(frames[0].radius<frames[1].radius and frames[1].radius<frames[2].radius,"actual GPU ring expands at all three sampled ages")
	check(frames[0].peak>frames[1].peak and frames[1].peak>frames[2].peak,"actual GPU ring fades monotonically")
	check(frames[0].gold>40 and frames[0].green>40,"native gold and green are both visible, not a generic white circle")
	var origin:Vector2 = wave.global_position
	caster.global_position += Vector2(30,15)
	check(wave.global_position==origin,"wave does not follow caster between GPU phases")
	game.now_stop_state = false
	wave.advance(0.07)
	await process_frame
	check(not is_instance_valid(wave),"final transparent phase cleans in real battle")
	# Actual live physics, not just inspecting a controller's fields.
	var second:Node2D = load("res://scenes/characters/我的世界/唤魔者.tscn").instantiate()
	second.Team = "Team0"
	second.Speed = 0
	second.Can_Attack = false
	second.Can_Skill = false
	world.add_child(second,true)
	second.global_position = center+Vector2(0,300)
	second.state_machine.set_physics_process(false)
	var enemy:Node2D = load("res://scenes/ball.tscn").instantiate()
	enemy.Team = "Team1"
	enemy.Max_health = 500
	enemy.Speed = 0
	enemy.Can_Attack = false
	enemy.Can_Skill = false
	enemy.Has_Collision_Damage = false
	enemy.Health_Restore = 0
	world.add_child(enemy,true)
	enemy.global_position = second.global_position+Vector2(90,0)
	var start:Vector2 = enemy.global_position
	second.health = 0
	await create_timer(1.0).timeout
	check(enemy.health==492,"unmodified physics ticks deliver exactly eight damage")
	check(enemy.global_position.x-start.x>45 and enemy.global_position.x-start.x<70 and absf(enemy.global_position.y-start.y)<3,"real victim moves outward about sixty units without added stun")
	check(not is_instance_valid(second._totem_wave),"automatic physics wave lifetime is bounded")
	if is_instance_valid(world._mc_prewarmer):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int = ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(str(path))
	capture.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	game.set_process(was_processing)
	game.Game_Settings = original
	game.now_stop_state = original_stop
	print("TOTEM_WAVE_GPU_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
