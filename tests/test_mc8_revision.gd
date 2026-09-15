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
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(200,200))
	ender.state_machine.set_physics_process(false)
	ender.chance_dodge = 0
	ender.chance_clone_on_projectile_dodge = 0
	var charge:float = ender.gaze_charge
	check(ender.try_full_projectile_dodge() and is_equal_approx(ender.gaze_charge-charge,0.08),"one actual dodge adds a small eight-percent anger charge")
	ender.try_full_projectile_dodge()
	check(is_equal_approx(ender.gaze_charge-charge,0.08),"same dodge grace does not count the same attack repeatedly")
	ender._dodge_grace = 0
	ender.gaze_charge = 0.96
	ender.try_full_projectile_dodge()
	check(ender.rage_remaining > 0,"dodge anger can finish charging into rage")
	ender.global_position = center+Vector2(250,250)
	var clone:Node2D = spawn("res://scenes/creatures/末影分身.tscn",source.global_position+Vector2(35,0),"Team0",ender)
	freeze_move(clone)
	clone._life_left = 30
	await create_timer(0.25).timeout
	check(clone.is_combat_targetable() and clone.is_combat_lockable(),"clone opts into damage and locking contracts")
	check(source.Nearest_Enemy == clone,"actual World nearest-enemy scan locks onto clone")
	check(clone.collision_layer == 0 and clone.collision_mask == 1,"clone remains obstacle-only rather than gaining character collision")
	var shot:Node2D = arrow(source,source.global_position,Vector2.RIGHT)
	var hp:int = clone.health
	await create_timer(0.15).timeout
	check(clone.health < hp and shot.get_parent() == clone.graphics,"real flying skeleton arrow hits and embeds into targetable clone hurtbox")
	shot.queue_free()
	clone.retire()
	await process_frame
	var hammer:Node2D = spawn("res://scenes/characters/我的世界/重锤.tscn",center)
	hammer.state_machine.set_physics_process(false)
	var embedded:Node2D = arrow(source,hammer.image.global_position+Vector2(3,0),Vector2.RIGHT)
	embedded.set_physics_process(false)
	embedded._capture_embed_anchor(hammer)
	var hit_pose:Transform2D = embedded._embed_local_pose
	embedded._request_embed_in_enemy(hammer)
	# 在 deferred 挂接执行前就腾空/旋转，模拟命中回调引发姿态变化。
	hammer._begin_flight(1)
	hammer._update_flight(0.12)
	await process_frame
	await process_frame
	check(embedded.get_parent() == hammer.image,"hammer arrow attaches to Image below animated Graphics")
	check(embedded.global_transform.is_equal_approx(hammer.image.global_transform*hit_pose),"pre-attachment jump keeps original local impact pose rather than world position")
	var before:Vector2 = embedded.global_position
	hammer._update_flight(0.15)
	check(embedded.global_position.distance_to(before)>2 and embedded.global_transform.is_equal_approx(hammer.image.global_transform*hit_pose),"embedded arrow follows actual hammer flight translation rotation and scale")
	hammer.image.rotation += 0.8
	check(embedded.get_flight_direction().is_equal_approx(embedded.global_transform.x.normalized()),"arrow execution direction follows rotated hammer rather than old shot direction")
	var airborne_hit:Node2D = arrow(source,source.global_position,Vector2.RIGHT)
	await create_timer(0.5).timeout
	check(airborne_hit.get_parent() == hammer.image and airborne_hit.global_position.distance_to(hammer.image.global_position) < 35,"real arrow hitting an already airborne hammer maps onto the airborne visual, not ground")
	check(airborne_hit.get_flight_direction().dot(Vector2.RIGHT) > 0.99,"new airborne hit keeps its incoming world direction")
	airborne_hit.queue_free()
	camera.global_position = hammer.image.global_position
	camera.zoom = Vector2(4,4)
	await capture("HAMMER_ARROW")
	var release_dir:Vector2 = embedded.get_flight_direction()
	var release_position:Vector2 = embedded.global_position
	embedded.launch_execution_flyout(release_dir)
	check(embedded.global_position.is_equal_approx(release_position) and Vector2.RIGHT.rotated(embedded.global_rotation).is_equal_approx(release_dir),"flyout preserves position and has correct world orientation after reparent")
	check(embedded.global_scale.is_equal_approx(Vector2.ONE),"flyout restores original arrow scale after enlarged hammer")
	embedded.queue_free()
	hammer.queue_free()
	await process_frame
	var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center)
	shell.state_machine.set_physics_process(false)
	check(is_equal_approx(shell.hurt_teleport_chance,0.10),"shulker hurt teleport defaults to ten percent")
	shell.shell_open = true
	shell._update_shell_visual()
	shell._shots_left = 3
	shell._shot_wait = 0.21
	shell._shell_left = 1.45
	shell.Attacking = true
	var shell_arrow:Node2D = arrow(source,shell.global_position+Vector2(-8,0),Vector2.RIGHT)
	shell_arrow.set_physics_process(false)
	shell_arrow._capture_embed_anchor(shell)
	var local_pose:Transform2D = shell_arrow._embed_local_pose
	var old_position:Vector2 = shell.global_position
	shell.hurt_teleport_chance = 1
	shell_arrow._apply_damage(shell,8)
	shell_arrow._request_embed_in_enemy(shell)
	await process_frame
	await process_frame
	check(shell.global_position.distance_to(old_position)>10,"arrow damage really triggers deferred shulker teleport")
	check(shell_arrow.get_parent() == shell.graphics and shell_arrow.global_transform.is_equal_approx(shell.graphics.global_transform*local_pose),"arrow follows teleport which occurs before deferred embedding")
	check(shell._shots_left == 3 and is_equal_approx(shell._shot_wait,0.21) and is_equal_approx(shell._shell_left,1.45) and shell.Attacking,"pure teleport preserves current volley count cooldown shell phase and attacking flag")
	var previous:Transform2D = shell_arrow.transform
	shell.mc_try_wall_teleport()
	check(shell_arrow.transform.is_equal_approx(previous) and shell_arrow.global_transform.is_equal_approx(shell.graphics.global_transform*previous),"already embedded arrow follows another teleport and wall rotation")
	camera.global_position = shell.global_position
	await capture("TELEPORTED_ARROW")
	var count_before:int = get_nodes_in_group("MCShulkerBullet").size()
	shell._shot_wait = 0
	shell.tick_physics(0,0.01)
	check(shell._shots_left == 2 and get_nodes_in_group("MCShulkerBullet").size() > count_before,"next shot of the existing volley still fires after teleport")
	# 同样覆盖挂到移动障碍物之前的位移。
	var block:StaticBody2D = obstacle(center+Vector2(0,150),Vector2(5,40))
	var wall_arrow:Node2D = arrow(source,block.global_position+Vector2(2,0),Vector2.RIGHT)
	wall_arrow.set_physics_process(false)
	var wall_local:Transform2D = block.global_transform.affine_inverse()*wall_arrow.global_transform
	wall_arrow._stick_to_terrain(block)
	block.global_position += Vector2(30,10)
	block.rotation = 0.3
	await process_frame
	await process_frame
	check(wall_arrow.global_transform.is_equal_approx(block.global_transform*wall_local),"terrain embed also survives pre-attachment movement and rotation")
	var execution_target:Node2D = spawn("res://scenes/characters/我的世界/重锤.tscn",center+Vector2(100,150))
	execution_target.state_machine.set_physics_process(false)
	var execution_arrow:Node2D = arrow(source,execution_target.global_position+Vector2(2,0),Vector2.RIGHT)
	execution_arrow.set_physics_process(false)
	execution_arrow._request_embed_in_enemy(execution_target)
	await process_frame
	await process_frame
	var execution_ref:WeakRef = weakref(execution_target)
	execution_target.health = 4
	await create_timer(0.10).timeout
	check(execution_target.get_node("MinecraftArrowWoundController")._executing,"low-health embedded arrow still starts original execution sequence")
	execution_target.image.rotation += 0.65
	var expected_release:Vector2 = execution_arrow.get_flight_direction()
	await create_timer(0.65).timeout
	check(execution_ref.get_ref() == null and is_instance_valid(execution_arrow) and execution_arrow._mode == 0,"execution kills target while arrow actually flies out instead of being deleted with body")
	check(execution_arrow.get_flight_direction().is_equal_approx(expected_release) and execution_arrow.global_transform.x.normalized().is_equal_approx(expected_release),"execution uses latest rotated direction at release")
	print("MC8_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func arrow(source:Node2D,point:Vector2,dir:Vector2) -> Node2D:
	var result:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(result)
	result.global_position = point
	result.configure(source,source.Team,dir,360.0,8.0,3.0,0.0,90.0,5.0)
	return result
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC8_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC8_EXIT=",code)
	quit(code)
