extends "res://tests/test_mc_frontier.gd"
func clear_audio() -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop()
		node.remove_from_group("MCNativeSFX")
		node.queue_free()
func hurt_sounds() -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sound_event","")=="entity.player.hurt": result.append(node)
	return result
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	var point:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = point
	moss.FOOTSTEPS.ensure(moss).set_physics_process(false)
	var a:Node2D = dummy(point)
	var b:Node2D = dummy(point)
	await physics_frame
	check(moss.Max_health==550 and moss.health==550 and moss.default_properties.Max_health==550,"moss spawns at 550 current, maximum and base health")
	moss.plant(point)
	clear_audio()
	moss.check_trampling()
	check(a.health==9990 and b.health==9990,"ground moss deals ten damage to both victims")
	var players:Array[Node] = hurt_sounds()
	check(players.size()==2,"same-frame victims each receive MC hurt feedback")
	for player:Node in players:
		check(is_equal_approx(player.volume_db,moss.impact_volume(10.0)),"ground hit volume measures actual damage")
		check(player.get_meta("mc_sound_priority",false),"damage feedback receives voice priority")
	moss.check_trampling()
	check(hurt_sounds().size()==2,"no duplicated audio when no further damage tick occurred")
	moss.plant(point)
	moss.plant(point)
	clear_audio()
	moss.clock += 0.81
	moss.check_trampling()
	players = hurt_sounds()
	check(players.size()==2 and a.health==9960 and b.health==9960,"three-layer ticks emit feedback per damaged victim")
	for player:Node in players: check(player.volume_db>moss.impact_volume(10.0),"higher moss damage is louder")
	clear_audio()
	a.Damage_reduction = 0.5
	b.max_block = 1000
	b.block = 1000
	moss.clock += 0.81
	moss.check_trampling()
	players = hurt_sounds()
	check(players.size()==1,"shield-only damage produces no health-loss sound")
	if players.size()==1: check(is_equal_approx(players[0].volume_db,moss.impact_volume(15.0)),"mitigation reduces actual hit volume")
	clear_audio()
	a.Damage_reduction = 0.0
	b.block = 0
	for i:int in range(24): moss.AUDIO.play(moss,"block.moss.place",point,-10.0,false,false,true,true)
	check(get_nodes_in_group("MCNativeSFX").size()==24,"voice-cap fixture fills ambient slots")
	moss.clock += 0.81
	moss.check_trampling()
	check(hurt_sounds().size()==2 and get_nodes_in_group("MCNativeSFX").size()<=24,"ground damage remains audible at voice cap without unbounded voices")
	var ender:Node2D = actor("末影人",center+Vector2(300,0))
	ender.side_status_set_permanent("right","mc_anger","旧状态文字",Color.RED)
	for rage:float in [0.0,3.0]:
		ender.rage_remaining = rage
		ender.gaze_charge = 0.8
		ender._update_anger_status()
		check(ender._anger_text.is_empty() and not ender.side_status_ui._right_permanent_labels.has("mc_anger"),"anger/rage text is removed without being recreated")
		check(ender.rage_remaining==rage and ender.gaze_charge==0.8,"removing text leaves rage mechanics unchanged")
	check(ender.side_status_ui_enabled,"normal HUD/status support remains enabled")
	print("MC REQUEST CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
