extends "res://tests/test_mc_warden_sound.gd"
## 瞄准提示：尖啸体探测波 / 监守者近战 / 声波蓄力期间，aim_* 指向声源位置；出手或取消后消失。
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func():finish(2))
	var w:Node=actor("监守者",o)
	var enemy:Node=dummy(o+Vector2(170,0))
	await physics_frame;await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	check(w.aim_left==0.0 and w.aim_kind=="","no aim hint before any attack")
	# 尖啸体：警戒满 → 探测波序列，提示指向记录的声源
	w.alert_level=w.alert_max
	# hear_noise 在警戒已满时可能自己就拉起探测序列；两种路径都接受。
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.probe_left>0.0 or w.begin_probe(),"probe sequence begins")
	check(w.aim_kind=="probe" and w.aim_left>0.0 and w.aim_point.distance_to(enemy.global_position)<0.01,"probe aim hint marks the recorded sound position")
	w.emit_probe(); w._probe_wait=w.probe_interval
	var total:float=w.aim_total
	check(w.probes_remaining>0 and w.aim_kind=="probe","hint re-arms for the next probe")
	w.step_mob(0.1)
	check(w.aim_left<total and w.aim_left>0.0,"aim hint counts down with the attack windup")
	while w.probes_remaining>0: w.emit_probe()
	check(w.aim_left==0.0 and w.aim_kind=="","aim hint disappears after the last probe")
	halt_waves(w)
	# 监守者声波：蓄力全程提示，释放时消失
	w._cancel_attacks(true);w.form=w.Form.AWAKE;w._form_stats(true);w._sonic_cooldown=0
	w.sounds.clear();w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic(),"sonic charge begins")
	check(w.aim_kind=="sonic" and absf(w.aim_total-w.sonic_windup)<0.001 and w.aim_point.distance_to(enemy.global_position)<0.01,"sonic aim hint covers the whole windup at the sound position")
	var state:Dictionary=w.visual_state()
	check(state.has("aim") and state.has("aim_left") and state.aim_kind=="sonic","aim hint is part of the replicated visual state")
	w.dizziness=true;w.step_mob(0.3)
	check(w.aim_left>0.0 and w.aim_left<w.sonic_windup,"stun does not cancel the hint of a committed sonic charge")
	w.dizziness=false
	w.step_mob(w.sonic_windup);halt_waves(w)
	check(latest(w,"sonic")!=null and w.aim_left==0.0,"hint disappears exactly when the sonic wave is released")
	# 近战：短前摇提示，释放后消失；取消攻击也会清掉
	w._cancel_attacks(true);w.sonic_recover=0;w._attack_cooldown=0
	w.sounds.clear();enemy.global_position=w.global_position+Vector2(30,0)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_melee(),"melee begins")
	check(w.aim_kind=="melee" and w.aim_point.distance_to(enemy.global_position)<0.01,"melee aim hint marks the sound position")
	w.melee_left=0;w.release_melee()
	check(w.aim_left==0.0,"melee release clears the hint")
	w._attack_cooldown=0;w.sounds.clear();w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_melee() and w.aim_left>0.0,"second melee re-arms the hint")
	w._cancel_attacks(true)
	check(w.aim_left==0.0 and w.aim_kind=="","cancelling attacks removes the hint")
	# 镜像端：accept_visual 复制提示并自行倒数
	var mirror:Node=actor("监守者",o+Vector2(0,200))
	await physics_frame
	mirror.accept_visual({"aim":enemy.global_position,"aim_left":0.5,"aim_total":1.0,"aim_kind":"sonic"})
	check(mirror.aim_kind=="sonic" and mirror.aim_left==0.5,"replica accepts the aim hint")
	mirror.client_visual_step(0.2)
	check(absf(mirror.aim_left-0.3)<0.001,"replica counts the hint down locally")
	# 绘制不报错
	w._aim("sonic",enemy.global_position,1.0);w.frontier_fx.queue_redraw();await process_frame
	check(true,"aim hint draws without errors")
	print("WARDEN_AIM_HINT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
