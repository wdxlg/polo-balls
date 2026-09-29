extends "res://tests/test_mc_bat_transform.gd"

func freeze(unit:Node2D) -> void:
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false

func reset_feed(b:Node2D,enemy:Node2D) -> void:
	b.detach()
	b.cohort.left = 10000.0
	b.cohort.frame = -1
	b.assign_vitals(150,300)
	b._cooldown = 0.0
	b._mc_target_ref = weakref(enemy)
	b._mc_target_wait = 10000.0
	b.global_position = enemy.global_position+Vector2(-20,0)
	b.global_position = b.target_surface(enemy)
	b.direction = Vector2.ZERO
	b.Repel = Vector2.ZERO
	enemy.block = 0
	enemy.Damage_reduction = 0.0
	enemy.health = 100000
	b.begin_bite(enemy)

func tick(b:Node2D,dt:float = 0.0166667) -> void:
	b.cohort.frame = -1
	b.tick_physics(b.State.Move,dt)

func exercise_deadline(b:Node2D,enemy:Node2D,label:String) -> void:
	reset_feed(b,enemy)
	check(is_equal_approx(b.attach_duration,2.0) and is_equal_approx(b._attach_left,2.0),label+" scene starts a two-second latch")
	for i:int in range(3): tick(b,0.5)
	check(b.attached_target()==enemy and is_equal_approx(b._attach_left,0.5),label+" periodic drains do not renew attachment lifetime")
	var previous_hp:int = enemy.health
	b._cooldown = 0.0
	b.begin_bite(enemy)
	check(enemy.health==previous_hp and is_equal_approx(b._attach_left,0.5),label+" repeated bite cannot refresh timer or add damage")
	tick(b,0.49)
	check(b.attached_target()==enemy and b.feeding_guard_active(),label+" still attached just before two seconds")
	var left:float = b._attach_left
	game.now_stop_state = true
	tick(b,10.0)
	check(b.attached_target()==enemy and b._attach_left==left,label+" pause freezes the attachment deadline")
	game.now_stop_state = false
	previous_hp = enemy.health
	var capacity:int = b.Max_health
	tick(b,0.01)
	check(b.attached_target()==null and is_zero_approx(b._attach_left) and is_zero_approx(b._drain_wait),label+" detaches exactly at two seconds and clears both timers")
	check(enemy.health==previous_hp and b.Max_health==capacity,label+" deadline tick causes no extra drain or growth")
	check(not b.feeding_guard_active() and not b.is_knockback_displacement_immune() and not b.get_collision_exceptions().has(enemy),label+" deadline clears guard, knockback immunity and host collision exception")
	check(is_equal_approx(b._cooldown,3.0),label+" timeout starts the full normal cooldown")
	var incoming_before:int = b.health
	b.receive_positional_damage(20,b.global_position,false,enemy)
	check(incoming_before-b.health==20,label+" timeout removes feeding damage reduction")
	tick(b,2.99)
	check(b.attached_target()==null and enemy.health==previous_hp,label+" cannot relatch during three-second cooldown")
	b.global_position = b.target_surface(enemy)
	tick(b,0.011)
	check(b.attached_target()==enemy and is_equal_approx(b._attach_left,2.0),label+" next valid bite starts a fresh two-second lifetime after cooldown")
	reset_feed(b,enemy)
	previous_hp = enemy.health
	tick(b,4.0)
	check(b.attached_target()==null and enemy.health==previous_hp and is_equal_approx(b._cooldown,3.0),label+" oversized delta expires before damage without immediate relatch")
	for state:int in [b.State.Move,b.State.Stand,b.State.Hurt]:
		reset_feed(b,enemy)
		for i:int in range(120): b.tick_physics(state,1.0/60.0)
		check(b.attached_target()==null,label+" 120 normal physics steps expire in state "+str(state))
	b.detach()

func exercise(b:Node2D,enemy:Node2D,label:String) -> void:
	reset_feed(b,enemy)
	check(b.attached_target() == enemy and b.feeding_guard_active(),label+" successful health bite starts feeding")
	b.cohort.left = 0.1
	var previous_hp:int = enemy.health
	for i:int in range(60): tick(b)
	check(b.attached_target() == enemy and b.feeding_guard_active(),label+" stays attached within two seconds even after the form timer expires")
	check(enemy.health < previous_hp and b.Max_health > 300,label+" feeding within its deadline continues real health damage and capacity growth")
	check(not b.cohort.get("gathering",false) and b.cohort.left == 0.0,label+" automatic morph waits rather than interrupting feeding")
	b.cohort.left = 10000.0
	var time_before:float = b._drain_wait
	previous_hp = enemy.health
	game.now_stop_state = true
	tick(b,10.0)
	check(enemy.health == previous_hp and b._drain_wait == time_before and b.attached_target() == enemy,label+" game pause freezes damage and timers without ending feeding")
	game.now_stop_state = false
	var incoming_before:int = b.health
	b.receive_positional_damage(20,b.global_position,false,enemy)
	check(incoming_before-b.health == 5 and b.attached_target() == enemy,label+" ordinary incoming hit neither breaks feeding nor changes its 75 percent reduction")
	incoming_before = b.health
	b.receive_spatial_damage(20,b.global_position,true,true)
	check(incoming_before-b.health == 5 and b.attached_target() == enemy,label+" raw spatial hit retains one feeding reduction and does not interrupt")
	var point:Vector2 = b.global_position
	for locked:bool in [true,false]:
		var effect:Node = b.apply_knockback(Vector2.LEFT,160,800,0,0,{"source":enemy,"lock_control":locked})
		check(effect == null and not b.dizziness,label+" rejects knockback without acquiring movement lock: "+str(locked))
		tick(b)
		check(b.global_position.distance_to(point)<0.1 and b.attached_target()==enemy,label+" knockback has no displacement or latch interruption: "+str(locked))
	# Bypass apply_knockback exactly like production piston/golem effects.
	for path:String in ["res://scripts/effects/knockback_effect.gd","res://scripts/characters/我的世界/new5/piston_push.gd","res://scripts/characters/我的世界/iron_golem/airborne.gd"]:
		var push:Node = load(path).new()
		push.target = b
		push.source = enemy
		push.distance = 120
		push.speed = 700
		push.stun_duration = 0.0
		b.add_child(push)
		check(not push.is_active_effect() and not b.dizziness and b.attached_target()==enemy,label+" directly spawned controller respects immunity: "+path.get_file())
		check(b.global_position.distance_to(point)<0.1 and b.Repel.is_zero_approx(),label+" direct controller has no root movement: "+path.get_file())
	# Older attacks can write Repel directly; even the Stand/Hurt route must follow.
	b.Repel = Vector2(-900,200)
	b._crowd_separation_velocity = Vector2(700,0)
	b.stand(1.0/60.0)
	check(b.global_position.distance_to(point)<0.1 and b.Repel.is_zero_approx(),label+" legacy Repel and crowd separation cannot push an attached bat in Stand")
	b._crowd_separation_velocity = Vector2.ZERO
	var offset:Vector2 = b.global_position-enemy.global_position
	enemy.global_position += Vector2(6,0)
	b.tick_physics(b.State.Hurt,1.0/60.0)
	check((b.global_position-enemy.global_position).distance_to(offset)<0.1 and b.attached_target()==enemy,label+" ordinary hurt state follows moving host")
	var bump:Node = b.apply_knockback(Vector2.LEFT,160,800,0,0.4,{"source":enemy,"stun_only_on_collision":true})
	check(bump==null and not b.dizziness and b.attached_target()==enemy,label+" collision-only stun cannot trigger without knockback collision")
	var stun:Node = b.apply_stun(0.4,enemy)
	check(is_instance_valid(stun) and b.dizziness and b.attached_target()==null,label+" real pure stun immediately interrupts feeding")
	if is_instance_valid(stun): stun._finish(false)
	check(not b.dizziness,label+" real stun releases its owned control lock")
	reset_feed(b,enemy)
	point = b.global_position
	stun = b.apply_knockback(Vector2.LEFT,160,800,0,0.4,{"source":enemy})
	check(is_instance_valid(stun) and b.dizziness and b.attached_target()==null and b.Repel.is_zero_approx() and b.global_position==point,label+" combined hit preserves stun but suppresses displacement while feeding")
	if is_instance_valid(stun): stun._finish(false)
	reset_feed(b,enemy)
	b.dizziness = true
	tick(b)
	check(b.attached_target()==null,label+" legacy independent stun flag can interrupt too")
	b.dizziness = false
	reset_feed(b,enemy)
	previous_hp = enemy.health
	var cap:int = b.Max_health
	enemy.max_block = 10000
	enemy.default_properties.max_block = 10000
	enemy.block = 1000
	check(not b.feeding_guard_active(),label+" new shield immediately invalidates feeding protection")
	tick(b)
	check(b.attached_target()==null and enemy.health==previous_hp and b.Max_health==cap,label+" shield ends feeding without free healing or health damage")
	check(not b.get_collision_exceptions().has(enemy),label+" defense interruption releases host collision exception")
	reset_feed(b,enemy)
	previous_hp = enemy.health
	cap = b.Max_health
	enemy.Damage_reduction = 1.0
	tick(b,0.51)
	check(b.attached_target()==null and enemy.health==previous_hp and b.Max_health==cap,label+" zero actual damage due to full damage immunity ends feeding without growth")
	check(b._cooldown>0.0,label+" blocked drain cannot immediately relatch and bypass normal cooldown")
	enemy.Damage_reduction = 0.0
	var effect:Node = b.apply_knockback(Vector2.LEFT,50,700,0,0,{"source":enemy})
	check(is_instance_valid(effect) and b.dizziness and not b.Repel.is_zero_approx(),label+" knockback vulnerability returns after feeding ends")
	if is_instance_valid(effect): effect._finish(false)
	reset_feed(b,enemy)
	enemy.health = 1
	tick(b,0.51)
	check(enemy.health<=0 and b.attached_target()==null,label+" host death ends feeding immediately")
	enemy.health = 100000
	reset_feed(b,enemy)
	enemy.global_position += Vector2(130,0)
	tick(b)
	check(b.attached_target()==null,label+" host teleport escapes without dragging bat through terrain")
	reset_feed(b,enemy)
	b._damage_output_disabled_until_msec = Time.get_ticks_msec()+200
	tick(b)
	check(b.attached_target()==null,label+" existing explicit damage-output disable still ends feeding")
	b._damage_output_disabled_until_msec = 0

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(90.0,true,false,true).timeout.connect(func(): finish(2))
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,120),"Team1")
	freeze(b)
	freeze(enemy)
	enemy.Max_health = 100000
	enemy.default_properties.Max_health = 100000
	enemy.health = 100000
	await physics_frame
	await process_frame
	pause_members(b)
	for member:Node2D in b.living_members(): member.global_position = center+Vector2(-250,0)
	exercise_deadline(b,enemy,"bat")
	exercise(b,enemy,"bat")
	# A feeding nonleader must also defer the leader's scheduled fusion.
	var sibling:Node2D = b.living_members()[1]
	reset_feed(sibling,enemy)
	b.cohort.left = 0.0
	tick(b)
	check(not b.cohort.get("gathering",false) and sibling.attached_target()==enemy,"feeding nonleader prevents scheduled group convergence")
	tick(sibling,2.0)
	check(sibling.attached_target()==null,"feeding nonleader also expires after two seconds")
	tick(b)
	check(b.cohort.get("gathering",false),"expired group timer proceeds to convergence once all feeding ends")
	b.cancel_gather()
	settle_fusion(b)
	check(b.vampire,"cohort still fuses with existing health conservation path")
	var summary:String = world._armor_test_special_effect_summary(b,b.Type_Tags)
	check(summary.contains("最多2秒") and not summary.contains("无时限") and summary.contains("击退") and summary.contains("眩晕") and summary.contains("等待本群吸血结束"),"actual bat/vampire introduction documents the two-second cap and its counters")
	await physics_frame
	await process_frame
	exercise_deadline(b,enemy,"vampire")
	exercise(b,enemy,"vampire")
	# Earlier unlocked pressure cannot leave a latent impulse after latching.
	b.detach()
	var old_push:Node = b.apply_knockback(Vector2.LEFT,100,700,0,0,{"source":enemy,"lock_control":false})
	reset_feed(b,enemy)
	check(b.attached_target()==enemy and is_instance_valid(old_push) and not old_push.is_active_effect() and b.Repel.is_zero_approx(),"latching cancels pre-existing unlocked knockback without a delayed residual push")
	b.detach()
	old_push = b.apply_knockback(Vector2.LEFT,100,700,0,0.4,{"source":enemy,"lock_control":false})
	reset_feed(b,enemy)
	check(b.attached_target()==null and b.dizziness and not old_push.is_active_effect(),"pre-existing unlocked effect preserves promised stun but not displacement")
	for child:Node in b.get_children():
		if child.has_method("is_active_effect") and child.is_active_effect(): child._finish(false)
	reset_feed(b,enemy)
	var direct_stun:Node = load("res://scripts/characters/我的世界/iron_golem/airborne.gd").new()
	direct_stun.target = b
	direct_stun.source = enemy
	direct_stun.distance = 100
	direct_stun.speed = 700
	direct_stun.stun_duration = 0.4
	b.add_child(direct_stun)
	check(not direct_stun.is_active_effect() and b.dizziness and b.attached_target()==null and b.Repel.is_zero_approx(),"direct golem launch with genuine stun preserves stun without airborne movement")
	for child:Node in b.get_children():
		if child.has_method("is_active_effect") and child.is_active_effect(): child._finish(false)
	# Test real Enderman defense routing rather than a fake drain stub.
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(150,-60),"Team1")
	freeze(ender)
	ender.Max_health = 100000
	ender.default_properties.Max_health = 100000
	ender.chance_dodge = 0.0
	ender.chance_clone_on_random_dodge = 0.0
	await physics_frame
	reset_feed(b,ender)
	check(b.attached_target()==ender,"real Enderman can be attached when it does not dodge")
	ender.chance_dodge = 1.0
	var before:int = ender.health
	var cap:int = b.Max_health
	tick(b,0.51)
	check(ender.health==before and b.Max_health==cap and b.attached_target()==null,"real Enderman dodge immediately ends drain with no healing")
	var bow:Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",center+Vector2(-150,100),"Team1")
	freeze(bow)
	bow.Max_health = 100000
	bow.default_properties.Max_health = 100000
	await physics_frame
	reset_feed(b,bow)
	check(b.attached_target()==bow,"actual longbow can be fed on outside its immunity window")
	bow._rift_grace = 1.0
	before = bow.health
	cap = b.Max_health
	tick(b,0.51)
	check(b.attached_target()==null and bow.health==before and b.Max_health==cap,"actual longbow invulnerability rejects drain and ends attachment")
	reset_feed(b,enemy)
	b.dizziness = true
	var external:Node = b.apply_stun(0.1,enemy)
	if is_instance_valid(external): external._finish(false)
	check(b.dizziness,"feeding/knockback changes never clear an independent stun baseline")
	b.dizziness = false
	b.detach()
	var victim:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(200,120),"Team1")
	freeze(victim)
	victim.Max_health = 100000
	victim.default_properties.Max_health = 100000
	reset_feed(b,victim)
	victim.queue_free()
	await process_frame
	tick(b)
	check(b.attached_target()==null,"freed host is cleaned up safely")
	print("BAT_CONTINUOUS_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
