extends SceneTree
## 3D blocks (workbench, smithing table, azalea, see-through layer) compile their pipelines
## while the world loads, and wall-top snow compiles when snow is chosen, so neither freezes a battle.
## Needs @gui; headless only checks that the warm-up is skipped cleanly.
var checks:int = 0
var failures:int = 0
var _worst_ms:float = 0.0
var _last_us:int = 0
var _measure:bool = false

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _process(_delta:float) -> bool:
	var now:int = Time.get_ticks_usec()
	if _measure and _last_us > 0: _worst_ms = maxf(_worst_ms,(now-_last_us)/1000.0)
	_last_us = now
	return false

func worst_over(seconds:float) -> float:
	_worst_ms = 0.0
	_measure = true
	await create_timer(seconds).timeout
	_measure = false
	return _worst_ms

func run() -> void:
	create_timer(80.0,true,false,true).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	# Game saves settings again on exit, so the redirect stays until quit.
	game._settings_storage_path = OS.get_temp_dir().path_join("mc_block_3d_prewarm_settings.cfg")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Local_Hitstop = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	await create_timer(6.0).timeout
	world.control.hide()
	var BLOCK:Script = load("res://scripts/effects/我的世界/mc_block_3d.gd")
	var gui:bool = DisplayServer.get_name() != "headless"
	check(world.get_node_or_null("MCBlock3DPipelineWarmup") == null,"warm-up renderer is gone after loading")
	check(BLOCK._warm_materials.is_empty() != gui,"warm-up runs with a renderer and is skipped headless")
	if gui:
		var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
		var size:float = BLOCK.map_cell(world)
		var models:Array[StringName] = [&"crafting_table",&"smithing_table",&"azalea"]
		var blocks:Array[Node2D] = []
		await worst_over(1.0)
		for i:int in range(models.size()):
			var holder := Node2D.new()
			holder.position = rect.get_center()+Vector2((i-1)*size*2.0,0.0)
			world.add_child(holder)
			var block:Node2D = BLOCK.create(models[i],size)
			holder.add_child(block)
			blocks.append(block)
			var worst:float = await worst_over(1.5)
			check(worst < 400.0,"first %s does not freeze the frame (worst %.0f ms)" % [models[i],worst])
		blocks[2].set_see_through(1.0)
		var worst_see:float = await worst_over(1.5)
		check(worst_see < 400.0,"first see-through bush does not freeze the frame (worst %.0f ms)" % worst_see)
		# Snow environment: the warm-up happens when snow is chosen, not when the first wall-top snow lands.
		var cond:Node = world.battle_conditions
		game.Game_Settings.Environment = "snow"
		cond.refresh_layout(true)
		await worst_over(1.0)
		check(world.get_node_or_null("SnowSurfacePipelineWarmup") == null,"snow warm-up renderer is gone")
		var before:int = cond.field.environment_patches.size()
		_worst_ms = 0.0
		_measure = true
		for _i:int in range(90):
			await process_frame
			if not cond._spawn_from(cond._wall_candidates): cond._spawn_from(cond._ground_candidates)
		_measure = false
		check(cond.field.environment_patches.size() > before,"snow patches were placed")
		check(_worst_ms < 400.0,"first wall-top snow does not freeze the frame (worst %.0f ms)" % _worst_ms)
	world.queue_free()
	await process_frame
	print("MC_BLOCK_PREWARM checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
