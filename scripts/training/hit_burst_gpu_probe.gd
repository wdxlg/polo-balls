extends "res://scripts/effects/hit_burst_effect.gd"
const STREAK_SHADER = preload("res://scripts/training/hit_streaks_probe.gdshader")
static var unit_mesh:ArrayMesh
var renderer:MultiMeshInstance2D
var table:ImageTexture
var descriptor_hash:int = 0
func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 98
	global_position = _origin
	global_rotation = 0.0
	global_scale = Vector2.ONE
	if _streaks.is_empty():
		queue_free()
		return
	if unit_mesh == null:
		unit_mesh = make_unit_mesh()
	renderer = MultiMeshInstance2D.new()
	renderer.name = "HitBurstStreaks"
	renderer.multimesh = MultiMesh.new()
	renderer.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	renderer.multimesh.use_custom_data = true
	renderer.multimesh.mesh = unit_mesh
	var shader_material:ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = STREAK_SHADER
	renderer.material = shader_material
	add_child(renderer)
	_update_descriptors()
func _update_descriptors() -> void:
	var data:Image = Image.create(5,maxi(_streaks.size(),1),false,Image.FORMAT_RGBAF)
	var bounds:Rect2
	var has_bounds:bool = false
	for i:int in range(_streaks.size()):
		var item:Dictionary = _streaks[i]
		var direction:Vector2 = item.get("direction",Vector2.RIGHT)
		if direction.length_squared() <= 0.000001:
			direction = Vector2.RIGHT
		direction = direction.normalized()
		var offset:Vector2 = item.get("spawn_offset",Vector2.ZERO)
		var distance:float = maxf(float(item.get("distance",100.0)),1.0)
		var length:float = maxf(float(item.get("length",28.0)),1.0)
		var grow_end:float = clampf(float(item.get("grow_end",0.30)),0.08,0.55)
		var delay:float = maxf(float(item.get("delay",0.0)),0.0)
		var duration:float = maxf(float(item.get("duration",0.28)),0.05)
		var fade_in:float = clampf(float(item.get("fade_in_end",0.14)),0.02,0.45)
		var fade_out:float = clampf(float(item.get("fade_out_start",0.50)),fade_in,0.92)
		var width:float = maxf(float(item.get("width",0.65)),0.22)
		data.set_pixel(0,i,Color(offset.x,offset.y,direction.x,direction.y))
		data.set_pixel(1,i,Color(distance,length,grow_end,delay))
		data.set_pixel(2,i,Color(duration,fade_in,fade_out,width))
		data.set_pixel(3,i,item.get("color",Color.WHITE))
		data.set_pixel(4,i,Color(1.0 if bool(item.get("anchored_origin_motion",false)) else 0.0,0,0,0))
		_end_time = maxf(_end_time,float(item.get("delay",0.0))+duration)
		var end:Vector2 = offset + direction * maxf(distance,length)
		var rect:Rect2 = Rect2(offset,Vector2.ZERO).expand(end).grow(width * 0.5 + 1.0)
		bounds = bounds.merge(rect) if has_bounds else rect
		has_bounds = true
	table = ImageTexture.create_from_image(data)
	(renderer.material as ShaderMaterial).set_shader_parameter("streak_data",table)
	renderer.multimesh.instance_count = _streaks.size()
	renderer.multimesh.custom_aabb = AABB(Vector3(bounds.position.x,bounds.position.y,-1),Vector3(bounds.size.x,bounds.size.y,2))
	for i:int in range(_streaks.size()):
		renderer.multimesh.set_instance_transform_2d(i,Transform2D.IDENTITY)
		renderer.multimesh.set_instance_custom_data(i,Color(float(i),0,0,0))
	descriptor_hash = _streaks.hash()
func _process(delta:float) -> void:
	if _use_real_time:
		_elapsed = maxf(float(Time.get_ticks_usec()-_start_ticks_usec)/1000000.0,0.0)
	else:
		_elapsed += delta
	if renderer != null:
		if descriptor_hash != _streaks.hash():
			_update_descriptors()
		renderer.set_instance_shader_parameter("elapsed",_elapsed)
	if _elapsed >= _end_time + 0.02:
		queue_free()
static func make_unit_mesh() -> ArrayMesh:
	var vertices:PackedVector3Array = PackedVector3Array()
	var uvs:PackedVector2Array = PackedVector2Array()
	var indices:PackedInt32Array = PackedInt32Array()
	# Same two round caps and quad as a two-point Line2D, round_precision=8.
	for cap:int in range(2):
		var start:int = vertices.size()
		vertices.append(Vector3.ZERO)
		uvs.append(Vector2(float(cap),0))
		for i:int in range(9):
			var angle:float = -PI*0.5 + (PI if cap==1 else -PI)*float(i)/8.0
			vertices.append(Vector3(cos(angle)*0.5,sin(angle)*0.5,0))
			uvs.append(Vector2(float(cap),0))
		for i:int in range(8):
			indices.append_array(PackedInt32Array([start,start+i+1,start+i+2]))
	var first:int = vertices.size()
	vertices.append_array(PackedVector3Array([Vector3(0,-0.5,0),Vector3(0,0.5,0),Vector3(0,-0.5,0),Vector3(0,0.5,0)]))
	uvs.append_array(PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2(1,0),Vector2(1,0)]))
	indices.append_array(PackedInt32Array([first,first+3,first+1,first,first+2,first+3]))
	var arrays:Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh:ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
