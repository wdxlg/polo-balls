extends Node3D
## Continuous, non-playable 3D rockland. Original PNG, no baked backdrop image.
const ROCK:Texture2D = preload("res://assets/maps/summit/shandian_stone.png")
const GRID:int = 96
var plateau_height:float
var floor_height:float
var coverage_rect:Rect2
var terrain:MeshInstance3D
var far_floor:MeshInstance3D
var build_count:int = 0
var _camera:Camera3D
var _cell:float
var _step:float
var _bounds:Rect2
var _islands:Array[Rect2]
var _supports:Array[Rect2]
var _material:StandardMaterial3D

func _height(point:Vector2) -> float:
	var distance:float = INF
	for support:Rect2 in _supports:
		var offset:Vector2 = (point-support.get_center()).abs()-support.size*0.5
		distance=minf(distance,maxf(maxf(offset.x,offset.y)-_step*0.65,0.0))
	if distance<0.01:
		# Distinguish gaps between islands from the playable stone floors.
		if _bounds.has_point(point):
			var supported:bool = false
			for island:Rect2 in _islands:
				if island.grow(_cell*0.35).has_point(point): supported=true
			if not supported: return -_cell*1.8
		return plateau_height
	var p:Vector2 = (point-_bounds.get_center())/_cell
	var ridges:float = sin(p.x*0.31)+cos(p.y*0.23)+sin((p.x+p.y)*0.17)*0.6
	var height:float = plateau_height-distance*2.8+ridges*_cell*minf(distance/(_cell*5.0),1.0)*0.85
	return clampf(floorf(height/(_cell*0.5))*_cell*0.5,floor_height+_cell*0.12,plateau_height)

func _face(tool:SurfaceTool,points:Array[Vector3]) -> void:
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	for i:int in [0,2,1,0,3,2]:
		tool.set_normal(normal)
		tool.set_uv(Vector2(points[i].x,points[i].z)/_step)
		tool.add_vertex(points[i])

func build(islands:Array[Rect2],supports:Array[Rect2],cell:float,camera:Camera3D) -> void:
	_camera=camera
	_cell=cell
	_islands=islands.duplicate()
	_supports=islands.duplicate()
	_supports.append_array(supports)
	_bounds=islands[0]
	for rect:Rect2 in islands: _bounds=_bounds.merge(rect)
	_step=maxf(_cell*0.5,maxf(_bounds.size.x,_bounds.size.y)/28.0)
	plateau_height=-_cell*0.3
	floor_height=-maxf(maxf(_bounds.size.x,_bounds.size.y)*3.0,_cell*32.0)
	_material=StandardMaterial3D.new()
	_material.albedo_texture=ROCK
	_material.albedo_color=Color(0.63,0.68,0.74)
	_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material.texture_repeat=true
	_material.uv1_triplanar=true
	_material.uv1_world_triplanar=true
	_material.uv1_scale=Vector3.ONE/_step
	_material.roughness=1.0
	var heights:PackedFloat32Array=[]
	var origin:Vector2=_bounds.get_center()-Vector2.ONE*float(GRID)*_step*0.5
	for z:int in range(GRID):
		for x:int in range(GRID): heights.append(_height(origin+(Vector2(x,z)+Vector2.ONE*0.5)*_step))
	var tool:=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z:int in range(GRID):
		for x:int in range(GRID):
			var p:Vector2=origin+Vector2(x,z)*_step
			var h:float=heights[z*GRID+x]
			var a:float=p.x+_step
			var b:float=p.y+_step
			_face(tool,[Vector3(p.x,h,b),Vector3(a,h,b),Vector3(a,h,p.y),Vector3(p.x,h,p.y)])
			for direction:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var nx:int=x+direction.x
				var nz:int=z+direction.y
				var low:float=heights[nz*GRID+nx] if nx>=0 and nx<GRID and nz>=0 and nz<GRID else floor_height
				if low>=h: continue
				if direction==Vector2i.LEFT: _face(tool,[Vector3(p.x,low,p.y),Vector3(p.x,low,b),Vector3(p.x,h,b),Vector3(p.x,h,p.y)])
				elif direction==Vector2i.RIGHT: _face(tool,[Vector3(a,low,b),Vector3(a,low,p.y),Vector3(a,h,p.y),Vector3(a,h,b)])
				elif direction==Vector2i.UP: _face(tool,[Vector3(a,low,p.y),Vector3(p.x,low,p.y),Vector3(p.x,h,p.y),Vector3(a,h,p.y)])
				else: _face(tool,[Vector3(p.x,low,b),Vector3(a,low,b),Vector3(a,h,b),Vector3(p.x,h,b)])
	terrain=MeshInstance3D.new()
	terrain.name="ContinuousVoxelRockland"
	terrain.mesh=tool.commit()
	terrain.material_override=_material
	add_child(terrain)
	far_floor=MeshInstance3D.new()
	far_floor.name="FrustumCoveringDeepRock"
	far_floor.mesh=PlaneMesh.new()
	far_floor.material_override=_material
	far_floor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_floor)
	build_count+=1
	RenderingServer.frame_pre_draw.connect(sync_coverage)
	sync_coverage()

func sync_coverage() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(far_floor): return
	var size:Vector2=Vector2(_camera.get_viewport().get_visible_rect().size)
	var first:bool=true
	var needed:Rect2
	for uv:Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var ray:Vector3=_camera.project_ray_normal(uv*size)
		var origin:Vector3=_camera.project_ray_origin(uv*size)
		if ray.y>=-0.0001: continue # diagnostic oblique views may contain actual sky
		var hit:Vector3=origin+ray*((floor_height-origin.y)/ray.y)
		var point:=Vector2(hit.x,hit.z)
		if first: needed=Rect2(point,Vector2.ZERO);first=false
		else: needed=needed.expand(point)
	if first: return
	needed=needed.grow(_cell*8.0)
	if coverage_rect.has_area() and coverage_rect.encloses(needed): return
	coverage_rect=needed.grow(maxf(needed.size.x,needed.size.y)*0.3)
	(far_floor.mesh as PlaneMesh).size=coverage_rect.size
	far_floor.position=Vector3(coverage_rect.get_center().x,floor_height,coverage_rect.get_center().y)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(sync_coverage):
		RenderingServer.frame_pre_draw.disconnect(sync_coverage)
