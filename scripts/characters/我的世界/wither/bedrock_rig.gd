extends Node3D
## Live, bone-by-bone Bedrock Wither. Geometry/UV/animation channels come from
## Mojang/bedrock-samples (see bedrock/SOURCE_MANIFEST.json), not a sprite bake.
const FOLDER = "res://Images/characters/我的世界/wither/bedrock/"
const BODY = preload("res://Images/characters/我的世界/wither/bedrock/wither.png")
const INVULNERABLE = preload("res://Images/characters/我的世界/wither/bedrock/wither_invulnerable.png")
const ARMOR_BLUE = preload("res://Images/characters/我的世界/wither/bedrock/wither_armor_blue.png")
const ARMOR_WHITE = preload("res://Images/characters/我的世界/wither/bedrock/wither_armor_white.png")
var armor_blue_material:StandardMaterial3D
var armor_white_material:StandardMaterial3D
var bones:Dictionary = {}
var armor_bones:Dictionary = {}
var body_meshes:Array[MeshInstance3D] = []
var armor_layer:Node3D
var current_invulnerable:bool = false
var _body_pitch:float = 0.0
var _body_roll:float = 0.0
var _head_yaw:Array[float] = [0.0,0.0,0.0]
var _head_pitch:Array[float] = [0.0,0.0,0.0]
var _head_recoil:Array[float] = [0.0,0.0,0.0]

func _ready() -> void:
	var original:Dictionary = _load_json(FOLDER+"wither_boss.geo.json")
	var armor_data:Dictionary = _load_json(FOLDER+"wither_boss_armor.geo.json")
	# Validate the real Minecraft Bedrock animation controller and channels, too.
	var animations:Dictionary = _load_json(FOLDER+"wither_boss.animation.json")
	var controllers:Dictionary = _load_json(FOLDER+"wither_boss.animation_controllers.json")
	assert(animations.has("animations") and controllers.has("animation_controllers"))
	var moves:Array = controllers["animation_controllers"]["controller.animation.wither_boss.move"]["states"]["default"]["animations"]
	assert(moves == ["scale","move","look_at_target"])
	_build(original["geometry.witherBoss"],self,BODY,bones,body_meshes)
	armor_layer = Node3D.new()
	armor_layer.name = "OriginalBlueShield"
	add_child(armor_layer)
	var temporary:Array[MeshInstance3D] = []
	_build(armor_data["geometry.witherBoss.armor.v1.8"],armor_layer,ARMOR_BLUE,armor_bones,temporary)
	armor_blue_material = _armor_material(ARMOR_BLUE,0.65)
	armor_white_material = _armor_material(ARMOR_WHITE,0.45)
	for mesh:MeshInstance3D in temporary:
		mesh.material_override = armor_blue_material
		var white:=MeshInstance3D.new()
		white.mesh = mesh.mesh
		white.material_override = armor_white_material
		mesh.get_parent().add_child(white)
	armor_layer.visible = false

func _load_json(path:String) -> Dictionary:
	var file:FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null:
		push_error("Missing official Bedrock animation/model: "+path)
		return {}
	var data:Variant = JSON.parse_string(file.get_as_text())
	return data as Dictionary if data is Dictionary else {}

func _vec(source:Array) -> Vector3:
	return Vector3(float(source[0]),float(source[1]),float(source[2]))

func _material(texture:Texture2D) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Alpha-scissor writes depth: otherwise transparent box faces drawn later
	# overwrite the visible front faces (including the Wither's white eyes).
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.1
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	return material

func _armor_material(texture:Texture2D,opacity:float) -> StandardMaterial3D:
	var material:StandardMaterial3D = _material(texture)
	# Energy overlay, not an opaque second skin. Keep the face/body legible.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color.a = opacity
	material.texture_repeat = true
	return material

func _build(geometry:Dictionary,parent:Node3D,texture:Texture2D,output:Dictionary,meshes:Array[MeshInstance3D]) -> void:
	var pivots:Dictionary = {}
	var material:StandardMaterial3D = _material(texture)
	for item:Variant in geometry["bones"]:
		var bone:Dictionary = item
		var name_string:String = String(bone["name"]).to_lower()
		var parent_name:String = String(bone.get("parent","")).to_lower()
		var pivot:Vector3 = _vec(bone.get("pivot",[0,0,0]))
		var parent_pivot:Vector3 = pivots.get(parent_name,Vector3.ZERO)
		var node:=Node3D.new()
		node.name = name_string
		var container:Node3D = output.get(parent_name,parent)
		container.add_child(node)
		node.position = (pivot-parent_pivot)/16.0
		output[name_string] = node
		pivots[name_string] = pivot
		for raw_cube:Variant in bone.get("cubes",[]):
			var cube:Dictionary = raw_cube
			var instance:=MeshInstance3D.new()
			instance.mesh = _cube_mesh(cube,pivot,Vector2(float(geometry.get("texturewidth",64)),float(geometry.get("textureheight",64))),float(bone.get("inflate",0.0)))
			instance.material_override = material
			node.add_child(instance)
			meshes.append(instance)

func _quad(surface:SurfaceTool, corners:Array, uv_rect:Rect2,atlas:Vector2,brightness:float) -> void:
	var texels:Array[Vector2] = [uv_rect.position+Vector2(0,uv_rect.size.y),uv_rect.position+uv_rect.size,uv_rect.position+Vector2(uv_rect.size.x,0),uv_rect.position]
	for index:int in [0,1,2,0,2,3]:
		surface.set_color(Color(brightness,brightness,brightness,1.0))
		surface.set_uv(texels[index]/atlas)
		surface.add_vertex(corners[index])

func _cube_mesh(cube:Dictionary,pivot:Vector3,atlas:Vector2,inflate:float) -> ArrayMesh:
	var origin:Vector3 = _vec(cube["origin"])
	var dims:Vector3 = _vec(cube["size"])
	var uv:Array = cube["uv"]
	var u:float = float(uv[0])
	var v:float = float(uv[1])
	var w:float = dims.x
	var h:float = dims.y
	var d:float = dims.z
	var x0:float = (origin.x-pivot.x-inflate)/16.0
	var x1:float = (origin.x+dims.x-pivot.x+inflate)/16.0
	var y0:float = (origin.y-pivot.y-inflate)/16.0
	var y1:float = (origin.y+dims.y-pivot.y+inflate)/16.0
	var z0:float = (origin.z-pivot.z-inflate)/16.0
	var z1:float = (origin.z+dims.z-pivot.z+inflate)/16.0
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bedrock box-UV layout: left / front / right / back, top / bottom.
	_quad(surface,[Vector3(x0,y0,z0),Vector3(x1,y0,z0),Vector3(x1,y1,z0),Vector3(x0,y1,z0)],Rect2(u+d,v+d,w,h),atlas,0.92)
	_quad(surface,[Vector3(x1,y0,z1),Vector3(x0,y0,z1),Vector3(x0,y1,z1),Vector3(x1,y1,z1)],Rect2(u+2*d+w,v+d,w,h),atlas,0.62)
	_quad(surface,[Vector3(x0,y0,z1),Vector3(x0,y0,z0),Vector3(x0,y1,z0),Vector3(x0,y1,z1)],Rect2(u,v+d,d,h),atlas,0.72)
	_quad(surface,[Vector3(x1,y0,z0),Vector3(x1,y0,z1),Vector3(x1,y1,z1),Vector3(x1,y1,z0)],Rect2(u+d+w,v+d,d,h),atlas,0.76)
	_quad(surface,[Vector3(x0,y1,z0),Vector3(x1,y1,z0),Vector3(x1,y1,z1),Vector3(x0,y1,z1)],Rect2(u+d,v,w,d),atlas,1.0)
	_quad(surface,[Vector3(x0,y0,z1),Vector3(x1,y0,z1),Vector3(x1,y0,z0),Vector3(x0,y0,z0)],Rect2(u+d+w,v,w,d),atlas,0.55)
	return surface.commit()

func recoil_head(index:int) -> void:
	if index >= 0 and index < 3: _head_recoil[index] = 1.0

func animate(original_life_time:float,heading:Vector2,awake:bool,intro_progress:float,shielded:bool,head_directions:Array = [],frame_delta:float = 1.0) -> void:
	if bones.is_empty(): return
	# The Bedrock client entity provides these continuous torso/neck curves.
	var base_rotation:float = cos(original_life_time*2.0)
	var upper_rotation:float = (0.065+0.05*base_rotation)*180.0
	var tail_rotation:float = (0.2+0.1*base_rotation)*180.0
	# Keep the white-eyed front facing the camera. Movement only leans the
	# torso: pitch for up/down, roll for left/right. No walking yaw or mirror.
	var moving:Vector2 = heading.normalized() if heading.length_squared() > 0.000001 else Vector2.ZERO
	var body_weight:float = clampf(frame_delta*7.0,0.0,1.0)
	_body_pitch = lerpf(_body_pitch,-moving.y*0.20,body_weight)
	_body_roll = lerpf(_body_roll,moving.x*0.26,body_weight)
	# Each head independently tracks the target's SCREEN position: yaw moves
	# its eyes left/right, pitch moves them up/down. In particular, an enemy
	# below the character makes the head look down, not spin to its back.
	for i:int in range(3):
		var aim_direction:Vector2 = head_directions[i].normalized() if i < head_directions.size() and head_directions[i].length_squared() > 0.000001 else Vector2.UP
		var desired_yaw:float = clampf(asin(clampf(aim_direction.x,-1.0,1.0)),-1.1,1.1)
		var desired_pitch:float = -aim_direction.y*0.38
		var weight:float = clampf(frame_delta*(9.0-float(i)*1.4),0.0,1.0)
		_head_yaw[i] = lerpf(_head_yaw[i],desired_yaw,weight)
		_head_pitch[i] = lerpf(_head_pitch[i],desired_pitch,weight)
		_head_recoil[i] = maxf(_head_recoil[i]-frame_delta*4.0,0.0)
	for group:Dictionary in [bones,armor_bones]:
		(group["upperbodypart2"] as Node3D).rotation_degrees.x = upper_rotation
		var tail:Node3D = group["upperbodypart3"]
		# Original animation.wither_boss.move: position [-2,-16.9,-0.5].
		tail.position = Vector3(0.0,-10.0,0.0)/16.0
		tail.rotation_degrees.x = tail_rotation
		for i:int in range(3):
			var head:Node3D = group["head%d" % (i+1)]
			head.rotation = Vector3(_head_pitch[i]+_head_recoil[i]*0.17,_head_yaw[i],0.0)
	var show_invulnerable:bool = not awake
	if show_invulnerable != current_invulnerable:
		current_invulnerable = show_invulnerable
		var material:StandardMaterial3D = _material(INVULNERABLE if show_invulnerable else BODY)
		for mesh:MeshInstance3D in body_meshes: mesh.material_override = material
	armor_layer.visible = awake and shielded
	# Mojang's original armor render controllers. Use actor simulation time,
	# not shader TIME: pause and offline export must retain the same phase.
	var scroll:float = fposmod(original_life_time*0.2,1.0)
	armor_blue_material.uv1_offset = Vector3(scroll,scroll,0.0)
	armor_white_material.uv1_offset = Vector3(fposmod(cos(deg_to_rad(original_life_time*22.92))*3.0,1.0),scroll,0.0)
	# Two full turns over the entire intro. No 80% construction delay.
	rotation = Vector3(_body_pitch,0.0,_body_roll) if awake else Vector3(0.0,TAU*2.0*clampf(intro_progress,0.0,1.0),0.0)
	position.y = sin(original_life_time*3.7)*0.02 if awake else 0.0
	# Official client entity pre_animation: swell_adjustment = swell^4,
	# wobble = 1 + sin(swell * 5730 degrees) * swell * 0.01.
	# Start at the former spin phase's scale, not the removed assembly swell.
	var swell:float = 0.0 if awake else 0.2*clampf(1.0-intro_progress,0.0,1.0)
	var wobble:float = 1.0+sin(deg_to_rad(swell*5730.0))*swell*0.01
	var adjustment:float = pow(swell,4.0)
	var scale_xz:float = (1.0+adjustment*0.4)*wobble*2.0
	var scale_y:float = (1.0+adjustment*0.1)/wobble*2.0
	scale = Vector3(scale_xz,scale_y,scale_xz)
