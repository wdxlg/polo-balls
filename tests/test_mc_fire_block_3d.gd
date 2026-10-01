extends "res://tests/test_mc_frontier.gd"
## 原版 3D 地面火方块：几何对照原版模型 JSON、普通/灵魂贴图、共享透视通道、显隐与清理。不需要 GPU。
const BLOCK = preload("res://scripts/effects/我的世界/mc_fire_block_3d.gd")
const FIRE_PATH:String = "res://scripts/effects/我的世界/烈焰火场.gd"
const TORCH_FIRE_PATH:String = "res://scripts/characters/我的世界/torch/torch_fire.gd"

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var source:Node2D = actor("烈焰人",center+Vector2(-180,0))
	var fire:Node2D = load(FIRE_PATH).new()
	world.add_child(fire)
	fire.setup(source,"Team0",center+Vector2(3,5),34.0,4.5,0.5,0.11,2.2,0.05)
	fire.set_physics_process(false)
	var block:Node2D = fire._fire_block
	check(block != null and block.get_script() == BLOCK and not block.soul,"Blaze ground fire uses the shared native 3D fire block")
	check(fire.find_children("*","AnimatedSprite2D",true,false).is_empty(),"no flat 2D fire sprite remains on the ground fire")
	var cell:Rect2 = fire._fire_cell_rect
	check(block.block_rect.is_equal_approx(cell),"block footprint is exactly the fire's map cell")
	var node:MeshInstance3D = block.mesh_instance()
	var view:Node2D = block.renderer()
	check(node != null and view != null and node.get_parent() == view.viewport,"geometry lives in the shared 3D overlay viewport")
	check(view.get_script() == BLOCK.WALL_RENDERER and view.get_parent() == world,"overlay reuses the map wall renderer and camera under the world")
	check(not view.z_as_relative and view.z_index == 92 and view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"overlay draws at ground-fire depth and renders while fire exists")
	check(node.position.is_equal_approx(Vector3(cell.position.x,0.0,cell.position.y)) and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"mesh origin is the cell's ground corner and casts no shadow")
	_check_model(node.mesh,cell.size)
	_check_materials(block,BLOCK.FIRE_TEXTURES)
	_check_animation(block)
	fire.hide()
	check(not node.visible,"hiding the ground fire hides its 3D block")
	fire.show()
	check(node.visible,"showing the ground fire shows its 3D block again")
	var twin:Node2D = load(FIRE_PATH).new()
	world.add_child(twin)
	twin.setup(source,"Team0",center+Vector2(3,5),20.0,4.5,0.5,0.11,2.2,0.05)
	twin.set_physics_process(false)
	var same:PackedVector3Array = twin._fire_block.mesh_instance().mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(same == node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"model variant is chosen by the cell only (same cell -> same native variant)")
	check(twin._fire_block.renderer() == view and int(view.get_meta(BLOCK.USERS_META)) == 2,"all ground fires share one overlay renderer")
	twin.free()
	check(int(view.get_meta(BLOCK.USERS_META)) == 1 and view.visible,"removing one fire keeps the shared renderer for the others")
	var torch_fire:Node2D = load(TORCH_FIRE_PATH).new()
	world.add_child(torch_fire)
	torch_fire.setup_torch(source,7,center+Vector2(-60,40),true,20.0,4.0,0.2,2.0,0.1)
	torch_fire.set_physics_process(false)
	var soul_block:Node2D = torch_fire._fire_block
	check(soul_block != null and soul_block.soul and soul_block.renderer() == view,"soul fire uses the same shared 3D block path")
	_check_materials(soul_block,BLOCK.SOUL_FIRE_TEXTURES)
	var soul_node:MeshInstance3D = soul_block.mesh_instance()
	torch_fire.extinguish(0.0)
	torch_fire._physics_process(0.01)
	check(torch_fire.is_queued_for_deletion(),"extinguished soul fire still expires through the normal lifetime")
	fire.free()
	await process_frame
	await process_frame
	check(not is_instance_valid(node) and not is_instance_valid(soul_node),"freed fires release their 3D meshes")
	check(int(view.get_meta(BLOCK.USERS_META)) == 0 and not view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"no fire left: the shared overlay stops rendering")
	print("MC FIRE BLOCK 3D: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)

func _check_model(mesh:Mesh,size:Vector2) -> void:
	var tall:float = minf(size.x,size.y)/16.0
	var vertices:int = 0
	var tilted:int = 0
	var upright:int = 0
	for surface:int in range(mesh.get_surface_count()):
		var arrays:Array = mesh.surface_get_arrays(surface)
		vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for normal:Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			if absf(normal.y-sin(PI/8.0)) < 0.002: tilted += 1
			elif absf(normal.y) < 0.002: upright += 1
	# fire_floor: 4 one-sided quads; 4 edge planes x (south + north faces): 8 quads; 6 vertices per quad.
	check(vertices == 72,"native fire model = 4 floor quads + 8 edge faces (%d vertices)" % vertices)
	check(tilted == 24,"the four fire_floor planes lean 22.5 degrees and face upward (%d)" % tilted)
	check(upright == 48,"the four fire_side planes stand upright on the block edges (%d)" % upright)
	var aabb:AABB = mesh.get_aabb()
	var lean:float = 0.8*tan(PI/8.0)
	check(absf(aabb.position.x) < 0.01 and absf(aabb.position.z) < 0.01 and absf(aabb.size.x-size.x) < 0.01 and absf(aabb.size.z-size.y) < 0.01,"model spans exactly one block on the ground plane")
	check(absf(aabb.position.y+lean*tall) < 0.01 and absf(aabb.end.y-(22.4+lean)*tall) < 0.01,"heights follow template_fire_floor/side: 22.4 px of 16 plus the rescaled 22.5-degree lean")

func _check_materials(block:Node2D,expected:Array[Texture2D]) -> void:
	var strips:Array[int] = block.surface_texture_indices()
	var ok:bool = not strips.is_empty() and block.mesh_instance().mesh.get_surface_count() == strips.size()
	for surface:int in range(strips.size()):
		var material:StandardMaterial3D = block.surface_material(surface)
		ok = ok and material.albedo_texture == expected[strips[surface]]
		ok = ok and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		ok = ok and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and material.cull_mode == BaseMaterial3D.CULL_BACK
		ok = ok and is_equal_approx(material.uv1_scale.y,1.0/32.0)
	check(ok,"%s strips: unshaded native cutout pixels, one 1/32 animation row per surface" % expected[0].resource_path.get_file())

func _check_animation(block:Node2D) -> void:
	block.frame = 0
	block._frame_time = 0.0
	block.play()
	block._process(0.051)
	check(block.frame == 1 and block.frame_row(0) == 17 and block.frame_row(1) == 1,"20 fps: *_0 advances through mcmeta order 16.., *_1 in order")
	var strips:Array[int] = block.surface_texture_indices()
	var ok:bool = true
	for surface:int in range(strips.size()):
		ok = ok and is_equal_approx(block.surface_material(surface).uv1_offset.y,float(block.frame_row(strips[surface]))/32.0)
	check(ok,"material rows follow the current animation frame")
	block.pause()
	block._process(1.0)
	check(block.frame == 1,"paused block keeps its frame")
	block.play()
