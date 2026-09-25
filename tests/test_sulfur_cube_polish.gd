extends SceneTree
## Actual physics contacts, shared telegraph contract and attached/fired model parity.
const PIXELS = preload("res://scripts/effects/我的世界/pixel_arc.gd")
var ABILITIES:Script
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func threat_count(analyzer:Node,kind:String) -> int:
	var result:int = 0
	for info:Dictionary in analyzer._debug_threats:
		if str(info.get("kind","")) == kind: result += 1
	return result
func obstacle(parent:Node,point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = point
	return body
func step(cube:Node,frames:int,state:int = 1) -> void:
	for i:int in range(frames):
		await physics_frame
		cube.tick_physics(state,1.0/60.0)
func run() -> void:
	ABILITIES = load("res://scripts/effects/我的世界/mc_combat_abilities.gd")
	create_timer(110.0,true,false,true).timeout.connect(func(): print("SULFUR_POLISH_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var cube:Node2D = load("res://scenes/characters/我的世界/硫方怪.tscn").instantiate()
	cube.position = center
	cube.Team = "Team0"
	world.add_child(cube,true)
	cube.state_machine.set_physics_process(false)
	cube.set_physics_process(false)
	cube.health = cube.Max_health
	var wall:StaticBody2D = obstacle(world,center+Vector2(55,0),Vector2(8,180))
	await physics_frame
	cube.set_block(cube.Block.ICE)
	cube.direction = Vector2.RIGHT
	cube._slide_velocity = Vector2.RIGHT*130.0
	var reflected:bool = false
	var hit_x:float = 0.0
	for i:int in range(85):
		await step(cube,1,cube.State.Move)
		if cube._slide_velocity.x < -20.0:
			reflected = true
			hit_x = cube.global_position.x
			break
	check(reflected,"ICE reflects persistent momentum at a real static wall")
	await step(cube,20,cube.State.Move)
	check(cube.global_position.x < hit_x-8.0 and cube.direction.x < 0.0,"ICE leaves wall instead of restoring the incoming heading and freezing")
	cube.player_control_peer_id = 1
	cube.global_position = center
	cube.player_control_direction = Vector2.RIGHT
	cube._slide_velocity = Vector2.RIGHT*130.0
	reflected = false
	for i:int in range(85):
		await step(cube,1,cube.State.Move)
		if cube._slide_velocity.x < -20.0:
			reflected = true
			hit_x = cube.global_position.x
			break
	await step(cube,7,cube.State.Move)
	check(reflected and cube.global_position.x < hit_x-3.0,"manual ICE retains a visible rebound even with input held into the wall")
	check(cube.player_control_direction == Vector2.RIGHT,"ice collision does not overwrite player input")
	cube.player_control_peer_id = 0
	var ceiling:StaticBody2D = obstacle(world,center+Vector2(0,-55),Vector2(180,8))
	cube.global_position = center
	cube.direction = Vector2(1,-1).normalized()
	cube._slide_velocity = cube.direction*130.0
	cube._ice_bounce_hold = 0.0
	reflected = false
	for i:int in range(110):
		await step(cube,1,cube.State.Move)
		if cube._slide_velocity.x < -10.0 and cube._slide_velocity.y > 10.0:
			reflected = true
			break
	check(reflected,"ICE resolves both real corner normals without sticking")
	wall.queue_free()
	ceiling.queue_free()
	await physics_frame
	var floor_body:StaticBody2D = obstacle(world,center+Vector2(0,65),Vector2(230,8))
	cube.global_position = center-Vector2(0,30)
	cube.set_block(cube.Block.IRON)
	cube.player_control_peer_id = 1
	cube.player_control_direction = Vector2.UP
	var before:Vector2 = cube.global_position
	await step(cube,16,cube.State.Move)
	check(cube.global_position.y > before.y+15.0,"IRON accelerates downward instead of flying upward with W")
	check(absf(cube.global_position.x-before.x) < 0.3,"IRON vertical-only input adds no horizontal drive")
	await step(cube,22,cube.State.Move)
	check(absf(cube.global_position.y-(center.y+61.0-cube.get_crowd_separation_radius_world())) < 1.0,"IRON lands on actual terrain and does not sink through it")
	before = cube.global_position
	cube.player_control_direction = Vector2.LEFT
	await step(cube,15,cube.State.Move)
	check(cube.global_position.x < before.x-5.0 and absf(cube.global_position.y-before.y) < 1.0,"IRON walks left along its support without upward drift")
	cube.global_position = center-Vector2(0,30)
	cube.clear_external_directional_gravity_velocity()
	cube.dizziness = true
	before = cube.global_position
	await step(cube,15,cube.State.Stand)
	check(cube.global_position.y > before.y+15.0 and absf(cube.global_position.x-before.x) < 0.5,"IRON keeps gravity while stunned/standing, with no voluntary drive")
	cube.dizziness = false
	before = cube.global_position
	game.now_stop_state = true
	await step(cube,5,cube.State.Move)
	check(cube.global_position.distance_to(before) < 0.01,"paused IRON does not advance gravity")
	game.now_stop_state = false
	cube.set_block(cube.Block.HONEY)
	check(not cube.is_external_directional_gravity_locomotion_enabled() and cube.get_external_directional_gravity_velocity().is_zero_approx(),"leaving IRON restores prior gravity mode and clears native falling momentum")
	floor_body.queue_free()
	cube.player_control_peer_id = 0
	cube.global_position = center
	cube.set_block(cube.Block.TNT)
	cube.set_process(false)
	cube._update_charge_circle()
	var circle:Node2D = cube._charge_circle
	check(is_instance_valid(circle) and circle.get_script() == ABILITIES.CHARGE_CIRCLE,"TNT obtains telegraph from the public combat-abilities entry")
	check(circle.progress == 0.0 and circle.fill_radius() == 0.0,"TNT charge begins with an empty interior")
	cube.fuse_left = cube.TNT_FUSE_SECONDS*0.5
	cube._update_charge_circle()
	check(is_equal_approx(circle.fill_radius(),cube.TNT_RADIUS*0.5) and circle.fill_color.a < circle.ring_color.a,"half fuse gives a half-radius low-opacity red pixel disk")
	cube.fuse_left = 0.001
	cube._update_charge_circle()
	check(absf(circle.fill_radius()-circle.radius) < 0.05,"charge disk reaches the exact outer radius at detonation time")
	check(circle.global_scale.distance_to(Vector2.ONE) < 0.001 and circle.global_position.distance_to(cube.global_position) < 0.001,"world-space circle is independent of the 0.2-scaled actor")
	check(is_equal_approx(cube.get_ai_attack_threats(null)[0].radius,circle.radius),"outer telegraph radius equals the actual TNT threat radius")
	check(not PIXELS.spans(40.0,0.0,TAU,80.0).is_empty(),"filled circle uses the existing cached pixel-span primitive")
	game.now_stop_state = true
	var paused_fuse:float = cube.fuse_left
	await step(cube,3,cube.State.Move)
	check(cube.fuse_left == paused_fuse,"pause freezes the fuse and therefore visual charge progress")
	game.now_stop_state = false
	cube._last_move_direction = Vector2.RIGHT
	cube.fuse_left = 0.0
	cube._detonate()
	check(not is_instance_valid(cube._charge_circle) and not circle.visible,"detonation immediately hides and releases the charge circle")
	cube.set_block(cube.Block.AMETHYST)
	cube.image.scale = Vector2.ONE*cube.MODEL_IMAGE_SCALE
	cube._native_model.animate(0.0,0.3,true,0.0)
	var body_model:Node3D = cube._native_model
	var tips:Array[Vector2] = cube._crystal_tip_points()
	var analyzer:Node2D = load("res://scripts/training/combat_threat_analyzer.gd").new()
	world.add_child(analyzer)
	analyzer.set_physics_process(false)
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	check(analyzer.visible and threat_count(analyzer,"sulfur_amethyst_crystal") == 4,"settings threat display discovers all four live crystal-tip regions without an RL receiver")
	cube._fire_all_crystals()
	var shards:Array[Node] = []
	for node:Node in get_nodes_in_group("AI_Hazard"):
		if node.get_script() == cube.SHARD:
			node.set_physics_process(false)
			shards.append(node)
	check(shards.size() == 4,"four original native crystal models detach as four projectiles")
	var match_pose:bool = shards.size() == 4
	for i:int in range(shards.size()):
		var attached:Node3D = body_model.crystal_layer.get_child(i)
		var shot:Node2D = shards[i] as Node2D
		match_pose = match_pose and shot.crystal.get_script() == attached.get_script()
		match_pose = match_pose and shot.crystal.global_transform.is_equal_approx(attached.global_transform)
		match_pose = match_pose and is_equal_approx(shot.crystal.length,attached.length) and is_equal_approx(shot.crystal.width,attached.width)
		match_pose = match_pose and shot.sprite.global_transform.is_equal_approx(cube.image.global_transform)
		match_pose = match_pose and shot.global_position.distance_to(tips[i]) < 0.01
	check(match_pose,"body and projectile share mesh, native texture, full squish pose, scale, camera and launch position")
	cube.crystals_out = true
	analyzer._physics_process(0.1)
	check(threat_count(analyzer,"sulfur_amethyst_crystal") == 0 and threat_count(analyzer,"sulfur_amethyst_shard") == 4,"after firing, threat display removes attached tips and follows all four real projectiles")
	cube.crystals_out = false
	check(not body_model.crystals_ready() and cube.get_ai_attack_threats(null).is_empty(),"regrowing crystals remain harmless while buried inside the body")
	body_model.animate(0.0,0.3,true,0.0)
	cube.player_control_peer_id = 1
	cube.crystals_out = false
	cube._crystal_timer = 0.01
	await step(cube,2,cube.State.Stand)
	check(not cube.crystals_out,"manual AMETHYST does not auto-fire when cooldown expires")
	cube.Attack()
	check(cube._surge_left > 0.0 and not cube.crystals_out,"manual left action preserves the existing amethyst surge")
	check(cube.player_control_action_ids() == [&"Attack",&"Skill",&"controlled_crystal_volley"],"amethyst keeps surge/change/volley in left/right/middle order")
	cube.player_control_action(2)
	check(cube.crystals_out,"manual middle action releases the existing four-crystal attack")
	# Remove the second volley before rendering, retain the first frozen sample.
	for node:Node in get_nodes_in_group("AI_Hazard"):
		if node.get_script() == cube.SHARD and not shards.has(node): node.queue_free()
	cube.crystals_out = false
	cube.set_process(false)
	body_model.animate(0.0,0.3,true,0.0)
	# Keep source pose exactly equal to the frozen launch snapshot for pixel parity.
	for i:int in range(4): body_model.crystal_layer.get_child(i).global_transform = shards[i].crystal.global_transform
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		var body_image:Image = cube._model_viewport.get_texture().get_image()
		body_image.save_png("user://sulfur_polish_body.png")
		print("SULFUR_POLISH_BODY_B64=",Marshalls.raw_to_base64(body_image.save_png_to_buffer()))
		analyzer._physics_process(0.1)
		RenderingServer.force_draw(false) # Exercise the actual enabled world overlay.
		body_model.outer_shell.hide()
		body_model.inner_block.hide()
		body_model.inner_shell.hide()
		for i:int in range(1,4): body_model.crystal_layer.get_child(i).hide()
		await process_frame
		RenderingServer.force_draw(false)
		var attached_image:Image = cube._model_viewport.get_texture().get_image()
		var fired_image:Image = shards[0].model_viewport.get_texture().get_image()
		var different:int = 0
		var visible_pixels:int = 0
		for y:int in range(attached_image.get_height()):
			for x:int in range(attached_image.get_width()):
				if attached_image.get_pixel(x,y).a > 0.1: visible_pixels += 1
				if attached_image.get_pixel(x,y) != fired_image.get_pixel(x,y): different += 1
		check(visible_pixels > 80 and different <= 4,"GPU: attached crystal and fired crystal render the same pixels in the same camera")
		print("CRYSTAL_PIXEL_PARITY visible=",visible_pixels," different=",different)
		print("SULFUR_POLISH_SHARD_B64=",Marshalls.raw_to_base64(fired_image.save_png_to_buffer()))
		var preview := SubViewport.new()
		preview.size = Vector2i(240,240)
		preview.transparent_bg = true
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(preview)
		var anchor := Node2D.new()
		preview.add_child(anchor)
		anchor.position = Vector2(120,120)
		anchor.scale = Vector2.ONE*0.2
		var indicator:Node2D = ABILITIES.charge_circle(anchor,80.0)
		indicator.set_charge(anchor.global_position,80.0,0.6)
		await process_frame
		RenderingServer.force_draw(false)
		var ring_image:Image = preview.get_texture().get_image()
		check(ring_image.get_pixel(120,120).a > 0.05 and ring_image.get_pixel(120,120).a < 0.3 and ring_image.get_pixel(120,40).a > 0.3,"GPU: translucent red fill and brighter stepped outer ring are both visible")
		print("SULFUR_POLISH_RING_B64=",Marshalls.raw_to_base64(ring_image.save_png_to_buffer()))
		preview.queue_free()
	for shard:Node in shards: shard.queue_free()
	await process_frame
	analyzer._physics_process(0.1)
	check(threat_count(analyzer,"sulfur_amethyst_shard") == 0,"deleted projectiles leave no old hazard regions")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"disabling threat display immediately hides and clears its cached geometry")
	cube.player_control_peer_id = 0
	cube.fuse_left = 0.0
	cube.set_block(cube.Block.TNT)
	cube._update_charge_circle()
	cube.health = 0
	cube._process(0.0)
	check(not is_instance_valid(cube._charge_circle),"death cleans up TNT telegraph with no stale circle")
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SULFUR_POLISH: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
