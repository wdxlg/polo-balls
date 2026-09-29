extends "res://tests/test_mc_snow_golem.gd"
## Former construction regression: now enforces removal and real block fracture cleanup.
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60,true,false,true).timeout.connect(func():finish(2))
	var source:Node2D = spawn(GOLEM_PATH,center)
	source.burst_probability = 0.0
	var field:Node2D = source._field
	field.set_physics_process(false)
	check(not source.has_method("mini_spawn_settings") and not field.has_method("drop_head") and not field.has_method("_spawn_mini"),"construction endpoints are removed rather than merely disabled")
	check(not ResourceLoader.exists(MINI_PATH) and not ResourceLoader.exists("res://scripts/characters/我的世界/snow_golem/heads_view.gd"),"retired runtime resources cannot be loaded")
	var cell:Vector2i = FIELD.cell_at(center)
	field.deposit(source,cell,false)
	var snapshot:Dictionary = field.patches.duplicate(true)
	source.take_damage(ceilf(source.Max_health*0.5),true)
	check(field.patches==snapshot and source.head_break_count==1,"head break does not consume existing terrain")
	var count:int = get_nodes_in_group("MCSnowGolem").size()
	for i:int in range(8):
		source.global_position += Vector2(24 if i%2==0 else -24,0)
		source.lay_trail()
		field.advance(0.1)
	await process_frame
	check(get_nodes_in_group("MCSnowGolem").size()==count,"repeated passes over the break location never summon a child")
	field._field_state([], [{"id":1,"cell":cell,"point":center,"blocks":2,"landed":true}],false)
	await process_frame
	check(get_nodes_in_group("MCSnowGolem").size()==count,"retired network head slot cannot restore a construction entity")
	var effects:Array[Node] = get_nodes_in_group("MCBlockFragments")
	check(not effects.is_empty(),"half health uses the shared native block-fragment effect")
	if not effects.is_empty():
		var effect:Node2D = effects.back()
		effect.set_process(false)
		check(effect.pieces.size()>6 and effect.pieces.size()<=16,"pumpkin breaks into bounded real texture fragments")
		var all_visual:bool = true
		for piece:Dictionary in effect.pieces: all_visual = all_visual and not piece.sprite is CollisionObject2D
		check(all_visual,"fragments never become damaging/blocking snow construction")
		game.now_stop_state = true
		var age:float = effect.age
		effect._process(2.0)
		check(effect.age==age,"paused fracture stays frozen")
		game.now_stop_state = false
		effect.advance(2.0)
		check(effect.is_queued_for_deletion(),"head fragments expire after their short visual lifetime")
	check(source.force_next_burst,"construction removal retains the requested next-attack guarantee")
	print("SNOW_BUILD_RETIREMENT_RESULT checks=",checks," failures=",failures)
	await finish(0 if failures==0 else 1)
