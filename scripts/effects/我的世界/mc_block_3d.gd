extends Node2D
## 原版单格 3D 方块：按原版方块模型 JSON（elements/faces/uv/rotation）生成网格，放进与 3D 地面火
## 共享的地图立体墙 overlay（同一透视相机与投影），离地部分随镜头产生真实视差。
## 明暗用原版方块面亮度（上 1.0 / 南北 0.8 / 东西 0.6 / 下 0.5，shade:false 为 1.0）烘进顶点色，
## 贴图保持原版颜色，不会被 overlay 的太阳照过曝；昼夜仍由世界画布统一调色。
## overlay 的 3D 输出直接当显示色合成到 2D，所以着色器按原值采样贴图（不做 sRGB→线性），
## 否则颜色会被平方压暗。
## 只负责视觉：碰撞仍是宿主自己的 2D 形状。节点原点 = 方块格中心，边长 = 一格（地图格）。
## 透明度（set_alpha）、破坏裂纹（set_cracks，原版 destroy_stage 贴在同一组模型面上）与隐藏都跟随宿主。
## 碎片：附带一张透明的原版 particle 贴图 Sprite2D，公共碎片切割仍能切出方块碎片。
const FIRE = preload("res://scripts/effects/我的世界/mc_fire_block_3d.gd")
const WALL_RENDERER:Script = preload("res://scripts/effects/我的世界/地图立体墙.gd")
const DEFAULT_CELL:float = 16.0
const TEXTURES:Dictionary = {
	&"crafting_table_top":preload("res://Images/effects/我的世界/obstacle_blocks/crafting_table_top.png"),
	&"crafting_table_front":preload("res://Images/effects/我的世界/obstacle_blocks/crafting_table_front.png"),
	&"crafting_table_side":preload("res://Images/effects/我的世界/obstacle_blocks/crafting_table_side.png"),
	&"oak_planks":preload("res://Images/effects/我的世界/obstacle_blocks/oak_planks.png"),
	&"smithing_table_top":preload("res://Images/effects/我的世界/obstacle_blocks/smithing_table_top.png"),
	&"smithing_table_front":preload("res://Images/effects/我的世界/obstacle_blocks/smithing_table_front.png"),
	&"smithing_table_side":preload("res://Images/effects/我的世界/obstacle_blocks/smithing_table_side.png"),
	&"smithing_table_bottom":preload("res://Images/effects/我的世界/obstacle_blocks/smithing_table_bottom.png"),
	&"cactus_top":preload("res://Images/effects/我的世界/obstacle_blocks/cactus_top.png"),
	&"cactus_side":preload("res://Images/effects/我的世界/obstacle_blocks/cactus_side.png"),
	&"cactus_bottom":preload("res://Images/effects/我的世界/obstacle_blocks/cactus_bottom.png"),
	&"azalea_top":preload("res://Images/effects/我的世界/obstacle_blocks/azalea_top.png"),
	&"azalea_side":preload("res://Images/effects/我的世界/obstacle_blocks/azalea_side.png"),
	&"azalea_plant":preload("res://Images/effects/我的世界/obstacle_blocks/azalea_plant.png"),
	&"flowering_azalea_top":preload("res://Images/effects/我的世界/obstacle_blocks/flowering_azalea_top.png"),
	&"flowering_azalea_side":preload("res://Images/effects/我的世界/obstacle_blocks/flowering_azalea_side.png"),
	&"short_grass":preload("res://Images/effects/我的世界/obstacle_blocks/short_grass.png"),
}
## 原版 short_grass 的 tintindex 0：平原草色 #91BD59。
const GRASS_TINT:Color = Color8(0x91,0xBD,0x59)
const FACES:Array[String] = ["down","up","north","south","west","east"]
## 原版 Java 方块面亮度（主世界）。
const FACE_SHADE:Dictionary = {"down":0.5,"up":1.0,"north":0.8,"south":0.8,"west":0.6,"east":0.6}
## 不透明：原版 cutout（透明像素丢弃），走不透明队列。
const OPAQUE_SHADER_CODE:String = """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D albedo_tex : filter_nearest;
void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	if (texel.a < 0.1) discard;
	ALBEDO = texel.rgb * COLOR.rgb;
}
"""
## 淡出：屏幕像素 4×4 有序抖动（仍走不透明队列）。overlay 合成对半透明 3D 像素的颜色处理与不透明
## 不一致（会发白），抖动不经过混合；同一屏幕像素的阈值相同，前后各层同时镂空，整格像一张半透明方块。
const FADE_SHADER_CODE:String = """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D albedo_tex : filter_nearest;
uniform float fade = 1.0;
const float BAYER[16] = float[16](0.0,8.0,2.0,10.0,12.0,4.0,14.0,6.0,3.0,11.0,1.0,9.0,15.0,7.0,13.0,5.0);
void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	if (texel.a < 0.1) discard;
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	if ((BAYER[p.y * 4 + p.x] + 0.5) / 16.0 > fade) discard;
	ALBEDO = texel.rgb * COLOR.rgb;
}
"""
## 原版破坏裂纹：乘法混合（DST_COLOR）贴在方块模型面上，透明像素丢弃。
const CRACK_SHADER_CODE:String = """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, blend_mul, depth_draw_never;
uniform sampler2D albedo_tex : filter_nearest;
void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	if (texel.a < 0.1) discard;
	ALBEDO = texel.rgb;
}
"""
static var _shaders:Dictionary = {}

var model:StringName = &""
var cell:float = DEFAULT_CELL
var alpha:float = 1.0
var crack_texture:Texture2D = null
var debris_sample:Sprite2D = null
var _mesh_node:MeshInstance3D = null
var _crack_node:MeshInstance3D = null
var _materials:Array[ShaderMaterial] = []
var _crack_material:ShaderMaterial = null
var _renderer:Node2D = null


## model 见 MODELS；size 为方块边长（像素，默认一格地图格）。
static func create(model_name:StringName,size:float = DEFAULT_CELL) -> Node2D:
	var block:Node2D = load("res://scripts/effects/我的世界/mc_block_3d.gd").new()
	block.name = "MCBlock3D"
	block.model = model_name
	block.cell = maxf(size,0.01)
	return block


## 当前地图的一格（与地图立体墙、3D 地面火同一尺寸）；没有地图时为 16。
static func map_cell(context:Node) -> float:
	if context == null or not context.is_inside_tree(): return DEFAULT_CELL
	var scene:Node = context.get_tree().current_scene
	if scene == null or not scene.has_method("map_visual_cell_size") or not scene.has_method("_current_map_node"): return DEFAULT_CELL
	var map_node:Node = scene.call("_current_map_node")
	if not is_instance_valid(map_node): return DEFAULT_CELL
	var size:Vector2 = scene.call("map_visual_cell_size",map_node)
	return maxf(minf(size.x,size.y),0.01)


## 障碍宿主（StaticBody2D 等）身上的 3D 方块：直接子节点。
static func find_in(node:Node) -> Node2D:
	if node == null: return null
	for child:Node in node.get_children():
		if child is Node2D and child.has_method("set_cracks") and child.has_method("block_rect"): return child as Node2D
	return null


func set_alpha(value:float) -> void:
	value = clampf(value,0.0,1.0)
	if is_equal_approx(value,alpha): return
	alpha = value
	_apply_alpha()


func set_cracks(texture:Texture2D) -> void:
	if texture == crack_texture: return
	crack_texture = texture
	if is_instance_valid(_crack_node):
		if crack_texture != null: _crack_material.set_shader_parameter("albedo_tex",crack_texture)
	_sync_visibility()


func set_model(model_name:StringName) -> void:
	if model_name == model: return
	model = model_name
	if is_inside_tree(): _rebuild()


func mesh_instance() -> MeshInstance3D:
	return _mesh_node


func crack_instance() -> MeshInstance3D:
	return _crack_node


func renderer() -> Node2D:
	return _renderer


func surface_material(surface:int) -> ShaderMaterial:
	return _materials[surface] if surface >= 0 and surface < _materials.size() else null


## 2D 落地格（世界坐标）：节点原点为中心、边长一格。
func block_rect() -> Rect2:
	return Rect2(global_position-Vector2.ONE*cell*0.5,Vector2.ONE*cell)


func _enter_tree() -> void:
	set_notify_transform(true)
	_ensure_debris_sample()
	_rebuild()


func _exit_tree() -> void:
	_release()


func _notification(what:int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED: _sync_visibility()
		NOTIFICATION_TRANSFORM_CHANGED: _sync_position()


func _ensure_debris_sample() -> void:
	if is_instance_valid(debris_sample): return
	var spec:Dictionary = MODELS.get(model,{})
	var texture:Texture2D = TEXTURES.get(spec.get("particle",&""))
	if texture == null: return
	debris_sample = Sprite2D.new()
	debris_sample.name = "BlockDebrisSample"
	debris_sample.texture = texture
	debris_sample.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	debris_sample.scale = Vector2.ONE*cell/float(maxi(texture.get_width(),1))
	# 只给公共碎片切割取样（碎片复制 texture/modulate，不复制 self_modulate）；画面由 3D 网格负责。
	debris_sample.self_modulate = Color(1,1,1,0)
	add_child(debris_sample)


func _rebuild() -> void:
	_release()
	if not is_inside_tree() or not MODELS.has(model): return
	var shared:Node2D = _shared_renderer()
	if shared == null: return
	var built:Dictionary = build_mesh(model,cell)
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "NativeBlock_%s" % model
	_mesh_node.mesh = built.mesh
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface_textures:Array = built.textures
	for surface:int in range(surface_textures.size()):
		var texture:Texture2D = TEXTURES[surface_textures[surface]]
		var material:ShaderMaterial = new_material(texture)
		_materials.append(material)
		_mesh_node.set_surface_override_material(surface,material)
	shared.viewport.add_child(_mesh_node)
	_crack_node = MeshInstance3D.new()
	_crack_node.name = "NativeBlockCracks"
	_crack_node.mesh = built.crack_mesh
	_crack_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack_material = new_crack_material()
	_crack_node.material_override = _crack_material
	shared.viewport.add_child(_crack_node)
	_renderer = shared
	FIRE._add_renderer_user(shared,1)
	_sync_position()
	_apply_alpha()
	if crack_texture != null: _crack_material.set_shader_parameter("albedo_tex",crack_texture)
	_sync_visibility()


func _release() -> void:
	for node:MeshInstance3D in [_mesh_node,_crack_node]:
		if is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()
	_mesh_node = null
	_crack_node = null
	_materials.clear()
	_crack_material = null
	if is_instance_valid(_renderer): FIRE._add_renderer_user(_renderer,-1)
	_renderer = null


func _sync_position() -> void:
	var corner:Vector2 = global_position-Vector2.ONE*cell*0.5
	for node:MeshInstance3D in [_mesh_node,_crack_node]:
		if is_instance_valid(node): node.position = Vector3(corner.x,0.0,corner.y)


func _sync_visibility() -> void:
	var shown:bool = is_visible_in_tree() and alpha > 0.001
	if is_instance_valid(_mesh_node): _mesh_node.visible = shown
	# 抖动淡出时乘法裂纹会透过镂空压暗地面，只在实心方块上显示。
	if is_instance_valid(_crack_node): _crack_node.visible = shown and crack_texture != null and alpha >= 0.999


func _apply_alpha() -> void:
	var faded:bool = alpha < 0.999
	for material:ShaderMaterial in _materials:
		# 不透明时用原版 cutout；淡出时改为有序抖动。
		material.shader = shader_for("fade" if faded else "opaque")
		material.set_shader_parameter("fade",alpha)
	_sync_visibility()


func _shared_renderer() -> Node2D:
	var host:Node = _renderer_host()
	if host == null: return null
	var existing:Node = host.get_node_or_null(NodePath(String(FIRE.RENDERER_NAME)))
	if existing != null:
		if existing.is_queued_for_deletion() or not is_instance_valid(existing.get("viewport")): return null
		return existing as Node2D
	# 与 3D 地面火共用同一个 overlay：一条整屏 3D 通道，火与方块之间也有正确的深度遮挡。
	var shared:Node2D = WALL_RENDERER.new() as Node2D
	shared.name = FIRE.RENDERER_NAME
	shared.set_meta(FIRE.USERS_META,0)
	host.add_child(shared)
	var light:Variant = host.get("map_wall_light_direction")
	shared.configure_surface_overlay(Vector2.ONE*cell,light if light is Vector2 else Vector2(1.0,-1.0))
	shared.z_as_relative = false
	shared.z_index = FIRE.RENDERER_Z
	FIRE._set_renderer_active(shared,false)
	return shared


func _renderer_host() -> Node:
	var tree:SceneTree = get_tree()
	if tree == null: return null
	var scene:Node = tree.current_scene
	if is_instance_valid(scene) and scene.is_ancestor_of(self) and scene.get_viewport() == get_viewport(): return scene
	return get_viewport()


static func shader_for(kind:String) -> Shader:
	if not _shaders.has(kind):
		var shader := Shader.new()
		match kind:
			"fade": shader.code = FADE_SHADER_CODE
			"crack": shader.code = CRACK_SHADER_CODE
			_: shader.code = OPAQUE_SHADER_CODE
		_shaders[kind] = shader
	return _shaders[kind]


static func new_material(texture:Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader_for("opaque")
	material.set_shader_parameter("albedo_tex",texture)
	return material


static func new_crack_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader_for("crack")
	material.render_priority = 1
	return material


## 原版模型（minecraft 1.21.4 models/block/*.json 的 elements 逐项照抄）。
## 元素：{from, to, faces:{面:[贴图, uv(u0,v0,u1,v1)]}, rotation:[轴 0=x/1=y/2=z, 角度, rescale]}，tint=tintindex 0。
const CUBE_UV:Vector4 = Vector4(0,0,16,16)
const MODELS:Dictionary = {
	# block/crafting_table.json（parent block/cube）
	&"crafting_table":{"particle":&"crafting_table_front","elements":[
		{"from":Vector3(0,0,0),"to":Vector3(16,16,16),"faces":{
			"down":[&"oak_planks",CUBE_UV],"up":[&"crafting_table_top",CUBE_UV],
			"north":[&"crafting_table_front",CUBE_UV],"south":[&"crafting_table_side",CUBE_UV],
			"west":[&"crafting_table_front",CUBE_UV],"east":[&"crafting_table_side",CUBE_UV]}},
	]},
	# block/smithing_table.json（parent block/cube）
	&"smithing_table":{"particle":&"smithing_table_front","elements":[
		{"from":Vector3(0,0,0),"to":Vector3(16,16,16),"faces":{
			"down":[&"smithing_table_bottom",CUBE_UV],"up":[&"smithing_table_top",CUBE_UV],
			"north":[&"smithing_table_front",CUBE_UV],"south":[&"smithing_table_front",CUBE_UV],
			"west":[&"smithing_table_side",CUBE_UV],"east":[&"smithing_table_side",CUBE_UV]}},
	]},
	# block/cactus.json：顶/底整格，四个侧面各内缩 1/16。
	&"cactus":{"particle":&"cactus_side","elements":[
		{"from":Vector3(0,0,0),"to":Vector3(16,16,16),"faces":{"down":[&"cactus_bottom",CUBE_UV],"up":[&"cactus_top",CUBE_UV]}},
		{"from":Vector3(0,0,1),"to":Vector3(16,16,15),"faces":{"north":[&"cactus_side",CUBE_UV],"south":[&"cactus_side",CUBE_UV]}},
		{"from":Vector3(1,0,0),"to":Vector3(15,16,16),"faces":{"west":[&"cactus_side",CUBE_UV],"east":[&"cactus_side",CUBE_UV]}},
	]},
	# block/template_azalea.json + azalea.json / flowering_azalea.json
	&"azalea":{"particle":&"azalea_top","elements":"azalea"},
	&"flowering_azalea":{"particle":&"flowering_azalea_top","elements":"flowering_azalea"},
	# block/short_grass.json（parent block/tinted_cross）
	&"short_grass":{"particle":&"short_grass","elements":[
		{"from":Vector3(0.8,0,8),"to":Vector3(15.2,16,8),"rotation":[1,45.0,true],"shade":false,"tint":true,"faces":{"north":[&"short_grass",CUBE_UV],"south":[&"short_grass",CUBE_UV]}},
		{"from":Vector3(8,0,0.8),"to":Vector3(8,16,15.2),"rotation":[1,45.0,true],"shade":false,"tint":true,"faces":{"west":[&"short_grass",CUBE_UV],"east":[&"short_grass",CUBE_UV]}},
	]},
}


static func azalea_elements(top:StringName,side:StringName) -> Array:
	return [
		{"from":Vector3(0,16,0),"to":Vector3(16,16,16),"faces":{"down":[top,Vector4(0,16,16,0)],"up":[top,CUBE_UV]}},
		{"from":Vector3(0,5,0),"to":Vector3(16,16,0.01),"faces":{"north":[side,Vector4(0,0,16,11)],"south":[side,Vector4(16,0,0,11)]}},
		{"from":Vector3(0,5,15.99),"to":Vector3(16,16,16),"faces":{"north":[side,Vector4(16,0,0,11)],"south":[side,Vector4(0,0,16,11)]}},
		{"from":Vector3(0,5,0),"to":Vector3(0.01,16,16),"faces":{"west":[side,Vector4(0,0,16,11)],"east":[side,Vector4(16,0,0,11)]}},
		{"from":Vector3(15.99,5,0),"to":Vector3(16,16,16),"faces":{"west":[side,Vector4(16,0,0,11)],"east":[side,Vector4(0,0,16,11)]}},
		{"from":Vector3(0.1,0,8),"to":Vector3(15.9,15.9,8),"rotation":[1,45.0,true],"faces":{"north":[&"azalea_plant",CUBE_UV],"south":[&"azalea_plant",CUBE_UV]}},
		{"from":Vector3(8,0,0.1),"to":Vector3(8,15.9,15.9),"rotation":[1,45.0,true],"faces":{"west":[&"azalea_plant",CUBE_UV],"east":[&"azalea_plant",CUBE_UV]}},
	]


static func model_elements(model_name:StringName) -> Array:
	var spec:Dictionary = MODELS.get(model_name,{})
	var elements:Variant = spec.get("elements",[])
	if elements is String:
		# 两种杜鹃花丛共用原版 template_azalea，只换 top/side 贴图。
		return azalea_elements(StringName(elements+"_top"),StringName(elements+"_side"))
	return elements if elements is Array else []


## 返回 {mesh, textures(每个表面的贴图键), crack_mesh}；网格原点在格子西北角地面。
static func build_mesh(model_name:StringName,size:float) -> Dictionary:
	var scale:float = size/16.0
	var tools:Dictionary = {} # 贴图 -> SurfaceTool
	var order:Array[String] = []
	var crack := SurfaceTool.new()
	crack.begin(Mesh.PRIMITIVE_TRIANGLES)
	for element:Dictionary in model_elements(model_name):
		var rotation:Array = element.get("rotation",[])
		var tint:Color = GRASS_TINT if bool(element.get("tint",false)) else Color.WHITE
		var shade:bool = bool(element.get("shade",true))
		var faces:Dictionary = element.faces
		for face:String in FACES:
			if not faces.has(face): continue
			var texture_key:StringName = faces[face][0]
			var uv:Vector4 = faces[face][1]
			var corners:Array[Vector3] = face_corners(element.from,element.to,face)
			if not rotation.is_empty():
				for i:int in range(4): corners[i] = element_rotate(corners[i],int(rotation[0]),float(rotation[1]),bool(rotation[2]))
			var key:String = String(texture_key)
			if not tools.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = tool
				order.append(key)
			var light:float = float(FACE_SHADE[face]) if shade else 1.0
			add_quad(tools[key],corners,uv,scale,0.0,Color(tint.r*light,tint.g*light,tint.b*light))
			# 裂纹沿外法线抬起 1/64 格，避免与方块面 z-fighting。
			add_quad(crack,corners,uv,scale,0.25,Color.WHITE)
	var mesh := ArrayMesh.new()
	var textures:Array[StringName] = []
	for key:String in order:
		(tools[key] as SurfaceTool).commit(mesh)
		textures.append(StringName(key))
	return {"mesh":mesh,"textures":textures,"crack_mesh":crack.commit()}


## 原版 FaceInfo 顶点顺序（从面外看逆时针），UV 依次取 (u0,v0)(u0,v1)(u1,v1)(u1,v0)。
## 坐标：原版 x→世界 x、y→高度、z→世界 2D 的 y（北 = 屏幕上方）。
static func face_corners(from:Vector3,to:Vector3,face:String) -> Array[Vector3]:
	var a:Vector3 = from.min(to)
	var b:Vector3 = from.max(to)
	match face:
		"down": return [Vector3(a.x,a.y,b.z),Vector3(a.x,a.y,a.z),Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z)]
		"up": return [Vector3(a.x,b.y,a.z),Vector3(a.x,b.y,b.z),Vector3(b.x,b.y,b.z),Vector3(b.x,b.y,a.z)]
		"north": return [Vector3(b.x,b.y,a.z),Vector3(b.x,a.y,a.z),Vector3(a.x,a.y,a.z),Vector3(a.x,b.y,a.z)]
		"south": return [Vector3(a.x,b.y,b.z),Vector3(a.x,a.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,b.y,b.z)]
		"west": return [Vector3(a.x,b.y,a.z),Vector3(a.x,a.y,a.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z)]
	return [Vector3(b.x,b.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z)]


## 原版元素旋转：绕 (8,8,8) 右手旋转；rescale 时另两轴乘 1/cos(角度)。
static func element_rotate(point:Vector3,axis:int,degrees:float,rescale:bool) -> Vector3:
	var d:Vector3 = point-Vector3(8,8,8)
	var angle:float = deg_to_rad(degrees)
	var c:float = cos(angle)
	var s:float = sin(angle)
	var r:Vector3
	match axis:
		0: r = Vector3(d.x,d.y*c-d.z*s,d.y*s+d.z*c)
		1: r = Vector3(d.x*c+d.z*s,d.y,-d.x*s+d.z*c)
		_: r = Vector3(d.x*c-d.y*s,d.x*s+d.y*c,d.z)
	if rescale:
		var k:float = 1.0/cos(absf(angle))
		var stretch := Vector3(k,k,k)
		stretch[axis] = 1.0
		r *= stretch
	return r+Vector3(8,8,8)


## 与地图立体墙/3D 火同一绕序：(p1-p0)x(p2-p0) 为外法线，按 0,2,1,0,3,2 输出即 Godot 正面。
static func add_quad(tool:SurfaceTool,corners:Array[Vector3],uv:Vector4,scale:float,lift:float,color:Color) -> void:
	var points:Array[Vector3] = []
	for corner:Vector3 in corners: points.append(corner*scale)
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if lift != 0.0:
		for i:int in range(4): points[i] += normal*lift
	var uvs:Array[Vector2] = [Vector2(uv.x,uv.y)/16.0,Vector2(uv.x,uv.w)/16.0,Vector2(uv.z,uv.w)/16.0,Vector2(uv.z,uv.y)/16.0]
	for i:int in [0,2,1,0,3,2]:
		tool.set_color(color)
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])
