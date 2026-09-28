extends "res://tests/test_mc_unified_status_effects.gd"
## Witch-specific upgrade policy; the canonical fixed-level API is unchanged.
var witch_api:Script
var bottle_script:Script
var cloud_script:Script

func clear_effects(unit:Node2D) -> void:
	for kind:String in catalog.all_kinds(): catalog.clear(unit,kind)
func stop_statuses(unit:Node2D) -> void:
	for kind:String in catalog.all_kinds():
		var status:Node = catalog.current(unit,kind)
		if is_instance_valid(status): status.set_physics_process(false)
func launch_hit(caster:Node2D,victim:Node2D,kind:String) -> int:
	var hp:int = victim.health
	var bottle:Node2D = bottle_script.new()
	world.add_child(bottle)
	bottle.setup(victim.global_position,victim.global_position,kind,caster)
	bottle.set_physics_process(false)
	bottle._physics_process(0.0)
	check(bottle._exploded,"real bottle contact shatters once")
	for child:Node in world.get_children():
		if child.get_script()==cloud_script: child.set_physics_process(false)
	return hp-victim.health

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3,true,false,true).timeout
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.set_physics_process(false)
	catalog = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	witch_api = load("res://scripts/effects/我的世界/女巫药水效果.gd")
	bottle_script = load("res://scripts/effects/我的世界/女巫药水.gd")
	cloud_script = load("res://scripts/effects/我的世界/女巫药水区域.gd")
	var witch:Node2D = spawn("女巫",Vector2(-220,0))
	var target:Node2D = spawn("",Vector2.ZERO,"Team1")
	var other:Node2D = spawn("",Vector2(220,0),"Team2")
	target.Max_health = 10000
	target.default_properties.Max_health = 10000
	target.health = 9000
	witch.Damage = 20
	for kind:String in ["regen","poison","wither","invisibility","speed","strength","slowness"]:
		clear_effects(target)
		witch_api.apply_stacking_effect(target,kind,witch)
		check(catalog.level_of(target,kind)==1,kind+" first application is level 1")
		var original_status:Node = catalog.current(target,kind)
		witch_api.apply_stacking_effect(target,kind,witch)
		check(catalog.level_of(target,kind)==2,kind+" repeated application upgrades to level 2")
		check(catalog.current(target,kind)==original_status,kind+" upgrades one canonical node, no duplicate status")
		check(float(original_status.remaining)>0.0,kind+" retains its lifetime")
		if kind in ["regen","poison"]: check(is_inf(original_status.remaining),kind+" retains infinite duration")
		stop_statuses(target)
	clear_effects(target)
	witch_api.apply_stacking_effect(target,"speed",witch)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(has_amount(target,catalog.current(target,"speed"),"speed_move",1.4),"speed II changes actual movement Buff to 1.4")
	witch_api.apply_stacking_effect(target,"strength",witch)
	witch_api.apply_stacking_effect(target,"strength",witch)
	check(has_amount(target,catalog.current(target,"strength"),"strength_damage",1.2),"strength II changes actual damage Buff to 1.2")
	check(catalog.level_of(target,"speed")==2,"a different potion does not upgrade speed")
	clear_effects(target)
	catalog.apply_effect(target,"wither",2,10.0,other)
	catalog.apply_effect(target,"weakness",8,10.0,other)
	witch_api.apply_stacking_effect(target,"wither",witch)
	check(catalog.level_of(target,"wither")==3 and catalog.level_of(target,"weakness")==9,"Wither and its Weakness each upgrade their own effective level")
	clear_effects(target)
	catalog.apply_effect(target,"speed",254,8.0,other)
	witch_api.apply_stacking_effect(target,"speed",witch)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(catalog.level_of(target,"speed")==255,"upgrades stop at shared level 255 cap")
	clear_effects(target)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(catalog.level_of(target,"speed")==1,"cleared effect restarts at level 1")
	clear_effects(target)
	catalog.apply_effect(target,"speed",4,0.01,other)
	catalog.current(target,"speed")._physics_process(0.02)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(catalog.level_of(target,"speed")==1,"expired queued status restarts at level 1 with the canonical name")
	clear_effects(target)
	catalog.apply_effect(target,"speed",5,2.0,other)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(catalog.level_of(target,"speed")==6,"upgrade is based on effective grade across sources")
	catalog.clear(target,"speed",witch)
	check(catalog.level_of(target,"speed")==5,"removing Witch source restores independent older source")
	clear_effects(target)
	witch_api.apply_effect(target,"invisibility",other)
	witch_api.apply_effect(target,"invisibility",other)
	check(catalog.level_of(target,"invisibility")==1,"fixed-level wrapper used by Trader does not begin stacking")
	clear_effects(target)
	target.minecraft_potion_negative_effect_ratio = 0.0
	witch_api.apply_stacking_effect(target,"poison",witch)
	witch_api.apply_stacking_effect(target,"wither",witch)
	check(catalog.level_of(target,"poison")==0 and catalog.level_of(target,"wither")==0 and catalog.level_of(target,"weakness")==0,"potion immunity blocks levels and extra Weakness")
	target.minecraft_potion_negative_effect_ratio = 1.0
	target.set_multiplayer_authority(2)
	witch_api.apply_stacking_effect(target,"speed",witch)
	check(catalog.level_of(target,"speed")==0,"non-authoritative receiver cannot locally upgrade")
	target.set_multiplayer_authority(1)
	clear_effects(witch)
	witch._finish_drink_effect("speed")
	witch._finish_drink_effect("speed")
	check(catalog.level_of(witch,"speed")==2,"actual drink completion upgrades beneficial potion")
	stop_statuses(witch)
	clear_effects(target)
	target.health = 9000
	check(launch_hit(witch,target,"speed")==30,"bottle deals 30 direct damage at Witch's base attack 20")
	check(catalog.level_of(target,"speed")==1,"direct contact applies first potion grade")
	check(launch_hit(witch,target,"speed")==30 and catalog.level_of(target,"speed")==2,"second bottle independently adds one grade and 30 impact")
	var cloud:Node2D = cloud_script.new()
	world.add_child(cloud)
	cloud.setup("speed",witch,64.0,5.2)
	cloud.global_position = target.global_position
	cloud.set_physics_process(false)
	cloud.particle_interval = 999.0
	cloud._particle_left = 999.0
	cloud._physics_process(0.99)
	check(catalog.level_of(target,"speed")==2,"cloud does not upgrade before first one-second pulse")
	cloud._physics_process(0.02)
	check(catalog.level_of(target,"speed")==3,"first cloud pulse upgrades level")
	cloud._physics_process(1.0)
	check(catalog.level_of(target,"speed")==4,"standing in same cloud upgrades again each second")
	cloud._physics_process(1.0)
	check(catalog.level_of(target,"speed")==5,"third pulse continues upgrading the same status")
	var level_before:int = catalog.level_of(target,"speed")
	target.global_position += Vector2(100,0)
	cloud._apply_to_units_in_radius()
	check(catalog.level_of(target,"speed")==level_before,"outside cloud does not gain levels")
	target.global_position = center
	clear_effects(target)
	var hp:int = target.health
	witch_api.apply_stacking_effect(target,"instant_heal",witch)
	witch_api.apply_stacking_effect(target,"instant_heal",witch)
	check(target.health==hp+100 and catalog.level_of(target,"instant_heal")==0,"instant healing stays two level-I pulses without a permanent grade counter")
	hp = target.health
	witch_api.apply_stacking_effect(target,"instant_damage",witch)
	witch_api.apply_stacking_effect(target,"instant_damage",witch)
	check(target.health==hp-100 and catalog.level_of(target,"instant_damage")==0,"instant damage stays two level-I pulses without a permanent grade counter")
	check(launch_hit(witch,target,"instant_damage")==80,"instant-damage bottle keeps 50 potion effect separate from 30 impact")
	witch.Damage = 40
	check(launch_hit(witch,target,"speed")==60,"impact scales with current attack, not a hard-coded final 30")
	var probe:Node2D = bottle_script.new()
	world.add_child(probe)
	probe.setup(center+Vector2(0,200),center+Vector2(0,220),"speed",witch)
	probe.set_physics_process(false)
	var interactions:Script = load("res://classes/projectile_interactions.gd")
	check(interactions.damage_of(probe)==60.0,"shared projectile descriptor uses native live damage instead of legacy 50")
	witch.Damage = 20
	check(probe.get_projectile_damage()==30.0 and interactions.damage_of(probe)==30.0,"descriptor follows current source attributes")
	probe.queue_free()
	var orphan:Node2D = bottle_script.new()
	world.add_child(orphan)
	other.Damage = 40
	orphan.setup(center,center,"speed",other)
	orphan.set_physics_process(false)
	other.free()
	check(orphan.get_projectile_damage()==60.0,"freed caster safely retains launch damage snapshot")
	orphan.queue_free()
	print("WITCH POTION UPGRADE: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
