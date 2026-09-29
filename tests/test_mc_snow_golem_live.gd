extends "res://tests/test_mc_snow_golem.gd"
## Real timers/state-machine firing: no injected construction or projectile callbacks.
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(25,true,false,true).timeout.connect(func():finish(2))
	var shooter:Node2D = spawn(GOLEM_PATH,center)
	shooter.burst_probability = 0.0
	shooter.Speed = 0.0
	shooter.default_properties.Speed = 0.0
	var target:Node2D = dummy(center+Vector2(120,0))
	target.Speed = 0.0
	target.default_properties.Speed = 0.0
	var field:Node2D = shooter._field
	field.set_physics_process(false)
	shooter.state_machine.set_physics_process(true)
	await create_timer(0.25).timeout
	check(shooter.has_pumpkin and shooter.shots_fired==0,"live actor respects its original initial attack cooldown")
	shooter.take_damage(ceilf(shooter.Max_health*0.5),true)
	check(not shooter.has_pumpkin and shooter.head_break_count==1 and shooter.force_next_burst,"real live health loss breaks the pumpkin and arms the next attack")
	var saw_volley:bool = false
	var maximum_remaining:int = 0
	var deadline:int = Time.get_ticks_msec()+5500
	while Time.get_ticks_msec()<deadline and shooter.shots_fired<20:
		saw_volley = saw_volley or shooter._burst_remaining>0
		maximum_remaining = maxi(maximum_remaining,shooter._burst_remaining)
		await process_frame
	check(shooter.shots_fired==20 and shooter.bursts_started==1 and saw_volley,"ordinary live state machine emits the guaranteed twenty-shot volley")
	check(maximum_remaining>=15 and shooter._burst_remaining==0,"live volley releases over time rather than creating twenty at once")
	check(target.health<target.Max_health and target.has_node("MCSnowCold"),"live snowballs actually hit and add the original cold state")
	check(get_nodes_in_group("MCSnowGolem").size()==1 and not field.has_method("_spawn_mini"),"live half-health and snow activity never creates a mini")
	shooter.state_machine.set_physics_process(false)
	shooter._shot_left = 0.0
	shooter.force_next_burst = true
	check(shooter.fire_at(target.global_position,target),"live pause probe starts another committed attack")
	var count:int = shooter.shots_fired
	var left:float = shooter._burst_wait
	shooter.state_machine.set_physics_process(true)
	game.now_stop_state = true
	await create_timer(0.2,true,false,true).timeout
	check(shooter.shots_fired==count and shooter._burst_wait==left,"real frame/timer pause freezes scheduled releases")
	game.now_stop_state = false
	shooter.state_machine.set_physics_process(false)
	shooter._cancel_burst()
	print("SNOW_LIVE_RESULT checks=",checks," failures=",failures," shots=",shooter.shots_fired)
	await finish(0 if failures==0 else 1)
