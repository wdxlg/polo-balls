extends "res://tests/test_drowned_trident_aim_stick.gd"
# 临时探针：检查附魔流光遮罩的裁切参数与绘制。
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(120.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.6).timeout
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1); return
	arena = world.return_map_world_rect(world.map_group["Map50x50"])
	center = arena.get_center()
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn", center+Vector2(-260,0))
	var target:Node2D = dummy(center+Vector2(40,80))
	await process_frame
	await process_frame
	drowned.mc_native_animation.set_process(false)
	drowned.set_physics_process(false)
	drowned.set_process(false)
	drowned.state_machine.set_physics_process(false)
	drowned._trident.set_physics_process(true)
	drowned._trident.set_process(true)
	check(drowned.throw_trident(target), "probe throw")
	drowned._advance_trident_throw(drowned.trident_throw_windup*0.55)
	target.global_position = center+Vector2(300,300)
	drowned._advance_trident_throw(drowned.trident_throw_windup+0.001)
	var spear:Node = drowned._trident
	var guard:int = 0
	while spear.flight_state==1 and guard<900:
		guard += 1
		await physics_frame
	spear.advance(drowned.stuck_enchant_delay+0.05)
	var cv:Node = spear.charge_visual
	cv.set_process(false)
	cv.advance(0.0)
	var ov:Sprite2D = cv.overlay
	var gm:ShaderMaterial = cv.glint_material
	print("PROBE cv.visible=",cv.visible," overlay.visible=",ov.visible," overlay.texture=",ov.texture)
	print("PROBE overlay.scale=",ov.scale," overlay.global_transform=",ov.global_transform)
	print("PROBE spear.transform=",spear.global_transform," spear.scale=",spear.scale," DRAW_SIZE=",spear.DRAW_SIZE)
	print("PROBE material_is_glint=",ov.material==gm," shader=",gm.shader.resource_path if gm.shader else "null")
	for key in ["plant_clip","plant_clip_y","plant_clip_origin","plant_clip_du","plant_clip_dv","world_texel"]:
		print("   param ",key,"=",gm.get_shader_parameter(key))
	print("PROBE clip_y from spear=",spear.plant_clip_y()," contact=",spear.plant_contact_point()," node=",spear.global_position)
	# 用 shader 的公式反推：节点中心对应的 UV 处应落在何处
	var origin:Vector2 = gm.get_shader_parameter("plant_clip_origin")
	var du:Vector2 = gm.get_shader_parameter("plant_clip_du")
	var dv:Vector2 = gm.get_shader_parameter("plant_clip_dv")
	print("PROBE uv(0,0)->",origin," uv(1,1)->",origin+du+dv," uv(0.5,0.5)->",origin+du*0.5+dv*0.5)
	# 强制全裁 / 全不裁 各截一张，确认 shader 裁切确实生效
	world.camera_2d.position_smoothing_enabled = false
	world.toolbar_zoom_multiplier = 12.0
	world.mouse_offset = spear.plant_contact_point()+Vector2(3,-5) - center
	world.process_always(0.0)
	for i in range(4):
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	gm.set_shader_parameter("plant_clip_y",-100000.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://probe_clip_off.png")
	gm.set_shader_parameter("plant_clip_y",100000.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://probe_clip_all.png")
	print("PROBE saved")
	finish(0)
