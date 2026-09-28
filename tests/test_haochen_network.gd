extends "res://tests/test_sulfur_cube_redesign_network.gd"
const HERO_PATH:String = "res://scenes/characters/我的世界/皓宸.tscn"
const REQUEST_PATH:String = "res://scenes/effects/我的世界/角色复制请求.tscn"
var closing:bool = false

func spawner(parent:Node2D) -> void:
	var spawn := MultiplayerSpawner.new()
	spawn.name = "HaochenSpawner"
	spawn.spawn_path = NodePath("..")
	for path:String in [HERO_PATH,REQUEST_PATH,"res://scenes/ball.tscn","res://scenes/characters/我的世界/末影人.tscn"]: spawn.add_spawnable_scene(path)
	parent.add_child(spawn)

func frozen(node:Node) -> void:
	if node.is_in_group("Ball"):
		node.state_machine.set_physics_process(false)
		node.set_physics_process(false)
		node.Has_Collision_Damage = false

func copies(parent:Node) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in parent.get_children():
		if node.is_in_group("Ball") and not node.character_copy_profile.is_empty(): result.append(node)
	return result

func audio_count(unit:Node,event:StringName) -> int:
	var result:int = 0
	for node:Node in get_nodes_in_group("MCHaochenAudio"):
		if int(node.get_meta("haochen_source",0))==unit.get_instance_id() and node.get_meta("haochen_event",&"")==event: result+=1
	return result

func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():print("HAOCHEN_NETWORK_TIMEOUT");finish(2))
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	host_root=Node2D.new();host_root.name="HaochenHost"
	guest_root=Node2D.new();guest_root.name="HaochenGuest"
	world.add_child(host_root);world.add_child(guest_root)
	host_api=SceneMultiplayer.new();guest_api=SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path());set_multiplayer(guest_api,guest_root.get_path())
	host_peer=ENetMultiplayerPeer.new();host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"authoritative ENet endpoint starts")
	host_api.multiplayer_peer=host_peer
	guest_peer=ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"independent replica endpoint connects")
	guest_api.multiplayer_peer=guest_peer
	spawner(host_root);spawner(guest_root)
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"two genuine peers complete their handshake")
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var host:Node2D=load(HERO_PATH).instantiate()
	host.name="NetworkHaochen";host.Team="Team0";host.position=center
	host_root.add_child(host,true);frozen(host)
	check(await until(func():return guest_root.has_node("NetworkHaochen")),"real Haochen scene is spawned on the guest")
	var guest:Node=guest_root.get_node("NetworkHaochen");frozen(guest)
	check(host.is_multiplayer_authority() and not guest.is_multiplayer_authority(),"only host owns energy and spawn decisions")
	var donor:Node2D=load("res://scenes/ball.tscn").instantiate()
	donor.name="NetworkEnergyDonor";donor.Team="Team1";donor.position=center+Vector2(20,0)
	donor.Max_health=600;donor.Damage=80;donor.Speed=150.0;donor.max_block=40;donor.max_energy=80;donor.Attack_Cooling=1.6
	host_root.add_child(donor,true);frozen(donor)
	check(await until(func():return guest_root.has_node("NetworkEnergyDonor")),"donor scene reaches the replica")
	var guest_donor:Node=guest_root.get_node("NetworkEnergyDonor");frozen(guest_donor)
	host._scan_left=0.0
	host._step_energy(2.0)
	check(is_equal_approx(host.charge_energy,40.0),"authority counts its donor once, not the guest-side mirror in the same test process")
	check(await until(func():return is_equal_approx(guest.charge_energy,40.0) and is_equal_approx(guest.movement_ratio,host.movement_ratio)),"energy bar and gradual slowdown replicate")
	check(await until(func():return audio_count(host,&"charge_start")==1 and audio_count(guest,&"charge_start")==1),"the user-supplied charge-start clip plays once on each peer")
	guest._step_energy(10.0)
	check(guest.charge_energy==40.0 and copies(guest_root).is_empty(),"replica cannot add energy or create a second summon")
	host._step_energy(3.0)
	var request:Node=host._copy_request.get_ref();request.set_physics_process(false)
	check(await until(func():return guest_root.has_node(str(request.name))),"confirmed copy cast has a real replicated request node")
	var mirrored:Node=guest_root.get_node(str(request.name))
	check(mirrored.template_snapshot.scene==donor.scene_file_path and mirrored.owner_name==str(host.name),"copy identity and owner are data snapshots, not client-side enemy selection")
	check(mirrored.source_name==str(donor.name) and is_equal_approx(mirrored.body_scale,0.5),"guest request knows the copied character by name and the half body scale")
	check(await until(func():return mirrored._assemble!=null or mirrored._soul_gather),"guest draws its own spawn gathering locally (pixel assembly, or souls without a readable frame)")
	check(await until(func():return mirrored.link_visible and mirrored.link_from.distance_to(donor.global_position)<1.0 and mirrored.link_to.distance_to(host.global_position)<1.0),"guest receives the authoritative source-to-Haochen link points")
	check(await until(func():return guest.image.texture==guest.FACE_LAUGH and host.image.texture==host.FACE_LAUGH),"both peers show the laughing face during the cast")
	mirrored._emit_link_particles(4,false)
	var guest_link:int = 0
	for raw:Node in get_nodes_in_group("MCHaochenLinkParticle"):
		if int(raw.get_meta("haochen_copy_request",0))==mirrored.get_instance_id(): guest_link += 1
	check(guest_link>=4,"guest draws its own local link particles from replicated points")
	request._physics_process(host.copy_duration)
	check(await until(func():return copies(host_root).size()==1 and copies(guest_root).size()==1),"one authoritative cast creates exactly one original-scene copy per peer")
	var a:Node=copies(host_root)[0];var b:Node=copies(guest_root)[0];frozen(a);frozen(b)
	check(a.scene_file_path==donor.scene_file_path and b.scene_file_path==donor.scene_file_path,"host and guest copies retain the actual donor scene and abilities")
	check(await until(func():return a.Max_health==300 and b.Max_health==300 and b.Damage==40 and b.Speed==150.0),"spawn-profile synchronization carries half stats and unmodified speed")
	check(a.Master==host and b.Master==guest and a.Team=="Team0" and b.Team=="Team0","subordinate ownership resolves to the corresponding peer's Haochen")
	check(b.character_copy_profile.monochrome and b.image.get_instance_shader_parameter("character_grayscale")==1.0,"guest copy is truly grayscale without sharing the original material state")
	check(await until(func():return a.scale.is_equal_approx(donor.scale*0.5) and b.scale.is_equal_approx(a.scale)),"the half-size copy root scale replicates to the guest")
	check((b.get_node("Health_Bar") as Control).scale.is_equal_approx((donor.get_node("Health_Bar") as Control).scale) and (b.get_node("Health_Bar") as Control).get_global_transform().get_scale().abs().is_equal_approx((donor.get_node("Health_Bar") as Control).get_global_transform().get_scale().abs()*0.5),"guest copy health bar is not counter-scaled: it shrinks to half with the copy")
	check(await until(func():return guest.charge_energy==0.0 and guest.completed_copies==1),"successful cast resets the meter once and replicates its completion")
	check(a.Attack_Cooling==1.6 and b.Attack_Cooling==1.6,"copying does not secretly halve skill/attack cooldowns")
	game.now_stop_state=true
	var energy:float=host.charge_energy
	host._step_energy(20.0)
	await process_frame
	check(host.charge_energy==energy and copies(host_root).size()==1,"pause cannot accumulate or duplicate copies")
	game.now_stop_state=false
	print("HAOCHEN_NETWORK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func replicated_children(parent:Node) -> int:
	var count:int = 0
	for node:Node in parent.get_children():
		if node.scene_file_path in [HERO_PATH,REQUEST_PATH,"res://scenes/ball.tscn","res://scenes/characters/我的世界/末影人.tscn"]: count += 1
	return count

func finish(code:int) -> void:
	if done or closing:return
	closing=true
	if is_instance_valid(host_root):
		for node:Node in host_root.get_children():
			if not node is MultiplayerSpawner:node.queue_free()
		var deadline:int=Time.get_ticks_msec()+2500
		while is_instance_valid(guest_root) and replicated_children(guest_root)>0 and Time.get_ticks_msec()<deadline:await process_frame
		if code==0:check(replicated_children(guest_root)==0,"networked copies and cast nodes despawn before peer teardown; local particle/audio tails are not network bodies")
	done=true
	if code==0 and failures>0:code=1
	if host_api!=null:host_api.multiplayer_peer=null
	if guest_api!=null:guest_api.multiplayer_peer=null
	if host_peer!=null:host_peer.close()
	if guest_peer!=null:guest_peer.close()
	if is_instance_valid(host_root):set_multiplayer(null,host_root.get_path())
	if is_instance_valid(guest_root):set_multiplayer(null,guest_root.get_path())
	if is_instance_valid(world):world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25,true,false,true).timeout
	game.Game_Settings=saved;game.now_stop_state=saved_stop
	print("HAOCHEN_NETWORK_FINAL checks=",checks," failures=",failures)
	quit(code)
