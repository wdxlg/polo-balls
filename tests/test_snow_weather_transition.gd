extends "res://tests/test_training_events_snow_gpu.gd"
## Real controller toggles; optional actual GPU readback of native precipitation.
var visual_metrics:Dictionary = {}

func step_weather(delta:float) -> void:
	game.now_stop_state = false
	conditions.advance(delta)
	game.now_stop_state = true

func energy(bare:Image,image:Image) -> float:
	var total:float = 0.0
	for y:int in range(30,image.get_height()-30,3):
		for x:int in range(30,image.get_width()-30,3): total += gap(bare.get_pixel(x,y),image.get_pixel(x,y))
	return total

func finish(code:int) -> void:
	if done: return
	var file:=FileAccess.open(capture_dir.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"exit_code":code,"visual":visual_metrics},"\t"));file.close()
	print("SNOW_WEATHER_TRANSITION checks=",checks," failures=",failures)
	await super.finish(code)

func run() -> void:
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Development_Mode = false
	root.size = Vector2i(640,480)
	root.content_scale_size = root.size
	var center:Vector2 = await setup_world()
	saved = original_settings
	capture_dir = OS.get_environment("SNOW_TRANSITION_EVIDENCE_DIR")
	if capture_dir.is_empty(): capture_dir = "user://snow_transition"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	create_timer(110,true,false,true).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	var actor:Node2D = spawn(GOLEM_PATH,center)
	actor.set_physics_process(false)
	actor.Can_Attack = false
	actor.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.global_position = center+Vector2(2000,-1500)
	camera.zoom = Vector2.ONE*0.7
	camera.force_update_scroll()
	var gpu:bool = DisplayServer.get_name()!="headless"
	var bare:Image
	if gpu: bare = await grab("00_bare")
	setting("Environment","snow")
	var field:Node2D = conditions.field
	field.set_physics_process(false)
	var view:Node2D = field.wall_view
	check(view.weather_enabled and view.weather_fade==0.0,"enable starts transparent instead of appearing suddenly")
	step_weather(0.225)
	check(is_equal_approx(view.weather_fade,0.25),"fade-in reaches quarter opacity after 0.225 combat seconds")
	var opening:Image
	if gpu: opening = await grab("00_on_quarter")
	step_weather(0.675)
	check(is_equal_approx(view.weather_fade,1.0),"fade-in reaches full opacity after 0.9 combat seconds")
	var full:Image
	if gpu:
		full = await grab("01_full")
		var opening_ratio:float = energy(bare,opening)/maxf(energy(bare,full),0.001)
		visual_metrics["opening_ratio"] = opening_ratio
		check(opening_ratio>0.08 and opening_ratio<0.5,"native flakes are visibly translucent during fade-in before reaching full density")
	var phases:Array = view.weather_phases.duplicate()
	var time:float = view.weather_time
	var retained:Dictionary = field.environment_patches.duplicate(true)
	setting("Environment","none")
	check(not view.weather_enabled and view.weather_fade==1.0 and view.weather_time==time,"disable changes only the target; no opacity or position jump")
	if gpu:
		var immediate:Image = await grab("02_off_start")
		check(energy(full,immediate)<0.01,"actual snow pixels remain continuous at the off switch")
	step_weather(0.45)
	check(is_equal_approx(view.weather_fade,0.5) and is_equal_approx(view.weather_time,time+0.45),"off tail continues falling while gradually fading")
	check(field.environment_patches==retained,"off tail never generates new gameplay snow")
	if gpu:
		var half:Image = await grab("03_off_half")
		var full_energy:float = energy(bare,full)
		var ratio:float = energy(bare,half)/maxf(full_energy,0.001)
		visual_metrics.merge({"full_energy":full_energy,"half_ratio":ratio})
		check(full_energy>40 and ratio>0.25 and ratio<0.75,"native snow really fades in GPU pixels, not merely a boolean")
	var alpha:float = view.weather_fade
	time = view.weather_time
	conditions.advance(10.0)
	check(view.weather_fade==alpha and view.weather_time==time,"pause freezes the transition and flake movement")
	game.now_stop_state = false
	Engine.time_scale = 0
	conditions.advance(10.0)
	check(view.weather_fade==alpha and view.weather_time==time,"zero game speed freezes the fade")
	Engine.time_scale = 1
	game.now_stop_state = true
	step_weather(0.45)
	check(view.weather_fade==0.0,"off tail reaches complete transparency after 0.9 combat seconds")
	time = view.weather_time
	step_weather(10.0)
	check(view.weather_time==time and field.environment_patches==retained,"fully hidden weather stops animation work and generation")
	if gpu:
		var gone:Image = await grab("04_off_gone")
		check(energy(bare,gone)<0.01,"fully faded snow leaves zero visible flakes")
	setting("Environment","snow")
	check(view.weather_fade==0.0 and view.weather_time==time,"re-enable starts from current opacity without rewinding positions")
	step_weather(0.45)
	setting("Environment","none")
	check(is_equal_approx(view.weather_fade,0.5),"switching off during fade-in preserves current opacity")
	step_weather(0.225)
	check(is_equal_approx(view.weather_fade,0.25),"interrupted fade-in smoothly reverses toward zero")
	time = view.weather_time
	setting("Environment","snow")
	check(is_equal_approx(view.weather_fade,0.25) and view.weather_time==time and view.weather_phases==phases,"switching on during fade-out preserves opacity, time and native flake phase")
	step_weather(0.225)
	check(is_equal_approx(view.weather_fade,0.5),"interrupted fade-out smoothly reverses toward full opacity")
	conditions.refresh_layout()
	check(is_equal_approx(view.weather_fade,0.5),"periodic layout refresh never restarts the transition")
	conditions.refresh_layout(true)
	check(view.weather_fade==0.0 and view.weather_time==0.0,"actual reset still starts a clean weather lifecycle")
	await finish(0 if failures==0 else 1)
