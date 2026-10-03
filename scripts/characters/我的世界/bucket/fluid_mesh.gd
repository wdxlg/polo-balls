extends RefCounted
const DIR:String = "res://Images/characters/我的世界/bucket/"
const WATER_STILL:Texture2D = preload(DIR + "water_still.png")
const WATER_FLOW:Texture2D = preload(DIR + "water_flow.png")
const LAVA_STILL:Texture2D = preload(DIR + "lava_still.png")
const LAVA_FLOW:Texture2D = preload(DIR + "lava_flow.png")
const WATER_TINT:Color = Color8(63,118,228)
const RENDERER_PATH:String = "res://scripts/effects/我的世界/mc_block_3d_renderer.gd"
const DEPTH_SCALE:float = 1.0
const FULL_HEIGHT:float = 8.0 / 9.0
const LOW_HEIGHT:float = 0.3
const SHADE_UP:float = 1.0
const SHADE_NORTH_SOUTH:float = 0.8
const SHADE_EAST_WEST:float = 0.6
const SHADE_LOW:float = 0.62
const STILL:int = 0
const FLOW:int = 1
const FRAME_COUNTS:Array = [[32,32],[20,16]]
const FRAME_SECONDS:Array = [[0.1,0.05],[0.1,0.15]]
const LAVA_STILL_ORDER:Array[int] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1]
const LIT_SHADER:String = """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 32.0;
uniform float frame = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 local = clamp(UV, vec2(0.002), vec2(0.998));
	vec3 color = texture(strip, vec2(local.x, (frame + local.y) / frames)).rgb * tint.rgb;
	ALBEDO = color * COLOR.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
"""
const GLOW_SHADER:String = """shader_type spatial;
render_mode cull_disabled, unshaded;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 20.0;
uniform float frame = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 local = clamp(UV, vec2(0.002), vec2(0.998));
	ALBEDO = texture(strip, vec2(local.x, (frame + local.y) / frames)).rgb * tint.rgb * COLOR.rgb;
}
"""
static var _shaders:Dictionary = {}
static var _warm_materials:Array[ShaderMaterial] = []


static func texture_for(liquid:int,surface:int) -> Texture2D:
	if liquid == 0: return WATER_STILL if surface == STILL else WATER_FLOW
	return LAVA_STILL if surface == STILL else LAVA_FLOW


static func shader_for(liquid:int) -> Shader:
	if not _shaders.has(liquid):
		var shader := Shader.new()
		shader.code = LIT_SHADER if liquid == 0 else GLOW_SHADER
		_shaders[liquid] = shader
	return _shaders[liquid]


static func new_material(liquid:int,surface:int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader_for(liquid)
	material.set_shader_parameter("strip",texture_for(liquid,surface))
	material.set_shader_parameter("frames",float(FRAME_COUNTS[liquid][surface]))
	material.set_shader_parameter("frame",0.0)
	material.set_shader_parameter("tint",WATER_TINT if liquid == 0 else Color.WHITE)
	return material


static func frame_at(liquid:int,surface:int,seconds:float) -> int:
	var step:int = int(floor(maxf(seconds,0.0) / float(FRAME_SECONDS[liquid][surface])))
	if liquid == 1 and surface == STILL: return LAVA_STILL_ORDER[posmod(step,LAVA_STILL_ORDER.size())]
	return posmod(step,int(FRAME_COUNTS[liquid][surface]))


static func corner_height(field:Node,liquid:int,cell:Vector2i,corner:Vector2i) -> float:
	var total:float = 0.0
	var weight:float = 0.0
	for offset:Vector2i in [Vector2i.ZERO,Vector2i(corner.x,0),Vector2i(0,corner.y),corner]:
		var other:Vector2i = cell + offset
		var height:float = field.fluid_height(liquid,other)
		if height <= 0.0: continue
		var w:float = 10.0 if height >= FULL_HEIGHT - 0.001 else 1.0
		total += height * w
		weight += w
	return total / weight if weight > 0.0 else 0.0


static func build(field:Node,liquid:int) -> Dictionary:
	var levels:Dictionary = field.levels[liquid]
	var size:Vector2 = field.grid_size
	var depth:float = minf(size.x,size.y) * DEPTH_SCALE
	var full:float = depth * FULL_HEIGHT
	var tools:Array[SurfaceTool] = []
	var used:Array[bool] = [false,false]
	for i:int in range(2):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(tool)
	for raw:Variant in levels.keys():
		var cell:Vector2i = raw
		var rect:Rect2 = field.cell_rect(cell)
		var x0:float = rect.position.x
		var x1:float = rect.end.x
		var z0:float = rect.position.y
		var z1:float = rect.end.y
		var nw:float = corner_height(field,liquid,cell,Vector2i(-1,-1)) * depth
		var ne:float = corner_height(field,liquid,cell,Vector2i(1,-1)) * depth
		var sw:float = corner_height(field,liquid,cell,Vector2i(-1,1)) * depth
		var se:float = corner_height(field,liquid,cell,Vector2i(1,1)) * depth
		var top:Array[Vector3] = [Vector3(x0,nw,z0),Vector3(x0,sw,z1),Vector3(x1,se,z1),Vector3(x1,ne,z0)]
		var flow:Vector2 = field.flow_vector(liquid,cell)
		if flow == Vector2.ZERO:
			_quad(tools[STILL],top,[Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)],full)
			used[STILL] = true
		else:
			var uvs:Array[Vector2] = []
			for q:Vector2 in [Vector2(-0.5,-0.5),Vector2(-0.5,0.5),Vector2(0.5,0.5),Vector2(0.5,-0.5)]:
				uvs.append(Vector2(0.5,0.5) + 0.5 * Vector2(flow.y * q.x - flow.x * q.y,flow.x * q.x + flow.y * q.y))
			_quad(tools[FLOW],top,uvs,full)
			used[FLOW] = true
		for side:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var other:Vector2i = cell + side
			if levels.has(other) or not field.is_open_cell(other): continue
			var pts:Array[Vector3] = []
			var heights:Array[float] = []
			match side:
				Vector2i.UP:
					pts = [Vector3(x1,ne,z0),Vector3(x1,0,z0),Vector3(x0,0,z0),Vector3(x0,nw,z0)]
					heights = [ne,nw]
				Vector2i.DOWN:
					pts = [Vector3(x0,sw,z1),Vector3(x0,0,z1),Vector3(x1,0,z1),Vector3(x1,se,z1)]
					heights = [sw,se]
				Vector2i.LEFT:
					pts = [Vector3(x0,nw,z0),Vector3(x0,0,z0),Vector3(x0,0,z1),Vector3(x0,sw,z1)]
					heights = [nw,sw]
				_:
					pts = [Vector3(x1,se,z1),Vector3(x1,0,z1),Vector3(x1,0,z0),Vector3(x1,ne,z0)]
					heights = [se,ne]
			if heights[0] <= 0.001 and heights[1] <= 0.001: continue
			var v0:float = (1.0 - heights[0] / maxf(depth,0.001)) * 0.5
			var v3:float = (1.0 - heights[1] / maxf(depth,0.001)) * 0.5
			_quad(tools[FLOW],pts,[Vector2(0.0,v0),Vector2(0.0,0.5),Vector2(0.5,0.5),Vector2(0.5,v3)],full)
			used[FLOW] = true
	var mesh := ArrayMesh.new()
	var surfaces:Array[int] = []
	for i:int in range(2):
		if not used[i]: continue
		tools[i].commit(mesh)
		surfaces.append(i)
	return {"mesh":mesh,"surfaces":surfaces}


static func face_shade(normal:Vector3) -> float:
	return normal.y * normal.y * SHADE_UP + normal.z * normal.z * SHADE_NORTH_SOUTH + normal.x * normal.x * SHADE_EAST_WEST


static func height_shade(y:float,full:float) -> float:
	if full <= 0.0: return 1.0
	return lerpf(SHADE_LOW,1.0,clampf(y / full,0.0,1.0))


static func _quad(tool:SurfaceTool,points:Array[Vector3],uvs:Array[Vector2],full:float = 0.0) -> void:
	var normal:Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	if normal.length_squared() < 0.000001: normal = (points[2] - points[0]).cross(points[3] - points[0])
	normal = normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
	if normal.y < -0.001: normal = -normal
	var shade:float = face_shade(normal)
	for i:int in [0,2,1,0,3,2]:
		var v:float = shade * height_shade(points[i].y,full)
		tool.set_color(Color(v,v,v,1.0))
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])


static func warm_mesh(origin:Vector2,size:float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var x0:float = origin.x - size * 0.5
	var x1:float = origin.x + size * 0.5
	var z0:float = origin.y - size * 0.5
	var z1:float = origin.y + size * 0.5
	var h:float = size * FULL_HEIGHT * DEPTH_SCALE
	for surface:int in [STILL,FLOW]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(tool,[Vector3(x0,h,z0),Vector3(x0,h,z1),Vector3(x1,h,z1),Vector3(x1,h,z0)],[Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)],h)
		_quad(tool,[Vector3(x0,h,z1),Vector3(x0,0,z1),Vector3(x1,0,z1),Vector3(x1,h,z1)],[Vector2(0,0),Vector2(0,0.5),Vector2(0.5,0.5),Vector2(0.5,0)],h)
		tool.commit(mesh)
	return mesh


static func prewarm_pipelines(host:Node) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless": return
	if not _warm_materials.is_empty(): return
	var renderer_script:Script = load(RENDERER_PATH)
	var size:float = 16.0
	var warm:Node2D = renderer_script.new()
	warm.name = "MCFluidPipelineWarmup"
	host.add_child(warm)
	warm.configure_block_overlay(size,renderer_script.GROUND)
	warm.set_active(true)
	warm.visible = false
	var view:Viewport = host.get_viewport()
	var center:Vector2 = view.get_canvas_transform().affine_inverse() * (view.get_visible_rect().size * 0.5)
	var mesh:ArrayMesh = warm_mesh(center,size)
	for liquid:int in [0,1]:
		var solid := MeshInstance3D.new()
		solid.mesh = mesh
		solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface:int in [STILL,FLOW]:
			var material:ShaderMaterial = new_material(liquid,surface)
			_warm_materials.append(material)
			solid.set_surface_override_material(surface,material)
		warm.viewport.add_child(solid)
	for _i:int in range(3): await RenderingServer.frame_post_draw
	if is_instance_valid(warm): warm.queue_free()
