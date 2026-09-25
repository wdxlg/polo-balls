extends Node2D
## 五种 Minecraft 地图的真实单层方块墙。3D 只负责视觉；原有 2D 碰撞、门洞和
## 地图格不变。透视相机逐帧跟随实际 Camera2D 的画布变换，因此平移/缩放时
## 地面逐点对齐，而离地的低矮方块会出现真实的侧面与视差。

const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const OAK_SIDE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/oak_log.png")
const SAND_SIDE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone.png")
const SAND_BOTTOM:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone_bottom.png")
const PURPUR_SIDE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/purpur_pillar_side.png")
const COMPOSITE_SHADER:Shader = preload("res://shaders/map_wall_composite.gdshader")
const MAX_VIEW_PIXELS:int = 2560
const VIEW_FOV:float = 90.0
const WALL_HEIGHT_CELLS:float = 0.4
const LIGHT_HORIZONTAL_RATIO:float = 1.5

var wall_edges:Array[Dictionary] = []
var wall_rects:Array[Rect2] = []
var cell_size:Vector2 = Vector2(16,16)
var block_height:float = 16.0*WALL_HEIGHT_CELLS
var block_count:int = 0
var tiled:bool = false
var wall_texture:Texture2D
var wall_side_texture:Texture2D
var wall_bottom_texture:Texture2D
var _emission_strength:float = 0.0
var viewport:SubViewport
var shadow_viewport:SubViewport
var mesh_node:MeshInstance3D
var shadow_mesh:MeshInstance3D
var ground_node:MeshInstance3D
var camera:Camera3D
var shadow_camera:Camera3D
var sun_light:DirectionalLight3D
var shadow_sun:DirectionalLight3D
var picture:Sprite2D
var shadow_picture:Sprite2D
var _center:Vector2
var _render_scale:float = 1.0
var _camera_height:float = 1.0
var _composite_material:ShaderMaterial


func _create_renderer() -> void:
	if is_instance_valid(viewport): return
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 99 # 地图外遮罩之后，边框/门扇之前；不加入任何 2D 碰撞。
	viewport = SubViewport.new()
	viewport.name = "PerspectiveBlockViewport"
	viewport.size = Vector2i(64,64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	# 第二个独立 3D 通道只绘制地面接影。它与方块共享 ArrayMesh，
	# 但不把不透明的白色 shadow_to_opacity 遮罩误认成方块贴图。
	shadow_viewport = SubViewport.new()
	shadow_viewport.name = "RealGroundShadowViewport"
	shadow_viewport.size = viewport.size
	shadow_viewport.transparent_bg = true
	shadow_viewport.own_world_3d = true
	shadow_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(shadow_viewport)
	mesh_node = MeshInstance3D.new()
	mesh_node.name = "SixSidedBlockMesh"
	viewport.add_child(mesh_node)
	shadow_mesh = MeshInstance3D.new()
	shadow_mesh.name = "InvisibleBlocksCastRealShadows"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow_viewport.add_child(shadow_mesh)
	ground_node = MeshInstance3D.new()
	ground_node.name = "RealGroundShadowReceiver"
	ground_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 透明地面只在接到真实 DirectionalLight3D 的投影时才有 alpha。
	var catcher := StandardMaterial3D.new()
	catcher.albedo_color = Color.WHITE
	catcher.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	catcher.shadow_to_opacity = true
	catcher.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_node.material_override = catcher
	shadow_viewport.add_child(ground_node)
	camera = Camera3D.new()
	camera.name = "MovingPerspectiveWallCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = VIEW_FOV
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 40000.0
	camera.rotation_degrees = Vector3(-90.0,0.0,0.0)
	viewport.add_child(camera)
	camera.make_current()
	shadow_camera = Camera3D.new()
	shadow_camera.name = "MovingGroundShadowCamera"
	shadow_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	shadow_camera.fov = VIEW_FOV
	shadow_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	shadow_camera.near = camera.near
	shadow_camera.far = camera.far
	shadow_camera.rotation_degrees = camera.rotation_degrees
	shadow_viewport.add_child(shadow_camera)
	shadow_camera.make_current()
	var environment := WorldEnvironment.new()
	environment.name = "BlockAmbientLight"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72,0.79,0.89)
	environment.environment.ambient_light_energy = 1.35
	viewport.add_child(environment)
	var shadow_environment := WorldEnvironment.new()
	shadow_environment.environment = environment.environment
	shadow_viewport.add_child(shadow_environment)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "WallSun3D"
	sun_light.light_color = Color(1.0,0.96,0.87)
	sun_light.light_energy = 2.6
	sun_light.shadow_enabled = true
	sun_light.shadow_opacity = 1.0
	viewport.add_child(sun_light)
	shadow_sun = DirectionalLight3D.new()
	shadow_sun.name = "RealGroundSun3D"
	shadow_sun.light_color = sun_light.light_color
	shadow_sun.light_energy = sun_light.light_energy
	shadow_sun.shadow_enabled = true
	shadow_sun.shadow_opacity = 1.0
	shadow_viewport.add_child(shadow_sun)
	_composite_material = ShaderMaterial.new()
	_composite_material.shader = COMPOSITE_SHADER
	shadow_picture = Sprite2D.new()
	shadow_picture.name = "RealShadowOn2DGround"
	shadow_picture.centered = false
	shadow_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow_picture.texture = shadow_viewport.get_texture()
	shadow_picture.material = _composite_material
	shadow_picture.modulate = Color(0.025,0.028,0.035,0.62)
	shadow_picture.z_index = -1
	add_child(shadow_picture)
	picture = Sprite2D.new()
	picture.name = "MovingBlocksAndRealShadows"
	picture.centered = false
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.texture = viewport.get_texture()
	picture.material = _composite_material
	add_child(picture)
	if not RenderingServer.frame_pre_draw.is_connected(_sync_projection_before_draw):
		RenderingServer.frame_pre_draw.connect(_sync_projection_before_draw)


func configure_regions(ground:Array[Rect2],walls:Array[Rect2],edges:Array[Dictionary],cell:Vector2,style:String,light_source:Vector2,_height_cells:float) -> void:
	wall_edges = edges.duplicate(true)
	wall_rects = walls.duplicate()
	tiled = THEMES.tiled(style)
	if not tiled or walls.is_empty():
		visible = false
		block_count = 0
		if is_instance_valid(viewport):
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			shadow_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	visible = true
	cell_size = cell.max(Vector2(0.01,0.01))
	# 低矮墙只改变视觉高度；保留完整格宽和原 2D 碰撞，不受旧高度参数影响。
	block_height = minf(cell_size.x,cell_size.y)*WALL_HEIGHT_CELLS
	wall_texture = THEMES.wall_texture(style)
	wall_side_texture = _side_texture(style)
	wall_bottom_texture = SAND_BOTTOM if style == "sand" else wall_texture
	_emission_strength = {"grass":0.28,"sand":0.0,"stone":0.75,"nether":2.1,"end":0.05}.get(style,0.0)
	_create_renderer()
	var ambient:Environment = (viewport.get_node("BlockAmbientLight") as WorldEnvironment).environment
	ambient.ambient_light_color = Color(0.72,0.79,0.89)
	ambient.ambient_light_energy = 1.35
	sun_light.light_energy = 2.6
	if style == "sand":
		ambient.ambient_light_color = Color(1.0,0.95,0.86)
		ambient.ambient_light_energy = 0.95
		sun_light.light_energy = 1.3
	elif style == "end":
		ambient.ambient_light_color = Color(0.77,0.70,0.88)
		ambient.ambient_light_energy = 1.0
		sun_light.light_energy = 1.45
	var bounds:Rect2 = walls[0]
	for i:int in range(1,walls.size()): bounds = bounds.merge(walls[i])
	_center = bounds.get_center()
	_rebuild_mesh(ground)
	shadow_sun.light_energy = sun_light.light_energy
	_update_light(light_source)
	_update_projection()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	shadow_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func update_time_lighting(source:Vector2,daylight:float) -> void:
	# 时间更新只转灯/淡化太阳影子，不走 configure_regions，不重建 ArrayMesh。
	if not tiled or not is_instance_valid(sun_light): return
	_update_light(source)
	shadow_picture.modulate.a = 0.62*clampf(daylight,0.0,1.0)


func _sync_projection_before_draw() -> void:
	# 等本帧所有 Camera2D/跟随/缩放逻辑完成后，使用真正将被渲染的画布。
	# 不 force_update_scroll：墙体渲染不能再次推进主相机平滑，也须支持暂停时平移。
	if is_visible_in_tree() and is_instance_valid(viewport): _update_projection()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_projection_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_sync_projection_before_draw)
	# 离开世界或测试退出时先停掉两路实时 GPU 渲染，再由 Godot 回收子视口。
	if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(shadow_viewport): shadow_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _update_projection() -> void:
	var screen:Vector2 = get_viewport().get_visible_rect().size
	if screen.x < 2.0 or screen.y < 2.0: return
	var canvas:Transform2D = get_viewport().get_canvas_transform()
	var inverse:Transform2D = canvas.affine_inverse()
	var center:Vector2 = inverse * (screen*0.5)
	var pixel_world_size:float = inverse.basis_xform(Vector2.RIGHT).length()
	_camera_height = screen.y*pixel_world_size/(2.0*tan(deg_to_rad(VIEW_FOV)*0.5))
	camera.position = Vector3(center.x,_camera_height,center.y)
	shadow_camera.position = camera.position
	# 默认的 100 米 DirectionalLight3D 阴影范围会把高位相机下的
	# 地面投影整个裁掉。用实际视距设置阴影范围，移动/缩放后仍接影。
	sun_light.directional_shadow_max_distance = maxf(300.0,_camera_height+block_height*8.0)
	shadow_sun.directional_shadow_max_distance = sun_light.directional_shadow_max_distance
	# 限制高分辨率窗口的 GPU 开销；用逻辑画布尺寸计算投影，
	# 不读取 ViewportTexture.get_size()：高 DPI 时它和真实 GPU 栅格不一致。
	_render_scale = minf(1.0,float(MAX_VIEW_PIXELS)/maxf(screen.x,screen.y))
	var render_size := Vector2i(maxi(2,roundi(screen.x*_render_scale)),maxi(2,roundi(screen.y*_render_scale)))
	if viewport.size != render_size: viewport.size = render_size
	if shadow_viewport.size != render_size: shadow_viewport.size = render_size
	# Sprite 位于 2D 世界，但每帧贴合屏幕像素；Camera2D 的滚动、震动和
	# zoom 不会重新移动已经投影过的 3D 帧，确保地面与旧地图一一对应。
	var render_to_screen := Transform2D(Vector2(1.0/_render_scale,0.0),Vector2(0.0,1.0/_render_scale),Vector2.ZERO)
	picture.transform = inverse * render_to_screen
	shadow_picture.transform = picture.transform
	# 两路 Sprite 的 UV/裁剪仍按原画布走，只绕开它们自己的 MODEL_MATRIX 平移取整。
	var precise:Transform2D = picture.global_transform
	_composite_material.set_shader_parameter("quad_world_basis",Vector4(precise.x.x,precise.x.y,precise.y.x,precise.y.y))
	_composite_material.set_shader_parameter("quad_world_origin",precise.origin)


func _side_texture(style:String) -> Texture2D:
	match style:
		"grass": return OAK_SIDE
		"sand": return SAND_SIDE
		"end": return PURPUR_SIDE
		_: return THEMES.wall_texture(style)


func _ground_point(point:Vector2,altitude:float) -> Vector3:
	return Vector3(point.x,altitude,point.y)


func _new_material(texture:Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _emission_strength>0.0:
		material.emission_enabled = true
		material.emission_texture = texture
		material.emission_energy_multiplier = _emission_strength
	return material


func _face(tool:SurfaceTool,points:Array[Vector3],uvs:Array[Vector2]) -> void:
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	for i:int in [0,1,2,0,2,3]:
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])


func _next_cell_boundary(at:float,origin:float,span:float) -> float:
	return origin+(floorf((at-origin+0.001)/span)+1.0)*span


func _rebuild_mesh(ground:Array[Rect2]) -> void:
	var origin:Vector2 = ground[0].position if not ground.is_empty() else wall_rects[0].position
	var tops := SurfaceTool.new()
	var sides := SurfaceTool.new()
	var bottoms := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	bottoms.begin(Mesh.PRIMITIVE_TRIANGLES)
	block_count = 0
	for rect:Rect2 in wall_rects:
		var x:float = rect.position.x
		while x < rect.end.x-0.01:
			var x2:float = minf(rect.end.x,_next_cell_boundary(x,origin.x,cell_size.x))
			var y:float = rect.position.y
			while y < rect.end.y-0.01:
				var y2:float = minf(rect.end.y,_next_cell_boundary(y,origin.y,cell_size.y))
				# 相邻方块共享精确边界，不再内缩留缝；门洞仍由 wall_rects 裁切。
				_add_block(tops,sides,bottoms,Rect2(x,y,x2-x,y2-y),origin)
				block_count += 1
				y = y2
			x = x2
	var model := ArrayMesh.new()
	tops.commit(model)
	sides.commit(model)
	bottoms.commit(model)
	model.surface_set_material(0,_new_material(wall_texture))
	model.surface_set_material(1,_new_material(wall_side_texture))
	model.surface_set_material(2,_new_material(wall_bottom_texture))
	mesh_node.mesh = model
	shadow_mesh.mesh = model
	# 地面三角面只覆盖真实岛屿，不让投影泄漏到空岛/地图外。门洞处
	# 已没有墙网格，自然也没有从那块墙向地面投出的假影。
	var catcher := SurfaceTool.new()
	catcher.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect:Rect2 in ground:
		var x0:float = rect.position.x
		var x1:float = rect.end.x
		var y0:float = rect.position.y
		var y1:float = rect.end.y
		_face(catcher,[Vector3(x0,-0.08,y0),Vector3(x0,-0.08,y1),Vector3(x1,-0.08,y1),Vector3(x1,-0.08,y0)],[Vector2.ZERO,Vector2.DOWN,Vector2.ONE,Vector2.RIGHT])
	ground_node.mesh = catcher.commit() if not ground.is_empty() else null


func _add_block(top:SurfaceTool,side:SurfaceTool,bottom:SurfaceTool,rect:Rect2,origin:Vector2) -> void:
	var x:float = rect.position.x
	var y:float = rect.position.y
	var u0:float = fposmod((x-origin.x)/cell_size.x,1.0)
	var v0:float = fposmod((y-origin.y)/cell_size.y,1.0)
	var u1:float = u0+rect.size.x/cell_size.x
	var v1:float = v0+rect.size.y/cell_size.y
	var b00:Vector3 = _ground_point(rect.position,0.0)
	var b10:Vector3 = _ground_point(Vector2(rect.end.x,y),0.0)
	var b11:Vector3 = _ground_point(rect.end,0.0)
	var b01:Vector3 = _ground_point(Vector2(x,rect.end.y),0.0)
	var t00:Vector3 = b00+Vector3.UP*block_height
	var t10:Vector3 = b10+Vector3.UP*block_height
	var t11:Vector3 = b11+Vector3.UP*block_height
	var t01:Vector3 = b01+Vector3.UP*block_height
	_face(top,[t00,t01,t11,t10],[Vector2(u0,v0),Vector2(u0,v1),Vector2(u1,v1),Vector2(u1,v0)])
	_face(bottom,[b00,b10,b11,b01],[Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1),Vector2(u0,v1)])
	_face(side,[t00,t10,b10,b00],[Vector2(u0,0),Vector2(u1,0),Vector2(u1,1),Vector2(u0,1)])
	_face(side,[t10,t11,b11,b10],[Vector2(v0,0),Vector2(v1,0),Vector2(v1,1),Vector2(v0,1)])
	_face(side,[t11,t01,b01,b11],[Vector2(u1,0),Vector2(u0,0),Vector2(u0,1),Vector2(u1,1)])
	_face(side,[t01,t00,b00,b01],[Vector2(v1,0),Vector2(v0,0),Vector2(v0,1),Vector2(v1,1)])


func _update_light(source:Vector2) -> void:
	var direction:Vector2 = source.normalized() if source.length_squared()>0.0001 else Vector2(1,-1).normalized()
	var target := Vector3(_center.x,0.0,_center.y)
	# 适当抬高右上光源：配合 0.4 格墙高，真实地影总长约 0.6 格，避免覆盖战场。
	sun_light.position = target+Vector3(direction.x*LIGHT_HORIZONTAL_RATIO,1.0,direction.y*LIGHT_HORIZONTAL_RATIO)*600.0
	sun_light.look_at(target)
	shadow_sun.position = sun_light.position
	shadow_sun.look_at(target)
