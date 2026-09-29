extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	var ghast:Node2D=spawn("恶魂",Vector2.ZERO,"Team0")
	check(ghast.health==700,"ghast retains 700 HP")
	var shot:Node2D=ghast.fire_at(center+Vector2(300,0))
	shot.state_machine.set_physics_process(false)
	check(shot.neutral and shot.Team.is_empty() and shot.Master==null,"neutral and unowned from launch")
	check(not shot.reflected,"neutral allegiance independent of reflection physics")
	shot.step_mob(0.016)
	check(not shot.exploded,"outward muzzle sweep does not collide with caster")
	var speed:float=shot.flight_velocity.length()
	shot.receive_positional_damage(5.0,shot.global_position+Vector2(10,0))
	check(shot.neutral and not shot.reflected and shot.flight_velocity.length()<speed,"light hit retains prior braking while remaining neutral")
	shot.queue_free()
	await process_frame
	var ally:Node2D=spawn("",Vector2(30,0),"Team0")
	var enemy:Node2D=spawn("",Vector2(30,20),"Team1")
	for target:Node in [ghast,ally,enemy]:
		target.health=1000
		target.block=0
		target.Damage_reduction=0
	shot=ghast.fire_at(center+Vector2(300,0))
	shot.state_machine.set_physics_process(false)
	shot.global_position=center+Vector2(20,0)
	shot.explode()
	check(ghast.health<1000,"fresh unreflected explosion hurts its caster")
	check(ally.health<1000,"fresh explosion hurts teammate with team damage disabled")
	check(enemy.health<1000,"fresh explosion still hurts enemy")
	await process_frame
	ally.global_position=center+Vector2(350,250)
	enemy.global_position=center+Vector2(350,300)
	shot=ghast.fire_at(center+Vector2(300,0))
	shot.state_machine.set_physics_process(false)
	shot.step_mob(0.016)
	shot.receive_positional_damage(100.0,shot.global_position+Vector2(10,0))
	check(shot.neutral and shot.reflected and shot.flight_velocity.x<0,"reflected fireball stays neutral")
	var hp:float=ghast.health
	shot.step_mob(0.4)
	check(shot.exploded and ghast.health<hp,"returning fireball can collide with and damage caster")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
