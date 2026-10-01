extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	var source:Node2D = actor("烈焰人",center+Vector2(-180,0))
	var script:Script = load("res://scripts/effects/我的世界/烈焰火场.gd")
	var first_size:Vector2 = Vector2.ZERO
	for radius:float in [8.0,34.0,80.0]:
		var fire:Node2D = script.new()
		world.add_child(fire)
		fire.setup(source,"Team0",center+Vector2(3,5),radius,4.5,0.5,0.11,2.2,0.05)
		fire.set_physics_process(false)
		var block:Node2D = fire._fire_block
		var size:Vector2 = block.block_rect.size
		check(size.is_equal_approx(fire._fire_cell_rect.size),"fire visual occupies exactly one map cell")
		check(block.block_rect.is_equal_approx(fire._fire_cell_rect),"3D fire block stands on its own cell (ground footprint equals the block)")
		var node:MeshInstance3D = block.mesh_instance()
		check(node != null and node.position.is_equal_approx(Vector3(fire._fire_cell_rect.position.x,0.0,fire._fire_cell_rect.position.y)),"block geometry starts at the cell ground corner in the shared 3D view")
		check(fire._radius==radius and fire._duration==4.5,"grid sizing does not change damage radius or lifetime")
		if first_size.is_zero_approx(): first_size = size
		else: check(size.is_equal_approx(first_size),"different damage radii no longer stretch the flame")
		var aabb:AABB = node.mesh.get_aabb() if node != null else AABB()
		var strips:Array[int] = block.surface_texture_indices()
		for frame:int in range(block.FRAME_COUNT):
			block.frame = frame
			block._apply_frame()
			var scrolled:bool = node != null and node.mesh.get_aabb().is_equal_approx(aabb) and not strips.is_empty()
			for surface:int in range(strips.size()):
				scrolled = scrolled and is_equal_approx(block.surface_material(surface).uv1_offset.y,float(block.frame_row(strips[surface]))/32.0)
			check(scrolled,"all native animation frames keep the one-block geometry and only scroll their strip row")
		fire.free()
	var probe:Node2D = script.new()
	world.add_child(probe)
	probe.set_physics_process(false)
	var layer := TileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_size = Vector2i(16,16)
	world.add_child(layer)
	layer.position = Vector2(7,13)
	layer.scale = Vector2.ONE*2.0
	var p:Vector2 = layer.to_global(layer.map_to_local(Vector2i(3,4)))
	var rect:Rect2 = probe._cell_rect_on_layer(layer,p+Vector2(4,-3))
	check(rect.size.is_equal_approx(Vector2(32,32)),"tilemap scale is included in one-block world size")
	check(rect.get_center().is_equal_approx(p),"translated grid origin is respected, not rounded against global zero")
	check(is_equal_approx(rect.end.y,p.y+16.0),"scaled block bottom is preserved")
	layer.free()
	probe.free()
	print("BLAZE FIRE GRID: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
