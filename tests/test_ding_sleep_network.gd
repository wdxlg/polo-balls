extends SceneTree
const CAT:String="res://scenes/characters/默认/丁某人睡觉.tscn"
var checks:int=0
var failures:int=0
var world:Node2D
var hroot:Node2D
var groot:Node2D
var ha:SceneMultiplayer
var ga:SceneMultiplayer
var hp:ENetMultiplayerPeer
var gp:ENetMultiplayerPeer
var role_streams:Dictionary={}
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func until(f:Callable,seconds:float=3.0) -> bool:
	var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if f.call(): return true
		await process_frame
	return false
func spawner(parent:Node) -> void:
	var s:=MultiplayerSpawner.new()
	s.name="Spawner"
	s.spawn_path=NodePath("..")
	s.add_spawnable_scene(CAT)
	s.add_spawnable_scene("res://scenes/shooter/默认/丁某人_Z.tscn")
	parent.add_child(s)
func heard(n:Node) -> void:
	if n is AudioStreamPlayer2D and n.has_meta("ding_sound_role"):
		var role:String=n.get_meta("ding_sound_role")
		if not role_streams.has(role): role_streams[role]=[]
		role_streams[role].append(n.stream)
func run() -> void:
	create_timer(35).timeout.connect(func(): print("DING_NETWORK_TIMEOUT");quit(2))
	root.get_node("Game").now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	world=Node2D.new();root.add_child(world);current_scene=world
	hroot=Node2D.new();hroot.name="Host";world.add_child(hroot)
	groot=Node2D.new();groot.name="Guest";world.add_child(groot)
	ha=SceneMultiplayer.new();ga=SceneMultiplayer.new()
	set_multiplayer(ha,hroot.get_path());set_multiplayer(ga,groot.get_path())
	hp=ENetMultiplayerPeer.new();hp.set_bind_ip("127.0.0.1")
	check(hp.create_server(0,1)==OK,"real ENet server")
	ha.multiplayer_peer=hp
	spawner(hroot);spawner(groot)
	var host:Variant=load(CAT).instantiate()
	host.name="Cat";host.Team="Team0";hroot.add_child(host)
	host.state_machine.set_physics_process(false)
	host.sleep_left=17.0
	host._spawn_z("Existing_Z",Vector2(50,-80),Vector2.UP,300.0,35.0)
	var old_z:Variant=hroot.get_node("Existing_Z")
	old_z.state_machine.set_physics_process(false)
	old_z.lifetime=2.25
	var waking:Variant=load(CAT).instantiate()
	waking.name="Waking";waking.Team="Team0";waking.position=Vector2(300,0);hroot.add_child(waking)
	waking.state_machine.set_physics_process(false)
	waking._wake();waking.step_sleep(waking.wave_windup_time+waking.wave_shiver_time);waking.wave_age=0.25;waking._sync_wave(false)
	var posed:Variant=load(CAT).instantiate()
	posed.name="Posed";posed.Team="Team0";posed.position=Vector2(-300,150);hroot.add_child(posed)
	posed.state_machine.set_physics_process(false);posed._burst_wait=0
	posed.begin_burst(Vector2.RIGHT);posed.step_sleep(posed.z_windup_time);posed.step_sleep(posed.z_stretch_time)
	hroot.get_node("Posed_Z_1").state_machine.set_physics_process(false)
	var charging:Variant=load(CAT).instantiate()
	charging.name="Charging";charging.Team="Team0";charging.position=Vector2(0,400);hroot.add_child(charging)
	charging.state_machine.set_physics_process(false);charging._wake()
	charging.step_sleep(charging.wave_windup_time+0.21)
	await process_frame
	node_added.connect(heard)
	gp=ENetMultiplayerPeer.new()
	check(gp.create_client("127.0.0.1",hp.get_host().get_local_port())==OK,"real ENet client")
	ga.multiplayer_peer=gp
	check(await until(func():return groot.has_node("Cat") and groot.has_node("Waking")),"late join spawns both authoritative phases")
	if not groot.has_node("Cat"): quit(1);return
	var guest:Variant=groot.get_node("Cat")
	var g_waking:Variant=groot.get_node("Waking")
	guest.state_machine.set_physics_process(false);g_waking.state_machine.set_physics_process(false)
	check(await until(func():return is_equal_approx(guest.sleep_left,17.0)),"late join preserves paused 17-second countdown")
	check(await until(func():return g_waking.awake and is_instance_valid(g_waking._wave)),"late join reconstructs active local wave")
	check(g_waking.image.texture==g_waking.OPEN and not g_waking._counter.visible,"late join opens eyes and hides counter")
	check(g_waking._wave.global_position.is_equal_approx(waking.wave_origin) and is_equal_approx(g_waking._wave.radius,100.0),"wave origin and current 0.25-second radius agree")
	check(role_streams.get("wake",[]).is_empty(),"late join never replays stale wake sound")
	check(await until(func():return groot.has_node("Existing_Z")),"late join restores an already flying Z")
	var remote_old:Variant=groot.get_node("Existing_Z")
	check(await until(func():return remote_old.Master==guest),"late-join projectile resolves local owner")
	check(is_equal_approx(remote_old.lifetime,2.25) and is_equal_approx(remote_old.Speed,300.0),"late-join projectile keeps remaining lifetime and speed")
	check(role_streams.get("z",[]).is_empty(),"late join does not replay past launch audio")
	old_z.expire()
	check(await until(func():return not groot.has_node("Existing_Z")),"late-join projectile retires on both peers")
	check(await until(func():return groot.has_node("Posed")),"late join spawns a real in-progress Z attack")
	var remote_pose:Variant=groot.get_node("Posed")
	remote_pose.state_machine.set_physics_process(false)
	check(await until(func():return remote_pose.z_pose_phase==2 and remote_pose.get_node("Graphics").scale.is_equal_approx(posed.Z_TALL)),"late join reconstructs held thin/tall pose")
	posed.step_sleep(0.5)
	check(await until(func():return remote_pose.z_pose_phase==3),"last actual Z starts remote recovery")
	posed.step_sleep(posed.z_recover_time*0.5)
	check(await until(func():return remote_pose.get_node("Graphics").scale.is_equal_approx(posed.get_node("Graphics").scale)),"partial recovery shape matches over ENet")
	posed.step_sleep(posed.z_recover_time*0.5+0.001)
	check(await until(func():return remote_pose.z_pose_phase==0 and remote_pose.get_node("Graphics").scale.is_equal_approx(Vector2.ONE)),"remote body fully restores after attack")
	check(await until(func():return groot.has_node("Charging")),"late join spawns wave charge already in held tremble")
	var remote_charge:Variant=groot.get_node("Charging")
	remote_charge.state_machine.set_physics_process(false)
	check(await until(func():return remote_charge.wave_charging and is_equal_approx(remote_charge.z_pose_age,charging.z_pose_age)),"late join preserves authoritative shiver age")
	check(await until(func():return remote_charge.get_node("Graphics").transform.is_equal_approx(charging.get_node("Graphics").transform)),"late-join bottom-anchored shiver pose matches without double scaling")
	check(not is_instance_valid(remote_charge._wave) and not remote_charge._counter.visible and role_streams.get("wake",[]).is_empty(),"late-join charge has no early wave or stale wake sound")
	var remote_anchor:Vector2=remote_charge.get_node("Graphics").transform*remote_charge._pose_pivot
	check(remote_anchor.is_equal_approx(remote_charge._pose_base*remote_charge._pose_pivot),"remote shiver keeps bottom-center anchor fixed")
	charging.step_sleep(charging.wave_shiver_time-0.21)
	check(await until(func():return remote_charge.awake and is_instance_valid(remote_charge._wave)),"real charge completion emits one replicated wave")
	charging.step_sleep(charging.wave_stretch_time)
	check(await until(func():return remote_charge.get_node("Graphics").transform.is_equal_approx(charging.get_node("Graphics").transform)),"remote stronger stretch converges including anchor compensation")
	charging.step_sleep(charging.wave_duration)
	charging.step_sleep(charging.wave_recover_time+0.001)
	check(await until(func():return remote_charge.z_pose_phase==0 and remote_charge.get_node("Graphics").transform.is_equal_approx(remote_charge._pose_base)),"remote wave recovery clears all scale and position offsets")
	charging.queue_free()
	check(await until(func():return not groot.has_node("Charging")),"held-charge late-join actor cleans up")
	role_streams.erase("wake")
	check(host.is_multiplayer_authority() and not guest.is_multiplayer_authority(),"client cannot settle attacks")
	var saved:float=guest.sleep_left
	guest.step_sleep(20.0)
	check(guest.sleep_left==saved,"remote simulation cannot advance authority timer")
	host.sleep_left=11.25
	check(await until(func():return is_equal_approx(guest.sleep_left,11.25)),"live countdown synchronizes")
	host._burst_wait=0
	host.player_control_peer_id=1
	check(host.begin_burst(Vector2.RIGHT),"host starts controlled burst")
	host.step_sleep(host.z_windup_time*0.5)
	check(await until(func():return guest.z_pose_phase==1 and guest.get_node("Graphics").scale.y<1.0),"live windup squash is replicated before first shot")
	host.step_sleep(host.z_windup_time*0.5)
	for i:int in range(3):host.step_sleep(0.2)
	check(await until(func():return groot.has_node("Cat_Z_4")),"all four Z spawn remotely by reliable RPC")
	for i:int in range(1,5):
		var path:String="Cat_Z_%d" % i
		check(hroot.has_node(path) and groot.has_node(path),"paired projectile "+path)
		if hroot.has_node(path) and groot.has_node(path):
			var hz:Variant=hroot.get_node(path);var gz:Variant=groot.get_node(path)
			hz.state_machine.set_physics_process(false);gz.state_machine.set_physics_process(false)
			check(await until(func():return gz.Master==guest and not gz.is_multiplayer_authority()),"remote Z owner and authority")
			check(is_equal_approx(hz.Speed,110.0) and is_equal_approx(gz.Speed,110.0),"half-speed default Z on both peers")
			hz.direction=Vector2(1,-1).normalized()
			hz.tick_physics(0,0.05)
			check(absf(angle_difference(hz.global_rotation,hz.direction.angle()))<0.001,"authority Z faces real diagonal flight")
			check(await until(func():return absf(angle_difference(gz._z_label.get_global_transform().get_rotation(),hz.global_rotation))<0.001),"Z glyph motion facing synchronizes")
			hz.expire()
	check(await until(func():return not groot.has_node("Cat_Z_4")),"authoritative retirement removes remote projectile")
	check(role_streams.get("z",[]).size()==2,"one burst-start snore exactly once per peer")
	for i:int in range(0,2,2):
		# Packets may group local then remote sounds; compare stream multisets below.
		check(role_streams.z[i]!=null,"native shot streams survive transport")
	check(role_streams.z[0]==role_streams.z[1],"authority-selected user snore matches on both peers")
	host.sleep_left=0.01
	host.step_sleep(0.02)
	check(await until(func():return guest.wave_charging and not guest._counter.visible and not is_instance_valid(guest._wave)),"remote sees charge without early wave")
	host.step_sleep(host.wave_windup_time+host.wave_shiver_time)
	check(await until(func():return guest.awake and guest.image.texture==guest.OPEN),"live wake switches remote eye texture")
	check(await until(func():return role_streams.get("wake",[]).size()==2),"live wake audio once on each peer")
	check(role_streams.wake[0]==role_streams.wake[1],"authority-selected native wake variation matches")
	host.step_sleep(0.4)
	check(await until(func():return is_instance_valid(guest._wave) and is_equal_approx(guest._wave.radius,160.0)),"wave clock/geometry synchronizes")
	host.step_sleep(1.7)
	check(await until(func():return not guest.awake and guest._counter.visible and guest.sleep_left==60.0),"remote return to sleeping countdown")
	host.Die()
	check(await until(func():return role_streams.get("death",[]).size()==2),"death sound on both peers")
	check(role_streams.death[0]==role_streams.death[1],"death native variation matches")
	check(guest._last_death_feedback,"client shows detached Minecraft death pose")
	host.queue_free()
	check(await until(func():return not groot.has_node("Cat")),"despawn removes remote cat")
	for child:Node in hroot.get_children():
		if str(child.name).begins_with("Posed_Z_"): child.expire()
	posed.queue_free()
	check(await until(func():return not groot.has_node("Posed")),"posing actor cleanup removes remote presentation")
	waking.queue_free()
	check(await until(func():return not groot.has_node("Waking")),"despawn removes in-flight wake effect")
	await create_timer(1.1).timeout
	ha.multiplayer_peer=null;ga.multiplayer_peer=null
	set_multiplayer(null,hroot.get_path());set_multiplayer(null,groot.get_path())
	hp.close();gp.close();world.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	ha=null;ga=null;hp=null;gp=null
	print("DING_NETWORK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
