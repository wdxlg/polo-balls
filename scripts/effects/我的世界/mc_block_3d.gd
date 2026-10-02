extends Node2D
## 原版单格 3D 方块障碍：按原版方块模型 JSON（elements/faces/uv/rotation）生成网格，放进
## mc_block_3d_renderer.gd 的透视 overlay —— 与地图立体墙同一相机/投影、同一受光材质与太阳
## （随昼夜转向），画在角色之下，并把真实影子投到地面。离地部分随镜头产生真实视差。
## 只负责视觉：碰撞仍是宿主自己的 2D 形状。节点原点 = 方块格中心，边长 = 一格（地图格）。
## 破坏裂纹（set_cracks）在方块着色器里按原版 destroy_stage 乘到同一组模型面上（无叠加网格，不会 z 闪烁）。
## 显现/消失（set_alpha）用固定在贴图像素上的溶解，不做半透明混合（overlay 合成半透明 3D 像素会发白），
## 也不用屏幕空间抖动（镜头移动时会闪）。
## 碎片：附带一张透明的原版 particle 贴图 Sprite2D，公共碎片切割仍能切出方块碎片。
const RENDERER = preload("res://scripts/effects/我的世界/mc_block_3d_renderer.gd")
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
}
const FACES:Array[String] = ["down","up","north","south","west","east"]
## 与地图立体墙 _new_material 同一受光模型（Burley 漫反射、粗糙度 1、非金属、sRGB 贴图），
## 另加原版 cutout、像素溶解与破坏裂纹。
const SHADER_CODE:String = """shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform sampler2D crack_tex : filter_nearest;
uniform bool cracked = false;
uniform float fade = 1.0;
float texel_hash(vec2 texel) {
	return fract(sin(dot(texel, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	if (texel.a < 0.1) discard;
	if (fade < 0.999 && texel_hash(floor(UV * 16.0)) >= fade) discard;
	vec3 color = texel.rgb;
	if (cracked) {
		vec4 crack = texture(crack_tex, UV);
		// 原版 crumbling：DST_COLOR * SRC_COLOR * 2，透明处不变。
		if (crack.a > 0.1) color *= min(crack.rgb * 2.0, vec3(1.0));
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
"""
static var _shader:Shader = null

var model:StringName = &""
var cell:float = DEFAULT_CELL
var alpha:float = 1.0
var crack_texture:Texture2D = null
var debris_sample:Sprite2D = null
var _mesh_node:MeshInstance3D = null
var _shadow_node:MeshInstance3D = null
var _materials:Array[ShaderMaterial] = []
var _renderer:Node2D = null
## 0 = 实体，1 = 完全换成半透明副本（仅花丛类模型）。
var see_through:float = 0.0
var _ghost_materials:Array[ShaderMaterial] = []
var _ghost_node:MeshInstance3D = null
var _ghost_renderer:Node2D = null
var _ghost_user:bool = false
const CANOPY_MODELS:Array[StringName] = [&"azalea",&"flowering_azalea"]


## model 见 MODELS；size 为方块边长（像素，默认一格地图格）。
static func create(model_name:StringName,size:float = DEFAULT_CELL) -> Node2D:
	var block:Node2D = load("res://scripts/effects/我的世界/mc_block_3d.gd").new()
	block.name = "MCBlock3D"
	block.model = model_name
	block.cell = maxf(size,0.01)
	return block


## 当前地图的一格（与地图立体墙同一尺寸）；没有地图时为 16。
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


## Materials of the load-time warm draw, kept so their compiled pipelines stay alive.
static var _warm_materials:Array[Material] = []


## Draws one hidden block through a private renderer for a few frames, so the block shader,
## its shadow pass and the ground shadow catcher compile while the world loads instead of
## freezing the battle the first time a block appears.
static func prewarm_pipelines(host:Node) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless": return
	if not _warm_materials.is_empty(): return
	var size:float = map_cell(host)
	var warm:Node2D = RENDERER.new()
	warm.name = "MCBlock3DPipelineWarmup"
	host.add_child(warm)
	warm.configure_block_overlay(size,RENDERER.GROUND)
	warm.set_active(true)
	warm.visible = false
	var view:Viewport = host.get_viewport()
	var center:Vector2 = view.get_canvas_transform().affine_inverse() * (view.get_visible_rect().size*0.5)
	var built:Dictionary = build_mesh(&"crafting_table",size)
	var solid := MeshInstance3D.new()
	solid.mesh = built.mesh
	solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var caster := MeshInstance3D.new()
	caster.mesh = built.mesh
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for surface:int in range(built.textures.size()):
		var material:ShaderMaterial = new_material(TEXTURES[built.textures[surface]])
		material.set_shader_parameter("fade",1.0)
		_warm_materials.append(material)
		solid.set_surface_override_material(surface,material)
		caster.set_surface_override_material(surface,material)
	if warm.ground_node.material_override != null: _warm_materials.append(warm.ground_node.material_override)
	for node:MeshInstance3D in [solid,caster]: node.position = Vector3(center.x-size*0.5,0.0,center.y-size*0.5)
	warm.viewport.add_child(solid)
	warm.shadow_viewport.add_child(caster)
	for _i:int in range(3): await RenderingServer.frame_post_draw
	if is_instance_valid(warm): warm.queue_free()


static func block_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


static func new_material(texture:Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = block_shader()
	material.set_shader_parameter("albedo_tex",texture)
	return material


func set_alpha(value:float) -> void:
	value = clampf(value,0.0,1.0)
	if is_equal_approx(value,alpha): return
	alpha = value
	_apply_material_state()


func set_cracks(texture:Texture2D) -> void:
	if texture == crack_texture: return
	crack_texture = texture
	_apply_material_state()


## 花丛被人挡住时变半透明：value 0..1 在实体与 SEE_THROUGH_ALPHA 之间过渡（纹素溶解实体层）。
func set_see_through(value:float) -> void:
	value = clampf(value,0.0,1.0)
	if is_equal_approx(value,see_through): return
	see_through = value
	_sync_ghost_user()
	_apply_material_state()


func ghost_instance() -> MeshInstance3D:
	return _ghost_node


func ghost_renderer() -> Node2D:
	return _ghost_renderer


func _sync_ghost_user() -> void:
	var wanted:bool = see_through > 0.001 and is_instance_valid(_ghost_node) and is_instance_valid(_ghost_renderer)
	if wanted == _ghost_user: return
	_ghost_user = wanted
	RENDERER.add_user(_ghost_renderer,1 if wanted else -1)


func set_model(model_name:StringName) -> void:
	if model_name == model: return
	model = model_name
	if is_inside_tree(): _rebuild()


func mesh_instance() -> MeshInstance3D:
	return _mesh_node


func shadow_instance() -> MeshInstance3D:
	return _shadow_node


func renderer() -> Node2D:
	return _renderer


## 苔藓长出的杜鹃花丛是"树冠"，画在角色之上；工作台/锻造台/仙人掌和墙同层在角色之下。
static func layer_for(model_name:StringName) -> StringName:
	return RENDERER.CANOPY if CANOPY_MODELS.has(model_name) else RENDERER.GROUND


func overlay_layer() -> StringName:
	return layer_for(model)


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
	var shared:Node2D = RENDERER.shared_for(_renderer_host(),cell,overlay_layer())
	if shared == null: return
	var built:Dictionary = build_mesh(model,cell)
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "NativeBlock_%s" % model
	_mesh_node.mesh = built.mesh
	# 主通道里方块之间互相投影（与墙同一太阳）；地面影子由影子通道的同网格代理投出。
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shadow_node = MeshInstance3D.new()
	_shadow_node.name = "NativeBlockGroundShadow_%s" % model
	_shadow_node.mesh = built.mesh
	_shadow_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var ghost_host:Node2D = RENDERER.shared_for(_renderer_host(),cell,RENDERER.SEE_THROUGH) if overlay_layer() == RENDERER.CANOPY else null
	if is_instance_valid(ghost_host):
		# 半透明副本层里放一模一样的网格（同样互相投影），像素与实体层一致。
		_ghost_node = MeshInstance3D.new()
		_ghost_node.name = "NativeBlockSeeThrough_%s" % model
		_ghost_node.mesh = built.mesh
		_ghost_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var surface_textures:Array = built.textures
	for surface:int in range(surface_textures.size()):
		var texture:Texture2D = TEXTURES[surface_textures[surface]]
		var material:ShaderMaterial = new_material(texture)
		_materials.append(material)
		_mesh_node.set_surface_override_material(surface,material)
		# 影子与主网格同材质（仙人掌内缩、出现溶解一致）；花丛的影子改用半透明副本的材质，
		# 两者状态都只跟 alpha 走，花丛变半透明时影子不消失。
		var shadow_material:ShaderMaterial = material
		if _ghost_node != null:
			shadow_material = new_material(texture)
			_ghost_materials.append(shadow_material)
			_ghost_node.set_surface_override_material(surface,shadow_material)
		_shadow_node.set_surface_override_material(surface,shadow_material)
	shared.viewport.add_child(_mesh_node)
	shared.shadow_viewport.add_child(_shadow_node)
	_renderer = shared
	RENDERER.add_user(shared,1)
	if _ghost_node != null:
		ghost_host.viewport.add_child(_ghost_node)
		_ghost_renderer = ghost_host
		_sync_ghost_user()
	_sync_position()
	_apply_material_state()


func _release() -> void:
	if _ghost_user and is_instance_valid(_ghost_renderer): RENDERER.add_user(_ghost_renderer,-1)
	_ghost_user = false
	_ghost_renderer = null
	for node:MeshInstance3D in [_mesh_node,_shadow_node,_ghost_node]:
		if is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()
	_mesh_node = null
	_shadow_node = null
	_ghost_node = null
	_materials.clear()
	_ghost_materials.clear()
	if is_instance_valid(_renderer): RENDERER.add_user(_renderer,-1)
	_renderer = null


func _sync_position() -> void:
	var corner:Vector2 = global_position-Vector2.ONE*cell*0.5
	for node:MeshInstance3D in [_mesh_node,_shadow_node,_ghost_node]:
		if is_instance_valid(node): node.position = Vector3(corner.x,0.0,corner.y)


func _sync_visibility() -> void:
	var shown:bool = is_visible_in_tree() and alpha > 0.001
	for node:MeshInstance3D in [_mesh_node,_shadow_node,_ghost_node]:
		if is_instance_valid(node): node.visible = shown


func _apply_material_state() -> void:
	var solid:float = alpha if _ghost_node == null else alpha*(1.0-see_through)
	for material:ShaderMaterial in _materials: _set_material_state(material,solid)
	for material:ShaderMaterial in _ghost_materials: _set_material_state(material,alpha)
	_sync_visibility()


func _set_material_state(material:ShaderMaterial,fade:float) -> void:
	material.set_shader_parameter("fade",fade)
	material.set_shader_parameter("cracked",crack_texture != null)
	if crack_texture != null: material.set_shader_parameter("crack_tex",crack_texture)


func _renderer_host() -> Node:
	var tree:SceneTree = get_tree()
	if tree == null: return null
	var scene:Node = tree.current_scene
	if is_instance_valid(scene) and scene.is_ancestor_of(self) and scene.get_viewport() == get_viewport(): return scene
	return get_viewport()


## 原版模型（minecraft 1.21.4 models/block/*.json 的 elements 逐项照抄）。
## 元素：{from, to, faces:{面:[贴图, uv(u0,v0,u1,v1)]}, rotation:[轴 0=x/1=y/2=z, 角度, rescale]}。
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


## 返回 {mesh, textures(每个表面的贴图键)}；网格原点在格子西北角地面。
static func build_mesh(model_name:StringName,size:float) -> Dictionary:
	var scale:float = size/16.0
	var tools:Dictionary = {} # 贴图 -> SurfaceTool
	var order:Array[String] = []
	for element:Dictionary in model_elements(model_name):
		var rotation:Array = element.get("rotation",[])
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
			add_quad(tools[key],corners,uv,scale)
	var mesh := ArrayMesh.new()
	var textures:Array[StringName] = []
	for key:String in order:
		(tools[key] as SurfaceTool).commit(mesh)
		textures.append(StringName(key))
	return {"mesh":mesh,"textures":textures}


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
static func add_quad(tool:SurfaceTool,corners:Array[Vector3],uv:Vector4,scale:float) -> void:
	var points:Array[Vector3] = []
	for corner:Vector3 in corners: points.append(corner*scale)
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	var uvs:Array[Vector2] = [Vector2(uv.x,uv.y)/16.0,Vector2(uv.x,uv.w)/16.0,Vector2(uv.z,uv.w)/16.0,Vector2(uv.z,uv.y)/16.0]
	for i:int in [0,2,1,0,3,2]:
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])
