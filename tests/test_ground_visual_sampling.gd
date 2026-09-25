extends SceneTree
const SAMPLER = preload("res://scripts/effects/地表渲染采样.gd")
const SHADOW = preload("res://scripts/effects/我的世界/地图内沿阴影.gd")
const OUTSIDE_SHADOW = preload("res://scripts/effects/我的世界/地图外沿阴影.gd")
var failures:int = 0
class FixtureWorld extends Node2D:
	func _get_center_watermark_map_rect() -> Rect2:
		return Rect2(100,200,128,128)

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1

func panel(parent:Node,color:Color,z:int,rect:Rect2) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	p.color = color
	p.z_index = z
	parent.add_child(p)
	return p

func near(a:Color,b:Color) -> bool:
	return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < 0.045

func _free_during_render(victims:Array) -> void:
	for victim in victims:
		if is_instance_valid(victim): victim.free()

func _run() -> void:
	var world := FixtureWorld.new()
	world.z_index = -2
	root.add_child(world)
	current_scene = world
	var rect := Rect2(100,200,128,128)
	var blue := panel(world,Color(0.0,0.5,0.9),-3,rect)
	var actor := panel(world,Color.RED,10,rect)
	var sampler := SAMPLER.new()
	sampler.name = "GroundSurfaceSampler"
	world.add_child(sampler)
	await process_frame
	var shot:Dictionary = await sampler.capture(rect)
	check(not shot.is_empty(),"rendered floor snapshot")
	if shot.is_empty(): quit(1); return
	check(near(shot.image.get_pixel(64,64),Color(0.0,0.5,0.9)),"blue floor, upper red actor excluded, world-coordinate transform")
	check(blue.visibility_layer == 1 and actor.visibility_layer == 1,"visibility masks restored")
	# 复现战斗中碎砖/角色在快照标记后、恢复显示层之前销毁。
	for iteration:int in range(20):
		await process_frame
		var temporary_floor := panel(world,Color.GRAY,-5,rect)
		var temporary_actor := panel(world,Color.WHITE,10,rect)
		RenderingServer.frame_pre_draw.connect(_free_during_render.bind([temporary_floor,temporary_actor]),CONNECT_ONE_SHOT)
		shot = await sampler.capture(rect)
		check(not shot.is_empty() and not sampler.get("_busy") and blue.visibility_layer == 1,"destroyed floor/actor during capture, recovery round %d" % iteration)
	var grass := panel(world,Color.WHITE,-5,rect)
	grass.z_as_relative = false
	grass.modulate = Color(0.2,0.7,0.3)
	await process_frame
	shot = await sampler.capture(rect)
	check(near(shot.image.get_pixel(64,64),Color(0.2,0.7,0.3)),"new tinted floor overrides blue automatically")
	var stone := panel(world,Color(0.4,0.4,0.4),-5,Rect2(100,200,64,128))
	stone.z_as_relative = false
	await process_frame
	shot = await sampler.capture(rect)
	check(near(shot.image.get_pixel(32,64),Color(0.4,0.4,0.4)) and near(shot.image.get_pixel(96,64),Color(0.2,0.7,0.3)),"overlay and uncovered ground sampled at different positions")
	stone.hide()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR=vec4(0.8,0.1,0.6,1.0); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	grass.material = mat
	await process_frame
	shot = await sampler.capture(rect)
	check(near(shot.image.get_pixel(64,64),Color(0.8,0.1,0.6)),"unknown future shader background supported without name branches")
	grass.hide()
	var real_grass:Node2D = load("res://scripts/effects/我的世界/地图草方块背景.gd").new()
	real_grass.z_as_relative = false
	real_grass.z_index = -5
	world.add_child(real_grass)
	real_grass.configure(rect,Vector2(16,16),true)
	await process_frame
	shot = await sampler.capture(rect)
	var grass_color:Color = shot.image.get_pixel(64,64)
	check(grass_color.g>grass_color.r and grass_color.r>grass_color.b,"actual grass texture and tint sampled instead of blue")
	var impact:Node2D = load("res://scripts/effects/我的世界/重锤落地冲击.gd").new()
	world.add_child(impact)
	impact.setup(Vector2(164,264),42.0)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var blocks:Array = impact.get("_blocks")
	var all_grass:bool = not blocks.is_empty()
	for block:Dictionary in blocks:
		var c:Color = block.color
		all_grass = all_grass and c.g>c.r and c.r>c.b
	check(all_grass,"real mace impact generates grass-colored particles, not blue")
	var view := SubViewport.new()
	view.size = Vector2i(128,128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var inner := SHADOW.new()
	view.add_child(inner)
	var spans:Array = [[Vector2(0,128)],[Vector2(0,128)],[Vector2(0,128)],[Vector2(0,128)]]
	inner.configure(Rect2(0,0,128,128),Vector2(16,16),spans)
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = view.get_texture().get_image()
	var wall:float = image.get_pixel(64,0).a
	var corner:float = image.get_pixel(0,0).a
	check(absf(wall-corner)<0.01,"shadow corner has no double alpha")
	check(wall>0.30 and image.get_pixel(64,8).a>0.10 and image.get_pixel(64,15).a<0.02 and image.get_pixel(64,32).a<0.01,"continuous wall-to-floor fade at 0/8/15/32 units")
	# 外沿阴影现以浮点纹理传入矩形并集；用生产 configure 而非旧的孤立 shader 空参数夹具。
	var outer:Node2D = OUTSIDE_SHADOW.new()
	view.add_child(outer)
	outer.configure(Rect2(0,0,128,64),Vector2(16,16))
	inner.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var outer_image:Image = view.get_texture().get_image()
	check(absf(image.get_pixel(64,8).a-outer_image.get_pixel(64,72).a)<0.012,"inner fade equals existing map outside shader at same distance")
	outer.hide()
	inner.show()
	spans[2] = [Vector2(0,40),Vector2(88,128)]
	inner.configure(Rect2(0,0,128,128),Vector2(16,16),spans)
	await process_frame
	await RenderingServer.frame_post_draw
	image = view.get_texture().get_image()
	check(image.get_pixel(64,0).a<0.01 and image.get_pixel(44,2).a>0.1 and image.get_pixel(53,2).a<0.08,"door opening clear with smoothly fading endpoints")
	print("VISUAL_REGRESSION failures=",failures)
	quit(0 if failures == 0 else 1)
