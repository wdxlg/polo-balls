extends SceneTree
## Same-material GPU probes catch reversed procedural-face winding, not texture differences.
const ARENA = preload("res://scripts/effects/summit_arena_3d.gd")
const WALL = preload("res://scripts/effects/我的世界/地图立体墙.gd")
var checks:int = 0
var failures:int = 0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func frame() -> void:
	for i:int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
func run() -> void:
	create_timer(40.0).timeout.connect(func():quit(2))
	var view:=SubViewport.new()
	view.size = Vector2i(600,300)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env_node:=WorldEnvironment.new()
	env_node.environment = Environment.new()
	env_node.environment.background_mode = Environment.BG_COLOR
	env_node.environment.background_color = Color(0.05,0.05,0.05)
	env_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_node.environment.ambient_light_color = Color.WHITE
	env_node.environment.ambient_light_energy = 0.15
	view.add_child(env_node)
	var camera:=Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.position = Vector3(0,12,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	view.add_child(camera)
	camera.make_current()
	var sun:=DirectionalLight3D.new()
	sun.light_color = Color.WHITE
	sun.light_energy = 1.0
	view.add_child(sun)
	sun.position = Vector3(6,10,-6)
	sun.look_at(Vector3.ZERO)
	var source:Node3D = ARENA.new()
	view.add_child(source)
	var white:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	source._surface("Probe",ImageTexture.create_from_image(white),Color(0.5,0.5,0.5))
	var material:StandardMaterial3D = source._materials["Probe"]
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	source._plane("Probe",Rect2(-1.5,-1.5,3,3),0.0)
	var generated:ArrayMesh = source._tools["Probe"].commit()
	generated.surface_set_material(0,material)
	var procedural:=MeshInstance3D.new()
	procedural.mesh = generated
	view.add_child(procedural)
	var reference:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size = Vector2(3,3)
	reference.mesh = plane
	reference.material_override = material
	reference.position.x = -4.0
	view.add_child(reference)
	# Diagnostic alternative: swap each generated triangle without altering normals/UVs.
	var arrays:Array = generated.surface_get_arrays(0)
	var vertices:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv:PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var flipped:=SurfaceTool.new()
	flipped.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i:int in range(0,vertices.size(),3):
		for j:int in [i,i+2,i+1]:
			flipped.set_normal(normals[j])
			flipped.set_uv(uv[j])
			flipped.add_vertex(vertices[j])
	var alternative:=MeshInstance3D.new()
	alternative.mesh = flipped.commit()
	alternative.material_override = material
	alternative.position.x = 4.0
	view.add_child(alternative)
	alternative.hide()
	var wall_source:Node2D = WALL.new()
	root.add_child(wall_source)
	var wall_tool:=SurfaceTool.new()
	wall_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_points:Array[Vector3] = [Vector3(-1.5,0,-1.5),Vector3(-1.5,0,1.5),Vector3(1.5,0,1.5),Vector3(1.5,0,-1.5)]
	var wall_uv:Array[Vector2] = [Vector2.ZERO,Vector2.DOWN,Vector2.ONE,Vector2.RIGHT]
	wall_source._face(wall_tool,wall_points,wall_uv)
	var wall_probe:=MeshInstance3D.new()
	wall_probe.mesh = wall_tool.commit()
	wall_probe.material_override = material
	wall_probe.position.x = 4.0
	view.add_child(wall_probe)
	await frame()
	var image:Image = view.get_texture().get_image()
	check(not image.is_empty(),"real GPU probe rendered")
	var normal_color:Color = image.get_pixel(100,150)
	var map_color:Color = image.get_pixel(300,150)
	var alternate_color:Color = image.get_pixel(500,150)
	var error:float = maxf(absf(normal_color.r-map_color.r),maxf(absf(normal_color.g-map_color.g),absf(normal_color.b-map_color.b)))
	print("LIGHTING_PROBE reference=",normal_color," arena=",map_color," wall=",alternate_color," arena_error=",error)
	check(error<0.005,"procedural arena face matches standard 3D face under the same light")
	var wall_error:float = maxf(absf(normal_color.r-alternate_color.r),maxf(absf(normal_color.g-alternate_color.g),absf(normal_color.b-alternate_color.b)))
	check(wall_error<0.005,"map wall face matches standard and authored scenery under the same light")
	var out:String = OS.get_environment("SUMMIT_EVIDENCE_DIR")
	if not out.is_empty(): image.save_png(out.path_join("lighting_probe.png"))
	view.queue_free()
	wall_source.queue_free()
	await process_frame
	print("SUMMIT_LIGHTING_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
