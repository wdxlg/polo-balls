extends SceneTree
## Real Evoker, real Absorption II/status/audio/health-bar scene, plus GPU readback.
var checks:int = 0
var failures:int = 0

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ABSORPTION_GOLD_FAIL "+label)

func screen_rect(item:Control) -> Rect2:
	var transform:Transform2D = root.get_final_transform()*item.get_global_transform_with_canvas()
	return Rect2(transform*Vector2.ZERO,transform*item.size-transform*Vector2.ZERO).abs()

func gold_pixels(shown:Image,rect:Rect2) -> Dictionary:
	var count:int = 0
	var min_y:int = shown.get_height()
	var max_y:int = -1
	var outside:int = 0
	for y:int in range(clampi(int(rect.position.y)-4,0,shown.get_height()-1),clampi(int(rect.end.y)+4,0,shown.get_height()-1)+1):
		for x:int in range(clampi(int(rect.position.x)-4,0,shown.get_width()-1),clampi(int(rect.end.x)+4,0,shown.get_width()-1)+1):
			var a:Color = shown.get_pixel(x,y)
			# The bright-gold material is distinguishable from blue background,
			# red damage numbers and the dark character image without a frame race.
			if a.r > 0.62 and a.g > 0.47 and a.b < 0.36 and a.r > a.g*1.04 and a.g > a.b*1.6:
				if not rect.has_point(Vector2(x+0.5,y+0.5)):
					outside += 1
					continue
				count += 1
				min_y = mini(min_y,y)
				max_y = maxi(max_y,y)
	return {"count":count,"top":min_y,"bottom":max_y,"outside":outside}

func capture_image() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	create_timer(48.0,true,false,true).timeout.connect(func(): push_error("ABSORPTION_GOLD_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
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
	evoker.Can_Attack = false
	evoker.health_bar.suppress_floating_text = true # fixture resizing is not a real hit
	evoker.Max_health = 100
	evoker.health = 100
	evoker.health_bar.suppress_floating_text = false
	evoker.state_machine.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.set_process(false)
	world.camera_2d.set_physics_process(false)
	var effects:GDScript = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	check(bool(effects.apply_effect(evoker,"absorption",2,20.0,evoker)),"real Absorption II installs")
	var status:Node = evoker.get_node_or_null("MinecraftStatus_absorption")
	check(status != null and is_equal_approx(float(status.absorption_remaining),40.0),"40 temporary HP are real")
	status.set_physics_process(false) # deterministic visual snapshots, not a timer test
	var bar:Node = evoker.health_bar
	var gold:TextureProgressBar = bar._absorption_bar
	check(gold != null and gold.visible and gold.fill_mode == TextureProgressBar.FILL_TOP_TO_BOTTOM,"gold fills existing bar from TOP to bottom")
	check(gold.get_parent() == bar.health_bar.get_parent() and gold.position == bar.health_bar.position and gold.size == bar.health_bar.size and gold.scale == bar.health_bar.scale,"gold never becomes an extra or oversized health bar")
	check(is_equal_approx(gold.value,0.4) and gold.get_index() < bar.label.get_index(),"40 of 100 HP draw inside original health silhouette below numbers")
	await create_timer(0.15).timeout
	var rect:Rect2 = screen_rect(gold)
	var full:Image = await capture_image()
	var full_pixels:Dictionary = gold_pixels(full,rect)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://absorption_gold"))
	full.get_region(Rect2i(Vector2i(int(rect.get_center().x)-95,int(rect.get_center().y)-95),Vector2i(190,190))).save_png("user://absorption_gold/full.png")
	var sound:AudioStreamPlayer = root.get_node("Audios").get_node_or_null("Sfx/BlockAtk1") as AudioStreamPlayer
	check(sound != null and sound.stream != null,"shared block sound is a real loaded audio stream")
	if sound != null: sound.stop()
	var hp_events:Array[Vector2i] = []
	bar.health_changed.connect(func(before:int,after:int,_max:int,_tween:bool): hp_events.append(Vector2i(before,after)))
	evoker.take_damage(20.0,true)
	check(evoker.health == 100 and is_equal_approx(float(status.absorption_remaining),20.0) and hp_events.is_empty(),"pure absorption does not touch red HP or emit health-change feedback")
	check(sound != null and sound.playing,"absorption hit uses the existing block-hit audio")
	check(is_equal_approx(gold.value,0.2) and gold.visible,"20 remaining absorption HP stay anchored at top")
	var half:Image = await capture_image()
	var half_pixels:Dictionary = gold_pixels(half,rect)
	half.get_region(Rect2i(Vector2i(int(rect.get_center().x)-95,int(rect.get_center().y)-95),Vector2i(190,190))).save_png("user://absorption_gold/half.png")
	print("ABSORPTION_GOLD_GPU_METRIC rect=",rect," full=",full_pixels," half=",half_pixels)
	check(full_pixels.count > 70 and half_pixels.count > 30 and half_pixels.count < full_pixels.count*0.8 and absi(full_pixels.top-half_pixels.top) <= 2 and full_pixels.bottom-half_pixels.bottom > 3 and full_pixels.outside == 0 and half_pixels.outside == 0,"real GPU gold stays INSIDE bar, anchored at top and retracts from bottom when hit")
	evoker.receive_spatial_raw_health_damage(5.0,{"point":center,"shape":"all"})
	check(evoker.health == 100 and is_equal_approx(float(status.absorption_remaining),15.0) and hp_events.is_empty(),"raw spatial absorption is also block-like without a red health hit")
	check(evoker.receive_positional_damage(5.0,center,true) and evoker.health == 100 and is_equal_approx(float(status.absorption_remaining),10.0),"ordinary spatial hits count as accepted even when all damage is absorbed")
	evoker.take_damage(15.0,true)
	check(evoker.health == 95 and is_equal_approx(float(status.absorption_remaining),0.0) and not gold.visible,"overflow only removes 5 true HP and hides the consumed gold")
	check(hp_events.size() == 1 and hp_events[0] == Vector2i(100,95),"only overflow creates a real health-bar change")
	effects.clear(evoker,"absorption",evoker)
	await process_frame
	check(not gold.visible,"expired or removed Absorption clears its gold overlay")
	if is_instance_valid(world._mc_prewarmer):
		for path:Variant in world._mc_prewarmer._paths.values():
			var state:int = ResourceLoader.load_threaded_get_status(str(path))
			if state in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(str(path))
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("ABSORPTION_GOLD_RESULT checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)
