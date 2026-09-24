extends "res://tests/test_mc_frontier.gd"
## Layer-to-bush mapping and the 21-cell (5x5 minus four corners) occlusion.
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
	check(canopy.top_level and not canopy.z_as_relative and canopy.z_index > moss.image.z_index and canopy.z_index > 101,"both bush variants render above ground, fighters and elytra")
	check(canopy.AZALEA.get_size() == Vector2(16,22) and canopy.FLOWERING.get_size() == Vector2(16,22) and canopy.AZALEA != canopy.FLOWERING,"nonflowering and flowering native-texture bushes are distinct real assets")
	var cells:Dictionary = canopy._canopy_cells()
	var two_cell:Vector2i = moss.cell_at(two)
	var three_cell:Vector2i = moss.cell_at(three)
	check(cells.size() == 2 and cells.has(two_cell) and cells.has(three_cell) and not cells.has(moss.cell_at(origin)),"one layer stays bare; two and three gain their canopies")
	var fx_source:String = FileAccess.get_file_as_string("res://scripts/characters/我的世界/frontier/fx.gd")
	var moss_draw:String = fx_source.split("func _draw_moss")[1].split("func _draw_sword")[0]
	check(moss_draw.count("draw_texture_rect(MOSS,") == 2 and not moss_draw.contains("for layer:"),"all moss depths draw one ground tile, with one preview at most")
	check(BUSH.shades_cell(two_cell,two_cell) and BUSH.shades_cell(two_cell,two_cell+Vector2i(2,1)) and BUSH.shades_cell(two_cell,two_cell+Vector2i(-1,-2)),"center and 5x5 edges fade")
	check(not BUSH.shades_cell(two_cell,two_cell+Vector2i(2,2)) and not BUSH.shades_cell(two_cell,two_cell+Vector2i(-2,-2)) and not BUSH.shades_cell(two_cell,two_cell+Vector2i(3,0)),"all four 5x5 corner cells and out-of-range cells are excluded")
	check(not canopy._faded_cells(cells).has(two_cell) and not canopy._faded_cells(cells).has(three_cell),"distant bushes keep full alpha")
	var walker:Node2D = dummy(two)
	check(canopy._faded_cells(cells).has(two_cell) and not canopy._faded_cells(cells).has(three_cell),"fighter occludes only nearby bush")
	canopy._process(0.0)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),1.0),"entering shade starts from full alpha instead of snapping translucent")
	var fade_time:float = canopy.opacity_transition_time
	canopy._process(fade_time*0.25)
	var quarter:float = canopy._alpha_for_cell(two_cell)
	game.now_stop_state = true
	canopy._process(fade_time)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),quarter),"global pause freezes in-flight canopy opacity")
	game.now_stop_state = false
	canopy._process(fade_time*0.25)
	var halfway:float = canopy._alpha_for_cell(two_cell)
	check(quarter > halfway and halfway > canopy.nearby_alpha and 1.0-quarter > quarter-halfway,"normal azalea fades quickly then slows down")
	check(is_equal_approx(canopy._alpha_for_cell(three_cell),1.0),"distant flowering azalea stays opaque while its neighbor fades")
	canopy._process(fade_time)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),canopy.nearby_alpha),"normal azalea reaches exact nearby opacity")
	walker.global_position = two+Vector2(48,48)
	check(not canopy._faded_cells(cells).has(two_cell),"diagonal corner does not fade")
	canopy._process(0.0)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),canopy.nearby_alpha),"leaving shade does not snap back to opaque")
	canopy._process(fade_time*0.25)
	var return_quarter:float = canopy._alpha_for_cell(two_cell)
	canopy._process(fade_time*0.25)
	var return_half:float = canopy._alpha_for_cell(two_cell)
	check(return_quarter > canopy.nearby_alpha and return_half > return_quarter and return_half < 1.0 and return_quarter-canopy.nearby_alpha > return_half-return_quarter,"returning to full opacity also eases out")
	walker.global_position = two+Vector2(48,24)
	check(canopy._faded_cells(cells).has(two_cell),"edge-neighbor fighter fades")
	canopy._process(0.0)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),return_half),"re-entering mid-transition retains the current alpha")
	canopy._process(fade_time*0.1)
	check(canopy._alpha_for_cell(two_cell) < return_half,"re-entering reverses smoothly toward nearby opacity")
	walker.free()
	canopy._process(0.0)
	canopy._process(fade_time)
	check(is_equal_approx(canopy._alpha_for_cell(two_cell),1.0),"clearing the fighter restores normal azalea opacity")
	var projectile:=Area2D.new()
	world.add_child(projectile)
	projectile.add_to_group("AllayExtendedProjectile")
	projectile.global_position = three
	check(canopy._faded_cells(cells).has(three_cell),"non-ball projectile fades flowering bush")
	canopy._process(0.0)
	check(is_equal_approx(canopy._alpha_for_cell(three_cell),1.0),"flowering azalea also avoids instant transparency changes")
	canopy._process(fade_time*0.25)
	var flower_partial:float = canopy._alpha_for_cell(three_cell)
	check(flower_partial < 1.0 and flower_partial > canopy.nearby_alpha and is_equal_approx(canopy._alpha_for_cell(two_cell),1.0),"flowering azalea fades independently of other cells")
	projectile.visible = false
	check(not canopy._faded_cells(cells).has(three_cell),"hidden projectile does not keep bush translucent")
	canopy._process(0.0)
	check(is_equal_approx(canopy._alpha_for_cell(three_cell),flower_partial),"hidden projectile starts a smooth return from current opacity")
	canopy._process(fade_time)
	check(is_equal_approx(canopy._alpha_for_cell(three_cell),1.0),"flowering azalea returns to exact full opacity")
	projectile.free()
	var object_sprite:=Sprite2D.new()
	world.add_child(object_sprite)
	object_sprite.texture = canopy.AZALEA
	object_sprite.add_to_group("BattleTransient")
	object_sprite.global_position = two
	check(canopy._faded_cells(cells).has(two_cell),"visible world objects also fade canopy")
	object_sprite.free()
	var audio:=AudioStreamPlayer2D.new()
	world.add_child(audio)
	audio.add_to_group("BattleTransient")
	audio.global_position = three
	check(not canopy._faded_cells(cells).has(three_cell),"audio-only objects do not create phantom transparency")
	audio.free()
	var mirror:Node2D = actor("苔藓",center+Vector2(0,250))
	mirror.accept_visual(moss.visual_state())
	check(mirror.get_node("MossAzaleaCanopy")._canopy_cells().size() == 2,"remote snapshot immediately has same 2/3 layer bushes")
	mirror.patches.clear()
	moss.patches[1].layers = 1
	canopy._process(0.0)
	check(not canopy._canopy_cells().has(two_cell) and canopy._canopy_cells().has(three_cell),"consumed layer removes azalea without leaving visual ghosts")
	check(not canopy._alpha_states.has(two_cell),"consumed azalea releases its opacity state")
	moss.health = 0
	canopy._process(0.0)
	check(not canopy.visible and canopy._alpha_states.is_empty(),"owner death immediately hides canopies and clears opacity states")
	print("MC AZALEA/STAT CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures == 0 else 1)
