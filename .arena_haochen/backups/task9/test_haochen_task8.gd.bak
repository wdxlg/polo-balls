extends "res://tests/test_sulfur_cube_balance.gd"
## Task 8 (2026-09-28): HP 800, energy-gain soul sound, illusioner copy sound and the
## staggered "soul rise" spawn particles that start from the copy's current body.
var HAOCHEN:PackedScene
var AUDIO:Script
var REQUEST:PackedScene

func run() -> void:
	game=root.get_node("Game")
	HAOCHEN=load("res://scenes/characters/我的世界/皓宸.tscn")
	AUDIO=load("res://scripts/characters/我的世界/haochen/audio.gd")
	REQUEST=load("res://scenes/effects/我的世界/角色复制请求.tscn")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()

	var hero:Node2D=HAOCHEN.instantiate();hero.name="Task8Haochen";hero.Team="Team0";hero.position=center
	world.add_child(hero,true)
	await process_frame
	check(int(hero.Max_health)==800 and int(hero.health)==800,"Haochen spawns with 800 max health (user request)")
	check(int(hero.default_properties.Max_health)==800 if hero.default_properties!=null else true,"default properties also carry 800 max health")

	# Copy sound = entity.illusioner.mirror_move (2 original variants), enderman.teleport gone.
	var copy_paths:Array=[]
	for s:AudioStream in AUDIO.EVENTS[&"copy_complete"]:copy_paths.append(s.resource_path)
	check(copy_paths.size()==2 and copy_paths.all(func(p):return str(p).get_file().begins_with("illusioner.mirror_move_")),"copy completion plays the chosen illusioner mirror_move variants")
	check(AUDIO.EVENTS[&"charge_soul"].size()==13,"energy gain uses all 13 native particle.soul_escape variants")

	# Energy gain sound: real charging with a donor in range repeats the soul whoosh.
	hero.state_machine.set_physics_process(false);hero.set_physics_process(false)
	var donor:Node2D=load("res://scenes/ball.tscn").instantiate();donor.name="Task8Donor";donor.Team="Team1";donor.position=center+Vector2(30,0)
	world.add_child(donor,true)
	await process_frame
	donor.state_machine.set_physics_process(false);donor.set_physics_process(false);donor.Can_Attack=false;donor.Has_Collision_Damage=false
	hero._scan_left=0.0;hero._step_energy(0.1)
	check(hero.charge_phase==hero.Phase.CHARGING,"a nearby enemy puts Haochen into the charging phase")
	var start_ms:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start_ms<1200:
		hero._step_energy(0.016)
		hero.charge_energy=minf(hero.charge_energy,50.0) # stay in CHARGING for the whole window
		await process_frame
	var souls:Array[Node]=[]
	for node:Node in get_nodes_in_group("MCHaochenAudio"):
		if node.get_meta("haochen_event",&"")==&"charge_soul":souls.append(node)
	check(souls.size()>=3,"energy gain keeps playing soul_escape while charging (got %d)" % souls.size())
	var pitch_ok:bool=not souls.is_empty()
	var path_ok:bool=not souls.is_empty()
	for p:Node in souls:
		pitch_ok=pitch_ok and p.pitch_scale>=0.84 and p.pitch_scale<=1.16
		path_ok=path_ok and str(p.stream.resource_path).get_file().begins_with("particle.soul_escape_")
	check(path_ok and pitch_ok,"charge sound uses the soul_escape clips with vanilla-like random pitch 0.85-1.15")
	var serial_before:int=hero._sound_serial
	hero.charge_phase=hero.Phase.RESTING
	for node:Node in souls:node.free()
	for i:int in range(30):
		hero._step_charge_stream(0.05)
	var after:int=0
	for node:Node in get_nodes_in_group("MCHaochenAudio"):
		if node.get_meta("haochen_event",&"")==&"charge_soul":after+=1
	check(after==0 and hero._sound_serial==serial_before,"no energy-gain sound once charging stops")

	# Spawn rise particles.
	var anchor:Node2D=load("res://scenes/ball.tscn").instantiate();anchor.name="Task8Copy";anchor.Team="Team0";anchor.position=center+Vector2(-120,0)
	world.add_child(anchor,true)
	await process_frame
	anchor.state_machine.set_physics_process(false);anchor.set_physics_process(false)
	var request:Node2D=REQUEST.instantiate();request.position=anchor.global_position;request.completed=true
	world.add_child(request)
	request.set_physics_process(false)
	var emitted:int=request._emit_spawn_rise("Task8Copy")
	var rise:Array[Node]=get_nodes_in_group("MCHaochenSpawnRiseParticle")
	check(emitted==20 and rise.size()==20,"spawn emits 20 staggered rising souls")
	var hidden:int=0
	for s:Node in rise:
		if not s.visible:hidden+=1
	check(hidden>=18,"souls start staggered (hidden until their turn), not as one burst")
	var brown:bool=false
	for s:Node in rise:
		if s.FRAMES.find(s.texture)<7:brown=true
	check(not brown,"spawn souls only use the cyan-white wisp frames 7..10 (brown frames skipped)")
	anchor.global_position+=Vector2(90,0) # the copy walks away right after spawning
	await create_timer(0.7,true,false,true).timeout
	var box:Vector2=anchor.collision_shape_2d.shape.get_rect().size*anchor.collision_shape_2d.global_scale.abs()
	var near:int=0;var visible_now:int=0
	for s:Node in get_nodes_in_group("MCHaochenSpawnRiseParticle"):
		if s.visible and s._age<0.6: # started after the move (the very first soul starts at t=0)
			visible_now+=1
			if absf(s._start.x-anchor.global_position.x)<=0.56*box.x+1.0:near+=1
	check(visible_now>=6,"souls keep appearing over about a second (%d visible at 0.7 s)" % visible_now)
	check(near==visible_now and near>0,"late souls start from the copy's CURRENT body, following it as it moves")
	var width_ok:bool=true
	for s:Node in get_nodes_in_group("MCHaochenSpawnRiseParticle"):
		var w:float=s.scale.x*16.0
		width_ok=width_ok and w>=21.9 and w<=28.1
	check(width_ok,"spawn souls are drawn at 22-28 px (clearly visible, twice the old size)")
	await create_timer(1.7,true,false,true).timeout # last start ~1.03 s + life <= 1.1 s
	check(get_nodes_in_group("MCHaochenSpawnRiseParticle").is_empty(),"every spawn soul frees itself after the effect")

	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved
	print("HAOCHEN_TASK8 checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
