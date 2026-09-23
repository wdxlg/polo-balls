extends "res://scripts/training/test_mc_new5.gd"
const PROFILE=preload("res://scripts/characters/我的世界/wither/beacon_profile.gd")
const ARTIFACTS:String="user://beacon_volume/"
var beacon:Node2D
var wither:Node2D
var enemy:Node2D
func check(ok:bool,label:String) -> void:
	super.check(ok,label)
	if ok: print("PASS: "+label)
func advance(dt:float) -> void:
	beacon.clock+=dt
	beacon.step_mob(dt)
	beacon._process(0)
func reset_cycle() -> void:
	beacon.global_position=center+Vector2(0,87.4)
	beacon.fall_speed=0
	beacon.beam_timer=0
	beacon.warning_left=0
	beacon.firing_left=0
	beacon.beams_fired=0
	beacon.damage_ticks=0
	beacon.Repel=Vector2.ZERO
	wither.apply_beacon_buff("")
	enemy.global_position=center+Vector2(0,-140)
	enemy.health=1000
	enemy.block=0
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Training_Debug_Mode=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(65).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	wither=spawn("凋零",Vector2(-220,-70))
	wither.summoned=true
	wither.health=250
	wither.on_actual_health_damage_received(1,251)
	beacon=wither.beacon
	beacon.state_machine.set_physics_process(false)
	enemy=spawn("",Vector2(0,-140),"Team1")
	enemy.Max_health=1000
	enemy.Damage_reduction=0
	var floor_body:StaticBody2D=obstacle(Vector2(200,100),true)
	(floor_body.get_child(0).shape as RectangleShape2D).size=Vector2(1400,12)
	await physics_frame
	beacon.global_position=center
	advance(.5)
	check(beacon.landed and beacon._activated,"vanilla block lands as a real character")
	check(beacon.image.texture.resource_path.ends_with("beacon_block/beacon_block.png"),"body uses glass-shell, obsidian-base and inner-core block render")
	var model:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Images/characters/我的世界/wither/beacon_block/beacon.json"))
	check(model.elements.size()==3,"original block has all three elements, not the flat core texture")
	check(absf(beacon.image.texture.get_width()*beacon.image.scale.x-62)<.01,"new block preserves character width")
	check(is_equal_approx(PROFILE.speed_factor(.6,0),1) and is_equal_approx(PROFILE.speed_factor(.3,0),.75),"charge smoothly decelerates")
	check(absf(PROFILE.speed_factor(.00001,0)-.5)<.001 and is_equal_approx(PROFILE.speed_factor(0,PROFILE.FIRING),.5),"emission starts at continuous half speed")
	check(is_equal_approx(PROFILE.speed_factor(0,.175),.75) and is_equal_approx(PROFILE.speed_factor(0,0),1),"final 0.35s smoothly restores full speed")
	var width:float=beacon.body_width()
	check(PROFILE.width(width,.6,0)<width*.1,"preparation begins with a thin ray")
	check(PROFILE.width(width,0,PROFILE.FIRING-.08)>width and PROFILE.width(width,0,PROFILE.FIRING-.08)<width*1.2,"burst overshoots slightly beyond body width")
	check(PROFILE.width(width,0,PROFILE.FIRING-.2)<width*.9 and absf(PROFILE.width(width,0,PROFILE.FIRING-.6)-width*.9)<width*.01,"burst recoils and elastically settles")
	check(PROFILE.width(width,0,.175)<PROFILE.width(width,0,.35) and PROFILE.opacity(0,.175)<PROFILE.opacity(0,.35),"shutdown narrows and fades simultaneously")
	check(PROFILE.width(width,0,0)==0 and PROFILE.opacity(0,0)==0,"shutdown ends at zero width and opacity")
	for dt:float in [1.0/60.0,1.0/30.0,PROFILE.WARNING+PROFILE.FIRING]:
		reset_cycle()
		var remaining:float=PROFILE.WARNING+PROFILE.FIRING+.00001
		while remaining>.000001:
			var step:float=minf(remaining,dt)
			advance(step)
			remaining-=step
		print("DAMAGE_RESULT dt=",dt," pulses=",beacon.damage_ticks," health=",enemy.health)
		check(beacon.damage_ticks==50,"fifty pulses at dt="+str(dt))
		check(absf(enemy.health-700.0)<.001,"300 total damage at dt="+str(dt))
		check(beacon.beams_fired==1 and beacon.warning_left==0 and beacon.firing_left==0,"one finish event at dt="+str(dt))
	reset_cycle()
	var times:Array[float]=[]
	var small_hits:bool=true
	for i:int in range(561):
		var hp:float=enemy.health
		advance(.01)
		if enemy.health<hp:
			times.append((i+1)*.01)
			small_hits=small_hits and (hp-enemy.health)==6.0
	var high_frequency:bool=times.size()==50
	for i:int in range(1,times.size()): high_frequency=high_frequency and absf(times[i]-times[i-1]-.1)<.011
	check(high_frequency,"actual damage events repeat every 0.1s")
	check(small_hits and not times.is_empty() and times[0]>=.65,"every pulse is exactly 6 damage; warning remains harmless")
	reset_cycle()
	advance(.3)
	var position_before:Vector2=beacon.global_position
	var image_before:Vector2=beacon.image.position
	beacon.clock+=.017
	beacon._process(0)
	check(beacon.image.position!=image_before and beacon.global_position==position_before,"only sprite shakes, physics stays stable")
	check(beacon._beam_visual.global_rotation==0 and beacon.beam_end.x==beacon.beam_origin().x,"shake cannot deflect upward beam")
	var frozen:Vector2=beacon.image.position
	beacon._process(.5)
	check(beacon.image.position==frozen,"wall-time rendering cannot advance paused shake")
	check(not beacon._ring_back.visible and not beacon._ring_front.visible,"no launch ring during preparation")
	advance(.3)
	check(beacon._ring_back.visible and beacon._ring_front.visible,"one blue ring starts at the actual emission transition")
	check(beacon._ring_back.ARC.resource_path.ends_with("pixel_arc.gd"),"ring reuses the heavy mace pixel-circle renderer")
	check(beacon._ring_back.get_index()<beacon._beam_visual.get_index() and beacon._beam_visual.get_index()<beacon._ring_front.get_index(),"rear ring draws behind the shaft and front ring above it")
	check(beacon._ring_front.PLANE_RATIO>.35 and beacon._ring_front.PLANE_RATIO<.45,"ellipse tilt matches original beacon top-face camera projection")
	check(beacon._ring_front.global_position==beacon.beam_origin() and beacon.beam_origin().y>beacon.global_position.y-6.6,"ring and ray originate at top-face centre, not highest bounding-box corner")
	check(not beacon._ring_front.is_in_group("AI_Hazard") and not beacon._ring_front.has_method("get_ai_hazard_info"),"blue ring is cosmetic and cannot add unrequested area damage")
	var initial_radius:float=beacon._ring_front.radius
	advance(.12)
	check(beacon._ring_front.radius>initial_radius and beacon._ring_front.opacity<1,"ring expands rapidly and fades with the mace envelope")
	var frozen_radius:float=beacon._ring_front.radius
	beacon._process(.5)
	check(beacon._ring_front.radius==frozen_radius,"wall-time rendering does not advance paused ring")
	var old_ring_position:Vector2=beacon._ring_front.global_position
	beacon.global_position+=Vector2(3,2)
	beacon._process(0)
	check(beacon._ring_front.global_position==old_ring_position+Vector2(3,2),"ring follows moving beacon head without ground-level drift")
	advance(.35)
	check(not beacon._ring_front.visible and not beacon._ring_back.visible and beacon.firing_left>4,"ring ends once while the longer laser continues")
	reset_cycle()
	enemy.global_position=center+Vector2(500,-140)
	var start_x:float=beacon.global_position.x
	advance(.6)
	var fired_x:float=beacon.global_position.x
	check(fired_x>start_x+20 and absf(fired_x-start_x-27)<.4,"moving throughout charge with progressive slowing")
	advance(PROFILE.FIRING-PROFILE.RECOVERY)
	check(beacon.global_position.x>fired_x+130 and absf(beacon.movement_multiplier()-.5)<.001,"moving throughout emission at half speed")
	var recovery_x:float=beacon.global_position.x
	advance(.35)
	check(absf(beacon.global_position.x-recovery_x-15.75)<.4 and beacon.movement_multiplier()==1,"late motion recovers smoothly")
	beacon.firing_left=PROFILE.FIRING-.08
	beacon.warning_left=0
	beacon.beam_end=beacon._clipped_beam()
	beacon._process(0)
	var threat:Dictionary=beacon.get_ai_hazard_info(enemy)
	check(threat.shape=="rect" and threat.half_extents*2==beacon.beam_rect().size and threat.damage==PROFILE.pulse_damage(beacon._pulse_index),"threat matches animated physical rectangle and pulse damage")
	check(is_equal_approx(beacon._beam_visual.core_width,beacon.beam_rect().size.x),"full translucent volume width matches real damage width")
	var volume:Node2D=beacon._beam_visual
	var projected_ok:bool=true
	var clipped_ok:bool=true
	for angle:float in [0.0,.4,1.4,2.9]:
		var section:PackedVector2Array=volume.projected_section(width,angle)
		var left:float=INF
		var right:float=-INF
		for vertex:Vector2 in section:
			left=minf(left,vertex.x)
			right=maxf(right,vertex.x)
			clipped_ok=clipped_ok and vertex.y<=.00001
		projected_ok=projected_ok and absf(right-left-width)<.0001
	check(projected_ok,"rotating projected prism preserves exact full gameplay width at every tested angle")
	check(clipped_ok,"all prism faces terminate at or above ray origin, never below damage rectangle")
	check(volume.projected_section(width,0.0)!=volume.projected_section(width,.6),"real projected corners move across the shaft, not billboard UV sliding")
	var frozen_angle:float=volume.prism_angle()
	beacon._process(.5)
	check(volume.prism_angle()==frozen_angle,"wall-time rendering cannot rotate paused prism")
	check(volume.beam_material.get_shader_parameter("faceted")==true,"firing enables original tiled texture with lit facet edges")
	var old_shape:Shape2D=enemy.self_hurtbox.get_child(0).shape
	var probe:=CircleShape2D.new()
	probe.radius=.1
	enemy.self_hurtbox.get_child(0).shape=probe
	enemy.global_position=beacon.global_position+Vector2(width*.54,-80)
	wither.apply_beacon_buff("")
	var before:float=enemy.health
	beacon._damage_tick(wither)
	check(enemy.health<before,"overshoot hits at its visibly wider edge")
	beacon.firing_left=1.0
	before=enemy.health
	beacon._damage_tick(wither)
	check(enemy.health==before,"retracted beam no longer hits old wide edge")
	enemy.self_hurtbox.get_child(0).shape=old_shape
	reset_cycle()
	enemy.global_position=center+Vector2(500,-140)
	beacon.state_machine.set_physics_process(true)
	await create_timer(.72).timeout
	var live_x:float=beacon.global_position.x
	check(beacon.firing_left>0 and beacon.movement_multiplier()==.5,"real state-machine enters emission at half speed")
	await create_timer(.2).timeout
	check(beacon.global_position.x>live_x+3 and beacon.beam_end.x==beacon.beam_origin().x,"real physics keeps moving the firing beacon and attached ray")
	beacon.state_machine.set_physics_process(false)
	if DisplayServer.get_name()!="headless":
		reset_cycle()
		# This capture isolates the beacon, not the owner's unrelated targeting pose.
		wither.set_process(false)
		beacon.get_node("Health_Bar").hide()
		enemy.global_position=center+Vector2(500,-140)
		var view:=SubViewport.new()
		view.size=Vector2i(384,512)
		view.world_2d=world.get_world_2d()
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var camera:=Camera2D.new()
		camera.zoom=Vector2(6,6)
		view.add_child(camera)
		camera.make_current()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACTS))
		for i:int in range(180):
			advance(1.0/30.0)
			camera.position=beacon.global_position+Vector2(0,-25)
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(ARTIFACTS+"frame_%03d.png"%i)
		view.queue_free()
		check(true,"180 actual GPU frames cover the full 5-second beam and top ring")
	beacon.warning_left=0
	beacon.firing_left=PROFILE.FIRING-.1
	beacon._process(0)
	check(beacon._ring_front.visible,"death fixture begins with active ring")
	beacon.Die()
	check(not beacon._beam_visual.visible and not beacon._ring_front.visible and not beacon._ring_back.visible and beacon.get_ai_hazard_info().is_empty(),"death cancels all beam damage and animation")
	print("BEACON_VOLUME: %d checks / %d failures"%[checks,failures])
	print("PULSE_TIMES=",times)
	await clear_units()
	finish(0 if failures==0 else 1)
