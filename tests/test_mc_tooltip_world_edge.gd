extends SceneTree
## GPU regression in the real World: the outside-map mask erases units, not
## the screen-aligned potion frame captured BEFORE those units are drawn.
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MC_TOOLTIP_EDGE_FAIL: "+label)

func difference(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func run() -> void:
	create_timer(45.0,true,false,true).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		print("MC_TOOLTIP_EDGE_SKIPPED headless requires a real GPU")
		quit()
		return
	var game:Node = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.Game_Settings.Map_Background = "blue"
	root.size = Vector2i(1080,1920)
	var world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.2).timeout
	var area:Rect2 = world.return_map_world_rect(world._current_map_node())
	var actor:Node2D = (load("res://scenes/characters/默认/药水测试盔甲架.tscn") as PackedScene).instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.set("Team","A")
	actor.position = Vector2(area.end.x-22.0,area.get_center().y)
	world.add_child(actor,true)
	var pool:Array = actor.get("potion_pool")
	var chosen:Array[MCPreviewPotionEffect] = [pool[0] as MCPreviewPotionEffect,pool[1] as MCPreviewPotionEffect]
	actor.call("set_displayed_potions",chosen)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ui:MCPreviewTooltip = actor.get_node("Minecraft信息框") as MCPreviewTooltip
	var panel:Control = ui._panel
	var frame_rect:=Rect2(panel.position,panel.size*panel.scale)
	var border_x:float = (root.get_canvas_transform()*Vector2(area.end.x,area.get_center().y)).x
	var outside:Rect2 = frame_rect.intersection(Rect2(Vector2(border_x+5.0,0),Vector2(root.size)))
	check(ui.top_level and ui.z_index == MCPreviewTooltip.TOOLTIP_Z and world.map_clip_backbuffer.z_index == 0 and world.map_outside_mask_root.visible,"real map snapshots the frame before world actors and leaves outside masking enabled")
	check(panel.visible and outside.has_area() and outside.size.x > 40.0,"potion frame visibly extends beyond the real map border")
	var with_frame:Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mc_tooltip_world_depth"))
	var saved:Error = with_frame.save_png("user://mc_tooltip_world_depth/world_edge_frame.png")
	# A foreground object outside the same border must STILL be erased by the
	# world mask. It overlaps the visible frame and must not paint on top of it.
	var outside_actor:=Node2D.new()
	# Use the panel's on-screen overlap, not a fixed world offset: camera zoom
	# can project a small world distance beyond the physical viewport.
	outside_actor.position = root.get_canvas_transform().affine_inverse()*outside.get_center()
	world.add_child(outside_actor)
	var ink:=ColorRect.new()
	ink.color = Color.MAGENTA
	ink.position = Vector2(-12,-12)
	ink.size = Vector2(24,24)
	outside_actor.add_child(ink)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var masked:Image = root.get_texture().get_image()
	var point:Vector2i = Vector2i((root.get_canvas_transform()*outside_actor.global_position).round())
	check(outside.has_point(Vector2(point)) and difference(masked.get_pixelv(point),with_frame.get_pixelv(point))<0.05,"map mask removes outside foreground but retains the frame beneath")
	outside_actor.queue_free()
	ui.set_process(false)
	panel.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without:Image = root.get_texture().get_image()
	var changed:int = 0
	for y:int in range(maxi(0,int(outside.position.y)),mini(with_frame.get_height(),int(outside.end.y)),4):
		for x:int in range(maxi(0,int(outside.position.x)),mini(with_frame.get_width(),int(outside.end.x)),4):
			if difference(with_frame.get_pixel(x,y),without.get_pixel(x,y)) > 0.07: changed += 1
	check(changed > 200 and saved == OK,"actual GPU shows the frame outside the map instead of hiding it with the mask")
	print("MC_TOOLTIP_EDGE_RESULT checks=%d failures=%d outside_frame_pixels=%d border_x=%f probe=%s" % [checks,failures,changed,border_x,point])
	world.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
