extends Node2D
# 天陨箭雨来临时的天穹特效：画面上缘一条横向星空带（与裂隙同一套原生星空，
# 但作为远景随镜头按地图外棋盘背景的比例视差滚动）。
# 出现：前沿用欠阻尼弹簧从 0 弹性弹出到全高（带过冲回弹，网格按过冲上限留余量）；
# 收回：整带统一不透明度渐隐，顶部实/自上而下渐隐的形状全程不变（不再等比缩小）。
# 层级在落箭（z=91）与扭曲（93）之上（z=94），仍低于
# ghost（95）/水印（98）与 CanvasLayer 上的 UI。视觉层：各端本地轮询各自
# 生成的落箭（组 HeavenfallRainArrow）即可，无需同步。
const SHADER: Shader = preload("res://shaders/heavenfall_sky_band.gdshader")
const COSMIC_ATLAS: Texture2D = preload("res://Images/characters/我的世界/new6/av_cosmic_atlas.png")
const GROUP: StringName = &"HeavenfallSkyBand"
const RAIN_GROUP: StringName = &"HeavenfallRainArrow"
const POP_DURATION: float = 0.6 # 弹出曲线在此收定（冻结为恰好 1）
const POP_OMEGA: float = TAU * 2.8 # 弹簧角频率（≈2.8Hz，与弓后坐同族手感）
const POP_DECAY: float = 9.0 # 阻尼：一次明显过冲后收敛
const POP_OVERSHOOT: float = 0.21 # 过冲上限（exp(-POP_DECAY·PI/POP_OMEGA)+余量），网格按此留高度余量
const FADE_TIME: float = 0.45
const WIDTH_MARGIN: float = 64.0
const TOP_SLACK: float = 64.0 # 向屏幕上方多画一段：镜头运动/取整误差下最上缘不会露出底下的背景
const BAND_Z: int = 94
const MIN_HEIGHT: float = 56.0
const MAX_HEIGHT: float = 140.0

var _pop_age: float = -1.0 # 弹性弹出的时钟；<0 = 尚无箭雨在途（弹出未开始）
var _front_up: float = 0.0 # 收回程度（0=完全不透明，1=完全收回）：只影响整带不透明度
var _age: float = 0.0
var _mesh: MeshInstance2D
var _material: ShaderMaterial
var _band_size: Vector2 = Vector2.ZERO

static func ensure(parent: Node) -> void:
	# 已有挂在该场景下的带则复用；否则新建（BattleTransient 语义，随局清场）。
	if parent == null or not parent.is_inside_tree():
		return
	for node: Node in parent.get_tree().get_nodes_in_group(GROUP):
		if node.get_parent() == parent:
			return
	var band := Node2D.new()
	band.set_script(load("res://scripts/characters/我的世界/new6/heavenfall_sky_band.gd"))
	band.name = "HeavenfallSkyBand"
	parent.add_child(band)

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group(GROUP)
	z_index = BAND_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mesh = MeshInstance2D.new()
	_mesh.name = "SkyBandMesh"
	add_child(_mesh)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("cosmic_atlas", COSMIC_ATLAS)
	_material.set_shader_parameter("linear_output", get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility")
	_mesh.material = _material
	RenderingServer.frame_pre_draw.connect(_track_viewport)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_track_viewport):
		RenderingServer.frame_pre_draw.disconnect(_track_viewport)

func reveal_extent() -> float:
	# 当前显现前沿（可短暂 >1：弹簧过冲），收定后恒为 1。
	if _pop_age < 0.0:
		return 0.0
	if _pop_age >= POP_DURATION:
		return 1.0
	return 1.0 - exp(-POP_DECAY * _pop_age) * cos(POP_OMEGA * _pop_age)

func fade_extent() -> float:
	return _front_up

func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	_age += maxf(delta, 0.0)
	var raining: bool = not get_tree().get_nodes_in_group(RAIN_GROUP).is_empty()
	if raining:
		# 弹性弹出：箭雨在途时前沿用欠阻尼弹簧从 0 弹到 1（+20% 过冲后回弹收定）。
		if _pop_age < 0.0:
			_pop_age = 0.0
		elif _pop_age < POP_DURATION:
			_pop_age = minf(_pop_age + maxf(delta, 0.0), POP_DURATION)
		_front_up = maxf(_front_up - maxf(delta, 0.0) / FADE_TIME, 0.0) # 收回途中又落箭：不透明度先恢复（形状从未变过）
	else:
		_front_up = minf(_front_up + maxf(delta, 0.0) / FADE_TIME, 1.0)
	visible = _pop_age >= 0.0 and _front_up < 0.999
	_material.set_shader_parameter("cosmic_time", _age)
	_material.set_shader_parameter("reveal_front", reveal_extent())
	_material.set_shader_parameter("fade_front", _front_up)
	if not raining and _front_up >= 1.0:
		queue_free() # 完全收回后自清理

func _track_viewport() -> void:
	# frame_pre_draw 跟随当前相机/视口。网格以“画面像素”为单位：全局变换直接取
	# canvas 逆变换（再向左让出 64px 边距），因此镜头拉近拉远（zoom≠1）时，
	# 带在画面上的位置与尺寸都精确钉在视口上缘，不随 zoom 放大缩小。
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var canvas: Transform2D = viewport.get_canvas_transform()
	var inverse: Transform2D = canvas.affine_inverse()
	var visible_size: Vector2 = viewport.get_visible_rect().size
	var height: float = clampf(visible_size.y * 0.16, MIN_HEIGHT, MAX_HEIGHT)
	var width: float = visible_size.x + WIDTH_MARGIN * 2.0
	global_transform = inverse * Transform2D(0.0, Vector2(-WIDTH_MARGIN, 0.0))
	# 星空视差：与地图外棋盘背景同源（镜头位置）同比例（map_outside_grid_parallax_scale）。
	var anchor: Vector2 = inverse * (visible_size * 0.5)
	var camera: Camera2D = viewport.get_camera_2d()
	if camera != null and camera.is_inside_tree():
		anchor = camera.global_position
	_material.set_shader_parameter("parallax_anchor", anchor)
	var parallax: float = 0.32
	var host: Object = get_parent()
	if host != null and "map_outside_grid_parallax_scale" in host:
		parallax = clampf(float(host.map_outside_grid_parallax_scale), 0.0, 1.0)
	_material.set_shader_parameter("parallax_scale", parallax)
	if absf(width - _band_size.x) > 0.5 or absf(height - _band_size.y) > 0.5:
		_band_size = Vector2(width, height)
		_material.set_shader_parameter("band_height", height)
		_rebuild_mesh()

func _rebuild_mesh() -> void:
	var w: float = _band_size.x
	var h: float = _band_size.y
	# 顶边从屏幕上方余量开始画：最上缘永远盖住视口顶边，不露底下的背景；
	# 底边按弹簧过冲上限多留一段：弹出最冲的那一下不会被网格裁掉。
	var mesh_bottom: float = h * (1.0 + POP_OVERSHOOT) + 2.0
	var vertices := PackedVector2Array([Vector2(0.0, -TOP_SLACK), Vector2(w, -TOP_SLACK), Vector2(0.0, mesh_bottom), Vector2(w, mesh_bottom)])
	var uvs := PackedVector2Array([Vector2(0.0, -TOP_SLACK), Vector2(w, -TOP_SLACK), Vector2(0.0, mesh_bottom), Vector2(w, mesh_bottom)])
	var indices := PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh
