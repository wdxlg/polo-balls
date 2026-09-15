extends Node2D

const MARK_1_TEXTURE:Texture2D = preload("res://Images/characters/游戏/魔角猎人/标记1.png")
const MARK_2_TEXTURE:Texture2D = preload("res://Images/characters/游戏/魔角猎人/标记2.png")
const MARK_3_TEXTURE:Texture2D = preload("res://Images/characters/游戏/魔角猎人/标记3.png")
const GLOW_SHADER:Shader = preload("res://shaders/魔角猎人_标记发光.gdshader")
const OVERLOAD_SHADER:Shader = preload("res://shaders/魔角猎人_标记过载.gdshader")

var target:ball = null
var source:ball = null
var stack_count:int = 0 # 可见阶段：0=尚未形成标记，1~3=标记1~3
var point_progress:int = 0 # 当前阶段内已累计的“点层数”
var points_per_stage:int = 3
var remaining:float = 4.5
var tick_interval:float = 0.5
var tick_damage_per_stack:float = 5.0
var overload_flash_duration:float = 0.26

var _tick_left:float = 0.5
var _overloading:bool = false
var _overload_left:float = 0.0
var _overload_start_scale:float = 1.0
var _bump_left:float = 0.0
var _shake_phase:float = 0.0
var _visual_root:Node2D = null
var _core:Sprite2D = null
var _core_material:ShaderMaterial = null
var _glows:Array[Sprite2D] = []

const MARK_WORLD_WIDTH:float = 30.0
const MARK_OFFSET_Y:float = -30.0
const OVERLOAD_MAX_SCALE:float = 1.82
const STACK_COLORS:Array[Color] = [
	Color(0.56,0.32,0.96,0.86),
	Color(1.0,0.54,0.12,0.88),
	Color(1.0,0.16,0.10,0.90),
]
const GLOW_OUTLINE_SIZES:Array[float] = [4.0,2.0]
const GLOW_STRENGTHS:Array[float] = [0.26,0.68]
const OVERLOAD_GLOW_COLORS:Array[Color] = [
	Color(1.0,0.08,0.015,0.94),
	Color(1.0,0.58,0.035,1.0),
]
const OVERLOAD_GLOW_STRENGTHS:Array[float] = [0.72,1.26]


func setup(
	new_target:ball,
	new_source:ball,
	duration:float,
	new_tick_interval:float,
	new_tick_damage_per_stack:float,
	new_overload_flash_duration:float,
	new_points_per_stage:int = 3,
	initial_points:int = 0
) -> void:
	target = new_target
	source = new_source
	stack_count = 0
	point_progress = 0
	points_per_stage = maxi(new_points_per_stage,1)
	remaining = maxf(duration,0.1)
	tick_interval = maxf(new_tick_interval,0.05)
	tick_damage_per_stack = maxf(new_tick_damage_per_stack,0.0)
	overload_flash_duration = maxf(new_overload_flash_duration,0.05)
	_tick_left = tick_interval
	_build_visual()
	_refresh_visual()
	_gain_points(initial_points)


func _ready() -> void:
	set_as_top_level(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _visual_root == null:
		_build_visual()
	_refresh_visual()


func apply_points(new_source:ball,duration:float,point_amount:int) -> void:
	if _overloading:
		return
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	remaining = maxf(duration,0.1)
	_gain_points(point_amount)


# 兼容旧调用：旧的“加一层”按现在的规则等价为直接增加一整个阶段所需的点数。
func apply_stack(new_source:ball,duration:float) -> void:
	apply_points(new_source,duration,points_per_stage)


func _gain_points(point_amount:int) -> void:
	if _overloading:
		return
	var incoming:int = maxi(point_amount,0)
	if incoming <= 0:
		return
	point_progress += incoming

	# 每满 points_per_stage 点才推进 1 个可见阶段。
	# 已经处于第 3 阶段时，再凑满下一整个阶段，立即触发过载爆炸。
	while point_progress >= points_per_stage and not _overloading:
		point_progress -= points_per_stage
		if stack_count < 3:
			stack_count += 1
			_refresh_visual()
			_play_stack_bump()
		else:
			point_progress = 0
			_start_overload()
			return


func _process(delta:float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	_shake_phase += delta * (43.0 if _overloading else 22.0)

	var overload_progress:float = _get_overload_progress() if _overloading else 0.0
	var overload_eased:float = _smooth_progress(overload_progress)
	var shake_strength:float = 0.0
	if _overloading:
		# 震动也从轻到重，不在触发第一帧突然跳到最大震幅。
		shake_strength = lerpf(0.55,3.4,overload_eased)
	elif _bump_left > 0.0:
		shake_strength = 1.4 * clampf(_bump_left / 0.30,0.0,1.0)
	var shake := Vector2(sin(_shake_phase * 1.11),cos(_shake_phase * 1.67)) * shake_strength
	global_position = target.global_position + Vector2(0.0,MARK_OFFSET_Y) + shake
	global_rotation = 0.0
	global_scale = Vector2.ONE

	if _bump_left > 0.0:
		_bump_left = maxf(_bump_left - delta,0.0)
		var p:float = 1.0 - _bump_left / 0.30
		var pulse:float = 1.0 + sin(p * PI * 2.6) * (1.0 - p) * 0.34
		if _visual_root != null:
			_visual_root.scale = Vector2.ONE * pulse
	elif _visual_root != null and not _overloading:
		_visual_root.scale = Vector2.ONE

	if _overloading and _visual_root != null:
		# 从触发时的当前尺寸开始连续放大，直到爆炸前一刻才到最大。
		var scale_value:float = lerpf(_overload_start_scale,OVERLOAD_MAX_SCALE,overload_eased)
		_visual_root.scale = Vector2.ONE * scale_value
		_visual_root.modulate = Color.WHITE
		_update_overload_visual(overload_progress,overload_eased)


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		queue_free()
		return
	if source == null or not is_instance_valid(source) or source.health <= 0:
		queue_free()
		return
	if not source.is_multiplayer_authority():
		return
	if not source.is_combat_runtime_active():
		return

	if _overloading:
		_overload_left -= delta
		if _overload_left <= 0.0:
			_finish_overload()
		return

	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return

	# 还没凑满第一阶段（不足 points_per_stage 点）时只有内部点数，不显示标记，也不造成灼烧。
	if stack_count <= 0:
		_tick_left = tick_interval
		return

	_tick_left -= delta
	while _tick_left <= 0.0:
		_tick_left += tick_interval
		var raw_damage:float = tick_damage_per_stack * float(clampi(stack_count,1,3))
		var outgoing:float = source.effective_outgoing_damage(raw_damage)
		if outgoing <= 0.0:
			continue
		var applied:bool = target.receive_fire_positional_damage(outgoing,target.global_position,false,source)
		if applied and source.has_method("play_magic_horn_burn_tick_sfx"):
			source.call("play_magic_horn_burn_tick_sfx",target.global_position)


func _build_visual() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		return
	_visual_root = Node2D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	# 两层同尺寸轮廓：外层柔和、内层清晰。两层都与原图严格同位置同缩放，
	# 不再靠放大 Sprite 冒充描边，因此不会与图片轮廓错位。
	for i:int in range(GLOW_OUTLINE_SIZES.size()):
		var glow := Sprite2D.new()
		glow.name = "Glow%d" % (i + 1)
		glow.centered = true
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		glow.z_index = -2 + i
		var shader_material := ShaderMaterial.new()
		shader_material.shader = GLOW_SHADER
		shader_material.set_shader_parameter("outline_size",GLOW_OUTLINE_SIZES[i])
		shader_material.set_shader_parameter("glow_strength",GLOW_STRENGTHS[i])
		shader_material.set_shader_parameter("alpha_threshold",0.035)
		glow.material = shader_material
		_visual_root.add_child(glow)
		_glows.append(glow)

	_core = Sprite2D.new()
	_core.name = "MarkCore"
	_core.centered = true
	_core.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_core.z_index = 1
	_core_material = ShaderMaterial.new()
	_core_material.shader = OVERLOAD_SHADER
	_core_material.set_shader_parameter("overload_progress",0.0)
	_core.material = _core_material
	_visual_root.add_child(_core)


func _refresh_visual() -> void:
	if _visual_root == null:
		return
	var has_visible_stage:bool = stack_count >= 1
	_visual_root.visible = has_visible_stage
	if not has_visible_stage:
		if _core_material != null:
			_core_material.set_shader_parameter("overload_progress",0.0)
		return
	var texture:Texture2D = _texture_for_stack(stack_count)
	if texture == null:
		return
	var width:float = maxf(texture.get_width(),1.0)
	var scale_value:float = MARK_WORLD_WIDTH / width
	if _core != null:
		_core.texture = texture
		_core.scale = Vector2.ONE * scale_value
		_core.self_modulate = Color.WHITE
	if _core_material != null:
		_core_material.set_shader_parameter("overload_progress",0.0)
	var glow_color:Color = STACK_COLORS[clampi(stack_count - 1,0,STACK_COLORS.size() - 1)]
	for i:int in range(_glows.size()):
		var glow:Sprite2D = _glows[i]
		glow.texture = texture
		# 轮廓层与核心图使用完全相同的缩放，Shader 在透明像素邻域内生成轮廓。
		glow.scale = Vector2.ONE * scale_value
		glow.position = Vector2.ZERO
		glow.rotation = 0.0
		if glow.material is ShaderMaterial:
			var shader_material:ShaderMaterial = glow.material as ShaderMaterial
			shader_material.set_shader_parameter("glow_color",glow_color)
			shader_material.set_shader_parameter("outline_size",GLOW_OUTLINE_SIZES[mini(i,GLOW_OUTLINE_SIZES.size() - 1)])
			shader_material.set_shader_parameter("glow_strength",GLOW_STRENGTHS[mini(i,GLOW_STRENGTHS.size() - 1)])
	_visual_root.modulate = Color.WHITE


func _texture_for_stack(value:int) -> Texture2D:
	match clampi(value,1,3):
		1:
			return MARK_1_TEXTURE
		2:
			return MARK_2_TEXTURE
		3:
			return MARK_3_TEXTURE
	return MARK_1_TEXTURE


func _play_stack_bump() -> void:
	_bump_left = 0.30
	_shake_phase += 0.93
	if _visual_root != null:
		_visual_root.scale = Vector2.ONE * 1.34
		_visual_root.modulate = Color.WHITE


func _start_overload() -> void:
	if _overloading:
		return
	_overloading = true
	point_progress = 0
	_overload_left = maxf(overload_flash_duration,0.05)
	_bump_left = 0.0
	_overload_start_scale = 1.0
	if _visual_root != null:
		# 记录触发瞬间的真实尺寸，不再硬设 1.22 倍，因此不会第一帧突然变大。
		_overload_start_scale = maxf(absf(_visual_root.scale.x),0.01)
		_visual_root.modulate = Color.WHITE
	_update_overload_visual(0.0,0.0)
	if source != null and is_instance_valid(source) and source.has_method("on_magic_horn_mark_triggered"):
		source.call("on_magic_horn_mark_triggered",target)


func _get_overload_progress() -> float:
	var duration:float = maxf(overload_flash_duration,0.05)
	return clampf(1.0 - maxf(_overload_left,0.0) / duration,0.0,1.0)


func _smooth_progress(value:float) -> float:
	var p:float = clampf(value,0.0,1.0)
	return p * p * (3.0 - 2.0 * p)


func _update_overload_visual(progress:float,eased_progress:float) -> void:
	var p:float = clampf(progress,0.0,1.0)
	var eased:float = clampf(eased_progress,0.0,1.0)
	if _core_material != null:
		_core_material.set_shader_parameter("overload_progress",p)

	var base_glow_color:Color = STACK_COLORS[clampi(stack_count - 1,0,STACK_COLORS.size() - 1)]
	# 光晕稍晚于核心变色开始出现，并在爆炸前逐渐增强。
	var glow_progress:float = _smooth_progress(clampf((p - 0.08) / 0.92,0.0,1.0))
	for i:int in range(_glows.size()):
		var glow:Sprite2D = _glows[i]
		if not (glow.material is ShaderMaterial):
			continue
		var shader_material:ShaderMaterial = glow.material as ShaderMaterial
		var index:int = mini(i,OVERLOAD_GLOW_COLORS.size() - 1)
		var target_color:Color = OVERLOAD_GLOW_COLORS[index]
		var target_strength:float = OVERLOAD_GLOW_STRENGTHS[mini(i,OVERLOAD_GLOW_STRENGTHS.size() - 1)]
		shader_material.set_shader_parameter("glow_color",base_glow_color.lerp(target_color,glow_progress))
		shader_material.set_shader_parameter("glow_strength",lerpf(GLOW_STRENGTHS[mini(i,GLOW_STRENGTHS.size() - 1)],target_strength,eased))


func _finish_overload() -> void:
	if not _overloading:
		return
	_overloading = false
	if source != null and is_instance_valid(source) and source.has_method("on_magic_horn_mark_overload"):
		# 标记图标悬在人物上方，但过载爆炸的真实伤害/击退中心应在敌人本体位置。
		var impact_position:Vector2 = target.global_position if target != null and is_instance_valid(target) else global_position
		source.call("on_magic_horn_mark_overload",target,impact_position)
	queue_free()
