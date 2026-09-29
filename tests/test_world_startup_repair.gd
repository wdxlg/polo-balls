extends "res://tests/test_mc_bat_transform.gd"

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(45.0,true,false,true).timeout.connect(func(): finish(2))
	# Resolve World at runtime, after Game autoload has been registered by SceneTree.
	check(world.has_method("get_combat_targetable_units_fast") and world.is_node_ready(),"real World scene loads and finishes ready")
	game._time_scale._apply_time_scale_overrides()
	check(Engine.physics_ticks_per_second==60,"normal time scale applies without the removed tick override property")
	check(Engine.max_physics_steps_per_frame<=2,"normal physics catch-up limit remains intact")
	game.request_time_scale_override("world_startup_repair",0.5,Color.TRANSPARENT)
	check(is_equal_approx(game.get_time_scale_override_factor(),0.5),"slow-motion override still applies")
	game.release_time_scale_override("world_startup_repair")
	check(is_equal_approx(game.get_time_scale_override_factor(),1.0) and Engine.physics_ticks_per_second==60,"releasing slow motion restores normal physics")
	var a:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-40,0),"Team0")
	var b:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(40,0),"Team1")
	for unit:Node2D in [a,b]:
		unit.state_machine.set_physics_process(false)
		unit.Has_Collision_Damage = false
		unit.self_hitbox.monitoring = false
	await physics_frame
	world._rebuild_battle_spatial_grid([a,b])
	check(world.get_combat_targetable_units_fast().size()==2,"grid rebuild populates targetable cache")
	world._rebuild_battle_spatial_grid([a,b])
	check(world.get_combat_targetable_units_fast().size()==2,"repeated rebuild clears old cache rather than duplicating units")
	check(world._find_nearest_enemy_spatial(a,[a,b])==b,"nearest enemy search remains valid after moving the misplaced code")
	b.remove_from_group("Ball")
	world._rebuild_battle_spatial_grid([a,b])
	check(world.get_combat_targetable_units_fast()==[a],"targetable cache excludes units that left the Ball group")
	b.add_to_group("Ball")
	world._rebuild_battle_spatial_grid([])
	check(world.get_combat_targetable_units_fast().is_empty(),"empty rebuild clears stale targetable units")
	world._armor_stand_test_hud_active = true
	world.unregister_battle_unit(b)
	await process_frame
	check(not world._battle_unit_ids.has(b.get_instance_id()),"unregister with active armor HUD completes and deferred refresh runs")
	world.register_battle_unit(b)
	print("WORLD_STARTUP_REPAIR_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
