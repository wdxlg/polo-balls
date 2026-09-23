extends "res://tests/test_copper_sword.gd"
## Autonomous state-machine integration, not manual begin_swing()/step_mob() calls.
func total_hp(targets:Array[Node2D]) -> float:
	var result:float = 0.0
	for unit:Node2D in targets: result += unit.health
	return result
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"live-test preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.Speed = 0.0
	unit.default_properties.Speed = 0.0
	unit.rust_duration = 2.0
	unit.charged_duration = 0.8
	unit.lightning_warning = 0.1
	var enemies:Array[Node2D] = []
	# Only a rear enemy: AI must acquire it and turn before it can hit anything.
	enemies.append(dummy(center+Vector2(-30,0)))
	await physics_frame
	await process_frame
	var hp:float = total_hp(enemies)
	unit.set_process(true)
	unit.state_machine.set_physics_process(true)
	await create_timer(1.5).timeout
	check(unit.clock>1.0 and total_hp(enemies)<hp and unit.lightning_count==0,"normal engine ticks autonomously turn and attack a rear enemy before the first rust strike")
	check(unit.combo_hits>=2 and unit.current_swing_duration()<unit.base_swing_duration,"live consecutive melee hits accelerate without test-side attack calls")
	var before_rust:float = unit.rust
	var before_clock:float = unit.clock
	hp = total_hp(enemies)
	game.now_stop_state = true
	await create_timer(0.2,true,false,true).timeout
	check(unit.rust==before_rust and unit.clock==before_clock and total_hp(enemies)==hp,"live pause freezes simulation and damage")
	game.now_stop_state = false
	await create_timer(1.8).timeout
	check(unit.cleanse_count==1 and unit.lightning_count>1,"live full oxidation cleanses and subsequent charged attacks summon extra lightning")
	check(unit.charged_left==0.0 and not unit.charge_visual.visible,"live charge duration ends and hides the shared trident effect")
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	before_rust = unit.rust
	var old_bolts:int = unit.lightning_count
	await create_timer(0.5).timeout
	check(unit.rust==before_rust and unit.lightning_count==old_bolts,"live Can_Skill gate blocks passive rust and new lightning")
	print("COPPER_SWORD_LIVE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
