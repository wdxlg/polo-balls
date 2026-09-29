extends "res://tests/test_mc_warden_sound.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func():finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(170,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.voice_controller.set_process(false)
	w.form=w.Form.AWAKE; w._form_stats(true)
	w.hear_noise(enemy,enemy.global_position,"attack",120); w.begin_sonic()
	var charge:AudioStreamPlayer2D=w._cue_players.back()
	check(charge.volume_db==0 and charge.stream.resource_path.ends_with("sonic_charge.ogg"),"charge audio raised to 0 dB")
	var screen:Node=world.get_node("MCWardenScreenFX")
	screen.set_process(false)
	var tiny:float=0
	for i:int in range(10):
		screen._process(0.02); tiny=maxf(tiny,screen.shake_offset.length())
	check(tiny>0.2 and tiny<2.0,"windup has subtle visible shake below two pixels")
	w.sonic_left=0; w.release_sonic(); halt_waves(w)
	var boom:AudioStreamPlayer2D=w._cue_players.back()
	check(boom.volume_db==2 and boom.stream.resource_path.ends_with("sonic_boom.ogg"),"release audio raised to +2 dB without old zero cap")
	var strong:float=0
	for i:int in range(10):
		screen._process(0.01); strong=maxf(strong,screen.shake_offset.length())
	check(strong>5.0 and strong>tiny*3.0,"release produces much stronger short screen shake")
	var remaining:float=screen.shake_left
	game.now_stop_state=true; screen._process(1)
	check(screen.shake_left==remaining,"pause freezes screen shake")
	game.now_stop_state=false; screen._process(0.6)
	check(screen.shake_offset==Vector2.ZERO and not screen.rect.visible,"shake and recoil cleanly stop without permanent screen displacement")
	w._cancel_attacks(true); w.form=w.Form.DORMANT; w.signals_received=5
	var cues_before:int=w._cue_players.size()
	check(w.begin_emergence() and w.emerge_duration==3 and w.form_left==3,"climb-out is slowed from 1.8 to 3 seconds")
	check(w._cue_players.size()==cues_before+2 and w._cue_players[cues_before].stream.resource_path.ends_with("shrieker.ogg"),"summoning explicitly plays shrieker scream before emerge sound")
	check(w._cue_players[cues_before].volume_db==-3 and w._cue_players.back().volume_db==-2,"summon sounds are louder")
	check(screen.summon_left==3,"summon screen sequence follows slower emergence duration")
	w.step_mob(1.81)
	check(w.form==w.Form.EMERGING,"old climb-out timing no longer finishes awakening early")
	w.step_mob(1.2)
	check(w.form==w.Form.AWAKE,"slower emergence still completes normally")
	# Actual rendered bar color, not just a source-code constant.
	screen._process(4); w.form=w.Form.DORMANT; w.alert_level=50; w.visual_mob(); w.frontier_fx.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var point:Vector2=root.get_final_transform()*w.get_canvas_transform()*(w.global_position+Vector2(-10,18.6))
	var pixel:Color=root.get_texture().get_image().get_pixelv(Vector2i(point))
	check(pixel.b>pixel.r+0.25 and pixel.b>pixel.g,"GPU shrieker alert bar fill is blue")
	print("WARDEN SHAKE/LEVELS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
