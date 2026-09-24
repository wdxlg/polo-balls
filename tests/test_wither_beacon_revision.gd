extends "res://scripts/training/test_mc_new5.gd"
const ARTIFACTS:String = "user://wither_beacon_revision/"
func check(ok:bool,label:String) -> void:
	super.check(ok,label)
	if ok: print("PASS: "+label)
func slab(offset:Vector2,size:Vector2) -> StaticBody2D:
	var b:StaticBody2D = obstacle(offset,true)
	(b.get_child(0).shape as RectangleShape2D).size = size
	return b
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2(-200,-100))
	var enemy:Node2D = spawn("",Vector2(0,-140),"Team1")
	enemy.health = 1000
	enemy.Max_health = 1000
	enemy.block = 0
	wither.summoned = true
	wither.image.visible = true
	wither.health = 250
	wither.on_actual_health_damage_received(1.0,251.0)
	var beacon:Node2D = wither.beacon
	beacon.state_machine.set_physics_process(false)
	beacon.global_position = center+Vector2(0,-30)
	check(beacon is CharacterBody2D and beacon.is_combat_targetable() and beacon.health==180,"summoned beacon is an attackable 180HP CharacterBody")
	check(beacon.Master==wither and beacon.Team==wither.Team,"beacon retains summoner and team, not a separate selectable character")
	var floor_body:StaticBody2D = slab(Vector2(0,100),Vector2(360,12))
	await physics_frame
	beacon.step_mob(0.5)
	check(beacon.landed and beacon._activated,"swept full body lands and activates")
	check(absf(beacon.global_position.y-(center.y+94.0-beacon._body.shape.get_rect().size.y*absf(beacon._body.global_scale.y)*0.5))<0.1,"landing height matches the actual collider height, not a 20px ray")
	var grounded_y:float = beacon.global_position.y
	enemy.global_position = center+Vector2(140,-140)
	var old_x:float = beacon.global_position.x
	beacon.step_mob(0.1)
	check(beacon.global_position.x>old_x and absf(beacon.global_position.y-grounded_y)<0.1,"ground locomotion seeks enemy X only, never enemy Y")
	var wall:StaticBody2D = slab(Vector2(75,40),Vector2(8,120))
	await physics_frame
	beacon.step_mob(1.0)
	check(beacon.global_position.x<=center.x+71.1-beacon._body.shape.get_rect().size.x*absf(beacon._body.global_scale.x)*0.5,"horizontal sweep respects the entire 62px body and thin walls")
	wall.queue_free()
	floor_body.queue_free()
	await physics_frame
	beacon.step_mob(0.1)
	check(not beacon.landed and beacon.global_position.y>grounded_y+1.0,"removing support makes an already activated beacon fall again")
	check(beacon.image.visible,"an activated beacon stays a beacon while falling, not a Nether Star again")
	# Move back to the fixture floor; the next tests do not depend on falling time.
	floor_body = slab(Vector2(0,100),Vector2(360,12))
	beacon.global_position = center+Vector2(0,57)
	beacon.fall_speed = 0
	enemy.global_position = center+Vector2(0,-140)
	await physics_frame
	beacon.beam_timer = 0
	beacon.step_mob(0.016)
	check(beacon.warning_left>0 and beacon.beam_direction==Vector2.UP,"beam begins warning vertically, not toward a target vector")
	check(wither._buff.is_empty() and beacon.last_buff.is_empty(),"preparation does not grant its upcoming effect")
	var threat:Dictionary = beacon.get_ai_hazard_info(enemy)
	check(threat.start==beacon.beam_origin() and threat.end==beacon.beam_end and is_equal_approx(threat.radius,beacon.beam_width()*0.5),"declared threat uses the exact beam origin, clipped endpoint and animated width")
	check(threat.end.x==threat.start.x and threat.end.y<threat.start.y,"warning segment points straight up")
	var analyzer:Node2D = load("res://scripts/training/combat_threat_analyzer.gd").new()
	world.add_child(analyzer)
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	var warning_drawn:bool = false
	for region:Dictionary in analyzer.get_world_threats():
		if region.source_id==beacon.get_instance_id() and region.get("debug_role","")=="detection" and region.shape=="rect": warning_drawn=true
	check(warning_drawn and analyzer.visible and threat.damage==0,"actual threat display shows blue windup, not current damage")
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	check(threat.danger_in>0,"windup carries delayed danger instead of claiming current damage")
	var before:float = enemy.health
	beacon.step_mob(0.61)
	check(enemy.health==before and beacon.firing_left>0,"warning itself deals no damage")
	var launch_buff:String = beacon.last_buff
	check(beacon.BUFFS.has(launch_buff) and wither._buff==launch_buff and is_equal_approx(wither._buff_left,6.0),"the real emission immediately gives the Wither one primary effect")
	var live:MCPreviewTooltip = wither.get_node_or_null("Minecraft药水状态框") as MCPreviewTooltip
	check(live!=null and not live._potions.is_empty() and live._potions[0].icon.resource_path.ends_with("/"+launch_buff+".png"),"the effect icon appears when the beam begins, not when it ends")
	beacon.step_mob(0.5)
	analyzer._physics_process(0.1)
	var attack_drawn:bool = false
	for region:Dictionary in analyzer.get_world_threats():
		if region.get("kind","")=="wither_beacon_beam" and region.damage==6.0 and region.get("debug_role","")=="damage": attack_drawn=true
	check(attack_drawn,"actual threat display switches to active damage during emission")
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	check(is_equal_approx(before-enemy.health,30.0),"vertical beam settles five high-frequency pulses totaling 30 damage above the beacon")
	enemy.global_position = center+Vector2(130,57)
	before = enemy.health
	beacon.step_mob(0.5)
	check(enemy.health==before and beacon.beam_end.x==beacon.beam_origin().x,"side enemy cannot bend the beam or take its damage")
	beacon.step_mob(0.5)
	var buff_left_before_finish:float=wither._buff_left
	beacon.step_mob(beacon.firing_left)
	check(beacon.beams_fired==1 and beacon.last_buff==launch_buff and wither._buff==launch_buff and is_equal_approx(wither._buff_left,buff_left_before_finish),"finished emission does not give or refresh the effect again")
	check(beacon.BUFFS.has(wither._buff) and live != null and live._potions[0].icon.resource_path.ends_with("/" + wither._buff + ".png"),"the effect granted at launch remains displayed through beam completion")
	analyzer._physics_process(0.1)
	var lingering:bool = false
	for region:Dictionary in analyzer.get_world_threats():
		if region.get("kind","")=="wither_beacon_beam": lingering=true
	check(not lingering,"actual threat display clears the ended beam")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"disabling threat display immediately clears its graphics and cache")
	check(beacon.get_ai_hazard_info().is_empty(),"finished beam removes its threat immediately")
	# Roof clips rendering, damage and threat to the same endpoint.
	var roof:StaticBody2D = slab(Vector2(0,-70),Vector2(100,8))
	enemy.global_position = center+Vector2(0,-160)
	await physics_frame
	beacon.global_position = center+Vector2(0,87.4)
	beacon.fall_speed = 0.0
	before = enemy.health
	beacon._pulse_index = 0
	beacon.firing_left = beacon.PROFILE.FIRING
	beacon.tick_left = 0.5
	beacon.step_mob(0.5)
	check(absf(beacon.beam_end.y-(center.y-66.0))<0.1,"upward beam clips against underside of real terrain")
	check(enemy.health==before,"beam cannot damage an enemy beyond the clipped roof")
	roof.queue_free()
	await physics_frame
	beacon.beam_end = beacon._clipped_beam()
	beacon.clock = 0.0
	beacon._process(0)
	check(beacon._beam_visual.global_scale.is_equal_approx(Vector2.ONE) and beacon._beam_visual.to_global(Vector2(0,-beacon._beam_visual.length)).distance_to(beacon.beam_end)<0.01,"rendered ray and world-space damage endpoint agree despite character scale 0.2")
	check(beacon._beam_visual.visible and beacon._beam_visual.length>0,"active column creates the original-texture visual")
	check(beacon._beam_visual.TEXTURE.resource_path.ends_with("wither/beacon_beam.png"),"beam uses supplied vanilla Minecraft texture, not a generated substitute")
	beacon.clock = 1.0
	beacon._process(0)
	check(is_equal_approx(float(beacon._beam_visual.beam_material.get_shader_parameter("scroll")),0.2),"beam UV animation advances from simulation time")
	beacon._process(0.5)
	check(is_equal_approx(float(beacon._beam_visual.beam_material.get_shader_parameter("scroll")),0.2),"visual-only wall frames cannot advance paused beam time")
	var rig:Node3D = wither._bedrock_model
	wither.set_process(false)
	rig.animate(0,Vector2.ZERO,true,1,true,[],1)
	check(wither._bedrock_viewport.size==Vector2i(384,384) and wither.image.scale.is_equal_approx(Vector2.ONE*(0.425*5.2/4.3)),"double-resolution rig keeps the same world-space size")
	check(rig.armor_blue_material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,"armor preserves original texels rather than blurring them")
	check(rig.armor_blue_material.blend_mode==BaseMaterial3D.BLEND_MODE_ADD,"shield is a translucent energy pass, not a solid blue skin")
	check(rig.armor_white_material.albedo_texture.resource_path.ends_with("wither_armor_white.png"),"original white layer accompanies the blue energy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACTS))
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		wither._bedrock_viewport.get_texture().get_image().save_png(ARTIFACTS+"armor_0.png")
	rig.animate(1,Vector2.ZERO,true,1,true,[],1)
	check(rig.armor_blue_material.uv1_offset.is_equal_approx(Vector3(0.2,0.2,0)),"blue armor follows original diagonal UV scroll")
	check(absf(rig.armor_white_material.uv1_offset.x-fposmod(cos(deg_to_rad(22.92))*3.0,1.0))<0.0001,"white armor follows original cosine UV flow")
	check(rig.armor_bones.head1.rotation==rig.bones.head1.rotation,"energy shell tracks the same animated head bones")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		wither._bedrock_viewport.get_texture().get_image().save_png(ARTIFACTS+"armor_1.png")
		root.get_texture().get_image().save_png(ARTIFACTS+"battle.png")
	beacon.firing_left = 0
	beacon.warning_left = 0
	beacon._process(0)
	check(not beacon._beam_visual.visible,"beam visual clears at the same time as its damage threat")
	# Verify the real state-machine path, not only manually stepped fixtures.
	enemy.global_position = center+Vector2(150,-80)
	var x_before_live:float = beacon.global_position.x
	beacon.state_machine.set_physics_process(true)
	await create_timer(0.35).timeout
	check(beacon.global_position.x>x_before_live and beacon.landed,"real state-machine physics drives horizontal movement with floor support")
	var y_before_live:float = beacon.global_position.y
	floor_body.queue_free()
	await create_timer(0.2).timeout
	check(beacon.global_position.y>y_before_live+1 and not beacon.landed,"real state-machine gravity resumes after floor removal")
	beacon.state_machine.set_physics_process(false)
	wither.apply_beacon_buff("strength")
	# Do not fake figure_buffs here: ensure the actual World physics loop turns
	# the beacon's Strength into the Wither's Damage before a body-owned hit.
	await physics_frame
	await physics_frame
	var boosted_attack:float = float(wither.Damage)
	check(boosted_attack > 75.0,"live World applies beacon Strength to the Wither's attack attribute")
	var head_target_before:float = enemy.health
	wither._blast(enemy.global_position,64.0,45.0,enemy,false)
	check(is_equal_approx(head_target_before-enemy.health,boosted_attack),"real beacon Strength boosts a Wither head's direct hit exactly once")
	beacon.warning_left = 0.5
	beacon._process(0)
	check(beacon._beam_visual.visible,"death cleanup fixture begins with a visible windup beam")
	beacon.Die()
	check(wither._buff.is_empty(),"destroying beacon removes its current summoner buff")
	check(live != null and not live.visible,"destroying beacon immediately removes the Wither's effect frame")
	check(not beacon._beam_visual.visible and beacon.get_ai_hazard_info().is_empty() and beacon.get_debug_detection_regions().is_empty(),"death immediately clears beam visual, damage and windup display")
	var beacon_id:int = beacon.get_instance_id()
	beacon.queue_free()
	await process_frame
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	var dead_shape:bool = false
	for region:Dictionary in analyzer.get_world_threats():
		if region.source_id==beacon_id: dead_shape=true
	check(not dead_shape,"deleting the beacon removes all its cached threat graphics")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	print("WITHER_BEACON_REVISION: %d checks / %d failures"%[checks,failures])
	await clear_units()
	finish(0 if failures==0 else 1)
