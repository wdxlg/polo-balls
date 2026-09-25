extends SceneTree
## D3D12 GPU readback of the original totem icon and native glitter particles
## in the genuine 2D battlefield; hiding FX provides the same-frame baseline.
var checks:int = 0
var failures:int = 0

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EVOKER_TOTEM_GPU_FAIL " + label)

func readback(fx:Node2D) -> Dictionary:
	await RenderingServer.frame_post_draw
	var shown:Image = root.get_texture().get_image()
	fx.hide()
	await RenderingServer.frame_post_draw
	var blank:Image = root.get_texture().get_image()
	fx.show()
	var origin:Vector2 = (root.get_final_transform()*fx.get_global_transform_with_canvas())*Vector2.ZERO
	var extent:int = 150
	var changed:int = 0
	var green:int = 0
	var yellow:int = 0
	for y:int in range(clampi(int(origin.y)-extent,0,shown.get_height()-1),clampi(int(origin.y)+extent,0,shown.get_height()-1)+1):
		for x:int in range(clampi(int(origin.x)-extent,0,shown.get_width()-1),clampi(int(origin.x)+extent,0,shown.get_width()-1)+1):
			var lit:Color = shown.get_pixel(x,y)
			var dark:Color = blank.get_pixel(x,y)
			if absf(lit.r-dark.r)+absf(lit.g-dark.g)+absf(lit.b-dark.b) < 0.12: continue
			changed += 1
			if lit.g > 0.28 and lit.g > lit.r*1.15 and lit.g > lit.b*1.3: green += 1
			if lit.r > 0.39 and lit.g > 0.30 and lit.b < 0.54: yellow += 1
	return {"changed":changed,"green":green,"yellow":yellow,"origin":origin,"shown":shown,"blank":blank}

func icon_pixels(frame:Dictionary, center:Vector2) -> int:
	var shown:Image = frame.shown
	var blank:Image = frame.blank
	var count:int = 0
	# Only the 20px item, not damage numbers or potion HUD near the Evoker.
	for y:int in range(clampi(int(center.y)-19,0,shown.get_height()-1),clampi(int(center.y)+19,0,shown.get_height()-1)+1):
		for x:int in range(clampi(int(center.x)-20,0,shown.get_width()-1),clampi(int(center.x)+20,0,shown.get_width()-1)+1):
			var a:Color = shown.get_pixel(x,y)
			var b:Color = blank.get_pixel(x,y)
			# The actual item's green/gold pixels; reject blue arena, red damage
			# numbers and animated potion HUD, which otherwise fake a GPU pass.
			var original_color:bool = (a.g > a.r*1.13 and a.g > a.b*1.1 and a.g > 0.25) or (a.r > 0.33 and a.g > 0.25 and a.b < a.g*0.8 and a.g > a.r*0.38)
			if original_color and absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.12: count += 1
	return count

func icon_center(fx:Node2D) -> Vector2:
	return (root.get_final_transform()*fx.totem_sprite.get_global_transform_with_canvas())*Vector2.ZERO

func save_crop(frame:Dictionary, center:Vector2, filename:String) -> Error:
	return (frame.shown as Image).get_region(Rect2i(Vector2i(int(center.x)-110,int(center.y)-110),Vector2i(220,220))).save_png("user://evoker_totem_visual/"+filename)

func run() -> void:
	create_timer(52.0,true,false,true).timeout.connect(func(): push_error("EVOKER_TOTEM_GPU_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	var original_stop:bool = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(540,960)
	var world:Node2D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node2D
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.set_process(false)
	world.control.get_parent().hide()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	var evoker:Node2D = (load("res://scenes/characters/我的世界/唤魔者.tscn") as PackedScene).instantiate() as Node2D
	evoker.Team = "Team0"
	evoker.position = center
	world.add_child(evoker,true)
	evoker.state_machine.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.set_process(false)
	world.camera_2d.set_physics_process(false)
	evoker.health = 0
	check(evoker.health == 50,"real scene revives with fifty health before the GPU capture")
	var all:Array[Node] = get_nodes_in_group("MCEvokerTotemFX")
	check(all.size() == 1,"real battlefield holds one detached totem effect")
	var fx:Node2D = all[0] as Node2D if all.size()==1 else null
	if fx != null:
		check(fx.totem_sprite.texture.resource_path.ends_with("totem_of_undying.png"),"drawn item uses Minecraft's original icon")
		check(fx.particles.size() == 88 and fx.particles[0].sprite.texture.resource_path.ends_with("glitter_7.png"),"drawn spark atlas uses Minecraft's original totem particle order")
		var start_scale:float = fx.totem_sprite.scale.x
		var start_y:float = fx.totem_sprite.position.y
		fx.advance_visual(0.07)
		check(fx.totem_sprite.scale.x > start_scale*1.5 and fx.totem_sprite.position.y < start_y-12.0 and fx.yaw_turns(fx.age) == 0.0,"icon first grows and flies out of the Evoker before turning")
		fx.advance_visual(fx.INTRO_SECONDS-fx.age)
		fx.set_process(false) # freeze each intentional phase for real GPU readbacks
		check(fx.totem_sprite.scale.x > start_scale and fx.totem_sprite.modulate.a > 0.8,"item reaches full size at the end of the launch")
		check(absf(fx.totem_sprite.scale.x) * fx.totem_sprite.texture.get_width() <= fx.ICON_WIDTH+0.01 and fx.ICON_WIDTH <= 24.0,"item stays near native character size instead of covering the battlefield")
		check(fx.totem_sprite.rotation == 0.0 and fx.totem_sprite.scale.x > 0.0,"item starts front-facing, with no in-plane spinning")
		await create_timer(0.15).timeout # allow newly loaded battlefield textures to appear before GPU sampling
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var complete:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_LIVE_GPU_METRIC ",complete)
		check(complete.changed > 160,"the item and sparks change actual battlefield pixels")
		# Icon alone and glitter alone must BOTH draw independently on a real GPU.
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		await RenderingServer.frame_post_draw
		var front_frame:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_ITEM_GPU_METRIC ",front_frame)
		check(front_frame.changed > 90,"original totem icon is visibly animated in the real view")
		var front_center:Vector2 = icon_center(fx)
		var front_count:int = icon_pixels(front_frame,front_center)
		fx.advance_visual(fx.INTRO_SECONDS+0.08-fx.age)
		for spark:Dictionary in fx.particles: spark.sprite.hide() # advance_visual re-enables glitter
		var edge_scale:float = fx.totem_sprite.scale.x
		var edge_center:Vector2 = icon_center(fx)
		var edge_frame:Dictionary = await readback(fx)
		var edge_count:int = icon_pixels(edge_frame,edge_center)
		fx.advance_visual(fx.INTRO_SECONDS+0.205-fx.age)
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		var back_scale:float = fx.totem_sprite.scale.x
		var back_center:Vector2 = icon_center(fx)
		var back_frame:Dictionary = await readback(fx)
		var back_count:int = icon_pixels(back_frame,back_center)
		print("EVOKER_TOTEM_YAW_GPU_METRIC front=",front_count," edge=",edge_count," back=",back_count," scales=",edge_scale,",",back_scale)
		check(absf(fx.totem_sprite.rotation) < 0.09 and edge_scale > 0.0 and back_scale < 0.0 and absf(edge_scale)*3.0 < absf(back_scale),"front/edge/mirrored-back turn remains pseudo-3D, with only a small wobble")
		check(front_count > 40 and edge_count < front_count*0.45 and back_count > edge_count*2.0,"actual green/gold icon pixels narrow to an edge and widen on the reverse face")
		var early_turns:float = fx.yaw_turns(fx.INTRO_SECONDS+0.13)-fx.yaw_turns(fx.INTRO_SECONDS+0.08)
		var late_turns:float = fx.yaw_turns(1.43)-fx.yaw_turns(1.38)
		print("EVOKER_TOTEM_SPIN_SPEED early_50ms=",early_turns," late_50ms=",late_turns," total_turns=",fx.yaw_turns(fx.LIFETIME))
		check(early_turns > late_turns*2.0 and late_turns > 0.015 and fx.yaw_turns(fx.LIFETIME) > 1.4,"front/back spin starts fast, slows down but never stops before fadeout")
		check(absf(fx.totem_sprite.rotation) > 0.025 and absf(fx.totem_sprite.position.x) > 0.1,"launch transitions into a visible bob and small side-to-side wobble")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://evoker_totem_visual"))
		check(save_crop(front_frame,front_center,"yaw_front.png") == OK and save_crop(edge_frame,edge_center,"yaw_edge.png") == OK and save_crop(back_frame,back_center,"yaw_back.png") == OK,"three genuine battlefield yaw phases are available for inspection")
		var previous_anchor:Vector2 = fx.global_position
		evoker.global_position += Vector2(36.0,16.0) # stay inside Map10x10 while measuring follow
		fx.set_process(true)
		await RenderingServer.frame_post_draw # process_frame fires before Node._process
		fx.set_process(false)
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		var followed_center:Vector2 = icon_center(fx)
		var followed_frame:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_FOLLOW_GPU_METRIC anchor=",previous_anchor," fx=",fx.global_position," owner=",evoker.global_position," centers=",back_center," -> ",followed_center," pixels=",icon_pixels(followed_frame,followed_center)," scale=",fx.totem_sprite.scale)
		check(fx.global_position.distance_to(evoker.global_position) < 0.1 and fx.global_position.distance_to(previous_anchor) > 30.0,"detached effect follows the real living evoker without snapping to spawn")
		check(followed_center.distance_to(back_center) > 20.0 and icon_pixels(followed_frame,followed_center) > 25,"followed original icon actually moves with evoker in GPU battlefield pixels")
		check(save_crop(followed_frame,followed_center,"yaw_follow.png") == OK,"followed battlefield frame is available for visual inspection")
		fx.advance_visual(0.0)
		fx.totem_sprite.hide()
		await RenderingServer.frame_post_draw
		var spark_pixels:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_PARTICLE_GPU_METRIC ",spark_pixels)
		check(spark_pixels.changed > 12 and spark_pixels.green > 5 and spark_pixels.yellow > 5,"original native particles render green and golden sparks, not a fake placeholder")
		fx.totem_sprite.show()
		fx.advance_visual(1.16-fx.age)
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		var late_x:float = fx.totem_sprite.scale.x
		var late_center:Vector2 = icon_center(fx)
		var late_frame:Dictionary = await readback(fx)
		fx.advance_visual(1.30-fx.age)
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		var later_center:Vector2 = icon_center(fx)
		var later_frame:Dictionary = await readback(fx)
		check(absf(fx.totem_sprite.scale.x-late_x) > 0.12 and fx.totem_sprite.modulate.a > 0.3 and icon_pixels(late_frame,late_center) > 12 and icon_pixels(later_frame,later_center) > 12,"original totem still visibly changes its front/back angle on GPU near fadeout")
		fx.set_process(true)
	evoker.free()
	game.now_stop_state = true
	# Real elapsed game time, not a fixed number of render frames (D3D12 can
	# exceed 120 FPS and 140 frames may be shorter than the 1.55 s FX).
	await create_timer(1.9).timeout
	check(not is_instance_valid(fx),"totem visual fades and frees after its owner is removed")
	if is_instance_valid(world._mc_prewarmer):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int = ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(path))
	world.queue_free()
	await process_frame
	game.Game_Settings = original
	game.now_stop_state = original_stop
	print("EVOKER_TOTEM_GPU_RESULT checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)
