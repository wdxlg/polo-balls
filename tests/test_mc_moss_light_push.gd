extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2=await setup_world()
	create_timer(45.0).timeout.connect(func():finish(2))
	var moss:Node=actor("苔藓",center)
	var point:Vector2=Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position=point
	var victim:Node=dummy(point)
	await physics_frame
	moss.plant(point)
	var hp:float=victim.health
	check(moss.begin_burrow(),"burrow still starts on connected moss")
	moss.burrow_left=0.0
	check(moss.finish_burrow(),"burrow still resolves at exit")
	check(hp-victim.health==60.0,"emergence retains sixty base damage")
	var knock:Node=null
	for child:Node in victim.get_children():
		if child.get_script()==victim.KNOCKBACK_EFFECT_SCRIPT: knock=child
	check(is_instance_valid(knock),"real emergence hit creates knockback controller")
	if is_instance_valid(knock):
		check(knock.distance==18.0,"emergence only pushes eighteen pixels instead of ninety")
		check(knock.speed==180.0,"emergence uses gentle push speed instead of seven hundred")
		check(knock.stun_duration==0.0 and knock.collision_damage==0.0,"small push adds no stun or collision damage")
	check(moss.burrow_radius==42.0 and moss.burrow_cooldown==5.0,"range and cooldown remain unchanged")
	print("MOSS_LIGHT_PUSH checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
