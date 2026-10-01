extends "res://tests/test_mc16_native_feedback.gd"
func seed_web(net:Node) -> void:
	reset_silk(net)
	for p:Vector2 in [Vector2(-120,-80),Vector2(120,80),Vector2(120,-80),Vector2(-120,80)]: wall_touch(net,center+p)
	net.anchor = {}
	net._update_crossings()
func total_steps(actors:Array) -> int:
	var result:int = 0
	for actor:Node in actors: result += count(actor,"block.cobweb.step")
	return result
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
	var target:Node = dummy(center)
	# Speed-buff recalculation restores default_properties, including Max_health.
	target.default_properties["Max_health"] = target.Max_health
	var friendly:Node = dummy(center,"Team0")
	var f:Node = spider.native_feedback
	f.set_physics_process(false)
	var net:Node = spider.silk_network
	var manager:Node = get_nodes_in_group("MCSpiderWebFootsteps")[0]
	await process_frame
	await process_frame
	check(spider.Max_health==500 and spider.health==500,"spider starts with 500 maximum and current health")
	check(spider.silk_damage==1.0 and spider.web_damage==1.0,"silk and extra web damage are fixed one point")
	check(spider.web_slow_multiplier==0.2,"cobweb applies an 80 percent slow")
	var script:String = FileAccess.get_file_as_string("res://scripts/effects/我的世界/spider_silk.gd")
	check(script.contains("1.0,false)") and not script.contains("draw_circle("),"silk uses a single non-antialiased thin stroke without round anchors")
	check(not script.contains("apply_stun("),"cobweb code no longer calls the stun API")
	wall_touch(net,center+Vector2(-180,0))
	var line:Dictionary = net.lines()[0]
	target.global_position = (line.a+line.b)*0.5
	spider.Damage = 1000
	var hp:float = target.health
	net._tick_contacts()
	check(hp-target.health==1.0,"one live strand deals 1 even when attack stat is 1000")
	spider.Damage = 26
	fresh(spider)
	seed_web(net)
	check(net.webs.size()==1,"completed fixed-line crossing produces a single web")
	check(count(spider,"block.cobweb.place")==1,"actual web birth emits native placement sound")
	var particles:Array[Node] = get_nodes_in_group("MCSpiderWebDebris")
	check(particles.size()==1,"actual web birth emits one moss-style particle burst")
	var debris:Node = particles[0]
	debris.set_process(false)
	check(debris.blocks.size()==6,"placement uses the same six-chip style as moss placement")
	var white:bool = true
	for block:Dictionary in debris.blocks:
		var color:Color = block.color
		white = white and color.r>0.7 and absf(color.r-color.g)<0.1 and absf(color.g-color.b)<0.1 and block.size>=1.0 and block.size<=2.0
	check(white,"web particles use native white/gray pixels, not moss green")
	var chip:Dictionary = debris.blocks[0]
	var air_time:float = chip.flight*0.5
	var ground:Vector2 = chip.start+chip.velocity*(1.0-exp(-3.0*air_time))/3.0
	check(debris.block_pose(chip,chip.delay+air_time).point.y<ground.y,"moss-style chips rise above their moving ground projection")
	net._update_crossings()
	check(get_nodes_in_group("MCSpiderWebDebris").size()==1 and count(spider,"block.cobweb.place")==1,"persistent web does not repeat particle/sound on every tick")
	target.global_position = center
	friendly.global_position = center
	target.Buff_Dic.clear()
	target.dizziness = false
	hp = target.health
	var friendly_hp:float = friendly.health
	net._tick_contacts()
	check(hp-target.health==3.0,"two intersecting strands plus web cause 1+1+1 damage")
	check(friendly.health==friendly_hp and friendly.Buff_Dic.get(spider.get_instance_id(),{}).is_empty(),"friendly actors are immune to web damage and slow")
	var buffs:Dictionary = target.Buff_Dic[spider.get_instance_id()]
	check(buffs.has("蜘蛛网") and is_equal_approx(buffs["蜘蛛网"].amount,0.2),"standing on web refreshes its strong movement slow")
	check(not target.dizziness,"web does not stun its victim")
	check(spider._lunge_left>0.0,"slow trap still calls the existing spider pounce")
	hp = target.health
	net._tick_contacts()
	check(hp-target.health==3.0 and target.Buff_Dic[spider.get_instance_id()].size()==3,"extra web damage repeats each tick without stacking its own slow")
	check(count(spider,"block.cobweb.step")==0,"stationary damage ticks do not play walking sounds")
	fresh(spider)
	manager.sample(0.08)
	target.global_position += Vector2(1,0)
	manager.sample(0.08)
	check(count(spider,"block.cobweb.step")==1,"enemy moving on a web emits original cobweb footstep")
	var ref:WeakRef = target.get_meta("mc_cobweb_step_player")
	var player:AudioStreamPlayer2D = ref.get_ref()
	check(player.get_meta("mc16_web_walker")==target.get_instance_id(),"footstep is tracked per walker")
	check(manager.base_interval()>=manager.longest_step,"base interval at base speed covers the longest native clip")
	# 脚步按踩踏者走过的距离计步：步幅 = 基础速度 × 基础间隔。
	var stride:float = manager.FOOTSTEP.base_speed(target)*manager.base_interval()
	target.global_position += Vector2(1,0)
	manager.sample(0.08)
	check(count(spider,"block.cobweb.step")==1,"less than one stride adds no web footstep")
	var side:float = -1.0
	var walked:float = 2.0
	while count(spider,"block.cobweb.step")==1 and walked<stride*2.0:
		target.global_position += Vector2(6.0*side,0)
		side = -side
		walked += 6.0
		manager.sample(0.08)
	check(count(spider,"block.cobweb.step")==2 and walked>=stride*0.9,"the next web footstep comes after one stride and may overlap the previous")
	# Independent walkers must not share an event-wide cooldown.
	var second:Node = dummy(center+Vector2(0,2))
	manager.sample(0.08)
	second.global_position += Vector2(1,0)
	manager.sample(0.08)
	check(count(spider,"block.cobweb.step")==3,"a second enemy has an independent footstep cadence")
	var ally:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(-250,0))
	ally.native_feedback.set_physics_process(false)
	seed_web(ally.silk_network)
	net._update_crossings()
	check(get_nodes_in_group("MCSpiderWebFootsteps").size()==1,"multiple spiders share one world footstep scheduler")
	fresh(spider)
	fresh(ally)
	var before:int = total_steps([spider,ally])
	manager.sample(10.0)
	check(total_steps([spider,ally])==before,"standing still remains silent after the cooldown expires")
	target.global_position += Vector2(1,0)
	manager.sample(0.08)
	check(total_steps([spider,ally])==before+1,"overlapping webs from two spiders still emit only one step per target")
	fresh(spider)
	fresh(ally)
	before = total_steps([spider,ally])
	target.dizziness = true
	target.global_position += Vector2(1,0)
	manager.sample(10.0)
	check(total_steps([spider,ally])==before,"stunned displacement does not produce footsteps")
	target.dizziness = false
	target.global_position = center+Vector2(100,100)
	manager.sample(0.08)
	target.global_position += Vector2(1,0)
	manager.sample(10.0)
	check(total_steps([spider,ally])==before,"walking outside all webs is silent")
	var clock:float = manager.states[target.get_instance_id()].cadence._progress
	game.now_stop_state = true
	target.global_position += Vector2(1,0)
	manager.sample(10.0)
	debris._process(10.0)
	check(manager.states[target.get_instance_id()].cadence._progress==clock and debris.elapsed==0.0,"pause freezes footstep clocks and web placement particles")
	game.now_stop_state = false
	debris._process(debris.duration+0.1)
	check(debris.is_queued_for_deletion(),"web placement particles clean themselves up")
	second.queue_free()
	await process_frame
	manager.sample(0.08)
	check(manager.states.size()<=get_nodes_in_group("Ball").size(),"dead walkers are pruned from the footstep scheduler")
	print("MC16_WEB_FEEDBACK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
