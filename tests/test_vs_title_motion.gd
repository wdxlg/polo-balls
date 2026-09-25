extends SceneTree
## GPU temporal regression: the ordinary VS must not shimmer as the camera moves.

var world:Node2D
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VS_MOTION_FAIL "+label)
	else:
		print("PASS: ",label)

func capture_white_title(viewport:Viewport = null) -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var target:Viewport = viewport if viewport != null else root
	var image:Image = target.get_texture().get_image()
	var width:int = image.get_width()
	var height:int = mini(210,image.get_height())
	var mask:PackedByteArray = PackedByteArray()
	mask.resize(width * height)
	for y:int in range(height):
		for x:int in range(width):
			var pixel:Color = image.get_pixel(x,y)
			# The blue checker never has near-white pixels; white VS is the motion probe.
			if pixel.r > 0.87 and pixel.g > 0.87 and pixel.b > 0.87:
				mask[y * width + x] = 1
	return mask

func changed_pixels(first:PackedByteArray,second:PackedByteArray) -> int:
	if first.size() != second.size():
		return maxi(first.size(),second.size())
	var changed:int = 0
	for i:int in range(first.size()):
		if first[i] != second[i]:
			changed += 1
	return changed

func mask_metrics(mask:PackedByteArray) -> String:
	var minimum:Vector2i = Vector2i(10000,10000)
	var maximum:Vector2i = Vector2i(-1,-1)
	var count:int = 0
	for i:int in range(mask.size()):
		if mask[i] == 0: continue
		var x:int = i % 540
		var y:int = i / 540
		minimum = Vector2i(mini(minimum.x,x),mini(minimum.y,y))
		maximum = Vector2i(maxi(maximum.x,x),maxi(maximum.y,y))
		count += 1
	return "count=%d box=%s..%s" % [count,minimum,maximum]

func run() -> void:
	create_timer(50.0,true,false,true).timeout.connect(func(): push_error("VS_MOTION_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var previous_settings:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	root.size = Vector2i(540,960)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node2D
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	world.control.get_parent().hide()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.global_position = center
	world.camera_2d.reset_smoothing()
	world.camera_2d.force_update_scroll()
	world.versus_label.text = "[center][color=#FFFFFF][b]VS[/b][/color][/center]"
	world.versus_label.visible = true
	world.refresh_top_text_layout()
	var baseline:PackedByteArray = await capture_white_title()
	print("VS_MOTION_BASE ",mask_metrics(baseline))
	var white_count:int = 0
	for pixel:int in baseline:
		white_count += pixel
	check(white_count > 15,"GPU screenshot contains white VS glyph pixels")
	var still:PackedByteArray = await capture_white_title()
	check(changed_pixels(baseline,still) == 0,"static camera does not animate ordinary VS lettering")
	var max_changed:int = 0
	var max_drift:float = 0.0
	var first_corner:Vector2 = world.versus_label.get_global_transform_with_canvas() * Vector2.ZERO
	for i:int in range(1,15):
		var t:float = float(i)
		world.camera_2d.global_position = center + Vector2(0.29*t + 9.8*sin(t*0.72),-0.21*t + 6.1*cos(t*0.43))
		world.camera_2d.offset = Vector2(1.7*sin(t*0.49),1.3*cos(t*0.87))
		world.camera_2d.force_update_scroll()
		var sample:PackedByteArray = await capture_white_title()
		var changed:int = changed_pixels(baseline,sample)
		max_changed = maxi(max_changed,changed)
		var corner:Vector2 = world.versus_label.get_global_transform_with_canvas() * Vector2.ZERO
		max_drift = maxf(max_drift,corner.distance_to(first_corner))
		print("VS_MOTION_FRAME ",i," changed=",changed," ",mask_metrics(sample)," corner=",corner," canvas=",world.get_viewport().get_canvas_transform().origin)
	check(max_drift < 0.02,"VS control origin stays fixed in screen coordinates under camera motion")
	check(max_changed == 0,"VS glyph pixels remain identical through camera pan and shake")
	# The recording viewports share World2D but not the main viewport's CanvasLayer.
	# Verify their bilingual source still exists and measure its temporal pixels.
	world.versus_label.text = "[center][color=#FFFFFF][b]钻石剑 VS 木剑[/b][/color][/center]"
	world.refresh_top_text_layout()
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	var sub:SubViewport = SubViewport.new()
	sub.disable_3d = true
	sub.size = Vector2i(540,960)
	sub.world_2d = root.world_2d
	sub.canvas_cull_mask = 1 | (1 << 17)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var sub_en:SubViewport = SubViewport.new()
	sub_en.disable_3d = true
	sub_en.size = sub.size
	sub_en.world_2d = root.world_2d
	sub_en.canvas_cull_mask = 1 | (1 << 18)
	sub_en.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub_en)
	mirror.begin(world,root,{"zh":sub,"en":sub_en})
	mirror.sync()
	check(mirror.copies.has(world.versus_label.get_instance_id()),"recorder mirrors VS even though its source belongs to a CanvasLayer")
	sub.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE*0.5)*world.get_viewport().get_canvas_transform()
	sub_en.canvas_transform = sub.canvas_transform
	# Both offscreen viewports need a rendered warm-up frame after creation.
	await RenderingServer.frame_post_draw
	var copy_base:PackedByteArray = await capture_white_title(sub)
	var copy_base_en:PackedByteArray = await capture_white_title(sub_en)
	var copy_count:int = 0
	for pixel:int in copy_base:
		copy_count += pixel
	check(copy_count > 15,"offscreen Chinese recording contains the white VS title")
	var en_count:int = 0
	for pixel:int in copy_base_en:
		en_count += pixel
	check(en_count > 15,"offscreen English recording contains the white VS title")
	var max_copy_changed:int = 0
	var max_copy_changed_en:int = 0
	for i:int in range(1,10):
		var t:float = float(i)
		world.camera_2d.global_position = center + Vector2(0.29*t + 9.8*sin(t*0.72),-0.21*t + 6.1*cos(t*0.43))
		world.camera_2d.offset = Vector2(1.7*sin(t*0.49),1.3*cos(t*0.87))
		world.camera_2d.force_update_scroll()
		sub.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE*0.5)*world.get_viewport().get_canvas_transform()
		sub_en.canvas_transform = sub.canvas_transform
		mirror.sync()
		var sample:PackedByteArray = await capture_white_title(sub)
		var sample_en:PackedByteArray = await capture_white_title(sub_en)
		max_copy_changed = maxi(max_copy_changed,changed_pixels(copy_base,sample))
		max_copy_changed_en = maxi(max_copy_changed_en,changed_pixels(copy_base_en,sample_en))
		print("VS_MOTION_RECORD_FRAME ",i," zh_changed=",changed_pixels(copy_base,sample)," en_changed=",changed_pixels(copy_base_en,sample_en)," ",mask_metrics(sample))
	check(max_copy_changed == 0,"Chinese recorded VS pixels remain stable through camera motion")
	check(max_copy_changed_en == 0,"English recorded VS pixels remain stable through camera motion")
	mirror.finish()
	mirror.queue_free()
	sub.queue_free()
	sub_en.queue_free()
	world.queue_free()
	await process_frame
	game.Game_Settings = previous_settings
	print("VS_MOTION_RESULT checks=",checks," failures=",failures," live_max=",max_changed," zh_max=",max_copy_changed," en_max=",max_copy_changed_en," max_drift=",max_drift)
	quit(1 if failures > 0 else 0)
