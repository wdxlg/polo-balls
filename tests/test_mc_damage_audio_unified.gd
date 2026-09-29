extends "res://tests/test_mc_snow_golem.gd"
## Production scenes + real receive paths. No fake health setters/audio players.
var feedback:Script
var captured:Array[Dictionary] = []
var captures:Array[Node] = []
var probe:AudioEffectCapture
var probe_bus:int = -1
var generic_voices:int = 0

func observe(node:Node) -> void:
	if node is AudioStreamPlayer2D:
		for event:String in ["entity.player.hurt","entity.player.attack.crit"]:
			for record:Dictionary in feedback.AUDIO.EVENTS[event]:
				if node.stream==record.stream:
					generic_voices+=1
	if node is AudioStreamPlayer2D and node.get_meta("mc_unified_hit",false):
		captured.append({"event":node.get_meta("mc_sound_event"),"actual":node.get_meta("mc_actual_damage"),"gain":node.volume_db,"stream":node.stream.resource_path})
		captures.append(node)
		if probe_bus>=0: node.bus = &"MCHitProbe"

func reset_victim(target:Node2D,hp:int = 10000,armor:int = 0,reduction:float = 0.0) -> void:
	clear_cold(target)
	for child:Node in target.get_children():
		if child.name=="WitherStatus" or str(child.name).begins_with("MinecraftStatus_"): child.free()
	target.Max_health = 10000
	target.health = hp
	target.max_block = maxi(armor,500)
	target.block = armor
	target.Damage_reduction = reduction
	target.dizziness = false

func expect_hit(target:Node2D,previous:int,actual:float,label:String) -> void:
	check(target.mc_damage_audio_count==previous+1,label+" emits exactly one cue")
	check(is_equal_approx(float(target.mc_damage_audio_last.get("actual",-1)),actual),label+" measures real bounded HP loss")
	check(target.mc_damage_audio_last.get("event","")==feedback.GAIN.damage_event(actual),label+" selects strict >50 event")
	check(is_equal_approx(float(target.mc_damage_audio_last.get("gain",-1)),feedback.GAIN.damage_gain(actual)),label+" uses nonnegative default-baseline damage gain")

func run() -> void:
	var center:Vector2 = await setup_world()
	feedback = load("res://scripts/effects/我的世界/mc_hit_feedback.gd")
	create_timer(140.0).timeout.connect(func(): finish(2))
	world._mc_prewarmer.set_process(false)
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"background native imports/preloads settle")
	node_added.connect(observe)
	probe_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(probe_bus,&"MCHitProbe")
	probe = AudioEffectCapture.new()
	AudioServer.add_bus_effect(probe_bus,probe)
	var target:Node2D = dummy(center+Vector2(180,0))
	var guardian:Node2D
	var roles:Array[String] = []
	var dir:=DirAccess.open("res://scenes/characters/我的世界")
	for file:String in dir.get_files():
		if file.ends_with(".tscn"): roles.append(file.trim_suffix(".tscn"))
	roles.sort()
	check(roles.size()==44,"all 44 selectable Minecraft roles enumerated")
	var automatic:int = 0
	for role:String in roles:
		var scene:PackedScene = load("res://scenes/characters/我的世界/"+role+".tscn")
		check(scene!=null,"scene loads: "+role)
		var actor:Node2D = scene.instantiate()
		actor.Team = "Team0"
		actor.position = center-Vector2(180,0)
		world.add_child(actor,true)
		actor.state_machine.set_physics_process(false)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.self_hitbox.set_deferred("monitoring",false)
		check(feedback.script_policy(actor.get_script())>=0,"explicit reviewed audio policy: "+role)
		if feedback.manages(actor):
			automatic += 1
			for amount:float in [1.0,49.0,50.0,51.0,100.0,1000.0]:
				reset_victim(target)
				var previous:int = target.mc_damage_audio_count
				check(target.receive_positional_damage(amount,target.global_position,false,actor),role+" damage accepted")
				expect_hit(target,previous,amount,role+" damage="+str(amount))
			reset_victim(target,17)
			var previous:int = target.mc_damage_audio_count
			target.receive_positional_damage(1000,target.global_position,false,actor)
			expect_hit(target,previous,17,role+" overkill capped at remaining HP")
			reset_victim(target,10000,0,0.5)
			previous = target.mc_damage_audio_count
			target.receive_positional_damage(100,target.global_position,false,actor)
			expect_hit(target,previous,50,role+" reduction crosses threshold downward")
			reset_victim(target,10000,500)
			previous = target.mc_damage_audio_count
			target.receive_positional_damage(51,target.global_position,false,actor)
			check(target.mc_damage_audio_count==previous,role+" shield-only hit has no health cue")
			reset_victim(target)
			previous = target.mc_damage_audio_count
			target.receive_spatial_raw_health_damage(51,{"point":target.global_position,"source":actor,"shape":"all"})
			expect_hit(target,previous,51,role+" raw-health/status/execution route")
		if role=="守卫者": guardian=actor
		elif role=="石矛":
			for amount:float in [49,50,51]:
				actor._emit_audio(true,actor.global_position,amount)
				check(actor.last_sound_event==("minecraft:item.spear.hit" if amount<50 else feedback.GAIN.damage_event(amount)),"stone spear explicit replacement preserved "+str(amount))
			actor.queue_free()
		else: actor.queue_free()
		await process_frame
		await process_frame
	check(automatic==26,"only the 26 broken automatic routes migrated; 17 manual routes plus stone retained")
	reset_victim(target)
	for amount:float in [49,50,51]:
		for laser:bool in [false,true]:
			var previous:int=target.mc_damage_audio_count
			guardian.damage_with_sound(target,amount,laser)
			expect_hit(target,previous,amount,"guardian actual attack laser="+str(laser))
	# Distinct same-frame hits are not conflated by event throttling or proximity.
	var second:Node2D = dummy(center+Vector2(180,0))
	reset_victim(target)
	var previous:int = target.mc_damage_audio_count
	for i:int in range(20): target.receive_positional_damage(51,target.global_position,false,guardian)
	check(target.mc_damage_audio_count==previous+20,"20 same-frame settlements are 20 distinct cues")
	second.receive_positional_damage(49,second.global_position,false,guardian)
	check(second.mc_damage_audio_last.event=="entity.player.hurt","same-point second victim keeps its own low-damage event")
	var serial:int = target._mc_damage_audio_received
	previous = target.mc_damage_audio_count
	target._receive_mc_damage_audio(serial,51,target.global_position,0)
	target._receive_mc_damage_audio(serial+1,51,target.global_position,-1)
	check(target.mc_damage_audio_count==previous,"duplicate serial and invalid variant cannot replay feedback")
	for value:float in [0,-1,INF,NAN]: target.request_mc_damage_audio(value,target.global_position)
	check(target.mc_damage_audio_count==previous,"zero/negative/nonfinite damage cannot manufacture feedback")
	game.now_stop_state=true
	target.request_mc_damage_audio(51,target.global_position)
	check(target.mc_damage_audio_count==previous,"battle pause blocks new damage cues")
	game.now_stop_state=false
	target.set_multiplayer_authority(2)
	target.request_mc_damage_audio(51,target.global_position)
	check(target.mc_damage_audio_count==previous,"non-authority cannot emit local or remote damage cues")
	target.set_multiplayer_authority(1)
	# Status-only paths whose direct attacks were already correct remain single-owner.
	reset_victim(target)
	var before:float = target.health
	previous = target.mc_damage_audio_count
	target.receive_spatial_raw_health_damage(51,{"point":target.global_position,"shape":"all"})
	feedback.finish(null,target,before,target.global_position)
	expect_hit(target,previous,51,"source-expired status adapter")
	var sheep_player:AudioStreamPlayer2D = feedback.AUDIO.play(target,"entity.sheep.hit",target.global_position,-2,false,true,true,true)
	check(is_instance_valid(sheep_player) and sheep_player.volume_db==0.0,"legacy sheep alias cannot bypass 0dB floor")
	second.queue_free()
	await real_attack_checks(center,target)
	# Wait for queued native playback, not just request counters.
	await process_frame
	await process_frame
	check(not captured.is_empty(),"real native players were created by shared safe queue")
	for record:Dictionary in captured:
		check(record.gain>=0 and record.gain<=6 and record.stream.ends_with(".ogg"),"actual player gain and native OGG: "+record.event)
	await create_timer(1.1,true,false,true).timeout
	probe.clear_buffer()
	target.request_mc_damage_audio(51,target.global_position)
	await create_timer(0.22,true,false,true).timeout
	var pcm:PackedVector2Array = probe.get_buffer(probe.get_frames_available())
	var peak:float=0
	for sample:Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	print("MC_DAMAGE_PCM frames=",pcm.size()," peak=",peak)
	check(pcm.size()>128 and peak>0.000001,"native critical player produces real mixed PCM")
	node_added.disconnect(observe)
	for player:Node in captures:
		if is_instance_valid(player): player.queue_free()
	await process_frame
	AudioServer.remove_bus(probe_bus)
	probe_bus=-1
	print("MC_DAMAGE_UNIFIED_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func quiet_frames() -> void:
	await process_frame
	await process_frame

func parked(role:String,point:Vector2) -> Node2D:
	var actor:Node2D=spawn("res://scenes/characters/我的世界/"+role+".tscn",point)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.self_hitbox.monitoring=false
	return actor

func real_attack_checks(center:Vector2,target:Node2D) -> void:
	await quiet_frames()
	for role:String in ["末影人","蠹虫"]:
		var actor:Node2D=parked(role,center)
		actor.Damage=51
		reset_victim(target)
		var previous:int=target.mc_damage_audio_count
		actor._on_hitbox_on_hit(target.self_hurtbox)
		expect_hit(target,previous,51,role+" real common contact callback")
		actor.queue_free()
	await quiet_frames()
	var archer:Node2D=parked("弓",center)
	var arrow:Node=load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(arrow)
	arrow.configure_plain(archer,archer.Team,Vector2.RIGHT,200.0,100.0,0.0,100.0,2.0)
	arrow.set_physics_process(false)
	reset_victim(target,10000,0,0.5)
	var previous:int=target.mc_damage_audio_count
	var voices:int=generic_voices
	arrow._apply_damage(target,100.0)
	load("res://scripts/characters/我的世界/new6/fx_burst.gd").hit_sfx(archer,target.global_position,100)
	expect_hit(target,previous,50,"real arrow damage plus old nominal FX call")
	await quiet_frames()
	check(generic_voices==voices+1,"arrow no longer stacks ordinary and nominal critical layers")
	arrow.queue_free()
	archer.queue_free()
	await quiet_frames()
	for role:String in ["史莱姆","羊","苦力怕"]:
		var actor:Node2D=parked(role,center)
		reset_victim(target)
		target.global_position=actor.global_position
		var before:float=target.health
		previous=target.mc_damage_audio_count
		voices=generic_voices
		match role:
			"史莱姆":
				actor._pulse(true)
			"羊":
				actor._charge_speed=actor.charge_speed
				actor._charge_dir=Vector2.RIGHT
				actor._charge_touch(target,target.global_position)
			"苦力怕": actor._explode()
		var actual:float=maxf(before-float(target.health),0)
		check(actual>0,role+" real attack settled damage")
		expect_hit(target,previous,actual,role+" real attack method")
		await quiet_frames()
		check(generic_voices-voices==target.mc_damage_audio_count-previous,role+" one real player per settlement, including secondary collision damage")
		actor.queue_free()
		await quiet_frames()
	target.global_position=center+Vector2(180,0)
	var wither:Node2D=parked("凋灵",center)
	var effects:Script=load("res://scripts/effects/我的世界/mc_status_effects.gd")
	reset_victim(target)
	check(effects.apply_effect(target,"wither",1,5.0,wither),"real Wither status installed")
	var status:Node=target.get_node("WitherStatus")
	status.set_physics_process(false)
	previous=target.mc_damage_audio_count
	status._physics_process(1.0)
	expect_hit(target,previous,100,"real Wither tick at 10000 max HP")
	wither.queue_free()
	await quiet_frames()
	previous=target.mc_damage_audio_count
	status._physics_process(1.0)
	expect_hit(target,previous,100,"Wither tick after source freed")
	reset_victim(target)
	var witch:Node2D=parked("女巫",center)
	previous=target.mc_damage_audio_count
	effects.apply_effect(target,"instant_damage",2,1.0,witch)
	expect_hit(target,previous,100,"real level-two instant potion damage")
	witch.queue_free()
	reset_victim(target)
	var golem:Node2D=parked("雪傀儡",center)
	golem._field.set_physics_process(false)
	golem.Damage=300
	var cold:Node=COLD.ensure(target)
	check(cold.add_cold(100,2,golem),"real freezing effect installed")
	cold.set_physics_process(false)
	previous=target.mc_damage_audio_count
	var before:float=target.health
	cold._freeze_tick()
	expect_hit(target,previous,before-float(target.health),"real internal freeze tick")
	golem.queue_free()
	reset_victim(target)
	var non_mc:Node2D=dummy(center,"Team0")
	previous=target.mc_damage_audio_count
	target.receive_positional_damage(51,target.global_position,false,non_mc)
	check(target.mc_damage_audio_count==previous,"non-Minecraft source retains its original audio behavior")
	non_mc.queue_free()
	await quiet_frames()
