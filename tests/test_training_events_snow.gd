extends "res://tests/test_mc_snow_golem.gd"
## Actual production settings, cold entry points and shared weather/trail behavior.
const CATALOG = preload("res://scripts/training/battle_conditions_catalog.gd")
var conditions:Node2D
var original_settings:Dictionary
var original_locale:String
var settings_file:String
var settings_existed:bool = false
var settings_bytes:PackedByteArray

func finish(code:int) -> void:
	if done: return
	if is_instance_valid(game):
		game.set_language(original_locale,false)
		if settings_existed:
			var output:FileAccess = FileAccess.open(settings_file,FileAccess.WRITE)
			if output!=null: output.store_buffer(settings_bytes)
		elif FileAccess.file_exists(settings_file): DirAccess.remove_absolute(settings_file)
	print("TRAINING_EVENTS_SNOW checks=",checks," failures=",failures)
	await super.finish(code)

func setting(key:String,value:Variant) -> void:
	game._apply_runtime_game_setting_local(key,value,false)

func run() -> void:
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Random_Events = false
	game.Game_Settings.Random_Event_Selection = []
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Only_In_Game_Translation = false
	var center:Vector2 = await setup_world()
	saved = original_settings
	create_timer(80.0).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	check(is_instance_valid(conditions) and conditions.environment=="none" and not world.has_node("MCSnowField"),"default environment is None and spawns no field or hidden character")
	check(CATALOG.EVENTS.is_empty(),"production registry contains no invented events")
	check(CATALOG.normalize_environment("bogus")=="none" and CATALOG.normalize_selection(["a","a",12,""])==["a"],"invalid saved values normalize safely without duplicate event IDs")
	var rng:=RandomNumberGenerator.new()
	rng.seed = 73
	var definitions:Array = [{"id":"checked","label_key":"checked"},{"id":"unchecked","label_key":"unchecked"}]
	var configuration:Dictionary = {"Random_Events":false,"Random_Event_Selection":["checked","obsolete"]}
	check(CATALOG.pick_event(configuration,rng,definitions)=="","disabled events never enter the draw pool")
	configuration.Random_Events = true
	var filtered:bool = true
	for i:int in range(200): filtered = filtered and CATALOG.pick_event(configuration,rng,definitions)=="checked"
	check(filtered,"only checked registered events are eligible across 200 draws")
	configuration.Random_Event_Selection = []
	check(CATALOG.pick_event(configuration,rng,definitions)=="","empty selection never falls back to all events")
	await check_ui()
	var source:Node2D = spawn(GOLEM_PATH,center+Vector2(-120,-96),"Team0")
	var victim:Node2D = dummy(center+Vector2(120,96),"Team1")
	var field:Node2D = source._field
	field.set_physics_process(false)
	await physics_frame
	await process_frame
	await check_cold(source,victim)
	await check_weather(source,victim,center)
	await finish(0 if failures==0 else 1)

func check_ui() -> void:
	var ui:Control = world.control
	var panel:Node = ui.settings_category_boxes.training.get_node("BattleConditionsSettings")
	check(not panel.event_box.visible and panel.event_checks.is_empty(),"Events starts off and the checkbox area is collapsed")
	setting("Random_Events",true)
	check(panel.event_box.visible and panel.event_empty.visible,"enabling Events reveals the honest empty selection area")
	setting("Random_Events",false)
	check(not panel.event_box.visible,"disabling Events collapses only its selection area")
	check(panel.environment_option.item_count==2 and panel.environment_option.get_item_metadata(0)=="none" and panel.environment_option.get_item_metadata(1)=="snow","Environment contains exactly None and Snow")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		await process_frame
		check(panel.environment_label.text==("环境" if locale=="zh" else "Environment"),locale+" Environment title is localized")
		check(panel.environment_option.get_item_text(1)==("雪" if locale=="zh" else "Snow"),locale+" Snow option is localized")
	setting("Environment","invalid_saved_weather")
	check(game.Game_Settings.Environment=="none" and panel.environment_option.selected==0,"invalid environment cannot escape normalization or desynchronize the dropdown")
	setting("Random_Event_Selection",["checked","checked"])
	check(game.Game_Settings.Random_Event_Selection==["checked"],"authoritative settings path normalizes selected event IDs")
	setting("Random_Event_Selection",[])

func check_cold(source:Node2D,victim:Node2D) -> void:
	check(source.is_cold_immune() and not source.can_receive_cold_status(),"real Snow Golem defaults to cold damage and status immunity")
	var hp:int = source.health
	check(not source.receive_cold_positional_damage(20,source.global_position,true,victim) and source.health==hp,"Snow Golem ignores the reusable cold damage entry")
	var immune_status:Node = COLD.ensure(source)
	check(not immune_status.add_cold(100,1.4,victim) and immune_status.frozen_left==0.0 and not source.dizziness,"Snow Golem cannot accumulate cold or freeze")
	immune_status.accept_state(100,1.4,1.4)
	check(immune_status.amount==0.0 and immune_status.frozen_left==0.0,"replicated cold visuals cannot bypass cold immunity")
	var mini:Node2D = spawn(MINI_PATH,source.global_position+Vector2(48,0))
	check(mini.is_cold_immune(),"mini snow golems inherit the same immunity")
	mini.queue_free()
	victim.cold_effect_ratio = 0.5
	hp = victim.health
	victim.receive_cold_positional_damage(10,victim.global_position,true,source)
	check(victim.health==hp-5,"cold multiplier is applied exactly once by the public damage entry")
	victim.cold_effect_ratio = 0.0
	hp = victim.health
	check(not victim.receive_cold_spatial_damage(10,{},true,true) and victim.health==hp,"cold spatial damage respects generic immunity too")
	victim.receive_positional_damage(10,victim.global_position,true,source)
	check(victim.health==hp-10,"cold immunity does not suppress ordinary direct damage")
	victim.cold_effect_ratio = 1.0
	var cold:Node = COLD.ensure(victim)
	check(cold.add_cold(100,1.4,source),"susceptible victim still freezes via the original cold meter")
	cold.set_process(false)
	cold.set_physics_process(false)
	world.figure_buffs(0.0,[victim])
	hp = victim.health
	cold._freeze_tick()
	check(victim.health==hp-4,"default freeze tick keeps 2 base damage and the existing double-damage vulnerability")
	source.Damage = 18
	hp = victim.health
	cold._freeze_tick()
	check(victim.health==hp-8,"freeze cold damage follows current source attack rather than a detached fixed attack")
	source.Damage = 9
	var other_lock:Node = victim.apply_stun(3.0)
	other_lock.set_physics_process(false)
	victim.cold_effect_ratio = 0.0
	check(cold.amount==0.0 and cold.frozen_left==0.0 and not victim.Buff_Dic.has(cold.get_instance_id()),"gaining cold immunity immediately removes cold and freeze vulnerability")
	check(victim.dizziness,"clearing cold immunity status preserves another stun's motion lock")
	other_lock.free()
	check(not victim.dizziness,"the remaining control ends normally without a leaked cold lock")
	clear_cold(victim)
	victim.restore_default_runtime_properties_fast()
	victim.cold_effect_ratio = 0.0
	# Real projectile contact: direct snowball damage/knockback are not cold damage.
	source._spawn_snowball("ColdImmunityImpact",victim.global_position-Vector2(24,0),Vector2.RIGHT,6.0)
	var shot:Node2D = world.get_node("ColdImmunityImpact")
	shot.state_machine.set_physics_process(false)
	hp = victim.health
	check(shot.self_hitbox.try_hit_hurtbox(victim.self_hurtbox),"cold-immune victim is still hit by a normal snowball")
	var knocked:bool = false
	for child:Node in victim.get_children():
		if child.get_script()==load("res://scripts/effects/knockback_effect.gd") and child.is_active_effect(): knocked = true
	check(victim.health<hp and knocked,"snowball retains ordinary hit damage and knockback against cold immunity")
	check(not victim.has_node("MCSnowCold"),"snowball adds no cold status to a cold-immune victim")
	if is_instance_valid(shot): shot.queue_free()
	victim.cold_effect_ratio = 1.0
	await process_frame

func check_weather(source:Node2D,victim:Node2D,center:Vector2) -> void:
	var field:Node2D = source._field
	field.patches.clear()
	clear_cold(victim)
	game.begin_battle_random(73421)
	setting("Environment","snow")
	await physics_frame
	await physics_frame
	await process_frame
	field = conditions.field
	field.set_physics_process(false)
	check(field==source._field and world.get_node("MCSnowField")==field,"weather and golem trails share one real sparse snow manager")
	check(get_nodes_in_group("MCSnowGolem").size()==1,"weather does not spawn a hidden golem or duplicate combat character")
	check(field.environment_patches.is_empty() and not is_instance_valid(field.wall_view.mesh_node),"Snow selection starts with no ground accumulation and no prebuilt wall snow")
	check(field.wall_view.weather_enabled and field.wall_view.weather_time==0.0 and field.wall_view.weather_fade==0.0,"native falling snow also starts empty instead of appearing prewarmed")
	conditions.advance(conditions.FIRST_SNOW_DELAY*0.5)
	check(field.environment_patches.is_empty() and field.wall_view.weather_time>0.0,"visible snowfall advances before the first accumulation")
	for i:int in range(20): conditions.advance(1.0)
	var floor_count:int = 0
	var wall_count:int = 0
	for item:Dictionary in field.environment_patches.values():
		if item.decorative: wall_count+=1
		else: floor_count+=1
	check(floor_count>0 and wall_count>0,"random environment snow creates both ground tiles and wall decorations, including blue maps")
	check(field.get_child_count()<8,"snow stays a sparse grid rather than one Area2D or timer per patch")
	var snapshot:Dictionary = field.environment_patches.duplicate(true)
	field.advance(100.0)
	check(field.environment_patches==snapshot,"environment snow never enters the ordinary melting lifecycle")
	var cell:Vector2i = FIELD.cell_at(center)
	var record:Dictionary = {"cell":cell,"decorative":false,"rects":[Rect2(center-Vector2.ONE*12,Vector2.ONE*24)]}
	field.add_environment_patch(conditions,record)
	park_contact(field,victim,center)
	var hp:int = victim.health
	field.check_ground()
	check(victim.health==hp-3,"neutral environment snow uses original golem ground damage of 3")
	var cold:Node = victim.get_node_or_null("MCSnowCold")
	check(is_instance_valid(cold) and is_equal_approx(cold.amount,8.0),"environment contact uses the original shared cold meter and gain")
	field.check_ground()
	check(victim.health==hp-3,"standing on weather snow obeys the shared per-target cooldown")
	field.deposit(source,cell,false)
	field._damage_until.erase(victim.get_instance_id())
	hp = victim.health
	field.check_ground()
	check(victim.health==hp-3,"overlapping golem/weather snow does not double-tick damage")
	clear_cold(victim)
	field.patches.clear()
	field.clear_environment()
	record.decorative = true
	field.add_environment_patch(conditions,record)
	field._damage_until.erase(victim.get_instance_id())
	hp = victim.health
	field.check_ground()
	check(victim.health==hp and not victim.has_node("MCSnowCold"),"decorative wall snow never deals damage, cold or control even when overlapped")
	check(field.get_debug_hazard_info().is_empty(),"wall decoration is excluded from damage threat geometry")
	record.decorative = false
	field.add_environment_patch(conditions,record)
	var info:Dictionary = field.get_debug_hazard_info()
	check(info.get("shape","")=="compound" and info.parts.size()==1 and info.parts[0].shape=="rect","ground snow declares its exact rectangular damage threat")
	var analyzer:Node = load("res://scripts/training/combat_threat_analyzer.gd").new()
	analyzer._debug_add_declared_threat(info,field)
	check(analyzer._debug_threats.size()==1,"shared threat renderer accepts sparse compound geometry")
	analyzer.free()
	field.deposit(source,cell+Vector2i.RIGHT,false)
	var natural_count:int = field.patches.size()
	game.now_stop_state = true
	var count:int = field.environment_patches.size()
	var snow_left:float = conditions._snow_left
	var weather_time:float = field.wall_view.weather_time
	conditions.advance(5.0)
	check(field.environment_patches.size()==count and conditions._snow_left==snow_left and field.wall_view.weather_time==weather_time,"pause freezes accumulation AND the native falling-snow animation")
	game.now_stop_state = false
	setting("Environment","none")
	check(not field.wall_view.weather_enabled and field.wall_view.weather_fade==0.0,"None removes falling snow immediately, without a visual tail")
	check(field.environment_patches.is_empty() and field.patches.size()==natural_count,"turning weather off removes only environmental snow, preserving ordinary golem trails")
	field.advance(field.full_snow_lifetime+field.half_snow_lifetime+0.1)
	check(field.patches.is_empty(),"ordinary golem trails still melt normally after weather is disabled")
	setting("Environment","snow")
	await physics_frame
	await physics_frame
	await process_frame
	check(field.environment_patches.is_empty(),"re-enabling Snow never restores stale accumulation")
	for i:int in range(12): conditions.advance(1.0)
	var replay_a:Dictionary = field.environment_patches.duplicate(true)
	var weather_phases:Array = field.wall_view.weather_phases.duplicate()
	var rng_counters:Dictionary = game._battle_random_counters.duplicate(true)
	setting("Environment","none")
	setting("Environment","snow")
	await physics_frame
	await physics_frame
	await process_frame
	check(field.environment_patches.is_empty() and field.wall_view.weather_time==0.0,"repeat selection starts both visual and gameplay weather at zero")
	for i:int in range(12): conditions.advance(1.0)
	check(field.environment_patches==replay_a and field.wall_view.weather_phases==weather_phases,"same seed and elapsed combat time reproduce accumulating snow and native weather phases")
	check(game._battle_random_counters==rng_counters,"weather does not consume another system's deterministic random stream")
	for i:int in range(400): conditions.advance(10.0)
	check(field.environment_patches.size()<=conditions.MAX_PATCHES,"long battles retain a bounded number of environmental patches")
	setting("Environment","none")
