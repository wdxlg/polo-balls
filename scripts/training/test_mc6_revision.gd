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
	var owner_unit:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-250,0))
	owner_unit.state_machine.set_physics_process(false)
	var fallback:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(250,0),"Team1")
	freeze_move(fallback)
	var seekers:Array[Node2D] = []
	for path:String in ["res://scenes/characters/我的世界/唤魔者.tscn","res://scenes/characters/我的世界/潜影贝.tscn","res://scenes/characters/我的世界/末影人.tscn","res://scenes/creatures/唤魔恼鬼.tscn","res://scenes/shooter/潜影弹.tscn"]:
		var seeker:Node2D = spawn(path,center,"Team0",owner_unit)
		seeker.state_machine.set_physics_process(false)
		seekers.append(seeker)
		var victim:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(25,0),"Team1")
		freeze_move(victim)
		check(seeker.mc_nearest(100.0) == victim,"seeker caches nearby enemy: "+path.get_file())
		var stale:Variant = victim
		var dead_ref:WeakRef = weakref(victim)
		victim.health = 0
		await process_frame
		await process_frame
		await process_frame
		check(dead_ref.get_ref() == null,"cached enemy really dies and is freed: "+path.get_file())
		seeker._mc_target_wait = 1.0
		check(not seeker.mc_enemy(stale),"freed reference is rejected without argument type error: "+path.get_file())
		check(seeker.mc_nearest(0.017) == fallback,"positive cache timer reacquires live enemy after death: "+path.get_file())
	var vex:Node2D = seekers[3]
	var queued:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(15,0),"Team1")
	vex.mc_nearest(100.0)
	queued.queue_free()
	check(not vex.mc_enemy(queued) and vex.mc_nearest(0.01) == fallback,"queued-but-not-yet-freed enemies are rejected too")
	var unrelated := Node.new()
	check(not vex.mc_enemy(unrelated) and not vex.mc_enemy(null),"enemy predicate safely rejects wrong node types and null")
	unrelated.free()
	var stable:bool = true
	for i:int in range(20):
		var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(10,0),"Team1")
		vex.mc_nearest(100.0)
		target.queue_free()
		await process_frame
		await process_frame
		vex._mc_target_wait = 1.0
		stable = stable and vex.mc_nearest(0.017) == fallback
	check(stable,"twenty consecutive cached target deletions reacquire safely")
	fallback.queue_free()
	await process_frame
	await process_frame
	check(vex.mc_nearest(0.01) == null,"no remaining enemy clears the cache instead of reusing a dead object")
	var ender:Node2D = seekers[2]
	for i:int in [0,1,3,4]: seekers[i].global_position = center+Vector2(-200,-200)
	await create_timer(1.5).timeout
	var fx:Script = load("res://scripts/effects/我的世界/mc_visual_effects.gd")
	fx.portal(ender,ender.global_position,8)
	var native:Array[Node] = get_nodes_in_group("MCEnderParticle")
	var sizes_ok:bool = not native.is_empty()
	for particle:Node in native:
		var w:float = particle.texture.get_width()*particle.scale.x
		sizes_ok = sizes_ok and w >= 3.5 and w <= 5.0
	check(sizes_ok,"enderman and clone portal particles are enlarged to 3.5-5 world units")
	fx.spark(ender,ender.global_position)
	var sparks:Array[Node] = get_nodes_in_group("MCShulkerTrail")
	check(not sparks.is_empty() and is_equal_approx(sparks[-1].texture.get_width()*sparks[-1].scale.x,1.4),"shulker trail size is unchanged")
	camera.global_position = center
	await capture("PORTAL_SIZE")
	var impact:Node2D = load("res://scripts/effects/combat_impact_layer.gd").new()
	world.add_child(impact)
	check(impact.critical_particle_count(50.0) == 0 and impact.critical_particle_count(50.01) > 0,"critical threshold remains strictly greater than fifty")
	check(impact.critical_particle_count(200.0) > impact.critical_particle_count(60.0),"critical particle count still scales with damage")
	impact.add_impact(ender.get_instance_id(),ender.global_position,18.0,1.0,true,false,200.0)
	var larger:bool = not impact._particles.is_empty()
	for p:Dictionary in impact._particles: larger = larger and p["size"] >= 7.0 and p["size"] <= 9.4
	check(larger,"critical particles have doubled width and height")
	check(impact.critical_particle_alpha(0.37,0.37) == 0.0,"critical particles retain their quick final fade")
	await create_timer(0.04).timeout
	await capture("CRITICAL_SIZE")
	print("MC6_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC6_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC6_EXIT=",code)
	quit(code)
