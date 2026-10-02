extends "res://tests/test_sulfur_cube_balance.gd"
## Regression of the extracted pre-existing copy ability and normal shared shaders/stats.
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():print("HAOCHEN_REUSE_TIMEOUT");quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	var stopped:bool=game.now_stop_state
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Ball_Can_Move=true
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world.set_process(false);world.set_physics_process(false)
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var dice:Node2D=load("res://scenes/characters/人物/掷骰子的人.tscn").instantiate()
	dice.name="SharedCopyDice";dice.Team="Team0";dice.position=center
	dice.set_meta("battle_setup_id",9900)
	world.add_child(dice)
	dice.state_machine.set_physics_process(false);dice.set_physics_process(false)
	var enemy:Node2D=fighter("OriginalDiceTarget",center+Vector2(25,0))
	enemy.Max_health=600;enemy.health=270;enemy.Damage=90;enemy.Speed=144.0
	enemy.Attack_Cooling=1.8;enemy.Skill_Cooling=6.0;enemy.max_block=30;enemy.block=12;enemy.max_energy=90;enemy.energy=60
	enemy.Health_Restore=9;enemy.Damage_reduction=0.6
	for key:String in enemy.default_properties:enemy.default_properties[key]=enemy.get(key)
	dice._clone_nearest_enemy_as_ally()
	var copy:Node2D
	for raw:Variant in get_nodes_in_group("Ball"):
		if is_instance_valid(raw) and raw!=dice and bool(raw.get_meta("dice_enemy_copy",false)):copy=raw;break
	check(is_instance_valid(copy),"existing Dice enemy-copy ability still creates a real original scene")
	if is_instance_valid(copy):
		copy.state_machine.set_physics_process(false);copy.set_physics_process(false)
		check(copy.Max_health==200 and copy.health==90 and copy.Damage==30,"Dice keeps its third maximum/current health and damage rules")
		check(copy.Speed==144.0 and is_equal_approx(copy.Attack_Cooling,0.6) and is_equal_approx(copy.Skill_Cooling,2.0),"Dice retains its own cooldown scaling and unchanged speed")
		check(copy.max_block==10 and copy.block==4 and copy.max_energy==30 and copy.energy==20,"Dice retains current shield/energy as well as their scaled capacities")
		check(copy.Health_Restore==3 and is_equal_approx(copy.Damage_reduction,0.2),"other Dice combat attributes still scale by one third")
		check(copy.Master==dice and copy.Master_name==str(dice.name) and copy.Team==dice.Team,"Dice retains real owner/team rather than Haochen-specific ownership")
		check(copy.has_meta("battle_setup_id") and int(copy.get_meta("battle_setup_id"))==9900,"existing Dice legacy identity metadata is preserved before spawn")
		check(not copy.character_copy_profile.monochrome,"Dice does not inherit the new monochrome option by default")
		copy.restore_default_runtime_properties_fast()
		check(copy.Damage==30 and copy.Max_health==200,"shared runtime property restoration preserves the copied defaults")
	var ordinary:Node2D=fighter("UnaffectedOrdinary",center+Vector2(-35,0))
	check(ordinary.character_copy_profile.is_empty() and not ordinary._copy_monochrome_inherited,"ordinary characters are not turned into copies by a default property")
	var previous:float=ordinary.Damage
	ordinary.restore_default_runtime_properties_fast()
	check(ordinary.Damage==previous,"ordinary per-frame stats are unchanged by the opt-in profile")
	var creeper:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate()
	creeper.Team="Team0";creeper.position=center+Vector2(0,40)
	world.add_child(creeper);creeper.state_machine.set_physics_process(false);creeper.set_physics_process(false)
	check(creeper.FUSE_BAR_RECT==Rect2(-55,92,110,16),"Creeper's exact established bar geometry remains unchanged")
	check(creeper.FUSE_BAR_START_COLOR==creeper.SHARED_BAR.START_COLOR and creeper.FUSE_BAR_END_COLOR==creeper.SHARED_BAR.END_COLOR,"Creeper and other callers share the same palette instead of parallel approximations")
	check(creeper.fuse_duration==2.5 and creeper.fuse_start_radius==50.0,"extracting the painter does not change Creeper fuse timing or detection radius")
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved;game.now_stop_state=stopped
	print("HAOCHEN_REUSE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
