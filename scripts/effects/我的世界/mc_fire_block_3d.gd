extends Node2D
## 原版 3D 地面火方块：fire / soul_fire 方块的地面形态 = fire_floor0|1（四片绕 x/z 轴 ±22.5° 的斜面）
## + 四条边各一片 fire_side|side_alt 0|1（双面），几何按原版模型 JSON 换算到所在地图格。
## 网格放进共享的地图立体墙 overlay（同一透视相机与投影，离地部分随镜头产生真实视差），只负责视觉。
## 贴图帧序：*_0 按 mcmeta 16..31,0..15，*_1 顺序；20 fps，每团火自己的起始帧，随 _process 暂停/变速。
const WALL_RENDERER:Script = preload("res://scripts/effects/我的世界/地图立体墙.gd")
const FIRE_TEXTURES:Array[Texture2D] = [
	preload("res://Images/Status/MCFire/fire_0.png"),
	preload("res://Images/Status/MCFire/fire_1.png"),
]
const SOUL_FIRE_TEXTURES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/torch/soul_fire_0.png"),
	preload("res://Images/characters/我的世界/torch/soul_fire_1.png"),
]
const RENDERER_NAME:StringName = &"MCFireBlock3DRenderer"
const USERS_META:StringName = &"mc_fire_block_3d_users"
## 与地面火根节点同层：地图外遮罩(90)之上、黑色地图边框(100)之下。
const RENDERER_Z:int = 92
const FRAME_COUNT:int = 32
const FRAMES_PER_SECOND:float = 20.0
const FRAME_ORDER_OFFSET:Array[int] = [16,0]
const MODEL_ORIGIN:Vector3 = Vector3(8.0,8.0,8.0)
## 原版 template_fire_floor：[from, to, 面, 旋转轴(0=x,2=z), 角度]；rescale=true。
const FLOOR_PLANES:Array = [
	[Vector3(0.0,0.0,8.8),Vector3(16.0,22.4,8.8),"south",0,-22.5],
	[Vector3(0.0,0.0,7.2),Vector3(16.0,22.4,7.2),"north",0,22.5],
	[Vector3(8.8,0.0,0.0),Vector3(8.8,22.4,16.0),"west",2,-22.5],
	[Vector3(7.2,0.0,0.0),Vector3(7.2,22.4,16.0),"east",2,22.5],
]
## 原版 template_fire_side(_alt)：北边一片，south/north 两面；方块状态 y=0/90/180/270 转到四边。
const SIDE_FROM:Vector3 = Vector3(0.0,0.0,0.01)
const SIDE_TO:Vector3 = Vector3(16.0,22.4,0.01)
## 最近邻采样落在帧边界时不读到相邻帧的一行。
const UV_INSET:float = 0.0005

var block_rect:Rect2 = Rect2()
var soul:bool = false
var frame:int = 0
var playing:bool = true
var _frame_time:float = 0.0
var _surface_textures:Array[int] = []
var _materials:Array[StandardMaterial3D] = []
var _mesh_node:MeshInstance3D = null
var _renderer:Node2D = null


func configure(rect:Rect2,soul_fire:bool,start_frame:int) -> void:
	block_rect = rect
	soul = soul_fire
	frame = posmod(start_frame,FRAME_COUNT)
	if is_inside_tree(): _rebuild()


func set_block_rect(rect:Rect2) -> void:
	if rect == block_rect: return
	block_rect = rect
	if is_inside_tree(): _rebuild()


func play() -> void:
	playing = true


func pause() -> void:
	playing = false


func textures() -> Array[Texture2D]:
	return SOUL_FIRE_TEXTURES if soul else FIRE_TEXTURES


## 当前帧在贴图条里的行号（texture_index 0 = *_0，1 = *_1）。
func frame_row(texture_index:int) -> int:
	return posmod(frame+FRAME_ORDER_OFFSET[clampi(texture_index,0,1)],FRAME_COUNT)


func mesh_instance() -> MeshInstance3D:
	return _mesh_node


func renderer() -> Node2D:
	return _renderer


func surface_texture_indices() -> Array[int]:
	return _surface_textures.duplicate()


func surface_material(surface:int) -> StandardMaterial3D:
	return _materials[surface] if surface >= 0 and surface < _materials.size() else null


func _enter_tree() -> void:
	_rebuild()


func _exit_tree() -> void:
	_release()


func _notification(what:int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_visibility()


func _process(delta:float) -> void:
	if not playing or not is_finite(delta) or delta <= 0.0:
		return
	_frame_time += delta*FRAMES_PER_SECOND
	if _frame_time < 1.0:
		return
	var steps:int = int(floor(_frame_time))
	_frame_time -= float(steps)
	frame = posmod(frame+steps,FRAME_COUNT)
	_apply_frame()


func _rebuild() -> void:
	_release()
	if not is_inside_tree() or block_rect.size.x <= 0.0 or block_rect.size.y <= 0.0:
		return
	var shared:Node2D = _shared_renderer()
	if shared == null:
		return
	var built:Dictionary = build_mesh(block_rect.size,variant_seed_for(block_rect))
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "NativeFireBlock"
	_mesh_node.mesh = built.mesh
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_node.position = Vector3(block_rect.position.x,0.0,block_rect.position.y)
	_surface_textures = built.surface_textures
	var strips:Array[Texture2D] = textures()
	for surface:int in range(_surface_textures.size()):
		var material:StandardMaterial3D = _new_material(strips[_surface_textures[surface]])
		_materials.append(material)
		_mesh_node.set_surface_override_material(surface,material)
	shared.viewport.add_child(_mesh_node)
	_renderer = shared
	_add_renderer_user(shared,1)
	_apply_frame()
	_sync_visibility()


func _release() -> void:
	if is_instance_valid(_mesh_node):
		if _mesh_node.get_parent() != null:
			_mesh_node.get_parent().remove_child(_mesh_node)
		_mesh_node.queue_free()
	_mesh_node = null
	_materials.clear()
	_surface_textures.clear()
	if is_instance_valid(_renderer):
		_add_renderer_user(_renderer,-1)
	_renderer = null


func _apply_frame() -> void:
	for surface:int in range(_materials.size()):
		var row:int = frame_row(_surface_textures[surface])
		_materials[surface].uv1_offset = Vector3(0.0,float(row)/float(FRAME_COUNT),0.0)


func _sync_visibility() -> void:
	if is_instance_valid(_mesh_node):
		_mesh_node.visible = is_visible_in_tree()


func _new_material(strip:Texture2D) -> StandardMaterial3D:
	# 原版火焰方块 shade:false、发光、cutout：不吃方向光，保持贴图原色。
	var material := StandardMaterial3D.new()
	material.albedo_texture = strip
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = false
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.1
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.uv1_scale = Vector3(1.0,1.0/float(FRAME_COUNT),1.0)
	return material


func _shared_renderer() -> Node2D:
	var host:Node = _renderer_host()
	if host == null:
		return null
	var existing:Node = host.get_node_or_null(NodePath(String(RENDERER_NAME)))
	if existing != null:
		if existing.is_queued_for_deletion() or not is_instance_valid(existing.get("viewport")):
			return null
		return existing as Node2D
	# 复用地图立体墙的 overlay 模式：同一透视相机/投影算法，不另写相机。
	var shared:Node2D = WALL_RENDERER.new() as Node2D
	shared.name = RENDERER_NAME
	shared.set_meta(USERS_META,0)
	host.add_child(shared)
	var light:Variant = host.get("map_wall_light_direction")
	shared.configure_surface_overlay(block_rect.size,light if light is Vector2 else Vector2(1.0,-1.0))
	shared.z_as_relative = false
	shared.z_index = RENDERER_Z
	_set_renderer_active(shared,false)
	return shared


func _renderer_host() -> Node:
	var tree:SceneTree = get_tree()
	if tree == null:
		return null
	var scene:Node = tree.current_scene
	if is_instance_valid(scene) and scene.is_ancestor_of(self) and scene.get_viewport() == get_viewport():
		return scene
	return get_viewport()


static func _add_renderer_user(shared:Node2D,change:int) -> void:
	var users:int = maxi(int(shared.get_meta(USERS_META,0))+change,0)
	shared.set_meta(USERS_META,users)
	_set_renderer_active(shared,users > 0)


## 没有火时停掉整屏 3D 通道，不留空转的 GPU 渲染。
static func _set_renderer_active(shared:Node2D,active:bool) -> void:
	shared.visible = active
	var view:Variant = shared.get("viewport")
	if view is SubViewport:
		(view as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


## 原版按方块坐标挑模型变体；这里同样只由所在格决定，各端一致且不消耗战斗随机数。
static func variant_seed_for(rect:Rect2) -> int:
	var cell:Vector2i = Vector2i((rect.get_center()/rect.size.max(Vector2.ONE*0.01)).floor())
	return hash(cell)


## 返回 {mesh, surface_textures}：每个表面对应一张贴图条（0 = *_0，1 = *_1），网格原点在格子西北角地面。
static func build_mesh(size:Vector2,seed_value:int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tools:Array[SurfaceTool] = []
	var used:Array[bool] = [false,false]
	for i:int in range(2):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(tool)
	var scale := Vector3(size.x,minf(size.x,size.y),size.y)/16.0
	var full_uv := Vector4(0.0,0.0,16.0,16.0)
	var floor_texture:int = rng.randi_range(0,1)
	used[floor_texture] = true
	for plane:Array in FLOOR_PLANES:
		var corners:Array[Vector3] = _face_corners(plane[0],plane[1],plane[2])
		for i:int in range(4):
			corners[i] = _element_rotate(corners[i],int(plane[3]),float(plane[4]))
		_add_quad(tools[floor_texture],corners,full_uv,scale)
	for side:int in range(4):
		# 方块状态候选顺序 side0, side1, side_alt0, side_alt1；alt 为水平翻转 UV。
		var choice:int = rng.randi_range(0,3)
		var texture_index:int = choice % 2
		var uv:Vector4 = Vector4(16.0,0.0,0.0,16.0) if choice >= 2 else full_uv
		used[texture_index] = true
		for face:String in ["south","north"]:
			var corners:Array[Vector3] = _face_corners(SIDE_FROM,SIDE_TO,face)
			for i:int in range(4):
				corners[i] = _block_rotate_y(corners[i],side*90)
			_add_quad(tools[texture_index],corners,uv,scale)
	var mesh := ArrayMesh.new()
	var surface_textures:Array[int] = []
	for i:int in range(2):
		if not used[i]:
			continue
		tools[i].commit(mesh)
		surface_textures.append(i)
	return {"mesh":mesh,"surface_textures":surface_textures}


## 原版 FaceInfo 顶点顺序（从面外看逆时针），UV 依次取 (u0,v0)(u0,v1)(u1,v1)(u1,v0)。
static func _face_corners(from:Vector3,to:Vector3,face:String) -> Array[Vector3]:
	var a:Vector3 = from.min(to)
	var b:Vector3 = from.max(to)
	var corners:Array[Vector3] = []
	match face:
		"north": corners = [Vector3(b.x,b.y,a.z),Vector3(b.x,a.y,a.z),Vector3(a.x,a.y,a.z),Vector3(a.x,b.y,a.z)]
		"south": corners = [Vector3(a.x,b.y,b.z),Vector3(a.x,a.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,b.y,b.z)]
		"west": corners = [Vector3(a.x,b.y,a.z),Vector3(a.x,a.y,a.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z)]
		_: corners = [Vector3(b.x,b.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z)]
	return corners


## 原版元素旋转：绕 (8,8,8) 右手旋转，rescale 时另两轴乘 1/cos(角度)。
static func _element_rotate(point:Vector3,axis:int,degrees:float) -> Vector3:
	var d:Vector3 = point-MODEL_ORIGIN
	var angle:float = deg_to_rad(degrees)
	var c:float = cos(angle)
	var s:float = sin(angle)
	var r:Vector3
	match axis:
		0: r = Vector3(d.x,d.y*c-d.z*s,d.y*s+d.z*c)
		1: r = Vector3(d.x*c+d.z*s,d.y,-d.x*s+d.z*c)
		_: r = Vector3(d.x*c-d.y*s,d.x*s+d.y*c,d.z)
	var k:float = 1.0/cos(absf(angle))
	var stretch := Vector3(k,k,k)
	stretch[axis] = 1.0
	return r*stretch+MODEL_ORIGIN


## 方块状态 y 旋转：俯视顺时针，北边 -> 东边 -> 南边 -> 西边。
static func _block_rotate_y(point:Vector3,degrees:int) -> Vector3:
	var d:Vector3 = point-MODEL_ORIGIN
	match posmod(degrees,360):
		90: d = Vector3(-d.z,d.y,d.x)
		180: d = Vector3(-d.x,d.y,-d.z)
		270: d = Vector3(d.z,d.y,-d.x)
	return d+MODEL_ORIGIN


## 与地图立体墙同一绕序约定：(p1-p0)x(p2-p0) 为外法线，按 0,2,1,0,3,2 输出即 Godot 正面。
static func _add_quad(tool:SurfaceTool,corners:Array[Vector3],uv:Vector4,scale:Vector3) -> void:
	var points:Array[Vector3] = []
	for corner:Vector3 in corners:
		points.append(corner*scale)
	var uvs:Array[Vector2] = [_frame_uv(uv.x,uv.y),_frame_uv(uv.x,uv.w),_frame_uv(uv.z,uv.w),_frame_uv(uv.z,uv.y)]
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	for i:int in [0,2,1,0,3,2]:
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])


static func _frame_uv(u:float,v:float) -> Vector2:
	return Vector2(lerpf(UV_INSET,1.0-UV_INSET,u/16.0),lerpf(UV_INSET,1.0-UV_INSET,v/16.0))
