extends "res://tests/test_mc_warden_sound.gd"
func latest_debris() -> Node2D:
	var nodes:Array[Node]=get_nodes_in_group("MCWardenGroundDebris")
	return nodes.back() if not nodes.is_empty() else null
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func():finish(2))
	var w:Node2D=actor("监守者",o)
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.signals_received=5
	check(w.begin_emergence(),"actual emergence starts")
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var rise:Node2D=latest_debris()
	rise.set_process(false)
	check(rise!=null and rise.emerging and rise.emission_duration==3,"climb-out triggers mace-style debris across full emergence")
	check(not rise._floor_snapshot.is_empty() and rise._blocks.size()>0 and rise._blocks.size()<=64,"real rendered ground is sampled into bounded square particles")
	check(rise.get_script().get_base_script().resource_path.ends_with("重锤落地冲击.gd"),"debris reuses the mace floor-color and flight renderer")
	var first:int=0; var late:int=0
	for block:Dictionary in rise._blocks:
		check(block.height>=13 and block.height<=42,"emerging chips use the mace's taller flight")
		if block.delay<=0.06: first+=1
		if block.delay>2.0: late+=1
	check(first>=12 and late>0,"emergence has an initial burst and continuing chips rather than one short puff")
	var t:float=rise._elapsed
	game.now_stop_state=true; rise._process(1)
	check(rise._elapsed==t,"pause freezes flying earth particles")
	game.now_stop_state=false
	w.form=w.Form.AWAKE; w._form_stats(true); w.begin_burrow()
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var dig:Node2D=latest_debris(); dig.set_process(false)
	check(dig!=rise and not dig.emerging,"burrowing starts its own continuous debris effect")
	check(dig._blocks.size()>0 and dig._blocks.size()<=64,"burrowing particle count remains bounded")
	var beginning:int=0; var middle:int=0; var ending:int=0
	for block:Dictionary in dig._blocks:
		check(block.height>=2 and block.height<=8,"burrowing chips fly low near the floor")
		if block.delay<0.5: beginning+=1
		elif block.delay<1.1: middle+=1
		else: ending+=1
	check(beginning>0 and middle>0 and ending>0,"low particles keep emerging throughout the descent")
	check(rise.z_index==4 and dig.z_index==4,"earth debris renders above ground and body layer")
	rise._process(rise._effect_end_time+0.1)
	check(rise.is_queued_for_deletion(),"particles fade and clean up after landing")
	w.Die(); dig._process(0.01)
	check(dig.is_queued_for_deletion(),"death cleans remaining descent particles")
	print("WARDEN GROUND DEBRIS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
