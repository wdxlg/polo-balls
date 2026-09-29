extends "res://tests/test_mc16_spider_drowned.gd"
func count(unit:Node,event:String) -> int: return int(unit.native_feedback.played.get(event,0))
func clear_voices() -> void:
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		player.stop()
		player.remove_from_group("MCNativeSFX")
		player.queue_free()
func fresh(unit:Node) -> void:
	clear_voices()
	unit.native_feedback._clock += 1.0
	unit.native_feedback._last.clear()
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
	var spider:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(180,0))
	var other:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(500,500))
	var drowned:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-300,300))
	var target:Node = dummy(center)
	for actor:Node in [spider,other,drowned]: actor.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var net:Node = spider.silk_network
	var bank:Script = load("res://scripts/effects/我的世界/mc16_sound_bank.gd")
	check(net.COBWEB_TEXTURE.get_size()==Vector2(16,16),"original cobweb is 16x16")
	check(net.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"cobweb keeps native hard pixel edges")
	for event:String in bank.EVENTS:
		var valid:bool = not bank.EVENTS[event].is_empty()
		for stream:AudioStream in bank.EVENTS[event]: valid = valid and stream is AudioStreamOggVorbis and stream.get_length()>0.0
		check(valid,"native OGGs import/decode: "+event)
	fresh(spider)
	var f:Node = spider.native_feedback
	f._last_position = spider.global_position
	f.advance(0.5)
	check(count(spider,"entity.spider.step")==0,"stationary spider is silent")
	spider.global_position += Vector2(20,0)
	f.advance(0.3)
	check(count(spider,"entity.spider.step")==1,"actual spider travel produces native step")
	spider.dizziness = true
	spider.global_position += Vector2(20,0)
	f.advance(0.3)
	check(count(spider,"entity.spider.step")==1,"stunned spider does not step")
	spider.dizziness = false
	spider.global_position += Vector2(400,0)
	f.advance(0.016)
	check(count(spider,"entity.spider.step")==1,"teleport does not manufacture steps")
	spider.global_position = center+Vector2(180,0)
	fresh(drowned)
	drowned.native_feedback._last_position = drowned.global_position
	drowned.global_position += Vector2(20,0)
	drowned.native_feedback.advance(0.3)
	check(count(drowned,"entity.drowned.step")==1,"drowned travel uses its native step bank")
	fresh(spider)
	for p:Vector2 in [Vector2(-120,-80),Vector2(120,80),Vector2(120,-80),Vector2(-120,80)]:
		f._clock += 0.2
		wall_touch(net,center+p)
	net.anchor = {}
	f._clock += 0.2
	net._update_crossings()
	check(net.webs.size()==1 and count(spider,"block.cobweb.place")>0,"wall silk/crossing emits original cobweb placement")
	var placed:int = count(spider,"block.cobweb.place")
	f._clock += 0.3
	net._update_crossings()
	check(count(spider,"block.cobweb.place")==placed,"persistent crossing does not replay placement every tick")
	fresh(spider)
	target.global_position = center
	net._tick_contacts()
	check(count(spider,"block.cobweb.step")==0,"stationary trapped enemy does not emit walking sound")
	check(count(spider,"entity.spider.lunge")==0,"pounce does not bypass the independent breathing timer")
	net._tick_contacts()
	check(count(spider,"block.cobweb.step")==0,"high-frequency damage does not manufacture walking sounds")
	fresh(drowned)
	target.global_position = drowned.trident_hand_position()+Vector2(60,0)
	check(drowned.throw_trident(target),"audio fixture throws at valid enemy")
	var spear:Node = drowned._trident
	spear.set_physics_process(false)
	check(count(drowned,"item.trident.throw")==1,"throw emits native trident throw")
	spear.advance(0.5)
	check(count(drowned,"item.trident.hit")==1,"hit emits native trident pierce")
	check(count(drowned,"item.trident.return")==1,"return transition emits loyalty recall once")
	spear._begin_return()
	check(count(drowned,"item.trident.return")==1,"duplicate return transition stays silent")
	spear.advance(1.0)
	check(count(drowned,"entity.item.pickup")==0 and count(drowned,"item.trident.return")==1,"catch keeps the native return cue without adding pickup sound")
	fresh(drowned)
	spear.launch(Vector2.RIGHT)
	spear.stick(center+Vector2(400,300))
	check(count(drowned,"item.trident.hit_ground")==1,"wall embedding emits native ground impact")
	spear.stick(center)
	check(count(drowned,"item.trident.hit_ground")==1,"already embedded spear does not replay impact")
	spear.charge()
	spear.charge()
	check(count(drowned,"block.enchantment_table.use")==1,"first enchant uses native enchanting-table audio exactly once")
	check(count(drowned,"item.trident.riptide_1")==0,"enchant cue no longer substitutes the old riptide sound")
	fresh(drowned)
	drowned._new_trident()
	drowned._trident.set_physics_process(false)
	check(count(drowned,"entity.experience_orb.pickup")==1 and count(drowned,"entity.item.pickup")==0,"only delayed replacement uses XP ding instead of item pickup")
	drowned._trident.charge()
	fresh(drowned)
	drowned.emit_trident_arc(spear,drowned._trident)
	drowned.emit_trident_arc(spear,drowned._trident)
	check(count(drowned,"block.redstone_torch.burnout")==1 and count(drowned,"item.trident.thunder")==0,"network burst uses one native electrical fizz, not thunder or one cue per edge")
	fresh(spider)
	fresh(other)
	var voice:AudioStreamPlayer2D = f.request("block.cobweb.place",center,-9.0,0.2)
	var peer:AudioStreamPlayer2D = other.native_feedback.request("block.cobweb.place",center,-9.0,0.2)
	check(is_instance_valid(voice) and is_instance_valid(peer),"different spiders do not globally suppress each other's sounds")
	check(f.request("block.cobweb.place",center,-9.0,0.2)==null,"same-source same-event cooldown rejects duplicate")
	check(voice.pitch_scale==1.0 and voice.stream is AudioStreamOggVorbis,"original OGG plays at original pitch")
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: check(voice.bus==&"GameplayRecord","mechanic sounds join gameplay recording bus")
	# AudioStreamPlayer2D starts pending play in its internal physics callback.
	await physics_frame
	await physics_frame
	game.now_stop_state = true
	f.advance(0.2)
	check(voice.stream_paused,"battle pause suspends owned active sounds")
	check(f.request("entity.spider.lunge",center)==null,"battle pause rejects new ability audio")
	game.now_stop_state = false
	f.advance(0.2)
	check(not voice.stream_paused,"battle resume continues sound")
	spider.set_multiplayer_authority(2)
	check(f.request("entity.spider.lunge",center)==null,"non-authority does not originate replicated cue")
	spider.set_multiplayer_authority(1)
	fresh(spider)
	for i:int in range(40): f.request("block.cobweb.step",center,-15.0,0.0)
	check(get_nodes_in_group("MCNativeSFX").size()<=24,"mechanic sounds share bounded 24-voice pool")
	fresh(other)
	var owned:AudioStreamPlayer2D = other.native_feedback.request("entity.spider.lunge",center)
	other.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(owned) or owned.is_queued_for_deletion(),"destroyed actor cleans owned mechanic audio")
	print("MC16_NATIVE_FEEDBACK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
