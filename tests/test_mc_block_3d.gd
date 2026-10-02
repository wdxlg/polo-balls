extends "res://tests/test_mc_frontier.gd"
const BLOCK:Script = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const RENDERER:Script = preload("res://scripts/effects/我的世界/mc_block_3d_renderer.gd")


func run() -> void:
	var o:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cell:float = BLOCK.map_cell(world)
	check(cell > 0.0,"map cell size is known (%.1f)" % cell)
	check(not BLOCK.MODELS.has(&"short_grass"),"no grass model is offered")
	# Every native model builds a mesh that stays inside one block of the requested size.
	for model_name:StringName in BLOCK.MODELS.keys():
		var built:Dictionary = BLOCK.build_mesh(model_name,cell)
		var mesh:ArrayMesh = built.mesh
		check(mesh != null and mesh.get_surface_count() == (built.textures as Array).size() and mesh.get_surface_count() > 0,"%s builds one surface per texture" % model_name)
		var box:AABB = mesh.get_aabb()
		var room:float = cell*0.02
		check(box.position.x >= -room and box.position.z >= -room and box.end.x <= cell+room and box.end.z <= cell+room,"%s fits in a single cell footprint (%s)" % [model_name,box])
		check(box.position.y >= -room and box.end.y <= cell+room and box.end.y >= cell*0.9,"%s is a full one-block-tall model" % model_name)
	# Outward normals so the real sun lights the faces like the map walls.
	var table_mesh:ArrayMesh = BLOCK.build_mesh(&"crafting_table",cell).mesh
	var normals_seen:Dictionary = {}
	for surface:int in range(table_mesh.get_surface_count()):
		var arrays:Array = table_mesh.surface_get_arrays(surface)
		for n:Vector3 in arrays[Mesh.ARRAY_NORMAL]: normals_seen[n.round()] = true
	check(normals_seen.size() == 6 and normals_seen.has(Vector3.UP) and normals_seen.has(Vector3.FORWARD),"cube faces carry the six outward normals")
	var code:String = BLOCK.block_shader().code
	check(not code.contains("unshaded") and code.contains("diffuse_burley") and code.contains("source_color"),"block shader is lit like the wall material (sRGB texture, Burley diffuse)")
	check(not code.contains("FRAGCOORD") and not code.contains("blend_") and not code.contains("ALPHA ="),"no screen-space dither and no translucent blending")
	# Live block in the shared 3D overlay.
	var host := Node2D.new()
	host.global_position = o
	world.add_child(host)
	var block:Node2D = BLOCK.create(&"crafting_table",cell)
	host.add_child(block)
	await process_frame
	check(BLOCK.find_in(host) == block,"find_in returns the obstacle's block")
	check(block.block_rect() == Rect2(o-Vector2.ONE*cell*0.5,Vector2.ONE*cell),"2D footprint is exactly one cell")
	var renderer:Node2D = block.renderer()
	check(is_instance_valid(renderer) and renderer.get_script() == RENDERER and renderer.visible,"block renders in the dedicated block overlay")
	check(not renderer.z_as_relative and renderer.z_index == -4,"blocks share the map walls' layer, under the characters")
	var mesh_node:MeshInstance3D = block.mesh_instance()
	check(is_instance_valid(mesh_node) and mesh_node.get_parent() == renderer.viewport and mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"mesh lives in the overlay viewport and casts shadows on other blocks")
	var shadow_node:MeshInstance3D = block.shadow_instance()
	check(is_instance_valid(shadow_node) and shadow_node.get_parent() == renderer.shadow_viewport and shadow_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"a shadow-only twin throws the real ground shadow")
	check(renderer.shadow_picture.visible and renderer.shadow_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and renderer.ground_node.mesh != null,"ground shadow pass is live over the map islands")
	check(mesh_node.position.is_equal_approx(Vector3(o.x-cell*0.5,0.0,o.y-cell*0.5)) and shadow_node.position.is_equal_approx(mesh_node.position),"mesh and shadow sit on the ground at the cell corner")
	check(is_instance_valid(block.debris_sample) and block.debris_sample.texture.get_size()*block.debris_sample.scale == Vector2.ONE*cell,"debris sample matches the block size")
	# Lighting follows the map walls exactly (or the walls' defaults when the theme has none).
	var wall:Node2D = world.get("map_wall_volume")
	renderer.sync_map_lighting()
	if is_instance_valid(wall) and wall.visible and wall.tiled:
		check(renderer.sun_light.global_transform.basis.is_equal_approx(wall.sun_light.global_transform.basis) and is_equal_approx(renderer.sun_light.light_energy,wall.sun_light.light_energy),"block sun matches the map wall sun")
		wall.sun_light.rotate_y(0.7)
		wall.sun_light.light_energy = 1.3
		renderer.sync_map_lighting()
		check(renderer.sun_light.global_transform.basis.is_equal_approx(wall.sun_light.global_transform.basis) and is_equal_approx(renderer.sun_light.light_energy,1.3),"block sun follows the walls when time of day turns them")
	else:
		check(is_equal_approx(renderer.sun_light.light_energy,RENDERER.DEFAULT_SUN_ENERGY),"wall-less theme uses the walls' default sun")
	check(renderer.shadow_sun.global_transform.basis.is_equal_approx(renderer.sun_light.global_transform.basis),"shadow pass uses the same sun")
	host.global_position = o+Vector2(cell*3.0,0)
	await process_frame
	check(block.mesh_instance().position.is_equal_approx(Vector3(o.x+cell*2.5,0.0,o.y-cell*0.5)) and block.shadow_instance().position.is_equal_approx(block.mesh_instance().position),"mesh and shadow follow the 2D node")
	var crack:Texture2D = load("res://Images/Status/BlockDamage/destroy_stage_7.png")
	block.set_cracks(crack)
	var material:ShaderMaterial = block.surface_material(0)
	check(bool(material.get_shader_parameter("cracked")) and material.get_shader_parameter("crack_tex") == crack,"cracks are multiplied onto the block faces in the shader")
	block.set_alpha(0.4)
	check(is_equal_approx(float(material.get_shader_parameter("fade")),0.4) and block.mesh_instance().visible,"materializing uses the pixel dissolve")
	block.set_alpha(1.0)
	check(is_equal_approx(float(material.get_shader_parameter("fade")),1.0) and bool(material.get_shader_parameter("cracked")),"solid again keeps its cracks")
	block.set_cracks(null)
	check(not bool(material.get_shader_parameter("cracked")),"clearing cracks")
	host.visible = false
	await process_frame
	check(not block.mesh_instance().visible and not block.shadow_instance().visible,"hidden obstacle hides its block and shadow")
	host.visible = true
	await process_frame
	check(block.mesh_instance().visible and block.shadow_instance().visible,"shown again")
	block.set_model(&"cactus")
	await process_frame
	check(is_instance_valid(block.mesh_instance()) and block.mesh_instance() != mesh_node and (not is_instance_valid(mesh_node) or mesh_node.is_queued_for_deletion()),"changing model rebuilds the mesh")
	check(int(renderer.get_meta(RENDERER.USERS_META)) == 1 and renderer.visible,"rebuilding keeps exactly one renderer user")
	var rebuilt:MeshInstance3D = block.mesh_instance()
	host.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(rebuilt),"freeing the obstacle removes its 3D mesh")
	check(int(renderer.get_meta(RENDERER.USERS_META)) == 0 and not renderer.visible and renderer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"no blocks left: the overlay stops rendering")
	print("MC BLOCK 3D: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
