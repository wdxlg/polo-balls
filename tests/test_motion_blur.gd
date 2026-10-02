extends SceneTree
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node2D
var camera:Camera2D
var blur:CanvasLayer
var MB:GDScript

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func white_texture(size:int) -> Texture2D:
	var image := Image.create(size,size,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func mover(point:Vector2,size:int = 8) -> Node2D:
	var node := Node2D.new()
	node.position = point
	var sprite := Sprite2D.new()
	sprite.texture = white_texture(size)
	node.add_child(sprite)
	world.add_child(node)
	return node

func step() -> void:
	await physics_frame
	blur.update_now()

func count() -> int:
	return int(blur._material.get_shader_parameter("object_count")) if blur._rect.visible else 0

func first_blur() -> Vector2:
	var objects:PackedVector4Array = blur._material.get_shader_parameter("objects")
	return Vector2(objects[0].z,objects[0].w)

func _initialize() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): print("MOTION_BLUR_TIMEOUT"); quit(2))
	await process_frame
	game = root.get_node("Game")
	MB = load("res://scripts/effects/motion_blur.gd")
	var original_path:String = game._settings_storage_path
	var original_value:Variant = game.Game_Settings.get("Motion_Blur",false)
	var original_locale:String = game.current_locale
	game._settings_storage_path = "user://test_motion_blur_settings.cfg"
	check(FileAccess.get_file_as_string("res://global/game.gd").contains("\tMotion_Blur = false,"),"motion blur is off by default")
	check(not game._is_network_shared_setting("Motion_Blur"),"motion blur is a local preference, not synced to the room")
	for lang:String in ["zh","en"]:
		game.set_language(lang,false)
		var text:String = game.t("SETTING_MOTION_BLUR")
		check(text == ("动态模糊" if lang == "zh" else "Motion Blur"),lang+" settings label translated")
		check(preload("res://global/translation_catalog.gd").TABLE[lang].get("SETTING_MOTION_BLUR","") == text,lang+" compiled catalog matches runtime text")
	game.set_language("zh",false)
	for path:String in ["res://scripts/world.gd","res://scripts/day_night_cycle.gd","res://scripts/ui/battle_record_locale.gd"]:
		var source:String = FileAccess.get_file_as_string(path)
		check(not source.contains(".layer = 1\n") and not source.contains(".layer = 1\r"),path.get_file()+" keeps screen UI off the motion-blur layer")
	world = Node2D.new()
	world.name = "MotionBlurWorld"
	root.add_child(world)
	current_scene = world
	var background := ColorRect.new()
	background.color = Color(0.1,0.12,0.16)
	background.size = Vector2(2000,2000)
	background.position = Vector2(-1000,-1000)
	background.z_index = -10
	world.add_child(background)
	camera = Camera2D.new()
	camera.zoom = Vector2(5,5)
	camera.position_smoothing_enabled = false
	world.add_child(camera)
	camera.make_current()
	blur = MB.attach(world,root)
	check(blur.layer == 1,"blur sits on layer 1: above the battle world, below screen UI")
	RenderingServer.frame_pre_draw.disconnect(blur.update_now)
	var fast:Node2D = mover(Vector2(-40,0))
	await process_frame
	game.Game_Settings["Motion_Blur"] = false
	fast.position.x += 10.0
	await step()
	check(not blur._rect.visible,"disabled setting draws nothing")
	game.Game_Settings["Motion_Blur"] = true
	await step()
	fast.position.x += 10.0
	await step()
	var tick_speed:float = 10.0*Engine.physics_ticks_per_second
	check(count() == 1,"object at %.0f units/s is blurred" % tick_speed)
	var b:Vector2 = first_blur()
	check(absf(b.x-25.0) < 0.6 and absf(b.y) < 0.01,"180-degree shutter: blur is half the frame movement along the velocity (%s, expected 25 on screen)" % str(b))
	fast.position.x -= 10.0
	await step()
	check(count() == 1 and first_blur().x < -20.0,"blur follows the current direction")
	fast.position.x += 2.0
	await step()
	check(count() == 0,"%.0f units/s is below the 300 threshold" % (2.0*Engine.physics_ticks_per_second))
	fast.position.x += 500.0
	await step()
	check(count() == 0,"teleport is not motion blurred")
	var still:Node2D = mover(Vector2(30,30))
	var hud := Label.new()
	hud.text = "HUD"
	hud.size = Vector2(20,6)
	world.add_child(hud)
	await step()
	for i:int in range(2):
		camera.position.x += 8.0
		hud.position.x += 8.0
		await process_frame
		await step()
	check(blur._rect.visible,"fast camera pan blurs the whole battle view")
	print("DEBUG count=",count()," first=",first_blur()," cam_o=",blur._material.get_shader_parameter("cam_o"))
	check(count() == 1 and first_blur().length() < 0.5,"screen-fixed labels in the world canvas get zero blur; world objects follow the camera blur")
	hud.visible = false
	still.visible = false
	await step()
	check(count() == 0 and not blur._rect.visible,"stopping the camera clears the blur")
	check(is_equal_approx(MB.measure_radius(fast),(4.0*sqrt(2.0))*MB.RADIUS_MARGIN+1.0),"object footprint comes from its own sprite")
	if DisplayServer.get_name() != "headless":
		await gpu_check()
	game.Game_Settings["Motion_Blur"] = original_value
	game.set_language(original_locale,false)
	game._settings_storage_path = original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_motion_blur_settings.cfg"))
	print("MOTION_BLUR checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func gpu_check() -> void:
	RenderingServer.frame_pre_draw.connect(blur.update_now)
	camera.position = Vector2.ZERO
	var square:Node2D = mover(Vector2(-60,0),12)
	for node:Node in world.get_children():
		if node is Node2D and node != square and node != camera: (node as Node2D).visible = false
	for i:int in range(20):
		await physics_frame
		square.position.x += 6.0
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	image.save_png(OS.get_temp_dir().path_join("motion_blur_gpu.png"))
	var view:Vector2 = root.get_visible_rect().size
	var center:Vector2 = (view*0.5+square.position*5.0)*Vector2(image.get_size())/view
	var y:int = int(center.y)
	var x:int = int(center.x)
	var horizontal:int = 0
	for px:int in range(image.get_width()):
		var v:float = image.get_pixel(px,y).get_luminance()
		if v > 0.2 and v < 0.85: horizontal += 1
	var vertical:int = 0
	for py:int in range(image.get_height()):
		var v:float = image.get_pixel(x,py).get_luminance()
		if v > 0.2 and v < 0.85: vertical += 1
	check(horizontal >= 8,"GPU frame: moving square has soft smeared edges along the motion (%d px)" % horizontal)
	check(vertical <= 3,"GPU frame: edges across the motion stay sharp (%d px)" % vertical)
