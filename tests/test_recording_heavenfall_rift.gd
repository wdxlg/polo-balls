extends SceneTree
# GPU regression: the late screen-reading warp must not erase the fracture in
# either recording language or after the offline preview mask is applied.
var checks: int = 0
var failed: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failed += 1
func sample(viewport: Viewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func compare(viewport: Viewport, rift: Node2D, bounds: Rect2) -> Dictionary:
	if viewport is SubViewport: viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	rift.visible = false
	var off: Image = await sample(viewport)
	rift.visible = true
	var on: Image = await sample(viewport)
	var projection: Viewport = viewport
	if viewport is SubViewport and viewport.name == "BattleRecordSRGB": projection = viewport.get_parent().get_node("BattleRecordCapture") as Viewport
	var to_pixels: Transform2D = projection.get_stretch_transform() * projection.global_canvas_transform * projection.canvas_transform
	var rect: Rect2i = Rect2i(to_pixels * bounds)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, on.get_size()))
	var changed: int = 0
	var bright: int = 0
	var max_delta: float = 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var a: Color = off.get_pixel(x,y)
			var b: Color = on.get_pixel(x,y)
			var d: float = maxf(absf(a.r-b.r), maxf(absf(a.g-b.g),absf(a.b-b.b)))
			if d > 0.07: changed += 1
			if maxf(b.r,maxf(b.g,b.b)) > 0.45: bright += 1
			max_delta = maxf(max_delta,d)
	return {"changed":changed,"bright":bright,"max":max_delta,"rect":rect,"size":on.get_size()}
func run() -> void:
	create_timer(50.0,true,false,true).timeout.connect(func(): print("RIFT_RECORD_TIMEOUT");quit(2))
	var game: Node = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	var world: Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.hide()
	root.size = Vector2i(540,960)
	await create_timer(0.4).timeout
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.make_current()
	await process_frame
	var rift: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd").new()
	world.add_child(rift)
	var points := PackedVector2Array([center+Vector2(-125,0),center+Vector2(125,0)])
	rift.call("configure",null,1703,points,[],center,5.0)
	rift.set_process(false)
	rift.set("_age",0.7)
	rift.call("_sync_visual")
	var bounds := Rect2(center+Vector2(-130,-13),Vector2(260,26))
	var normal: Dictionary = await compare(root,rift,bounds)
	print("REAL_RIFT ",normal)
	check(normal.changed > 40,"main battle viewport shows crack")
	var recorder: Node = world.control._battle_record_controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://rift_probe.cfg")
	recorder.preferences.directory = "user://recordings/rift_probe"
	check(recorder.start_live(), "recorder starts real dual-language capture")
	await process_frame
	recorder._prepare_next_capture()
	var zh: Dictionary = await compare(recorder._sim_viewport,rift,bounds)
	var old_mask: int = root.canvas_cull_mask
	root.canvas_cull_mask = recorder.CAPTURE_MASK_BIT
	recorder._prepare_next_capture()
	var sim_zh: Dictionary = await compare(recorder._sim_viewport,rift,bounds)
	print("SIM_ZH_RIFT ",sim_zh)
	rift.visible = false
	var newborn: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd").new()
	world.add_child(newborn)
	newborn.call("configure",null,1704,points,[],center,5.0)
	newborn.set_process(false)
	newborn.set("_age",0.7)
	newborn.call("_sync_visual")
	var born_zh: Dictionary = await compare(recorder._sim_viewport,newborn,bounds)
	print("SIM_NEW_RIFT ",born_zh)
	check(born_zh.changed > 300,"fracture created after preview hidden renders into offline viewport")
	newborn.visible = false
	rift.visible = true
	check(sim_zh.changed > 300,"Chinese offline mode shows crack after main viewport mask switch")
	root.canvas_cull_mask = old_mask
	print("RECORD_ZH_RIFT ",zh)
	recorder._prepare_next_capture()
	var en: Dictionary = await compare(recorder._secondary._sim_viewport,rift,bounds)
	var resolved: Dictionary = await compare(recorder._capture_viewport,rift,bounds)
	var en_resolved: Dictionary = await compare(recorder._secondary._capture_viewport,rift,bounds)
	print("RECORD_EN_RESOLVE_RIFT ",en_resolved)
	check(en_resolved.changed > 300,"English resolved video source shows crack")
	print("RECORD_RESOLVE_RIFT ",resolved)
	check(resolved.changed > 300,"resolved video source shows crack")
	print("RECORD_EN_RIFT ",en)
	check(zh.changed > 300,"Chinese recording viewport shows crack")
	check(en.changed > 300,"English recording viewport shows crack")
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd != null:
		var bytes: PackedByteArray = recorder._grab_offline_rgba()
		var legacy: PackedByteArray = recorder._grab_image().get_data()
		check(bytes.size() == 1080*1920*4 and bytes == legacy,"direct GPU RGBA readback is byte-identical to the original image path")
	recorder.stop()
	print("RIFT_RECORD_RESULT %d/%d" % [checks-failed,checks])
	quit(0 if failed == 0 else 1)
