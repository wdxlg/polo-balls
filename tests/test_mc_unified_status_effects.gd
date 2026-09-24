extends SceneTree
## All 39 Java 1.21.4 effects; pure grade math AND real Witch/Wither/beacon
## application, source-local lifetimes, actual Buffs, immunity and tooltip.
## Keep the fixture self-contained: other sessions' New5 test harness is untracked.
var game:Node
var world:Node
var saved:Dictionary
var center:Vector2
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var catalog:GDScript

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MC_UNIFIED_STATUS_FAIL " + label)

func spawn(role:String,offset:Vector2,team:String = "Team0") -> Node2D:
	var path:String = "res://scenes/characters/我的世界/" + role + ".tscn" if not role.is_empty() else "res://scenes/ball.tscn"
	var packed:PackedScene = load(path) as PackedScene
	var actor:Node2D = packed.instantiate() as Node2D
	actor.set("Team",team)
	actor.position = center + offset
	world.add_child(actor,true)
	actor.get("state_machine").set_physics_process(false)
	actor.set("Has_Collision_Damage",false)
	return actor

func clear_units() -> void:
	for actor:Node in get_nodes_in_group("Ball"):
		if actor.get_parent() == world: actor.queue_free()
	await process_frame
	await physics_frame

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world) and is_instance_valid(world.get("_mc_prewarmer")):
		for resource_path:Variant in world._mc_prewarmer._paths.values():
			var load_status:int = ResourceLoader.load_threaded_get_status(str(resource_path))
			if load_status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(resource_path))
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)

func potency(kind:String,grade:int) -> Dictionary:
	return catalog.call("properties",kind,grade) as Dictionary

func has_amount(unit:Node2D,status:Node,key:String,amount:float) -> bool:
	var buffs:Dictionary = unit.Buff_Dic.get(status.get_instance_id(),{})
	var buff:Buff = buffs.get("MC效果_"+key) as Buff
	return buff != null and is_equal_approx(float(buff.amount),amount)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(55.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3,true,false,true).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	catalog = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	var witch_api:GDScript = load("res://scripts/effects/我的世界/女巫药水效果.gd") as GDScript
	var names:Array = catalog.call("all_kinds")
	check(names.size() == 39 and (names as Array).has("wind_charged") and (names as Array).has("trial_omen"),"exactly 39 effects from the 1.21.4 icon pack")
	var java_ids:Array = catalog.call("all_java_ids")
	check(java_ids.size() == 39 and java_ids.has("regeneration") and java_ids.has("instant_health") and not java_ids.has("regen"),"public catalog enumerates canonical 1.21.4 Java IDs")
	for raw:Variant in names:
		var kind:String = str(raw)
		var meta:Dictionary = catalog.call("info",kind)
		var tex:Texture2D = catalog.call("icon",kind) as Texture2D
		check(not str(meta.get("zh","")).is_empty() and not str(meta.get("en","")).is_empty() and tex != null and potency(kind,1).get("level",0) == 1 and potency(kind,2).get("level",0) == 2,"named/iconed two-grade status: "+kind)
	check(catalog.call("canonical","minecraft:regeneration") == "regen" and catalog.call("canonical","instant_health") == "instant_heal","Java IDs alias existing Witch IDs")
	check(is_equal_approx(float(potency("speed",1).move),1.2) and is_equal_approx(float(potency("speed",2).move),1.4) and is_equal_approx(float(potency("slowness",2).move),0.7),"Speed +20%/level and Slowness -15%/level")
	check(is_equal_approx(float(potency("haste",2).attack_rate),1.2) and is_equal_approx(float(potency("mining_fatigue",3).attack_rate),0.7),"Haste +10% attack rate/level and Mining Fatigue -10%/level")
	check(float(potency("strength",2).melee_damage) == 6.0 and float(potency("weakness",2).melee_damage) == -8.0,"Java additive +3 Strength / -4 Weakness per level")
	check(is_equal_approx(float(potency("resistance",2).damage_reduction),0.4) and float(potency("resistance",5).damage_reduction) == 1.0,"Resistance reduces incoming damage 20% per level to 100%")
	check(int(potency("health_boost",2).extra_health) == 8 and int(potency("absorption",2).absorption) == 8,"Health Boost and Absorption add four HP per level")
	check(float(potency("instant_heal",2).instant_health) == 8.0 and float(potency("instant_damage",2).instant_damage) == 12.0,"Java instant healing 4/8 HP, damage 6/12 HP")
	check(int(potency("regen",1).period_ticks) == 50 and int(potency("regen",3).period_ticks) == 12 and int(potency("poison",2).period_ticks) == 12 and int(potency("wither",2).period_ticks) == 20,"periodic amplifier shifts the 50/25/40-tick intervals")
	check(is_equal_approx(float(potency("levitation",2).upward_acceleration),0.1) and is_equal_approx(float(potency("hunger",2).exhaustion_per_tick),0.01),"Levitation and Hunger levels derive contextual potency")
	var wither:Node2D = spawn("凋零",Vector2(-160,-50))
	var witch:Node2D = spawn("女巫",Vector2(-190,85))
	var victim:Node2D = spawn("",Vector2(90,10),"Team1")
	for unit:Node2D in [wither,witch,victim]: unit.process_mode = Node.PROCESS_MODE_DISABLED
	# Independent durations, overlapping sources; exactly one effective status.
	wither.apply_beacon_buff("speed")
	var speed:Node = wither.get_node_or_null("MinecraftStatus_speed")
	check(speed != null and speed.level == 1 and has_amount(wither,speed,"speed_move",1.2),"beacon I creates the same 20% Speed Buff as every other source")
	witch_api.call("apply_effect",wither,"speed",witch,2,2.0)
	check(wither.get_node_or_null("MinecraftStatus_speed") == speed and speed.level == 2 and has_amount(wither,speed,"speed_move",1.4),"Witch II upgrades one shared speed node to +40%")
	var frame:MCPreviewTooltip = wither.get_node_or_null("Minecraft药水状态框") as MCPreviewTooltip
	check(frame != null and frame._potions[0].level == 2 and frame._shown_keys == PackedStringArray(["speed"]),"real status UI displays stronger level II only once")
	speed._physics_process(2.1)
	check(speed.level == 1 and speed.remaining > 3.0 and speed.remaining < 4.0 and has_amount(wither,speed,"speed_move",1.2),"expired Witch II re-exposes beacon I at its own remaining time")
	witch_api.call("apply_effect",wither,"speed",witch,1,9.0)
	wither.apply_beacon_buff("")
	check(speed != null and not speed.is_queued_for_deletion() and speed.remaining > 8.0 and has_amount(wither,speed,"speed_move",1.2),"beacon cancellation does not erase Witch's independent 9-second source")
	# A Wither skull and Witch's Wither bottle are the same lethal 1 HP/tick status.
	victim.Max_health = 1000
	victim.health = 1000
	witch_api.call("apply_effect",victim,"wither",witch)
	var dot:Node = victim.get_node_or_null("WitherStatus")
	wither.apply_wither(victim)
	check(dot != null and victim.get_node_or_null("WitherStatus") == dot and is_equal_approx(dot.remaining,6.5),"Witch and skull merge their Wither status without changing Witch duration")
	var before:int = victim.health
	dot._physics_process(2.0)
	check(before - victim.health == 1 and dot.remaining > 4.0,"same-level Wither is one flat HP per 40 ticks, not 2% of target max HP")
	var guard:Node2D = spawn("",Vector2(150,105),"Team1")
	guard.process_mode = Node.PROCESS_MODE_DISABLED
	guard.Max_health = 100
	guard.health = 100
	catalog.call("apply_effect",guard,"fire_resistance",1,9.0,witch)
	check(guard.is_fire_immune() and not guard.receive_fire_spatial_damage(25.0,{"shape":"all"},true,true) and guard.health == 100,"Fire Resistance suppresses actual fire damage, not just its icon")
	catalog.call("clear",guard,"fire_resistance",witch)
	check(not guard.is_fire_immune(),"ending Fire Resistance immediately restores the original fire ratio")
	catalog.call("apply_effect",guard,"water_breathing",2,12.0,witch)
	check(catalog.call("blocks_drowning",guard) and not guard.receive_spatial_raw_health_damage(4.0,{"shape":"all","element":"drowning"}) and guard.health == 100,"Water Breathing ignores tagged drowning damage without negating ordinary water attacks")
	check(guard.receive_spatial_raw_health_damage(3.0,{"shape":"all"}) and guard.health == 97,"Water Breathing does not grant general invulnerability")
	catalog.call("apply_effect",guard,"absorption",2,10.0,witch)
	var absorb:Node = guard.get_node_or_null("MinecraftStatus_absorption")
	guard.take_damage(5.0,true)
	check(absorb != null and guard.health == 97 and is_equal_approx(absorb.absorption_remaining,3.0),"Absorption II consumes 5 of its temporary 8 HP before health")
	guard.take_damage(7.0,true)
	check(guard.health == 93 and is_equal_approx(absorb.absorption_remaining,0.0),"remaining 3 absorption HP soak damage, 4 reaches actual health")
	# Every non-instant effect can be installed as a real status (including
	# effects whose native world features, e.g. villages, do not exist here).
	var shelf:Node2D = spawn("",Vector2(230,100),"Team1")
	shelf.process_mode = Node.PROCESS_MODE_DISABLED
	shelf.Max_health = 10000
	shelf.health = 10000
	var timed:int = 0
	for raw:Variant in names:
		var kind:String = str(raw)
		if catalog.call("is_instant",kind): continue
		timed += 1
		catalog.call("apply_effect",shelf,kind,2,13.0,witch)
		check(catalog.call("level_of",shelf,kind) == 2,"real, renewable level-II status exists: "+kind)
	var display:MCPreviewTooltip = shelf.get_node_or_null("Minecraft药水状态框") as MCPreviewTooltip
	check(display != null and display.get("_shown_keys").size() == timed and display._potions.size() == timed,"all 36 sustained statuses render unique, real level-II rows")
	shelf.velocity = Vector2(0.0,200.0)
	shelf.get_node("MinecraftStatus_slow_falling")._physics_process(0.016)
	check(shelf.velocity.y <= 40.0,"Slow Falling caps downward movement instead of boosting horizontal speed")
	catalog.call("apply_effect",guard,"resistance",2,6.0,witch)
	world.set_ball_properties_to_dafault([guard])
	world.figure_buffs(0.016,[guard])
	check(is_equal_approx(guard.Damage_reduction,0.4),"actual target Resistance II Buff gives 40% damage reduction")
	var health_before:int = guard.health
	guard.take_damage(10.0,true)
	check(health_before-guard.health == 6,"incoming 10 damage is reduced to 6 by level-II Resistance")
	catalog.call("apply_effect",guard,"health_boost",2,6.0,witch)
	world.set_ball_properties_to_dafault([guard])
	world.figure_buffs(0.016,[guard])
	check(guard.Max_health == int(guard.default_properties.get("Max_health",0))+8,"Health Boost II adds 8 HP to the real runtime max health")
	catalog.call("apply_effect",guard,"mining_fatigue",2,6.0,witch)
	var fatigue:Node = guard.get_node_or_null("MinecraftStatus_mining_fatigue")
	check(fatigue != null and has_amount(guard,fatigue,"mining_fatigue_attack",1.25),"Mining Fatigue II installs the same +25% attack cooldown on a real target")
	world.set_ball_properties_to_dafault([guard])
	world.figure_buffs(0.016,[guard])
	var base_cooldown:float = float(guard.default_properties.get("Attack_Cooling",0.0))
	check(base_cooldown > 0.0 and is_equal_approx(guard.Attack_Cooling,base_cooldown*1.25),"runtime combat attack rate really decreases when Mining Fatigue II is active")
	var event_victim:Node2D = spawn("",Vector2(300,80),"Team1")
	event_victim.process_mode = Node.PROCESS_MODE_DISABLED
	event_victim.Max_health = 100
	event_victim.health = 100
	for kind:String in ["oozing","weaving","wind_charged"]:
		catalog.call("apply_effect",event_victim,kind,2,15.0,witch)
	var spawn_before:int = get_nodes_in_group("MCStatusSpawn").size()
	var web_before:int = get_nodes_in_group("MCWeavingWeb").size()
	event_victim.health = 0
	var slime_available:bool = ResourceLoader.exists("res://scenes/creatures/我的世界/史莱姆_小.tscn")
	check((not slime_available or get_nodes_in_group("MCStatusSpawn").size() == spawn_before+2) and get_nodes_in_group("MCWeavingWeb").size() == web_before+3,"Weaving death places three webs; Oozing spawns two slimes only when its independent scene is installed")
	var web:Area2D = get_nodes_in_group("MCWeavingWeb")[0] as Area2D
	web.call("_entered",guard.get_node("hurtbox"))
	web.call("_physics_process",0.016)
	check(guard.Buff_Dic.has(web.get_instance_id()),"Web entry creates a real speed-slowing Buff")
	web.call("_exited",guard.get_node("hurtbox"))
	check(not guard.Buff_Dic.has(web.get_instance_id()),"Web exit clears its own slow without removing potion Buffs")
	print("MC_UNIFIED_STATUS_RESULT checks=",checks," failures=",failures)
	await finish(1 if failures > 0 else 0)
