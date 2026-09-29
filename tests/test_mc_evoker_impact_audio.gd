extends "res://tests/test_mc_frontier.gd"
func impact_players(source:Node) -> Array[Node]:
	return get_nodes_in_group("MCNativeSFX").filter(func(n:Node):return n.get_meta("mc_damage_source",0)==source.get_instance_id())
func last_impact(source:Node) -> AudioStreamPlayer2D:
	var players:Array[Node]=impact_players(source)
	return players.back() if not players.is_empty() else null
func fang(source:Node2D,point:Vector2,amount:float,hits:Dictionary={}) -> Node2D:
	var f:Node2D=load("res://scripts/effects/我的世界/唤魔尖牙.gd").new()
	world.add_child(f); f.global_position=point
	f.setup(source,0.0,amount,hits); f.set_physics_process(false)
	f._physics_process(0.01)
	return f
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func():finish(2))
	var e:Node2D=actor("唤魔者",o)
	var victim:Node2D=dummy(o+Vector2(100,0))
	var vex:Node2D=spawn("res://scenes/creatures/唤魔恼鬼.tscn",o+Vector2(50,0))
	vex.Master=e; vex.Master_name=str(e.get_path())
	vex.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	check(e.mc_impact_event(50)=="entity.player.hurt" and e.mc_impact_event(51)=="entity.player.attack.crit","50 normal / 51 critical threshold")
	var hp:float=victim.health
	var f:Node2D=fang(e,victim.global_position,50)
	check(is_equal_approx(hp-victim.health,50),"fang does real 50 health damage")
	var p:AudioStreamPlayer2D=last_impact(e)
	check(p!=null and p.playing and p.get_meta("mc_sound_event")=="entity.player.hurt","fang 50 plays native hurt")
	var quiet:float=p.volume_db
	var before:int=impact_players(e).size()
	f._physics_process(0.1)
	check(impact_players(e).size()==before,"one fang contact does not duplicate impact sound")
	fang(e,victim.global_position,51)
	p=last_impact(e)
	check(p.get_meta("mc_sound_event")=="entity.player.attack.crit" and p.volume_db>quiet,"fang 51 switches to louder native critical")
	var critical_volume:float=p.volume_db
	fang(e,victim.global_position,144)
	check(last_impact(e).volume_db>critical_volume,"larger actual damage produces louder critical audio")
	victim.Damage_reduction=0.9
	fang(e,victim.global_position,100)
	check(last_impact(e).get_meta("mc_sound_event")=="entity.player.hurt","post-reduction health damage determines sound tier")
	victim.Damage_reduction=1.0; before=impact_players(e).size()
	fang(e,victim.global_position,100)
	check(impact_players(e).size()==before,"fully absorbed damage has no false hurt sound")
	victim.Damage_reduction=0.0
	before=impact_players(e).size(); fang(e,o+Vector2(-200,0),100)
	check(impact_players(e).size()==before,"missed fang has no damage audio")
	victim.max_block=500; victim.default_properties.max_block=500; victim.block=500
	before=impact_players(e).size(); hp=victim.health
	fang(e,victim.global_position,100)
	check(victim.health==hp and impact_players(e).size()==before,"shield-only damage does not pretend health was hurt")
	victim.block=0
	vex.Damage=50; vex.default_properties.Damage=50
	vex._dash_target=weakref(victim); vex._dash_hit=false
	hp=victim.health
	vex._check_dash_hit(o+Vector2(60,0),o+Vector2(120,0))
	check(is_equal_approx(hp-victim.health,50),"real vex swept contact damages target")
	p=last_impact(vex)
	check(p!=null and p.get_meta("mc_sound_event")=="entity.player.hurt","vex 50 plays native hurt")
	before=impact_players(vex).size()
	vex._check_dash_hit(o+Vector2(60,0),o+Vector2(120,0))
	check(impact_players(vex).size()==before,"one dash cannot repeatedly sound on same victim")
	vex.Damage=51; vex.default_properties.Damage=51; vex._dash_hit=false
	vex._check_dash_hit(o+Vector2(60,0),o+Vector2(120,0))
	check(last_impact(vex).get_meta("mc_sound_event")=="entity.player.attack.crit","vex above 50 plays critical")
	check(last_impact(vex).global_position==victim.global_position,"impact sound is positioned on struck victim")
	vex._dash_hit=false; before=impact_players(vex).size()
	vex._check_dash_hit(o+Vector2(-100,100),o+Vector2(-40,100))
	check(impact_players(vex).size()==before,"missed vex dash emits no damage sound")
	print("EVOKER/VEX IMPACT: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
