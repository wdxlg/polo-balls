extends SceneTree
## 软体形变不被贴图矩形裁切：形变期间 Shader 拿到绘制矩形并外扩顶点，结束后清零。
var checks:int = 0
var failures:int = 0

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DEFORM_NO_CLIP_FAIL " + label)
	else:
		print("DEFORM_NO_CLIP_PASS ",label)

func rect_vec(unit:Node) -> Vector4:
	var rect:Rect2 = unit._hit_effect_visual_rect()
	return Vector4(rect.get_center().x,rect.get_center().y,rect.size.x,rect.size.y)

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): print("DEFORM_NO_CLIP_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_path:String = game._settings_storage_path
	game._settings_storage_path = "user://test_deform_no_clip_settings.cfg"
	game.Game_Settings.Training_Mode = false
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	var shader:Shader = load("res://shaders/Set_RGB_Color.gdshader")
	var code:String = shader.code
	check(code.contains("instance uniform vec4 deform_rect") and code.contains("local_uv = deform_local_uv;"),"character shader expands its quad from deform_rect")
	var instance_uniforms:int = 0
	for line:String in code.split("\n"):
		if line.strip_edges().begins_with("instance uniform"): instance_uniforms += 1
	check(instance_uniforms <= 16,"shader stays within Godot's 16 instance uniforms (%d)" % instance_uniforms)
	var WALL_CLIP:GDScript = load("res://scripts/characters/我的世界/wandering_trader/wall_clip.gd")
	var clip:Shader = WALL_CLIP.clip_shader(shader)
	check(clip != null and clip.code.find("wall_clip_world = (MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;") > clip.code.find("VERTEX += grow * deform_rect.zw;"),"wall clip still injects, after the quad expansion")

	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world._mc_prewarmer = null
	world.set_process(false)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	await create_timer(0.3,true,false,true).timeout
	for path:String in ["res://scenes/characters/我的世界/骷髅.tscn","res://scenes/characters/我的世界/烈焰人.tscn"]:
		var unit:Node2D = load(path).instantiate()
		unit.Team = "A"
		unit.position = center
		world.add_child(unit,true)
		unit.set_physics_process(false)
		unit.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		await process_frame
		var tag:String = path.get_file().get_basename()
		check(unit._collision_shader_supported(),tag + " uses the deformable character shader")
		check(unit.image.get_instance_shader_parameter("deform_rect") in [null,Vector4.ZERO],tag + " draws its normal quad while idle")
		unit.Figure_collide_transform(Vector2.RIGHT,400.0)
		check(unit.image.get_instance_shader_parameter("deform_rect") == rect_vec(unit),tag + " collision squash hands the draw rect to the shader")
		# 手动推进到结束（不依赖测试启动阶段的全局时间缩放）。
		unit.collide_tween.custom_step(1.0)
		check(unit.image.get_instance_shader_parameter("deform_rect") == Vector4.ZERO,tag + " quad shrinks back once the squash settles")
		unit._play_ranged_hit_feedback_local(Vector2.LEFT,0.8)
		check(unit.image.get_instance_shader_parameter("deform_rect") == rect_vec(unit),tag + " ranged-hit squash also expands")
		unit.collide_tween.kill()
		unit._reset_collision_shader()
		unit._set_motion_shader_values(Vector2.RIGHT,0.6)
		check(unit.image.get_instance_shader_parameter("deform_rect") == rect_vec(unit),tag + " motion stretch also expands")
		unit._set_motion_shader_values(Vector2.RIGHT,0.0)
		check(unit.image.get_instance_shader_parameter("deform_rect") == Vector4.ZERO,tag + " motion stretch at rest clears the expansion")
		unit.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	game._settings_storage_path = saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_deform_no_clip_settings.cfg"))
	print("DEFORM_NO_CLIP_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
