extends "res://tests/test_ding_z_squash.gd"
func anchor() -> Vector2:
	return cat.get_node("Graphics").transform*cat._pose_pivot
func reset_pose() -> void:
	cat.awake=false;cat._reset_z_pose();cat.sleep_left=60;cat._burst_wait=100
	cat.dizziness=false;cat.Can_Attack=true;cat.Can_Skill=true
	cat._sync_wave(false);cat._refresh_visual()
func snapshot(key:String) -> void:
	cat._counter.hide();cat.health_bar.hide()
	if is_instance_valid(cat._wave):cat._wave.hide()
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var frame:Image=root.get_texture().get_image()
	gpu_images[key]=frame;frame.save_png("user://ding_anchor_"+key+".png")
func run() -> void:
	create_timer(75).timeout.connect(func():print("DING_ANCHOR_TIMEOUT");quit(2))
	game=root.get_node("Game");game.now_stop_state=false
	arena=Node2D.new();root.add_child(arena);current_scene=arena
	var camera:=Camera2D.new();camera.zoom=Vector2(6,6);arena.add_child(camera)
	cat=load(CAT_PATH).instantiate();cat.Team="Team0";arena.add_child(cat)
	cat.state_machine.set_physics_process(false);cat.set_process(false)
	node_added.connect(heard);await flush()
	var graphic:Node2D=cat.get_node("Graphics")
	var foot:Vector2=anchor()
	var body:Transform2D=cat.get_node("CollisionShape2D").global_transform
	var hurt:Transform2D=cat.self_hurtbox.get_node("CollisionShape2D").global_transform
	var hud:Transform2D=cat.health_bar.get_transform()
	var counter:Transform2D=cat._counter.get_transform()
	var position:Vector2=cat.position
	cat.image.hide();await snapshot("blank");cat.image.show();await snapshot("rest")
	for phase:int in [1,2,3,4,6]:
		cat.z_pose_phase=phase;cat.z_recover_from=cat.Z_TALL if phase==3 else Vector2.ONE
		var anchored:bool=true
		for i:int in range(181):
			cat.z_pose_age=float(i)/180.0;cat._apply_z_pose()
			anchored=anchored and anchor().distance_to(foot)<0.0001
		check(anchored,"bottom-center fixed across dense pose samples, phase "+str(phase))
	check(cat.position==position and cat.get_node("CollisionShape2D").global_transform==body and cat.self_hurtbox.get_node("CollisionShape2D").global_transform==hurt,"anchor compensation never moves root or collisions")
	check(cat.health_bar.get_transform()==hud and cat._counter.get_transform()==counter,"HUD transforms unaffected including wave tremble")
	for phase:int in [1,2,3,6]:
		cat.z_pose_phase=phase;cat.z_recover_from=cat.WAVE_TALL if phase==3 else Vector2.ONE
		var duration:float=cat.z_windup_time if phase==1 else cat.z_stretch_time if phase==2 else cat.z_recover_time if phase==3 else cat.wave_stretch_time
		cat.z_pose_age=0;var first:Vector2=cat.z_pose_scale()
		cat.z_pose_age=0.0001;var start_speed:float=cat.z_pose_scale().distance_to(first)/0.0001
		cat.z_pose_age=duration;var last:Vector2=cat.z_pose_scale()
		cat.z_pose_age=duration-0.0001;var end_speed:float=cat.z_pose_scale().distance_to(last)/0.0001
		check(start_speed<0.01 and end_speed<0.03,"smooth zero-speed endpoints, phase "+str(phase))
	reset_pose();cat._burst_wait=0;cat.begin_burst(Vector2.RIGHT);cat.step_sleep(cat.z_windup_time)
	check(cat.shots_fired==1 and cat.z_pose_phase==2 and not cat.wave_charging,"Z has no added tremble hold")
	cat.step_sleep(cat.z_stretch_time)
	var transition:Vector2=cat.z_pose_scale()
	cat._wake()
	check(cat.wave_charging and cat.z_pose_scale().is_equal_approx(transition),"wave charge takes over Z without snapping")
	check(cat._shots_left==0 and not cat.begin_burst(Vector2.RIGHT),"wave charge cancels remaining Z and prevents active retrigger")
	await clear_shots();reset_pose()
	var count:int=cat.wakes_fired
	cat.sleep_left=0.001;cat.step_sleep(0.002)
	check(cat.wave_charging and not cat.awake and not cat._counter.visible,"zero starts closed-eye charge and hides countdown")
	check(not is_instance_valid(cat._wave) and cat.wakes_fired==count,"compression creates neither real wave nor extra cast")
	cat.step_sleep(cat.wave_windup_time);await snapshot("flat")
	check(cat.z_pose_scale().is_equal_approx(cat.WAVE_FLAT),"stronger wave squash reached before tremble")
	check(cat.WAVE_FLAT.x>cat.Z_FLAT.x and cat.WAVE_FLAT.y<cat.Z_FLAT.y and cat.WAVE_TALL.x<cat.Z_TALL.x and cat.WAVE_TALL.y>cat.Z_TALL.y,"wave compression and elongation are both larger than Z")
	var low:float=10;var high:float=0
	for i:int in range(35):
		cat.step_sleep(0.01)
		low=minf(low,cat.z_pose_scale().y);high=maxf(high,cat.z_pose_scale().y)
	check(high-low>0.012 and low>0.40 and high<0.44,"flat held pose visibly trembles without returning to normal")
	check(cat.wave_charging and not is_instance_valid(cat._wave) and cat.wakes_fired==count,"held shiver still has no attack")
	await snapshot("shiver")
	var frozen:Transform2D=graphic.transform;var age:float=cat.z_pose_age
	game.now_stop_state=true;cat.step_sleep(2);cat._process(2)
	check(graphic.transform==frozen and cat.z_pose_age==age,"pause freezes tremble even through render updates")
	game.now_stop_state=false;cat.step_sleep(0.099)
	check(not is_instance_valid(cat._wave),"wave cannot fire just before charge boundary")
	cat.step_sleep(0.0011)
	check(cat.awake and not cat.wave_charging and cat.wakes_fired==count+1 and is_instance_valid(cat._wave),"actual wave appears only after complete compression and held shiver")
	check(cat.z_pose_phase==6 and cat.z_pose_scale().is_equal_approx(cat.WAVE_FLAT),"wave release begins stretching from exact flat pose")
	check(cat.image.texture==cat.OPEN and is_equal_approx(cat.awake_left,2.0),"eyes open and two-second awake timer begin on real release")
	await flush()
	check(sounds.get("entity.warden.sonic_boom",0)==1,"one native wave sound on real release, none during charge")
	cat.step_sleep(cat.wave_stretch_time);await snapshot("tall")
	check(cat.z_pose_scale().is_equal_approx(cat.WAVE_TALL),"wave reaches stronger tall limit")
	cat.step_sleep(0.3);await snapshot("hold")
	check(cat.z_pose_scale().is_equal_approx(cat.WAVE_TALL),"wave keeps tall limit while ring still attacks")
	cat.step_sleep(cat.wave_duration-cat.wave_age+0.0001)
	check(cat.z_pose_phase==3 and cat.z_pose_scale().is_equal_approx(cat.WAVE_TALL),"wave ending starts continuous recovery rather than snap")
	cat.step_sleep(cat.wave_recover_time*0.5)
	check(cat.z_pose_scale().y>1 and cat.z_pose_scale().y<cat.WAVE_TALL.y,"wave release smoothly returns through intermediate sizes")
	cat.step_sleep(cat.wave_recover_time*0.5+0.001);await snapshot("restored")
	check(graphic.transform.is_equal_approx(cat._pose_base) and anchor().is_equal_approx(foot),"full recovery restores exact base and anchor")
	cat.step_sleep(2)
	check(not cat.awake and cat.sleep_left==60 and cat.wakes_fired==count+1,"return to sleep has no second wave")
	for interrupt:String in ["dizziness","Can_Attack","Can_Skill"]:
		reset_pose();cat._wake();cat.step_sleep(cat.wave_windup_time+0.15)
		count=cat.wakes_fired;cat.set(interrupt,interrupt=="dizziness");cat.step_sleep(0.01)
		check(not cat.wave_charging and cat.z_pose_phase==3 and not is_instance_valid(cat._wave),interrupt+" cancels unspent wave and smoothly recovers")
		cat.step_sleep(cat.wave_recover_time+0.01)
		check(cat.wakes_fired==count and graphic.transform.is_equal_approx(cat._pose_base),interrupt+" cannot create delayed damage")
	for rate:int in [30,60,120]:
		reset_pose();cat._wake();var elapsed:float=0
		while cat.wave_charging and elapsed<2:
			cat.step_sleep(1.0/rate);elapsed+=1.0/rate
		check(absf(elapsed-cat.wave_windup_time-cat.wave_shiver_time)<=1.0/rate+0.00001,"charge duration bounded to one physics tick at "+str(rate)+" Hz")
		check(anchor().distance_to(foot)<0.0001,"anchor preserved through real timed charge at "+str(rate)+" Hz")
	reset_pose()
	# Exercise actual render interpolation between two authority samples, not just the ease function.
	cat._pose_previous=cat.WAVE_FLAT;cat._pose_current=cat.WAVE_TALL;cat._pose_tick=Engine.get_physics_frames()
	cat._render_z_pose(0.002)
	var expected:Vector2=cat._pose_previous.lerp(cat._pose_current,Engine.get_physics_interpolation_fraction())
	check(graphic.scale.is_equal_approx(expected*cat._pose_base.get_scale()) and anchor().distance_to(foot)<0.0001,"render subframe uses authority interpolation and retains anchor")
	reset_pose();cat._wake();cat.step_sleep(0.4);cat.Die()
	check(not cat.wave_charging and cat.z_pose_phase==0 and graphic.transform.is_equal_approx(cat._pose_base),"death clears charge and anchor compensation before shared death")
	if not gpu_images.is_empty():
		var rest:Rect2i=changed_bounds(gpu_images.rest,gpu_images.blank)
		var flat:Rect2i=changed_bounds(gpu_images.flat,gpu_images.blank)
		var tall:Rect2i=changed_bounds(gpu_images.tall,gpu_images.blank)
		var hold:Rect2i=changed_bounds(gpu_images.hold,gpu_images.blank)
		var restored:Rect2i=changed_bounds(gpu_images.restored,gpu_images.blank)
		print("DING_ANCHOR_PIXELS rest=%s flat=%s tall=%s hold=%s restored=%s"%[rest,flat,tall,hold,restored])
		check(absi(flat.end.y-rest.end.y)<=1 and absi(tall.end.y-rest.end.y)<=1,"real GPU bottom edge stays fixed to raster tolerance")
		check(absf(flat.get_center().x-rest.get_center().x)<=1 and absf(tall.get_center().x-rest.get_center().x)<=1,"real GPU horizontal center stays fixed")
		check(flat.size.x>rest.size.x*1.45 and flat.size.y<rest.size.y*0.5,"real GPU wave flat amplitude is larger")
		check(tall.size.y>rest.size.y*1.65 and tall.size.x<rest.size.x*0.6,"real GPU wave tall amplitude is larger")
		check(hold==tall and restored==rest,"GPU hold and full restoration retain expected bounds")
	cat.queue_free();await create_timer(1.2).timeout
	arena.queue_free();await flush()
	print("DING_ANCHOR_RESULT checks=%d failures=%d renderer=%s"%[checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
