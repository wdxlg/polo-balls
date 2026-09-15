extends SceneTree
var game:Node
var world:Node
var sans:Node2D
var phase:Node
var saved:Dictionary
var saved_stop:bool
var units:Array[Node2D] = []
var stage:int = 0
var elapsed:float = 0.0
var started:bool = false
var failures:int = 0
var max_x:float = 0.0
var screenshots:Array[float] = [2.3,9.2,18.0,26.6,31.6,45.5]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	Engine.time_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var roles:Array[String] = ["磐灯守卫","霆针游侠","时砂司祭"]
	for i:int in range(3):
		var unit:Node2D = load("res://scenes/characters/AI/"+roles[i]+".tscn").instantiate()
		unit.Team = "Team0"
		unit.Max_health = 100000
		unit.position = rect.get_center()+Vector2((i-1)*70,50)
		world.add_child(unit,true)
		unit.Can_Attack = false
		unit.Can_Skill = false
		units.append(unit)
	sans = load("res://scenes/characters/传说之下/Sans.tscn").instantiate()
	sans.Team = "Team1"
	sans.position = rect.get_center()-Vector2(0,100)
	sans.prepare_training_boss_specialization(1.0)
	world.add_child(sans,true)
	sans.activate_training_boss_specialization(1.0)
	sans._dodge_count = 2
	sans._dodge_grace_remaining = 0.0
	sans._try_dodge_incoming()
	await process_frame
	await process_frame
	phase = sans._last_trial_controller
	if not is_instance_valid(phase):
		finish(1)
		return
	started = true
	print("LIVE_BEGIN total=",phase.total_duration," base=",phase.base_rect," participants=",phase.participants.size())
func _process(delta:float) -> bool:
	if not started:
		return false
	elapsed += delta
	if is_instance_valid(phase):
		for unit:Node2D in units:
			max_x = maxf(max_x,unit.global_position.x-phase.base_rect.position.x)
		if stage < screenshots.size() and phase.elapsed >= screenshots[stage]:
			var report:Array = []
			for unit:Node2D in units:
				report.append({"p":str(unit.global_position),"g":str(unit.get_external_directional_gravity()),"hp":unit.health})
			print("LIVE_STAGE ",stage," t=",phase.elapsed," rect=",phase.arena_rect," slams=",phase.impact_sides," wind=",phase.wind_emitted," units=",JSON.stringify(report))
			if DisplayServer.get_name() != "headless":
				capture(stage)
			stage += 1
	elif elapsed > 40.0:
		print("LIVE_COMPLETE max_x=",max_x," map=",world.now_choose_map," immune=",sans._last_trial_active)
		if sans._last_trial_active or world.now_choose_map != "Map50x50" or max_x < 1000:
			failures += 1
		finish(0 if failures == 0 else 1)
	return false
func capture(index:int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scripts/training/sans_final_stage_%d.png" % index)
func finish(code:int) -> void:
	started = false
	if is_instance_valid(phase):
		phase.finish(false)
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	print("LIVE_RESULT code=",code)
	quit(code)
