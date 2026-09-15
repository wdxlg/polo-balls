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
	for gravity:Vector2 in [Vector2.DOWN,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
		var closed:bool = checks != 3
		var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center+Vector2(120,100))
		var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(120,100),"Team1")
		enemy.state_machine.set_physics_process(false)
		shell.state_machine.set_physics_process(false)
		shell.gravity_direction = gravity
		shell.up_direction = -gravity
		shell.shell_open = not closed
		shell._shell_left = 99
		shell._shots_left = 2
		shell._shot_wait = 99
		shell.hurt_teleport_chance = 0
		shell._turn_wait = 10
		shell._external_directional_gravity_lateral_sign = 1
		shell._update_shell_visual()
		var tangent:Vector2 = gravity.orthogonal()
		var origin:Vector2 = center+Vector2(120,100)
		var support:StaticBody2D = obstacle(origin+gravity*40,Vector2(400,20) if gravity == Vector2.DOWN else Vector2(20,400))
		var h_shell:Vector2 = half_size(shell)
		var h_enemy:Vector2 = half_size(enemy)
		var shell_radius:float = h_shell.y if gravity == Vector2.DOWN else h_shell.x
		var enemy_radius:float = h_enemy.y if gravity == Vector2.DOWN else h_enemy.x
		enemy.global_position = origin+gravity*(30-enemy_radius)
		shell.global_position = origin+gravity*(30-shell_radius-0.2)-tangent*45
		shell.clear_external_directional_gravity_velocity()
		shell.direction = tangent
		await physics_frame
		shell.state_machine.set_physics_process(true)
		var collided:bool = false
		for frame:int in range(150):
			await physics_frame
			if shell._external_directional_gravity_lateral_sign < 0:
				collided = true
				break
		check(collided,"real character collision reverses shulker tangent: "+str(gravity)+(" closed" if closed else " open"))
		var contact_position:Vector2 = shell.global_position
		await create_timer(0.25).timeout
		check((shell.global_position-contact_position).dot(tangent)<-0.5,"rebound persists in next moves instead of being overwritten")
		check(shell.gravity_direction == gravity and shell._shots_left == 2 and shell._turn_wait>0,"character rebound preserves wall attachment and volley even during wall-turn grace")
		shell.queue_free()
		enemy.queue_free()
		support.queue_free()
		await process_frame
		await process_frame
	var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center)
	shell.state_machine.set_physics_process(false)
	shell._last_requested_velocity = Vector2(20,100)
	shell._bounce_from_character(Vector2.UP)
	check(shell._external_directional_gravity_velocity.y<0 and shell.gravity_direction == Vector2.DOWN,"falling onto a character bounces vertical velocity without treating character as a wall")
	shell._last_requested_velocity = Vector2.RIGHT*50
	shell._bounce_from_character(Vector2.LEFT)
	var sign_before:float = shell._external_directional_gravity_lateral_sign
	shell._last_requested_velocity = Vector2.LEFT*50
	shell._bounce_from_character(Vector2.LEFT)
	check(shell._external_directional_gravity_lateral_sign == sign_before,"separating contact does not flip back toward the character")
	shell.accept_wall_normal(Vector2.RIGHT)
	check(shell.gravity_direction == Vector2.LEFT,"real wall attachment rule remains available")
	shell.accept_wall_normal(Vector2.DOWN)
	check(shell.gravity_direction != Vector2.UP,"ceiling still cannot become an attachment surface")
	shell.queue_free()
	await process_frame
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(120,100),"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Max_health = 10000
	enemy.health = 10000
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",enemy.global_position-Vector2(60,0))
	ender.state_machine.set_physics_process(false)
	ender.gaze_range = 0
	ender.chance_dodge = 0
	await physics_frame
	await process_frame
	check(ender.rage_remaining == 0 and ender.Has_Collision_Damage and ender.self_hitbox.monitoring,"fresh calm Enderman has body damage and active hitbox")
	ender.direction = Vector2.RIGHT
	ender.state_machine.set_physics_process(true)
	await create_timer(0.9).timeout
	ender.state_machine.set_physics_process(false)
	check(enemy.health<10000 and ender.rage_remaining == 0,"calm Enderman actually inflicts collision damage without anger")
	ender.gaze_charge = 1
	ender.update_rage(0,false,false)
	ender.update_rage(100,false,false)
	await physics_frame
	await process_frame
	check(ender.rage_remaining == 0 and ender.Has_Collision_Damage and ender.self_hitbox.monitoring,"rage exit does not switch off collision damage or monitoring")
	enemy.health = 10000
	ender.global_position = enemy.global_position-Vector2(60,0)
	ender.direction = Vector2.RIGHT
	ender.state_machine.set_physics_process(true)
	await create_timer(0.9).timeout
	ender.state_machine.set_physics_process(false)
	check(enemy.health<10000 and ender.rage_remaining == 0,"Enderman still deals real collision damage after rage expires")
	print("MC10_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func half_size(unit:Node2D) -> Vector2:
	var shape:CollisionShape2D = unit.collision_shape_2d
	var half:Vector2 = shape.shape.get_rect().size*0.5
	var t:Transform2D = shape.global_transform
	return Vector2(absf(t.x.x)*half.x+absf(t.y.x)*half.y,absf(t.x.y)*half.x+absf(t.y.y)*half.y)
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
	print("MC10_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC10_EXIT=",code)
	quit(code)
