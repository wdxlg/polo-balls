extends "res://tests/test_training_events_snow.gd"
## Production map/reset/rematch and settings persistence, not simulated node counters.
func until(condition:Callable,seconds:float = 8.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false
func snow_ready() -> bool:
	return is_instance_valid(conditions.field) and not conditions.field.is_queued_for_deletion() and conditions.field.environment_patches.size()>0 and conditions._seed==conditions._weather_seed()

func run() -> void:
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Development_Mode = false
	var center:Vector2 = await setup_world()
	saved = original_settings
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	game.now_stop_state = true
	setting("Random_Events",true)
	setting("Random_Event_Selection",["future_event"])
	setting("Environment","snow")
	game.save_persistent_settings()
	game.Game_Settings.Random_Events = false
	game.Game_Settings.Random_Event_Selection = []
	game.Game_Settings.Environment = "none"
	game.load_persistent_settings()
	check(game.Game_Settings.Random_Events and game.Game_Settings.Random_Event_Selection==["future_event"] and game.Game_Settings.Environment=="snow","Events choice, checked IDs and weather persist through the real settings file")
	check(not game.Game_Settings.Training_Mode,"weather persistence never re-enables the training-only mode")
	check(await until(snow_ready),"paused setup still creates its initial permanent snow layout")
	var field:Node2D = conditions.field
	var count:int = field.environment_patches.size()
	var left:float = conditions._snow_left
	conditions.advance(3.0)
	check(field.environment_patches.size()==count and conditions._snow_left==left,"global pause stops weather clock without deleting accumulated snow")
	game.now_stop_state = false
	Engine.time_scale = 0
	conditions.advance(3.0)
	check(field.environment_patches.size()==count and conditions._snow_left==left,"zero time scale also stops new snow generation")
	Engine.time_scale = 1
	game.now_stop_state = true
	var previous_map:String = world.now_choose_map
	var next_map:String = ""
	for key:String in world.map_group:
		if key!=previous_map and world.map_group[key] is TileMapLayer:
			next_map = key
			break
	check(not next_map.is_empty(),"production world exposes another ordinary map")
	game.request_map_choice(next_map)
	check(await until(func():return conditions._map_key==next_map and snow_ready()),"public map-change path replaces weather layout for the selected arena")
	var inside:bool = true
	for record:Dictionary in field.environment_patches.values():
		if record.decorative: continue
		var rectangle:Array[Rect2] = [Rect2(FIELD.point_at(record.cell)-Vector2.ONE*12,Vector2.ONE*24)]
		inside = inside and conditions.GEOMETRY.subtract(rectangle,conditions._ground).is_empty()
	check(inside,"new map snow stays on actual floor regions instead of the old map or holes")
	game.request_map_choice(previous_map)
	check(await until(func():return conditions._map_key==previous_map and snow_ready()),"returning to the original map restores its own layout")
	# Use the production placement recorder so the normal rematch path owns the setup.
	await world.create_char("Team0","雪傀儡",center)
	check(world.has_rematch_setup() and await until(snow_ready),"real character placement establishes a replayable battle and weather seed")
	var original_seed:int = game.current_battle_random_seed()
	check(game.begin_battle_random(original_seed)==original_seed,"reusing a recorded battle seed is idempotent rather than incrementing it")
	var replay:Dictionary = conditions.field.environment_patches.duplicate(true)
	var old_field:WeakRef = weakref(conditions.field)
	await world.rematch_last_battle(true)
	check(await until(func():return not is_instance_valid(old_field.get_ref()) and snow_ready()),"normal exact rematch retires the previous transient field and recreates weather")
	check(game.current_battle_random_seed()==original_seed and conditions.field.environment_patches==replay,"exact replay reproduces the actual snow layout, not just a matching RNG seed")
	old_field = weakref(conditions.field)
	await world.rematch_last_battle(false)
	check(await until(func():return not is_instance_valid(old_field.get_ref()) and snow_ready()),"fresh-random rematch also creates a new authoritative snow field")
	check(game.current_battle_random_seed()!=original_seed and conditions.field.environment_patches!=replay,"fresh-random replay changes snow while retaining the chosen environment")
	var victim:Node2D = dummy(center+Vector2(72,0))
	game.now_stop_state = false
	var status:Node = COLD.ensure(victim)
	status.add_cold(100,1.4,conditions)
	game.now_stop_state = true
	var ice_ref:WeakRef = weakref(status)
	old_field = weakref(conditions.field)
	world.reset()
	check(await until(func():return not is_instance_valid(old_field.get_ref()) and snow_ready()),"ordinary reset clears old weather but retains the user's Snow selection")
	check(not is_instance_valid(ice_ref.get_ref()) and get_nodes_in_group("MCSnowIce").is_empty(),"reset leaves no frozen victim, ice shell or control lease from the old battle")
	field = conditions.field
	conditions.set_physics_process(false)
	field.set_physics_process(false)
	field.clear_environment()
	var center_cell:Vector2i = FIELD.cell_at(center)
	for dx:int in [-2,2]:
		var cell:Vector2i = center_cell+Vector2i(dx,0)
		field.add_environment_patch(conditions,{"cell":cell,"decorative":false,"rects":[Rect2(FIELD.point_at(cell)-Vector2.ONE*12,Vector2.ONE*24)]})
	field.development_begin_merge(func(point:Vector2):return "left" if point.x<center.x else "right",{"left":Vector2(-48,0),"right":Vector2(48,0)})
	field.development_preview_merge({}, {"left":{"offset":Vector2.ZERO},"right":{"offset":Vector2.ZERO}})
	check(field._development_environment_offsets.values().has(Vector2(48,0)) and field._development_environment_offsets.values().has(Vector2(-48,0)),"existing development-map movement previews carry permanent snow with each lane")
	field.development_finish_merge()
	check(field.environment_patches.size()==1 and field.environment_patches.has(center_cell),"development merge coalesces overlapping permanent tiles without duplicate damage")
	setting("Environment","none")
	world.reset()
	conditions.set_physics_process(true)
	for i:int in range(8): await process_frame
	check(not world.has_node("MCSnowField"),"reset with None does not recreate an unwanted snow field")
	print("TRAINING_SNOW_LIFECYCLE checks=",checks," failures=",failures)
	await finish(0 if failures==0 else 1)
