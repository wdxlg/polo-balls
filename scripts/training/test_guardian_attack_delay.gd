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
	var guardian:Node2D=spawn("守卫者",Vector2.ZERO,"Team0")
	var target:Node2D=spawn("",Vector2(180,0),"Team1")
	target.health=10000
	guardian.step_mob(0.01)
	guardian._tick_left=0.8
	var effect:Node=guardian.apply_knockback(Vector2.LEFT,40.0,200.0)
	check(effect!=null and guardian.dizziness,"normal knockback retains movement control lock")
	check(guardian.can_act(),"motion lock alone does not disable guardian attack")
	check(is_equal_approx(guardian._laser_delay_left,0.76),"forty unit knockback adds 760 ms")
	guardian.step_mob(0.04)
	check(guardian.locked==target and guardian.beam_active,"knockback keeps laser target and beam")
	check(is_equal_approx(guardian._tick_left,0.8),"knockback delays rather than resets charge")
	guardian.step_mob(0.80)
	check(is_equal_approx(guardian._tick_left,0.72),"charge resumes after only its small delay, even while moving")
	guardian._laser_delay_left=0.0
	guardian._laser_delay_total=0.0
	guardian.block=0
	guardian.Damage_reduction=0
	var hp:float=guardian.health
	guardian.receive_positional_damage(10.0,target.global_position,false,target)
	check(guardian.health<hp and guardian._laser_delay_left>0.0,"actual health damage schedules attack delay")
	check(guardian._laser_delay_left<guardian.knockback_attack_delay(1.0),"hurt delay smaller than even light knockback")
	check(is_equal_approx(guardian.hurt_attack_delay(10.0),0.088),"ten damage now delays laser by 88 ms")
	check(is_equal_approx(guardian.knockback_attack_delay(1000.0),1.76),"single knockback delay capped at 1.76 seconds")
	check(is_equal_approx(guardian.hurt_attack_delay(1000.0),0.24),"single hurt delay capped at 240 ms")
	check(guardian.knockback_attack_delay(20.0)<guardian.knockback_attack_delay(80.0),"larger knockback adds more delay")
	guardian.spike_charging=true
	guardian.spike_phase=1
	guardian._spike_charge=0.15
	guardian.add_attack_delay(0.08)
	target.global_position=center+Vector2(25,0)
	guardian.step_spikes(0.04)
	check(is_equal_approx(guardian._spike_charge,0.15) and guardian.spike_charging,"spike windup retains its progress during delay")
	for i:int in range(100): guardian.add_attack_delay(0.2)
	check(guardian._laser_delay_total<=3.60001 and guardian._spike_delay_total<=0.12001,"repeated hits have bounded per-charge delay")
	guardian.step_mob(4.0)
	check(guardian._laser_delay_left==0.0,"delay budget eventually drains")
	var data:Dictionary=guardian.visual_state()
	check(data.has("laser_delay") and data.has("spike_delay"),"client visual state carries both delays")
	# Generic controller queues a stun behind ongoing motion; finish that motion first.
	effect._finish(false)
	guardian.apply_stun(0.3)
	check(not guardian.can_act(),"explicit stun still disables attack")
	guardian.step_mob(0.01)
	check(guardian.locked==null and not guardian.spike_charging,"explicit stun remains a real interruption")
	await clear_units()
	guardian=spawn("守卫者",Vector2.ZERO,"Team0")
	target=spawn("",Vector2(180,0),"Team1")
	guardian.step_mob(0.01)
	guardian.apply_knockback(Vector2.LEFT,15.0,150.0)
	target.global_position=center+Vector2(400,0)
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"knockback cannot retain an out-of-range target")
	await clear_units()
	var creeper:Node2D=spawn("苦力怕",Vector2.ZERO,"Team0")
	target=spawn("",Vector2(25,0),"Team1")
	creeper._charged=false
	creeper._begin_fuse(target)
	check(is_equal_approx(creeper._current_fuse_duration,2.5),"normal creeper fuse now 2.50 seconds")
	creeper._cancel_fuse()
	creeper._charged=true
	creeper._begin_fuse(target)
	check(is_equal_approx(creeper._current_fuse_duration,1.95),"charged creeper fuse now 1.95 seconds")
	creeper._cancel_fuse()
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
