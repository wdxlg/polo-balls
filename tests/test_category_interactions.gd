extends "res://tests/test_mc_frontier.gd"
var API:Script
var CAP:Script
var WOOL:Script
const FIXTURE = preload("res://tests/category_projectile_fixture.gd")
var driver:Node

func unit(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var value:Node2D = spawn(path,point,team)
	value.state_machine.set_physics_process(false)
	value.set_physics_process(false)
	value.set_process(false)
	value.Has_Collision_Damage = false
	value.self_hitbox.monitoring = false
	return value

func shot(kind:String,source:Node2D,point:Vector2) -> Node2D:
	var value:Node2D
	if kind == "bolt": value = load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	elif kind == "rain": value = load("res://scenes/shooter/我的世界/天陨箭.tscn").instantiate()
	elif kind == "legacy": value = load("res://scenes/shooter/子弹.tscn").instantiate()
	else:
		value = FIXTURE.new()
		value.set_meta("projectile_damage_kind","fire")
	value.position = point
	world.add_child(value,true)
	if kind == "bolt": value.configure(source,source.Team,Vector2.RIGHT,620.0,17.0,0.0,0.0,0.0,560.0,3,60.0,4.0,22.0,0.38)
	elif kind == "rain":
		value.configure(source,source.Team,point+Vector2(100,0),0.38,17.0,22.0)
		value._falling = true
		value._vy = 620.0
	value.global_position = point
	API.bind_owner(value,source,source.Team)
	if kind == "legacy": value.Speed = 620.0; value.Damage = 17; value.direction = Vector2.RIGHT
	value.set_physics_process(false)
	if value.has_node("state_machine"): value.state_machine.set_physics_process(false)
	return value

func reserve(collector:Node,point:Vector2) -> void:
	collector.notes = 1
	collector._note_cloud.clear()
	collector._note_cloud.resize(1,point)

func run() -> void:
	API = load("res://classes/projectile_interactions.gd")
	CAP = load("res://scripts/characters/我的世界/allay/capture.gd")
	WOOL = load("res://scripts/characters/我的世界/new6/wool_projectile.gd")
	var center:Vector2 = await setup_world()
	create_timer(70.0).timeout.connect(func(): finish(2))
	var source:Node2D = dummy(center+Vector2(-300,150),"Team1")
	var collector:Node2D = actor("悦灵",center+Vector2(100,150),"Team0")
	await process_frame
	driver = root.get_node("SharedProjectileInteractions")
	driver.set_physics_process(false)
	collector.set_physics_process(false)
	collector.Can_Attack = false
	var magnet:Node2D = unit("res://scenes/characters/人物/磁铁.tscn",center+Vector2(0,-180))
	var drunk:Node2D = unit("res://scenes/characters/人物/醉汉.tscn",center+Vector2(-180,-180))
	var shield:Node2D = unit("res://scenes/characters/三角洲/盾狗.tscn",center+Vector2(200,-180))
	var mirror:Node2D = unit("res://scenes/characters/人物/镜子.tscn",center+Vector2(300,0))
	var speedster:Node2D = unit("res://scenes/characters/人物/极速者.tscn",center+Vector2(-200,0))
	var pig:Node2D = unit("res://scenes/characters/meme/寸头没事沙漠溜达猪.tscn",center+Vector2(0,200))
	var sword:Node2D = unit("res://scenes/characters/人物/剑客.tscn",center+Vector2(240,200))
	var enderman:Node2D = actor("末影人",center+Vector2(300,200))
	var wither:Node2D = actor("凋灵",center+Vector2(-300,-240))
	wither.summoned = false
	var wire:Node = load("res://scripts/effects/三角洲_铁丝网.gd").new()
	world.add_child(wire)
	wire.set_physics_process(false)
	for kind:String in ["bolt","rain","legacy","new_protocol"]:
		var value:Node2D = shot(kind,source,center)
		check(API.live(value),kind+" shared projectile identity/live phase")
		check(API.candidates(self).has(value),kind+" discover without private role group")
		check(not CAP.describe(value).is_empty(),kind+" Allay descriptor")
		check(CAP.hostile(collector,value),kind+" hostile source")
		check(shield._is_blockable_projectile_source(value),kind+" shield category")
		check(wire._is_projectile_node(value),kind+" wire category")
		check(magnet._is_magnetic_projectile(value),kind+" magnet capability")
		check(drunk._is_projectile_candidate(value) and drunk._projectile_velocity(value).length()>1.0,kind+" drunk reads motion")
		check(speedster._is_hostile_projectile(value),kind+" speedster category/team")
		check(pig._looks_like_projectile(value),kind+" pig category")
		check(enderman._ranged_source(value),kind+" enderman ranged category")
		check(WOOL.is_projectile(value) and WOOL.motion(value).length()>1.0,kind+" wool reads motion")
		magnet._set_projectile_direction(value,Vector2.LEFT)
		magnet._set_projectile_speed(value,420.0)
		check(API.velocity_of(value).distance_to(Vector2(-420,0))<0.01,kind+" magnet actually rewrites movement")
		API.bind_owner(value,collector,collector.Team)
		check(not CAP.hostile(collector,value) and not API.hostile(drunk,value),kind+" friendly ownership is not stolen")
		API.bind_owner(value,source,source.Team)
		mirror._reflect_active = true
		check(mirror.try_reflect_projectile(value),kind+" mirror reflects native projectile")
		check(API.owner_of(value)==mirror and API.team_of(value)==mirror.Team and API.velocity_of(value).x>0,kind+" reflection changes owner team and direction")
		API.bind_owner(value,source,source.Team)
		check(wither.try_reflect_projectile(value) and API.owner_of(value)==wither,kind+" wither awakening reflects native projectile")
		API.bind_owner(value,source,source.Team)
		value.global_position = center
		reserve(collector,center)
		var before:int = collector.cargo.size()
		check(collector.collect_projectile(value,center,0),kind+" real contact consumes note")
		check(collector.notes==0 and collector.cargo.size()==before+1,kind+" native cargo stored")
		var data:Dictionary = collector.cargo.back()
		var returned:Node2D = CAP.launch(collector,data,source,center+Vector2(50,0))
		check(is_instance_valid(returned),kind+" native relaunch succeeds")
		if is_instance_valid(returned):
			returned.set_physics_process(false)
			check(API.team_of(returned)==collector.Team and API.velocity_of(returned).x<0,kind+" returned projectile moves toward enemy with new team")
			check(not CAP.hostile(collector,returned),kind+" returned shot friendly protection")
			check(API.damage_kind_of(returned)==str(data.damage_kind),kind+" returned damage-kind protocol metadata retained")
			check(absf(API.damage_of(returned)-17.0)<0.01,kind+" captured damage retained")
			if kind in ["bolt","rain"]:
				var old_point:Vector2 = source.global_position
				var direction:Vector2 = API.velocity_of(returned).normalized()
				source.global_position = returned.global_position+direction*20.0
				var hp:float = source.health
				if kind == "rain": returned._redirect_left = 0.0
				returned._physics_process(0.05)
				check(source.health < hp,kind+" returned native projectile really damages enemy")
				if kind == "bolt": check(get_nodes_in_group("HeavenfallRainArrow").size()>=3,"returned bolt retains native rain payload")
				source.global_position = old_point
			returned.queue_free()
		collector.cargo.clear()
	# Phase changes must defeat stale groups/paths and cannot resurrect a grounded projectile.
	var rock:Node = load("res://scenes/shooter/凑企鹅石头.tscn").instantiate()
	rock.flying = true
	world.add_child(rock,true)
	rock.set_physics_process(false)
	rock.flying = true
	check(API.is_projectile(rock) and shield._is_blockable_projectile_source(rock),"flying rock recognized")
	rock.flying = false
	check(not API.is_projectile(rock) and not shield._is_blockable_projectile_source(rock) and not pig._looks_like_projectile(rock),"landed rock is obstacle even with projectile groups")
	check(CAP.describe(rock).is_empty() and not WOOL.is_projectile(rock),"grounded rock cannot be captured")
	rock.queue_free()
	var fallen:Node2D = shot("rain",source,center)
	fallen._landed = true
	check(not API.is_projectile(fallen) and not magnet._is_magnetic_projectile(fallen) and CAP.describe(fallen).is_empty(),"burrowing rain is visual, not flying projectile")
	fallen.queue_free()
	check(not API.is_projectile(source) and CAP.describe(source).is_empty(),"characters are never captured")
	# Actual magnet hold/release retains native object and restores ticking.
	var held:Node2D = shot("bolt",source,magnet.global_position+Vector2(30,0))
	held.set_physics_process(true)
	magnet._start_projectile_orbit(held)
	check(not held.is_physics_processing() and held.has_meta("_magnet_orbit_owner"),"magnet stores actual Area2D and pauses its script")
	magnet._release_all_orbiting_projectiles()
	check(held.is_physics_processing() and not held.has_meta("_magnet_orbit_owner") and API.velocity_of(held).length()>0,"magnet releases Area2D with restored movement")
	held.queue_free()
	# Wire consumes durability through its actual category scan, once per projectile.
	var wire_shot:Node2D = shot("bolt",source,center)
	wire.global_position = center
	var wire_hp:float = wire.durability
	wire._process_projectile_durability()
	check(wire.durability < wire_hp,"wire actual durability scan includes Area2D bolt")
	wire_hp = wire.durability
	wire._process_projectile_durability()
	check(wire.durability == wire_hp,"wire does not charge durability twice for one projectile")
	wire_shot.queue_free()
	# Shield front/back policy remains unchanged; native damage/secondary effects are stopped.
	var shield_shot:Node2D = shot("bolt",source,shield.global_position+Vector2(50,0))
	shield.direction = Vector2.RIGHT
	check(shield.try_block_projectile_hit(shield_shot,shield.global_position+Vector2(20,0),17.0),"shield blocks native bolt in front")
	check(not shield.try_block_projectile_hit(shield_shot,shield.global_position-Vector2(20,0),17.0),"shield still does not block behind")
	API.set_velocity(shield_shot,Vector2(-620,0))
	driver._physics_process(0.1)
	check(shield_shot.is_queued_for_deletion(),"driver shield block retires native arrow without rain explosion")
	# Parry retirement cannot trigger secondary rain.
	var parried:Node2D = shot("bolt",source,center)
	sword._play_special_defense_feedback("parry",center,17.0,parried)
	check(parried.is_queued_for_deletion(),"swordsman retires non-ball native projectile")
	# Real predictive queries, not just helper booleans.
	var threat_shot:Node2D = shot("bolt",source,drunk.global_position+Vector2(100,0))
	API.set_velocity(threat_shot,Vector2(-620,0))
	check(not drunk._find_projectile_threat().is_empty(),"drunk predicts actual non-ball trajectory")
	threat_shot.global_position = speedster.global_position+Vector2(100,0)
	check(speedster._find_projectile_threat()!=null,"speedster predicts actual non-ball trajectory")
	threat_shot.queue_free()
	# Pre-motion driver catches a fast ungrouped/new-schema projectile without touching its script.
	for child:Node in API.candidates(self):
		if child.is_in_group("MagnetElectricBall"): child.queue_free()
	var fast:Node2D = shot("new_protocol",source,center+Vector2(-60,0))
	API.set_velocity(fast,Vector2(12000,0))
	reserve(collector,center)
	driver._physics_process(0.01)
	check(fast.is_queued_for_deletion() and collector.notes==0,"driver swept capture prevents fast/new projectile tunneling")
	collector.cargo.clear()
	collector.notes=0
	# Driver mirror intercept occurs before the projectile's own impact/retirement.
	var incoming:Node2D = shot("bolt",source,mirror.global_position+Vector2(60,0))
	API.set_velocity(incoming,Vector2(-620,0))
	mirror._reflect_active = true
	driver._physics_process(0.1)
	check(not incoming.is_queued_for_deletion() and API.owner_of(incoming)==mirror and API.velocity_of(incoming).x>0,"driver reflects before native arrow can expire")
	incoming.queue_free()
	# Authority and pause: no stolen/modified remote-owned projectile.
	var remote:Node2D = shot("bolt",source,center)
	remote.set_multiplayer_authority(2)
	check(CAP.describe(remote).is_empty() and not mirror.try_reflect_projectile(remote),"non-authority cannot capture or reflect")
	remote.queue_free()
	var paused:Node2D = shot("new_protocol",source,center+Vector2(-60,0))
	API.set_velocity(paused,Vector2(12000,0)); reserve(collector,center)
	game.now_stop_state = true
	driver._physics_process(0.01)
	check(not paused.is_queued_for_deletion() and collector.notes==1,"pause freezes shared interception")
	game.now_stop_state = false
	paused.queue_free()
	var skeleton:Node = load("res://scripts/effects/我的世界/骷髅箭.gd").new()
	check(API.is_projectile(skeleton),"flying skeleton arrow category")
	skeleton._mode = 1
	check(not API.is_projectile(skeleton) and CAP.describe(skeleton).is_empty(),"stuck arrow is terrain, not capturable projectile")
	skeleton._mode = 2
	check(not API.is_projectile(skeleton),"embedded arrow is status, not flying projectile")
	skeleton.free()
	var flame:Node = load("res://scripts/effects/我的世界/烈焰弹.gd").new()
	flame.configure(source,source.Team,Vector2.RIGHT,330.0,2.0,3.0,0.1,34.0,4.5,0.1,0.1)
	check(API.damage_kind_of(flame)=="fire" and API.damage_of(flame)==source.attack_damage(2.0),"blaze payload retains fire kind and source multiplier")
	flame.free()
	var sheep:Node2D = actor("羊",center)
	var fire_shot:Node2D = shot("new_protocol",source,center)
	fire_shot.set_meta("projectile_damage_kind","fire")
	var wool:Node = WOOL.new()
	world.add_child(wool)
	wool.setup(fire_shot,sheep)
	wool.set_physics_process(false)
	check(wool.damage_kind==&"fire","wool capture preserves fire damage rather than ordinary")
	fire_shot.queue_free(); wool.queue_free()
	print("CATEGORY_INTERACTIONS checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
