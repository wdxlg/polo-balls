extends "res://tests/test_mc16_native_feedback.gd"
func pending_bolt(pole:Node) -> Node:
	for child:Node in pole.get_children():
		if child.has_signal("impact_started") and not child._impact_started: return child
	return null
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(55.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var spider:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(-250,200))
	var drowned:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(250,200))
	var target:Node = dummy(center+Vector2(700,-400))
	spider.native_feedback.set_physics_process(false)
	drowned.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var net:Node = spider.silk_network
	for i:int in range(40): wall_touch(net,center+Vector2(-300 if i%2==0 else 300,-120+i*6))
	net.anchor = {}
	check(net.segments.size()==39,"39 fixed strands survive the former 16-strand limit")
	var first:Dictionary = net.segments[0]
	var old_start:Vector2 = net._point(first.start)
	net._sample_left = 100000.0
	for i:int in range(60): net.advance(60.0)
	check(net.segments.size()==39,"fixed strands survive one simulated hour without expiration")
	check(net.segments[0].id==first.id and net._point(net.segments[0].start)==old_start,"oldest strand and its endpoint are not replaced by later strands")
	reset_silk(net)
	for point:Vector2 in [Vector2(-120,-80),Vector2(120,80),Vector2(120,-80),Vector2(-120,80)]: wall_touch(net,center+point)
	net.anchor = {}
	net._update_crossings()
	net._sample_left = 100000.0
	net.advance(3600.0)
	check(net.segments.size()==3 and net.webs.size()==1,"supported crossing web remains with permanent silk")
	var poles:Array[Node] = []
	for i:int in range(12):
		var pole:Node = drowned._create_trident(100+i)
		pole.set_physics_process(false)
		pole.stick(center+Vector2(700+i*15,-400))
		poles.append(pole)
	var retained:bool = true
	for pole:Node in poles: retained = retained and is_instance_valid(pole) and not pole.is_queued_for_deletion() and drowned._tridents.has(pole.serial)
	check(retained,"all 12 lodged tridents survive the former six-pole cap")
	for pole:Node in poles: pole.advance(3600.0)
	retained = true
	for pole:Node in poles: retained = retained and is_instance_valid(pole) and not pole.is_queued_for_deletion() and pole.flight_state==3
	check(retained,"lodged tridents survive one simulated hour without expiration")
	# Genuine return transitions, no inventory-pickup substitution.
	fresh(drowned)
	var held:Node = drowned._trident
	held.launch(Vector2.RIGHT)
	held.global_position = drowned.trident_hand_position()+Vector2(80,0)
	held._begin_return()
	check(count(drowned,"item.trident.return")==1,"return begins with original trident recall audio")
	held._begin_return()
	check(count(drowned,"item.trident.return")==1,"same return phase does not replay recall audio")
	held.advance(1.0)
	check(drowned.has_trident and count(drowned,"entity.item.pickup")==0,"catch finishes recall without unrelated pickup sound")
	held.launch(Vector2.LEFT)
	held._begin_return()
	check(count(drowned,"item.trident.return")==2,"a second real recall is not swallowed by a time debounce")
	held.advance(1.0)
	fresh(drowned)
	var pole:Node = poles[0]
	pole.charge()
	pole.advance(drowned.lightning_first_delay+0.01)
	var bolt:Node = pending_bolt(pole)
	check(is_instance_valid(bolt),"long-lived charged pole still schedules lightning")
	bolt.set_process(false)
	check(count(drowned,"item.trident.thunder")==0 and count(drowned,"entity.lightning_bolt.thunder")==1,"native Creeper thunder warns without premature trident impact thunder")
	check(count(drowned,"entity.generic.explode")==0,"Creeper impact sound waits for actual impact")
	bolt._process(drowned.lightning_warning*0.5)
	check(count(drowned,"item.trident.thunder")==0,"pre-impact portion does not play trident impact audio")
	var hp:float = target.health
	bolt._process(drowned.lightning_warning*0.51)
	check(bolt._impact_started and target.health<hp,"native audio change preserves timed lightning damage")
	check(count(drowned,"item.trident.thunder")==1 and count(drowned,"entity.generic.explode")==1,"impact plays original trident thunder and Creeper impact sound once")
	var bank:Script = load("res://scripts/effects/我的世界/mc16_sound_bank.gd")
	var native:bool = false
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")=="item.trident.thunder": native = player.stream in bank.EVENTS["item.trident.thunder"] and player.pitch_scale==1.0
	check(native,"impact uses the original trident thunder OGG at original pitch")
	hp = target.health
	bolt._start_impact()
	bolt._process(0.02)
	check(count(drowned,"item.trident.thunder")==1 and target.health==hp,"repeated visual updates cannot duplicate impact audio or damage")
	check(count(drowned,"entity.generic.explode")==1,"duplicate impact does not replay the added Creeper layer")
	pole.lightning_left = 0.01
	pole.advance(0.02)
	bolt = pending_bolt(pole)
	bolt.set_process(false)
	game.now_stop_state = true
	bolt._process(10.0)
	check(not bolt._impact_started and count(drowned,"item.trident.thunder")==1,"pause freezes pending strike and its sound")
	game.now_stop_state = false
	bolt._process(drowned.lightning_warning+0.01)
	check(count(drowned,"item.trident.thunder")==2,"next periodic strike plays its own channeling thunder")
	drowned.set_multiplayer_authority(2)
	var replica:Node = load("res://scripts/effects/我的世界/trident_lightning.gd").new()
	replica.caster = drowned
	replica.setup(pole.global_position,123,drowned.lightning_radius,drowned.lightning_warning)
	pole.add_child(replica)
	replica.set_process(false)
	replica._start_impact()
	check(count(drowned,"item.trident.thunder")==2,"non-authority lightning replica cannot originate duplicate thunder")
	drowned.set_multiplayer_authority(1)
	replica.queue_free()
	# Non-natural lifecycle cleanup is intentionally retained.
	var wall := Node2D.new()
	world.add_child(wall)
	var attached:Node = drowned._create_trident(200)
	attached.set_physics_process(false)
	attached.stick(center+Vector2(500,500),wall)
	reset_silk(net)
	wall_touch(net,center+Vector2(-200,100))
	net._contact_left = 0.0
	net.touch_wall(center+Vector2(200,100),wall)
	wall.queue_free()
	await process_frame
	await process_frame
	attached.advance(0.01)
	net.advance(0.01)
	check(attached.is_queued_for_deletion(),"destroying a support wall still cleans its trident")
	check(net.segments.is_empty(),"destroying a support wall still invalidates its silk")
	drowned.health = 0
	pole.advance(0.01)
	check(pole.is_queued_for_deletion(),"owner death still cleans its trident rather than orphaning it")
	print("MC16_PERSISTENCE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
