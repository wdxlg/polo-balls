extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	var origin:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = origin
	var target:Node2D = dummy(origin+Vector2(100,0))
	await physics_frame
	moss.set_player_control_peer(0)
	moss.direction = Vector2.DOWN
	moss.growth_left = 999.0
	moss.burrow_wait = 999.0
	moss.step_mob(0.1)
	check(moss.direction == Vector2.DOWN,"AI keeps ordinary movement direction rather than steering at nearest enemy")
	moss.set_player_control_peer(1)
	check(moss.frontier_fx.z_index == -3 and not moss.frontier_fx.z_as_relative,"ground moss renders at absolute -3, above floor -5 and below obstacle/projectile/character layers")
	check(moss.frontier_fx.z_index < moss.image.z_index,"ground moss stays below character")
	var source:String = FileAccess.get_file_as_string("res://scripts/characters/我的世界/frontier/fx.gd")
	var moss_draw:String = source.split("func _draw_moss")[1].split("func _draw_sword")[0]
	check(not moss_draw.contains("draw_arc") and not moss_draw.contains("draw_rect("),"moss draw contains no circular cues or green layer-count markers")
	var debris_script:Script = load("res://scripts/characters/我的世界/frontier/moss_debris.gd")
	var entry:Node2D = debris_script.new()
	var exit_fx:Node2D = debris_script.new()
	world.add_child(entry)
	world.add_child(exit_fx)
	entry.setup(moss,origin,false,moss.CELL)
	exit_fx.setup(moss,origin,true,moss.CELL)
	entry.set_process(false)
	exit_fx.set_process(false)
	check(entry.blocks.size() == 24 and exit_fx.blocks.size() == 28,"entry and exit generate bounded moss square-chip bursts")
	var entry_max:float = 0.0
	var exit_min:float = INF
	for block:Dictionary in entry.blocks:
		check(is_equal_approx(maxf(absf(block.start.x),absf(block.start.y)),moss.CELL*0.5),"entry fragment is born on a straight edge of the moss cell")
		entry_max = maxf(entry_max,block.upward)
	for block:Dictionary in exit_fx.blocks:
		check(maxf(absf(block.start.x),absf(block.start.y))<=moss.CELL*0.22,"exit fragment is born in the central region")
		exit_min = minf(exit_min,block.upward)
	check(exit_min > entry_max*1.7,"exit fragments rise substantially faster than entry fragments")
	var block:Dictionary = exit_fx.blocks[0]
	var airborne:Dictionary = exit_fx.block_pose(block,block.delay+block.flight*0.5)
	var landed:Dictionary = exit_fx.block_pose(block,block.delay+block.flight)
	check(airborne.point.y < block.start.y-15.0 and landed.alpha==1.0,"square fragments arc upward then land before fading")
	check(exit_fx.block_pose(block,block.delay+block.flight+0.41).alpha==0.0,"landed fragments fade away completely")
	game.now_stop_state = true
	entry._process(0.3)
	check(entry.elapsed == 0.0,"pause freezes fragments")
	game.now_stop_state = false
	var resting_scale:Vector2 = moss.image.scale
	var resting_position:Vector2 = moss.image.position
	var start:Dictionary = moss.burrow_pose("dig",0.0)
	var sink:Dictionary = moss.burrow_pose("dig",moss.burrow_sink_time*0.7)
	var hidden:Dictionary = moss.burrow_pose("dig",moss.burrow_delay)
	check(start.visible and start.scale==Vector2.ONE,"entry starts from normal visible body")
	check(sink.scale.x<1.0 and sink.offset.y>0.0,"entry sinks down and narrows")
	check(not hidden.visible and hidden.alpha==0.0,"body fully disappears only after sinking")
	var rise:Dictionary = moss.burrow_pose("emerge",moss.burrow_rise_time*0.5)
	var apex:Dictionary = moss.burrow_pose("emerge",moss.burrow_rise_time)
	var fall:Dictionary = moss.burrow_pose("emerge",moss.burrow_rise_time+moss.burrow_fall_time*0.8)
	var landing:Dictionary = moss.burrow_pose("emerge",moss.burrow_rise_time+moss.burrow_fall_time)
	var settled:Dictionary = moss.burrow_pose("emerge",2.0)
	check(rise.scale.x<1.0 and rise.scale.y>1.0 and rise.offset.y<0.0,"exit rises quickly as a narrow stretched body")
	check(apex.offset.y < fall.offset.y and fall.offset.y<0.0,"airborne body falls back down after its apex")
	check(landing.scale.x>1.0 and landing.scale.y<1.0,"landing visibly squashes before elastic recovery")
	check(not settled.active and settled.scale==Vector2.ONE and settled.offset==Vector2.ZERO,"elastic recovery returns exactly to the unmodified pose")
	moss.burrow_wait = 0.0
	moss.plant(origin)
	moss.plant(origin+Vector2(24,0))
	target.global_position = origin+Vector2(24,0)
	check(moss.begin_burrow(),"actual skill begins the entry animation")
	moss.clock += moss.burrow_sink_time*0.7
	moss.visual_mob()
	check(moss.image.scale.x<resting_scale.x and moss.image.position.y>resting_position.y,"live sprite receives the sinking/narrowing pose")
	var snapshot:Dictionary = moss.visual_state()
	check(snapshot.moss_pose_phase=="dig" and snapshot.has("moss_pose_started"),"replication includes animation phase and combat-clock start time")
	game.now_stop_state = true
	var saved_transform:Transform2D = moss.image.transform
	moss.tick_physics(0,1.0)
	moss.visual_mob()
	check(moss.image.transform==saved_transform,"combat pause freezes body animation too")
	game.now_stop_state = false
	moss.cancel_burrow()
	check(moss.image.scale==resting_scale and moss.image.position==resting_position and moss.image.visible and moss.image.self_modulate.a==1.0,"cancellation restores position, scale, visibility and opacity")
	moss.burrow_wait = 0.0
	moss.begin_burrow()
	moss.burrow_left = 0.0
	moss.finish_burrow()
	check(moss._moss_pose_phase=="emerge","actual successful exit starts jump/landing animation")
	moss.clock += moss.burrow_rise_time*0.5
	moss.visual_mob()
	check(moss.image.position.y<resting_position.y and moss.image.scale.x<resting_scale.x,"live exit sprite is airborne and narrow")
	var mirror:Node2D = actor("苔藓",origin+Vector2(200,100))
	mirror.accept_visual(moss.visual_state())
	check(mirror._moss_pose_phase==moss._moss_pose_phase and mirror._moss_pose_started==moss._moss_pose_started,"animation snapshot does not restart time on remote viewers")
	mirror.patches.clear()
	moss.clock += 2.0
	moss.visual_mob()
	check(moss.image.scale==resting_scale and moss.image.position==resting_position and moss.image.self_modulate.a==1.0,"finished animation restores exact original sprite state")
	print("MOSS PRESENTATION CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
