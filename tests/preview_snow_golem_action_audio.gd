extends "res://tests/test_mc_snow_golem.gd"
## Real MovieWriter audio/video: no synthesized sound, no separate fake movement.
var unit:Node2D
var caption:Label
var folder:String
var metrics:Dictionary = {}
var cue_counts:Dictionary = {}

func _initialize() -> void:
	root.size = Vector2i(540,960)
	root.content_scale_size = root.size
	super._initialize()

func trace(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.get_meta("mc_snow_action",false):
		var event:String = node.get_meta("mc_sound_event","")
		cue_counts[event] = int(cue_counts.get(event,0))+1

func frame(move_body:bool) -> void:
	await physics_frame
	unit.step_mob(1.0/60.0)
	if move_body: unit.move(unit.Speed,1.0/60.0)
	else: unit.move(0.0,1.0/60.0)
	unit.visual_mob()

func run() -> void:
	game = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Development_Mode = false
	var center:Vector2 = await setup_world()
	saved = original
	AudioServer.set_bus_mute(0,false)
	folder = OS.get_environment("GOLEM_ACTION_EVIDENCE_DIR")
	if folder.is_empty(): folder = "user://golem_action_movie"
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(75,true,false,true).timeout.connect(func():finish(2))
	world.set_process(false)
	world.set_physics_process(false)
	world.control.hide()
	world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.global_position = center+Vector2(30,-25)
	camera.zoom = Vector2.ONE*2.0
	camera.force_update_scroll()
	var overlay:=CanvasLayer.new()
	overlay.layer = 60
	world.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(22,16)
	caption.size = Vector2(496,100)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_outline_color",Color.BLACK)
	caption.add_theme_constant_override("outline_size",4)
	overlay.add_child(caption)
	unit = spawn(GOLEM_PATH,center+Vector2(-50,20))
	unit.set_physics_process(false)
	unit._field.set_physics_process(false)
	unit.health_bar.hide()
	unit.hurt_voice_chance = 0.0
	unit.burst_probability = 0.0
	unit.Can_Attack = false
	unit.direction = Vector2.RIGHT
	var target:Node2D = dummy(Vector2(-10000,-10000))
	target.global_position = center+Vector2(120,-80)
	target.set_physics_process(false)
	target.Can_Attack = false
	target.Can_Skill = false
	target.Health_Restore = 0
	target.health_bar.hide()
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	var shape:=RectangleShape2D.new()
	shape.size = Vector2(6,110)
	var collider:=CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = center+Vector2(20,20)
	var outline:=Line2D.new()
	outline.width = 3
	outline.default_color = Color(0.75,0.78,0.84)
	outline.points = PackedVector2Array([Vector2(0,-55),Vector2(0,55)])
	wall.add_child(outline)
	node_added.connect(trace)
	caption.text = "实机有声验证｜正常行走：左右斜向 · 雪地脚步声"
	for i:int in range(75): await frame(true)
	caption.text = "真实墙体反弹｜转回左斜向 · 反弹雪地声"
	var bounced:bool = false
	for i:int in range(85):
		await frame(true)
		bounced = bounced or unit.direction.x<0
	check(bounced,"movie shows a real wall rebound")
	wall.queue_free()
	await process_frame
	caption.text = "发射时才朝向目标｜原版雪球发射声"
	unit.Can_Attack = true
	unit._shot_left = 0
	unit.set_player_control_peer(1)
	unit.set_player_control_aim_position(target.global_position)
	unit.player_control_action(0)
	for i:int in range(45): await frame(false)
	caption.text = "攻击结束｜恢复左右斜向，原地不播脚步"
	for i:int in range(25): await frame(false)
	caption.text = "首次半血｜原版南瓜碎裂声 + 方块碎片"
	unit.take_damage(ceilf(unit.Max_health*0.5),true)
	for i:int in range(35): await frame(false)
	caption.text = "下一轮保证20发｜每发一次原版射击声，保留重叠尾音"
	unit._shot_left = 0
	unit.player_control_action(0)
	for i:int in range(110): await frame(false)
	check(unit.shots_fired==21 and unit.bursts_started==1,"movie preserves one ordinary shot and one guaranteed twenty-shot volley")
	unit.Can_Attack = false
	caption.text = "行走 / 反弹 / 发射 / 南瓜碎裂：均为游戏实际播放的原版声音"
	for i:int in range(50): await frame(false)
	check(int(cue_counts.get("block.snow.step",0))>=2 and int(cue_counts.get("entity.snow_golem.shoot",0))>=2 and int(cue_counts.get("block.wood.break",0))==1,"native action players were really heard by the movie mix")
	var f:=FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"cues":cue_counts,"shots":unit.shots_fired,"bursts":unit.bursts_started},"\t"));f.close()
	print("GOLEM_ACTION_MOVIE_RESULT checks=",checks," failures=",failures," cues=",cue_counts)
	node_added.disconnect(trace)
	await finish(0 if failures==0 else 1)
