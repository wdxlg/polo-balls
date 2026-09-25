extends "res://tests/test_mc_new6_load.gd"
var FX:Script
var GROUND:Script

func rings() -> Array[Node]: return get_nodes_in_group("HeavenfallShotRing")

func freeze_shots() -> void:
	for n:Node in _bolts(): n.set_physics_process(false)
	for n:Node in rings(): n.set_process(false)

func image_metrics(img:Image) -> Dictionary:
	var count:int = 0
	var peak:float = 0.0
	var radius:float = 0.0
	var cyan:int = 0
	for y:int in img.get_height():
		for x:int in img.get_width():
			var c:Color = img.get_pixel(x,y)
			if c.a > 0.008:
				count += 1
				peak = maxf(peak,c.a)
				radius = maxf(radius,Vector2(x+0.5,y+0.5).distance_to(Vector2(64,64)))
				if c.g > c.r*1.2 and c.b > c.r*1.2: cyan += 1
	return {"count":count,"peak":peak,"radius":radius,"cyan":cyan}

func projected_extent(img:Image,axis:Vector2) -> Vector2:
	var extent:=Vector2.ZERO
	for y:int in img.get_height():
		for x:int in img.get_width():
			if img.get_pixel(x,y).a <= 0.008: continue
			var point:Vector2 = Vector2(x+0.5,y+0.5)-Vector2(64,64)
			extent.x = maxf(extent.x,absf(point.dot(axis)))
			extent.y = maxf(extent.y,absf(point.dot(axis.orthogonal())))
	return extent

func gpu_ring() -> void:
	if DisplayServer.get_name() == "headless":
		print("MUZZLE_GPU_SKIPPED headless; run gl_compatibility for real pixels")
		return
	var view:=SubViewport.new()
	view.size = Vector2i(128,128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var ring:Node2D = FX.expanding_ring(view,Vector2(64,64),8,{"palette":[Color("14534f"),Color("83dbd6"),Color("c8c8c8")],"direction":Vector2.RIGHT,"depth_ratio":0.35})
	ring.set_process(false)
	var samples:Array[Dictionary] = []
	for age:float in [0.0,0.19,0.34,0.38]:
		ring._elapsed = age
		ring.queue_redraw()
		await process_frame
		RenderingServer.force_draw(false)
		var img:Image = view.get_texture().get_image()
		img.save_png("user://heavenfall_muzzle_3d_%.2f.png" % age)
		samples.append(image_metrics(img))
		check(img.get_pixel(64,64).a < 0.005,"GPU hollow center remains transparent at %.2fs" % age)
	print("MUZZLE_GPU_METRICS ",samples)
	check(samples[0].count > 0 and samples[0].cyan > 0,"GPU first ring contains visible cyan palette pixels")
	check(samples[1].radius > samples[0].radius+5 and samples[2].radius >= samples[1].radius-3.0 and samples[2].radius > samples[0].radius+5,"GPU pixel circumference expands outward")
	check(samples[0].peak > samples[1].peak and samples[1].peak > samples[2].peak,"GPU ring alpha fades continuously")
	check(samples[3].count == 0,"GPU ring disappears exactly at lifetime")
	for axis:Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
		ring.ring_axis = axis
		ring._elapsed = 0.12
		ring.queue_redraw()
		await process_frame
		RenderingServer.force_draw(false)
		var image:Image = view.get_texture().get_image()
		var extent:Vector2 = projected_extent(image,axis)
		check(extent.y > extent.x*1.8 and extent.x > 3.0,"GPU hoop is compressed along shot normal, wide across it: "+str(axis))
		image.save_png("user://heavenfall_muzzle_3d_direction_%d.png" % int(rad_to_deg(axis.angle())))
	view.queue_free()
	await process_frame

func run() -> void:
	FX = load("res://scripts/effects/我的世界/mc_combat_abilities.gd")
	GROUND = load("res://scripts/effects/我的世界/重锤落地冲击.gd")
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var legacy:Node2D = GROUND.new()
	check(legacy.show_block_particles and legacy.show_impact_streaks and not legacy.pause_with_battle and is_equal_approx(legacy.ring_depth_ratio,1.0),"existing impact defaults preserve rubble/streaks and clock")
	legacy.free()
	var parent:=Node2D.new()
	parent.position = Vector2(33,18)
	parent.scale = Vector2(0.2,0.4)
	parent.rotation = 0.4
	world.add_child(parent)
	var sampler_before:Node = world.get_node_or_null("GroundSurfaceSampler")
	var pure:Node2D = FX.expanding_ring(parent,center,10,{"lifetime":0.8,"end_scale":2.4,"palette":[Color.CYAN]})
	pure.set_process(false)
	check(pure.get_script() == GROUND,"reusable preset instantiates the existing ground impact implementation")
	check(pure.global_position.is_equal_approx(center) and pure.global_scale.is_equal_approx(Vector2.ONE) and is_zero_approx(pure.global_rotation),"ring uses world units under rotated/scaled parents")
	check(pure._blocks.is_empty() and pure._streaks.is_empty() and pure._floor_snapshot.is_empty(),"no debris, rays or floor sampling")
	check(world.get_node_or_null("GroundSurfaceSampler") == sampler_before,"pure ring never creates a floor readback node")
	check(pure.get_child_count() == 0 and not pure.is_in_group("AI_Hazard") and pure.is_in_group("BattleTransient"),"pure transient has no hitboxes, hazard or audio children")
	check(is_equal_approx(pure._effect_end_time,0.8) and pure.ring_palette[0] == Color.CYAN,"custom lifetime and palette are applied without the block builder")
	check(is_equal_approx(pure.ring_depth_ratio,1.0),"generic callers keep a flat circle unless projection is requested")
	parent.position += Vector2(100,30)
	check(pure.global_position.is_equal_approx(center),"spawned ring does not follow its moving parent")
	game.now_stop_state = true
	pure._process(0.2)
	check(is_zero_approx(pure._elapsed),"battle pause freezes ring lifetime")
	game.now_stop_state = false
	paused = true
	pure._process(0.2)
	check(is_zero_approx(pure._elapsed),"SceneTree pause freezes manual updates too")
	paused = false
	pure._process(0.79)
	check(not pure.is_queued_for_deletion(),"configured longer lifetime does not end at old 0.46s default")
	pure._process(0.02)
	check(pure.is_queued_for_deletion(),"ring self-cleans at configured lifetime")
	parent.queue_free()
	await process_frame
	var bow:Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",center)
	bow.Can_Attack = true
	bow.state_machine.set_physics_process(false)
	bow.set_player_control_peer(1)
	bow._cool = 0.0
	bow.drawing = 0.0
	bow.facing = Vector2.RIGHT
	bow.controlled_attack_action()
	bow.step_mob(bow.draw_time*0.4)
	check(rings().is_empty() and _bolts().is_empty(),"manual partial draw emits neither arrow nor ring")
	bow.player_control_action_cancelled(0)
	bow.step_mob(0.01)
	check(rings().is_empty(),"cancelling a draw does not emit a ring")
	bow.controlled_attack_action()
	bow.step_mob(bow.draw_time+0.01)
	freeze_shots()
	check(rings().size() == 1 and _bolts().size() == 1,"one completed manual shot emits one arrow and one ring")
	if rings().is_empty(): finish(1); return
	var ring:Node2D = rings()[0]
	var origin:Vector2 = ring.global_position
	check(origin.is_equal_approx(_bolts()[0].global_position),"ring center equals the actual authoritative projectile spawn")
	check(is_equal_approx(ring._radius,8.0) and is_equal_approx(ring.ring_end_scale,3.0) and is_equal_approx(ring.lifetime,0.38),"muzzle ring expands from radius 8 toward 24 over 0.38s")
	check(ring.ring_palette == PackedColorArray(bow.SHOT_RING_PALETTE),"muzzle uses the native longbow teal/cyan/silver palette")
	bow.global_position += Vector2(70,15)
	var launch_axis:Vector2 = ring.ring_axis
	check(launch_axis.is_equal_approx(bow.facing) and is_equal_approx(ring.ring_depth_ratio,0.35),"bow hoop normal matches launch direction with pseudo-3D depth")
	bow.facing = Vector2.UP
	bow._start_recoil(1.0,Vector2.RIGHT,bow.clock)
	bow.visual_mob()
	check(ring.global_position.is_equal_approx(origin) and ring.ring_axis.is_equal_approx(launch_axis),"moving/recoiling/turning bow leaves emitted position and orientation frozen")
	bow.step_mob(0.01)
	check(rings().size() == 1,"cooldown/held input cannot duplicate the ring")
	var state:Dictionary = bow.visual_state()
	bow.accept_visual(state)
	state.shot += 1
	bow.accept_visual(state)
	bow.accept_visual(state)
	check(rings().size() == 1,"visual-state recoil replay never duplicates ring RPC visuals")
	bow.player_control_action_cancelled(0)
	bow.set_player_control_peer(0)
	var enemy:Node2D = _mk_enemy(bow.global_position+Vector2(140,0))
	bow._cool = 0.0
	bow.drawing = 0.0
	bow.step_mob(bow.draw_time+0.01)
	freeze_shots()
	check(rings().size() == 2 and _bolts().size() == 2,"AI shot uses the same single ring spawn path")
	bow.set_multiplayer_authority(42)
	bow._fire()
	check(rings().size() == 2 and _bolts().size() == 2,"non-authority cannot originate arrows or muzzle rings")
	bow.set_multiplayer_authority(1)
	var hp:float = enemy.health
	var hazards:int = get_nodes_in_group("AI_Hazard").size()
	bow._spawn_shot_ring(enemy.global_position,Vector2.LEFT)
	freeze_shots()
	check(enemy.health == hp and get_nodes_in_group("AI_Hazard").size() == hazards,"visual-only ring adds no damage or threat")
	for n:Node in rings(): n._process(1.0)
	await process_frame
	check(rings().is_empty(),"all shot rings clean themselves up")
	await gpu_ring()
	print("HEAVENFALL_MUZZLE: %d checks / %d failures" % [checks,failures])
	finish(0 if failures == 0 else 1)
