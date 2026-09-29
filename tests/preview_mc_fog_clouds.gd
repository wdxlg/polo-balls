extends "res://tests/test_mc_frontier.gd"
var camera:Camera2D
var fog:Node2D
func capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func pixel_at(image:Image,point:Vector2) -> Color:
	var pixel:Vector2i = Vector2i(root.get_final_transform()*(fog.get_global_transform_with_canvas()*point))
	return image.get_pixelv(pixel.clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
func difference(a:Image,b:Image,point:Vector2) -> float:
	return absf(pixel_at(a,point).r-pixel_at(b,point).r)
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(45).timeout.connect(func(): finish(2))
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	camera = Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2.ONE*1.4
	camera.make_current()
	var man:Node2D = actor("雾中人",center+Vector2(-110,0))
	var enemy:Node2D = dummy(center)
	enemy.velocity = Vector2.RIGHT*10.0
	fog = man.fog
	fog.set_process(false)
	fog.fog_alpha = 0.985
	fog._process(0.1)
	fog.refresh_viewers()
	fog.rebuild_mask(fog.owners())
	check(not fog.veil.visible,"no solid fog backing surface is drawn")
	check(fog.NEAR==32.0,"near clearing radius reduced to 32")
	var early:float = fog.mist_reveal_at(center+Vector2(100,0))
	check(early<0.3,"new clearing does not disappear instantly")
	for i:int in range(12): fog.update_mist_memory(0.1)
	var settled:float = fog.mist_reveal_at(center+Vector2(100,0))
	check(settled>0.7,"clearing gradually reaches target")
	var repelled:bool = false
	for cloud:Sprite2D in fog.clouds.values():
		if Vector2(cloud.get_meta("avoid_target",Vector2.ZERO)).length()>1.0: repelled = true
	check(repelled,"clouds actively retreat from clearing")
	enemy.velocity = Vector2.LEFT*10.0
	fog.refresh_viewers()
	fog.rebuild_mask(fog.owners())
	fog.update_mist_memory(0.1)
	check(fog.mist_reveal_at(center+Vector2(100,0))>0.6,"old clearing persists after turning")
	for i:int in range(28): fog.update_mist_memory(0.1)
	check(fog.mist_reveal_at(center+Vector2(100,0))<0.05,"old clearing slowly refills")
	enemy.velocity = Vector2.RIGHT*10.0
	fog.refresh_viewers()
	fog.rebuild_mask(fog.owners())
	for i:int in range(12): fog.update_mist_memory(0.1)
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([center+Vector2(-10000,-10000),center+Vector2(10000,-10000),center+Vector2(10000,10000),center+Vector2(-10000,10000)])
	backdrop.z_index = 89
	world.add_child(backdrop)
	backdrop.color = Color.BLACK
	var black:Image = await capture()
	backdrop.color = Color.WHITE
	var white:Image = await capture()
	var dense:float = difference(black,white,center+Vector2(-150,70))
	var near_hole:float = difference(black,white,center+Vector2(0,25))
	var cone_hole:float = difference(black,white,center+Vector2(120,0))
	print("FOG TRANSMISSION dense=",dense," circle=",near_hole," cone=",cone_hole," cloud_count=",fog.clouds.size())
	check(dense<0.04,"dense fog transmits less than four percent of background")
	check(near_hole>0.08 and near_hole<0.75,"near circle retains substantial mist")
	check(cone_hole>0.08 and cone_hole<0.75,"movement triangle retains substantial mist")
	check(fog.cloud_textures.size()==4 and fog.clouds.size()>20,"actual individual RGBA cloud sprites overlap")
	var first:Sprite2D = fog.clouds.values()[0]
	var old_position:Vector2 = first.position
	fog._process(2.0)
	check(first.position.distance_to(old_position)>0.1,"clouds drift independently over time")
	# Test beyond map edge with the camera outside the arena, not merely enlarged data bounds.
	camera.position = fog.arena_rect().end+Vector2(130,130)
	await process_frame
	fog.viewers.clear()
	fog.rebuild_mask(fog.owners())
	backdrop.color = Color.BLACK
	black = await capture()
	backdrop.color = Color.WHITE
	white = await capture()
	var outside:float = difference(black,white,camera.position)
	print("FOG OUTSIDE MAP transmission=",outside)
	check(outside<0.04,"fog renders outside map without rectangle clipping")
	# Restore normal battlefield for a human-viewable screenshot.
	backdrop.queue_free()
	camera.position = center
	await process_frame
	fog.refresh_viewers()
	fog.rebuild_mask(fog.owners())
	var shot:Image = await capture()
	shot.save_png("res://tests/fog_cloud_preview.png")
	finish(0 if failures==0 else 1)
