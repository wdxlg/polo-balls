extends "res://tests/test_mc_frontier.gd"
## Layer-to-plant mapping: 2 = azalea, 3 = flowering azalea, never grass; plants sit under characters.
const BUSH = preload("res://scripts/characters/我的世界/frontier/moss_azalea.gd")

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(70.0).timeout.connect(func(): finish(2))
	var w:Node2D = actor("监守者",center+Vector2(300,-180))
	var bat:Node2D = actor("蝙蝠",center+Vector2(320,-40))
	await physics_frame
	var original_root_scale:Vector2 = Vector2(0.2,0.2) # Inherited from the original scenes/ball.tscn.
	check(w.scale == original_root_scale and w.image.scale == Vector2.ONE and w.image.texture == w.SHRIEKER,"Shrieker restores its original body and pixel size")
	check(w.collision_shape_2d.shape.size == Vector2(96,74) and w.collision_shape_2d.global_scale == original_root_scale,"dormant Shrieker collision geometry remains original")
	var top_image:Image = w.SHRIEKER.get_image()
	check(top_image.get_size() == Vector2i(128,128) and top_image.get_pixel(55,25).a > 0.9 and top_image.get_pixel(64,70).a > 0.9,"raised Shrieker rim and inner surface both retain complete native material")
	w.form = w.Form.EMERGING
	w.form_left = 0.0 # Last emerging frame should visually meet the first idle frame.
	w.visual_mob()
	check(w.image.scale == Vector2(1.4,1.4) and w.image.texture.get_size() == Vector2(192,240),"emerging Warden frames already match its awakened visual size")
	var emerging_height:float = w.image.texture.get_image().get_used_rect().size.y*w.image.scale.y
	w.form = w.Form.AWAKE
	w.visual_mob()
	await physics_frame
	check(w.scale == original_root_scale and w.image.scale == Vector2(1.4,1.4) and w.image.texture.get_size() == Vector2(192,240),"only fully awakened Warden artwork is 1.4x its original pixels")
	var idle_height:float = w.image.texture.get_image().get_used_rect().size.y*w.image.scale.y
	check(absf(emerging_height-idle_height)<10.0,"end of emergence and awake idle match in actual visible model height")
	check(w.collision_shape_2d.shape.size == Vector2(126,170) and w.collision_shape_2d.global_scale == original_root_scale,"Warden physical geometry does not inherit an extra root zoom")
	w.form = w.Form.BURROWING
	w.form_left = 1.8 # First digging frame should visually meet the last idle frame.
	w.visual_mob()
	check(w.image.scale == Vector2(1.4,1.4) and w.image.texture.get_size() == Vector2(192,240),"burrowing Warden frames do not shrink before turning into a Shrieker")
	check(absf(float(w.image.texture.get_image().get_used_rect().size.y)*w.image.scale.y-idle_height)<10.0,"start of digging matches the awake idle model height")
	w.form = w.Form.DORMANT
	w.visual_mob()
	await physics_frame
	check(w.image.scale == Vector2.ONE and w.collision_shape_2d.shape.size == Vector2(96,74),"returning Shrieker is still original size")
	check(bat.initial_bat_health == 70 and bat.Max_health == 70 and bat.health == 70,"bat scene starts at 70 HP")
	check(bat.living_members().size() == 5 and totals(bat) == Vector2i(350,350),"five bats and their split capacity all use 70 HP")
	var moss:Node2D = actor("苔藓",center+Vector2(-450,220))
	var origin:Vector2 = Vector2(moss.cell_at(moss.global_position))*moss.CELL
	moss.global_position = origin
	var two:Vector2 = origin+Vector2(120,0)
	var three:Vector2 = origin+Vector2(240,0)
	moss.patches.assign([{"point":origin,"layers":1,"serial":1},{"point":two,"layers":2,"serial":2},{"point":three,"layers":3,"serial":3}])
	var canopy:Node2D = moss.get_node("MossAzaleaCanopy")
	var two_cell:Vector2i = moss.cell_at(two)
	var three_cell:Vector2i = moss.cell_at(three)
	var origin_cell:Vector2i = moss.cell_at(origin)
	canopy._process(0.0)
	var plants:Dictionary = canopy._plant_cells()
	check(plants.size() == 2 and plants[two_cell] == BUSH.AZALEA and plants[three_cell] == BUSH.FLOWERING and not plants.has(origin_cell),"one layer has no plant; deeper moss grows azalea, then flowering azalea, instead of stacking moss")
	check(BUSH.plant_for_layers(1) == &"" and BUSH.plant_for_layers(0) == &"" and not BUSH.MODELS_USED.has(&"short_grass"),"single-layer moss never grows grass")
	var bush:Node2D = canopy.plant_block(two_cell)
	var flowering:Node2D = canopy.plant_block(three_cell)
	check(is_instance_valid(bush) and bush.model == &"azalea" and is_instance_valid(bush.mesh_instance()) and is_equal_approx(bush.cell,moss.CELL),"azalea is a single-block 3D model")
	check(is_instance_valid(flowering) and flowering.model == &"flowering_azalea" and flowering.global_position.is_equal_approx(moss.point_for_cell(three_cell)),"flowering azalea stands on its own moss cell")
	var renderer:Node2D = bush.renderer()
	var RENDERER:Script = load("res://scripts/effects/我的世界/mc_block_3d_renderer.gd")
	check(is_instance_valid(renderer) and renderer == flowering.renderer() and renderer.name == RENDERER.node_name(RENDERER.CANOPY),"azalea plants share the canopy overlay")
	check(not renderer.z_as_relative and renderer.z_index > moss.frontier_fx.z_index and renderer.z_index > moss.z_index+36 and renderer.z_index < int(world.get("map_health_bar_z_index")),"azalea bushes draw above the moss ground and every character sprite, below health bars (z %d)" % renderer.z_index)
	check(renderer.shadow_picture.visible and not renderer.shadow_picture.z_as_relative and renderer.shadow_picture.z_index > moss.frontier_fx.z_index and renderer.shadow_picture.z_index < 0,"bush shadows fall on the moss ground, under the characters")
	var BLOCK3D:Script = load("res://scripts/effects/我的世界/mc_block_3d.gd")
	var table:Node2D = BLOCK3D.create(&"crafting_table",moss.CELL)
	world.add_child(table)
	check(table.renderer() != renderer and table.renderer().z_index == -4,"workbench-type blocks stay on the wall layer under characters")
	table.free()
	var fx_source:String = FileAccess.get_file_as_string("res://scripts/characters/我的世界/frontier/fx.gd")
	var moss_draw:String = fx_source.split("func _draw_moss")[1].split("func _draw_sword")[0]
	check(moss_draw.count("draw_texture_rect(MOSS,") == 2 and not moss_draw.contains("for layer:"),"all moss depths draw one ground tile, with one preview at most")
	check(is_equal_approx(bush.see_through,0.0) and is_equal_approx(float(bush.surface_material(0).get_shader_parameter("fade")),1.0),"bush with nobody nearby is fully solid")
	var ghost_layer:Node2D = bush.ghost_renderer()
	check(is_instance_valid(ghost_layer) and ghost_layer.name == RENDERER.node_name(RENDERER.SEE_THROUGH) and bush.ghost_instance().get_parent() == ghost_layer.viewport and not ghost_layer.visible,"see-through copy layer exists but does not render while nothing is near")
	var walker:Node2D = dummy(two)
	canopy._process(0.14)
	var mid:float = bush.see_through
	check(mid > 0.2 and mid < 1.0,"bush fades smoothly as a fighter approaches (%.2f)" % mid)
	canopy._process(0.3)
	check(is_equal_approx(bush.see_through,1.0) and is_equal_approx(float(bush.surface_material(0).get_shader_parameter("fade")),0.0) and is_equal_approx(float(bush.ghost_instance().get_surface_override_material(0).get_shader_parameter("fade")),1.0),"fighter in the bush: solid pixels removed, only the see-through copy remains")
	check(ghost_layer.visible and ghost_layer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and is_equal_approx(ghost_layer.picture.modulate.a,RENDERER.SEE_THROUGH_ALPHA) and ghost_layer.z_index > renderer.z_index and not ghost_layer.shadow_picture.visible,"see-through layer is real 40% translucency above the canopy, without a second shadow")
	check(is_equal_approx(float(bush.shadow_instance().get_surface_override_material(0).get_shader_parameter("fade")),1.0) and bush.shadow_instance().visible,"bush still casts its ground shadow while see-through")
	check(is_equal_approx(flowering.see_through,0.0),"far bush stays solid (%.2f)" % flowering.see_through)
	walker.free()
	canopy._process(0.3)
	canopy._process(0.3)
	check(is_equal_approx(bush.see_through,0.0) and is_equal_approx(float(bush.surface_material(0).get_shader_parameter("fade")),1.0),"bush returns to solid after the fighter leaves")
	check(not ghost_layer.visible and ghost_layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"see-through layer stops rendering when no bush is faded")
	var mirror:Node2D = actor("苔藓",center+Vector2(0,250))
	mirror.accept_visual(moss.visual_state())
	check(mirror.get_node("MossAzaleaCanopy")._plant_cells().size() == 2,"remote snapshot immediately has same 2/3 layer plants")
	mirror.patches.clear()
	moss.patches[1].layers = 1
	canopy._process(0.0)
	check(canopy.plant_block(two_cell) == null and canopy.plant_block(three_cell) == flowering,"consumed layer removes only that azalea, keeping the other block untouched")
	moss.patches[2].layers = 2
	canopy._process(0.0)
	check(canopy.plant_block(three_cell) == flowering and flowering.model == &"azalea","thinning a flowering bush swaps its model in place")
	moss.health = 0
	canopy._process(0.0)
	check(not canopy.visible and canopy.plant_block(three_cell) == null,"owner death immediately removes the plants")
	print("MC AZALEA/STAT CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures == 0 else 1)
