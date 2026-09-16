extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	change_scene_to_file("res://scenes/world.tscn")
	await scene_changed
	var world:Node = current_scene
	var warmer:Node = world._mc_prewarmer
	world.now_choose_char = "骷髅"
	var checks:int = 0
	var t:int = Time.get_ticks_usec()
	world.create_ghost_ball()
	world.create_char("Team0","骷髅",Vector2(200,200))
	print("WORLD_PENDING_CLICK_MS=",(Time.get_ticks_usec()-t)/1000.0)
	world.reset()
	while warmer.finished.size()+warmer.failed.size()<warmer.CHARACTERS.size(): await process_frame
	assert(world._mc_pending_placements.is_empty() and world._battle_setup.is_empty())
	checks += 1
	assert(warmer.failed.is_empty())
	checks += 1
	var index:int = 0
	for character:String in warmer.CHARACTERS:
		t = Time.get_ticks_usec()
		world.create_char("Team0",character,Vector2(120+index*105,280))
		index += 1
		var placed:int = Time.get_ticks_usec()
		await process_frame
		await process_frame
		print("WORLD_FIRST ",character," create_ms=",(placed-t)/1000.0," two_frames_ms=",(Time.get_ticks_usec()-placed)/1000.0)
	for unit:Node in get_nodes_in_group("Ball"):
		if not unit.has_method("is_combat_runtime_active") or not is_instance_valid(unit.health_bar): continue
		unit.state_machine.set_physics_process(false)
		var number:Label = unit.health_bar.label
		# 数字会按血条宽度自动缩小（三位数以上），但不会超过 900 的基准字号；白描边加粗到 190。
		assert(number.get_theme_font_size("font_size") <= 900 and number.get_theme_font_size("font_size") > 0)
		assert(number.get_theme_constant("outline_size") == 190)
		assert(number.get_theme_font("font").multichannel_signed_distance_field)
		checks += 3
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scripts/training/mc_native_assets/mc_first_spawn_world.png")
	print("WORLD_PREWARM_CHECKS=",checks," failures=0")
	world.queue_free()
	await process_frame
	await process_frame
	quit()
