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
	var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center)
	shell.state_machine.set_physics_process(false)
	shell.hurt_teleport_chance = 0
	shell.hurt_voice_chance = 0
	for age:float in [0.0,9.99,10.0,20.0,60.0]:
		shell._combat_elapsed = age
		var gain:int = int(age/10.0)
		check(shell.get_volley_count_range() == Vector2i(2+gain,4+gain),"volley min and max grow once every ten seconds at "+str(age))
	shell._combat_elapsed = 9.9
	shell._shell_left = 99
	shell.tick_physics(0,0.2)
	check(shell.get_volley_count_range() == Vector2i(3,5),"actual active combat tick advances growth across boundary")
	var elapsed:float = shell._combat_elapsed
	game.now_stop_state = true
	shell.tick_physics(0,10)
	check(is_equal_approx(shell._combat_elapsed,elapsed),"stopped battle does not accumulate volley growth")
	game.now_stop_state = false
	shell._combat_elapsed = 40
	shell.shell_open = false
	shell._shell_left = 0
	shell.tick_physics(0,0)
	var total:int = shell._shots_left
	check(total>=6 and total<=8 and shell.shell_open,"opening selects the increased six-to-eight round volley")
	var bullet_before:int = get_nodes_in_group("MCShulkerBullet").size()
	for i:int in range(total):
		shell._shot_wait = 0
		shell.tick_physics(0,0.4)
	check(get_nodes_in_group("MCShulkerBullet").size()-bullet_before == total,"entire increased volley really spawns instead of being cut off by old open duration")
	check(shell._shots_left == 0 and shell.shell_open,"overdue open phase lasts until final shot")
	shell.tick_physics(0,0.01)
	check(not shell.shell_open,"shell closes again after increased volley completes")
	for node:Node in get_nodes_in_group("MCShulkerBullet"): node.queue_free()
	await process_frame
	await process_frame
	var blockers:Array[Node] = []
	for i:int in range(64):
		var node := Node.new()
		world.add_child(node)
		node.add_to_group("MCShulkerBullet")
		blockers.append(node)
	shell.shell_open = true
	shell._shots_left = 3
	shell._shot_wait = 0
	shell._shell_left = -1
	shell.tick_physics(0,0.01)
	check(shell._shots_left == 3 and shell.shell_open,"full projectile budget waits without discarding unfired rounds")
	for node:Node in blockers: node.free()
	shell.tick_physics(0,0.11)
	check(shell._shots_left == 2 and get_nodes_in_group("MCShulkerBullet").size() == 1,"volley resumes when projectile capacity becomes available")
	for node:Node in get_nodes_in_group("MCShulkerBullet"): node.queue_free()
	await process_frame
	shell.shell_open = false
	shell._update_shell_visual()
	_stop_audio(root)
	await process_frame
	await process_frame
	var bus:int = AudioServer.get_bus_index("GameplayRecord")
	var saved_volume:float = AudioServer.get_bus_volume_db(bus)
	var saved_mute:bool = AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus,false)
	AudioServer.set_bus_volume_db(bus,0)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1
	AudioServer.add_bus_effect(bus,cap)
	var listener := AudioListener2D.new()
	world.add_child(listener)
	listener.global_position = shell.global_position
	listener.make_current()
	var hp:int = shell.health
	var state_before:int = shell.state_machine.current_state
	var accepted:bool = source.self_hitbox.try_hit_hurtbox(shell.self_hurtbox)
	check(not accepted and shell.health == hp,"closed shell rejects actual standard Hitbox before damage or hurt state")
	check(shell.state_machine.current_state == state_before and is_zero_approx(shell._hit_white_visual_power),"standard block does not enter Hurt or turn the shell white")
	check(get_nodes_in_group("MCShulkerBlockRing").size() == 1,"standard block generates spear-style white ring")
	var visible_streak:bool = false
	for node:Node in world.get_children():
		if node.get_script() == shell.HIT_BURST_EFFECT_SCRIPT: visible_streak = true
	check(visible_streak,"standard block also generates shared white burst streaks")
	var defensive:AudioStreamPlayer2D
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sound_event","") == "entity.shulker.hurt_closed": defensive = node
	check(is_instance_valid(defensive) and defensive.playing and defensive.volume_db>=-0.1,"closed hurt sound always plays at clear volume even when hurt probability is zero")
	camera.global_position = shell.global_position
	await capture("CLOSED_BLOCK")
	await create_timer(0.25).timeout
	var frames:PackedVector2Array = cap.get_buffer(cap.get_frames_available())
	var peak:float = 0
	for sample:Vector2 in frames: peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	print("MC11_CLOSED_AUDIO frames=",frames.size()," peak=",peak)
	check(frames.size()>100 and peak>0.0001,"defensive hurt_closed sound produces real nonzero audio PCM")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	AudioServer.set_bus_volume_db(bus,saved_volume)
	AudioServer.set_bus_mute(bus,saved_mute)
	check(get_nodes_in_group("MCShulkerBlockRing").is_empty(),"short white block ring fades and cleans up")
	shell.receive_positional_damage(100,source.global_position,true,source)
	shell.hit_white(true)
	shell.hit_white_visual_only()
	shell.hit_white_method(1)
	check(shell.health == hp and is_zero_approx(shell._hit_white_visual_power),"direct ignore-block and all legacy white-flash entry points remain blocked without white body")
	check(get_nodes_in_group("MCShulkerBlockRing").size() == 1,"positional damage has same block effect")
	await create_timer(0.15).timeout
	shell.health = 0
	check(shell.health == hp and not shell._teleport_pending,"raw lethal write is restored and never causes hurt teleport")
	check(get_nodes_in_group("MCShulkerBlockRing").size() == 1,"raw health block also has visible feedback")
	await create_timer(0.15).timeout
	_stop_audio(root)
	await process_frame
	await process_frame
	for i:int in range(24):
		var dummy := AudioStreamPlayer2D.new()
		world.add_child(dummy)
		dummy.add_to_group("MCNativeSFX")
		dummy.set_meta("mc_sound_event","entity.evoker.ambient")
	shell.take_damage(10)
	var second:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center+Vector2(80,0))
	second.state_machine.set_physics_process(false)
	second.take_damage(10)
	var count:int = 0
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sound_event","") == "entity.shulker.hurt_closed" and node.playing: count += 1
	check(count == 2,"two shulkers can both play defensive sounds in the same frame despite full ordinary audio budget")
	check(get_nodes_in_group("MCNativeSFX").size() == 24,"priority defensive sounds still respect the 24-voice cap")
	shell.shell_open = true
	shell._update_shell_visual()
	shell.receive_positional_damage(10,source.global_position,true,source)
	check(shell.health == hp-10 and shell._hit_white_visual_power>0,"actual open-shell damage still has ordinary hurt white flash")
	shell.shell_open = false
	shell._update_shell_visual()
	check(is_zero_approx(shell._hit_white_visual_power),"closing shell immediately clears any unfinished actual-hurt flash")
	print("MC11_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
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
	print("MC11_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC11_EXIT=",code)
	quit(code)
