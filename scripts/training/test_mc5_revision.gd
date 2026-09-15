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
	var caster:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-300,0))
	caster.state_machine.set_physics_process(false)
	var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center)
	shell.state_machine.set_physics_process(false)
	camera.global_position = center+Vector2(0,-6)
	var aligned:bool = true
	for angle:float in [0.0,PI*0.5,-PI*0.5]:
		shell.graphics.rotation = angle
		shell.shell_open = false
		shell._update_shell_visual()
		var bottom:Vector2 = shell.image.to_global(Vector2(0,shell.image.texture.get_height()*0.5))
		if angle == 0.0: await capture("SHELL_CLOSED")
		shell.shell_open = true
		shell._update_shell_visual()
		var other:Vector2 = shell.image.to_global(Vector2(0,shell.image.texture.get_height()*0.5))
		aligned = aligned and bottom.distance_to(other) < 0.001
		if angle == 0.0: await capture("SHELL_OPEN")
	check(aligned,"open and closed shell share identical bottom anchor on floor and both walls")
	shell.graphics.rotation = 0.0
	var vex:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn",center+Vector2(-200,0),"Team0",caster)
	vex._life_left = 100
	vex._attack_wait = 100
	vex.direction = Vector2.RIGHT
	vex._roam_point = vex.global_position+Vector2(150,0)
	vex._roam_wait = 100
	await create_timer(0.15).timeout
	check(vex.is_character_visual_flipped_h() == vex.dir_left,"vex visibly faces right while moving right")
	vex.direction = Vector2.LEFT
	vex._roam_point = vex.global_position+Vector2(-150,0)
	await create_timer(0.15).timeout
	check(vex.is_character_visual_flipped_h() != vex.dir_left,"vex visibly faces left while moving left")
	var arena:Rect2 = vex.mc_arena_rect().grow(-10)
	vex.global_position = Vector2(arena.end.x-0.1,center.y)
	vex.direction = Vector2.RIGHT
	vex._charging = true
	vex._dash_direction = Vector2.RIGHT
	vex._dash_distance = 100
	await create_timer(0.10).timeout
	check(arena.grow(0.01).has_point(vex.global_position) and not vex._charging,"dash cannot leave the visible arena and ends at outer boundary")
	check(vex.collision_mask == 0,"outer boundary guard does not remove interior wall phasing")
	vex.state_machine.set_physics_process(false)
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(200,-150))
	freeze_move(ender)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-220,-70),"Team1")
	enemy.state_machine.set_physics_process(false)
	var clone:Node2D = spawn("res://scenes/creatures/末影分身.tscn",center+Vector2(-220,0),"Team0",ender)
	clone.direction = Vector2.RIGHT
	var start:Vector2 = clone.global_position
	await create_timer(0.35).timeout
	check(clone.global_position.x > start.x+15 and absf(clone.direction.y) < 0.01,"clone keeps ordinary movement instead of steering into nearby enemy")
	var wall:StaticBody2D = obstacle(clone.global_position+Vector2(28,0),Vector2(4,70))
	await create_timer(0.45).timeout
	check(clone.direction.x < 0,"clone uses ordinary wall rebound")
	wall.queue_free()
	var ids:Dictionary = {}
	for particle:Node in get_nodes_in_group("MCEnderParticle"):
		ids[particle.get_meta("mc_emitter_id",0)] = true
	check(ids.has(ender.get_instance_id()) and ids.has(clone.get_instance_id()),"both non-raging enderman and clone continuously emit native particles")
	ender.state_machine.set_physics_process(false)
	clone.state_machine.set_physics_process(false)
	ender.gaze_charge = 0
	ender.rage_remaining = 0
	ender.update_rage(ender.gaze_charge_seconds,true,true)
	var elapsed:float = 0.0
	while ender.rage_remaining > 0 and elapsed < 6:
		ender.update_rage(0.1,false,true)
		elapsed += 0.1
	check(ender.rage_duration == 3.0 and elapsed <= 5.1 and ender.rage_remaining == 0,"continuous enemy watching cannot extend rage beyond five total seconds")
	var texts:Dictionary = {"count":0}
	var listener:Callable = func(node:Node):
		if node.scene_file_path == "res://scenes/damage_text.tscn": texts["count"] += 1
	node_added.connect(listener)
	enemy.global_position = center+Vector2(400,100)
	var bullet:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(100,100))
	bullet.direction = Vector2.RIGHT
	bullet._course = Vector2.RIGHT
	bullet._course_wait = 100
	await create_timer(0.30).timeout
	var trails:Array[Node] = get_nodes_in_group("MCShulkerTrail")
	check(trails.size() >= 3 and trails[0].texture.resource_path.contains("glitter_"),"shulker projectile leaves original end-rod glitter trail")
	check(trails[0].self_modulate.r > 0.95 and trails[0].self_modulate.g > 0.9,"trail is white rather than purple portal particles")
	var ref:WeakRef = weakref(bullet)
	bullet.take_damage(999,true)
	bullet.take_damage(999,true)
	bullet.take_damage(999,true)
	await process_frame
	await process_frame
	check(ref.get_ref() == null and texts["count"] == 0,"destroyed projectile produces no self damage floating text")
	check(not get_nodes_in_group("MCShulkerTrail").is_empty(),"trail and impact sparks survive projectile deletion and fade independently")
	node_added.disconnect(listener)
	clone.global_position = center+Vector2(0,-80)
	var clone_ref:WeakRef = weakref(clone)
	clone.take_damage(1000,true)
	await process_frame
	await process_frame
	var burst:Array[Node] = get_nodes_in_group("MCCloneBurst")
	check(clone_ref.get_ref() == null and burst.size() >= 24,"destroyed clone is removed and bursts into many native purple particles")
	var burst_position:Vector2 = burst[0].global_position
	await create_timer(0.25).timeout
	check(burst[0].global_position.distance_to(burst_position) > 2.0,"clone fragments visibly disperse outward")
	# 清除旧分身烟雾，单独验证三角色和恼鬼的死亡姿势与烟雾。
	for old:Node in get_nodes_in_group("MCDeathSmoke"): old.queue_free()
	await process_frame
	var actors:Array[Node2D] = [caster,shell,ender,vex]
	var refs:Array[WeakRef] = []
	for i:int in range(actors.size()):
		var unit:Node2D = actors[i]
		unit.global_position = center+Vector2((i-1.5)*50,0)
		unit.state_machine.set_physics_process(true)
		refs.append(weakref(unit))
		unit.health = 0
	await create_timer(0.12).timeout
	var removed:int = 0
	for item:WeakRef in refs:
		if item.get_ref() == null: removed += 1
	check(removed == 4,"three dead actors and vex release gameplay nodes promptly")
	check(get_nodes_in_group("MCDeathPose").size() == 4,"all four keep detached red falling death visuals")
	camera.zoom = Vector2(2,2)
	camera.global_position = center
	await create_timer(0.25).timeout
	await capture("DEATH_POSES")
	await create_timer(0.65).timeout
	var smoke_count:int = 0
	for smoke:Node in get_nodes_in_group("MCDeathSmoke"):
		if smoke.visible and smoke.is_playing() and smoke.animation == &"死亡烟雾": smoke_count += 1
	check(smoke_count == 4 and get_nodes_in_group("MCDeathPose").is_empty(),"falling visuals finish then all four play existing Minecraft death smoke")
	await capture("DEATH_SMOKE")
	await create_timer(4.0).timeout
	check(get_nodes_in_group("MCDeathSmoke").is_empty(),"death smoke finishes and cleans itself up")
	print("MC5_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC5_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC5_EXIT=",code)
	quit(code)
