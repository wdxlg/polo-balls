extends SceneTree
## Regressions for battling parasite parents and their spawned offspring.
## Long battle: godot --headless --path . --script res://tests/test_parasite_battle_errors.gd -- --battle-seconds=24
const PARENT_SCENE_PATH:String = "res://scenes/characters/杀戮尖塔/异蛙寄生虫.tscn"
const CHILD_SCRIPT_PATH:String = "res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd"
var game:Node
var world:Node
var saved:Dictionary
var checks:int = 0
var failures:int = 0
var spawned_children:int = 0
var finishing:bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition:bool,description:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PARASITE_BATTLE_FAIL " + description)

func spawn_parent(team:String,position:Vector2) -> Node2D:
	var actor:Node2D = (load(PARENT_SCENE_PATH) as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.position = position
	world.add_child(actor,true)
	return actor

func on_world_child_entered(child:Node) -> void:
	if child.get_script() != null and str(child.get_script().resource_path) == CHILD_SCRIPT_PATH:
		spawned_children += 1

func finish(code:int) -> void:
	if finishing:
		return
	finishing = true
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world):
		world.queue_free()
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
	create_timer(65.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	world.child_entered_tree.connect(on_world_child_entered)
	await create_timer(0.2,true,false,true).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var a:Node2D = spawn_parent("Team0",center+Vector2(-90,-60))
	var b:Node2D = spawn_parent("Team0",center+Vector2(-90,60))
	var c:Node2D = spawn_parent("Team1",center+Vector2(90,-60))
	var d:Node2D = spawn_parent("Team1",center+Vector2(90,60))
	check(is_instance_valid(a) and is_instance_valid(b) and is_instance_valid(c) and is_instance_valid(d),"four parasite parents spawn on opposing teams")

	# A spatial skill without enchant metadata must deal damage without logging
	# a missing-meta error; explicit elemental context must not leak to later hits.
	check(not a.has_meta("_mc_enchant_element"),"target starts without enchantment element metadata")
	var hp:int = a.health
	var accepted:bool = a.receive_spatial_damage(5.0,{"point":a.global_position,"element":"explosion","source":c},true)
	check(accepted and a.health < hp,"ordinary spatial damage is applied")
	check(not a.has_meta("_mc_enchant_element"),"temporary explosion element does not leak")
	a.set_meta("_mc_enchant_element","fire")
	a.receive_spatial_damage(3.0,{"point":a.global_position,"element":"projectile","source":c},true)
	check(a.get_meta("_mc_enchant_element") == "fire","previous element survives a typed spatial hit")
	a.remove_meta("_mc_enchant_element")
	a.receive_spatial_damage(2.0,a.global_position,true)
	check(not a.has_meta("_mc_enchant_element"),"untyped spatial damage also leaves metadata clear")

	# Enemy references can expire between World target selection and skill/death
	# spawning. A dead nearest-enemy reference must never be copied into a child.
	var stale:Node = Node.new()
	a.Target_Enemy = null
	a.Nearest_Enemy = stale
	stale.free()
	var child:Node = a.create_newbug(world.return_now_map_border())
	check(is_instance_valid(child) and child.is_inside_tree(),"stale nearest target does not prevent child creation")
	if is_instance_valid(child):
		check(child.Target_Enemy == null or is_instance_valid(child.Target_Enemy),"new child never inherits a freed enemy")

	var stale_direct:Node = Node.new()
	a.Target_Enemy = stale_direct
	stale_direct.free()
	a.Nearest_Enemy = c
	var replacement:Node = a.create_newbug(world.return_now_map_border())
	check(is_instance_valid(replacement) and replacement.Target_Enemy == c,"freed primary target falls back to a living nearest enemy")

	var queued:Node = Node.new()
	world.add_child(queued)
	a.Target_Enemy = queued
	queued.queue_free()
	a.Nearest_Enemy = c
	var queued_replacement:Node = a.create_newbug(world.return_now_map_border())
	check(is_instance_valid(queued_replacement) and queued_replacement.Target_Enemy == c,"queued-for-deletion primary target is not inherited")
	var queued_nearest:Node = Node.new()
	world.add_child(queued_nearest)
	a.Target_Enemy = null
	a.Nearest_Enemy = queued_nearest
	queued_nearest.queue_free()
	var nearest_replacement:Node = a.create_newbug(world.return_now_map_border())
	check(is_instance_valid(nearest_replacement) and nearest_replacement.Target_Enemy == null,"queued-for-deletion nearest target is not inherited")

	# Finish with real authoritative skills and several seconds of nearby
	# opposing parents to exercise spawn, collision, infection and retargeting.
	a.Target_Enemy = c
	a.Nearest_Enemy = c
	a.Skill()
	c.Skill()
	check(spawned_children >= 2,"two parents produce offspring via their real skill")
	var before_death_spawns:int = spawned_children
	var expired:Node = Node.new()
	b.Target_Enemy = expired
	b.Nearest_Enemy = expired
	expired.free()
	b.Die()
	check(spawned_children >= before_death_spawns+4,"dying parent produces four offspring even with stale targets")
	var battle_seconds:float = 4.0
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--battle-seconds="):
			battle_seconds = clampf(float(arg.trim_prefix("--battle-seconds=")),4.0,28.0)
	await create_timer(battle_seconds,true,false,true).timeout
	check(spawned_children >= 4,"four-parent battle continues spawning offspring")
	print("PARASITE_BATTLE_RESULT checks=",checks," failures=",failures," offspring=",spawned_children," battle_seconds=",battle_seconds)
	await finish(1 if failures > 0 else 0)
