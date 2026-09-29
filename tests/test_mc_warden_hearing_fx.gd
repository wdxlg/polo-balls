extends "res://tests/test_mc_warden_sound.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	var ally:Node2D=dummy(o+Vector2(120,80),"Team0")
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	var fx:Node2D=w.frontier_fx
	fx.set_process(false)
	for form:int in [w.Form.DORMANT,w.Form.AWAKE]:
		w.form=form; w.global_position=o; w.direction=Vector2.LEFT
		fx.hearing_signals.clear()
		var credits:int=w.signals_received
		var hp:float=enemy.health
		check(w.hear_noise(enemy,o+Vector2(120,0),"attack",120),"form hears an audible enemy action")
		check(fx.hearing_signals.size()==1 and fx.hearing_signals[0].point==o+Vector2(120,0),"hearing FX starts at recorded sound position in form "+str(form))
		fx._process(0.1)
		check(fx.hearing_signals[0].point.distance_to(o)<120 and not fx.hearing_signals[0].arrived,"hearing signal visibly travels inward, not an instant line")
		w.global_position=o+Vector2(0,30)
		fx._process(0.3)
		check(fx.hearing_signals[0].arrived and fx.hearing_signals[0].point==w.global_position,"signal follows moving listener and arrives at its current position")
		check(w.signals_received==credits and enemy.health==hp,"pure hearing feedback grants no summon progress or damage")
		fx._process(0.17)
		check(fx.hearing_signals.is_empty(),"arrival flash finishes and is cleaned up")
		check(not w.hear_noise(ally,ally.global_position,"attack",120),"ally sound is rejected")
		check(not w.hear_noise(enemy,w.global_position+Vector2(400,0),"attack",120) and fx.hearing_signals.is_empty(),"inaudible or rejected sounds create no visual signal")
	fx.burst("heard_noise",o+Vector2(100,0),Vector2.ZERO)
	var point:Vector2=fx.hearing_signals[0].point
	game.now_stop_state=true; fx._process(1.0)
	check(fx.hearing_signals[0].point==point,"pause freezes hearing signal flight")
	game.now_stop_state=false
	for i:int in range(50): fx.burst("heard_noise",o+Vector2(100,0),Vector2.ZERO)
	check(fx.hearing_signals.size()==24,"many enemy sounds keep a bounded number of visual signals")
	check(w.waves.is_empty(),"hearing visuals do not create gameplay projectiles or echo tokens")
	w.form=w.Form.DORMANT; w.global_position=o; w.alert_level=0
	fx.hearing_signals.clear()
	var voice:Node=w.voice_controller
	voice.set_process(false); voice.tendril_chance=1.0; voice.waits.tendril=0.0
	var prior:Variant=voice.players.get("tendril")
	if is_instance_valid(prior): prior.stop()
	var clips:int=int(voice.counts.get("tendril",0))
	check(w.hear_noise(enemy,o+Vector2(180,0),"move",24),"weak but audible sound is still heard")
	check(fx.hearing_signals.is_empty() and w.alert_level>0,"heard strength 12 is visually filtered without changing alert logic")
	check(int(voice.counts.get("tendril",0))==clips+1,"shrieker hearing can play tendril clicks")
	check(voice.waits.tendril>voice.last_duration.tendril,"shrieker tendril playback retains finish-before-replay spacing")
	w.hear_noise(enemy,o+Vector2(180,0),"attack",32)
	check(fx.hearing_signals.size()==1,"heard strength exactly 16 is visible")
	check(fx.VIBRATION.resource_path.ends_with("vibration.png"),"hearing uses the native vibration animation instead of sonic ring chains")
	print("WARDEN HEARING FX: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
