extends "res://tests/test_rabbit_birth_feedback.gd"

const OUTPUT:String = "user://rabbit_birth_feedback/"

func run() -> void:
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Shaking_Camera = true
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(720,960)
	var w:Node2D = load("res://scenes/world.tscn").instantiate()
	w.tree_entered.connect(func(): current_scene = w,CONNECT_ONE_SHOT)
	root.add_child(w)
	if is_instance_valid(w._mc_prewarmer): w._mc_prewarmer.free()
	w.control.team.hide()
	w.control.hide()
	w.set_physics_process(false)
	var center:Vector2 = w.return_map_world_rect(w._current_map_node()).get_center()
	var parent:Node2D = spawn(w,center+Vector2(-18,0))
	var partner:Node2D = spawn(w,center+Vector2(18,0))
	for i:int in range(25): await process_frame
	check(w.is_combat_runtime_active() and w._impact_is_on_screen(center),"GPU fixture uses active real World and visible parents")
	check(w.damage_focus_enabled and w.impact_visuals_enabled,"GPU fixture leaves camera focus and hit particles enabled")
	var base_zoom:Vector2 = w.camera_2d.zoom
	var base_position:Vector2 = w.camera_2d.global_position
	var max_zoom_delta:float = 0.0
	var max_position_delta:float = 0.0
	var max_focus_weight:float = 0.0
	var max_particles:int = 0
	var new_babies:int = 0
	var events:Array[Dictionary] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	node_added.connect(observe_added)
	clear_feedback(w)
	for frame:int in range(90):
		if frame == 12 or frame == 48:
			parent._spawn_baby_with(partner)
			new_babies += 1
			for actor:Node in get_nodes_in_group("Ball"): freeze(actor)
		await RenderingServer.frame_post_draw
		max_zoom_delta = maxf(max_zoom_delta,w.camera_2d.zoom.distance_to(base_zoom))
		max_position_delta = maxf(max_position_delta,w.camera_2d.global_position.distance_to(base_position))
		max_focus_weight = maxf(max_focus_weight,w._damage_focus_weight)
		max_particles = maxi(max_particles,particles(w))
		events.append({"frame":frame,"zoom":[w.camera_2d.zoom.x,w.camera_2d.zoom.y],"camera":[w.camera_2d.global_position.x,w.camera_2d.global_position.y],"focus":w._damage_focus_weight,"particles":particles(w)})
		if frame in [0,13,25,49,65,89]:
			root.get_texture().get_image().save_png(OUTPUT+"frame_%03d.png"%frame)
	check(new_babies == 2 and get_nodes_in_group("Ball").size() == 4,"GPU renders two breeding events and two real newborns")
	check(health_losses.is_empty(),"GPU repeated breeding has no synthetic health loss")
	check(max_zoom_delta < 0.00001,"GPU real camera zoom unchanged across all 90 frames")
	check(max_position_delta < 0.00001,"GPU real camera position unchanged across all 90 frames")
	check(max_focus_weight == 0.0,"GPU has no damage-focus animation during breeding")
	check(max_particles == 0,"GPU has no critical particles during either birth")
	var result:Dictionary = {"frames":90,"births":new_babies,"max_zoom_delta":max_zoom_delta,"max_camera_position_delta":max_position_delta,"max_damage_focus_weight":max_focus_weight,"max_critical_particles":max_particles,"health_losses":health_losses,"frame_data":events}
	var file:FileAccess = FileAccess.open(OUTPUT+"render_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	node_added.disconnect(observe_added)
	game.Game_Settings = saved
	w.queue_free()
	await process_frame
	print("RABBIT_BIRTH_RENDER: %d checks / %d failures"%[checks,failures])
	quit(1 if failures > 0 else 0)
