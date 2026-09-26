extends SceneTree
## Two-slot FIFO, real combined mechanics, manual controls and shared-viewport GPU checks.
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node
var cube:Node2D
var victim:Node2D
var C:Script
var center:Vector2
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",label)
func kinds() -> Dictionary:
	var result:Dictionary = {}
	for info:Dictionary in cube.get_ai_attack_threats(null): result[str(info.kind)] = true
	return result
func reset_block(mode:int = 0) -> void:
	cube.fuse_left = 0.0
	cube.set_block(C.Block.EMPTY)
	if mode != C.Block.EMPTY: cube.acquire_block(mode)
	cube._process(0.0)
func settle_model() -> void:
	cube._process(0.0)
	cube._native_model.animate(0.0,0.3,true,cube.fuse_left)
func has_frame(index:int,mode:int) -> bool:
	var frame:Node2D = cube._block_frames.get_child(index) as Node2D
	return frame.is_visible_in_tree() and frame.get_node("BlockIcon").visible and int(frame.get_meta("block_mode",0)) == mode and frame.get_node("BlockIcon").texture == C.MODEL.BLOCK_TEXTURES[mode]
func empty_frame(index:int) -> bool:
	var frame:Node2D = cube._block_frames.get_child(index) as Node2D
	var icon:Sprite2D = frame.get_node("BlockIcon") as Sprite2D
	return frame.is_visible_in_tree() and frame.get_node("Frame").visible and not icon.visible and icon.texture == null and int(frame.get_meta("block_mode",0)) == C.Block.EMPTY
func fighter(sulfur:bool,point:Vector2) -> Node2D:
	var unit:Node2D = load("res://scenes/characters/我的世界/硫方怪.tscn" if sulfur else "res://scenes/ball.tscn").instantiate()
	unit.Team = "Team0" if sulfur else "Team1"
	unit.position = point
	unit.get_node("CharacterAutoFit").enabled = false
	world.add_child(unit,true)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.set_deferred("monitoring",false)
	unit.Max_health = 10000
	unit.default_properties.Max_health = 10000
	unit.health = 10000
	return unit
func run() -> void:
	create_timer(100.0,true,false,true).timeout.connect(func(): print("SULFUR_DUAL_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	C = load("res://scripts/characters/我的世界/硫方怪.gd")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	center = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	cube = fighter(true,center)
	victim = fighter(false,center+Vector2(160,0))
	var tiny := CircleShape2D.new()
	tiny.radius = 2.0
	victim.collision_shape_2d.shape = tiny
	victim.get_node("hurtbox/CollisionShape2D").shape = tiny
	await physics_frame
	check(cube.block_slots.is_empty() and empty_frame(0) and empty_frame(1),"BOTH empty frames are visible immediately at spawn, without block icons")
	var frame_positions:PackedVector2Array = PackedVector2Array([cube._block_frames.get_child(0).position,cube._block_frames.get_child(1).position])
	game.now_stop_state = true
	cube._process(0.0)
	check(empty_frame(0) and empty_frame(1),"empty frames remain visible while combat is paused / before the first pickup")
	game.now_stop_state = false
	cube.acquire_block(C.Block.ICE)
	check(cube.block_slots == PackedInt32Array([C.Block.ICE]) and has_frame(0,C.Block.ICE) and empty_frame(1),"first pickup fills LEFT icon while the RIGHT empty frame stays visible")
	cube.acquire_block(C.Block.MAGMA)
	check(cube.block_slots == PackedInt32Array([C.Block.ICE,C.Block.MAGMA]) and has_frame(0,C.Block.ICE) and has_frame(1,C.Block.MAGMA),"second pickup fills RIGHT and keeps the left trait")
	check(cube._native_model.block_mode == C.Block.MAGMA and cube.has_block(C.Block.ICE),"internal block is newest magma while older ice remains active")
	cube.acquire_block(C.Block.HONEY)
	check(cube.block_slots == PackedInt32Array([C.Block.MAGMA,C.Block.HONEY]) and has_frame(0,C.Block.MAGMA) and has_frame(1,C.Block.HONEY) and not cube.has_block(C.Block.ICE),"third pickup evicts left, shifts old right left, puts new item right")
	check(cube.block_mode == C.Block.HONEY and cube._native_model.inner_block.get_child_count() == 6,"body still contains one six-faced newest block, never two overlaid blocks")
	var unchanged:PackedInt32Array = cube.block_slots.duplicate()
	check(not cube.acquire_block(C.Block.HONEY) and not cube.acquire_block(-1) and not cube.acquire_block(99) and cube.block_slots == unchanged,"duplicate newest / invalid acquisitions cannot invent stacks or exceed capacity")
	var picks:Dictionary = {}
	var valid:bool = true
	for i:int in range(200):
		var pick:int = cube.next_block()
		valid = valid and not cube.has_block(pick)
		picks[pick] = true
	check(valid and picks.size() == 4,"random acquisition selects from the four unheld block types")
	reset_block()
	check(empty_frame(0) and empty_frame(1),"clearing filled slots removes stale icons/textures without hiding either frame")
	check(frame_positions == PackedVector2Array([cube._block_frames.get_child(0).position,cube._block_frames.get_child(1).position]),"empty, single and full inventories use the same fixed two frame positions")
	reset_block(C.Block.ICE)
	cube.Skill()
	check(cube.block_slots.size() == 2 and cube.block_slots[0] == C.Block.ICE,"real Skill entry acquires into the second slot instead of replacing the first")

	var derived_is_stored:bool = false
	for property:Dictionary in cube.get_property_list():
		if property.name == "block_mode": derived_is_stored = (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0
	check(not derived_is_stored,"newest-only compatibility alias is not serialized over the two-slot snapshot")
	var stored:Dictionary = {}
	for property:Dictionary in cube.get_property_list():
		if property.name in ["block_slots","block_mode"] and (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0:
			stored[property.name] = cube.get(property.name)
	# Restore exported data onto a fresh original scene, not a PackedScene
	# clone of runtime health-bar signal connections unrelated to this feature.
	var restored:Node = load("res://scenes/characters/我的世界/硫方怪.tscn").instantiate()
	for key:String in stored: restored.set(key,stored[key])
	check(restored.block_slots == cube.block_slots and restored.block_mode == cube.block_mode,"stored-property snapshot/restore retains both blocks in order")
	if is_instance_valid(restored): restored.free()

	# All 30 ordered distinct pairs: inventory, latest-only model and complete threat union.
	for first:int in range(C.Block.ICE,C.Block.AMETHYST+1):
		for second:int in range(C.Block.ICE,C.Block.AMETHYST+1):
			if first == second: continue
			reset_block(first)
			cube.acquire_block(second)
			settle_model()
			check(cube.has_block(first) and cube.has_block(second) and has_frame(0,first) and has_frame(1,second),"pair %d/%d retains both traits and ordered original-texture icons" % [first,second])
			check(cube._native_model.block_mode == second and cube._native_model.inner_block.get_child(0).material_override.albedo_texture == C.MODEL.BLOCK_TEXTURES[second],"pair %d/%d renders only newest inner material" % [first,second])
			var expected:Dictionary = {}
			for mode:int in [first,second]:
				if mode == C.Block.ICE: expected["sulfur_ice_speed_contact"] = true
				elif mode == C.Block.MAGMA:
					expected["sulfur_magma_touch"] = true
					expected["sulfur_magma_top"] = true
				elif mode == C.Block.IRON: expected["sulfur_iron_bottom"] = true
				elif mode == C.Block.TNT: expected["sulfur_cube_tnt"] = true
				elif mode == C.Block.AMETHYST: expected["sulfur_amethyst_crystal"] = true
			check(kinds() == expected,"pair %d/%d exposes every actual damage region, not only the latest mode" % [first,second])

	# Independent damage cooldowns and attribute-based settlement.
	reset_block(C.Block.ICE)
	cube.acquire_block(C.Block.MAGMA)
	cube._actual_speed = cube._ice_reference_speed
	victim.global_position = cube.global_position+Vector2(cube.get_crowd_separation_radius_world(),0)
	var before:float = victim.health
	cube._pulse_contact()
	var expected_damage:float = cube._mode_damage(C.Block.ICE)+cube._mode_damage(C.Block.MAGMA)
	check(absf((before-victim.health)-expected_damage) <= 2.0,"ice and magma both deal their own real contact damage on the same frame")
	before = victim.health
	cube._pulse_contact()
	check(victim.health == before,"each contact trait has an independent cooldown without duplicate same-frame hits")
	var base_ice:float = cube._mode_damage(C.Block.ICE)
	var base_magma:float = cube._mode_damage(C.Block.MAGMA)
	cube.Damage = 96
	check(is_equal_approx(cube._mode_damage(C.Block.ICE),base_ice*2.0) and is_equal_approx(cube._mode_damage(C.Block.MAGMA),base_magma*2.0),"both retained damage formulas follow current attack attributes")
	cube.Damage = 48
	reset_block(C.Block.MAGMA)
	cube._pulse_contact()
	cube.acquire_block(C.Block.TNT)
	before = victim.health
	cube._pulse_contact()
	check(victim.health == before,"acquiring a companion does not reset the retained magma hit cooldown")
	check(cube.get_fire_effect_ratio() == 0.0 and kinds().has("sulfur_cube_tnt") and kinds().has("sulfur_magma_touch"),"older magma immunity/contact coexist with primed newer TNT")
	victim.global_position = center+Vector2(160,0)
	reset_block(C.Block.MAGMA)
	cube.acquire_block(C.Block.IRON)
	check(not cube.can_receive_fire_status(),"magma fire immunity survives in the left slot")
	before = cube.health
	cube.take_damage(100.0)
	check(before-cube.health == 50.0,"newer iron mitigation coexists with older magma immunity")
	cube.acquire_block(C.Block.HONEY)
	check(cube.can_receive_fire_status() and cube.has_block(C.Block.IRON),"eviction removes only magma immunity while retained iron still exists")
	before = cube.health
	cube.take_damage(100.0)
	check(before-cube.health == 50.0,"older iron mitigation survives a different latest visual block")
	cube.acquire_block(C.Block.ICE)
	check(not cube.is_external_directional_gravity_locomotion_enabled(),"evicting iron restores previous gravity mode")
	before = cube.health
	cube.take_damage(100.0)
	check(before-cube.health == 100.0,"evicted iron no longer grants resistance")

	# Sticky collision leases remain until HONEY itself is evicted.
	reset_block(C.Block.HONEY)
	victim.global_position = cube.global_position+Vector2(4,0)
	cube._pull_touching_enemies(0.1)
	cube.acquire_block(C.Block.MAGMA)
	check(cube.get_collision_exceptions().has(victim) and victim.get_collision_exceptions().has(cube),"honey pair collision exemption survives insertion of magma")
	victim.Repel = Vector2(250,0)
	cube._pull_touching_enemies(0.1)
	check(victim.Repel.x < 250.0 and victim.Repel.x > 0.0,"retained honey keeps its bounded pull, not a hard lock")
	cube.acquire_block(C.Block.IRON)
	check(not cube.get_collision_exceptions().has(victim) and not victim.get_collision_exceptions().has(cube),"eviction releases both sides of the honey lease")
	victim.global_position = center+Vector2(160,0)

	# Older amethyst keeps real crystals, hit memory, timing and its manual volley.
	reset_block(C.Block.AMETHYST)
	settle_model()
	var layout:PackedVector3Array = cube.crystal_layout.duplicate()
	var crystal_id:int = cube._native_model.crystal_layer.get_child(0).get_instance_id()
	var top_tip:Vector2 = cube._crystal_tip_points()[0]
	for tip:Vector2 in cube._crystal_tip_points():
		if tip.y < top_tip.y: top_tip = tip
	victim.global_position = top_tip
	cube._pulse_contact()
	var hits:Dictionary = cube._crystal_hits.duplicate(true)
	cube._crystal_timer = 1.2
	cube.acquire_block(C.Block.IRON)
	check(cube.crystal_layout == layout and cube._native_model.crystal_layer.get_child(0).get_instance_id() == crystal_id and cube._native_model.crystal_layer.visible,"new inner iron does not rebuild or hide retained external amethyst crystals")
	check(cube._crystal_hits == hits and is_equal_approx(cube._crystal_timer,1.2) and cube._native_model.crystals_ready(),"retained crystals keep hit memory, cooldown and growth readiness")
	before = victim.health
	cube._pulse_contact()
	check(victim.health == before,"same old crystal cannot re-hit merely because the inner block changed")
	check(cube.player_control_action_ids() == [&"Attack",&"Skill",&"controlled_crystal_volley",&"controlled_surge"],"iron + amethyst retains all four real actions in mouse/mouse/mouse/1 order")
	cube.player_control_peer_id = 1
	cube._crystal_timer = 0.0
	victim.global_position = center+Vector2(160,0)
	cube.player_control_action(2)
	check(cube.crystals_out and not cube._native_model.crystal_layer.visible,"middle mouse can fire the OLD retained amethyst, not just newest inner block")
	cube.state_machine.last_state_dis["Attack"] = 99.0
	cube._slam_time = -1.0
	cube.player_control_action(3)
	check(cube._surge_left > 0.0 and cube.state_machine.last_state_dis.Attack == 0.0,"fourth action preserves companion surge and consumes shared attack cooldown")
	cube._surge_left = 0.11
	cube.player_control_action(3)
	check(is_equal_approx(cube._surge_left,0.11),"extra surge cannot bypass its original attack cooldown")
	cube._crystal_timer = 0.01
	cube.tick_physics(cube.State.Stand,0.02)
	check(not cube.crystals_out,"controlled old amethyst still regrows passively")
	cube._crystal_timer = 0.01
	cube.tick_physics(cube.State.Stand,0.02)
	check(not cube.crystals_out,"controlled entity does not automatically fire retained amethyst")
	cube.acquire_block(C.Block.ICE)
	check(not cube._native_model.crystal_layer.visible and not cube.player_control_extra_actions().has(&"controlled_crystal_volley"),"evicted amethyst loses visuals, threat and manual volley together")
	cube.player_control_peer_id = 0

	# User-selected TNT exception: consume it once, preserve its companion, refill.
	reset_block(C.Block.IRON)
	cube.acquire_block(C.Block.TNT)
	cube.fuse_left = 0.7
	check(not cube.acquire_block(C.Block.TNT) and cube.block_slots.size() == 2,"duplicate TNT pickup cannot create two fuse instances")
	cube.fuse_left = 0.0
	before = cube.health
	cube._detonate()
	check(cube.block_slots.size() == 2 and cube.block_slots[0] == C.Block.IRON and not cube.has_block(C.Block.TNT),"TNT consumption preserves the other block and fills the right frame with a new non-TNT block")
	check(before-cube.health == 30.0 and cube.fuse_left == 0.0 and not is_instance_valid(cube._charge_circle),"one TNT self-hit respects retained iron mitigation and leaves no new fuse")
	before = cube.health
	cube._detonate()
	check(cube.health == before,"consumed TNT cannot explode again")
	reset_block(C.Block.TNT)
	cube.acquire_block(C.Block.HONEY)
	check(not cube.acquire_block(C.Block.ICE),"a primed left-slot TNT cannot be evicted to avoid its self damage")
	cube.fuse_left = 0.0
	cube._detonate()
	check(cube.block_slots[0] == C.Block.HONEY and not cube.has_block(C.Block.TNT),"left-slot TNT is also consumed while its newer honey companion is preserved")
	reset_block(C.Block.TNT)
	var tnt_threat:float = cube.get_ai_attack_threats(null)[0].damage
	cube.Damage = 96
	check(is_equal_approx(cube.get_ai_attack_threats(null)[0].damage,tnt_threat*2.0),"TNT damage uses a base coefficient rather than cancelling current attack attributes")
	cube.Damage = 48

	# Real movement: iron gravity and horizontal-only input, plus ice trail/inertia.
	reset_block(C.Block.IRON)
	cube.acquire_block(C.Block.ICE)
	cube.global_position = center-Vector2(0,30)
	cube.player_control_peer_id = 1
	cube.player_control_direction = Vector2.UP
	cube._slide_velocity = Vector2.ZERO
	cube._recoil_velocity = Vector2.ZERO
	cube._surge_left = 0.0
	cube.Repel = Vector2.ZERO
	for tile:Node in get_nodes_in_group("MCSulfurIceTrail"): tile.queue_free()
	var start:Vector2 = cube.global_position
	for i:int in range(12):
		await physics_frame
		cube.tick_physics(cube.State.Move,1.0/60.0)
	check(cube.global_position.y > start.y+10.0 and absf(cube.global_position.x-start.x) < 0.5,"iron + ice falls under real gravity; W does not generate vertical or phantom horizontal drive")
	check(get_nodes_in_group("MCSulfurIceTrail").size() > 0,"older iron does not suppress newer ice tiles during real displacement")
	cube.player_control_direction = Vector2.RIGHT
	start = cube.global_position
	for i:int in range(10):
		await physics_frame
		cube.tick_physics(cube.State.Move,1.0/60.0)
	check(cube.global_position.x > start.x+1.0 and cube.player_control_direction == Vector2.RIGHT,"iron + ice keeps actual horizontal movement and original player input")
	cube.player_control_peer_id = 0
	cube.global_position = center

	# Pause/disable affect both traits and the threat setting shows/clears their union.
	reset_block(C.Block.ICE)
	cube.acquire_block(C.Block.MAGMA)
	game.now_stop_state = true
	before = victim.health
	cube._pulse_contact()
	check(cube.get_ai_attack_threats(null).is_empty() and victim.health == before,"pause disables both retained damage sources and their active threats")
	game.now_stop_state = false
	var analyzer:Node2D = load("res://scripts/training/combat_threat_analyzer.gd").new()
	world.add_child(analyzer)
	analyzer.set_physics_process(false)
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	var displayed:Dictionary = {}
	for info:Dictionary in analyzer._debug_threats:
		if str(info.get("kind","")).begins_with("sulfur_"): displayed[str(info.kind)] = true
	check(analyzer.visible and displayed.has("sulfur_ice_speed_contact") and displayed.has("sulfur_magma_touch") and displayed.has("sulfur_magma_top"),"real threat-display setting shows the union of both retained damage shapes")
	cube.acquire_block(C.Block.HONEY)
	analyzer._physics_process(0.1)
	var old_ice:bool = false
	for info:Dictionary in analyzer._debug_threats:
		old_ice = old_ice or str(info.get("kind","")) == "sulfur_ice_speed_contact"
	check(not old_ice and kinds().has("sulfur_magma_touch"),"evicted ice disappears from the actual overlay while retained magma remains")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"disabling threat display immediately hides and clears the union")
	if DisplayServer.get_name() != "headless": await gpu_frames()
	cube.health = 0
	cube._process(0.0)
	check(not cube._block_frames.visible and cube.get_ai_attack_threats(null).is_empty(),"death hides inventory displays and removes both sets of active threats")
	world.queue_free()
	await process_frame
	await process_frame
	# Allow final empty-state crystal debris / GPU resources to flush before exit.
	await create_timer(0.15,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SULFUR_DUAL: %d checks / %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func mark_layer(node:Node,layer:int) -> void:
	if node is CanvasItem: (node as CanvasItem).visibility_layer = layer
	for child:Node in node.get_children():
		if not child is SubViewport: mark_layer(child,layer)
func gpu_frames() -> void:
	var layer:int = 1 << 18
	mark_layer(cube,layer)
	# Canvas visibility requires matching ancestor layers too. Keep unrelated
	# world children culled without accidentally culling this whole subtree.
	var ancestors:Array[CanvasItem] = []
	var previous_layers:Array[int] = []
	var ancestor:Node = cube.get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasItem:
			ancestors.append(ancestor as CanvasItem)
			previous_layers.append((ancestor as CanvasItem).visibility_layer)
			(ancestor as CanvasItem).visibility_layer |= layer
		ancestor = ancestor.get_parent()
	var shots:Array[String] = ["empty_spawn","first_ice","ice_magma","magma_honey","amethyst_iron","emptied"]
	var pairs:Array = [[C.Block.EMPTY,C.Block.EMPTY],[C.Block.ICE,C.Block.EMPTY],[C.Block.ICE,C.Block.MAGMA],[C.Block.MAGMA,C.Block.HONEY],[C.Block.AMETHYST,C.Block.IRON],[C.Block.EMPTY,C.Block.EMPTY]]
	var preview := SubViewport.new()
	preview.size = Vector2i(320,320)
	preview.transparent_bg = true
	preview.disable_3d = true
	preview.world_2d = world.get_world_2d()
	preview.canvas_cull_mask = layer
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(preview)
	preview.canvas_transform = Transform2D(Vector2(5,0),Vector2(0,5),Vector2(160,125)-cube.global_position*5.0)
	for i:int in range(shots.size()):
		reset_block(int(pairs[i][0]))
		if int(pairs[i][1]) != C.Block.EMPTY: cube.acquire_block(int(pairs[i][1]))
		settle_model()
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image:Image = preview.get_texture().get_image()
		var both_visible:bool = true
		for slot:Node2D in cube._block_frames.get_children():
			var point:Vector2 = preview.canvas_transform*slot.global_position
			var colored:int = 0
			for y:int in range(int(point.y)-8,int(point.y)+8):
				for x:int in range(int(point.x)-8,int(point.x)+8):
					if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and image.get_pixel(x,y).a > 0.5: colored += 1
			both_visible = both_visible and colored > 200
		check(both_visible,"real GPU shared World2D viewport shows both permanent frames: "+shots[i])
		var folder:String = OS.get_environment("SULFUR_DUAL_ARTIFACTS")
		if not folder.is_empty():
			DirAccess.make_dir_recursive_absolute(folder)
			image.save_png(folder+"/"+shots[i]+".png")
	preview.queue_free()
	mark_layer(cube,1)
	for i:int in range(ancestors.size()): ancestors[i].visibility_layer = previous_layers[i]
	await process_frame
