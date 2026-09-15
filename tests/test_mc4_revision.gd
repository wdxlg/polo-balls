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
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var evoker:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-400,0))
	evoker.state_machine.set_physics_process(false)
	var ender:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(-80,-100))
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(80,-100),"Team1")
	enemy.Max_health = 100000
	enemy.health = 100000
	enemy.Speed = 75
	enemy.default_properties["Speed"] = 75
	var gaze_start:Vector2 = ender.global_position
	# 方向几乎向下，画面依然左右相对。旧实现用移动向量会漏掉这类真实对视。
	ender.direction = Vector2(0.25,1).normalized()
	enemy.direction = Vector2(-0.25,1).normalized()
	ender.set_character_visual_flip_h(true)
	enemy.set_character_visual_flip_h(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = ender.global_position
	camera.zoom = Vector2(3,3)
	camera.make_current()
	await capture("NORMAL")
	await create_timer(0.45).timeout
	check(ender.gaze_charge > 0.12 and ender.gaze_charge < 0.9,"actual facing raises anger without assigning rage or charge directly")
	check(ender.image_color_mix > 0.10,"live rendering tint visibly increases during gaze")
	camera.global_position = ender.global_position
	await capture("CHARGING")
	await create_timer(1.05).timeout
	check(ender.rage_remaining > 0 and ender.Has_Collision_Damage,"natural sustained facing enters rage in actual scene")
	check(ender.image_color_mix > 0.65 and not ender._anger_text.is_empty(),"rage has strong red tint and a visible status label")
	var rage_events:int = 0
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","") == "entity.enderman.stare": rage_events += 1
	check(rage_events > 0,"entering rage starts the requested cry-out sound")
	check(ender.global_position.distance_to(gaze_start) > 60,"natural gaze succeeds while both actors are physically moving")
	camera.global_position = ender.global_position
	await capture("RAGE")
	freeze_move(ender)
	freeze_move(enemy)
	var portals:Array[Node] = get_nodes_in_group("MCEnderParticle")
	check(not portals.is_empty() and portals[0].texture.resource_path.contains("通用粒子/generic_"),"enderman uses native portal texture frames, not potion spirals")
	var particle_width:float = float(portals[0].texture.get_width())*portals[0].scale.x if not portals.is_empty() else 0.0
	check(particle_width >= 3.5 and particle_width <= 5.0,"upscaled native textures are normalized to readable bounded world-space particles")
	# MC9 已可主动绕后；这里单测“背对停止续怒”，固定相对位置并暂停主动攻击计时。
	ender.global_position = center+Vector2(-60,0)
	enemy.global_position = center+Vector2(60,0)
	ender._rage_teleport_wait = 30.0
	ender._rush_left = 0.0
	enemy.direction = Vector2.RIGHT
	enemy.set_character_visual_flip_h(true)
	var remaining:float = ender.rage_remaining
	await create_timer(0.35).timeout
	check(not ender._enemy_watching and ender.rage_remaining < remaining,"turning away stops gaze extension")
	await create_timer(7.0).timeout
	check(ender.rage_remaining <= 0 and ender.Has_Collision_Damage and ender.image_color_mix < 0.05,"actual rage expires and red tint returns to normal without disabling contact damage")
	ender.state_machine.set_physics_process(false)
	enemy.state_machine.set_physics_process(false)
	# 删除检测必须检查实例释放，不能只检查 health==0。
	var bullet:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,120))
	bullet.state_machine.set_physics_process(false)
	check(not bullet.health_bar.visible and bullet.health_bar.visibility_layer == 0,"shulker projectile cannot display a health bar")
	var bullet_ref:WeakRef = weakref(bullet)
	bullet.take_damage(1000,true)
	bullet.take_damage(1000,true)
	check(bullet.health == 1 and not bullet.is_queued_for_deletion(),"two attacks leave a projectile alive regardless of damage")
	bullet.take_damage(1000,true)
	await process_frame
	await process_frame
	check(bullet_ref.get_ref() == null,"third attack really frees projectile node")
	var raw_shot:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,120))
	var raw_ref:WeakRef = weakref(raw_shot)
	raw_shot.health = 0
	await create_timer(0.1).timeout
	check(raw_ref.get_ref() == null,"raw-zero projectile also really leaves the scene")
	var timed:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,140))
	var timed_ref:WeakRef = weakref(timed)
	timed._life = 0.05
	await create_timer(0.15).timeout
	check(timed_ref.get_ref() == null,"expired projectile is removed rather than remaining at zero health")
	var block:StaticBody2D = obstacle(center+Vector2(35,180),Vector2(4,60))
	var wall_shot:Node2D = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(0,180))
	wall_shot.direction = Vector2.RIGHT
	wall_shot._course = Vector2.RIGHT
	wall_shot._course_wait = 10
	var wall_ref:WeakRef = weakref(wall_shot)
	await create_timer(0.45).timeout
	check(wall_ref.get_ref() == null,"wall impact removes projectile")
	block.queue_free()
	for kind:int in range(3):
		var clone:Node2D = spawn("res://scenes/creatures/末影分身.tscn",center+Vector2(0,220),"Team0",ender)
		var ref:WeakRef = weakref(clone)
		if kind == 0: clone.take_damage(1000,true)
		elif kind == 1: clone.health = 0
		else: clone._life_left = 0.05
		await create_timer(0.15).timeout
		check(ref.get_ref() == null,"clone node freed for damage/raw-zero/lifetime case %d" % kind)
	# 恼鬼：无接触常驻伤害、穿墙游荡，敌人近身后才冲刺穿透一次。
	var vex:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn",center+Vector2(-400,20),"Team0",evoker)
	vex._life_left = 20
	vex._mc_rng.seed = 25
	check(vex.collision_layer == 0 and vex.collision_mask == 0 and not vex.has_collision_damage(),"vex ignores terrain bodies and has no permanent contact attack")
	check(vex.image.self_modulate.a > 0.75 and vex.image.self_modulate.a < 0.9,"vex is slightly translucent")
	enemy.global_position = center+Vector2(0,20)
	var headings:Array[float] = []
	var dash_seen:bool = false
	for i:int in range(80):
		await physics_frame
		headings.append(vex.direction.angle())
		dash_seen = dash_seen or vex._charging or vex._windup > 0.0
	check(not dash_seen and absf(headings.max()-headings.min()) > 0.2,"out-of-range vex wanders instead of continuously pursuing enemy")
	vex._attack_wait = 100
	vex.global_position = enemy.global_position
	vex._roam_point = enemy.global_position+Vector2(80,0)
	vex._roam_wait = 10
	var before_hp:int = enemy.health
	await create_timer(0.12).timeout
	check(enemy.health == before_hp,"wandering overlap does not inflict collision damage")
	vex.global_position = center+Vector2(-300,80)
	enemy.global_position = vex.global_position+Vector2(55,0)
	var attack_start:Vector2 = vex.global_position
	var thin_wall:StaticBody2D = obstacle(attack_start+Vector2(25,0),Vector2(4,70))
	vex._roam_wait = 10
	vex._roam_point = vex.global_position
	vex._attack_wait = 0
	before_hp = enemy.health
	await create_timer(0.23).timeout
	check(vex._charging and vex.image.texture.resource_path.ends_with("恼鬼冲刺.png"),"charge uses the original angry vex appearance")
	await create_timer(0.42).timeout
	var after_hp:int = enemy.health
	check(before_hp-after_hp == 16,"one charge applies exactly one base hit, not multiple overlap hits")
	check(after_hp < before_hp and vex.global_position.x > enemy.global_position.x+5,"close-range dash passes through wall and through enemy while dealing damage")
	await create_timer(0.25).timeout
	check(enemy.health == after_hp and vex._dash_hit,"one dash cannot deal repeated contact damage")
	thin_wall.queue_free()
	var vex_ref:WeakRef = weakref(vex)
	vex.take_damage(100000,true)
	await process_frame
	await process_frame
	check(vex_ref.get_ref() == null,"killed vex is really deleted")
	# 尖牙绘制使用原版资源，不再调用自绘三角形。
	evoker.global_position = center+Vector2(-80,100)
	enemy.global_position = center+Vector2(40,100)
	evoker.cast_fangs(enemy)
	var fangs:Array[Node] = get_nodes_in_group("MCEvokerFang")
	check(not fangs.is_empty() and fangs[0].TEXTURE.resource_path.ends_with("唤魔者/尖牙.png"),"fangs use the imported original Minecraft fang artwork")
	await create_timer(0.44).timeout
	camera.global_position = center+Vector2(0,95)
	await capture("FANGS")
	await create_timer(0.86).timeout
	# 全部音效素材解码，并检测实际声音混音信号。
	var audio:Script = load("res://scripts/effects/我的世界/mc_native_audio.gd")
	var decoded:int = 0
	for event:String in audio.EVENTS:
		for item:Dictionary in audio.EVENTS[event]:
			var stream:AudioStream = item["stream"]
			if stream != null and stream.get_length() > 0.02: decoded += 1
	check(decoded == 74,"all expanded website audio clips decode successfully")
	_stop_audio(root)
	await process_frame
	await process_frame
	var bus:int = AudioServer.get_bus_index("GameplayRecord")
	AudioServer.set_bus_mute(bus,false)
	AudioServer.set_bus_volume_db(bus,0)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1
	AudioServer.add_bus_effect(bus,cap)
	var listener := AudioListener2D.new()
	world.add_child(listener)
	listener.global_position = enemy.global_position
	listener.make_current()
	audio._last.clear()
	var player:AudioStreamPlayer2D = audio.play(enemy,"entity.enderman.teleport",enemy.global_position,-3)
	check(player != null and player.playing and player.bus == "GameplayRecord" and player.global_position.is_equal_approx(enemy.global_position),"native sound starts on correct bus and world position")
	await create_timer(0.45).timeout
	var frames:PackedVector2Array = cap.get_buffer(cap.get_frames_available())
	var peak:float = 0.0
	for sample:Vector2 in frames: peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	print("MC4_AUDIO frames=",frames.size()," peak=",peak)
	check(frames.size() > 100 and peak > 0.0001,"native audio produces real nonzero PCM, not just a player node")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	print("MC4_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.20),int(size.y*0.39)),Vector2i(int(size.x*0.60),int(size.y*0.24))))
	print("MC4_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
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
	print("MC4_EXIT=",code)
	quit(code)
