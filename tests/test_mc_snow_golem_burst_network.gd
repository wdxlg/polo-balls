extends "res://tests/test_mc_snow_golem_burst.gd"
## Real ENet transport, scoped World2Ds, live fracture RPC and late actor state.
class Arena extends Node2D:
	func _current_map_node() -> Node: return self
	func return_map_world_rect(_map:Node) -> Rect2: return Rect2(-320,-240,640,480)
	func is_combat_runtime_active() -> bool: return true

var host_scope:Node2D
var guest_scope:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer

func until(condition:Callable,seconds:float = 5.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false

func scope(label:String) -> Node2D:
	var view:=SubViewport.new()
	view.name = label
	view.size = Vector2i(512,384)
	view.world_2d = World2D.new()
	world.add_child(view)
	var node:Node2D = Arena.new()
	node.name = "Arena"
	view.add_child(node)
	return node

func golem(parent:Node2D) -> Node2D:
	var node:Node2D = load(GOLEM_PATH).instantiate()
	node.name = "Golem"
	node.Team = "Team0"
	parent.add_child(node)
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.set_process(false)
	node._field.set_physics_process(false)
	node._shot_left = 0.0
	node.burst_probability = 0.0
	return node

func opponent(parent:Node2D) -> Node2D:
	var node:Node2D = load("res://scenes/ball.tscn").instantiate()
	node.name = "Victim"
	node.Team = "Team1"
	node.Max_health = 10000
	node.Health_Restore = 0
	node.Has_Collision_Damage = false
	parent.add_child(node)
	node.global_position = Vector2(130,0)
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.Can_Attack = false
	node.Can_Skill = false
	return node

func fractures(parent:Node) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCBlockFragments"):
		if parent.is_ancestor_of(node) and node.has_meta("snow_pumpkin_break"): result.append(node)
	return result

func finish(code:int) -> void:
	if done: return
	done = true
	game.now_stop_state = true
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self): code = 1
	for parent:Node2D in [host_scope,guest_scope]:
		if not is_instance_valid(parent): continue
		for child:Node in parent.get_children(): child.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(host_scope): set_multiplayer(null,host_scope.get_path())
	if is_instance_valid(guest_scope): set_multiplayer(null,guest_scope.get_path())
	if host_peer!=null: host_peer.close()
	if guest_peer!=null: guest_peer.close()
	if host_api!=null: host_api.multiplayer_peer = null
	if guest_api!=null: guest_api.multiplayer_peer = null
	host_api = null; guest_api = null; host_peer = null; guest_peer = null
	var file:=FileAccess.open(evidence.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	print("SNOW_BURST_NETWORK_RESULT checks=",checks," failures=",failures)
	current_scene = null
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	await create_timer(0.15,true,false,true).timeout
	quit(code)

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
	evidence = OS.get_environment("SNOW_GOLEM_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://snow_burst_network"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(85,true,false,true).timeout.connect(func():finish(2))
	host_scope = scope("SnowHost")
	guest_scope = scope("SnowGuest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_scope.get_path())
	set_multiplayer(guest_api,guest_scope.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"real snow-golem authority starts an ephemeral ENet listener")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"guest starts its own real ENet transport")
	guest_api.multiplayer_peer = guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"separate SceneMultiplayer roots complete their handshake")
	var source:Node2D = golem(host_scope)
	var remote:Node2D = golem(guest_scope)
	var target:Node2D = opponent(host_scope)
	var remote_target:Node2D = opponent(guest_scope)
	await physics_frame
	await process_frame
	check(source._field!=remote._field and source.get_world_2d()!=remote.get_world_2d(),"golems use separate terrain managers and physics worlds")
	check(source.is_multiplayer_authority() and not remote.is_multiplayer_authority(),"only server owns attack scheduling")
	check(source.nearest_snow_enemy()==target and not source.RULES.enemy(source,remote_target),"target acquisition cannot select a different peer's world")
	source.take_damage(ceilf(source.Max_health*0.5),true)
	check(await until(func():return not remote.has_pumpkin and remote.force_next_burst),"real half-health state and next-attack guarantee reach the guest")
	check(await until(func():return fractures(host_scope).size()==1 and fractures(guest_scope).size()==1),"live break RPC creates one actual block-fragment effect in EACH correct world")
	var local_effect:Node2D = fractures(host_scope)[0]
	var remote_effect:Node2D = fractures(guest_scope)[0]
	local_effect.set_process(false)
	remote_effect.set_process(false)
	var same:bool = local_effect.pieces.size()==remote_effect.pieces.size()
	for i:int in range(local_effect.pieces.size()):
		for key:String in ["start","landing","flight","height","spin"]: same = same and local_effect.pieces[i][key]==remote_effect.pieces[i][key]
	check(same,"one authoritative cosmetic seed produces matching native shard trajectories")
	source._show_pumpkin_break.rpc(1,source.global_position,0,0.2,42)
	for i:int in range(4): await process_frame
	check(fractures(guest_scope).size()==1,"duplicate fracture packet does not replay the break")
	remote.accept_visual({"pumpkin":true,"break_count":0,"force_burst":false})
	check(not remote.has_pumpkin and remote.head_break_count==1,"stale pre-break visual snapshot cannot restore the pumpkin")
	check(not remote.fire_at(remote_target.global_position,remote_target),"guest cannot consume its replicated guarantee to start an independent attack")
	check(source.fire_at(target.global_position,target),"authority uses the guarantee to start a volley with random probability zero")
	shots(source)
	source._new5_visual.rpc(source.network_visual_state())
	check(await until(func():return remote._burst_remaining==19 and shots(remote).size()==1),"volley progress and first actual projectile reach the guest")
	var wait:float = remote._burst_wait
	remote.step_mob(2.0)
	check(remote._burst_wait==wait and shots(remote).size()==1,"replica never integrates or duplicates scheduled releases")
	while source._burst_remaining>0:
		source.step_mob(0.05)
		shots(source)
		await process_frame
	source._new5_visual.rpc(source.network_visual_state())
	check(await until(func():return shots(remote).size()==20 and remote._burst_remaining==0),"the complete twenty-shot attack is replicated, not re-rolled locally")
	var own:Array[Node2D] = shots(source)
	var other:Array[Node2D] = shots(remote)
	check(own.size()==20 and other.size()==20,"authority and replica each have exactly the same twenty real projectiles")
	var projectile_match:bool = true
	for i:int in range(mini(own.size(),other.size())):
		projectile_match = projectile_match and own[i].direction.is_equal_approx(other[i].direction) and own[i].Damage==other[i].Damage and other[i].Master==remote and other[i].get_parent()==guest_scope
	check(projectile_match,"per-shot direction, damage, owner and battle scope agree across ENet")
	target.global_position = own[0].global_position+own[0].direction*100.0
	await physics_frame
	var hp:int = target.health
	own[0].move(260.0,0.65)
	check(target.health<hp,"one real authoritative burst projectile still settles original damage")
	var guest_hp:int = remote_target.health
	other[1].tick_physics(other[1].State.Move,0.5)
	check(remote_target.health==guest_hp,"remote projectile cannot deal a second local hit")
	var source_pose:int = source.direction_pose(Vector2.UP)
	source._aim_hold_left = 0.25 # Only attack aim uses a full upward/rear view now.
	source._aim = Vector2.UP
	source.direction = Vector2.UP
	source.visual_mob()
	source._new5_visual.rpc(source.network_visual_state())
	check(await until(func():return remote._visual_heading==Vector2.UP),"authoritative full heading reaches the other peer")
	remote.direction = Vector2.LEFT
	remote.visual_mob()
	check(remote._aim_pose==source_pose and not remote.is_character_visual_flipped_h(),"client uses the native rear pose rather than mirroring its stale local movement")
	# Recreate only the client actor to exercise its real initial-state request.
	# Retire through the actual authority protocol BEFORE replacing the actor;
	# deleting only guest bullets would intentionally break their synchronizers.
	for shot:Node2D in shots(source): shot.expire()
	check(await until(func():return shots(source).is_empty() and shots(remote).is_empty()),"authority retirement clears both peers before actor recreation")
	for i:int in range(3): await process_frame
	remote.free()
	remote = golem(guest_scope)
	check(await until(func():return not remote.has_pumpkin and remote.head_break_count==1 and remote.shots_fired==source.shots_fired),"late/recreated actor requests current head and attack state instead of resetting it")
	remote.accept_visual({"revision":0,"pumpkin":true,"break_count":0,"force_burst":true,"burst_remaining":19})
	check(not remote.has_pumpkin and not remote.force_next_burst and remote._burst_remaining==0,"stale pre-volley packet cannot rearm a consumed guarantee or restore an ended burst")
	check(fractures(guest_scope).size()==1,"late state snapshot does not replay the old shatter event")
	check(not remote._field.has_method("_spawn_mini") and not source._field.has_method("drop_head"),"neither peer retains an obsolete summon RPC or pumpkin construction path")
	finish(0 if failures==0 else 1) # Release run() locals before asynchronous teardown.
