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
	var baseline:bool = "--baseline" in OS.get_cmdline_user_args()
	var units:Array[Node2D] = []
	for name:String in ["重锤","木矛"]:
		var unit:Node2D = spawn("res://scenes/characters/我的世界/"+name+".tscn",center+Vector2(0,60*units.size()))
		unit.state_machine.set_physics_process(false)
		units.append(unit)
		for i:int in range(6):
			var shot:Node2D = arrow(source,unit.image.global_position+Vector2(0,i-3),Vector2.RIGHT)
			shot.set_physics_process(false)
			shot._request_embed_in_enemy(unit)
	await process_frame
	await process_frame
	check(get_nodes_in_group("MinecraftSkeletonArrow").size() == 12,"twelve real arrows embedded before snapshots")
	for unit:Node2D in units:
		var original_count:int = get_nodes_in_group("MinecraftSkeletonArrow").size()
		var before:Array[Node] = world.get_children()
		if unit == units[0]: unit._spawn_swing_afterimage()
		else: unit._queue_wood_spear_afterimage(unit.image.global_transform,Vector2.RIGHT,0.20,0.34,Color.WHITE,0.5,1.8,Vector2.ONE)
		await process_frame
		await process_frame
		var ghosts:Array[Node2D] = []
		for child:Node in world.get_children():
			if not before.has(child) and child is Sprite2D: ghosts.append(child)
		check(not ghosts.is_empty(),"original weapon afterimage still generated: "+unit.name)
		var extra:int = get_nodes_in_group("MinecraftSkeletonArrow").size()-original_count
		print("MC9_SNAPSHOT_EXTRA_ARROWS ",unit.name,"=",extra)
		if not baseline:
			check(extra == 0,"weapon snapshot never duplicates real arrows: "+unit.name)
			var pure:bool = true
			for ghost:Node2D in ghosts:
				pure = pure and not has_collision_node(ghost)
			check(pure,"snapshot has no live physics or projectile children: "+unit.name)
		unit.global_position += Vector2(70,0)
		camera.global_position = center+Vector2(30,30)
		await capture(unit.name+("_BEFORE" if baseline else "_AFTER"))
		await create_timer(0.30).timeout
		check(get_nodes_in_group("MinecraftSkeletonArrow").size() == 12,"afterimages expire without deleting original arrows: "+unit.name)
	if baseline:
		print("MC9_BASELINE_COMPLETE")
		finish(0)
		return
	# 非纯叶 Sprite 的兼容分支：保留普通装饰，递归排除它下面的箭。
	var unit:Node2D = units[0]
	var decoration := Node2D.new()
	unit.image.add_child(decoration)
	var nested_arrow:Node2D = arrow(source,unit.image.global_position,Vector2.RIGHT)
	nested_arrow.set_physics_process(false)
	nested_arrow.reparent(decoration)
	var snapshot:Node2D = unit._make_after_image_snapshot_visual(unit.image.texture)
	check(snapshot.get_child_count()>0 and not has_collision_node(snapshot),"fallback snapshot preserves decoration but prunes nested projectile before ready")
	snapshot.free()
	nested_arrow.queue_free()
	decoration.queue_free()
	# 腾空→落地→延迟生成旧姿态残影；不能把当前身体的插箭复制到旧世界位置。
	unit._begin_flight(1)
	unit._update_flight(0.15)
	var old_pose:Transform2D = unit.image.global_transform
	unit._update_flight(2.0)
	await create_timer(0.25).timeout
	unit._spawn_after_image_at_transform(old_pose,Vector2.RIGHT)
	check(get_nodes_in_group("MinecraftSkeletonArrow").size() == 12,"delayed old airborne pose cannot resurrect arrow ghosts after landing")
	for actor:Node2D in units: actor.queue_free()
	await process_frame
	await process_frame
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(80,0))
	ender.state_machine.set_physics_process(false)
	ender.chance_clone_on_random_dodge = 0
	ender.chance_clone_on_projectile_dodge = 0
	ender.chance_dodge = 0
	ender._mc_rng.seed = 731927
	ender.direction = Vector2.RIGHT
	var directions:Array[Vector2] = []
	for i:int in range(5):
		ender._dodge_grace = 0
		ender.try_full_projectile_dodge(source)
		directions.append(ender.direction)
	var varied:bool = true
	for i:int in range(1,5): varied = varied and directions[i].distance_to(directions[i-1])>0.01 and is_equal_approx(directions[i].length(),1.0)
	check(varied,"successful defensive teleports select fresh normalized random movement directions")
	var last_dir:Vector2 = ender.direction
	ender.try_full_projectile_dodge(source)
	check(ender.direction == last_dir,"same dodge grace does not reroll direction again")
	ender.global_position = center+Vector2(80,0)
	source.global_position = center
	ender._dodge_grace = 0
	ender.gaze_charge = 1
	ender.update_rage(0,false,false)
	var anger:float = ender.gaze_charge
	var before_attack:Vector2 = ender.global_position
	ender._tick_rage_teleport(0.25)
	check(ender._rush_left>0 and ender.global_position.distance_to(before_attack)>10,"rage proactively teleports into ram without an incoming attack")
	check((ender.global_position-source.global_position).dot(ender._facing(source))<0 and ender.mc_body_position_clear(ender.global_position),"active teleport lands behind enemy at a safe non-overlapping position")
	check(ender.direction.dot(ender.global_position.direction_to(source.global_position))>0.99,"active ram points toward enemy")
	check(is_equal_approx(ender.gaze_charge,anger) and get_nodes_in_group("MCEndermanClone").is_empty(),"active attack is not counted as dodge and does not spawn dodge clones")
	var active_pos:Vector2 = ender.global_position
	ender._tick_rage_teleport(0.01)
	check(ender.global_position == active_pos,"active teleport has cooldown instead of firing every frame")
	var hp:int = source.health
	ender.state_machine.set_physics_process(true)
	await create_timer(0.32).timeout
	ender.state_machine.set_physics_process(false)
	check(source.health<hp,"active ram actually moves into enemy and inflicts collision damage")
	ender._dodge_grace = 0
	ender.chance_dodge = 0
	ender.try_full_projectile_dodge(source)
	check(ender._rush_left == 0 and ender._rage_teleport_wait>0.5,"guaranteed-only projectile dodge cancels ram and postpones proactive attack")
	active_pos = ender.global_position
	ender._tick_rage_teleport(0.10)
	check(ender.global_position == active_pos and ender._rush_left == 0,"guaranteed projectile dodge cannot immediately chain into a backstab")
	ender._rage_teleport_wait = 0
	ender._dodge_grace = 0
	ender.try_full_projectile_dodge(source)
	check(is_equal_approx(ender._rage_teleport_wait,0.30),"defensive dodge only adds short recovery, not a full cooldown reset that suppresses proactive attacks")
	ender._dodge_grace = 0
	ender.chance_dodge = 1
	ender._perform_dodge(source,true)
	check(ender._rush_left>0,"angry probability dodge keeps its existing behind-enemy counterattack")
	ender.global_position = center+Vector2(80,80)
	ender._rush_left = 0
	var behind:Vector2 = source.global_position-ender._facing(source)*(ender.get_crowd_separation_radius_world()+source.get_crowd_separation_radius_world()+10.0)
	var wall:StaticBody2D = obstacle(behind,Vector2(12,50))
	await physics_frame
	active_pos = ender.global_position
	check(not ender._try_rage_backstab(source) and ender.global_position == active_pos,"blocked back position is rejected instead of teleporting inside a wall")
	wall.queue_free()
	ender.rage_remaining = 0
	ender._rush_left = 0
	active_pos = ender.global_position
	ender._tick_rage_teleport(5)
	check(ender.global_position == active_pos,"non-raging Enderman does not proactively teleport attack")
	ender.rage_remaining = 2
	ender._rage_teleport_wait = 0
	source.queue_free()
	await process_frame
	ender._tick_rage_teleport(0.5)
	check(ender._rush_left == 0,"freed or missing enemy is safely ignored by proactive attack")
	print("MC9_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func has_collision_node(node:Node) -> bool:
	if node is CollisionObject2D: return true
	for child:Node in node.get_children():
		if has_collision_node(child): return true
	return false
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
	print("MC9_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC9_EXIT=",code)
	quit(code)
