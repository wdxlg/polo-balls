extends SceneTree
## 出界倒数只保留内部计时与淘汰，不在角色身旁生成红字。

var checks:int = 0
var failures:int = 0
var finishing:bool = false
var world:Node
var game:Node
var saved_settings:Dictionary
var saved_stop:bool
var saved_mute:bool

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,description:String) -> void:
	checks += 1
	if ok:
		print("OOB_NO_TEXT_PASS ",description)
	else:
		failures += 1
		push_error("OOB_NO_TEXT_FAIL "+description)

func direct_label_count(parent:Node) -> int:
	var count:int = 0
	for child:Node in parent.get_children():
		if child is Label:
			count += 1
	return count

func run() -> void:
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	saved_mute = AudioServer.is_bus_mute(0)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(35.0).timeout.connect(func(): finish(2))

	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.out_of_bounds_death_delay = 3.0
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var inside:Vector2 = bounds.get_center()
	var outside:Vector2 = Vector2(bounds.end.x + 180.0,inside.y)

	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.Team = "Team0"
	unit.Can_Attack = false
	unit.Can_Skill = false
	world.add_child(unit)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.global_position = outside
	var initial_health:float = unit.health
	var initial_labels:int = direct_label_count(world)
	var id:int = unit.get_instance_id()
	check(initial_health > 0.0,"fixture is a living character outside the map")
	check(not world.map_contains_point(outside,world.map_island_rects(world.map_group["Map50x50"])),"fixture really starts out of bounds")

	world._process_out_of_bounds_rule(0.2,[unit])
	var entry:Dictionary = world._out_of_bounds_states.get(id,{})
	check(entry.has("elapsed") and is_equal_approx(float(entry.get("elapsed",-1.0)),0.2),"out-of-bounds time still starts")
	check(not entry.has("label") and not entry.has("shown") and direct_label_count(world) == initial_labels,"no red number Label is created")
	world._process_out_of_bounds_rule(1.0,[unit])
	check(is_equal_approx(float(world._out_of_bounds_states[id].get("elapsed",-1.0)),1.2) and unit.health == initial_health,"timer advances without premature elimination")
	check(direct_label_count(world) == initial_labels,"timer updates without showing red digits")

	var screenshot_path:String = OS.get_environment("OOB_NO_TEXT_SCREENSHOT")
	if not screenshot_path.is_empty() and DisplayServer.get_name() != "headless":
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.global_position = outside - Vector2(145.0,0.0)
		camera.zoom = Vector2.ONE * 1.5
		camera.make_current()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(screenshot_path) == OK,"GPU frame saved with character outside the map")

	unit.global_position = inside
	world._process_out_of_bounds_rule(0.1,[unit])
	check(not world._out_of_bounds_states.has(id) and unit.health == initial_health,"returning inside cancels the invisible countdown")

	unit.global_position = outside
	unit.set_meta(&"submission_allow_map_escape",true)
	world._process_out_of_bounds_rule(4.0,[unit])
	check(not world._out_of_bounds_states.has(id) and unit.health == initial_health,"intentional escape exemption remains intact")
	unit.remove_meta(&"submission_allow_map_escape")

	world._process_out_of_bounds_rule(0.2,[unit])
	world.out_of_bounds_enabled = false
	world._process_out_of_bounds_rule(0.2,[unit])
	check(not world._out_of_bounds_states.has(id) and unit.health == initial_health,"disabling rule clears its timer")
	world.out_of_bounds_enabled = true

	world._process_out_of_bounds_rule(0.2,[unit])
	world._process_out_of_bounds_rule(2.9,[unit])
	check(unit.health <= 0.0 and bool(unit.get_meta(&"__out_of_bounds_forced_death",false)),"three-second out-of-bounds elimination still occurs")
	check(not world._out_of_bounds_states.has(id) and direct_label_count(world) == initial_labels,"elimination clears timer without text")
	finish(0 if failures == 0 else 1)

func finish(code:int) -> void:
	if finishing:
		return
	finishing = true
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	AudioServer.set_bus_mute(0,saved_mute)
	if is_instance_valid(world):
		world.queue_free()
	current_scene = null
	await process_frame
	print("OOB_NO_TEXT_RESULT checks=",checks," failures=",failures)
	quit(code)
