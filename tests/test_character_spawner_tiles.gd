extends SceneTree
const ENTRY = preload("res://classes/character_spawn_entry.gd")
var failures:int = 0
var checks:int = 0
var game:Node
var world:Node
var layer:TileMapLayer
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
# 只修改测试进程内的实例；不依赖或改写用户已绘制的方块、角色表和 Inspector 配置。
func disable_authored_spawners(node:Node) -> void:
	if node.has_method("is_character_spawn_layer"): node.spawning_enabled = false
	for child:Node in node.get_children(): disable_authored_spawners(child)

func run() -> void:
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	disable_authored_spawners(world)
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	var map:Node = world.map_group.Map_Portal
	layer = load("res://addons/character_spawner/character_spawner_tiles.gd").new()
	layer.name = "SpawnerRegressionFixture"
	map.add_child(layer)
	layer.set_physics_process(false)
	check(layer.is_character_spawn_layer(),"dedicated paintable spawn layer is available")
	check(layer.get_used_cells().is_empty(),"new component starts empty independently of authored map edits")
	check(not layer.collision_enabled and not layer.navigation_enabled and not layer.occlusion_enabled,"spawn tiles have no terrain physics/navigation/occlusion")
	check(layer.resolved_map_name()=="Map_Portal","layer binds to its owning map automatically")
	var exposes_target_override:bool = false
	for property:Dictionary in layer.get_property_list():
		if str(property.name)=="target_map": exposes_target_override = true
	check(not exposes_target_override,"no manual target-map override exists")
	var nested := Node2D.new()
	nested.name = "SpawnerOwnershipProbe"
	map.add_child(nested)
	layer.reparent(nested,false)
	check(layer.resolved_map_name()=="Map_Portal","nested containers still belong to their enclosing map")
	var other_map:Node = null
	var ordinary_map:Node = null
	for candidate:Node in world.map_group.values():
		if candidate != map and other_map == null: other_map = candidate
		if candidate is TileMapLayer and ordinary_map == null: ordinary_map = candidate
	check(other_map != null,"a second map is available for ownership validation")
	if other_map != null:
		layer.reparent(other_map,false)
		check(layer.resolved_map_name()==str(other_map.name),"moving the node changes its owning map without configuration")
		check(not layer.is_selected_map() and layer.advance_spawning(0)==0,"the previous map cannot activate a relocated layer")
		world.now_choose_map = str(other_map.name)
		check(layer.is_selected_map(),"only the actual new parent map activates the layer")
	layer.reparent(world,false)
	check(layer.resolved_map_name().is_empty() and not layer.can_generate(),"a layer outside all maps never generates")
	check(ordinary_map != null,"an ordinary tile map is available for ownership validation")
	if ordinary_map != null:
		layer.reparent(ordinary_map,false)
		world.now_choose_map = str(ordinary_map.name)
		check(layer.resolved_map_name()==str(ordinary_map.name) and layer.is_selected_map(),"ordinary TileMapLayer parents bind automatically too")
	layer.reparent(map,false)
	world.now_choose_map = "Map_Portal"
	check(layer.resolved_map_name()=="Map_Portal" and layer.is_selected_map(),"moving back restores ownership automatically")
	nested.free()
	var old_island_count:int = map.islands.size()
	layer.set_cell(Vector2i(2,2),0,Vector2i.ZERO)
	layer.set_cell(Vector2i(4,2),0,Vector2i.ZERO)
	map.collect_islands()
	check(map.islands.size()==old_island_count and not map.islands.has(str(layer.name)),"spawn cells never become map islands")
	check(not world._is_map_node(layer),"spawn layer is not exposed as a selectable map")
	var enabled:Resource = ENTRY.new()
	enabled.character = load("res://scenes/ball.tscn")
	var disabled:Resource = ENTRY.new()
	disabled.character = load("res://scenes/ball.tscn")
	disabled.enabled = false
	layer.character_table.append(enabled)
	layer.character_table.append(disabled)
	layer.spawn_interval = 1.0
	layer.spawn_count = 2
	layer.frame_spawn_budget = 2
	layer.max_alive = 3
	layer.max_alive_per_cell = 2
	layer.max_total = 4
	check(layer.advance_spawning(10)==0,"default does not produce while toolbar is open")
	world.control.hide()
	check(layer.advance_spawning(0)==2,"first painted tile starts an immediate wave within frame budget")
	check(layer.advance_spawning(0)==1,"remaining wave is processed next frame and respects layer cap")
	check(layer.alive_count()==3 and layer.total_spawned==3,"live and cumulative counts are tracked independently")
	check(layer.advance_spawning(5)==0,"a full live cap prevents additional spawning")
	check(world._battle_setup.is_empty(),"map characters do not pollute rematch setup or training respawn entries")
	for record:Dictionary in layer._alive.values():
		var actor:Node = record.node.get_ref()
		check(int(actor.get_meta("battle_setup_id"))<0,"map spawns use independent negative setup IDs")
	var record:Dictionary = layer._alive.values()[0]
	var removed:Node = record.node.get_ref()
	removed.queue_free()
	check(layer.advance_spawning(1)==1,"deletion releases a live slot and permits replacement")
	check(layer.total_spawned==4,"successful replacement increments total")
	for item:Dictionary in layer._alive.values():
		var actor:Node = item.node.get_ref()
		if is_instance_valid(actor): actor.queue_free()
	check(layer.advance_spawning(5)==0,"cumulative limit is not bypassed by deaths")
	await process_frame
	layer.reset_runtime()
	layer.max_total = 0
	layer.max_alive = 0
	layer.max_alive_per_cell = 1
	layer.spawn_count = 3
	layer.frame_spawn_budget = 16
	check(layer.advance_spawning(0)==2,"per-cell cap applies independently to every painted square")
	layer.reset_runtime()
	await process_frame
	layer.initial_delay = 1.0
	layer.spawn_count = 1
	check(layer.advance_spawning(0.4)==0,"initial delay is honored")
	check(layer.advance_spawning(0.5)==0,"delay does not fire early")
	check(layer.advance_spawning(0.11)==2,"generation begins when initial delay expires")
	layer.reset_runtime()
	await process_frame
	layer.initial_delay = 0
	layer.spawn_immediately = false
	check(layer.advance_spawning(0)==0,"spawn_immediately=false waits a full interval")
	check(layer.advance_spawning(1)==2,"delayed first wave arrives on schedule")
	paused = true
	check(layer.advance_spawning(99)==0,"paused game cannot generate even through explicit clock entry")
	paused = false
	layer.spawning_enabled = false
	check(layer.advance_spawning(99)==0,"enabled switch stops generation")
	layer.spawning_enabled = true
	layer.spawn_immediately = true
	var alternative:String = ""
	for name:Variant in world.map_group.keys():
		if str(name)!="Map_Portal":
			alternative = str(name)
			break
	world.now_choose_map = alternative
	check(layer.advance_spawning(99)==0,"unselected map cannot generate")
	check(layer.alive_count()==0 and layer.total_spawned==0,"leaving map resets its counters and removes its own spawns")
	world.now_choose_map = "Map_Portal"
	layer.character_table.clear()
	check(layer.advance_spawning(99)==0,"empty character table is safe and does not fall back")
	layer.character_table.append(enabled)
	enabled.weight = 0.0
	check(layer.advance_spawning(99)==0,"zero-weight entries are not selectable")
	enabled.weight = 1.0
	layer.clear()
	check(layer.advance_spawning(99)==0,"erasing all painted squares stops generation")
	layer.set_cell(Vector2i(2,2),0,Vector2i.ZERO)
	layer.reset_runtime()
	layer.position = Vector2(13,7)
	layer.scale = Vector2(1.1,0.9)
	layer.require_inside_map = false
	layer.randomize_position = false
	check(layer.advance_spawning(0)==1,"a transformed paint layer still emits")
	record = layer._alive.values()[0]
	var transformed:Node2D = record.node.get_ref()
	check(transformed.global_position.is_equal_approx(layer.to_global(layer.map_to_local(Vector2i(2,2)))),"tile center uses full local-to-global transform")
	world.reset()
	await process_frame
	check(layer.total_spawned==0 and layer.alive_count()==0,"world Reset resets spawner lifecycle too")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("CHARACTER_SPAWNER_TILES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
