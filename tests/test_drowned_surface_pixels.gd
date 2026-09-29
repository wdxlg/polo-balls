extends "res://tests/test_drowned_surface_probe.gd"
func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func world_pixel(point:Vector2) -> Vector2:
	return world.get_global_transform_with_canvas()*world.to_local(point)
func world_rect_pixels(rect:Rect2) -> Rect2i:
	var a:Vector2 = world_pixel(rect.position)
	var b:Vector2 = world_pixel(rect.end)
	return Rect2i(Vector2i(a.ceil()),Vector2i((b-a).floor())).intersection(Rect2i(Vector2i.ZERO,root.size))
func changed_pixels(reference:Image,current:Image,rect:Rect2i) -> int:
	var count:int = 0
	for y:int in range(rect.position.y,rect.end.y):
		for x:int in range(rect.position.x,rect.end.x):
			var a:Color = reference.get_pixel(x,y)
			var b:Color = current.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > 0.065: count += 1
	return count
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This regression requires an actual GPU/window")
		quit(2)
		return
	root.size = Vector2i(900,660)
	root.content_scale_size = Vector2i(900,660)
	await setup_probe()
	create_timer(55.0).timeout.connect(func(): finish(2))
	for ui:Node in world.find_children("*","CanvasLayer",true,false): ui.visible = false
	world.versus_label.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center+Vector2(0,-5)
	camera.zoom = Vector2(12,12)
	camera.make_current()
	# A known visible floor patch proves the mace sampler reads actual rendered
	# ground, not a fixed invented dust color. It is a test fixture only.
	var floor_patch := Polygon2D.new()
	floor_patch.polygon = PackedVector2Array([Vector2(-60,-60),Vector2(60,-60),Vector2(60,60),Vector2(-60,60)])
	floor_patch.color = Color(0.72,0.21,0.08,1.0)
	floor_patch.z_as_relative = false
	floor_patch.z_index = -5
	world.add_child(floor_patch)
	floor_patch.global_position = center
	await process_frame
	var spear:Node2D = new_spear(1501)
	spear.launch(Vector2.RIGHT,center-Vector2(80,0),center)
	spear.stick_ground(center)
	var effect:Node2D
	for node:Node in get_nodes_in_group("MCTridentGroundDebris"):
		if int(node.get_meta("mc_trident_source_id",0)) == spear.get_instance_id(): effect = node
	for i:int in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
		if effect != null and not effect._blocks.is_empty(): break
	check(is_instance_valid(effect) and effect._blocks.size() >= 30,"GPU impact produces the actual dense mace preset, not just an empty node")
	var matching:int = 0
	for block:Dictionary in effect._blocks:
		var color:Color = block.color
		if color.r > color.g+0.18 and color.g > color.b: matching += 1
	check(matching == effect._blocks.size(),"all ground fragments inherit the real red/orange floor samples")
	check(effect.z_as_relative == false and effect.z_index == 4 and is_zero_approx(effect.global_rotation),"fragment rendering stays upright/visible instead of inheriting the lodged spear transform")
	effect.set_process(false)
	effect.hide()
	spear.charged = false
	spear.charge_visual.advance(0.0)
	var reference:Image = await grab()
	var contact:Vector2 = spear.plant_contact_point()
	var clip_y:float = spear.plant_clip_y()
	var below:Rect2i = world_rect_pixels(Rect2(Vector2(contact.x-11,clip_y+0.4),Vector2(22,spear.plant_tip_point().y-clip_y+2.0)))
	var above:Rect2i = world_rect_pixels(Rect2(Vector2(contact.x-11,clip_y-20),Vector2(22,19.4)))
	var worst_below:int = 0
	var best_above:int = 0
	spear.charged = true
	for i:int in range(24):
		spear._clock += 0.073
		spear.charge_visual._reroute_left = 0.0
		spear.charge_visual.advance(0.073)
		var shot:Image = await grab()
		worst_below = maxi(worst_below,changed_pixels(reference,shot,below))
		best_above = maxi(best_above,changed_pixels(reference,shot,above))
	check(worst_below == 0,"native glow AND randomized electric forks reveal zero pixels below the dirt surface")
	check(best_above > 25,"above-ground shaft still visibly carries native glint/electricity")
	print("DROWNED_PIXEL_CLIP below=",worst_below," above=",best_above," particles=",effect._blocks.size())
	# Negative control: turning off just the native overlay clip must expose
	# the original buried fork, proving this image assertion detects the bug.
	spear.charge_visual.glint_material.set_shader_parameter("plant_clip",0.0)
	var unclipped:Image = await grab()
	var negative:int = changed_pixels(reference,unclipped,below)
	check(negative > 25,"negative control detects the buried fork if its overlay clip is removed")
	print("DROWNED_PIXEL_NEGATIVE buried=",negative)
	spear.charge_visual.sync_plant_clip()
	var fixed:Image = await grab()
	fixed.save_png("res://tests/drowned_trident_ground_clipped.png")
	effect._elapsed = 0.18
	effect.show()
	effect.queue_redraw()
	var burst:Image = await grab()
	var burst_region:Rect2i = world_rect_pixels(Rect2(contact-Vector2(33,45),Vector2(66,67)))
	var visible_blocks:int = changed_pixels(fixed,burst,burst_region)
	check(visible_blocks > 40,"mace-style fragment quads actually reach the final rendered image")
	burst.save_png("res://tests/drowned_trident_ground_burst.png")
	print("DROWNED_PIXEL_DEBRIS visible_pixels=",visible_blocks)
	# Ground burials may later be collected: restore all rendering layers.
	spear._begin_return()
	spear.charge_visual.advance(0.0)
	check(float(spear.material.get_shader_parameter("plant_clip")) < 0.5 and float(spear.charge_visual.glint_material.get_shader_parameter("plant_clip")) < 0.5 and float(spear.charge_visual.arc_material.get_shader_parameter("plant_clip")) < 0.5,"returning weapon clears body/glow/arc clip together")
	print("DROWNED_SURFACE_PIXELS checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
