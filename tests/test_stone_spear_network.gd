extends SceneTree
const SCENE_PATH:String = "res://scenes/characters/我的世界/石矛.tscn"
var checks:int=0
var failures:int=0
var done:bool=false
var stance_audio_count:int=0
var stance_streams:Array[AudioStream]=[]
var audio_streams:Dictionary={}
func heard_stance(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.has_meta("mc_sound_event"):
		var event:String=node.get_meta("mc_sound_event")
		if not audio_streams.has(event): audio_streams[event]=[]
		audio_streams[event].append(node.stream)
	if node is AudioStreamPlayer2D and node.get_meta("mc_sound_event","")=="minecraft:item.spear.use":
		stance_audio_count+=1
		stance_streams.append(node.stream)
var world:Node2D
var host_root:Node2D
var guest_root:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func until(condition:Callable,seconds:float=4.0) -> bool:
	var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call(): return true
		await process_frame
	return false
func spawner(parent:Node2D) -> void:
	var node:=MultiplayerSpawner.new()
	node.name="Spawner"
	node.spawn_path=NodePath("..")
	node.add_spawnable_scene(SCENE_PATH)
	parent.add_child(node)
func run() -> void:
	create_timer(35.0).timeout.connect(func(): print("STONE_NETWORK_TIMEOUT"); quit(2))
	var game:Node=root.get_node("Game")
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	world=Node2D.new()
	root.add_child(world)
	current_scene=world
	node_added.connect(heard_stance)
	host_root=Node2D.new()
	guest_root=Node2D.new()
	host_root.name="Host"
	guest_root.name="Guest"
	world.add_child(host_root)
	world.add_child(guest_root)
	host_api=SceneMultiplayer.new()
	guest_api=SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer=ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"ENet host starts")
	host_api.multiplayer_peer=host_peer
	guest_peer=ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"ENet guest starts")
	guest_api.multiplayer_peer=guest_peer
	spawner(host_root)
	spawner(guest_root)
	check(await until(func(): return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"two independent APIs connect")
	var host:Variant=load(SCENE_PATH).instantiate()
	host.name="Spear"
	host.position=Vector2(120,180)
	host_root.add_child(host)
	host.state_machine.set_physics_process(false)
	host.permanent_speed_bonus=83.0
	host._switch_wait=0.0
	host.set_formation(1)
	host._transition_left=0.0
	host._orbit=0.4
	for i:int in range(4):
		var pose:Dictionary=host.formation_pose(i,210.0)
		host._centers[i]=host.global_position+pose.offset
		host._angles[i]=pose.angle
	host._store_pose()
	check(await until(func(): return guest_root.has_node("Spear")),"production scene spawned remotely")
	if not guest_root.has_node("Spear"): quit(1); return
	var guest:Variant=guest_root.get_node("Spear")
	guest.state_machine.set_physics_process(false)
	check(await until(func(): return guest.formation==1 and is_equal_approx(guest.permanent_speed_bonus,83.0)),"stance and permanent speed replicated")
	check(host.is_multiplayer_authority() and not guest.is_multiplayer_authority(),"client is never damage authority")
	check(await until(func(): return guest._pose_state==host._pose_state),"all four copy poses use authoritative snapshot")
	host._formation_heading=0.7
	host._formation_center=host.global_position+Vector2(-2,1)
	check(await until(func(): return is_equal_approx(guest._formation_heading,0.7) and guest._formation_center.is_equal_approx(host._formation_center)),"smoothed formation frame synchronizes over ENet")
	guest._process(0.0)
	for i:int in range(4):
		check(guest._copies[i].global_position.distance_to(host._copies[i].global_position)<0.01 or guest._centers[i].distance_to(host._centers[i])<0.01,"copy %d position synchronized" % i)
	host._apply_pose()
	guest._process(0.0)
	check(host._tip_guards.size()==4 and guest._tip_guards.size()==4,"four guard shapes on each peer")
	for i:int in range(4):
		check(host._tip_guards[i].global_position.distance_to(guest._tip_guards[i].global_position)<0.01,"guard follows authoritative visible pose on guest")
		check(host._tip_guards[i].collision_layer==2 and guest._tip_guards[i].collision_layer==0,"only authority registers gameplay guard collisions")
	var attacker:Node2D=load("res://scenes/ball.tscn").instantiate()
	attacker.Team="Team1"
	host.Team="Team0"
	world.add_child(attacker) # local fixture, not an unregistered network spawn
	attacker.state_machine.set_physics_process(false)
	attacker.self_hitbox.monitoring=false
	attacker.self_hitbox.global_position=host._tip_guards[0].global_position
	var contact_point:Vector2=host._tip_guards[0].global_position
	check(not attacker.self_hitbox.try_hit_hurtbox(host._tip_guards[0]),"network authority rejects real guard contact")
	check(await until(func(): return guest.last_sound_event=="stone_spear.block"),"reliable guard sound reaches guest")
	check(host.guard_feedback_count==1 and guest.guard_feedback_count==1,"exactly one guard feedback on each peer")
	check(guest.last_guard_position.distance_to(contact_point)<0.01,"guest receives actual copy tip impact position")
	guest.on_incoming_hit_rejected(attacker.self_hitbox)
	check(guest.guard_feedback_count==1,"guest cannot locally re-emit a block decision")
	attacker.queue_free()
	var old:int=guest.formation
	guest._switch_wait=0.0
	check(not guest.choose_formation() and guest.formation==old,"client cannot reroll formation")
	var before_switch:int=stance_audio_count
	host._switch_wait=0.0
	host.set_formation(2)
	check(await until(func(): return guest.last_sound_event=="minecraft:item.spear.use" and stance_audio_count>=before_switch+2),"reliable stance sound plays on both peers")
	check(stance_audio_count==before_switch+2,"one accepted switch creates exactly one audio player per peer")
	check(stance_streams[-1]==stance_streams[-2],"both peers play the authority-selected native variant")
	check(host.last_sound_gain==0.0 and guest.last_sound_gain==0.0,"same 0dB stance audio gain on both peers")
	check(not host.set_formation(2) and not guest.set_formation(0),"duplicate stance and non-authority switch rejected")
	for i:int in range(4): guest._process(0.0)
	await process_frame
	await process_frame
	check(stance_audio_count==before_switch+2,"rejected actions and repeated snapshots do not duplicate switch audio")
	host._transition_left=0.0
	host._stab_wait=0.0
	host._real_speed=250.0
	for i:int in range(4):
		var pose:Dictionary=host.formation_pose(i,250.0)
		host._centers[i]=host.global_position+pose.offset
		host._angles[i]=pose.angle
	check(host.begin_stab(),"authority begins real stroke")
	check(host._formation_heading==host._angles[0]+PI*0.5,"launch locks already visible follower heading")
	host._store_pose()
	check(await until(func(): return guest.formation==2 and is_equal_approx(guest._stab_time,0.0) and guest._stab_axes==host._stab_axes),"stroke phase and locked axes replicated")
	guest._process(0.0)
	check(host._tip_guards[0].collision_layer==0 and guest._tip_guards[0].collision_layer==0,"switch away removes guard on both peers")
	check(await until(func(): return guest.last_sound_event=="minecraft:item.spear.attack"),"reliable original stab audio event reaches guest")
	check(await until(func(): return audio_streams.get("minecraft:item.spear.attack",[]).size()==2),"attack event creates one audio player on each peer")
	check(audio_streams["minecraft:item.spear.attack"][0]==audio_streams["minecraft:item.spear.attack"][1] and audio_streams["minecraft:item.spear.attack"][0] in host.STAB_SOUNDS,"both peers preserve exact native spear attack variant")
	for damage:float in [49.0,50.0,51.0]:
		var event:String="minecraft:item.spear.hit" if damage<50.0 else "entity.player.hurt" if damage==50.0 else "entity.player.attack.crit"
		var count_before:int=audio_streams.get(event,[]).size()
		host._emit_audio(true,host.global_position,damage)
		check(await until(func(): return guest.last_sound_event==event and audio_streams.get(event,[]).size()>=count_before+2),"actual-damage sound boundary replicated at %s" % damage)
		check(audio_streams[event].size()==count_before+2,"exactly one hit sound per peer")
		check(audio_streams[event][-1]==audio_streams[event][-2],"both peers receive identical selected hit variant")
		check(is_equal_approx(guest.last_sound_gain,host.HIT_GAIN.damage_gain(damage)),"actual-damage audio gain preserved on guest")
	host._emit_audio(true,host.global_position,80.0)
	check(await until(func(): return guest.last_sound_event=="entity.player.attack.crit" and is_equal_approx(guest.last_sound_gain,host.last_sound_gain)),"actual-damage crit audio replicated")
	check(is_equal_approx(host.last_sound_gain,guest.last_sound_gain),"same audio gain on both peers")
	# Clients create only local visual snapshots from replicated actual speed/poses.
	for form:int in range(3):
		host._stab_time=-1.0
		if host.formation!=form: host.set_formation(form)
		host._transition_left=0.0
		host._real_speed=400.0
		host._stab_time=0.05 if form==2 else -1.0
		for i:int in range(4):
			var pose:Dictionary=host.formation_pose(i,400.0)
			host._centers[i]=host.global_position+pose.offset+Vector2(form*3,0)
			host._angles[i]=pose.angle
		host._store_pose()
		host._apply_pose()
		host._process(0.04)
		check(await until(func(): return guest.formation==form and is_equal_approx(guest._real_speed,400.0) and guest._pose_state==host._pose_state),"trail speed and pose replicated in formation %d" % form)
		guest._process(0.04)
		check(not guest._copy_trails.samples.is_empty(),"guest renders copy trails in formation %d" % form)
		var sample:Dictionary=guest._copy_trails.samples.back()
		check(sample.sprite.global_position.distance_to(guest._copies[sample.tag].global_position)<0.01,"guest snapshot uses authoritative visible copy position")
	check(not guest.is_multiplayer_authority() and guest._tip_guards[0].collision_layer==0,"visual trail generation grants no gameplay authority")
	host._stab_time=host.stab_out_time+0.1
	check(await until(func(): return guest._stab_time>host.stab_out_time),"return phase replicated")
	var previous_count:int=guest._copy_trails.total_emitted
	guest._process(0.3)
	check(guest._copy_trails.total_emitted==previous_count and guest._copy_trails.samples.is_empty(),"guest return phase creates no new ghosts and old trail expires")
	# Fully gathered offsets must remain exact on the client, not a visual-only illusion.
	host._stab_time=-1.0
	host.set_formation(0)
	host._transition_left=0.0
	host._real_speed=600.0
	for i:int in range(4):
		var gathered:Dictionary=host.formation_pose(i,600.0)
		host._centers[i]=host.global_position+gathered.offset
		host._angles[i]=gathered.angle
	host._apply_pose()
	host._store_pose()
	check(await until(func(): return guest.formation==0 and guest._pose_state==host._pose_state),"fully gathered zero offsets synchronize")
	guest._process(0.0)
	for i:int in range(4):
		check(guest._centers[i]==guest.global_position and guest._copies[i].global_position.is_equal_approx(guest.image.global_position),"remote copy position exactly overlaps body")
		check(host._tip_guards[i].collision_layer==0 and guest._tip_guards[i].collision_layer==0,"fully gathered follow does not inherit orbit guard")
	var guest_trails:Node2D=guest._copy_trails
	host.queue_free()
	check(await until(func(): return not guest_root.has_node("Spear")),"despawn removes all four remote copies")
	await process_frame
	check(not is_instance_valid(guest_trails),"remote despawn removes local trail container")
	host_api.multiplayer_peer=null
	guest_api.multiplayer_peer=null
	set_multiplayer(null,host_root.get_path())
	set_multiplayer(null,guest_root.get_path())
	host_peer.close()
	guest_peer.close()
	world.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	host_api=null
	guest_api=null
	host_peer=null
	guest_peer=null
	print("STONE_NETWORK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
