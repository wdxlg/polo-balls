extends "res://tests/test_mc_frontier.gd"
const CC = preload("res://classes/combat_classification.gd")
const REG = preload("res://classes/combat_classification_catalog.gd")
var scene_count:int = 0

func walk_scenes(folder:String) -> void:
	var dir:DirAccess = DirAccess.open(folder)
	check(dir != null,"scene directory "+folder)
	if dir == null: return
	for file:String in dir.get_files():
		if not file.ends_with(".tscn"): continue
		var path:String = folder.path_join(file)
		scene_count += 1
		check(REG.SCENES.has(path),"registered scene "+path)
	for sub:String in dir.get_directories(): walk_scenes(folder.path_join(sub))

func registry_checks() -> void:
	for folder:String in ["res://scenes","res://ui","res://global"]: walk_scenes(folder)
	for path:String in REG.SCENES:
		check(ResourceLoader.exists(path),"scene resource exists "+path)
		check(CC.ENTITY_KINDS.has(REG.SCENES[path].entity_kind),"scene kind valid "+path)
		# Do not call _ready(): this checks classification of real instantiated
		# scenes, not 224 characters' live combat behavior.
		if path.begins_with("res://scenes/characters/") or path.begins_with("res://scenes/shooter/") or path.begins_with("res://scenes/creatures/"):
			var scene:PackedScene = load(path)
			var node:Node = scene.instantiate()
			var profile:Dictionary = CC.profile_of(node)
			check(profile.registered and CC.ENTITY_KINDS.has(profile.entity_kind),"instance registered "+path)
			if path.begins_with("res://scenes/characters/"):
				check(profile.entity_kind=="character","selectable form remains character "+path)
			node.free()
	for path:String in REG.SCRIPTS:
		check(ResourceLoader.exists(path),"script resource exists "+path)
		check(CC.ENTITY_KINDS.has(REG.SCRIPTS[path].entity_kind),"script kind valid "+path)
		for mode:String in REG.SCRIPTS[path].get("attack_modes",[]): check(CC.ATTACK_MODES.has(mode),"valid attack mode "+path)
		for carrier:String in REG.SCRIPTS[path].get("carriers",[]): check(CC.CARRIERS.has(carrier),"valid carrier "+path)
	var fire:Node = load("res://scripts/effects/我的世界/烈焰弹.gd").new()
	check(CC.is_projectile(fire),"dynamic Node2D fireball is a projectile before ready")
	fire.free()
	var blast:Node = load("res://scripts/effects/我的世界/mc_explosion.gd").new()
	check(CC.profile_of(blast).entity_kind=="visual" and not CC.is_projectile(blast),"explosion visual is not a projectile or damage element")
	blast.free()
	var wall:StaticBody2D = StaticBody2D.new()
	check(CC.profile_of(wall).entity_kind=="obstacle","engine-created map wall is an obstacle")
	wall.free()
	var scriptless:Node2D = Node2D.new()
	check(not CC.profile_of(scriptless).registered,"unknown empty object is not silently a normal-damage actor")
	scriptless.free()
	var rock:Node = load("res://scenes/shooter/凑企鹅石头.tscn").instantiate()
	rock.add_to_group("CouPenguinRock")
	rock.set("flying",true)
	check(CC.is_projectile(rock),"rock flying stage is a projectile")
	rock.set("flying",false)
	check(not CC.is_projectile(rock) and CC.profile_of(rock).entity_kind=="obstacle","rock landing immediately changes identity without stale cache")
	rock.free()
	var banana:Node = load("res://scripts/shooter/clown/clown_area_object.gd").new()
	banana.object_mode = 0
	check(not CC.is_projectile(banana) and CC.profile_of(banana).entity_kind=="terrain","banana trap is not a projectile despite shooter directory")
	banana.object_mode = 1
	check(CC.is_projectile(banana),"same component in confetti mode is a projectile")
	banana.free()
	var bare:Node = load("res://classes/ball.gd").new()
	bare.Type = 1
	check(CC.is_projectile(bare),"dynamic bare ball uses explicit runtime Type")
	bare.Type = 3
	check(CC.profile_of(bare).entity_kind=="subentity","dynamic bare ball can become subentity")
	bare.free()

func run() -> void:
	registry_checks()
	var center:Vector2 = await setup_world()
	create_timer(90.0).timeout.connect(func():finish(2))
	var victim:Node2D = dummy(center)
	victim.Damage_reduction = 0
	victim.block = 0
	for kind:String in ["fire","cold"]:
		for ratio:float in [0.0,0.5,1.0,2.0]:
			victim.set("fire_effect_ratio" if kind=="fire" else "cold_effect_ratio",ratio)
			for raw:bool in [false,true]:
				var before:float = victim.health
				var space:Dictionary = {"point":center,"damage_kind":kind,"carrier":"area"}
				var saved:Dictionary = space.duplicate(true)
				victim.receive_spatial_damage(20.0,space,raw,raw)
				check(before-victim.health==20.0*ratio,"typed "+kind+" ratio="+str(ratio)+" raw="+str(raw))
				check(space==saved and not victim.has_meta("_blood_damage_element") and not victim.has_meta("_classified_damage_space"),"context copy and metadata cleanup "+kind)
	victim.fire_effect_ratio = 0.0
	var hp:float = victim.health
	victim.receive_positional_damage(20.0,center,false,null)
	check(hp-victim.health==20.0,"fire immunity does not block ordinary melee/impact")
	for kind:String in ["poison","wither","magic"]:
		hp = victim.health
		victim.receive_spatial_raw_health_damage(10.0,{"point":center,"damage_kind":kind,"carrier":"status_tick"})
		check(hp-victim.health==10.0,"typed status retains damage independently of fire immunity "+kind)
	hp = victim.health
	check(not victim.receive_classified_positional_damage(10.0,center,&"unreviewed_acid"),"unknown damage kind rejected")
	check(not victim.receive_spatial_damage(10.0,{"damage_kind":"ordinary","element":"fire"}),"contradictory known kind and element rejected")
	check(not victim.receive_classified_positional_damage(INF,center,&"fire") and victim.health==hp,"invalid classified amount rejected")
	victim.fire_effect_ratio = 1.0
	victim.set_multiplayer_authority(2)
	check(not victim.receive_fire_positional_damage(10.0,center) and victim.health==hp,"non-authority cannot settle classified damage")
	victim.set_multiplayer_authority(1)
	victim.set_meta("_blood_damage_element","prior_sentinel")
	victim.receive_fire_positional_damage(10.0,center)
	check(victim.get_meta("_blood_damage_element")=="prior_sentinel","prior nested metadata restored")
	victim.remove_meta("_blood_damage_element")
	victim.max_block = 100
	victim.block = 50
	hp = victim.health
	victim.receive_fire_positional_damage(20.0,center)
	check(victim.health==hp and victim.block==30,"fire preserves ordinary block policy")
	var internal_before:float = victim.health
	victim.receive_internal_status_damage(7.0,&"bleed")
	check(internal_before-victim.health==7.0 and victim.block==30,"explicit legacy internal bleed preserves block bypass")
	check(victim.receive_internal_status_damage(7.0,&"fire")==0.0,"internal status route cannot smuggle fire past immunity")
	victim.block = 0
	# Live status immunity, not merely a potion source/icon.
	var effects:GDScript = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	effects.apply_effect(victim,"fire_resistance",1,5.0,victim)
	hp = victim.health
	check(not victim.receive_fire_positional_damage(20.0,center) and victim.health==hp,"active fire-resistance potion rejects typed fire")
	effects.clear(victim,"fire_resistance")
	# Every boat member applies its own multiplier once, after the split.
	var boat:Node2D = actor("木船",center+Vector2(100,0))
	boat.Max_health = 10000
	boat.health = 10000
	boat.block = 0
	boat.Damage_reduction = 0
	boat.fire_effect_ratio = 2.0
	victim.fire_effect_ratio = 0.5
	boat._attach_passenger(victim,0)
	var boat_hp:float = boat.health
	hp = victim.health
	boat.receive_fire_positional_damage(60.0,center,false,null)
	check(boat_hp-boat.health==60.0 and hp-victim.health==15.0,"unscaled 60 splits 30/30 then independent 2x/0.5x fire")
	# Mixed components from the same source in one frame must not deduplicate
	# one another when they initially contact different members of the boat.
	var source:Node2D = dummy(center+Vector2(250,0),"Team0")
	boat.fire_effect_ratio = 1.0
	victim.fire_effect_ratio = 0.0
	boat_hp = boat.health
	hp = victim.health
	boat.receive_positional_damage(60.0,center,false,source)
	victim.receive_fire_positional_damage(60.0,center,false,source)
	check(boat_hp-boat.health==60.0 and hp-victim.health==30.0,"boat deduplication preserves distinct ordinary/fire components")
	boat.release_all()
	var probe:Node2D = load("res://scenes/ball.tscn").instantiate()
	probe.set_script(load("res://tests/combat_classification_probe.gd"))
	world.add_child(probe,true)
	probe.state_machine.set_physics_process(false)
	probe.set_physics_process(false)
	probe.Max_health = 10000
	probe.health = 10000
	probe.block = 0
	probe.Damage_reduction = 0.0
	probe.fire_effect_ratio = 0.5
	probe.nested_damage = 20.0
	hp = probe.health
	probe.receive_fire_positional_damage(30.0,center)
	check(hp-probe.health==25.0 and probe.seen_kinds==["fire","fire"],"nested same-element hit has its own scaling and kind")
	check(not probe.has_meta("_combat_damage_kind") and not probe.has_meta("_classified_damage_space"),"nested envelopes fully restore metadata")
	probe.spatial_calls = 0
	probe.spatial_ratio = 0.5
	hp = probe.health
	probe.receive_spatial_damage(20.0,{"element":"fire","point":center})
	check(hp-probe.health==5.0 and probe.spatial_calls==1,"generic typed space applies derived spatial defense once")
	probe.spatial_calls = 0
	hp = probe.health
	probe.receive_fire_spatial_damage(20.0,{"point":center})
	check(hp-probe.health==5.0 and probe.spatial_calls==1,"legacy fire wrapper applies derived spatial defense once")
	print("CLASSIFICATION_FULL scenes=",scene_count," scripts=",REG.SCRIPTS.size()," checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
