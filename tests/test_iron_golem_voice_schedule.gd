extends "res://tests/test_iron_golem_landing.gd"
var LAND_AUDIO:Script
func voices(owner_node:Node,event:String="") -> Array:
	var result:Array = []
	for p:Node in get_nodes_in_group("GolemPairAudio"):
		if not p.is_queued_for_deletion() and p.get_meta("mc_pair_owner",0)==owner_node.get_instance_id() and (event.is_empty() or str(p.get_meta("mc_sound_event","")).ends_with("."+event)): result.append(p)
	return result
func clear_voices(owner_node:Node) -> void:
	for p:Node in voices(owner_node): p.free()
func clear_landing_audio() -> void:
	for p:Node in get_nodes_in_group("GolemLandingAudio"): p.free()
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("GOLEM_VOICE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	LAND_AUDIO = load("res://scripts/characters/我的世界/iron_golem/landing_audio.gd")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2(-200,0))
	var v:Node2D = g.companion
	v.global_position = Vector2(-300,0)
	check(is_equal_approx(g.hurt_voice_chance,0.45) and is_equal_approx(v.hurt_voice_chance,0.45),"both actors default to probabilistic hurt, not forced 100 percent")
	g.tick_pair_audio(100.0,false)
	check(voices(g).is_empty() and g.mc_play("ambient")==null,"golem has no breath/ambient event")
	v._breath_wait = 0.0
	v.tick_pair_audio(0.0,false)
	check(voices(v,"ambient").size()==1,"idle villager mutters")
	var p:Variant = v._voice_player
	var duration:float = p.stream.get_length()/p.pitch_scale
	check(v._breath_wait>=duration+2.0 and v._breath_wait<=duration+5.001,"breath interval includes whole previous clip and randomized silence")
	var original_wait:float = v._breath_wait
	v.mc_tick_ambient(999.0)
	check(v._breath_wait==original_wait and voices(v,"ambient").size()==1,"generic inherited scheduler cannot duplicate pair ambient")
	v.tick_pair_audio(999.0,false)
	check(voices(v,"ambient").size()==1 and v._voice_player==p,"playing gate prevents overlap even with accelerated delta")
	p.free()
	v.tick_pair_audio(0.0,false)
	check(voices(v,"ambient").size()==1,"freed player reference safely permits next clip")
	var gap_values:Dictionary = {}
	for i:int in range(12):
		clear_voices(v)
		v._breath_wait = 0.0
		v.tick_pair_audio(0.0,false)
		gap_values[snappedf(v._breath_wait-v._audio_duration(v._voice_player),0.001)] = true
	check(gap_values.size()>1,"breath gaps vary rather than fixed interval")
	var hurt:Variant = v.mc_play("hurt")
	check(hurt!=null and voices(v,"ambient").is_empty() and voices(v,"hurt").size()==1,"hurt interrupts mutter without layering two voices")
	check(v.mc_play("hurt")==null and v.mc_play("ambient")==null,"busy hurt voice cannot overlap another hurt or mutter")
	clear_voices(v)
	v._breath_wait = 999.0
	for actor:Node2D in [g,v]:
		actor._step_cadence.ready_now()
		actor.tick_pair_audio(100.0,false)
		check(voices(actor,"step").is_empty(),"idle has no step "+actor.mc_audio_role)
		actor.global_position.x += 1.0
		actor.tick_pair_audio(0.016,true)
		p = actor._step_player
		check(is_instance_valid(p) and p.playing,"walking starts step "+actor.mc_audio_role)
		duration = actor._audio_duration(p)
		var stride:float = actor.FOOTSTEP.base_speed(actor)*(duration+(actor.step_silence.x+actor.step_silence.y)*0.5)
		actor.global_position.x += stride*0.5
		actor.tick_pair_audio(0.1,true)
		check(voices(actor,"step").size()==1,"half a stride adds no step "+actor.mc_audio_role)
		actor.global_position.x += stride*0.6
		actor.tick_pair_audio(0.1,true)
		check(voices(actor,"step").size()==2 and p.playing,"fast walking starts the next step before the previous ends "+actor.mc_audio_role)
		actor.tick_pair_audio(0.0,false)
		check(not p.playing and voices(actor,"step").is_empty(),"stopping movement stops step "+actor.mc_audio_role)
		clear_voices(actor)
	check(v._pair_event_key("step")=="block.stone.step" and v.PAIR_SOUNDS.EVENTS["block.stone.step"].size()==6,"villager uses six native stone footsteps, not fabricated entity event")
	v._breath_wait = 999.0
	g._step_cadence.ready_now()
	g.direction = Vector2.RIGHT
	g.Can_Attack = false
	g.dizziness = true
	g.tick_physics(g.State.Move,0.05)
	check(voices(g,"step").is_empty(),"stunned body emits no walking step")
	g.dizziness = false
	game.Game_Settings.Ball_Can_Move = false
	g.tick_physics(g.State.Move,0.05)
	check(voices(g,"step").is_empty(),"disabled movement emits no step")
	game.Game_Settings.Ball_Can_Move = true
	g.set_meta("golem_air_height",30.0)
	g.tick_physics(g.State.Move,0.05)
	check(voices(g,"step").is_empty(),"airborne displacement is not a walking step")
	g.remove_meta("golem_air_height")
	p = v.mc_play("ambient")
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	await process_frame
	await physics_frame
	var saved_wait:float = v._breath_wait
	game.now_stop_state = true
	v.tick_pair_audio(500.0,true)
	p._process(0.0)
	check(v._breath_wait==saved_wait and p.stream_paused,"pause freezes timer and active sound")
	check(v.mc_play("hurt")==null,"pause blocks new event sound")
	game.now_stop_state = false
	p._process(0.0)
	check(not p.stream_paused,"resume unpauses active sound")
	clear_voices(v)
	v.set_multiplayer_authority(2)
	v._breath_wait = 0.0
	v._step_cadence.ready_now()
	v.tick_pair_audio(100.0,true)
	check(voices(v).is_empty() and v.mc_play("hurt")==null,"replica does not independently schedule or randomly choose voices")
	p = v._pair_audio_local("block.stone.step",v.global_position,-10.0,4)
	check(p.get_meta("mc_pair_variant")==4 and p.stream==v.PAIR_SOUNDS.EVENTS["block.stone.step"][4].stream,"replica playback accepts explicit authoritative variant")
	v.tick_pair_audio(0.1,false)
	check(p.playing,"sparse replica position snapshots do not prematurely stop authoritative step")
	v._pair_stop_step()
	check(not p.playing,"authoritative stop command stops replica step")
	v.set_multiplayer_authority(1)
	clear_voices(g)
	clear_voices(v)
	for actor:Node2D in [g,v]:
		actor._mc_voice_rng.seed = 424242
		for chance:float in [0.0,1.0,0.45]:
			actor.hurt_voice_chance = chance
			var heard:int = 0
			for i:int in range(80):
				clear_voices(actor)
				actor.health = actor.Max_health
				actor.receive_positional_damage(1.0,Vector2.ZERO,false,null)
				if not voices(actor,"hurt").is_empty(): heard += 1
			check(heard==0 if chance==0.0 else heard==80 if chance==1.0 else heard>0 and heard<80,"actual damage honors hurt probability "+actor.mc_audio_role+" "+str(chance)+" heard="+str(heard))
		actor.hurt_voice_chance = 0.0
		clear_voices(actor)
	for pair:Vector2i in [Vector2i(800,799),Vector2i(601,600),Vector2i(600,599),Vector2i(401,400),Vector2i(400,399),Vector2i(201,200),Vector2i(200,199),Vector2i(599,550),Vector2i(800,100),Vector2i(199,200)]:
		g.health = pair.x
		clear_voices(g)
		g.health = pair.y
		g.tick_physics(g.State.Stand,0.0)
		var should_crack:bool = pair.x>pair.y and g.crack_stage_for_health(pair.y)>g.crack_stage_for_health(pair.x)
		check(voices(g,"damage").size()==(1 if should_crack else 0),"crack sound matches actual texture transition "+str(pair))
		check(g.visual_stage==g.crack_stage_for_health(pair.y),"texture/audio share crack stage "+str(pair))
	g.health = 800
	v.health = 180
	for actor:Node2D in [g,v]:
		clear_voices(actor)
		actor.mc_play("step")
		actor.mc_play("hurt")
		actor.health = 0
		actor.Die()
		p = actor._voice_player
		check(is_instance_valid(p) and p.playing and str(p.get_meta("mc_sound_event")).ends_with(".death"),"death always plays even when hurt busy and probability zero "+actor.mc_audio_role)
		check(voices(actor,"step").is_empty() and voices(actor,"hurt").is_empty(),"death replaces hurt and step "+actor.mc_audio_role)
		actor.Die()
		check(voices(actor,"death").size()==1 and actor.mc_play("death")==null,"death plays once "+actor.mc_audio_role)
		check(actor._pair_audio_local(actor._pair_event_key("hurt"),Vector2.ZERO,0.0)==null,"late nondeath audio rejected "+actor.mc_audio_role)
		actor.free()
		p._process(0.0)
		check(p.playing and not p.is_queued_for_deletion(),"death tail survives actor removal")
		p.free()
	g = golem(Vector2(-500,0))
	g.companion.global_position = Vector2(-550,0)
	var victim:Node2D = enemy(Vector2.ZERO)
	await physics_frame
	await process_frame
	for h:float in [55.0,121.0,190.0]:
		clear_landing_audio()
		victim.position = Vector2.ZERO
		var flight:Node = fly(g,victim,h,300.0)
		flight.advance(flight.flight_duration*0.5)
		check(get_nodes_in_group("GolemLandingAudio").is_empty(),"ascending/apex has no landing audio "+str(h))
		flight.advance(flight.flight_duration*0.5+0.01)
		var sounds:Array = get_nodes_in_group("GolemLandingAudio")
		check(sounds.size()==1,"actual touchdown emits one landing sound "+str(h))
		if sounds.is_empty(): continue
		p = sounds[0]
		check(p.global_position.is_equal_approx(flight.landing_position) and is_equal_approx(p.get_meta("mc_landing_height"),flight.peak_height),"landing audio uses actual point and peak height")
		check(str(p.get_meta("mc_sound_event"))=="golem.landing."+["light","medium","heavy"][LAND_AUDIO.tier(flight.peak_height)],"landing audio selects actual-height tier")
		var native_event:String = "entity.generic.small_fall" if flight.peak_height<100.0 else "entity.generic.big_fall"
		check(p.get_meta("mc_native_event")==native_event,"landing uses native generic fall event, not mace")
		check(p.stream==g.PAIR_SOUNDS.EVENTS[native_event][0].stream and not "重锤" in p.stream.resource_path,"landing stream is exact official generic fall asset")
		flight.land()
		flight._land_visual(Vector2.ZERO,50.0,999.0,0)
		check(get_nodes_in_group("GolemLandingAudio").size()==1,"duplicate land/RPC cannot replay sound")
		clear_control(victim)
		p._process(0.0)
		check(p.playing and not p.is_queued_for_deletion(),"landing sound survives flight-controller cleanup")
	clear_landing_audio()
	var cancelled:Node = fly(g,victim)
	cancelled.advance(cancelled.flight_duration*0.3)
	victim.health = 0
	cancelled.advance(1.0)
	check(get_nodes_in_group("GolemLandingAudio").is_empty(),"death-cancelled flight has no phantom landing sound")
	check(LAND_AUDIO.tier(99.9)==0 and LAND_AUDIO.tier(100.0)==1 and LAND_AUDIO.tier(169.9)==1 and LAND_AUDIO.tier(170.0)==2,"landing tier boundaries precise")
	print("GOLEM_VOICE_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
