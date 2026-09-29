extends "res://tests/test_sulfur_cube_balance.gd"
## Real alternating Move calls stay inside one production-sized ice cell.
## Separate narrow-corridor collisions exercise a reflection on every physical step.
var origin:Vector2
var tile:Node2D
var effect:Node
var victim:Node2D

func sounds(event:StringName) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sulfur_event",&"")==event: result.append(node)
	return result

func quiet() -> void:
	await process_frame
	await process_frame
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop()
		node.free()
	source._sound_time.clear()

func reset_ice(speed:float,rect:Rect2) -> void:
	if is_instance_valid(effect): effect.free()
	if is_instance_valid(tile): tile.free()
	source.fuse_left = 0.0
	source.set_block(source.Block.EMPTY)
	source.Speed = speed
	source.default_properties.Speed = speed
	source.set_block(source.Block.ICE)
	source._ice_bounce_hold = 0.0
	source._slide_velocity = Vector2.RIGHT*speed
	source.surface_motion_velocity = Vector2.ZERO
	source.Repel = Vector2.ZERO
	source.global_position = rect.get_center()
	source.player_control_direction = Vector2.RIGHT
	tile = floor_tile(rect)
	effect = SURFACE.touch(source,tile)
	effect.set_physics_process(false)

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func():print("ICE_REVERSAL_TIMEOUT");quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	var original_rate:int = Engine.physics_ticks_per_second
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	origin = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	source = fighter("IceReversalCube",origin,true)
	source.set_process(false)
	source.collision_mask = 0
	source.Damage = 48.0
	source.default_properties.Damage = 48.0
	SURFACE = load("res://scripts/effects/surface_acceleration.gd")
	var cell:Rect2 = source.ICE_TRAIL.cell_at(source,origin)
	# A low configured drive lets input complete 180-degree turns within one
	# step; no positions, momentum, or physics velocities are faked in this run.
	Engine.physics_ticks_per_second = 60
	await physics_frame
	reset_ice(1.0,cell)
	var peaks:Array[float] = []
	var min_growth:float = INF
	var last_speed:float = 0.0
	var contained:bool = true
	var sign_ok:bool = true
	var sum_travel:float = 0.0
	for i:int in range(204):
		await physics_frame
		tile._physics_process(1.0/60.0)
		effect._physics_process(1.0/60.0)
		var heading:Vector2 = Vector2.RIGHT if i%2==0 else Vector2.LEFT
		source.player_control_direction = heading
		var before:Vector2 = source.global_position
		source.move(source.Speed,1.0/60.0)
		var traveled:Vector2 = source.global_position-before
		var real_speed:float = traveled.length()*60.0
		contained = contained and cell.has_point(source.global_position)
		sign_ok = sign_ok and traveled.dot(heading)>0.0 and source.player_control_direction==heading
		sum_travel += traveled.length()
		if i>3: min_growth = minf(min_growth,real_speed-last_speed)
		last_speed = real_speed
		if i in [59,119,179,203]: peaks.append(real_speed)
	check(contained and effect.surfaces.size()==1 and get_nodes_in_group("MCSulfurIceTrail").size()==1,"204 genuine left/right moves stay in ONE production-sized ice cell with one shared controller")
	check(sign_ok and sum_travel>1000.0,"actual left/right travel covers over1000 world units without changing position by hand")
	check(peaks.size()==4 and peaks[0]>220.0 and peaks[1]>450.0 and peaks[2]>700.0 and peaks[3]>800.0,"ice form keeps accelerating past the previous cap and old high-speed teleport cutoff")
	check(min_growth>3.7,"every alternating moving sample continues gaining speed instead of cancelling previous momentum")
	check(source.Speed==1.0 and source._slide_velocity.length()>0.99,"surface acceleration leaves configured drive attributes and intrinsic steering speed unchanged")
	print("ICE_ONE_CELL size=",cell.size," speed_samples=",peaks," min_growth=",min_growth," distance=",sum_travel)
	var held:Vector2 = effect.momentum
	game.now_stop_state = true
	effect._physics_process(20.0)
	check(effect.momentum==held,"pause cannot advance unlimited ice acceleration")
	game.now_stop_state = false
	source.acquire_block(source.Block.HONEY)
	check(source.has_block(source.Block.ICE) and source.block_mode==source.Block.HONEY,"retained ice remains an active trait independently from the newest inner block")
	for i:int in range(4):
		await physics_frame
		source.player_control_direction = Vector2.RIGHT if i%2==0 else Vector2.LEFT
		source.move(source.Speed,1.0/60.0)
		effect._physics_process(1.0/60.0)
	check(effect.momentum.length()>held.length(),"retained ICE+HONEY has no speed cap either")
	# Keep a real wider surface under the fast body for the form-loss check;
	# otherwise the uncapped body correctly leaves the small cell and coasts.
	var wider:Node2D = floor_tile(Rect2(origin-Vector2(1000,1000),Vector2(2000,2000)))
	SURFACE.touch(source,wider)
	Engine.physics_ticks_per_second = 20
	await physics_frame
	source._previous_motion_position = source.global_position
	source._motion_sample_valid = true
	source.player_control_direction = Vector2.RIGHT
	var fast_start:Vector2 = source.global_position
	source.move(source.Speed,1.0/20.0)
	check(source.global_position.distance_to(fast_start)>36.0,"already accumulated speed creates a genuine step beyond the old character sampling cutoff")
	source.tick_physics(source.State.Stand,1.0/20.0)
	check(source._ice_cells.size()>1,"fast genuine movement still updates ice trail generation instead of being misclassified as a teleport")
	for generated:Variant in source._ice_cells.values():
		if is_instance_valid(generated): generated.free()
	source._ice_cells.clear()
	effect._physics_process(1.0/20.0)
	source.set_block(source.Block.HONEY)
	Engine.physics_ticks_per_second = 60
	await physics_frame
	source.move(source.Speed,1.0/60.0)
	effect._physics_process(1.0/60.0)
	check(is_equal_approx(effect.momentum.length(),source.Speed*source.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER*1.5),"losing ice restores the normal capped surface policy while still on ice")
	wider.free()

	# Frequency invariance and ordinary-character cap on a single larger surface.
	var by_rate:Array[float] = []
	for rate:int in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await physics_frame
		reset_ice(130.0,Rect2(origin-Vector2(2000,2000),Vector2(4000,4000)))
		for i:int in range(rate+1):
			await physics_frame
			effect._physics_process(1.0/float(rate))
			source.move(source.Speed,1.0/float(rate))
		by_rate.append(effect.momentum.length())
		check(is_equal_approx(effect.momentum.length(),240.0),"one second of genuine sampled travel adds240 at %d Hz" % rate)
	check(absf(by_rate.max()-by_rate.min())<0.1,"uncapped acceleration is not multiplied by physics tick frequency")
	Engine.physics_ticks_per_second = 60
	await physics_frame
	reset_ice(100.0,Rect2(origin-Vector2(1000,1000),Vector2(2000,2000)))
	victim = fighter("CappedIceVisitor",origin+Vector2(0,45))
	victim.collision_mask = 0
	victim.player_control_direction = Vector2.RIGHT
	var ordinary:Node = SURFACE.touch(victim,tile)
	ordinary.set_physics_process(false)
	for i:int in range(30):
		await physics_frame
		ordinary._physics_process(1.0/60.0)
		victim.move(victim.Speed,1.0/60.0)
	check(is_equal_approx(ordinary.momentum.length(),90.0),"ordinary actors on the same ice retain their existing1.5x base bonus cap")
	ordinary.free()
	victim.free()
	var no_motion:Vector2 = source.global_position
	for i:int in range(3): effect._physics_process(1.0/60.0)
	check(effect.momentum.is_zero_approx() and source.global_position==no_motion,"a stationary body cannot manufacture unlimited acceleration")
	source.global_position += Vector2(500,0)
	effect._physics_process(1.0/60.0)
	check(effect.momentum.is_zero_approx(),"a large teleport with no physical drive is rejected instead of banked as ice movement")

	# A reflection every step used to throw away every real movement sample.
	var obstacles:Array[Node] = []
	reset_ice(2000.0,cell)
	source.collision_mask = 1
	var radius:float = source.get_crowd_separation_radius_world()
	for sign_x:float in [-1.0,1.0]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(2,180)
		shape.shape = rectangle
		wall.add_child(shape)
		world.add_child(wall)
		wall.global_position = cell.get_center()+Vector2(sign_x*(radius+cell.size.x*0.5),0)
		obstacles.append(wall)
	await physics_frame
	var bounces:int = 0
	var positions_valid:bool = true
	for i:int in range(36):
		await physics_frame
		effect._physics_process(1.0/60.0)
		source.player_control_direction = source._slide_velocity.normalized()
		source.move(source.Speed,1.0/60.0)
		if source.get_slide_collision_count()>0: bounces += 1
		positions_valid = positions_valid and cell.has_point(source.global_position)
	check(bounces>=30 and positions_valid,"real narrow-corridor reflections occur almost every step while the center remains on one ice cell")
	check(effect.momentum.length()>125.0,"real travel before repeated wall reflections continues contributing acceleration")
	print("ICE_REPEATED_REFLECTION bounces=",bounces," bonus=",effect.momentum.length())
	# The completed previous step is first consumed; a purely manual reflection
	# with no movement then gets one grace sample but no extra acceleration.
	effect._physics_process(1.0/60.0)
	effect.reflect_momentum(-effect.momentum.normalized())
	held = effect.momentum
	effect._physics_process(1.0/60.0)
	check(effect.momentum.is_equal_approx(held),"a reflection without real travel preserves once but cannot create extra thrust")
	effect._physics_process(1.0/60.0)
	check(effect.momentum.is_zero_approx(),"genuine continued wall-blocked standstill still clears momentum")
	for wall:Node in obstacles: wall.free()
	effect.free()
	tile.free()
	await test_silent_iron()
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	Engine.physics_ticks_per_second = original_rate
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_ICE_REVERSAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func test_silent_iron() -> void:
	source.set_block(source.Block.IRON)
	source.collision_mask = 1
	source.global_position = origin
	source.clear_external_directional_gravity_velocity()
	await quiet()
	check(not source.AUDIO.EVENTS.has(&"iron_land"),"iron landing event is removed from the active audio bank")
	check(source.AUDIO.play(source,&"iron_land",source.global_position).is_empty(),"stale direct/RPC landing requests are silent too")
	source._start_single_slam()
	await process_frame
	await process_frame
	check(sounds(&"iron_form").size()==1,"iron slam startup still keeps its separate material cue")
	await quiet()
	source._slam_time = 0.81
	source._step_single_slam(0.02)
	await process_frame
	await process_frame
	check(sounds(&"iron_land").is_empty(),"completed jump-slam no longer plays a landing sound")
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(120,6)
	shape.shape = rectangle
	floor_body.add_child(shape)
	world.add_child(floor_body)
	floor_body.global_position = origin+Vector2(0,40)
	source.global_position = origin+Vector2(0,37-source.get_crowd_separation_radius_world()-0.1)
	source.Repel = Vector2.DOWN*170.0
	await physics_frame
	var project_audio:Node = root.get_node("Audios")
	var legacy_starts:Dictionary = project_audio.get("_dynamic_last_start_frame_by_source").duplicate()
	source.move(0.0,1.0/60.0)
	check(project_audio.get("_dynamic_last_start_frame_by_source")==legacy_starts,"iron ground impact also suppresses the shared fallback footstep sound, not only iron_land")
	check(source.get_slide_collision_count()>0,"iron really collides downward with terrain in the silence regression")
	await process_frame
	await process_frame
	check(sounds(&"iron_land").is_empty(),"real iron terrain impact no longer plays a landing sound")
	floor_body.free()
	await quiet()
	source._emit_sound(&"iron_hit")
	await process_frame
	await process_frame
	check(sounds(&"iron_hit").size()==1,"iron hit feedback was not removed along with the unwanted landing cue")
