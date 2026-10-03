extends SceneTree
## Real World/physics regression plus an isolated GPU ground-layer fixture.
var checks:int = 0
var failures:int = 0
var world:Node
var cube:Node2D
var center:Vector2
var PAIRS:Script
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func fighter(name_key:String,point:Vector2,sulfur:bool = false) -> Node2D:
	var unit:Node2D = load("res://scenes/characters/我的世界/硫方怪.tscn" if sulfur else "res://scenes/ball.tscn").instantiate()
	unit.name = name_key
	unit.Team = "Team0" if sulfur else "Team1"
	unit.position = point
	if not sulfur: unit.get_node("CharacterAutoFit").enabled = false
	world.add_child(unit)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.get_body_motion().set_physics_process(false)
	unit.Max_health = 2000
	unit.default_properties.Max_health = 2000
	unit.health = 2000
	if not sulfur:
		unit.scale = Vector2.ONE
		var shape := CircleShape2D.new()
		shape.radius = 3.0
		unit.collision_shape_2d.shape = shape
	return unit
func sweep(unit:Node2D,start:Vector2,motion:Vector2) -> Object:
	var original:Vector2 = unit.global_position
	unit.global_position = start
	unit.force_update_transform()
	await physics_frame
	var collision:KinematicCollision2D = unit.move_and_collide(motion)
	unit.global_position = original
	unit.force_update_transform()
	return collision.get_collider() if collision != null else null
func crowd(units:Array) -> Array[Vector2]:
	var before:Array[Vector2] = []
	for unit:Node2D in units:
		before.append(unit.global_position)
		unit.set_large_battle_performance_mode(true)
	for unit:Node2D in units: unit.get_body_motion().separate_overlaps()
	var displacement:Array[Vector2] = []
	for i:int in range(units.size()): displacement.append(units[i].global_position-before[i])
	return displacement
func color_rect(parent:Node,rect:Rect2,color:Color,z:int) -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	node.color = color
	node.z_as_relative = false
	node.z_index = z
	parent.add_child(node)
	return node
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("SULFUR_CONTACT_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("sulfur_contact_settings.json")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	PAIRS = load("res://classes/body_collision_exclusions.gd")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"honey preloads complete")
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	center = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	cube = fighter("HoneySource",center,true)
	var victim:Node2D = fighter("HoneyVictim",center+Vector2(6,0))
	var third:Node2D = fighter("UnrelatedFighter",center+Vector2(0,55),true)
	third.Team = "Team2"
	var mask_before:int = victim.collision_mask
	var layer_before:int = victim.collision_layer
	cube.set_block(cube.Block.HONEY)
	cube._pull_touching_enemies(0.1)
	await physics_frame
	check(cube.get_collision_exceptions().has(victim) and victim.get_collision_exceptions().has(cube),"honey excludes both directions of ONLY the adhering pair")
	check(not victim.get_collision_exceptions().has(third) and not cube.get_collision_exceptions().has(third),"other characters retain physical collision")
	check(victim.collision_mask == mask_before and victim.collision_layer == layer_before,"no global collision layer or mask is cleared")
	for n:int in range(3): await physics_frame
	var through_cube := Transform2D(0.0,center+Vector2(-25,0))
	check(await sweep(victim,through_cube.origin,Vector2(50,0)) == null,"real physics sweep passes through the adhering source")
	var reach_to_third:float = victim.get_crowd_separation_radius_world()+third.get_crowd_separation_radius_world()+10.0
	check(await sweep(victim,third.global_position-Vector2.DOWN*reach_to_third,Vector2.DOWN*reach_to_third) == third,"real physics sweep still collides with an unrelated character")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8,45)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(75,0)
	await physics_frame
	check(await sweep(victim,center+Vector2(45,0),Vector2(50,0)) == wall,"adhered victim still collides with solid terrain")
	var hp:float = victim.health
	victim.receive_positional_damage(17.0,center,true,cube)
	check(is_equal_approx(hp-victim.health,17.0) and not victim.get_node("hurtbox/CollisionShape2D").disabled,"adhesion preserves hurt detection and damage, not invulnerability")
	var correction:Array[Vector2]=crowd([cube,victim])
	check(correction[0].is_zero_approx() and correction[1].is_zero_approx(),"large-battle body correction honors the adhering pair")
	third.global_position = center+Vector2(0,5)
	await physics_frame
	correction=crowd([cube,victim,third])
	check(not correction[2].is_zero_approx(),"large-battle body correction remains enabled against third parties")
	third.global_position = center+Vector2(0,75)
	victim.global_position = center+Vector2(40,0)
	cube._pull_touching_enemies(0.1)
	check(not PAIRS.are_excluded(cube,victim) and await sweep(victim,through_cube.origin,Vector2(50,0)) == cube,"escape releases the pair and restores actual physical blocking")
	victim.global_position = center+Vector2(6,0)
	cube._pull_touching_enemies(0.1)
	cube.set_block(cube.Block.EMPTY)
	check(not victim.get_collision_exceptions().has(cube),"changing form releases honey collision exclusions immediately")
	preload("res://classes/body_collision_exclusions.gd").add_exception(cube,victim)
	var holder_a := Node.new()
	var holder_b := Node.new()
	world.add_child(holder_a)
	world.add_child(holder_b)
	PAIRS.acquire(cube,victim,holder_a)
	PAIRS.acquire(cube,victim,holder_b)
	PAIRS.release(cube,victim,holder_a)
	check(PAIRS.are_excluded(cube,victim),"one lease owner cannot release another owner's exclusion")
	holder_b.free()
	check(not cube.get_meta(PAIRS.META,{}).has(victim.get_instance_id()) and cube.get_collision_exceptions().has(victim) and not victim.get_collision_exceptions().has(cube),"holder teardown clears owned exceptions but preserves preexisting external exceptions")
	preload("res://classes/body_collision_exclusions.gd").remove_exception(cube,victim)
	holder_a.free()
	var other_cube:Node2D = fighter("SecondHoneySource",center+Vector2(0,2),true)
	cube.set_block(cube.Block.HONEY)
	other_cube.set_block(other_cube.Block.HONEY)
	cube._pull_touching_enemies(0.1)
	other_cube._pull_touching_enemies(0.1)
	cube.set_block(cube.Block.EMPTY)
	check(not victim.get_collision_exceptions().has(cube) and victim.get_collision_exceptions().has(other_cube),"two honey sources maintain independent source-victim pairs")
	other_cube.free()
	check(not victim.has_meta(PAIRS.META),"source deletion releases the surviving victim without metadata residue")
	cube.set_block(cube.Block.HONEY)
	var removed:Node2D = fighter("RemovedVictim",center+Vector2(-5,0))
	cube._pull_touching_enemies(0.1)
	var removed_id:int = removed.get_instance_id()
	removed.free()
	cube._sync_honey_collision_pairs()
	var remaining:Dictionary = cube.get_meta(PAIRS.META) if cube.has_meta(PAIRS.META) else {}
	check(not remaining.has(removed_id),"victim deletion prunes the pair before its PhysicsBody is freed")
	cube.set_block(cube.Block.AMETHYST)
	victim.global_position = center+Vector2(130,0)
	third.global_position = center+Vector2(130,30)
	cube.image.scale = Vector2.ONE*cube.MODEL_IMAGE_SCALE
	cube._random.seed = 8675309
	var counts:Dictionary = {}
	var roots:Dictionary = {}
	var clustered:bool = false
	var bounded:bool = true
	var unclipped:bool = true
	var camera:Camera3D = cube._model_viewport.get_node("ModelCamera")
	for round_id:int in range(64):
		cube._roll_crystal_layout()
		cube._native_model.animate(0.0,0.3,true,0.0)
		var count:int = cube.crystal_layout.size()/2
		counts[count] = true
		bounded = bounded and count >= cube.CRYSTAL_COUNT_MIN and count <= cube.CRYSTAL_COUNT_MAX
		var sides:Dictionary = {}
		for i:int in range(count):
			var root3:Vector3 = cube.crystal_layout[i*2]
			var tip3:Vector3 = cube.crystal_layout[i*2+1]
			roots[str(root3)] = true
			var sector:int = posmod(roundi(Vector2(tip3.x,tip3.y).angle()/(TAU/4.0)),4)
			if sides.has(sector): clustered = true
			sides[sector] = true
			for phase:float in [0.0,0.25/1.15,0.75/1.15]:
				cube._native_model.animate(phase,0.0,true,0.0)
				var pixel:Vector2 = camera.unproject_position(cube._native_model.crystal_tip_world(i))
				unclipped = unclipped and Rect2(Vector2.ONE*2,Vector2(cube._model_viewport.size)-Vector2.ONE*4).has_point(pixel)
	check(bounded and counts.size() >= 4,"seeded 64-growth sample varies crystal count within 3..8")
	check(roots.size() > 100 and clustered,"random root positions vary freely and multiple crystals occupy the same direction")
	check(unclipped,"all sampled random tips remain inside the viewport at neutral and both maximum squish poses")
	cube.crystal_layout = PackedVector3Array([Vector3(0.4,-0.1,0.4),Vector3(1.70,0.12,1.1),Vector3(0.4,0.1,0.4),Vector3(1.73,0.16,1.1),Vector3(-0.4,0,0.4),Vector3(-1.70,0,1.1)])
	var before_grow:float = victim.health
	victim.global_position = center
	cube._pulse_contact()
	check(victim.health == before_grow and cube.get_ai_attack_threats(null).is_empty(),"new layout stays harmless throughout the 0.24-second growth")
	cube._native_model.animate(0.0,0.3,true,0.0)
	var tips:Array[Vector2] = cube._crystal_tip_points()
	victim.global_position = (tips[0]+tips[1])*0.5
	hp = victim.health
	var damage:float = ceilf(cube.attack_damage(cube.AMETHYST_CONTACT_MULT))
	cube._pulse_contact()
	check(is_equal_approx(hp-victim.health,damage*2.0),"two overlapping crystals independently damage the same enemy in one scan")
	check(cube.get_ai_attack_threats(victim).size() == 1 and cube.get_ai_attack_threats(null).size() == 3,"receiver-aware threats exclude spent hits while global display retains other-enemy threats")
	hp = victim.health
	for i:int in range(20):
		cube._clock += 1.0
		cube._pulse_contact()
	check(victim.health == hp,"remaining against the same crystals does not repeat damage, even after the old shared cooldown")
	victim.global_position = tips[2]
	cube._pulse_contact()
	check(is_equal_approx(hp-victim.health,damage),"a third crystal still damages immediately, independent of prior crystals")
	hp = victim.health
	victim.global_position = center+Vector2(130,0)
	cube._pulse_contact()
	victim.global_position = tips[0]
	cube._pulse_contact()
	check(victim.health == hp,"one generated crystal hits a given enemy once until the next growth")
	third.global_position = (tips[0]+tips[1])*0.5
	hp = third.health
	cube._pulse_contact()
	check(is_equal_approx(hp-third.health,damage*2.0),"the same crystals have independent hit histories for different enemies")
	victim.global_position = center+Vector2(130,0)
	third.global_position = center+Vector2(130,30)
	var old_layout:PackedVector3Array = cube.crystal_layout.duplicate()
	cube.crystals_out = true
	cube._crystal_timer = 0.01
	cube.tick_physics(cube.State.Stand,0.05)
	check(not cube.crystals_out and cube.crystal_layout != old_layout and cube._crystal_hits.is_empty(),"regrowth rerolls quantity/positions and resets each crystal's hit history")
	world._large_battle_mode_active = false
	# Fixture uses actual trail/crack scripts with a deliberately high-z parent.
	# The colored polygons are test occluders, not shipped replacement MC art.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96,96)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fixture := Node2D.new()
	fixture.z_index = 250
	viewport.add_child(fixture)
	color_rect(fixture,Rect2(0,0,96,96),Color(0.1,0.1,0.1),-5)
	color_rect(fixture,Rect2(8,8,20,20),Color.RED,-2)
	color_rect(fixture,Rect2(38,8,20,20),Color.GREEN,0)
	color_rect(fixture,Rect2(68,8,20,20),Color.BLUE,2)
	var trail:Node2D = cube.ICE_TRAIL.new()
	fixture.add_child(trail)
	trail.setup(cube,Rect2(0,0,96,96))
	trail.set_physics_process(false)
	trail.age = 3.0
	trail._physics_process(0.0)
	check(not trail.z_as_relative and trail.z_index == -4 and trail._crack.z_as_relative and trail._crack.z_index == 0,"ice and cracks use the absolute ground overlay layer, independent of parent z")
	if DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw(false)
		var image:Image = viewport.get_texture().get_image()
		check(image.get_pixel(18,18).is_equal_approx(Color.RED),"GPU: obstacle occludes ice and cracks")
		check(image.get_pixel(48,18).is_equal_approx(Color.GREEN),"GPU: character layer occludes ice and cracks")
		check(image.get_pixel(78,18).is_equal_approx(Color.BLUE),"GPU: projectile layer occludes ice and cracks")
		var blue_pixels:int = 0
		for y:int in range(35,96):
			for x:int in range(96):
				var pixel:Color = image.get_pixel(x,y)
				if pixel.b > 0.2 and pixel.b > pixel.r+0.05: blue_pixels += 1
		check(blue_pixels > 500,"GPU: uncovered blue ice remains visible above the map floor")
		print("SULFUR_LAYER_GPU_PNG_B64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
	else: print("SKIP: GPU layer pixels require a real renderer")
	trail._break_tile()
	var ground_fragments:bool = false
	for effect:Node in get_nodes_in_group("MCBlockFragments"):
		if effect.z_layer == -4: ground_fragments = true
	check(ground_fragments,"melting ice reuses ground-layer block fragments instead of covering actors")
	viewport.queue_free()
	cube.set_block(cube.Block.HONEY)
	victim.global_position = cube.global_position+Vector2(5,0)
	cube._pull_touching_enemies(0.1)
	cube.Die()
	check(not victim.get_collision_exceptions().has(cube),"source death immediately restores honey pair collision")
	world.queue_free()
	await process_frame
	await process_frame
	# Let deferred native audio/particle teardown finish before resource-cache shutdown.
	await create_timer(0.25,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SULFUR_CONTACTS: %d checks / %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
