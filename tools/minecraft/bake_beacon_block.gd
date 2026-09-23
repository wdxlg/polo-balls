extends SceneTree
## Rebuild the icon from the unmodified vanilla Java block model and face UVs.
const FOLDER:String = "res://Images/characters/我的世界/wither/beacon_block/"
func _initialize() -> void: call_deferred("bake")
func bake() -> void:
	var view:=SubViewport.new()
	view.size=Vector2i(256,256)
	view.transparent_bg=true
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.85
	camera.position=Vector3(0.5,0.5,0.5)+Vector3(2,1.6,3)
	view.add_child(camera)
	camera.look_at(Vector3(0.5,0.5,0.5))
	camera.current=true
	var model:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"beacon.json"))
	for element:Dictionary in model.elements:
		var a:Vector3=Vector3(element.from[0],element.from[1],element.from[2])/16.0
		var b:Vector3=Vector3(element.to[0],element.to[1],element.to[2])/16.0
		var quads:Dictionary={
			"north":[Vector3(a.x,a.y,a.z),Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z),Vector3(a.x,b.y,a.z)],
			"south":[Vector3(b.x,a.y,b.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z),Vector3(b.x,b.y,b.z)],
			"west":[Vector3(a.x,a.y,b.z),Vector3(a.x,a.y,a.z),Vector3(a.x,b.y,a.z),Vector3(a.x,b.y,b.z)],
			"east":[Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z),Vector3(b.x,b.y,b.z),Vector3(b.x,b.y,a.z)],
			"up":[Vector3(a.x,b.y,a.z),Vector3(b.x,b.y,a.z),Vector3(b.x,b.y,b.z),Vector3(a.x,b.y,b.z)],
			"down":[Vector3(a.x,a.y,b.z),Vector3(b.x,a.y,b.z),Vector3(b.x,a.y,a.z),Vector3(a.x,a.y,a.z)]}
		for face:String in element.faces:
			var def:Dictionary=element.faces[face]
			var mat:=StandardMaterial3D.new()
			mat.albedo_texture=load(FOLDER+String(def.texture).trim_prefix("#")+".png")
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold=0.1
			mat.cull_mode=BaseMaterial3D.CULL_DISABLED
			var light:float=1.0 if face=="up" else (0.85 if face in ["north","south"] else 0.65)
			mat.albedo_color=Color(light,light,light,1)
			var uv:Array=def.uv
			var texels:Array[Vector2]=[Vector2(uv[0],uv[3]),Vector2(uv[2],uv[3]),Vector2(uv[2],uv[1]),Vector2(uv[0],uv[1])]
			var surface:=SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i:int in [0,1,2,0,2,3]:
				surface.set_uv(texels[i]/16.0)
				surface.add_vertex(quads[face][i])
			var mesh:=MeshInstance3D.new()
			mesh.mesh=surface.commit()
			mesh.material_override=mat
			view.add_child(mesh)
	for i:int in range(5): await RenderingServer.frame_post_draw
	var result:Image=view.get_texture().get_image()
	var rect:Rect2i=result.get_used_rect().grow(2).intersection(Rect2i(Vector2i.ZERO,result.get_size()))
	result=result.get_region(rect)
	var error:int=result.save_png(FOLDER+"beacon_block.png")
	print("BEACON_BLOCK_BAKE ",result.get_size()," error=",error)
	quit(error)
