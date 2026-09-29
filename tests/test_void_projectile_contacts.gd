extends "res://tests/test_mc_frontier.gd"
## Contact regressions: absence of damage alone is NOT projectile pass-through.
var void_stand:Node2D
var source:Node2D
var origin:Vector2

func frozen_scene(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var node:Node2D = load(path).instantiate()
	if node.has_method("_is_projectile_motion_object"): node.Team = team
	node.position = point
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject2D: node.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in node.find_children("*","CollisionObject2D",true,false):
		child.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(node,true)
	return node

func script_node(path:String,point:Vector2) -> Node2D:
	var node:Node2D = load(path).new()
	node.position = point
	node.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(node,true)
	return node

func dispose(node:Variant) -> void:
	if is_instance_valid(node): node.queue_free()
	await process_frame
	await physics_frame

func run() -> void:
	origin = await setup_world()
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	create_timer(90.0).timeout.connect(func(): finish(2))
	source = actor("溺尸",origin+Vector2(-180,100),"Team0")
	# A projectile already exists when the intangible stand enters the tree.
	var older:Node2D = frozen_scene("res://scenes/shooter/无重力弹球.tscn",origin-Vector2(100,0))
	older.collision_mask = 3
	void_stand = frozen_scene("res://scenes/characters/默认/虚无盔甲架.tscn",origin,"Team1")
	await physics_frame
	await process_frame
	var U = load("res://scripts/characters/我的世界/new5/utils.gd")
	check(void_stand.is_combat_targetable() and U.enemy(source,void_stand),"projectile immunity preserves ordinary enemy targeting")
	check(void_stand.can_receive_hit_contact(source.self_hitbox,void_stand.self_hurtbox),"ordinary melee contact remains valid")
	check(is_equal_approx(void_stand.modulate.a,0.75) and not void_stand.health_bar.visible,"75 percent opacity and hidden health bar remain unchanged")
	var hp:float = void_stand.health
	var contact:KinematicCollision2D = older.move_and_collide(Vector2(200,0))
	check(contact==null and older.global_position.x>origin.x+90.0,"already-existing physical projectile crosses the entire stand")
	await dispose(older)
	await physical_cases()
	await ray_cases()
	await custom_contact_cases()
	await homing_cases()
	await bookkeeping_and_terrain_cases()
	await reentry_cases()
	check(void_stand.health==hp and void_stand.global_position.is_equal_approx(origin),"all projectile paths leave the stand unharmed and unmoved")
	check(U.enemy(source,void_stand) and void_stand.can_receive_hit_contact(source.self_hitbox,void_stand.self_hurtbox),"targeting and melee still work after projectile traffic")
	print("VOID_PROJECTILE_CONTACTS checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func physical_cases() -> void:
	for name:String in ["子弹","knife","伪军子弹","不坏煎饼弹","时光客时钟","凑企鹅石头","弹球","无重力弹球","潜影弹"]:
		var shot:Node2D = frozen_scene("res://scenes/shooter/"+name+".tscn",origin-Vector2(100,0))
		shot.collision_mask = 3 # Include real character bodies, not just terrain.
		await physics_frame
		await process_frame
		var contact:KinematicCollision2D = shot.move_and_collide(Vector2(200,0))
		check(contact==null and shot.global_position.x>origin.x+90.0,name+" physical body passes through without a bounce/stop")
		if shot.has_method("_is_projectile_motion_object"):
			shot.Master = source
			var events:Array[int] = [0]
			shot.self_hitbox.on_hit.connect(func(_hurt): events[0]+=1)
			check(not shot.self_hitbox.try_hit_hurtbox(void_stand.self_hurtbox) and events[0]==0,name+" hitbox emits no contact signal")
			check(shot.health>0 and not shot.is_queued_for_deletion(),name+" is not consumed by rejected contact")
		await dispose(shot)
	var melee:Node2D = frozen_scene("res://scenes/ball.tscn",origin-Vector2(100,0))
	await physics_frame
	var collision:KinematicCollision2D = melee.move_and_collide(Vector2(200,0))
	check(collision!=null and collision.get_collider()==void_stand,"ordinary character bodies are NOT given projectile collision exceptions")
	await dispose(melee)

func ray_cases() -> void:
	var normal:Node2D = dummy(origin+Vector2(90,0),"Team1")
	await physics_frame
	await process_frame
	var a:Vector2 = origin-Vector2(90,0)
	var b:Vector2 = origin+Vector2(140,0)
	for name:String in ["军火商_子弹","猎人_霰弹","魔角猎人_黑弹"]:
		var shot:Node2D = frozen_scene("res://scenes/shooter/"+name+".tscn",a)
		shot.Team = "Team0"
		shot.Master_name = str(source.name)
		var hit:Dictionary = shot._raycast_motion(a,b,source) if name=="魔角猎人_黑弹" else shot._raycast_motion(a,b)
		check(hit.get("collider")==normal,name+" skips the stand and finds the normal victim behind it in the same sweep")
		await dispose(shot)
	for name:String in ["骷髅箭","仙人掌刺"]:
		var arrow:Node2D = frozen_scene("res://scenes/shooter/我的世界/"+name+".tscn",a)
		arrow._source_ref = weakref(source)
		arrow._source_team = "Team0"
		var hit:Dictionary = arrow._raycast_motion(a,b)
		check(arrow._resolve_ball_from_collider(hit.get("collider"))==normal,name+" ignores both stand body and hurtbox, then finds the next victim")
		await dispose(arrow)
	var blaze:Node2D = script_node("res://scripts/effects/我的世界/烈焰弹.gd",a)
	blaze._source_ref = weakref(source)
	blaze._source_team = "Team0"
	check(blaze._raycast_motion(a,b,source).get("collider")==normal,"blaze ray passes through without leaving a fire patch on the stand")
	await dispose(blaze)
	var bolt:Node2D = frozen_scene("res://scenes/shooter/我的世界/天陨箭矢.tscn",a)
	bolt.configure(source,"Team0",Vector2.RIGHT,620.0,10.0,0.0,0.0,0.0,5000.0,1,10.0,4.0,5.0,0.38)
	var C = load("res://scripts/characters/我的世界/new6/heavenfall_collision.gd")
	check(C.projectile(bolt,source,a,b).get("victim")==normal,"Heavenfall ray ignores every stand collider before accepting a real enemy")
	await dispose(normal)
	bolt._physics_process(180.0/620.0)
	check(not bolt._dead and not bolt.has_pierced() and bolt.global_position.x>origin.x+80.0,"Heavenfall flight creates no hit/rain/rift and spends no terrain pierce on the stand")
	await dispose(bolt)

func custom_contact_cases() -> void:
	for kind:String in ["水泼弹","蛛网弹"]:
		var shot:Node2D = script_node("res://scripts/effects/我的世界/"+kind+".gd",origin)
		shot._caster = weakref(source)
		if kind=="水泼弹": shot._physics_process(0.0)
		else: shot._try_hit(source)
		check(not shot._hit and not shot.is_queued_for_deletion(),kind+" does not consume itself or apply a contact status")
		await dispose(shot)
	var spear:Node2D = load("res://scripts/effects/我的世界/三叉戟.gd").new()
	spear.unit = source
	spear.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(spear)
	spear.global_position = origin-Vector2(40,0)
	spear.axis = Vector2.RIGHT
	spear.flight_state = 1
	spear._fly_out(80.0/source.trident_speed)
	check(spear.flight_state==1 and not spear._impact_emitted and spear.global_position.x>origin.x,"trident passes without sticking, returning early or producing contact lightning")
	await dispose(spear)
	var potion:Node2D = script_node("res://scripts/effects/我的世界/女巫药水.gd",origin-Vector2(40,0))
	potion.source_witch = source
	check(potion._find_segment_hit(origin-Vector2(40,0),origin+Vector2(40,0))==null,"witch bottle ignores the stand before shattering/status-area creation")
	await dispose(potion)
	var brick:Node = load("res://scripts/shooter/建筑工人_砖块.gd").new()
	brick.builder_owner = source
	brick.team = "Team0"
	brick._on_body_entered(void_stand)
	check(brick._hit_ids.is_empty() and not brick.is_queued_for_deletion(),"brick records no intangible contact")
	brick.free()
	var sword:Node = load("res://scripts/shooter/战争女神_火焰剑气.gd").new()
	sword.owner_ball = source
	sword._apply_projectile_hit(void_stand,origin)
	check(sword._hit_target_ids.is_empty() and not sword._finished,"fire sword wave records no intangible contact or burn")
	sword.free()
	var rock:Node2D = frozen_scene("res://scenes/shooter/凑企鹅石头.tscn",origin-Vector2(40,0))
	rock.Master = source
	rock._land(void_stand)
	check(rock.flying and rock.is_in_group("BattleTransient"),"penguin rock ignores the stand BEFORE switching to its landed state")
	await dispose(rock)
	var snow:Node2D = frozen_scene("res://scenes/shooter/我的世界/雪球.tscn",origin-Vector2(70,0))
	snow.Master = source
	snow.direction = Vector2.RIGHT
	snow.move(260.0,140.0/260.0)
	check(not snow._spent and not snow._impact_played and snow.global_position.x>origin.x+60.0,"snowball passes without impact sound, consumption or cold")
	await dispose(snow)
	var card:Node2D = script_node("res://scripts/effects/占卜师卡牌.gd",origin-Vector2(50,0))
	card._flight_target_cache = void_stand
	card._flight_source_cache = source
	check(card._sweep_attack_contact(origin-Vector2(50,0),origin+Vector2(50,0))==null,"divination card does not report a contact or consume itself")
	await dispose(card)
	var clown:Node2D = frozen_scene("res://scenes/characters/人物/小丑.tscn",origin+Vector2(-160,100))
	var shot:Node2D = frozen_scene("res://scenes/shooter/clown/clown_projectile.tscn",origin-Vector2(50,0))
	shot.Master = clown
	shot.projectile_mode = shot.ProjectileMode.BOOMERANG
	shot.direction = Vector2.RIGHT
	check(not shot._try_boomerang_hit(void_stand) and shot.boomerang_last_hit_msec.is_empty() and shot.direction==Vector2.RIGHT,"boomerang does not reverse or enter hit cooldown on the stand")
	shot.projectile_mode = shot.ProjectileMode.SNIPER
	shot._swept_sniper_hit(origin-Vector2(50,0),origin+Vector2(50,0))
	check(not shot.exploded and not shot.is_queued_for_deletion(),"clown sniper sweep does not consume the projectile")
	await dispose(shot)
	var confetti:Node2D = frozen_scene("res://scenes/shooter/clown/clown_area_object.tscn",origin)
	confetti.Master = clown
	confetti.object_mode = confetti.ObjectMode.CONFETTI
	confetti._try_trigger_target(void_stand)
	check(not confetti.triggered and confetti.hit_ids.is_empty() and not confetti.is_queued_for_deletion(),"confetti ignores contact before locking its one-shot trigger")
	await dispose(confetti)
	await dispose(clown)
	var projectile:Node2D = frozen_scene("res://scenes/shooter/子弹.tscn",origin-Vector2(50,0))
	var flight:Node = load("res://scripts/characters/我的世界/new6/wool_projectile.gd").new()
	flight.shot = projectile
	flight.flying = true
	flight.flight = Vector2(200,0)
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(flight)
	flight._physics_process(0.5)
	check(not flight.is_queued_for_deletion() and not projectile.is_queued_for_deletion() and projectile.global_position.x>origin.x+40.0,"wool-reflected projectiles also pass through without retirement")
	await dispose(flight)
	await dispose(projectile)

func homing_cases() -> void:
	var fire:Node2D = script_node("res://scripts/effects/薇欧拉_火焰弹.gd",origin-Vector2(40,0))
	fire.setup(source,void_stand,origin-Vector2(40,0),{"speed":200.0})
	fire._physics_process(0.5)
	check(not fire._finished and not fire.is_queued_for_deletion() and fire.global_position.x>origin.x+50.0,"targeted fire arrow flies PAST the stand, rather than stopping at its center")
	await dispose(fire)
	for name:String in ["乌鲁鲁巡飞弹","堵桥巡飞弹"]:
		var missile:Node2D = script_node("res://scripts/effects/"+name+".gd",origin-Vector2(50,0))
		missile.setup(source,void_stand,origin-Vector2(50,0))
		check(missile._sweep_enemy(source,origin-Vector2(50,0),origin+Vector2(50,0))==null,name+" proximity/sweep treats the stand as absent")
		if name=="乌鲁鲁巡飞弹": missile.speed = 200.0
		else:
			missile.cruise_speed = 200.0
			missile.elapsed = missile.rise_duration+0.01
		missile.current_direction = Vector2.RIGHT
		missile._physics_process(0.25)
		missile._physics_process(0.25)
		check(not missile._exploding and not missile._finished and not missile.is_queued_for_deletion() and missile.global_position.x>origin.x+40.0,name+" neither proximity-explodes nor turns back on reaching the stand")
		await dispose(missile)

func bookkeeping_and_terrain_cases() -> void:
	# Spy only on the feedback API; the real stand scene and rejection chain still run.
	var probe:Node2D = load("res://scenes/characters/默认/虚无盔甲架.tscn").instantiate()
	probe.set_script(load("res://tests/void_contact_feedback_probe.gd"))
	probe.Team = "Team1"
	probe.position = origin+Vector2(0,-120)
	probe.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(probe,true)
	var bullet:Node2D = frozen_scene("res://scenes/shooter/子弹.tscn",origin-Vector2(100,0))
	bullet.Master = source
	check(not bullet.self_hitbox.try_hit_hurtbox(probe.self_hurtbox) and probe.block_bursts==0,"rejected projectile contact is silent, not an inherited shield/block burst")
	await dispose(bullet)
	await dispose(probe)
	var normal:Node2D = dummy(origin+Vector2(120,100),"Team1")
	for kind:String in ["Sans骨头攻击","Sans滚动骨头","Sans龙骨炮"]:
		var effect:Node = load("res://scripts/effects/传说之下/"+kind+".gd").new()
		effect.source = source
		effect.source_team = "Team0"
		check(not effect._is_enemy(void_stand) and effect._is_enemy(normal),kind+" skips intangible contacts without disabling hits on ordinary enemies")
		effect.free()
	await dispose(normal)
	var clock:Node2D = frozen_scene("res://scenes/shooter/时光客时钟.tscn",origin-Vector2(60,0))
	clock.Master = source
	clock._rewind_damage_multiplier = 1.0
	clock._deal_reverse_projectile_damage(origin-Vector2(60,0),origin+Vector2(60,0))
	check(not clock._rewind_hit_ids.has(void_stand.get_instance_id()),"rewound clock does not record a hit on the stand")
	await dispose(clock)
	var fireball:Node2D = frozen_scene("res://scenes/shooter/我的世界/恶魂火焰弹.tscn",origin-Vector2(60,0))
	fireball.flight_velocity = Vector2(200,0)
	fireball._launch_pending = false
	fireball.step_mob(0.6)
	check(not fireball.exploded and not fireball.is_queued_for_deletion() and fireball.global_position.x>origin.x+50.0,"neutral Creature-type ghast fireball passes without a proximity blast")
	await dispose(fireball)
	var registered:bool = false
	for i:int in world.spawner.get_spawnable_scene_count():
		registered = registered or world.spawner.get_spawnable_scene(i)=="res://scenes/characters/默认/石头.tscn"
	check(registered,"actual World multiplayer spawner still registers the independent stone scene")
	var stone:Node2D = frozen_scene("res://scenes/characters/默认/石头.tscn",origin+Vector2(80,0))
	var rock:Node2D = frozen_scene("res://scenes/shooter/凑企鹅石头.tscn",origin-Vector2(100,0))
	rock.Master = source
	rock.collision_mask = 3
	await physics_frame
	await process_frame
	var hit:KinematicCollision2D = rock.move_and_collide(Vector2(240,0))
	check(hit!=null and hit.get_collider()==stone,"projectile passes through the stand but still strikes solid stone behind it")
	if hit!=null: rock._land(hit.get_collider())
	check(not rock.flying and not rock.get_collision_exceptions().has(void_stand),"landing restores ordinary solid-object collision, rather than permanent projectile exemptions")
	rock.global_position = origin-Vector2(100,0)
	await physics_frame
	hit = rock.move_and_collide(Vector2(180,0))
	check(hit!=null and hit.get_collider()==void_stand,"a grounded rock is no longer treated as a flying projectile")
	await dispose(rock)
	await dispose(stone)
	check(void_stand._void_projectile_bodies.is_empty(),"retired projectiles leave no accumulated collision-exception references")

func reentry_cases() -> void:
	var shot:Node2D = frozen_scene("res://scenes/shooter/子弹.tscn",origin-Vector2(100,0))
	shot.collision_mask = 3
	await physics_frame
	world.remove_child(void_stand)
	world.add_child(void_stand,true)
	await physics_frame
	await process_frame
	var hit:KinematicCollision2D = shot.move_and_collide(Vector2(200,0))
	check(hit==null and shot.global_position.x>origin.x+90.0,"stand re-entry restores exceptions for already-existing projectiles without requesting _ready again")
	await dispose(shot)
	shot = frozen_scene("res://scenes/shooter/子弹.tscn",origin-Vector2(100,0))
	shot.collision_mask = 3
	await physics_frame
	await process_frame
	hit = shot.move_and_collide(Vector2(200,0))
	check(hit==null and shot.global_position.x>origin.x+90.0,"stand re-entry also restores the new-projectile watcher")
	world.remove_child(shot)
	shot.position = origin-Vector2(100,0)
	world.add_child(shot,true)
	await physics_frame
	await process_frame
	hit = shot.move_and_collide(Vector2(200,0))
	check(hit==null and shot.global_position.x>origin.x+90.0,"reused projectile bodies are covered even when Godot does not emit ready a second time")
	await dispose(shot)
