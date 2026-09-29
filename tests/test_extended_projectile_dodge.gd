extends "res://tests/test_mc_frontier.gd"
var ender:Node
var origin:Vector2
func reset_ender() -> void:
	ender.global_position=origin
	ender._dodge_grace=0.0
	ender.last_dodge_kind=""
func verify(label:String,hp:float,shot:Node) -> void:
	check(ender.last_dodge_kind=="projectile",label+" invokes guaranteed projectile dodge with random chance disabled")
	check(ender.health==hp,label+" does not deal damage")
	check(not shot.is_queued_for_deletion(),label+" survives dodge")
func run() -> void:
	origin=await setup_world()
	create_timer(60.0).timeout.connect(func():finish(2))
	ender=actor("末影人",origin,"Team1")
	ender.chance_dodge=0.0
	ender.chance_clone_on_projectile_dodge=0.0
	var source:Node=actor("溺尸",origin+Vector2(-160,0))
	await physics_frame
	var hp:float=ender.health
	for kind:String in ["水泼弹","蛛网弹"]:
		reset_ender()
		var shot:Node=load("res://scripts/effects/我的世界/"+kind+".gd").new()
		world.add_child(shot);shot.set_physics_process(false);shot.global_position=origin
		shot._caster=weakref(source)
		if kind=="水泼弹": shot._physics_process(0.0)
		else: shot._try_hit(source)
		verify(kind,hp,shot)
		check(not shot._hit,kind+" does not consume projectile or apply wet/web status")
		shot.queue_free()
	reset_ender()
	var spear:Node=load("res://scripts/effects/我的世界/三叉戟.gd").new()
	spear.unit=source;world.add_child(spear);spear.set_physics_process(false)
	spear.global_position=origin-Vector2(20,0);spear.axis=Vector2.RIGHT;spear.flight_state=1
	spear._fly_out(40.0/source.trident_speed)
	verify("trident",hp,spear)
	check(spear.flight_state==1 and not spear._impact_emitted,"dodged trident continues outbound without contact lightning")
	spear.queue_free()
	reset_ender()
	var brick:Node=load("res://scripts/shooter/建筑工人_砖块.gd").new()
	brick.builder_owner=source;brick.team="Team0"
	brick._on_body_entered(ender)
	verify("brick",hp,brick)
	check(brick._hit_ids.is_empty(),"dodge does not enter brick hit history")
	brick.free()
	reset_ender()
	var sword:Node=load("res://scripts/shooter/战争女神_火焰剑气.gd").new()
	sword.owner_ball=source
	sword._apply_projectile_hit(ender,origin)
	verify("fire sword projectile",hp,sword)
	check(sword._hit_target_ids.is_empty() and not sword._finished,"dodge does not burn, consume or enter sword hit history")
	sword.free()
	reset_ender()
	var text:Node=load("res://scripts/effects/薇欧拉_文字弹.gd").new()
	text.owner_ref=weakref(source)
	text._hit_target(ender)
	verify("text projectile",hp,text)
	text.free()
	reset_ender()
	check(ender.receive_positional_damage(10.0,origin,false,source),"ordinary owner-sourced melee is not turned into guaranteed projectile immunity")
	check(ender.health==hp-10.0,"ordinary melee still deals damage with random dodge disabled")
	print("EXTENDED_PROJECTILE_DODGE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
