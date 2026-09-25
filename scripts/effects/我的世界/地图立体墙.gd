extends Node2D
## 五种贴图地图的真实 3D 方块墙。战场/碰撞依旧是 2D；唯一的 3D 世界在透明
## SubViewport 内，使用六面体网格、原版方块各面的纹理和 DirectionalLight3D。
## 墙的平面坐标通过正交相机投影的逆矩阵校正，故门洞、内凹边和地图切换
## 不会随着透视倾角逐格漂移。蓝色地图完全不渲染这个 3D Viewport。

const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const OAK_SIDE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/oak_log.png")
const SAND_SIDE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone.png")
const SAND_BOTTOM:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone_bottom.png")
const PURPUR_SIDE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/purpur_pillar_side.png")
const MAX_VIEW_PIXELS:int = 4096

var wall_edges:Array[Dictionary] = []
var wall_rects:Array[Rect2] = []
var cell_size:Vector2 = Vector2(16,16)
var block_height:float = 20.0
var block_count:int = 0
var tiled:bool = false
var wall_texture:Texture2D
var wall_side_texture:Texture2D
var wall_bottom_texture:Texture2D
var _emission_strength:float = 0.0
var viewport:SubViewport
var mesh_node:MeshInstance3D
var camera:Camera3D
var sun_light:DirectionalLight3D
var picture:Sprite2D
var _center:Vector2
var _render_scale:float = 1.0
var _right:Vector3
var _up:Vector3
var _inverse_det:float = 1.0


func _create_renderer() -> void:
	if is_instance_valid(viewport): return
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 99 # 外部遮罩之后、门扇/黑框之前；与 2D 物理完全分开。
	viewport = SubViewport.new()
	viewport.name = "True3DBlockViewport"
	viewport.size = Vector2i(64,64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	mesh_node = MeshInstance3D.new()
	mesh_node.name = "SixSidedBlockMesh"
	viewport.add_child(mesh_node)
	camera = Camera3D.new()
	camera.name = "OrthographicWallCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(380.0,980.0,920.0)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.rotate_object_local(Vector3.FORWARD,deg_to_rad(12.0))
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.name = "BlockAmbientLight"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0,0,0,0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72,0.79,0.89)
	environment.environment.ambient_light_energy = 1.35
	viewport.add_child(environment)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "WallSun3D"
	sun_light.light_color = Color(1.0,0.96,0.87)
	sun_light.light_energy = 2.6
	sun_light.shadow_enabled = true
	sun_light.shadow_opacity = 0.7
	viewport.add_child(sun_light)
	picture = Sprite2D.new()
	picture.name = "WallBlocksOn2DMap"
	picture.centered = false
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.texture = viewport.get_texture()
	add_child(picture)


func configure_regions(ground:Array[Rect2],walls:Array[Rect2],edges:Array[Dictionary],cell:Vector2,style:String,light_source:Vector2,height_cells:float) -> void:
	wall_edges = edges.duplicate(true)
	wall_rects = walls.duplicate()
	tiled = THEMES.tiled(style)
	if not tiled or walls.is_empty():
		visible = false
		block_count = 0
		if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	visible = true
	cell_size = cell.max(Vector2(0.01,0.01))
	block_height = minf(cell_size.x,cell_size.y)*clampf(height_cells,0.1,2.25)
	wall_texture = THEMES.wall_texture(style)
	wall_side_texture = _side_texture(style)
	wall_bottom_texture = SAND_BOTTOM if style == "sand" else wall_texture
	# 原版深色方块仍取原图色值；少量同图自发光是填充照明，不换亮化贴图。
	_emission_strength = {"grass":0.28,"sand":0.0,"stone":0.75,"nether":2.1,"end":0.05}.get(style,0.0)
	_create_renderer()
	var ambient:Environment = (viewport.get_node("BlockAmbientLight") as WorldEnvironment).environment
	ambient.ambient_light_color = Color(0.72,0.79,0.89)
	ambient.ambient_light_energy = 1.35
	sun_light.light_energy = 2.6
	if style == "sand":
		# 砂岩的亮面本就接近白色，维持暖白光避免顶面失去原版沙色。
		ambient.ambient_light_color = Color(1.0,0.95,0.86)
		ambient.ambient_light_energy = 0.95
		sun_light.light_energy = 1.3
	elif style == "end":
		# 紫珀柱自然偏亮，不让背光面因为其它深色主题的补光而发白。
		ambient.ambient_light_color = Color(0.77,0.70,0.88)
		ambient.ambient_light_energy = 1.00
		sun_light.light_energy = 1.45
	var bounds:Rect2 = walls[0]
	for i:int in range(1,walls.size()): bounds = bounds.merge(walls[i])
	# 留出顶部与真实侧面投影的空间；绝不按外接矩形造额外墙块。
	var pad:float = block_height*1.5+maxf(cell_size.x,cell_size.y)*1.5+4.0
	var target:Vector2 = bounds.size+Vector2.ONE*pad*2.0
	_render_scale = minf(1.0,float(MAX_VIEW_PIXELS)/maxf(target.x,target.y))
	viewport.size = Vector2i(maxi(2,ceili(target.x*_render_scale)),maxi(2,ceili(target.y*_render_scale)))
	camera.size = float(viewport.size.y)/_render_scale
	_center = bounds.get_center()
	picture.scale = Vector2.ONE/_render_scale
	picture.position = _center-Vector2(viewport.size)*0.5/_render_scale
	# 2D 世界的地图格必须无视相机俯视角仍逐像素对应 3D 方块的地面位置。
	_right = camera.global_transform.basis.x
	_up = camera.global_transform.basis.y
	_inverse_det = _right.x*(-_up.z)-_right.z*(-_up.x)
	if absf(_inverse_det)<0.01:
		push_error("Map 3D wall camera cannot project ground coordinates")
		visible = false
		return
	_rebuild_mesh(ground)
	_update_light(light_source)
	# 墙和光只在主题/地图/门洞刷新时改变，不让大尺寸 3D Viewport 每帧重绘。
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _side_texture(style:String) -> Texture2D:
	match style:
		"grass": return OAK_SIDE
		"sand": return SAND_SIDE
		"end": return PURPUR_SIDE
		_: return THEMES.wall_texture(style) # 深板岩砖、下界砖全六面同图。


func _ground_point(point:Vector2,altitude:float) -> Vector3:
	var pixel:Vector2 = point-_center
	var a:float = _right.x
	var b:float = _right.z
	var c:float = -_up.x
	var d:float = -_up.z
	return Vector3((d*pixel.x-b*pixel.y)/_inverse_det,altitude,(-c*pixel.x+a*pixel.y)/_inverse_det)


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
				# 约半个屏幕像素的真实 3D 缝隙，让每块方块各自拥有可见的侧棱。
				var gap:float = minf(0.34,minf(x2-x,y2-y)*0.07)
				_add_block(tops,sides,bottoms,Rect2(x+gap,y+gap,x2-x-gap*2.0,y2-y-gap*2.0),origin)
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


func _add_block(top:SurfaceTool,side:SurfaceTool,bottom:SurfaceTool,rect:Rect2,origin:Vector2) -> void:
	var x:float = rect.position.x
	var y:float = rect.position.y
	var u0:float = fposmod((x-origin.x)/cell_size.x,1.0)
	var v0:float = fposmod((y-origin.y)/cell_size.y,1.0)
	var u1:float = u0+rect.size.x/cell_size.x
	var v1:float = v0+rect.size.y/cell_size.y
	# 两格高的墙身仍一格一格使用原版侧面贴图，而不是把一格纹理拉长。
	var repeat_height:float = block_height/minf(cell_size.x,cell_size.y)
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
	# 北、东、南、西四面；每段门洞的断面也确实是 3D 方块的侧面。
	_face(side,[t00,t10,b10,b00],[Vector2(u0,0),Vector2(u1,0),Vector2(u1,repeat_height),Vector2(u0,repeat_height)])
	_face(side,[t10,t11,b11,b10],[Vector2(v0,0),Vector2(v1,0),Vector2(v1,repeat_height),Vector2(v0,repeat_height)])
	_face(side,[t11,t01,b01,b11],[Vector2(u1,0),Vector2(u0,0),Vector2(u0,repeat_height),Vector2(u1,repeat_height)])
	_face(side,[t01,t00,b00,b01],[Vector2(v1,0),Vector2(v0,0),Vector2(v0,repeat_height),Vector2(v1,repeat_height)])


func _update_light(source:Vector2) -> void:
	var direction:Vector2 = source.normalized() if source.length_squared()>0.0001 else Vector2(1,-1).normalized()
	var from_plane:Vector3 = _ground_point(_center+direction*minf(cell_size.x,cell_size.y),0.0)
	var sun:Vector3 = (from_plane+Vector3.UP*block_height*1.5).normalized()
	sun_light.position = sun*600.0
	sun_light.look_at(Vector3.ZERO)
