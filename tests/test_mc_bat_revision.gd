extends "res://tests/test_mc_bat.gd"
func run() -> void:
	game = root.get_node("Game")
	BAT = load("res://scripts/characters/我的世界/bat/bat.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(60.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(20,0),"Team1")
	b.state_machine.set_physics_process(false)
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 100000
	enemy.default_properties.Max_health = 100000
	enemy.health = 100000
	await physics_frame
	await process_frame
	pause_members(b)
	b.set_process(false)
	check(totals(b) == Vector2i(150,150),"five bats now start at 30 HP each")
	check(b.initial_bat_health == 30 and BAT.split_count(150,30) == 5,"split divisor changes to 30 with initial HP")
	b.assign_vitals(200,200)
	b.set("_cooldown",0.0)
	b.begin_bite(enemy)
	check(b.feeding_guard_active(),"feeding guard begins only on a successful latch")
	var before:int = b.health
	b.take_damage(20.0,true)
	check(before-b.health == 5,"bat feeding reduces a 20-damage hit to 5")
	before = b.health
	b.receive_positional_damage(20.0,b.global_position,false,enemy)
	check(before-b.health == 5,"positional damage applies 75 percent reduction exactly once")
	before = b.health
	b.receive_spatial_damage(20.0,b.global_position,true,true)
	check(before-b.health == 5,"raw-health spatial damage also gets feeding reduction once")
	b.max_block = 100
	b.default_properties.max_block = 100
	b.block = 100
	b.take_damage(20.0)
	check(b.block == 95,"feeding reduction applies before shield consumption")
	b.block = 0
	b.Damage_reduction = 0.5
	before = b.health
	b.take_damage(40.0,true)
	check(before-b.health == 5,"feeding protection composes with existing damage reduction")
	b.Damage_reduction = 0.0
	b.detach()
	before = b.health
	b.take_damage(20.0,true)
	check(before-b.health == 20 and not b.feeding_guard_active(),"detaching removes feeding reduction immediately")
	settle_fusion(b)
	b.assign_vitals(150,300)
	check(b.attack_damage() == 13.0,"vampire 150 current HP deals 8 plus 5 damage")
	b.health = 60
	check(b.attack_damage() == 10.0,"vampire damage falls immediately with current HP")
	b.health = 300
	check(b.attack_damage() == 18.0,"vampire healing raises damage without a stale timer")
	b.health = 29
	check(b.attack_damage() == 8.0,"partial 30 HP does not round bonus upward")
	b.health = 150
	check(b.attack_damage(2.0) == 26.0,"standard attack multipliers also apply to the HP bonus")
	b.global_position = enemy.global_position+Vector2(-20,0)
	b.set("_cooldown",0.0)
	b.begin_bite(enemy)
	before = b.health
	b.take_damage(20.0,true)
	check(before-b.health == 5,"vampire also gets 75 percent feeding protection")
	check(b.image.scale == Vector2(0.6,0.6),"vampire visual width and height are halved")
	b.detach()
	b.assign_vitals(30,30)
	b.split_swarm()
	pause_members(b)
	check(b.image.scale == Vector2(0.55,0.55),"bat uses enlarged fixed scale without whole-image pulsing")
	var scale_before:Vector2 = b.image.scale
	var texture_before:Texture2D = b.image.texture
	b.advance_native_animation(0.12)
	check(b.image.texture != texture_before and b.image.scale == scale_before,"native animation changes frame pixels, not sprite size")
	check(BAT.BAT_FRAMES.get_frame_count(&"fly") == 25 and BAT.BAT_FRAMES.get_animation_speed(&"fly") == 50.0,"all 25 original Minecraft flight frames retain 20ms timing")
	var unique:Dictionary = {}
	var same_size:bool = true
	for i:int in range(25):
		var tex:Texture2D = BAT.BAT_FRAMES.get_frame_texture(&"fly",i)
		unique[hash(tex.get_image().get_data())] = true
		same_size = same_size and tex.get_size() == Vector2(128,114)
	check(unique.size() == 25 and same_size,"25 distinct full frames use identical canvas bounds")
	game.now_stop_state = true
	texture_before = b.image.texture
	b.advance_native_animation(0.12)
	check(b.image.texture == texture_before,"pause freezes the native flight animation")
	game.now_stop_state = false
	check(not b.motion_blur_enabled and not b.motion_stretch_enabled and b.AfterImage_Speed == 0.0,"both motion blur and whole-body stretch/afterimages are disabled")
	b.set("_approaching",true)
	b.move(b.Speed,0.016)
	b._set_motion_blur_values(Vector2.RIGHT,1000.0,1.0)
	check(b.get_node_or_null("Graphics/MotionBlurLayer") == null or not b.get_node("Graphics/MotionBlurLayer").visible,"even high-speed bite approach cannot show a blur layer")
	check(b.detection_range == 45.0,"detection radius is reduced from 90 to 45")
	var regions:Array = b.get_debug_detection_regions()
	check(regions.size() == 1 and regions[0].radius == 45.0 and regions[0].position == b.global_position,"declared threat circle matches actual world-space detection radius")
	var analyzer:Node = world.get_node("CombatThreatAnalyzer")
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	var found:bool = false
	for threat:Dictionary in analyzer._debug_threats:
		if threat.get("kind","") == "bat_lifesteal_detection": found = true
	check(analyzer.visible and found,"real settings switch displays bat detection in the existing analyzer")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"turning threat setting off clears the detection display")
	b.global_position = enemy.global_position+Vector2(-46,0)
	b.set("_cooldown",0.0)
	b.set("_mc_target_wait",0.0)
	b.tick_physics(0,0.016)
	check(not b._approaching and b.attached_target() == null,"enemy center outside displayed radius cannot trigger approach")
	b.global_position = enemy.global_position+Vector2(-44,0)
	b.tick_physics(0,0.016)
	check(b._approaching or b.attached_target() == enemy,"enemy center inside displayed radius triggers approach")
	finish(0 if failures == 0 else 1)
