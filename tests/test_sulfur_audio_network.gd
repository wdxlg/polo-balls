extends "res://tests/test_sulfur_cube_dual_network.gd"
## Extend the existing two real ENet peers; no second damage or snapshot-replayed sound.
var _audio_checks_running:bool = false

func cue_count(unit:Node,event:StringName) -> int:
	var count:int = 0
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sulfur_event",&"")==event and int(node.get_meta("mc_sulfur_source",0))==unit.get_instance_id(): count += 1
	return count

func cue_node(unit:Node,event:StringName) -> Node:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sulfur_event",&"")==event and int(node.get_meta("mc_sulfur_source",0))==unit.get_instance_id(): return node
	return null

func quiet(host:Node,guest:Node) -> void:
	await process_frame
	await process_frame
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop()
		node.free()
	host._sound_time.clear()
	guest._sound_time.clear()
	host._motion_audio_ticket.clear()
	guest._motion_audio_ticket.clear()

func finish(code:int) -> void:
	if done or _audio_checks_running: return
	if code != 0:
		super.finish(code)
		return
	_audio_checks_running = true
	var host:Node2D = host_root.get_node("NetworkSulfurCube")
	var guest:Node2D = guest_root.get_node("NetworkSulfurCube")
	await quiet(host,guest)
	for event:StringName in [&"ice_hit",&"magma_hit",&"honey_grab",&"iron_hit",&"tnt_hit",&"amethyst_launch"]:
		host._emit_sound(event,host.global_position)
		check(await until(func(): return cue_count(host,event)==1 and cue_count(guest,event)==1),"one "+String(event)+" cue is played exactly once per actual peer")
		var a:Node = cue_node(host,event)
		var b:Node = cue_node(guest,event)
		check(a != null and b != null and a.stream.resource_path==b.stream.resource_path and a.get_meta("mc_sulfur_variant")==b.get_meta("mc_sulfur_variant"),"authority selects the same original variant for both peers")
		await quiet(host,guest)
	guest._emit_sound(&"honey_grab",guest.global_position)
	await create_timer(0.15,true,false,true).timeout
	check(cue_count(host,&"honey_grab")==0 and cue_count(guest,&"honey_grab")==0,"replica cannot originate an extra local or remote contact cue")

	check(not host.AUDIO.EVENTS.has(&"iron_land") and not guest.AUDIO.EVENTS.has(&"iron_land"),"both peers use the bank without the removed iron landing cue")
	host._emit_sound(&"iron_land")
	await process_frame
	await process_frame
	check(cue_count(host,&"iron_land")==0 and cue_count(guest,&"iron_land")==0,"a stale landing event cannot originate or replay on either peer")
	host.set_block(host.Block.ICE)
	check(await until(func(): return guest.has_block(guest.Block.ICE)),"uncapped ice trait is replicated before the movement probe")
	var start_point:Vector2 = host.global_position
	var saved_mask:int = host.collision_mask
	var saved_speed:float = host.Speed
	host.collision_mask = 0
	host.Speed = 130.0
	host._slide_velocity = Vector2.RIGHT*130.0
	host._ice_bounce_hold = 0.0
	host.player_control_direction = Vector2.RIGHT
	var surface:Node2D = host.ICE_TRAIL.new()
	world.add_child(surface)
	surface.setup(host,Rect2(start_point-Vector2(2000,2000),Vector2(4000,4000)))
	surface.set_physics_process(false)
	var controller:Node = host.ICE_TRAIL.ACCELERATION.touch(host,surface)
	controller.set_physics_process(false)
	for i:int in range(50):
		await physics_frame
		controller._physics_process(1.0/60.0)
		host.move(host.Speed,1.0/60.0)
	check(controller.momentum.length()>117.0 and host._actual_speed>250.0,"authority physically accelerates past the ordinary surface cap")
	check(await until(func(): return absf(guest._actual_speed-host._actual_speed)<0.01),"actual uncapped impact/threat speed reaches the replica")
	check(guest.get_node_or_null("SurfaceAcceleration")==null,"replica does not create another acceleration simulation")
	controller.free()
	surface.free()
	host.Speed = saved_speed
	host.collision_mask = saved_mask
	host.global_position = start_point
	host._slide_velocity = Vector2.ZERO
	await quiet(host,guest)

	host.set_block(host.Block.HONEY)
	check(await until(func(): return guest.has_block(guest.Block.HONEY)),"honey state reaches the guest before contact audio")
	await quiet(host,guest)
	var a_victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	a_victim.name = "AudioHoneyVictim"
	a_victim.Team = "Team1"
	host_root.add_child(a_victim)
	a_victim.state_machine.set_physics_process(false)
	a_victim.set_physics_process(false)
	a_victim.global_position = host.global_position+Vector2(5,0)
	var b_victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	b_victim.name = "AudioHoneyVictim"
	b_victim.Team = "Team1"
	guest_root.add_child(b_victim)
	b_victim.state_machine.set_physics_process(false)
	b_victim.set_physics_process(false)
	b_victim.global_position = guest.global_position+Vector2(600,0)
	host._pull_touching_enemies(0.0)
	check(await until(func(): return cue_count(host,&"honey_grab")==1 and cue_count(guest,&"honey_grab")==1 and guest.get_collision_exceptions().has(b_victim)),"actual grab replication has one sticky cue and one matching remote pair lease")
	await quiet(host,guest)
	for i:int in range(10): host._pull_touching_enemies(0.01)
	await create_timer(0.15,true,false,true).timeout
	check(cue_count(host,&"honey_grab")==0 and cue_count(guest,&"honey_grab")==0,"membership refresh does not replay sticky contact on either peer")
	host._pull_touching_enemies(0.9)
	check(await until(func(): return cue_count(host,&"honey_release")==1 and cue_count(guest,&"honey_release")==1 and not guest.get_collision_exceptions().has(b_victim)),"one-second release produces one matching cue and removes both pair leases")
	a_victim.queue_free()
	b_victim.queue_free()
	await quiet(host,guest)
	game.now_stop_state = true
	host._emit_sound(&"iron_hit")
	await process_frame
	check(cue_count(host,&"iron_hit")==0 and cue_count(guest,&"iron_hit")==0,"paused contact audio does not broadcast or allocate a remote sound")
	game.now_stop_state = false
	print("SULFUR_AUDIO_NETWORK checks=",checks," failures=",failures)
	super.finish(0 if failures==0 else 1)
