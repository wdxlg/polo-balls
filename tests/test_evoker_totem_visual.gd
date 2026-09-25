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
	return {"changed":changed,"green":green,"yellow":yellow,"origin":origin}

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
		fx.advance_visual(0.22)
		fx.set_process(false) # freeze this exact original art frame for two readbacks
		check(fx.totem_sprite.scale.x > start_scale and fx.totem_sprite.modulate.a > 0.8,"icon really pops larger rather than remaining a still image")
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var complete:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_LIVE_GPU_METRIC ",complete)
		check(complete.changed > 160,"the item and sparks change actual battlefield pixels")
		# Icon alone and glitter alone must BOTH draw independently on a real GPU.
		for spark:Dictionary in fx.particles: spark.sprite.hide()
		await RenderingServer.frame_post_draw
		var icon_pixels:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_ITEM_GPU_METRIC ",icon_pixels)
		check(icon_pixels.changed > 90,"original totem icon is visibly animated in the real view")
		fx.advance_visual(0.0)
		fx.totem_sprite.hide()
		await RenderingServer.frame_post_draw
		var spark_pixels:Dictionary = await readback(fx)
		print("EVOKER_TOTEM_PARTICLE_GPU_METRIC ",spark_pixels)
		check(spark_pixels.changed > 12 and spark_pixels.green > 5 and spark_pixels.yellow > 5,"original native particles render green and golden sparks, not a fake placeholder")
		fx.totem_sprite.show()
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
