extends "res://tests/test_mc_snow_golem_burst_network.gd"
## Real ENet: authoritative variant/serial and queued playback in each local World2D.
func audio_player(ticket:Dictionary) -> AudioStreamPlayer2D:
	return load("res://scripts/characters/我的世界/snow_golem/audio.gd").action_player(ticket)
func audible(ticket:Dictionary) -> bool:
	return is_instance_valid(audio_player(ticket)) and audio_player(ticket).playing
func cues(parent:Node,event:String) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCSnowSound"):
		if parent.is_ancestor_of(node) and node.get_meta("mc_sound_event","")==event: result.append(node)
	return result

func replicate_pose(source:Node2D,remote:Node2D,pose:int) -> bool:
	# Production resends this unreliable_ordered stream every 75ms. A one-shot
	# fixture packet may legitimately be discarded among mixed-size ENet updates.
	var next_send:Array[int] = [0]
	return await until(func():
		if remote._aim_pose==pose: return true
		if Time.get_ticks_msec()>=next_send[0]:
			next_send[0] = Time.get_ticks_msec()+75
			source._new5_visual.rpc(source.network_visual_state())
		return false)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	evidence = OS.get_environment("GOLEM_ACTION_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://golem_action_network"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(70,true,false,true).timeout.connect(func():finish(2))
	host_scope = scope("ActionHost")
	guest_scope = scope("ActionGuest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_scope.get_path())
	set_multiplayer(guest_api,guest_scope.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"action audio starts a real ENet server")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"action audio client has an independent transport")
	guest_api.multiplayer_peer = guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"action audio peers complete handshake")
	var source:Node2D = golem(host_scope)
	var remote:Node2D = golem(guest_scope)
	var target:Node2D = opponent(host_scope)
	opponent(guest_scope)
	await physics_frame
	await process_frame
	check(not remote._request_action_sound("block.snow.step","walk",-3),"replica cannot invent authoritative movement cues")
	check(source._request_action_sound("block.snow.step","wall",0),"server accepts a physical-contact cue through the shared channel")
	check(await until(func():return audible(source._step_audio) and audible(remote._step_audio)),"both worlds obtain an actually playing native step")
	var host_voice:AudioStreamPlayer2D = audio_player(source._step_audio)
	var guest_voice:AudioStreamPlayer2D = audio_player(remote._step_audio)
	check(host_voice.get_parent()==host_scope and guest_voice.get_parent()==guest_scope and host_voice.get_world_2d()!=guest_voice.get_world_2d(),"sound parent follows the correct peer's World2D, not the global current-scene canvas")
	check(host_voice.stream==guest_voice.stream and host_voice.get_meta("mc_snow_variant")==guest_voice.get_meta("mc_snow_variant"),"one authority-selected original step variant is shared by both peers")
	var count:int = cues(guest_scope,"block.snow.step").size()
	source._receive_action_sound.rpc(source._sound_serial,"block.snow.step",int(host_voice.get_meta("mc_snow_variant")),source.global_position,0.0,"wall")
	for i:int in range(3): await process_frame
	check(cues(guest_scope,"block.snow.step").size()<=count,"duplicate reliable serial cannot replay an overlapping step")
	check(source.fire_at(target.global_position,target),"real authoritative attack emits its original snowball")
	shots(source)
	check(await until(func():return audible(source._shoot_audio) and audible(remote._shoot_audio)),"actual projectile release plays a launch cue in both peers")
	host_voice = audio_player(source._shoot_audio)
	guest_voice = audio_player(remote._shoot_audio)
	check(host_voice.stream==guest_voice.stream and is_equal_approx(host_voice.volume_db,0.0) and host_voice.get_meta("mc_sound_priority",false),"launch stream/gain/priority match the production action contract")
	check(guest_voice.get_parent()==guest_scope and guest_voice.bus==&"GameplayRecord","guest launch uses the correct world and standard gameplay-record bus")
	source.hurt_voice_chance = 0.0
	source.take_damage(ceilf(source.Max_health*0.5),true)
	check(await until(func():return audible(source._break_audio) and audible(remote._break_audio)),"real half-health fracture has audible native wood break on both peers")
	host_voice = audio_player(source._break_audio)
	guest_voice = audio_player(remote._break_audio)
	check(host_voice.stream==guest_voice.stream and host_voice.get_meta("mc_snow_phase","")=="pumpkin_break" and guest_voice.get_parent()==guest_scope,"fracture variant and critical phase metadata survive peer scoping")
	check(not source.has_pumpkin and remote.force_next_burst,"audio changes preserve the half-health gameplay guarantee")
	count = cues(guest_scope,"block.wood.break").size()
	source._show_pumpkin_break.rpc(1,source.global_position,0,0.2,33)
	for i:int in range(3): await process_frame
	check(cues(guest_scope,"block.wood.break").size()<=count,"duplicate fracture cannot double its audio")
	game.now_stop_state = true
	check(not source._request_action_sound("entity.snow_golem.shoot","shot",0.0),"paused battle cannot start new native action cues")
	source._process(0.0)
	remote._process(0.0)
	if is_instance_valid(guest_voice): check(guest_voice.stream_paused,"ongoing local phase sound freezes with battle pause")
	game.now_stop_state = false
	source._process(0.0)
	remote._process(0.0)
	# A coarse frame generates a real 20-projectile volley in one batch. Reliable
	# delivery must not suppress all but the first sound on either endpoint.
	var emitted:Array[int] = [0,0]
	var launches:Callable = func(node:Node):
		if not node is AudioStreamPlayer2D or node.get_meta("mc_sound_event","")!="entity.snow_golem.shoot": return
		if node.get_meta("mc_snow_source",0)==source.get_instance_id(): emitted[0]+=1
		elif node.get_meta("mc_snow_source",0)==remote.get_instance_id(): emitted[1]+=1
	node_added.connect(launches)
	source._shot_left = 0.0
	source.burst_probability = 1.0
	var previous:int = source.shots_fired
	check(source.fire_at(target.global_position,target),"real guaranteed volley starts for per-shot audio replication")
	source.step_mob(3.0)
	shots(source)
	check(source.shots_fired-previous==20,"coarse frame still creates twenty actual snowballs")
	check(await until(func():return emitted[0]>=20 and emitted[1]>=20),"all twenty native launch players start in EACH independent peer world")
	check(emitted==[20,20],"no lost or extra launch starts despite a late reliable batch")
	var last:AudioStreamPlayer2D = audio_player(source._shoot_audio)
	source._receive_action_sound.rpc(source._sound_serial,"entity.snow_golem.shoot",int(last.get_meta("mc_snow_variant")),source.global_position,0.0,"shot")
	for i:int in range(4): await process_frame
	check(emitted==[20,20],"duplicate audio serial cannot replay the final shot")
	node_added.disconnect(launches)
	game.now_stop_state = true
	source._process(0.0); remote._process(0.0)
	var paused_all:bool = true
	for actor:Node2D in [source,remote]:
		for ticket:Dictionary in actor._shoot_voices:
			var voice:AudioStreamPlayer2D = audio_player(ticket)
			if is_instance_valid(voice): paused_all = paused_all and voice.stream_paused
	check(paused_all,"both peers pause the complete overlapping voice collection")
	game.now_stop_state = false
	source._process(0.0); remote._process(0.0)
	source._stop_movement_and_launch_audio(); remote._stop_movement_and_launch_audio()

	# Full actor visual state still distinguishes walking from attack heading.
	source._aim_hold_left = 0
	source.direction = Vector2.LEFT
	source.visual_mob()
	check(source._aim_pose==6,"authority selects the actual front-left walking pose")
	check(await replicate_pose(source,remote,6),"client receives front-left diagonal walking pose")
	source._aim = Vector2.UP
	source._aim_hold_left = 0.25
	source.visual_mob()
	check(source._aim_pose==12,"authority selects the exact upward attack pose")
	check(await replicate_pose(source,remote,12),"client still receives exact upward attack aim")
	print("GOLEM_ACTION_NETWORK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1) # Release run() locals before asynchronous world teardown.
