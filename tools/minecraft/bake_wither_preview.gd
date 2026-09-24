extends SceneTree
## Bake ONLY menu/placement art from the same live rig and camera as combat.
## Does not instantiate a character or trigger the intro, sound, AI or damage.
const RIG=preload("res://scripts/characters/我的世界/wither/bedrock_rig.gd")
const OUTPUT:String="res://Images/characters/我的世界/wither/bedrock/wither_preview.png"
func _initialize() -> void: call_deferred("bake")
func bake() -> void:
	var view:=SubViewport.new()
	view.size=Vector2i(384,384)
	view.transparent_bg=true
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=5.2
	camera.position=Vector3(0,2,-6)
	view.add_child(camera)
	camera.look_at(Vector3(0,2,0),Vector3.UP)
	camera.current=true
	var rig:Node3D=RIG.new()
	view.add_child(rig)
	rig.animate(0.0,Vector2.ZERO,true,1.0,false,[Vector2.UP,Vector2.UP,Vector2.UP],1.0)
	for i:int in range(5): await RenderingServer.frame_post_draw
	var image:Image=view.get_texture().get_image()
	assert(image.get_used_rect().has_area(),"preview must contain actual rendered geometry")
	var error:int=image.save_png(OUTPUT)
	print("WITHER_PREVIEW_BAKE size=",image.get_size()," used=",image.get_used_rect()," error=",error)
	quit(error)
