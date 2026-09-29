extends "res://tests/test_mc_snow_golem.gd"
## Real Area2D crossing plus the public rejected-hit/death pathways.
const BALL_PATH:String = "res://scenes/shooter/我的世界/雪球.tscn"
func launch_snow(owner_unit:Node2D,point:Vector2,heading:Vector2,suffix:String) -> Node2D:
	owner_unit._spawn_snowball("SnowContact_"+suffix,point,heading,6.0)
	return world.get_node("SnowContact_"+suffix)
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(25.0).timeout.connect(func(): finish(2))
	var source:Node2D = spawn(GOLEM_PATH,center+Vector2(0,-192),"Team0")
	source._field.set_physics_process(false)
	var hostile:Node2D = dummy(center+Vector2(0,240),"Team1")
	var target:Node2D = dummy(center+Vector2(-120,96),"Team0")
	var snow:Node2D = launch_snow(source,center+Vector2(-48,96),Vector2.RIGHT,"Crossing")
	var snow_ref:WeakRef = weakref(snow)
	var incoming:Node2D = load("res://scenes/shooter/子弹.tscn").instantiate()
	incoming.Master = hostile
	incoming.Team = "Team1"
	incoming.position = center+Vector2(48,96)
	incoming.direction = Vector2.LEFT
	world.add_child(incoming,true)
	await create_timer(0.65).timeout
	print("SNOW_CONTACT_CROSS target_hp=",target.health," snow_valid=",is_instance_valid(snow_ref.get_ref()))
	check(target.health == 9995,"a real enemy bullet crosses a snowball and hits the character behind it")
	if is_instance_valid(snow_ref.get_ref()):
		var survivor:Node2D = snow_ref.get_ref()
		check(survivor.health == 1 and survivor.global_position.x > center.x+80.0,"snowball is neither shot down into a stationary corpse nor stopped by the crossing bullet")
		survivor.queue_free()
	else: check(false,"crossing snowball remains in flight until its legitimate contact or lifetime ends")
	if is_instance_valid(incoming): incoming.queue_free()

	var blocked:Node2D = launch_snow(source,center+Vector2(-48,-48),Vector2.RIGHT,"Rejected")
	var blocked_ref:WeakRef = weakref(blocked)
	hostile.on_incoming_hit_rejected(blocked.self_hitbox)
	await physics_frame
	await process_frame
	await process_frame
	check(not is_instance_valid(blocked_ref.get_ref()),"public rejection destroys the snowball instead of leaving a zero-speed Die-state sprite")
	if is_instance_valid(blocked_ref.get_ref()): blocked_ref.get_ref().queue_free()
	var dead:Node2D = launch_snow(source,center+Vector2(-48,-96),Vector2.RIGHT,"Dead")
	var dead_ref:WeakRef = weakref(dead)
	dead.take_damage(1.0,true)
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	check(not is_instance_valid(dead_ref.get_ref()),"the actual projectile death path removes its sprite and collision in the next frame")
	if is_instance_valid(dead_ref.get_ref()): dead_ref.get_ref().queue_free()
	# A legacy script can call the public hitbox method without using Area layers.
	var untouched:Node2D = launch_snow(source,center+Vector2(-180,-96),Vector2.RIGHT,"Passthrough")
	untouched.state_machine.set_physics_process(false)
	var legacy:Node2D = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(-120,-96),"Team1")
	legacy.Master = hostile
	var legacy_speed:float = legacy.Speed
	check(not legacy.self_hitbox.try_hit_hurtbox(untouched.self_hurtbox),"direct legacy hitbox queries also see snowballs as non-targets")
	check(legacy.Speed == legacy_speed and not legacy.is_queued_for_deletion() and untouched.health == 1,"rejecting a hit on a snowball neither consumes nor deflects the incoming projectile")
	await physics_frame
	await process_frame
	check(untouched.collision_layer == 0 and untouched.self_hurtbox.collision_layer == 0 and not untouched.self_hurtbox.monitorable,"base/deferred ready callbacks do not restore the snowball's incoming hurt surface")
	check(not untouched.self_hitbox.monitoring and untouched.self_hitbox.collision_mask == 0,"outgoing contacts use the filtered sweep, not automatic projectile overlaps")
	untouched.queue_free()
	legacy.queue_free()

	var stopped:Node2D = launch_snow(source,center+Vector2(-216,-96),Vector2.RIGHT,"ZeroSpeed")
	stopped.Speed = 0.0
	stopped.default_properties.Speed = 0.0
	var stopped_ref:WeakRef = weakref(stopped)
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	check(not is_instance_valid(stopped_ref.get_ref()),"invalid zero-speed flight retires instead of leaving a stationary live snowball")
	var timed:Node2D = launch_snow(source,center+Vector2(-216,-144),Vector2.RIGHT,"Lifetime")
	timed.life = 0.08
	var timed_ref:WeakRef = weakref(timed)
	game.now_stop_state = true
	var original_point:Vector2 = timed.global_position
	await create_timer(0.12).timeout
	check(is_instance_valid(timed_ref.get_ref()) and timed.life == 0.08 and timed.global_position == original_point,"a real pause freezes flight and lifetime without falsely retiring an intact projectile")
	game.now_stop_state = false
	await create_timer(0.16).timeout
	check(not is_instance_valid(timed_ref.get_ref()),"resuming consumes the remaining lifetime and removes the projectile")
	var captured:Node2D = launch_snow(source,center+Vector2(-216,-192),Vector2.RIGHT,"Capture")
	var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
	var captured_ref:WeakRef = weakref(captured)
	capture.discard(captured)
	check(captured._spent and not captured.visible,"Allay capture invokes the same inert/hidden retirement path, without an impact")
	await process_frame
	check(not is_instance_valid(captured_ref.get_ref()),"captured snowball does not survive as an invisible or stationary obstacle")
	print("SNOW_CONTACT_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
