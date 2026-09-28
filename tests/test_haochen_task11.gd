extends "res://tests/test_sulfur_cube_balance.gd"
## Task 11 (2026-09-28): the user's three videos (repo root) became Haochen voices:
## "今天搬哪个" replaces the charging-start clip, "啊" replaces the hurt voice (same
## mc_mob_base hurt_voice_chance), "好期待啊" replaces the ambient/breathing voice (same
## RESTING-only 3-7 s cadence). Checks real playback through the character's own paths.
const DIR:String = "res://audio/characters/我的世界/haochen/"

func voices(hero:Node,event:StringName) -> Array:
	return get_nodes_in_group("MCHaochenAudio").filter(func(n):return n.get_meta("haochen_event",&"")==event and int(n.get_meta("haochen_source",0))==hero.get_instance_id() and not n.is_queued_for_deletion())

func run() -> void:
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var AUDIO:Script=load("res://scripts/characters/我的世界/haochen/audio.gd")
	var want:Dictionary={&"charge_start":["charge_start.wav",2.368],&"hurt":["hurt_ah.wav",0.441],&"ambient":["breath_haoqidai.wav",1.022]}
	for ev:StringName in want:
		var list:Array=AUDIO.EVENTS[ev]
		var s:AudioStream=list[0] if list.size()==1 else null
		check(s!=null and s.resource_path==DIR+str(want[ev][0]) and absf(s.get_length()-float(want[ev][1]))<0.02,"%s is exactly the converted user clip %s (%.3f s)" % [ev,want[ev][0],s.get_length() if s!=null else -1.0])
	check(is_equal_approx(AUDIO.gain(&"hurt"),-4.0) and is_equal_approx(AUDIO.gain(&"ambient"),-8.0) and is_equal_approx(AUDIO.gain(&"charge_start"),0.0),"gains unchanged (hurt -4, ambient -8, charge start 0 dB)")
	var hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate();hero.name="T11Haochen";hero.Team="Team0";hero.position=center
	world.add_child(hero,true)
	await process_frame
	hero.state_machine.set_physics_process(false)
	check(is_equal_approx(hero.hurt_voice_chance,0.45),"hurt voice probability is the unchanged mc_mob_base value (%.2f)" % hero.hurt_voice_chance)
	# Hurt: through a real damage entry; force the roll to always / never succeed.
	var chance:float=hero.hurt_voice_chance
	hero.hurt_voice_chance=1.0
	hero.receive_positional_damage(10.0,hero.global_position,true,null)
	await process_frame
	var hv:Array=voices(hero,&"hurt")
	check(hv.size()==1 and hv[0].stream.resource_path==DIR+"hurt_ah.wav","a real hit plays \"啊\"")
	await create_timer(0.7,true,false,true).timeout
	hero.hurt_voice_chance=0.0
	var before:Array=voices(hero,&"hurt").map(func(n):return n.get_instance_id())
	hero.receive_positional_damage(10.0,hero.global_position,true,null)
	await process_frame
	check(voices(hero,&"hurt").filter(func(n):return not before.has(n.get_instance_id())).is_empty(),"the hurt voice still follows the probability roll (0 -> no new voice)")
	hero.hurt_voice_chance=chance
	# Breathing: the resting ambient timer.
	check(hero.charge_phase==hero.Phase.RESTING,"resting")
	hero._ambient_left=0.0
	hero._step_creature_audio(1.0/60.0)
	await process_frame
	var av:Array=voices(hero,&"ambient")
	check(av.size()==1 and av[0].stream.resource_path==DIR+"breath_haoqidai.wav","resting breathing plays \"好期待啊\"")
	check(hero._ambient_left>=3.0 and hero._ambient_left<=7.0,"next breath is still scheduled 3-7 s later (%.2f)" % hero._ambient_left)
	hero._ambient_left=0.0
	hero._step_creature_audio(1.0/60.0)
	await process_frame
	check(voices(hero,&"ambient").size()==1,"breaths never overlap")
	# Charging start voice.
	hero._emit_audio(&"charge_start")
	await process_frame
	var cv:Array=voices(hero,&"charge_start")
	check(cv.size()==1 and cv[0].stream.resource_path==DIR+"charge_start.wav" and absf(cv[0].stream.get_length()-2.368)<0.02,"charging start plays the new \"今天搬哪个\" recording")
	print("HAOCHEN_TASK11 checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
