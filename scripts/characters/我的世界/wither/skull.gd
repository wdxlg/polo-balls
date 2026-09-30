extends Node2D
## 3D Bedrock Wither Skull projectile with Mojang geometry & UVs.
const FOLDER = "res://Images/characters/我的世界/wither/bedrock/"
const BODY = preload("res://Images/characters/我的世界/wither/bedrock/wither.png")
const SKULL_DIAMETER:float = 12.0
const HIT_RADIUS:float = 6.0
const DIRECT_DAMAGE:float = 30.0
const SPLASH_DAMAGE:float = 20.0
const BOSS_DIRECT_DAMAGE:float = 50.0
const BOSS_SPLASH_DAMAGE:float = 25.0
const TRAIL_VISUALS = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
var _trail_distance:float = 0.0

var source_ref:WeakRef
var heading:Vector2 = Vector2.RIGHT
var speed:float = 260.0
var life:float = 4.0
var exploded:bool = false

var _viewport:SubViewport
var _camera:Camera3D
var _head_node:Node3D
var _sprite:Sprite2D

func configure(source:ball,direction:Vector2) -> void:
	source_ref = weakref(source)
	heading = direction.normalized()
	rotation = 0.0
	add_to_group("AI_Hazard")

func _ready() -> void:
	_create_3d_head()

func _create_3d_head() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "WitherSkull3D"
	_viewport.size = Vector2i(64,64)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.25
	_camera.position = Vector3(0,0,-2.5)
	_viewport.add_child(_camera)
	_camera.look_at(Vector3.ZERO,Vector3.UP)
	_camera.current = true

	_head_node = Node3D.new()
	_viewport.add_child(_head_node)

	var mesh_inst:=MeshInstance3D.new()
	mesh_inst.mesh = _create_skull_mesh()
	mesh_inst.material_override = _create_material(BODY)
	_head_node.add_child(mesh_inst)

	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * (SKULL_DIAMETER / 64.0) * 2.0
	add_child(_sprite)
	_update_head_rotation()

func _create_material(tex:Texture2D) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	return mat

func _quad(surface:SurfaceTool, corners:Array, uv_rect:Rect2, atlas:Vector2, brightness:float) -> void:
	var texels:Array[Vector2] = [
		uv_rect.position+Vector2(0,uv_rect.size.y),
		uv_rect.position+uv_rect.size,
		uv_rect.position+Vector2(uv_rect.size.x,0),
		uv_rect.position
	]
	for index:int in [0,1,2,0,2,3]:
		surface.set_color(Color(brightness,brightness,brightness,1.0))
		surface.set_uv(texels[index]/atlas)
		surface.add_vertex(corners[index])

func _create_skull_mesh() -> ArrayMesh:
	# Cube [-4,-4,-4] to [4,4,4] centered at (0,0,0) in 1/16 blocks -> [-0.25, 0.25]
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0:float = -0.25; var x1:float = 0.25
	var y0:float = -0.25; var y1:float = 0.25
	var z0:float = -0.25; var z1:float = 0.25
	var u:float = 0.0; var v:float = 35.0; var w:float = 8.0; var h:float = 8.0; var d:float = 8.0
	var atlas:=Vector2(64.0,64.0)

	# Bedrock UV layout:
	# Left
	_quad(surface,[Vector3(x0,y0,z0),Vector3(x1,y0,z0),Vector3(x1,y1,z0),Vector3(x0,y1,z0)],Rect2(u+d,v+d,w,h),atlas,0.92)
	# Front
	_quad(surface,[Vector3(x1,y0,z1),Vector3(x0,y0,z1),Vector3(x0,y1,z1),Vector3(x1,y1,z1)],Rect2(u+2*d+w,v+d,w,h),atlas,0.62)
	# Right
	_quad(surface,[Vector3(x0,y0,z1),Vector3(x0,y0,z0),Vector3(x0,y1,z0),Vector3(x0,y1,z1)],Rect2(u,v+d,d,h),atlas,0.72)
	# Back
	_quad(surface,[Vector3(x1,y0,z0),Vector3(x1,y0,z1),Vector3(x1,y1,z1),Vector3(x1,y1,z0)],Rect2(u+d+w,v+d,d,h),atlas,0.76)
	# Top
	_quad(surface,[Vector3(x0,y1,z0),Vector3(x1,y1,z0),Vector3(x1,y1,z1),Vector3(x0,y1,z1)],Rect2(u+d,v,w,d),atlas,1.0)
	# Bottom
	_quad(surface,[Vector3(x0,y0,z1),Vector3(x1,y0,z1),Vector3(x1,y0,z0),Vector3(x0,y0,z0)],Rect2(u+d+w,v,w,d),atlas,0.55)

	return surface.commit()

func _update_head_rotation() -> void:
	if _head_node == null: return
	var dir:Vector2 = heading.normalized()
	# Screen direction -> 3D pitch and yaw
	var yaw:float = clampf(asin(clampf(dir.x,-1.0,1.0)),-1.3,1.3)
	var pitch:float = -dir.y * 0.45
	_head_node.rotation = Vector3(pitch, yaw, 0.0)

func _source() -> ball:
	var node:Variant = source_ref.get_ref() if source_ref != null else null
	return node as ball if is_instance_valid(node) and node is ball and node.health > 0 else null

func _physics_process(delta:float) -> void:
	if exploded or delta <= 0.0: return
	var source:ball = _source()
	if source == null: queue_free(); return
	if not source.is_multiplayer_authority() or not source.is_combat_runtime_active(): return
	life -= delta
	if life <= 0: queue_free(); return
	var start:Vector2 = global_position
	var end:Vector2 = start+heading*speed*delta
	var excluded:Array[RID] = [source.get_rid()]
	for n:int in range(12):
		var query:=PhysicsRayQueryParameters2D.create(start,end,3,excluded)
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var collider:Variant = hit.get("collider")
		if collider is ball and not source.call("mc_enemy",collider):
			excluded.append((collider as ball).get_rid())
			continue
		var direct:ball = collider as ball if collider is ball else null
		var center:Vector2 = Vector2(hit.position)-heading*3.0
		_emit_trail(source,start,Vector2(hit.position))
		source.call("_blast",center,64.0,source.call("skull_splash_damage"),direct,true)
		source.call("_show_explosion",center,64.0)
		source.call("_emit_sound","explode",center)
		if source.multiplayer.has_multiplayer_peer(): source.call("_sync_skull_explosion",center)
		exploded = true
		remove_from_group("AI_Hazard")
		queue_free()
		return
	if not exploded:
		_emit_trail(source,start,end)
		global_position = end
	_update_head_rotation()

func _emit_trail(source:ball,from:Vector2,to:Vector2) -> void:
	if from.is_equal_approx(to): return
	var sample:Dictionary = TRAIL_VISUALS.sample_smoke_trail(from,to,6.0,SKULL_DIAMETER*0.5,_trail_distance)
	_trail_distance = float(sample.distance)
	var points:PackedVector2Array = sample.points
	if points.is_empty(): return
	source.call("_show_skull_trail",points,heading)
	if source.multiplayer.has_multiplayer_peer(): source.rpc("_show_skull_trail",points,heading)

func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var source:ball = _source()
	if exploded or source == null: return {}
	return {"shape":"circle","position":global_position,"velocity":heading*speed,"radius":HIT_RADIUS,"damage":source.call("own_attack_damage",source.call("skull_direct_damage")),"source":source,"danger_duration":0.1,"kind":"wither_skull"}
