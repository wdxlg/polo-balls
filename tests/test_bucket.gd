extends SceneTree
const WATER_SCENE:String = "res://scenes/characters/我的世界/水桶.tscn"
const LAVA_SCENE:String = "res://scenes/characters/我的世界/岩浆桶.tscn"
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit,true)
	return unit

func dummy(point:Vector2,team:String = "Team1",live:bool = false) -> Node2D:
	var target:Node2D = spawn("res://scenes/ball.tscn",point,team)
	target.Can_Attack = false
	target.Can_Skill = false
	target.Max_health = 10000
	target.default_properties["Max_health"] = 10000
	target.health = 10000
	target.Has_Collision_Damage = false
	target.Speed = 0.0
	target.default_properties["Speed"] = 0.0
	if not live: target.state_machine.set_physics_process(false)
	return target

func park(unit:Node2D) -> void:
	unit.Speed = 0.0
	unit.default_properties["Speed"] = 0.0
	unit._pour_wait = 1.0e9

func sim(seconds:float) -> float:
	var elapsed:float = 0.0
	await physics_frame
	while elapsed < seconds:
		await physics_frame
		elapsed += root.get_physics_process_delta_time()
	return elapsed

func steps(field:Node2D,liquid:int,n:int) -> void:
	for i:int in range(n): field.step_liquid(liquid)

func freeze(field:Node2D) -> void:
	field._step_left[0] = 1.0e9
	field._step_left[1] = 1.0e9
	field._drain_left = 1.0e9

func finish(code:int) -> void:
	if done: return
	done = true
	print("BUCKET RESULT: ",checks - failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world):
		for node:Node in world.find_children("*","Node",true,false):
			if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"):
				node.set_process(false)
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/" + role + ".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(150.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var map:Node = world.map_group["Map50x50"]
	var center:Vector2 = world.return_map_world_rect(map).get_center()
	var classifier:Script = load("res://classes/combat_classification.gd")

	var water:Node2D = spawn(WATER_SCENE,center + Vector2(-400,-300))
	park(water)
	await physics_frame
	await process_frame
	await process_frame
	check(water.Max_health == 650 and is_equal_approx(water.Damage,10.0) and is_equal_approx(water.pour_cooldown,6.0),"水桶 stats 650 HP / 10 damage / 6 s pour")
	check(world.return_all_character_names().has("水桶") and world.return_all_character_names().has("岩浆桶"),"both buckets appear in the roster")
	check(water.Unique_Death_Audio == water.AUDIO.EVENTS["entity.item.break"][0].stream and water.Dead_Audio == "DeadBell","death uses item break plus the default death sound")
	check(str(classifier.profile_of(water).get("entity_kind","")) == "character","water bucket classified as character")
	check(not water.get_armor_test_effect_summary().is_empty() and water.get_armor_test_effect_summary() != "MC_ARMOR_INTRO_WATER_BUCKET","water intro resolves")
	check(water.is_in_group("MCWaterBucket"),"water bucket is immune to its own water")

	var field:Node2D = world.get_node_or_null("MCFluidField")
	check(field != null and water.fluid_field() == field,"fluid field singleton lives under World")
	if field == null:
		finish(1)
		return
	freeze(field)
	check(field.floor_cells.size() == 2500,"every floor cell of the 50x50 map can hold fluid")
	check(not field.z_as_relative and field.z_index == -3,"fluid draws above the floor, under characters")
	var g:float = field.grid_size.x
	var c:Vector2i = field.cell_of(center)

	# --- water spread ---
	check(field.place_source(field.WATER,c,water),"water source placed")
	check(field.levels[field.WATER].size() == 1 and field.fluid_height(field.WATER,c) > 0.88,"starts as a single full cell")
	steps(field,field.WATER,1)
	check(int(field.levels[field.WATER].get(c + Vector2i(1,0),0)) == 7 and not field.levels[field.WATER].has(c + Vector2i(2,0)),"spreads one cell per step")
	steps(field,field.WATER,8)
	var reach_ok:bool = true
	for d:int in range(1,8):
		if int(field.levels[field.WATER].get(c + Vector2i(d,0),0)) != 8 - d: reach_ok = false
	check(reach_ok and not field.levels[field.WATER].has(c + Vector2i(8,0)) and int(field.levels[field.WATER].get(c + Vector2i(3,4),0)) == 1,"water reaches 7 cells by taxicab distance")
	check(field.flow_vector(field.WATER,c + Vector2i(3,0)).is_equal_approx(Vector2.RIGHT) and field.flow_vector(field.WATER,c + Vector2i(0,-3)).is_equal_approx(Vector2.UP),"water flows away from the source")
	await process_frame
	await process_frame
	var mesh:MeshInstance3D = field.mesh_instance(field.WATER)
	check(mesh != null and mesh.mesh != null and mesh.mesh.get_surface_count() >= 1 and field.renderer(field.WATER).visible,"3D water mesh is built in the block renderer")
	check(field.renderer(field.WATER).z_index == -3 and is_equal_approx(field.renderer(field.WATER).picture.modulate.a,0.78),"water renderer is translucent at fluid layer")
	check(field.levels[field.LAVA].is_empty() and field.renderer(field.LAVA) != null and field.renderer(field.LAVA).viewport != null,"both fluid renderers are prepared up front, before the first pour")
	var caster:MeshInstance3D = field.shadow_instance(field.WATER)
	check(caster != null and caster.mesh == mesh.mesh and caster.get_parent() == field.renderer(field.WATER).shadow_viewport and caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and field.renderer(field.WATER).shadow_picture.visible and field.renderer(field.WATER).shadow_picture.z_index < field.z_index,"water throws a real ground shadow under itself")
	var MESH_SCRIPT:Script = load("res://scripts/characters/我的世界/bucket/fluid_mesh.gd")
	check(is_equal_approx(MESH_SCRIPT.DEPTH_SCALE,1.0) and field.fluid_height(field.WATER,c + Vector2i(7,0)) >= MESH_SCRIPT.LOW_HEIGHT * MESH_SCRIPT.FULL_HEIGHT - 0.001,"full vanilla depth, and the thinnest edge still stands as a visible wall")
	check(is_equal_approx(MESH_SCRIPT.face_shade(Vector3.UP),1.0) and is_equal_approx(MESH_SCRIPT.face_shade(Vector3.BACK),0.8) and is_equal_approx(MESH_SCRIPT.face_shade(Vector3.RIGHT),0.6),"vanilla face shading: top 1.0, north/south 0.8, east/west 0.6")
	var min_shade:float = 1.0
	for s:int in range(mesh.mesh.get_surface_count()):
		var colors:PackedColorArray = mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
		for col:Color in colors: min_shade = minf(min_shade,col.r)
	check(min_shade < 0.65,"side walls are darker than the top (min shade %.2f)" % min_shade)
	check(MESH_SCRIPT.height_shade(0.0,10.0) < MESH_SCRIPT.height_shade(5.0,10.0) and is_equal_approx(MESH_SCRIPT.height_shade(10.0,10.0),1.0),"higher fluid is brighter, so the mound reads as 3D from above")
	var prewarm_source:String = FileAccess.get_file_as_string("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	check(MESH_SCRIPT.has_method("prewarm_pipelines") and prewarm_source.contains("fluid_mesh.gd") and prewarm_source.contains("\"水桶\"") and prewarm_source.contains("\"岩浆桶\""),"fluid shaders and bucket resources are prewarmed at startup")

	# --- merging and infinite source ---
	check(field.place_source(field.WATER,c + Vector2i(2,0),water),"second water source placed two cells away")
	steps(field,field.WATER,1)
	check(field.is_source(field.WATER,c + Vector2i(1,0)),"water between two sources becomes a source")
	steps(field,field.WATER,7)
	check(int(field.levels[field.WATER].get(c + Vector2i(9,0),0)) == 1 and field.flow_vector(field.WATER,c + Vector2i(5,0)).is_equal_approx(Vector2.RIGHT),"merged water extends the range and the current")

	# --- push ---
	var swimmer:Node2D = dummy(field.cell_center(c + Vector2i(5,0)),"Team1",true)
	var start:Vector2 = swimmer.global_position
	await sim(0.5)
	check(swimmer.global_position.x > start.x + 4.0,"water pushes units along the flow (moved %.1f)" % (swimmer.global_position.x - start.x))
	var water_start:Vector2 = field.cell_center(c + Vector2i(-5,0))
	water.global_position = water_start
	await sim(0.4)
	check(water.global_position.distance_to(water_start) < 1.0,"water bucket is not pushed")

	# --- oxygen ---
	var diver:Node2D = dummy(field.cell_center(c + Vector2i(0,0)))
	await sim(0.3)
	var entry:Dictionary = field.air.get(diver.get_instance_id(),{})
	check(not entry.is_empty() and float(entry.air) < field.AIR_SECONDS,"air drains in water")
	check(field.air_view().has(diver.get_instance_id()) and field.oxygen_display().visible_units().has(diver),"oxygen bar shows above units in water")
	check(not field.air.has(water.get_instance_id()),"water bucket never uses air")
	entry.air = 0.01
	var hp:float = diver.health
	await sim(1.15)
	check(absf((hp - diver.health) - 1000.0) < 1.0,"drowning removes 10%% of max health per second (lost %.1f)" % (hp - diver.health))
	check(field.oxygen_display().bubbles_for(diver) == 0,"empty air shows no bubbles")
	diver.global_position = field.cell_center(c + Vector2i(0,-12))
	await sim(1.6)
	var mid:Dictionary = field.air.get(diver.get_instance_id(),{})
	check(not mid.is_empty() and float(mid.air) > 3.5 and float(mid.air) < 7.0,"air recovers gradually out of water")
	await sim(2.0)
	check(not field.air.has(diver.get_instance_id()),"full air hides the bar")
	diver.queue_free()
	swimmer.queue_free()

	# --- lava ---
	var lava_bucket:Node2D = spawn(LAVA_SCENE,center + Vector2(400,-300))
	park(lava_bucket)
	await physics_frame
	await process_frame
	check(lava_bucket.Max_health == 600 and is_equal_approx(lava_bucket.pour_cooldown,8.0) and lava_bucket.is_in_group("MCLavaBucket"),"岩浆桶 stats 600 HP / 8 s pour")
	check(not lava_bucket.get_armor_test_effect_summary().is_empty() and lava_bucket.get_armor_test_effect_summary() != "MC_ARMOR_INTRO_LAVA_BUCKET","lava intro resolves")
	var l:Vector2i = c + Vector2i(0,15)
	check(field.place_source(field.LAVA,l,lava_bucket),"lava source placed")
	steps(field,field.LAVA,4)
	check(int(field.levels[field.LAVA].get(l + Vector2i(3,0),0)) == 1 and not field.levels[field.LAVA].has(l + Vector2i(4,0)),"lava reaches 3 cells")
	var victim:Node2D = dummy(field.cell_center(l + Vector2i(1,0)))
	var friend:Node2D = dummy(field.cell_center(l + Vector2i(-1,0)),"Team0")
	hp = victim.health
	await sim(1.1)
	check(victim.health < hp - 15.0 and friend.health >= 10000.0,"lava burns enemies only (lost %.1f)" % (hp - victim.health))
	var burn:Node = victim.get_node_or_null("MinecraftBlazeBurn")
	check(burn != null and burn.source == lava_bucket and is_equal_approx(float(burn.tick_damage),3.0),"lava sets enemies burning")
	check(field.lava_owner(l + Vector2i(2,0)) == lava_bucket,"lava keeps its owner")
	await process_frame
	check(field.mesh_instance(field.LAVA) != null and field.mesh_instance(field.LAVA).mesh != null,"3D lava mesh is built")
	victim.queue_free()
	friend.queue_free()

	# --- lava recedes from the centre ---
	field.sources[field.LAVA][l].until = field.clock
	await sim(0.05)
	check(not field.is_source(field.LAVA,l) and field.drains.size() == 1,"lava source expires")
	check(is_equal_approx(field.DRAIN_STEP_SECONDS,field.STEP_SECONDS[field.LAVA]),"lava recedes exactly as fast as it spreads")
	field._step_drains()
	check(not field.levels[field.LAVA].has(l + Vector2i(1,0)) and field.levels[field.LAVA].has(l + Vector2i(3,0)),"lava recedes from the centre outward")
	for i:int in range(6): field._step_drains()
	check(field.levels[field.LAVA].is_empty() and field.drains.is_empty(),"lava fully gone")

	# --- water meets lava ---
	var o:Vector2i = c + Vector2i(-12,15)
	field.place_source(field.LAVA,o,lava_bucket)
	steps(field,field.LAVA,4)
	var stuck:Node2D = dummy(field.cell_center(o))
	await physics_frame
	field.place_source(field.WATER,o + Vector2i(5,0),water)
	steps(field,field.WATER,1)
	check(field.blocks.has(o + Vector2i(3,0)) and int(field.blocks[o + Vector2i(3,0)].kind) == field.STONE,"flowing lava touching water turns to stone")
	field.place_source(field.WATER,o + Vector2i(0,-1),water)
	check(field.blocks.has(o) and int(field.blocks[o].kind) == field.OBSIDIAN,"water touching a lava source makes obsidian")
	var obsidian:Node = field.blocks.get(o)
	await physics_frame
	check(obsidian != null and obsidian.trapped_units().has(stuck),"a unit standing in the new block is trapped")
	check(obsidian.block != null and obsidian.collision_layer == 1,"block is a solid 3D block")
	check(is_equal_approx(obsidian.duration,10.0) and is_equal_approx(field.blocks[o + Vector2i(3,0)].duration,5.0),"obsidian lasts longer than stone")
	var pos:Vector2 = stuck.global_position
	var stuck_burn:Node = stuck.get_node_or_null("MinecraftBlazeBurn")
	if stuck_burn != null: stuck_burn.free()
	hp = stuck.health
	stuck.velocity = Vector2(500,0)
	await sim(1.05)
	check(absf((hp - stuck.health) - 400.0) < 1.0 and stuck.global_position.distance_to(pos) < 0.5,"trapped unit is held and suffocates 2%% per half second (lost %.1f)" % (hp - stuck.health))
	obsidian.age = obsidian.duration - 0.5
	await sim(0.1)
	check(obsidian.block.crack_texture != null,"block cracks before breaking")
	await sim(0.6)
	check(not field.blocks.has(o) and (not is_instance_valid(obsidian) or obsidian.is_queued_for_deletion()),"block breaks after its time")

	# --- pour and owner death ---
	lava_bucket.global_position = field.cell_center(c + Vector2i(18,-15))
	check(lava_bucket.pour(),"bucket pours at its feet")
	check(field.is_source(field.LAVA,field.cell_of(lava_bucket.global_position)),"poured source is under the bucket")
	lava_bucket.health = 0
	lava_bucket.Die()
	check(not field.is_source(field.LAVA,c + Vector2i(18,-15)),"lava recedes when the lava bucket dies")
	finish(0 if failures == 0 else 1)
