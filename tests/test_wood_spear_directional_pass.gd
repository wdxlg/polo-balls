extends SceneTree
var failures:int = 0
var checks:int = 0
var spear:Node2D
var target:Node2D
var world:Node
var saved:Dictionary
var saved_stop:bool
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func approx(a:float,b:float) -> bool: return absf(a-b)<0.01
func reset_speed(value:float = 420.0) -> void:
	spear._cancel_penetration_speed()
	spear._cleanup_attack()
	spear._cleanup_pass(false)
	spear._reset_speed_to_base()
	spear._base_move_speed = 90.0
	spear.max_move_speed = 420.0
	spear._current_move_speed = value
	spear.Speed = value
	spear.direction = Vector2.RIGHT
	spear._set_facing_direction(Vector2.RIGHT)
	spear.dizziness = false
func run() -> void:
	var game:Node = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	await create_timer(0.25).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	spear = load("res://scenes/characters/我的世界/木矛.tscn").instantiate()
	spear.Team = "Team0"
	world.add_child(spear)
	spear.global_position = center
	spear.state_machine.set_physics_process(false)
	spear.set_physics_process(false)
	target = load("res://scenes/ball.tscn").instantiate()
	target.Team = "Team1"
	world.add_child(target)
	# 固定小受击框，避免默认ball的大受击框让侧面15px也属于直线路径。
	for child:Node in target.self_hurtbox.get_children():
		if child is CollisionShape2D:
			var circle := CircleShape2D.new()
			circle.radius = 10.0
			child.shape = circle
	target.state_machine.set_physics_process(false)
	target.set_physics_process(false)
	target.global_position = center+Vector2(20,0)
	reset_speed()
	spear._begin_penetration_speed(false)
	check(approx(spear.Speed,512.4),"active burst 420 -> 512.4 above cap")
	spear._begin_penetration_speed(false)
	check(approx(spear.Speed,512.4),"repeated trigger cannot stack burst")
	spear._end_penetration_speed(true,false)
	check(spear._speed_recovery_active and approx(spear.Speed,512.4),"active loss starts smoothly, no instant drop")
	spear._tick_speed_recovery(0.325)
	check(spear.Speed>255.0 and spear.Speed<512.4,"active smooth intermediate speed")
	spear._tick_speed_recovery(0.325)
	check(approx(spear.Speed,255.0),"active retains 50 percent of 330 accumulated speed")
	spear._tick_speed_recovery(2.0)
	check(approx(spear.Speed,255.0),"no second decay to base")
	reset_speed()
	spear._begin_penetration_speed(true)
	check(approx(spear.Speed,567.0),"passive burst stronger: 420 -> 567")
	spear._end_penetration_speed(true,true)
	spear._tick_speed_recovery(0.65)
	check(approx(spear.Speed,172.5),"passive retains 25 percent accumulated, temporary boost excluded")
	spear._end_penetration_speed(true,true)
	spear._tick_speed_recovery(1.0)
	check(approx(spear.Speed,172.5),"cleanup cannot charge loss twice")
	reset_speed()
	spear._begin_penetration_speed(true)
	spear._tick_thrust_boost(0.22)
	check(approx(spear.Speed,420.0),"burst expires without leaving permanent overspeed")
	spear._end_penetration_speed(true,true)
	spear._tick_speed_recovery(0.65)
	check(approx(spear.Speed,172.5),"late pass still pays correct stored accumulation")
	reset_speed()
	spear._begin_penetration_speed(false)
	spear._end_penetration_speed(false,false)
	check(approx(spear.Speed,420.0) and not spear._speed_recovery_active,"miss removes burst without charging hit loss")
	reset_speed()
	target.global_position = spear._spear_tip_world_position()+Vector2(15,0)
	check(spear._path_can_hit_target(target,Vector2.RIGHT),"original forward path hits target")
	spear._attack_direction = Vector2.RIGHT
	spear._attack_needed_turn = false
	check(int(spear._active_thrust_pass_trigger_for_target(target)) == 2,"inside red circle still passive when original path hits")
	spear._attack_needed_turn = true
	check(int(spear._active_thrust_pass_trigger_for_target(target)) == 1,"turned attack remains active after facing target")
	spear._attack_pass_through = true
	spear._attack_pass_trigger = 2
	check(approx(spear._penetration_damage_multiplier(),2.0),"FORWARD_PATH within Attack is double damage")
	spear._attack_pass_trigger = 1
	check(approx(spear._penetration_damage_multiplier(),1.0),"turned penetration is normal damage")
	spear._attack_needed_turn = false
	spear._attack_target = target
	target.global_position = spear.global_position+Vector2(0,30)
	var original:Vector2 = spear._attack_direction
	spear._update_attack_direction_tracking(0.1)
	check(spear._attack_direction.is_equal_approx(original),"passive does not steer to follow moving target")
	spear._attack_pass_hit = false
	spear._attack_turn_active = false
	target.global_position = spear.global_position-Vector2(100,0)
	check(spear._attack_has_missed_target(),"fully passed target ends empty chase")
	spear._attack_turn_active = true
	check(not spear._attack_has_missed_target(),"turning stage is not falsely canceled")
	reset_speed(70.0)
	spear._schedule_low_speed_recovery()
	spear._tick_low_speed_recovery(0.10)
	var wait:float = spear._low_speed_recovery_wait
	spear._apply_knockback_momentum_response(Vector2.LEFT,20.0)
	check(approx(spear._low_speed_recovery_wait,wait),"weak hit does not reset recovery wait")
	spear._tick_low_speed_recovery(0.2)
	spear._tick_low_speed_recovery(0.02)
	spear._apply_knockback_momentum_response(Vector2.LEFT,20.0)
	check(spear._low_speed_recovery_active and approx(spear._low_speed_recovery_wait,0.0),"weak hit does not interrupt active recovery")
	spear._apply_knockback_momentum_response(Vector2.LEFT,200.0)
	check(not spear._low_speed_recovery_active and approx(spear._low_speed_recovery_wait,0.22),"strong hit restarts wait and control")
	reset_speed()
	spear._begin_penetration_speed(true)
	spear._apply_knockback_momentum_response(Vector2.LEFT,20.0)
	var after_hit:float = spear.Speed
	spear._tick_thrust_boost(0.5)
	check(approx(spear.Speed,after_hit) and not spear._penetration_budget_active,"knockback cannot be undone by stale burst")
	spear._reset_speed_to_base()
	check(approx(spear.Speed,90.0) and not spear._thrust_boost_active,"stun reset clears burst and returns base")
	reset_speed()
	target.global_position = spear.global_position+Vector2(20,0)
	var forward_score:float = spear._attack_target_score(target,20.0,6.0)
	target.global_position = spear.global_position+Vector2(0,20)
	var side_score:float = spear._attack_target_score(target,20.0,6.0)
	check(forward_score<side_score,"equal-distance candidate favors forward at speed")
	reset_speed()
	target.Max_health = 10000
	target.health = 10000
	target.velocity = Vector2.ZERO
	target.global_position = spear._spear_tip_world_position()+Vector2(15,0)
	spear.Attack()
	check(spear._attack_active and not spear._attack_needed_turn and int(spear._attack_pass_trigger)==2 and approx(spear.Speed,567.0),"real Attack entry classifies forward as passive and bursts once")
	var before_hp:float = target.health
	var expected:float = spear._resolved_damage_against(target,2.0)
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(absf((before_hp-target.health)-expected)<1.01,"real forward Attack hit delivers double positional damage")
	var after_hp:float = target.health
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(approx(target.health,after_hp),"same pass cannot damage target twice")
	spear._finish_attack_pass()
	spear._tick_speed_recovery(0.65)
	check(approx(spear.Speed,172.5),"real forward Attack completion pays passive 75 percent loss")
	reset_speed()
	target.global_position = spear._spear_tip_world_position()+Vector2(0,15)
	spear.Attack()
	check(spear._attack_active and spear._attack_needed_turn and int(spear._attack_pass_trigger)==1 and approx(spear.Speed,512.4),"real turning Attack entry stays active and uses smaller burst")
	before_hp = target.health
	expected = spear._resolved_damage_against(target,1.0)
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(absf((before_hp-target.health)-expected)<1.01,"real turning hit delivers normal positional damage")
	spear._finish_attack_pass()
	spear._tick_speed_recovery(0.65)
	check(approx(spear.Speed,255.0),"real turning Attack completion pays active 50 percent loss")
	# 非穿刺：转向普通刺/顺向普通刺/自然接触分别验证命中奖励。
	reset_speed(200.0)
	target.global_position = spear._spear_tip_world_position()+Vector2(0,15)
	spear.Attack()
	var pre_normal:float = spear.Speed
	check(spear._attack_needed_turn and not spear._attack_pass_through,"ordinary turned attack stays non-penetrating")
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(approx(spear.Speed,pre_normal+8.0) and not spear._attack_active,"ordinary turned hit gains 8, retreat no longer removes speed")
	reset_speed(200.0)
	target.global_position = spear._spear_tip_world_position()+Vector2(15,0)
	spear.Attack()
	pre_normal = spear.Speed
	check(not spear._attack_needed_turn and not spear._attack_pass_through,"ordinary straight Attack stays non-penetrating")
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(approx(spear.Speed,pre_normal+14.0),"ordinary straight hit gains 14 even within Attack")
	reset_speed(200.0)
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(approx(spear.Speed,214.0) and not spear._pass_active,"natural low-speed contact gains 14 without starting penetration")
	reset_speed(418.0)
	spear._apply_normal_hit_speed_gain(true)
	check(approx(spear.Speed,420.0),"normal hit gain respects daily cap")
	reset_speed(90.0)
	spear._last_obstacle_slowdown_msec = -1000000
	spear._apply_obstacle_speed_loss()
	check(approx(spear.Speed,90.0),"obstacle does not reduce base speed")
	reset_speed(60.0)
	spear._last_obstacle_slowdown_msec = -1000000
	spear._apply_obstacle_speed_loss()
	check(approx(spear.Speed,60.0),"obstacle does not restore or reduce already slowed speed")
	reset_speed(420.0)
	spear._last_obstacle_slowdown_msec = -1000000
	spear._apply_obstacle_speed_loss()
	check(approx(spear.Speed,403.5),"obstacle removes only 5 percent accumulation")
	spear._apply_obstacle_speed_loss()
	check(approx(spear.Speed,403.5),"same instant repeated wall callbacks do not stack loss")
	reset_speed(420.0)
	spear._begin_penetration_speed(false)
	spear._end_penetration_speed(true,false)
	spear._tick_speed_recovery(0.325)
	spear._apply_normal_hit_speed_gain(true)
	spear._tick_speed_recovery(0.325)
	check(approx(spear.Speed,269.0),"normal gain during recovery preserves original 50 percent loss plus reward")
	reset_speed(420.0)
	spear._begin_penetration_speed(false)
	spear._end_penetration_speed(true,false)
	spear._last_obstacle_slowdown_msec = -1000000
	spear._apply_obstacle_speed_loss()
	spear._tick_speed_recovery(0.65)
	check(approx(spear.Speed,246.75),"obstacle loss is not undone by penetration recovery")
	reset_speed()
	target.global_position = spear._spear_tip_world_position()+Vector2(15,0)
	before_hp = target.health
	expected = spear._resolved_damage_against(target,2.0)
	spear._on_hitbox_on_hit(target.self_hurtbox)
	check(spear._pass_active and spear._pass_hit and approx(spear.Speed,567.0) and absf((before_hp-target.health)-expected)<1.01,"natural passive entry shares burst and double damage")
	spear.Attack()
	check(not spear._attack_active and spear._pass_active,"Attack cannot overlap ongoing natural penetration")
	target.free()
	spear._tick_pass_completion(0.016)
	spear._tick_speed_recovery(0.65)
	check(not spear._pass_active and approx(spear.Speed,172.5),"destroyed target still settles passive loss without invalid access")
	reset_speed(420.0)
	spear.global_position = center
	spear._last_obstacle_slowdown_msec = -1000000
	var wall := StaticBody2D.new()
	wall.collision_layer = spear.collision_mask
	var wall_shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(4,60)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(40,0)
	await physics_frame
	var collision:KinematicCollision2D = spear.move_and_collide(Vector2(60,0))
	check(collision != null and collision.get_collider() == wall,"actual movement collides with test obstacle")
	if collision != null:
		spear.when_collide(420.0,collision)
		check(approx(spear.Speed,403.5),"actual obstacle callback applies 5 percent accumulated loss")
	wall.queue_free()
	# 碰撞会生成deferred特效；释放测试场景并排空两帧，避免进程退出时残留。
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SPEAR_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
