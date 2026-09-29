extends "res://tests/test_mc16_spider_drowned.gd"
func hits(unit:Node) -> Array[Node]:
	var result:Array[Node]=[]
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_damage_source",0)==unit.get_instance_id(): result.append(player)
	return result
func run() -> void:
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true);saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Ball_Can_Move=true;game.Game_Settings.Have_Team_Damage=false;game.now_stop_state=false
	AudioServer.set_bus_mute(0,true);create_timer(45).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.3).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node=spawn("res://scenes/characters/我的世界/溺尸.tscn",center)
	var target:Node=dummy(center+Vector2(120,0))
	await process_frame
	check(unit.mc_impact_event(50)=="entity.player.hurt" and unit.mc_impact_event(51)=="entity.player.attack.crit","strict 50/51 critical threshold")
	var previous:float=-100.0
	for damage:float in [50.0,51.0,100.0,200.0]:
		var hp:float=target.health
		var count:int=hits(unit).size()
		unit.mc_damage_with_impact(target,damage,target.global_position)
		check(hp-target.health==damage,"audio does not change resolved damage")
		check(hits(unit).size()==count+1,"one actual hit creates exactly one damage cue")
		var cue:AudioStreamPlayer2D=hits(unit).back()
		check(cue.playing and cue.get_meta("mc_sound_event")==unit.mc_impact_event(damage),"actual playing clip matches damage threshold")
		check(cue.volume_db>previous,"larger actual damage makes playing clip louder")
		previous=cue.volume_db
	check(unit.mc_outgoing_impact_volume(1000000.0)<=6.0,"volume has safe upper bound")
	check(unit.mc_outgoing_impact_volume(100)>unit.mc_outgoing_impact_volume(50) and unit.mc_outgoing_impact_volume(1)>=0.0,"larger damage raises gain above original audio baseline")
	target.Damage_reduction=0.9
	unit.mc_damage_with_impact(target,100,target.global_position)
	check(hits(unit).back().get_meta("mc_sound_event")=="entity.player.hurt","reduced damage does not falsely play critical cue")
	target.Damage_reduction=1.0
	var count:int=hits(unit).size()
	unit.mc_damage_with_impact(target,1000,target.global_position)
	check(hits(unit).size()==count,"immunity emits no successful damage cue")
	target.Damage_reduction=0.0
	# Exercise production projectile, bolt and network routes with boosted test damage.
	unit.Damage=160;unit.default_properties.Damage=160
	var spear:Node=unit._trident
	spear.launch(Vector2.RIGHT)
	for i:int in 80:
		spear.advance(0.02)
		if spear.flight_state==spear.Phase.RETURNING: break
	check(hits(unit).back().get_meta("mc_sound_event")=="entity.player.attack.crit","real projectile hit plays critical cue above threshold")
	count=hits(unit).size()
	unit._strike_area(target.global_position,false)
	check(hits(unit).size()>count and hits(unit).back().get_meta("mc_sound_event")=="entity.player.attack.crit","real lightning area damage uses same critical feedback")
	var arc:Node=unit.ARC.new();arc.caster=unit;arc.start=target.global_position+Vector2(-50,0);arc.end=target.global_position+Vector2(50,0)
	world.add_child(arc);arc.set_physics_process(false)
	count=hits(unit).size();arc.advance(0.01)
	check(hits(unit).size()==count+1 and hits(unit).back().get_meta("mc_sound_event")=="entity.player.attack.crit","real electric arc hit uses same critical feedback")
	print("DROWNED_DAMAGE_AUDIO checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
