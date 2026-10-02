extends "res://tests/test_mc_frontier.gd"
const BLOCK:Script = preload("res://scripts/effects/我的世界/mc_block_3d.gd")


func run() -> void:
	var o:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cell:float = BLOCK.map_cell(world)
	check(cell > 0.0,"map cell size is known (%.1f)" % cell)
	# Every native model builds a mesh that stays inside one block of the requested size.
	for model_name:StringName in BLOCK.MODELS.keys():
		var built:Dictionary = BLOCK.build_mesh(model_name,cell)
		var mesh:ArrayMesh = built.mesh
		check(mesh != null and mesh.get_surface_count() == (built.textures as Array).size() and mesh.get_surface_count() > 0,"%s builds one surface per texture" % model_name)
		var box:AABB = mesh.get_aabb()
		var room:float = cell*0.02
		check(box.position.x >= -room and box.position.z >= -room and box.end.x <= cell+room and box.end.z <= cell+room,"%s fits in a single cell footprint (%s)" % [model_name,box])
		check(box.position.y >= -room and box.end.y <= cell+room and box.end.y >= cell*0.9,"%s is a full one-block-tall model" % model_name)
		check(built.crack_mesh != null,"%s has a crack overlay mesh" % model_name)
	# Vanilla face shading is baked into vertex colors.
	var table_mesh:ArrayMesh = BLOCK.build_mesh(&"crafting_table",cell).mesh
	var shades:Dictionary = {}
	for surface:int in range(table_mesh.get_surface_count()):
		var arrays:Array = table_mesh.surface_get_arrays(surface)
		var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors:PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i:int in range(normals.size()):
			shades[normals[i].round()] = snappedf(colors[i].r,0.01)
	check(shades.get(Vector3.UP) == 1.0 and shades.get(Vector3.DOWN) == 0.5,"top face is full brightness, bottom is vanilla 0.5")
	check(shades.get(Vector3.FORWARD) == 0.8 and shades.get(Vector3.BACK) == 0.8 and shades.get(Vector3.LEFT) == 0.6 and shades.get(Vector3.RIGHT) == 0.6,"north/south 0.8 and east/west 0.6 like vanilla")
	# Live block in the shared 3D overlay.
	var host := Node2D.new()
	host.global_position = o
	world.add_child(host)
	var block:Node2D = BLOCK.create(&"crafting_table",cell)
	host.add_child(block)
	await process_frame
	check(BLOCK.find_in(host) == block,"find_in returns the obstacle's block")
	check(block.block_rect() == Rect2(o-Vector2.ONE*cell*0.5,Vector2.ONE*cell),"2D footprint is exactly one cell")
	var mesh_node:MeshInstance3D = block.mesh_instance()
	check(is_instance_valid(mesh_node) and mesh_node.get_parent() == block.renderer().viewport,"mesh lives in the shared 3D overlay viewport")
	check(mesh_node.position.is_equal_approx(Vector3(o.x-cell*0.5,0.0,o.y-cell*0.5)),"mesh sits on the ground at the cell corner")
	check(block.surface_material(0).shader == BLOCK.shader_for("opaque"),"opaque block uses the cutout shader")
	check(is_instance_valid(block.debris_sample) and block.debris_sample.texture.get_size()*block.debris_sample.scale == Vector2.ONE*cell,"debris sample matches the block size")
	host.global_position = o+Vector2(cell*3.0,0)
	await process_frame
	check(block.mesh_instance().position.is_equal_approx(Vector3(o.x+cell*2.5,0.0,o.y-cell*0.5)),"mesh follows the 2D node")
	var crack:Texture2D = load("res://Images/Status/BlockDamage/destroy_stage_7.png")
	block.set_cracks(crack)
	check(block.crack_instance().visible and block.crack_instance().material_override.get_shader_parameter("albedo_tex") == crack,"cracks are drawn on the 3D faces")
	block.set_alpha(0.4)
	check(block.surface_material(0).shader == BLOCK.shader_for("fade") and is_equal_approx(float(block.surface_material(0).get_shader_parameter("fade")),0.4),"faded block switches to the dithered fade shader")
	check(not block.crack_instance().visible,"cracks hide while the block is faded")
	block.set_alpha(1.0)
	check(block.surface_material(0).shader == BLOCK.shader_for("opaque") and block.crack_instance().visible,"opaque again restores cutout and cracks")
	block.set_cracks(null)
	check(not block.crack_instance().visible,"clearing cracks hides the overlay")
	host.visible = false
	await process_frame
	check(not block.mesh_instance().visible,"hidden obstacle hides its 3D block")
	host.visible = true
	await process_frame
	check(block.mesh_instance().visible,"shown again")
	block.set_model(&"cactus")
	await process_frame
	check(is_instance_valid(block.mesh_instance()) and block.mesh_instance() != mesh_node and (not is_instance_valid(mesh_node) or mesh_node.is_queued_for_deletion()),"changing model rebuilds the mesh")
	var rebuilt:MeshInstance3D = block.mesh_instance()
	host.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(rebuilt),"freeing the obstacle removes its 3D mesh")
	print("MC BLOCK 3D: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
