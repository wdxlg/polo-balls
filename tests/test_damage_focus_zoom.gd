extends SceneTree
## Real hit -> World focus request -> live Camera2D zoom, including overkill.

var game:Node
var world:Node
var checks:int = 0
var failures:int = 0
const EVIDENCE:String = "user://recordings/damage_focus_zoom/"

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",label)
	else:
		failures += 1
		push_error("DAMAGE_FOCUS_FAIL "+label)

func spawn_character(hp:int,team:String) -> Node2D:
	var actor:Node2D = load("res://scenes/ball.tscn").instantiate()
	actor.Max_health = hp
	actor.Team = team
	actor.position = world.return_map_world_rect(world._current_map_node()).get_center() + Vector2(22 if team == "B" else -22,0)
	world.add_child(actor,true)
	actor.Can_Attack = false
	actor.Can_Skill = false
	actor.Has_Collision_Damage = false
	actor.self_hitbox.monitoring = false
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	return actor

func hit_case(label:String,max_health:int,damage:float,expected:bool,immune:bool = false,shielded:bool = false) -> void:
	var target:Node2D = spawn_character(max_health,"B")
	if immune: target.Damage_reduction = 1.0
	if shielded:
		target.max_block = 200
		target.block = 200
	world._release_heavy_hitstop()
	world._damage_focus_pending_strength = -1.0
	world._damage_focus_started_usec = 0
	world._damage_focus_next_usec = 0
	world._damage_focus_weight = 0.0
	world._damage_focus_peak_zoom = 1.0
	world._apply_camera_zoom()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base_zoom:float = world.camera_2d.zoom.x
	check(world.is_combat_runtime_active() and world._impact_is_on_screen(target.global_position),label+": real combat and visible target")
	target.take_damage(damage,not shielded)
	var pending:float = world._damage_focus_pending_strength
	var remaining:int = target.health
	var maximum_zoom:float = base_zoom
	var maximum_weight:float = 0.0
	var captured:bool = false
	for frame:int in range(45):
		await RenderingServer.frame_post_draw
		maximum_zoom = maxf(maximum_zoom,world.camera_2d.zoom.x)
		maximum_weight = maxf(maximum_weight,world._damage_focus_weight)
		if expected and not captured and world.camera_2d.zoom.x > base_zoom * 1.045:
			root.get_texture().get_image().save_png(EVIDENCE+label+".png")
			captured = true
	print("DAMAGE_FOCUS_FRAME ",label," damage=",damage," hp=",max_health," left=",remaining,
		" requested=",pending," baseline=",base_zoom," peak=",maximum_zoom," weight=",maximum_weight)
	if expected:
		check(pending >= 0.0,label+": confirmed high damage queues the real focus")
		check(maximum_zoom > base_zoom * 1.045 and maximum_weight > 0.1 and captured,label+": GPU frame shows a real camera push-in")
	else:
		check(pending < 0.0,label+": ineffective or small hit never queues focus")
		check(maximum_zoom <= base_zoom * 1.01 and maximum_weight < 0.01,label+": no false camera push-in")
	if is_instance_valid(target) and not target.is_queued_for_deletion(): target.queue_free()
	await process_frame

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): push_error("DAMAGE_FOCUS_TIMEOUT");quit(2))
	game = root.get_node("Game")
	var saved_settings:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Map_Background = "blue"
	game.now_stop_state = false
	root.size = Vector2i(540,960)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.hide()
	world.set_physics_process(false)
	var attacker:Node2D = spawn_character(200,"A")
	await create_timer(0.2,true,false,true).timeout
	check(world.damage_focus_enabled,"high-damage camera focus is enabled")
	await hit_case("ordinary_100_on_200",200,100.0,true)
	await hit_case("overkill_100_on_20",20,100.0,true)
	await hit_case("tank_100_on_1000",1000,100.0,true)
	await hit_case("small_10_on_200",200,10.0,false)
	await hit_case("immune_200_on_200",200,200.0,false,true)
	await hit_case("shield_100_on_200",200,100.0,false,false,true)
	if is_instance_valid(attacker): attacker.queue_free()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	print("DAMAGE_FOCUS_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
