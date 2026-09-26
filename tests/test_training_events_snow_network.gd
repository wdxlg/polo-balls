extends "res://tests/test_training_events_snow.gd"
## One process, independent SceneMultiplayer APIs and real ENet transport.
var host_root:Node2D
var guest_root:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer

func until(condition:Callable,seconds:float = 4.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false

func finish(code:int) -> void:
	if done: return
	game.now_stop_state = true
	# Let synchronizers unregister while their original APIs still own the subtree.
	for scope:Node in [host_root,guest_root]:
		if not is_instance_valid(scope): continue
		scope.process_mode = Node.PROCESS_MODE_DISABLED
		for child:Node in scope.get_children(): child.queue_free()
	await process_frame
	if is_instance_valid(host_root): set_multiplayer(null,host_root.get_path())
	if is_instance_valid(guest_root): set_multiplayer(null,guest_root.get_path())
	if host_peer!=null: host_peer.close()
	if guest_peer!=null: guest_peer.close()
	print("TRAINING_SNOW_NETWORK checks=",checks," failures=",failures)
	await super.finish(code)

func arena(name_value:String) -> Node2D:
	var view:=SubViewport.new()
	view.name = name_value+"View"
	view.size = Vector2i(512,512)
	view.world_2d = World2D.new()
	world.add_child(view)
	var scope:=Node2D.new()
	scope.name = "Arena"
	view.add_child(scope)
	return scope

func target(scope:Node2D) -> Node2D:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.name = "Victim"
	unit.Team = "Team1"
	unit.Has_Collision_Damage = false
	scope.add_child(unit)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.self_hitbox.monitoring = false
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	unit.Max_health = 10000
	unit.default_properties.Max_health = 10000
	unit.health = 10000
	return unit

func source(scope:Node2D) -> Node2D:
	# Actual production neutral-source API, with geometry intentionally supplied by this network fixture.
	var node:Node2D = load("res://scripts/training/battle_conditions.gd").new(scope)
	node.environment = "snow"
	scope.add_child(node)
	node.set_physics_process(false)
	return node

func run() -> void:
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Development_Mode = false
	await setup_world()
	saved = original_settings
	create_timer(65,true,false,true).timeout.connect(func():finish(2))
	world.set_process(false)
	world.set_physics_process(false)
	world.battle_conditions.set_physics_process(false)
	host_root = arena("SnowHost")
	guest_root = arena("SnowGuest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	var error:Error = host_peer.create_server(0,1)
	check(error==OK,"snow authority starts a real ephemeral ENet server")
	if error!=OK: await finish(1); return
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	error = guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())
	check(error==OK,"independent client creates its own transport")
	guest_api.multiplayer_peer = guest_peer
	var connected:bool = await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED)
	check(connected,"real ENet handshake completes between distinct multiplayer roots")
	if not connected: await finish(1); return
	var host_target:Node2D = target(host_root)
	var guest_target:Node2D = target(guest_root)
	var host_source:Node2D = source(host_root)
	var guest_source:Node2D = source(guest_root)
	var host_field:Node2D = FIELD.ensure(host_source,host_root)
	host_field.environment_source = host_source
	host_source.field = host_field
	host_field.set_physics_process(false)
	var ground:Dictionary = {"cell":Vector2i.ZERO,"decorative":false,"rects":[Rect2(-12,-12,24,24)]}
	var wall:Dictionary = {"cell":Vector2i(0,-2),"decorative":true,"rects":[Rect2(-12,-49,24,2)]}
	# Before a guest-side field exists, exercise a genuine late snapshot rather than sending RPCs to a missing node.
	host_field._environment_state([ground,wall],true)
	host_field._clock = 500.0
	var guest_field:Node2D = FIELD.ensure(guest_source,guest_root)
	guest_field.environment_source = guest_source
	guest_source.field = guest_field
	guest_field.set_physics_process(false)
	check(await until(func():return guest_field.environment_patches==host_field.environment_patches),"late field requests permanent ground and decorative wall state across ENet")
	check(host_field.is_multiplayer_authority() and not guest_field.is_multiplayer_authority(),"only the server owns sparse snow gameplay")
	check(host_field.get_world_2d()!=guest_field.get_world_2d(),"replicas use independent physics worlds")
	check(guest_field._clock<10 and guest_field.environment_patches.size()==2,"late join does not mistake server absolute age for a melting deadline")
	check(not guest_field.add_environment_patch(guest_source,{"cell":Vector2i.ONE,"decorative":false,"rects":[Rect2(12,12,24,24)]}),"client cannot independently generate damaging weather cells")
	var local_walls:Array[Rect2] = [Rect2(-12,-49,24,2)]
	for snow_field:Node2D in [host_field,guest_field]:
		snow_field.wall_view.visual_walls = local_walls.duplicate()
		snow_field.wall_view.weather_bounds = Rect2(-256,-256,512,512)
		snow_field.wall_view.set_weather(true)
		snow_field.wall_view.request_update()
	var authoritative:Dictionary = guest_field.environment_patches.duplicate(true)
	guest_source.advance(0.5)
	check(is_equal_approx(guest_field.wall_view.weather_time,0.5) and guest_field.wall_view.weather_fade>0.0,"non-authority client runs its own native falling-snow animation")
	check(guest_field.environment_patches==authoritative,"client precipitation does not generate, replace or age authoritative snow cells")
	game.now_stop_state = true
	guest_source.advance(2.0)
	check(is_equal_approx(guest_field.wall_view.weather_time,0.5),"client weather animation respects the combat pause")
	game.now_stop_state = false
	for i:int in range(3): await process_frame
	check(is_instance_valid(host_field.wall_view.mesh_node) and is_instance_valid(guest_field.wall_view.mesh_node),"both ENet peers independently build actual 3D decorative snow from one replicated record")
	var hp:int = host_target.health
	host_field.check_ground()
	check(host_target.health==hp-3,"authority resolves neutral snow through the real cold damage pipeline")
	check(await until(func():return guest_target.has_node("MCSnowCold")),"host cold state reaches the correct victim under the guest's own world")
	var remote_cold:Node = guest_target.get_node("MCSnowCold")
	check(is_equal_approx(remote_cold.amount,8.0),"network contact keeps the original snow-golem cold gain")
	var guest_hp:int = guest_target.health
	guest_field.advance(10.0)
	check(guest_target.health==guest_hp,"replica never performs an extra local damage tick")
	var host_cold:Node = host_target.get_node("MCSnowCold")
	host_cold.set_physics_process(false)
	host_cold.add_cold(32,1.4,host_source)
	check(await until(func():return is_equal_approx(remote_cold.amount,40.0)),"reliable status updates accumulate on one shared remote cold meter")
	guest_target.cold_effect_ratio = 0.0
	host_field.sync_cold(host_target,100,1.4,1.4)
	for i:int in range(8): await process_frame
	check(remote_cold.amount==0 and remote_cold.frozen_left==0 and not guest_target.dizziness,"a replicated freeze cannot bypass recipient cold immunity")
	guest_target.cold_effect_ratio = 1.0
	host_field.clear_environment()
	check(await until(func():return guest_field.environment_patches.is_empty()),"turning off weather clears only the synchronized environmental layer")
	host_field.add_environment_patch(host_source,ground)
	check(await until(func():return guest_field.environment_patches.size()==1),"incremental authority snow placement reaches the client")
	clear_cold(guest_target)
	guest_field.free()
	guest_field = FIELD.ensure(guest_source,guest_root)
	guest_source.field = guest_field
	guest_field.environment_source = guest_source
	guest_field.set_physics_process(false)
	check(await until(func():return guest_field.environment_patches.size()==1 and guest_target.has_node("MCSnowCold")),"recreated client field requests both snow and existing victim cold state")
	check(is_equal_approx(guest_target.get_node("MCSnowCold").amount,40.0),"late status snapshot is world-scoped and retains the authoritative amount")
	await check_guest_permissions()
	await finish(0 if failures==0 else 1)

func check_guest_permissions() -> void:
	var original_role:String = game.network_role
	var server_root:=Node.new()
	server_root.name = "SettingsPermissionHost"
	world.add_child(server_root)
	var server_api:=SceneMultiplayer.new()
	var client_api:=SceneMultiplayer.new()
	set_multiplayer(server_api,server_root.get_path())
	set_multiplayer(client_api,game.get_path())
	var server:=ENetMultiplayerPeer.new()
	server.set_bind_ip("127.0.0.1")
	var error:Error = server.create_server(0,1)
	check(error==OK,"permissions probe creates a separate real settings connection")
	server_api.multiplayer_peer = server
	var client:=ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1",server.get_host().get_local_port())
	client_api.multiplayer_peer = client
	check(await until(func():return client.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"Game facade has a connected client-side multiplayer API")
	game.network_role = "client"
	setting("Guest_Free_Permissions",false)
	var panel:Control = world.control.settings_category_boxes.training.get_node("BattleConditionsSettings")
	panel.refresh()
	check(not game.can_local_change_settings() and panel.event_toggle.disabled and panel.environment_option.disabled,"restricted guest sees Events and Environment disabled")
	var before:Dictionary = game.Game_Settings.duplicate(true)
	panel._on_environment_selected(1)
	panel._on_event_toggled(true,"test_only")
	game.set_runtime_game_setting("Random_Events",true,false)
	check(game.Game_Settings==before,"UI callbacks and the public settings API cannot bypass guest permissions")
	setting("Guest_Free_Permissions",true)
	panel.refresh()
	check(game.can_local_change_settings() and not panel.environment_option.disabled and not panel.event_toggle.disabled,"host-granted free permissions enable the new controls consistently")
	game.network_role = original_role
	set_multiplayer(null,game.get_path())
	set_multiplayer(null,server_root.get_path())
	client.close()
	server.close()
	server_root.queue_free()
	setting("Guest_Free_Permissions",false)
	panel.refresh()
