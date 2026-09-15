extends SceneTree
var failures:int = 0
var pixel_frames:int = 0
var max_difference:int = 0
var views:Array[SubViewport] = []
var worlds:Array[Node2D] = []
var unit:Node2D
var factory:RefCounted
var params_script:Script
var original_tweens:Array[Tween] = []
func _initialize() -> void:
	call_deferred("_run")
func compare_pixels(stage:String) -> void:
	await RenderingServer.frame_post_draw
	var records:Array = factory.debug_rids()
	for i:int in range(records.size()):
		var expected:Sprite2D = worlds[0].get_child(i)
		if expected.transform != records[i].transform:
			print("NATIVE_MATRIX ",stage," i=",i," expected=",var_to_bytes(expected.transform).hex_encode()," actual=",var_to_bytes(records[i].transform).hex_encode())
		if expected.get_instance_shader_parameter("progress") != records[i].progress:
			print("NATIVE_PROGRESS ",stage," i=",i," expected=",var_to_bytes(expected.get_instance_shader_parameter("progress")).hex_encode()," actual=",var_to_bytes(records[i].progress).hex_encode())
	var a:PackedByteArray = views[0].get_texture().get_image().get_data()
	var b:PackedByteArray = views[1].get_texture().get_image().get_data()
	if stage == "initial" and not views[0].get_texture().get_image().get_used_rect().has_area():
		failures += 1
		print("NATIVE_RID_EMPTY_REFERENCE")
	pixel_frames += 1
	if a != b:
		failures += 1
		var changed:int = 0
		for i:int in range(a.size()):
			if a[i] != b[i]:
				changed += 1
				max_difference = maxi(max_difference,absi(int(a[i])-int(b[i])))
		print("NATIVE_RID_DIFFERENCE ",stage," channels=",changed," max=",max_difference)
		if failures == 1:
			views[0].get_texture().get_image().save_png("res://scripts/training/native_rid_expected.png")
			views[1].get_texture().get_image().save_png("res://scripts/training/native_rid_actual.png")
func _run() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	GDExtensionManager.load_extension("res://.performance_tools/native/knife_native.gdextension")
	factory = ClassDB.instantiate("KnifeNativeSnapshots")
	params_script = load("res://scripts/training/knife_native_rid_probe.gd")
	unit = load("res://scenes/shooter/knife.tscn").instantiate()
	unit.batch_after_image_snapshots = false
	root.add_child(unit)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.AfterImage_Lifetime = 0.18
	for i:int in range(2):
		var view:SubViewport = SubViewport.new()
		view.size = Vector2i(320,192)
		view.transparent_bg = true
		view.use_hdr_2d = root.use_hdr_2d
		view.world_2d = World2D.new()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		views.append(view)
		var world:Node2D = Node2D.new()
		world.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(world)
		RenderingServer.canvas_item_set_parent(world.get_canvas_item(),view.world_2d.canvas)
		worlds.append(world)
	for style:int in range(6):
		unit.AfterImage_Style = style
		unit.AfterImage_Fade = style % 4
		unit._visual_facing_flipped_h = style % 2 == 1
		unit.image.modulate = Color(0.87,0.73,0.94,0.81)
		unit.image.self_modulate = Color(0.62,0.89,0.74,0.93)
		unit.AfterImage_Tint = Color(0.89,0.51,0.72,0.83)
		unit.AfterImage_End_Tint = Color(0.47,0.83,0.66,0.74)
		unit.AfterImage_End_Alpha = 0.12
		for j:int in range(3):
			var t:Transform2D = Transform2D(0.3 * float(j),Vector2(48+style*43,70+j*14)).scaled_local(Vector2(0.13,0.13))
			current_scene = worlds[0]
			var before:Array[Tween] = get_processed_tweens()
			unit._spawn_after_image_at_transform(t,Vector2(0.8,0.6))
			for tween:Tween in get_processed_tweens():
				if not before.has(tween):
					tween.pause()
					original_tweens.append(tween)
			current_scene = worlds[1]
			before = get_processed_tweens()
			if not factory.can_spawn_rid(unit.image,worlds[1]) or not factory.spawn_rid(unit,unit.image,worlds[1],params_script.parameters(unit,t,Vector2(0.8,0.6)),unit.AFTER_IMAGE_MATERIAL):
				failures += 1
				print("NATIVE_RID_REJECTED")
			for tween:Tween in get_processed_tweens():
				if not before.has(tween):
					tween.pause()

	print("NATIVE_RID_VIEW_HDR ",root.use_hdr_2d," ",views[0].use_hdr_2d)
	await compare_pixels("initial")
	for delta:float in [0.0166666666666667,0.025,0.031,0.042,0.04,0.03]:
		for tween:Tween in original_tweens:
			if tween.is_valid():
				tween.custom_step(delta)
		factory.advance_rids(delta)
		if delta == 0.031 and "--kill-source" in OS.get_cmdline_user_args():
			unit.free()
			unit = null
		await compare_pixels(str(delta))
	print("NATIVE_RID_VISUAL_RESULT ",JSON.stringify({"frames":pixel_frames,"failures":failures,"max_channel_difference":max_difference}))
	current_scene = null
	if is_instance_valid(unit):
		unit.queue_free()
	for world:Node2D in worlds:
		world.queue_free()
	for view:SubViewport in views:
		view.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
