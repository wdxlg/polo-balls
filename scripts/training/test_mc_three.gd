extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	return unit
func wall(point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)
	body.global_position = point
	return body
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var evoker:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-130,-90))
	var shulker:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center+Vector2(130,90))
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(-70,0))
	var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(60,0),"Team1")
	target.Max_health = 100000
	target.health = 100000
	target.Speed = 0.0
	target.default_properties["Speed"] = 0.0
	for unit:Node2D in [evoker,ender,shulker]: unit.state_machine.set_physics_process(false)
	check(evoker.mc_live(),"actual World combat runtime active")
	check(evoker.image.texture != null and shulker.image.texture != null and ender.image.texture != null,"all three actual scenes load with character textures")
	var names:Variant = world.return_all_character_names()
	check(names.has("唤魔者") and names.has("潜影贝") and names.has("末影人"),"three characters appear in actual world roster index")
	# 真正的远程入口和各伤害入口，检查不重复抽闪避概率。
	var bullet:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,100),"Team1")
	bullet.state_machine.set_physics_process(false)
	ender.chance_dodge = 0.0
	ender.chance_clone_on_projectile_dodge = 0.0
	ender.chance_clone_on_random_dodge = 0.0
	ender._dodge_grace = 0.0
	var hp:int = ender.health
	check(not ender.receive_positional_damage(100,ender.global_position,false,bullet) and ender.health == hp,"enderman completely avoids ranged positional damage")
	ender._dodge_grace = 0.0
	check(ender.try_full_projectile_dodge(bullet) and ender.last_dodge_kind == "projectile","projectile protocol uses guaranteed fallback when random roll fails")
	ender._dodge_grace = 0.0
	ender.receive_positional_damage(10,ender.global_position,false,target)
	check(ender.health < hp,"ordinary melee can damage enderman when probability fails")
	ender.chance_dodge = 1.0
	ender._dodge_grace = 0.0
	hp = ender.health
	check(not ender.receive_spatial_damage(100,{"source":target,"point":ender.global_position},true,true) and ender.health == hp,"probability dodge also covers raw-health spatial damage")
	ender.global_position = center + Vector2(-60,0)
	target.global_position = center + Vector2(60,0)
	ender.direction = Vector2.RIGHT
	target.direction = Vector2.LEFT
	ender.set_character_visual_flip_h(true)
	target.set_character_visual_flip_h(false)
	ender._scan_gazes()
	check(ender._mutual_gaze and ender._enemy_watching,"face-to-face gaze is detected")
	ender.update_rage(2.3,true,true)
	check(ender.rage_remaining > 0.0 and ender.Has_Collision_Damage,"full red charge enters contact-damage rage")
	var before:float = ender.rage_remaining
	ender.update_rage(1.0,false,true)
	check(ender.rage_remaining > before,"enemy gaze rapidly extends remaining rage")
	ender.update_rage(100.0,false,false)
	check(ender.rage_remaining == 0.0 and ender.Has_Collision_Damage,"rage expires but normal collision damage remains enabled")
	ender.gaze_charge = 0.8
	ender.update_rage(0.5,false,false)
	check(ender.gaze_charge < 0.8,"red charge fades when mutual gaze breaks")
	ender.rage_remaining = 6.0
	ender.chance_dodge = 1.0
	ender._dodge_grace = 0.0
	ender.try_full_projectile_dodge(bullet)
	check(ender.last_dodge_kind == "random","random dodge roll runs before projectile classification")
	ender._dodge_grace = 0.0
	ender.receive_positional_damage(20,ender.global_position,false,target)
	check(ender._rush_left > 0.0 and (ender.global_position-target.global_position).dot(target.direction) < 0.0,"rage probability dodge teleports behind attacker and starts collision rush")
	ender.chance_dodge = 0.0
	ender._dodge_grace = 0.0
	ender._rush_left = 0.0
	ender.try_full_projectile_dodge(bullet)
	check(ender._rush_left == 0.0,"guaranteed projectile dodge alone does not start a rage rush")
	ender._spawn_clones(3)
	await physics_frame
	var clones:Array[Node] = get_nodes_in_group("MCEndermanClone")
	check(clones.size() == 3,"clone skill creates independent summons")
	var safe_clones:bool = true
	for clone:Node in clones:
		safe_clones = safe_clones and not clone.has_method("try_full_projectile_dodge") and clone.collision_layer == 0 and clone.collision_mask == 1 and clone.image.self_modulate.a > 0.35 and clone.image.self_modulate.a < 0.7
		clone._life_left = 0.10
	check(safe_clones,"clones have medium alpha, wall-only collision and no inherited dodge")
	ender._spawn_clones(30)
	check(get_nodes_in_group("MCEndermanClone").size() <= ender.max_clones,"clone per-owner budget enforced")
	# 潜影贝减伤以及三方向重力/天花板反弹。
	shulker.shell_open = false
	hp = shulker.health
	shulker.take_damage(100,true)
	check(hp == shulker.health,"closed shell completely blocks damage")
	shulker.shell_open = true
	hp = shulker.health
	shulker.take_damage(100,true)
	check(hp-shulker.health == 100,"open shell takes normal damage")
	check(shulker.gravity_direction == Vector2.DOWN,"shulker starts with downward gravity")
	shulker.accept_wall_normal(Vector2.RIGHT)
	check(shulker.gravity_direction == Vector2.LEFT,"left wall contact changes gravity to left")
	shulker.accept_wall_normal(Vector2.DOWN)
	check(shulker.gravity_direction == Vector2.LEFT and shulker._external_directional_gravity_lateral_sign > 0.0,"ceiling contact reverses tangent without ceiling attachment")
	shulker.accept_wall_normal(Vector2.UP)
	check(shulker.gravity_direction == Vector2.DOWN,"side wall descent can return to floor gravity")
	bullet.take_damage(999,true)
	bullet.take_damage(999,true)
	check(bullet.health == 1,"shulker bullet survives two attacks regardless of raw damage")
	var bullet_ref:WeakRef = weakref(bullet)
	bullet.take_damage(1,true)
	await process_frame
	await process_frame
	check(bullet_ref.get_ref() == null,"third attack actually frees shulker bullet")
	# 公共重力系统实际使目标上升，重复命中只保留一个状态。
	var effect:Script = load("res://scripts/effects/我的世界/潜影浮空.gd")
	target.global_position = center
	var start_y:float = target.global_position.y
	effect.apply(target,shulker)
	effect.apply(target,shulker)
	check(target.has_meta(effect.META),"levitation state is installed")
	await create_timer(0.35).timeout
	check(target.global_position.y < start_y-1.0,"actual shared gravity moves the affected character upward")
	var ref:WeakRef = target.get_meta(effect.META,null)
	check(ref != null and is_instance_valid(ref.get_ref()),"repeated application retains one live status")
	var top:float = target.collision_shape_2d.global_position.y - target.collision_shape_2d.shape.size.y * absf(target.collision_shape_2d.global_scale.y)*0.5
	var ceiling:StaticBody2D = wall(Vector2(target.global_position.x,top-2.5),Vector2(100,4))
	await physics_frame
	await physics_frame
	effect.apply(target,shulker)
	check(not target.has_meta(effect.META),"head obstruction clears levitation instead of refreshing it")
	ceiling.queue_free()
	# 尖牙与恼鬼通过真实场景进行施法测试。
	evoker.global_position = center+Vector2(-130,-90)
	target.global_position = center+Vector2(0,-90)
	evoker.cast_fangs(target)
	check(get_nodes_in_group("MCEvokerFang").size() == 12,"evoker casts a twelve-fang sequential line")
	hp = target.health
	await create_timer(1.3).timeout
	check(target.health < hp,"evoker fangs deal actual damage")
	check(get_nodes_in_group("MCEvokerFang").is_empty(),"fang effects clean up after attack")
	evoker.summon_vex()
	evoker.summon_vex()
	check(get_nodes_in_group("MCVex").size() == 3,"evoker summons living vex with a three-summon cap")
	# 留出真实战斗帧，检查自动开合发射、弹道、分身自然死亡。
	shulker.health = shulker.Max_health
	shulker._shell_left = 0.01
	shulker.shell_open = false
	shulker.state_machine.set_physics_process(true)
	await create_timer(0.9).timeout
	check(shulker.shell_open,"shulker automatically opens its shell")
	check(get_nodes_in_group("MCShulkerBullet").size() > 0,"open shell automatically fires actual destructible projectiles")
	var expired:int = 0
	for clone:Node in clones:
		if not is_instance_valid(clone): expired += 1
	check(expired == 3,"short-lived clone nodes are actually released")
	await extra_checks(center,ender,target,evoker,shulker)
	print("MC_THREE_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_test_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("MC_THREE_EXIT=",code)
	quit(code)

func _stop_test_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D: node.stop()
	for child:Node in node.get_children(): _stop_test_audio(child)

func extra_checks(center:Vector2,ender:Node2D,target:Node2D,evoker:Node2D,shulker:Node2D) -> void:
	for unit:Node2D in [ender,target,evoker,shulker]: unit.state_machine.set_physics_process(false)
	for group:String in ["MCShulkerBullet","MCEndermanClone","MCVex","MCEvokerFang"]:
		for unit:Node in get_nodes_in_group(group): unit.queue_free()
	await physics_frame
	await physics_frame
	# 真正经过运动积分与 move_and_slide 的墙角路径，而不是只直接调用法线处理函数。
	var room:Vector2 = center + Vector2(0,180)
	var floor_wall:StaticBody2D = wall(room+Vector2(0,50),Vector2(150,6))
	var left_wall:StaticBody2D = wall(room+Vector2(-75,-5),Vector2(6,110))
	var roof_wall:StaticBody2D = wall(room+Vector2(0,-60),Vector2(150,6))
	var crawler:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",room+Vector2(-40,30))
	crawler.Speed = 400.0
	crawler.default_properties["Speed"] = 400.0
	crawler._shell_left = 100.0
	crawler.closed_duration = 100.0
	crawler._external_directional_gravity_lateral_sign = -1.0
	crawler.direction = Vector2.LEFT
	var seen_left:bool = false
	var seen_roof_bounce:bool = false
	var seen_floor_again:bool = false
	var never_up:bool = true
	var previous:Vector2 = crawler.gravity_direction
	var turns:int = 0
	print("ROOM_TRACE room=",room," unit_scale=",crawler.global_scale," shape=",crawler.collision_shape_2d.shape.size," wall_scale=",left_wall.global_scale," time_scale=",Engine.time_scale)
	for i:int in range(160):
		await physics_frame
		if i % 30 == 0: print("WALL_STEP i=",i," p=",crawler.global_position," g=",crawler.gravity_direction," sign=",crawler._external_directional_gravity_lateral_sign," v=",crawler.velocity," state=",crawler.state_machine.current_state)
		never_up = never_up and crawler.gravity_direction != Vector2.UP
		if crawler.gravity_direction != previous: turns += 1
		previous = crawler.gravity_direction
		if crawler.gravity_direction == Vector2.LEFT:
			seen_left = true
			if crawler._external_directional_gravity_lateral_sign > 0.0: seen_roof_bounce = true
		elif seen_roof_bounce and crawler.gravity_direction == Vector2.DOWN: seen_floor_again = true
	check(seen_left,"actual shulker movement transfers from floor onto left wall")
	check(seen_roof_bounce and never_up,"actual ceiling collision reflects movement without upward gravity")
	check(seen_floor_again and turns < 8,"crawler returns to floor without corner oscillation")
	print("CRAWLER_TRACE turns=",turns," final=",crawler.global_position," gravity=",crawler.gravity_direction)
	crawler.queue_free()
	floor_wall.queue_free()
	left_wall.queue_free()
	roof_wall.queue_free()
	await physics_frame
	# 实际伤害 Hitbox 入口，不只检查角色自己的直接伤害函数。
	ender._dodge_grace = 0.0
	ender.chance_dodge = 0.0
	var shot:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,240),"Team1")
	shot.state_machine.set_physics_process(false)
	var hp:int = ender.health
	check(not shot.self_hitbox.try_hit_hurtbox(ender.self_hurtbox) and ender.health == hp and shot.health == 3,"standard projectile hitbox is dodged without consuming projectile")
	ender._dodge_grace = 0.0
	target.Damage = 10
	target.self_hitbox.try_hit_hurtbox(ender.self_hurtbox)
	check(ender.health < hp,"standard melee hitbox can damage enderman after failed dodge roll")
	shot.queue_free()
	# 子弹从身体前方真实飞入，并产生伤害、浮空及白色原药水粒子。
	target.global_position = center + Vector2(70,-170)
	target.clear_external_directional_gravity_velocity()
	target.Repel = Vector2.ZERO
	var impact_shot:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",target.global_position-Vector2(28,0))
	impact_shot.Master = shulker
	impact_shot.target_ref = weakref(target)
	impact_shot.direction = Vector2.RIGHT
	impact_shot._course = Vector2.RIGHT
	impact_shot._course_wait = 10.0
	hp = target.health
	await create_timer(0.3).timeout
	check(target.health < hp and target.has_meta("mc_shulker_levitation"),"actual projectile collision deals damage and installs levitation")
	var particles:Array[Node] = get_nodes_in_group("MCLevitationParticle")
	check(not particles.is_empty() and particles[-1].self_modulate.r > 0.99 and particles[-1].self_modulate.g > 0.99 and particles[-1].self_modulate.b > 0.99,"levitation displays the original potion particles in white")
	if target.has_meta("mc_shulker_levitation"):
		var effect:Node = target.get_meta("mc_shulker_levitation").get_ref()
		var remaining:float = effect.remaining
		game.now_stop_state = true
		await create_timer(0.25).timeout
		check(is_equal_approx(effect.remaining,remaining),"pause does not consume levitation duration")
		game.now_stop_state = false
		effect.finish()
	# 轨迹带分段转弯，不是直接追踪的直线弹。
	var curve_shot:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(-160,-190))
	curve_shot.Master = shulker
	curve_shot.target_ref = weakref(target)
	curve_shot.direction = Vector2.UP
	curve_shot._mc_rng.seed = 19
	var angles:Array[float] = []
	for i:int in range(42):
		await physics_frame
		if is_instance_valid(curve_shot) and curve_shot.health > 0: angles.append(curve_shot.direction.angle())
	check(angles.size() > 20 and absf(angles.max()-angles.min()) > 0.3,"shulker projectile follows a turning segmented trajectory")
	if is_instance_valid(curve_shot): curve_shot.queue_free()
	# 凝视必须有视线，且概率分身、普通分身两条分支都真实执行。
	ender.global_position = center+Vector2(-60,0)
	target.global_position = center+Vector2(60,0)
	ender.direction = Vector2.RIGHT
	target.direction = Vector2.LEFT
	var occluder:StaticBody2D = wall(center,Vector2(6,90))
	await physics_frame
	await physics_frame
	ender._scan_gazes()
	check(not ender._mutual_gaze and not ender._enemy_watching,"walls prevent gaze and rage extension")
	occluder.queue_free()
	await physics_frame
	ender.rage_remaining = 2.0
	ender.update_rage(100.0,false,true)
	check(ender.rage_remaining == 0.0,"continuous watching cannot exceed the new hard total rage duration")
	ender._dodge_grace = 0.0
	ender.chance_clone_on_projectile_dodge = 1.0
	ender.chance_dodge = 0.0
	ender.try_full_projectile_dodge()
	await process_frame
	check(get_nodes_in_group("MCEndermanClone").size() >= 2,"guaranteed projectile dodge can trigger clone skill")
	var before_count:int = get_nodes_in_group("MCEndermanClone").size()
	ender._dodge_grace = 0.0
	ender.chance_clone_on_random_dodge = 1.0
	ender.chance_dodge = 1.0
	ender.receive_positional_damage(20,ender.global_position,false,target)
	await process_frame
	check(get_nodes_in_group("MCEndermanClone").size() > before_count,"probability dodge can also trigger clone skill")
	# 近身释放完整环形尖牙。
	evoker.global_position = center+Vector2(-100,-70)
	target.global_position = evoker.global_position + Vector2(35,0)
	evoker.cast_fangs(target)
	var fangs:Array[Node] = get_nodes_in_group("MCEvokerFang")
	var radial:bool = fangs.size() == 48
	for fang:Node2D in fangs:
		var radius:float = fang.global_position.distance_to(evoker.global_position)
		radial = radial and (absf(radius-24.0)<0.1 or absf(radius-36.0)<0.1 or absf(radius-48.0)<0.1)
	check(radial,"close enemy triggers the radial fang pattern")
	var contact_start:Vector2 = target.global_position
	target.state_machine.set_physics_process(true)
	await create_timer(0.6).timeout
	check(target.global_position.x > contact_start.x+2.0,"radial fangs physically push a nearby enemy away")
