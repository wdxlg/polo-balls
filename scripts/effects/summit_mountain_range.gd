extends Node3D
## Surrounding ridges use the SAME authored mountain, not generic procedural cones.
## PackedScene instances share mesh/material resources and retain normal mesh culling.
const MOUNTAIN:PackedScene = preload("res://assets/maps/summit/shandian_natural.glb")
const ROCK:Texture2D = preload("res://assets/maps/summit/shandian_stone.png")
var terrain:MeshInstance3D
var far_floor:MeshInstance3D
var coverage_rect:Rect2
var build_count:int = 0
var peak_count:int = 0
var floor_height:float
var max_peak_height:float = -INF
var observed_max_height:float = -INF
var observed_min_height:float = INF
var authored_instances:Array[Node3D] = []
var _camera:Camera3D
var _sun:DirectionalLight3D
var _cell:float

func _random(x:int,z:int,seed:float) -> float:
	return fposmod(sin(float(x)*127.1+float(z)*311.7+seed)*43758.5453,1.0)

func build(_islands:Array[Rect2],cell:float,camera:Camera3D,heroes:Array[Node3D],source_bounds:AABB) -> void:
	_cell=cell
	_camera=camera
	_sun=camera.get_parent().get_node_or_null("WallSun3D") as DirectionalLight3D
	var main:Node3D=heroes[0]
	var scale_factor:float=main.scale.x
	# Every mountain has the same valley floor. Overlapping lower slopes connect
	# their detailed rock strata and forests, while the original stays highest.
	floor_height=main.position.y+source_bounds.position.y*scale_factor
	observed_min_height=floor_height
	var spacing:float=scale_factor*49.0
	for z:int in range(-6,7):
		for x:int in range(-6,7):
			if x==0 and z==0: continue
			var p:Vector2=Vector2(main.position.x,main.position.z)+Vector2(float(x)+(_random(x,z,7)-0.5)*0.20,float(z)+(_random(x,z,19)-0.5)*0.20)*spacing
			var occupied:bool=false
			for hero:Node3D in heroes:
				if p.distance_to(Vector2(hero.position.x,hero.position.z))<spacing*0.7: occupied=true
			if occupied: continue
			var ridge:Node3D=MOUNTAIN.instantiate() as Node3D
			ridge.name="AuthoredRidge_%s_%s" % [x,z]
			var s:float=scale_factor*(0.56+_random(x,z,41)*0.20)
			ridge.scale=Vector3.ONE*s
			ridge.rotation.y=float(posmod(x*7+z*11,4))*PI*0.5
			ridge.position=Vector3(p.x,floor_height-source_bounds.position.y*s,p.y)
			for detail:MeshInstance3D in ridge.find_children("*","MeshInstance3D",true,false):
				if String(detail.name).to_lower().contains("landmark"): detail.hide()
			add_child(ridge)
			authored_instances.append(ridge)
			observed_max_height=maxf(observed_max_height,floor_height+source_bounds.size.y*s)
			if terrain==null: terrain=ridge.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	peak_count=authored_instances.size()
	max_peak_height=observed_max_height
	var material:=StandardMaterial3D.new()
	material.albedo_texture=ROCK
	material.albedo_color=Color(0.68,0.74,0.82)
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat=true
	material.uv1_triplanar=true
	material.uv1_world_triplanar=true
	material.uv1_scale=Vector3.ONE/scale_factor
	material.roughness=0.95
	far_floor=MeshInstance3D.new()
	far_floor.name="ConnectedValleyFloor"
	far_floor.mesh=PlaneMesh.new()
	far_floor.material_override=material
	far_floor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_floor)
	build_count+=1
	RenderingServer.frame_pre_draw.connect(sync_coverage)
	sync_coverage()

func sync_coverage() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(far_floor): return
	if is_instance_valid(_sun): _sun.directional_shadow_max_distance=maxf(_sun.directional_shadow_max_distance,_camera.position.y-floor_height+_cell*8.0)
	var size:Vector2=_camera.get_viewport().get_visible_rect().size
	var first:bool=true
	var needed:Rect2
	for uv:Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var ray:Vector3=_camera.project_ray_normal(uv*size)
		var origin:Vector3=_camera.project_ray_origin(uv*size)
		if ray.y>=-0.0001: continue
		var hit:Vector3=origin+ray*((floor_height-origin.y)/ray.y)
		var point:=Vector2(hit.x,hit.z)
		if first: needed=Rect2(point,Vector2.ZERO);first=false
		else: needed=needed.expand(point)
	if first:return
	needed=needed.grow(_cell*8.0)
	if coverage_rect.has_area() and coverage_rect.encloses(needed): return
	coverage_rect=needed.grow(maxf(needed.size.x,needed.size.y)*0.3)
	(far_floor.mesh as PlaneMesh).size=coverage_rect.size
	far_floor.position=Vector3(coverage_rect.get_center().x,floor_height,coverage_rect.get_center().y)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(sync_coverage): RenderingServer.frame_pre_draw.disconnect(sync_coverage)
