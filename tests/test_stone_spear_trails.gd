extends "res://tests/test_stone_spear.gd"
const TRAIL = preload("res://classes/sprite_snapshot_trail.gd")
var preview_camera:Camera2D
func drive(form:int,speed_value:float,frames:int=8,fps:float=60.0) -> void:
	reset_pose(form)
	spear._reset_copy_trails()
	spear.movement_growth=0.0
	spear.Speed=speed_value/0.6
	spear._real_speed=speed_value
	if form==2:
		spear._stab_wait=0.0
		spear.begin_stab()
	for frame:int in range(frames):
		await physics_frame
		spear.tick_physics(spear.State.Move,1.0/fps)
		spear._process(1.0/fps)
func run() -> void:
	create_timer(65.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	check(spear.movement_growth==10.0 and spear.SPEED_DAMAGE_FACTOR==0.25,"growth and speed damage halved again")
	check(spear.body_turn_degrees_per_second==3600.0 and spear.follow_cohesion_reference_speed==45.0,"fast turn and early follow contraction preserved")
	check(spear.orbit_base_rate==0.65 and spear.orbit_speed_factor==0.018,"base orbit unchanged and speed conversion doubled")
	for v:float in [0.0,102.0,180.0,500.0,1000.0]:
		check(is_equal_approx(spear.orbit_rate(v)-0.65,v*0.009*2.0),"twice the speed-driven orbit increment at %s" % v)
	check(spear.copy_trail_min_speed==180.0,"trails require actual high body movement speed")
	var config:SceneReplicationConfig=spear.get_node("MultiplayerSynchronizer").replication_config
	check(config.has_property(NodePath(".:_real_speed")) and config.property_get_spawn(NodePath(".:_real_speed")),"actual body speed replicated for local client visual gating")
	# Low speed must not leave ghosts even when orbit/thrust tips themselves move fast.
	for form:int in range(3):
		await drive(form,102.0)
		check(spear._copy_trails.samples.is_empty(),"no birth-speed ghosts in formation %d" % form)
	for form:int in range(3):
		await drive(form,500.0)
		var samples:Array=spear._copy_trails.samples
		check(samples.size()>=8 and samples.size()<=24,"high-speed production pose creates bounded trail in formation %d" % form)
		var tags:Dictionary={}
		for sample:Dictionary in samples:
			tags[sample.tag]=true
			var ghost:Sprite2D=sample.sprite
			check(ghost.texture==spear.TEXTURE and ghost.material==TRAIL.MATERIAL,"snapshot reuses original spear texture and shared shader")
			check(ghost.get_child_count()==0 and ghost.get_script()==null,"snapshot has no hitbox, hurtbox or guard subtree")
		check(tags.size()==4,"all four copies, but not the main spear, leave trails")
		if samples.is_empty(): quit(1); return
		var first:Sprite2D=samples[0].sprite
		var before:Transform2D=first.global_transform
		spear.position+=Vector2(6,4)
		check(first.global_transform.is_equal_approx(before),"snapshot stays at historical world pose when its owner moves")
		spear.position-=Vector2(6,4)
		if DisplayServer.get_name()!="headless": await visual_check(form)
	# Zero/stale replicated displacement cannot stamp an infinite pile of ghosts.
	await drive(1,500.0,4)
	spear._process(0.04) # Capture the last unsampled production pose first.
	var emitted:int=spear._copy_trails.total_emitted
	spear._process(0.1)
	check(spear._copy_trails.total_emitted==emitted,"unchanged pose never emits duplicate snapshots")
	# Existing outward ghosts may fade, but idle and return produce no new ones.
	await drive(2,500.0,5)
	emitted=spear._copy_trails.total_emitted
	spear._stab_time=spear.stab_out_time+0.03
	spear._process(0.06)
	check(spear._copy_trails.total_emitted==emitted,"thrust return never emits afterimages")
	spear._stab_time=-1.0
	spear._process(0.3)
	check(spear._copy_trails.total_emitted==emitted and spear._copy_trails.samples.is_empty(),"idle thrust is silent and old outward ghosts expire")
	# Pause stops both aging and creation, even with a very long presentation delta.
	await drive(0,500.0,5)
	var age:float=spear._copy_trails.samples[0].age
	emitted=spear._copy_trails.total_emitted
	game.now_stop_state=true
	spear._process(4.0)
	check(spear._copy_trails.samples[0].age==age and spear._copy_trails.total_emitted==emitted,"pause freezes trail clock without catch-up generation")
	game.now_stop_state=false
	spear.dizziness=true
	spear._process(0.016)
	check(spear._copy_trails.samples.is_empty(),"stun immediately removes visual trails")
	spear.dizziness=false
	await drive(1,500.0,5)
	spear.Can_Attack=false
	spear._process(0.016)
	check(spear._copy_trails.samples.is_empty(),"disabled attack removes attack-copy trails")
	spear.Can_Attack=true
	await drive(1,500.0,5)
	check(spear.set_formation(0) and spear._copy_trails.samples.is_empty(),"switch clears old-formation trails immediately")
	await drive(1,500.0,5)
	spear.position+=Vector2(1000,0)
	spear.tick_physics(spear.State.Stand,1.0/60.0)
	check(spear._copy_trails.samples.is_empty(),"teleport does not produce a trail bridge")
	# Render snapshots cannot change damage state or extend the guard regions.
	await drive(1,500.0,5)
	var guards:Array=[]
	for guard:Node2D in spear._tip_guards: guards.append(guard.global_transform)
	var hits:Array=spear._hits.duplicate(true)
	var hp:int=spear.health
	spear._update_copy_trails(0.07)
	check(spear._hits==hits and spear.health==hp,"render-only updates do not touch health or hit history")
	for i:int in range(4): check(spear._tip_guards[i].global_transform==guards[i],"trail does not move or extend orbit guard")
	# Per-owner and whole-process budgets remain bounded even under adversarial callers.
	spear._reset_copy_trails()
	for i:int in range(100): spear._copy_trails.capture(spear._copies[0],spear._copies[0].global_transform)
	check(spear._copy_trails.samples.size()==24,"hard 24-snapshot per-owner budget")
	var extra:Array[Node2D]=[]
	for i:int in range(12):
		var renderer:Node2D=TRAIL.new()
		spear.add_child(renderer)
		extra.append(renderer)
		for j:int in range(24): renderer.capture(spear._copies[0],spear._copies[0].global_transform)
	check(TRAIL.live_count==256,"hard 256-snapshot global budget")
	for renderer:Node2D in extra: renderer.free()
	spear._reset_copy_trails()
	check(TRAIL.live_count==0,"clear and exit release all global budget reservations")
	await drive(1,500.0,5)
	var trail_refs:Array=[]
	for sample:Dictionary in spear._copy_trails.samples: trail_refs.append(sample.sprite)
	spear.queue_free()
	await process_frame
	check(TRAIL.live_count==0,"despawn releases snapshot budget")
	for ghost:Variant in trail_refs: check(not is_instance_valid(ghost),"despawn removes world-fixed snapshots")
	print("STONE_TRAILS_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)

func visual_check(form:int) -> void:
	root.size=Vector2i(1080,720)
	root.content_scale_size=Vector2i(1080,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	if not is_instance_valid(preview_camera):
		preview_camera=Camera2D.new()
		preview_camera.zoom=Vector2(4,4)
		arena.add_child(preview_camera)
	preview_camera.position=spear.global_position
	preview_camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	var visible_image:Image=root.get_texture().get_image()
	for sample:Dictionary in spear._copy_trails.samples: sample.sprite.hide()
	await RenderingServer.frame_post_draw
	var hidden_image:Image=root.get_texture().get_image()
	var changed:int=0
	for y:int in range(visible_image.get_height()):
		for x:int in range(visible_image.get_width()):
			if visible_image.get_pixel(x,y)!=hidden_image.get_pixel(x,y): changed+=1
	check(changed>20,"GPU actually draws historical copy pixels in formation %d: %d changed pixels" % [form,changed])
	for sample:Dictionary in spear._copy_trails.samples: sample.sprite.show()
	visible_image.save_png("E:/godot/polo-balls-checkpoints/stone_spear_trails_20260927/trails_%d.png" % form)
