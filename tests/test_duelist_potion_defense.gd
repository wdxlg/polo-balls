extends SceneTree
## Duelist's weakspot gate must preserve the shared Minecraft defense rules.
var world:Node
var game:Node
var saved:Dictionary
var catalog:GDScript
var checks:int = 0
var failures:int = 0
var finishing:bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DUELIST_POTION_FAIL " + label)

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world) and is_instance_valid(world.get("_mc_prewarmer")):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int = ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(path))
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3,true,false,true).timeout
	catalog = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	var packed:PackedScene = load("res://scenes/characters/人物/决斗者.tscn") as PackedScene
	check(packed != null,"Duelist scene loads")
	if packed == null:
		await finish(1)
		return
	var duel:Node2D = packed.instantiate() as Node2D
	duel.Team = "Team0"
	duel.position = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.add_child(duel,true)
	duel.state_machine.set_physics_process(false)
	duel.process_mode = Node.PROCESS_MODE_DISABLED
	duel.Has_Collision_Damage = false
	duel.health = duel.Max_health
	check(bool(catalog.call("apply_effect",duel,"absorption",2,15.0)),"Absorption II installs on Duelist")
	var status:Node = duel.get_node_or_null("MinecraftStatus_absorption")
	check(status != null and is_equal_approx(float(status.get("absorption_remaining")),40.0),"Duelist gains 40 temporary HP")
	var initial_health:int = duel.health
	duel.receive_spatial_raw_health_damage(10.0,{"shape":"all","point":duel.global_position})
	check(duel.health == initial_health and is_equal_approx(float(status.get("absorption_remaining")),30.0),"raw weakspot hit consumes absorption before real health")
	check(bool(catalog.call("apply_effect",duel,"water_breathing",1,15.0)),"Water Breathing installs on Duelist")
	duel.receive_spatial_raw_health_damage(8.0,{"shape":"all","element":"drowning"})
	check(duel.health == initial_health and is_equal_approx(float(status.get("absorption_remaining")),30.0),"drowning immunity preserves both real and temporary HP")
	duel.receive_spatial_raw_health_damage(35.0,{"shape":"all"})
	check(duel.health == initial_health-5 and is_equal_approx(float(status.get("absorption_remaining")),0.0),"raw overflow charges only the health beyond remaining absorption")
	check(bool(catalog.call("apply_effect",duel,"fire_resistance",1,15.0)),"Fire Resistance installs on Duelist")
	var before_fire:int = duel.health
	check(not duel.receive_fire_spatial_damage(12.0,{"shape":"all"},true,true) and duel.health == before_fire,"fire-specific entry point rejects incoming fire")
	print("DUELIST_POTION_RESULT checks=",checks," failures=",failures)
	await finish(1 if failures > 0 else 0)
