extends Node3D
## Actual six-sided door geometry. Native MC model: 16x32, thickness 3/16.
## Each carriage travels offscreen while its door rotates around a fixed local hinge.
## Width/height adapt only at layout time; no animated mesh rebuilds.
const TOP:Texture2D = preload("res://assets/ui/dark_oak_transition/dark_oak_door_top.png")
const BOTTOM:Texture2D = preload("res://assets/ui/dark_oak_transition/dark_oak_door_bottom.png")
const THICKNESS_RATIO:float = 3.0/16.0
var carriages:Array[Node3D] = []
var hinges:Array[Node3D] = []
var outward_travel:float = 0.0
var leaves:Array[MeshInstance3D] = []
var materials:Array[StandardMaterial3D] = []
var camera:Camera3D
var half_width:float = 0.0
var thickness:float = 0.0
var build_count:int = 0
var _aspect:float = -1.0

func _ready() -> void:
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0,0,0,0)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=0.65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-20,-28,0)
	sun.light_energy=0.85
	sun.shadow_enabled=false
	add_child(sun)
	camera=Camera3D.new()
	camera.name="DoorPerspectiveCamera"
	camera.near=0.01
	camera.far=100.0
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	add_child(camera)
	camera.make_current()
	for texture:Texture2D in [BOTTOM,TOP]:
		var material:=StandardMaterial3D.new()
		material.albedo_texture=texture
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness=1.0
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		materials.append(material)
	for side:int in range(2):
		var carriage:=Node3D.new()
		carriage.name="LeftCarriage" if side==0 else "RightCarriage"
		add_child(carriage);carriages.append(carriage)
		var hinge:=Node3D.new()
		hinge.name="LeftHinge" if side==0 else "RightHinge"
		carriage.add_child(hinge);hinges.append(hinge)
		for half:int in range(2):
			var leaf:=MeshInstance3D.new()
			leaf.name="LowerDoor" if half==0 else "UpperDoor"
			hinge.add_child(leaf);leaves.append(leaf)

func _quad(tool:SurfaceTool,p:Array[Vector3],uv:Rect2,mirror:bool=false) -> void:
	var normal:Vector3=(p[1]-p[0]).cross(p[2]-p[0]).normalized()
	var coords:Array[Vector2]=[Vector2(uv.position.x,uv.end.y),uv.end,Vector2(uv.end.x,uv.position.y),uv.position]
	if mirror:
		for i:int in range(4):coords[i].x=uv.position.x+uv.end.x-coords[i].x
	for i:int in [0,2,1,0,3,2]:
		tool.set_normal(normal);tool.set_uv(coords[i]);tool.add_vertex(p[i])

func _mesh(side:int,half:int) -> ArrayMesh:
	var width:float=half_width+0.002
	var a:float=0.0 if side==0 else -width
	var b:float=width if side==0 else 0.0
	var y:float=-1.004 if half==0 else 0.0
	var t:float=0.0 if half==0 else 1.004
	var z:float=-thickness
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Full front/back and the native three-pixel edge strips, not transparent planes.
	_quad(tool,[Vector3(a,y,0),Vector3(b,y,0),Vector3(b,t,0),Vector3(a,t,0)],Rect2(0,0,1,1),side==1)
	_quad(tool,[Vector3(b,y,z),Vector3(a,y,z),Vector3(a,t,z),Vector3(b,t,z)],Rect2(0,0,1,1),side==0)
	_quad(tool,[Vector3(a,y,z),Vector3(a,y,0),Vector3(a,t,0),Vector3(a,t,z)],Rect2(0,0,THICKNESS_RATIO,1))
	_quad(tool,[Vector3(b,y,0),Vector3(b,y,z),Vector3(b,t,z),Vector3(b,t,0)],Rect2(0,0,THICKNESS_RATIO,1))
	if half==1: _quad(tool,[Vector3(a,t,0),Vector3(b,t,0),Vector3(b,t,z),Vector3(a,t,z)],Rect2(0,0,1,THICKNESS_RATIO))
	else: _quad(tool,[Vector3(a,y,z),Vector3(b,y,z),Vector3(b,y,0),Vector3(a,y,0)],Rect2(0,1-THICKNESS_RATIO,1,THICKNESS_RATIO))
	var mesh:ArrayMesh=tool.commit()
	mesh.surface_set_material(0,materials[half])
	return mesh

func configure(size:Vector2) -> void:
	var aspect:float=size.x/maxf(size.y,1.0)
	if is_equal_approx(_aspect,aspect):return
	_aspect=aspect
	half_width=aspect*1.003
	thickness=half_width*THICKNESS_RATIO
	# Clear the inward-facing thickness at 90 degrees plus a visible offscreen margin.
	outward_travel=thickness+half_width*0.25+0.01
	# Keep open leaves in front of the near plane even on very wide windows.
	var distance:float=maxf(1.0/tan(deg_to_rad(18.0)),half_width*1.8)
	camera.position=Vector3(0,0,distance)
	camera.fov=rad_to_deg(2.0*atan(1.0/distance))
	hinges[0].position=Vector3(-half_width,0,0)
	hinges[1].position=Vector3(half_width,0,0)
	for side:int in range(2):
		for half:int in range(2): leaves[side*2+half].mesh=_mesh(side,half)
	build_count+=1

func set_progress(value:float) -> void:
	var remaining:float=1.0-clampf(value,0.0,1.0)
	var angle:float=remaining*PI*0.5
	# Use the same eased progress for travel and rotation, reversed when opening.
	# At zero, all faces (including hinges/thick edges) are outside the frustum.
	carriages[0].position.x=-outward_travel*remaining
	carriages[1].position.x=outward_travel*remaining
	hinges[0].rotation.y=-angle
	hinges[1].rotation.y=angle
