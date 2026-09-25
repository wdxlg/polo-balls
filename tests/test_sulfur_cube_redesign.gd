extends SceneTree
## Scoped live-World regression for the six-mode redesign; does not mutate legacy fixtures.
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func run() -> void:
	create_timer(30.0,true,false,true).timeout.connect(func(): print("SULFUR_REDRAW_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	var script:Script = load("res://scripts/characters/我的世界/硫方怪.gd")
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var cube:Node2D = load("res://scenes/characters/我的世界/硫方怪.tscn").instantiate()
	cube.Team = "Team0"
	cube.position = center
	world.add_child(cube,true)
	cube.state_machine.set_physics_process(false)
	cube.set_physics_process(false)
	cube.health = cube.Max_health
	var enemy:Node2D = load("res://scenes/ball.tscn").instantiate()
	enemy.Team = "Team1"
	enemy.position = center+Vector2(16,0)
	world.add_child(enemy,true)
	enemy.state_machine.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.Max_health = 2000
	enemy.default_properties.Max_health = 2000
	enemy.health = 2000
	await physics_frame
	check(cube.Max_health == 500 and cube.Damage == 48,"500 HP with stronger base attack")
	check(script.Block.size() == 7 and not script.Block.has("WOOD"),"only six live blocks plus empty; wood removed")
	var outcomes:Dictionary = {}
	for i:int in range(200):
		var pick:int = cube.next_block()
		check(pick >= script.Block.ICE and pick <= script.Block.AMETHYST and pick != cube.block_mode,"random pick is valid and never current") if i == 0 else null
		outcomes[pick] = true
	check(outcomes.size() == 6,"all six blocks are reachable via random roll")
	cube.set_block(script.Block.ICE)
	cube._actual_speed = cube._ice_reference_speed
	var slow_hit:float = cube._mode_damage()
	cube._actual_speed = cube._ice_reference_speed*1.8
	check(slow_hit < 25.0 and cube._mode_damage() > 70.0,"ice contact increases with actual movement speed instead of fixed damage")
	outcomes.clear()
	for i:int in range(200): outcomes[cube.next_block()] = true
	check(outcomes.size() == 5 and not outcomes.has(script.Block.ICE),"switch randomizes among the other five, not fixed sequence")
	cube._leave_ice(center,center+Vector2(25,0))
	check(get_nodes_in_group("MCSulfurIceTrail").size() >= 2,"blue ice leaves square world-grid tiles along path")
	var trail:Node2D = get_nodes_in_group("MCSulfurIceTrail")[0] as Node2D
	trail.age = 2.3
	trail._physics_process(0.1)
	check(trail._crack.visible and trail._crack.texture != null,"original crack texture appears before ice breaks")
	trail.age = 3.99
	trail._physics_process(0.02)
	check(trail.is_queued_for_deletion(),"ice expires and invokes shared block fragmentation")
	cube.set_block(script.Block.MAGMA)
	check(cube.get_fire_effect_ratio() == 0.0 and not cube.can_receive_fire_status(),"magma is immune through common fire protocol")
	enemy.global_position = center+Vector2(0,-7)
	var before:float = enemy.health
	cube._pulse_contact()
	check(enemy.health < before and cube.get_ai_attack_threats(enemy).size() == 2,"magma top and touch both have real damage regions")
	var burn:Node = enemy.get_node_or_null("MinecraftBlazeBurn")
	check(is_instance_valid(burn) and burn.get_script().resource_path.ends_with("mc_shared_burn_status.gd"),"magma applies the shared Blaze burn status")
	if is_instance_valid(burn):
		cube.Damage = 300
		burn.refresh(cube,2.4,cube.attack_damage(0.21))
		burn._tick_left = 0.01
		before = enemy.health
		var crit_before:int = 0
		for sound:Node in get_nodes_in_group("MCNativeSFX"):
			if sound.get_meta("mc_sulfur_event","") == &"entity.player.attack.crit": crit_before += 1
		burn._physics_process(0.05)
		var crit_after:int = 0
		for sound:Node in get_nodes_in_group("MCNativeSFX"):
			if sound.get_meta("mc_sulfur_event","") == &"entity.player.attack.crit": crit_after += 1
		check(enemy.health < before and crit_after == crit_before+1,"effective burn tick over 50 emits one native Minecraft critical hit")
		cube.Damage = 48
	cube.set_block(script.Block.HONEY)
	check(cube.can_receive_fire_status(),"fire immunity ends immediately on changing away from magma")
	enemy.global_position = center+Vector2(12,0)
	enemy.Repel = Vector2(250,0)
	cube._pull_touching_enemies(0.10)
	check(enemy.Repel.x < 250 and enemy.Repel.x > 0,"honey cancels part of outward velocity but allows a fast enemy to escape")
	cube.set_block(script.Block.IRON)
	check(cube.get_ai_attack_threats(enemy).is_empty(),"iron body has no full-body damage before single slam")
	cube._slam_time = 0.5
	enemy.global_position = center+Vector2(0,10)
	before = enemy.health
	cube._iron_bottom_contacts()
	check(enemy.health < before and cube.get_ai_attack_threats(enemy).size() == 1,"iron damages only its bottom during one descent")
	cube._slam_time = -1.0
	var original_mask:int = cube.collision_mask
	cube._start_single_slam()
	check(cube._slam_time >= 0.0 and cube.collision_mask != original_mask,"iron jump temporarily ignores character bodies but not terrain")
	for i:int in range(9): cube._step_single_slam(0.10)
	check(cube._slam_time < 0.0 and cube.collision_mask == original_mask,"one slam finishes without combo and restores body collision")
	cube.set_block(script.Block.AMETHYST)
	check(cube._native_model.crystal_layer.get_child_count() == 4 and cube.get_ai_attack_threats(enemy).size() == 4,"original-texture live 3D crystals have four separate hit regions")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image:Image = cube._model_viewport.get_texture().get_image()
		var opaque:int = 0
		var purple:int = 0
		for y:int in range(image.get_height()):
			for x:int in range(image.get_width()):
				var pixel:Color = image.get_pixel(x,y)
				if pixel.a > 0.2:
					opaque += 1
					if pixel.b > pixel.r*1.08 and pixel.b > pixel.g*1.06: purple += 1
		check(opaque > 1500 and purple > 25,"real GPU renders the translucent 3D shell plus visible purple crystals")
		print("SULFUR_AMETHYST_GPU_PNG_B64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
	cube._fire_all_crystals()
	check(get_nodes_in_group("AI_Hazard").size() >= 4,"all four amethyst shards fire along their current directions")
	cube.crystals_out = true
	check(cube.get_ai_attack_threats(enemy).is_empty() and not cube._native_model.crystal_layer.visible,"fired crystals disappear from body and no longer hit")
	cube.crystals_out = false
	cube.set_block(script.Block.TNT)
	check(cube.fuse_left > 0.0 and cube.block_mode == script.Block.TNT,"TNT primes as soon as it is inserted")
	cube.Skill()
	check(cube.block_mode == script.Block.TNT,"primed TNT cannot be skipped to avoid self damage")
	cube.fuse_left = 0.0
	var self_before:float = cube.health
	cube._last_move_direction = Vector2.RIGHT
	cube._detonate()
	check(cube.health < self_before and cube.health > 0,"TNT explosion damages its own living caster")
	check(cube.block_mode != script.Block.TNT and cube.block_mode != script.Block.EMPTY and cube._recoil_velocity.length() > 100.0,"TNT immediately randomizes a non-TNT block and recoils")
	check(get_nodes_in_group("MCExplosion").size() >= 1,"TNT uses the shared reusable Minecraft explosion effect")
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SULFUR_REDRAW: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
