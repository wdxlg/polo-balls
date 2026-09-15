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
	var evoker:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-200,0))
	evoker.state_machine.set_physics_process(false)
	var shell:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center)
	shell.state_machine.set_physics_process(false)
	var audio:Script = load("res://scripts/effects/我的世界/mc_native_audio.gd")
	check(shell.Max_health == 300 and shell.health == 300,"shulker starts at three hundred HP")
	shell.hurt_voice_chance = 0
	shell.take_damage(10000,true)
	check(shell.health == 300,"closed shell blocks even ignore-block direct damage")
	shell.health -= 10000
	await process_frame
	await process_frame
	check(is_instance_valid(shell) and shell.health == 300,"raw lethal HP write is blocked before death scheduling")
	check(sound_count("entity.shulker.hurt_closed") > 0,"closed block uses defensive hurt sound even with hurt voice chance zero")
	var old_position:Vector2 = shell.global_position
	check(not shell._teleport_pending and old_position == shell.global_position,"blocked damage does not trigger hurt teleport")
	shell.shell_open = true
	shell._update_shell_visual()
	shell.hurt_teleport_chance = 0
	shell.take_damage(20,true)
	check(shell.health == 280,"open shell takes full damage")
	shell.hurt_teleport_chance = 1
	shell._mc_rng.seed = 71
	shell.take_damage(20,true)
	await process_frame
	await process_frame
	check(shell.global_position.distance_to(old_position)>20 and shell.gravity_direction != Vector2.DOWN,"actual hurt can teleport onto another wall")
	check(shell.gravity_direction != Vector2.UP and shell.mc_body_position_clear(shell.global_position),"wall teleport is collision-safe and never attaches to ceiling")
	check(sound_count("entity.shulker.teleport") > 0,"successful wall teleport plays teleport sound")
	var successes:int = 0
	for i:int in range(8):
		var previous:Vector2 = shell.gravity_direction
		if shell.mc_try_wall_teleport() and shell.gravity_direction != previous: successes += 1
	check(successes == 8,"repeated random teleport selects a different valid wall face")
	# 随机受伤语音与常驻语音使用独立 RNG，不改变攻击/传送随机序列。
	evoker.hurt_voice_chance = 0
	var before:int = sound_count("entity.evoker.hurt")
	evoker.take_damage(10,true)
	check(sound_count("entity.evoker.hurt") == before,"hurt voice may remain silent")
	evoker.hurt_voice_chance = 1
	audio._last.clear()
	evoker.take_damage(10,true)
	check(sound_count("entity.evoker.hurt") > before,"accepted hurt can play a randomly selected matching voice")
	var vex:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn",center+Vector2(-100,0),"Team0",evoker)
	vex.state_machine.set_physics_process(false)
	vex.hurt_voice_chance = 1
	vex.take_damage(1,true)
	check(sound_count("entity.vex.hurt") > 0,"vex uses its own hurt voice")
	for actor:Node2D in [evoker,vex,shell]:
		actor._mc_ambient_wait = 0
		audio._last.clear()
		actor.mc_tick_ambient(0)
		var player:AudioStreamPlayer2D = actor._mc_ambient_player
		check(player != null and player.get_meta("mc_sound_event","") == "entity."+actor.mc_audio_role+".ambient","correct idle/peek/grumble voice for "+actor.mc_audio_role)
		check(actor._mc_ambient_wait >= player.stream.get_length()/player.pitch_scale,"idle interval includes full previous clip for "+actor.mc_audio_role)
		var id:int = player.get_instance_id()
		actor._mc_ambient_wait = 0
		actor.mc_tick_ambient(0)
		check(actor._mc_ambient_player.get_instance_id() == id,"idle clips cannot overlap for "+actor.mc_audio_role)
	# AudioStreamPlayer2D.play() 排入下一物理帧；先等实际开始播放，再验证暂停。
	await physics_frame
	await process_frame
	shell._mc_ambient_wait = 4
	shell.shell_open = false
	shell._update_shell_visual()
	shell.mc_tick_ambient(1)
	check(shell._mc_ambient_wait == 4 and shell._mc_ambient_player.stream_paused,"closed shell freezes both peek playback and cooldown")
	shell.shell_open = true
	shell._update_shell_visual()
	shell.mc_tick_ambient(0.2)
	check(shell._mc_ambient_wait < 4 and not shell._mc_ambient_player.stream_paused,"opening shell resumes peek and cooldown")
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(100,0))
	ender.state_machine.set_physics_process(false)
	ender._mc_ambient_wait = 0
	ender.mc_tick_ambient(0)
	check(ender._mc_ambient_player.get_meta("mc_sound_event","") == "entity.enderman.ambient","normal enderman breath is low murmur")
	ender.update_rage(ender.gaze_charge_seconds,true,true)
	check(sound_count("entity.enderman.stare") > 0,"entering rage immediately plays cry-out rather than ambient scream")
	ender.mc_tick_ambient(0)
	ender._mc_ambient_wait = 0
	ender.mc_tick_ambient(0)
	check(ender._mc_ambient_player.get_meta("mc_sound_event","") == "entity.enderman.scream","raging enderman changes idle voice to scream")
	ender.update_rage(6,false,false)
	check(ender.mc_ambient_event() == "ambient","ending rage returns to low murmur")
	# 使用 World 的正式胜利通知，不把暂时没有目标当成胜利。
	audio._last.clear()
	var side:String = world._victory_side_key_for_character(evoker)
	world._notify_battle_victory_for_side(side)
	await process_frame
	await process_frame
	var cheers:int = sound_count("entity.evoker.celebrate")
	check(cheers > 0,"official world victory callback plays evoker cheer")
	evoker.on_battle_victory()
	check(sound_count("entity.evoker.celebrate") == cheers,"victory cheer plays once")
	# 三圈分别共享命中表，按半径/时刻增加，伤害和推力降低。
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(24,0),"Team1")
	freeze_move(enemy)
	enemy.Max_health = 10000
	enemy.health = 10000
	evoker.global_position = center
	shell.global_position = center+Vector2(200,200)
	ender.global_position = center+Vector2(200,-200)
	vex.global_position = center+Vector2(-200,200)
	evoker.cast_fangs(enemy)
	var fangs:Array[Node] = get_nodes_in_group("MCEvokerFang")
	var rings:Dictionary = {}
	for fang:Node2D in fangs:
		var radius:int = int(round(fang.global_position.distance_to(center)))
		if not rings.has(radius): rings[radius] = []
		rings[radius].append(fang)
	check(rings.has(24) and rings.has(36) and rings.has(48) and fangs.size() == 48,"close cast spawns compact outward rings with 12/16/20 fangs")
	var a:Node = rings[24][0]
	var b:Node = rings[36][0]
	var c:Node = rings[48][0]
	check(a._delay < b._delay and b._delay < c._delay,"rings trigger sequentially from inside to outside")
	check(a._damage > b._damage and b._damage > c._damage and a._push_distance > b._push_distance and b._push_distance > c._push_distance,"inner rings have greater damage and knockback")
	camera.global_position = center
	camera.zoom = Vector2(2,2)
	await create_timer(0.24).timeout
	await capture("INNER_RING")
	await create_timer(0.24).timeout
	await capture("MIDDLE_RING")
	await create_timer(0.24).timeout
	await capture("OUTER_RING")
	check(enemy.health < 10000,"three-ring cast deals actual combat damage")
	await create_timer(0.55).timeout
	check(get_nodes_in_group("MCEvokerFang").is_empty(),"all three rings clean up")
	print("MC7_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func sound_count(event:String) -> int:
	var count:int = 0
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","") == event: count += 1
	return count
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC7_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC7_EXIT=",code)
	quit(code)
