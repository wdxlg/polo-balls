extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var failures:int = 0
var checks:int = 0
var finishing:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0",master:Node = null) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Master = master
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	return unit
func freeze_move(unit:Node2D) -> void:
	unit.Speed = 0
	unit.default_properties["Speed"] = 0
func obstacle(point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = point
	return body
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(4,4)
	camera.make_current()
	var source:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-150,0),"Team1")
	freeze_move(source)
	var key:StringName = &"minecraft_skeleton_execution_slowmo_last_usec"
	var low:Dictionary = await execution_fixture(99,center,source)
	var low_ref:WeakRef = weakref(low.unit)
	var speed_before:float = Engine.time_scale
	low.control._begin_execution()
	check(low.control._executing,"below-100 unit still begins original execution animation")
	check(not low.control._cinematic_focus_requested and world._cinematic_focus_requests.is_empty(),"max HP 99 requests neither zoom nor slow motion")
	check(not world.has_meta(key),"small execution does not create or consume shared cooldown")
	await create_timer(0.23).timeout
	check(is_equal_approx(Engine.time_scale,speed_before),"small execution leaves actual world time scale unchanged")
	var sound:bool = false
	for node:Node in root.get_children():
		if node is AudioStreamPlayer and str(node.name).begins_with("骷髅拔箭处决音效") and node.playing: sound = true
	check(sound,"small execution retains pull-arrow sound")
	await create_timer(0.30).timeout
	check(low_ref.get_ref() == null and is_instance_valid(low.arrow) and low.arrow._mode == 0,"small execution kills target and releases real flying arrow")
	check(not world.has_meta(key),"finishing small execution still leaves cooldown unused")
	var normal:Dictionary = await execution_fixture(100,center+Vector2(100,0),source)
	normal.control._begin_execution()
	var id:int = normal.control.get_instance_id()
	var request:Dictionary = world._cinematic_focus_requests.get(id,{})
	check(normal.control._cinematic_focus_requested and is_equal_approx(request.get("slow",0),0.25) and is_equal_approx(request.get("zoom",0),1.55),"exactly 100 max HP still receives original 0.25 slow and 1.55 zoom despite only four current HP")
	var stamp:int = int(world.get_meta(key,-1))
	check(stamp>=0,"eligible execution can consume cooldown immediately after small unit")
	var second:Dictionary = await execution_fixture(30,center+Vector2(0,100),source)
	second.control._begin_execution()
	check(not second.control._cinematic_focus_requested and not world._cinematic_focus_requests.has(second.control.get_instance_id()),"30-HP execution adds no request during another unit's active cinematic")
	check(int(world.get_meta(key,-1)) == stamp and world._cinematic_focus_requests.has(id),"small execution neither updates cooldown nor cancels another unit's focus")
	second.control._release_execution_camera_focus()
	check(world._cinematic_focus_requests.has(id),"small cleanup cannot release another execution's camera ownership")
	var later:Dictionary = await execution_fixture(400,center+Vector2(100,100),source)
	later.control._begin_execution()
	request = world._cinematic_focus_requests.get(later.control.get_instance_id(),{})
	check(is_equal_approx(request.get("slow",0),1.0) and is_equal_approx(request.get("zoom",0),1.55),"large unit during existing cooldown retains old zoom-only behavior")
	check(int(world.get_meta(key,-1)) == stamp,"cooldown-suppressed execution does not extend the shared timer")
	await create_timer(0.65).timeout
	check(world._cinematic_focus_requests.is_empty(),"all actual executions release their own requests after completion")
	print("MC12_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func execution_fixture(max_hp:int,point:Vector2,source:Node2D) -> Dictionary:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.Team = "Team0"
	unit.Max_health = max_hp
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	unit.state_machine.set_physics_process(false)
	var shot:Node2D = arrow(source,unit.global_position,Vector2.RIGHT)
	shot.set_physics_process(false)
	shot._request_embed_in_enemy(unit)
	await process_frame
	await process_frame
	var control:Node = unit.get_node("MinecraftArrowWoundController")
	control.set_process(false)
	# 设定测试残血不应先制造普通大伤害镜头，避免混入被测的处决镜头。
	var stopped:bool = game.now_stop_state
	game.now_stop_state = true
	unit.health = 4
	game.now_stop_state = stopped
	return {"unit":unit,"arrow":shot,"control":control}
func arrow(source:Node2D,point:Vector2,dir:Vector2) -> Node2D:
	var result:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(result,true)
	result.global_position = point
	result.configure(source,source.Team,dir,360.0,8.0,3.0,0.0,90.0,5.0)
	return result
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC12_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
func _stop_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		if node.is_in_group("MCNativeSFX"): node.queue_free()
	for child:Node in node.get_children(): _stop_audio(child)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("MC12_EXIT=",code)
	quit(code)
