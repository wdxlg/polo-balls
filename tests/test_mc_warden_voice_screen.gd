extends "res://tests/test_mc_warden_sound.gd"
func reset_channel(voice:Node,channel:String) -> void:
	var p:Variant=voice.players.get(channel)
	if is_instance_valid(p): p.stop()
	voice.waits[channel]=0.0
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func():finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	var voice:Node=w.voice_controller
	voice.set_process(false)
	voice.waits.breath=0.0; voice._process(0.01)
	check(voice.counts.is_empty(),"shrieker does not play awakened breathing or footstep loops")
	w.form=w.Form.AWAKE; w._form_stats(true)
	reset_channel(voice,"breath"); voice._process(0.01)
	check(voice.players.breath.get_meta("warden_voice")=="ambient","normal breathing uses native ambient groan")
	check(voice.waits.breath>voice.last_duration.breath,"minimum breath replay delay exceeds actual preceding audio length")
	check(not voice.play_channel("breath","ambient",-10),"same breathing channel cannot overlap")
	var count_before:int=voice.counts.breath
	voice._voice_event(voice._received,"breath","ambient",1,-10)
	check(voice.counts.breath==count_before,"replayed network voice events do not duplicate audio")
	reset_channel(voice,"breath"); w.rage_left=2.8; voice._process(0.01)
	check(voice.players.breath.get_meta("warden_voice")=="angry","angry breathing selects native angry groan")
	w.rage_left=0; voice.tendril_chance=1.0
	w.hear_noise(enemy,enemy.global_position,"attack",200)
	check(int(voice.counts.get("roar",0))==1,"entering rage triggers one native roar")
	w.hear_noise(enemy,enemy.global_position,"attack",200)
	check(int(voice.counts.get("roar",0))==1,"refreshing existing rage does not repeatedly roar")
	check(int(voice.counts.get("tendril",0))==1 and voice.waits.tendril>voice.last_duration.tendril,"heard sound can play tendril clicks with clip-length cooldown")
	reset_channel(voice,"tendril"); voice.tendril_chance=0.0
	w.hear_noise(enemy,enemy.global_position,"attack",200)
	check(int(voice.counts.tendril)==1,"tendril probability gate can skip heard sounds")
	voice._step_cadence.ready_now(); reset_channel(voice,"step")
	w.velocity=Vector2(30,0); w.global_position+=Vector2(3,0); voice._process(0.1)
	check(int(voice.counts.get("step",0))==1,"actual walking emits native footsteps")
	# 脚步按走过的距离计步：步幅 = 基础速度 × 基础间隔；快速走完一步时可与上一声重叠。
	var stride:float=voice.FOOTSTEP.base_speed(w)*voice.step_base_interval
	w.global_position+=Vector2(stride*0.5,0); voice._process(0.1)
	check(int(voice.counts.step)==1,"half a stride adds no footstep")
	w.global_position+=Vector2(stride*0.6,0); voice._process(0.1)
	check(int(voice.counts.step)==2,"after one stride the next footstep starts even while the previous plays")
	voice._process(0.3)
	check(int(voice.counts.step)==2,"fake velocity while stationary does not produce footsteps")
	var wait:float=voice.waits.breath
	game.now_stop_state=true; voice._process(2.0)
	await process_frame
	voice._process(0.0)
	check(voice.waits.breath==wait and voice.players.breath.stream_paused,"pause freezes voice timers and audio")
	game.now_stop_state=false; voice._process(0.01)
	await process_frame
	check(not voice.players.breath.stream_paused,"audio resumes with gameplay")
	w._cancel_attacks(true); w.form=w.Form.DORMANT; w.signals_received=5
	check(w.begin_emergence(),"five returned signals starts emergence")
	check(w._cue_players.back().stream.resource_path.ends_with("emerge.ogg"),"emergence plays native emerge sound")
	var screen:Node=world.get_node("MCWardenScreenFX")
	screen.set_process(false)
	check(screen.summon_left>0 and screen.rect.mouse_filter==Control.MOUSE_FILTER_IGNORE,"summon begins viewport-wide flashes without intercepting controls")
	var pulses:int=0
	var was_on:bool=false
	for i:int in range(61):
		screen._process(0.05)
		var on:bool=float(screen.shader_material.get_shader_parameter("darkness"))>0.0
		if on and not was_on: pulses+=1
		was_on=on
	check(pulses==1 and screen.summon_left<=0.0001,"summon uses continuous darkness with pulses then clears")
	w.form=w.Form.AWAKE; w._form_stats(true); w.global_position=o; w._sonic_cooldown=0
	w.sounds.clear(); w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic() and w._cue_players.back().stream.resource_path.ends_with("sonic_charge.ogg"),"sonic windup plays native charge sound")
	w.sonic_left=0; w.release_sonic(); halt_waves(w)
	check(w._cue_players.back().stream.resource_path.ends_with("sonic_boom.ogg") and screen.inversion_left>0,"sonic release plays native boom and triggers inversion")
	# Actual GPU pixels, not just shader parameters: cover world with a known test color below the screen layer.
	var layer:=CanvasLayer.new(); layer.layer=119; world.add_child(layer)
	var background:=ColorRect.new(); layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.color=Color(0.2,0.3,0.4)
	screen.inversion_left=0; screen._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	var original:Color=root.get_texture().get_image().get_pixel(20,20)
	screen._invert_gap=0; screen.trigger(w,"sonic_screen"); screen._process(0.01)
	await process_frame; await RenderingServer.frame_post_draw
	var inverted:Color=root.get_texture().get_image().get_pixel(20,20)
	check(absf(inverted.r-(1-original.r))<0.04 and absf(inverted.g-(1-original.g))<0.04 and absf(inverted.b-(1-original.b))<0.04,"GPU output briefly inverts the entire screen color")
	screen._process(0.11)
	check(float(screen.shader_material.get_shader_parameter("inversion"))==0.0,"inversion clears after a tenth of a second while recoil may continue")
	screen._process(0.5)
	layer.queue_free()
	w.begin_burrow()
	check(w._cue_players.back().stream.resource_path.ends_with("warden_dig.ogg"),"leaving plays native digging sound")
	print("WARDEN VOICE/SCREEN: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
