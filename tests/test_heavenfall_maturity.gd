extends "res://tests/test_heavenfall_tuning_audio.gd"

func reset_charges() -> void:
	bow._cancel_rift_transit()
	bow._rift_cool = 0.0
	bow._rift_grace = 0.0
	for ref in bow._rifts:
		var old: Variant = ref.get_ref()
		if is_instance_valid(old): old.queue_free()
	bow._rifts.clear()

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(70.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for other: Node in get_nodes_in_group("Ball"):
		other.process_mode = Node.PROCESS_MODE_DISABLED
		other.remove_from_group("Ball")
		(other as Node2D).global_position = Vector2(4000,4000)
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",center+Vector2(-120,0))
	bow.state_machine.set_physics_process(false)
	bow.set_process(false)
	victim = _mk_enemy(center+Vector2(140,60))
	await physics_frame
	await process_frame
	bow.spawn_heaven_rift(center,Vector2.RIGHT)
	var rift: Node2D = bow._rifts.back().get_ref()
	rift.set_process(false)
	check(rift._age==0.0 and rift.opening_time==0.5,"new main fracture starts at zero with the existing half-second opening")
	check(rift.is_open() and not rift.is_mature() and not rift.can_transit(),"opening fracture remains alive but is not a teleport charge yet")
	bow._prune_rifts()
	check(bow._rifts.size()==1 and bow._live_rift_count()==1,"immature fracture is retained and counts toward the unchanged capacity")
	check(not rift.reserve_transit() and not rift.reserve_transit(true) and not rift.is_reserved(),"authority cannot reserve an immature fracture even with a replay flag")
	clear_sounds()
	check(not bow._try_rift_dodge() and bow._rift_cool==0.0 and bow._rift_grace==0.0,"failed immature dodge consumes no cooldown or invulnerability")
	var last_id: int = bow._last_transit_id
	bow._apply_rift_dodge(bow.global_position,rift.landing,rift.rift_id,rift._points[0])
	check(not bow.is_rift_transiting() and bow._last_transit_id==last_id and event_nodes("entity.heavenfall.teleport").is_empty(),"authoritative action entry cannot bypass maturity or play a false departure")
	bow._apply_rift_dodge(bow.global_position,rift.landing,99999,rift._points[0])
	check(not bow.is_rift_transiting() and bow._last_transit_id==last_id,"missing authoritative fracture cannot create a phantom teleport")
	rift._age = rift.opening_time-0.0001
	check(not rift.is_mature() and not bow._try_rift_dodge(),"almost visually open is still unavailable immediately before the boundary")
	var hp: float = bow.health
	check(bow.receive_positional_damage(10,bow.global_position,false,victim) and bow.health<hp and not bow.is_rift_transiting(),"real incoming damage is not negated when only an immature fracture exists")
	var age: float = rift._age
	game.now_stop_state = true
	rift._process(1.0)
	check(rift._age==age and not rift.can_transit(),"game pause cannot mature a fracture")
	game.now_stop_state = false
	paused = true
	rift._process(1.0)
	check(rift._age==age and not rift.can_transit(),"tree pause cannot mature a fracture")
	paused = false
	rift._age = rift.opening_time
	check(rift.is_mature() and rift.can_transit() and rift._opening_factor()==1.0,"exact opening completion unlocks teleport")
	hp = bow.health
	check(not bow.receive_positional_damage(10,bow.global_position,false,victim) and bow.health==hp and bow.is_rift_transiting(),"the same incoming hit is dodged once the fracture matures")
	check(rift.is_reserved() and not rift.can_transit() and not rift.reserve_transit(),"mature reservation still permits only one use")
	check(is_equal_approx(bow._rift_cool,bow.rift_dodge_cooldown),"successful mature dodge keeps its existing cooldown")
	reset_charges()
	var near: Node2D = _mature_rift_fixture(bow,center+Vector2(-50,-50))
	near._age = 0.1
	var far: Node2D = _mature_rift_fixture(bow,center+Vector2(80,-50))
	check(bow._try_rift_dodge() and far.is_reserved() and not near.is_reserved(),"selection skips the nearer immature fracture and chooses the mature one")
	check(bow._rift_transit.target.is_equal_approx(far.landing),"animation destination is the selected mature fracture")
	bow._cancel_rift_transit()
	bow._prune_rifts()
	check(near in [bow._rifts[0].get_ref()] and near.is_open(),"unused immature fracture survives consuming another charge")
	reset_charges()
	var custom: Node2D = _mature_rift_fixture(bow,center)
	custom.opening_time = 0.75
	custom._age = 0.5
	check(not custom.can_transit(),"maturity follows configured opening duration rather than a hardcoded half second")
	custom._process(0.25)
	check(custom.can_transit(),"normal fracture clock unlocks the configured mature boundary")
	custom._age = custom._life
	check(not custom.can_transit() and not custom.reserve_transit(),"expiry wins even for a mature fracture")
	reset_charges()
	for i in range(bow.rift_max_active+1):
		bow.spawn_heaven_rift(center+Vector2(0,-60),Vector2.RIGHT)
		bow._rifts.back().get_ref().set_process(false)
	check(bow._rifts.size()==bow.rift_max_active and bow._live_rift_count()==bow.rift_max_active,"new immature charges still obey the original maximum-rift eviction rule")
	reset_charges()
	var rain: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_rain_rift.gd").new()
	world.add_child(rain)
	rain.configure_impact(center,77)
	rain.set_process(false)
	rain._age = 0.2
	check(rain.opening_time==0.15 and bow._rifts.is_empty() and not bow._try_rift_dodge(),"small rain cracks keep their original timing and never become teleport charges")
	rain.queue_free()
	# Reliable authority replay must not depend on a delayed peer's local birth clock.
	var client: Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",center+Vector2(-80,80))
	client.state_machine.set_physics_process(false)
	client.set_process(false)
	client.set_multiplayer_authority(2)
	var remote: Node2D = _mature_rift_fixture(client,center+Vector2(30,30),801)
	remote._age = 0.1
	check(not remote.reserve_transit() and not client._try_rift_dodge(),"replica never initiates an immature dodge itself")
	hp = victim.health
	client._apply_rift_dodge(client.global_position,remote.landing,remote.rift_id,remote._points[0])
	check(client.is_rift_transiting() and remote.is_reserved(),"confirmed authority action reserves and replays despite a lagging visual clock")
	client._advance_rift_transit(client.TRANSIT.TOTAL_TIME+0.01)
	check(victim.health==hp and not client.is_rift_transiting(),"replica replay finishes without duplicating authoritative damage")
	client.queue_free()
	print("HEAVENFALL_MATURITY_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
